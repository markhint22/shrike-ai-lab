#!/usr/bin/env python3
"""Start or stage bootstrap training queue for agent teams."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from log_layout import queue_lock_file, queue_pid_file


def process_exists(pid: int) -> bool:
    result = subprocess.run(
        ["tasklist", "/FI", f"PID eq {pid}"],
        check=False,
        capture_output=True,
        text=True,
    )
    return str(pid) in (result.stdout or "")


def read_alive_pid(path: Path) -> int | None:
    if not path.exists():
        return None
    try:
        value = int(path.read_text(encoding="ascii").strip())
    except Exception:
        return None
    return value if process_exists(value) else None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Start/stage agent team bootstrap queue")
    parser.add_argument(
        "--python",
        default=sys.executable,
        help="Python executable",
    )
    parser.add_argument(
        "--jobs-file",
        default="training/queue/agent_team_bootstrap_jobs.json",
        help="Bootstrap jobs file",
    )
    parser.add_argument(
        "--max-hours",
        type=float,
        default=6.0,
        help="Max runtime hours for bootstrap queue",
    )
    parser.add_argument(
        "--pending-file",
        default="training/logs/interventions/agent-team-bootstrap-pending.json",
        help="Pending launch metadata when queue is busy",
    )
    parser.add_argument(
        "--rollout-json",
        default="configs/agent_team_rollout.json",
        help="Rollout state JSON with intervention-required flags",
    )
    parser.add_argument(
        "--mapping-json",
        default="configs/agent_team_queue_mapping.json",
        help="Team-to-(project/task) mapping JSON for bootstrap jobs",
    )
    return parser.parse_args()


def _load_json(path: Path, default_payload: dict) -> dict:
    if not path.exists():
        return default_payload
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default_payload


def _paused_job_keys(rollout: dict, mapping: dict) -> set[tuple[str, str]]:
    paused_teams: set[str] = set()
    for team, state in (rollout.get("teams") or {}).items():
        enabled = bool(state.get("enabled", False))
        intervention_required = bool(state.get("intervention_required", False))
        if intervention_required or not enabled:
            paused_teams.add(str(team))

    keys: set[tuple[str, str]] = set()
    for team in paused_teams:
        for item in (mapping.get(team) or []):
            project = str(item.get("project", "")).strip()
            task = str(item.get("task", "")).strip()
            if project and task:
                keys.add((project, task))
    return keys


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent

    jobs_path = (repo_root / args.jobs_file).resolve()
    if not jobs_path.exists():
        raise SystemExit(f"Bootstrap jobs file not found: {jobs_path}")

    jobs_payload = _load_json(jobs_path, {"jobs": []})
    all_jobs = list(jobs_payload.get("jobs") or [])
    jobs = [item for item in all_jobs if bool(item.get("enabled", True))]

    rollout_payload = _load_json((repo_root / args.rollout_json).resolve(), {"teams": {}})
    mapping_payload = _load_json((repo_root / args.mapping_json).resolve(), {})
    paused_keys = _paused_job_keys(rollout_payload, mapping_payload)

    filtered_jobs = [
        item for item in jobs
        if (str(item.get("project", "")).strip(), str(item.get("task", "")).strip()) not in paused_keys
    ]

    filtered_jobs_path = jobs_path
    policy_note = "No paused teams."
    if paused_keys:
        filtered_jobs_path = jobs_path.with_name(f"{jobs_path.stem}.active{jobs_path.suffix}")
        policy_payload = {
            "jobs": filtered_jobs,
            "generated_at": datetime.now().isoformat(),
            "source_jobs_file": str(jobs_path),
            "paused_job_keys": sorted([{"project": p, "task": t} for p, t in paused_keys], key=lambda x: (x["project"], x["task"])),
        }
        filtered_jobs_path.write_text(json.dumps(policy_payload, indent=2), encoding="utf-8")
        policy_note = f"Filtered paused jobs and wrote active queue file: {filtered_jobs_path}"

    if not filtered_jobs:
        if not jobs and all_jobs:
            reason = "All bootstrap jobs are disabled (enabled=false)."
            status = "PAUSED_BY_CONFIG"
        else:
            reason = "All bootstrap jobs map to paused/intervention-required teams."
            status = "PAUSED_BY_POLICY"

        payload = {
            "timestamp": datetime.now().isoformat(),
            "status": status,
            "reason": reason,
            "paused_job_keys": sorted([{"project": p, "task": t} for p, t in paused_keys], key=lambda x: (x["project"], x["task"])),
            "source_jobs_file": str(jobs_path),
        }
        pending_path = (repo_root / args.pending_file).resolve()
        pending_path.parent.mkdir(parents=True, exist_ok=True)
        pending_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(json.dumps(payload, indent=2))
        print(f"\nBootstrap launch blocked. Pending state saved to: {pending_path}")
        return 0

    pid_file = queue_pid_file(repo_root)
    lock_file = queue_lock_file(repo_root)

    busy_pid = read_alive_pid(pid_file)
    busy_lock = read_alive_pid(lock_file)
    if busy_pid or busy_lock:
        payload = {
            "timestamp": datetime.now().isoformat(),
            "status": "PENDING_QUEUE_BUSY",
            "busy_pid": busy_pid,
            "busy_lock_pid": busy_lock,
            "policy_note": policy_note,
            "next_command": [
                str(Path(args.python).resolve()),
                str(repo_root / "scripts" / "start_nightly_queue.py"),
                "--python",
                str(Path(args.python).resolve()),
                "--jobs-file",
                str(filtered_jobs_path),
                "--max-hours",
                str(args.max_hours),
            ],
        }
        pending_path = repo_root / args.pending_file
        pending_path.parent.mkdir(parents=True, exist_ok=True)
        pending_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

        print(json.dumps(payload, indent=2))
        print(f"\nQueue busy. Pending launch saved to: {pending_path}")
        return 0

    cmd = [
        str(Path(args.python).resolve()),
        str(repo_root / "scripts" / "start_nightly_queue.py"),
        "--python",
        str(Path(args.python).resolve()),
        "--jobs-file",
        str(filtered_jobs_path),
        "--max-hours",
        str(args.max_hours),
    ]
    proc = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True)

    if proc.stdout:
        print(proc.stdout)
    if proc.returncode != 0:
        if proc.stderr:
            print(proc.stderr)
        return proc.returncode

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
