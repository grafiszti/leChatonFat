# LeChatonFat - LLM Development Environment

![img](img.png)

A Docker-based setup for running llama.cpp server with GPU acceleration, SearXNG web search, and MCP tool servers — optimized for use as a local LLM provider for the Opencode coding assistant.

## Features
- **GPU Acceleration**: Configured for NVIDIA GPUs with optimized settings
- **Docker Compose**: Easy setup and management with auto-detection (GPU/CPU)
- **Speculative Decoding**: Fit-based speculative decoding with configurable batch sizes
- **Configurable Inference**: Sampling parameters, penalties, reasoning mode, and more via `.env`
- **Jinja Chat Template**: Bundled chat template for improved model formatting
- **Auto-generated Config**: Generate `opencode.json` from `.env` via script
- **SearXNG Integration**: Self-hosted privacy-focused web search service
- **RAG Knowledge Base**: Semantic search over ingested documents (URLs, PDF, DOCX, TXT/MD) via Qdrant vector DB + llama.cpp embeddings, with a web UI and MCP tools
- **MCP Servers**: Browser automation, SearXNG, and RAG MCP tools for Opencode
- **Simple Management**: Makefile commands for common tasks

## Prerequisites
- Docker and Docker Compose installed
- NVIDIA GPU with drivers installed (optional, falls back to CPU)
- NVIDIA Container Toolkit (for GPU support)

## Quick Start

```bash
# Copy environment template
make copy_env

# Build and start the container (auto-detects GPU/CPU)
make up

# Validate the server is running
make validate
```

## Configuration

### Model
Use `make copy_env` to create `.env` file with all settings to configure:

| Variable           | Default                           | Description                                     |
|--------------------|-----------------------------------|-------------------------------------------------|
| `MODEL_NAME`       | `Qwen3.6-35B-A3B-UD-Q4_K_XL`      | GGUF model filename (without `.gguf` extension) |
| `MODEL_NAME_ALIAS` | `qwen3.6-35b`                     | Alias for the model (used in opencode.json)     |
| `HF_REPO`          | `unsloth/Qwen3.6-35B-A3B-UD-GGUF` | Hugging Face repository for model download      |
| `CTX_SIZE`         | `98304`                           | Context window size in tokens                   |
| `FLASH_ATTN`       | `on`                              | Enable flash attention                          |
| `THREADS`          | `5`                               | CPU threads for inference                       |
| `BATCH_SIZE`       | `256`                             | Prompt processing batch size                    |
| `CACHE_TYPE_K`     | `q4_0`                            | KV cache type for K tensor                      |
| `CACHE_TYPE_V`     | `q4_0`                            | KV cache type for V tensor                      |
| `NO_MMAP`          | `false`                           | Disable memory-mapped model loading             |
| `PARALLEL`         | `1`                               | Context parallelism                             |
| `CACHE_RAM`        | `4096`                            | KV cache memory budget in MiB                   |

### Speculative Decoding (Fit)
| Variable      | Default | Description                           |
|---------------|---------|---------------------------------------|
| `FIT`         | `on`    | Enable fit-based speculative decoding |
| `FIT_TARGET`  | `256`   | Fit target sequence length            |
| `FIT_CTX`     | `98304` | Fit context size                      |
| `UBATCH_SIZE` | `256`   | Unbatched (speculative) batch size    |
| `POLL_BATCH`  | `0`     | Poll batch size                       |

### Sampling & Penalties
| Variable           | Default | Description                   |
|--------------------|---------|-------------------------------|
| `TEMP`             | `0.6`   | Sampling temperature          |
| `TOP_P`            | `0.95`  | Top-p nucleus sampling        |
| `TOP_K`            | `20`    | Top-k sampling                |
| `MIN_P`            | `0.0`   | Minimum probability threshold |
| `PRESENCE_PENALTY` | `0.0`   | Presence penalty              |
| `REPEAT_PENALTY`   | `1.0`   | Repetition penalty            |

