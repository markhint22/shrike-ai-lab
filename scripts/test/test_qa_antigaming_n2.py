#!/usr/bin/env python3
"""Tests for the 2026-10-13 package-qa rules in qa/ag_n2.py (wired into qa/gate_antigaming.py; REAL gate entry point, env -i, temp git repos, no network):
  * N_NEWPATH_LOOKALIKE: a NEW .py/.ts/.gd file in a directory that did not exist at base and that repeats its parent's name (`iptv-backend/iptv-backend/tests/`,
    `routers/outers/`) or is within edit distance 2 of an existing sibling directory. FLAG; FAIL only with gate mode `antigaming_newpath`=enforce; off = skipped.
  * N_EMPTIED_SOURCE: a tracked source file non-empty at base and <= 1 byte at head (FLAG only) + the `ag_n2.py sweep` CLI.
  * A_TESTFILE_EMPTIED gets its own key `antigaming_emptied` (FAIL when enforce, FLAG by default).
Every rule has a NEGATIVE control (seeded bad -> fires) and BENIGN controls (legit change -> silent).
QAGATE_QA_DIR=<dir holding another copy of qa/> runs the suite against that gate instead (mutation proofs)."""
import json
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OVN = os.path.abspath(os.path.join(HERE, "..", ".."))
QA = os.environ.get("QAGATE_QA_DIR") or os.path.join(OVN, "qa")
GATE = os.path.join(QA, "gate_antigaming.py")
PY = sys.executable
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + extra) if extra else ""))


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-agn2-test-"))
REPOS, STATE = os.path.join(T, "repos"), os.path.join(T, "state")
os.makedirs(REPOS)
os.makedirs(STATE)
ENV = {"PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": T, "NTFY_SERVER": "http://127.0.0.1:9/x", "OVN_DIR": T, "OVN_REPOS_DIR": REPOS,
       "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1", "QA_FETCH_WAIT": "0"}


