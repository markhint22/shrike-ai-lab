#!/usr/bin/env python3
"""qa/qa_block_watch.py 2026-10-10 (package qagate, analysis[3] F5): a stall older than QA_BLOCK_EMERGENCY_H (or holding >= QA_BLOCK_EMERGENCY_COMMITS) is escalated
into the hourly-update notes (state/notify_notes.jsonl) on every run, and - behind QA_BLOCK_DEMOTE=on, default OFF - a block whose FAIL findings are ALL
test-file findings of an allow-listed rule is demoted FAIL->FLAG after QA_BLOCK_DEMOTE_H hours via state/qa_demoted.json, which gate_antigaming honours.
Fixture: bare origin + clone with develop and claude/feature; a stub gate_antigaming.py that reports the FAIL findings given in $QBW_FINDINGS."""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.environ.get("QAGATE_QA_DIR") or os.path.join(ROOT, "qa")
SCRIPT = os.path.join(QA, "qa_block_watch.py")
REAL_GATE = os.path.join(QA, "gate_antigaming.py")

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
STUB_GATE = '''#!/usr/bin/env python3
import json, os, sys
fs = json.loads(os.environ.get("QBW_FINDINGS", "[]"))
print(json.dumps({"verdict": "FAIL" if fs else "PASS", "mode": "enforce", "details": {"findings": [dict(f, sev="FAIL") for f in fs]}}))
'''
TEST_FIND = [{"rule": "E_ZERO_ASSERTS", "file": "tests/test_uid_hygiene.gd", "line": 17, "msg": "all assertions removed"}]


def make_fixture(held=13, since_ago_h=5, branch="claude/feature"):
    d = os.path.realpath(tempfile.mkdtemp(prefix="qbw10-"))
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
    sh(*GIT, "checkout", "-q", "-b", branch, cwd=clone)
    os.makedirs(os.path.join(clone, "tests"))
    open(os.path.join(clone, "tests", "test_uid_hygiene.gd"), "w").write("extends GutTest\n")
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "fleet work", cwd=clone)
    sh("git", "push", "-q", "origin", branch, cwd=clone)
    state = os.path.join(d, "state")
    os.makedirs(os.path.join(state, "qa_blocked"))
    gates = os.path.join(d, "gates")
    os.makedirs(gates)
    open(os.path.join(gates, "gate_antigaming.py"), "w").write(STUB_GATE)
    since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - since_ago_h * 3600))
    tip = sh("git", "rev-parse", "HEAD", cwd=clone).stdout.strip()
    json.dump({"repo": "demo", "branch": branch, "gate": "antigaming", "commit": tip, "held_commits": held, "since": since, "finding": "x", "subject": "s"},
              open(os.path.join(state, "qa_blocked", "demo__%s.json" % branch.replace("/", "_")), "w"))
    return d, clone, state, gates


def run(d, gates, findings, *flags, **env):
    e = dict(os.environ, OVN_DIR=d, QA_GATES_DIR=gates, QBW_FINDINGS=json.dumps(findings))
    for k in [k for k in e if k.startswith("QA_BLOCK_") or k.startswith("OVN_QA_")]:
        del e[k]
    e.update(env)
    return sh(sys.executable, SCRIPT, *flags, env=e)


def read(path):
    try:
        return open(path).read()
    except OSError:
        return ""


def notes(state):
    out = []
    for ln in read(os.path.join(state, "notify_notes.jsonl")).splitlines():
        try:
            out.append(json.loads(ln))
        except ValueError:
            pass
    return out


def alerts(state):
    return read(os.path.join(state, "alerts.log"))


def demoted(state):
    try:
        return json.load(open(os.path.join(state, "qa_demoted.json")))
    except (OSError, ValueError):
        return {}


