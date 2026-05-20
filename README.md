# Shrike AI Lab 🦅

[![Tests](https://github.com/markhint22/shrike-ai-lab/actions/workflows/tests.yml/badge.svg)](https://github.com/markhint22/shrike-ai-lab/actions/workflows/tests.yml)
[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![License: Proprietary](https://img.shields.io/badge/license-proprietary-red.svg)](LICENSE)

Local LLM infrastructure for Shrike Labs development. Run AI models on your own hardware, train custom models for multiple projects, and reduce API costs by 90%.

## Features

- 🚀 **Local Inference**: Run 7B models on RTX 2080/2080 Ti
- 🔄 **Unified API**: OpenAI-compatible endpoint via LiteLLM
- 🎯 **Multi-Project Training**: SpecPilot, GitLark, BillWatch
- 🤖 **AI Agents**: Code review, documentation, autonomous coding
- 📊 **Evaluation Tools**: Compare local models vs Claude
- 💰 **Cost Savings**: ~90% reduction in API costs

## Quick Start

```bash
# Clone
git clone https://github.com/markhint22/shrike-ai-lab.git
cd shrike-ai-lab

# Setup (Windows)
./scripts/setup-windows.sh

# Or manual setup
make setup
make start

# Check status
make status
```

## Hardware Requirements

**Tested Configuration:**
- GPU: NVIDIA RTX 2080 / 2080 Ti (8-11GB VRAM)
- RAM: 64GB system memory
- Storage: 50GB+ free (for models)

**What You Can Run:**
| Model | VRAM | Speed | Use Case |
|-------|------|-------|----------|
| Phi-3 Mini | ~2GB | Fast | Quick tasks, prototyping |
| Mistral 7B | ~4GB | Good | General purpose |
| CodeLlama 7B | ~4GB | Good | **SpecPilot primary** |
| CodeLlama 13B | ~8GB | Slower | Higher quality (CPU offload) |

## Quick Start

### 1. Clone and Setup

```bash
cd ~/LocalProjects
git clone https://github.com/markhint22/shrike-ai-lab.git
cd shrike-ai-lab

# Make scripts executable
chmod +x scripts/*.sh

# Run setup (installs Docker services, pulls models)
./scripts/setup.sh
```

### 2. Verify It's Working

```bash
# Test Ollama directly
curl http://localhost:11434/api/generate -d '{
  "model": "codellama:7b-instruct",
  "prompt": "Write a hello world in Python",
  "stream": false
}'

# Test LiteLLM proxy (OpenAI-compatible API)
curl http://localhost:4000/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-shrike-local" \
  -d '{
    "model": "specpilot-local",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### 3. Chat Interface

Open http://localhost:3000 for a ChatGPT-like UI powered by your local models.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Your Applications                        │
│  (SpecPilot, BillWatch, GitLark, etc.)                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    LiteLLM Proxy (:4000)                    │
│  Unified API - routes to local or cloud based on config    │
└─────────────────────────────────────────────────────────────┘
                    │                       │
         ┌──────────┘                       └──────────┐
         ▼                                             ▼
┌─────────────────────┐                 ┌─────────────────────┐
│   Ollama (:11434)   │                 │    Claude API       │
│   Local LLM Engine  │                 │    (Fallback)       │
│   - CodeLlama 7B    │                 │                     │
│   - Mistral 7B      │                 │                     │
│   - Phi-3           │                 │                     │
└─────────────────────┘                 └─────────────────────┘
         │
         ▼
┌─────────────────────┐
│   Your RTX 2080     │
│   64GB RAM          │
└─────────────────────┘
```

## Directory Structure

```
shrike-ai-lab/
├── docker-compose.yml      # Main services (Ollama, LiteLLM, WebUI)
├── configs/
│   └── litellm_config.yaml # Model routing configuration
├── models/                 # Downloaded models (gitignored)
├── training/
│   └── specpilot/          # SpecPilot fine-tuning
│       ├── data/           # Training examples
│       ├── finetune.py     # QLoRA training script
│       └── README.md       # Training guide
├── agents/
│   └── autonomous/         # OpenHands, CrewAI setup
├── scripts/
│   ├── setup.sh            # Initial setup
│   └── benchmark.sh        # Test your hardware
└── README.md
```

## Integration with SpecPilot

### Option 1: Direct Replacement

Update SpecPilot to use local LLM instead of Claude:

```python
# In test-automation-agent/backend/app/services/llm_service.py

# Before (Claude API)
# client = anthropic.Anthropic(api_key=os.environ["ANTHROPIC_API_KEY"])

# After (Local via LiteLLM)
from openai import OpenAI
client = OpenAI(
    base_url="http://localhost:4000",
    api_key="sk-shrike-local"
)

response = client.chat.completions.create(
    model="specpilot-local",  # Routes to CodeLlama 7B
    messages=[{"role": "user", "content": prompt}]
)
```

### Option 2: Hybrid (Recommended)

Use local for simple tasks, Claude for complex:

```python
def get_completion(prompt: str, complexity: str = "simple"):
    model = "specpilot-local" if complexity == "simple" else "claude-fallback"
    # ... rest of code
```

## Training Custom Models

### Collect Training Data

As you use SpecPilot, save successful interactions:

```python
# In SpecPilot, after successful selector optimization:
training_example = {
    "html": element_html,
    "bad_selector": original_selector,
    "good_selector": optimized_selector,
    "reason": "More stable pattern"
}
# Append to training/specpilot/data/selector_optimization.jsonl
```

### Fine-tune

```bash
cd training/specpilot
pip install unsloth transformers datasets peft

# Fine-tune on your collected data
python finetune.py --data data/selector_optimization.jsonl --epochs 3
```

### Deploy Fine-tuned Model

```bash
# Export to Ollama format
python export_to_ollama.py --checkpoint checkpoints/final

# Update litellm_config.yaml to use your model
# model: ollama/specpilot-finetuned
```

## Autonomous Agents

### OpenHands (Devin Alternative)

```bash
# Start OpenHands
docker-compose -f agents/autonomous/docker-compose.openhands.yml up -d

# Access at http://localhost:3001
# Give it tasks like: "Add error handling to SpecPilot's executor.py"
```

### CrewAI (Multi-Agent)

```bash
cd agents/autonomous
pip install -r requirements.txt

# Run a crew of specialized agents
python crewai_config.py "Analyze SpecPilot test failures and suggest improvements"
```

## Benchmarking

Test your hardware performance:

```bash
./scripts/benchmark.sh
```

Expected results for RTX 2080:
- Phi-3 Mini: ~30-40 tokens/sec
- CodeLlama 7B: ~15-25 tokens/sec
- CodeLlama 13B: ~5-10 tokens/sec (with CPU offload)

## Troubleshooting

### "CUDA out of memory"

Reduce batch size or use smaller model:
```bash
# Use quantized model
docker exec shrike-ollama ollama pull codellama:7b-instruct-q4_0
```

### "Connection refused" to Ollama

```bash
# Check if Ollama is running
docker ps | grep ollama

# Restart if needed
docker-compose restart ollama
```

### Slow inference

- Check GPU utilization: `nvidia-smi`
- Ensure Docker has GPU access
- Consider using smaller context length

## Cost Comparison

| Task | Claude API | Local (RTX 2080) |
|------|------------|------------------|
| 1000 selector optimizations | ~$2-5 | $0 (electricity only) |
| Fine-tuning on 10k examples | N/A | $0 + ~4 hours |
| 24/7 autonomous agent | ~$50-100/day | $0.50/day electricity |

## Next Steps

1. **Run setup**: `./scripts/setup.sh`
2. **Benchmark**: `./scripts/benchmark.sh`
3. **Integrate SpecPilot**: Update LLM service to use `http://localhost:4000`
4. **Collect training data**: Log successful SpecPilot interactions
5. **Fine-tune**: Train model on your data
6. **Experiment**: Try autonomous agents on safe tasks

## Resources

- [Ollama Documentation](https://ollama.ai/docs)
- [LiteLLM Documentation](https://docs.litellm.ai/)
- [OpenHands](https://github.com/All-Hands-AI/OpenHands)
- [CrewAI](https://docs.crewai.com/)
- [Unsloth Fine-tuning](https://github.com/unslothai/unsloth)

---

**Shrike Labs LLC** - Building intelligent software that matters.
