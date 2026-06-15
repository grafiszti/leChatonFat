# llama coder
A Docker-based setup for running llama.cpp server with GPU acceleration, optimized for use as a
local LLM provider for the Opencode coding assistant.

## Features
- **GPU Acceleration**: Configured for NVIDIA GPUs with optimized settings
- **Docker Compose**: Easy setup and management
- **Speculative Decoding**: Fit-based speculative decoding for faster inference
- **Configurable Inference**: Sampling parameters, penalties, reasoning mode, and more via `.env`
- **Simple Management**: Makefile commands for common tasks

## Prerequisites
- Docker and Docker Compose installed
- NVIDIA GPU with drivers installed
- NVIDIA Container Toolkit (for GPU support)

## Quick Start

```bash
# Copy environment template
make copy_env

# Build and start the container
make up

# Validate the server is running
make validate
```

## Configuration

### Model
Edit `templates/.env.template` (then copy to `.env`) to configure:

| Variable       | Default                     | Description                                                |
|----------------|-----------------------------|------------------------------------------------------------|
| `MODEL_NAME`   | `Qwen3.6-35B-A3B-UD-Q3_K_M` | GGUF model filename (without `.gguf` extension)            |
| `CTX_SIZE`     | `65536`                     | Context window size in tokens                              |
| `N_GPU_LAYERS` | *(unset)*                   | Number of layers to offload to GPU (omit or `999` for all) |
| `THREADS`      | `6`                         | CPU threads for inference                                  |
| `FLASH_ATTN`   | `on`                        | Enable flash attention                                     |
| `BATCH_SIZE`   | `1024`                      | Prompt processing batch size                               |
| `CACHE_RAM`    | `4096`                      | KV cache memory budget in MiB                              |
| `PARALLEL`     | `1`                         | Context parallelism                                        |

### Speculative Decoding (Fit)
| Variable      | Default | Description                           |
|---------------|---------|---------------------------------------|
| `FIT`         | `on`    | Enable fit-based speculative decoding |
| `FIT_TARGET`  | `768`   | Fit target sequence length            |
| `FIT_CTX`     | `65536` | Fit context size                      |
| `UBATCH_SIZE` | `512`   | Unbatched (speculative) batch size    |
| `POLL_BATCH`  | `0`     | Poll batch size                       |

### Sampling & Penalties
| Variable           | Default | Description                   |
|--------------------|---------|-------------------------------|
| `TEMP`             | `0.6`   | Sampling temperature          |
| `TOP_P`            | `0.80`  | Top-p nucleus sampling        |
| `TOP_K`            | `20`    | Top-k sampling                |
| `MIN_P`            | `0.0`   | Minimum probability threshold |
| `PRESENCE_PENALTY` | `0.0`   | Presence penalty              |
| `REPEAT_PENALTY`   | `1.0`   | Repetition penalty            |

### Features
| Variable    | Default | Description                              |
|-------------|---------|------------------------------------------|
| `REASONING` | `on`    | Enable reasoning mode (`--reasoning on`) |

### Server
| Variable           | Default   | Description                    |
|--------------------|-----------|--------------------------------|
| `HOST`             | `0.0.0.0` | Bind address                   |
| `PORT_INTERNAL`    | `8080`    | Port inside Docker container   |
| `PORT_EXTERNAL`    | `8001`    | Port exposed to host           |

Adjust these in `.env` after copying from the template.

## Makefile Commands

| Command                         | Description                             |
|---------------------------------|-----------------------------------------|
| `make up`                       | Build and start the llama.cpp container |
| `make down`                     | Stop and remove the container           |
| `make validate`                 | Check if the server is healthy          |
| `make install_opencode`         | Install Opencode CLI                    |
| `make check_gpu`                | Verify GPU and NVIDIA runtime setup     |
| `make smoke_test`               | Run a sample chat completion request    |
| `make generate_opencode_config` | Generate `opencode.json` from `.env`    |
| `make copy_env`                 | Copy `.env.template` to `.env`          |

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

### Port Already in Use
If the external port is already in use, modify `PORT_EXTERNAL` in `.env`:

```bash
PORT_EXTERNAL=8002
```

The mapping in `docker-compose.yml` uses `${PORT_EXTERNAL}:${PORT_INTERNAL}` automatically.

### Out of Memory
If you encounter OOM errors:
- Use a smaller model
- Reduce `THREADS` or `CTX_SIZE`
- Lower `N_GPU_LAYERS` or remove it to offload fewer layers

## Data Persistence
Model data is stored in `./models/` (bind-mounted), and KV cache is stored 
in the `llama_cache` Docker volume, so both persist across container restarts.
