"""Tests for autonomous team benchmark evaluator."""

from pathlib import Path

from scripts.evaluate_agent_teams import contract_ok, load_cases, score_case


def test_contract_ok_true_for_valid_payload() -> None:
    payload = {
        "team": "demo-team",
        "mode": "dry-run",
        "summary": "ok",
        "actions": ["a"],
        "artifacts": ["b"],
        "metrics": {"m": 1},
        "notes": ["n"],
    }
    assert contract_ok(payload)


def test_contract_ok_false_when_missing_fields() -> None:
    payload = {
        "team": "demo-team",
        "summary": "ok",
        "actions": ["a"],
    }
    assert not contract_ok(payload)


def test_score_case_detects_missing_keyword_and_artifact() -> None:
    payload = {
        "team": "demo",
        "mode": "dry-run",
        "summary": "summary",
        "actions": ["use cache strategy"],
        "artifacts": ["a.md"],
        "metrics": {},
        "notes": [],
    }
    case = {
        "id": "c1",
        "required_action_keywords": ["cache", "freshness"],
        "required_artifacts": ["a.md", "b.md"],
    }

    result = score_case(payload, case, "team-x")
    assert result.contract_pass is True
    assert "freshness" in result.missing_keywords
    assert "b.md" in result.missing_artifacts
    assert result.score < 1.0


def test_load_cases_reads_benchmark_fixture() -> None:
    path = Path("agents/autonomous/benchmarks/test_automation_cases.json")
    cases = load_cases(path)
    assert len(cases) >= 1
    assert "id" in cases[0]
