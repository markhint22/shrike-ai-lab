#!/usr/bin/env python3
"""
Model Evaluation Tools

Compare local model quality against Claude baseline.
Track performance metrics over time.
"""

import os
import json
import asyncio
import argparse
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Any, Optional
from dataclasses import dataclass, asdict

from openai import AsyncOpenAI
from rich.console import Console
from rich.table import Table
from rich.progress import Progress


console = Console()


@dataclass
class EvaluationResult:
    """Single evaluation result."""
    task: str
    model: str
    input_text: str
    expected_output: str
    actual_output: str
    correct: bool
    latency_ms: float
    tokens_used: int
    timestamp: str


@dataclass
class EvaluationSummary:
    """Summary of evaluation run."""
    task: str
    model: str
    total_examples: int
    correct: int
    accuracy: float
    avg_latency_ms: float
    total_tokens: int
    timestamp: str


class ModelEvaluator:
    """Evaluate model quality on test sets."""
    
    def __init__(
        self,
        local_url: str = "http://localhost:4000",
        local_key: str = "sk-shrike-local",
        request_timeout: float = 20.0,
        max_retries: int = 1,
    ):
        self.local_client = AsyncOpenAI(
            base_url=local_url,
            api_key=local_key,
            timeout=request_timeout,
            max_retries=max_retries,
        )
        
        # Claude client for optional baseline comparison.
        # Keep this optional so local-only evaluation works without cloud keys.
        self.claude_client = None
        anthropic_key = os.getenv("ANTHROPIC_API_KEY", "").strip()
        if anthropic_key:
            self.claude_client = AsyncOpenAI(
                base_url="https://api.anthropic.com/v1",
                api_key=anthropic_key,
                timeout=request_timeout,
                max_retries=max_retries,
            )
    
    async def evaluate_single(
        self,
        model: str,
        task: str,
        input_text: str,
        expected_output: str,
        system_prompt: str = "",
    ) -> EvaluationResult:
        """Evaluate single example."""
        
        import time
        start = time.time()
        
        client = self.local_client
        
        try:
            response = await client.chat.completions.create(
                model=model,
                messages=[
                    {"role": "system", "content": system_prompt} if system_prompt else {},
                    {"role": "user", "content": input_text},
                ],
                max_tokens=500,
                temperature=0.2,
            )
            
            actual_output = response.choices[0].message.content.strip()
            latency_ms = (time.time() - start) * 1000
            tokens = response.usage.total_tokens if response.usage else 0
            
            # Simple correctness check (can be customized per task)
            correct = self._check_correctness(task, expected_output, actual_output)
            
            return EvaluationResult(
                task=task,
                model=model,
                input_text=input_text[:200],
                expected_output=expected_output[:200],
                actual_output=actual_output[:200],
                correct=correct,
                latency_ms=latency_ms,
                tokens_used=tokens,
                timestamp=datetime.now().isoformat(),
            )
            
        except Exception as e:
            console.print(f"[red]Error evaluating: {e}[/red]")
            return EvaluationResult(
                task=task,
                model=model,
                input_text=input_text[:200],
                expected_output=expected_output[:200],
                actual_output=f"ERROR: {str(e)}",
                correct=False,
                latency_ms=(time.time() - start) * 1000,
                tokens_used=0,
                timestamp=datetime.now().isoformat(),
            )
    
    def _check_correctness(
        self,
        task: str,
        expected: str,
        actual: str,
    ) -> bool:
        """Check if output is correct for the task."""
        
        # Normalize for comparison
        expected_norm = expected.lower().strip()
        actual_norm = actual.lower().strip()
        
        if task == "classification":
            # Exact match for classification
            return expected_norm in actual_norm
        
        elif task == "code_review":
            # Check if key issues are mentioned
            try:
                expected_issues = json.loads(expected)
                for issue in expected_issues:
                    if issue.get("type", "").lower() not in actual_norm:
                        return False
                return True
            except json.JSONDecodeError:
                return expected_norm in actual_norm
        
        elif task in ("summarization", "code_explanation"):
            # Semantic similarity check (simplified)
            # In production, use embedding similarity
            expected_words = set(expected_norm.split())
            actual_words = set(actual_norm.split())
            overlap = len(expected_words & actual_words) / max(len(expected_words), 1)
            return overlap > 0.3

        elif task in (
            "test_generation",
            "failure_analysis",
            "flow_analysis",
            "test_building",
            "pr_description",
            "repo_intelligence",
            "memdiff",
            "bill_background",
            "article_relevance",
        ):
            # Structured outputs vary, so use loose lexical overlap.
            expected_words = set(expected_norm.split())
            actual_words = set(actual_norm.split())
            overlap = len(expected_words & actual_words) / max(len(expected_words), 1)
            return overlap > 0.15

        elif task == "moderation":
            return expected_norm in actual_norm
        
        elif task == "commit_message":
            # Check format and key words
            has_type = any(t in actual_norm for t in ["feat", "fix", "docs", "refactor", "chore"])
            return has_type and len(actual) > 10
        
        else:
            # Default: substring match
            return expected_norm in actual_norm or actual_norm in expected_norm
    
    async def evaluate_test_set(
        self,
        model: str,
        task: str,
        test_data_path: str,
        system_prompt: str = "",
        limit: Optional[int] = None,
    ) -> EvaluationSummary:
        """Evaluate model on entire test set."""
        
        # Load test data
        examples = []
        with open(test_data_path) as f:
            for line in f:
                if line.strip():
                    examples.append(json.loads(line))
        
        if limit:
            examples = examples[:limit]
        
        console.print(f"\n[bold]Evaluating {model} on {task}[/bold]")
        console.print(f"Test set: {test_data_path} ({len(examples)} examples)")
        
        results = []
        
        with Progress() as progress:
            task_progress = progress.add_task(
                f"Evaluating {model}...",
                total=len(examples),
            )
            
            for example in examples:
                # Extract input and expected output based on task
                input_text, expected = self._extract_io(task, example)
                
                result = await self.evaluate_single(
                    model=model,
                    task=task,
                    input_text=input_text,
                    expected_output=expected,
                    system_prompt=system_prompt,
                )
                
                results.append(result)
                progress.update(task_progress, advance=1)
        
        # Calculate summary
        correct = sum(1 for r in results if r.correct)
        accuracy = correct / len(results) if results else 0
        avg_latency = sum(r.latency_ms for r in results) / len(results) if results else 0
        total_tokens = sum(r.tokens_used for r in results)
        
        summary = EvaluationSummary(
            task=task,
            model=model,
            total_examples=len(results),
            correct=correct,
            accuracy=accuracy,
            avg_latency_ms=avg_latency,
            total_tokens=total_tokens,
            timestamp=datetime.now().isoformat(),
        )
        
        return summary
    
    def _extract_io(self, task: str, example: Dict) -> tuple:
        """Extract input and expected output from example."""
        
        if task == "code_explanation":
            return example.get("code", ""), example.get("explanation", "")
        elif task == "summarization":
            return example.get("bill_text", ""), example.get("summary", "")
        elif task == "classification":
            return example.get("bill_text", ""), example.get("policy_area", "")
        elif task == "code_review":
            return example.get("code", ""), json.dumps(example.get("issues", []))
        elif task == "commit_message":
            return example.get("diff", ""), example.get("commit_message", "")
        elif task == "selector_optimization":
            return example.get("html", ""), example.get("good_selector", "")
        elif task == "test_generation":
            return example.get("instruction", ""), example.get("playwright_code", "")
        elif task == "failure_analysis":
            input_text = f"Error: {example.get('error', '')}\nSelector: {example.get('selector', '')}"
            expected = f"Diagnosis: {example.get('diagnosis', '')}\nFix: {example.get('fix', '')}"
            return input_text, expected
        elif task == "flow_analysis":
            input_text = (
                f"Step: {example.get('test_plan_step', '')}\n"
                f"HTML: {example.get('page_html_snippet', '')}"
            )
            expected = json.dumps(
                {
                    "requires_auth": example.get("requires_auth"),
                    "flow_type": example.get("flow_type"),
                    "recommended_setup": example.get("recommended_setup", {}),
                },
                ensure_ascii=False,
            )
            return input_text, expected
        elif task == "test_building":
            input_text = f"Goal: {example.get('test_goal', '')}\nFlow: {example.get('flow_type', '')}"
            return input_text, example.get("full_test", "")
        elif task == "pr_description":
            input_text = example.get("diff", "")
            expected = f"Title: {example.get('title', '')}\n\n{example.get('description', '')}".strip()
            return input_text, expected
        elif task == "repo_intelligence":
            input_text = (
                f"Repo: {example.get('repo_name', '')}\n"
                f"File tree:\n{example.get('file_tree', '')}\n"
                f"Metadata: {example.get('metadata', {})}"
            )
            expected = json.dumps(
                {
                    "suggested_features": example.get("suggested_features", []),
                    "learning_path": example.get("learning_path", []),
                },
                ensure_ascii=False,
            )
            return input_text, expected
        elif task == "memdiff":
            input_text = (
                f"Scenario: {example.get('scenario', '')}\n"
                f"Query: {example.get('user_query', '')}\n"
                f"Memory: {example.get('memory_state', {})}"
            )
            expected = json.dumps(
                {
                    "decision": example.get("decision", ""),
                    "action": example.get("action", ""),
                    "reasoning": example.get("reasoning", ""),
                    "response_plan": example.get("response_plan", ""),
                },
                ensure_ascii=False,
            )
            return input_text, expected
        elif task == "bill_background":
            input_text = f"Title: {example.get('title', '')}\nBill: {example.get('bill_text', '')}"
            expected = json.dumps(example.get("background_brief", {}), ensure_ascii=False)
            return input_text, expected
        elif task == "article_relevance":
            input_text = (
                f"Topics: {example.get('bill_topics', [])}\n"
                f"Candidates: {example.get('candidate_articles', [])}"
            )
            expected = json.dumps(example.get("ranked_selection", []), ensure_ascii=False)
            return input_text, expected
        elif task == "moderation":
            input_text = f"Context: {example.get('context', '')}\nMessage: {example.get('message', '')}"
            return input_text, example.get("decision", "")
        else:
            # Generic fallback
            return str(example.get("input", "")), str(example.get("output", ""))


