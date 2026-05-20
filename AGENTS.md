# AGENTS.md - Shrike AI Lab Development Context

## Overview

Shrike AI Lab is the local LLM infrastructure for all Shrike Labs projects. It provides:
- **Ollama**: Local LLM inference engine
- **LiteLLM**: Unified API proxy (routes to local or cloud)
- **Training**: QLoRA fine-tuning for multiple projects
- **Agents**: Code review, documentation, and autonomous agents

## Repository Structure

```
shrike-ai-lab/
├── docker-compose.yml              # Main services
├── configs/
│   └── litellm_config.yaml         # Model routing config
├── models/                         # Downloaded/fine-tuned models
├── training/
│   ├── specpilot/                  # Test automation training
│   │   ├── data/                   # selector_optimization, test_generation, failure_analysis
│   │   └── finetune.py
│   ├── gitlark/                    # Code workspace training
│   │   ├── data/                   # code_explanation, pr_descriptions, code_review
│   │   └── finetune.py
│   ├── billwatch/                  # Bill summarization training
│   │   ├── data/                   # bill_summaries
│   │   └── finetune.py
│   └── shared/                     # Cross-project models
├── agents/
│   ├── autonomous/                 # OpenHands, CrewAI
│   ├── code-review/                # Universal code review agent
│   ├── gitlark/                    # GitLark-specific agents
│   └── documentation/              # Auto-documentation agent
├── scripts/
│   ├── train.py                    # Unified training pipeline
│   └── data-collection/            # Data collection scripts
├── tests/
└── docs/
    ├── integrations/               # Integration guides per project
    └── ROADMAP_YEAR1.md            # 1-year strategic roadmap
```

## Project Training Overview

| Project | Tasks | Base Model | Status |
|---------|-------|------------|--------|
| **SpecPilot** | selector_optimization, test_generation, failure_analysis | CodeLlama 7B | Scaffold ready |
| **GitLark** | code_explanation, pr_description, code_review, commit_message | CodeLlama 7B | Scaffold ready |
| **BillWatch** | summarization, classification, impact | Mistral 7B | Scaffold ready |
| **Shared** | code_review (universal) | CodeLlama 7B | Scaffold ready |

## Key Files

| File | Purpose |
|------|---------|
| `scripts/train.py` | **Unified training for all projects** |
| `docker-compose.yml` | Ollama, LiteLLM, Open WebUI services |
| `configs/litellm_config.yaml` | Model routing and fallback config |
| `agents/code-review/review_agent.py` | Universal PR review agent |
| `docs/ROADMAP_YEAR1.md` | Strategic 1-year plan |

## Hardware Requirements

- **GPU**: NVIDIA RTX 2080/2080 Ti (8-11GB VRAM)
- **RAM**: 64GB system memory
- **Storage**: 50GB+ for models

## Quick Start Commands

```bash
# Infrastructure
make setup              # Initial setup
make start              # Start services
make stop               # Stop services
make status             # Check service health

# Training (unified pipeline)
make train-list         # See available tasks
make train-gitlark-explain     # Train GitLark code explainer
make train-billwatch-summary   # Train BillWatch summarizer
make train-specpilot-selector  # Train SpecPilot selector optimizer

# Or use the script directly
python scripts/train.py --project gitlark --task code_explanation --version v1

# Data Collection
make collect-gitlark    # Extract training data from repos
make collect-billwatch  # Fetch bills from Congress.gov API

# Testing
make test               # Run all tests
make test-llm           # Test LLM connectivity
```

## Integration Points

### SpecPilot → Local LLM
```python
from openai import OpenAI
client = OpenAI(base_url="http://192.168.x.x:4000", api_key="sk-shrike-local")
response = client.chat.completions.create(model="specpilot-selector-v1", messages=[...])
```

### GitLark → Local LLM
See `docs/integrations/GITLARK_INTEGRATION.md`

### BillWatch → Local LLM
See `docs/integrations/BILLWATCH_INTEGRATION.md`

## Model Routing (LiteLLM)

| Model Name | Routes To |
|------------|-----------|
| `specpilot-*` | Ollama (local) |
| `gitlark-*` | Ollama (local) |
| `billwatch-*` | Ollama (local) |
| `claude-haiku` | Anthropic API (fallback) |
| `claude-sonnet` | Anthropic API (complex tasks) |

## Training Data Format

See project-specific README files in `training/<project>/README.md` for data formats.

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
