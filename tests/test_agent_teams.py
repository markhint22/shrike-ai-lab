"""Tests for autonomous team scaffolding outputs."""

from agents.autonomous.gitlark_memdiff_team import (
    GitlarkMemdiffEfficiencyTeam,
    MemdiffEfficiencyRequest,
)
from agents.autonomous.test_automation_team import (
    AutomationTeamRequest,
    TestAutomationTeam,
)


def test_test_automation_team_dry_run_contract() -> None:
    team = TestAutomationTeam()
    output = team.run(
        AutomationTeamRequest(objective="Build smoke suite for auth + dashboard"),
        dry_run=True,
    )

    payload = output.to_dict()
    assert payload["team"] == "test-automation-team"
    assert payload["mode"] == "dry-run"
    assert payload["summary"]
    assert len(payload["actions"]) >= 4
    assert "playwright-suite-seed.spec.ts" in payload["artifacts"]
    assert "target_flake_rate_max" in payload["metrics"]


def test_memdiff_team_dry_run_contract() -> None:
    team = GitlarkMemdiffEfficiencyTeam()
    output = team.run(
        MemdiffEfficiencyRequest(
            objective="Reduce memdiff over-refresh cost",
            query_type="freshness-sensitive",
            freshness_sla_minutes=10,
        ),
        dry_run=True,
    )

    payload = output.to_dict()
    assert payload["team"] == "gitlark-memdiff-efficiency-team"
    assert payload["mode"] == "dry-run"
    assert payload["summary"]
    assert len(payload["actions"]) >= 4
    assert "query-to-scope-mapping.json" in payload["artifacts"]
    assert payload["metrics"]["target_cache_hit_ratio_min"] >= 0.5
