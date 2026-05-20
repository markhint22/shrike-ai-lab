#!/usr/bin/env python3
"""
Hardware and Inference Benchmark Tools

Benchmark LLM inference speed on your hardware.
Compare different models and quantization levels.
"""

import os
import json
import asyncio
import argparse
from pathlib import Path
from datetime import datetime
from typing import List, Dict, Optional
from dataclasses import dataclass, asdict
import time

from openai import AsyncOpenAI
from rich.console import Console
from rich.table import Table
from rich.progress import Progress


console = Console()


@dataclass
class BenchmarkResult:
    """Single benchmark result."""
    model: str
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    latency_ms: float
    tokens_per_second: float
    first_token_ms: float
    timestamp: str


@dataclass
class BenchmarkSummary:
    """Summary of benchmark run."""
    model: str
    runs: int
    avg_latency_ms: float
    min_latency_ms: float
    max_latency_ms: float
    avg_tokens_per_second: float
    avg_first_token_ms: float
    timestamp: str


# Standard benchmark prompts
BENCHMARK_PROMPTS = {
    "short": "What is 2 + 2?",
    "medium": "Explain the concept of recursion in programming. Give a simple example.",
    "long": """Write a detailed technical explanation of how neural networks learn through backpropagation. 
Include the mathematical intuition, the chain rule, gradient descent, and common optimizations like momentum and Adam.
Also discuss common problems like vanishing gradients and their solutions.""",
    "code": """Write a Python function that implements a binary search tree with the following methods:
- insert(value)
- search(value) -> bool
- delete(value)
- inorder_traversal() -> list

Include proper error handling and docstrings.""",
}


class Benchmarker:
    """Benchmark LLM inference speed."""
    
    def __init__(
        self,
        base_url: str = "http://localhost:4000",
        api_key: str = "sk-shrike-local",
    ):
        self.client = AsyncOpenAI(
            base_url=base_url,
            api_key=api_key,
        )
    
    async def benchmark_single(
        self,
        model: str,
        prompt: str,
        max_tokens: int = 200,
    ) -> BenchmarkResult:
        """Run single benchmark."""
        
        start = time.time()
        first_token_time = None
        
        try:
            # Use streaming to measure time to first token
            response_text = ""
            
            stream = await self.client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                max_tokens=max_tokens,
                temperature=0.7,
                stream=True,
            )
            
            async for chunk in stream:
                if first_token_time is None and chunk.choices[0].delta.content:
                    first_token_time = time.time()
                
                if chunk.choices[0].delta.content:
                    response_text += chunk.choices[0].delta.content
            
            end = time.time()
            
            # Estimate token counts (rough approximation)
            prompt_tokens = len(prompt.split()) * 1.3
            completion_tokens = len(response_text.split()) * 1.3
            total_tokens = prompt_tokens + completion_tokens
            
            latency_ms = (end - start) * 1000
            tokens_per_second = completion_tokens / (end - start) if end > start else 0
            first_token_ms = (first_token_time - start) * 1000 if first_token_time else latency_ms
            
            return BenchmarkResult(
                model=model,
                prompt_tokens=int(prompt_tokens),
                completion_tokens=int(completion_tokens),
                total_tokens=int(total_tokens),
                latency_ms=latency_ms,
                tokens_per_second=tokens_per_second,
                first_token_ms=first_token_ms,
                timestamp=datetime.now().isoformat(),
            )
            
        except Exception as e:
            console.print(f"[red]Error benchmarking {model}: {e}[/red]")
            return BenchmarkResult(
                model=model,
                prompt_tokens=0,
                completion_tokens=0,
                total_tokens=0,
                latency_ms=0,
                tokens_per_second=0,
                first_token_ms=0,
                timestamp=datetime.now().isoformat(),
            )
    
    async def benchmark_model(
        self,
        model: str,
        prompt_type: str = "medium",
        runs: int = 5,
        max_tokens: int = 200,
    ) -> BenchmarkSummary:
        """Benchmark model multiple times."""
        
        prompt = BENCHMARK_PROMPTS.get(prompt_type, prompt_type)
        
        console.print(f"\n[bold]Benchmarking: {model}[/bold]")
        console.print(f"Prompt type: {prompt_type}, Runs: {runs}")
        
        results = []
        
        with Progress() as progress:
            task = progress.add_task(f"Running...", total=runs)
            
            for i in range(runs):
                result = await self.benchmark_single(model, prompt, max_tokens)
                results.append(result)
                progress.update(task, advance=1)
                
                # Small delay between runs
                await asyncio.sleep(0.5)
        
        # Calculate summary
        latencies = [r.latency_ms for r in results if r.latency_ms > 0]
        tps = [r.tokens_per_second for r in results if r.tokens_per_second > 0]
        first_tokens = [r.first_token_ms for r in results if r.first_token_ms > 0]
        
        summary = BenchmarkSummary(
            model=model,
            runs=runs,
            avg_latency_ms=sum(latencies) / len(latencies) if latencies else 0,
            min_latency_ms=min(latencies) if latencies else 0,
            max_latency_ms=max(latencies) if latencies else 0,
            avg_tokens_per_second=sum(tps) / len(tps) if tps else 0,
            avg_first_token_ms=sum(first_tokens) / len(first_tokens) if first_tokens else 0,
            timestamp=datetime.now().isoformat(),
        )
        
        return summary


