#!/usr/bin/env python3
"""A/B evaluation gate for promote/hold decisions.

Compares baseline vs candidate on a fixed test set and emits a decision.
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Any

from evaluate import ModelEvaluator


DEFAULT_TEST_DATA = {
    ("specpilot", "selector_optimization"): "training/specpilot/data/selector_optimization.jsonl",
    ("specpilot", "test_generation"): "training/specpilot/data/test_generation.jsonl",
    ("specpilot", "failure_analysis"): "training/specpilot/data/failure_analysis.jsonl",
    ("specpilot", "flow_analysis"): "training/specpilot/data/flow_analysis.jsonl",
    ("specpilot", "test_building"): "training/specpilot/data/test_building.jsonl",
    ("gitlark", "code_explanation"): "training/gitlark/data/code_explanation.jsonl",
    ("gitlark", "pr_description"): "training/gitlark/data/pr_descriptions.jsonl",
    ("gitlark", "code_review"): "training/gitlark/data/code_review.jsonl",
    ("gitlark", "commit_message"): "training/gitlark/data/commit_messages.jsonl",
    ("gitlark", "repo_intelligence"): "training/gitlark/data/repo_intelligence.jsonl",
    ("gitlark", "memdiff"): "training/gitlark/data/memdiff.jsonl",
    ("billwatch", "summarization"): "training/billwatch/eval/summarization_eval.jsonl",
    ("shared", "code_review"): "training/gitlark/data/code_review.jsonl",
    ("shared", "moderation"): "training/shared/data/moderation.jsonl",
    ("billwatch", "classification"): "training/billwatch/eval/classification_eval.jsonl",
    ("billwatch", "impact"): "training/billwatch/eval/impact_eval.jsonl",
    ("billwatch", "bill_background"): "training/billwatch/eval/bill_background_eval.jsonl",
    ("billwatch", "article_relevance"): "training/billwatch/eval/article_relevance_eval.jsonl",
}


def default_test_data(project: str, task: str) -> str | None:
    return DEFAULT_TEST_DATA.get((project, task))


def decide(
    baseline_accuracy: float,
    candidate_accuracy: float,
    baseline_latency_ms: float,
    candidate_latency_ms: float,
    min_accuracy_delta: float,
    max_latency_regression_pct: float,
) -> tuple[str, list[str]]:
    reasons: list[str] = []
    acc_delta = candidate_accuracy - baseline_accuracy
    latency_regression_pct = (
        ((candidate_latency_ms - baseline_latency_ms) / baseline_latency_ms) if baseline_latency_ms > 0 else 0.0
    )

    if acc_delta < min_accuracy_delta:
        reasons.append(
            f"Accuracy delta {acc_delta:+.3f} below required {min_accuracy_delta:+.3f}."
        )

    if latency_regression_pct > max_latency_regression_pct:
        reasons.append(
            "Latency regression "
            f"{latency_regression_pct:.1%} exceeds allowed {max_latency_regression_pct:.1%}."
        )

    if reasons:
        return "HOLD", reasons
    return "PROMOTE", ["Meets accuracy and latency gates."]


def _iter_prior_reports(report_path: Path, project: str, task: str) -> list[dict[str, Any]]:
    """Load prior A/B gate reports for the same project/task from the same folder."""
    reports: list[dict[str, Any]] = []
    if not report_path.parent.exists():
        return reports

    prefix = f"ab-gate-{project}-{task}-"
    for candidate in report_path.parent.glob("ab-gate-*.json"):
        name = candidate.name
        if not name.startswith(prefix):
            continue
        if candidate.resolve() == report_path.resolve():
            continue
        try:
            payload = json.loads(candidate.read_text(encoding="utf-8"))
        except Exception:
            continue
        if payload.get("project") != project or payload.get("task") != task:
            continue
        payload["_file"] = name
        reports.append(payload)

    reports.sort(key=lambda item: item.get("generated_at", ""))
    return reports


def apply_stability_rule(
    *,
    raw_decision: str,
    raw_reasons: list[str],
    project: str,
    task: str,
    baseline_model: str,
    candidate_model: str,
    current_eval_examples: int,
    json_out_path: Path | None,
    min_consecutive_promotes: int,
    min_eval_examples: int,
) -> tuple[str, list[str], dict[str, Any]]:
    """Apply stability policy on top of the raw gate decision.

    Policy:
    - Any raw HOLD remains HOLD.
    - PROMOTE requires at least N consecutive PROMOTE results.
    - PROMOTE requires decision-grade eval size (minimum examples).
    - If a later HOLD appears, streak resets; HOLD overrides earlier promote.
    """
    stability_meta: dict[str, Any] = {
        "required_consecutive_promotes": min_consecutive_promotes,
        "min_eval_examples": min_eval_examples,
        "current_eval_examples": current_eval_examples,
        "history_reports_considered": 0,
        "promote_streak": 0,
        "matching_history_reports": 0,
    }

    if raw_decision != "PROMOTE":
        return "HOLD", raw_reasons, stability_meta

    if current_eval_examples < min_eval_examples:
        return (
            "HOLD",
            raw_reasons
            + [
                f"Eval size {current_eval_examples} below decision-grade minimum {min_eval_examples}; rerun with larger limit."
            ],
            stability_meta,
        )

    if not json_out_path:
        # Without report history we cannot validate streak; fail safe.
        return (
            "HOLD",
            raw_reasons
            + [
                "No JSON output path was provided, so stability streak could not be verified.",
            ],
            stability_meta,
        )

    prior = _iter_prior_reports(json_out_path, project=project, task=task)
    stability_meta["history_reports_considered"] = len(prior)

    matching: list[dict[str, Any]] = [
        item
        for item in prior
        if item.get("baseline", {}).get("model", item.get("baseline_model")) == baseline_model
        and item.get("candidate", {}).get("model", item.get("candidate_model")) == candidate_model
    ]
    stability_meta["matching_history_reports"] = len(matching)

    streak = 1  # include current raw PROMOTE
    for item in reversed(matching):
        if item.get("decision") == "PROMOTE":
            examples = int(item.get("baseline", {}).get("total_examples", 0) or 0)
            if examples >= min_eval_examples:
                streak += 1
                continue
        break

    stability_meta["promote_streak"] = streak

    if streak < min_consecutive_promotes:
        return (
            "HOLD",
            raw_reasons
            + [
                f"PROMOTE streak {streak}/{min_consecutive_promotes} not yet met; keep HOLD until consecutive promotes are stable.",
            ],
            stability_meta,
        )

    return "PROMOTE", raw_reasons + ["Promotion stability rule satisfied."], stability_meta


async def run_gate(args: argparse.Namespace) -> int:
    evaluator = ModelEvaluator(local_url=args.local_url, local_key=args.local_key)

    if args.baseline_model == args.candidate_model:
        report: dict[str, Any] = {
            "generated_at": datetime.now().isoformat(),
            "project": args.project,
            "task": args.task,
            "test_data": args.test_data,
            "gate": {
                "min_accuracy_delta": args.min_accuracy_delta,
                "max_latency_regression_pct": args.max_latency_regression_pct,
            },
            "baseline_model": args.baseline_model,
            "candidate_model": args.candidate_model,
            "decision": "HOLD",
            "reasons": ["Baseline and candidate model names are identical; use distinct versions for promotion."],
            "deltas": {},
        }

        print("A/B Evaluation Gate")
        print(f"Project/task: {args.project}/{args.task}")
        print(f"Test data:    {args.test_data}")
        print(f"Baseline:     {args.baseline_model}")
        print(f"Candidate:    {args.candidate_model}")
        print("Decision:     HOLD")
        print("  - Baseline and candidate model names are identical; use distinct versions for promotion.")

        if args.json_out:
            out = Path(args.json_out)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(json.dumps(report, indent=2), encoding="utf-8")
            print(f"Report saved: {out}")

        return 0

    baseline = await evaluator.evaluate_test_set(
        model=args.baseline_model,
        task=args.task,
        test_data_path=args.test_data,
        system_prompt=args.system_prompt,
        limit=args.limit,
    )

    candidate = await evaluator.evaluate_test_set(
        model=args.candidate_model,
        task=args.task,
        test_data_path=args.test_data,
        system_prompt=args.system_prompt,
        limit=args.limit,
    )

    decision, reasons = decide(
        baseline_accuracy=baseline.accuracy,
        candidate_accuracy=candidate.accuracy,
        baseline_latency_ms=baseline.avg_latency_ms,
        candidate_latency_ms=candidate.avg_latency_ms,
        min_accuracy_delta=args.min_accuracy_delta,
        max_latency_regression_pct=args.max_latency_regression_pct,
    )

    final_decision, final_reasons, stability_meta = apply_stability_rule(
        raw_decision=decision,
        raw_reasons=reasons,
        project=args.project,
        task=args.task,
        baseline_model=args.baseline_model,
        candidate_model=args.candidate_model,
        current_eval_examples=baseline.total_examples,
        json_out_path=(Path(args.json_out) if args.json_out else None),
        min_consecutive_promotes=max(1, args.min_consecutive_promotes),
        min_eval_examples=max(1, args.min_eval_examples),
    )

    report: dict[str, Any] = {
        "generated_at": datetime.now().isoformat(),
        "project": args.project,
        "task": args.task,
        "test_data": args.test_data,
        "gate": {
            "min_accuracy_delta": args.min_accuracy_delta,
            "max_latency_regression_pct": args.max_latency_regression_pct,
        },
        "baseline": asdict(baseline),
        "candidate": asdict(candidate),
        "raw_decision": decision,
        "raw_reasons": reasons,
        "decision": final_decision,
        "reasons": final_reasons,
        "stability": stability_meta,
        "deltas": {
            "accuracy": candidate.accuracy - baseline.accuracy,
            "avg_latency_ms": candidate.avg_latency_ms - baseline.avg_latency_ms,
            "latency_regression_pct": (
                ((candidate.avg_latency_ms - baseline.avg_latency_ms) / baseline.avg_latency_ms)
                if baseline.avg_latency_ms > 0
                else 0.0
            ),
            "total_tokens": candidate.total_tokens - baseline.total_tokens,
        },
    }

    print("A/B Evaluation Gate")
    print(f"Project/task: {args.project}/{args.task}")
    print(f"Test data:    {args.test_data}")
    print(f"Baseline:     {args.baseline_model} (accuracy={baseline.accuracy:.1%}, latency={baseline.avg_latency_ms:.0f}ms)")
    print(f"Candidate:    {args.candidate_model} (accuracy={candidate.accuracy:.1%}, latency={candidate.avg_latency_ms:.0f}ms)")
    print(f"Decision:     {final_decision}")
    if final_decision != decision:
        print(f"Raw decision: {decision} (overridden by stability policy)")
    for reason in final_reasons:
        print(f"  - {reason}")

    if args.json_out:
        out = Path(args.json_out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"Report saved: {out}")

    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="A/B evaluation gate for model promotion")
    parser.add_argument("--project", required=True, help="Project name (specpilot, gitlark, billwatch, shared)")
    parser.add_argument("--task", required=True, help="Task name")
    parser.add_argument("--baseline-model", required=True, help="Baseline model name exposed by LiteLLM")
    parser.add_argument("--candidate-model", required=True, help="Candidate model name exposed by LiteLLM")
    parser.add_argument("--test-data", help="Path to held-out JSONL test data")
    parser.add_argument("--system-prompt", default="", help="Optional system prompt")
    parser.add_argument("--limit", type=int, default=20, help="Max examples to evaluate (default: 20)")

    parser.add_argument(
        "--min-accuracy-delta",
        type=float,
        default=0.02,
        help="Minimum candidate-baseline accuracy delta required for PROMOTE (default: 0.02)",
    )
    parser.add_argument(
        "--max-latency-regression-pct",
        type=float,
        default=0.20,
        help="Max allowed latency regression as fraction (default: 0.20 = 20%%)",
    )
    parser.add_argument(
        "--min-consecutive-promotes",
        type=int,
        default=2,
        help="Consecutive PROMOTE runs required before final PROMOTE (default: 2)",
    )
    parser.add_argument(
        "--min-eval-examples",
        type=int,
        default=10,
        help="Minimum examples required for promotion-grade evaluation (default: 10)",
    )

    parser.add_argument("--json-out", help="Optional JSON report output path")
    parser.add_argument("--local-url", default="http://localhost:4000", help="LiteLLM URL")
    parser.add_argument("--local-key", default="sk-shrike-local", help="LiteLLM API key")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if not args.test_data:
        guessed = default_test_data(args.project, args.task)
        if not guessed:
            raise SystemExit("No default test set for this project/task. Pass --test-data explicitly.")
        args.test_data = guessed

    if not Path(args.test_data).exists():
        raise SystemExit(f"Test data file not found: {args.test_data}")

    import asyncio

    return asyncio.run(run_gate(args))


if __name__ == "__main__":
    raise SystemExit(main())
