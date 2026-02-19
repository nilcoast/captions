## AI summary generation via embedded llama.cpp.
## Loads a GGUF model and generates a summary of the transcript.
## Runs in a background thread to avoid blocking the GLib main loop.

import std/[os, strutils, strformat, logging, osproc]
import ./config
import ./llama_bindings

proc tokenize(vocab: LlamaVocabPtr, text: string, addSpecial: bool,
              parseSpecial: bool = false): seq[LlamaToken] =
  ## Tokenize text, returning a sequence of tokens.
  let maxTokens = text.len + 64  # generous estimate
  result = newSeq[LlamaToken](maxTokens)
  let n = llama_tokenize(vocab, text.cstring, text.len.int32,
                         addr result[0], maxTokens.int32,
                         addSpecial, parseSpecial)
  if n < 0:
    # Buffer too small — retry with exact size
    result.setLen(-n)
    let n2 = llama_tokenize(vocab, text.cstring, text.len.int32,
                            addr result[0], (-n).int32,
                            addSpecial, parseSpecial)
    result.setLen(n2)
  else:
    result.setLen(n)

proc tokenToStr(vocab: LlamaVocabPtr, token: LlamaToken): string =
  ## Convert a single token to its string representation.
  var buf: array[128, char]
  let n = llama_token_to_piece(vocab, token, cast[cstring](addr buf[0]),
                                buf.len.int32, 0, false)
  if n > 0:
    result = newString(n)
    copyMem(addr result[0], addr buf[0], n)
  else:
    result = ""

proc buildChatPrompt(model: LlamaModelPtr, systemPrompt: string, transcript: string): string =
  ## Apply the model's own chat template from GGUF metadata.
  var messages = [
    LlamaChatMessage(role: "system", content: systemPrompt.cstring),
    LlamaChatMessage(role: "user", content: transcript.cstring),
  ]

  # Get the template from the model metadata
  let tmpl = llama_model_chat_template(model, nil)

  # First call to get required buffer size
  let needed = llama_chat_apply_template(tmpl, addr messages[0],
                                          messages.len.csize_t, true, nil, 0)
  if needed <= 0:
    # Fallback to simple format if template not available
    return systemPrompt & "\n\n" & transcript & "\n\nSummary:"

  var buf = newString(needed + 1)
  discard llama_chat_apply_template(tmpl, addr messages[0],
                                     messages.len.csize_t, true,
                                     buf.cstring, (needed + 1).int32)
  buf.setLen(needed)
  result = buf

