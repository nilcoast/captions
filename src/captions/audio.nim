## Platform-agnostic audio types: RingBuffer and CaptureKind.
## The actual capture implementation lives in audio_miniaudio.nim.

import std/[locks]

type
  RingBuffer* = object
    data*: seq[float32]
    capacity*: int       # in samples
    writePos*: int
    totalWritten*: int64 # monotonic sample counter
    lock*: Lock

  CaptureKind* = enum
    ckMic,   ## Microphone input
    ckSink   ## System audio (sink monitor)

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
