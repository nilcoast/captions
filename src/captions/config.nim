## Configuration loading from TOML with sensible defaults.

import std/[os, strutils]
import parsetoml

type
  AudioConfig* = object
    sampleRate*: int
    channels*: int
    bufferSeconds*: int
    captureMic*: bool      # capture microphone input
    captureSink*: bool     # capture system audio (sink monitor)
    monitorDevice*: string # explicit monitor source name (auto-detect if empty)

  WhisperConfig* = object
    modelPath*: string
    chunkMs*: int
    overlapMs*: int
    strategy*: string
    threads*: int
    language*: string

  OverlayConfig* = object
    font*: string
    textColor*: string
    bgColor*: string
    maxLines*: int
    marginBottom*: int
    marginSide*: int
    fadeTimeout*: int
    borderRadius*: int
    padding*: int

  RecordingConfig* = object
    outputDir*: string
    saveAudio*: bool
    saveTranscript*: bool

  SummaryConfig* = object
    enabled*: bool
    modelPath*: string  # path to GGUF model file
    prompt*: string
    gpuLayers*: int     # number of GPU layers to offload (-1 = all, 0 = CPU only)
    maxTokens*: int     # max tokens for summary output

  DaemonConfig* = object
    socketPath*: string

  AppConfig* = object
    audio*: AudioConfig
    whisper*: WhisperConfig
    overlay*: OverlayConfig
    recording*: RecordingConfig
    summary*: SummaryConfig
    daemon*: DaemonConfig

proc expandHome(path: string): string =
  if path.startsWith("~/"):
    getHomeDir() / path[2..^1]
  else:
    path

proc defaultConfig*(): AppConfig =
  result.audio = AudioConfig(
    sampleRate: 16000,
    channels: 1,
    bufferSeconds: 30,
    captureMic: false,
    captureSink: true,
    monitorDevice: "",
  )
  result.whisper = WhisperConfig(
    modelPath: expandHome("~/.local/share/captions/ggml-base.en.bin"),
    chunkMs: 3000,
    overlapMs: 500,
    strategy: "greedy",
    threads: 4,
    language: "en",
  )
  result.overlay = OverlayConfig(
    font: "Sans Bold 24",
    textColor: "rgba(255, 255, 255, 0.95)",
    bgColor: "rgba(0, 0, 0, 0.70)",
    maxLines: 3,
    marginBottom: 60,
    marginSide: 80,
    fadeTimeout: 5,
    borderRadius: 16,
    padding: 16,
  )
  result.recording = RecordingConfig(
    outputDir: expandHome("~/captions"),
    saveAudio: true,
    saveTranscript: true,
  )
  result.summary = SummaryConfig(
    enabled: true,
    modelPath: expandHome("~/.local/share/captions/phi-3.1-mini-128k-instruct-q4_k_m.gguf"),
    prompt: "Summarize the following transcript concisely, highlighting key points and action items:",
    gpuLayers: -1,
    maxTokens: 256,
  )
  result.daemon = DaemonConfig(
    socketPath: "/tmp/captions.sock",
  )

proc getStr(t: TomlValueRef, key: string, default: string): string =
  if t.hasKey(key):
    t[key].getStr()
  else:
    default

proc getInt(t: TomlValueRef, key: string, default: int): int =
  if t.hasKey(key):
    t[key].getInt().int
  else:
    default

proc getBool(t: TomlValueRef, key: string, default: bool): bool =
  if t.hasKey(key):
    t[key].getBool()
  else:
    default

proc loadConfig*(path: string = ""): AppConfig =
  result = defaultConfig()

  var configPath = path
  if configPath == "":
    configPath = getConfigDir() / "captions" / "captions.toml"

  if not fileExists(configPath):
    return

  let toml = parsetoml.parseFile(configPath)

  if toml.hasKey("audio"):
    let a = toml["audio"]
    result.audio.sampleRate = a.getInt("sample_rate", result.audio.sampleRate)
    result.audio.channels = a.getInt("channels", result.audio.channels)
    result.audio.bufferSeconds = a.getInt("buffer_seconds", result.audio.bufferSeconds)
    result.audio.captureMic = a.getBool("capture_mic", result.audio.captureMic)
    result.audio.captureSink = a.getBool("capture_sink", result.audio.captureSink)
    result.audio.monitorDevice = a.getStr("monitor_device", result.audio.monitorDevice)

  if toml.hasKey("whisper"):
    let w = toml["whisper"]
    result.whisper.modelPath = expandHome(w.getStr("model_path", result.whisper.modelPath))
    result.whisper.chunkMs = w.getInt("chunk_ms", result.whisper.chunkMs)
    result.whisper.overlapMs = w.getInt("overlap_ms", result.whisper.overlapMs)
    result.whisper.strategy = w.getStr("strategy", result.whisper.strategy)
    result.whisper.threads = w.getInt("threads", result.whisper.threads)
    result.whisper.language = w.getStr("language", result.whisper.language)

  if toml.hasKey("overlay"):
    let o = toml["overlay"]
    result.overlay.font = o.getStr("font", result.overlay.font)
    result.overlay.textColor = o.getStr("text_color", result.overlay.textColor)
    result.overlay.bgColor = o.getStr("bg_color", result.overlay.bgColor)
    result.overlay.maxLines = o.getInt("max_lines", result.overlay.maxLines)
    result.overlay.marginBottom = o.getInt("margin_bottom", result.overlay.marginBottom)
    result.overlay.marginSide = o.getInt("margin_side", result.overlay.marginSide)
    result.overlay.fadeTimeout = o.getInt("fade_timeout", result.overlay.fadeTimeout)
    result.overlay.borderRadius = o.getInt("border_radius", result.overlay.borderRadius)
    result.overlay.padding = o.getInt("padding", result.overlay.padding)

  if toml.hasKey("recording"):
    let r = toml["recording"]
    result.recording.outputDir = expandHome(r.getStr("output_dir", result.recording.outputDir))
    result.recording.saveAudio = r.getBool("save_audio", result.recording.saveAudio)
    result.recording.saveTranscript = r.getBool("save_transcript", result.recording.saveTranscript)

  if toml.hasKey("summary"):
    let s = toml["summary"]
    result.summary.enabled = s.getBool("enabled", result.summary.enabled)
    result.summary.modelPath = expandHome(s.getStr("model_path", result.summary.modelPath))
    result.summary.prompt = s.getStr("prompt", result.summary.prompt)
    result.summary.gpuLayers = s.getInt("gpu_layers", result.summary.gpuLayers)
    result.summary.maxTokens = s.getInt("max_tokens", result.summary.maxTokens)

  if toml.hasKey("daemon"):
    let d = toml["daemon"]
    result.daemon.socketPath = d.getStr("socket_path", result.daemon.socketPath)
