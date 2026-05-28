#!/usr/bin/env python3
"""Clear intervention pause and resume agent-team rollout."""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any


DEFAULT_ROLLOUT = "configs/agent_team_rollout.json"


def _load_json(path: Path, default_payload: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return default_payload
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return default_payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Resume paused agent-team rollout state")
    parser.add_argument(
        "--team",
        action="append",
        dest="teams",
        help="Team id to resume (repeat for multiple teams)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Resume all teams found in rollout JSON",
    )
    parser.add_argument(
        "--rollout-json",
        default=DEFAULT_ROLLOUT,
        help="Rollout state JSON path",
    )
    parser.add_argument(
        "--reason",
        default="Manual intervention completed.",
        help="Reason included in resume metadata",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    rollout_path = Path(args.rollout_json)
    payload = _load_json(rollout_path, {"generated_at": datetime.now().isoformat(), "teams": {}})
    teams = payload.setdefault("teams", {})

    requested = set(args.teams or [])
    if args.all:
        requested = set(teams.keys())

    if not requested:
        raise SystemExit("No teams selected. Use --team <id> or --all.")

    now = datetime.now().isoformat()
    resumed: list[str] = []
    missing: list[str] = []

    for team in sorted(requested):
        state = teams.get(team)
        if state is None:
            missing.append(team)
            continue

        state["enabled"] = True
        state["hold_streak"] = 0
        state["intervention_required"] = False
        state["pause_reason"] = ""
        state["resumed_at"] = now
        state["resume_reason"] = args.reason
        resumed.append(team)

    payload["generated_at"] = now
    rollout_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(
        json.dumps(
            {
                "timestamp": now,
                "rollout_json": str(rollout_path),
                "resumed": resumed,
                "missing": missing,
                "reason": args.reason,
            },
            indent=2,
        )
    )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
