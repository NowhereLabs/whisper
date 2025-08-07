#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     WhisperLive Cache Status                  ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

echo "📦 Docker Volumes (Model Cache):"
echo "----------------------------------------"

# Check if volumes exist and their sizes
for volume in whisper-models huggingface-models openvino-models; do
    if docker volume inspect $volume &>/dev/null; then
        echo "✅ $volume: exists"
        # Get volume mountpoint and check size
        mountpoint=$(docker volume inspect $volume --format '{{.Mountpoint}}' 2>/dev/null)
        if [ -n "$mountpoint" ] && [ -d "$mountpoint" ]; then
            size=$(sudo du -sh "$mountpoint" 2>/dev/null | cut -f1 || echo "unknown")
            echo "   📁 Size: $size"
            echo "   📍 Path: $mountpoint"
        fi
    else
        echo "❌ $volume: not created yet"
    fi
    echo ""
done

echo "🗂️  Cache Directory Contents:"
echo "----------------------------------------"

# Check what's in the volumes by running a temporary container
for volume in whisper-models huggingface-models openvino-models; do
    if docker volume inspect $volume &>/dev/null; then
        echo "📂 Contents of $volume:"
        docker run --rm -v $volume:/cache alpine:latest find /cache -type f -name "*.bin" -o -name "*.safetensors" -o -name "*.onnx" -o -name "*.pt" 2>/dev/null | head -5
        file_count=$(docker run --rm -v $volume:/cache alpine:latest find /cache -type f 2>/dev/null | wc -l)
        echo "   📄 Total files: $file_count"
        echo ""
    fi
done

echo "💡 Tips:"
echo "• First server start: downloads models (~2-10GB)"
echo "• Subsequent starts: uses cached models (fast!)"
echo "• Run 'make clean-cache' to remove all cached models"
echo "• Rebuilding Docker images won't affect model cache"