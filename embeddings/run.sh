#!/bin/bash
set -e

# Load .env file
if [ -f .env ]; then
    set -a
    . .env
    set +a
fi

# Validate model file exists
MODEL_PATH="/models/${EMBEDDING_MODEL}.gguf"
if [ ! -f "$MODEL_PATH" ]; then
    echo "Error: Embedding model not found at $MODEL_PATH" >&2
    echo "Available models in /models/:" >&2
    ls -1 /models/ 2>/dev/null || echo "No models found"
    exit 1
fi

# Build server command — embeddings mode
SERVER_CMD=(
    /app/llama-server
    -m "${MODEL_PATH}"
    --host 0.0.0.0
    --port 8084
    --embeddings
    --ctx-size "${EMBEDDING_CTX:-8192}"
    --threads "${EMBEDDING_THREADS:-4}"
    --batch-size "${EMBEDDING_BATCH_SIZE:-8192}"
    --ubatch-size "${EMBEDDING_UBATCH_SIZE:-8192}"
)

echo "Starting llama.cpp embedding server..."
echo "  Model:       ${EMBEDDING_MODEL}"
echo "  Model path:  ${MODEL_PATH}"
echo "  Port:        8084"
echo "  Context:     ${EMBEDDING_CTX:-8192}"
echo "  Threads:     ${EMBEDDING_THREADS:-4}"
echo "  Embed dim:   ${EMBEDDING_DIM:-1024}"
echo ""

exec "${SERVER_CMD[@]}"
