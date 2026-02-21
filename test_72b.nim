## Test Qwen2.5-72B - The best open source model
## Usage: nim c -r test_72b.nim

import std/[os, strformat, times, strutils]
import src/captions/[summary, config]

const testTranscript = staticRead("/home/erik/captions/2026-02-17T15-00-22/transcript.txt")

proc main() =
  let modelPath = getHomeDir() / ".local/share/captions/qwen2.5-72b-instruct-q4_k_m.gguf"

  if not fileExists(modelPath):
    echo "❌ Model not found: " & modelPath
    echo "Download first with:"
    echo "  cd ~/.local/share/captions"
    echo "  wget https://huggingface.co/bartowski/Qwen2.5-72B-Instruct-GGUF/resolve/main/Qwen2.5-72B-Instruct-Q4_K_S.gguf"
    quit(1)

  echo """
╔══════════════════════════════════════════════════════════════════╗
║     Qwen2.5-72B Quality Test (GPT-4 Class)                      ║
╚══════════════════════════════════════════════════════════════════╝

Model: Qwen2.5-72B-Instruct Q4_K_M (44GB)
Transcript: 38KB Sufism conversation (53 minutes)
Target: Match or exceed Claude's summary quality

This may take 90-120 seconds. Quality over speed!

"""

  # Use moderate sampler settings - 72B doesn't need aggressive penalties
  let cfg = SummaryConfig(
    enabled: true,
    modelPath: modelPath,
    prompt: """You are a precise summarization assistant. Summarize ONLY the information present in the following transcript. Do not add speculation or external information.

Create a well-structured summary with:
- Clear sections for different topic areas
- Specific details preserved (names, numbers, dates, times)
- Concrete action items with context
- Professional markdown formatting

Focus on:
- Key topics discussed
- Important points mentioned
- Action items or decisions (with specifics)
- Attendees and any mentioned timeframes

Be thorough but concise.""",
    gpuLayers: -1,
    maxTokens: 1024,  # Allow longer, more detailed summaries
  )

  echo "Generating summary with 72B model..."
  echo "Expected time: 90-120 seconds"
  echo ""

  let startTime = cpuTime()
  let summary = generateSummary(cfg, testTranscript)
  let elapsed = cpuTime() - startTime

  if summary.len == 0:
    echo "❌ Generation failed"
    quit(1)

  echo "═".repeat(70)
  echo "✅ GENERATION COMPLETE"
  echo "═".repeat(70)
  echo &"Time: {elapsed:.1f}s ({(testTranscript.len.float / elapsed):.0f} chars/sec)"
  let lineCount = summary.count('\n') + 1
  echo &"Output: {summary.len} chars, {lineCount} lines"
  echo ""
  echo "═".repeat(70)
  echo "72B SUMMARY OUTPUT:"
  echo "═".repeat(70)
  echo summary
  echo ""
  echo "═".repeat(70)
  echo "COMPARISON TO CLAUDE (2243 chars, 50 lines):"
  echo "═".repeat(70)
  echo ""
  echo "Evaluate:"
  echo "  • Does it capture specific names? (Jeremy, Teddy, etc.)"
  echo "  • Does it preserve numbers? (500 RSS feeds, 6:30-7 AM, etc.)"
  echo "  • Are action items specific and actionable?"
  echo "  • Is the structure professional and well-organized?"
  echo "  • Does it cover BOTH spiritual and work topics thoroughly?"
  echo ""
  echo "If 72B matches or exceeds Claude quality → SUCCESS!"
  echo ""

when isMainModule:
  main()
