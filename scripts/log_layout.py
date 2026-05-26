#!/usr/bin/env python3
"""Shared log layout helpers for Shrike AI Lab scripts."""

from __future__ import annotations

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


def logs_root(repo_root: Path) -> Path:
    return repo_root / "training" / "logs"


def ensure_log_layout(repo_root: Path) -> Path:
    root = logs_root(repo_root)
    root.mkdir(parents=True, exist_ok=True)
    for name in LOG_SUBDIRS.values():
        (root / name).mkdir(parents=True, exist_ok=True)
    return root


def log_dir(repo_root: Path, key: str) -> Path:
    root = ensure_log_layout(repo_root)
    subdir = LOG_SUBDIRS.get(key)
    if not subdir:
        raise KeyError(f"Unknown log directory key: {key}")
    return root / subdir


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
