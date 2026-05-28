#!/usr/bin/env python3
"""Run autonomous agent teams in dry-run or LLM mode."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from agents.autonomous.gitlark_memdiff_team import (
    GitlarkMemdiffEfficiencyTeam,
    MemdiffEfficiencyRequest,
)
from agents.autonomous.test_automation_team import (
    AutomationTeamRequest,
    TestAutomationTeam,
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run Shrike AI Lab agent teams")
    parser.add_argument(
        "--team",
        required=True,
        choices=["test-automation", "gitlark-memdiff"],
        help="Team to run",
    )
    parser.add_argument("--objective", required=True, help="Primary objective for the team")
    parser.add_argument(
        "--mode",
        default="dry-run",
        choices=["dry-run", "llm"],
        help="Execution mode",
    )
    parser.add_argument(
        "--output-json",
        default="",
        help="Optional path to write normalized JSON output",
    )
    parser.add_argument(
        "--materialize-dir",
        default="",
        help="Optional directory to create artifact files listed in team output",
    )
    parser.add_argument("--app-stack", default="unknown", help="(test-automation) app stack")
    parser.add_argument(
        "--test-framework",
        default="playwright",
        help="(test-automation) target framework",
    )
    parser.add_argument(
        "--scope",
        default="smoke + regression",
        help="(test-automation) intended coverage scope",
    )
    parser.add_argument(
        "--query-type",
        default="mixed",
        help="(gitlark-memdiff) query class",
    )
    parser.add_argument(
        "--freshness-sla-minutes",
        type=int,
        default=30,
        help="(gitlark-memdiff) freshness SLA in minutes",
    )
    parser.add_argument(
        "--repo-scope",
        default="gitlark",
        help="(gitlark-memdiff) repository scope",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    dry_run = args.mode == "dry-run"

    if args.team == "test-automation":
        team = TestAutomationTeam()
        request = AutomationTeamRequest(
            objective=args.objective,
            app_stack=args.app_stack,
            test_framework=args.test_framework,
            scope=args.scope,
        )
    else:
        team = GitlarkMemdiffEfficiencyTeam()
        request = MemdiffEfficiencyRequest(
            objective=args.objective,
            query_type=args.query_type,
            freshness_sla_minutes=args.freshness_sla_minutes,
            repo_scope=args.repo_scope,
        )

    output = team.run(request, dry_run=dry_run)
    payload = output.to_dict()

    print(json.dumps(payload, indent=2))

    if args.output_json:
        output_path = Path(args.output_json)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")
        print(f"\nSaved output to: {output_path}")

    if args.materialize_dir:
        materialize_dir = Path(args.materialize_dir)
        materialize_dir.mkdir(parents=True, exist_ok=True)

        notes_block = _format_notes(payload.get("notes"))
        for artifact_name in payload.get("artifacts", []):
            artifact_path = materialize_dir / artifact_name
            artifact_path.parent.mkdir(parents=True, exist_ok=True)
            content = [
                f"# {artifact_name}",
                "",
                f"Team: {payload.get('team')}",
                f"Mode: {payload.get('mode')}",
                "",
                "## Summary",
                payload.get("summary", ""),
                "",
                "## Recommended Actions",
            ]
            for idx, action in enumerate(payload.get("actions", []), start=1):
                content.append(f"{idx}. {action}")

            content.extend(
                [
                    "",
                    "## Metrics",
                    "```json",
                    json.dumps(payload.get("metrics", {}), indent=2),
                    "```",
                    "",
                    "## Notes",
                    notes_block,
                    "",
                ]
            )
            artifact_path.write_text("\n".join(content), encoding="utf-8")

        notes_path = materialize_dir / "llm-notes.md"
        notes_path.write_text(
            "\n".join(
                [
                    "# LLM Notes",
                    "",
                    f"Team: {payload.get('team')}",
                    f"Mode: {payload.get('mode')}",
                    "",
                    _format_notes(payload.get("notes")),
                    "",
                ]
            ),
            encoding="utf-8",
        )

        print(f"Materialized artifacts in: {materialize_dir}")

    return 0


def _format_notes(notes: Any) -> str:
    """Render notes payload into readable markdown text."""

    if notes is None:
        return "(none)"

    if isinstance(notes, str):
        return notes.strip() or "(none)"

    if isinstance(notes, list):
        lines = []
        for item in notes:
            if isinstance(item, str):
                text = item.strip()
                if text:
                    lines.append(f"- {text}")
            elif isinstance(item, dict):
                title = str(item.get("title", "Note")).strip()
                body = str(item.get("content", item)).strip()
                lines.append(f"- {title}: {body}")
            else:
                lines.append(f"- {str(item).strip()}")
        return "\n".join(lines) if lines else "(none)"

    if isinstance(notes, dict):
        lines = []
        for key, value in notes.items():
            lines.append(f"- {key}: {value}")
        return "\n".join(lines) if lines else "(none)"

    return str(notes).strip() or "(none)"


if __name__ == "__main__":
    raise SystemExit(main())
