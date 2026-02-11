## WAV file writer — records float32 samples to 16-bit PCM WAV.

import std/[os, streams, times, strformat, logging]
import ./config

type
  WavRecorder* = object
    file: FileStream
    sampleRate: int
    channels: int
    dataSize: uint32
    filePath*: string

proc writeWavHeader(r: var WavRecorder) =
  ## Write a placeholder WAV header (to be finalized later).
  let f = r.file
  f.write("RIFF")
  f.write(0'u32)  # placeholder for file size - 8
  f.write("WAVE")
  f.write("fmt ")
  f.write(16'u32)  # chunk size
  f.write(1'u16)   # PCM format
  f.write(r.channels.uint16)
  f.write(r.sampleRate.uint32)
  let bytesPerSample = 2  # 16-bit
  let byteRate = r.sampleRate * r.channels * bytesPerSample
  f.write(byteRate.uint32)
  let blockAlign = r.channels * bytesPerSample
  f.write(blockAlign.uint16)
  f.write(16'u16)  # bits per sample
  f.write("data")
  f.write(0'u32)  # placeholder for data size

proc finalizeWavHeader(r: var WavRecorder) =
  ## Go back and fill in the size fields.
  let f = r.file
  f.setPosition(4)
  f.write((36 + r.dataSize).uint32)
  f.setPosition(40)
  f.write(r.dataSize)
  f.close()

proc sessionDir*(cfg: RecordingConfig): string =
  let ts = now().format("yyyy-MM-dd'T'HH-mm-ss")
  cfg.outputDir / ts

proc newWavRecorder*(dir: string, sampleRate: int, channels: int): WavRecorder =
  createDir(dir)
  result.sampleRate = sampleRate
  result.channels = channels
  result.dataSize = 0
  result.filePath = dir / "audio.wav"
  result.file = newFileStream(result.filePath, fmWrite)
  writeWavHeader(result)

proc writeSamples*(r: var WavRecorder, data: ptr float32, count: int) =
  ## Convert float32 samples to 16-bit PCM and write.
  let src = cast[ptr UncheckedArray[float32]](data)
  for i in 0 ..< count:
    var sample = src[i]
    # Clamp to [-1, 1]
    if sample > 1.0: sample = 1.0
    elif sample < -1.0: sample = -1.0
    let pcm = int16(sample * 32767.0)
    r.file.write(pcm)
    r.dataSize += 2

proc finalize*(r: var WavRecorder) =
  finalizeWavHeader(r)
  info &"WAV saved: {r.filePath} ({r.dataSize} bytes audio data)"
