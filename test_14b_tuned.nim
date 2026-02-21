## Test different sampler settings for Qwen2.5-14B to fix repetition issue
## Usage: nim c -r test_14b_tuned.nim

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

type SamplerConfig = object
  temp: float32
  penaltyLastN: int32
  penaltyRepeat: float32
  penaltyFreq: float32
  penaltyPresent: float32
  name: string

proc testWithSamplers(modelPath: string, samplerCfg: SamplerConfig): string =
  if not fileExists(modelPath):
    return "❌ Model not found"

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

  let prompt = buildChatPrompt(model,
    "You are a precise summarization assistant. Summarize ONLY the information present in the following transcript. Do not add speculation or external information. Focus on:\n- Key topics discussed\n- Important points mentioned\n- Action items or decisions (if any)\nBe factual and concise.",
    testTranscript)

  var tokens = tokenize(vocab, prompt, false, true)
  let maxPromptTokens = ctxParams.n_ctx.int - 512 - 16
  if tokens.len > maxPromptTokens:
    tokens.setLen(maxPromptTokens)

  # Test with custom sampler settings
  var samplerParams = llama_sampler_chain_default_params()
  let sampler = llama_sampler_chain_init(samplerParams)
  llama_sampler_chain_add(sampler, llama_sampler_init_penalties(
    samplerCfg.penaltyLastN,
    samplerCfg.penaltyRepeat,
    samplerCfg.penaltyFreq,
    samplerCfg.penaltyPresent))
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(samplerCfg.temp))
  llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.1, 1))
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

  for i in 0 ..< 512:
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
  result = &"""
Config: {samplerCfg.name}
  temp={samplerCfg.temp}, penalty_last_n={samplerCfg.penaltyLastN}
  penalty_repeat={samplerCfg.penaltyRepeat}, freq={samplerCfg.penaltyFreq}, present={samplerCfg.penaltyPresent}
Time: {elapsed:.1f}s
Output ({output.len} chars):

{output.strip()}
"""

proc main() =
  let modelPath = getHomeDir() / ".local/share/captions/qwen2.5-14b-instruct-q4_k_m.gguf"

  echo """
╔══════════════════════════════════════════════════════════════════╗
║     Qwen2.5-14B Sampler Tuning Test                             ║
╚══════════════════════════════════════════════════════════════════╝

Testing different sampler configurations to fix repetition issue.
Transcript: 38KB Sufism conversation

"""

  # Test different configurations
  let configs = [
    SamplerConfig(
      name: "Current (Broken)",
      temp: 0.1,
      penaltyLastN: 512,
      penaltyRepeat: 1.5,
      penaltyFreq: 0.3,
      penaltyPresent: 0.3
    ),
    SamplerConfig(
      name: "Moderate",
      temp: 0.3,
      penaltyLastN: 256,
      penaltyRepeat: 1.1,
      penaltyFreq: 0.0,
      penaltyPresent: 0.0
    ),
    SamplerConfig(
      name: "Higher Temp",
      temp: 0.5,
      penaltyLastN: 256,
      penaltyRepeat: 1.2,
      penaltyFreq: 0.1,
      penaltyPresent: 0.1
    ),
    SamplerConfig(
      name: "Balanced",
      temp: 0.4,
      penaltyLastN: 384,
      penaltyRepeat: 1.15,
      penaltyFreq: 0.05,
      penaltyPresent: 0.05
    ),
  ]

  for cfg in configs:
    echo "\n" & "═".repeat(70)
    echo "Testing: " & cfg.name
    echo "═".repeat(70)
    let result = testWithSamplers(modelPath, cfg)
    echo result

  echo "\n" & "═".repeat(70)
  echo "Compare to Claude's summary (2243 chars, 50 lines)"
  echo "═".repeat(70)

when isMainModule:
  main()
