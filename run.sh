#!/bin/bash
set -e

# Validate model file exists
MODEL_PATH="/models/${MODEL_NAME}.gguf"
if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model file not found at $MODEL_PATH" >&2
    echo "Available models in /models/:" >&2
    ls -1 /models/ 2>/dev/null || echo "No models found"
    exit 1
fi

# Print startup configuration
echo "Starting llama.cpp server..."
echo "  Model:     $MODEL_NAME"
echo "  Model path: $MODEL_PATH"
echo "  Host:      $HOST"
echo "  Port:      $PORT"
echo "  Context:   $CTX_SIZE"
echo "  Flash Attn: $FLASH_ATTN"
echo "  Threads:   $THREADS"
echo ""

# Run the server
exec /app/llama-server \
    -m "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port 8080 \
    --ctx-size 16384 \
    --flash-attn on \
    --batch-size 1024 \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --no-mmap \
    --parallel 1 \
    --cache-ram 0 \
    --n-gpu-layers 999 \
    --threads 12