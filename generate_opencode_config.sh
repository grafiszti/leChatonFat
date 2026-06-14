#!/bin/bash
# Generate opencode.json from opencode.json.template using variables in .env

set -euo pipefail

# ---------------------------------------------------------------------------
# Helper: extract an unquoted, unspaced value from .env
#   • skips comment lines (leading #)
#   • returns the LAST matching uncommented line
#   • strips surrounding double-quotes / single-quotes
#   • trims leading/trailing whitespace
# ---------------------------------------------------------------------------
env_var() {
    local key="$1"
    local val

    # grep only uncommented lines, take the last match, cut value after =
    val=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" ".env" \
        | tail -n 1 \
        | sed 's/^[^=]*=[[:space:]]*//' \
        | sed 's/[[:space:]]*$//')

    # strip surrounding quotes (both single and double)
    val="${val#\"}"
    val="${val%\"}"
    val="${val#\'}"
    val="${val%\'}"

    echo "$val"
}

# ---------------------------------------------------------------------------
# Validate .env exists
# ---------------------------------------------------------------------------
if [ ! -f .env ]; then
    echo "Error: .env file not found" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Validate template exists
# ---------------------------------------------------------------------------
if [ ! -f templates/opencode.json.template ]; then
    echo "Error: templates/opencode.json.template not found" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Extract and validate required variables
# ---------------------------------------------------------------------------
MODEL_NAME=$(env_var "MODEL_NAME")
MODEL_NAME_ALIAS=$(env_var "MODEL_NAME_ALIAS")

if [ -z "$MODEL_NAME" ]; then
    echo "Error: MODEL_NAME not set in .env" >&2
    exit 1
fi

if [ -z "$MODEL_NAME_ALIAS" ]; then
    echo "Error: MODEL_NAME_ALIAS not set in .env" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Generate opencode.json
# ---------------------------------------------------------------------------
sed -e "s/{{MODEL_NAME}}/${MODEL_NAME}/g" \
    -e "s/{{MODEL_NAME_ALIAS}}/${MODEL_NAME_ALIAS}/g" \
    templates/opencode.json.template > opencode.json

echo "Successfully generated opencode.json with:"
echo "  MODEL_NAME:       $MODEL_NAME"
echo "  MODEL_NAME_ALIAS: $MODEL_NAME_ALIAS"
