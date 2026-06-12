#!/bin/bash
set -e

# Environment variables are loaded from .env
# Load .env file
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Validate model file exists
MODEL_PATH="/models/${MODEL_NAME}.gguf"
if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Model file not found at $MODEL_PATH" >&2
    echo "Available models in /models/:" >&2
    ls -1 /models/ 2>/dev/null || echo "No models found"
    exit 1
fi

JINJA_TEMPLATE_PATH="/app/${JINJA_TEMPLATE_FILE}"

# Print startup configuration
echo "Starting llama.cpp server..."
echo "  Model:     ${MODEL_NAME}"
echo "  Model path: ${MODEL_PATH}"
echo "  Host:      ${HOST}"
echo "  Port:      ${PORT}"
echo "  Context:   ${CTX_SIZE}"
echo "  Flash Attn: ${FLASH_ATTN}"
echo "  Threads:   ${THREADS}"
echo ""

# Run the server
exec /app/llama-server \
    -m "${MODEL_PATH}" \
    --host "${HOST}" \
    --port "${PORT}" \
    --ctx-size "${CTX_SIZE}" \
    --flash-attn "${FLASH_ATTN}" \
    --batch-size "${BATCH_SIZE}" \
    --cache-type-k "${CACHE_TYPE_K}" \
    --cache-type-v "${CACHE_TYPE_V}" \
    --parallel "${PARALLEL}" \
    --jinja \
    --cache-ram "${CACHE_RAM}" \
    --n-gpu-layers "${N_GPU_LAYERS}" \
    --threads "${THREADS}" \
    --chat-template-file "${JINJA_TEMPLATE_PATH}"