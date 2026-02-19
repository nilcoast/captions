## Unix socket control server using platform-specific event loops.
## Handles toggle/stop/status commands from the CLI client.

import std/[os, net, nativesockets, atomics, strutils, logging, strformat, locks]
import ./config
import ./audio

# Platform-specific event loop bindings
when not defined(macosx):
  import ./gtk4_bindings

# Platform-conditional audio backends
when defined(macosx):
  # macOS: Use miniaudio for mic, CoreAudio Taps for sink
  import ./audio_miniaudio as audio_mic
  import ./audio_coreaudio as audio_sink
else:
  # Linux/other: Use miniaudio for both mic and sink (PulseAudio/PipeWire monitor)
  import ./audio_miniaudio as audio_mic
  import ./audio_miniaudio as audio_sink

import ./transcribe
import ./recorder
import ./summary

# Platform-conditional overlay import
when defined(macosx):
  import ./overlay_macos as overlay
else:
  import ./overlay

# Platform-specific dispatch helpers
when defined(macosx):
  type DispatchQueue {.importc: "dispatch_queue_t", header: "<dispatch/dispatch.h>".} = pointer

  proc dispatch_get_main_queue(): DispatchQueue {.
    importc: "dispatch_get_main_queue",
    header: "<dispatch/dispatch.h>".}

  proc dispatch_async_f(queue: DispatchQueue, context: pointer,
                        work: proc(ctx: pointer) {.cdecl.}) {.
    importc: "dispatch_async_f",
    header: "<dispatch/dispatch.h>".}

  {.emit: """
  static const void* _nim_dispatch_timer_ptr_daemon = DISPATCH_SOURCE_TYPE_TIMER;
  """.}
  var nimDispatchTimerPtrDaemon {.importc: "_nim_dispatch_timer_ptr_daemon", nodecl.}: pointer

  proc dispatch_get_global_queue(qos_class: clong, flags: culong): DispatchQueue {.
    importc: "dispatch_get_global_queue",
    header: "<dispatch/dispatch.h>".}

  template dispatchAsync(callback: proc(data: pointer): cint {.cdecl.}) =
    proc wrapper(ctx: pointer) {.cdecl.} = discard callback(nil)
    let mainQueue = dispatch_get_main_queue()
    dispatch_async_f(mainQueue, nil, wrapper)
else:
  template dispatchAsync(callback: proc(data: pointer): cint {.cdecl.}) =
    discard g_idle_add(callback, nil)

type
  SessionState = object
    micRing: ptr RingBuffer
    sinkRing: ptr RingBuffer
    micCapture: ptr audio_mic.AudioCapture
    sinkCapture: ptr audio_sink.AudioCapture
    transcriber: ptr Transcriber
    wavRecorder: ptr WavRecorder
    sessionDir: string
    transcript: string
    transcriptLock: Lock
    active: Atomic[bool]

  Daemon* = ref object
    cfg*: AppConfig
    serverSock: Socket
    session: ptr SessionState
    running*: bool

proc newDaemon*(cfg: AppConfig): Daemon =
  result = Daemon(
    cfg: cfg,
    session: nil,
    running: false,
  )

proc isActive*(d: Daemon): bool =
  d.session != nil and d.session.active.load(moRelaxed)

