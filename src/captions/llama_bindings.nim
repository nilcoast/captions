## Hand-written llama.cpp C API bindings.
## Only the subset needed for text generation (summarization).

when defined(macosx):
  # macOS with Metal GPU support
  # Build llama.cpp with Metal support using:
  #   cmake -B build -DGGML_METAL=ON -DBUILD_SHARED_LIBS=ON
  #   cmake --build build --config Release
  #   sudo cmake --install build
  {.passl: "-framework Metal".}
  {.passl: "-framework MetalPerformanceShaders".}
  {.passl: "-framework Foundation".}
  {.passl: "-lllama".}
  # Try Homebrew ARM64 path first, fallback to Intel path
  when defined(arm64):
    {.passc: "-I/opt/homebrew/include".}
  else:
    {.passc: "-I/usr/local/include".}
else:
  # Linux and other platforms
  {.passl: "-lllama".}
  {.passc: "-I/usr/local/include".}

type
  LlamaModel* {.importc: "struct llama_model", header: "llama.h", incompleteStruct.} = object
  LlamaModelPtr* = ptr LlamaModel

  LlamaContext* {.importc: "struct llama_context", header: "llama.h", incompleteStruct.} = object
  LlamaContextPtr* = ptr LlamaContext

  LlamaVocab* {.importc: "struct llama_vocab", header: "llama.h", incompleteStruct.} = object
  LlamaVocabPtr* = ptr LlamaVocab

  LlamaSampler* {.importc: "struct llama_sampler", header: "llama.h", incompleteStruct.} = object
  LlamaSamplerPtr* = ptr LlamaSampler

  LlamaToken* = int32

  LlamaBatch* {.importc: "struct llama_batch", header: "llama.h".} = object
    n_tokens*: int32
    token*: ptr UncheckedArray[LlamaToken]
    embd*: ptr cfloat
    pos*: ptr UncheckedArray[int32]
    n_seq_id*: ptr UncheckedArray[int32]
    seq_id*: ptr UncheckedArray[ptr UncheckedArray[int32]]
    logits*: ptr UncheckedArray[int8]

  LlamaModelParams* {.importc: "struct llama_model_params", header: "llama.h".} = object
    devices*: pointer
    n_gpu_layers*: int32
    split_mode*: int32
    main_gpu*: int32
    tensor_split*: ptr cfloat
    progress_callback*: pointer
    progress_callback_user_data*: pointer
    kv_overrides*: pointer
    vocab_only*: bool
    use_mmap*: bool
    use_mlock*: bool
    check_tensors*: bool

  LlamaContextParams* {.importc: "struct llama_context_params", header: "llama.h".} = object
    n_ctx*: uint32
    n_batch*: uint32
    n_ubatch*: uint32
    n_seq_max*: uint32
    n_threads*: int32
    n_threads_batch*: int32
    rope_scaling_type*: int32
    pooling_type*: int32
    attention_type*: int32
    rope_freq_base*: cfloat
    rope_freq_scale*: cfloat
    yarn_ext_factor*: cfloat
    yarn_attn_factor*: cfloat
    yarn_beta_fast*: cfloat
    yarn_beta_slow*: cfloat
    yarn_orig_ctx*: uint32
    defrag_thold*: cfloat
    cb_eval*: pointer
    cb_eval_user_data*: pointer
    type_k*: int32
    type_v*: int32
    logits_all*: bool
    embeddings*: bool
    offload_kqv*: bool
    flash_attn*: bool
    no_perf*: bool

  LlamaSamplerChainParams* {.importc: "struct llama_sampler_chain_params", header: "llama.h".} = object
    no_perf*: bool

# --- Backend ---

proc llama_backend_init*() {.importc, header: "llama.h".}
proc llama_backend_free*() {.importc, header: "llama.h".}

# --- Model ---

proc llama_model_default_params*(): LlamaModelParams {.importc, header: "llama.h".}
proc llama_model_load_from_file*(path_model: cstring, params: LlamaModelParams): LlamaModelPtr {.importc: "llama_model_load_from_file", header: "llama.h".}
proc llama_model_free*(model: LlamaModelPtr) {.importc, header: "llama.h".}
proc llama_model_get_vocab*(model: LlamaModelPtr): LlamaVocabPtr {.importc, header: "llama.h".}
proc llama_model_n_ctx_train*(model: LlamaModelPtr): int32 {.importc, header: "llama.h".}

