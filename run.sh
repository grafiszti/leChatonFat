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

# Build server command from env vars
SERVER_CMD=(
    /app/llama-server
    -m "${MODEL_PATH}"
    --host "${HOST}"
    --port "${PORT_INTERNAL}"
    --ctx-size "${CTX_SIZE}"
    --flash-attn "${FLASH_ATTN}"
    --batch-size "${BATCH_SIZE}"
    --cache-type-k "${CACHE_TYPE_K}"
    --cache-type-v "${CACHE_TYPE_V}"
    --parallel "${PARALLEL}"
    --jinja
    --cache-ram "${CACHE_RAM}"
    --threads "${THREADS}"
)

# Speculative decoding / fit
if [[ "${FIT}" == "on" ]]; then
    SERVER_CMD+=(--fit "${FIT}")
    SERVER_CMD+=(--fit-target "${FIT_TARGET}")
    SERVER_CMD+=(--fit-ctx "${FIT_CTX}")
fi

if [[ -n "${UBATCH_SIZE}" ]]; then
    SERVER_CMD+=(--ubatch-size "${UBATCH_SIZE}")
fi

if [[ -n "${CTX_CHECKPOINTS}" ]]; then
    SERVER_CMD+=(--ctx-checkpoints "${CTX_CHECKPOINTS}")
fi

if [[ -n "${POLL_BATCH}" ]]; then
    SERVER_CMD+=(--poll-batch "${POLL_BATCH}")
fi

# Speculative decoding (draft model)
if [[ -n "${SPEC_TYPE}" ]]; then
    SERVER_CMD+=(--spec-type "${SPEC_TYPE}")
fi
if [[ -n "${SPEC_DRAFT_P_MIN}" ]]; then
    SERVER_CMD+=(--spec-draft-p-min "${SPEC_DRAFT_P_MIN}")
fi
if [[ -n "${SPEC_DRAFT_N_MAX}" ]]; then
    SERVER_CMD+=(--spec-draft-n-max "${SPEC_DRAFT_N_MAX}")
fi

# Sampling parameters
if [[ -n "${TEMP}" ]]; then
    SERVER_CMD+=(--temp "${TEMP}")
fi
if [[ -n "${TOP_P}" ]]; then
    SERVER_CMD+=(--top-p "${TOP_P}")
fi
if [[ -n "${TOP_K}" ]]; then
    SERVER_CMD+=(--top-k "${TOP_K}")
fi
if [[ -n "${MIN_P}" ]]; then
    SERVER_CMD+=(--min-p "${MIN_P}")
fi

# Penalties
if [[ -n "${PRESENCE_PENALTY}" ]]; then
    SERVER_CMD+=(--presence-penalty "${PRESENCE_PENALTY}")
fi
if [[ -n "${REPEAT_PENALTY}" ]]; then
    SERVER_CMD+=(--repeat-penalty "${REPEAT_PENALTY}")
fi

# Features
if [[ "${REASONING}" == "on" ]]; then
    SERVER_CMD+=(--reasoning on)
fi

# Print startup configuration
echo "Starting llama.cpp server..."
echo "  Model:      ${MODEL_NAME}"
echo "  Model path: ${MODEL_PATH}"
echo "  Host:       ${HOST}"
echo "  Port (internal):  ${PORT_INTERNAL}"
echo "  Port (external):  ${PORT_EXTERNAL}"
echo "  Context:    ${CTX_SIZE}"
echo "  Flash Attn: ${FLASH_ATTN}"
echo "  Threads:    ${THREADS}"
echo "  Fit:        ${FIT:-off}"
if [[ "${FIT}" == "on" ]]; then
    echo "  Fit Target: ${FIT_TARGET}"
    echo "  Fit Ctx:    ${FIT_CTX}"
fi
echo "  Sampling:   temp=${TEMP:-1.0} top_p=${TOP_P:-1.0} top_k=${TOP_K:-0} min_p=${MIN_P:-0.0}"
echo "  Penalties:  presence=${PRESENCE_PENALTY:-0.0} repeat=${REPEAT_PENALTY:-1.0}"
echo ""

# Run the server
exec "${SERVER_CMD[@]}"