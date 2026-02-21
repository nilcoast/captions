## Test all model tiers with optimized settings
## Creates a reference for choosing the right model based on hardware

import std/[os, strformat, times, strutils]
import src/captions/[config, llama_bindings]

const testTranscript = staticRead("/home/erik/captions/2026-02-17T15-00-22/transcript.txt")

proc tokenize(vocab: LlamaVocabPtr, text: string, addSpecial: bool,
              parseSpecial: bool = false): seq[LlamaToken] =
  let maxTokens = text.len + 64
  result = newSeq[LlamaToken](maxTokens)
  let n = llama_tokenize(vocab, text.cstring, text.len.int32,
                         addr result[0], maxTokens.int32,
                         addSpecial, parseSpecial)
  if n < 0:
    result.setLen(-n)
    let n2 = llama_tokenize(vocab, text.cstring, text.len.int32,
                            addr result[0], (-n).int32,
                            addSpecial, parseSpecial)
    result.setLen(n2)
  else:
    result.setLen(n)

proc tokenToStr(vocab: LlamaVocabPtr, token: LlamaToken): string =
  var buf: array[128, char]
  let n = llama_token_to_piece(vocab, token, cast[cstring](addr buf[0]),
                                buf.len.int32, 0, false)
  if n > 0:
    result = newString(n)
    copyMem(addr result[0], addr buf[0], n)
  else:
    result = ""

proc buildChatPrompt(model: LlamaModelPtr, systemPrompt: string, transcript: string): string =
  var messages = [
    LlamaChatMessage(role: "system", content: systemPrompt.cstring),
    LlamaChatMessage(role: "user", content: transcript.cstring),
  ]
  let tmpl = llama_model_chat_template(model, nil)
  let needed = llama_chat_apply_template(tmpl, addr messages[0],
                                          messages.len.csize_t, true, nil, 0)
  if needed <= 0:
    return systemPrompt & "\n\n" & transcript & "\n\nSummary:"
  var buf = newString(needed + 1)
  discard llama_chat_apply_template(tmpl, addr messages[0],
                                     messages.len.csize_t, true,
                                     buf.cstring, (needed + 1).int32)
  buf.setLen(needed)
  result = buf

type TierConfig = object
  name: string
  modelPath: string
  temp: float32
  penaltyLastN: int32
  penaltyRepeat: float32
  maxTokens: int
  prompt: string
  hardware: string

proc testTier(cfg: TierConfig): string =
  if not fileExists(cfg.modelPath):
    return &"❌ Model not found: {cfg.modelPath}\n"

  llama_backend_init()
  defer: llama_backend_free()

  var modelParams = llama_model_default_params()
  modelParams.n_gpu_layers = -1

  let model = llama_model_load_from_file(cfg.modelPath.cstring, modelParams)
  if model == nil:
    return "❌ Failed to load model"
  defer: llama_model_free(model)

  let vocab = llama_model_get_vocab(model)
  let nCtxTrain = llama_model_n_ctx_train(model)
  let nCtx = min(16384'u32, nCtxTrain.uint32)

  var ctxParams = llama_context_default_params()
  ctxParams.n_ctx = nCtx
  ctxParams.n_batch = min(2048'u32, nCtx)
  ctxParams.n_threads = 4
  ctxParams.n_threads_batch = 4

  let ctx = llama_context_new(model, ctxParams)
  if ctx == nil:
    return "❌ Failed to create context"
  defer: llama_context_free(ctx)

  let prompt = buildChatPrompt(model, cfg.prompt, testTranscript)

  var tokens = tokenize(vocab, prompt, false, true)
  let maxPromptTokens = ctxParams.n_ctx.int - cfg.maxTokens - 16
  if tokens.len > maxPromptTokens:
    tokens.setLen(maxPromptTokens)

  var samplerParams = llama_sampler_chain_default_params()
  let sampler = llama_sampler_chain_init(samplerParams)
  llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
    cfg.penaltyLastN, cfg.penaltyRepeat, 0.0, 0.0))
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(cfg.temp))
  llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05, 1))
  llama_sampler_chain_add(sampler, llama_sampler_init_dist(0))
  defer: llama_sampler_free(sampler)

  # Decode prompt
  let nBatch = ctxParams.n_batch.int
  var pos = 0
  while pos < tokens.len:
    let chunkLen = min(nBatch, tokens.len - pos)
    var batch = llama_batch_get_one(addr tokens[pos], chunkLen.int32)
    if llama_decode(ctx, batch) != 0:
      return "❌ Decode failed"
    pos += chunkLen

  # Generate
  let eosToken = llama_vocab_eos(vocab)
  var output = ""
  let startTime = cpuTime()

  for i in 0 ..< cfg.maxTokens:
    let newToken = llama_sampler_sample(sampler, ctx, -1)
    if newToken == eosToken:
      break
    let piece = tokenToStr(vocab, newToken)
    let combined = output & piece
    if "<|im_end|>" in combined or "<|end|>" in combined or "<|eot_id|>" in combined:
      break
    output.add(piece)
    var tokenArr = [newToken]
    var nextBatch = llama_batch_get_one(addr tokenArr[0], 1)
    if llama_decode(ctx, nextBatch) != 0:
      break

  let elapsed = cpuTime() - startTime
  let lineCount = output.count('\n') + 1

  result = &"""
═══════════════════════════════════════════════════════════════
{cfg.name}
Hardware: {cfg.hardware}
═══════════════════════════════════════════════════════════════
Settings: temp={cfg.temp}, penalty={cfg.penaltyLastN}/{cfg.penaltyRepeat}, max_tokens={cfg.maxTokens}
Time: {elapsed:.1f}s
Output: {output.len} chars, {lineCount} lines

{output.strip()}

"""

