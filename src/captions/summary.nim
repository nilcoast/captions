## AI summary generation via the `llm` CLI tool.
## Spawns llm as a background process after session ends.

import std/[os, osproc, strutils, strformat, logging]
import ./config

proc spawnSummary*(cfg: SummaryConfig, transcript: string, sessionDir: string) =
  if not cfg.enabled:
    return

  if transcript.strip().len == 0:
    info "Empty transcript, skipping summary"
    return

  let outputPath = sessionDir / "summary.txt"

  # Write transcript to a temp file for llm to read
  let inputPath = sessionDir / ".transcript_input.txt"
  writeFile(inputPath, cfg.prompt & "\n\n" & transcript)

  # Build shell command: llm < input > output, runs in background
  var cmd = "llm"
  if cfg.model != "":
    cmd &= " -m " & quoteShell(cfg.model)
  cmd &= " < " & quoteShell(inputPath)
  cmd &= " > " & quoteShell(outputPath)
  cmd &= " && rm -f " & quoteShell(inputPath)
  cmd &= " && xdg-open " & quoteShell(outputPath)
  cmd &= " && gvim " & quoteShell(outputPath)

  # Fire and forget — the shell process outlives us if needed
  let p = startProcess("/bin/sh", args = ["-c", cmd], options = {poUsePath, poDaemon})
  info &"Summary generation started (pid {p.processID})"
  p.close()  # close handles, process continues in background
