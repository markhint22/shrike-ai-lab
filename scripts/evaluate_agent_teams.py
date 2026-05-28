#!/usr/bin/env python3
"""Offline benchmark evaluator for autonomous team outputs."""

from __future__ import annotations

import argparse
import json
from dataclasses import dataclass
from pathlib import Path

from agents.autonomous.gitlark_memdiff_team import (
    GitlarkMemdiffEfficiencyTeam,
    MemdiffEfficiencyRequest,
)
from agents.autonomous.test_automation_team import (
    AutomationTeamRequest,
    TestAutomationTeam,
)


@dataclass
class CaseResult:
    case_id: str
    team: str
    contract_pass: bool
    keyword_score: float
    artifact_score: float
    score: float
    missing_keywords: list[str]
    missing_artifacts: list[str]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Evaluate autonomous teams against benchmark cases")
    parser.add_argument(
        "--team",
        required=True,
        choices=["test-automation", "gitlark-memdiff", "all"],
        help="Team benchmark target",
    )
    parser.add_argument(
        "--mode",
        default="dry-run",
        choices=["dry-run", "llm"],
        help="Execution mode for teams",
    )
    parser.add_argument(
        "--pass-threshold",
        type=float,
        default=0.7,
        help="Minimum average score to mark benchmark as pass",
    )
    parser.add_argument(
        "--output-json",
        default="training/logs/interventions/agent-team-benchmark.json",
        help="Path to write benchmark report JSON",
    )
    return parser.parse_args()


def load_cases(path: Path) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))


def contract_ok(payload: dict) -> bool:
    required_keys = {"team", "mode", "summary", "actions", "artifacts", "metrics", "notes"}
    if not required_keys.issubset(payload.keys()):
        return False
    return bool(payload["summary"]) and isinstance(payload["actions"], list) and isinstance(payload["artifacts"], list)


def score_case(payload: dict, case: dict, team: str) -> CaseResult:
    actions_text = " ".join(payload.get("actions", [])).lower()
    required_keywords = [k.lower() for k in case.get("required_action_keywords", [])]
    missing_keywords = [k for k in required_keywords if k not in actions_text]
    keyword_score = 1.0 if not required_keywords else (len(required_keywords) - len(missing_keywords)) / len(required_keywords)

    artifacts = set(payload.get("artifacts", []))
    required_artifacts = case.get("required_artifacts", [])
    missing_artifacts = [a for a in required_artifacts if a not in artifacts]
    artifact_score = 1.0 if not required_artifacts else (len(required_artifacts) - len(missing_artifacts)) / len(required_artifacts)

    contract_pass = contract_ok(payload)
    contract_score = 1.0 if contract_pass else 0.0

    score = round((0.4 * contract_score) + (0.35 * keyword_score) + (0.25 * artifact_score), 4)

    return CaseResult(
        case_id=case["id"],
        team=team,
        contract_pass=contract_pass,
        keyword_score=round(keyword_score, 4),
        artifact_score=round(artifact_score, 4),
        score=score,
        missing_keywords=missing_keywords,
        missing_artifacts=missing_artifacts,
    )


def run_test_automation(cases: list[dict], dry_run: bool) -> list[CaseResult]:
    team = TestAutomationTeam()
    results: list[CaseResult] = []
    for case in cases:
        payload = team.run(
            AutomationTeamRequest(
                objective=case["objective"],
                app_stack=case.get("app_stack", "unknown"),
                test_framework=case.get("test_framework", "playwright"),
                scope=case.get("scope", "smoke + regression"),
            ),
            dry_run=dry_run,
        ).to_dict()
        results.append(score_case(payload, case, "test-automation"))
    return results


def run_memdiff(cases: list[dict], dry_run: bool) -> list[CaseResult]:
    team = GitlarkMemdiffEfficiencyTeam()
    results: list[CaseResult] = []
    for case in cases:
        payload = team.run(
            MemdiffEfficiencyRequest(
                objective=case["objective"],
                query_type=case.get("query_type", "mixed"),
                freshness_sla_minutes=case.get("freshness_sla_minutes", 30),
                repo_scope=case.get("repo_scope", "gitlark"),
            ),
            dry_run=dry_run,
        ).to_dict()
        results.append(score_case(payload, case, "gitlark-memdiff"))
    return results


def summarize(results: list[CaseResult], pass_threshold: float) -> dict:
    if not results:
        return {"avg_score": 0.0, "pass": False, "cases": []}

    avg_score = round(sum(r.score for r in results) / len(results), 4)
    return {
        "avg_score": avg_score,
        "pass_threshold": pass_threshold,
        "pass": avg_score >= pass_threshold,
        "cases": [r.__dict__ for r in results],
    }


def main() -> int:
    args = parse_args()
    dry_run = args.mode == "dry-run"

    repo_root = Path(__file__).resolve().parent.parent
    ta_cases_path = repo_root / "agents" / "autonomous" / "benchmarks" / "test_automation_cases.json"
    md_cases_path = repo_root / "agents" / "autonomous" / "benchmarks" / "gitlark_memdiff_cases.json"

    report: dict = {
        "mode": args.mode,
        "team": args.team,
        "results": {},
    }

    if args.team in {"test-automation", "all"}:
        ta_results = run_test_automation(load_cases(ta_cases_path), dry_run=dry_run)
        report["results"]["test-automation"] = summarize(ta_results, args.pass_threshold)

    if args.team in {"gitlark-memdiff", "all"}:
        md_results = run_memdiff(load_cases(md_cases_path), dry_run=dry_run)
        report["results"]["gitlark-memdiff"] = summarize(md_results, args.pass_threshold)

    print(json.dumps(report, indent=2))

    output_path = Path(args.output_json)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    print(f"\nSaved benchmark report: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
