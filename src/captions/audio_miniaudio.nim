## Audio capture via miniaudio.
## Handles mic capture on all platforms. On Linux, selects a PulseAudio/PipeWire
## monitor source for system audio (sink) loopback.

import std/[atomics, logging]
import ./audio
import ./config

# --- C helper bindings (ma_helper.c) ---

{.compile: "ma_helper.c".}
when defined(linux):
  {.passl: "-lpthread -lm -ldl".}
when defined(macosx):
  {.passl: "-framework CoreAudio -framework AudioToolbox -framework CoreFoundation".}

type
  MaCapturePtr* = pointer

  MaSamplesCallback = proc(data: ptr cfloat, count: cint, userdata: pointer) {.cdecl.}

proc ma_capture_new(): MaCapturePtr {.importc, cdecl.}
proc ma_capture_free(cap: MaCapturePtr) {.importc, cdecl.}
proc ma_capture_start(cap: MaCapturePtr, device_name: cstring,
                      sample_rate: cint, channels: cint,
                      callback: MaSamplesCallback, userdata: pointer): cint {.importc, cdecl.}
proc ma_capture_stop(cap: MaCapturePtr) {.importc, cdecl.}
proc ma_find_monitor_source(out_name: cstring, max_len: cint): cint {.importc, cdecl.}

# --- AudioCapture ---

type
  AudioCapture* = object
    cfg: AudioConfig
    kind*: CaptureKind
    ring*: ptr RingBuffer
    device: MaCapturePtr
    active*: Atomic[bool]
    onSamples*: proc(data: ptr float32, count: int) {.gcsafe.}

proc onAudioData(data: ptr cfloat, count: cint, userdata: pointer) {.cdecl.} =
  let capture = cast[ptr AudioCapture](userdata)
  if not capture.active.load(moRelaxed):
    return

  let samplesPtr = cast[ptr float32](data)

  # Write to ring buffer
  write(capture.ring, samplesPtr, count.int)

  # Notify recorder callback
  if capture.onSamples != nil:
    capture.onSamples(samplesPtr, count.int)

proc newAudioCapture*(cfg: AudioConfig, kind: CaptureKind, ring: ptr RingBuffer): ptr AudioCapture =
  result = cast[ptr AudioCapture](allocShared0(sizeof(AudioCapture)))
  result.cfg = cfg
  result.kind = kind
  result.ring = ring
  result.active.store(false, moRelaxed)
  result.onSamples = nil

proc start*(capture: ptr AudioCapture) =
  if capture.active.load(moRelaxed):
    return

  capture.device = ma_capture_new()
  if capture.device == nil:
    error "Failed to allocate miniaudio capture device"
    return

  # Determine device name for miniaudio
  var deviceName: string = ""

  case capture.kind
  of ckMic:
    # Default capture device (mic)
    deviceName = ""
  of ckSink:
    # System audio loopback — find monitor source
    if capture.cfg.monitorDevice != "":
      # User-specified monitor device
      deviceName = capture.cfg.monitorDevice
    else:
      # Auto-detect: find first monitor source
      var nameBuf: array[256, char]
      if ma_find_monitor_source(cast[cstring](addr nameBuf[0]), 256) == 0:
        deviceName = $cast[cstring](addr nameBuf[0])
        info "Auto-detected monitor source: " & deviceName
      else:
        warn "No monitor source found for sink capture. " &
             "Set [audio] monitor_device in config, or ensure PulseAudio/PipeWire is running."
        ma_capture_free(capture.device)
        capture.device = nil
        return

  capture.active.store(true, moRelaxed)

  let ret = ma_capture_start(
    capture.device,
    if deviceName == "": nil else: deviceName.cstring,
    capture.cfg.sampleRate.cint,
    capture.cfg.channels.cint,
    onAudioData,
    cast[pointer](capture)
  )

  if ret != 0:
    let errMsg = case ret
      of -1: "context init failed"
      of -2: "device not found: " & deviceName
      of -3: "device init failed"
      of -4: "device start failed"
      else: "unknown error " & $ret
    error "Failed to start audio capture (" & $capture.kind & "): " & errMsg
    capture.active.store(false, moRelaxed)
    ma_capture_free(capture.device)
    capture.device = nil
    return

  info "Audio capture started: " & $capture.kind &
       (if deviceName != "": " (" & deviceName & ")" else: " (default)")

proc stop*(capture: ptr AudioCapture) =
  if not capture.active.load(moRelaxed):
    return

  capture.active.store(false, moRelaxed)
  if capture.device != nil:
    ma_capture_stop(capture.device)
    ma_capture_free(capture.device)
    capture.device = nil

proc destroy*(capture: ptr AudioCapture) =
  stop(capture)
  deallocShared(capture)
