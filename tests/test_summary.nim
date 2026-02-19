## Quick test harness: run summary on an existing transcript file.
## Usage: ./test_summary <transcript.txt> [output_dir]

import std/[os, strutils, times, strformat]
import ../src/captions/config
import ../src/captions/summary

proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo "Usage: test_summary <transcript.txt> [output_dir]"
    quit(1)

  let transcriptPath = args[0]
  if not fileExists(transcriptPath):
    echo "File not found: ", transcriptPath
    quit(1)

  let transcript = readFile(transcriptPath)
  echo &"Transcript: {transcriptPath} ({transcript.len} bytes, {transcript.countLines} lines)"

  let cfg = defaultConfig().summary
  echo &"Model: {cfg.modelPath}"
  echo &"GPU layers: {cfg.gpuLayers}"
  echo &"Max tokens: {cfg.maxTokens}"
  echo ""

  let t0 = cpuTime()
  let result = generateSummary(cfg, transcript)
  let elapsed = cpuTime() - t0

  echo &"--- Summary ({elapsed:.1f}s) ---"
  echo result
  echo "---"

  if args.len >= 2:
    let outDir = args[1]
    createDir(outDir)
    let outPath = outDir / "summary.txt"
    writeFile(outPath, result)
    echo &"Saved to {outPath}"

when isMainModule:
  main()
