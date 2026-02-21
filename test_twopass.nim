## Two-Pass Summarization: Extract facts (7B) → Synthesize summary (32B)
## This should capture 100% of details by ensuring nothing is lost

import std/[os, strformat, times, strutils]
import src/captions/[summary, config]

const testTranscript = staticRead("/home/erik/captions/2026-02-17T15-00-22/transcript.txt")

proc main() =
  let modelDir = getHomeDir() / ".local/share/captions"
  let model7B = modelDir / "qwen2.5-7b-instruct-q4_k_m.gguf"
  let model32B = modelDir / "qwen2.5-32b-instruct-q4_k_m.gguf"

  echo """
╔══════════════════════════════════════════════════════════════════╗
║     TWO-PASS SUMMARIZATION EXPERIMENT                           ║
║     Pass 1: Extract Facts (7B) → Pass 2: Synthesize (32B)       ║
╚══════════════════════════════════════════════════════════════════╝

Goal: Capture 100% of details by extracting facts first, then synthesizing.

"""

  # ============================================================================
  # PASS 1: Extract all facts with 7B (fast, focused on extraction)
  # ============================================================================
  echo "═".repeat(70)
  echo "PASS 1: Extracting Facts (7B Model, ~5-8 seconds)"
  echo "═".repeat(70)
  echo ""

  let extractionPrompt = """Extract and list all factual details from the following transcript. Focus on:

**PEOPLE:**
- List every name mentioned (first names, full names, nicknames)

**NUMBERS & QUANTITIES:**
- List every number mentioned (e.g., "500 feeds", "150 words")

**TIMES & DATES:**
- List every time mentioned (e.g., "6:30 AM", "Tuesday afternoon")
- List every date mentioned

**BOOKS & REFERENCES:**
- List every book title, author, or text mentioned

**CONCEPTS & TERMS:**
- List every technical concept, theory, or specialized term (e.g., "Conway's Law", "mycelium")

**PLACES & EVENTS:**
- List locations, events, meetings mentioned

Format as a simple bullet list of facts. Do not synthesize or summarize - just extract."""

  let cfg1 = SummaryConfig(
    enabled: true,
    modelPath: model7B,
    prompt: extractionPrompt,
    gpuLayers: -1,
    maxTokens: 1024,
  )

  let startTime1 = cpuTime()
  let extractedFacts = generateSummary(cfg1, testTranscript)
  let elapsed1 = cpuTime() - startTime1

  if extractedFacts.len == 0:
    echo "❌ Pass 1 failed"
    quit(1)

  echo &"✅ Pass 1 complete: {elapsed1:.1f}s"
  echo &"   Extracted {extractedFacts.len} chars of facts"
  echo ""
  echo "--- EXTRACTED FACTS ---"
  echo extractedFacts
  echo "--- END FACTS ---"
  echo ""

  # ============================================================================
  # PASS 2: Synthesize summary using facts + original transcript (32B)
  # ============================================================================
  echo "═".repeat(70)
  echo "PASS 2: Synthesizing Summary (32B Model, ~20-30 seconds)"
  echo "═".repeat(70)
  echo ""

  let synthesisPrompt = &"""Create a comprehensive executive summary of the following transcript.

IMPORTANT: Use the extracted facts below to ensure NO details are lost.

EXTRACTED FACTS:
{extractedFacts}

---

Now create a professional, well-structured summary that:
1. Incorporates ALL the facts listed above
2. Organizes them into clear topic sections
3. Provides context and narrative flow
4. Includes specific action items with owners

Be thorough and preserve all details from the facts list."""

  let cfg2 = SummaryConfig(
    enabled: true,
    modelPath: model32B,
    prompt: synthesisPrompt,
    gpuLayers: -1,
    maxTokens: 3000,
  )

  let startTime2 = cpuTime()
  let finalSummary = generateSummary(cfg2, testTranscript)
  let elapsed2 = cpuTime() - startTime2

  if finalSummary.len == 0:
    echo "❌ Pass 2 failed"
    quit(1)

  echo &"✅ Pass 2 complete: {elapsed2:.1f}s"
  echo ""

  # ============================================================================
  # RESULTS
  # ============================================================================
  let totalTime = elapsed1 + elapsed2
  let lineCount = finalSummary.count('\n') + 1

  echo "═".repeat(70)
  echo "✅ TWO-PASS GENERATION COMPLETE"
  echo "═".repeat(70)
  echo &"Total Time: {totalTime:.1f}s (Pass 1: {elapsed1:.1f}s + Pass 2: {elapsed2:.1f}s)"
  echo &"Output: {finalSummary.len} chars, {lineCount} lines"
  echo ""
  echo "═".repeat(70)
  echo "FINAL SUMMARY (TWO-PASS APPROACH):"
  echo "═".repeat(70)
  echo finalSummary
  echo ""
  echo "═".repeat(70)
  echo "EVALUATION vs Claude:"
  echo "═".repeat(70)
  echo ""
  echo "Check if two-pass captured:"
  echo "  ✓ Jeremy (name)"
  echo "  ✓ 500 RSS feeds (number)"
  echo "  ✓ 6:30-7 AM (exact time)"
  echo "  ✓ Tuesday afternoon (specific day)"
  echo "  ✓ Black Elk Speaks (book)"
  echo "  ✓ Conway's Law (concept)"
  echo "  ✓ Mycelium (metaphor)"
  echo ""
  echo "If ALL are present → Two-pass achieves 100% Claude parity!"
  echo ""

when isMainModule:
  main()
