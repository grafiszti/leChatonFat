# Embedding server — llama.cpp in --embeddings mode
FROM ghcr.io/ggml-org/llama.cpp:server-cuda

COPY run.sh /app/run.sh
RUN chmod +x /app/run.sh

WORKDIR /app

EXPOSE 8084

ENTRYPOINT ["/app/run.sh"]
