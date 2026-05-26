#!/usr/bin/env python3
"""Crash recovery launcher for Shrike AI Lab on Windows.

Restores local services and training queue after reboot/crash:
- Ollama (port 11434)
- LiteLLM proxy (port 4000)
- Nightly training queue (detached)
- Optional Open WebUI via docker compose (if docker exists)

Also captures Windows crash diagnostics to training/logs/diagnostics/crash-diag-*.txt.
"""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from log_layout import ensure_log_layout, log_dir, logs_root


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def run(
    cmd: list[str],
    cwd: Path | None = None,
    timeout_seconds: float | None = 30,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        check=False,
        capture_output=True,
        text=True,
        timeout=timeout_seconds,
    )


def is_port_open(host: str, port: int, timeout: float = 1.0) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(timeout)
        return sock.connect_ex((host, port)) == 0


def http_status(url: str, headers: dict[str, str] | None = None, timeout: float = 5.0) -> int | None:
    request = Request(url, headers=headers or {})
    try:
        with urlopen(request, timeout=timeout) as response:
            return response.status
    except HTTPError as err:
        return err.code
    except (URLError, TimeoutError, OSError):
        # Python 3.11+: socket-level TimeoutError is NOT a subclass of URLError
        # and can escape the URLError handler when the port is bound but not
        # yet fully serving (common during LiteLLM startup after a crash).
        return None


def process_exists(pid: int) -> bool:
    result = run(["tasklist", "/FI", f"PID eq {pid}"])
    return str(pid) in (result.stdout or "")


