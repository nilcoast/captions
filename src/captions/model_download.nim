## Model download with resume support and progress reporting.
## Downloads GGUF models from Hugging Face.

import std/[os, httpclient, strutils, strformat, logging]
import ./hardware

type
  ModelInfo* = object
    url*: string
    filename*: string
    sizeMb*: int

  ProgressCallback* = proc(downloaded, total: int64)

const Models*: array[ModelTier, ModelInfo] = [
  mt7B: ModelInfo(
    url: "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
    filename: "qwen2.5-7b-instruct-q4_k_m.gguf",
    sizeMb: 4400,
  ),
  mt14B: ModelInfo(
    url: "https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf",
    filename: "qwen2.5-14b-instruct-q4_k_m.gguf",
    sizeMb: 8300,
  ),
  mt32B: ModelInfo(
    url: "https://huggingface.co/bartowski/Qwen2.5-32B-Instruct-GGUF/resolve/main/Qwen2.5-32B-Instruct-Q4_K_M.gguf",
    filename: "qwen2.5-32b-instruct-q4_k_m.gguf",
    sizeMb: 18900,
  ),
]

proc modelDir*(): string =
  when defined(macosx):
    getHomeDir() / "Library" / "Application Support" / "captions"
  else:
    getHomeDir() / ".local" / "share" / "captions"

proc modelPath*(tier: ModelTier): string =
  modelDir() / Models[tier].filename

proc isModelDownloaded*(tier: ModelTier): bool =
  fileExists(modelPath(tier))

proc downloadModel*(tier: ModelTier, progress: ProgressCallback = nil) =
  ## Download a model with resume support (.part file).
  let info = Models[tier]
  let destDir = modelDir()
  createDir(destDir)

  let destPath = destDir / info.filename
  let partPath = destPath & ".part"

  if fileExists(destPath):
    info &"Model already exists: {destPath}"
    return

  # Check for partial download (resume support)
  var startByte: int64 = 0
  if fileExists(partPath):
    startByte = getFileSize(partPath)
    info &"Resuming download from byte {startByte}"

  let client = newHttpClient(timeout = 30_000)
  defer: client.close()

  if startByte > 0:
    client.headers = newHttpHeaders({
      "Range": &"bytes={startByte}-"
    })

  info &"Downloading {info.filename} (~{info.sizeMb} MB)..."

  try:
    let resp = client.get(info.url)

    if resp.code notin {Http200, Http206}:
      error &"Download failed with HTTP {resp.code}"
      return

    # Get total size from Content-Length or Content-Range
    var totalSize: int64 = -1
    let contentLength = resp.headers.getOrDefault("Content-Length")
    if contentLength.len > 0:
      try:
        totalSize = parseBiggestInt(contentLength) + startByte
      except ValueError:
        discard

    # Write to .part file
    let mode = if startByte > 0: fmAppend else: fmWrite
    var f: File
    if not open(f, partPath, mode):
      error "Failed to open file for writing: " & partPath
      return
    defer: f.close()

    let body = resp.body
    f.write(body)

    if progress != nil:
      progress(startByte + body.len.int64, totalSize)

    # Rename .part to final filename
    f.close()
    moveFile(partPath, destPath)
    info &"Model downloaded: {destPath}"

  except CatchableError as e:
    error &"Download failed: {e.msg}"
    info "Partial download saved. Re-run to resume."

type
  DownloadArgs = tuple[tier: ModelTier, progress: ProgressCallback]

var downloadThread: Thread[DownloadArgs]

proc downloadThreadProc(args: DownloadArgs) {.thread.} =
  {.cast(gcsafe).}:
    downloadModel(args.tier, args.progress)

proc spawnDownload*(tier: ModelTier, progress: ProgressCallback = nil) =
  ## Fire-and-forget: spawns model download in a background thread.
  {.cast(gcsafe).}:
    createThread(downloadThread, downloadThreadProc, (tier, progress))
