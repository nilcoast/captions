## Final 32B tuning - testing 3 refined configs to match Claude quality
## Tweaks: temp variations + better prompts + more tokens

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

type TestConfig = object
  name: string
  temp: float32
  maxTokens: int
  prompt: string

proc testConfig(modelPath: string, cfg: TestConfig): string =
  llama_backend_init()
  defer: llama_backend_free()

  var modelParams = llama_model_default_params()
  modelParams.n_gpu_layers = -1

  let model = llama_model_load_from_file(modelPath.cstring, modelParams)
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
  llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, 1.05, 0.0, 0.0))
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
Config: {cfg.name}
  temp={cfg.temp}, max_tokens={cfg.maxTokens}
═══════════════════════════════════════════════════════════════
Time: {elapsed:.1f}s
Output: {output.len} chars, {lineCount} lines

{output.strip()}

"""

proc main() =
  let modelPath = getHomeDir() / ".local/share/captions/qwen2.5-32b-instruct-q4_k_m.gguf"

  echo """
╔══════════════════════════════════════════════════════════════════╗
║     32B Final Tuning: Finding Claude-Level Quality              ║
╚══════════════════════════════════════════════════════════════════╝

Testing 3 configurations to maximize detail capture.

"""

  let configs = [
    TestConfig(
      name: "Config A: Detailed + Focused (temp=0.65, 2048 tokens)",
      temp: 0.65,
      maxTokens: 2048,
      prompt: """Create a detailed, professional summary of the following transcript.

Important: Preserve specific details exactly as mentioned:
- All names of people referenced
- Exact times (e.g., if "6:30 AM" is mentioned, include "6:30 AM")
- Exact numbers (e.g., if "500 feeds" is mentioned, include "500")
- Specific days/dates (e.g., "Tuesday afternoon")
- Book titles, concepts, and technical terms

Structure with clear sections. Be thorough and precise."""
    ),
    TestConfig(
      name: "Config B: Natural + Comprehensive (temp=0.7, 2500 tokens)",
      temp: 0.7,
      maxTokens: 2500,
      prompt: """Summarize the following transcript comprehensively. Include:

1. All participant names mentioned
2. Specific times, dates, and numbers referenced
3. Book titles and concepts discussed
4. Detailed action items with context
5. Both personal/spiritual and work-related topics

Preserve details as mentioned in the transcript. Use professional markdown structure."""
    ),
    TestConfig(
      name: "Config C: Ultra-Detailed (temp=0.6, 3000 tokens)",
      temp: 0.6,
      maxTokens: 3000,
      prompt: """Create an executive-level summary preserving all important details from the transcript.

Capture:
- Participant names
- Specific numbers, times, dates mentioned
- Books, concepts, theories referenced
- Complete action items with owners and contexts
- Separate sections for different topic areas

Be comprehensive without speculation. Quality over brevity."""
    ),
  ]

  for cfg in configs:
    echo "\n" & "═".repeat(70)
    echo "TESTING: " & cfg.name
    echo "═".repeat(70)
    echo ""
    let result = testConfig(modelPath, cfg)
    echo result

  echo "\n" & "═".repeat(70)
  echo "COMPARE TO CLAUDE:"
  echo "═".repeat(70)
  echo "Claude: 2243 chars, captures Jeremy, 500 RSS, 6:30-7AM, Tuesday, Black Elk, Conway's Law"
  echo "Which config came closest?"
  echo ""

when isMainModule:
  main()