# ============================================================================================ escalation into the hourly update
d, clone, state, gates = make_fixture(held=13, since_ago_h=19.7)
r = run(d, gates, TEST_FIND)
n = notes(state)
ok("ESCALATE: a 19.7 h stall writes ONE high-priority hourly-update note", len(n) == 1 and n[0]["prio"] == "high" and n[0]["source"] == "qa_block_watch", r.stdout + str(n))
ok("ESCALATE: the note names repo, branch, age, rule and file (so the update line is actionable)",
   n and all(x in (n[0]["title"] + n[0]["text"]) for x in ("demo", "claude/feature", "19h", "E_ZERO_ASSERTS", "test_uid_hygiene.gd")), str(n))
ok("ESCALATE: the note is fresh (ts ~ now) so the hourly update lists it", n and abs(n[0]["ts"] - time.time()) < 120)
ok("ESCALATE: the title survives ovn_notify's 'needs' filter (no recover/start/complete/fixed/ok word)",
   n and not __import__("re").search(r"recover|start|complete|fixed|\bok\b", n[0]["title"], __import__("re").I), n[0]["title"] if n else "")
run(d, gates, TEST_FIND)
ok("ESCALATE: every run while the stall lasts writes a fresh note (the update only lists notes newer than the last update)", len(notes(state)) == 2)
ok("the existing stall alert (alerts.log) is unchanged and still deduped to one line", alerts(state).count("qa-block-stall:demo") == 1, alerts(state))

d, clone, state, gates = make_fixture(held=13, since_ago_h=5)
run(d, gates, TEST_FIND)
ok("BENIGN: a 5 h stall (< QA_BLOCK_EMERGENCY_H=6) alerts in alerts.log but is NOT pushed into the hourly update", not notes(state) and "qa-block-stall:demo" in alerts(state))
run(d, gates, TEST_FIND, QA_BLOCK_EMERGENCY_H="4")
ok("QA_BLOCK_EMERGENCY_H is tunable (4 h -> escalates a 5 h stall)", len(notes(state)) == 1)

d, clone, state, gates = make_fixture(held=235, since_ago_h=1.5)
r = run(d, gates, TEST_FIND)
ok("iptv-style scenario: 235 held commits escalate even when the block is young (QA_BLOCK_EMERGENCY_COMMITS=100)", len(notes(state)) == 1, r.stdout + str(notes(state)))
d, clone, state, gates = make_fixture(held=30, since_ago_h=1.5)
run(d, gates, TEST_FIND)
ok("BENIGN: 30 held commits at 1.5 h: stall alert (>=20 commits) but no hourly-update escalation", not notes(state) and "qa-block-stall:demo" in alerts(state))

d, clone, state, gates = make_fixture(held=13, since_ago_h=19.7)
r = run(d, gates, TEST_FIND, "--dry-run")
ok("dry-run: prints what it would escalate, writes no note", "would escalate" in r.stdout and not notes(state) and not alerts(state), r.stdout)
d, clone, state, gates = make_fixture(held=13, since_ago_h=19.7)
r = run(d, gates, [])
ok("BENIGN: a block that no longer FAILs is 'resolved' and never escalated", "resolved" in r.stdout and not notes(state))

# ============================================================================================ demotion (default OFF)
d, clone, state, gates = make_fixture(held=13, since_ago_h=19.7)
run(d, gates, TEST_FIND)
ok("DEFAULT OFF: a 19.7 h test-only allow-listed block is NOT demoted without QA_BLOCK_DEMOTE=on", not demoted(state) and "DEMOTED" not in alerts(state))

d, clone, state, gates = make_fixture(held=13, since_ago_h=5)
r = run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on")
rec = demoted(state)
key = "demo__claude_feature"
ok("DEMOTE: a 5 h test-only block with an allow-listed rule is demoted (record written)", key in rec and rec[key]["rules"] == ["E_ZERO_ASSERTS"] and rec[key]["files"] == ["tests/test_uid_hygiene.gd"]
   and rec[key]["who"] == "qa_block_watch" and r.stdout.strip().endswith("demoted"), r.stdout + str(rec))
