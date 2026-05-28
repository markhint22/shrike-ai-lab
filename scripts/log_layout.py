#!/usr/bin/env python3
"""Shared log layout helpers for Shrike AI Lab scripts."""

from __future__ import annotations

import os
from pathlib import Path


LOG_SUBDIRS = {
    "runs": "runs",
    "queue": "queue",
    "interventions": "interventions",
    "ab_gates": "ab-gates",
    "recovery": "recovery",
    "diagnostics": "diagnostics",
    "startup": "startup",
    "monitoring": "monitoring",
    "services": "services",
}

QUEUE_RUNTIME_SUBDIR = Path("runtime") / "queue"
QUEUE_PID_FILENAME = "training-queue.pid"
QUEUE_LOCK_FILENAME = "training-queue.lock"
QUEUE_LAUNCHER_LOCK_FILENAME = "queue-launch.lock"


def logs_root(repo_root: Path) -> Path:
    return repo_root / "training" / "logs"


def ensure_log_layout(repo_root: Path) -> Path:
    root = logs_root(repo_root)
    root.mkdir(parents=True, exist_ok=True)
    for name in LOG_SUBDIRS.values():
        (root / name).mkdir(parents=True, exist_ok=True)
    queue_runtime_dir(repo_root)
    return root


def log_dir(repo_root: Path, key: str) -> Path:
    root = ensure_log_layout(repo_root)
    subdir = LOG_SUBDIRS.get(key)
    if not subdir:
        raise KeyError(f"Unknown log directory key: {key}")
    return root / subdir


def queue_runtime_dir(repo_root: Path) -> Path:
    path = repo_root / QUEUE_RUNTIME_SUBDIR
    path.mkdir(parents=True, exist_ok=True)
    return path


def queue_pid_file(repo_root: Path) -> Path:
    return queue_runtime_dir(repo_root) / QUEUE_PID_FILENAME


def queue_lock_file(repo_root: Path) -> Path:
    return queue_runtime_dir(repo_root) / QUEUE_LOCK_FILENAME


def queue_launcher_lock_file(repo_root: Path) -> Path:
    return queue_runtime_dir(repo_root) / QUEUE_LAUNCHER_LOCK_FILENAME


def queue_legacy_pid_candidates(repo_root: Path) -> list[Path]:
    return [
        queue_runtime_dir(repo_root) / "nightly-queue.pid",
        logs_root(repo_root) / "queue" / "nightly-queue.pid",
        logs_root(repo_root) / "nightly-queue.pid",
    ]


def queue_legacy_lock_candidates(repo_root: Path) -> list[Path]:
    return [
        queue_runtime_dir(repo_root) / "train-queue.lock",
        logs_root(repo_root) / "queue" / "train-queue.lock",
        logs_root(repo_root) / "train-queue.lock",
    ]


def migrate_legacy_queue_state(repo_root: Path) -> None:
    pid_dest = queue_pid_file(repo_root)
    lock_dest = queue_lock_file(repo_root)

    def _alive_pid(path: Path) -> int | None:
        if not path.exists():
            return None
        try:
            value = int(path.read_text(encoding="ascii").strip())
        except ValueError:
            return None
        try:
            os.kill(value, 0)
        except OSError:
            return None
        return value

    if _alive_pid(pid_dest) is None:
        for old_pid in queue_legacy_pid_candidates(repo_root):
            alive = _alive_pid(old_pid)
            if alive is not None and old_pid != pid_dest:
                pid_dest.write_text(str(alive), encoding="ascii")
                break

    if _alive_pid(lock_dest) is None:
        for old_lock in queue_legacy_lock_candidates(repo_root):
            alive = _alive_pid(old_lock)
            if alive is not None and old_lock != lock_dest:
                lock_dest.write_text(str(alive), encoding="ascii")
                break

    old_launch_dir = logs_root(repo_root) / "queue"
    new_launch_dir = queue_runtime_dir(repo_root)
    if old_launch_dir.exists():
        for old_log in old_launch_dir.glob("queue-launch-*.log"):
            new_log = new_launch_dir / old_log.name
            if new_log.exists():
                continue
            try:
                old_log.replace(new_log)
            except PermissionError:
                continue


def resolve_run_log_dirs(repo_root: Path, logs_dir_arg: str | None = None) -> list[Path]:
    """Return directories to search for run logs, newest layout first.

    Includes compatibility fallback to legacy flat `training/logs`.
    """
    ensure_log_layout(repo_root)
    dirs: list[Path] = []

    if logs_dir_arg:
        requested = (repo_root / logs_dir_arg).resolve()
        if requested.name == "logs":
            dirs.append(requested / "runs")
        dirs.append(requested)

    dirs.append(log_dir(repo_root, "runs"))
    dirs.append(logs_root(repo_root))

    out: list[Path] = []
    seen: set[Path] = set()
    for path in dirs:
        if path.exists() and path not in seen:
            out.append(path)
            seen.add(path)
    return out