async def compare_models(
    models: List[str],
    task: str,
    test_data_path: str,
    system_prompt: str = "",
    limit: Optional[int] = None,
):
    """Compare multiple models on same test set."""
    
    evaluator = ModelEvaluator()
    summaries = []
    
    for model in models:
        summary = await evaluator.evaluate_test_set(
            model=model,
            task=task,
            test_data_path=test_data_path,
            system_prompt=system_prompt,
            limit=limit,
        )
        summaries.append(summary)
    
    # Display comparison table
    table = Table(title=f"Model Comparison: {task}")
    
    table.add_column("Model", style="cyan")
    table.add_column("Accuracy", justify="right")
    table.add_column("Avg Latency", justify="right")
    table.add_column("Total Tokens", justify="right")
    
    for s in summaries:
        table.add_row(
            s.model,
            f"{s.accuracy:.1%}",
            f"{s.avg_latency_ms:.0f}ms",
            str(s.total_tokens),
        )
    
    console.print(table)
    
    # Save results
    output_dir = Path("evaluation_results")
    output_dir.mkdir(exist_ok=True)
    
    output_file = output_dir / f"{task}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(output_file, "w") as f:
        json.dump([asdict(s) for s in summaries], f, indent=2)
    
    console.print(f"\n[green]Results saved to {output_file}[/green]")
    
    return summaries


def main():
    parser = argparse.ArgumentParser(description="Evaluate model quality")
    parser.add_argument("--models", "-m", nargs="+", required=True,
                       help="Models to evaluate")
    parser.add_argument("--task", "-t", required=True,
                       help="Task name (code_explanation, summarization, etc.)")
    parser.add_argument("--test-data", "-d", required=True,
                       help="Path to test data JSONL")
    parser.add_argument("--system-prompt", "-s", default="",
                       help="System prompt to use")
    parser.add_argument("--limit", "-l", type=int, default=None,
                       help="Limit number of examples")
    
    args = parser.parse_args()
    
    asyncio.run(compare_models(
        models=args.models,
        task=args.task,
        test_data_path=args.test_data,
        system_prompt=args.system_prompt,
        limit=args.limit,
    ))


if __name__ == "__main__":
    main()
