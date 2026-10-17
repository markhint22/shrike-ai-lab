#!/usr/bin/env python3
"""Intake package (2026-10-13), xlite night F2: the VERIFY clause is a command, never an edit target.

why_unworkable() / scout_guard() took the first path-like token that exists on disk from the WHOLE item line. The GUT runner `addons/gut/gut_cmdln.gd` (named after `-s` in every
GUT VERIFY) matched `.queue-hard-banned-files`' `addons/` entry, so every 'Create test X' item whose target file did not exist yet was parked [unworkable: hard-banned file ...]
(9 open xlite lines, the lane ran out of work). Fix: scan only the text before `VERIFY:`, never a token after -s/--script.
Mutation proofs (scratch copy): edit_text() returning the whole line, or why_unworkable() scanning `line` instead of edit_text(line), turns the marked cases red."""
import os
import subprocess
import sys
import tempfile
import os as _tt_os, sys as _tt_sys
_tt_sys.path.insert(0, _tt_os.path.dirname(_tt_os.path.abspath(__file__)))
import tmp_track
tmp_track.install()   # 2026-10-16: every tempfile.mkdtemp() below is removed at exit (these tests left dirs in the private TMPDIR)

HERE = os.path.dirname(os.path.abspath(__file__))
QDIR = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, QDIR)
import ovn_park_unworkable as P  # noqa: E402

PASS = FAIL = 0


