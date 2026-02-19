## Audio capture via CoreAudio Taps (macOS 13.0+).
## Handles system audio (sink) loopback using ScreenCaptureKit audio taps.
## This module provides the same AudioCapture interface as audio_miniaudio.nim
## for seamless platform-conditional usage.

import std/[atomics, logging]
import ./audio
import ./config
import ./coreaudio_bindings

# --- AudioCapture ---

type
  AudioCapture* = object
    cfg: AudioConfig
    kind*: CaptureKind
    ring*: ptr RingBuffer
    device: CaCapturePtr
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

proc start*(capture: ptr AudioCapture): bool =
  if capture.active.load(moRelaxed):
    return true

  if capture.kind != ckSink:
    error "CoreAudio Taps only supports sink (system audio) capture. Use miniaudio for microphone."
    return false

  capture.device = ca_capture_new()
  if capture.device == nil:
    error "Failed to allocate CoreAudio capture device"
    return false

  capture.active.store(true, moRelaxed)

  let ret = ca_capture_start(
    capture.device,
    capture.cfg.sampleRate.cint,
    capture.cfg.channels.cint,
    onAudioData,
    cast[pointer](capture)
  )

  if ret != 0:
    let errMsg = case ret
      of -1: "timeout waiting for shareable content"
      of -2: "no displays available"
      of -3: "failed to create stream"
      of -4: "failed to add audio output"
      of -5: "failed to start capture"
      of -6: "requires macOS 13.0 or later"
      of -99: "ObjC exception (check NSLog output)"
      else: "unknown error " & $ret
    error "Failed to start CoreAudio capture: " & errMsg
    capture.active.store(false, moRelaxed)
    ca_capture_free(capture.device)
    capture.device = nil
    return false

  info "CoreAudio Taps capture started: " & $capture.kind
  return true

proc stop*(capture: ptr AudioCapture) =
  if not capture.active.load(moRelaxed):
    return

  capture.active.store(false, moRelaxed)
  if capture.device != nil:
    ca_capture_stop(capture.device)
    ca_capture_free(capture.device)
    capture.device = nil

proc destroy*(capture: ptr AudioCapture) =
  stop(capture)
  deallocShared(capture)
