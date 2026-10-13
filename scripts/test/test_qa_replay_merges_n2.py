#!/usr/bin/env python3
"""qa_replay.py --merges (package qa, 2026-10-13): replay the first-parent MERGES of a branch as `<merge>^..<merge>` (the range branch_hygiene's pre-push QA hook judges) instead
of every non-merge commit (which judges intermediate states such as the harness's placeholder stub before its fill-in). A fake gate records its --base/--head."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
QA = os.path.abspath(os.path.join(HERE, "..", "..", "qa"))
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + extra) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-replay-merges-"))
REPOS, STATE = os.path.join(T, "repos"), os.path.join(T, "state")
os.makedirs(os.path.join(REPOS, "demo"))
os.makedirs(STATE)
env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": T, "OVN_DIR": T, "OVN_REPOS_DIR": REPOS, "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"}
R = os.path.join(REPOS, "demo")


def g(*a):
    return subprocess.run(["git", "-C", R, "-c", "user.name=t", "-c", "user.email=t@t", *a], capture_output=True, text=True, env=env).stdout.strip()


g("init", "-q", "-b", "develop")
open(os.path.join(R, "a.txt"), "w").write("a\n")
g("add", "-A"); g("commit", "-q", "-m", "base")
g("checkout", "-q", "-b", "feature")
for i in range(3):
    open(os.path.join(R, "f%d.txt" % i), "w").write("x\n")
    g("add", "-A"); g("commit", "-q", "-m", "feat %d" % i)
g("checkout", "-q", "develop")
g("merge", "-q", "--no-ff", "-m", "merge feature", "feature")
merge = g("rev-parse", "HEAD")
open(os.path.join(R, "d.txt"), "w").write("d\n")
g("add", "-A"); g("commit", "-q", "-m", "direct commit on develop")
g("update-ref", "refs/remotes/origin/develop", "HEAD")
gate = os.path.join(T, "gate_fake.py")
open(gate, "w").write('import json, os, sys\nopen(os.path.join(%r, "calls.log"), "a").write(" ".join(sys.argv[1:]) + "\\n")\nprint(json.dumps({"verdict": "PASS", "summary": "ok", "details": {}}))\n' % T)
open(os.path.join(T, "calls.log"), "w").close()


def replay(*extra):
    open(os.path.join(T, "calls.log"), "w").close()
    p = subprocess.run([sys.executable, os.path.join(QA, "qa_replay.py"), gate, "demo", "--days", "3650", "--limit", "50", "--sample", "0", *extra], capture_output=True, text=True, env=env, cwd=T)
    return p, open(os.path.join(T, "calls.log")).read().splitlines()


p, calls = replay("--merges")
ok("--merges: exactly ONE gate call (the one merge)", len(calls) == 1, "%s | %s" % (calls, p.stdout + p.stderr))
ok("--merges: judged as <merge>^ .. <merge>", bool(calls) and ("--base %s^ --head %s" % (merge, merge)) in calls[0], str(calls))
ok("--merges: the summary counts 1 commit", "1 commits" in p.stdout, p.stdout)
p, calls = replay()
ok("default (no flag): every NON-merge commit with a parent is replayed (3 feature commits + 1 direct = 4; the root has no base), the merge is not", len(calls) == 4 and not any(merge in c for c in calls), "%d %s" % (len(calls), calls))
p, calls = replay("--merges", "--days", "3650")
ok("--merges composes with --days (value flags still parsed)", len(calls) == 1)
shutil.rmtree(T, ignore_errors=True)
print("\nqa replay merges n2: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
