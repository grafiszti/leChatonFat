#!/bin/bash
set -e

# Source environment variables
if [ -f "/.env" ]; then
    export $(cat /.env | grep -v "^#" | xargs)
fi

# Validate required environment variables
if [ -z "$MODEL_NAME" ]; then
    echo "Error: MODEL_NAME is not set" >&2
    exit 1
fi

if [ -z "$HOST" ]; then
    HOST="0.0.0.0"
fi

if [ -z "$PORT" ]; then
    PORT="8080"
fi

if [ -z "$CTX_SIZE" ]; then
    CTX_SIZE="4096"
fi

if [ -z "$FLASH_ATTN" ]; then
    FLASH_ATTN="on"
fi

if [ -z "$THREADS" ]; then
    THREADS="12"
fi

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
    --host "$HOST" \
    --port "$PORT" \
    --ctx-size "$CTX_SIZE" \
    --flash-attn "$FLASH_ATTN" \
    --threads "$THREADS"