ok("DEMOTE: the record is bound to the offending commit recorded in the block", rec.get(key, {}).get("commit") == json.load(open(os.path.join(state, "qa_blocked", "demo__claude_feature.json")))["commit"])
hist = [json.loads(x) for x in read(os.path.join(state, "qa_gate_modes.history.jsonl")).splitlines() if x.strip()]
ok("DEMOTE: history row with who=qa_block_watch, FAIL -> FLAG", len(hist) == 1 and hist[0]["who"] == "qa_block_watch" and hist[0]["from"] == "FAIL" and hist[0]["to"] == "FLAG", str(hist))
ok("DEMOTE: exactly one alert line names the rule, file and branch", alerts(state).count("DEMOTED") == 1 and "E_ZERO_ASSERTS" in alerts(state) and "test_uid_hygiene.gd" in alerts(state)
   and "claude/feature" in alerts(state), alerts(state))
r = run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on")
ok("DEMOTE: idempotent - a second run adds no alert, no history row", alerts(state).count("DEMOTED") == 1 and len(read(os.path.join(state, "qa_gate_modes.history.jsonl")).splitlines()) == 1
   and "already" in r.stdout, r.stdout + alerts(state))

d, clone, state, gates = make_fixture(held=13, since_ago_h=2)
run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on")
ok("BENIGN: a 2 h block is not demoted yet (< QA_BLOCK_DEMOTE_H=4)", not demoted(state))
run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on", QA_BLOCK_DEMOTE_H="1")
ok("QA_BLOCK_DEMOTE_H is tunable (1 h -> demotes a 2 h block)", demoted(state))

d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
run(d, gates, [{"rule": "E_ZERO_ASSERTS", "file": "app/service.py", "line": 3, "msg": "x"}], QA_BLOCK_DEMOTE="on")
ok("NEGATIVE: a finding in PRODUCT code is never demoted", not demoted(state))
d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
run(d, gates, [{"rule": "A_MOCK_ONLY", "file": "tests/test_x.py", "line": 3, "msg": "x"}], QA_BLOCK_DEMOTE="on")
ok("NEGATIVE: a test-file finding of a rule outside the allow-list is never demoted", not demoted(state))
d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
run(d, gates, TEST_FIND + [{"rule": "D_FROZEN_EDIT", "file": "tests/test_y.gd", "line": 1, "msg": "x"}], QA_BLOCK_DEMOTE="on")
ok("NEGATIVE: a mixed block (one demotable + one not) demotes NOTHING", not demoted(state))
d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
run(d, gates, TEST_FIND + [{"rule": "E_ZERO_ASSERTS", "file": "scripts/battle.gd", "line": 1, "msg": "x"}], QA_BLOCK_DEMOTE="on")
ok("NEGATIVE: a second finding in a non-test file blocks the whole demotion", not demoted(state))
d, clone, state, gates = make_fixture(held=13, since_ago_h=8, branch="main")
run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on")
ok("NEGATIVE: a protected / non-feature branch (main) is never demoted", not demoted(state))
d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
rec_p = os.path.join(state, "qa_blocked", "demo__claude_feature.json")
rj = json.load(open(rec_p)); rj["gate"] = "migrations"
json.dump(rj, open(rec_p, "w"))
shutil.copy(os.path.join(gates, "gate_antigaming.py"), os.path.join(gates, "gate_migrations.py"))
run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on")
ok("NEGATIVE: a block by another gate is never demoted", not demoted(state))
d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
r = run(d, gates, TEST_FIND, "--dry-run", QA_BLOCK_DEMOTE="on")
ok("dry-run: says it would demote, writes nothing", "would demote" in r.stdout and not demoted(state) and not alerts(state), r.stdout)
d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on", QA_BLOCK_DEMOTE_RULES="A_VACUOUS")
ok("QA_BLOCK_DEMOTE_RULES overrides the allow-list (E_ZERO_ASSERTS no longer listed -> not demoted)", not demoted(state))
d, clone, state, gates = make_fixture(held=13, since_ago_h=8)
run(d, gates, TEST_FIND, QA_BLOCK_DEMOTE="on")
ok("a demoted block still escalates nothing further this run (demoted returns before escalation)", not notes(state))

