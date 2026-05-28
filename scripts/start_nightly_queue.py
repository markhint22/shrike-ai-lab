#!/usr/bin/env python3
"""Start the nightly training queue as a detached background process on Windows."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from log_layout import (
    migrate_legacy_queue_state,
    queue_launcher_lock_file,
    queue_lock_file,
    queue_pid_file,
    queue_runtime_dir,
)


def process_exists(pid: int) -> bool:
    result = subprocess.run(
        ["tasklist", "/FI", f"PID eq {pid}"],
        check=False,
        capture_output=True,
        text=True,
    )
    return str(pid) in (result.stdout or "")


def active_train_queue_pids() -> list[int]:
    query = (
        "Get-CimInstance Win32_Process | "
        "Where-Object { $_.Name -eq 'python.exe' -and $_.CommandLine -match 'scripts\\\\train_queue\\.py' } | "
        "Select-Object -ExpandProperty ProcessId"
    )
    result = subprocess.run(
        ["powershell", "-NoProfile", "-Command", query],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return []

    out: list[int] = []
    for line in (result.stdout or "").splitlines():
        value = line.strip()
        if not value:
            continue
        try:
            out.append(int(value))
        except ValueError:
            continue
    return out


def acquire_launcher_lock(path: Path) -> int | None:
    path.parent.mkdir(parents=True, exist_ok=True)
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    try:
        fd = os.open(str(path), flags)
    except FileExistsError:
        return None
    os.write(fd, str(os.getpid()).encode("ascii"))
    return fd


def release_launcher_lock(fd: int | None, path: Path) -> None:
    if fd is not None:
        try:
            os.close(fd)
        except OSError:
            pass
    path.unlink(missing_ok=True)


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
    parser.add_argument(
        "--job-timeout-minutes",
        type=float,
        default=180,
        help="Per-job timeout in minutes (0 disables timeout)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    migrate_legacy_queue_state(repo_root)
    logs_dir = queue_runtime_dir(repo_root)

    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    launcher_log = logs_dir / f"queue-launch-{timestamp}.log"
    pid_file = queue_pid_file(repo_root)
    lock_file = queue_lock_file(repo_root)
    launcher_lock = queue_launcher_lock_file(repo_root)

    launcher_fd = acquire_launcher_lock(launcher_lock)
    if launcher_fd is None:
        print("Queue launcher is already active; skipping duplicate start attempt.")
        print(f"Launcher lock: {launcher_lock}")
        return 0

    try:
        # Prevent duplicate queue instances: prefer PID file, then lock owner.
        if pid_file.exists():
            try:
                existing_pid = int(pid_file.read_text(encoding="ascii").strip())
            except ValueError:
                existing_pid = None
            if existing_pid and process_exists(existing_pid):
                print("Nightly queue is already running.")
                print(f"PID: {existing_pid}")
                print(f"PID file: {pid_file}")
                return 0

        if lock_file.exists():
            try:
                lock_pid = int(lock_file.read_text(encoding="ascii").strip())
            except ValueError:
                lock_pid = None
            if lock_pid and process_exists(lock_pid):
                print("Nightly queue lock indicates an active instance.")
                print(f"Lock owner PID: {lock_pid}")
                print(f"Lock file: {lock_file}")
                return 0

        queue_pids = active_train_queue_pids()
        if queue_pids:
            pid_file.write_text(str(queue_pids[0]), encoding="ascii")
            print("Detected active train_queue process; skipping duplicate start.")
            print(f"Active PID: {queue_pids[0]}")
            print(f"PID file: {pid_file}")
            return 0

        command = [
            str(Path(args.python).resolve()),
            "-u",
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
            "--job-timeout-minutes",
            str(args.job_timeout_minutes),
            "--repeat",
            "--stamp-version",
            "--max-hours",
            str(args.max_hours),
        ]

        creationflags = 0
        if sys.platform == "win32":
            creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS

        child_env = os.environ.copy()
        # Force line-buffered / unbuffered behavior so queue-launch logs stream in real time.
        child_env["PYTHONUNBUFFERED"] = "1"

        with launcher_log.open("w", encoding="utf-8") as log_handle:
            log_handle.write(f"START {datetime.now().isoformat()}\n")
            log_handle.write("COMMAND " + " ".join(command) + "\n")
            log_handle.flush()
            process = subprocess.Popen(
                command,
                cwd=repo_root,
                env=child_env,
                stdout=log_handle,
                stderr=subprocess.STDOUT,
                text=True,
                creationflags=creationflags,
                close_fds=False,
            )

        # Give detached child a brief startup window and resolve actual lock owner.
        # On some Windows launches, train_queue may hand off lock ownership to a child PID.
        time.sleep(2)

        owner_pid = process.pid
        for _ in range(12):
            if lock_file.exists():
                try:
                    lock_pid = int(lock_file.read_text(encoding="ascii").strip())
                except ValueError:
                    lock_pid = None
                if lock_pid and process_exists(lock_pid):
                    owner_pid = lock_pid
                    break
            time.sleep(0.5)

        if process.poll() is not None and not process_exists(owner_pid):
            print("Nightly queue failed to start.")
            print(f"Exit code: {process.returncode}")
            print(f"Launcher log: {launcher_log}")
            return 1

        pid_file.write_text(str(owner_pid), encoding="ascii")

        print("Started nightly queue")
        print(f"PID: {owner_pid}")
        print(f"Launcher log: {launcher_log}")
        print(f"PID file: {pid_file}")
        return 0
    finally:
        release_launcher_lock(launcher_fd, launcher_lock)


if __name__ == "__main__":
    raise SystemExit(main())