proc generateSummary*(cfg: SummaryConfig, transcript: string): string =
  ## Generate a summary of the transcript using an embedded GGUF model.
  ## Returns the generated summary text, or empty string on failure.
  if not fileExists(cfg.modelPath):
    error "Summary model not found: " & cfg.modelPath
    return ""

  llama_backend_init()
  defer: llama_backend_free()

  # Load model
  var modelParams = llama_model_default_params()
  modelParams.n_gpu_layers = cfg.gpuLayers.int32

  let model = llama_model_load_from_file(cfg.modelPath.cstring, modelParams)
  if model == nil:
    error "Failed to load summary model: " & cfg.modelPath
    return ""
  defer: llama_model_free(model)

  let vocab = llama_model_get_vocab(model)

  # Create context — cap at 16K to avoid huge KV cache allocation,
  # but never exceed the model's training context.
  let nCtxTrain = llama_model_n_ctx_train(model)
  let nCtx = min(16384'u32, nCtxTrain.uint32)
  var ctxParams = llama_context_default_params()
  ctxParams.n_ctx = nCtx
  ctxParams.n_batch = min(2048'u32, nCtx)
  ctxParams.n_threads = 4
  ctxParams.n_threads_batch = 4

  info &"Model context: {nCtxTrain} (using {nCtx})"

  let ctx = llama_context_new(model, ctxParams)
  if ctx == nil:
    error "Failed to create llama context"
    return ""
  defer: llama_context_free(ctx)

  # Build prompt using the model's own chat template
  let prompt = buildChatPrompt(model, cfg.prompt, transcript)

  # Tokenize with parse_special=true so chat template tokens are recognized
  var tokens = tokenize(vocab, prompt, false, true)
  if tokens.len == 0:
    error "Failed to tokenize prompt"
    return ""

  info &"Summary prompt: {tokens.len} tokens"

  # Truncate if too long for context (leave room for generation)
  let maxPromptTokens = ctxParams.n_ctx.int - cfg.maxTokens - 16
  if tokens.len > maxPromptTokens:
    warn &"Prompt too long ({tokens.len} tokens), truncating to {maxPromptTokens}"
    tokens.setLen(maxPromptTokens)

  # Set up sampler chain: penalties before temperature/sampling
  var samplerParams = llama_sampler_chain_default_params()
  let sampler = llama_sampler_chain_init(samplerParams)
  llama_sampler_chain_add(sampler, llama_sampler_init_penalties(512, 1.5, 0.3, 0.3))
  llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.1))
  llama_sampler_chain_add(sampler, llama_sampler_init_min_p(0.1, 1))
  llama_sampler_chain_add(sampler, llama_sampler_init_dist(0))
  defer: llama_sampler_free(sampler)

  # Decode prompt in n_batch-sized chunks
  let nBatch = ctxParams.n_batch.int
  var pos = 0
  while pos < tokens.len:
    let chunkLen = min(nBatch, tokens.len - pos)
    var batch = llama_batch_get_one(addr tokens[pos], chunkLen.int32)
    if llama_decode(ctx, batch) != 0:
      error "Failed to decode prompt at position " & $pos
      return ""
    pos += chunkLen

  # Generate tokens — stop on EOS or any end-of-generation token
  let eosToken = llama_vocab_eos(vocab)
  var output = ""

  for i in 0 ..< cfg.maxTokens:
    let newToken = llama_sampler_sample(sampler, ctx, -1)

    if newToken == eosToken:
      break

    let piece = tokenToStr(vocab, newToken)

    # Stop on common end-of-turn markers
    let combined = output & piece
    if "<|im_end|>" in combined or "<|end|>" in combined or "<|eot_id|>" in combined:
      break

    output.add(piece)

    # Decode the new token for next iteration
    var tokenArr = [newToken]
    var nextBatch = llama_batch_get_one(addr tokenArr[0], 1)
    if llama_decode(ctx, nextBatch) != 0:
      warn "Decode failed during generation at token " & $i
      break

  result = output.strip()

type
  SummaryArgs = tuple[cfg: SummaryConfig, transcript: string, sessionDir: string]

var summaryThread: Thread[SummaryArgs]

proc summaryThreadProc(args: SummaryArgs) {.thread.} =
  let cfg = args.cfg
  let transcript = args.transcript
  let sessionDir = args.sessionDir

  info "Generating summary..."
  let summary = generateSummary(cfg, transcript)

  if summary.len == 0:
    warn "Summary generation produced no output"
    return

  createDir(sessionDir)
  let outputPath = sessionDir / "summary.txt"
  writeFile(outputPath, summary)
  info &"Summary saved: {outputPath}"

  # Open in default app
  when defined(macosx):
    let p = startProcess("open", args = [outputPath], options = {poUsePath, poDaemon})
  else:
    let p = startProcess("xdg-open", args = [outputPath], options = {poUsePath, poDaemon})
  p.close()

proc spawnSummary*(cfg: SummaryConfig, transcript: string, sessionDir: string) {.gcsafe.} =
  ## Fire-and-forget: spawns summary generation in a background thread.
  if not cfg.enabled:
    return

  if transcript.strip().len == 0:
    info "Empty transcript, skipping summary"
    return

  if cfg.modelPath == "":
    warn "No summary model path configured, skipping summary"
    return

  {.cast(gcsafe).}:
    createThread(summaryThread, summaryThreadProc, (cfg, transcript, sessionDir))
