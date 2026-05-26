#!/usr/bin/env python3
"""Start the nightly training queue as a detached background process on Windows."""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from log_layout import log_dir


def main() -> int:
    parser = argparse.ArgumentParser(description="Start detached nightly training queue")
    parser.add_argument("--python", default=sys.executable, help="Python executable for the queue")
    parser.add_argument(
        "--jobs-file",
        default="training/queue/nightly_jobs.json",
        help="Queue definition JSON path",
    )
    parser.add_argument("--max-hours", type=float, default=18, help="Max runtime window in hours")
    parser.add_argument("--retry-count", type=int, default=1, help="Retries per failed job")
    parser.add_argument(
        "--retry-lr-multiplier",
        type=float,
        default=0.5,
        help="Learning-rate multiplier for retries",
    )
    parser.add_argument(
        "--max-consecutive-failures",
        type=int,
        default=16,
        help="Stop repeating after this many consecutive failed jobs",
    )
    parser.add_argument(
        "--cycle-delay-seconds",
        type=float,
        default=30,
        help="Delay between repeat cycles to avoid rapid failure loops",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    logs_dir = log_dir(repo_root, "queue")

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    launcher_log = logs_dir / f"queue-launch-{timestamp}.log"
    pid_file = logs_dir / "nightly-queue.pid"

    command = [
        str(Path(args.python).resolve()),
        str(repo_root / "scripts" / "train_queue.py"),
        "--jobs-file",
        args.jobs_file,
        "--continue-on-error",
        "--retry-count",
        str(args.retry_count),
        "--retry-lr-multiplier",
        str(args.retry_lr_multiplier),
        "--max-consecutive-failures",
        str(args.max_consecutive_failures),
        "--cycle-delay-seconds",
        str(args.cycle_delay_seconds),
        "--repeat",
        "--stamp-version",
        "--max-hours",
        str(args.max_hours),
    ]

    creationflags = 0
    if sys.platform == "win32":
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS

    with launcher_log.open("w", encoding="utf-8") as log_handle:
        log_handle.write(f"START {datetime.now().isoformat()}\n")
        log_handle.write("COMMAND " + " ".join(command) + "\n")
        log_handle.flush()
        process = subprocess.Popen(
            command,
            cwd=repo_root,
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            text=True,
            creationflags=creationflags,
            close_fds=False,
        )

    # Give detached child a brief startup window and verify it didn't die immediately.
    time.sleep(2)
    if process.poll() is not None:
        print("Nightly queue failed to start.")
        print(f"Exit code: {process.returncode}")
        print(f"Launcher log: {launcher_log}")
        return 1

    pid_file.write_text(str(process.pid), encoding="ascii")

    print("Started nightly queue")
    print(f"PID: {process.pid}")
    print(f"Launcher log: {launcher_log}")
    print(f"PID file: {pid_file}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())