# ---------------------------- Docker management ----------------------------
up:
	# Always rebuild MCP images (docker layer cache makes this cheap when
	# nothing changed); guards only on existence kept stale images around.
	@docker build -t lechatonfat-mcp-browser mcps/browser
	@docker build --network=host -t lechatonfat-searxng-mcp mcps/searxng
	@docker build --network=host -t lechatonfat-mcp-rag mcps/rag
	@if [ -f .env ]; then \
		FORCE_CPU=$$(grep '^FORCE_CPU=' .env | head -1 | cut -d'=' -f2); \
	else \
		FORCE_CPU=off; \
	fi; \
	if [ "$$FORCE_CPU" = "on" ] || ! (command -v nvidia-smi > /dev/null 2>&1 && docker info 2>/dev/null | grep -q "nvidia"); then \
		echo "CPU runtime"; \
		docker compose -f docker-compose.yml build; \
		docker compose -f docker-compose.yml up -d; \
	else \
		echo "GPU detected - using NVIDIA runtime"; \
		docker compose -f docker-compose.yml -f docker-compose.override.yml build; \
		docker compose -f docker-compose.yml -f docker-compose.override.yml up -d; \
	fi

down:
	docker compose down

# ---------------------------- Deployment validation ----------------------------
validate:
	curl http://localhost:8001/health

# ---------------------------- Hardware validation ----------------------------
check_docker:
	@if command -v docker > /dev/null 2>&1; then \
		echo "✓ Docker is installed"; \
	else \
		echo "✗ Docker is NOT installed"; \
	fi
	@if command -v docker compose > /dev/null 2>&1; then \
		echo "✓ Docker Compose is installed"; \
	else \
		echo "✗ Docker Compose is NOT installed"; \
	fi

check_gpu:
	@echo "Checking GPU setup..."
	@if command -v nvidia-smi > /dev/null 2>&1; then \
		echo "✓ NVIDIA driver is installed"; \
		nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1; \
	else \
		echo "✗ NVIDIA driver not found"; \
	fi
	@if docker info 2>/dev/null | grep -q "nvidia"; then \
		echo "✓ NVIDIA runtime is configured in Docker"; \
	else \
		echo "✗ NVIDIA runtime not configured in Docker"; \
		echo ""; \
		echo "To install NVIDIA Container Toolkit:"; \
		echo "  Visit: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"; \
		echo "  Or run: curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"; \
		echo "         curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list"; \
		echo "         sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit"; \
		echo "         sudo nvidia-ctk runtime configure --runtime=docker && sudo systemctl restart docker"; \
	fi