### Features
| Variable        | Default                         | Description                                                          |
|-----------------|---------------------------------|----------------------------------------------------------------------|
| `REASONING`     | `on`                            | Enable reasoning mode (`--reasoning on`)                             |
| `CHAT_TEMPLATE` | `/app/qwen_chat_template.jinja` | Path to Jinja chat template file (empty = model's built-in template) |

### Server
| Variable           | Default   | Description                    |
|--------------------|-----------|--------------------------------|
| `HOST`             | `0.0.0.0` | Bind address                   |
| `PORT_INTERNAL`    | `8080`    | Port inside Docker container   |
| `PORT_EXTERNAL`    | `8001`    | Port exposed to host           |
| `FORCE_CPU`        | `off`     | Force CPU runtime (on/off)     |
| `SEARXNG_SECRET`   | *(empty)* | Secret key for SearXNG         |

Adjust these in `.env` after copying from the template.

### Auto-generated opencode.json

Run `make generate_opencode_config` to generate `opencode.json` from `templates/opencode.json.template` using values from `.env`. This updates the provider URL, model name, model alias, and MCP configurations automatically.

The generated config includes MCP tool integration:
- **fetch**: Web fetching via the `mcp/fetch` Docker image
- **searxng-search**: Self-hosted web search via SearXNG
- **browser**: Browser automation via a custom MCP server
- **rag**: Knowledge-base semantic search and ingestion via the RAG service

## Makefile Commands

| Command                         | Description                                    |
|---------------------------------|------------------------------------------------|
| `make up`                       | Build and start (auto-detects GPU/CPU)         |
| `make down`                     | Stop and remove the container                  |
| `make validate`                 | Check if the server is healthy                 |
| `make install_opencode`         | Install Opencode CLI                           |
| `make check_gpu`                | Verify GPU and NVIDIA runtime setup            |
| `make check_docker`             | Verify Docker and Docker Compose               |
| `make smoke_test`               | Run a sample chat completion request           |
| `make generate_opencode_config` | Generate `opencode.json` from `.env`           |
| `make copy_env`                 | Copy `templates/.env.template` to `.env`       |
| `make download_qwen`            | Download the default Qwen model to `./models/` |
| `make install_huggingface_cli`  | Install Hugging Face CLI                       |
| `make build-mcp-browser`        | Build the MCP browser server image             |
| `make build-searxng-mcp`        | Build the MCP SearXNG server image             |
| `make build-mcp-rag`            | Build the MCP RAG server image                 |
| `make build-mcp`                | Build all MCP server images                    |
| `make download_embeddings`      | Download the embedding model to `./models/`    |
| `make rag-ingest-url URL=...`   | Ingest a URL into the knowledge base           |
| `make rag-ingest-file FILE=...` | Ingest a local PDF/DOCX/TXT/MD file            |
| `make rag-search QUERY=...`     | Semantic search over the knowledge base        |
| `make rag-sources`              | List ingested sources                          |
| `make rag-ui`                   | Open the RAG web UI in a browser               |

## Docker Compose Services

The project runs these services via Docker Compose:

- **llama**: The llama.cpp LLM server (main inference, `http://localhost:8001`)
- **searxng**: Self-hosted SearXNG web search engine (`http://localhost:8081`)
- **embeddings**: Dedicated llama.cpp instance in `--embeddings` mode serving the RAG vector model (`Qwen3-Embedding-0.6B-Q8_0`)
- **qdrant**: Vector database holding the RAG knowledge-base chunks
- **rag**: FastAPI RAG service — ingestion, chunking, embedding, and semantic search (`http://localhost:8002`)

All services include healthchecks and persistent data volumes.

## RAG Knowledge Base

The RAG service ingests web pages, PDF, DOCX, Markdown, and plain-text files, chunks them,
embeds the chunks with a llama.cpp embedding model, and stores the vectors in Qdrant.
You can search semantically over everything ingested via the API, the web UI, or Opencode
MCP tools.

### Web UI

Open `http://localhost:8002` (`RAG_PORT_EXTERNAL`) for the management UI: search the KB,
ingest a URL or file, list sources, expand a source to see its chunks, and delete sources.

### Ingesting & Searching

```bash
# URL (page only by default; add depth >= 1 to also follow same-origin links)
make rag-ingest-url URL=https://example.com/article

# Local file (PDF/DOCX/TXT/MD) — go through the Makefile, not the MCP, for binary uploads
make rag-ingest-file FILE=/path/to/doc.pdf

# Semantic search
make rag-search QUERY='what is a stack in python'
```

### Opencode MCP tools

- `knowledge_search` — semantic search over the KB (`query`, optional `top_k`, `min_score`)
- `knowledge_add_url` — scrape and ingest a web page (`url`)
- `knowledge_add_text` — ingest raw text (`text`, optional `title`)

### RAG environment variables

| Variable           | Default                        | Description                              |
|--------------------|--------------------------------|------------------------------------------|
| `EMBEDDING_MODEL`  | `Qwen3-Embedding-0.6B-Q8_0`    | Embedding GGUF filename (no extension)   |
| `EMBEDDING_HF_REPO`| `Qwen/Qwen3-Embedding-0.6B-GGUF` | Hugging Face repo for download         |
| `EMBEDDING_CTX`    | `8192`                         | Embedding context size                   |
| `EMBEDDING_DIM`    | `1024`                         | Embedding vector dimension               |
| `RAG_PORT_EXTERNAL`| `8002`                         | RAG service host port (web UI + API)     |
| `RAG_EMBED_BATCH`  | `8`                            | Chunks per embedding request             |
| `RAG_CHUNK_WORDS`  | `600`                          | Target chunk size in words               |
| `RAG_CHUNK_OVERLAP`| `100`                          | Chunk overlap in words                   |
| `RAG_MAX_CRAWL_PAGES` | `10`                        | Page cap for depth >= 1 URL crawls       |
| `RAG_FETCH_TIMEOUT` | `30`                          | Per-URL fetch timeout (seconds)          |
| `QDRANT_PORT`      | `6333`                         | Qdrant host port (admin UI, optional)    |

## Troubleshooting

### GPU Not Detected
If GPU acceleration isn't working:

1. Verify NVIDIA drivers are installed:
   ```bash
   nvidia-smi
   ```

2. Check NVIDIA Container Toolkit installation:
   ```bash
   make check_gpu
   ```

3. Restart Docker after installing the toolkit:
   ```bash
   sudo systemctl restart docker
   ```

4. The `make up` command auto-detects GPU availability; if neither `nvidia-smi` nor the NVIDIA Docker runtime is found, it falls back to CPU mode.

### Port Already in Use
If the external port is already in use, modify `PORT_EXTERNAL` in `.env`:

```bash
PORT_EXTERNAL=8002
```

### Out of Memory
If you encounter OOM errors:
- Use a smaller model
- Reduce `THREADS` or `CTX_SIZE`
- Set `FORCE_CPU=on` to disable GPU offloading
- Reduce `CACHE_RAM` or use a higher cache type (`q4_0` → `f16`)

## Data Persistence
Model data is stored in `./models/` (bind-mounted), KV cache is stored in the `llama_cache` Docker volume, SearXNG data in the `searxng_data` volume, Qdrant vectors in the `qdrant_data` volume, and ingested RAG documents in `./rag_data/` (bind-mounted) — all persist across container restarts.

## License

This project is licensed under the [MIT License](LICENSE).

Copyright (c) 2026 Retro Crest Mateusz Choiński

Note: Any tools, models, or third-party software used in this project are subject to their own respective licenses.