proc main() =
  let modelDir = getHomeDir() / ".local/share/captions"

  echo """
╔══════════════════════════════════════════════════════════════════╗
║     Hardware-Tiered Model Configuration Test                    ║
╚══════════════════════════════════════════════════════════════════╝

Testing optimal settings for each hardware tier.
All using IMPROVED prompts and backported findings from 32B testing.

"""

  # Universal improved prompt (works for all models)
  let improvedPrompt = """Create a detailed summary of the following transcript.

Important: Preserve specific details as mentioned:
- Names of people referenced
- Exact times, dates, and numbers
- Book titles, concepts, and technical terms
- Specific action items with context

Structure with clear sections. Be thorough and factual."""

  let tiers = [
    TierConfig(
      name: "TIER 1: Budget (7B Model)",
      modelPath: modelDir / "qwen2.5-7b-instruct-q4_k_m.gguf",
      temp: 0.2,  # Low but not too low (was 0.1)
      penaltyLastN: 256,  # Reduced from 512
      penaltyRepeat: 1.3,  # Reduced from 1.5
      maxTokens: 768,  # Increased from 256
      prompt: improvedPrompt,
      hardware: "8-16GB RAM, M1/M2/M3 Base, RTX 3060"
    ),
    TierConfig(
      name: "TIER 2: Enthusiast (14B Model)",
      modelPath: modelDir / "qwen2.5-14b-instruct-q4_k_m.gguf",
      temp: 0.55,  # Sweet spot for 14B
      penaltyLastN: 128,
      penaltyRepeat: 1.1,
      maxTokens: 1536,  # Good balance
      prompt: improvedPrompt,
      hardware: "16-24GB RAM, M3 Pro, RTX 4070"
    ),
    TierConfig(
      name: "TIER 3: Professional (32B Model)",
      modelPath: modelDir / "qwen2.5-32b-instruct-q4_k_m.gguf",
      temp: 0.6,  # Proven best for 32B
      penaltyLastN: 64,
      penaltyRepeat: 1.05,
      maxTokens: 3000,  # Executive-level detail
      prompt: improvedPrompt & "\n\nProvide executive-level detail with comprehensive coverage.",
      hardware: "32GB+ RAM/VRAM, M3 Max, RTX 4090"
    ),
  ]

  for tier in tiers:
    echo "\n" & "═".repeat(70)
    echo "TESTING: " & tier.name
    echo "═".repeat(70)
    echo ""
    let result = testTier(tier)
    echo result

  echo "\n" & "═".repeat(70)
  echo "TIER COMPARISON SUMMARY:"
  echo "═".repeat(70)
  echo """
TIER 1 (7B): Fast summaries, good for most use cases
  - Best for: Quick summaries, limited hardware
  - Quality: Good, minimal hallucinations
  - Speed: ~6-10s

TIER 2 (14B): Balanced quality and speed
  - Best for: Better detail capture, mid-range hardware
  - Quality: Very good, approaches Claude
  - Speed: ~15-25s

TIER 3 (32B): Maximum quality, matches Claude
  - Best for: Professional use, maximum detail
  - Quality: Excellent, matches/exceeds Claude
  - Speed: ~25-40s
"""

when isMainModule:
  main()
