#!/usr/bin/env python3
"""Review and consume A/B gate reports.

Applies stability promotion policy to historical gate files, writes a summary,
and optionally archives consumed files so unresolved gates remain visible.
"""

from __future__ import annotations

import argparse
import json
import shutil
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Any


@dataclass
class GateRecord:
    file_path: Path
    project: str
    task: str
    generated_at: str
    decision: str
    baseline_examples: int


@dataclass
class GroupOutcome:
    project: str
    task: str
    total_reports: int
    latest_file: str | None
    latest_decision: str | None
    promote_streak: int
    promoted: bool
    reason: str
    moved_to_consumed: list[str]
    moved_to_promoted: list[str]


def parse_gate(path: Path) -> GateRecord | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None

    project = payload.get("project")
    task = payload.get("task")
    decision = payload.get("decision")
    if not project or not task or not decision:
        return None

    baseline_examples = int(payload.get("baseline", {}).get("total_examples", 0) or 0)
    generated_at = payload.get("generated_at") or datetime.fromtimestamp(path.stat().st_mtime).isoformat()

    return GateRecord(
        file_path=path,
        project=str(project),
        task=str(task),
        generated_at=str(generated_at),
        decision=str(decision),
        baseline_examples=baseline_examples,
    )


def safe_move(src: Path, dest: Path) -> str:
    dest.parent.mkdir(parents=True, exist_ok=True)
    candidate = dest
    if candidate.exists():
        stem = candidate.stem
        suffix = candidate.suffix
        i = 1
        while True:
            alt = candidate.with_name(f"{stem}-{i}{suffix}")
            if not alt.exists():
                candidate = alt
                break
            i += 1
    shutil.move(str(src), str(candidate))
    return candidate.name


def promote_streak(records: list[GateRecord], min_eval_examples: int) -> int:
    streak = 0
    for record in reversed(records):
        if record.decision == "PROMOTE" and record.baseline_examples >= min_eval_examples:
            streak += 1
        else:
            break
    return streak


def main() -> int:
    parser = argparse.ArgumentParser(description="Review and consume A/B gate reports")
    parser.add_argument("--ab-gates-dir", default="training/logs/ab-gates", help="Directory containing A/B gate JSON files")
    parser.add_argument("--required-consecutive-promotes", type=int, default=2, help="Consecutive PROMOTE files required")
    parser.add_argument("--min-eval-examples", type=int, default=10, help="Minimum eval examples for promotion-grade reports")
    parser.add_argument("--apply-moves", action="store_true", help="Move consumed/promoted files on disk")
    parser.add_argument(
        "--summary-out",
        default="training/logs/interventions/ab-gate-review-summary.json",
        help="Path for JSON summary output",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    ab_dir = (repo_root / args.ab_gates_dir).resolve()
    if not ab_dir.exists():
        raise SystemExit(f"A/B gate directory not found: {ab_dir}")

    active_files = [
        p for p in ab_dir.glob("ab-gate-*.json")
        if p.is_file() and p.parent == ab_dir and "-consumed" not in p.name and "-promoted" not in p.name
    ]

    grouped: dict[tuple[str, str], list[GateRecord]] = {}
    skipped = 0
    for gate_file in active_files:
        rec = parse_gate(gate_file)
        if rec is None:
            skipped += 1
            continue
        grouped.setdefault((rec.project, rec.task), []).append(rec)

    consumed_dir = ab_dir / "consumed"
    promoted_dir = ab_dir / "promoted"

    outcomes: list[GroupOutcome] = []

    for (project, task), recs in sorted(grouped.items()):
        recs.sort(key=lambda r: r.generated_at)
        latest = recs[-1] if recs else None
        streak = promote_streak(recs, min_eval_examples=max(1, args.min_eval_examples))

        promoted = (
            latest is not None
            and latest.decision == "PROMOTE"
            and latest.baseline_examples >= max(1, args.min_eval_examples)
            and streak >= max(1, args.required_consecutive_promotes)
        )

        if latest is None:
            reason = "No records"
        elif promoted:
            reason = (
                f"Stable promote streak {streak}/{max(1, args.required_consecutive_promotes)} "
                f"with eval size {latest.baseline_examples}."
            )
        else:
            reason = (
                f"Needs review: latest={latest.decision}, streak={streak}/{max(1, args.required_consecutive_promotes)}, "
                f"examples={latest.baseline_examples}."
            )

        moved_consumed: list[str] = []
        moved_promoted: list[str] = []

        older = recs[:-1]
        if args.apply_moves:
            for old in older:
                stamp = old.generated_at[:10].replace("-", "") if old.generated_at else "unknown"
                dest = consumed_dir / stamp / old.file_path.name
                moved_consumed.append(safe_move(old.file_path, dest))

            if promoted and latest is not None:
                stamp = latest.generated_at[:10].replace("-", "") if latest.generated_at else "unknown"
                dest = promoted_dir / stamp / latest.file_path.name
                moved_promoted.append(safe_move(latest.file_path, dest))

        outcomes.append(
            GroupOutcome(
                project=project,
                task=task,
                total_reports=len(recs),
                latest_file=(latest.file_path.name if latest else None),
                latest_decision=(latest.decision if latest else None),
                promote_streak=streak,
                promoted=promoted,
                reason=reason,
                moved_to_consumed=moved_consumed,
                moved_to_promoted=moved_promoted,
            )
        )

    summary = {
        "generated_at": datetime.now().isoformat(),
        "ab_gates_dir": str(ab_dir),
        "required_consecutive_promotes": max(1, args.required_consecutive_promotes),
        "min_eval_examples": max(1, args.min_eval_examples),
        "groups": [asdict(o) for o in outcomes],
        "group_count": len(outcomes),
        "promoted_count": sum(1 for o in outcomes if o.promoted),
        "needs_review_count": sum(1 for o in outcomes if not o.promoted),
        "skipped_files": skipped,
        "apply_moves": bool(args.apply_moves),
    }

    summary_path = (repo_root / args.summary_out).resolve()
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print("A/B Gate Review Summary")
    print(f"Groups: {summary['group_count']} | Promoted: {summary['promoted_count']} | Needs review: {summary['needs_review_count']}")
    print(f"Summary saved: {summary_path}")

    for o in outcomes:
        state = "PROMOTED" if o.promoted else "REVIEW"
        print(f"- {o.project}/{o.task}: {state} | {o.reason}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
