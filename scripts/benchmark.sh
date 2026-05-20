#!/bin/bash
# ===========================================
# Shrike AI Lab - Hardware Benchmark Script
# ===========================================
# Tests your GPU/RAM performance with different models
# Run after setup.sh to understand your hardware limits
#
# Usage: ./scripts/benchmark.sh
# ===========================================

set -e

echo "🦅 Shrike AI Lab - Hardware Benchmark"
echo "======================================"
echo ""

# Check Ollama is running
if ! curl -s http://localhost:11434/api/tags > /dev/null 2>&1; then
    echo "❌ Ollama not running. Start with: docker-compose up -d"
    exit 1
fi

# Get GPU info
echo "Hardware Info:"
echo "--------------"
if command -v nvidia-smi &> /dev/null; then
    nvidia-smi --query-gpu=name,memory.total,memory.free --format=csv,noheader
fi
echo "System RAM: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}' || echo 'N/A')"
echo ""

# Benchmark function
benchmark_model() {
    local model=$1
    local prompt=$2
    local description=$3
    
    echo "Testing: $model ($description)"
    echo "  Prompt: \"$prompt\""
    
    # Time the request
    start_time=$(date +%s.%N)
    
    response=$(curl -s http://localhost:11434/api/generate -d "{
        \"model\": \"$model\",
        \"prompt\": \"$prompt\",
        \"stream\": false
    }" 2>/dev/null)
    
    end_time=$(date +%s.%N)
    duration=$(echo "$end_time - $start_time" | bc)
    
    # Extract metrics
    eval_count=$(echo "$response" | jq -r '.eval_count // 0')
    eval_duration=$(echo "$response" | jq -r '.eval_duration // 0')
    
    if [ "$eval_duration" -gt 0 ]; then
        tokens_per_sec=$(echo "scale=2; $eval_count / ($eval_duration / 1000000000)" | bc)
    else
        tokens_per_sec="N/A"
    fi
    
    echo "  Total time: ${duration}s"
    echo "  Tokens generated: $eval_count"
    echo "  Speed: ${tokens_per_sec} tokens/sec"
    echo ""
}

# ===========================================
# Benchmark Tests
# ===========================================

echo "Running Benchmarks..."
echo "===================="
echo ""

# Quick generation test
echo "1. Quick Generation (short response)"
echo "-------------------------------------"
benchmark_model "phi3:mini" "What is 2+2? Answer in one word." "Phi-3 Mini - Fast model"
benchmark_model "mistral:7b-instruct" "What is 2+2? Answer in one word." "Mistral 7B"
benchmark_model "codellama:7b-instruct" "What is 2+2? Answer in one word." "CodeLlama 7B"
echo ""

# Code generation test (SpecPilot use case)
echo "2. Code Generation (SpecPilot use case)"
echo "---------------------------------------"
code_prompt="Write a Python function to click a button with Playwright. Keep it under 5 lines."
benchmark_model "codellama:7b-instruct" "$code_prompt" "CodeLlama 7B - Primary SpecPilot model"
echo ""

# Selector optimization test
echo "3. Selector Analysis (SpecPilot use case)"
echo "-----------------------------------------"
selector_prompt="Given this HTML: <button class=\"btn-primary submit-form\" data-testid=\"login-btn\">Login</button>, suggest the most reliable CSS selector and explain why in 2 sentences."
benchmark_model "codellama:7b-instruct" "$selector_prompt" "CodeLlama 7B"
echo ""

# Memory check
echo "4. Memory Usage"
echo "---------------"
if command -v nvidia-smi &> /dev/null; then
    echo "GPU Memory after tests:"
    nvidia-smi --query-gpu=memory.used,memory.free --format=csv,noheader
fi
echo ""

# Summary
echo "=========================================="
echo "Benchmark Summary"
echo "=========================================="
echo ""
echo "For SpecPilot (UI test automation):"
echo "  - Use codellama:7b-instruct for selector optimization"
echo "  - Target: >10 tokens/sec for responsive UX"
echo "  - If slower, reduce context length or use phi3:mini"
echo ""
echo "For complex analysis:"
echo "  - Use mistral:7b-instruct"
echo "  - Falls back to Claude API if needed"
echo ""
echo "Your hardware recommendations:"
if command -v nvidia-smi &> /dev/null; then
    vram=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ "$vram" -ge 10000 ]; then
        echo "  ✅ 11GB+ VRAM: Can run 13B models efficiently"
    elif [ "$vram" -ge 7000 ]; then
        echo "  ✅ 8GB VRAM: Optimal for 7B models"
        echo "  ⚠️  13B models will use CPU offload (slower)"
    else
        echo "  ⚠️  <8GB VRAM: Stick to phi3:mini or 7B quantized"
    fi
fi
echo ""
