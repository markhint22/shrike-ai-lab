# AGENTS.md - Shrike AI Lab Development Context

## Overview

Shrike AI Lab is local LLM infrastructure for Shrike Labs development. It provides:
- **Ollama**: Local LLM inference engine
- **LiteLLM**: Unified API proxy (routes to local or cloud)
- **Training**: QLoRA fine-tuning for SpecPilot
- **Autonomous Agents**: OpenHands, CrewAI integration

## Repository Structure

```
shrike-ai-lab/
├── docker-compose.yml          # Main services
├── configs/
│   └── litellm_config.yaml     # Model routing config
├── models/                     # Downloaded/fine-tuned models
├── training/
│   └── specpilot/              # SpecPilot training
│       ├── data/               # Training examples
│       ├── finetune.py         # QLoRA script
│       └── export_to_ollama.py # Model export
├── agents/
│   └── autonomous/             # Agent frameworks
├── tests/                      # Test suite
└── scripts/
    ├── setup.sh                # Initial setup
    └── benchmark.sh            # Hardware test
```

## Key Files

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Ollama, LiteLLM, Open WebUI services |
| `configs/litellm_config.yaml` | Model routing and fallback config |
| `training/specpilot/finetune.py` | QLoRA fine-tuning for SpecPilot |
| `training/specpilot/data/*.jsonl` | Training examples |
| `agents/autonomous/crewai_config.py` | Multi-agent setup |

## Hardware Requirements

- **GPU**: NVIDIA RTX 2080/2080 Ti (8-11GB VRAM)
- **RAM**: 64GB system memory
- **Storage**: 50GB+ for models

## Common Commands

```bash
# Setup
make setup              # Initial setup
make start              # Start services
make stop               # Stop services

# Testing
make test               # Run tests
make test-llm           # Test LLM connection
make benchmark          # Hardware benchmark

# Training
make train              # Fine-tune SpecPilot model
make export             # Export to Ollama
```

## Integration Points

### SpecPilot Integration

SpecPilot connects via LiteLLM proxy:

```python
# In test-automation-agent backend
from openai import OpenAI

client = OpenAI(
    base_url="http://localhost:4000",  # LiteLLM proxy
    api_key="sk-shrike-local"
)

response = client.chat.completions.create(
    model="specpilot-local",  # Routes to CodeLlama
    messages=[{"role": "user", "content": prompt}]
)
```

### Model Routing

LiteLLM routes based on model name:
- `specpilot-local` → Ollama CodeLlama 7B
- `mistral-local` → Ollama Mistral 7B
- `claude-fallback` → Anthropic API

## Training Data Format

### Selector Optimization
```json
{"html": "<button class='btn'>Submit</button>", "bad_selector": ".btn", "good_selector": "button:has-text('Submit')", "reason": "Text more stable"}
```

### Test Generation
```json
{"instruction": "Click login button", "playwright_code": "await page.click('[data-testid=\"login\"]')"}
```

### Failure Analysis
```json
{"error": "TimeoutError", "selector": "#loading", "diagnosis": "Element never appears", "fix": "Add explicit wait"}
```

## Development Notes

- Services run in Docker containers
- GPU access via NVIDIA Container Toolkit
- Fine-tuning uses 4-bit quantization (QLoRA)
- Models stored in Docker volumes by default

## Troubleshooting

- **CUDA OOM**: Use smaller model or reduce batch size
- **Connection refused**: Check `docker-compose ps`
- **Slow inference**: Verify GPU is being used (`nvidia-smi`)

## Contact

**Shrike Labs LLC** - mark@shrikelabsllc.com
