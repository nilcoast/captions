## Test Qwen2.5-32B with tuned settings
## Usage: nim c -r test_32b.nim

import std/[os, strformat, times, strutils]
import src/captions/[summary, config]

const testTranscript = staticRead("/home/erik/captions/2026-02-17T15-00-22/transcript.txt")

proc main() =
  let modelPath = getHomeDir() / ".local/share/captions/qwen2.5-32b-instruct-q4_k_m.gguf"

  if not fileExists(modelPath):
    echo "❌ Model not found: " & modelPath
    echo "Still downloading?"
    quit(1)

  echo """
╔══════════════════════════════════════════════════════════════════╗
║     Qwen2.5-32B Quality Test                                     ║
╚══════════════════════════════════════════════════════════════════╝

Model: Qwen2.5-32B-Instruct Q4_K_M (18.9GB)
Transcript: 38KB Sufism conversation (53 minutes)
Target: Match Claude's summary quality

Testing with moderate sampler settings (not too aggressive)

"""

  # Use balanced sampler - not too restrictive for 32B
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
- Important points mentioned (with specifics!)
- Action items or decisions (with details)
- Any mentioned names, numbers, or timeframes

Be thorough and detailed.""",
    gpuLayers: -1,
    maxTokens: 1024,  # Allow detailed summaries
  )

  echo "Generating summary with 32B model..."
  echo "Expected time: 30-90 seconds"
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
  echo "32B SUMMARY OUTPUT:"
  echo "═".repeat(70)
  echo summary
  echo ""
  echo "═".repeat(70)
  echo "COMPARISON CHECKLIST vs Claude (2243 chars, 50 lines):"
  echo "═".repeat(70)
  echo ""
  echo "Did 32B capture:"
  echo "  ✓/✗ Specific names? (Jeremy, Teddy, etc.)"
  echo "  ✓/✗ Exact numbers? (500 RSS feeds)"
  echo "  ✓/✗ Exact times? (6:30-7 AM, Tuesday afternoon)"
  echo "  ✓/✗ Specific books? (Black Elk Speaks)"
  echo "  ✓/✗ Technical terms? (Conway's Law, mycelium)"
  echo "  ✓/✗ Detailed action items? (specific tasks, not vague)"
  echo "  ✓/✗ Professional structure? (sections, formatting)"
  echo "  ✓/✗ Both spiritual AND work topics thoroughly?"
  echo ""
  echo "If 32B gets 7-8 checkmarks → Use 32B (good enough!)"
  echo "If 32B gets <5 checkmarks → Wait for 72B (2 hours)"
  echo ""

when isMainModule:
  main()
