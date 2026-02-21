## Test harness to compare summary quality across different models.
## Usage: nim c -r test_models.nim

import std/[os, strformat, times, strutils]
import src/captions/[summary, config]

# Real transcript from actual captions session (38KB, ~53 minutes)
# Topics: Rumi poetry, Sufism, spiritual practices, meditation, phone usage,
# higher power concepts, mycelium metaphor, work discussion (RSS feeds, LLMs,
# editorial workflow, WordPress infrastructure, Slack communication theory,
# Conway's Law)
const testTranscript = staticRead("/home/erik/captions/2026-02-17T15-00-22/transcript.txt")

proc testModel(modelPath: string, modelName: string): string =
  ## Run summary generation and return the result
  if not fileExists(modelPath):
    return &"❌ Model not found: {modelPath}\n   Download with: make download-test-models"

  echo "\n" & "=".repeat(70)
  echo &"Testing: {modelName}"
  echo &"Model: {modelPath}"
  echo "=".repeat(70)

  let cfg = SummaryConfig(
    enabled: true,
    modelPath: modelPath,
    prompt: "You are a precise summarization assistant. Summarize ONLY the information present in the following transcript. Do not add speculation or external information. Focus on:\n- Key topics discussed\n- Important points mentioned\n- Action items or decisions (if any)\nBe factual and concise.",
    gpuLayers: -1,
    maxTokens: 512,  # Longer transcript needs more tokens
  )

  let startTime = cpuTime()
  let summary = generateSummary(cfg, testTranscript)
  let elapsed = cpuTime() - startTime

  if summary.len == 0:
    return &"❌ Generation failed for {modelName}"

  result = &"""
📊 Model: {modelName}
⏱️  Time: {elapsed:.1f}s ({(testTranscript.len / elapsed.int):.0f} chars/sec)
📝 Output ({summary.len} chars, {summary.split('\n').len} lines):

{summary}

"""
  return result

proc main() =
  echo """
╔══════════════════════════════════════════════════════════════════╗
║           Model Comparison Test Harness                          ║
║           Testing Qwen2.5 7B vs 14B vs 32B                       ║
╚══════════════════════════════════════════════════════════════════╝

Test Transcript: Real 53-minute conversation
Size: """ & $testTranscript.len & """ chars (~""" & $(testTranscript.len div 1024) & """KB)
Topics: Sufism/Rumi, spirituality, meditation, work infrastructure, LLMs
""" & "-".repeat(70) & """
"""

  # Platform-aware model directory
  let modelDir = when defined(macosx):
    getHomeDir() / "Library/Application Support/captions"
  else:
    getHomeDir() / ".local/share/captions"

  echo &"Model directory: {modelDir}\n"
  echo "This will test how well each model summarizes a long, multi-topic"
  echo "conversation without hallucinating or losing key details.\n"

  # Test all three models
  let results = [
    testModel(
      modelDir / "qwen2.5-7b-instruct-q4_k_m.gguf",
      "Qwen2.5-7B-Instruct (Q4_K_M)"
    ),
    testModel(
      modelDir / "qwen2.5-14b-instruct-q4_k_m.gguf",
      "Qwen2.5-14B-Instruct (Q4_K_M)"
    ),
    testModel(
      modelDir / "qwen2.5-32b-instruct-q4_k_m.gguf",
      "Qwen2.5-32B-Instruct (Q4_K_M)"
    ),
  ]

  echo "\n"
  echo "╔══════════════════════════════════════════════════════════════════╗"
  echo "║                     COMPARISON RESULTS                           ║"
  echo "╚══════════════════════════════════════════════════════════════════╝"

  for r in results:
    echo r

  echo "\n📋 Evaluation Criteria:"
  echo "  1. Factual accuracy (no hallucinations about people/topics not in transcript)"
  echo "  2. Coverage (captures both spiritual AND work discussions)"
  echo "  3. Specificity (preserves key details: Rumi, mycelium, Conway's Law, etc.)"
  echo "  4. Structure (coherent organization of multiple topics)"
  echo "  5. Conciseness (no fluff, just key points)"
  echo ""
  echo "Key details to verify:"
  echo "  • Rumi poetry reading (\"Worms Waking\")"
  echo "  • Sunday morning meetings about higher power"
  echo "  • Phone restriction card (can't use until 6:30-7am)"
  echo "  • Mycelium network metaphor for interconnectedness"
  echo "  • Black Elk Speaks book discussion"
  echo "  • RSS feed compilation (500 feeds)"
  echo "  • Newsletter embeddings for semantic search"
  echo "  • WordPress infrastructure issues"
  echo "  • LLM editorial workflow with Jeremy"
  echo "  • Miami meeting planning (Tuesday afternoon)"
  echo "  • Slack channel philosophy & Conway's Law"
  echo "  • 2FA authentication discussion"

when isMainModule:
  main()
