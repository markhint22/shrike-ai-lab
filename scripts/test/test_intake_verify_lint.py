#!/usr/bin/env python3
"""Intake package (2026-10-13): VERIFY intake lint - xlite night F4/F5, platform P3/P8.

  * ovn_gut_clause.normalize step 0: `cd /path/to/<repo> &&` placeholder dropped, `[cd D &&] godot -s <GutTest>.gd` -> the gut_cmdln form, `-gexit 0` junk
  * spec rule R16 (ingest) drops the placeholder cd but leaves `godot -s <test>` to R13; new rule R17 rejects what is left that can never run (quarantine-class, shadow by default)
  * ovn_backlog_eligibility.unrunnable_verify_reason / verify-lint CLI
  * ovn_spec_classify: GUT that ran nothing behind exit 0 is never passes-before
  * ovn_spec_gate recover-lint (ovn_recover_parked.sh): a decomposed child never inherits a VERIFY that can never run
  * ovn_spec_gate.seed_godot: the gate's worktree gets the import cache (without it GUT prints 'class_names have not been imported' and exits 0)
Mutation proofs are listed in the report (each marked [mut] case turns red when the named hunk is reverted in a scratch copy)."""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SD)
import ovn_backlog_eligibility as E  # noqa: E402
import ovn_gut_clause as G  # noqa: E402
import ovn_spec_classify as C  # noqa: E402
import ovn_spec_gate as GATE  # noqa: E402
import ovn_spec_rules as R  # noqa: E402

PASS = FAIL = 0


def ok(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  ok   " + name)
    else:
        FAIL += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


RUN = "godot --headless -s addons/gut/gut_cmdln.gd"
GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]


def mkrepo(files):
    d = tempfile.mkdtemp(prefix="intake-lint-")
    for rel, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(d, rel)), exist_ok=True)
        open(os.path.join(d, rel), "w").write(body)
    subprocess.run(["git", "-C", d, "init", "-q", "-b", "main"], check=True)
    subprocess.run(["git", "-C", d, "add", "-A"], check=True)
    subprocess.run(["git", "-C", d] + GIT[1:] + ["commit", "-qm", "x"], check=True)
    return d


FILES = {"addons/gut/gut_cmdln.gd": "x", "tests/test_a.gd": "extends GutTest\nfunc test_a():\n\tpass\n", "tests/run_x.gd": "extends SceneTree\nfunc _init():\n\tquit()\n",
         "tests/sub/test_b.gd": "extends GutTest\n", "scripts/tool.gd": "extends SceneTree\n", "tests/mission/test_mission_directive.gd": "extends GutTest\n"}
repo = mkrepo(FILES)
fs = G.DirFS(repo)
N = lambda c, **kw: G.normalize(c, fs, **kw)[0]  # noqa: E731

print("== normalize step 0a: placeholder cd")
ok("[F4] `cd /path/to/xlite && godot ... gut_cmdln` -> the cd is dropped",
   N("cd /path/to/xlite && " + RUN + " -gtest=res://tests/test_a.gd -gexit") == RUN + " -gtest=res://tests/test_a.gd -gexit")
ok("[F4] the live shape: placeholder cd + bare -gtest + -gdir=res://tests -> repaired AND resolved",
   N("cd /path/to/xlite && " + RUN + " -gdir=res://tests -gtest=test_a.gd -gexit") == RUN + " -gtest=res://tests/test_a.gd -gexit")
ok("a placeholder naming a SUB directory keeps the sub directory (`cd backend && ...`), any command", N("cd /path/to/iptv_apps/backend && pytest -q tests/x.py") == "cd backend && pytest -q tests/x.py")
ok("a quoted placeholder and a `;` separator", N("cd '/path/to/xlite'; ls") == "ls")
ok("a REAL absolute cd is never touched", N("cd /tmp && ls") == "cd /tmp && ls")
ok("a command with no placeholder is untouched", N("pytest tests/x.py -q") == "pytest tests/x.py -q")

