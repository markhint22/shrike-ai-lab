#!/usr/bin/env python3
"""Summarize train-loss trends from nightly training logs."""

from __future__ import annotations

import re
from pathlib import Path

from log_layout import resolve_run_log_dirs


PAT = re.compile(
    r"^(\d{8}-\d{6})-([^-]+)-([^-]+)-nightly-[^-]+-[^-]+-c(\d{3})-\d{8}-\d{6}\.log$"
)
LOSS_RE = re.compile(r"'train_loss':\s*'?(\d+(?:\.\d+)?)'?")


def parse_log(path: Path):
    m = PAT.match(path.name)
    if not m:
        return None

    stamp, project, task, cycle = m.groups()
    text = path.read_text(encoding="utf-8", errors="replace")
    exit_code = None
    for line in reversed(text.splitlines()):
        if line.startswith("EXIT "):
            try:
                exit_code = int(line.split()[1])
            except Exception:
                exit_code = None
            break

    lm = LOSS_RE.search(text)
    loss = float(lm.group(1)) if lm else None

    return {
        "project": project,
        "task": task,
        "cycle": int(cycle),
        "stamp": stamp,
        "loss": loss,
        "exit": exit_code,
        "name": path.name,
    }


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    log_dirs = resolve_run_log_dirs(repo_root, "training/logs/runs")

    grouped: dict[tuple[str, str], list[dict]] = {}
    seen: set[Path] = set()
    for directory in log_dirs:
        for path in directory.glob("*.log"):
            resolved = path.resolve()
            if resolved in seen:
                continue
            seen.add(resolved)
            parsed = parse_log(path)
            if parsed is None:
                continue
            key = (parsed["project"], parsed["task"])
            grouped.setdefault(key, []).append(parsed)

    if not grouped:
        print("No nightly run logs found.")
        return 0

    print("Learning Trend Summary")
    print("Logs:")
    for directory in log_dirs:
        print(f"- {directory}")
    print()

    for (project, task) in sorted(grouped):
        vals = sorted(grouped[(project, task)], key=lambda r: (r["cycle"], r["stamp"]))
        ok_vals = [r for r in vals if r["exit"] == 0 and r["loss"] is not None]
        total = len(vals)
        ok = len([r for r in vals if r["exit"] == 0])
        fail = len([r for r in vals if r["exit"] not in (0, None)])
        running = len([r for r in vals if r["exit"] is None])

        print(f"{project}/{task}: total={total} ok={ok} fail={fail} running={running}")
        if not ok_vals:
            print("  trend: insufficient completed runs with train_loss")
            print()
            continue

        first = ok_vals[0]
        last = ok_vals[-1]
        delta = last["loss"] - first["loss"]
        if delta < -0.05:
            trend = "improved"
        elif delta > 0.05:
            trend = "worse"
        else:
            trend = "flat"

        print(f"  first successful loss: {first['loss']:.3f} ({first['name']})")
        print(f"  latest successful loss: {last['loss']:.3f} ({last['name']})")
        print(f"  delta: {delta:+.3f} => {trend}")
        print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
