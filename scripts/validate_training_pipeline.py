#!/usr/bin/env python3
"""Validate training/agent pipeline wiring and JSONL integrity."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parent.parent


def load_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def validate_jsonl(path: Path) -> list[str]:
    issues: list[str] = []
    if not path.exists():
        issues.append(f"Missing JSONL file: {path}")
        return issues

    with path.open("r", encoding="utf-8") as f:
        for idx, line in enumerate(f, start=1):
            stripped = line.strip()
            if not stripped:
                continue
            try:
                json.loads(stripped)
            except json.JSONDecodeError as exc:
                issues.append(f"Invalid JSONL in {path}:{idx} -> {exc.msg}")
                break
    return issues


def validate_training_queues(include_paused: bool) -> list[str]:
    issues: list[str] = []
    queue_files = [
        ROOT / "training" / "queue" / "nightly_jobs.json",
        ROOT / "training" / "queue" / "agent_team_bootstrap_jobs.json",
    ]

    for queue_path in queue_files:
        payload = load_json(queue_path)
        for i, job in enumerate(payload.get("jobs", []), start=1):
            enabled = bool(job.get("enabled", True))
            if (not include_paused) and (not enabled):
                continue
            kind = str(job.get("kind", "llm_train"))
            if kind == "llm_train":
                project = job.get("project")
                task = job.get("task")
                if not project or not task:
                    issues.append(f"Invalid queue job (missing project/task): {queue_path} index={i}")
                    continue
                data_path = ROOT / "training" / str(project) / "data" / f"{task}.jsonl"
                if not data_path.exists():
                    if project == "billwatch" and task == "summarization":
                        data_path = ROOT / "training" / "billwatch" / "data" / "bill_summaries.jsonl"
                issues.extend(validate_jsonl(data_path))
                continue

            if kind == "agent_benchmark":
                if not job.get("team"):
                    issues.append(f"Agent benchmark job missing team: {queue_path} index={i}")
                if not job.get("output_json"):
                    issues.append(f"Agent benchmark job missing output_json: {queue_path} index={i}")
                continue

            if kind == "agent_run":
                team = job.get("team")
                objective = job.get("objective")
                if team not in {"test-automation", "gitlark-memdiff"}:
                    issues.append(f"Agent run job has unsupported team '{team}': {queue_path} index={i}")
                if not objective:
                    issues.append(f"Agent run job missing objective: {queue_path} index={i}")
                if not job.get("output_json"):
                    issues.append(f"Agent run job missing output_json: {queue_path} index={i}")
                if team == "test-automation":
                    for key in ["app_stack", "test_framework", "scope"]:
                        if not job.get(key):
                            issues.append(f"Agent run job missing {key}: {queue_path} index={i}")
                if team == "gitlark-memdiff":
                    for key in ["query_type", "freshness_sla_minutes", "repo_scope"]:
                        if job.get(key) in (None, ""):
                            issues.append(f"Agent run job missing {key}: {queue_path} index={i}")
                continue

            if kind == "agent_promote":
                required = ["benchmark_report", "thresholds", "output_json", "rollout_json", "queue_json"]
                missing = [key for key in required if not job.get(key)]
                if missing:
                    issues.append(
                        f"Agent promote job missing {', '.join(missing)}: {queue_path} index={i}"
                    )
                continue

            issues.append(f"Unsupported queue job kind '{kind}': {queue_path} index={i}")

    return issues


def validate_agent_registry() -> list[str]:
    issues: list[str] = []
    thresholds = load_json(ROOT / "configs" / "agent_team_promotion_thresholds.json")
    mapping = load_json(ROOT / "configs" / "agent_team_queue_mapping.json")
    rollout = load_json(ROOT / "configs" / "agent_team_rollout.json")

    teams = sorted(set(thresholds.keys()))
    for team in teams:
        if team not in mapping:
            issues.append(f"Missing team in queue mapping: {team}")
        if team not in rollout.get("teams", {}):
            issues.append(f"Missing team in rollout state: {team}")

    benchmark_map = {
        "test-automation": ROOT / "agents" / "autonomous" / "benchmarks" / "test_automation_cases.json",
        "gitlark-memdiff": ROOT / "agents" / "autonomous" / "benchmarks" / "gitlark_memdiff_cases.json",
    }
    for team in teams:
        benchmark_path = benchmark_map.get(team)
        if benchmark_path is None:
            issues.append(f"No benchmark mapping configured for team: {team}")
            continue
        if not benchmark_path.exists():
            issues.append(f"Missing benchmark file for team {team}: {benchmark_path}")

    return issues


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate Shrike AI Lab training/agent pipeline")
    parser.add_argument(
        "--include-paused",
        action="store_true",
        help="Also validate JSONL for paused/disabled queue jobs",
    )
    args = parser.parse_args()

    issues = []
    issues.extend(validate_training_queues(include_paused=bool(args.include_paused)))
    issues.extend(validate_agent_registry())

    payload = {
        "ok": len(issues) == 0,
        "issue_count": len(issues),
        "issues": issues,
    }
    print(json.dumps(payload, indent=2))
    return 0 if not issues else 2


if __name__ == "__main__":
    raise SystemExit(main())
