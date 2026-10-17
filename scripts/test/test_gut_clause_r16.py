#!/usr/bin/env python3
"""R14 verify package (2026-10-12) - X2 / platform P3: ovn_gut_clause.normalize and spec rule R16 (golden cases).
Shapes GUT 9.4 cannot run (reproduced on the box): -gdir=<file>.gd, bare -gtest=<name>.gd, -gselect=<function>. Mutations proved inline: normaliser disabled, R16 removed from STATIC_RULES."""
import os
import subprocess
import sys
import tempfile
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()   # 2026-10-16: every tempfile.mkdtemp() below is removed at exit (these tests left dirs in the private TMPDIR)

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_gut_clause as G  # noqa: E402
import ovn_spec_rules as R  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


RUN = "godot --headless -s addons/gut/gut_cmdln.gd"
d = tempfile.mkdtemp(prefix="gutr16-")
for rel, body in {"tests/test_enemy_faction_map.gd": "func test_faction_for_returns_correct_string():\n\tpass\n", "tests/test_aggro.gd": "",
                  "tests/sub/test_dup.gd": "", "tests2/test_dup.gd": "", "scripts/battle/enemy_faction_map.gd": "func faction_for(x):\n\treturn 1\n", "addons/gut/x.gd": ""}.items():
    os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
    open(os.path.join(d, rel), "w").write(body)
fs = G.DirFS(d)

print("== normalize: golden cases (DirFS)")
N = lambda c: G.normalize(c, fs)[0]  # noqa: E731
ok("-gdir=<existing file>.gd -> -gtest=res://",
   N(RUN + " -gdir=tests/test_enemy_faction_map.gd -gexit") == RUN + " -gtest=res://tests/test_enemy_faction_map.gd -gexit")
ok("res:// prefix on the gdir file is accepted",
   N(RUN + " -gdir=res://tests/test_aggro.gd") == RUN + " -gtest=res://tests/test_aggro.gd")
ok("-gdir=<file> + -gselect=<function> -> -gtest + -gunit_test_name (the live xlite shape)",
   N(RUN + " -gdir=tests/test_enemy_faction_map.gd -gexit -gselect=faction_for_returns_correct_string") ==
   RUN + " -gtest=res://tests/test_enemy_faction_map.gd -gexit -gunit_test_name=faction_for_returns_correct_string")
ok("-gdir=<dir> -gtest=<bare>.gd -> res:// path, -gdir dropped", N(RUN + " -gdir=res://tests -gtest=test_aggro.gd -gexit") == RUN + " -gtest=res://tests/test_aggro.gd -gexit")
ok("bare -gtest with NO -gdir resolves by unique basename", N(RUN + " -gtest=test_aggro.gd") == RUN + " -gtest=res://tests/test_aggro.gd")
ok("AMBIGUOUS bare name (2 tracked files) is left untouched", N(RUN + " -gtest=test_dup.gd") == RUN + " -gtest=test_dup.gd")
ok("MISSING bare name is left untouched", N(RUN + " -gtest=test_nope.gd") == RUN + " -gtest=test_nope.gd")
ok("a -gdir file that does not exist is left alone at run time (stays 'GUT target missing')", N(RUN + " -gdir=tests/test_nope.gd") == RUN + " -gdir=tests/test_nope.gd")
ok("-gdir with directories AND a file keeps the directories", N(RUN + " -gdir=tests/sub,tests/test_aggro.gd") == RUN + " -gtest=res://tests/test_aggro.gd -gdir=tests/sub")
ok("already-valid -gtest=res://... clause is untouched", N(RUN + " -gtest=res://tests/test_aggro.gd -gexit") == RUN + " -gtest=res://tests/test_aggro.gd -gexit")
ok("-gselect that IS a script file name fragment is untouched", N(RUN + " -gtest=res://tests/test_aggro.gd -gselect=aggro") == RUN + " -gtest=res://tests/test_aggro.gd -gselect=aggro")
ok("-gselect naming a function the file does not define is untouched", N(RUN + " -gtest=res://tests/test_aggro.gd -gselect=not_defined_anywhere") == RUN + " -gtest=res://tests/test_aggro.gd -gselect=not_defined_anywhere")
ok("non-GUT command untouched", N("pytest tests/x.py -gdir=a.gd") == "pytest tests/x.py -gdir=a.gd")
c1 = N(RUN + " -gdir=tests/test_enemy_faction_map.gd -gselect=faction_for_returns_correct_string")
ok("idempotent", N(c1) == c1)
ok("CLI: normalize reads stdin, uses the project dir", subprocess.run([sys.executable, os.path.join(HERE, "..", "ovn_gut_clause.py"), "normalize", d], input=RUN + " -gdir=tests/test_aggro.gd", capture_output=True, text=True).stdout == RUN + " -gtest=res://tests/test_aggro.gd")

