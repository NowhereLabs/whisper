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
# Default: /output/triggers.log (inside Docker container, maps to ./logs/triggers.log)
TRIGGER_OUTPUT_FILE ?= /output/triggers.log

# Text Stability Delay - Time to wait after text stops changing before saving (seconds)
# Prevents saving incomplete transcriptions, waits for speech to finish
# Default: 1.5s (good balance between responsiveness and completeness)
TEXT_STABILITY_DELAY ?= 1.0

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                      WINDOWS AUTOMATION (WSL2)                            ║
# ║                     Auto-Type Transcriptions to Windows                   ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# WSL Auto-Type - Enable automatic typing into Windows applications (true/false)
# When true, transcribed text after trigger words will be typed into active Windows app
# Requires Windows automation service running: ./scripts/start_windows_automation_service.sh
# Default: true (auto-typing enabled)
WSL_AUTO_TYPE ?= true

# Type Delay - Delay between keystrokes in milliseconds (Range: 0-1000)
# Lower values type faster but may overwhelm some applications
# Default: 0ms (fastest typing)
WSL_TYPE_DELAY_MS ?= 0

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║                          LOGGING CONFIGURATION                            ║
# ║                     Transcription Analysis & Debugging                    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# Log Directory - Where to save transcription logs (absolute path recommended)
# Logs include JSON data for analysis and human-readable text files
# Default: /output (inside Docker container, maps to ./logs on host)
LOG_DIR ?= /output

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



.PHONY: server client stop clear check-cache clean-cache build nuke help compose-up compose-down compose-logs automation-service

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
	@echo "  make automation-service - Start Windows automation service (for WSL→Windows typing)"
	@echo "  make build           - Build both server and client images"
	@echo "  make stop            - Stop all WhisperLive containers"
	@echo "  make clear           - Clear all logs in the /logs directory"
	@echo "  make nuke            - Complete rebuild: stop, clear, build, server, client"
	@echo "  make check-cache     - Show cached model status and sizes"
	@echo "  make clean-cache     - Remove cached models (force re-download)"
	@echo ""
	@echo "Docker Compose (Orchestrated Services):"
	@echo "  make compose-up      - Start server in background"
	@echo "  make compose-down    - Stop and remove all compose services"
	@echo "  make compose-logs    - View logs from all services"
	@echo ""
	@echo "Examples:"
	@echo "  make client VAD_THRESHOLD=0.6"
	@echo "  make client TRIGGER_WORDS=\"computer alert help\""
	@echo "  make client TRIGGER_WORDS=\"computer\" WSL_AUTO_TYPE=true"
	@echo "  make compose-up  # Start services, then make client"
	@echo ""

server:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                  WhisperLive Orchestrated Server              ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║ Architecture: Docker Compose Service                          ║"
	@echo "║ Model: Whisper Large-v3 (GPU Backend)                         ║"
	@echo "║ Port:  9090                                                    ║"
	@echo "║ GPU:   CUDA (Required)                                         ║"
	@echo "║ Cache: Persistent model storage enabled                       ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 Starting orchestrated GPU server..."
	@echo "   📦 Models will be cached and reused between restarts"
	@echo "   🔧 Stopping any existing services..."
	@docker-compose down 2>/dev/null || true
	@echo ""
	docker-compose up -d server
	@echo ""
	@echo "✅ Server started successfully!"
	@echo "🔗 Server: http://localhost:9090"
	@echo "💡 Next: Run 'make client' for interactive transcription"

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
	fi
	@echo "⌨️  Windows Auto-Typing: $(WSL_AUTO_TYPE)"
	@if [ "$(WSL_AUTO_TYPE)" = "true" ]; then \
		echo "💡 Recommended: Start Windows automation service first:"; \
		echo "   make automation-service"; \
	fi
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
	@echo "🛑 Stopping Windows automation service..."
	@lsof -ti :8080 2>/dev/null | xargs kill -9 2>/dev/null || echo "   No service running on port 8080"
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
	@echo "✅ All WhisperLive services stopped and cleaned"
	@echo "📦 Note: Model cache volumes are preserved for faster restarts"

