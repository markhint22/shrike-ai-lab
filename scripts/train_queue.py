#!/usr/bin/env python3
"""
Sequential training queue runner.

Runs training jobs one at a time by invoking scripts/train.py.
Designed for overnight execution on a single workstation.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from log_layout import ensure_log_layout, log_dir, queue_lock_file, queue_pid_file


@dataclass
class Job:
    project: str = ""
    task: str = ""
    version: str = ""
    kind: str = "llm_train"
    team: str = ""
    objective: str = ""
    mode: str = "dry-run"
    materialize_dir: str = ""
    app_stack: str = "unknown"
    test_framework: str = "playwright"
    scope: str = "smoke + regression"
    query_type: str = "mixed"
    freshness_sla_minutes: int = 30
    repo_scope: str = "gitlark"
    pass_threshold: float = 0.7
    output_json: str = ""
    benchmark_report: str = ""
    thresholds: str = ""
    rollout_json: str = ""
    queue_json: str = ""
    auto_apply: bool = False
    apply_hold_disable: bool = False
    hold_streak_limit: int = 3
    engine: str = "hf"
    epochs: int = 1
    batch_size: int = 1
    learning_rate: float = 2e-4
    base_model: str | None = None
    max_seq_length: int | None = None
    ab_gate_baseline_model: str | None = None
    ab_gate_candidate_model: str | None = None
    ab_gate_limit: int = 20


def process_exists(pid: int) -> bool:
    result = subprocess.run(
        ["tasklist", "/FI", f"PID eq {pid}"],
        check=False,
        capture_output=True,
        text=True,
    )
    return str(pid) in (result.stdout or "")


def _subprocess_window_kwargs() -> dict[str, Any]:
    if sys.platform != "win32":
        return {}

    creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = 0
    return {
        "creationflags": creationflags,
        "startupinfo": startupinfo,
    }


def acquire_queue_lock(lock_file: Path) -> int | None:
    lock_file.parent.mkdir(parents=True, exist_ok=True)
    pid_text = str(os.getpid())

    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    try:
        fd = os.open(str(lock_file), flags)
        os.write(fd, pid_text.encode("ascii"))
        return fd
    except FileExistsError:
        now = time.time()
        try:
            existing_pid = int(lock_file.read_text(encoding="ascii").strip())
        except ValueError:
            existing_pid = None

        if existing_pid:
            if process_exists(existing_pid):
                print(f"Another train_queue instance is already running (pid={existing_pid}); exiting.")
                return None

            # If the lock is very recent, treat it as active to avoid race-y double starts.
            age_seconds = now - lock_file.stat().st_mtime
            if age_seconds < 120:
                print(
                    "train_queue lock is present and recent; "
                    f"assuming another startup is in progress (pid={existing_pid}). Exiting."
                )
                return None

        if existing_pid is None:
            age_seconds = now - lock_file.stat().st_mtime
            if age_seconds < 120:
                print("train_queue lock is present and recent but unreadable; exiting to avoid duplicates.")
                return None

        # Stale lock: no live owner and lock file is old enough.
        print("Removing stale train_queue lock file")
        lock_file.unlink(missing_ok=True)
        try:
            fd = os.open(str(lock_file), flags)
        except FileExistsError:
            print("train_queue lock was recreated by another process; exiting.")
            return None

    os.write(fd, pid_text.encode("ascii"))
    return fd


def release_queue_lock(lock_fd: int | None, lock_file: Path) -> None:
    if lock_fd is not None:
        try:
            os.close(lock_fd)
        except OSError:
            pass
    lock_file.unlink(missing_ok=True)


def load_jobs(jobs_file: Path) -> list[Job]:
    with jobs_file.open("r", encoding="utf-8") as f:
        payload = json.load(f)

    raw_jobs = payload.get("jobs", [])
    jobs: list[Job] = []
    for item in raw_jobs:
        if not bool(item.get("enabled", True)):
            continue
        jobs.append(
            Job(
                kind=item.get("kind", "llm_train"),
                project=item.get("project", ""),
                task=item.get("task", ""),
                version=item.get(
                    "version",
                    (
                        f"nightly-{item['project']}-{item['task']}"
                        if item.get("project") and item.get("task")
                        else f"nightly-{item.get('kind', 'job')}"
                    ),
                ),
                team=item.get("team", ""),
                objective=item.get("objective", ""),
                mode=item.get("mode", "dry-run"),
                materialize_dir=item.get("materialize_dir", ""),
                app_stack=item.get("app_stack", "unknown"),
                test_framework=item.get("test_framework", "playwright"),
                scope=item.get("scope", "smoke + regression"),
                query_type=item.get("query_type", "mixed"),
                freshness_sla_minutes=int(item.get("freshness_sla_minutes", 30)),
                repo_scope=item.get("repo_scope", "gitlark"),
                pass_threshold=float(item.get("pass_threshold", 0.7)),
                output_json=item.get("output_json", ""),
                benchmark_report=item.get("benchmark_report", ""),
                thresholds=item.get("thresholds", ""),
                rollout_json=item.get("rollout_json", ""),
                queue_json=item.get("queue_json", ""),
                auto_apply=bool(item.get("auto_apply", False)),
                apply_hold_disable=bool(item.get("apply_hold_disable", False)),
                hold_streak_limit=int(item.get("hold_streak_limit", 3)),
                engine=item.get("engine", "hf"),
                epochs=int(item.get("epochs", 1)),
                batch_size=int(item.get("batch_size", 1)),
                learning_rate=float(item.get("learning_rate", 2e-4)),
                base_model=item.get("base_model"),
                max_seq_length=item.get("max_seq_length"),
                ab_gate_baseline_model=item.get("ab_gate_baseline_model"),
                ab_gate_candidate_model=item.get("ab_gate_candidate_model"),
                ab_gate_limit=int(item.get("ab_gate_limit", 20)),
            )
        )
    return jobs


def run_ab_gate_for_job(
    python_exe: Path,
    repo_root: Path,
    job: Job,
    logs_dir: Path,
) -> tuple[bool, str]:
    """Run A/B gate after a successful job when models are configured.

    Returns (ok, message). Missing model aliases is treated as a skip.
    """
    if not job.ab_gate_baseline_model or not job.ab_gate_candidate_model:
        return True, "ab-gate skipped (no baseline/candidate model configured)"

    gate_dir = log_dir(repo_root, "ab_gates")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    gate_json = gate_dir / f"ab-gate-{job.project}-{job.task}-{stamp}.json"

    gate_cmd = [
        str(python_exe),
        str(repo_root / "scripts" / "ab_eval_gate.py"),
        "--project",
        job.project,
        "--task",
        job.task,
        "--baseline-model",
        job.ab_gate_baseline_model,
        "--candidate-model",
        job.ab_gate_candidate_model,
        "--limit",
        str(max(1, job.ab_gate_limit)),
        "--json-out",
        str(gate_json),
    ]

    gate_log = logs_dir / f"ab-gate-{job.project}-{job.task}-{stamp}.log"
    with gate_log.open("w", encoding="utf-8") as log:
        log.write(f"START {datetime.now().isoformat()}\n")
        log.write("COMMAND " + " ".join(gate_cmd) + "\n\n")
        log.flush()
        proc = subprocess.run(
            gate_cmd,
            cwd=str(repo_root),
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
            **_subprocess_window_kwargs(),
        )
        log.write(f"\nEND {datetime.now().isoformat()}\n")
        log.write(f"EXIT {proc.returncode}\n")

    if proc.returncode == 0:
        return True, f"ab-gate complete ({gate_json.name})"
    return False, f"ab-gate failed ({gate_log.name})"


def run_job(python_exe: Path, repo_root: Path, job: Job, logs_dir: Path) -> int:
    return run_job_with_version(python_exe, repo_root, job, logs_dir, job.version)


def _job_logs_dir(repo_root: Path, job: Job) -> Path:
    if job.kind == "llm_train":
        return log_dir(repo_root, "runs")
    return log_dir(repo_root, "interventions")


def run_agent_job(
    python_exe: Path,
    repo_root: Path,
    job: Job,
    timeout_seconds: float | None = None,
) -> int:
    logs_dir = _job_logs_dir(repo_root, job)
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    team_slug = job.team or "all"
    log_file = logs_dir / f"{timestamp}-{job.kind}-{team_slug}-{job.version}.log"

    if job.kind == "agent_run":
        if not job.team:
            raise ValueError("agent_run queue job requires a team")
        if not job.objective:
            raise ValueError("agent_run queue job requires an objective")

        cmd = [
            str(python_exe),
            str(repo_root / "scripts" / "run_agent_teams.py"),
            "--team",
            job.team,
            "--objective",
            job.objective,
            "--mode",
            job.mode,
        ]
        if job.output_json:
            cmd.extend(["--output-json", job.output_json])
        if job.materialize_dir:
            cmd.extend(["--materialize-dir", job.materialize_dir])
        if job.team == "test-automation":
            cmd.extend(["--app-stack", job.app_stack, "--test-framework", job.test_framework, "--scope", job.scope])
        elif job.team == "gitlark-memdiff":
            cmd.extend(
                [
                    "--query-type",
                    job.query_type,
                    "--freshness-sla-minutes",
                    str(max(1, job.freshness_sla_minutes)),
                    "--repo-scope",
                    job.repo_scope,
                ]
            )
    elif job.kind == "agent_benchmark":
        cmd = [
            str(python_exe),
            str(repo_root / "scripts" / "evaluate_agent_teams.py"),
            "--team",
            (job.team or "all"),
            "--mode",
            job.mode,
            "--pass-threshold",
            str(job.pass_threshold),
        ]
        if job.output_json:
            cmd.extend(["--output-json", job.output_json])
    elif job.kind == "agent_promote":
        cmd = [
            str(python_exe),
            str(repo_root / "scripts" / "decide_agent_team_promotion.py"),
        ]
        if job.benchmark_report:
            cmd.extend(["--benchmark-report", job.benchmark_report])
        if job.thresholds:
            cmd.extend(["--thresholds", job.thresholds])
        if job.output_json:
            cmd.extend(["--output-json", job.output_json])
        if job.auto_apply:
            cmd.append("--auto-apply")
        if job.rollout_json:
            cmd.extend(["--rollout-json", job.rollout_json])
        if job.queue_json:
            cmd.extend(["--queue-json", job.queue_json])
        if job.apply_hold_disable:
            cmd.append("--apply-hold-disable")
        cmd.extend(["--hold-streak-limit", str(max(1, job.hold_streak_limit))])
    else:
        raise ValueError(f"Unsupported queue job kind: {job.kind}")

    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")

    with log_file.open("w", encoding="utf-8") as log:
        log.write(f"START {datetime.now().isoformat()}\n")
        log.write("COMMAND " + " ".join(cmd) + "\n\n")
        log.flush()
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(repo_root),
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
                timeout=timeout_seconds,
                **_subprocess_window_kwargs(),
            )
        except subprocess.TimeoutExpired:
            log.write(f"\nTIMEOUT after {timeout_seconds} seconds\n")
            log.write(f"END {datetime.now().isoformat()}\n")
            log.write("EXIT 124\n")
            return 124
        log.write(f"\nEND {datetime.now().isoformat()}\n")
        log.write(f"EXIT {proc.returncode}\n")

    return proc.returncode


def run_job_with_version(
    python_exe: Path,
    repo_root: Path,
    job: Job,
    logs_dir: Path,
    version: str,
    timeout_seconds: float | None = None,
) -> int:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    log_file = logs_dir / f"{timestamp}-{job.project}-{job.task}-{version}.log"

    cmd = [
        str(python_exe),
        str(repo_root / "scripts" / "train.py"),
        "--project",
        job.project,
        "--task",
        job.task,
        "--engine",
        job.engine,
        "--version",
        version,
        "--epochs",
        str(job.epochs),
        "--batch-size",
        str(job.batch_size),
        "--learning-rate",
        str(job.learning_rate),
    ]
    if job.base_model:
        cmd.extend(["--base-model", job.base_model])
    if job.max_seq_length:
        cmd.extend(["--max-seq-length", str(job.max_seq_length)])

    env = os.environ.copy()
    # Keep log decoding stable on Windows and reduce CPU-thread contention across runs.
    env.setdefault("PYTHONIOENCODING", "utf-8")
    env.setdefault("TOKENIZERS_PARALLELISM", "false")
    env.setdefault("OMP_NUM_THREADS", "1")
    env.setdefault("MKL_NUM_THREADS", "1")

    with log_file.open("w", encoding="utf-8") as log:
        log.write(f"START {datetime.now().isoformat()}\n")
        log.write("COMMAND " + " ".join(cmd) + "\n\n")
        log.flush()
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(repo_root),
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                check=False,
                timeout=timeout_seconds,
                **_subprocess_window_kwargs(),
            )
        except subprocess.TimeoutExpired:
            log.write(f"\nTIMEOUT after {timeout_seconds} seconds\n")
            log.write(f"END {datetime.now().isoformat()}\n")
            log.write("EXIT 124\n")
            return 124
        log.write(f"\nEND {datetime.now().isoformat()}\n")
        log.write(f"EXIT {proc.returncode}\n")

    return proc.returncode


def run_with_retries(
    python_exe: Path,
    repo_root: Path,
    job: Job,
    logs_dir: Path,
    version: str,
    retry_count: int,
    retry_lr_multiplier: float,
    timeout_seconds: float | None,
) -> tuple[int, int]:
    """Run a job and optionally retry with safer params.

    Returns: (exit_code, attempts_used)
    """
    if job.kind != "llm_train":
        code = run_agent_job(
            python_exe=python_exe,
            repo_root=repo_root,
            job=job,
            timeout_seconds=timeout_seconds,
        )
        return code, 1

    code = run_job_with_version(
        python_exe,
        repo_root,
        job,
        logs_dir,
        version,
        timeout_seconds=timeout_seconds,
    )
    attempts = 1
    if code == 0:
        return code, attempts

    for retry_idx in range(1, retry_count + 1):
        safer_batch = max(1, job.batch_size // 2)
        safer_lr = max(1e-6, job.learning_rate * (retry_lr_multiplier ** retry_idx))
        safer_version = f"{version}-retry{retry_idx}"

        retry_job = Job(
            project=job.project,
            task=job.task,
            version=safer_version,
            engine=job.engine,
            epochs=job.epochs,
            batch_size=safer_batch,
            learning_rate=safer_lr,
            base_model=job.base_model,
            max_seq_length=job.max_seq_length,
        )

        print(
            f"Retry {retry_idx}/{retry_count} for {job.project}/{job.task} "
            f"with batch_size={safer_batch}, learning_rate={safer_lr}"
        )

        code = run_job_with_version(
            python_exe,
            repo_root,
            retry_job,
            logs_dir,
            safer_version,
            timeout_seconds=timeout_seconds,
        )
        attempts += 1
        if code == 0:
            return code, attempts

    return code, attempts


def main() -> int:
    parser = argparse.ArgumentParser(description="Run sequential model training jobs")
    parser.add_argument(
        "--jobs-file",
        default="training/queue/nightly_jobs.json",
        help="Path to queue definition JSON",
    )
    parser.add_argument(
        "--python",
        default=sys.executable,
        help="Python executable path to use for training",
    )
    parser.add_argument(
        "--continue-on-error",
        action="store_true",
        help="Continue running remaining jobs if one fails",
    )
    parser.add_argument(
        "--repeat",
        action="store_true",
        help="Keep repeating the queue until max-hours is reached",
    )
    parser.add_argument(
        "--max-hours",
        type=float,
        default=None,
        help="Optional max wall-clock runtime in hours",
    )
    parser.add_argument(
        "--stamp-version",
        action="store_true",
        help="Append timestamp/cycle info to version for unique output dirs",
    )
    parser.add_argument(
        "--retry-count",
        type=int,
        default=1,
        help="Retries per failed job with safer params (default: 1)",
    )
    parser.add_argument(
        "--retry-lr-multiplier",
        type=float,
        default=0.5,
        help="Multiplier applied to LR for each retry (default: 0.5)",
    )
    parser.add_argument(
        "--max-consecutive-failures",
        type=int,
        default=16,
        help="Stop repeating queue after this many consecutive failed jobs (default: 16)",
    )
    parser.add_argument(
        "--cycle-delay-seconds",
        type=float,
        default=30.0,
        help="Delay between repeat cycles to avoid rapid failure loops (default: 30)",
    )
    parser.add_argument(
        "--job-timeout-minutes",
        type=float,
        default=180.0,
        help="Per-job timeout in minutes (default: 180)",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    jobs_file = (repo_root / args.jobs_file).resolve()
    python_exe = Path(args.python).resolve()
    ensure_log_layout(repo_root)
    logs_dir = log_dir(repo_root, "runs")
    lock_file = queue_lock_file(repo_root)
    pid_file = queue_pid_file(repo_root)
    lock_fd = acquire_queue_lock(lock_file)
    if lock_fd is None:
        return 0
    pid_file.write_text(str(os.getpid()), encoding="ascii")

    try:
        if not jobs_file.exists():
            print(f"Jobs file not found: {jobs_file}")
            return 1

        jobs = load_jobs(jobs_file)
        if not jobs:
            print("No jobs found in queue file")
            return 1

        print(f"Running {len(jobs)} queue jobs sequentially")
        print(f"Training logs directory: {logs_dir}")

        failures = 0
        successes = 0
        retries_used = 0
        deadline = None
        if args.max_hours is not None:
            deadline = datetime.now() + timedelta(hours=args.max_hours)
            print(f"Max runtime: {args.max_hours} hours (until {deadline.isoformat(timespec='seconds')})")

        cycle = 0
        consecutive_failures = 0
        while True:
            cycle += 1
            print(f"\n=== Queue Cycle {cycle} ===")

            for idx, job in enumerate(jobs, start=1):
                if deadline is not None and datetime.now() >= deadline:
                    print("Reached max runtime window, stopping queue")
                    if failures:
                        print(f"Queue completed with failures: {failures}")
                        return 2
                    print("Queue completed successfully")
                    return 0

                version = job.version
                if args.stamp_version:
                    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
                    version = f"{job.version}-c{cycle:03d}-{stamp}"

                job_label = (
                    f"{job.project}/{job.task}"
                    if job.kind == "llm_train"
                    else f"{job.kind}/{job.team or 'all'}"
                )
                print(f"[{idx}/{len(jobs)}] {job_label} ({version})")
                code, attempts = run_with_retries(
                    python_exe=python_exe,
                    repo_root=repo_root,
                    job=job,
                    logs_dir=logs_dir,
                    version=version,
                    retry_count=max(0, args.retry_count),
                    retry_lr_multiplier=args.retry_lr_multiplier,
                    timeout_seconds=(None if args.job_timeout_minutes <= 0 else args.job_timeout_minutes * 60),
                )
                if attempts > 1:
                    retries_used += attempts - 1
                if code != 0:
                    failures += 1
                    consecutive_failures += 1
                    print(f"Job failed with exit code {code}: {job_label}")
                    if args.repeat and consecutive_failures >= max(1, args.max_consecutive_failures):
                        print(
                            f"Stopping queue after {consecutive_failures} consecutive failures "
                            f"(limit={max(1, args.max_consecutive_failures)})"
                        )
                        return 2
                    if not args.continue_on_error:
                        print("Stopping queue due to failure")
                        return code
                else:
                    successes += 1
                    consecutive_failures = 0
                    if job.kind == "llm_train":
                        gate_ok, gate_note = run_ab_gate_for_job(
                            python_exe=python_exe,
                            repo_root=repo_root,
                            job=job,
                            logs_dir=logs_dir,
                        )
                        print(f"A/B gate: {gate_note}")
                        if not gate_ok:
                            failures += 1
                            if not args.continue_on_error:
                                print("Stopping queue due to A/B gate failure")
                                return 2

            if not args.repeat:
                break

            if deadline is not None and datetime.now() >= deadline:
                break

            if args.cycle_delay_seconds > 0:
                time.sleep(args.cycle_delay_seconds)

        if failures:
            print(f"Summary: successes={successes}, failures={failures}, retries_used={retries_used}")
            print(f"Queue completed with failures: {failures}")
            return 2

        print(f"Summary: successes={successes}, failures={failures}, retries_used={retries_used}")
        print("Queue completed successfully")
        return 0
    finally:
        if pid_file.exists():
            try:
                current = int(pid_file.read_text(encoding="ascii").strip())
            except ValueError:
                current = None
            if current == os.getpid():
                pid_file.unlink(missing_ok=True)
        release_queue_lock(lock_fd, lock_file)


if __name__ == "__main__":
    raise SystemExit(main())
