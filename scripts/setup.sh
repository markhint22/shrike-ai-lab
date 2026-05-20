#!/bin/bash
# ===========================================
# Shrike AI Lab - Initial Setup Script
# ===========================================
# Run this on your local PC with RTX GPU
# 
# Prerequisites:
#   - Docker with NVIDIA Container Toolkit
#   - NVIDIA drivers installed
#   - 64GB RAM, RTX 2080/2080 Ti
#
# Usage: ./scripts/setup.sh
# ===========================================

set -e

echo "🦅 Shrike AI Lab - Setup"
echo "========================"
echo ""

# Check for NVIDIA GPU
echo "1. Checking NVIDIA GPU..."
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total --format=csv,noheader
    echo "✅ NVIDIA GPU detected"
else
    echo "⚠️  nvidia-smi not found. GPU acceleration may not work."
    echo "   Install NVIDIA drivers: https://developer.nvidia.com/cuda-downloads"
fi
echo ""

# Check Docker
echo "2. Checking Docker..."
if command -v docker &> /dev/null; then
    docker --version
    echo "✅ Docker installed"
else
    echo "❌ Docker not found. Install from: https://docs.docker.com/get-docker/"
    exit 1
fi
echo ""

# Check NVIDIA Container Toolkit
echo "3. Checking NVIDIA Container Toolkit..."
if docker info 2>/dev/null | grep -q "nvidia"; then
    echo "✅ NVIDIA Container Toolkit configured"
else
    echo "⚠️  NVIDIA Container Toolkit may not be installed."
    echo "   Install: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
fi
echo ""

# Create .env file if not exists
echo "4. Creating .env file..."
if [ ! -f .env ]; then
    cat > .env << 'EOF'
# Shrike AI Lab Environment Variables
# Copy this to .env and fill in your API keys

# LiteLLM Master Key (for API authentication)
LITELLM_MASTER_KEY=sk-shrike-local

# Cloud API Keys (optional - for fallback to cloud models)
ANTHROPIC_API_KEY=
OPENAI_API_KEY=

# GPU Memory Settings (adjust based on your RTX card)
# RTX 2080: 8GB, RTX 2080 Ti: 11GB
OLLAMA_GPU_MEMORY=8GB
EOF
    echo "✅ Created .env file - edit it to add your API keys"
else
    echo "✅ .env file already exists"
fi
echo ""

# Start services
echo "5. Starting Docker services..."
docker-compose up -d
echo ""

# Wait for Ollama to be ready
echo "6. Waiting for Ollama to start..."
sleep 5
until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
    echo "   Waiting for Ollama..."
    sleep 2
done
echo "✅ Ollama is running"
echo ""

# Pull recommended models
echo "7. Pulling recommended models for RTX 2080..."
echo "   This will take a while on first run (downloading ~15GB)..."
echo ""

# Models optimized for 8-11GB VRAM
MODELS=(
    "codellama:7b-instruct"   # Primary for SpecPilot (~4GB)
    "mistral:7b-instruct"     # General purpose (~4GB)
    "phi3:mini"               # Fast, small tasks (~2GB)
)

for model in "${MODELS[@]}"; do
    echo "   Pulling $model..."
    docker exec shrike-ollama ollama pull "$model"
done
echo ""

echo "✅ Core models downloaded"
echo ""

# Optional: larger model with CPU offload
read -p "8. Pull CodeLlama 13B? (Uses CPU offload, slower but better quality) [y/N]: " pull_13b
if [[ "$pull_13b" =~ ^[Yy]$ ]]; then
    echo "   Pulling codellama:13b-instruct..."
    docker exec shrike-ollama ollama pull "codellama:13b-instruct"
fi
echo ""

# Test the setup
echo "9. Testing setup..."
echo ""
echo "   Testing Ollama directly:"
curl -s http://localhost:11434/api/generate -d '{
  "model": "phi3:mini",
  "prompt": "Say hello in one word",
  "stream": false
}' | jq -r '.response' 2>/dev/null || echo "   (jq not installed, raw output shown)"
echo ""

echo "   Testing LiteLLM proxy:"
curl -s http://localhost:4000/health | jq . 2>/dev/null || echo "   LiteLLM health check"
echo ""

echo "=========================================="
echo "🎉 Setup Complete!"
echo "=========================================="
echo ""
echo "Services running:"
echo "  - Ollama:     http://localhost:11434"
echo "  - LiteLLM:    http://localhost:4000"
echo "  - Open WebUI: http://localhost:3000"
echo ""
echo "Quick test:"
echo "  curl http://localhost:4000/chat/completions \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"model\": \"specpilot-local\", \"messages\": [{\"role\": \"user\", \"content\": \"Hello\"}]}'"
echo ""
echo "Next steps:"
echo "  1. Visit http://localhost:3000 to chat with models"
echo "  2. Run ./scripts/benchmark.sh to test your hardware"
echo "  3. See training/specpilot/README.md for fine-tuning guide"
echo ""