smoke_test:
	@if [ ! -f .env ]; then echo "Error: .env file not found" >&2; exit 1; fi
	@MODEL=$$(grep '^MODEL_NAME=' .env | head -1 | cut -d'=' -f2 | sed 's/^["'\''"]//;s/["'\''"]$$//'); \
	PORT=$$(grep '^PORT_EXTERNAL=' .env | head -1 | cut -d'=' -f2 | sed 's/^["'\''"]//;s/["'\''"]$$//'); \
	PORT=$${PORT:-8001}; \
	echo "Using model: $$MODEL on port $$PORT"; \
	curl -s "http://localhost:$$PORT/v1/chat/completions" \
	-H "Content-Type: application/json" \
	-d '{"model":"'"$$MODEL"'", "messages":[{"role":"user","content":"Write hello world in Python"}]}'

# ---------------------------- MCP server images ----------------------------
build-mcp-browser:
	docker build -t lechatonfat-mcp-browser mcps/browser

build-searxng-mcp:
	docker build --network=host -t lechatonfat-searxng-mcp mcps/searxng

build-mcp-rag:
	docker build --network=host -t lechatonfat-mcp-rag mcps/rag

build-mcp: build-mcp-browser build-searxng-mcp build-mcp-rag

# Force a clean rebuild of both MCP images (no cache, in case sources changed)
rebuild-mcp:
	docker rmi -f lechatonfat-mcp-browser lechatonfat-searxng-mcp lechatonfat-mcp-rag 2>/dev/null || true
	$(MAKE) build-mcp

# ---------------------------- RAG --------------------------------------------
RAG_PORT := $(shell grep '^RAG_PORT_EXTERNAL=' .env 2>/dev/null | head -1 | cut -d'=' -f2)
RAG_PORT := $(if $(RAG_PORT),$(RAG_PORT),8002)
RAG_BASE := http://localhost:$(RAG_PORT)

rag-ingest-url:
	@if [ -z "$(URL)" ]; then echo "Usage: make rag-ingest-url URL=https://example.com"; exit 1; fi
	curl -s -X POST "$(RAG_BASE)/ingest/url" -H "Content-Type: application/json" -d '{"url":"$(URL)"}'

rag-ingest-file:
	@if [ -z "$(FILE)" ]; then echo "Usage: make rag-ingest-file FILE=/path/to/doc.pdf"; exit 1; fi
	curl -s -X POST "$(RAG_BASE)/ingest/file" -F "file=@$(FILE)"

rag-search:
	@if [ -z "$(QUERY)" ]; then echo "Usage: make rag-search QUERY='your query'"; exit 1; fi
	curl -s "$(RAG_BASE)/search?q=$(QUERY)"

rag-sources:
	curl -s "$(RAG_BASE)/sources"

rag-ui:
	@command -v xdg-open > /dev/null 2>&1 && xdg-open "$(RAG_BASE)" || echo "Open $(RAG_BASE) in your browser"

# ---------------------------- Config generation ----------------------------
generate_opencode_config:
	bash generate_opencode_config.sh

copy_env:
	cp templates/.env.template .env

# ---------------------------- Installing third-party tools ----------------------------
install_opencode:
	curl -fsSL https://opencode.ai/install | bash

install_huggingface_cli:
	curl -LsSf https://hf.co/cli/install.sh | bash

# ---------------------------- Embedding model download -------------------------
download_embeddings:
	@if [ ! -f .env ]; then echo "Error: .env not found. Run 'make copy_env' first." >&2; exit 1; fi
	@MODEL=$$(grep '^EMBEDDING_MODEL=' .env | head -1 | cut -d'=' -f2 | sed 's/^["'\''"]//;s/["'\''"]$$//'); \
	REPO=$$(grep '^EMBEDDING_HF_REPO=' .env | head -1 | cut -d'=' -f2 | sed 's/^["'\''"]//;s/["'\''"]$$//'); \
	echo "Downloading $$MODEL from $$REPO..."; \
	mkdir -p models; \
	if [ -f "models/$$MODEL.gguf" ]; then \
		echo "Model already exists at models/$$MODEL.gguf"; \
	else \
		hf download "hf://$$REPO/$$MODEL.gguf" --local-dir models; \
		echo "Download complete: models/$$MODEL.gguf"; \
	fi

# ---------------------------- Default model download ---------------------------------
download_qwen:
	@if [ ! -f .env ]; then echo "Error: .env not found. Run 'make copy_env' first." >&2; exit 1; fi
	@MODEL=$$(grep '^MODEL_NAME=' .env | head -1 | cut -d'=' -f2 | sed 's/^["'\''"]//;s/["'\''"]$$//'); \
	REPO=$$(grep '^HF_REPO=' .env | head -1 | cut -d'=' -f2 | sed 's/^["'\''"]//;s/["'\''"]$$//'); \
	echo "Downloading $$MODEL from $$REPO..."; \
	mkdir -p models; \
	if [ -f "models/$$MODEL.gguf" ]; then \
		echo "Model already exists at models/$$MODEL.gguf"; \
	else \
		hf download "hf://$$REPO/$$MODEL.gguf" --local-dir models; \
		echo "Download complete: models/$$MODEL.gguf"; \
	fi
