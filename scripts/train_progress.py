#!/usr/bin/env python3
"""
Summarize training queue progress from log files.
"""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_log(path: Path) -> tuple[str, int | None]:
    """Return (state, exit_code). state in {running, done}."""
    state = "running"
    exit_code: int | None = None
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return "running", None

    for line in reversed(text.splitlines()):
        if line.startswith("EXIT "):
            try:
                exit_code = int(line.split(" ", 1)[1].strip())
            except Exception:
                exit_code = None
            state = "done"
            break
    return state, exit_code


def main() -> int:
    parser = argparse.ArgumentParser(description="Show training progress summary")
    parser.add_argument(
        "--logs-dir",
        default="training/logs",
        help="Directory containing train_queue log files",
    )
    parser.add_argument(
        "--tail",
        type=int,
        default=10,
        help="How many latest log files to show (default: 10)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    logs_dir = (repo_root / args.logs_dir).resolve()
    if not logs_dir.exists():
        print(f"Logs directory not found: {logs_dir}")
        return 1

    logs = sorted(logs_dir.glob("*.log"), key=lambda p: p.stat().st_mtime)
    if not logs:
        print(f"No log files in {logs_dir}")
        return 0

    completed_ok = 0
    completed_fail = 0
    running = 0

    rows: list[tuple[str, str, str]] = []
    for log in logs:
        state, code = parse_log(log)
        if state == "running":
            running += 1
            status = "RUNNING"
        else:
            if code == 0:
                completed_ok += 1
                status = "OK"
            else:
                completed_fail += 1
                status = f"FAIL({code})"
        rows.append((log.name, status, str(log.stat().st_size)))

    print("Training Progress Summary")
    print(f"Logs dir: {logs_dir}")
    print(f"Completed OK: {completed_ok}")
    print(f"Completed Fail: {completed_fail}")
    print(f"Running: {running}")
    print()
    print(f"Latest {min(args.tail, len(rows))} logs:")
    for name, status, size in rows[-args.tail:]:
        print(f"  {status:<10} {name} ({size} bytes)")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
