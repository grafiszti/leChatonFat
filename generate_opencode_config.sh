#!/bin/bash
# Generate opencode.json from opencode.json.template using variables in .env

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    exit 1
fi

# Extract MODEL_NAME and MODEL_NAME_ALIAS from .env
MODEL_NAME=$(grep "^MODEL_NAME" .env | cut -d'=' -f2)
MODEL_NAME_ALIAS=$(grep "^MODEL_NAME_ALIAS" .env | cut -d'=' -f2)

if [ -z "$MODEL_NAME" ] || [ -z "$MODEL_NAME_ALIAS" ]; then
    echo "Error: MODEL_NAME or MODEL_NAME_ALIAS not found in .env"
    exit 1
fi

# Replace the placeholders in the template
sed "s/{{MODEL_NAME}}/$MODEL_NAME/g" \
    "s/{{MODEL_NAME_ALIAS}}/$MODEL_NAME_ALIAS/g" \
    opencode.json.template > opencode.json

echo "Successfully generated opencode.json with MODEL_NAME: $MODEL_NAME and MODEL_NAME_ALIAS: $MODEL_NAME_ALIAS"