# ============================================================================================ gate honours the record (REAL gate_antigaming)
GENV = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "QA_FETCH_WAIT": "0"}
EQ = "extends GutTest\n\nfunc test_add():\n\tassert_eq(add(1, 2), 3)\n"


def gate_repo():
    d = os.path.realpath(tempfile.mkdtemp(prefix="qbw10g-"))
    repo = os.path.join(d, "demo")
    os.makedirs(os.path.join(repo, "tests"))
    sh(*GIT, "init", "-q", cwd=repo)
    open(os.path.join(repo, "tests", "test_m.gd"), "w").write(EQ)
    sh("git", "add", "-A", cwd=repo)
    sh(*GIT, "commit", "-q", "-m", "a", cwd=repo)
    open(os.path.join(repo, "tests", "test_m.gd"), "w").write(EQ.replace("\tassert_eq(add(1, 2), 3)\n", "\tadd(1, 2)\n"))
    sh("git", "add", "-A", cwd=repo)
    sh(*GIT, "commit", "-q", "-m", "b", cwd=repo)
    sha = sh("git", "rev-parse", "HEAD", cwd=repo).stdout.strip()
    os.makedirs(os.path.join(d, "state"))
    return d, repo, sha


def gate(d, repo, **env):
    e = dict(GENV, OVN_DIR=d, QA_STATE_DIR=os.path.join(d, "state"))
    e.update(env)
    p = sh(sys.executable, REAL_GATE, "check", "--repo", repo, "--base", "HEAD~1", "--head", "HEAD", "--no-record", env=e)
    try:
        return json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        return {"verdict": "NOJSON", "summary": p.stdout + p.stderr, "details": {}}


def write_rec(d, **kw):
    rec = {"repo": "demo", "branch": "claude/feature", "gate": "antigaming", "rules": ["E_ZERO_ASSERTS"], "files": ["tests/test_m.gd"], "who": "qa_block_watch",
           "ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    rec.update(kw)
    json.dump({"demo__claude_feature": rec}, open(os.path.join(d, "state", "qa_demoted.json"), "w"))


d, repo, sha = gate_repo()
res = gate(d, repo)
ok("GATE control: with no record the all-assertions-removed test is FAIL E_ZERO_ASSERTS", res["verdict"] == "FAIL", res["summary"])
write_rec(d, commit=sha)
res = gate(d, repo)
fs = res["details"]["findings"]
ok("GATE: a matching demotion record turns that (rule, file) FAIL into FLAG (verdict FLAG), finding still reported and labelled",
   res["verdict"] == "FLAG" and fs and fs[0]["sev"] == "FLAG" and "demoted" in fs[0]["msg"], str(res["verdict"]) + str(fs))
write_rec(d, commit=sha, files=["tests/other.gd"])
ok("GATE NEGATIVE: a record for another file does not demote", gate(d, repo)["verdict"] == "FAIL")
write_rec(d, commit=sha, rules=["A_VACUOUS"])
ok("GATE NEGATIVE: a record for another rule does not demote", gate(d, repo)["verdict"] == "FAIL")
write_rec(d, commit=sha, repo="other")
ok("GATE NEGATIVE: a record for another repo does not demote", gate(d, repo)["verdict"] == "FAIL")
write_rec(d, commit="0" * 40)
ok("GATE NEGATIVE: a record whose commit is not in the head's history does not demote", gate(d, repo)["verdict"] == "FAIL")
write_rec(d, commit=sha, ts=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 10 * 86400)))
ok("GATE NEGATIVE: an expired record (> QA_DEMOTE_TTL_H) does not demote", gate(d, repo)["verdict"] == "FAIL")
write_rec(d, commit=sha)
ok("GATE kill switch OVN_QA_DEMOTE=off ignores the record", gate(d, repo, OVN_QA_DEMOTE="off")["verdict"] == "FAIL")
open(os.path.join(d, "state", "qa_demoted.json"), "w").write("{not json")
ok("GATE: a corrupt record file never crashes or demotes (still FAIL)", gate(d, repo)["verdict"] == "FAIL")

print("\nqa_block_watch r10 tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
