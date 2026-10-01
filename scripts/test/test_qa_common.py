#!/usr/bin/env python3
"""Tests for qa/qa_common.py + qa/qa_replay.py - the contract every QA gate relies on."""
import json, os, subprocess, sys, tempfile, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
QA = os.path.abspath(os.path.join(HERE, "..", "..", "qa"))
sys.path.insert(0, QA)
import qa_common as qc
P = F = 0
def ok(name, cond):
    global P, F
    if cond: P += 1; print("  ok   " + name)
    else: F += 1; print("  FAIL " + name)

T = tempfile.mkdtemp(prefix="qa-common-test-")
os.environ["OVN_DIR"] = T
os.makedirs(os.path.join(T, "state"))
for k in [k for k in os.environ if k.startswith("OVN_QA_")]: del os.environ[k]

ok("mode defaults to shadow", qc.mode("antigaming") == "shadow")
json.dump({"antigaming": "enforce", "scanners": "bogus"}, open(os.path.join(T, "state", "qa_modes.json"), "w"))
ok("mode read from state/qa_modes.json", qc.mode("antigaming") == "enforce")
ok("an invalid mode value falls back to shadow", qc.mode("scanners") == "shadow")
os.environ["OVN_QA_ANTIGAMING"] = "off"
ok("env var beats the state file", qc.mode("antigaming") == "off")
ok("gate names with dashes map to the env var", (lambda: (os.environ.__setitem__("OVN_QA_MY_GATE", "enforce"), qc.mode("my-gate"))[1])() == "enforce")
del os.environ["OVN_QA_ANTIGAMING"]

v = qc.verdict("PASS", "g", "r", "ref", "fine")
ok("verdict() builds the canonical shape", all(k in v for k in ("ts", "gate", "repo", "ref", "verdict", "mode", "summary", "details", "ms")))
ok("an invalid verdict is coerced to UNVERIFIED (never PASS)", qc.verdict("MAYBE", "g", "r", "x")["verdict"] == "UNVERIFIED")
qc.record(v)
rows = [json.loads(l) for l in open(os.path.join(T, "state", "qa_shadow", "g.jsonl"))]
ok("record() appends one JSON line per result", len(rows) == 1 and rows[0]["verdict"] == "PASS")
os.environ["OVN_DIR"] = "/proc/definitely/not/writable"
try:
    qc.record(v); safe = True
except Exception:
    safe = False
ok("record() never raises even when the state dir is unwritable", safe)
os.environ["OVN_DIR"] = T

rc, out, err = qc.run(["sleep", "5"], timeout=1, polite=False)
ok("run() reports rc=124 on timeout", rc == 124)
ok("run() reports rc=127 for a missing binary", qc.run(["definitely-not-a-binary-xyz"], polite=False)[0] == 127)
ok("run() captures stdout", qc.run(["echo", "hi"], polite=False)[1].strip() == "hi")
os.environ["QA_CPUSET"] = ""
ok("cpu_prefix() is nice'd", "nice" in qc.cpu_prefix())

# main_guard: crash -> UNVERIFIED + exit 0 ; enforce+FAIL+--enforce-exit -> exit 1
import io, contextlib
def crash(argv): raise RuntimeError("boom")
buf = io.StringIO()
with contextlib.redirect_stdout(buf): rc = qc.main_guard("crashy", crash, ["--no-record"])
ok("main_guard turns an exception into UNVERIFIED and exit 0", rc == 0 and json.loads(buf.getvalue())["verdict"] == "UNVERIFIED")
os.environ["OVN_QA_FAILY"] = "enforce"
def failing(argv): return qc.verdict("FAIL", "faily", "r", "x", "bad")
buf = io.StringIO()
with contextlib.redirect_stdout(buf): rc_noflag = qc.main_guard("faily", failing, ["--no-record"])
buf = io.StringIO()
with contextlib.redirect_stdout(buf): rc_flag = qc.main_guard("faily", failing, ["--no-record", "--enforce-exit"])
ok("enforce-mode FAIL exits 1 only when --enforce-exit is passed", rc_noflag == 0 and rc_flag == 1)
os.environ["OVN_QA_FAILY"] = "shadow"
buf = io.StringIO()
with contextlib.redirect_stdout(buf): rc_sh = qc.main_guard("faily", failing, ["--no-record", "--enforce-exit"])
ok("shadow-mode FAIL never exits non-zero", rc_sh == 0)

# worktree helper + replay harness against a throwaway git repo
R = os.path.join(T, "repos", "demo"); os.makedirs(R)
def g(*a): return subprocess.run(["git", "-C", R] + list(a), capture_output=True, text=True, env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t"))
g("init", "-q", "-b", "develop")
for i in range(3):
    open(os.path.join(R, "f%d.txt" % i), "w").write("x%d\n" % i); g("add", "f%d.txt" % i); g("commit", "-q", "-m", "c%d" % i)
os.environ["OVN_REPOS_DIR"] = os.path.join(T, "repos")
ok("repo_dir resolves a clone by name", qc.repo_dir("demo") == R)
with qc.worktree(R, "HEAD") as wt:
    inside = wt is not None and os.path.isfile(os.path.join(wt, "f2.txt"))
    wtpath = wt
ok("worktree() checks out the ref and is removed afterwards", inside and not os.path.exists(wtpath))
ok("worktree() leaves no registered worktrees behind", "worktree" not in g("worktree", "list", "--porcelain").stdout.replace(R, "").replace("worktree ", "x", 0) or g("worktree", "list").stdout.count("\n") == 1)
ok("changed_files lists files in a range", qc.changed_files(R, "HEAD~1", "HEAD") == ["f2.txt"])
gate = os.path.join(T, "fake_gate.py")
open(gate, "w").write('import sys,json\na=sys.argv\nhead=a[a.index("--head")+1]\nprint(json.dumps({"verdict":"FLAG" if head.startswith("0") or head.startswith("1") else "PASS","summary":"s","details":{}}))\n')
out = subprocess.run([sys.executable, os.path.join(QA, "qa_replay.py"), gate, "demo", "--branch", "develop", "--days", "30"], capture_output=True, text=True, env=dict(os.environ))
ok("replay summarises verdicts over history (2 commits with parents)", "replay fake_gate on demo" in out.stdout and "2 commits" in out.stdout)
ok("replay writes per-commit results", os.path.isfile(os.path.join(T, "state", "qa_replay", "fake_gate-demo.jsonl")))
shutil.rmtree(T, ignore_errors=True)
print("  %d passed, %d failed" % (P, F)); sys.exit(1 if F else 0)
