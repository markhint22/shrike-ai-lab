#!/usr/bin/env python3
"""qa_common.py - shared plumbing for every QA gate (see docs/QA_GATES_SPEC.md).

Design rules enforced here so individual gates cannot get them wrong:
  * A gate has a MODE: off | shadow | enforce. Resolution: env OVN_QA_<GATE> > state/qa_gate_modes.json (written by qa/qa_enforce.sh)
    > state/qa_modes.json (legacy) > "shadow". Nothing ships as enforce: new gates default to shadow (log, never block).
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
    # 2026-10-02: QA_STATE_DIR lets branch_hygiene.sh (whose STATE_DIR is itself overridable, e.g. by its test fixtures) and the gates it spawns
    # agree on ONE state dir. Unset => <OVN_DIR>/state exactly as before.
    return os.environ.get("QA_STATE_DIR") or os.path.join(ovn_dir(), "state")


GATE_MODES_FILE = "qa_gate_modes.json"
GATE_MODES_HISTORY = "qa_gate_modes.history.jsonl"


def mode_source(gate):
    """(mode, source) where source is env | file | legacy | default. A missing/corrupt/unknown-valued file never raises and never
    yields enforce: it falls through to the next source (an unreadable flip file must not silently turn enforcement on OR off)."""
    env = os.environ.get("OVN_QA_" + gate.upper().replace("-", "_"))
    if env in MODES:
        return env, "env"
    for fname, src in ((GATE_MODES_FILE, "file"), ("qa_modes.json", "legacy")):
        try:
            with open(os.path.join(state_dir(), fname)) as f:
                v = json.load(f).get(gate)
            if v in MODES:
                return v, src
        except (OSError, ValueError, AttributeError):
            pass
    return "shadow", "default"


def mode(gate):
    """off | shadow | enforce for `gate` (env > state/qa_gate_modes.json > state/qa_modes.json > shadow)."""
    return mode_source(gate)[0]


def set_gate_mode(gate, new_mode, who="?"):
    """Persist `new_mode` for `gate` in state/qa_gate_modes.json (atomic: temp file in the same dir + os.replace, so a concurrent
    mode() reader sees the old or the new file, never a torn one) and append who/when to qa_gate_modes.history.jsonl.
    Raises ValueError on a bad gate name / mode; never leaves a partial file."""
    import re
    if new_mode not in MODES:
        raise ValueError("mode must be one of %s" % "|".join(MODES))
    if not re.match(r"^[a-z0-9][a-z0-9_-]*$", gate or ""):
        raise ValueError("bad gate name %r" % gate)
    d = state_dir()
    os.makedirs(d, exist_ok=True)
    path = os.path.join(d, GATE_MODES_FILE)
    try:
        with open(path) as f:
            cur = json.load(f)
        if not isinstance(cur, dict):
            cur = {}
    except (OSError, ValueError):
        cur = {}
    prev = cur.get(gate)
    cur[gate] = new_mode
    fd, tmp = tempfile.mkstemp(prefix=".qa_gate_modes.", dir=d)
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(cur, f, indent=1, sort_keys=True)
            f.write("\n")
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    with open(os.path.join(d, GATE_MODES_HISTORY), "a") as f:
        f.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "gate": gate, "from": prev, "to": new_mode,
                            "who": who}, sort_keys=True) + "\n")
    return prev


def paused_repos():
    """Repo names whose dev lane is PAUSED, so per-merge gates that cost CPU may skip them (2026-10-03: scanners ran 117 times for paused shrike-* lanes).
    Sources, unioned: env QA_PAUSED_REPOS (comma list; 'none' = nothing is paused, for tests; empty = unset), the tracked list qa/qa_paused_repos.txt next to this
    file and state/qa_paused_repos.txt. EXPLICIT lists only: pause is never inferred from tasks.json (a `queue.sh hold` would silently switch off secret
    scanning for a repo that still receives interactive commits). Missing files never raise."""
    env = os.environ.get("QA_PAUSED_REPOS")
    if env is not None and env.strip():
        return set() if env.strip().lower() == "none" else set(x.strip() for x in env.split(",") if x.strip())
    out = set()
    for path in (os.path.join(os.path.dirname(os.path.abspath(__file__)), "qa_paused_repos.txt"), os.path.join(state_dir(), "qa_paused_repos.txt")):
        try:
            with open(path) as f:
                for line in f:
                    line = line.split("#", 1)[0].strip()
                    if line:
                        out.add(line)
        except OSError:
            pass
    return out


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


def ensure_commits(repo_path, refs, attempts=3, wait=15):
    """True when every ref resolves to a commit in repo_path. 2026-10-02: the hygiene hook hands the shadow run the merge commit it just made in a
    TEMP clone; the live clone does not have it until it fetches (8 of 65 real runs = 12% ended UNVERIFIED 'cannot resolve ref'). So when something is
    missing, fetch origin (read-only: updates remote-tracking refs/objects, never the working tree - reconcile_branches does the same every 20 min)
    and retry a couple of times (the merge may not be pushed yet). Never raises."""
    def missing():
        return [r for r in refs if git(repo_path, "rev-parse", "--verify", "-q", r + "^{commit}")[0] != 0]
    try:
        m = missing()
        for i in range(max(0, attempts)):
            if not m:
                break
            git(repo_path, "fetch", "-q", "--no-tags", "origin", timeout=90)
            m = missing()
            if m and i < attempts - 1:
                time.sleep(wait)
        return not m
    except Exception:  # noqa: BLE001
        return False


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
