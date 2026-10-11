#!/usr/bin/env python3
"""Tests for the 2026-10-10 package-qagate changes in qa/gate_antigaming.py + qa/ag_r10.py + qa/ag_h13.py (REAL gate entry point, env -i, temp git repos,
no network):
  * GUT fail_test()/pass_test(): the exact xlite tests/test_uid_hygiene.gd before/after pair (commit 2a19940, fixtures_qagate/) is NOT an oracle weakening
    (it held claude/feature behind an enforcing FAIL for ~20 h); pass_test() alone is still no protection (E_ZERO_ASSERTS / A_ASSERT_NOOP stay FAIL)
  * E_GD_TEST_NOT_GUT, A_TESTFILE_EMPTIED (FLAG; FAIL only with gate mode antigaming_testfiles=enforce), E_TEST_NOT_COLLECTED FAIL for NEW files in the
    same mode, D_UNREFERENCED_FUNC
Every rule has a NEGATIVE control (seeded bad -> fires) and a BENIGN control (legit change -> silent).
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


T = os.path.realpath(tempfile.mkdtemp(prefix="qa-agr10-test-"))
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
    name = name or "r%d" % _n[0]
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


def fnd(res, rule):
    return [f for f in res.get("details", {}).get("findings", []) if f["rule"] == rule]


def rules(res):
    return sorted({"%s:%s" % (f["rule"], f["sev"]) for f in res.get("details", {}).get("findings", [])})


def fires(name, res, rule, sev=None):
    hit = [f for f in fnd(res, rule) if sev is None or f["sev"] == sev]
    ok(name, bool(hit), "verdict=%s rules=%s" % (res["verdict"], rules(res)))


def silent(name, res, rule):
    ok(name, not fnd(res, rule), "unexpected %s" % [f["msg"] for f in fnd(res, rule)])


def fixture(n):
    return open(os.path.join(HERE, "fixtures_qagate", n)).read()


ENFORCE_TF = {"OVN_QA_ANTIGAMING_TESTFILES": "enforce"}

# ================================================================================================ GUT fail_test / pass_test
UID_OLD = fixture("xlite_test_uid_hygiene_before_2a19940.gd")
UID_NEW = fixture("xlite_test_uid_hygiene_after_2a19940.gd")
res = gate(mkrepo({"tests/test_uid_hygiene.gd": UID_OLD}, {"tests/test_uid_hygiene.gd": UID_NEW}, name="xlite"))
ok("REPRO (real diff of xlite 2a19940): assert_false(true,msg)/assert_true(true,..) -> fail_test(msg)/pass_test(..) is NOT a FAIL", res["verdict"] != "FAIL",
   "verdict=%s rules=%s" % (res["verdict"], rules(res)))
silent("REPRO: no E_ZERO_ASSERTS on the uid-hygiene rewrite", res, "E_ZERO_ASSERTS")
silent("REPRO: no A_ASSERT_NOOP on the uid-hygiene rewrite", res, "A_ASSERT_NOOP")
ok("REPRO: the rewrite is a clean PASS", res["verdict"] == "PASS", "verdict=%s rules=%s" % (res["verdict"], rules(res)))

EQ = "extends GutTest\n\nfunc test_add():\n\tassert_eq(add(1, 2), 3)\n\nfunc test_sub():\n\tassert_eq(sub(3, 1), 2)\n\tassert_eq(sub(1, 1), 0)\n"
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ.replace("\tassert_eq(add(1, 2), 3)\n", "\tpass_test(\"fine\")\n")}, name="xlite"))
fires("NEGATIVE: assert_eq replaced by pass_test() only -> still FAIL E_ZERO_ASSERTS", res, "E_ZERO_ASSERTS", "FAIL")
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ.replace("\tassert_eq(sub(3, 1), 2)\n\tassert_eq(sub(1, 1), 0)\n", "\tassert_eq(sub(3, 1), 2)\n\tpass_test(\"fine\")\n")}, name="xlite"))
fires("NEGATIVE: one of two assert_eq replaced by pass_test() -> A_ASSERT_NOOP FAIL (a real assertion became a no-op)", res, "A_ASSERT_NOOP", "FAIL")
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ.replace("\tassert_eq(add(1, 2), 3)\n", "\tif add(1, 2) != 3:\n\t\tfail_test(\"bad\")\n")}, name="xlite"))
ok("fail_test() counts as an effective assertion: assert_eq -> `if bad: fail_test()` is not E_ZERO_ASSERTS/FAIL", not fnd(res, "E_ZERO_ASSERTS") and res["verdict"] != "FAIL", str(rules(res)))
fires("... but it is a weakening (rank 4 -> 1): FLAG A_ASSERT_WEAKENED stays visible", res, "A_ASSERT_WEAKENED", "FLAG")
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ + "\nfunc test_new():\n\tvar r := add(2, 2)\n\tif r != 4:\n\t\tfail_test(\"wrong\")\n\telse:\n\t\tpass_test(\"ok\")\n"}, name="xlite"))
ok("BENIGN: new test `if bad: fail_test() else: pass_test()` -> no A_VACUOUS / A_VACUOUS_ASSERT, PASS",
   res["verdict"] == "PASS" and not fnd(res, "A_VACUOUS") and not fnd(res, "A_VACUOUS_ASSERT"), "%s %s" % (res["verdict"], rules(res)))
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ + "\nfunc test_new():\n\tpass_test(\"ok\")\n"}, name="xlite"))
ok("NEW test with ONLY pass_test() and no other call: not a hard FAIL on its own (no protection, but no A_VACUOUS FAIL)", res["verdict"] != "FAIL" and not fnd(res, "A_VACUOUS"),
   "%s %s" % (res["verdict"], rules(res)))
fires("... it is visible as A_VACUOUS_ASSERT (FLAG)", res, "A_VACUOUS_ASSERT", "FLAG")
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ + "\nfunc test_smoke():\n\t_make_unit(1)\n\t_refresh()\n\tpass_test(\"did not crash\")\n"}, name="xlite"))
ok("BENIGN: a smoke test that calls code and ends in pass_test('did not crash') is not reported (xlite c4c473c9 / e5d3effc / e61563a3 in the 60-day replay)",
   res["verdict"] == "PASS" and not fnd(res, "A_VACUOUS_ASSERT"), "%s %s" % (res["verdict"], rules(res)))
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ + "\nfunc test_new():\n\tassert_true(true, \"placeholder\")\n"}, name="xlite"))
fires("tautology with a message: assert_true(true, msg) is rank 0 like assert_true(true): a new test of only that FAILs A_VACUOUS", res, "A_VACUOUS", "FAIL")
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ + "\nfunc test_new():\n\tvar r := add(2, 2)\n\tif r != 4:\n\t\tassert_false(true, \"wrong\")\n\telse:\n\t\tassert_true(true, \"ok\")\n"}, name="xlite"))
ok("BENIGN: the pre-GUT-9 if/else idiom `assert_false(true, m)` / `assert_true(true, m)` next to a real assertion is not reported as vacuous (gold row F5 shape)",
   res["verdict"] == "PASS" and not fnd(res, "A_VACUOUS") and not fnd(res, "A_VACUOUS_ASSERT"), "%s %s" % (res["verdict"], rules(res)))
res = gate(mkrepo({"tests/test_m.gd": EQ}, {"tests/test_m.gd": EQ.replace("add(1, 2), 3", "add(1, 2), 4")}, name="xlite"))
ok("BENIGN control: a plain assert_eq edit is unchanged -> PASS", res["verdict"] == "PASS", "%s %s" % (res["verdict"], rules(res)))
ASRT = "extends GutTest\n\nfunc test_a():\n\tassert_true(x(), \"x must hold\")\n"
res = gate(mkrepo({"tests/test_a.gd": ASRT}, {"tests/test_a.gd": ASRT.replace("assert_true(x(), \"x must hold\")", "assert_true(true, \"x must hold\")")}, name="xlite"))
fires("NEGATIVE: assert_true(x(), msg) -> assert_true(true, msg) is a no-op swap (FAIL)", res, "E_ZERO_ASSERTS", "FAIL")

# ================================================================================================ E_GD_TEST_NOT_GUT
GD_BASE = {"scripts/a.gd": "extends Node\n", "tests/test_ok.gd": "extends GutTest\n\nfunc test_a():\n\tassert_eq(1, 1)\n"}
ONE = "func test_a():\n\tassert_eq(1, 1)\n"
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "extends Node\n\n" + ONE}, name="xlite"))
fires("E_GD_TEST_NOT_GUT: edited tests/*.gd with func test_ but `extends Node` -> FLAG", res, "E_GD_TEST_NOT_GUT", "FLAG")
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": ONE}, name="xlite"))
fires("E_GD_TEST_NOT_GUT: no extends at all -> FLAG", res, "E_GD_TEST_NOT_GUT", "FLAG")
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "extends GUTTest\n\n" + ONE}, name="xlite"))
fires("E_GD_TEST_NOT_GUT: the 'extends GUTTest' typo -> FLAG", res, "E_GD_TEST_NOT_GUT", "FLAG")
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "extends GutTest\n\n" + ONE + "\nfunc test_b():\n\tassert_eq(2, 2)\n"}, name="xlite"))
silent("BENIGN: extends GutTest with tests is silent", res, "E_GD_TEST_NOT_GUT")
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "extends \"res://addons/gut/test.gd\"\n\n" + ONE}, name="xlite"))
silent("BENIGN: extends \"res://addons/gut/test.gd\" is silent", res, "E_GD_TEST_NOT_GUT")
res = gate(mkrepo(GD_BASE, {"tests/base_case.gd": "class_name BaseCase\nextends GutTest\n", "tests/test_ok.gd": "extends BaseCase\n\n" + ONE}, name="xlite"))
silent("BENIGN: extends a project class_name base that extends GutTest is silent", res, "E_GD_TEST_NOT_GUT")
res = gate(mkrepo(GD_BASE, {"tests/base_case2.gd": "extends GutTest\n", "tests/test_ok.gd": "extends \"res://tests/base_case2.gd\"\n\n" + ONE}, name="xlite"))
silent("BENIGN: extends a res:// base file that extends GutTest is silent", res, "E_GD_TEST_NOT_GUT")
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "extends NotAGutBase\n\n" + ONE}, name="xlite"))
fires("an unresolvable / engine-class base is not GUT -> FLAG", res, "E_GD_TEST_NOT_GUT", "FLAG")
res = gate(mkrepo(GD_BASE, {"tests/helpers/builder.gd": "extends RefCounted\n\nfunc build():\n\tpass\n"}, name="xlite"))
silent("BENIGN: a non-test helper under tests/ (no test_ name, no func test_) is not judged", res, "E_GD_TEST_NOT_GUT")
res = gate(mkrepo(GD_BASE, {"tests/test_new.gd": "extends Node\n\n" + ONE}, name="xlite"))
ok("a NEW non-GUT test is reported once (E_TEST_NOT_COLLECTED), not twice", len(fnd(res, "E_TEST_NOT_COLLECTED")) == 1 and not fnd(res, "E_GD_TEST_NOT_GUT"), str(rules(res)))

# ================================================================================================ A_TESTFILE_EMPTIED
for label, empty in (("2-byte file", "\n\n"), ("one-line comment", "# The Scatter class was removed.\n"), ("placeholder comment", "# Placeholder - the implement step fills this in.\n"),
                     ("extends only", "extends GutTest\n")):
    res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": empty}, name="xlite"))
    fires("A_TESTFILE_EMPTIED (gd %s): the only test is gone but the file stays -> FLAG by default" % label, res, "A_TESTFILE_EMPTIED", "FLAG")
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "\n"}, name="xlite"), env=ENFORCE_TF)
ok("A_TESTFILE_EMPTIED -> FAIL once the gate mode antigaming_testfiles is enforce (second key), verdict FAIL",
   res["verdict"] == "FAIL" and fnd(res, "A_TESTFILE_EMPTIED")[0]["sev"] == "FAIL", str(rules(res)))
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "\n"}, name="xlite"), env={"OVN_QA_ANTIGAMING": "enforce"})
ok("flipping only the shared `antigaming` gate leaves it a FLAG (own key not armed)", res["verdict"] == "FLAG" and fnd(res, "A_TESTFILE_EMPTIED"), str(rules(res)))
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": "\n"}, name="xlite"), env={"OVN_QA_ANTIGAMING_TESTFILES": "off"})
fires("antigaming_testfiles=off keeps the FLAG (never turns the rule into silence)", res, "A_TESTFILE_EMPTIED", "FLAG")
res = gate(mkrepo(GD_BASE, {"tests/test_ok.gd": None}, name="xlite"))
silent("BENIGN: a deleted test file is the A_TESTFILE_DELETED business, not 'emptied'", res, "A_TESTFILE_EMPTIED")
res = gate(mkrepo({"tests/test_ok.gd": "extends GutTest\n\nfunc test_a():\n\tassert_eq(1, 1)\n\nfunc test_b():\n\tassert_eq(2, 2)\n"},
                  {"tests/test_ok.gd": "extends GutTest\n\nfunc test_a():\n\tassert_eq(1, 1)\n"}, name="xlite"))
silent("BENIGN: one of two tests removed -> the file still has a test", res, "A_TESTFILE_EMPTIED")
res = gate(mkrepo({"tests/test_empty.gd": "# placeholder\n"}, {"tests/test_empty.gd": "# placeholder, reworded\n"}, name="xlite"))
silent("BENIGN: a file that ALREADY had no test (pre-existing) is not blamed on this diff", res, "A_TESTFILE_EMPTIED")
res = gate(mkrepo(GD_BASE, {"tests/test_new.gd": "# Placeholder - the implement step fills this in.\n"}, name="xlite"))
fires("a NEW test file with no test function (harness stub never filled) -> FLAG", res, "A_TESTFILE_EMPTIED", "FLAG")
res = gate(mkrepo(GD_BASE, {"tests/test_new.gd": "# Placeholder - the implement step fills this in.\n"}, name="xlite"), env=ENFORCE_TF)
ok("... and FAIL in enforce", res["verdict"] == "FAIL", str(rules(res)))
res = gate(mkrepo(dict(GD_BASE, **{"tests/helpers/builder.gd": "extends RefCounted\n\nfunc build():\n\tpass\n"}), {"tests/helpers/builder.gd": "extends RefCounted\n\nfunc build2():\n\tpass\n"}, name="xlite"))
silent("BENIGN: editing a helper under tests/ is not a test file", res, "A_TESTFILE_EMPTIED")
PYT = "def test_a():\n    assert 1 == 1\n"
res = gate(mkrepo({"tests/test_a.py": PYT}, {"tests/test_a.py": '"""All tests removed."""\n'}))
fires("A_TESTFILE_EMPTIED (py): module reduced to a docstring -> FLAG", res, "A_TESTFILE_EMPTIED", "FLAG")
res = gate(mkrepo({"tests/test_a.py": PYT}, {"tests/test_a.py": "# nothing\n"}))
fires("A_TESTFILE_EMPTIED (py): module reduced to a comment -> FLAG", res, "A_TESTFILE_EMPTIED", "FLAG")
res = gate(mkrepo({"tests/test_a.py": PYT}, {"tests/test_a.py": "class TestX:\n    def test_m(self):\n        assert 1 == 1\n"}))
silent("BENIGN (py): tests moved into a class are still tests", res, "A_TESTFILE_EMPTIED")
res = gate(mkrepo({"tests/test_a.py": PYT}, {"tests/test_a.py": "def test_a(:\n"}))
silent("BENIGN (py): an unparsable module is not judged (unknown, never FAIL on a guess)", res, "A_TESTFILE_EMPTIED")
res = gate(mkrepo({"tests/test_a.py": PYT, "tests/conftest.py": "x = 1\n"}, {"tests/conftest.py": "x = 2\n"}))
silent("BENIGN (py): conftest.py has no tests by design", res, "A_TESTFILE_EMPTIED")
res = gate(mkrepo({"tests/test_a.py": PYT}, {"tests/test_b.py": "from tests.helpers import mk\n\n\nVALUE = mk()\n"}))
fires("a NEW python test_*.py with no test function -> FLAG", res, "A_TESTFILE_EMPTIED", "FLAG")

# ================================================================================================ E_TEST_NOT_COLLECTED: FAIL for NEW files in enforce
IPTV = {"iptv-backend/pytest.ini": "[pytest]\ntestpaths = tests\n", "iptv-backend/tests/test_a.py": "def test_a():\n    assert f(1) == 1\n", "iptv-backend/app/x.py": "X = 1\n"}
NEWT = {"iptv-backend/app/services/test_epg.py": "def test_e():\n    assert f(2) == 2\n"}
res = gate(mkrepo(IPTV, NEWT, name="iptv_apps"))
ok("E_TEST_NOT_COLLECTED stays FLAG by default (shadow)", res["verdict"] == "FLAG" and fnd(res, "E_TEST_NOT_COLLECTED")[0]["sev"] == "FLAG", str(rules(res)))
res = gate(mkrepo(IPTV, NEWT, name="iptv_apps"), env=ENFORCE_TF)
ok("E_TEST_NOT_COLLECTED for a NEW file -> FAIL when antigaming_testfiles=enforce", res["verdict"] == "FAIL" and fnd(res, "E_TEST_NOT_COLLECTED")[0]["sev"] == "FAIL", str(rules(res)))
res = gate(mkrepo(IPTV, NEWT, name="iptv_apps"), env={"OVN_QA_ANTIGAMING": "enforce"})
ok("... the shared antigaming flip alone does not arm it", res["verdict"] == "FLAG", str(rules(res)))
res = gate(mkrepo(dict(IPTV, **NEWT), {"iptv-backend/app/services/test_epg2.py": NEWT["iptv-backend/app/services/test_epg.py"], "iptv-backend/app/services/test_epg.py": None},
                  name="iptv_apps"), env=ENFORCE_TF)
ok("BENIGN in enforce: a RENAME of an already-uncollected file stays FLAG (only genuinely new files FAIL)", res["verdict"] != "FAIL", str(rules(res)))
res = gate(mkrepo(IPTV, {"iptv-backend/tests/test_new.py": "def test_e():\n    assert f(3) == 3\n"}, name="iptv_apps"), env=ENFORCE_TF)
ok("BENIGN in enforce: a new test under iptv-backend/tests/ is collected -> PASS", res["verdict"] == "PASS", str(rules(res)))
GUTN = "extends GutTest\n\nfunc test_a():\n\tassert_eq(1, 1)\n"
res = gate(mkrepo(GD_BASE, {"test/test_x.gd": GUTN}, name="xlite"), env=ENFORCE_TF)
fires("xlite: new GUT test outside tests/ -> FAIL in enforce", res, "E_TEST_NOT_COLLECTED", "FAIL")

# ================================================================================================ D_UNREFERENCED_FUNC
UB = {"scripts/battle/damage.gd": "extends RefCounted\n\nstatic func compute(a, b):\n\treturn a - b\n", "scripts/use.gd": "extends Node\n\nfunc go():\n\treturn 1\n"}
DMG = UB["scripts/battle/damage.gd"]
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nstatic func coerce_to_array(v):\n\treturn [v]\n"}, name="xlite"))
fires("D_UNREFERENCED_FUNC (or the older D_DEAD_SYMBOL): new public static func referenced nowhere is flagged", res, "D_DEAD_SYMBOL", "FLAG")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _private_helper(v):\n\treturn v\n"}, name="xlite"))
fires("D_UNREFERENCED_FUNC: a new PRIVATE func with no reference is flagged (D_DEAD_SYMBOL skips private)", res, "D_UNREFERENCED_FUNC", "FLAG")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nstatic func helper_a(v):\n\treturn v\n", "scripts/use.gd": UB["scripts/use.gd"].replace("return 1", "return Damage.helper_a(1)")}, name="xlite"))
silent("BENIGN: a new func called from another file in the same commit", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _helper_b(v):\n\treturn v\n\nfunc _compute2(a):\n\treturn _helper_b(a)\n"}, name="xlite"))
ok("a private func called only by another new (itself unreferenced) func: the caller is flagged, the callee is not",
   not any("_helper_b" in f["msg"] for f in fnd(res, "D_UNREFERENCED_FUNC")) and any("_compute2" in f["msg"] for f in fnd(res, "D_UNREFERENCED_FUNC")),
   str([f["msg"][:40] for f in fnd(res, "D_UNREFERENCED_FUNC")]))
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _tested_only(v):\n\treturn v\n", "tests/test_damage.gd": "extends GutTest\n\nfunc test_t():\n\tassert_eq(Damage._tested_only(1), 1)\n"}, name="xlite"))
silent("BENIGN: referenced only by a test counts as a reference (D_DEAD_SYMBOL's job, not this rule's)", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _on_pressed():\n\tpass\n", "scenes/hud.tscn": "[connection signal=\"pressed\" from=\"B\" to=\".\" method=\"_on_pressed\"]\n"}, name="xlite"))
silent("BENIGN: a handler named only in a .tscn connection", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _dyn():\n\tpass\n", "scripts/use.gd": UB["scripts/use.gd"].replace("return 1", "return call(\"_dyn\")")}, name="xlite"))
silent("BENIGN: reached through call(\"name\")", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _ready():\n\tpass\n\nfunc _process(delta):\n\tpass\n"}, name="xlite"))
silent("BENIGN: Godot virtual callbacks (_ready/_process) are never flagged", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\n@rpc(\"any_peer\")\nfunc _remote_hit():\n\tpass\n"}, name="xlite"))
silent("BENIGN: an annotated func (@rpc) is reachable by other means", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG.replace("return a - b", "return a - b - 1")}, name="xlite"))
silent("BENIGN: editing the body of an existing func (not a new func)", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\n# note: _unused_thing is gone\nfunc _unused_thing():\n\tpass\n"}, name="xlite"))
fires("a mention in a comment is not a use -> still flagged", res, "D_UNREFERENCED_FUNC", "FLAG")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc test_looking_helper():\n\tpass\n"}, name="xlite"))
silent("BENIGN: test_-prefixed names are not judged", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _orphan(v):\n\treturn v\n"}, name="xlite"), env={"OVN_QA_AG_R10": "off"})
silent("OVN_QA_AG_R10=off kill switch disables the r10 rules", res, "D_UNREFERENCED_FUNC")
res = gate(mkrepo(UB, {"scripts/battle/damage.gd": DMG + "\nfunc _orphan(v):\n\treturn v\n"}, name="xlite"), env=dict(ENFORCE_TF, OVN_QA_ANTIGAMING="enforce"))
ok("D_UNREFERENCED_FUNC is advisory: verdict FLAG, never FAIL, even with both enforce keys", res["verdict"] == "FLAG" and fnd(res, "D_UNREFERENCED_FUNC"), str(rules(res)))

# ================================================================================================ reviewer r2 minor 1: partial qa/ sync (ag_r10.py missing)
QA_PARTIAL = os.path.join(T, "qa_partial")
os.makedirs(QA_PARTIAL)
for _f in os.listdir(QA):
    if _f.endswith((".py", ".json")) and _f != "ag_r10.py" and os.path.isfile(os.path.join(QA, _f)):
        shutil.copy(os.path.join(QA, _f), QA_PARTIAL)
ok("(setup) the partial qa copy really lacks ag_r10.py and has ag_h13.py", not os.path.exists(os.path.join(QA_PARTIAL, "ag_r10.py")) and os.path.exists(os.path.join(QA_PARTIAL, "ag_h13.py")))
res = gate(mkrepo(IPTV, NEWT, name="iptv_apps"), env=ENFORCE_TF, gate_path=os.path.join(QA_PARTIAL, "gate_antigaming.py"))
hit = fnd(res, "E_TEST_NOT_COLLECTED")
ok("PARTIAL SYNC: ag_h13 still runs when ag_r10.py is missing: E_TEST_NOT_COLLECTED is reported, as FLAG (never FAIL, new sub-key unavailable)",
   bool(hit) and hit[0]["sev"] == "FLAG" and res["verdict"] == "FLAG", "verdict=%s rules=%s notes=%s" % (res["verdict"], rules(res), res.get("details", {}).get("notes")))
ok("PARTIAL SYNC: the loss of the r10 rules is only a note, not a lost ag_h13 run",
   not any("ag_h13 failed" in n for n in res.get("details", {}).get("notes", [])), str(res.get("details", {}).get("notes")))

shutil.rmtree(T, ignore_errors=True)
print("\nantigaming r10 tests: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