async def compare_models(
    models: List[str],
    prompt_type: str = "medium",
    runs: int = 5,
    max_tokens: int = 200,
):
    """Compare multiple models."""
    
    benchmarker = Benchmarker()
    summaries = []
    
    for model in models:
        summary = await benchmarker.benchmark_model(
            model=model,
            prompt_type=prompt_type,
            runs=runs,
            max_tokens=max_tokens,
        )
        summaries.append(summary)
    
    # Display comparison table
    console.print("\n")
    table = Table(title="Benchmark Results")
    
    table.add_column("Model", style="cyan")
    table.add_column("Avg Latency", justify="right")
    table.add_column("First Token", justify="right")
    table.add_column("Tokens/sec", justify="right")
    table.add_column("Min/Max", justify="right")
    
    for s in summaries:
        table.add_row(
            s.model,
            f"{s.avg_latency_ms:.0f}ms",
            f"{s.avg_first_token_ms:.0f}ms",
            f"{s.avg_tokens_per_second:.1f}",
            f"{s.min_latency_ms:.0f}/{s.max_latency_ms:.0f}ms",
        )
    
    console.print(table)
    
    # Save results
    output_dir = Path("benchmark_results")
    output_dir.mkdir(exist_ok=True)
    
    output_file = output_dir / f"benchmark_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json"
    with open(output_file, "w") as f:
        json.dump([asdict(s) for s in summaries], f, indent=2)
    
    console.print(f"\n[green]Results saved to {output_file}[/green]")
    
    # Print recommendations
    console.print("\n[bold]Recommendations:[/bold]")
    
    if summaries:
        fastest = min(summaries, key=lambda s: s.avg_latency_ms)
        most_efficient = max(summaries, key=lambda s: s.avg_tokens_per_second)
        quickest_response = min(summaries, key=lambda s: s.avg_first_token_ms)
        
        console.print(f"  • Fastest overall: [cyan]{fastest.model}[/cyan] ({fastest.avg_latency_ms:.0f}ms)")
        console.print(f"  • Best throughput: [cyan]{most_efficient.model}[/cyan] ({most_efficient.avg_tokens_per_second:.1f} tok/s)")
        console.print(f"  • Quickest response: [cyan]{quickest_response.model}[/cyan] ({quickest_response.avg_first_token_ms:.0f}ms)")
    
    return summaries


async def hardware_benchmark():
    """Run comprehensive hardware benchmark."""
    
    console.print("[bold]Hardware Benchmark[/bold]")
    console.print("Testing inference speed across prompt sizes...\n")
    
    benchmarker = Benchmarker()
    
    # Test with default model
    model = "mistral:7b-instruct"
    
    results = []
    
    for prompt_type in ["short", "medium", "long", "code"]:
        console.print(f"\nTesting: {prompt_type}")
        summary = await benchmarker.benchmark_model(
            model=model,
            prompt_type=prompt_type,
            runs=3,
            max_tokens=300,
        )
        results.append((prompt_type, summary))
    
    # Summary table
    console.print("\n")
    table = Table(title=f"Hardware Benchmark: {model}")
    
    table.add_column("Prompt Type", style="cyan")
    table.add_column("Avg Latency", justify="right")
    table.add_column("First Token", justify="right")
    table.add_column("Tokens/sec", justify="right")
    
    for prompt_type, s in results:
        table.add_row(
            prompt_type,
            f"{s.avg_latency_ms:.0f}ms",
            f"{s.avg_first_token_ms:.0f}ms",
            f"{s.avg_tokens_per_second:.1f}",
        )
    
    console.print(table)
    
    # Performance assessment
    avg_tps = sum(s.avg_tokens_per_second for _, s in results) / len(results)
    
    console.print("\n[bold]Performance Assessment:[/bold]")
    if avg_tps > 30:
        console.print("  [green]✓ Excellent[/green] - Your hardware is well-suited for local LLM inference")
    elif avg_tps > 15:
        console.print("  [yellow]○ Good[/yellow] - Adequate for most tasks, may be slow for long generations")
    else:
        console.print("  [red]✗ Limited[/red] - Consider using smaller models or cloud fallback")


def main():
    parser = argparse.ArgumentParser(description="Benchmark LLM inference")
    
    subparsers = parser.add_subparsers(dest="command", help="Command to run")
    
    # Compare models command
    compare_parser = subparsers.add_parser("compare", help="Compare multiple models")
    compare_parser.add_argument("--models", "-m", nargs="+", required=True,
                               help="Models to compare")
    compare_parser.add_argument("--prompt", "-p", default="medium",
                               choices=list(BENCHMARK_PROMPTS.keys()),
                               help="Prompt type")
    compare_parser.add_argument("--runs", "-r", type=int, default=5,
                               help="Number of runs per model")
    compare_parser.add_argument("--max-tokens", type=int, default=200,
                               help="Max tokens to generate")
    
    # Hardware benchmark command
    hw_parser = subparsers.add_parser("hardware", help="Run hardware benchmark")
    
    args = parser.parse_args()
    
    if args.command == "compare":
        asyncio.run(compare_models(
            models=args.models,
            prompt_type=args.prompt,
            runs=args.runs,
            max_tokens=args.max_tokens,
        ))
    elif args.command == "hardware":
        asyncio.run(hardware_benchmark())
    else:
        parser.print_help()


if __name__ == "__main__":
    main()
