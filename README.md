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
  "model": "phi3:mini",
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
│   - Phi-3 Mini      │                 │                     │
│   - Mistral 7B      │                 │                     │
│   - CodeLlama       │                 │                     │
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
    model="specpilot-local",  # Routes to current default local model
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

### Quick Preflight (Recommended First)

```bash
# Check dependencies + data availability for all training tasks
python scripts/train.py --preflight

# See all discovered project/task combos
python scripts/train.py --list
```

If `unsloth` is unavailable on your platform, use the built-in HF fallback engine:

```bash
python scripts/train.py --project specpilot --task selector_optimization --engine hf
```

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
# Unified pipeline (preferred)
python scripts/train.py --project specpilot --task selector_optimization --engine hf

# Optional: tiny-model smoke run to validate end-to-end training quickly
python scripts/train.py \
  --project specpilot \
  --task selector_optimization \
  --engine hf \
  --base-model sshleifer/tiny-gpt2 \
  --epochs 1 \
  --batch-size 1 \
  --version smoke

# Legacy project-specific trainer still available
cd training/specpilot
python finetune.py --data data/selector_optimization.jsonl --epochs 3
```

### Human Intervention Dashboard (Recommended)

Use these scripts to decide when to stop and review instead of guessing from raw logs.

```bash
# 1) Learning trend (first successful run vs latest successful run)
python scripts/eval_learning_trend.py

# 2) Intervention dashboard (review gates + recommendations)
python scripts/training_intervention_board.py

# 3) Save machine-readable report for tracking/history
python scripts/training_intervention_board.py --json-out training/logs/interventions/intervention-board.json

# 4) Live watch mode (refresh every 60s)
python scripts/training_intervention_board.py --watch --interval 60
```

### Desktop Notifications for Human Intervention

When you want an alert as soon as review is needed:

```bash
# One-shot check + alert if queue is non-empty
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ops-notify-readyreview.ps1

# Continuous watch mode (checks every 2 minutes)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ops-watch-readyreview.ps1 -IntervalSec 120 -QuietBoard

# Optional modal popup dialog (blocking) if you explicitly want it
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/ops-notify-readyreview.ps1 -UseModalDialog
```

Notification behavior:
- Uses Windows toast via BurntToast if available.
- Falls back to non-blocking console + sound if BurntToast is not installed.

### A/B Promotion Gate (Baseline vs Candidate)

After dashboard shows `READY_REVIEW`, run an A/B gate to decide `PROMOTE` or `HOLD`.

```bash
python scripts/ab_eval_gate.py \
  --project shared \
  --task code_review \
  --baseline-model phi3-local \
  --candidate-model phi3-local \
  --test-data training/gitlark/data/code_review.jsonl \
  --limit 20 \
  --json-out training/logs/ab-gate-shared-code_review.json
```

Notes:
- `--baseline-model` and `--candidate-model` are model names exposed by LiteLLM.
- Use a held-out test set whenever possible (avoid only evaluating on training examples).
- Default gate settings:
  - minimum accuracy delta: `+0.02`
  - maximum latency regression: `20%`
- If gate fails, decision is `HOLD` with reasons in the JSON report.

Dashboard recommendations:
- `READY_REVIEW`: Human review now (A/B eval + promote/hold decision)
- `WAIT_RUNNING`: Active run in progress; wait for completion
- `COLLECT_MORE_RUNS`: Not enough successful runs yet for a decision
- `INVESTIGATE_STABILITY`: Failure rate too high; fix reliability first
- `RETUNE_DATA`: Trend regressing; adjust training data/hyperparameters
- `BLOCKED`: Repeated failures and no successful completions in window

Suggested review cadence:
1. Run 2-3 successful runs per project/task.
2. Trigger review when dashboard shows `READY_REVIEW`.
3. Compare baseline vs trained on held-out tasks.
4. Promote artifacts only when no major regression is observed.

For controlled memory/performance experiments without changing global defaults:

```bash
python scripts/train.py \
  --project billwatch \
  --task classification \
  --engine hf \
  --max-seq-length 3072 \
  --version billwatch-mem-test \
  --dry-run
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

## Crash Recovery (Windows)

If your machine reboots or crashes overnight, use the built-in recovery flow:

```bash
# Restore Ollama, LiteLLM, and nightly queue
D:\LocalProjects\shrike-ai-lab\.venv\Scripts\python.exe scripts/recover_after_crash.py --skip-open-webui
```

Register automatic startup on login:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/register_windows_startup.ps1 -UseScheduledTask -UseStartupFolder
```

Notes:
- If Scheduled Task registration is denied by system policy, Startup folder fallback is still installed.
- Startup launcher path: `C:\Users\<you>\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup\ShrikeAILabRecovery.cmd`
- Recovery summaries and diagnostics are written to `training/logs/`.

## Queue Ops (Windows, No API Tokens)

Use local queue helpers to inspect and manage training queue state without any LLM calls:

```powershell
# Summary: pid/lock health, active queue/train processes, latest queue log hints
scripts\queue.cmd status

# List all jobs in nightly queue definition
scripts\queue.cmd jobs

# Tail latest queue launch log
scripts\queue.cmd tail

# Follow latest queue launch log live
scripts\queue.cmd tailf

# Tail latest per-job run log (often most detailed live output)
scripts\queue.cmd tailrun

# Follow latest per-job run log live
scripts\queue.cmd tailrunf

# Show recent failure-related lines
scripts\queue.cmd failures

# Show pid/lock ownership only
scripts\queue.cmd pids

# Remove stale pid/lock files only (safe; keeps active locks)
scripts\queue.cmd cleanup
```

Advanced usage (direct PowerShell script):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/queue_ops.ps1 -Action status
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/queue_ops.ps1 -Action tail -TailLines 120 -Follow
```

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
