# LLM Server Container
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

# Copy and setup run.sh for validation and startup
COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

COPY templates/qwen_chat_template.jinja /app/qwen_chat_template.jinja

# Set working directory so run.sh's model path validation works correctly
WORKDIR /app

# Expose the server port
EXPOSE 8080

# Validate model and start the server on boot
ENTRYPOINT ["/app/run.sh"]
