# WhisperLive Makefile

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                           VAD CONFIGURATION                               ║
# ║                   Voice Activity Detection Parameters                     ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# VAD Threshold - Controls speech detection sensitivity (Range: 0.0-1.0)
# Lower values (0.3) = More sensitive, detects quieter speech
# Higher values (0.7) = Less sensitive, requires clearer speech signals
# Default: 0.5 (balanced sensitivity)
VAD_THRESHOLD ?= 0.5

# Negative Threshold - Probability threshold for end-of-speech detection (Range: 0.0-1.0)
# Controls when speech is considered to have ended
# Default: None (auto-calculated as VAD_THRESHOLD - 0.15)
VAD_NEG_THRESHOLD ?= 

# Minimum Speech Duration - Shortest duration for valid speech in milliseconds (Range: 0-5000)
# Speech shorter than this will be ignored as noise
# Default: 250ms (helps filter out very brief sounds)
VAD_MIN_SPEECH_DURATION_MS ?= 250

# Maximum Speech Duration - Longest continuous speech segment in seconds (Range: 1-300)
# Longer speech will be split into chunks for processing
# Default: 30s (prevents memory issues with very long utterances)
VAD_MAX_SPEECH_DURATION_S ?= 10

# Minimum Silence Duration - Required silence before ending speech in milliseconds (Range: 100-5000)
# How long to wait in silence before considering speech finished
# Default: 2000ms (2 seconds of silence ends speech detection)
VAD_MIN_SILENCE_DURATION_MS ?= 300

# Speech Padding - Extra audio added around detected speech in milliseconds (Range: 0-1000)
# Prevents cutting off speech at beginning/end of detected segments
# Default: 400ms (adds 0.4s padding on each side)
VAD_SPEECH_PAD_MS ?= 400

# Window Size - Analysis window size for VAD processing in milliseconds (Range: 32-128)
# Smaller = more responsive but less stable, Larger = more stable but less responsive
# Default: 64ms (good balance for real-time processing)
VAD_WINDOW_SIZE_SAMPLES ?= 64

# Return Seconds - Return speech timestamps in seconds instead of samples (Range: true/false)
# true = timestamps in seconds, false = timestamps in audio samples
# Default: false (uses sample-based timestamps)
VAD_RETURN_SECONDS ?= false

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                         TRIGGER WORD DETECTION                            ║
# ║                     Activate Recording on Keywords                        ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# Trigger Words - Space-separated list of words that activate recording
# When any of these words are detected, the following speech is saved
# Example: "computer alert help" - detects any of these words
# Default: empty (no trigger word detection)
TRIGGER_WORDS ?= computer

# Trigger Output File - Where to save triggered transcriptions (absolute path)
# File will contain timestamped transcriptions after trigger word detection
# Default: /output/logs/triggers.log (inside Docker container, maps to ./logs/triggers.log)
TRIGGER_OUTPUT_FILE ?= /output/logs/triggers.log

# Text Stability Delay - Time to wait after text stops changing before saving (seconds)
# Prevents saving incomplete transcriptions, waits for speech to finish
# Default: 1.5s (good balance between responsiveness and completeness)
TEXT_STABILITY_DELAY ?= 1.0

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                          LOGGING CONFIGURATION                            ║
# ║                     Transcription Analysis & Debugging                    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# Log Directory - Where to save transcription logs (absolute path recommended)
# Logs include JSON data for analysis and human-readable text files
# Default: /output/logs (inside Docker container, maps to ./logs on host)
LOG_DIR ?= /output/logs

# Disable JSON Logging - Turn off structured data logging (Range: true/false)
# JSON logs contain timestamps, durations, and metadata for analysis
# Default: false (JSON logging enabled by default)
DISABLE_JSON_LOG ?= false

# Disable Text Logging - Turn off human-readable logs (Range: true/false)
# Text logs contain timestamped segments and statistics
# Default: false (text logging enabled by default)
DISABLE_TEXT_LOG ?= false

# Verbose Logging - Include extra metadata (Range: true/false)
# Adds no_speech_prob, VAD events, and detailed timing information
# Default: false (enable for debugging VAD/segment issues)
LOG_VERBOSE ?= false

# Disable All Logging - Turn off transcription logging (Range: true/false)
# Set to true to disable all logging (overrides other log settings)
# Default: false (logging enabled)
DISABLE_LOGGING ?= false



.PHONY: server client stop clear check-cache clean-cache build build-server build-server-prod build-client build-automation nuke help compose-up compose-down compose-logs compose-build