def ok(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  ok   " + name)
    else:
        FAIL += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


root = tempfile.mkdtemp(prefix="park-scope-")
for rel, body in {"addons/gut/gut_cmdln.gd": "x", "addons/gut/gut.gd": "x", "scripts/battle/battle.gd": "x", "scripts/small.gd": "x",
                  "tests/battle/test_damage.gd": "x", "tests/test_existing.gd": "x"}.items():
    os.makedirs(os.path.dirname(os.path.join(root, rel)), exist_ok=True)
    open(os.path.join(root, rel), "w").write(body)
open(os.path.join(root, ".queue-hard-banned-files"), "w").write("# vendored\nscripts/battle/battle.gd\naddons/\n")
banned = P.banned_list(root)
W = lambda line: P.why_unworkable(line, root, banned, 120000)  # noqa: E731

RUN = "godot --headless -s addons/gut/gut_cmdln.gd"
print("== why_unworkable: the VERIFY clause is not scanned")
ok("[F2] 'Create test X' (target not on disk) whose VERIFY runs the GUT runner is NOT hard-banned",
   W("- [ ] [T4] tests/battle/test_battle_spawn_directives.gd — Create test verifying x. VERIFY: `%s -gdir=tests/battle -gtest=test_battle_spawn_directives.gd`. (cat:test)" % RUN) is None)
ok("[F2] same for a bare (no backtick) VERIFY with -gdir=res://",
   W("- [ ] [T2] tests/test_new.gd — Create a new GUT test. VERIFY: %s -gdir=res://tests -gexit && echo PASS. (cat:test)" % RUN) is None)
ok("[F2] 'VERIFY: Run `godot -s addons/gut/gut_cmdln.gd -gdir=tests/x.gd`' prose form",
   W("- [ ] [T2] tests/test_new.gd — Create a new GUT test. VERIFY: Run `%s -gdir=tests/test_new.gd` and ensure all tests pass. (cat:test)" % RUN) is None)
ok("a REAL banned target before the VERIFY is still parked",
   W("- [ ] [T3] scripts/battle/battle.gd — add a helper. VERIFY: `grep -n helper scripts/battle/battle.gd`") == "hard-banned file scripts/battle/battle.gd")
ok("a vendored target (addons/gut/gut.gd) is still parked",
   W("- [ ] [T5] addons/gut/gut.gd — Run GUT test suite. VERIFY: %s -gdir=res://tests -gexit" % RUN) == "hard-banned file addons/gut/gut.gd")
ok("a banned file named in the DESCRIPTION after the target is still found when the first path is absent on disk",
   W("- [ ] [T3] tests/test_new.gd — add a test that calls code in scripts/battle/battle.gd. VERIFY: `true`") == "hard-banned file scripts/battle/battle.gd")
ok("a banned path ONLY inside the VERIFY is not a target",
   W("- [ ] [T3] tests/test_new.gd — add a test for the small helper. VERIFY: `grep -c x scripts/battle/battle.gd`") is None)
ok("an existing small target is still fine", W("- [ ] [T2] scripts/small.gd — add. VERIFY: `%s -gtest=res://tests/test_existing.gd`" % RUN) is None)

print("== -s / --script arguments in the description are never an edit target")
ok("[F2] `godot -s addons/gut/gut_cmdln.gd` in the DESCRIPTION is not an edit target",
   W("- [ ] [T2] tests/test_new.gd — Create a GUT test (run it with `godot --headless -s addons/gut/gut_cmdln.gd`). VERIFY: `true`") is None)
ok("--script <x> and -s=<x> forms", W("- [ ] [T2] tests/test_new.gd — Create test; run godot --script addons/gut/gut_cmdln.gd and godot -s=addons/gut/gut.gd. VERIFY: `true`") is None)
ok("a path that merely follows other words is untouched by the -s blanking",
   W("- [ ] [T2] tests/test_new.gd — Create test for scripts/battle/battle.gd behaviour. VERIFY: `true`") == "hard-banned file scripts/battle/battle.gd")

print("== FILES: clause")
ok("FILES: before the VERIFY is honoured", W("- [ ] [T3] scripts/small.gd — add. FILES: scripts/battle/battle.gd VERIFY: `true`") == "hard-banned file scripts/battle/battle.gd")
ok("FILES: after the VERIFY is honoured too", W("- [ ] [T3] scripts/small.gd — add. VERIFY: `true`. FILES: scripts/battle/battle.gd") == "hard-banned file scripts/battle/battle.gd")
ok("GUT runner inside a FILES-less VERIFY does not trip the FILES branch", W("- [ ] [T3] tests/test_new.gd — add. VERIFY: `%s -gtest=res://tests/test_new.gd`" % RUN) is None)

print("== kill switch")
os.environ["OVN_PARK_VERIFY_SCOPE"] = "off"
ok("OVN_PARK_VERIFY_SCOPE=off restores the old whole-line scan (the F2 shape is hard-banned again)",
   W("- [ ] [T4] tests/battle/test_x.gd — Create test. VERIFY: `%s -gtest=test_x.gd`" % RUN) == "hard-banned file addons/gut/gut_cmdln.gd")
del os.environ["OVN_PARK_VERIFY_SCOPE"]

print("== scout_guard target selection")
item = "- [ ] [T4] tests/battle/test_new.gd — Create test. VERIFY: `%s -gtest=res://tests/battle/test_new.gd`" % RUN
dropped, why = P.scout_guard(root, ["tests/battle/test_new.gd", "scripts/small.gd"], item, 120000)
ok("[F2] scout-guard does not make the item UNWORKABLE because its VERIFY names the GUT runner", why is None and dropped == [], (dropped, why))
dropped, why = P.scout_guard(root, ["addons/gut/gut_cmdln.gd", "tests/battle/test_new.gd"], item, 120000)
ok("[F2] a planner-listed runner file is DROPPED from the chat but the item stays workable (its own target is a new test file)",
   [t for t, _ in dropped] == ["addons/gut/gut_cmdln.gd"] and why is None, (dropped, why))
dropped, why = P.scout_guard(root, ["scripts/battle/battle.gd"], "- [ ] [T3] scripts/battle/battle.gd — add. VERIFY: `true`", 120000)
ok("a banned item target is still UNWORKABLE in the scout guard", why == "hard-banned file scripts/battle/battle.gd", (dropped, why))

print("== CLI")
prog = os.path.join(root, "P.md")
open(prog, "w").write("\n".join([
    "- [ ] [T4] tests/battle/test_a.gd — Create test. VERIFY: `%s -gtest=res://tests/battle/test_a.gd`" % RUN,
    "- [ ] [T3] scripts/battle/battle.gd — add. VERIFY: `true`",
    "- [ ] [T2] tests/test_b.gd — Create test. VERIFY: `%s -gdir=tests/test_b.gd`" % RUN, ""]))
r = subprocess.run([sys.executable, os.path.join(QDIR, "ovn_park_unworkable.py"), prog, root], capture_output=True, text=True)
ok("park pass parks only the really-banned item", r.stdout.strip() == "PARKED=1", r.stdout + r.stderr)
body = open(prog).read()
ok("the GUT-runner items are left open and untagged", "- [ ] [T4] tests/battle/test_a.gd" in body and "- [ ] [T2] tests/test_b.gd" in body and body.count("[unworkable") == 1, body)
r = subprocess.run([sys.executable, os.path.join(QDIR, "ovn_park_unworkable.py"), "--edit-text"], input="[T4] t.gd — Create test. VERIFY: `%s -gtest=x`. (cat:test)" % RUN, capture_output=True, text=True)
ok("--edit-text prints only the text before VERIFY:", r.stdout == "[T4] t.gd — Create test. " and r.returncode == 0, repr(r.stdout))

print("park scope: %d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
