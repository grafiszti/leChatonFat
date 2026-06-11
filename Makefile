up:
	docker compose build
	docker compose up -d

down:
	docker compose down

validate:
	curl http://localhost:8080/health

install_opencode:
	curl -fsSL https://opencode.ai/install | bash

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
	curl http://localhost:8080/v1/chat/completions \
	-H "Content-Type: application/json" \
	-d '{"model":"Qwopus3.5-9B-coder-Exp-Q4_K_M", "messages":[{"role":"user","content":"Write hello world in Python"}]}'

opencode:
	bash ./generate_opencode_config.sh