proc startSession(d: Daemon) =
  if d.isActive:
    return

  info "Starting capture session (thread=" & $getThreadId() & ")"

  let sess = cast[ptr SessionState](allocShared0(sizeof(SessionState)))
  initLock(sess.transcriptLock)
  sess.active.store(true, moRelaxed)
  sess.transcript = ""
  d.session = sess

  # Create session directory for recording
  let sessDir = sessionDir(d.cfg.recording)
  sess.sessionDir = sessDir

  # Init ring buffers and captures for enabled sources
  var rings: seq[ptr RingBuffer]

  if d.cfg.audio.captureMic:
    sess.micRing = initRingBuffer(d.cfg.audio.bufferSeconds, d.cfg.audio.sampleRate)
    sess.micCapture = audio_mic.newAudioCapture(d.cfg.audio, ckMic, sess.micRing)
    rings.add(sess.micRing)

  if d.cfg.audio.captureSink:
    sess.sinkRing = initRingBuffer(d.cfg.audio.bufferSeconds, d.cfg.audio.sampleRate)
    sess.sinkCapture = audio_sink.newAudioCapture(d.cfg.audio, ckSink, sess.sinkRing)
    rings.add(sess.sinkRing)

  if rings.len == 0:
    warn "No audio sources enabled (capture_mic and capture_sink are both false)"
    deallocShared(sess)
    d.session = nil
    return

  # Set up WAV recording — record from whichever source is active.
  # When both are active, we record from the first source only (mic).
  # The full mixed audio is in the transcript via whisper.
  if d.cfg.recording.saveAudio:
    createDir(sessDir)
    var rec = cast[ptr WavRecorder](allocShared0(sizeof(WavRecorder)))
    rec[] = newWavRecorder(sessDir, d.cfg.audio.sampleRate, d.cfg.audio.channels)
    sess.wavRecorder = rec

    # Attach recording callback to both captures — mixer sums into WAV
    let wavRec = sess.wavRecorder
    let recordCb = proc(data: ptr float32, count: int) {.gcsafe.} =
      if wavRec != nil:
        writeSamples(wavRec[], data, count)

    if sess.micCapture != nil:
      sess.micCapture.onSamples = recordCb
    if sess.sinkCapture != nil:
      sess.sinkCapture.onSamples = recordCb

  # Start captures
  if sess.micCapture != nil:
    if not audio_mic.start(sess.micCapture):
      warn "Mic capture failed to start"
      audio_mic.destroy(sess.micCapture)
      sess.micCapture = nil
      if sess.micRing != nil:
        rings.del(rings.find(sess.micRing))
        destroyRingBuffer(sess.micRing)
        sess.micRing = nil
  if sess.sinkCapture != nil:
    if not audio_sink.start(sess.sinkCapture):
      warn "Sink capture failed to start, continuing with mic-only"
      audio_sink.destroy(sess.sinkCapture)
      sess.sinkCapture = nil
      # Remove sink ring from the rings list
      if sess.sinkRing != nil:
        rings.del(rings.find(sess.sinkRing))
        destroyRingBuffer(sess.sinkRing)
        sess.sinkRing = nil

  # Check we still have at least one working source
  if rings.len == 0:
    warn "All audio sources failed to start"
    deallocShared(sess)
    d.session = nil
    return

  # Re-init transcriber with surviving ring buffers (in case sink was removed)
  sess.transcriber = newTranscriber(d.cfg.whisper, d.cfg.audio, rings, addr sess.active)

  # Transcription callback — sends text to overlay + collects transcript
  sess.transcriber.onText = proc(text: string) {.gcsafe.} =
    idleAddText(text)
    acquire(sess.transcriptLock)
    if sess.transcript.len > 0:
      sess.transcript.add(" ")
    sess.transcript.add(text)
    release(sess.transcriptLock)

  start(sess.transcriber)

  # Show overlay via platform-specific dispatch
  proc showCb(data: pointer): cint {.cdecl.} =
    if gOverlay != nil: showOverlay(gOverlay)
    return 0
  dispatchAsync(showCb)

  info "Session started"

