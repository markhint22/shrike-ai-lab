#!/usr/bin/env python3
"""Decide GO/HOLD for agent teams from benchmark scorecards."""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path

try:
    from scripts.auto_apply_agent_team_promotions import apply_decisions
except ModuleNotFoundError:
    from auto_apply_agent_team_promotions import apply_decisions


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Decide agent team promotion from benchmark report")
    parser.add_argument(
        "--benchmark-report",
        default="training/logs/interventions/agent-team-benchmark.json",
        help="Benchmark report JSON path",
    )
    parser.add_argument(
        "--thresholds",
        default="configs/agent_team_promotion_thresholds.json",
        help="Threshold config JSON path",
    )
    parser.add_argument(
        "--output-json",
        default="training/logs/interventions/agent-team-promotion-decision.json",
        help="Decision output JSON path",
    )
    parser.add_argument(
        "--tickets-dir",
        default="training/logs/interventions/agent-team-tickets",
        help="Directory for generated markdown tickets",
    )
    parser.add_argument(
        "--auto-apply",
        action="store_true",
        help="Automatically apply GO/HOLD decisions to rollout and promotion queue files",
    )
    parser.add_argument(
        "--rollout-json",
        default="configs/agent_team_rollout.json",
        help="Rollout state JSON path used by auto-apply",
    )
    parser.add_argument(
        "--queue-json",
        default="training/queue/agent_team_promotions.json",
        help="Promotion audit queue JSON path used by auto-apply",
    )
    parser.add_argument(
        "--apply-hold-disable",
        action="store_true",
        help="When auto-apply is enabled, HOLD decisions also disable team rollout",
    )
    parser.add_argument(
        "--hold-streak-limit",
        type=int,
        default=3,
        help="Consecutive HOLD decisions before auto-pausing rollout",
    )
    return parser.parse_args()


def load_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def decide_team(team_name: str, result_block: dict, threshold_block: dict) -> dict:
    avg_score = float(result_block.get("avg_score", 0.0))
    min_avg = float(threshold_block.get("benchmark_min_avg_score", 0.8))
    required_case_min = float(threshold_block.get("required_case_min_score", 0.75))
    max_missing_keywords = int(threshold_block.get("max_missing_keywords_per_case", 2))
    max_missing_artifacts = int(threshold_block.get("max_missing_artifacts_per_case", 1))

    reasons: list[str] = []
    if avg_score < min_avg:
        reasons.append(f"avg_score {avg_score:.4f} below threshold {min_avg:.4f}")

    for case in result_block.get("cases", []):
        case_id = case.get("case_id", "unknown")
        case_score = float(case.get("score", 0.0))
        missing_keywords = case.get("missing_keywords", [])
        missing_artifacts = case.get("missing_artifacts", [])

        if case_score < required_case_min:
            reasons.append(f"{case_id} score {case_score:.4f} below required minimum {required_case_min:.4f}")
        if len(missing_keywords) > max_missing_keywords:
            reasons.append(
                f"{case_id} missing keywords {len(missing_keywords)} exceeds limit {max_missing_keywords}"
            )
        if len(missing_artifacts) > max_missing_artifacts:
            reasons.append(
                f"{case_id} missing artifacts {len(missing_artifacts)} exceeds limit {max_missing_artifacts}"
            )

    decision = "GO" if not reasons else "HOLD"
    return {
        "team": team_name,
        "decision": decision,
        "avg_score": avg_score,
        "reasons": reasons,
    }


def write_ticket(ticket_dir: Path, decision: dict) -> Path:
    ticket_dir.mkdir(parents=True, exist_ok=True)
    slug = decision["team"].replace("/", "-")
    out = ticket_dir / f"{slug}-promotion-{decision['decision'].lower()}.md"

    lines = [
        f"# Agent Team Promotion Decision: {decision['team']}",
        "",
        f"- Timestamp: {datetime.now().isoformat()}",
        f"- Decision: **{decision['decision']}**",
        f"- Average Score: {decision['avg_score']:.4f}",
        "",
    ]

    if decision["reasons"]:
        lines.append("## Hold Reasons")
        lines.append("")
        for reason in decision["reasons"]:
            lines.append(f"- {reason}")
    else:
        lines.append("## Promotion Notes")
        lines.append("")
        lines.append("- All benchmark thresholds satisfied.")
        lines.append("- Ready for controlled rollout.")

    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return out


def main() -> int:
    args = parse_args()

    benchmark = load_json(Path(args.benchmark_report))
    thresholds = load_json(Path(args.thresholds))

    decisions: list[dict] = []
    ticket_paths: list[str] = []

    result_map = benchmark.get("results", {})
    for team_name, block in result_map.items():
        threshold_block = thresholds.get(team_name, {})
        decision = decide_team(team_name, block, threshold_block)
        decisions.append(decision)

        ticket_path = write_ticket(Path(args.tickets_dir), decision)
        ticket_paths.append(str(ticket_path))

    payload = {
        "timestamp": datetime.now().isoformat(),
        "decisions": decisions,
        "tickets": ticket_paths,
    }

    out_path = Path(args.output_json)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    if args.auto_apply:
        apply_result = apply_decisions(
            payload,
            rollout_json=Path(args.rollout_json),
            queue_json=Path(args.queue_json),
            apply_hold_disable=bool(args.apply_hold_disable),
            hold_streak_limit=max(1, int(args.hold_streak_limit)),
        )
        payload["auto_apply"] = apply_result
        out_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(json.dumps(payload, indent=2))
    print(f"\nSaved decision report: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
