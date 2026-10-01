#!/usr/bin/env python3
"""qa_common.py - shared plumbing for every QA gate (see docs/QA_GATES_SPEC.md).

Design rules enforced here so individual gates cannot get them wrong:
  * A gate has a MODE: off | shadow | enforce. Resolution: env OVN_QA_<GATE> > state/qa_modes.json > "shadow".
    Nothing ships as enforce: new gates default to shadow (log, never block).
  * Verdicts are exactly PASS | FAIL | FLAG | NA | UNVERIFIED. UNVERIFIED is what a gate says when it could not run
    (timeout, contention, missing tool) - never PASS, never FAIL. There is no composite score.
  * A gate never raises into its caller: every entry point is wrapped by `main_guard`, which converts any exception into an
    UNVERIFIED verdict + exit code 0.
  * Shadow results are appended (one JSON line) to state/qa_shadow/<gate>.jsonl.
  * Gates read repos through detached git worktrees under a temp dir and always clean them up; they never touch a live clone,
    never `git add -A`, never take run.lock or a per-repo verify lock.
"""
import contextlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

VERDICTS = ("PASS", "FAIL", "FLAG", "NA", "UNVERIFIED")
MODES = ("off", "shadow", "enforce")


def ovn_dir():
    return os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")


def state_dir():
    return os.path.join(ovn_dir(), "state")


def mode(gate):
    """off | shadow | enforce for `gate` (env > state/qa_modes.json > shadow)."""
    env = os.environ.get("OVN_QA_" + gate.upper().replace("-", "_"))
    if env in MODES:
        return env
    try:
        with open(os.path.join(state_dir(), "qa_modes.json")) as f:
            v = json.load(f).get(gate)
        if v in MODES:
            return v
    except (OSError, ValueError, AttributeError):
        pass
    return "shadow"


def verdict(v, gate, repo, ref, summary="", details=None, ms=None):
    """Build the canonical result dict (does not write it)."""
    if v not in VERDICTS:
        v, summary = "UNVERIFIED", "gate returned an invalid verdict %r: %s" % (v, summary)
    return {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "gate": gate, "repo": repo, "ref": ref,
            "verdict": v, "mode": mode(gate), "summary": summary[:400], "details": details or {}, "ms": ms}


def record(result):
    """Append one result to state/qa_shadow/<gate>.jsonl. Never raises."""
    try:
        d = os.path.join(state_dir(), "qa_shadow")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, result["gate"] + ".jsonl"), "a") as f:
            f.write(json.dumps(result, ensure_ascii=False, sort_keys=True) + "\n")
    except Exception:  # noqa: BLE001 - recording must never break a caller
        pass


def cpu_prefix():
    """Command prefix that keeps QA CPU work polite: nice + idle io class, and (if configured) a CPU set.
    QA_CPUSET e.g. '10-15' pins to those cores (the box has 16; the plan caps QA at 6)."""
    p = ["nice", "-n", "15"]
    if shutil.which("ionice"):
        p = ["ionice", "-c3"] + p
    cs = os.environ.get("QA_CPUSET", "")
    if cs and shutil.which("taskset"):
        p = ["taskset", "-c", cs] + p
    return p


def run(cmd, cwd=None, timeout=120, env=None, polite=True, input_text=None):
    """Run a command with a hard timeout. Returns (rc, stdout, stderr); rc=124 on timeout, 127 if the binary is missing.
    Output is captured as text with errors replaced (never raises on bad bytes)."""
    full = (cpu_prefix() if polite else []) + list(cmd)
    e = dict(os.environ)
    if env:
        e.update(env)
    try:
        p = subprocess.run(full, cwd=cwd, env=e, capture_output=True, timeout=timeout, input=(input_text.encode() if input_text else None))
        return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")
    except subprocess.TimeoutExpired as ex:
        return 124, (ex.stdout or b"").decode("utf-8", "replace"), "timeout after %ss" % timeout
    except FileNotFoundError as ex:
        return 127, "", str(ex)


def git(repo_dir, *args, timeout=60):
    return run(["git", "-C", repo_dir] + list(args), timeout=timeout, polite=False)


def repo_dir(name):
    """Resolve a repo name to a clone: $OVN_REPOS_DIR/<name>, ~/overnight-queue/repos/<name>, then ~/LocalProjects/<name>."""
    cands = []
    if os.environ.get("OVN_REPOS_DIR"):
        cands.append(os.path.join(os.environ["OVN_REPOS_DIR"], name))
    cands += [os.path.join(ovn_dir(), "repos", name), os.path.expanduser("~/LocalProjects/" + name)]
    for c in cands:
        if os.path.isdir(os.path.join(c, ".git")) or os.path.isfile(os.path.join(c, ".git")):
            return c
    return None


@contextlib.contextmanager
def worktree(repo_path, ref):
    """Detached worktree of `ref` in a temp dir; ALWAYS removed. Yields the path (or None if it could not be created)."""
    tmp = tempfile.mkdtemp(prefix="qa-wt-")
    wt = os.path.join(tmp, "wt")
    rc, _, err = git(repo_path, "worktree", "add", "-q", "--detach", wt, ref, timeout=120)
    try:
        yield wt if rc == 0 else None
    finally:
        git(repo_path, "worktree", "remove", "--force", wt, timeout=60)
        git(repo_path, "worktree", "prune", timeout=30)
        shutil.rmtree(tmp, ignore_errors=True)


def changed_files(repo_path, base, head):
    rc, out, _ = git(repo_path, "diff", "--name-only", "--diff-filter=ACMR", "%s..%s" % (base, head))
    return [l for l in out.splitlines() if l] if rc == 0 else []


def diff_text(repo_path, base, head, paths=None, unified=3):
    args = ["diff", "-U%d" % unified, "%s..%s" % (base, head)]
    if paths:
        args += ["--"] + list(paths)
    rc, out, _ = git(repo_path, *args, timeout=120)
    return out if rc == 0 else ""


def main_guard(gate, fn, argv=None):
    """Run fn(argv)->result dict, print it as JSON, record it in shadow, and ALWAYS exit 0 unless mode==enforce and verdict==FAIL
    and the caller passed --enforce-exit. Any exception becomes an UNVERIFIED verdict."""
    argv = list(sys.argv[1:] if argv is None else argv)
    enforce_exit = "--enforce-exit" in argv
    argv = [a for a in argv if a != "--enforce-exit"]
    t0 = time.time()
    try:
        res = fn(argv)
    except SystemExit:
        raise
    except Exception as ex:  # noqa: BLE001
        res = verdict("UNVERIFIED", gate, "?", "?", "gate crashed: %s: %s" % (type(ex).__name__, ex))
    if res.get("ms") is None:
        res["ms"] = int((time.time() - t0) * 1000)
    if "--no-record" not in argv:
        record(res)
    print(json.dumps(res, ensure_ascii=False, sort_keys=True))
    return 1 if (enforce_exit and res["mode"] == "enforce" and res["verdict"] == "FAIL") else 0
