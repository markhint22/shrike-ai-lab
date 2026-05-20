# Copilot Instructions for Shrike AI Lab

## Project Context

Shrike AI Lab is local LLM infrastructure for Shrike Labs development. It provides Ollama for local inference, LiteLLM for API routing, and training tools for SpecPilot.

## Owner

**Shrike Labs LLC** - Contact: mark@shrikelabsllc.com

## Tech Stack

| Component | Technology |
|-----------|------------|
| **LLM Engine** | Ollama |
| **API Proxy** | LiteLLM |
| **Training** | Unsloth, QLoRA |
| **Agents** | OpenHands, CrewAI |
| **Container** | Docker, NVIDIA Container Toolkit |

## Directory Structure

```
shrike-ai-lab/
├── docker-compose.yml      # Main services
├── configs/                # Configuration files
├── training/specpilot/     # SpecPilot training
├── agents/autonomous/      # Agent frameworks
├── tests/                  # Test suite
└── scripts/                # Utility scripts
```

## Development Guidelines

### Running Commands
```bash
make setup      # Initial setup
make start      # Start services
make test       # Run tests
make train      # Fine-tune model
```

### Adding Training Data
Training data is in JSONL format in `training/specpilot/data/`:
- `selector_optimization.jsonl` - Selector examples
- `test_generation.jsonl` - Playwright code examples
- `failure_analysis.jsonl` - Error diagnosis examples

### Testing LLM Connection
```bash
make test-llm   # Quick connectivity test
pytest tests/   # Full test suite
```

## Key Integration Points

- **SpecPilot**: Uses LiteLLM proxy at `http://localhost:4000`
- **Models**: `specpilot-local` (CodeLlama), `claude-fallback` (API)
- **Training**: QLoRA with Unsloth for 8GB VRAM cards

## Git Workflow

Follow standard Shrike Labs branch policy:
- Feature branches from `develop`
- PRs for all changes
- Semantic commit messages
