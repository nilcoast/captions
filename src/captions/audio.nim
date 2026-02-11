## PipeWire audio capture — captures system audio (sink monitor) into a ring buffer.
## Runs pw_main_loop on a dedicated thread.

import std/[locks, atomics, logging]
import ./pipewire_bindings
import ./config

type
  RingBuffer* = object
    data*: seq[float32]
    capacity*: int       # in samples
    writePos*: int
    totalWritten*: int64 # monotonic sample counter
    lock*: Lock

  AudioCapture* = object
    cfg: AudioConfig
    ring*: ptr RingBuffer
    pwLoop: PwMainLoopPtr
    stream: PwStreamPtr
    thread: Thread[ptr AudioCapture]
    active*: Atomic[bool]
    # Callback for raw samples (e.g. WAV recording)
    onSamples*: proc(data: ptr float32, count: int) {.gcsafe.}

proc initRingBuffer*(seconds: int, sampleRate: int): ptr RingBuffer =
  result = cast[ptr RingBuffer](allocShared0(sizeof(RingBuffer)))
  result.capacity = seconds * sampleRate
  result.data = newSeq[float32](result.capacity)
  result.writePos = 0
  result.totalWritten = 0
  initLock(result.lock)

proc destroyRingBuffer*(rb: ptr RingBuffer) =
  deinitLock(rb.lock)
  rb.data = @[]
  deallocShared(rb)

proc write*(rb: ptr RingBuffer, samples: ptr float32, count: int) =
  acquire(rb.lock)
  let src = cast[ptr UncheckedArray[float32]](samples)
  for i in 0 ..< count:
    rb.data[rb.writePos] = src[i]
    rb.writePos = (rb.writePos + 1) mod rb.capacity
  rb.totalWritten += count.int64
  release(rb.lock)

proc read*(rb: ptr RingBuffer, count: int): seq[float32] =
  ## Read the last `count` samples from the ring buffer.
  acquire(rb.lock)
  let available = min(count, rb.totalWritten.int)
  result = newSeq[float32](available)
  if available > 0:
    var readPos = (rb.writePos - available + rb.capacity) mod rb.capacity
    for i in 0 ..< available:
      result[i] = rb.data[readPos]
      readPos = (readPos + 1) mod rb.capacity
  release(rb.lock)

# --- PipeWire process callback ---

type
  PwUserData = object
    capture: ptr AudioCapture

proc onProcess(userdata: pointer) {.cdecl.} =
  let ud = cast[ptr PwUserData](userdata)
  let capture = ud.capture
  if not capture.active.load(moRelaxed):
    return

  let buf = pw_stream_dequeue_buffer(capture.stream)
  if buf == nil:
    return

  let spaBuf = buf.buffer
  if spaBuf == nil or spaBuf.n_datas == 0:
    discard pw_stream_queue_buffer(capture.stream, buf)
    return

  let d = addr spaBuf.datas[0]

  if d.data != nil and d.chunk != nil and d.chunk.size > 0:
    let nSamples = d.chunk.size.int div sizeof(float32)
    let samplesPtr = cast[ptr float32](cast[uint](d.data) + d.chunk.offset.uint)

    # Write to ring buffer
    write(capture.ring, samplesPtr, nSamples)

    # Notify recorder callback
    if capture.onSamples != nil:
      capture.onSamples(samplesPtr, nSamples)

  discard pw_stream_queue_buffer(capture.stream, buf)

# --- PipeWire thread ---

proc pwThreadProc(capture: ptr AudioCapture) {.thread.} =
  discard pw_main_loop_run(capture.pwLoop)

proc newAudioCapture*(cfg: AudioConfig, ring: ptr RingBuffer): ptr AudioCapture =
  result = cast[ptr AudioCapture](allocShared0(sizeof(AudioCapture)))
  result.cfg = cfg
  result.ring = ring
  result.active.store(false, moRelaxed)
  result.onSamples = nil

proc start*(capture: ptr AudioCapture) =
  if capture.active.load(moRelaxed):
    return

  # Init PipeWire (safe to call multiple times)
  pw_init(nil, nil)

  capture.pwLoop = pw_main_loop_new(SpaDictPtr(nil))
  if capture.pwLoop == nil:
    error "Failed to create PipeWire main loop"
    return

  let loop = pw_main_loop_get_loop(capture.pwLoop)

  var props: PwPropertiesPtr
  if capture.cfg.source == "mic":
    props = pw_properties_new(
      PW_KEY_MEDIA_TYPE, cstring"Audio",
      PW_KEY_MEDIA_CATEGORY, cstring"Capture",
      PW_KEY_MEDIA_ROLE, cstring"Communication",
      PW_KEY_NODE_NAME, cstring"captions-capture",
      nil
    )
  else:
    props = pw_properties_new(
      PW_KEY_MEDIA_TYPE, cstring"Audio",
      PW_KEY_MEDIA_CATEGORY, cstring"Capture",
      PW_KEY_MEDIA_ROLE, cstring"Music",
      PW_KEY_STREAM_CAPTURE_SINK, cstring"true",
      PW_KEY_NODE_NAME, cstring"captions-capture",
      nil
    )

  var userData = cast[ptr PwUserData](allocShared0(sizeof(PwUserData)))
  userData.capture = capture

  var events: PwStreamEvents
  zeroMem(addr events, sizeof(PwStreamEvents))
  events.version = PW_STREAM_EVENTS_VERSION
  events.process = onProcess

  # We need events to persist — store on shared heap
  var eventsPtr = cast[ptr PwStreamEvents](allocShared0(sizeof(PwStreamEvents)))
  eventsPtr[] = events

  capture.stream = pw_stream_new_simple(
    loop,
    "captions-audio",
    props,
    eventsPtr,
    userData
  )

  if capture.stream == nil:
    error "Failed to create PipeWire stream"
    pw_main_loop_destroy(capture.pwLoop)
    return

  # Build SPA format pod
  var podBuffer: array[1024, uint8]
  let pod = build_audio_format_pod(
    addr podBuffer[0],
    podBuffer.len.csize_t,
    capture.cfg.sampleRate.uint32,
    capture.cfg.channels.uint32
  )

  var params = pod
  let flags = PW_STREAM_FLAG_AUTOCONNECT or PW_STREAM_FLAG_MAP_BUFFERS or PW_STREAM_FLAG_RT_PROCESS
  let ret = pw_stream_connect(
    capture.stream,
    PW_DIRECTION_INPUT,
    PW_ID_ANY,
    flags,
    addr params,
    1
  )

  if ret < 0:
    error "Failed to connect PipeWire stream: " & $ret
    pw_stream_destroy(capture.stream)
    pw_main_loop_destroy(capture.pwLoop)
    return

  capture.active.store(true, moRelaxed)
  createThread(capture.thread, pwThreadProc, capture)

proc stop*(capture: ptr AudioCapture) =
  if not capture.active.load(moRelaxed):
    return

  capture.active.store(false, moRelaxed)
  discard pw_main_loop_quit(capture.pwLoop)
  joinThread(capture.thread)
  discard pw_stream_disconnect(capture.stream)
  pw_stream_destroy(capture.stream)
  pw_main_loop_destroy(capture.pwLoop)

proc destroy*(capture: ptr AudioCapture) =
  stop(capture)
  deallocShared(capture)
