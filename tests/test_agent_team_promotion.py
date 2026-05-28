"""Tests for agent team promotion decision logic."""

from scripts.decide_agent_team_promotion import decide_team


def test_decide_team_go_when_thresholds_met() -> None:
    result_block = {
        "avg_score": 0.9,
        "cases": [
            {
                "case_id": "c1",
                "score": 0.85,
                "missing_keywords": ["x"],
                "missing_artifacts": [],
            }
        ],
    }
    thresholds = {
        "benchmark_min_avg_score": 0.8,
        "required_case_min_score": 0.75,
        "max_missing_keywords_per_case": 2,
        "max_missing_artifacts_per_case": 1,
    }

    decision = decide_team("team-a", result_block, thresholds)
    assert decision["decision"] == "GO"
    assert decision["reasons"] == []


def test_decide_team_hold_when_case_below_threshold() -> None:
    result_block = {
        "avg_score": 0.85,
        "cases": [
            {
                "case_id": "c1",
                "score": 0.6,
                "missing_keywords": ["x", "y", "z"],
                "missing_artifacts": ["a", "b"],
            }
        ],
    }
    thresholds = {
        "benchmark_min_avg_score": 0.8,
        "required_case_min_score": 0.75,
        "max_missing_keywords_per_case": 2,
        "max_missing_artifacts_per_case": 1,
    }

    decision = decide_team("team-b", result_block, thresholds)
    assert decision["decision"] == "HOLD"
    assert len(decision["reasons"]) >= 1
