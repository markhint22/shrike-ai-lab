# Autonomous Agents Setup

This directory contains configuration for running autonomous coding agents locally.

## Available Frameworks

### 1. OpenHands (Recommended)
Open-source alternative to Devin. Runs autonomous coding tasks.

```bash
# Start OpenHands with local LLM
docker run -it \
  -e LLM_MODEL="ollama/codellama:7b-instruct" \
  -e LLM_API_BASE="http://host.docker.internal:11434" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 3001:3000 \
  ghcr.io/all-hands-ai/openhands:main
```

Access at: http://localhost:3001

### 2. CrewAI
Multi-agent orchestration framework. Define specialized agents that work together.

```bash
cd crewai
pip install -r requirements.txt
python run_crew.py "Analyze the SpecPilot codebase and suggest improvements"
```

### 3. AutoGen (Microsoft)
Multi-agent conversations with code execution.

```bash
pip install pyautogen
python autogen_example.py
```

## Using with Local LLMs

All frameworks configured to use:
- **Primary**: Local Ollama (codellama:7b-instruct)
- **Fallback**: Claude API (when local can't handle complexity)

Connection via LiteLLM proxy at `http://localhost:4000`

## New Team Workflows

Two implementation-focused teams are now scaffolded in this repository:

1. Test Automation Team
- File: `agents/autonomous/test_automation_team.py`
- Purpose: Assess testability, plan suites, and build Playwright-oriented outputs.

2. GitLark Memdiff Efficiency Team
- File: `agents/autonomous/gitlark_memdiff_team.py`
- Purpose: Improve cache-vs-refresh policy for memdiff workflows.

Run either team with the unified runner:

```bash
# Dry-run (no LLM calls)
python scripts/run_agent_teams.py \
  --team test-automation \
  --objective "Assess and build a reliable login + checkout test suite" \
  --mode dry-run

python scripts/run_agent_teams.py \
  --team gitlark-memdiff \
  --objective "Reduce memdiff latency while preserving freshness" \
  --mode dry-run

# LLM mode (CrewAI + LiteLLM/Ollama)
python scripts/run_agent_teams.py \
  --team test-automation \
  --objective "Generate p0 smoke suite plan" \
  --mode llm

# Materialize suggested artifact files into a working folder
python scripts/run_agent_teams.py \
  --team gitlark-memdiff \
  --objective "Reduce memdiff cost while preserving freshness" \
  --mode dry-run \
  --materialize-dir training/logs/interventions/memdiff-team-output
```

Outputs are normalized JSON with fields: `summary`, `actions`, `artifacts`, `metrics`, and `notes`.

## Team Benchmarking

Offline benchmark cases are stored here:

- `agents/autonomous/benchmarks/test_automation_cases.json`
- `agents/autonomous/benchmarks/gitlark_memdiff_cases.json`

Run benchmark evaluation:

```bash
# Evaluate both teams in dry-run mode and write scorecard JSON
python scripts/evaluate_agent_teams.py --team all --mode dry-run

# Evaluate only memdiff team with custom pass threshold
python scripts/evaluate_agent_teams.py --team gitlark-memdiff --mode dry-run --pass-threshold 0.75
```

Default report output:

- `training/logs/interventions/agent-team-benchmark.json`

Promotion decisions and intervention tickets:

```bash
python scripts/decide_agent_team_promotion.py \
  --benchmark-report training/logs/interventions/agent-team-benchmark.json \
  --thresholds configs/agent_team_promotion_thresholds.json \
  --hold-streak-limit 3 \
  --auto-apply

# Auto-apply writes these files:
# - configs/agent_team_rollout.json
# - training/queue/agent_team_promotions.json
# Repeated HOLD decisions auto-pause a team and require intervention.
```

Bootstrap team-focused initial training queue:

```bash
# Starts immediately if queue is free; otherwise writes pending launch metadata
python scripts/start_agent_team_bootstrap.py \
  --python .venv/Scripts/python.exe \
  --jobs-file training/queue/agent_team_bootstrap_jobs.json \
  --max-hours 6
```

Main CLI equivalents:

```bash
shrike-ai agents run test-automation "Assess and build p0 suite" --mode dry-run
shrike-ai agents run gitlark-memdiff "Optimize memdiff freshness policy" --mode dry-run
shrike-ai agents benchmark --team all --mode dry-run --pass-threshold 0.7
shrike-ai agents promote --benchmark-report training/logs/interventions/agent-team-benchmark.json --thresholds configs/agent_team_promotion_thresholds.json
shrike-ai agents bootstrap-train --jobs-file training/queue/agent_team_bootstrap_jobs.json --max-hours 6

# Auto-watch current queue and launch bootstrap as soon as it is free
shrike-ai agents bootstrap-watch --jobs-file training/queue/agent_team_bootstrap_jobs.json --max-hours 6 --poll-seconds 30

# Resume paused teams after human intervention
shrike-ai agents resume --team test-automation --reason "Updated prompts and benchmark cases"
shrike-ai agents resume --all --reason "Policy reset after tuning pass"

# Validate pipeline wiring before adding/changing teams
shrike-ai agents validate-pipeline
shrike-ai agents validate-pipeline --include-paused
```

## Reporting Format (Agent vs LLM)

Use this split in operational summaries to avoid ambiguity:

- Agent workflows: `agents run`, `agents benchmark`, `agents promote`, rollout/resume state.
- LLM trainings: queue jobs from `training/queue/*.json` executed by `scripts/train_queue.py`.

For each item, report:

`[name]: [Agent|LLM] | [Running|Paused] | previous gate [HOLD|PROMOTED|N/A]`

This keeps team automation status separate from model fine-tuning status.

## Resource Usage

Running autonomous agents is resource-intensive:
- Expect 6-8GB VRAM usage
- CPU will spike during inference
- Allow 30-60 seconds per agent response

For complex tasks, consider using Claude API fallback.

## Safety

⚠️ Autonomous agents can execute code. Be careful:
- Run in isolated Docker containers
- Don't give access to production credentials
- Review proposed changes before applying
- Use sandboxed environments for testing
