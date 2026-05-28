# Agent Team Implementation Plan

## Goal
Build two production-oriented agent teams in shrike-ai-lab:

1. Test Automation Team
- Assess application testability and current coverage.
- Propose and build Playwright test plans and concrete test code.
- Analyze failures and generate remediation actions.

2. GitLark Memdiff Efficiency Team
- Improve freshness-vs-cost decisions when resolving memdiff requests.
- Reduce unnecessary full-repo scans and stale-cache misses.
- Produce measurable gains in latency, token usage, and hit quality.

## Constraints
- Hybrid model strategy: local models for most analysis/generation, Claude only for high-complexity final reasoning.
- Cost control first: prioritize offline/local iteration and deterministic evaluation.
- Reuse existing training/eval stack (queue, AB gates, intervention board) where possible.

## Architecture

### Shared Team Pattern
Each team uses four roles:
- Assessor: evaluates current state and gaps.
- Planner: produces prioritized execution plan.
- Builder/Optimizer: generates implementation artifacts.
- Reviewer: validates output quality and risk.

Execution modes:
- Dry-run mode: returns a structured plan without LLM calls.
- LLM mode: runs CrewAI agents through LiteLLM/Ollama aliases.

Output contract (both teams):
- summary: concise status and recommendation.
- actions: ordered, actionable steps.
- artifacts: generated files/snippets/checklists.
- metrics: suggested KPIs and pass/fail criteria.

## Team 1: Test Automation Team

### Mission
Increase successful automated test creation rate and reduce flaky failures.

### Agent Responsibilities
- Testability Assessor
  - Inputs: app URL/scope, existing tests, framework constraints.
  - Outputs: testability score, risk map, missing observability.
- Coverage Planner
  - Outputs: smoke/regression/p0 matrix and rollout sequence.
- Test Builder
  - Outputs: Playwright test specs, selectors, fixtures, and assertions.
- Failure Reviewer
  - Outputs: likely flake causes, stabilization changes, retry policy.

### Initial Deliverables (Phase 1)
- Structured assessment template.
- Test plan template with risk-tiered suite strategy.
- Starter test generation prompt package.
- Failure triage checklist and fix suggestion format.

### Metrics
- Test generation acceptance rate.
- First-run pass rate.
- Flake rate over N reruns.
- Mean time to diagnose failure.

## Team 2: GitLark Memdiff Efficiency Team

### Mission
Improve cache-vs-fresh pull decision quality for repository memory operations.

### Agent Responsibilities
- Context Assessor
  - Classifies query intent (structure, code semantics, freshness-sensitive, metadata).
- Policy Planner
  - Chooses cache-read, selective-refresh, or full-refresh strategy.
- Memdiff Optimizer
  - Generates decision rationale and suggested fetch scope.
- Outcome Reviewer
  - Scores decision quality and suggests policy updates.

### Initial Deliverables (Phase 1)
- Memdiff decision rubric (cache/stale/fresh thresholds).
- Query-to-scope mapping (file-level, subtree-level, repo-level).
- Efficiency recommendation payload format.
- KPI schema for latency, token cost, and correctness proxy.

### Metrics
- Cache hit ratio.
- Freshness miss rate.
- Median response latency.
- Tokens per successful answer.

## Implementation Phases

### Phase 0 (Now)
- Add team scaffolding code in `agents/autonomous/`.
- Add runner script in `scripts/`.
- Add docs for usage and dry-run behavior.

### Phase 1
- Wire CrewAI task graphs for both teams.
- Add deterministic dry-run outputs for CI/unit checks.
- Add minimal integration tests for output schema.

### Phase 2
- Add offline benchmark inputs for both teams.
- Add scorecards and promotion thresholds.
- Add optional AB gate hooks for team-level policy changes.

### Phase 3
- Add Claude escalation gate (small eval set only).
- Production route: local-first, Claude-on-demand.
- Add cost guardrails and regression alerts.

## Definition of Done for Initial Build
- Team modules exist and can run in dry-run mode.
- Team runner CLI can invoke either team.
- Output schema is stable and documented.
- User can execute with one command from repo root.

## Immediate Next Steps
1. Scaffold team modules and orchestrator.
2. Add dry-run output contracts and examples.
3. Add usage docs and command examples.
4. Add first integration smoke test.

## Commands Implemented

### Direct scripts
- `python scripts/run_agent_teams.py --team test-automation --objective "..." --mode dry-run`
- `python scripts/run_agent_teams.py --team gitlark-memdiff --objective "..." --mode dry-run`
- `python scripts/evaluate_agent_teams.py --team all --mode dry-run`

### Main CLI
- `shrike-ai agents run test-automation "Assess and build p0 suite" --mode dry-run`
- `shrike-ai agents run gitlark-memdiff "Optimize memdiff freshness policy" --mode dry-run`
- `shrike-ai agents benchmark --team all --mode dry-run --pass-threshold 0.7`

## Initial Agent Training Workflow (Implemented)

1. Run team workflows and materialize artifacts
- `shrike-ai agents run test-automation "..." --mode dry-run --materialize-dir training/logs/interventions/test-automation-team-output`
- `shrike-ai agents run gitlark-memdiff "..." --mode dry-run --materialize-dir training/logs/interventions/memdiff-team-output`

2. Benchmark both teams
- `shrike-ai agents benchmark --team all --mode dry-run --pass-threshold 0.7`

3. Produce GO/HOLD promotion decisions + intervention tickets
- `shrike-ai agents promote --benchmark-report training/logs/interventions/agent-team-benchmark.json --thresholds configs/agent_team_promotion_thresholds.json`

4. Launch bootstrap model-training queue for team-relevant skills
- `shrike-ai agents bootstrap-train --jobs-file training/queue/agent_team_bootstrap_jobs.json --max-hours 6`

If queue is busy, bootstrap command writes pending launch metadata:
- `training/logs/interventions/agent-team-bootstrap-pending.json`