# --- Context ---

proc llama_context_default_params*(): LlamaContextParams {.importc, header: "llama.h".}
proc llama_context_new*(model: LlamaModelPtr, params: LlamaContextParams): LlamaContextPtr {.importc: "llama_init_from_model", header: "llama.h".}
proc llama_context_free*(ctx: LlamaContextPtr) {.importc: "llama_free", header: "llama.h".}

# --- Vocab / Tokens ---

proc llama_vocab_n_tokens*(vocab: LlamaVocabPtr): int32 {.importc, header: "llama.h".}
proc llama_vocab_bos*(vocab: LlamaVocabPtr): LlamaToken {.importc, header: "llama.h".}
proc llama_vocab_eos*(vocab: LlamaVocabPtr): LlamaToken {.importc, header: "llama.h".}

proc llama_tokenize*(vocab: LlamaVocabPtr, text: cstring, text_len: int32,
                     tokens: ptr LlamaToken, n_tokens_max: int32,
                     add_special: bool, parse_special: bool): int32 {.importc, header: "llama.h".}

proc llama_token_to_piece*(vocab: LlamaVocabPtr, token: LlamaToken,
                           buf: cstring, length: int32,
                           lstrip: int32, special: bool): int32 {.importc, header: "llama.h".}

# --- Batch ---

proc llama_batch_get_one*(tokens: ptr LlamaToken, n_tokens: int32): LlamaBatch {.importc, header: "llama.h".}

# --- Decode ---

proc llama_decode*(ctx: LlamaContextPtr, batch: LlamaBatch): int32 {.importc, header: "llama.h".}

# --- Sampler ---

proc llama_sampler_chain_default_params*(): LlamaSamplerChainParams {.importc, header: "llama.h".}
proc llama_sampler_chain_init*(params: LlamaSamplerChainParams): LlamaSamplerPtr {.importc, header: "llama.h".}
proc llama_sampler_chain_add*(chain: LlamaSamplerPtr, smpl: LlamaSamplerPtr) {.importc, header: "llama.h".}
proc llama_sampler_sample*(smpl: LlamaSamplerPtr, ctx: LlamaContextPtr, idx: int32): LlamaToken {.importc, header: "llama.h".}
proc llama_sampler_free*(smpl: LlamaSamplerPtr) {.importc, header: "llama.h".}

# --- Built-in samplers ---

proc llama_sampler_init_temp*(t: cfloat): LlamaSamplerPtr {.importc, header: "llama.h".}
proc llama_sampler_init_top_p*(p: cfloat, min_keep: csize_t): LlamaSamplerPtr {.importc, header: "llama.h".}
proc llama_sampler_init_min_p*(p: cfloat, min_keep: csize_t): LlamaSamplerPtr {.importc, header: "llama.h".}
proc llama_sampler_init_dist*(seed: uint32): LlamaSamplerPtr {.importc, header: "llama.h".}
proc llama_sampler_init_penalties*(penalty_last_n: int32, penalty_repeat: cfloat,
                                   penalty_freq: cfloat, penalty_present: cfloat): LlamaSamplerPtr {.importc, header: "llama.h".}

# --- Chat template ---

type
  LlamaChatMessage* {.importc: "struct llama_chat_message", header: "llama.h".} = object
    role*: cstring
    content*: cstring

proc llama_chat_apply_template*(tmpl: cstring, chat: ptr LlamaChatMessage,
                                 n_msg: csize_t, add_ass: bool,
                                 buf: cstring, length: int32): int32 {.importc, header: "llama.h".}

# --- Model metadata ---

proc llama_model_chat_template*(model: LlamaModelPtr, name: cstring): cstring {.importc, header: "llama.h".}

# --- KV cache ---

proc llama_kv_self_clear*(ctx: LlamaContextPtr) {.importc: "llama_kv_self_clear", header: "llama.h".}
