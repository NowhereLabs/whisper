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
VAD_MAX_SPEECH_DURATION_S ?= 30

# Minimum Silence Duration - Required silence before ending speech in milliseconds (Range: 100-5000)
# How long to wait in silence before considering speech finished
# Default: 2000ms (2 seconds of silence ends speech detection)
VAD_MIN_SILENCE_DURATION_MS ?= 2000

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



.PHONY: server client stop check-cache clean-cache build build-server build-server-prod build-client help

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
	@echo "  make client          - Run the client with microphone"
	@echo "  make build           - Build both server and client images"
	@echo "  make stop            - Stop all WhisperLive containers"
	@echo "  make check-cache     - Show cached model status and sizes"
	@echo "  make clean-cache     - Remove cached models (force re-download)"
	@echo ""
	@echo "Build Options:"
	@echo "  make build-server    - Build server (fast, with cache, ~14GB)"
	@echo "  make build-server-prod - Build production server (smaller, ~10GB)"
	@echo "  make build-client    - Build client image"
	@echo ""
	@echo "Example with VAD tuning:"
	@echo "  make client VAD_THRESHOLD=0.6 LOG_VERBOSE=true"
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

client:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                      WhisperLive GPU Client                   ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║ Server: localhost:9090                                         ║"
	@echo "║ Model:  large-v3 (GPU Optimized)                              ║"
	@echo "║ Audio:  Microphone input via Docker                           ║"
	@echo "║ Note:   WSL2 audio passthrough enabled                        ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🎤 Initializing GPU audio client..."
	@echo "🔗 Connecting to GPU transcription server..."
	@if [ "$(VAD_THRESHOLD)" != "0.5" ] || [ -n "$(VAD_NEG_THRESHOLD)" ] || [ "$(VAD_MIN_SPEECH_DURATION_MS)" != "250" ] || [ "$(VAD_MAX_SPEECH_DURATION_S)" != "30" ] || [ "$(VAD_MIN_SILENCE_DURATION_MS)" != "2000" ] || [ "$(VAD_SPEECH_PAD_MS)" != "400" ] || [ "$(VAD_WINDOW_SIZE_SAMPLES)" != "64" ] || [ "$(VAD_RETURN_SECONDS)" = "true" ]; then \
		echo "🎛️  VAD Configuration:"; \
		echo "   - Threshold: $(VAD_THRESHOLD)"; \
		echo "   - Negative Threshold: $(VAD_NEG_THRESHOLD)"; \
		echo "   - Min Speech Duration: $(VAD_MIN_SPEECH_DURATION_MS)ms"; \
		echo "   - Max Speech Duration: $(VAD_MAX_SPEECH_DURATION_S)s"; \
		echo "   - Min Silence Duration: $(VAD_MIN_SILENCE_DURATION_MS)ms"; \
		echo "   - Speech Padding: $(VAD_SPEECH_PAD_MS)ms"; \
		echo "   - Window Size: $(VAD_WINDOW_SIZE_SAMPLES) samples"; \
		echo "   - Return Seconds: $(VAD_RETURN_SECONDS)"; \
	fi
	@echo ""
	docker run -it --rm \
		--device /dev/snd \
		--group-add audio \
		-e PULSE_SERVER=/mnt/wslg/PulseServer \
		-e ALSA_PCM_CARD=default \
		-e ALSA_PCM_DEVICE=0 \
		-v /mnt/wslg:/mnt/wslg \
		-v $$(pwd):/output \
		--network host \
		whisperlive-client \
		python run_client.py --server localhost --port 9090 --model large-v3 \
			--vad_threshold $(VAD_THRESHOLD) \
			$(if $(VAD_NEG_THRESHOLD),--vad_neg_threshold $(VAD_NEG_THRESHOLD),) \
			--vad_min_speech_duration_ms $(VAD_MIN_SPEECH_DURATION_MS) \
			--vad_max_speech_duration_s $(VAD_MAX_SPEECH_DURATION_S) \
			--vad_min_silence_duration_ms $(VAD_MIN_SILENCE_DURATION_MS) \
			--vad_speech_pad_ms $(VAD_SPEECH_PAD_MS) \
			--vad_window_size_samples $(VAD_WINDOW_SIZE_SAMPLES) \
			$(if $(filter true,$(VAD_RETURN_SECONDS)),--vad_return_seconds,) \
			--log_dir $(LOG_DIR) \
			$(if $(filter true,$(DISABLE_JSON_LOG)),--disable_json_log,) \
			$(if $(filter true,$(DISABLE_TEXT_LOG)),--disable_text_log,) \
			$(if $(filter true,$(LOG_VERBOSE)),--log_verbose,) \
			$(if $(filter true,$(DISABLE_LOGGING)),--disable_logging,) \
			$(ARGS)

stop:
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║                      Stopping WhisperLive                     ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "🛑 Stopping server containers..."
	@docker stop whisperlive-server-gpu 2>/dev/null || true
	@docker rm whisperlive-server-gpu 2>/dev/null || true
	@echo "🛑 Stopping client containers..."
	@docker stop $$(docker ps -q --filter ancestor=whisperlive-client) 2>/dev/null || true
	@docker rm $$(docker ps -aq --filter ancestor=whisperlive-client) 2>/dev/null || true
	@docker stop $$(docker ps -q --filter ancestor=whisperlive-gpu) 2>/dev/null || true  
	@docker rm $$(docker ps -aq --filter ancestor=whisperlive-gpu) 2>/dev/null || true
	@echo "🧹 Cleaning up containers..."
	@docker container prune -f 2>/dev/null || true
	@echo "✅ All WhisperLive containers stopped and cleaned"
	@echo "📦 Note: Model cache volumes are preserved for faster restarts"

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