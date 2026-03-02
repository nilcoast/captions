## Configuration loading from TOML with sensible defaults.
## Includes saveConfig for round-tripping config back to disk.

import std/[os, strutils, strformat]
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

  ExternalSummaryConfig* = object
    apiUrl*: string     # OpenAI-compatible API base URL
    apiKey*: string     # plain text, "env:VAR_NAME", or "file:~/.config/captions/api_key"
    model*: string      # e.g. "gpt-4o-mini"
    maxTokens*: int     # max tokens for summary output

  SummaryConfig* = object
    enabled*: bool
    modelPath*: string  # path to GGUF model file
    prompt*: string
    gpuLayers*: int     # number of GPU layers to offload (-1 = all, 0 = CPU only)
    maxTokens*: int     # max tokens for summary output
    backend*: string    # "local" (default) or "external"
    external*: ExternalSummaryConfig

  TrayConfig* = object
    enabled*: bool

  ShortcutConfig* = object
    enabled*: bool
    keybinding*: string  # "<Super>c" (Linux) / "Cmd+Shift+C" (macOS)

  DaemonConfig* = object
    socketPath*: string

  AppConfig* = object
    audio*: AudioConfig
    whisper*: WhisperConfig
    overlay*: OverlayConfig
    recording*: RecordingConfig
    summary*: SummaryConfig
    daemon*: DaemonConfig
    tray*: TrayConfig
    shortcut*: ShortcutConfig

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
    captureMic: true,
    captureSink: true,
    monitorDevice: "",
  )
  result.whisper = WhisperConfig(
    modelPath: when defined(macosx):
      expandHome("~/Library/Application Support/captions/ggml-base.en.bin")
    else:
      expandHome("~/.local/share/captions/ggml-base.en.bin"),
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
    modelPath: when defined(macosx):
      expandHome("~/Library/Application Support/captions/qwen2.5-7b-instruct-q4_k_m.gguf")
    else:
      expandHome("~/.local/share/captions/qwen2.5-7b-instruct-q4_k_m.gguf"),
    prompt: "You are a precise summarization assistant. Summarize ONLY the information present in the following transcript. Do not add speculation or external information. Focus on:\n- Key topics discussed\n- Important points mentioned\n- Action items or decisions (if any)\nBe factual and concise.",
    gpuLayers: -1,
    maxTokens: 256,
    backend: "local",
    external: ExternalSummaryConfig(
      apiUrl: "https://api.openai.com/v1",
      apiKey: "",
      model: "gpt-4o-mini",
      maxTokens: 512,
    ),
  )
  result.daemon = DaemonConfig(
    socketPath: "/tmp/captions.sock",
  )
  result.tray = TrayConfig(
    enabled: true,
  )
  result.shortcut = ShortcutConfig(
    enabled: true,
    keybinding: when defined(macosx): "Cmd+Shift+C" else: "<Super>c",
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
    result.summary.backend = s.getStr("backend", result.summary.backend)
    if s.hasKey("external"):
      let e = s["external"]
      result.summary.external.apiUrl = e.getStr("api_url", result.summary.external.apiUrl)
      result.summary.external.apiKey = e.getStr("api_key", result.summary.external.apiKey)
      result.summary.external.model = e.getStr("model", result.summary.external.model)
      result.summary.external.maxTokens = e.getInt("max_tokens", result.summary.external.maxTokens)

  if toml.hasKey("daemon"):
    let d = toml["daemon"]
    result.daemon.socketPath = d.getStr("socket_path", result.daemon.socketPath)

  if toml.hasKey("tray"):
    let t = toml["tray"]
    result.tray.enabled = t.getBool("enabled", result.tray.enabled)

  if toml.hasKey("shortcut"):
    let sc = toml["shortcut"]
    result.shortcut.enabled = sc.getBool("enabled", result.shortcut.enabled)
    result.shortcut.keybinding = sc.getStr("keybinding", result.shortcut.keybinding)

proc configPath*(): string =
  getConfigDir() / "captions" / "captions.toml"

proc escToml(s: string): string =
  ## Escape a string for TOML — double-quote with backslash escapes.
  result = "\""
  for c in s:
    case c
    of '\\': result.add("\\\\")
    of '"': result.add("\\\"")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(c)
  result.add("\"")

proc saveConfig*(cfg: AppConfig, path: string = "") =
  ## Serialize config back to TOML.
  var p = path
  if p == "":
    p = configPath()

  createDir(parentDir(p))

  var lines: seq[string]

  lines.add("[audio]")
  lines.add(&"sample_rate = {cfg.audio.sampleRate}")
  lines.add(&"channels = {cfg.audio.channels}")
  lines.add(&"buffer_seconds = {cfg.audio.bufferSeconds}")
  lines.add(&"capture_mic = {cfg.audio.captureMic}")
  lines.add(&"capture_sink = {cfg.audio.captureSink}")
  lines.add(&"monitor_device = {escToml(cfg.audio.monitorDevice)}")
  lines.add("")

  lines.add("[whisper]")
  lines.add(&"model_path = {escToml(cfg.whisper.modelPath)}")
  lines.add(&"chunk_ms = {cfg.whisper.chunkMs}")
  lines.add(&"overlap_ms = {cfg.whisper.overlapMs}")
  lines.add(&"strategy = {escToml(cfg.whisper.strategy)}")
  lines.add(&"threads = {cfg.whisper.threads}")
  lines.add(&"language = {escToml(cfg.whisper.language)}")
  lines.add("")

  lines.add("[overlay]")
  lines.add(&"font = {escToml(cfg.overlay.font)}")
  lines.add(&"text_color = {escToml(cfg.overlay.textColor)}")
  lines.add(&"bg_color = {escToml(cfg.overlay.bgColor)}")
  lines.add(&"max_lines = {cfg.overlay.maxLines}")
  lines.add(&"margin_bottom = {cfg.overlay.marginBottom}")
  lines.add(&"margin_side = {cfg.overlay.marginSide}")
  lines.add(&"fade_timeout = {cfg.overlay.fadeTimeout}")
  lines.add(&"border_radius = {cfg.overlay.borderRadius}")
  lines.add(&"padding = {cfg.overlay.padding}")
  lines.add("")

  lines.add("[recording]")
  lines.add(&"output_dir = {escToml(cfg.recording.outputDir)}")
  lines.add(&"save_audio = {cfg.recording.saveAudio}")
  lines.add(&"save_transcript = {cfg.recording.saveTranscript}")
  lines.add("")

  lines.add("[summary]")
  lines.add(&"enabled = {cfg.summary.enabled}")
  lines.add(&"model_path = {escToml(cfg.summary.modelPath)}")
  lines.add(&"prompt = {escToml(cfg.summary.prompt)}")
  lines.add(&"gpu_layers = {cfg.summary.gpuLayers}")
  lines.add(&"max_tokens = {cfg.summary.maxTokens}")
  lines.add(&"backend = {escToml(cfg.summary.backend)}")
  lines.add("")

  lines.add("[summary.external]")
  lines.add(&"api_url = {escToml(cfg.summary.external.apiUrl)}")
  lines.add(&"api_key = {escToml(cfg.summary.external.apiKey)}")
  lines.add(&"model = {escToml(cfg.summary.external.model)}")
  lines.add(&"max_tokens = {cfg.summary.external.maxTokens}")
  lines.add("")

  lines.add("[daemon]")
  lines.add(&"socket_path = {escToml(cfg.daemon.socketPath)}")
  lines.add("")

  lines.add("[tray]")
  lines.add(&"enabled = {cfg.tray.enabled}")
  lines.add("")

  lines.add("[shortcut]")
  lines.add(&"enabled = {cfg.shortcut.enabled}")
  lines.add(&"keybinding = {escToml(cfg.shortcut.keybinding)}")
  lines.add("")

  writeFile(p, lines.join("\n"))