print("== normalize step 0b: godot -s <GutTest>.gd")
GUT_A = RUN + " -gtest=res://tests/test_a.gd -gexit"
ok("[F4] `cd tests && godot --headless -s test_a.gd` (existing GutTest) -> the gut_cmdln form",
   N("cd tests && godot --headless -s test_a.gd") == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd -gexit")
ok("[F4] the live shape: a test that does not exist yet (the item creates it)",
   N("cd tests && godot --headless -s test_orphan_save_manager.gd") == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_orphan_save_manager.gd -gexit")
ok("no cd: `godot --headless -s tests/test_a.gd`", N("godot --headless -s tests/test_a.gd") == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd -gexit")
ok("res:// script path and a basename with a unique match under a sub directory", N("godot -s res://tests/sub/test_b.gd") == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/sub/test_b.gd -gexit")
ok("an absolute godot binary path is kept as the binary", N("/home/u/godot/godot4 --headless -s tests/test_a.gd").startswith("/home/u/godot/godot4 --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd"))
ok("a test file that extends SceneTree is a runnable script: untouched", N("godot --headless -s tests/run_x.gd") == "godot --headless -s tests/run_x.gd")
ok("a non-test script is untouched", N("godot --headless -s scripts/tool.gd") == "godot --headless -s scripts/tool.gd")
ok("the GUT runner itself is untouched", N(GUT_A) == GUT_A)
ok("a repo WITHOUT addons/gut is untouched (not a GUT project)", G.normalize("godot -s tests/test_zzz.gd", G.DirFS(mkrepo({"tests/other.gd": "x"})))[0] == "godot -s tests/test_zzz.gd")
ok("godot not the LAST command (cwd-dependent tail) is untouched", N("cd tests && godot --headless -s test_a.gd && echo ok") == "cd tests && godot --headless -s test_a.gd && echo ok")
ok("a cd to a directory that is itself a godot project is untouched", G.normalize("cd game && godot -s tests/test_x.gd", G.DirFS(mkrepo({"game/project.godot": "x", "addons/gut/gut_cmdln.gd": "x"})))[0] == "cd game && godot -s tests/test_x.gd")
ok("repair_script=False (what R16 uses at ingest) leaves the shape to R13", G.normalize("cd tests && godot --headless -s test_a.gd", fs, repair_script=False)[0] == "cd tests && godot --headless -s test_a.gd")
c1 = N("cd tests && godot --headless -s test_a.gd")
ok("idempotent", N(c1) == c1)
ok("needs_normalize: the three shapes and nothing else", G.needs_normalize("cd /path/to/x && ls") and G.needs_normalize("godot -s tests/t.gd") and G.needs_normalize(GUT_A) and not G.needs_normalize("pytest -q"))

print("== normalize step 0c: -gexit <junk>")
ok("[F4] `-gexit 0` -> `-gexit`", N(RUN + " -gtest=res://tests/test_a.gd -gexit 0") == GUT_A)
ok("-gexit alone untouched", N(GUT_A) == GUT_A)

print("== normalize step 0b: only a call whose every argument is understood is rewritten (reviewer minor 1)")
ok("[mut] `|| true` (the thing that made it always pass) keeps the clause unchanged", N("godot --headless -s tests/test_a.gd || true") == "godot --headless -s tests/test_a.gd || true")
ok("[mut] `--path game` is not dropped: unchanged", N("godot --headless --path game -s tests/test_a.gd") == "godot --headless --path game -s tests/test_a.gd")
ok("a pipe keeps the clause unchanged", N("godot --headless -s tests/test_a.gd | tail -5") == "godot --headless -s tests/test_a.gd | tail -5")
ok("an unknown flag before -s keeps the clause unchanged", N("godot --headless --verbose -s tests/test_a.gd") == "godot --headless --verbose -s tests/test_a.gd")
ok("an unknown trailing argument keeps the clause unchanged", N("godot --headless -s tests/test_a.gd --some-arg") == "godot --headless -s tests/test_a.gd --some-arg")
ok("[mut] `--filter <fn>` is kept as -gunit_test_name=<fn> (the 20+ historical xlite shapes)",
   N("godot --headless -s tests/test_a.gd --filter test_a") == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd -gexit -gunit_test_name=test_a")
ok("`--filter=<fn>` spelling", N("godot -s tests/test_a.gd --filter=test_a") == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd -gexit -gunit_test_name=test_a")
ok("a --filter that is not a bare function name (a glob, a phrase) keeps the clause unchanged", N("godot -s tests/test_a.gd --filter 'a b'") == "godot -s tests/test_a.gd --filter 'a b'" and N("godot -s tests/test_a.gd --filter test_*") == "godot -s tests/test_a.gd --filter test_*")
ok("`--filter` with no value, or given twice: unchanged", N("godot -s tests/test_a.gd --filter") == "godot -s tests/test_a.gd --filter" and N("godot -s tests/test_a.gd --filter a --filter b") == "godot -s tests/test_a.gd --filter a --filter b")
ok("--quiet / -q are accepted flags", N("godot --headless --quiet -s tests/test_a.gd") == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd -gexit")
ok("the --filter rewrite is idempotent", N(N("godot -s tests/test_a.gd --filter test_a")) == N("godot -s tests/test_a.gd --filter test_a"))

print("== unrunnable_verify_reason: the placeholder must be in a PATH position (reviewer minor 4)")
U0 = E.unrunnable_verify_reason
ok("[mut] a quoted docs check `grep -q '/path/to/' README.md` is NOT rejected", U0("grep -q '/path/to/' README.md") is None)
ok("a double-quoted pattern and an unquoted grep pattern are not rejected", U0('grep -c "/path/to/x" docs/a.md') is None and U0("grep -q /path/to/ README.md") is None)
ok("echo of a quoted placeholder is not rejected", U0("echo '/path/to/x' | wc -c") is None)
ok("a cd into the placeholder is still rejected (quoted or not)", bool(U0("cd /path/to/xlite && ls")) and bool(U0("cd '/path/to/xlite'; ls")))
ok("a placeholder FILE argument is still rejected", bool(U0("grep -q x /path/to/xlite/a.gd")) and bool(U0("cat /path/to/x")))
ok("a pattern-first command with a placeholder file after the pattern is still rejected", bool(U0("sed -n 1p /path/to/f")))
ok("R17 follows the same rule (a docs-check item is not quarantined; a placeholder file still is)",
   R._r17("- [ ] [T2] README.md — doc. VERIFY: `grep -q '/path/to/' README.md`. (cat:doc)") is None and R._r17("- [ ] [T2] a.gd — doc. VERIFY: `cat /path/to/a.gd`. (cat:doc)") is not None)

print("== ovn_spec_classify: a nonzero exit with a load failure of a script the item DECLARES is red-before (reviewer minor 2)")
LN_T = "- [ ] [T4] tests/battle/test_new.gd — Create test. VERIFY: `%s -gtest=res://tests/battle/test_new.gd -gexit`. (cat:test)" % RUN
BF = "- [ ] [T2] scripts/battle/new_helper.gd — Create the helper class. VERIFY: `%s -gtest=res://tests/battle/test_helper.gd -gexit`. (cat:test)" % RUN
ok("[mut] 'Failed to load script' naming the declared (not yet existing) helper -> red/new-target",
   C.classify(BF, 1, 'ERROR: Failed to load script "res://scripts/battle/new_helper.gd" with error "File not found".') == ("red", "new-target"))
ok("a Parse Error located in the declared script -> red/new-target", C.classify(BF, 1, "SCRIPT ERROR: Parse Error: x. at: GDScript::reload (res://scripts/battle/new_helper.gd:12)") == ("red", "new-target"))
ok("the TEST file failing to load stays bad-spec", C.classify(BF, 1, 'ERROR: Failed to load script "res://tests/battle/test_helper.gd" with error "Parse error".')[0] == "bad-spec")
ok("[mut] the test file the item itself DECLARES (create-test item) failing to load stays bad-spec: the test does not even parse",
   C.classify(LN_T, 1, 'ERROR: Failed to load script "res://tests/battle/test_new.gd" with error "Parse error".')[0] == "bad-spec")
ok("a script the item does NOT declare stays bad-spec", C.classify(BF, 1, 'ERROR: Failed to load script "res://scripts/other/unrelated.gd" with error "Parse error".')[0] == "bad-spec")
ok("one declared and one undeclared failing script stays bad-spec", C.classify(BF, 1, 'Failed to load script "res://scripts/battle/new_helper.gd" ... Failed to load script "res://scripts/x/y.gd"')[0] == "bad-spec")
ok("the import-cache failure is never red", C.classify(BF, 1, 'GUT-not-imported Failed to load script "res://scripts/battle/new_helper.gd"')[0] == "bad-spec")
ok("behind exit 0 it is still never passes-before and never red", C.classify(BF, 0, 'ERROR: Failed to load script "res://scripts/battle/new_helper.gd"') == ("bad-spec", "crash-unexplained"))
ok("no refs in the output: stays bad-spec", C.classify(BF, 1, "SCRIPT ERROR: Parse Error: Expected parameter name.")[0] == "bad-spec")

print("== spec rule R16 (ingest) and R17")
def item(v, target="tests/test_a.gd", body="Add a test."):
    return "- [ ] [T2] %s — %s VERIFY: `%s`. (cat:test; multifile:no)" % (target, body, v)
l = item("cd /path/to/xlite && " + GUT_A)
l2, fs2 = R.lint_static(l, only={"R16"})
ok("R16 static drops the placeholder cd (repair finding)", E.extract_verify(l2) == GUT_A and [f["rule"] for f in fs2] == ["R16"], (l2, fs2))
l = item("cd tests && godot --headless -s test_a.gd")
l2, fs2 = R.lint_static(l, only={"R16"})
ok("R16 leaves `cd tests && godot -s test_a.gd` alone: R13 owns it at ingest", l2 == l and not fs2, (l2, fs2))
ctx = R.Ctx(repo, ref="main")
rules = lambda line: [f["rule"] for f in R.lint_batch([line], ctx)[0][1]]  # noqa: E731
ok("R13 still rejects `cd tests && godot -s test_a.gd` with the repo at the ref", "R13" in rules(l), rules(l))
l = item("grep -q x /path/to/xlite/scripts/a.gd")
fr = [f for f in R.lint_batch([l], ctx)[0][1] if f["rule"] == "R17"]
ok("[P8] R17 rejects a /path/to/ placeholder R16 cannot strip", len(fr) == 1 and fr[0]["sev"] == "reject", fr)
l = item(RUN + " -gdir=res://tests -ginclude=test_a.gd -gexit")
ok("[F4] R17 rejects -ginclude= (not a GUT option)", "R17" in rules(l), rules(l))
ok("R17 stays silent on a clean GUT clause and on a clean grep", "R17" not in rules(item(GUT_A)) and "R17" not in rules(item("grep -q foo scripts/tool.gd")))
ok("R17 is not raised for a placeholder cd that R16 repaired (judged on the repaired line)", "R17" not in rules(item("cd /path/to/xlite && " + GUT_A)), rules(item("cd /path/to/xlite && " + GUT_A)))
sys.path.insert(0, os.path.join(SD, ".."))
QR = __import__("queue_refill")
ok("R17 is quarantine-class in the gate and in queue_refill, and NEVER in the default enforce set",
   "R17" in GATE.QUARANTINE_RULES and "R17" in QR.GATE_QUARANTINE_RULES and GATE.DEFAULT_ENFORCE_RULES == "R01,R11" and QR.DEFAULT_ENFORCE_RULES == "R01,R11")
ok("the gate's would-do for an R17 finding is quarantine:R17", GATE.would_do([{"rule": "R17", "sev": "reject"}], None) == "quarantine:R17")

print("== ovn_backlog_eligibility.unrunnable_verify_reason / verify-lint")
U = E.unrunnable_verify_reason
ok("placeholder", "placeholder" in (U("cd /path/to/xlite && ls") or ""))
ok("godot -s <test>.gd", "test file as a script" in (U("cd tests && godot --headless -s test_x.gd") or ""))
ok("godot -s res://tests/test_x.gd", "test file as a script" in (U("godot --headless -s res://tests/test_x.gd") or ""))
ok("the runner and a non-test script are fine", U(GUT_A) is None and U("godot --headless -s scripts/tool.gd") is None)
ok("-ginclude", "ginclude" in (U(RUN + " -ginclude=a.gd") or ""))
ok("None / empty", U(None) is None and U("") is None)
txt = "\n".join([item("cd /path/to/xlite && ls"), item(GUT_A), "- [x] [T2] done — x. VERIFY: `cd /path/to/y`", item("cd tests && godot -s test_x.gd")])
ok("verify_lint_lines flags only OPEN items whose VERIFY can never run", [n for n, _ in E.verify_lint_lines(txt)] == [1, 4], E.verify_lint_lines(txt))
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_backlog_eligibility.py"), "verify-lint"], input=txt, capture_output=True, text=True)
ok("CLI verify-lint prints '<line>\\t<reason>'", [x.split("\t")[0] for x in r.stdout.strip().split("\n")] == ["1", "4"], r.stdout + r.stderr)

print("== ovn_spec_classify: GUT that ran nothing is never passes-before")
LN = "- [ ] [T4] tests/battle/test_new.gd — Create test. VERIFY: `%s -gtest=res://tests/battle/test_new.gd -gexit`. (cat:test)" % RUN
ok("control: a clean GUT pass is passes-before", C.classify(LN, 0, "---- All tests passed! ----") == ("passes-before", ""))
ok("[P3] rc 0 + 'Could not find script' on the declared new test -> red/new-target", C.classify(LN, 0, "[ERROR]: Could not find script: res://tests/battle/test_new.gd Nothing was run.") == ("red", "new-target"))
ok("[P3] rc 0 + 'Failed to load script' -> never passes-before", C.classify(LN, 0, 'ERROR: Failed to load script "res://tests/battle/test_new.gd" with error "Parse error".')[0] == "bad-spec")
ok("[P3] rc 0 + 'Parse Error' -> bad-spec", C.classify(LN, 0, "SCRIPT ERROR: Parse Error: Expected parameter name.")[0] == "bad-spec")
ok("[P3] rc 0 + 'Tests 0' -> bad-spec", C.classify(LN, 0, "Totals Scripts 1 Tests 0")[0] == "bad-spec")
ok("[P3] 'Tests 10' is NOT 'Tests 0'", C.classify(LN, 0, "Totals Scripts 1 Tests 10 Passing 10")[0] == "passes-before")
ok("a NONZERO exit with 'Nothing was run' (X2: a not-yet-written test function) stays red/assert: a legitimate red-before is not reclassified", C.classify(LN, 1, "GUT-reported-failures [ERROR]: Nothing was run.") == ("red", "assert"))
ok("[P3] rc 1 + the runner's GUT-load-failed marker is a crash, never an assertion (red/assert)", C.classify(LN, 1, "GUT-load-failed SCRIPT ERROR: Parse Error: Expected parameter name.")[0] == "bad-spec")
ok("[P3] the runner's GUT-not-imported marker -> never passes-before", C.classify(LN, 0, "GUT-not-imported Missing class_names")[0] == "bad-spec")
ok("[P3] rc 127 (what the runner now reports for not-imported) is unrunnable", C.classify(LN, 127, "GUT-not-imported Missing class_names") == ("bad-spec", "unrunnable"))
ok("a non-GUT command that prints 'Parse Error' is still passes-before at rc 0", C.classify("- [ ] [T2] a.py — x. VERIFY: `echo Parse Error`. (cat:t)", 0, "Parse Error")[0] == "passes-before")

print("== ovn_spec_gate recover-lint")
rl_repo = mkrepo(FILES)
env = dict(os.environ, OVN_SPEC_BASE="main")


def recover(lines, mode="repair"):
    p = subprocess.run([sys.executable, os.path.join(SD, "ovn_spec_gate.py"), "recover-lint", rl_repo, mode], input="\n".join(lines) + "\n", capture_output=True, text=True, env=env)
    return p.returncode, p.stdout, p.stderr


kids = [item("cd /path/to/xlite && " + RUN + " -gdir=tests -gtest=test_a.gd -gexit"), item("cd tests && godot --headless -s test_a.gd"), item(GUT_A),
        "- [ ] [CLAUDE] escalation note (recovery:escalated)"]
rc, out, err = recover(kids)
outl = out.strip().split("\n")
ok("[F5] a child's placeholder cd + bare gtest is repaired", E.extract_verify(outl[0]) == GUT_A, outl[0])
ok("[F5] a child's `cd tests && godot -s test_a.gd` is repaired to the gut_cmdln form", E.extract_verify(outl[1]) == "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd -gexit", outl[1])
ok("a clean child and a [CLAUDE] line pass through untouched", outl[2] == kids[2] and outl[3] == kids[3] and len(outl) == 4)
ok("the repair is reported on stderr", "R16 repaired" in err, err)
bad = item("grep -q x /path/to/xlite/scripts/a.gd")
rc, out, err = recover([bad, kids[2]])
ok("repair mode KEEPS a child that still cannot run (shadow) and says so", bad in out and "kept (shadow)" in err and rc == 0, (out, err))
rc, out, err = recover([bad, kids[2]], "enforce")
ok("enforce mode DROPS it", bad not in out and kids[2] in out and "DROPPED" in err and rc == 0, (out, err))
rc, out, err = recover([bad], "enforce")
ok("enforce mode with nothing left exits 3 (the caller escalates)", rc == 3 and out.strip() == "", (rc, out))
rc, out, err = recover(kids, "off")
ok("off echoes the input", out.strip() == "\n".join(kids), out)
p = subprocess.run([sys.executable, os.path.join(SD, "ovn_spec_gate.py"), "recover-lint", "/nonexistent-dir-xyz", "repair"], input=kids[2] + "\n", capture_output=True, text=True, env=env)
ok("a missing repo degrades to the input (never loses a decomposition)", kids[2] in p.stdout and p.returncode == 0, (p.stdout, p.stderr))

print("== ovn_spec_gate.seed_godot")
if shutil.which("rsync") and subprocess.run("printf 'a\\0' | grep -zq a", shell=True).returncode == 0:
    sg = tempfile.mkdtemp(prefix="seedgodot-")
    clone = os.path.join(sg, "clone")
    os.makedirs(os.path.join(clone, ".godot", "imported"))
    open(os.path.join(clone, "project.godot"), "w").write("config_version=5\n")
    open(os.path.join(clone, ".gitignore"), "w").write(".godot/\n*.import\n")
    open(os.path.join(clone, ".godot", "global_script_class_cache.cfg"), "w").write("cache")
    open(os.path.join(clone, ".godot", "imported", "a.ctex"), "w").write("x")
    subprocess.run(["git", "-C", clone, "init", "-q", "-b", "main"], check=True)
    subprocess.run(["git", "-C", clone, "add", "-A"], check=True)
    subprocess.run(["git", "-C", clone] + GIT[1:] + ["commit", "-qm", "x"], check=True)
    wt = os.path.join(sg, "wt")
    subprocess.run(["git", "-C", clone, "worktree", "add", "-q", "--detach", wt, "main"], check=True)
    ok("a fresh worktree has no import cache", not os.path.exists(os.path.join(wt, ".godot")))
    ok("seed_godot copies .godot into the worktree", GATE.seed_godot(sg, clone, wt) and os.path.isfile(os.path.join(wt, ".godot", "global_script_class_cache.cfg")))
    ok("... it is a COPY, not a symlink", not os.path.islink(os.path.join(wt, ".godot")) and not os.path.islink(os.path.join(wt, ".godot", "imported", "a.ctex")))
    wt2 = os.path.join(sg, "wt2")
    subprocess.run(["git", "-C", clone, "worktree", "add", "-q", "--detach", wt2, "main"], check=True)
    os.environ["OVN_SPEC_GATE_SEED_GODOT"] = "off"
    ok("OVN_SPEC_GATE_SEED_GODOT=off disables it", GATE.seed_godot(sg, clone, wt2) is False and not os.path.exists(os.path.join(wt2, ".godot")))
    del os.environ["OVN_SPEC_GATE_SEED_GODOT"]
    ok("a repo without project.godot is skipped (no slow ignored-file walk)", GATE.seed_godot(sg, repo, wt2) is False)
    # end to end through open_worktree (what `scan` calls): the gate's worktree of origin/<branch> gets the cache
    org = os.path.join(sg, "origin.git")
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", org], check=True)
    subprocess.run(["git", "-C", clone, "remote", "add", "origin", org], check=True)
    subprocess.run(["git", "-C", clone, "push", "-q", "origin", "main"], check=True)
    subprocess.run(["git", "-C", clone, "fetch", "-q", "origin"], check=True)
    gwt = GATE.open_worktree(sg, clone, "main")
    ok("open_worktree (the scan path) returns a worktree that already carries the .godot import cache",
       bool(gwt) and os.path.isfile(os.path.join(gwt or "/nonexistent", ".godot", "global_script_class_cache.cfg")), gwt)
    if gwt:
        GATE.close_worktree(sg, clone, gwt)
else:
    print("  skip seed_godot (rsync / grep -z unavailable on this host)")

print("intake verify lint: %d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
