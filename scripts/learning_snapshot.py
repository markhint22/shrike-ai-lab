#!/usr/bin/env python3
"""Plain-language training snapshot for non-technical progress checks."""

from __future__ import annotations

import argparse
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from log_layout import resolve_run_log_dirs


LOG_NAME_RE = re.compile(r"^(\d{8})-(\d{6})-([^-]+)-([^-]+)-.*\.log$")
LOSS_RE = re.compile(r"'train_loss':\s*'?(\d+(?:\.\d+)?)'?")


@dataclass
class RunInfo:
    log_name: str
    project: str
    task: str
    stamp: str
    ok: bool
    running: bool
    exit_code: int | None
    train_loss: float | None
    model_saved: bool


def iter_logs(log_dirs: list[Path]) -> Iterable[Path]:
    all_paths: list[Path] = []
    seen: set[Path] = set()
    for directory in log_dirs:
        for path in directory.glob("*.log"):
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            all_paths.append(path)

    for path in sorted(all_paths, key=lambda p: p.stat().st_mtime, reverse=True):
        if LOG_NAME_RE.match(path.name):
            yield path


def parse_log(path: Path) -> RunInfo | None:
    m = LOG_NAME_RE.match(path.name)
    if not m:
        return None

    ymd, hms, project, task = m.groups()
    stamp = f"{ymd} {hms}"
    text = path.read_text(encoding="utf-8", errors="replace")

    exit_code = None
    for line in reversed(text.splitlines()):
        if line.startswith("EXIT "):
            try:
                exit_code = int(line.split(" ", 1)[1].strip())
            except Exception:
                exit_code = None
            break

    running = exit_code is None
    ok = exit_code == 0

    loss_match = LOSS_RE.search(text)
    train_loss = float(loss_match.group(1)) if loss_match else None

    model_saved = "Model saved to:" in text

    return RunInfo(
        log_name=path.name,
        project=project,
        task=task,
        stamp=stamp,
        ok=ok,
        running=running,
        exit_code=exit_code,
        train_loss=train_loss,
        model_saved=model_saved,
    )


def loss_label(loss: float | None) -> str:
    if loss is None:
        return "unknown"
    if loss < 1.6:
        return "strong"
    if loss < 2.3:
        return "good"
    if loss < 3.0:
        return "early"
    return "weak"


def main() -> int:
    parser = argparse.ArgumentParser(description="Show a plain-language learning snapshot")
    parser.add_argument(
        "--logs-dir",
        default="training/logs/runs",
        help="Directory containing training log files",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    log_dirs = resolve_run_log_dirs(repo_root, args.logs_dir)
    if not log_dirs:
        print("No log directories found for training runs")
        return 1

    latest_by_project: dict[str, RunInfo] = {}
    total_ok = 0
    total_fail = 0
    total_running = 0

    for path in iter_logs(log_dirs):
        info = parse_log(path)
        if info is None:
            continue

        if info.running:
            total_running += 1
        elif info.ok:
            total_ok += 1
        else:
            total_fail += 1

        if info.project not in latest_by_project:
            latest_by_project[info.project] = info

    print("Learning Snapshot")
    print("Logs:")
    for directory in log_dirs:
        print(f"- {directory}")
    print(f"Completed OK: {total_ok} | Completed Fail: {total_fail} | Running: {total_running}")
    print()
    print("Latest by project:")

    for project in sorted(latest_by_project.keys()):
        info = latest_by_project[project]
        if info.running:
            status = "running"
        elif info.ok:
            status = "finished"
        else:
            status = f"failed ({info.exit_code})"

        learned = "yes" if info.model_saved else "no"
        print(
            f"- {project}: {status}; task={info.task}; last={info.stamp}; "
            f"loss={info.train_loss if info.train_loss is not None else 'n/a'} "
            f"({loss_label(info.train_loss)}); model_saved={learned}"
        )

    print()
    print("How to read this:")
    print("- model_saved=yes means that run produced updated weights.")
    print("- lower loss is usually better, but the best test is task quality checks.")
    print("- running means current cycle still in progress.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
