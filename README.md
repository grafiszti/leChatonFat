# llama coder
A Docker-based setup for running llama.cpp server with GPU acceleration, optimized for use as a 
local LLM provider as coding assistant.

## Features
- **GPU Acceleration**: Configured for NVIDIA GPUs with optimized settings
- **Docker Compose**: Easy setup and management
- **Optimized Performance**: Pre-configured with flash attention and GPU tuning
- **Simple Management**: Makefile commands for common tasks

## Prerequisites
- Docker and Docker Compose installed
- NVIDIA GPU with drivers installed
- NVIDIA Container Toolkit (for GPU support)

## Configuration
### GPU Settings
The docker-compose.yml is configured with:
- `-m /models/Qwopus3.5-9B-coder-Exp-Q4_K_M.gguf`: Model path
- `--ctx-size 16384`: Context size of 16K tokens
- `--n-gpu-layers 99`: 99 GPU layers offloaded
- `--flash-attn on`: Flash attention enabled
- `--threads 12`: 12 CPU threads for inference

You can adjust these settings in `docker-compose.yml` based on your GPU memory and requirements.

## Makefile Commands
| Command                 | Description                                          |
|-------------------------|------------------------------------------------------|
| `make up`               | Start the Ollama container                           |
| `make down`             | Turn off the Ollama container                        |
| `make validate`         | Check if Ollama is running and list available models |
| `make install_opencode` | Install Opencode                                     |
| `make check_gpu`        | Verify GPU setup and NVIDIA runtime configuration    |
| `make smoke_test`       | Run a sample chat completion request                 |

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
If port 8080 is already in use, modify the port mapping in `docker-compose.yml`:

```yaml
ports:
  - "8081:8080"  # Change 8080 to your preferred port
```

### Out of Memory
If you encounter OOM errors:
- Use a smaller model instead
- Reduce `--threads 12` to 1

## Data Persistence
Model data is stored in a Docker volume, so your downloaded models persist across container restarts.
