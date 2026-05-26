#!/usr/bin/env python3
"""Organize legacy flat training/logs files into categorized subfolders."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

from log_layout import ensure_log_layout, log_dir, logs_root


RUN_LOG_RE = re.compile(r"^\d{8}-\d{6}-[^-]+-[^-]+-.*\.log$")


def category_for(name: str) -> str | None:
    lower = name.lower()

    if RUN_LOG_RE.match(name):
        return "runs"
    if name in {"nightly-queue.pid", "train-queue.lock"} or lower.startswith("queue-launch-"):
        return "queue"
    if lower == "intervention-board.json":
        return "interventions"
    if lower.startswith("ab-gate-") and lower.endswith(".json"):
        return "ab_gates"
    if lower.startswith("crash-diag-") or lower.startswith("diagnostic-") or lower in {
        "diagnostic-output.txt",
        "shellcheck.txt",
    }:
        return "diagnostics"
    if lower.startswith("startup-") or lower.startswith("register-startup"):
        return "startup"
    if lower.startswith("training-monitor-") or lower == "training-monitor.pid":
        return "monitoring"
    if lower.startswith("recovery-") or lower.startswith("manual-recover") or lower.startswith("postpatch-recovery"):
        return "recovery"
    if lower.startswith("litellm-"):
        return "services"
    return None


def unique_destination(dest: Path) -> Path:
    if not dest.exists():
        return dest
    stem = dest.stem
    suffix = dest.suffix
    idx = 1
    while True:
        candidate = dest.with_name(f"{stem}-{idx}{suffix}")
        if not candidate.exists():
            return candidate
        idx += 1


def main() -> int:
    parser = argparse.ArgumentParser(description="Organize flat training/logs files into subfolders")
    parser.add_argument("--dry-run", action="store_true", help="Print planned moves without changing files")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    ensure_log_layout(repo_root)
    root = logs_root(repo_root)

    moved = 0
    skipped = 0
    for path in sorted(root.iterdir(), key=lambda p: p.name):
        if path.is_dir():
            continue

        category = category_for(path.name)
        if not category:
            skipped += 1
            continue

        destination = unique_destination(log_dir(repo_root, category) / path.name)
        if args.dry_run:
            print(f"DRY-RUN: {path.name} -> {destination.relative_to(root)}")
            moved += 1
            continue

        try:
            path.replace(destination)
            print(f"MOVED: {path.name} -> {destination.relative_to(root)}")
            moved += 1
        except PermissionError:
            print(f"SKIP (in use): {path.name}")
            skipped += 1

    print(f"Done. moved={moved} skipped={skipped}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
