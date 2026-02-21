# Model Comparison Test Harness

This test harness compares the quality of three Qwen2.5 models for transcript summarization.

## Models Tested

1. **Qwen2.5-7B-Instruct** (Q4_K_M) - ~4.4GB
   - Fast, good quality
   - ~15-25 tokens/sec on M3

2. **Qwen2.5-14B-Instruct** (Q4_K_M) - ~8.3GB
   - Excellent quality, balanced speed
   - ~10-15 tokens/sec on M3 Pro/Max

3. **Qwen2.5-32B-Instruct** (Q4_K_M) - ~18.9GB
   - Best quality, slower
   - ~5-8 tokens/sec on M3 Max

## Quick Start

### 1. Download Models (~32GB total)

```bash
./download_test_models.sh
```

This will download all three models to your model directory:
- **macOS**: `~/Library/Application Support/captions/`
- **Linux**: `~/.local/share/captions/`

### 2. Run Comparison Test

```bash
nim c --threads:on --mm:orc -r test_models.nim
```

Or add to Makefile:

```bash
make test-models
```

## Test Transcript

The test uses a realistic meeting transcript with:
- ✓ Specific numbers ($50,000, 3.2x ROI)
- ✓ Names (Sarah, John)
- ✓ Dates (Q3, Q4, Tuesday 2pm, December 15th)
- ✓ Action items (reconvene, review metrics)
- ✓ Decisions (approve 30k now, defer 20k)

This tests the model's ability to:
1. **Avoid hallucinations** - No making up information
2. **Preserve details** - Keep numbers/dates accurate
3. **Extract action items** - Identify decisions and next steps
4. **Be concise** - No unnecessary elaboration

## Evaluation Criteria

When comparing outputs, look for:

1. ✅ **Factual Accuracy** - All points in the summary appear in the transcript
2. ✅ **Completeness** - Key information not omitted
3. ✅ **No Hallucinations** - No invented details
4. ✅ **Preserved Details** - Numbers, dates, names correct
5. ✅ **Action Items** - Next steps clearly identified
6. ✅ **Conciseness** - No fluff or repetition

## Example Output Format

```
═══════════════════════════════════════════════════════════════
Testing: Qwen2.5-7B-Instruct (Q4_K_M)
═══════════════════════════════════════════════════════════════

📊 Model: Qwen2.5-7B-Instruct (Q4_K_M)
⏱️  Time: 12.3s
📝 Output (234 chars):

The team discussed Q4 budget planning. Marketing requested $50,000
for a new campaign (previous ROI: 3.2x). Finance suggested waiting
for Q3 results. Compromise: approve $30k now, defer $20k pending
Q3 performance. Next meeting: Tuesday 2pm. Budget deadline: Dec 15.
```

## Interpreting Results

### Speed Expectations (M3 Pro/Max)
- **7B**: 10-20 seconds
- **14B**: 20-40 seconds
- **32B**: 40-90 seconds

### Quality Expectations
- **7B**: Good baseline, occasional minor omissions
- **14B**: Excellent balance of quality and speed
- **32B**: Near-perfect, minimal hallucinations

## Choosing Your Model

**For M3 Base (8GB RAM)**:
- Use 7B only

**For M3 Pro (18GB RAM)**:
- Use 7B for speed (real-time feel)
- Use 14B for quality (recommended)

**For M3 Max (36GB+ RAM)**:
- Use 14B for daily use (best balance)
- Use 32B for important transcripts (maximum quality)

## Custom Transcripts

To test with your own transcripts, edit `test_models.nim`:

```nim
const testTranscript = """
Your custom transcript here...
"""
```

Or modify the script to read from a file:

```nim
let testTranscript = readFile("my_transcript.txt")
```

## Integration with Main App

After choosing your preferred model, update `~/.config/captions/captions.toml`:

```toml
[summary]
model_path = "~/Library/Application Support/captions/qwen2.5-14b-instruct-q4_k_m.gguf"
gpu_layers = -1
max_tokens = 256
```

Or for macOS, the default config will automatically use the correct path.

## Troubleshooting

**Model not found errors:**
- Make sure models are in the correct directory
- Check file names match exactly (lowercase, dashes, underscores)

**Out of memory:**
- Close other applications
- Try a smaller model
- Reduce `gpu_layers` in the config

**Slow generation:**
- Ensure Metal/Vulkan GPU acceleration is working
- Check `gpu_layers = -1` to offload all layers
- Verify llama.cpp was built with Metal (macOS) or Vulkan (Linux)

**Generation hangs:**
- Increase timeout in the test script
- Check GPU memory availability
- Try reducing `max_tokens`
