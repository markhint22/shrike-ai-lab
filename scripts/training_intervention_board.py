#!/usr/bin/env python3
"""Human intervention dashboard for nightly training decisions.

This script turns raw logs into actionable review gates.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

PAT = re.compile(
    r"^(\d{8}-\d{6})-([^-]+)-([^-]+)-nightly-[^-]+-[^-]+-c(\d{3})-\d{8}-\d{6}\.log$"
)
LOSS_RE = re.compile(r"'train_loss':\s*'?(\d+(?:\.\d+)?)'?")


@dataclass
class RunInfo:
    project: str
    task: str
    cycle: int
    stamp: str
    loss: float | None
    exit_code: int | None
    name: str
    mtime: datetime


@dataclass
class BoardRow:
    project: str
    task: str
    status_24h: str
    ok_24h: int
    fail_24h: int
    running_24h: int
    fail_rate_24h: float
    latest_success_loss: float | None
    trend: str
    recommendation: str
    reason: str


def parse_log(path: Path) -> RunInfo | None:
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

    return RunInfo(
        project=project,
        task=task,
        cycle=int(cycle),
        stamp=stamp,
        loss=loss,
        exit_code=exit_code,
        name=path.name,
        mtime=datetime.fromtimestamp(path.stat().st_mtime),
    )


def health_label(ok: int, fail: int, running: int) -> str:
    if running > 0:
        return "IN_PROGRESS"
    if ok > 0 and fail == 0:
        return "HEALTHY"
    if ok > 0 and fail > 0:
        return "MIXED"
    return "UNHEALTHY"


def trend_from_successes(success_runs: list[RunInfo], threshold: float) -> str:
    with_loss = [r for r in success_runs if r.loss is not None]
    if len(with_loss) < 2:
        return "unknown"

    first = with_loss[0].loss
    last = with_loss[-1].loss
    assert first is not None and last is not None
    delta = last - first

    if delta < -threshold:
        return "improving"
    if delta > threshold:
        return "regressing"
    return "flat"


def compute_recommendation(
    ok_24h: int,
    fail_24h: int,
    running_24h: int,
    fail_rate_24h: float,
    trend: str,
    min_success_runs: int,
    max_fail_rate: float,
) -> tuple[str, str]:
    if running_24h > 0:
        return (
            "WAIT_RUNNING",
            "At least one run is still active; wait for completion before review.",
        )

    if ok_24h >= min_success_runs and fail_rate_24h <= max_fail_rate and trend in {"improving", "flat", "unknown"}:
        return (
            "READY_REVIEW",
            f"Meets gate: >= {min_success_runs} successful runs in 24h with fail_rate <= {max_fail_rate:.2f}.",
        )

    if fail_24h >= min_success_runs and ok_24h == 0:
        return (
            "BLOCKED",
            "Repeated failures with no successful completion in 24h; fix stability before training more.",
        )

    if fail_rate_24h > max_fail_rate:
        return (
            "INVESTIGATE_STABILITY",
            "Failure rate exceeds threshold; prioritize crash/infra troubleshooting.",
        )

    if trend == "regressing":
        return (
            "RETUNE_DATA",
            "Loss trend regressing across successful runs; inspect data quality and hyperparameters.",
        )

    return (
        "COLLECT_MORE_RUNS",
        f"Need more successful runs to reach review gate (target: {min_success_runs} in 24h).",
    )


def build_rows(
    runs_by_key: dict[tuple[str, str], list[RunInfo]],
    hours: int,
    min_success_runs: int,
    max_fail_rate: float,
    trend_threshold: float,
) -> list[BoardRow]:
    window_start = datetime.now() - timedelta(hours=hours)
    rows: list[BoardRow] = []

    for (project, task), runs in sorted(runs_by_key.items()):
        vals = sorted(runs, key=lambda r: (r.cycle, r.stamp))
        recent = [r for r in vals if r.mtime >= window_start]

        ok_recent = [r for r in recent if r.exit_code == 0]
        fail_recent = [r for r in recent if r.exit_code not in (0, None)]
        running_recent = [r for r in recent if r.exit_code is None]

        attempts_completed = len(ok_recent) + len(fail_recent)
        fail_rate = (len(fail_recent) / attempts_completed) if attempts_completed else 0.0

        all_ok = [r for r in vals if r.exit_code == 0]
        latest_success_loss = None
        with_loss = [r for r in all_ok if r.loss is not None]
        if with_loss:
            latest_success_loss = with_loss[-1].loss

        trend = trend_from_successes(all_ok, threshold=trend_threshold)

        rec, reason = compute_recommendation(
            ok_24h=len(ok_recent),
            fail_24h=len(fail_recent),
            running_24h=len(running_recent),
            fail_rate_24h=fail_rate,
            trend=trend,
            min_success_runs=min_success_runs,
            max_fail_rate=max_fail_rate,
        )

        rows.append(
            BoardRow(
                project=project,
                task=task,
                status_24h=health_label(len(ok_recent), len(fail_recent), len(running_recent)),
                ok_24h=len(ok_recent),
                fail_24h=len(fail_recent),
                running_24h=len(running_recent),
                fail_rate_24h=fail_rate,
                latest_success_loss=latest_success_loss,
                trend=trend,
                recommendation=rec,
                reason=reason,
            )
        )

    return rows


def print_board(rows: list[BoardRow], hours: int, min_success_runs: int, max_fail_rate: float) -> None:
    print("Training Intervention Dashboard")
    print(f"Window: last {hours}h | Review gate: >= {min_success_runs} successful runs | Max fail rate: {max_fail_rate:.2f}")
    print()

    for r in rows:
        loss_str = f"{r.latest_success_loss:.3f}" if r.latest_success_loss is not None else "n/a"
        print(f"{r.project}/{r.task}")
        print(
            f"  status={r.status_24h} ok={r.ok_24h} fail={r.fail_24h} running={r.running_24h} fail_rate={r.fail_rate_24h:.2f}"
        )
        print(f"  trend={r.trend} latest_success_loss={loss_str}")
        print(f"  recommendation={r.recommendation}")
        print(f"  reason={r.reason}")
        print()

    ready = [r for r in rows if r.recommendation == "READY_REVIEW"]
    print("HUMAN INTERVENTION QUEUE")
    if ready:
        for r in ready:
            print(f"  - {r.project}/{r.task}")
    else:
        print("  - none")


def write_json(path: Path, rows: list[BoardRow], args: argparse.Namespace) -> None:
    payload: dict[str, Any] = {
        "generated_at": datetime.now().isoformat(),
        "window_hours": args.hours,
        "min_success_runs": args.min_success_runs,
        "max_fail_rate": args.max_fail_rate,
        "trend_threshold": args.trend_threshold,
        "rows": [asdict(r) for r in rows],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def load_runs(logs_dir: Path, project_filter: str | None = None) -> dict[tuple[str, str], list[RunInfo]]:
    grouped: dict[tuple[str, str], list[RunInfo]] = {}

    for path in logs_dir.glob("*.log"):
        parsed = parse_log(path)
        if parsed is None:
            continue
        if project_filter and parsed.project != project_filter:
            continue
        key = (parsed.project, parsed.task)
        grouped.setdefault(key, []).append(parsed)

    return grouped


def render_once(args: argparse.Namespace) -> int:
    repo_root = Path(__file__).resolve().parent.parent
    logs_dir = repo_root / args.logs_dir

    grouped = load_runs(logs_dir=logs_dir, project_filter=args.project)
    if not grouped:
        print(f"No nightly logs found in {logs_dir}")
        return 0

    rows = build_rows(
        runs_by_key=grouped,
        hours=args.hours,
        min_success_runs=args.min_success_runs,
        max_fail_rate=args.max_fail_rate,
        trend_threshold=args.trend_threshold,
    )

    print_board(rows, hours=args.hours, min_success_runs=args.min_success_runs, max_fail_rate=args.max_fail_rate)

    if args.json_out:
        write_json(Path(args.json_out), rows, args)
        print()
        print(f"Wrote JSON report: {args.json_out}")

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Human intervention dashboard for training runs")
    parser.add_argument("--logs-dir", default="training/logs", help="Logs directory relative to repo root")
    parser.add_argument("--hours", type=int, default=24, help="Lookback window in hours")
    parser.add_argument(
        "--min-success-runs",
        type=int,
        default=2,
        help="Successful runs needed inside window before manual review gate",
    )
    parser.add_argument(
        "--max-fail-rate",
        type=float,
        default=0.50,
        help="Maximum tolerated fail rate in window for READY_REVIEW",
    )
    parser.add_argument(
        "--trend-threshold",
        type=float,
        default=0.05,
        help="Absolute loss delta threshold used to classify trend",
    )
    parser.add_argument("--project", help="Optional project filter (e.g., billwatch)")
    parser.add_argument("--json-out", help="Optional path to write machine-readable JSON report")
    parser.add_argument("--watch", action="store_true", help="Refresh the dashboard continuously")
    parser.add_argument("--interval", type=int, default=60, help="Watch refresh interval in seconds")
    return parser.parse_args()


def clear_screen() -> None:
    os.system("cls" if os.name == "nt" else "clear")


def main() -> int:
    args = parse_args()

    if not args.watch:
        return render_once(args)

    while True:
        clear_screen()
        render_once(args)
        print()
        print(f"Refreshing in {args.interval}s... Press Ctrl+C to stop.")
        time.sleep(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
