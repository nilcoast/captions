## Streaming transcription using whisper.cpp.
## Reads chunks from the ring buffer and runs inference.

import std/[atomics, math, strutils, logging, os]

const
  SILENCE_RMS_THRESHOLD = 0.003  # ~-50 dBFS, skip whisper on silence
import ./audio
import ./config

# --- whisper.cpp C bindings (low-level) ---

{.passl: "-lwhisper".}
when defined(macosx) and defined(arm64):
  {.passc: "-I/opt/homebrew/include".}
else:
  {.passc: "-I/usr/local/include".}

type
  WhisperContext* {.importc: "struct whisper_context", header: "whisper.h", incompleteStruct.} = object
  WhisperContextPtr* = ptr WhisperContext

  WhisperContextParams* {.importc: "struct whisper_context_params", header: "whisper.h".} = object
    use_gpu*: bool
    flash_attn*: bool
    gpu_device*: cint
    dtw_token_timestamps*: bool
    dtw_aheads_preset*: cint
    dtw_n_top*: cint
    dtw_aheads*: WhisperAheads
    dtw_mem_size*: csize_t

  WhisperAheads* {.importc: "struct whisper_ahead", header: "whisper.h".} = object
    n_heads*: csize_t
    heads*: pointer

  WhisperFullParams* {.importc: "struct whisper_full_params", header: "whisper.h".} = object
    strategy*: cint
    n_threads*: cint
    n_max_text_ctx*: cint
    offset_ms*: cint
    duration_ms*: cint
    translate*: bool
    no_context*: bool
    no_timestamps*: bool
    single_segment*: bool
    print_special*: bool
    print_progress*: bool
    print_realtime*: bool
    print_timestamps*: bool
    token_timestamps*: bool
    thold_pt*: cfloat
    thold_ptsum*: cfloat
    max_len*: cint
    split_on_word*: bool
    max_tokens*: cint
    debug_mode*: bool
    audio_ctx*: cint
    tdrz_enable*: bool
    suppress_regex*: cstring
    initial_prompt*: cstring
    prompt_tokens*: ptr cint
    prompt_n_tokens*: cint
    language*: cstring
    detect_language*: bool
    suppress_blank*: bool
    suppress_nst*: bool
    temperature*: cfloat
    max_initial_ts*: cfloat
    length_penalty*: cfloat
    temperature_inc*: cfloat
    entropy_thold*: cfloat
    logprob_thold*: cfloat
    no_speech_thold*: cfloat
    greedy*: WhisperGreedy
    beam_search*: WhisperBeamSearch

  WhisperGreedy* {.importc: "struct whisper_full_params::anon_greedy".} = object
    best_of*: cint

  WhisperBeamSearch* {.importc: "struct whisper_full_params::anon_beam_search".} = object
    beam_size*: cint
    patience*: cfloat

const
  WHISPER_SAMPLING_GREEDY* = 0.cint
  WHISPER_SAMPLING_BEAM_SEARCH* = 1.cint

proc whisper_init_from_file_with_params*(path: cstring, params: WhisperContextParams): WhisperContextPtr {.importc, header: "whisper.h".}
proc whisper_free*(ctx: WhisperContextPtr) {.importc, header: "whisper.h".}
proc whisper_full_default_params*(strategy: cint): WhisperFullParams {.importc, header: "whisper.h".}
proc whisper_context_default_params*(): WhisperContextParams {.importc, header: "whisper.h".}
proc whisper_full*(ctx: WhisperContextPtr, params: WhisperFullParams, samples: ptr cfloat, n_samples: cint): cint {.importc, header: "whisper.h".}
proc whisper_full_n_segments*(ctx: WhisperContextPtr): cint {.importc, header: "whisper.h".}
proc whisper_full_get_segment_text*(ctx: WhisperContextPtr, i_segment: cint): cstring {.importc, header: "whisper.h".}
proc whisper_full_n_tokens*(ctx: WhisperContextPtr, i_segment: cint): cint {.importc, header: "whisper.h".}
proc whisper_full_get_token_id*(ctx: WhisperContextPtr, i_segment: cint, i_token: cint): cint {.importc, header: "whisper.h".}

# --- Transcriber ---

type
  Transcriber* = object
    ctx: WhisperContextPtr
    cfg: WhisperConfig
    audioCfg: AudioConfig
    rings: array[2, ptr RingBuffer]  # [0] = mic, [1] = sink (nil if unused)
    numRings: int
    active*: ptr Atomic[bool]
    thread: Thread[ptr Transcriber]
    onText*: proc(text: string) {.gcsafe.}
    promptTokens: seq[cint]
    lastTotals: array[2, int64]

proc newTranscriber*(cfg: WhisperConfig, audioCfg: AudioConfig,
                     rings: openArray[ptr RingBuffer],
                     active: ptr Atomic[bool]): ptr Transcriber =
  result = cast[ptr Transcriber](allocShared0(sizeof(Transcriber)))
  result.cfg = cfg
  result.audioCfg = audioCfg
  result.numRings = min(rings.len, 2)
  for i in 0 ..< result.numRings:
    result.rings[i] = rings[i]
  result.active = active
  result.lastTotals = [0'i64, 0'i64]
  result.onText = nil

  if not fileExists(cfg.modelPath):
    error "Whisper model not found: " & cfg.modelPath
    return

  let ctxParams = whisper_context_default_params()
  result.ctx = whisper_init_from_file_with_params(cfg.modelPath.cstring, ctxParams)
  if result.ctx == nil:
    error "Failed to initialize whisper context"

