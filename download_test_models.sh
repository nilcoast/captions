#!/bin/bash
# Download all three Qwen2.5 models for comparison testing

set -e

# Detect platform and set model directory
if [[ "$OSTYPE" == "darwin"* ]]; then
    MODEL_DIR="$HOME/Library/Application Support/captions"
else
    MODEL_DIR="$HOME/.local/share/captions"
fi

mkdir -p "$MODEL_DIR"
cd "$MODEL_DIR"

echo "═══════════════════════════════════════════════════════════════"
echo "  Downloading Qwen2.5 Models for Comparison Testing"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Model directory: $MODEL_DIR"
echo ""
echo "This will download approximately 32GB total:"
echo "  - Qwen2.5-7B-Instruct (Q4_K_M): ~4.4GB"
echo "  - Qwen2.5-14B-Instruct (Q4_K_M): ~8.3GB"
echo "  - Qwen2.5-32B-Instruct (Q4_K_M): ~18.9GB"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled."
    exit 0
fi

# Download 7B model
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Downloading Qwen2.5-7B-Instruct (~4.4GB)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "qwen2.5-7b-instruct-q4_k_m.gguf" ]; then
    echo "✓ Already exists, skipping"
else
    wget --progress=bar:force:noscroll \
        -O qwen2.5-7b-instruct-q4_k_m.gguf \
        https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf
    echo "✓ Downloaded qwen2.5-7b-instruct-q4_k_m.gguf"
fi

# Download 14B model
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "qwen2.5-14b-instruct-q4_k_m.gguf" ]; then
    echo "✓ Already exists, skipping"
else
    wget --progress=bar:force:noscroll \
        -O qwen2.5-14b-instruct-q4_k_m.gguf \
        https://huggingface.co/bartowski/Qwen2.5-14B-Instruct-GGUF/resolve/main/Qwen2.5-14B-Instruct-Q4_K_M.gguf
    echo "✓ Downloaded qwen2.5-14b-instruct-q4_k_m.gguf"
fi

# Download 32B model
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Downloading Qwen2.5-32B-Instruct (~18.9GB)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -f "qwen2.5-32b-instruct-q4_k_m.gguf" ]; then
    echo "✓ Already exists, skipping"
else
    wget --progress=bar:force:noscroll \
        -O qwen2.5-32b-instruct-q4_k_m.gguf \
        https://huggingface.co/bartowski/Qwen2.5-32B-Instruct-GGUF/resolve/main/Qwen2.5-32B-Instruct-Q4_K_M.gguf
    echo "✓ Downloaded qwen2.5-32b-instruct-q4_k_m.gguf"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "✅ All models downloaded successfully!"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Models are located in: $MODEL_DIR"
echo ""
echo "To run the comparison test:"
echo "  cd $(pwd)"
echo "  nim c -r test_models.nim"
echo ""