clear: ## Clear all logs and fix permissions
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     Clearing Log Directory                    ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🗑️  Clearing and fixing permissions for logs directory..."
	@sudo rm -rf logs/* 2>/dev/null || rm -rf logs/* 2>/dev/null || true
	@sudo chown -R $$USER:$$USER logs 2>/dev/null || true
	@mkdir -p logs 2>/dev/null || true
	@chmod 755 logs 2>/dev/null || true
	@echo "✅ All logs cleared and permissions fixed"

check-cache: ## Show cached model status and sizes
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                     WhisperLive Cache Status                  ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "📦 Docker Volumes (Model Cache):"
	@echo "----------------------------------------"
	@for volume in whisper-models huggingface-models openvino-models; do \
		if docker volume inspect $$volume &>/dev/null; then \
			echo "✅ $$volume: exists"; \
			mountpoint=$$(docker volume inspect $$volume --format '{{.Mountpoint}}' 2>/dev/null); \
			if [ -n "$$mountpoint" ] && [ -d "$$mountpoint" ]; then \
				size=$$(sudo du -sh "$$mountpoint" 2>/dev/null | cut -f1 || echo "unknown"); \
				echo "   📁 Size: $$size"; \
				echo "   📍 Path: $$mountpoint"; \
			fi; \
		else \
			echo "❌ $$volume: not created yet"; \
		fi; \
		echo ""; \
	done
	@echo "💡 Tips:"
	@echo "• First server start: downloads models (~2-10GB)"
	@echo "• Subsequent starts: uses cached models (fast!)"
	@echo "• Run 'make clean-cache' to remove all cached models"
	@echo "• Rebuilding Docker images won't affect model cache"

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

nuke: ## Complete rebuild: stop, clear, build, start server and client
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    NUCLEAR ORCHESTRATED REBUILD               ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚨 Starting complete orchestrated rebuild sequence..."
	@echo "   1. Stopping all services..."
	@$(MAKE) --no-print-directory stop
	@echo ""
	@echo "   2. Clearing all logs..."
	@$(MAKE) --no-print-directory clear
	@echo ""
	@echo "   3. Building all services (server, client)..."
	@$(MAKE) --no-print-directory build
	@echo ""
	@echo "   4. Starting server in background..."
	@$(MAKE) --no-print-directory compose-up
	@echo ""
	@echo "🎯 Server ready! Waiting 3 seconds for initialization..."
	@sleep 3
	@echo "   5. Launching interactive client..."
	@$(MAKE) --no-print-directory client

build: ## Build all Docker Compose services
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                Building All Compose Services                  ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔨 Building server and client services in parallel..."
	docker-compose build --parallel
	@echo "✅ All services built successfully!"

# ╔════════════════════════════════════════════════════════════════╗
# ║                     DOCKER COMPOSE TARGETS                    ║
# ║              Orchestrated Multi-Service Deployment            ║
# ╚════════════════════════════════════════════════════════════════╝


compose-up: ## Start server in background
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                    Starting WhisperLive Stack                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🚀 Starting GPU transcription server..."
	@echo "   📁 Setting up logs directory..."
	@mkdir -p "$$(pwd)/logs" 2>/dev/null || true
	@chmod 755 "$$(pwd)/logs" 2>/dev/null || true
	VAD_THRESHOLD=$(VAD_THRESHOLD) \
	TRIGGER_WORDS='$(TRIGGER_WORDS)' \
	WSL_AUTO_TYPE=$(WSL_AUTO_TYPE) \
	WSL_TYPE_DELAY_MS=$(WSL_TYPE_DELAY_MS) \
	TEXT_STABILITY_DELAY=$(TEXT_STABILITY_DELAY) \
	docker-compose up -d server
	@echo "✅ Server started in background!"
	@echo "🔗 Server: http://localhost:9090"
	@echo ""
	@echo "💡 For Windows automation, start host service:"
	@echo "   make automation-service"
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

automation-service: ## Start Windows automation service for WSL→Windows typing
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║             Windows Automation Service (WSL2)                 ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🔧 Starting Windows Automation Service on WSL Host..."
	@echo ""
	@if ! grep -qi microsoft /proc/version 2>/dev/null; then \
		echo "❌ This requires WSL2 (Windows Subsystem for Linux)"; \
		exit 1; \
	fi
	@if ! command -v powershell.exe > /dev/null 2>&1; then \
		echo "❌ PowerShell not available from WSL"; \
		exit 1; \
	fi
	@echo "✅ WSL2 environment detected"
	@echo "✅ PowerShell available"
	@echo ""
	@if ! python3 -c "import flask, requests" 2>/dev/null; then \
		echo "📦 Installing Python dependencies..."; \
		pip3 install flask requests; \
	fi
	@echo "🚀 Starting Windows Automation API service on port 8080..."
	@echo "💡 The service will accept typing requests from Docker containers"
	@echo ""
	@echo "🎯 API Endpoints:"
	@echo "   GET  /health - Service health check"
	@echo "   POST /type   - Type text into Windows applications"
	@echo "   GET  /status - Service capabilities"
	@echo ""
	@echo "🛑 Press Ctrl+C to stop the service"
	@echo ""
	@cd "$$(pwd)" && python3 utils/windows_sidecar.py