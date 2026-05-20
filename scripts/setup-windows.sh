#!/bin/bash
# Shrike AI Lab - Windows Setup Script
# Run this in WSL2 or Git Bash on Windows

set -e

echo "============================================"
echo "  Shrike AI Lab - Windows Setup"
echo "============================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on Windows
check_windows() {
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ -n "$WSL_DISTRO_NAME" ]]; then
        echo -e "${GREEN}✓ Windows environment detected${NC}"
    else
        echo -e "${YELLOW}⚠ This script is designed for Windows. You may need to adapt commands.${NC}"
    fi
}

# Check NVIDIA GPU
check_gpu() {
    echo ""
    echo "Checking NVIDIA GPU..."
    
    if command -v nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓ NVIDIA driver detected${NC}"
        nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv
    else
        echo -e "${RED}✗ NVIDIA driver not found${NC}"
        echo "  Install from: https://www.nvidia.com/Download/index.aspx"
        exit 1
    fi
}

# Check Docker
check_docker() {
    echo ""
    echo "Checking Docker..."
    
    if command -v docker &> /dev/null; then
        echo -e "${GREEN}✓ Docker installed${NC}"
        docker --version
    else
        echo -e "${RED}✗ Docker not found${NC}"
        echo "  Install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
        exit 1
    fi
    
    # Check Docker daemon
    if docker info &> /dev/null; then
        echo -e "${GREEN}✓ Docker daemon running${NC}"
    else
        echo -e "${RED}✗ Docker daemon not running${NC}"
        echo "  Start Docker Desktop and try again"
        exit 1
    fi
}

# Check NVIDIA Container Toolkit
check_nvidia_docker() {
    echo ""
    echo "Checking NVIDIA Container Toolkit..."
    
    if docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi &> /dev/null; then
        echo -e "${GREEN}✓ NVIDIA Container Toolkit working${NC}"
    else
        echo -e "${YELLOW}⚠ NVIDIA Container Toolkit not configured${NC}"
        echo ""
        echo "To install NVIDIA Container Toolkit:"
        echo "1. Enable WSL2 GPU support in Docker Desktop settings"
        echo "2. Or install manually: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
        echo ""
        read -p "Continue anyway? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check Python
check_python() {
    echo ""
    echo "Checking Python..."
    
    if command -v python3 &> /dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
        echo -e "${GREEN}✓ Python $PYTHON_VERSION found${NC}"
    else
        echo -e "${RED}✗ Python 3 not found${NC}"
        echo "  Install from: https://www.python.org/downloads/"
        exit 1
    fi
}

# Create virtual environment
setup_venv() {
    echo ""
    echo "Setting up Python virtual environment..."
    
    if [ ! -d "venv" ]; then
        python3 -m venv venv
        echo -e "${GREEN}✓ Virtual environment created${NC}"
    else
        echo -e "${GREEN}✓ Virtual environment exists${NC}"
    fi
    
    # Activate and install dependencies
    source venv/bin/activate || source venv/Scripts/activate
    pip install --upgrade pip
    pip install -r requirements.txt
    echo -e "${GREEN}✓ Dependencies installed${NC}"
}

# Pull Docker images
pull_images() {
    echo ""
    echo "Pulling Docker images (this may take a while)..."
    
    docker pull ollama/ollama:latest
    echo -e "${GREEN}✓ Ollama image pulled${NC}"
    
    docker pull ghcr.io/berriai/litellm:main-latest
    echo -e "${GREEN}✓ LiteLLM image pulled${NC}"
    
    docker pull ghcr.io/open-webui/open-webui:main
    echo -e "${GREEN}✓ Open WebUI image pulled${NC}"
}

# Start services
start_services() {
    echo ""
    echo "Starting services..."
    
    docker-compose up -d
    
    echo ""
    echo "Waiting for services to start..."
    sleep 10
    
    # Check health
    echo ""
    echo "Checking service health..."
    
    if curl -s http://localhost:11434/api/tags > /dev/null; then
        echo -e "${GREEN}✓ Ollama running on :11434${NC}"
    else
        echo -e "${RED}✗ Ollama not responding${NC}"
    fi
    
    if curl -s http://localhost:4000/health > /dev/null; then
        echo -e "${GREEN}✓ LiteLLM running on :4000${NC}"
    else
        echo -e "${RED}✗ LiteLLM not responding${NC}"
    fi
    
    if curl -s http://localhost:3000 > /dev/null; then
        echo -e "${GREEN}✓ Open WebUI running on :3000${NC}"
    else
        echo -e "${YELLOW}⚠ Open WebUI may still be starting...${NC}"
    fi
}

# Pull base models
pull_models() {
    echo ""
    echo "Pulling base models for Ollama..."
    
    # Pull CodeLlama (for code tasks)
    echo "Pulling CodeLlama 7B..."
    docker exec shrike-ollama ollama pull codellama:7b-instruct
    
    # Pull Mistral (for text tasks)
    echo "Pulling Mistral 7B..."
    docker exec shrike-ollama ollama pull mistral:7b-instruct
    
    echo -e "${GREEN}✓ Base models pulled${NC}"
}

# Create .env file
create_env() {
    echo ""
    echo "Creating .env file..."
    
    if [ ! -f ".env" ]; then
        cat > .env << 'EOF'
# Shrike AI Lab Configuration

# Ollama
OLLAMA_HOST=0.0.0.0
OLLAMA_ORIGINS=*

# LiteLLM
LITELLM_MASTER_KEY=sk-shrike-local

# Anthropic API (for Claude fallback)
# Get key from: https://console.anthropic.com/
ANTHROPIC_API_KEY=

# OpenAI API (optional)
# OPENAI_API_KEY=

# Network (for remote access)
# Set to your Windows PC's IP on your local network
HOST_IP=localhost
EOF
        echo -e "${GREEN}✓ .env file created${NC}"
        echo -e "${YELLOW}  Edit .env to add your Anthropic API key for Claude fallback${NC}"
    else
        echo -e "${GREEN}✓ .env file exists${NC}"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo "============================================"
    echo "  Setup Complete!"
    echo "============================================"
    echo ""
    echo "Services:"
    echo "  • Ollama:     http://localhost:11434"
    echo "  • LiteLLM:    http://localhost:4000"
    echo "  • Open WebUI: http://localhost:3000"
    echo ""
    echo "Next steps:"
    echo "  1. Edit .env and add your ANTHROPIC_API_KEY"
    echo "  2. Test connection: make test-llm"
    echo "  3. List available tasks: make train-list"
    echo "  4. Start training: make train-specpilot-selector"
    echo ""
    echo "For remote access from Mac/Railway:"
    echo "  1. Find your PC's IP: ipconfig (look for IPv4)"
    echo "  2. Update .env: HOST_IP=192.168.x.x"
    echo "  3. Use http://192.168.x.x:4000 as LLM_BASE_URL"
    echo ""
    echo "Documentation:"
    echo "  • SpecPilot: docs/integrations/SPECPILOT_INTEGRATION.md"
    echo "  • GitLark:   docs/integrations/GITLARK_INTEGRATION.md"
    echo "  • BillWatch: docs/integrations/BILLWATCH_INTEGRATION.md"
    echo ""
}

# Main
main() {
    check_windows
    check_gpu
    check_docker
    check_nvidia_docker
    check_python
    create_env
    setup_venv
    pull_images
    start_services
    pull_models
    print_summary
}

# Run
main "$@"
