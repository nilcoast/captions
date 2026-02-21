## Test Qwen2.5-32B with improved prompt, more tokens, and temp=0.6
## Tweaks: Better prompt + 2048 tokens + temp 0.6

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

proc main() =
  let modelPath = getHomeDir() / ".local/share/captions/qwen2.5-32b-instruct-q4_k_m.gguf"

  echo """
╔══════════════════════════════════════════════════════════════════╗
║     Qwen2.5-32B with IMPROVED Settings                          ║
╚══════════════════════════════════════════════════════════════════╝

Tweaks:
  1. More explicit prompt (ask for names, times, numbers)
  2. Increased tokens: 1024 → 2048
  3. Slightly lower temp: 0.7 → 0.6

"""

  llama_backend_init()
  defer: llama_backend_free()

  var modelParams = llama_model_default_params()
  modelParams.n_gpu_layers = -1

  let model = llama_model_load_from_file(modelPath.cstring, modelParams)
  if model == nil:
    echo "❌ Failed to load model"
    quit(1)
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
    echo "❌ Failed to create context"
    quit(1)
  defer: llama_context_free(ctx)

  # IMPROVED PROMPT - more explicit about details (but not overfitted)
  let systemPrompt = """You are a precise summarization assistant. Create a detailed summary of the following transcript.

Pay special attention to:
- Specific names of people mentioned
- Exact times, dates, and numbers
- Book titles, proper nouns, and technical concepts referenced
- Concrete action items with context and specifics

Structure your summary with clear sections and preserve important details. Be thorough and factual - do not add speculation or information not present in the transcript."""

  let prompt = buildChatPrompt(model, systemPrompt, testTranscript)

  var tokens = tokenize(vocab, prompt, false, true)
  let maxPromptTokens = ctxParams.n_ctx.int - 2048 - 16  # Room for 2048 token output
  if tokens.len > maxPromptTokens:
    tokens.setLen(maxPromptTokens)

  # Optimized sampler: temp=0.6, minimal penalties
  var samplerParams = llama_sampler_chain_default_params()
  let sampler = llama_sampler_chain_init(samplerParams)
  llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, 1.05, 0.0, 0.0))
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.6))
  llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.05, 1))
  llama_sampler_chain_add(sampler, llama_sampler_init_dist(0))
  defer: llama_sampler_free(sampler)

  echo "Generating with improved settings..."
  echo "  temp: 0.6"
  echo "  max_tokens: 2048"
  echo "  prompt: Explicit detail preservation"
  echo ""

  # Decode prompt
  let nBatch = ctxParams.n_batch.int
  var pos = 0
  while pos < tokens.len:
    let chunkLen = min(nBatch, tokens.len - pos)
    var batch = llama_batch_get_one(addr tokens[pos], chunkLen.int32)
    if llama_decode(ctx, batch) != 0:
      echo "❌ Decode failed"
      quit(1)
    pos += chunkLen

  # Generate up to 2048 tokens
  let eosToken = llama_vocab_eos(vocab)
  var output = ""
  let startTime = cpuTime()

  for i in 0 ..< 2048:
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

  echo "═".repeat(70)
  echo "✅ GENERATION COMPLETE"
  echo "═".repeat(70)
  echo &"Time: {elapsed:.1f}s"
  let lineCount = output.count('\n') + 1
  echo &"Output: {output.len} chars, {lineCount} lines"
  echo ""
  echo "═".repeat(70)
  echo "32B IMPROVED SUMMARY:"
  echo "═".repeat(70)
  echo output.strip()
  echo ""
  echo "═".repeat(70)
  echo "COMPARISON TO CLAUDE (2243 chars, 50 lines):"
  echo "═".repeat(70)
  echo ""
  echo "Check if 32B now captures:"
  echo "  • Jeremy (name) ✓"
  echo "  • 500 RSS feeds (number) ✓"
  echo "  • 6:30-7 AM (exact time) ?"
  echo "  • Tuesday afternoon (specific day) ?"
  echo "  • Black Elk Speaks (book title) ✓"
  echo "  • Conway's Law (concept) ?"
  echo "  • Mycelium network metaphor ?"
  echo "  • 2FA/authenticator app details ?"
  echo ""

when isMainModule:
  main()
