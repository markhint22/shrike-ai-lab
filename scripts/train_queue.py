#!/usr/bin/env python3
"""
Sequential training queue runner.

Runs training jobs one at a time by invoking scripts/train.py.
Designed for overnight execution on a single workstation.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any


@dataclass
class Job:
    project: str
    task: str
    version: str
    engine: str = "hf"
    epochs: int = 1
    batch_size: int = 1
    learning_rate: float = 2e-4
    base_model: str | None = None


def load_jobs(jobs_file: Path) -> list[Job]:
    with jobs_file.open("r", encoding="utf-8") as f:
        payload = json.load(f)

    raw_jobs = payload.get("jobs", [])
    jobs: list[Job] = []
    for item in raw_jobs:
        jobs.append(
            Job(
                project=item["project"],
                task=item["task"],
                version=item.get("version", f"nightly-{item['project']}-{item['task']}"),
                engine=item.get("engine", "hf"),
                epochs=int(item.get("epochs", 1)),
                batch_size=int(item.get("batch_size", 1)),
                learning_rate=float(item.get("learning_rate", 2e-4)),
                base_model=item.get("base_model"),
            )
        )
    return jobs


def run_job(python_exe: Path, repo_root: Path, job: Job, logs_dir: Path) -> int:
    return run_job_with_version(python_exe, repo_root, job, logs_dir, job.version)


def run_job_with_version(
    python_exe: Path,
    repo_root: Path,
    job: Job,
    logs_dir: Path,
    version: str,
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

    with log_file.open("w", encoding="utf-8") as log:
        log.write(f"START {datetime.now().isoformat()}\n")
        log.write("COMMAND " + " ".join(cmd) + "\n\n")
        log.flush()
        proc = subprocess.run(
            cmd,
            cwd=str(repo_root),
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )
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
) -> tuple[int, int]:
    """Run a job and optionally retry with safer params.

    Returns: (exit_code, attempts_used)
    """
    code = run_job_with_version(python_exe, repo_root, job, logs_dir, version)
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
        )

        print(
            f"Retry {retry_idx}/{retry_count} for {job.project}/{job.task} "
            f"with batch_size={safer_batch}, learning_rate={safer_lr}"
        )

        code = run_job_with_version(python_exe, repo_root, retry_job, logs_dir, safer_version)
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
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    jobs_file = (repo_root / args.jobs_file).resolve()
    python_exe = Path(args.python).resolve()
    logs_dir = repo_root / "training" / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)

    if not jobs_file.exists():
        print(f"Jobs file not found: {jobs_file}")
        return 1

    jobs = load_jobs(jobs_file)
    if not jobs:
        print("No jobs found in queue file")
        return 1

    print(f"Running {len(jobs)} training jobs sequentially")
    print(f"Logs directory: {logs_dir}")

    failures = 0
    successes = 0
    retries_used = 0
    deadline = None
    if args.max_hours is not None:
        deadline = datetime.now() + timedelta(hours=args.max_hours)
        print(f"Max runtime: {args.max_hours} hours (until {deadline.isoformat(timespec='seconds')})")

    cycle = 0
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

            print(f"[{idx}/{len(jobs)}] {job.project}/{job.task} ({version})")
            code, attempts = run_with_retries(
                python_exe=python_exe,
                repo_root=repo_root,
                job=job,
                logs_dir=logs_dir,
                version=version,
                retry_count=max(0, args.retry_count),
                retry_lr_multiplier=args.retry_lr_multiplier,
            )
            if attempts > 1:
                retries_used += attempts - 1
            if code != 0:
                failures += 1
                print(f"Job failed with exit code {code}: {job.project}/{job.task}")
                if not args.continue_on_error:
                    print("Stopping queue due to failure")
                    return code
            else:
                successes += 1

        if not args.repeat:
            break

        if deadline is not None and datetime.now() >= deadline:
            break

    if failures:
        print(f"Summary: successes={successes}, failures={failures}, retries_used={retries_used}")
        print(f"Queue completed with failures: {failures}")
        return 2

    print(f"Summary: successes={successes}, failures={failures}, retries_used={retries_used}")
    print("Queue completed successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