# Default target: show help
help: ## Show this help message
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    WhisperLive Makefile Help                  ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "Usage: make [target] [VAR=value ...]"
	@echo ""
	@echo "Main Targets:"
	@echo "  make server          - Run the GPU server (with model cache)"
	@echo "  make client          - Run orchestrated client with Windows automation"
	@echo "  make build           - Build both server and client images"
	@echo "  make stop            - Stop all WhisperLive containers"
	@echo "  make clear           - Clear all logs in the /logs directory"
	@echo "  make nuke            - Complete rebuild: stop, clear, build, server, client"
	@echo "  make check-cache     - Show cached model status and sizes"
	@echo "  make clean-cache     - Remove cached models (force re-download)"
	@echo ""
	@echo "Docker Compose (Orchestrated Services):"
	@echo "  make compose-up      - Start all services with Windows automation"
	@echo "  make compose-down    - Stop and remove all compose services"
	@echo "  make compose-logs    - View logs from all services"
	@echo "  make compose-build   - Build all compose services"
	@echo ""
	@echo "Build Options:"
	@echo "  make build-server    - Build server (fast, with cache, ~14GB)"
	@echo "  make build-server-prod - Build production server (smaller, ~10GB)"
	@echo "  make build-client    - Build client image"
	@echo "  make build-automation - Build Windows automation service"
	@echo ""
	@echo "Examples:"
	@echo "  make client VAD_THRESHOLD=0.6"
	@echo "  make client TRIGGER_WORDS=\"computer alert help\""
	@echo "  make client TRIGGER_WORDS=\"computer\" WSL_AUTO_TYPE=true"
	@echo "  make compose-up  # Start services, then make client"
	@echo ""

server:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                       WhisperLive GPU Server                  ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║ Model: Whisper Large-v3 (GPU Backend)                         ║"
	@echo "║ Port:  9090                                                    ║"
	@echo "║ GPU:   CUDA (Required)                                         ║"
	@echo "║ Cache: Persistent model storage enabled                       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔄 Preparing GPU server environment..."
	@docker stop whisperlive-server-gpu 2>/dev/null || true
	@docker rm whisperlive-server-gpu 2>/dev/null || true
	@echo "🚀 Starting GPU server container with persistent model cache..."
	@echo "   📦 Models will be cached and reused between restarts"
	@echo ""
	docker run -d --name whisperlive-server-gpu \
		-p 9090:9090 \
		--gpus all \
		-v whisper-models:/root/.cache/whisper-live \
		-v huggingface-models:/root/.cache/huggingface \
		-v openvino-models:/root/.cache/openvino_whisper_models \
		whisperlive-gpu \
		python3 run_server.py --port 9090 \
			--backend faster_whisper

client: ## Run orchestrated client with Windows automation
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  WhisperLive Orchestrated Client              ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║ Architecture: Docker Compose Multi-Service                    ║"
	@echo "║ Server: Containerized GPU transcription                       ║"
	@echo "║ Client: Containerized audio processing                        ║"
	@echo "║ Automation: Windows typing via host bridge                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🎤 Starting orchestrated client with Windows automation..."
	@if [ -n "$(TRIGGER_WORDS)" ]; then \
		echo "🎯 Trigger Words: $(TRIGGER_WORDS)"; \
		echo "⌨️  Windows Auto-Typing: $(WSL_AUTO_TYPE)"; \
	fi
	@echo "💡 Recommended: Start Windows automation service first:"
	@echo "   ./scripts/start_windows_automation_service.sh"
	@echo ""
	VAD_THRESHOLD=$(VAD_THRESHOLD) \
	TRIGGER_WORDS='$(TRIGGER_WORDS)' \
	WSL_AUTO_TYPE=$(WSL_AUTO_TYPE) \
	WSL_TYPE_DELAY_MS=$(WSL_TYPE_DELAY_MS) \
	TEXT_STABILITY_DELAY=$(TEXT_STABILITY_DELAY) \
	docker-compose run --rm client

stop:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                      Stopping WhisperLive                     ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🛑 Stopping Docker Compose services..."
	@docker-compose down 2>/dev/null || true
	@echo "🛑 Stopping legacy server containers..."
	@docker stop whisperlive-server-gpu 2>/dev/null || true
	@docker rm whisperlive-server-gpu 2>/dev/null || true
	@echo "🛑 Stopping any remaining containers..."
	@docker stop $$(docker ps -q --filter ancestor=whisperlive-client) 2>/dev/null || true
	@docker rm $$(docker ps -aq --filter ancestor=whisperlive-client) 2>/dev/null || true
	@docker stop $$(docker ps -q --filter ancestor=whisperlive-gpu) 2>/dev/null || true  
	@docker rm $$(docker ps -aq --filter ancestor=whisperlive-gpu) 2>/dev/null || true
	@echo "🧹 Cleaning up containers..."
	@docker container prune -f 2>/dev/null || true
	@echo "✅ All WhisperLive containers stopped and cleaned"
	@echo "📦 Note: Model cache volumes are preserved for faster restarts"