def find_python(repo_root: Path) -> Path:
    candidates = [
        repo_root / ".venv" / "Scripts" / "python.exe",
        Path(sys.executable),
        Path(r"C:\Users\markh\AppData\Local\Programs\Python\Python311\python.exe"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    raise FileNotFoundError("No usable python executable found")


def find_litellm_command(repo_root: Path, py_exe: Path) -> list[str]:
    """Prefer the litellm console entrypoint to avoid module runpy issues.

    Falls back to python -m invocation if the script is not present.
    """
    candidates = [
        repo_root / ".venv" / "Scripts" / "litellm.exe",
        repo_root / ".venv" / "Scripts" / "litellm",
    ]
    for candidate in candidates:
        if candidate.exists():
            return [str(candidate)]

    where = run(["where", "litellm"], timeout_seconds=8)
    if where.returncode == 0 and where.stdout.strip():
        first = where.stdout.splitlines()[0].strip()
        if first:
            return [first]

    return [str(py_exe), "-m", "litellm.proxy.proxy_cli"]


def find_docker() -> Path | None:
    candidates = [
        Path(r"C:\Program Files\Docker\Docker\resources\bin\docker.exe"),
        Path(r"C:\Program Files\Docker\Docker\resources\docker.exe"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    where = run(["where", "docker"], timeout_seconds=8)
    if where.returncode == 0 and where.stdout.strip():
        first = Path(where.stdout.splitlines()[0].strip())
        if first.exists():
            return first
    return None


def get_litellm_pids() -> list[int]:
    query = (
        "Get-CimInstance Win32_Process | "
        "Where-Object { $_.CommandLine -match 'litellm\\.proxy\\.proxy_cli' } | "
        "Select-Object -ExpandProperty ProcessId"
    )
    try:
        result = run(["powershell", "-NoProfile", "-Command", query], timeout_seconds=15)
    except subprocess.TimeoutExpired:
        return []
    if result.returncode != 0:
        return []
    pids: list[int] = []
    for line in (result.stdout or "").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            pids.append(int(line))
        except ValueError:
            continue
    return pids


def get_port_owner_pid(port: int) -> int | None:
    try:
        result = run(["netstat", "-ano"], timeout_seconds=15)
    except subprocess.TimeoutExpired:
        return None
    if result.returncode != 0:
        return None
    for line in (result.stdout or "").splitlines():
        row = line.strip()
        if not row.startswith("TCP"):
            continue
        cols = row.split()
        if len(cols) < 5:
            continue
        local_addr, state, pid_str = cols[1], cols[3], cols[4]
        if local_addr.endswith(f":{port}") and state.upper() == "LISTENING":
            try:
                return int(pid_str)
            except ValueError:
                return None
    return None


def kill_pid(pid: int) -> bool:
    result = run(["taskkill", "/PID", str(pid), "/F"])
    return result.returncode == 0


def start_ollama(log_file: Path) -> bool:
    if http_status("http://localhost:11434/api/tags") == 200:
        return True
    with log_file.open("a", encoding="utf-8") as log:
        creationflags = 0
        if sys.platform == "win32":
            creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
        subprocess.Popen(
            ["ollama", "serve"],
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            creationflags=creationflags,
        )
    for _ in range(30):
        if http_status("http://localhost:11434/api/tags") == 200:
            return True
        time.sleep(1)
    return False


def litellm_is_healthy() -> bool:
    # Quick port check first — avoids a slow HTTP timeout when the process
    # hasn't bound the port yet, and lets the urlopen timeout guard against
    # the port-bound-but-not-serving window seen during LiteLLM startup.
    if not is_port_open("localhost", 4000, timeout=1.0):
        return False
    status = http_status(
        "http://localhost:4000/health",
        headers={"Authorization": "Bearer sk-shrike-local"},
        timeout=10,
    )
    # LiteLLM /health returns 200 when all configured endpoints are reachable.
    # A 401 means the proxy is running but the key is wrong — not a crash.
    return status == 200


def start_litellm(repo_root: Path, py_exe: Path, log_file: Path) -> bool:
    if litellm_is_healthy():
        return True

    env = os.environ.copy()
    env.setdefault("LITELLM_MASTER_KEY", "sk-shrike-local")
    # Fix UnicodeEncodeError when banner/emoji is written to a cp1252 log file
    env["PYTHONIOENCODING"] = "utf-8"
    # PRODUCTION mode suppresses heavy telemetry and the FastAPI lifespan recursion
    env.setdefault("LITELLM_MODE", "PRODUCTION")
    litellm_cmd = find_litellm_command(repo_root, py_exe)

    with log_file.open("a", encoding="utf-8") as log:
        creationflags = 0
        if sys.platform == "win32":
            creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
        subprocess.Popen(
            litellm_cmd
            + [
                "--config",
                "configs/litellm_config.yaml",
                "--host",
                "0.0.0.0",
                "--port",
                "4000",
            ],
            cwd=str(repo_root),
            env=env,
            stdout=log,
            stderr=subprocess.STDOUT,
            text=True,
            creationflags=creationflags,
        )

    # LiteLLM can take 45-90 s to fully start on this machine; poll generously.
    for _ in range(90):
        if litellm_is_healthy():
            return True
        time.sleep(1)
    return False


def cleanup_extra_litellm() -> dict[str, Any]:
    pids = get_litellm_pids()
    owner = get_port_owner_pid(4000)
    killed: list[int] = []
    for pid in pids:
        if owner is not None and pid == owner:
            continue
        if pid != owner:
            if kill_pid(pid):
                killed.append(pid)
    return {"all": pids, "owner": owner, "killed": killed}


def training_running(repo_root: Path) -> bool:
    queue_pid = log_dir(repo_root, "queue") / "nightly-queue.pid"
    legacy_pid = logs_root(repo_root) / "nightly-queue.pid"
    pid_file = queue_pid if queue_pid.exists() else legacy_pid
    if not pid_file.exists():
        return False
    try:
        pid = int(pid_file.read_text(encoding="ascii").strip())
    except ValueError:
        return False
    return process_exists(pid)


def start_training_queue(repo_root: Path, py_exe: Path) -> tuple[bool, str]:
    if training_running(repo_root):
        return True, "already running"

    cmd = [
        str(py_exe),
        str(repo_root / "scripts" / "start_nightly_queue.py"),
        "--python",
        str(py_exe),
        "--jobs-file",
        "training/queue/nightly_jobs.json",
        "--max-hours",
        "18",
        "--retry-count",
        "1",
        "--retry-lr-multiplier",
        "0.5",
        "--max-consecutive-failures",
        "16",
        "--cycle-delay-seconds",
        "30",
    ]
    try:
        result = run(cmd, cwd=repo_root, timeout_seconds=45)
    except subprocess.TimeoutExpired:
        return False, "start_nightly_queue.py timed out"
    ok = result.returncode == 0
    note = (result.stdout or "").strip() or (result.stderr or "").strip()
    return ok, note


def start_open_webui_if_possible(repo_root: Path) -> tuple[bool, str]:
    if http_status("http://localhost:3000") == 200:
        return True, "already running"

    docker = find_docker()
    if docker is None:
        return False, "docker cli not found"

    try:
        compose = run(
            [str(docker), "compose", "up", "-d", "open-webui"],
            cwd=repo_root,
            timeout_seconds=120,
        )
    except subprocess.TimeoutExpired:
        return False, "docker compose timed out"
    if compose.returncode != 0:
        return False, (compose.stderr or compose.stdout or "docker compose failed").strip()

    for _ in range(20):
        if http_status("http://localhost:3000") in {200, 302, 307}:
            return True, "started via docker compose"
        time.sleep(1)

    return False, "open-webui did not report healthy after startup"


def collect_crash_diagnostics(repo_root: Path, lookback_hours: int = 24) -> Path:
    logs_dir = log_dir(repo_root, "diagnostics")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_file = logs_dir / f"crash-diag-{stamp}.txt"

    start_time = (datetime.now() - timedelta(hours=lookback_hours)).strftime("%Y-%m-%dT%H:%M:%S")

    script = f"""
$ErrorActionPreference = 'Continue'
Write-Output "=== Crash Diagnostics ({lookback_hours}h) ==="
Write-Output "Collected: $(Get-Date -Format o)"
Write-Output ""
Write-Output "--- Last bugcheck/reboot indicators (System) ---"
Get-WinEvent -FilterHashtable @{{LogName='System'; StartTime=[datetime]'{start_time}'}} |
  Where-Object {{ $_.Id -in 41, 6008, 1001, 1074 }} |
  Select-Object TimeCreated, Id, ProviderName, LevelDisplayName, Message |
  Format-List
Write-Output ""
Write-Output "--- WHEA hardware errors (System) ---"
Get-WinEvent -FilterHashtable @{{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'; StartTime=[datetime]'{start_time}'}} |
  Select-Object TimeCreated, Id, LevelDisplayName, Message |
  Format-List
Write-Output ""
Write-Output "--- Application errors (Application) ---"
Get-WinEvent -FilterHashtable @{{LogName='Application'; StartTime=[datetime]'{start_time}'}} |
  Where-Object {{ $_.LevelDisplayName -in 'Error','Critical' }} |
  Select-Object -First 60 TimeCreated, Id, ProviderName, LevelDisplayName, Message |
  Format-List
"""

    try:
        result = run(
            ["powershell", "-NoProfile", "-Command", script],
            timeout_seconds=90,
        )
        text = result.stdout or ""
        if result.stderr:
            text += "\n--- STDERR ---\n" + result.stderr
    except subprocess.TimeoutExpired:
        text = (
            "Diagnostics collection timed out after 90 seconds. "
            "Run scripts/recover_after_crash.py --skip-diagnostics to bypass this step.\n"
        )
    out_file.write_text(text, encoding="utf-8")
    return out_file


def main() -> int:
    parser = argparse.ArgumentParser(description="Recover Shrike AI Lab services after crash")
    parser.add_argument("--skip-diagnostics", action="store_true", help="Skip Windows event collection")
    parser.add_argument("--skip-open-webui", action="store_true", help="Skip Open WebUI restore checks")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    ensure_log_layout(repo_root)
    recovery_dir = log_dir(repo_root, "recovery")
    services_dir = log_dir(repo_root, "services")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")

    summary: dict[str, Any] = {"timestamp_utc": utc_now_iso()}

    def step(message: str) -> None:
        print(message, flush=True)

    step("[1/6] locating python runtime")
    py_exe = find_python(repo_root)
    summary["python"] = str(py_exe)

    if not args.skip_diagnostics:
        step("[2/6] collecting crash diagnostics")
        diag_file = collect_crash_diagnostics(repo_root)
        summary["diagnostics_file"] = str(diag_file)

    ollama_log = services_dir / f"recovery-ollama-{stamp}.log"
    litellm_log = services_dir / f"recovery-litellm-{stamp}.log"

    step("[3/6] ensuring Ollama is healthy")
    summary["ollama_ok"] = start_ollama(ollama_log)

    step("[4/6] ensuring LiteLLM is healthy")
    summary["litellm_ok"] = start_litellm(repo_root, py_exe, litellm_log)
    summary["litellm_cleanup"] = cleanup_extra_litellm()

    step("[5/6] ensuring nightly training queue is running")
    queue_ok, queue_note = start_training_queue(repo_root, py_exe)
    summary["training_queue_ok"] = queue_ok
    summary["training_queue_note"] = queue_note

    if args.skip_open_webui:
        summary["open_webui"] = "skipped"
    else:
        step("[6/6] restoring Open WebUI if docker is available")
        webui_ok, webui_note = start_open_webui_if_possible(repo_root)
        summary["open_webui_ok"] = webui_ok
        summary["open_webui_note"] = webui_note

    summary_file = recovery_dir / f"recovery-summary-{stamp}.json"
    summary_file.write_text(json.dumps(summary, indent=2), encoding="utf-8")

    print(json.dumps(summary, indent=2))
    print(f"summary_file={summary_file}")

    if not summary.get("ollama_ok") or not summary.get("litellm_ok") or not summary.get("training_queue_ok"):
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
