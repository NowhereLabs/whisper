#!/bin/bash
# Start Windows Automation Service on WSL Host
# This runs the sidecar service directly on the WSL host for PowerShell access

echo "🔧 Starting Windows Automation Service on WSL Host..."

# Check if we're in WSL
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    echo "❌ This requires WSL2 (Windows Subsystem for Linux)"
    exit 1
fi

# Check if PowerShell is available
if ! command -v powershell.exe > /dev/null 2>&1; then
    echo "❌ PowerShell not available from WSL"
    exit 1
fi

echo "✅ WSL2 environment detected"
echo "✅ PowerShell available"
echo ""

# Install Python dependencies if needed
if ! python3 -c "import flask, requests" 2>/dev/null; then
    echo "📦 Installing Python dependencies..."
    pip3 install flask requests
fi

echo "🚀 Starting Windows Automation API service on port 8080..."
echo "💡 The service will accept typing requests from Docker containers"
echo ""
echo "🎯 API Endpoints:"
echo "   GET  /health - Service health check"
echo "   POST /type   - Type text into Windows applications"
echo "   GET  /status - Service capabilities"
echo ""
echo "🛑 Press Ctrl+C to stop the service"
echo ""

# Set environment variables
export FLASK_ENV=production
export FLASK_DEBUG=false

# Run the service
cd "$(dirname "$0")/.."
python3 utils/windows_sidecar.py