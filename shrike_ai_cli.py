#!/usr/bin/env python3
"""
Shrike AI Lab CLI

Command-line interface for managing the AI lab infrastructure.

Usage:
    shrike-ai status              # Check service health
    shrike-ai train --list        # List training tasks
    shrike-ai train specpilot selector  # Train specific task
    shrike-ai evaluate gitlark code_explanation  # Evaluate model
    shrike-ai benchmark codellama:7b  # Benchmark model
    shrike-ai models list         # List installed models
    shrike-ai models pull mistral:7b  # Pull model
"""

import os
import sys
from pathlib import Path
from typing import Optional

import typer
from rich.console import Console
from rich.table import Table
from rich.panel import Panel


# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))


app = typer.Typer(
    name="shrike-ai",
    help="Shrike AI Lab CLI - Local LLM infrastructure management",
    add_completion=False,
)

console = Console()


# ===========================================
# Agent Team Commands
# ===========================================

agents_app = typer.Typer(help="Autonomous team commands")
app.add_typer(agents_app, name="agents")


@agents_app.command("run")
def agents_run(
    team: str = typer.Argument(..., help="Team: test-automation or gitlark-memdiff"),
    objective: str = typer.Argument(..., help="Primary objective"),
    mode: str = typer.Option("dry-run", "--mode", help="dry-run or llm"),
    output_json: str = typer.Option("", "--output-json", help="Optional JSON output path"),
    materialize_dir: str = typer.Option(
        "",
        "--materialize-dir",
        help="Optional directory to create output artifact files",
    ),
):
    """Run an autonomous team workflow."""
    import subprocess

    cmd = [
        sys.executable,
        "scripts/run_agent_teams.py",
        "--team",
        team,
        "--objective",
        objective,
        "--mode",
        mode,
    ]
    if output_json:
        cmd.extend(["--output-json", output_json])
    if materialize_dir:
        cmd.extend(["--materialize-dir", materialize_dir])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        console.print(result.stderr or result.stdout)
        raise typer.Exit(result.returncode)

    console.print(result.stdout)


@agents_app.command("benchmark")
def agents_benchmark(
    team: str = typer.Option("all", "--team", help="test-automation, gitlark-memdiff, or all"),
    mode: str = typer.Option("dry-run", "--mode", help="dry-run or llm"),
    pass_threshold: float = typer.Option(0.7, "--pass-threshold", help="Pass score threshold"),
    output_json: str = typer.Option(
        "training/logs/interventions/agent-team-benchmark.json",
        "--output-json",
        help="Benchmark report JSON path",
    ),
):
    """Evaluate autonomous teams against benchmark cases."""
    import subprocess

    cmd = [
        sys.executable,
        "scripts/evaluate_agent_teams.py",
        "--team",
        team,
        "--mode",
        mode,
        "--pass-threshold",
        str(pass_threshold),
        "--output-json",
        output_json,
    ]

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        console.print(result.stderr or result.stdout)
        raise typer.Exit(result.returncode)

    console.print(result.stdout)


@agents_app.command("promote")
def agents_promote(
    benchmark_report: str = typer.Option(
        "training/logs/interventions/agent-team-benchmark.json",
        "--benchmark-report",
        help="Benchmark report JSON path",
    ),
    thresholds: str = typer.Option(
        "configs/agent_team_promotion_thresholds.json",
        "--thresholds",
        help="Promotion thresholds JSON path",
    ),
    output_json: str = typer.Option(
        "training/logs/interventions/agent-team-promotion-decision.json",
        "--output-json",
        help="Promotion decision JSON output path",
    ),
    auto_apply: bool = typer.Option(
        True,
        "--auto-apply/--no-auto-apply",
        help="Automatically apply promotion decisions to rollout/audit files",
    ),
    rollout_json: str = typer.Option(
        "configs/agent_team_rollout.json",
        "--rollout-json",
        help="Rollout state JSON path",
    ),
    queue_json: str = typer.Option(
        "training/queue/agent_team_promotions.json",
        "--queue-json",
        help="Promotion audit queue JSON path",
    ),
    apply_hold_disable: bool = typer.Option(
        False,
        "--apply-hold-disable/--keep-hold-state",
        help="Disable rollout on HOLD when auto-apply is enabled",
    ),
    hold_streak_limit: int = typer.Option(
        3,
        "--hold-streak-limit",
        help="Consecutive HOLD decisions before auto-pausing rollout",
    ),
):
    """Generate GO/HOLD decisions and intervention tickets from benchmark scores."""
    import subprocess

    cmd = [
        sys.executable,
        "scripts/decide_agent_team_promotion.py",
        "--benchmark-report",
        benchmark_report,
        "--thresholds",
        thresholds,
        "--output-json",
        output_json,
    ]
    if auto_apply:
        cmd.extend(
            [
                "--auto-apply",
                "--rollout-json",
                rollout_json,
                "--queue-json",
                queue_json,
                "--hold-streak-limit",
                str(max(1, int(hold_streak_limit))),
            ]
        )
        if apply_hold_disable:
            cmd.append("--apply-hold-disable")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        console.print(result.stderr or result.stdout)
        raise typer.Exit(result.returncode)

    console.print(result.stdout)