clear: ## Clear all logs and fix permissions
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     Clearing Log Directory                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🗑️  Clearing and fixing permissions for output directories..."
	@sudo rm -rf logs/* output/* 2>/dev/null || rm -rf logs/* output/* 2>/dev/null || true
	@sudo chown -R $$USER:$$USER logs output 2>/dev/null || true
	@mkdir -p logs output 2>/dev/null || true
	@chmod 755 logs output 2>/dev/null || true
	@echo "✅ All logs cleared and permissions fixed"

check-cache: ## Show cached model status and sizes
	@./scripts/check-cache.sh

clean-cache: ## Remove all cached models (will re-download on next start)
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     Cleaning Model Cache                      ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "⚠️  This will remove all cached models!"
	@echo "   Next server start will re-download models (~2-10GB)"
	@echo ""
	@read -p "Are you sure? (y/N): " confirm && [ "$$confirm" = "y" ] || exit 1
	@echo ""
	@echo "🗑️  Removing model cache volumes..."
	@docker volume rm whisper-models huggingface-models openvino-models 2>/dev/null || true
	@echo "✅ Model cache cleaned - models will re-download on next start"

nuke: ## Complete rebuild: stop, clear, build, server, client
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                         NUCLEAR REBUILD                       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚨 Starting complete rebuild sequence..."
	@echo "   1. Stopping all containers..."
	@$(MAKE) --no-print-directory stop
	@echo ""
	@echo "   2. Clearing all logs..."
	@$(MAKE) --no-print-directory clear
	@echo ""
	@echo "   3. Building fresh images..."
	@$(MAKE) --no-print-directory build
	@echo ""
	@echo "   4. Starting server..."
	@$(MAKE) --no-print-directory server
	@echo ""
	@echo "🎯 Server started! Waiting 3 seconds for initialization..."
	@sleep 3
	@echo "   5. Starting client..."
	@$(MAKE) --no-print-directory client

build: build-server build-client ## Build both server and client images

build-server: ## Build server image with cache (default - fast rebuilds)
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║        Building WhisperLive GPU Server (Cache Optimized)      ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 Using BuildKit with persistent cache for fast rebuilds..."
	@echo "   • First build: ~15 minutes (downloading packages)"
	@echo "   • Subsequent builds: ~30 seconds (using cache)"
	@echo "   • Image size: ~14 GB"
	@echo ""
	@DOCKER_BUILDKIT=1 docker build \
		--progress=plain \
		-f docker/Dockerfile.gpu \
		-t whisperlive-gpu .
	@echo "✅ GPU Server image built with caching!"

build-server-prod: ## Build smaller production server image (multi-stage)
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║      Building WhisperLive GPU Server (Production Build)       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📦 Building smaller production image with multi-stage..."
	@echo "   • Build time: ~15 minutes"
	@echo "   • Image size: ~8-10 GB (30-40% smaller)"
	@echo "   • Best for: deployment, not development"
	@echo ""
	@DOCKER_BUILDKIT=1 docker build \
		--progress=plain \
		-f docker/Dockerfile.gpu-multistage \
		-t whisperlive-gpu:prod .
	@echo "✅ Production GPU Server image built!"
	@echo "   Tagged as: whisperlive-gpu:prod"

build-client: ## Build client image
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  Building WhisperLive GPU Client              ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔨 Building GPU client image..."
	docker build -f docker/Dockerfile.client -t whisperlive-client .
	@echo "✅ GPU Client image built successfully!"

build-automation: ## Build Windows automation service
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║              Building Windows Automation Service              ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔨 Building automation service with WSL interop bridge..."
	docker build -f docker/Dockerfile.automation -t whisper-automation .
	@echo "✅ Windows automation service built successfully!"

# ╔════════════════════════════════════════════════════════════════╗
# ║                     DOCKER COMPOSE TARGETS                    ║
# ║              Orchestrated Multi-Service Deployment            ║
# ╚════════════════════════════════════════════════════════════════╝

compose-build: ## Build all Docker Compose services
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                Building All Compose Services                  ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔨 Building server, client, and automation services..."
	docker-compose build --parallel
	@echo "✅ All services built successfully!"

compose-up: ## Start all services (server + automation) in background
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    Starting WhisperLive Stack                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 Starting server and Windows automation service..."
	@echo "   📁 Setting up output directories..."
	@mkdir -p "$$(pwd)/logs" "$$(pwd)/output" 2>/dev/null || true
	@chmod 755 "$$(pwd)/logs" "$$(pwd)/output" 2>/dev/null || true
	VAD_THRESHOLD=$(VAD_THRESHOLD) \
	TRIGGER_WORDS='$(TRIGGER_WORDS)' \
	WSL_AUTO_TYPE=$(WSL_AUTO_TYPE) \
	WSL_TYPE_DELAY_MS=$(WSL_TYPE_DELAY_MS) \
	TEXT_STABILITY_DELAY=$(TEXT_STABILITY_DELAY) \
	docker-compose up -d server automation
	@echo "✅ Services started in background!"
	@echo "🔗 Server: http://localhost:9090"
	@echo "🔗 Automation: http://localhost:8080"
	@echo ""
	@echo "💡 Host service recommended: ./scripts/start_windows_automation_service.sh"
	@echo "Next: Run 'make client' for interactive transcription"

compose-down: ## Stop and remove all compose services
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                   Stopping Compose Services                   ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🛑 Stopping all orchestrated services..."
	docker-compose down
	@echo "✅ All services stopped and removed!"

compose-logs: ## View logs from all running compose services
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                      Service Logs                             ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	docker-compose logs -f