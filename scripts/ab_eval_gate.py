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
    ("gitlark", "code_review"): "training/gitlark/data/code_review.jsonl",
    ("shared", "code_review"): "training/gitlark/data/code_review.jsonl",
    ("billwatch", "classification"): "training/billwatch/data/classification.jsonl",
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


async def run_gate(args: argparse.Namespace) -> int:
    evaluator = ModelEvaluator(local_url=args.local_url, local_key=args.local_key)

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
        "decision": decision,
        "reasons": reasons,
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
    print(f"Decision:     {decision}")
    for reason in reasons:
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
