#!/usr/bin/env python3
"""Tests for qa/qa_label.py (analysis F9, 2026-10-10): (gate, rule, id) labels for any gate, the refuse-under-50-decisive-labels rule per (gate, rule), the
Wilson bound, suggestions that are never counted, legacy reviewer labels, and `harvest` (a seeded commit sample replayed through qa_replay.replay_commit in a
scratch state dir, GPU-idle guard for model gates, hard budget, no duplicates, nothing written to the live shadow state).

Runs the REAL CLI under `env -i` against a temp OVN_DIR. The harvest tests use the real gate_gdparse.py with a FAKE python (content-marker protocol, like
test_qa_gate_gdparse.py) so no model, no GPU and no gdtoolkit install is needed."""
import json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.path.join(ROOT, "qa")
SCRIPT = os.path.join(QA, "qa_label.py")
sys.path.insert(0, QA)
import qa_label as ql  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:500]) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-label-test-"))
OVN = os.path.join(T, "ovn")
STATE = os.path.join(OVN, "state")
SHADOW = os.path.join(STATE, "qa_shadow")
REPOS = os.path.join(OVN, "repos")
os.makedirs(SHADOW)
os.makedirs(REPOS)
TMP = os.path.join(T, "tmp")
os.makedirs(TMP)


def cli(args, env=None, rc_only=False):
    e = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": T, "OVN_DIR": OVN, "OVN_REPOS_DIR": REPOS, "TMPDIR": TMP, "LANG": "C"}
    e.update(env or {})
    p = subprocess.run(["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [sys.executable, SCRIPT] + args, cwd=T, capture_output=True, text=True, timeout=300)
    return p.returncode, p.stdout, p.stderr


def jrep(*extra):
    rc, out, err = cli(["report", "--json"] + list(extra))
    return json.loads(out.strip().splitlines()[-1])


def rows(path):
    try:
        return [json.loads(l) for l in open(path) if l.strip()]
    except OSError:
        return []


def add_shadow(gate, row):
    with open(os.path.join(SHADOW, gate + ".jsonl"), "a") as f:
        f.write(json.dumps(dict(row, gate=gate), sort_keys=True) + "\n")


def ag_row(ref, ts, findings, repo="xlite"):
    return {"repo": repo, "ref": ref, "ts": ts, "verdict": "FLAG", "details": {"findings": findings}}


def ag_f(rule, file, line, msg):
    return {"rule": rule, "file": file, "line": line, "msg": msg, "sev": "FLAG"}


print("== empty state")
rc, out, err = cli(["report"])
ok("report on empty state works (exit 0)", rc == 0 and "findings known: 0" in out, out + err)
ok("usage errors exit 2: no command / unknown command / bad option", cli([])[0] == 2 and cli(["bogus"])[0] == 2 and cli(["list", "--nope"])[0] == 2)

print("== findings from several gates, stable ids")
add_shadow("antigaming", ag_row("a..b", "2026-10-09T10:00:00Z", [ag_f("D_DEAD_SYMBOL", "scripts/x.gd", 10, "symbol foo_bar (3 refs) is never used"),
                                                                  ag_f("E_TEST_NOT_COLLECTED", "tests/t.gd", 3, "test file t.gd is not collected")]))
add_shadow("antigaming", ag_row("c..d", "2026-10-09T12:00:00Z", [ag_f("D_DEAD_SYMBOL", "scripts/x.gd", 55, "symbol foo_bar (9 refs) is never used")]))   # same finding, line + digits shifted
add_shadow("reviewer", {"repo": "billwatch", "ref": "e..f", "ts": "2026-10-09T11:00:41Z", "verdict": "FLAG",
                        "details": {"findings": [{"id": "a712928067f3", "file": "scripts/tech.gd", "line": 277, "claim": "material_cost always returns 0", "severity": "medium"}]}})
add_shadow("scanners", {"repo": "iptv_apps", "ref": "g..h", "ts": "2026-10-09T13:00:00Z", "verdict": "FLAG",
                        "details": {"new": [{"tool": "ruff", "rule": "F821", "at": "app/x.py:12", "sev": "high", "msg": "undefined name y"}]}})
add_shadow("gdparse", {"repo": "xlite", "ref": "i..j", "ts": "2026-10-09T14:00:00Z", "verdict": "FLAG",
                       "details": {"parse_errors": [{"file": "tests/test_new.gd", "err": "line 4 col 1: Unexpected token", "preexisting": False}]}})
add_shadow("migrations", {"repo": "billwatch", "ref": "k..l", "ts": "2026-10-09T15:00:00Z", "verdict": "PASS", "details": {"cells": {}}})
os.environ["OVN_DIR"] = OVN
fs = ql.all_findings()
by = {(f["gate"], f["rule"]): f for f in fs}
ok("5 distinct findings: dead-symbol (deduped across two ranges), not-collected, reviewer, scanner, gdparse", len(fs) == 5, [(f["gate"], f["rule"]) for f in fs])
ok("antigaming ids derived from (gate,repo,rule,file,message) - a shifted line/ref/digits does not create a second job",
   len([f for f in fs if f["rule"] == "D_DEAD_SYMBOL"]) == 1)
ok("reviewer keeps the gate's own id; rule is '-'", ("reviewer", "-") in by and by[("reviewer", "-")]["id"] == "a712928067f3")
ok("scanner rule is tool:rule and 'at' is split into file/line", by[("scanners", "ruff:F821")]["file"] == "app/x.py" and by[("scanners", "ruff:F821")]["line"] == 12)
ok("gdparse parse_errors get rule parse_error", ("gdparse", "parse_error") in by)
ok("a PASS row with no findings contributes nothing", not [f for f in fs if f["gate"] == "migrations"])
rc, out, _ = cli(["list", "--gate", "antigaming"])
ok("list --gate filters", rc == 0 and out.count("\n") == 2 and "D_DEAD_SYMBOL" in out and "scanners" not in out, out)

print("== label validation")
dead = by[("antigaming", "D_DEAD_SYMBOL")]["id"]
ok("unknown id => exit 2, nothing stored", cli(["label", "--gate", "antigaming", "--id", "deadbeef0000", "--label", "TP"])[0] == 2 and not rows(os.path.join(STATE, "qa_labels.jsonl")))
ok("bad label => exit 2", cli(["label", "--gate", "antigaming", "--id", dead, "--label", "maybe"])[0] == 2)
ok("wrong rule for a known id => exit 2", cli(["label", "--gate", "antigaming", "--id", dead, "--rule", "A_TEST_DELETED", "--label", "TP"])[0] == 2)
ok("wrong gate for a known id => exit 2", cli(["label", "--gate", "scanners", "--id", dead, "--label", "TP"])[0] == 2)
rc, out, _ = cli(["label", "--gate", "antigaming", "--id", dead, "--label", "FP", "--note", "symbol used via call_deferred"])
lr = rows(os.path.join(STATE, "qa_labels.jsonl"))
ok("a valid label is appended with gate/rule/id/note", rc == 0 and len(lr) == 1 and lr[0]["gate"] == "antigaming" and lr[0]["rule"] == "D_DEAD_SYMBOL" and lr[0]["label"] == "FP" and lr[0]["note"], lr)
cli(["label", "--gate", "antigaming", "--id", dead, "--label", "TP"])
r = jrep("--gate", "antigaming", "--rule", "D_DEAD_SYMBOL")
g = r["by_rule"][0]
ok("the LATEST label per (gate, rule, id) wins (FP then TP => tp 1, fp 0)", g["tp"] == 1 and g["fp"] == 0 and g["labelled"] == 1, g)

print("== refuse-under-50 rule, per (gate, rule)")
# 49 decisive labels (rule A), 5 unclear on top
for i in range(54):
    add_shadow("antigaming", ag_row("r%d" % i, "2026-10-09T16:%02d:00Z" % (i % 60), [ag_f("F_CLAIM_TEST_ONLY", "scripts/f%d.gd" % i, 1, "claim only touches tests")]))
fs = ql.all_findings()
fct = [f for f in fs if f["rule"] == "F_CLAIM_TEST_ONLY"]
ok("54 distinct F_CLAIM_TEST_ONLY findings known", len(fct) == 54, len(fct))
for i, f in enumerate(fct):
    lab = "unclear" if i >= 49 else ("TP" if i < 29 else "FP")
    assert cli(["label", "--gate", "antigaming", "--id", f["id"], "--rule", "F_CLAIM_TEST_ONLY", "--label", lab])[0] == 0
r = jrep("--gate", "antigaming", "--rule", "F_CLAIM_TEST_ONLY")["by_rule"][0]
ok("49 decisive + 5 unclear: NO precision, NO interval, bar_met None (unclear never counts toward 50)", r["decisive"] == 49 and r["unclear"] == 5 and r["precision"] is None
   and r["ci95"] is None and r["bar_met"] is None, r)
rc, out, _ = cli(["report", "--gate", "antigaming", "--rule", "F_CLAIM_TEST_ONLY"])
ok("text report says INSUFFICIENT SAMPLE and prints no percentage for it", "INSUFFICIENT SAMPLE" in out and "precision %" not in out.split("F_CLAIM_TEST_ONLY")[-1].split("\n")[0], out)
nxt = [f for f in fct][49]
cli(["label", "--gate", "antigaming", "--id", nxt["id"], "--rule", "F_CLAIM_TEST_ONLY", "--label", "FP"])     # relabel an unclear one: now 50 decisive, 29 TP / 21 FP
r = jrep("--gate", "antigaming", "--rule", "F_CLAIM_TEST_ONLY")["by_rule"][0]
ok("the 50th decisive label unlocks the percentage: 29/50 = 58% -> bar NOT met (needs 60%)", r["decisive"] == 50 and r["precision"] == 0.58 and r["bar_met"] is False and r["ci95"] and r["wilson_lower"] < 0.58, r)
cli(["label", "--gate", "antigaming", "--id", fct[29]["id"], "--rule", "F_CLAIM_TEST_ONLY", "--label", "TP"])    # FP -> TP: 30/50 = 60%
r = jrep("--gate", "antigaming", "--rule", "F_CLAIM_TEST_ONLY")["by_rule"][0]
ok("30/50 = 60% -> bar met, and the Wilson lower bound is reported separately (below the point estimate)", r["precision"] == 0.6 and r["bar_met"] is True and 0.4 < r["wilson_lower"] < 0.6, r)
ok("another rule of the same gate is NOT unlocked by that rule's 50 labels", [x for x in jrep("--gate", "antigaming")["by_rule"] if x["rule"] == "E_TEST_NOT_COLLECTED"][0]["precision"] is None)
ga = [x for x in jrep()["by_gate"] if x["gate"] == "antigaming"][0]
ok("the per-gate line of a MULTI-rule gate is counts only: no pooled precision, interval or bar verdict (the bar is per rule), even with >= 50 pooled decisive labels",
   ga["rules"] > 1 and ga["decisive"] >= 50 and ga["precision"] is None and ga["ci95"] is None and ga["wilson_lower"] is None and ga["bar_met"] is None and ga.get("pooled") is True, ga)
rc, out, _ = cli(["report", "--gate", "antigaming"])
gl = [l for l in out.split("\n") if l.startswith("[antigaming]")]
gline = out.split("[antigaming]")[1].split("\n    ")[0]
ok("text report: the gate header carries neither a percentage nor 'bar MET' for the pool", gl and "bar MET" not in gline and "bar NOT MET" not in gline and "precision %" not in gline and "per rule" in gline, gline)
ok("... while the (gate, rule) row that has 50 decisive labels still shows its percentage and bar", "F_CLAIM_TEST_ONLY" in out and "bar MET" in out.split("F_CLAIM_TEST_ONLY")[1].split("\n")[0], out)
ok("pure stats(): 49 -> refused, 50 -> computed, 0 -> refused", ql.stats(30, 19)["precision"] is None and ql.stats(30, 20)["precision"] == 0.6 and ql.stats(0, 0)["precision"] is None)

print("== legacy reviewer labels are honoured, suggestions are never counted")
with open(os.path.join(STATE, "qa_reviewer_labels.jsonl"), "w") as f:
    f.write(json.dumps({"ts": "2026-10-09T17:00:00Z", "id": "a712928067f3", "label": "FP", "note": "returns t.material_cost now", "repo": "billwatch", "file": "scripts/tech.gd"}) + "\n")
r = [x for x in jrep("--gate", "reviewer")["by_rule"]][0]
ok("legacy qa_reviewer_labels.jsonl row counts as gate=reviewer rule='-'", r["rule"] == "-" and r["fp"] == 1 and r["labelled"] == 1, r)
scan = by[("scanners", "ruff:F821")]["id"]
rc, out, _ = cli(["suggest", "--gate", "scanners", "--id", scan, "--label", "TP", "--evidence", "y is never defined in app/x.py at head"])
r = [x for x in jrep("--gate", "scanners")["by_rule"]][0]
ok("a pre-read suggestion is stored apart and NOT counted (labelled 0, tp 0), listed as pre-read 1", rc == 0 and r["labelled"] == 0 and r["tp"] == 0 and r["suggested"] == 1, r)
ok("suggest needs --evidence", cli(["suggest", "--gate", "scanners", "--id", scan, "--label", "TP"])[0] == 2)
cli(["label", "--gate", "scanners", "--id", scan, "--label", "FP", "--note", "human disagrees"])
lr = [x for x in rows(os.path.join(STATE, "qa_labels.jsonl")) if x["gate"] == "scanners"][0]
rep = jrep("--gate", "scanners")
ok("the human label records the pre-read it saw, and agreement is tracked (0 of 1 agree)", lr.get("suggested") == "TP" and rep["suggestion_agreement"] == {"n": 1, "agree": 0}, (lr, rep["suggestion_agreement"]))

print("== suggested TP from the ledger (never counted)")
pe = by[("gdparse", "parse_error")]
import calendar, time as _t
ep = calendar.timegm(_t.strptime(pe["ts"], "%Y-%m-%dT%H:%M:%SZ"))
with open(os.path.join(STATE, "qa_ledger.jsonl"), "w") as f:
    f.write(json.dumps({"kind": "event", "type": "hotfix", "repo": "xlite", "files": ["tests/test_new.gd"], "epoch": ep + 86400, "ref": "abc123def456"}) + "\n")
rep = jrep("--gate", "gdparse")
ok("a hotfix touching the same file within 7 days AFTER the finding is SUGGESTED, not labelled", len(rep["suggested_tp"]) == 1 and rep["labelled"] == 0, rep["suggested_tp"])

print("== harvest")
FAKEPY = os.path.join(T, "fakepy")
with open(FAKEPY, "w") as f:
    f.write('''#!/usr/bin/env python3
import json, os, sys
a = sys.argv[1:]
if a[:1] == ["-I"]: a = a[1:]
if a[:1] == ["-c"]: sys.exit(0)
helper, mode, root = a[0], a[1], a[2]
files = json.loads(sys.stdin.read() or "[]")
res = {}
for rel in files:
    code = open(os.path.join(root, rel), "rb").read().decode("utf-8", "replace")
    r = {"ok": True, "kind": "ok", "err": "", "problems": []}
    if "SYNTAX_ERROR" in code:
        r.update(ok=False, kind="parse_error", err="line 1 col 1: Unexpected token")
    res[rel] = r
print(json.dumps({"version": "fake", "results": res}))
''')
os.chmod(FAKEPY, 0o755)


def g(*a):
    return subprocess.run(["git", "-C", R] + list(a), capture_output=True, text=True, timeout=60).stdout.strip()


R = os.path.join(REPOS, "hrepo")
os.makedirs(R)
g("init", "-q")
g("config", "user.email", "t@t")
g("config", "user.name", "t")
open(os.path.join(R, "README.md"), "w").write("x\n")
g("add", "-A")
g("commit", "-q", "-m", "init")
for i in range(12):
    nm = "scripts/s%d.gd" % i
    os.makedirs(os.path.dirname(os.path.join(R, nm)), exist_ok=True)
    open(os.path.join(R, nm), "w").write(("SYNTAX_ERROR %d\n" if i % 3 == 0 else "extends Node # %d\n") % i)
    g("add", "-A")
    g("commit", "-q", "-m", "c%d" % i)
g("update-ref", "refs/remotes/origin/develop", "HEAD")
HENV = {"QA_GDTOOLKIT_PYTHON": FAKEPY, "QA_FETCH_WAIT": "0"}
rc, out, err = cli(["harvest", "--gate", "gdparse", "--repo", "hrepo", "--sample", "5", "--seed", "3", "--dry-run"], HENV)
d1 = json.loads(out)
rc, out, err = cli(["harvest", "--gate", "gdparse", "--repo", "hrepo", "--sample", "5", "--seed", "3", "--dry-run"], HENV)
d2 = json.loads(out)
ok("dry-run lists a seeded sample of 5 of 13 window commits and runs no gate", d1["sampled"] == 5 and d1["window_commits"] == 13 and d1["dry_run"] and d1["first_commits"] == d2["first_commits"], d1)
ok("dry-run wrote nothing (no candidates file)", not os.path.exists(os.path.join(STATE, "qa_label_candidates.jsonl")))
ok("sample_commits is deterministic per seed, ordered like the log, distinct", ql.sample_commits(list("abcdefghij"), 4, 1) == ql.sample_commits(list("abcdefghij"), 4, 1)
   and len(set(ql.sample_commits(list("abcdefghij"), 4, 1))) == 4 and ql.sample_commits(list("abc"), 10, 1) == list("abc"))
live_before = set(os.listdir(SHADOW))
rc, out, err = cli(["harvest", "--gate", "gdparse", "--repo", "hrepo", "--sample", "100", "--seed", "1"], HENV)
d = json.loads(out)
cands = rows(os.path.join(STATE, "qa_label_candidates.jsonl"))
ok("harvest replays every sampled non-merge commit (the root commit has no parent and is skipped)", rc == 0 and d["ranges_run"] == 12 and d["sampled"] == 13, d)
ok("findings from the replay: the 4 broken files (s0,s3,s6,s9) are 4 candidates, rule parse_error", d["new_candidates"] == 4 and len(cands) == 4 and all(c["rule"] == "parse_error" and c["gate"] == "gdparse" for c in cands), (d, cands))
ok("ranges_with_findings counts the 4 replayed ranges that introduced broken files", d["ranges_with_findings"] == 4, d)
ok("the replay ran in a scratch state dir: the live qa_shadow dir got NO new row and the scratch dir is gone", set(os.listdir(SHADOW)) == live_before
   and not [x for x in os.listdir(TMP) if x.startswith("qa-label-harvest-")], (os.listdir(SHADOW), os.listdir(TMP)))
rc, out, err = cli(["harvest", "--gate", "gdparse", "--repo", "hrepo", "--sample", "100", "--seed", "1"], HENV)
ok("a second harvest adds no duplicates (ids are stable)", json.loads(out)["new_candidates"] == 0 and len(rows(os.path.join(STATE, "qa_label_candidates.jsonl"))) == 4, out)
rc, out, _ = cli(["list", "--candidates-only", "--gate", "gdparse"])
ok("candidates show up in list (harvest-sourced)", out.count("parse_error") == 4, out)
cid = cands[0]["id"]
ok("a harvested candidate can be labelled and counts", cli(["label", "--gate", "gdparse", "--id", cid, "--label", "TP"])[0] == 0
   and [x for x in jrep("--gate", "gdparse")["by_rule"] if x["rule"] == "parse_error"][0]["tp"] == 1)
os.remove(os.path.join(STATE, "qa_label_candidates.jsonl"))
rc, out, _ = cli(["harvest", "--gate", "gdparse", "--repo", "hrepo", "--sample", "100", "--no-record"], HENV)
ok("--no-record reports candidates but writes none", json.loads(out)["new_candidates"] == 4 and not os.path.exists(os.path.join(STATE, "qa_label_candidates.jsonl")), out)
rc, out, _ = cli(["harvest", "--gate", "gdparse", "--repo", "hrepo", "--sample", "100", "--budget-s", "0", "--no-record"], HENV)
dd = json.loads(out)
ok("budget exhausted => stops before running anything and says so", dd["ranges_run"] == 0 and "budget" in dd.get("stopped", ""), dd)
ok("unknown repo => exit 3", cli(["harvest", "--gate", "gdparse", "--repo", "nope"], HENV)[0] == 3)
ok("unknown gate => exit 2", cli(["harvest", "--gate", "nogate", "--repo", "hrepo"], HENV)[0] == 2)
ok("missing --gate/--repo => exit 2", cli(["harvest", "--gate", "gdparse"], HENV)[0] == 2)
ok("bad gate name (path trick) => exit 2", cli(["harvest", "--gate", "../x", "--repo", "hrepo"], HENV)[0] == 2)

print("== harvest runs the gate in a SCRATCH state dir (a gate that writes state must not touch the live one)")
GD = os.path.join(T, "fakegates")
os.makedirs(GD)
with open(os.path.join(GD, "gate_probe.py"), "w") as f:
    f.write('''import json, os, sys
open(os.environ["PROBE_OUT"], "a").write(json.dumps({"ovn": os.environ.get("OVN_DIR"), "state": os.environ.get("QA_STATE_DIR"), "repos": os.environ.get("OVN_REPOS_DIR")}) + "\\n")
os.makedirs(os.path.join(os.environ["QA_STATE_DIR"], "qa_shadow"), exist_ok=True)
open(os.path.join(os.environ["QA_STATE_DIR"], "qa_shadow", "probe_wrote.txt"), "w").write("x")
print(json.dumps({"verdict": "FLAG", "summary": "probe", "details": {"findings": [{"rule": "P_RULE", "file": "a.gd", "line": 1, "msg": "probe finding"}]}}))
''')
PO = os.path.join(T, "probe_out.jsonl")
rc, out, err = cli(["harvest", "--gate", "probe", "--repo", "hrepo", "--sample", "2", "--no-record"], {"QA_LABEL_GATE_DIR": GD, "PROBE_OUT": PO})
seen = [json.loads(l) for l in open(PO)] if os.path.exists(PO) else []
ok("the gate subprocess got a scratch OVN_DIR/QA_STATE_DIR (not the live ones) and the real repos dir", rc == 0 and len(seen) == 2 and all(
    x["ovn"] != OVN and x["state"] != STATE and "qa-label-harvest-" in x["ovn"] and x["state"].startswith(x["ovn"]) and os.path.realpath(x["repos"]) == os.path.realpath(REPOS) for x in seen), (rc, err, seen))
ok("what the gate wrote went to the scratch dir, which is gone; the live state has no probe file", not os.path.exists(os.path.join(SHADOW, "probe_wrote.txt"))
   and not [x for x in os.listdir(TMP) if x.startswith("qa-label-harvest-")], os.listdir(TMP))

print("== harvest of a model gate (reviewer) needs an idle GPU")
rc, out, err = cli(["harvest", "--gate", "reviewer", "--repo", "hrepo", "--dry-run"], {"OVN_NVIDIA_SMI": os.path.join(T, "no-smi")})
ok("nvidia-smi unusable counts as BUSY: refused, exit 3", rc == 3 and "refused" in err, (rc, err))
for name, val, want in (("idle", "5", 0), ("busy", "90", 3)):
    smi = os.path.join(T, "smi_" + name)
    with open(smi, "w") as f:
        f.write("#!/bin/sh\necho %s\n" % val)
    os.chmod(smi, 0o755)
    rc, out, err = cli(["harvest", "--gate", "reviewer", "--repo", "hrepo", "--dry-run"], {"OVN_NVIDIA_SMI": smi})
    ok("GPU at %s%% => exit %d" % (val, want), rc == want, (rc, err))
rc, out, err = cli(["harvest", "--gate", "reviewer", "--repo", "hrepo", "--dry-run", "--ignore-gpu"], {"OVN_NVIDIA_SMI": os.path.join(T, "no-smi")})
ok("--ignore-gpu overrides the guard", rc == 0, (rc, err))
rc, out, err = cli(["harvest", "--gate", "gdparse", "--repo", "hrepo", "--dry-run"], {"OVN_NVIDIA_SMI": os.path.join(T, "no-smi")})
ok("a deterministic gate needs no GPU check", rc == 0, (rc, err))

print("== the old qa_reviewer_label.py is untouched and still works on the same state")
p = subprocess.run(["env", "-i", "PATH=" + os.environ.get("PATH", ""), "OVN_DIR=" + OVN, sys.executable, os.path.join(QA, "qa_reviewer_label.py"), "report"],
                   capture_output=True, text=True, timeout=60)
ok("qa_reviewer_label.py report still exits 0", p.returncode == 0, p.stderr)

print("== qa_replay.replay_commit always passes --no-record (a replay must never write rows into the live shadow ledger)")
import qa_replay as qrp  # noqa: E402
_argv = os.path.join(T, "gate_argv.txt")
_gate = os.path.join(T, "gate_fake.py")
with open(_gate, "w") as f:
    f.write("import json, sys\nopen(%r, 'w').write('\\n'.join(sys.argv[1:]))\nprint(json.dumps({'verdict': 'PASS', 'summary': 'x', 'details': {}}))\n" % _argv)
_res = qrp.replay_commit(_gate, "somerepo", "abc123", extra=["--timeout", "9"], timeout=60, env={"PATH": os.environ.get("PATH", ""), "HOME": T})
_args = open(_argv).read().split("\n") if os.path.exists(_argv) else []
ok("replay_commit runs the gate with --no-record", "--no-record" in _args, _args)
ok("... and the rest of the argv is check --repo R --base sha^ --head sha + extras", _args[:7] == ["check", "--repo", "somerepo", "--base", "abc123^", "--head", "abc123"] and _args[-2:] == ["--timeout", "9"], _args)
ok("... returning the gate's JSON with the commit attached", _res.get("verdict") == "PASS" and _res.get("commit") == "abc123", _res)

shutil.rmtree(T, ignore_errors=True)
print("\nqa_label: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