def sh(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


_n = [0]


def mkrepo(*steps, name=None):
    """steps: dicts path->text (None deletes), one commit each. Gate range is HEAD~1..HEAD."""
    _n[0] += 1
    name = "%s_%d" % (name or "r", _n[0])
    d = os.path.join(REPOS, name)
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    g = lambda *a: sh(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", *a])  # noqa: E731
    g("init", "-q")
    for i, step in enumerate(steps):
        for path, txt in step.items():
            full = os.path.join(d, path)
            if txt is None:
                g("rm", "-q", path)
            else:
                os.makedirs(os.path.dirname(full), exist_ok=True)
                open(full, "w").write(txt)
                g("add", path)
        g("commit", "-q", "-m", "c%d" % i)
    return name


def gate(repo, env=None, gate_path=None):
    e = dict(ENV)
    if env:
        e.update(env)
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in e.items()] + [PY, gate_path or GATE, "check", "--repo", repo, "--base", "HEAD~1", "--head", "HEAD", "--no-record"]
    p = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
    try:
        res = json.loads(p.stdout.strip().splitlines()[-1])
    except Exception:  # noqa: BLE001
        res = {"verdict": "NOJSON", "summary": (p.stdout + p.stderr)[-300:], "details": {}}
    return res


def sweep(repo, base="HEAD~1", head="HEAD"):
    cmd = ["env", "-i"] + ["%s=%s" % kv for kv in ENV.items()] + [PY, os.path.join(QA, "ag_n2.py"), "sweep", "--repo", repo, "--base", base, "--head", head]
    p = subprocess.run(cmd, cwd=T, capture_output=True, text=True)
    return [json.loads(ln) for ln in p.stdout.strip().splitlines() if ln.strip()]


def fnd(res, rule):
    return [f for f in res.get("details", {}).get("findings", []) if f["rule"] == rule]


def rules(res):
    return sorted({"%s:%s" % (f["rule"], f["sev"]) for f in res.get("details", {}).get("findings", [])})


def fires(name, res, rule, sev=None):
    hit = [f for f in fnd(res, rule) if sev is None or f["sev"] == sev]
    ok(name, bool(hit), "verdict=%s rules=%s" % (res["verdict"], rules(res)))


def silent(name, res, rule):
    ok(name, not fnd(res, rule), "unexpected %s" % [f["msg"] for f in fnd(res, rule)])


MOD = "def f(x):\n    return x + 1\n\n\ndef g(x):\n    return x * 2\n"
TST = "from app.routers import f\n\n\ndef test_f():\n    assert f(1) == 2\n"
BASE = {"iptv-backend/app/routers/billing.py": MOD, "iptv-backend/app/services/parental.py": MOD, "iptv-backend/tests/test_billing.py": TST,
        "iptv-backend/app/v1/a.py": MOD, "web/src/api/client.ts": "export const a = 1\n"}
ENF_NP = {"OVN_QA_ANTIGAMING_NEWPATH": "enforce"}
OUTERS = {"iptv-backend/app/routers/outers/subscription.py": "\n"}

# ================================================================================================ N_NEWPATH_LOOKALIKE
res = gate(mkrepo(BASE, OUTERS, name="iptv_apps"))
fires("REPRO (iptv 64a01ac4): app/routers/outers/subscription.py (outers ~ routers, the parent) -> FLAG N_NEWPATH_LOOKALIKE", res, "N_NEWPATH_LOOKALIKE", "FLAG")
ok("... verdict is FLAG (shadow default: never FAIL)", res["verdict"] == "FLAG", "verdict=%s" % res["verdict"])
res = gate(mkrepo(BASE, {"iptv-backend/iptv-backend/tests/test_parental_pure.py": TST}, name="iptv_apps"))
fires("REPRO (iptv 6cdf9c68): iptv-backend/iptv-backend/tests/ doubles the parent while iptv-backend/tests/ exists -> FLAG", res, "N_NEWPATH_LOOKALIKE", "FLAG")
res = gate(mkrepo(BASE, {"iptv-backend/app/servces/x.py": MOD}, name="iptv_apps"))
fires("sibling typo: app/servces/ ~ app/services/ (distance 1) -> FLAG", res, "N_NEWPATH_LOOKALIKE", "FLAG")
res = gate(mkrepo(BASE, {"web/src/apis/x.ts": "export const b = 2\n"}, name="web"))
silent("api/ is 3 letters: below the minimum name length, so apis/ is NOT judged (documented limit)", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo({"web/src/clients/a.ts": "export const a = 1\n"}, {"web/src/client/x.ts": "export const b = 2\n"}, name="web"))
fires("ts: web/src/client/ ~ web/src/clients/ -> FLAG", res, "N_NEWPATH_LOOKALIKE", "FLAG")
res = gate(mkrepo({"scripts/battle/damage.gd": "extends Node\n"}, {"scripts/battel/x.gd": "extends Node\n"}, name="xlite"))
fires("gd: scripts/battel/ ~ scripts/battle/ -> FLAG", res, "N_NEWPATH_LOOKALIKE", "FLAG")
res = gate(mkrepo(BASE, OUTERS, name="iptv_apps"), env=ENF_NP)
fires("antigaming_newpath=enforce -> the same diff is a FAIL", res, "N_NEWPATH_LOOKALIKE", "FAIL")
ok("... and the verdict is FAIL", res["verdict"] == "FAIL", "verdict=%s" % res["verdict"])
res = gate(mkrepo(BASE, OUTERS, name="iptv_apps"), env={"OVN_QA_ANTIGAMING_NEWPATH": "off"})
silent("antigaming_newpath=off skips the rule", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, OUTERS, name="iptv_apps"), env={"OVN_QA_AG_N2": "off"})
silent("OVN_QA_AG_N2=off disables the whole n2 module", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/app/routers/outers/subscription.py": "\n", "iptv-backend/app/routers/outers/other.py": "\n"}, name="iptv_apps"))
ok("two new files in the same bad directory -> ONE finding (per directory)", len(fnd(res, "N_NEWPATH_LOOKALIKE")) == 1, str(len(fnd(res, "N_NEWPATH_LOOKALIKE"))))
# BENIGN controls
res = gate(mkrepo(BASE, {"iptv-backend/app/routers/payments/x.py": MOD}, name="iptv_apps"))
silent("BENIGN: a genuinely new feature directory (payments/) is not a lookalike", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/app/v2/a.py": MOD}, name="iptv_apps"))
silent("BENIGN: v2/ next to v1/ differs only in digits - siblings by design", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo({"app/batch10/a.py": MOD}, {"app/batch11/a.py": MOD}, name="iptv_apps"))
silent("BENIGN: batch11/ next to batch10/ (long enough to be judged, differs only in digits)", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/app/routers/billing_extra.py": MOD}, name="iptv_apps"))
silent("BENIGN: a new FILE (not directory) in an existing directory", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/app/services/parental2.py": MOD, "iptv-backend/tests/test_new.py": TST}, name="iptv_apps"))
silent("BENIGN: new files in EXISTING directories (tests/, services/)", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/app/api/x.py": MOD}, name="iptv_apps"))
silent("BENIGN: api/ (3 letters) is below the minimum name length even though it is within distance 2 of app/", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/docs/notes/readme.md": "x\n"}, name="iptv_apps"))
silent("BENIGN: a non-code file in a new directory", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/app/routers/outers/readme.md": "x\n"}, name="iptv_apps"))
silent("BENIGN: the typo directory but only a .md file in it (rule is for .py/.ts/.gd)", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo({"app/service/a.py": MOD, "app/service/b.py": MOD},
                  {"app/service/a.py": None, "app/service/b.py": None, "app/services/a.py": MOD, "app/services/b.py": MOD}, name="ren"))
silent("BENIGN: a whole directory renamed (service/ -> services/): the old sibling no longer holds files", res, "N_NEWPATH_LOOKALIKE")
res = gate(mkrepo(BASE, {"iptv-backend/node_modules/routers/x.js": "1\n", "iptv-backend/app/build/outers/y.py": MOD}, name="iptv_apps"))
silent("BENIGN: ignorable trees (node_modules/, build/) are not judged", res, "N_NEWPATH_LOOKALIKE")

# ================================================================================================ N_EMPTIED_SOURCE + sweep
res = gate(mkrepo(BASE, {"iptv-backend/app/services/parental.py": "\n"}, name="iptv_apps"))
fires("N_EMPTIED_SOURCE: a non-test source module emptied to one newline -> FLAG", res, "N_EMPTIED_SOURCE", "FLAG")
res = gate(mkrepo(BASE, {"iptv-backend/app/services/parental.py": ""}, name="iptv_apps"),
           env=dict(ENF_NP, OVN_QA_ANTIGAMING_TESTFILES="enforce", OVN_QA_ANTIGAMING_EMPTIED="enforce"))
ok("N_EMPTIED_SOURCE never FAILs, even with every sub-key enforce", res["verdict"] == "FLAG" and fnd(res, "N_EMPTIED_SOURCE"), "%s %s" % (res["verdict"], rules(res)))
res = gate(mkrepo(BASE, {"web/src/api/client.ts": "\n"}, name="web"))
fires("ts source emptied -> FLAG", res, "N_EMPTIED_SOURCE", "FLAG")
res = gate(mkrepo(BASE, {"iptv-backend/tests/test_billing.py": "\n"}, name="iptv_apps"))
fires("a TEST file emptied is still reported by A_TESTFILE_EMPTIED ...", res, "A_TESTFILE_EMPTIED", "FLAG")
silent("... and not a second time as N_EMPTIED_SOURCE", res, "N_EMPTIED_SOURCE")
res = gate(mkrepo(BASE, {"iptv-backend/app/services/parental.py": None}, name="iptv_apps"))
silent("BENIGN: the file is DELETED (the right way to retire it)", res, "N_EMPTIED_SOURCE")
res = gate(mkrepo(BASE, {"iptv-backend/app/services/parental.py": MOD + "\n# trailing\n"}, name="iptv_apps"))
silent("BENIGN: an ordinary edit", res, "N_EMPTIED_SOURCE")
res = gate(mkrepo({"pkg/mod.py": "\n"}, {"pkg/mod.py": "x = 1\n"}, name="iptv_apps"))
silent("BENIGN: an empty file that GAINED content", res, "N_EMPTIED_SOURCE")
res = gate(mkrepo({"pkg/__init__.py": "from .a import f\n", "pkg/a.py": MOD}, {"pkg/__init__.py": "\n", "pkg/a.py": MOD + "# x\n"}, name="iptv_apps"))
silent("BENIGN (replay FP, gitlark 5afb880e1b): an emptied __init__.py (re-exports stripped) is a normal refactor", res, "N_EMPTIED_SOURCE")
res = gate(mkrepo({"pkg/empty.py": "\n", "pkg/a.py": MOD}, {"pkg/empty.py": "", "pkg/a.py": MOD + "\n# x\n"}, name="iptv_apps"))
silent("BENIGN: a file that was ALREADY empty at base (newline -> nothing) is pre-existing, not an emptying", res, "N_EMPTIED_SOURCE")
res = gate(mkrepo(BASE, {"iptv-backend/app/services/parental.py": "\n"}, name="iptv_apps"), env={"OVN_QA_AG_N2": "off"})
silent("OVN_QA_AG_N2=off disables N_EMPTIED_SOURCE", res, "N_EMPTIED_SOURCE")
# sweep CLI
r = mkrepo(BASE, {"iptv-backend/app/services/parental.py": "\n", "iptv-backend/tests/test_billing.py": "\n", "web/src/api/client.ts": "export const a = 1\n// x\n"}, name="iptv_apps")
rows = sweep(r)
files = sorted(x["file"] for x in rows if x.get("rule"))
ok("sweep: lists exactly the emptied source + test files (not the edited one)", files == ["iptv-backend/app/services/parental.py", "iptv-backend/tests/test_billing.py"], str(files))
ok("sweep: the summary row says FLAG with a count of 2", rows[-1].get("verdict") == "FLAG" and rows[-1].get("count") == 2, str(rows[-1]))
r2 = mkrepo(BASE, {"iptv-backend/app/services/parental.py": MOD + "# edit\n"}, name="iptv_apps")
ok("sweep: a clean range is PASS", sweep(r2)[-1].get("verdict") == "PASS", str(sweep(r2)))
r4 = mkrepo({"pkg/__init__.py": "from .a import f\n", "pkg/a.py": MOD}, {"pkg/__init__.py": "\n"}, name="iptv_apps")
ok("sweep: an emptied __init__.py is not reported", sweep(r4)[-1].get("verdict") == "PASS", str(sweep(r4)))
r3 = mkrepo({"pkg/__init__.py": "", "pkg/a.py": MOD}, {"pkg/a.py": MOD + "# x\n"}, name="iptv_apps")
ok("sweep: a file that was already empty at base is not reported", sweep(r3)[-1].get("verdict") == "PASS", str(sweep(r3)))

# ================================================================================================ A_TESTFILE_EMPTIED own key
EMP = {"iptv-backend/tests/test_billing.py": "\n"}
res = gate(mkrepo(BASE, EMP, name="iptv_apps"))
fires("antigaming_emptied default (shadow): A_TESTFILE_EMPTIED is a FLAG", res, "A_TESTFILE_EMPTIED", "FLAG")
res = gate(mkrepo(BASE, EMP, name="iptv_apps"), env={"OVN_QA_ANTIGAMING_EMPTIED": "enforce"})
fires("antigaming_emptied=enforce: A_TESTFILE_EMPTIED is a FAIL", res, "A_TESTFILE_EMPTIED", "FAIL")
ok("... verdict FAIL", res["verdict"] == "FAIL", res["verdict"])
res2 = gate(mkrepo(BASE, OUTERS, name="iptv_apps"), env={"OVN_QA_ANTIGAMING_EMPTIED": "enforce"})
ok("the emptied key does NOT arm the new-path FAIL (separate keys)", fnd(res2, "N_NEWPATH_LOOKALIKE") and all(f["sev"] == "FLAG" for f in fnd(res2, "N_NEWPATH_LOOKALIKE")),
   str(rules(res2)))
res = gate(mkrepo(BASE, EMP, name="iptv_apps"), env={"OVN_QA_ANTIGAMING_TESTFILES": "enforce"})
fires("compat: the older antigaming_testfiles=enforce still arms A_TESTFILE_EMPTIED", res, "A_TESTFILE_EMPTIED", "FAIL")
STUB = {"iptv-backend/tests/test_new_thing.py": '"""Placeholder - the implement step fills this in."""\n'}
res = gate(mkrepo(BASE, STUB, name="iptv_apps"), env={"OVN_QA_ANTIGAMING_EMPTIED": "enforce"})
fires("the NEW-file placeholder stub (no test function) stays a FLAG under antigaming_emptied=enforce (replay: that state is routinely transient, the stub is filled next commit)", res, "A_TESTFILE_EMPTIED", "FLAG")
res = gate(mkrepo(BASE, STUB, name="iptv_apps"), env={"OVN_QA_ANTIGAMING_TESTFILES": "enforce"})
fires("... while the older antigaming_testfiles=enforce still arms it (unchanged behaviour)", res, "A_TESTFILE_EMPTIED", "FAIL")
res = gate(mkrepo(BASE, {"iptv-backend/tests/test_billing.py": TST + "\n\ndef test_g():\n    assert f(2) == 3\n"}, name="iptv_apps"),
           env={"OVN_QA_ANTIGAMING_EMPTIED": "enforce", "OVN_QA_ANTIGAMING_NEWPATH": "enforce"})
ok("BENIGN: a test file that gained a test is clean even with both keys enforce", res["verdict"] == "PASS", "%s %s" % (res["verdict"], rules(res)))

# ================================================================================================ pure unit: judge / lev
sys.path.insert(0, QA)
import ag_n2  # noqa: E402
ok("lev: routers/outers = 1", ag_n2.lev("routers", "outers") == 1)
ok("lev: early exit beyond the limit", ag_n2.lev("abcdefgh", "zzzzzzzz") == 3)
d, k = ag_n2.dir_index(["a/b/c.py", "a/d/e.py", "f.py"])
ok("dir_index: prefixes + children", d == {"a", "a/b", "a/d"} and k == {"": {"a"}, "a": {"b", "d"}}, str((d, k)))
ok("judge: an existing directory is never suspect", ag_n2.judge("a/b/new.py", d, k) is None)

# ================================================================================================ partial sync: ag_n2.py missing
QA_PARTIAL = os.path.join(T, "qa_partial")
os.makedirs(QA_PARTIAL)
for _f in os.listdir(QA):
    if _f.endswith((".py", ".json")) and _f != "ag_n2.py" and os.path.isfile(os.path.join(QA, _f)):
        shutil.copy(os.path.join(QA, _f), QA_PARTIAL)
ok("(setup) the partial qa copy lacks ag_n2.py", not os.path.exists(os.path.join(QA_PARTIAL, "ag_n2.py")))
res = gate(mkrepo(BASE, EMP, name="iptv_apps"), gate_path=os.path.join(QA_PARTIAL, "gate_antigaming.py"))
ok("PARTIAL SYNC: without ag_n2.py the older rules still run (A_TESTFILE_EMPTIED reported) and the loss is only a note",
   bool(fnd(res, "A_TESTFILE_EMPTIED")) and any("ag_n2 failed" in n for n in res.get("details", {}).get("notes", [])),
   "%s %s" % (rules(res), res.get("details", {}).get("notes")))

shutil.rmtree(T, ignore_errors=True)
print("\nantigaming n2 tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
