#!/usr/bin/env python3
"""Watch queue lock and auto-launch agent-team bootstrap queue when free."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
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


def read_pid(path: Path) -> int | None:
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="ascii").strip())
    except Exception:
        return None


def queue_busy(repo_root: Path) -> bool:
    for path in (queue_pid_file(repo_root), queue_lock_file(repo_root)):
        pid = read_pid(path)
        if pid and process_exists(pid):
            return True
    return False


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Watch queue and auto-start team bootstrap training")
    parser.add_argument("--python", default=sys.executable, help="Python executable")
    parser.add_argument(
        "--jobs-file",
        default="training/queue/agent_team_bootstrap_jobs.json",
        help="Bootstrap queue jobs file",
    )
    parser.add_argument("--max-hours", type=float, default=6.0, help="Bootstrap queue runtime window")
    parser.add_argument(
        "--poll-seconds",
        type=float,
        default=30.0,
        help="Polling interval while queue is busy",
    )
    parser.add_argument(
        "--timeout-minutes",
        type=float,
        default=720.0,
        help="Stop watching after this timeout (minutes)",
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


def main() -> int:
    args = parse_args()
    repo_root = Path(__file__).resolve().parent.parent

    deadline = time.time() + (args.timeout_minutes * 60)
    print(f"[{datetime.now().isoformat()}] Watching queue for bootstrap window...")

    while time.time() < deadline:
        if not queue_busy(repo_root):
            print(f"[{datetime.now().isoformat()}] Queue free. Launching bootstrap queue...")
            cmd = [
                str(Path(args.python).resolve()),
                str(repo_root / "scripts" / "start_agent_team_bootstrap.py"),
                "--python",
                str(Path(args.python).resolve()),
                "--jobs-file",
                args.jobs_file,
                "--max-hours",
                str(args.max_hours),
                "--rollout-json",
                args.rollout_json,
                "--mapping-json",
                args.mapping_json,
            ]
            proc = subprocess.run(cmd, cwd=repo_root, capture_output=True, text=True)
            if proc.stdout:
                print(proc.stdout)
            if proc.returncode != 0:
                if proc.stderr:
                    print(proc.stderr)
                return proc.returncode
            return 0

        print(f"[{datetime.now().isoformat()}] Queue busy; retrying in {args.poll_seconds:.0f}s...")
        time.sleep(args.poll_seconds)

    print(f"[{datetime.now().isoformat()}] Timeout reached before queue became free.")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