proc stopSession(d: Daemon) =
  if not d.isActive:
    return

  info "Stopping capture session"
  let sess = d.session

  # Signal stop
  sess.active.store(false, moRelaxed)

  # Join transcriber thread
  join(sess.transcriber)

  # Stop audio captures
  if sess.micCapture != nil:
    audio_mic.stop(sess.micCapture)
  if sess.sinkCapture != nil:
    audio_sink.stop(sess.sinkCapture)

  # Finalize WAV
  if sess.wavRecorder != nil:
    finalize(sess.wavRecorder[])
    deallocShared(sess.wavRecorder)
    sess.wavRecorder = nil

  # Save transcript
  if d.cfg.recording.saveTranscript and sess.transcript.len > 0:
    createDir(sess.sessionDir)
    let path = sess.sessionDir / "transcript.txt"
    writeFile(path, sess.transcript)
    info &"Transcript saved: {path}"

  # Hide overlay via platform-specific dispatch
  proc hideCb(data: pointer): cint {.cdecl.} =
    if gOverlay != nil: hideOverlay(gOverlay)
    return 0
  dispatchAsync(hideCb)

  # Spawn summary generation (background thread — non-blocking)
  spawnSummary(d.cfg.summary, sess.transcript, sess.sessionDir)

  # Cleanup
  destroy(sess.transcriber)
  if sess.micCapture != nil:
    audio_mic.destroy(sess.micCapture)
  if sess.sinkCapture != nil:
    audio_sink.destroy(sess.sinkCapture)
  if sess.micRing != nil:
    destroyRingBuffer(sess.micRing)
  if sess.sinkRing != nil:
    destroyRingBuffer(sess.sinkRing)
  deinitLock(sess.transcriptLock)
  deallocShared(sess)
  d.session = nil

  info "Session stopped"

proc shutdownDaemon*(d: Daemon) =
  ## Graceful shutdown — safe to call from platform event loop context.
  if d.isActive:
    stopSession(d)
  d.running = false
  proc quitCb(data: pointer): cint {.cdecl.} =
    if gOverlay != nil:
      quitApp(gOverlay)
    return 0
  dispatchAsync(quitCb)

proc setupSocket(d: Daemon) =
  let path = d.cfg.daemon.socketPath
  # Always try to remove stale socket (fileExists doesn't reliably detect unix sockets)
  try: removeFile(path)
  except CatchableError: discard

  d.serverSock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  d.serverSock.setSockOpt(OptReuseAddr, true)
  bindUnix(d.serverSock, path)
  d.serverSock.listen()
  d.serverSock.getFd().SocketHandle.setBlocking(false)
  info &"Listening on {path}"

# We store the Daemon ref in a global so the GLib callback can access it
var gDaemon: Daemon = nil

# macOS: dedicated Nim thread for session ops so ORC and ScreenCaptureKit work correctly.
# ScreenCaptureKit delivers completion handlers on the main queue, so session ops
# must NOT run on the main queue. And Nim ORC requires a Nim-created thread for GC safety.
when defined(macosx):
  var nimSessionChan: Channel[string]
  var nimSessionThread: Thread[Daemon]

  proc nimSessionLoop(d: Daemon) {.thread, gcsafe.} =
    info "nimSessionLoop started (thread=" & $getThreadId() & ")"
    while true:
      let cmd = nimSessionChan.recv()
      info "nimSessionLoop received: " & cmd & " (thread=" & $getThreadId() & ")"
      case cmd
      of "start":
        if not d.isActive:
          startSession(d)
      of "stop":
        if d.isActive:
          stopSession(d)
      of "quit":
        break
      else:
        discard

  # cdecl shims called from GCD — just forward to the Nim channel
  proc startSessionBg(ctx: pointer) {.cdecl.} =
    info "startSessionBg dispatched (thread=" & $getThreadId() & ")"
    nimSessionChan.send("start")

  proc stopSessionBg(ctx: pointer) {.cdecl.} =
    info "stopSessionBg dispatched (thread=" & $getThreadId() & ")"
    nimSessionChan.send("stop")

proc handleCommand(d: Daemon, cmd: string): string =
  let c = cmd.strip().toLowerAscii()
  case c
  of "toggle":
    if d.isActive:
      when defined(macosx):
        dispatch_async_f(dispatch_get_global_queue(0, 0), nil, stopSessionBg)
      else:
        stopSession(d)
      "stopped"
    else:
      when defined(macosx):
        dispatch_async_f(dispatch_get_global_queue(0, 0), nil, startSessionBg)
      else:
        startSession(d)
      "started"
  of "stop":
    when defined(macosx):
      dispatch_async_f(dispatch_get_global_queue(0, 0), nil, stopSessionBg)
    else:
      if d.isActive:
        stopSession(d)
    "stopped"
  of "status":
    if d.isActive: "active" else: "idle"
  of "quit":
    shutdownDaemon(d)
    "bye"
  else:
    "unknown command: " & c

