#!/usr/bin/env python3
"""Training queue status/monitoring ops.

Cross-platform (Linux/macOS) replacement for the old Windows-only
queue_ops.ps1. Same subcommands, same semantics, no PowerShell required.

Usage:
  python scripts/queue_ops.py status
  python scripts/queue_ops.py jobs
  python scripts/queue_ops.py tail [--tail-lines N] [--follow]
  python scripts/queue_ops.py tailrun [--tail-lines N]
  python scripts/queue_ops.py tailrunf [--tail-lines N]
  python scripts/queue_ops.py failures [--recent N]
  python scripts/queue_ops.py pids
  python scripts/queue_ops.py cleanup
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from log_layout import log_dir, queue_lock_file, queue_pid_file, queue_runtime_dir

REPO_ROOT = Path(__file__).resolve().parent.parent


def process_alive(pid: int | None) -> bool:
    if pid is None:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True  # exists, just owned by another user
    except OSError:
        return False
    return True


def read_pid(path: Path) -> int | None:
    if not path.exists():
        return None
    try:
        return int(path.read_text(encoding="ascii").strip())
    except (ValueError, OSError):
        return None


def _newest(paths_glob) -> Path | None:
    matches = sorted(paths_glob, key=lambda p: p.stat().st_mtime, reverse=True)
    return matches[0] if matches else None


def latest_queue_log(queue_dir: Path) -> Path | None:
    if not queue_dir.exists():
        return None
    return _newest(queue_dir.glob("queue-launch-*.log"))


def latest_run_log(runs_dir: Path) -> Path | None:
    if not runs_dir.exists():
        return None
    return _newest(runs_dir.glob("*.log"))


def running_queue_processes() -> list[tuple[int, str]]:
    """List processes whose command line references the training queue scripts."""
    pattern = re.compile(r"train_queue\.py|scripts/train\.py|start_nightly_queue\.py")
    try:
        result = subprocess.run(
            ["ps", "-eo", "pid,args"], check=False, capture_output=True, text=True
        )
    except OSError:
        return []
    if result.returncode != 0:
        return []

    out: list[tuple[int, str]] = []
    for line in result.stdout.splitlines()[1:]:  # skip header row
        line = line.strip()
        if not line or not pattern.search(line):
            continue
        pid_str, _, rest = line.partition(" ")
        try:
            pid = int(pid_str)
        except ValueError:
            continue
        out.append((pid, rest.strip()))
    return out


def _read_lines(path: Path) -> list[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def cmd_status(_args: argparse.Namespace) -> int:
    queue_dir = queue_runtime_dir(REPO_ROOT)
    pid_file = queue_pid_file(REPO_ROOT)
    lock_file = queue_lock_file(REPO_ROOT)

    print("=== Queue Status ===")
    print(f"Time: {datetime.now().isoformat()}")
    print()

    print("[PID and lock files]")
    for path in (pid_file, lock_file):
        pid = read_pid(path)
        print(f"  {path.name:28s} exists={str(path.exists()):5s} pid={pid} alive={process_alive(pid)}")

    print()
    print("[Running Python queue/train processes]")
    running = running_queue_processes()
    if not running:
        print("  none")
    else:
        for pid, cmdline in running:
            print(f"  pid={pid}  {cmdline}")

    print()
    print("[Latest queue log]")
    latest = latest_queue_log(queue_dir)
    if not latest:
        print(f"  No queue-launch log found in {queue_dir}")
        return 0

    print(f"  File: {latest}")
    tail_lines = _read_lines(latest)[-300:]

    def last_match(pattern: str) -> str | None:
        rx = re.compile(pattern)
        for line in reversed(tail_lines):
            if rx.search(line):
                return line
        return None

    last_cycle = last_match(r"^=== Queue Cycle")
    last_job = last_match(r"^\[\d+/\d+\]")
    last_stop = last_match(r"Queue completed|Reached max runtime window|Stopping queue")

    if last_cycle:
        print(f"  Cycle: {last_cycle}")
    if last_job:
        print(f"  Latest job line: {last_job}")
    if last_stop:
        print(f"  Latest stop/completion line: {last_stop}")
    return 0


def cmd_jobs(_args: argparse.Namespace) -> int:
    jobs_file = REPO_ROOT / "training" / "queue" / "nightly_jobs.json"
    if not jobs_file.exists():
        print(f"Jobs file not found: {jobs_file}", file=sys.stderr)
        return 1

    payload = json.loads(jobs_file.read_text(encoding="utf-8"))
    jobs = payload.get("jobs", [])

    print("=== Nightly Queue Jobs ===")
    print(f"File: {jobs_file}")
    print(f"Total jobs: {len(jobs)}")
    print()
    for i, job in enumerate(jobs, start=1):
        print(
            f"{i:3d}. kind={job.get('kind', 'llm_train'):14s} "
            f"project={job.get('project', ''):12s} task={job.get('task', ''):24s} "
            f"team={job.get('team', ''):16s} version={job.get('version', ''):30s} "
            f"candidate_model={job.get('ab_gate_candidate_model', '')}"
        )
    return 0


def _print_tail(path: Path, n: int, follow: bool) -> None:
    lines = _read_lines(path)
    for line in lines[-n:]:
        print(line)
    if not follow:
        return
    try:
        with path.open("r", encoding="utf-8", errors="replace") as f:
            f.seek(0, os.SEEK_END)
            while True:
                line = f.readline()
                if line:
                    print(line, end="")
                else:
                    time.sleep(0.5)
    except KeyboardInterrupt:
        pass


def cmd_tail(args: argparse.Namespace) -> int:
    queue_dir = queue_runtime_dir(REPO_ROOT)
    latest = latest_queue_log(queue_dir)
    if not latest:
        print(f"No queue-launch log found in {queue_dir}", file=sys.stderr)
        return 1

    print("=== Queue Log Tail ===")
    print(f"File: {latest}")
    print()
    _print_tail(latest, args.tail_lines, follow=args.follow)
    return 0


def cmd_tailrun(args: argparse.Namespace, follow: bool) -> int:
    runs_dir = log_dir(REPO_ROOT, "runs")
    latest = latest_run_log(runs_dir)
    if not latest:
        print(f"No run logs found in {runs_dir}", file=sys.stderr)
        return 1

    print("=== Latest Run Log Tail ===")
    print(f"File: {latest}")
    print()

    if not follow:
        _print_tail(latest, args.tail_lines, follow=False)
        return 0

    print("Auto-follow mode: will switch to the next run log when a new job starts.")
    print("Press Ctrl+C to stop.")
    print()

    current_file: Path | None = None
    line_cursor = 0
    try:
        while True:
            latest = latest_run_log(runs_dir)
            if not latest:
                time.sleep(0.8)
                continue

            if latest != current_file:
                current_file = latest
                all_lines = _read_lines(current_file)
                line_cursor = max(0, len(all_lines) - args.tail_lines)
                print(f"\n>>> Switched to: {current_file}\n")
                for line in all_lines[line_cursor:]:
                    print(line)
                line_cursor = len(all_lines)

            all_lines = _read_lines(current_file)
            if len(all_lines) > line_cursor:
                for line in all_lines[line_cursor:]:
                    print(line)
                line_cursor = len(all_lines)

            time.sleep(0.8)
    except KeyboardInterrupt:
        pass
    return 0


def cmd_failures(args: argparse.Namespace) -> int:
    queue_dir = queue_runtime_dir(REPO_ROOT)
    latest = latest_queue_log(queue_dir)
    if not latest:
        print(f"No queue-launch log found in {queue_dir}", file=sys.stderr)
        return 1

    pattern = re.compile("Job failed|ab-gate failed|Stopping queue due to|Queue completed with failures")
    print("=== Recent Failures ===")
    print(f"File: {latest}")
    print()

    matches = [line for line in _read_lines(latest) if pattern.search(line)]
    matches = matches[-args.recent :] if args.recent > 0 else matches
    if not matches:
        print("No matching failure lines found in latest queue log.")
    else:
        for line in matches:
            print(line)
    return 0


def cmd_pids(_args: argparse.Namespace) -> int:
    print("=== Queue PIDs ===")
    for path in (queue_pid_file(REPO_ROOT), queue_lock_file(REPO_ROOT)):
        pid = read_pid(path)
        print(f"  {path.name:28s} pid={pid} alive={process_alive(pid)}")
    return 0


def cmd_cleanup(_args: argparse.Namespace) -> int:
    print("=== Cleanup Stale Queue Artifacts ===")
    removed: list[str] = []
    kept: list[str] = []
    for path in (queue_pid_file(REPO_ROOT), queue_lock_file(REPO_ROOT)):
        if not path.exists():
            continue
        if process_alive(read_pid(path)):
            kept.append(path.name)
        else:
            path.unlink()
            removed.append(path.name)

    print("Removed: " + (", ".join(removed) if removed else "none"))
    if kept:
        print("Kept active: " + ", ".join(kept))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="action", required=True)

    sub.add_parser("status", help="Summary of PID/locks, running processes, latest cycle/job lines")
    sub.add_parser("jobs", help="Print all jobs from training/queue/nightly_jobs.json")

    p_tail = sub.add_parser("tail", help="Tail latest queue-launch log")
    p_tail.add_argument("--tail-lines", type=int, default=80)
    p_tail.add_argument("--follow", action="store_true")

    p_tailrun = sub.add_parser("tailrun", help="Tail latest per-job run log")
    p_tailrun.add_argument("--tail-lines", type=int, default=80)

    p_tailrunf = sub.add_parser("tailrunf", help="Follow latest per-job run log live")
    p_tailrunf.add_argument("--tail-lines", type=int, default=80)

    p_failures = sub.add_parser("failures", help="Show recent failure-related lines from latest log")
    p_failures.add_argument("--recent", type=int, default=20)

    sub.add_parser("pids", help="Show PID and lock file process states")
    sub.add_parser("cleanup", help="Remove stale queue PID/lock files")

    args = parser.parse_args()

    dispatch = {
        "status": cmd_status,
        "jobs": cmd_jobs,
        "tail": cmd_tail,
        "tailrun": lambda a: cmd_tailrun(a, follow=False),
        "tailrunf": lambda a: cmd_tailrun(a, follow=True),
        "failures": cmd_failures,
        "pids": cmd_pids,
        "cleanup": cmd_cleanup,
    }
    return dispatch[args.action](args)


if __name__ == "__main__":
    raise SystemExit(main())
