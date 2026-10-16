#!/usr/bin/env python3
"""R18 (spec-intake-5-lanes, 2026-10-13): an item that CREATES a test file whose VERIFY only greps the CONTENT of that file.

Replay: xlite 1b2478ce VERIFY `grep -q 'assert_eq("Raider"' tests/test_unit_display_name.gd` while the real (passing) test is assert_eq(u.display_name(), "Raider") -> credit refused,
10 rows / 447k tokens fleet-wide for this class. Proposed repair: RUN the file (pytest <file> -q, or the GUT form through ovn_gut_clause), which proves the test exists AND passes.
SHADOW by default: a 'flag' finding that carries the proposed VERIFY, the line is not touched; OVN_SPEC_R18=repair rewrites; =off silences the rule.
All repository reads are at a ref (a committed branch); the fixture working tree is dirtied to prove it is never read."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
sys.path.insert(0, ROOT)
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_spec_classify as C  # noqa: E402
import ovn_spec_rules as R  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


def item(target, text, verify, cat="test", feat=None):
    s = "- [ ] [T2] %s — %s VERIFY: %s (cat:%s; multifile:no)" % (target, text, verify, cat)
    return s + (" [feat:%s]" % feat if feat else "")


def mk_repo(files, branch="main"):
    work = os.path.realpath(tempfile.mkdtemp(prefix="r18-"))
    repo = os.path.join(work, "repo")
    os.makedirs(repo)
    git = lambda *a: subprocess.run(["git", "-C", repo] + list(a), capture_output=True, text=True)  # noqa: E731
    git("init", "-q")
    git("checkout", "-q", "-b", branch)
    for rp, body in files.items():
        fp = os.path.join(repo, rp)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(body)
    git("add", "-A")
    subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "init"], capture_output=True)
    return work, repo


def r18(line, ctx):
    l2, f = R._r18(line, ctx)
    return l2, f


for k in ("OVN_SPEC_R18", "OVN_SPEC_R19", "OVN_SPEC_GATE_ENFORCE_RULES"):
    os.environ.pop(k, None)

GODOT = {
    "project.godot": "config_version=5\n",
    "addons/gut/gut_cmdln.gd": "extends SceneTree\n",
    "scripts/unit/unit.gd": "func display_name():\n\treturn name\n",
    "tests/test_existing.gd": "extends GutTest\nfunc test_a():\n\tassert_true(true)\n",
}
PY = {
    "backend/app/svc.py": "def f():\n    return 1\n",
    "backend/tests/test_existing.py": "def test_a():\n    assert True\n",
    "backend/tests/__init__.py": "",
}
work_g, repo_g = mk_repo(GODOT)
work_p, repo_p = mk_repo(PY)
open(os.path.join(repo_g, "tests/test_unit_display_name.gd"), "w").write("worktree only\n")       # never seen: reads are at the ref
open(os.path.join(repo_p, "backend/tests/test_new.py"), "w").write("def test_x():\n    pass\n")
cg, cp = R.Ctx(repo_g, "main"), R.Ctx(repo_p, "main")

GUT_CMD = "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_unit_display_name.gd -gexit"
X = item("tests/test_unit_display_name.gd", "Create tests/test_unit_display_name.gd with a GUT test for Unit.display_name().", "`grep -q 'assert_eq(\"Raider\"' tests/test_unit_display_name.gd`.", "godot")

print("== R18 SHADOW (default): flag with the proposal, the line is untouched")
l2, f = r18(X, cg)
ok("xlite 1b2478ce: flagged, line unchanged", l2 == X and f and f["rule"] == "R18" and f["sev"] == "flag", (l2, f))
ok("the finding carries the proposed GUT VERIFY and action=rewrite", f and f["evidence"]["proposed"] == GUT_CMD and f["evidence"]["action"] == "rewrite" and "grep -q" in f["evidence"]["verify"], f)
ok("finding shape rule/sev/msg/evidence", f and set(f) == {"rule", "sev", "msg", "evidence"})
ok("lint_batch in shadow does not mutate the line and records exactly one R18 flag", R.lint_batch([X], cg)[0][0] == X and [x["rule"] for x in R.lint_batch([X], cg)[0][1] if x["rule"] == "R18"] == ["R18"])
ok("R18 is not a static rule: lint_static (queue_refill / planner) never touches it", R.lint_static(X) == (X, []))
ok("R18 is not in the default enforce set of the gate or queue_refill", "R18" not in __import__("ovn_spec_gate").DEFAULT_ENFORCE_RULES and "R18" not in __import__("queue_refill").DEFAULT_ENFORCE_RULES)

print("== R18 repair mode")
os.environ["OVN_SPEC_R18"] = "repair"
l2, f = r18(X, cg)
ok("godot: the VERIFY is rewritten to the GUT run of the very file", l2 != X and E.extract_verify(l2) == GUT_CMD == C.verify_of(l2), l2)
ok("godot: sev repair, text outside the VERIFY untouched", f and f["sev"] == "repair" and l2.startswith(X.split("VERIFY:")[0]) and l2.endswith("(cat:godot; multifile:no)"), (l2, f))
ok("godot: the repaired line is clean for every other rule (no R16/R17/R13 finding, R12 sees the declared file)", [x["rule"] for x in R.lint_batch([l2], cg)[0][1]] == [], R.lint_batch([l2], cg)[0][1])
ok("godot: idempotent (the repaired line has no grep left)", r18(l2, cg) == (l2, None))
ok("lint_batch applies it when repair is on", R.lint_batch([X], cg)[0][0] == l2)
PYL = item("backend/tests/test_new.py", "Create unit tests for f().", "`grep -c 'def test_' backend/tests/test_new.py`.")
l2, f = r18(PYL, cp)
ok("py: `grep -c 'def test_' file` -> pytest <file> -q", E.extract_verify(l2) == "pytest backend/tests/test_new.py -q" and f["sev"] == "repair", (l2, f))
l2, f = r18(item("backend/tests/test_new.py", "Create tests.", "`grep -q 'def test_a' backend/tests/test_new.py && grep -q 'def test_b' backend/tests/test_new.py`."), cp)
ok("py: two greps of the same file collapse into ONE run", E.extract_verify(l2) == "pytest backend/tests/test_new.py -q", l2)
l2, f = r18(item("backend/tests/test_new.py", "Create tests.", "`cd backend && grep -q 'def test_a' tests/test_new.py`."), cp)
ok("py: a cd prefix is kept, the operand stays as written", E.extract_verify(l2) == "cd backend && pytest tests/test_new.py -q", l2)
l2, f = r18(item("backend/app/svc.py", "Add f2() and create backend/tests/test_new.py covering it.", "`grep -q 'def test_f2' backend/tests/test_new.py`."), cp)
ok("py: the item creates the test file through a Create path in its body (target is production code)", E.extract_verify(l2) == "pytest backend/tests/test_new.py -q", (l2, f))
l2, f = r18(item("backend/tests/test_new.py", "Create tests.", "`grep -qE 'def test_(a|b)' ./backend/tests/test_new.py`."), cp)
ok("py: ./ prefix and -E flag are understood", E.extract_verify(l2) == "pytest backend/tests/test_new.py -q", l2)
os.environ.pop("OVN_SPEC_R18")

print("== NEGATIVES (any mode): the rule says nothing")
os.environ["OVN_SPEC_R18"] = "repair"
NEG = [
    ("the test file ALREADY exists at the ref (the item edits it)", item("backend/tests/test_existing.py", "Add a test case.", "`grep -q 'def test_b' backend/tests/test_existing.py`."), cp),
    ("grep of a PRODUCTION file (iptv 0732ca62 shape: api.post<Recording>(...) breaks the literal; R18 is not that rule)",
     item("iptv-web/src/stores/recordings.ts", "Post the recording.", "`grep -q \"api.post('/downloads/dvr/record'\" iptv-web/src/stores/recordings.ts`.", "typescript"), cp),
    ("grep of the created test file AND another file", item("backend/tests/test_new.py", "Create tests.", "`grep -q 'def test_a' backend/tests/test_new.py && grep -q 'f(' backend/app/svc.py`."), cp),
    ("an absence check (! grep)", item("backend/tests/test_new.py", "Create tests.", "`! grep -q 'skip' backend/tests/test_new.py`."), cp),
    ("a pipe after the grep", item("backend/tests/test_new.py", "Create tests.", "`grep -c 'def test_' backend/tests/test_new.py | wc -l`."), cp),
    ("the VERIFY already runs the test", item("backend/tests/test_new.py", "Create tests.", "`pytest backend/tests/test_new.py -q`."), cp),
    ("a value-taking grep flag (-e PAT) is not understood", item("backend/tests/test_new.py", "Create tests.", "`grep -q -e 'def test_a' backend/tests/test_new.py`."), cp),
    ("a redirect", item("backend/tests/test_new.py", "Create tests.", "`grep -q 'def test_a' backend/tests/test_new.py > /tmp/x`."), cp),
    ("an item that creates no test file", item("backend/app/new_mod.py", "Create new_mod.", "`grep -q 'def g' backend/app/new_mod.py`.", "python"), cp),
    ("a GUT test in a repo without addons/gut (no GUT form to propose)", X, R.Ctx(repo_p, "main")),
    ("a bare (unbackticked) VERIFY: R01 backticks it first", item("backend/tests/test_new.py", "Create tests.", "grep -q 'def test_a' backend/tests/test_new.py"), cp),
]
for name, l, c in NEG:
    ok("NEGATIVE %s" % name, r18(l, c) == (l, None), r18(l, c))
ok("no ctx (lint_static / planner): nothing", R._r18(X, None) == (X, None))
os.environ["OVN_SPEC_R18"] = "off"
ok("OVN_SPEC_R18=off: silent even on the canonical case", r18(X, cg) == (X, None))
ok("an unknown mode value falls back to shadow (flag only)", (os.environ.__setitem__("OVN_SPEC_R18", "bogus"), r18(X, cg)[0] == X and r18(X, cg)[1]["sev"] == "flag")[1])
os.environ.pop("OVN_SPEC_R18")

print("== a mixed batch: only the matching item is judged, order and the other items are untouched")
other = item("backend/tests/test_existing.py", "Add a test case.", "`grep -q 'def test_b' backend/tests/test_existing.py`.")
out = R.lint_batch([other, PYL, "# header"], cp)
ok("lint_batch keeps one entry per line in order", [o[0] for o in out] == [other, PYL, "# header"])
ok("R18 flags only the creating item", [x["rule"] for x in out[0][1] if x["rule"] == "R18"] == [] and [x["rule"] for x in out[1][1] if x["rule"] == "R18"] == ["R18"])

for w in (work_g, work_p):
    shutil.rmtree(w, ignore_errors=True)
print("\nR18: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
