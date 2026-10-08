#!/usr/bin/env python3
"""qa/qa_block_watch.py: an enforcing QA block either self-heals (net-new placeholder tests only) or alerts loudly - never touches anything else.
Fixture: bare origin + clone with develop and overnight/feature; a stub gate_antigaming.py that FAILs while the placeholder file exists."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SCRIPT = os.path.join(ROOT, "qa", "qa_block_watch.py")
sys.path.insert(0, os.path.join(ROOT, "qa"))
import qa_block_watch as W  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def sh(*a, cwd=None, env=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, env=env)


GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]

# --- is_placeholder_test unit cases
ok("placeholder: assert True only", W.is_placeholder_test("def test_placeholder():\n    '''x'''\n    assert True\n"))
ok("placeholder: pass body + docstring + import", W.is_placeholder_test('"""m"""\nimport os\ndef test_a():\n    pass\n'))
ok("NEGATIVE: a real assertion is not a placeholder", not W.is_placeholder_test("def test_a():\n    assert 1 + 1 == 2\n"))
ok("NEGATIVE: a call in the body is not a placeholder", not W.is_placeholder_test("def test_a():\n    do()\n    assert True\n"))
ok("NEGATIVE: module-level code is not a placeholder", not W.is_placeholder_test("x = compute()\ndef test_a():\n    assert True\n"))
ok("NEGATIVE: no test function at all is not a placeholder", not W.is_placeholder_test("import os\n"))
ok("NEGATIVE: a helper function next to the test is not a placeholder", not W.is_placeholder_test("def helper():\n    return 1\ndef test_a():\n    assert True\n"))
ok("NEGATIVE: syntax error is not a placeholder", not W.is_placeholder_test("def test_a(:\n"))

STUB_GATE = '''#!/usr/bin/env python3
import json, os, subprocess, sys
repo = sys.argv[sys.argv.index("--repo") + 1]
head = sys.argv[sys.argv.index("--head") + 1]
base = sys.argv[sys.argv.index("--base") + 1]
files = subprocess.run(["git", "-C", repo, "diff", "--name-only", "--diff-filter=A", base, head], capture_output=True, text=True).stdout.split()
findings = []
for f in files:
    if f.endswith("placeholder_test.py"):
        findings.append({"rule": "A_VACUOUS", "sev": "FAIL", "file": f, "line": 3, "msg": "vacuous"})
    if f.endswith("realbad_test.py"):
        findings.append({"rule": "A_MOCK_ONLY", "sev": "FAIL", "file": f, "line": 1, "msg": "mock only"})
print(json.dumps({"verdict": "FAIL" if any(x["sev"] == "FAIL" for x in findings) else "PASS", "mode": "enforce", "details": {"findings": findings}}))
'''


def make_fixture(extra_files, held=235, since_ago_h=17):
    d = tempfile.mkdtemp(prefix="qbw-")
    origin = os.path.join(d, "origin.git")
    sh("git", "init", "-q", "--bare", origin)
    clone = os.path.join(d, "repos", "demo")
    os.makedirs(os.path.dirname(clone))
    sh("git", "clone", "-q", origin, clone)
    sh(*GIT, "checkout", "-q", "-b", "develop", cwd=clone)
    open(os.path.join(clone, "app.py"), "w").write("x = 1\n")
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "base", cwd=clone)
    sh("git", "push", "-q", "origin", "develop", cwd=clone)
    sh(*GIT, "checkout", "-q", "-b", "overnight/feature", cwd=clone)
    for rp, body in extra_files.items():
        os.makedirs(os.path.dirname(os.path.join(clone, rp)) or clone, exist_ok=True)
        open(os.path.join(clone, rp), "w").write(body)
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "fleet work", cwd=clone)
    sh("git", "push", "-q", "origin", "overnight/feature", cwd=clone)
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "qa_blocked"))
    gates = os.path.join(d, "gates")
    os.makedirs(gates)
    open(os.path.join(gates, "gate_antigaming.py"), "w").write(STUB_GATE)
    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - since_ago_h * 3600))
    json.dump({"repo": "demo", "branch": "overnight/feature", "gate": "antigaming", "commit": "abc", "held_commits": held, "since": since,
               "finding": "x", "subject": "s"}, open(os.path.join(state, "qa_blocked", "demo__overnight_feature.json"), "w"))
    return d, clone, state, gates


def run(d, gates, *flags, extra_env=None):
    env = dict(os.environ, OVN_DIR=d, QA_GATES_DIR=gates, OVN_STATE_DIR=os.path.join(d, "state"))
    env.update(extra_env or {})
    return sh(sys.executable, SCRIPT, *flags, env=env)


def alerts(state):
    try:
        return open(os.path.join(state, "alerts.log")).read()
    except OSError:
        return ""


def origin_has(d, path):
    r = sh("git", "--git-dir", os.path.join(d, "origin.git"), "cat-file", "-e", "overnight/feature:" + path)
    return r.returncode == 0


PH = "def test_placeholder():\n    assert True\n"

# --- 1. the real incident: only a net-new placeholder test blocks -> deleted, alert says so
d, clone, state, gates = make_fixture({"app/jobs/placeholder_test.py": PH, "app/real.py": "y = 2\n"})
ok("fixture sanity: the placeholder is on origin before the run", origin_has(d, "app/jobs/placeholder_test.py"))
r = run(d, gates)
ok("self-heal: placeholder deleted on the feature branch, other files untouched",
   not origin_has(d, "app/jobs/placeholder_test.py") and origin_has(d, "app/real.py"), r.stdout + r.stderr)
ok("self-heal: output and alert name what happened", "self-healed" in r.stdout and "self-healed" in alerts(state) and "placeholder" in alerts(state), r.stdout + alerts(state))
ok("self-heal: a second run is a no-op (resolved)", "resolved" in run(d, gates).stdout)
ok("self-heal: no worktree left behind", len(sh("git", "worktree", "list", cwd=clone).stdout.strip().split("\n")) == 1)

# --- 2. dry-run changes nothing
d, clone, state, gates = make_fixture({"app/jobs/placeholder_test.py": PH})
r = run(d, gates, "--dry-run")
ok("dry-run: reports the heal it WOULD do, deletes nothing, raises no alert",
   origin_has(d, "app/jobs/placeholder_test.py") and "self-healed dry-run" in r.stdout and "self-healed" not in alerts(state), r.stdout + alerts(state))

# --- 3. a REAL finding blocks the heal: nothing deleted, stall alert (old block), then deduped
d, clone, state, gates = make_fixture({"app/jobs/placeholder_test.py": PH, "tests/realbad_test.py": "def test_x():\n    assert foo() == 1\n"}, held=235, since_ago_h=17)
r = run(d, gates)
ok("NEGATIVE: a non-placeholder FAIL means NOTHING is deleted (not even the placeholder)",
   origin_has(d, "app/jobs/placeholder_test.py") and origin_has(d, "tests/realbad_test.py"), r.stdout)
ok("stall alert: names repo, hours held, commits held and the finding", "qa-block-stall:demo" in alerts(state) and "235 commit" in alerts(state) and "17." in alerts(state) and ("A_VACUOUS" in alerts(state) or "A_MOCK_ONLY" in alerts(state)), alerts(state))
n1 = alerts(state).count("qa-block-stall")
run(d, gates)
ok("stall alert is deduped within the re-alert window", alerts(state).count("qa-block-stall") == n1 == 1, alerts(state))

# --- 4. young + small block: quiet
d, clone, state, gates = make_fixture({"tests/realbad_test.py": "def test_x():\n    assert foo() == 1\n"}, held=3, since_ago_h=0.2)
r = run(d, gates)
ok("a young small block is left quiet (hygiene may still resolve it)", "blocked (young)" in r.stdout and not alerts(state), r.stdout + alerts(state))

# --- 5. protected branches: never self-heal main/develop
d, clone, state, gates = make_fixture({"app/jobs/placeholder_test.py": PH})
rec_p = os.path.join(state, "qa_blocked", "demo__overnight_feature.json")
rec = json.load(open(rec_p)); rec["branch"] = "main"
json.dump(rec, open(os.path.join(state, "qa_blocked", "demo__main.json"), "w")); os.unlink(rec_p)
r = run(d, gates)
ok("NEGATIVE: a record for a non-feature branch is never self-healed", origin_has(d, "app/jobs/placeholder_test.py") and "self-healed" not in r.stdout and "self-healed" not in alerts(state), r.stdout)

# --- 6. other gate: never self-heal
d, clone, state, gates = make_fixture({"app/jobs/placeholder_test.py": PH})
rec_p = os.path.join(state, "qa_blocked", "demo__overnight_feature.json")
rec = json.load(open(rec_p)); rec["gate"] = "migrations"
json.dump(rec, open(rec_p, "w"))
shutil.copy(os.path.join(gates, "gate_antigaming.py"), os.path.join(gates, "gate_migrations.py"))
r = run(d, gates)
ok("NEGATIVE: a block by a different gate is never self-healed", origin_has(d, "app/jobs/placeholder_test.py"), r.stdout)

# --- 7. no blocks at all
d, clone, state, gates = make_fixture({"a.py": "z = 1\n"})
os.unlink(os.path.join(state, "qa_blocked", "demo__overnight_feature.json"))
ok("no records -> 'no QA blocks'", "no QA blocks" in run(d, gates).stdout)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