@agents_app.command("bootstrap-train")
def agents_bootstrap_train(
    jobs_file: str = typer.Option(
        "training/queue/agent_team_bootstrap_jobs.json",
        "--jobs-file",
        help="Bootstrap queue jobs file",
    ),
    max_hours: float = typer.Option(6.0, "--max-hours", help="Bootstrap runtime window"),
):
    """Start bootstrap training queue if free, otherwise stage pending launch metadata."""
    import subprocess

    cmd = [
        sys.executable,
        "scripts/start_agent_team_bootstrap.py",
        "--python",
        sys.executable,
        "--jobs-file",
        jobs_file,
        "--max-hours",
        str(max_hours),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        console.print(result.stderr or result.stdout)
        raise typer.Exit(result.returncode)

    console.print(result.stdout)


@agents_app.command("bootstrap-watch")
def agents_bootstrap_watch(
    jobs_file: str = typer.Option(
        "training/queue/agent_team_bootstrap_jobs.json",
        "--jobs-file",
        help="Bootstrap queue jobs file",
    ),
    max_hours: float = typer.Option(6.0, "--max-hours", help="Bootstrap runtime window"),
    poll_seconds: float = typer.Option(30.0, "--poll-seconds", help="Queue poll interval"),
    timeout_minutes: float = typer.Option(720.0, "--timeout-minutes", help="Watcher timeout"),
):
    """Watch queue and auto-launch bootstrap training as soon as current queue finishes."""
    import subprocess

    cmd = [
        sys.executable,
        "scripts/watch_and_start_agent_team_bootstrap.py",
        "--python",
        sys.executable,
        "--jobs-file",
        jobs_file,
        "--max-hours",
        str(max_hours),
        "--poll-seconds",
        str(poll_seconds),
        "--timeout-minutes",
        str(timeout_minutes),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        console.print(result.stderr or result.stdout)
        raise typer.Exit(result.returncode)

    console.print(result.stdout)


@agents_app.command("resume")
def agents_resume(
    team: list[str] = typer.Option(
        [],
        "--team",
        help="Team id to resume (repeat for multiple teams)",
    ),
    all_teams: bool = typer.Option(
        False,
        "--all",
        help="Resume all teams in rollout state",
    ),
    rollout_json: str = typer.Option(
        "configs/agent_team_rollout.json",
        "--rollout-json",
        help="Rollout state JSON path",
    ),
    reason: str = typer.Option(
        "Manual intervention completed.",
        "--reason",
        help="Reason included in resume metadata",
    ),
):
    """Clear intervention pause and resume team rollout."""
    import subprocess

    cmd = [
        sys.executable,
        "scripts/resume_agent_team_rollout.py",
        "--rollout-json",
        rollout_json,
        "--reason",
        reason,
    ]
    if all_teams:
        cmd.append("--all")
    for item in team:
        cmd.extend(["--team", item])

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        console.print(result.stderr or result.stdout)
        raise typer.Exit(result.returncode)

    console.print(result.stdout)


@agents_app.command("validate-pipeline")
def agents_validate_pipeline(
    include_paused: bool = typer.Option(
        False,
        "--include-paused",
        help="Also validate paused/disabled queue jobs",
    ),
):
    """Validate agent + training pipeline wiring and JSONL integrity."""
    import subprocess

    cmd = [
        sys.executable,
        "scripts/validate_training_pipeline.py",
    ]
    if include_paused:
        cmd.append("--include-paused")

    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        console.print(result.stderr or result.stdout)
        raise typer.Exit(result.returncode)

    console.print(result.stdout)


# ===========================================
# Status Commands
# ===========================================

@app.command()
def status():
    """Check health of all services."""
    import httpx
    
    services = [
        ("Ollama", "http://localhost:11434/api/tags"),
        ("LiteLLM", "http://localhost:4000/health"),
        ("Open WebUI", "http://localhost:3000"),
    ]
    
    console.print("\n[bold]Service Status[/bold]\n")
    
    for name, url in services:
        try:
            response = httpx.get(url, timeout=5.0)
            if response.status_code == 200:
                console.print(f"  ✅ {name}: [green]Running[/green] ({url})")
            else:
                console.print(f"  ⚠️ {name}: [yellow]Responding ({response.status_code})[/yellow]")
        except Exception as e:
            console.print(f"  ❌ {name}: [red]Not running[/red]")
    
    console.print()


# ===========================================
# Training Commands
# ===========================================

train_app = typer.Typer(help="Training commands")
app.add_typer(train_app, name="train")


@train_app.command("list")
def train_list():
    """List available training tasks."""
    from scripts.train import PROJECT_CONFIGS, get_data_path, count_examples
    
    console.print("\n[bold]Available Training Tasks[/bold]\n")
    
    for project, config in PROJECT_CONFIGS.items():
        console.print(f"[cyan]{project}/[/cyan] ({config['description']})")
        console.print(f"  Base model: {config['base_model']}")
        console.print(f"  Tasks:")
        
        for task in config["tasks"]:
            try:
                data_path = get_data_path(project, task)
                count = count_examples(data_path)
                status = f"✅ {count} examples"
            except FileNotFoundError:
                status = "❌ No data"
            
            console.print(f"    • {task}: {status}")
        
        console.print()


@train_app.command("run")
def train_run(
    project: str = typer.Argument(..., help="Project name"),
    task: str = typer.Argument(..., help="Task name"),
    version: str = typer.Option("v1", "--version", "-v", help="Model version"),
    epochs: int = typer.Option(3, "--epochs", "-e", help="Training epochs"),
    dry_run: bool = typer.Option(False, "--dry-run", help="Show config without training"),
):
    """Run model training."""
    from scripts.train import train_model
    
    result = train_model(
        project=project,
        task=task,
        version=version,
        epochs=epochs,
        dry_run=dry_run,
    )
    
    if result["status"] == "error":
        raise typer.Exit(1)


# ===========================================
# Model Commands
# ===========================================

models_app = typer.Typer(help="Model management commands")
app.add_typer(models_app, name="models")


@models_app.command("list")
def models_list():
    """List installed Ollama models."""
    import httpx
    
    try:
        response = httpx.get("http://localhost:11434/api/tags", timeout=10.0)
        data = response.json()
        
        models = data.get("models", [])
        
        if not models:
            console.print("[yellow]No models installed[/yellow]")
            console.print("Pull a model with: shrike-ai models pull codellama:7b")
            return
        
        table = Table(title="Installed Models")
        table.add_column("Name", style="cyan")
        table.add_column("Size", justify="right")
        table.add_column("Modified")
        
        for model in models:
            name = model.get("name", "unknown")
            size_gb = model.get("size", 0) / (1024**3)
            modified = model.get("modified_at", "")[:10]
            
            table.add_row(name, f"{size_gb:.1f} GB", modified)
        
        console.print(table)
        
    except Exception as e:
        console.print(f"[red]Error connecting to Ollama: {e}[/red]")
        console.print("Make sure Ollama is running: docker-compose up -d")


@models_app.command("pull")
def models_pull(
    model: str = typer.Argument(..., help="Model to pull (e.g., codellama:7b)"),
):
    """Pull a model from Ollama registry."""
    import subprocess
    
    console.print(f"Pulling {model}...")
    
    result = subprocess.run(
        ["docker", "exec", "shrike-ollama", "ollama", "pull", model],
        capture_output=False,
    )
    
    if result.returncode == 0:
        console.print(f"[green]✓ Successfully pulled {model}[/green]")
    else:
        console.print(f"[red]✗ Failed to pull {model}[/red]")
        raise typer.Exit(1)


@models_app.command("delete")
def models_delete(
    model: str = typer.Argument(..., help="Model to delete"),
    force: bool = typer.Option(False, "--force", "-f", help="Skip confirmation"),
):
    """Delete an installed model."""
    import subprocess
    
    if not force:
        confirm = typer.confirm(f"Delete model {model}?")
        if not confirm:
            raise typer.Abort()
    
    result = subprocess.run(
        ["docker", "exec", "shrike-ollama", "ollama", "rm", model],
        capture_output=True,
        text=True,
    )
    
    if result.returncode == 0:
        console.print(f"[green]✓ Deleted {model}[/green]")
    else:
        console.print(f"[red]✗ Failed to delete: {result.stderr}[/red]")


# ===========================================
# Evaluate Commands
# ===========================================

@app.command()
def evaluate(
    project: str = typer.Argument(..., help="Project name"),
    task: str = typer.Argument(..., help="Task name"),
    models: str = typer.Option(
        "local,claude-haiku",
        "--models", "-m",
        help="Comma-separated models to evaluate",
    ),
    limit: int = typer.Option(20, "--limit", "-l", help="Number of examples"),
):
    """Evaluate model quality on test set."""
    import asyncio
    from scripts.evaluate import compare_models
    from scripts.train import get_data_path
    
    model_list = [m.strip() for m in models.split(",")]
    
    # Construct local model name
    local_model = f"{project}-{task}-v1"
    model_list = [local_model if m == "local" else m for m in model_list]
    
    try:
        test_data = get_data_path(project, task)
    except FileNotFoundError:
        console.print(f"[red]No test data found for {project}/{task}[/red]")
        raise typer.Exit(1)
    
    asyncio.run(compare_models(
        models=model_list,
        task=task,
        test_data_path=str(test_data),
        limit=limit,
    ))


# ===========================================
# Benchmark Commands
# ===========================================

@app.command()
def benchmark(
    models: str = typer.Argument(
        "codellama:7b,mistral:7b",
        help="Comma-separated models to benchmark",
    ),
    prompt: str = typer.Option("medium", "--prompt", "-p", help="Prompt type"),
    runs: int = typer.Option(5, "--runs", "-r", help="Number of runs"),
):
    """Benchmark inference speed."""
    import asyncio
    from scripts.benchmark import compare_models
    
    model_list = [m.strip() for m in models.split(",")]
    
    asyncio.run(compare_models(
        models=model_list,
        prompt_type=prompt,
        runs=runs,
    ))


# ===========================================
# Collect Commands
# ===========================================

collect_app = typer.Typer(help="Data collection commands")
app.add_typer(collect_app, name="collect")


@collect_app.command("gitlark")
def collect_gitlark(
    repos: str = typer.Option(
        "~/LocalProjects/billwatch,~/LocalProjects/gitlark",
        "--repos", "-r",
        help="Comma-separated repo paths",
    ),
    output: str = typer.Option(
        "training/gitlark/data",
        "--output", "-o",
        help="Output directory",
    ),
):
    """Collect GitLark training data from repositories."""
    from scripts.data_collection.collect_gitlark_data import collect_from_repo
    
    repo_list = [Path(r.strip()).expanduser() for r in repos.split(",")]
    output_dir = Path(output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    for repo in repo_list:
        if repo.exists():
            collect_from_repo(repo, output_dir)
        else:
            console.print(f"[yellow]Skipping {repo} (not found)[/yellow]")
    
    console.print(f"\n[green]Data saved to {output_dir}[/green]")


@collect_app.command("billwatch")
def collect_billwatch(
    limit: int = typer.Option(100, "--limit", "-l", help="Number of bills"),
    congress: int = typer.Option(118, "--congress", "-c", help="Congress number"),
    output: str = typer.Option(
        "training/billwatch/data",
        "--output", "-o",
        help="Output directory",
    ),
):
    """Collect BillWatch training data from Congress.gov."""
    import asyncio
    
    api_key = os.getenv("CONGRESS_API_KEY")
    if not api_key:
        console.print("[red]CONGRESS_API_KEY environment variable not set[/red]")
        console.print("Get a key from: https://api.congress.gov/sign-up/")
        raise typer.Exit(1)
    
    from scripts.data_collection.collect_billwatch_data import collect_data
    
    output_dir = Path(output)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    asyncio.run(collect_data(
        api_key=api_key,
        congress=congress,
        limit=limit,
        output_dir=output_dir,
    ))


# ===========================================
# Info Command
# ===========================================

@app.command()
def info():
    """Show system information and quick start guide."""
    
    panel = Panel.fit(
        """[bold cyan]Shrike AI Lab[/bold cyan]
Local LLM infrastructure for Shrike Labs projects

[bold]Quick Start:[/bold]
  1. Start services:     docker-compose up -d
  2. Check status:       shrike-ai status
  3. List models:        shrike-ai models list
  4. Pull a model:       shrike-ai models pull codellama:7b
  5. List tasks:         shrike-ai train list
  6. Train a model:      shrike-ai train run specpilot selector
  7. Evaluate:           shrike-ai evaluate specpilot selector

[bold]Services:[/bold]
  • Ollama:     http://localhost:11434
  • LiteLLM:    http://localhost:4000
  • Open WebUI: http://localhost:3000

[bold]Documentation:[/bold]
  • README.md
  • docs/ROADMAP_YEAR1.md
  • docs/integrations/*.md
""",
        title="System Info",
    )
    
    console.print(panel)


if __name__ == "__main__":
    app()