proc pollSocketCb(data: pointer): cint {.cdecl.} =
  ## Called periodically from GLib timeout. Returns 1 to continue, 0 to stop.
  let d = gDaemon
  if d == nil or not d.running:
    return 0

  try:
    var client: Socket
    new(client)
    d.serverSock.accept(client, inheritable = false)
    client.getFd().SocketHandle.setBlocking(true)

    var data = ""
    try:
      data = client.recvLine(timeout = 1000)
    except TimeoutError:
      data = ""

    if data.len > 0:
      let response = handleCommand(d, data)
      try:
        client.send(response & "\n")
      except CatchableError:
        discard
    client.close()
  except OSError:
    # No pending connection, that's fine
    discard

  return if d.running: 1.cint else: 0.cint

proc startDaemon*(d: Daemon) =
  d.running = true
  gDaemon = d
  setupSocket(d)
  when defined(macosx):
    nimSessionChan.open()
    createThread(nimSessionThread, nimSessionLoop, d)

  # Add platform-specific timeout to poll the Unix socket every 100ms
  when defined(macosx):
    type DispatchSource {.importc: "dispatch_source_t", header: "<dispatch/dispatch.h>".} = pointer

    proc dispatch_source_create(stype: pointer, handle: culong, mask: culong,
                                queue: DispatchQueue): DispatchSource {.
      importc: "dispatch_source_create",
      header: "<dispatch/dispatch.h>".}

    proc dispatch_source_set_event_handler_f(source: DispatchSource,
                                            handler: proc(ctx: pointer) {.cdecl.}) {.
      importc: "dispatch_source_set_event_handler_f",
      header: "<dispatch/dispatch.h>".}

    proc dispatch_source_set_timer(source: DispatchSource, start: uint64,
                                  interval: uint64, leeway: uint64) {.
      importc: "dispatch_source_set_timer",
      header: "<dispatch/dispatch.h>".}

    proc dispatch_resume(obj: pointer) {.
      importc: "dispatch_resume",
      header: "<dispatch/dispatch.h>".}

    const NSEC_PER_MSEC = 1_000_000'u64

    proc pollWrapper(ctx: pointer) {.cdecl.} =
      discard pollSocketCb(nil)

    let mainQueue = dispatch_get_main_queue()
    let timer = dispatch_source_create(nimDispatchTimerPtrDaemon, 0, 0, mainQueue)
    dispatch_source_set_event_handler_f(timer, pollWrapper)
    dispatch_source_set_timer(timer, 100 * NSEC_PER_MSEC, 100 * NSEC_PER_MSEC, 0)
    dispatch_resume(timer)
  else:
    # GLib timeout to poll the Unix socket every 100ms
    discard g_timeout_add(100, pollSocketCb, nil)

proc stopDaemon*(d: Daemon) =
  when defined(macosx):
    nimSessionChan.send("quit")
    joinThread(nimSessionThread)
    nimSessionChan.close()
  if d.isActive:
    stopSession(d)
  d.running = false
  gDaemon = nil
  try:
    d.serverSock.close()
  except CatchableError:
    discard
  if fileExists(d.cfg.daemon.socketPath):
    removeFile(d.cfg.daemon.socketPath)

# --- CLI client ---

proc sendCommand*(socketPath: string, command: string): string =
  let sock = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
  defer: sock.close()
  try:
    connectUnix(sock, socketPath)
    sock.send(command & "\n")
    result = sock.recvLine(timeout = 5000)
  except OSError as e:
    result = "error: " & e.msg
  except TimeoutError:
    result = "error: timeout"