proc mixBuffers(bufs: openArray[seq[float32]]): seq[float32] =
  ## Mix multiple audio buffers by summing samples and clamping to [-1, 1].
  var maxLen = 0
  for b in bufs:
    if b.len > maxLen: maxLen = b.len
  result = newSeq[float32](maxLen)
  for b in bufs:
    for i in 0 ..< b.len:
      result[i] += b[i]
  # Clamp
  for i in 0 ..< result.len:
    if result[i] > 1.0f: result[i] = 1.0f
    elif result[i] < -1.0f: result[i] = -1.0f

proc transcribeLoop(t: ptr Transcriber) {.thread.} =
  let chunkSamples = (t.cfg.chunkMs * t.audioCfg.sampleRate) div 1000
  let overlapSamples = (t.cfg.overlapMs * t.audioCfg.sampleRate) div 1000
  let readSamples = chunkSamples + overlapSamples
  let sleepMs = t.cfg.chunkMs

  while t.active[].load(moRelaxed):
    # Wait until at least one ring has enough samples
    var anyReady = false
    for i in 0 ..< t.numRings:
      let available = t.rings[i].totalWritten - t.lastTotals[i]
      if available >= chunkSamples.int64:
        anyReady = true
        break
    if not anyReady:
      sleep(50)
      continue

    # Read from all active ring buffers and mix
    var bufs: seq[seq[float32]]
    for i in 0 ..< t.numRings:
      let ring = t.rings[i]
      bufs.add(read(ring, readSamples))
      t.lastTotals[i] = ring.totalWritten

    var samples = if bufs.len == 1: bufs[0]
                  else: mixBuffers(bufs)

    if samples.len == 0:
      sleep(50)
      continue

    # Skip silence — compute RMS energy
    var sumSq: float64 = 0
    for i in 0 ..< samples.len:
      sumSq += float64(samples[i]) * float64(samples[i])
    let rms = sqrt(sumSq / float64(samples.len))
    if rms < SILENCE_RMS_THRESHOLD:
      sleep(sleepMs)
      continue

    # Set up whisper params
    let strategy = if t.cfg.strategy == "beam": WHISPER_SAMPLING_BEAM_SEARCH
                   else: WHISPER_SAMPLING_GREEDY
    var params = whisper_full_default_params(strategy)
    params.n_threads = t.cfg.threads.cint
    params.print_realtime = false
    params.print_progress = false
    params.print_timestamps = false
    params.print_special = false
    params.single_segment = true
    params.no_timestamps = true
    params.language = t.cfg.language.cstring
    params.suppress_blank = true
    params.suppress_nst = true
    params.tdrz_enable = true

    # Use prompt tokens from previous chunk for continuity
    if t.promptTokens.len > 0:
      params.prompt_tokens = addr t.promptTokens[0]
      params.prompt_n_tokens = t.promptTokens.len.cint
    else:
      params.prompt_tokens = nil
      params.prompt_n_tokens = 0

    # Run inference
    let ret = whisper_full(t.ctx, params, addr samples[0], samples.len.cint)
    if ret != 0:
      warn "whisper_full returned: " & $ret
      continue

    # Extract text
    let nSeg = whisper_full_n_segments(t.ctx)
    var text = ""
    for i in 0 ..< nSeg:
      let segText = $whisper_full_get_segment_text(t.ctx, i.cint)
      text.add(segText.strip())
      if i < nSeg - 1:
        text.add(" ")

    # Save prompt tokens from last segment for next chunk
    if nSeg > 0:
      let lastSeg = nSeg - 1
      let nTokens = whisper_full_n_tokens(t.ctx, lastSeg.cint)
      t.promptTokens.setLen(nTokens)
      for j in 0 ..< nTokens:
        t.promptTokens[j] = whisper_full_get_token_id(t.ctx, lastSeg.cint, j.cint)

    # Send text to callback — split on speaker turns so each gets its own line
    if text.len > 0 and t.onText != nil:
      let parts = text.split("[SPEAKER_TURN]")
      for part in parts:
        let trimmed = part.strip()
        if trimmed.len > 0:
          t.onText(trimmed)

    sleep(sleepMs)

proc start*(t: ptr Transcriber) =
  if t.ctx == nil:
    error "Cannot start transcriber: no whisper context"
    return
  for i in 0 ..< t.numRings:
    t.lastTotals[i] = t.rings[i].totalWritten
  t.promptTokens = @[]
  createThread(t.thread, transcribeLoop, t)

proc join*(t: ptr Transcriber) =
  joinThread(t.thread)

proc destroy*(t: ptr Transcriber) =
  if t.ctx != nil:
    whisper_free(t.ctx)
  deallocShared(t)
