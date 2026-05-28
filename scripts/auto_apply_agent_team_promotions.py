#!/usr/bin/env python3
"""Auto-apply agent team promotion decisions.

Reads GO/HOLD decisions and updates:
1) rollout state (configs/agent_team_rollout.json)
2) promotion audit queue (training/queue/agent_team_promotions.json)
"""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any


def _load_json(path: Path, default_payload: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return default_payload
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default_payload


def _save_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def apply_decisions(
    decision_payload: dict[str, Any],
    *,
    rollout_json: Path,
    queue_json: Path,
    apply_hold_disable: bool,
    hold_streak_limit: int,
) -> dict[str, Any]:
    now = datetime.now().isoformat()
    decision_timestamp = str(decision_payload.get("timestamp", now))

    limit = max(1, int(hold_streak_limit))

    rollout = _load_json(
        rollout_json,
        {
            "generated_at": now,
            "policy": {"hold_streak_limit": limit},
            "teams": {},
        },
    )
    policy = rollout.setdefault("policy", {})
    policy["hold_streak_limit"] = limit
    rollout_teams = rollout.setdefault("teams", {})

    queue = _load_json(queue_json, {"generated_at": now, "promotions": []})
    queue_items: list[dict[str, Any]] = list(queue.get("promotions", []))

    applied: list[dict[str, Any]] = []

    for decision in decision_payload.get("decisions", []):
        team = str(decision.get("team", "")).strip()
        state = str(decision.get("decision", "")).strip().upper()
        avg_score = float(decision.get("avg_score", 0.0))
        reasons = [str(r) for r in decision.get("reasons", [])]
        if not team or state not in {"GO", "HOLD"}:
            continue

        previous = rollout_teams.get(team, {})
        previous_decision = str(previous.get("last_decision", "")).upper()
        previous_hold_streak = int(previous.get("hold_streak", 0) or 0)

        if state == "HOLD":
            hold_streak = previous_hold_streak + 1 if previous_decision == "HOLD" else 1
        else:
            hold_streak = 0

        intervention_required = hold_streak >= limit

        if state == "GO":
            enabled = True
        elif intervention_required:
            enabled = False
        elif apply_hold_disable:
            enabled = False
        else:
            # HOLD is recorded but does not auto-disable unless explicitly requested.
            enabled = bool(previous.get("enabled", True))

        pause_reason = ""
        if state == "HOLD" and intervention_required:
            pause_reason = (
                f"Auto-paused after {hold_streak} consecutive HOLD decisions "
                f"(limit={limit}); human intervention required."
            )

        rollout_teams[team] = {
            "enabled": enabled,
            "last_decision": state,
            "hold_streak": hold_streak,
            "intervention_required": intervention_required,
            "pause_reason": pause_reason,
            "avg_score": avg_score,
            "reasons": reasons,
            "decision_timestamp": decision_timestamp,
            "applied_at": now,
        }

        duplicate = any(
            item.get("team") == team
            and item.get("decision_timestamp") == decision_timestamp
            and item.get("decision") == state
            for item in queue_items
        )

        if not duplicate:
            queue_items.append(
                {
                    "team": team,
                    "decision": state,
                    "enabled": enabled,
                    "hold_streak": hold_streak,
                    "intervention_required": intervention_required,
                    "pause_reason": pause_reason,
                    "avg_score": avg_score,
                    "reasons": reasons,
                    "decision_timestamp": decision_timestamp,
                    "applied_at": now,
                    "source": "agent-team-promotion-decision",
                }
            )

        applied.append(
            {
                "team": team,
                "decision": state,
                "enabled": enabled,
                "hold_streak": hold_streak,
                "intervention_required": intervention_required,
                "pause_reason": pause_reason,
                "avg_score": avg_score,
                "decision_timestamp": decision_timestamp,
            }
        )

    rollout["generated_at"] = now
    queue["generated_at"] = now
    queue["promotions"] = queue_items

    _save_json(rollout_json, rollout)
    _save_json(queue_json, queue)

    return {
        "applied_at": now,
        "hold_streak_limit": limit,
        "rollout_json": str(rollout_json),
        "queue_json": str(queue_json),
        "applied": applied,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Auto-apply agent team promotions")
    parser.add_argument(
        "--decision-json",
        default="training/logs/interventions/agent-team-promotion-decision.json",
        help="Decision report JSON path",
    )
    parser.add_argument(
        "--rollout-json",
        default="configs/agent_team_rollout.json",
        help="Rollout state JSON path",
    )
    parser.add_argument(
        "--queue-json",
        default="training/queue/agent_team_promotions.json",
        help="Promotion audit queue JSON path",
    )
    parser.add_argument(
        "--apply-hold-disable",
        action="store_true",
        help="When set, HOLD decisions automatically disable team rollout",
    )
    parser.add_argument(
        "--hold-streak-limit",
        type=int,
        default=3,
        help="Consecutive HOLD decisions required before auto-pausing team rollout",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    decision_path = Path(args.decision_json)
    if not decision_path.exists():
        raise SystemExit(f"Decision JSON not found: {decision_path}")

    decision_payload = json.loads(decision_path.read_text(encoding="utf-8"))
    result = apply_decisions(
        decision_payload,
        rollout_json=Path(args.rollout_json),
        queue_json=Path(args.queue_json),
        apply_hold_disable=bool(args.apply_hold_disable),
        hold_streak_limit=max(1, int(args.hold_streak_limit)),
    )
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
