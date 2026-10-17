#!/usr/bin/env python3
"""phase5_common.py - tiny shared plumbing for the Phase 5 shadow tools (wip_cap.py, gpu_ledger.py, promote_manifest.py, rollback_drill.py).

Everything here is fail-soft: no helper raises into a caller for an I/O problem, nothing writes outside <state_dir>, and nothing here ever
takes run.lock or touches a live clone. State dir resolution is qa_common.state_dir() (QA_STATE_DIR > OVN_DIR/state).
"""
import json
import os
import sys
try:
    import fcntl
except ImportError:  # pragma: no cover - non-posix
    fcntl = None
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402


def flag(env_name, allowed, default="shadow"):
    """-> (mode, note). The env value when it is one of `allowed`; anything else (unset, typo, a value that is not wired in this package such
    as 'enforce') falls back to `default` and `note` says why, so a stray value can never switch behaviour ON."""
    raw = os.environ.get(env_name)
    if raw is None or raw == "":
        return default, ""
    v = raw.strip().lower()
    if v in allowed:
        return v, ""
    return default, "%s=%r is not one of %s: using %s (this package wires no enforcement)" % (env_name, raw[:20], "|".join(allowed), default)


def read_jsonl(path):
    """Yield dict rows of a jsonl file; torn / non-dict / NUL-ridden lines are skipped, a missing file yields nothing."""
    try:
        with open(path, "rb") as f:
            for raw in f:
                try:
                    d = json.loads(raw.decode("utf-8", "replace"))
                except ValueError:
                    continue
                if isinstance(d, dict):
                    yield d
    except OSError:
        return


def append_jsonl(path, obj):
    """Append one sorted-key JSON line (creating the dir). Returns True on success; never raises."""
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a") as f:
            f.write(json.dumps(obj, ensure_ascii=False, sort_keys=True, default=str) + "\n")
        return True
    except OSError:
        return False


def atomic_write(path, text):
    """temp file in the same dir + os.replace (a concurrent reader sees the old or the new file, never a torn one). Returns True on success."""
    try:
        d = os.path.dirname(path) or "."
        os.makedirs(d, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=".p5.", dir=d)
        try:
            try:
                os.fchmod(fd, 0o644)         # mkstemp is 0600; sibling state files are 0644 and the dashboards read them
            except OSError:
                pass
            with os.fdopen(fd, "w") as f:
                f.write(text)
            os.replace(tmp, path)
        except BaseException:
            try:
                os.unlink(tmp)
            except OSError:
                pass
            raise
        return True
    except OSError:
        return False


def shadow_path(name):
    return os.path.join(qc.state_dir(), "qa_shadow", name)


def alert_once(level, tag, msg, dedupe_key, now=None):
    """ONE alerts.log line per dedupe_key per UTC day (the single alert channel, same line format as the other QA gates; no ntfy here).
    The whole read-dedupe-append-save sequence runs under an flock on phase5_alerted.lock, so two concurrent manual runs cannot both emit the line.
    Returns True when a line was written."""
    now = time.time() if now is None else now
    day = time.strftime("%Y-%m-%d", time.gmtime(now))
    sd = qc.state_dir()
    try:
        os.makedirs(sd, exist_ok=True)
    except OSError:
        return False
    lk = None
    try:
        if fcntl is not None:
            lk = open(os.path.join(sd, "phase5_alerted.lock"), "a")
            fcntl.flock(lk, fcntl.LOCK_EX)
    except OSError:
        lk = None
    try:
        p = os.path.join(sd, "phase5_alerted.json")
        try:
            with open(p) as f:
                seen = json.load(f)
            if not isinstance(seen, dict):
                seen = {}
        except (OSError, ValueError):
            seen = {}
        seen = {k: v for k, v in seen.items() if v == day}      # yesterday's keys are forgotten (so a persisting breach re-alerts daily)
        if dedupe_key in seen:
            return False
        seen[dedupe_key] = day
        try:
            with open(os.path.join(sd, "alerts.log"), "a") as f:
                f.write("[%s] %s | %s | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), level, tag, msg.replace("\n", " ")[:400]))
        except OSError:
            return False
        atomic_write(p, json.dumps(seen, sort_keys=True))
        return True
    finally:
        if lk is not None:
            try:
                lk.close()
            except OSError:
                pass


def opt(argv, name, default=""):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else default