print("== R16 ingest rule (static: no repo)")
def it(v):
    return "- [ ] [T2] tests/test_enemy_faction_map.gd — add test. VERIFY: `%s`. (cat:gd; multifile:no)" % v
l = it(RUN + " -gdir=tests/test_enemy_faction_map.gd -gexit -gselect=faction_for_returns_correct_string")
l2, fs2 = R.lint_static(l, only={"R16"})
ok("R16 static: -gdir=<file>.gd -> -gtest=res://<file>.gd (even when the file does not exist yet: the item may create it)",
   E.extract_verify(l2) == RUN + " -gtest=res://tests/test_enemy_faction_map.gd -gexit -gselect=faction_for_returns_correct_string" and [f["rule"] for f in fs2] == ["R16"], (l2, fs2))
ok("R16 is part of lint_static by default and idempotent", R.lint_static(l2)[0] == R.lint_static(l)[0] and not [f for f in R.lint_static(l2)[1] if f["rule"] == "R16"])
ok("R16 leaves a non-GUT VERIFY alone", R.lint_static(it("grep -q x f"), only={"R16"})[1] == [])
ok("R16 bare form (no backticks) is rewritten too", E.extract_verify(R.lint_static("- [ ] [T2] a.gd — x. VERIFY: " + RUN + " -gdir=tests/a.gd. (cat:gd)", only={"R16"})[0]).startswith(RUN + " -gtest=res://tests/a.gd"))

print("== R16 with the repo at a ref (lint_batch)")
GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]
repo = os.path.join(tempfile.mkdtemp(prefix="gutr16-repo-"), "r")
os.makedirs(repo)
subprocess.run(["git", "-C", repo, "init", "-q", "-b", "main"], check=True)
for rel in ("tests/test_aggro.gd", "tests/sub/test_dup.gd", "tests2/test_dup.gd"):
    os.makedirs(os.path.dirname(os.path.join(repo, rel)), exist_ok=True)
    open(os.path.join(repo, rel), "w").write("func test_a():\n\tpass\n")
subprocess.run(GIT[:1] + ["-C", repo] + GIT[1:] + ["add", "-A"], check=True)
subprocess.run(["git", "-C", repo] + GIT[1:] + ["commit", "-qm", "x"], check=True)
ctx = R.Ctx(repo, ref="main")
b = "- [ ] [T2] tests/test_aggro.gd — x. VERIFY: `%s -gdir=tests -gtest=test_aggro.gd -gexit`. (cat:gd; multifile:no)" % RUN
out = R.lint_batch([b], ctx)[0]
ok("bare -gtest=test_aggro.gd resolves to the unique tracked path", E.extract_verify(out[0]) == RUN + " -gtest=res://tests/test_aggro.gd -gexit" and "R16" in [f["rule"] for f in out[1]], out)
b2 = b.replace("test_aggro.gd -gexit", "test_dup.gd -gexit")
out2 = R.lint_batch([b2], ctx)[0]
ok("ambiguous bare name: line untouched + R16 flag", E.extract_verify(out2[0]) == E.extract_verify(b2) and [f["sev"] for f in out2[1] if f["rule"] == "R16"] == ["flag"], out2)
b3 = "- [ ] [T2] tests/test_new_thing.gd — create. VERIFY: `%s -gtest=test_new_thing.gd -gexit`. (cat:gd; multifile:no)" % RUN
out3 = R.lint_batch([b3], ctx)[0]
ok("a bare name the ITEM ITSELF creates (its target) resolves to that path", E.extract_verify(out3[0]) == RUN + " -gtest=res://tests/test_new_thing.gd -gexit", out3)

print("== MUTATIONS")
_g = G.normalize
G.normalize = lambda cmd, fs=None, require_exists=True: (cmd, [])
mut = R.lint_static(l, only={"R16"})[0]
G.normalize = _g
ok("MUTATION (normaliser disabled): the shape is not rewritten", mut == l)
_sr = R.STATIC_RULES
R.STATIC_RULES = tuple(x for x in _sr if x[0] != "R16")
mut2 = R.lint_static(l)[0]
R.STATIC_RULES = _sr
ok("MUTATION (R16 not in STATIC_RULES): the static pass leaves -gdir=<file>.gd", "-gdir=tests/test_enemy_faction_map.gd" in mut2)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
