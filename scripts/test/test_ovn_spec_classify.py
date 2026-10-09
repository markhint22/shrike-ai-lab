#!/usr/bin/env python3
"""scripts/ovn_spec_classify.py + scripts/ovn_spec_check.sh (spec-compiler-v2 C1).
Part 1: classify() on synthetic (line, rc, tail) triples - the probe lines that the old regex classifier got wrong, timeouts, GUT-missing.
Part 2: the CLI helpers (canon / extract / rows).
Part 3: ovn_spec_check.sh end to end against a fixture repo (cols 1-3 unchanged, cols 4-5 added, `^(\\d+)\\t(\\w[\\w-]*)` on every row, bare VERIFY judged, GUT shim)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import ovn_spec_classify as C  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def item(target, body, verify, bare=False):
    v = ("VERIFY: %s" % verify) if bare else ("VERIFY: `%s`" % verify)
    return "- [ ] [T2] %s — %s %s. (cat:python; multifile:no)" % (target, body, v)


MODNF = "Traceback (most recent call last):   File \"<string>\", line 1, in <module> ModuleNotFoundError: No module named 'app.services.zzz_new'"
IMPERR = "Traceback (most recent call last):   File \"<string>\", line 1, in <module> ImportError: cannot import name 'foo' from 'app.services.zzz' (/x/app/services/zzz.py)"
ASSERT = "Traceback (most recent call last):   File \"<string>\", line 1, in <module> AssertionError"
NAMEERR = "Traceback (most recent call last):   File \"<string>\", line 1, in <module> NameError: name 'undefined_name_xyz' is not defined"
FNF = "Traceback (most recent call last):   File \"<string>\", line 1, in <module> FileNotFoundError: [Errno 2] No such file or directory: 'docs/new_file.md'"

print("== part 1: classify()")
V_MOD = 'python3 -c "from app.services.zzz_new import foo"'
declared = item("iptv-backend/app/services/zzz_new.py", "Create `foo()` in the new module.", V_MOD)
undeclared = item("iptv-backend/app/services/other.py", "Change the thing.", V_MOD)
ok("legit new-module import (module IS the item's target) -> red/new-target (old: bad-spec)", C.classify(declared, 1, MODNF) == ("red", "new-target"), C.classify(declared, 1, MODNF))
ok("NEGATIVE: the same import error for a module the item never mentions -> bad-spec/crash-unexplained", C.classify(undeclared, 1, MODNF) == ("bad-spec", "crash-unexplained"), C.classify(undeclared, 1, MODNF))
created = item("iptv-backend/app/routers/r.py", "Create iptv-backend/app/services/zzz_new.py with `foo()` and call it.", V_MOD)
ok("module introduced by a Create verb in the body counts as declared", C.classify(created, 1, MODNF) == ("red", "new-target"))
V_IMP = 'python3 -c "from app.services.zzz import foo"'
ok("'cannot import name' from the item's own target module -> red/new-target", C.classify(item("iptv-backend/app/services/zzz.py", "Add `foo()`.", V_IMP), 1, IMPERR) == ("red", "new-target"))
ok("NEGATIVE: 'cannot import name' from an unrelated module -> bad-spec", C.classify(item("iptv-backend/app/services/q.py", "Add `foo()`.", V_IMP), 1, IMPERR)[0] == "bad-spec")
ok("`python3 -c \"assert 1==2\"` -> red/assert (old: bad-spec, the Traceback regex matched AssertionError)", C.classify(item("a.py", "x", 'python3 -c "assert 1==2"'), 1, ASSERT) == ("red", "assert"))
ok("rc 1 with no traceback (grep miss) -> red/assert", C.classify(item("a.py", "x", "grep -q foo a.py"), 1, "") == ("red", "assert"))
ok("pytest -k selecting nothing (rc 5) -> bad-spec/no-tests-collected (old: red)", C.classify(item("a.py", "x", "pytest tests/test_a.py -k nothing"), 5, "no tests ran in 0.01s") == ("bad-spec", "no-tests-collected"))
ok("'collected 0 items' with rc 1 also -> no-tests-collected", C.classify(item("a.py", "x", "pytest tests/test_a.py"), 1, "collected 0 items") == ("bad-spec", "no-tests-collected"))
ok("pytest rc 5 when the item CREATES that test file -> red/new-target", C.classify(item("iptv-backend/tests/test_a.py", "Create the test.", "pytest iptv-backend/tests/test_a.py -q"), 5, "no tests ran") == ("red", "new-target"))
ok("pytest rc 4 'not found' for a test file the item creates -> red/new-target", C.classify(item("iptv-backend/tests/test_new.py", "Write the test.", "pytest iptv-backend/tests/test_new.py::test_x"), 4, "ERROR: not found: /w/iptv-backend/tests/test_new.py::test_x (no match in any of [<Module test_new.py>])") == ("red", "new-target"))
NF = "ERROR: not found: /w/iptv-backend/tests/test_new.py::test_x (no match in any of [<Module test_new.py>])  no tests ran in 0.01s"
ok("rc 4 'not found' followed by pytest's 'no tests ran' is a MISSING target (new-target when declared), not an empty collection", C.classify(item("iptv-backend/tests/test_new.py", "Write the test.", "pytest iptv-backend/tests/test_new.py::test_x"), 4, NF) == ("red", "new-target"))
ok("... and crash-unexplained (never no-tests-collected) when the item does not declare it", C.classify(item("iptv-backend/app/x.py", "Change.", "pytest iptv-backend/tests/test_new.py::test_x"), 4, NF) == ("bad-spec", "crash-unexplained"))
ok("NEGATIVE: pytest rc 4 for a file the item never declares -> bad-spec/crash-unexplained", C.classify(item("iptv-backend/app/x.py", "Change.", "pytest iptv-backend/tests/test_other.py::test_x"), 4, "ERROR: file or directory not found: iptv-backend/tests/test_other.py")[0] == "bad-spec")
ok("NameError inside python -c -> bad-spec/crash-unexplained", C.classify(item("a.py", "x", 'python3 -c "print(undefined_name_xyz)"'), 1, NAMEERR) == ("bad-spec", "crash-unexplained"))
ok("SyntaxError -> bad-spec/crash-unexplained", C.classify(item("a.py", "x", 'python3 -c "def"'), 1, "SyntaxError: invalid syntax") == ("bad-spec", "crash-unexplained"))
ok("FileNotFoundError for a doc the item creates -> red/new-target", C.classify(item("docs/new_file.md", "Create docs/new_file.md.", "python3 -c \"open('docs/new_file.md').read()\""), 1, FNF) == ("red", "new-target"))
ok("NEGATIVE: FileNotFoundError for an undeclared path -> bad-spec", C.classify(item("a.py", "Change.", "python3 -c \"open('docs/new_file.md').read()\""), 1, FNF)[0] == "bad-spec")
ok("rc 0 -> passes-before", C.classify(item("a.py", "x", "true"), 0, "") == ("passes-before", ""))
ok("timeout rc 124 -> bad-spec/unrunnable", C.classify(item("a.py", "x", "sleep 99"), 124, "") == ("bad-spec", "unrunnable"))
ok("rc 127 / 126 -> bad-spec/unrunnable", C.classify(item("a.py", "x", "nope"), 127, "")[1] == "unrunnable" and C.classify(item("a.py", "x", "nope"), 126, "")[1] == "unrunnable")
V_GUT = "godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_missing.gd"
gut_tail = "GUT-target-missing Totals Scripts 391 Passing Tests 2987"
ok("GUT missing target, the item creates that script -> red/new-target (shadow_check reports rc 0 behind the failure; the marker decides)", C.classify(item("tests/test_missing.gd", "Create the test.", V_GUT), 1, gut_tail) == ("red", "new-target"))
ok("... even if the raw rc is 0 (marker present, never passes-before)", C.classify(item("tests/test_missing.gd", "Create the test.", V_GUT), 0, gut_tail) == ("red", "new-target"))
ok("NEGATIVE: GUT missing target the item does not declare -> bad-spec/crash-unexplained", C.classify(item("scripts/battle.gd", "Change the thing.", V_GUT), 1, gut_tail) == ("bad-spec", "crash-unexplained"))
ok("no VERIFY at all -> no-verify", C.classify("- [ ] [T2] a.py — no clause (cat:python)", 1, "") == ("no-verify", ""))
bare = "- [ ] [T2] a.py — change it. VERIFY: python3 -c \"assert 0\". (cat:python; multifile:no)"
ok("a bare no-backtick VERIFY is judged (queue_refill._extract_verify accepts it; old classifier said no-verify)", C.classify(bare, 1, ASSERT) == ("red", "assert"))
ok("rc None -> bad-spec/no-rc", C.classify(item("a.py", "x", "true"), None, "") == ("bad-spec", "no-rc"))
ok("odd rc 2 without a recognised error -> bad-spec/crash-unexplained", C.classify(item("a.py", "x", "grep foo"), 2, "usage: grep") == ("bad-spec", "crash-unexplained"))
ok("verdict set stays inside {red, passes-before, no-verify, bad-spec}", {C.classify(l, rc, t)[0] for l, rc, t in [(declared, 1, MODNF), (bare, 0, ""), (bare, 5, ""), (bare, 124, ""), ("x", 1, "")]} <= {"red", "passes-before", "no-verify", "bad-spec"})

# mutations
_m = C.maps_onto
C.maps_onto = lambda ref, decl: True
mut = C.classify(undeclared, 1, MODNF)
C.maps_onto = _m
ok("MUTATION (maps_onto always true): the undeclared-module negative control flips to red/new-target, so it is load-bearing", mut == ("red", "new-target"))
_f = C._FATAL_VERIFY
_oe0 = C._OTHER_EXC
C._FATAL_VERIFY = re.compile(r"NEVERMATCHES")
C._OTHER_EXC = re.compile(r"NEVERMATCHES")
mut = C.classify(item("a.py", "x", 'python3 -c "print(undefined_name_xyz)"'), 1, NAMEERR)
C._FATAL_VERIFY = _f
C._OTHER_EXC = _oe0
ok("MUTATION (NameError no longer fatal): the NameError case becomes red/assert, so it is load-bearing", mut == ("red", "assert"))

# review defect (spec-compiler-v2 fixer): a VERIFY that CRASHES with another exception type is not a red assertion
for exc in ("ZeroDivisionError: division by zero", "AttributeError: 'NoneType' object has no attribute 'x'", "TypeError: unsupported operand", "KeyError: 'x'",
            "Traceback (most recent call last): File \"<string>\", line 1, in <module>"):
    ok("rc 1 + '%s' -> bad-spec/crash-unexplained (was red/assert)" % exc[:30], C.classify(item("a.py", "x", 'python3 -c "1/0"'), 1, exc) == ("bad-spec", "crash-unexplained"))
ok("rc 1 + AssertionError still red/assert even when a Traceback is printed", C.classify(item("a.py", "x", 'python3 -c "assert 0"'), 1, "Traceback (most recent call last): AssertionError") == ("red", "assert"))
ok("rc 1 + pytest failure summary without an exception name stays red/assert", C.classify(item("a.py", "x", "pytest a.py -q"), 1, "1 failed in 0.03s") == ("red", "assert"))
_oe = C._OTHER_EXC
C._OTHER_EXC = re.compile("NEVERMATCHES")
mut = C.classify(item("a.py", "x", 'python3 -c "1/0"'), 1, "ZeroDivisionError: division by zero")
C._OTHER_EXC = _oe
ok("MUTATION (other-exception detection disabled): ZeroDivisionError becomes red/assert, so the fix is load-bearing", mut == ("red", "assert"))

ok("-gdir to a file the item creates (GUT-target-missing marker) -> red/new-target",
   C.classify(item("test/battle/test_overwatch.gd", "Create the test.", "godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle/test_overwatch.gd"), 1, "GUT-target-missing x") == ("red", "new-target"))
ok("-gdir to a path the item never mentions (marker) -> bad-spec/crash-unexplained",
   C.classify(item("scripts/battle.gd", "Change.", "godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/other/test_x.gd"), 1, "GUT-target-missing x") == ("bad-spec", "crash-unexplained"))

print("== part 2: CLI helpers")
d = tempfile.mkdtemp(prefix="classify-")
try:
    f = os.path.join(d, "items.md")
    lines = [
        "# comment",
        "- [ ] [T2] a.py — backticked. VERIFY: `grep -q x a.py`. (cat:python)",
        "- [ ] [T2] b.py — bare with period. VERIFY: pytest tests/test_b.py -q. (cat:python; multifile:no)",
        "- [ ] [T2] c.py — bare plain. VERIFY: grep -q y c.py (cat:python)",
        "- [x] [T2] d.py — done bare. VERIFY: grep -q z d.py (cat:python)",
        "- [ ] [T2] e.py — prose. (cat:python)",
        "- [ ] [T2] g.py — dot arg kept. VERIFY: ls . (cat:python)",
    ]
    open(f, "w").write("\n".join(lines) + "\n")
    canon = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_spec_classify.py"), "canon", f], capture_output=True, text=True).stdout.split("\n")
    ok("canon keeps the line count", len(canon) == len(lines) + 1)
    ok("canon backticks a bare clause and drops the sentence period", "VERIFY: `pytest tests/test_b.py -q` (cat:python; multifile:no)" in canon[2], canon[2])
    ok("canon backticks a bare clause without a period", "VERIFY: `grep -q y c.py` (cat:python)" in canon[3], canon[3])
    ok("canon leaves a backticked clause, a done item and a comment alone", canon[0] == lines[0] and canon[1] == lines[1] and canon[4] == lines[4] and canon[5] == lines[5])
    ok("canon keeps a '.' that is its own argument", "VERIFY: `ls .` (cat:python)" in canon[6], canon[6])
    ex = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_spec_classify.py"), "extract"], input=lines[2] + "\n", capture_output=True, text=True).stdout.strip()
    ok("extract on a bare line returns the cleaned command", ex == "pytest tests/test_b.py -q", ex)
    ok("extract on a line without VERIFY returns empty", subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_spec_classify.py"), "extract"], input=lines[5] + "\n", capture_output=True, text=True).stdout.strip() == "")
    rows = os.path.join(d, "rows.tsv")
    open(rows, "w").write("2\tFAIL\t1\t\tAssertionError\n3\tPASS\t0\t\t\n4\tTIMEOUT\t124\tVERIFY timed out\t\n6\tNO_VERIFY_CLAUSE\t\t\t\n7\tSKIPPED_DENYLIST\t\t\t\n2\tFAIL\t0\tGUT target missing\tGUT-target-missing x\n")
    out = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "ovn_spec_classify.py"), "rows", f, rows], capture_output=True, text=True).stdout.strip().split("\n")
    cols = [o.split("\t") for o in out]
    ok("rows: every output row has 5 columns", all(len(c) == 5 for c in cols), out)
    ok("rows: FAIL rc1 -> red/assert, rc column kept", cols[0][:2] == ["2", "red"] and cols[0][3] == "assert" and cols[0][4] == "1", cols[0])
    ok("rows: PASS -> passes-before rc 0", cols[1][1] == "passes-before" and cols[1][4] == "0")
    ok("rows: TIMEOUT -> bad-spec/unrunnable rc 124", cols[2][1] == "bad-spec" and cols[2][3] == "unrunnable" and cols[2][4] == "124")
    ok("rows: NO_VERIFY_CLAUSE -> no-verify", cols[3][1] == "no-verify")
    ok("rows: denylist -> bad-spec/denylisted", cols[4][1] == "bad-spec" and cols[4][3] == "denylisted")
    ok("rows: a failure behind exit code 0 reads rc 1", cols[5][4] == "1")
    ok("rows: every row matches the supply parser regex ^(\\d+)\\t(\\w[\\w-]*)", all(re.match(r"^(\d+)\t(\w[\w-]*)", o) for o in out))
finally:
    shutil.rmtree(d, ignore_errors=True)

print("== part 3: ovn_spec_check.sh end to end")
GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]


def sh(*a, cwd=None, env=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, env=env)


def make_fixture():
    d = os.path.realpath(tempfile.mkdtemp(prefix="sc-"))
    origin = os.path.join(d, "origin.git")
    sh("git", "init", "-q", "--bare", origin)
    clone = os.path.join(d, "repos", "demo")
    os.makedirs(os.path.dirname(clone))
    sh("git", "clone", "-q", origin, clone)
    for rp, body in {"app/__init__.py": "", "app/services/__init__.py": "", "app/services/present.py": "def here():\n    return 1\n", "OVERNIGHT_PROGRESS.md": "# p\n"}.items():
        fp = os.path.join(clone, rp)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(body)
    sh(*GIT, "checkout", "-q", "-b", "overnight/feature", cwd=clone)
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "init", cwd=clone)
    sh("git", "push", "-q", "origin", "overnight/feature", cwd=clone)
    os.makedirs(os.path.join(d, "scripts"))
    for fn in ("lib_verify_clause.sh", "ovn_spec_check.sh", "lib_gut_xml.sh", "ovn_spec_classify.py", "ovn_backlog_eligibility.py"):
        if os.path.exists(os.path.join(ROOT, "scripts", fn)):
            shutil.copy(os.path.join(ROOT, "scripts", fn), os.path.join(d, "scripts"))
    return d, clone


d, clone = make_fixture()
shimhome = os.path.join(d, "home")
os.makedirs(os.path.join(shimhome, "godot"))
open(os.path.join(shimhome, "godot", "godot4"), "w").write('#!/usr/bin/env bash\necho "[ERROR]: Could not find script res://tests/test_missing.gd"\necho "Passing Tests 2987"\nexit 0\n')
os.chmod(os.path.join(shimhome, "godot", "godot4"), 0o755)
spec = os.path.join(d, "cand.md")
E2E = [
    ("red-assert", item("a.py", "x", 'python3 -c "assert 1==2"')),
    ("passes-before", item("b.py", "x", "true")),
    ("no-verify", "- [ ] [T2] c.py — no clause at all. (cat:python)"),
    ("new-module-declared", item("app/services/zzz_new.py", "Create `foo()` in the new module.", 'python3 -c "from app.services.zzz_new import foo"')),
    ("new-module-undeclared", item("app/services/present.py", "Change `here()`.", 'python3 -c "from app.services.zzz_new import foo"')),
    ("bare", "- [ ] [T2] d.py — bare clause. VERIFY: python3 -c \"assert 0\". (cat:python; multifile:no)"),
    ("nameerror", item("e.py", "x", 'python3 -c "print(undefined_name_xyz)"')),
    ("unrunnable", item("f.py", "x", "definitely_not_a_command_xyz --flag")),
    ("denylist", item("g.py", "x", "rm -rf /tmp/zzz")),
    ("timeout", item("h.py", "x", "sleep 5")),
    ("gut-declared", item("tests/test_missing.gd", "Create the test.", V_GUT)),
    ("gut-undeclared", item("scripts/battle.gd", "Change.", V_GUT)),
]
body = ["# header", "  indented skipped"] + [l for _, l in E2E] + ["- [x] [T2] done.py — skipped VERIFY: `true`. (cat:python)"]
open(spec, "w").write("\n".join(body) + "\n")
# a PRIVATE TMPDIR: the leftover check must only see this invocation's files (the global temp dir also holds live files of parallel test runs, gate scans and the
# :07/:37 ovn_work_supply cron, which made the old glob of tempfile.gettempdir() flaky)
PRIVATE_TMP = os.path.join(d, "private-tmp")
os.makedirs(PRIVATE_TMP)
env = dict(os.environ, OVN_DIR=d, VERIFY_TIMEOUT_SECS="2", HOME=shimhome, TMPDIR=PRIVATE_TMP)
r = sh("bash", os.path.join(d, "scripts", "ovn_spec_check.sh"), "demo", spec, env=env)
rows = {}
for l in r.stdout.strip().split("\n"):
    c = l.split("\t")
    if c and c[0].isdigit():
        rows[int(c[0])] = c
name_at = {3 + i: n for i, (n, _) in enumerate(E2E)}   # line numbers: header=1, indented=2, items from 3
got = {name_at[k]: (rows[k][1], rows[k][3] if len(rows[k]) > 3 else None, rows[k][4] if len(rows[k]) > 4 else None) for k in rows if k in name_at}
ok("every output row matches ^(\\d+)\\t(\\w[\\w-]*)", r.stdout.strip() and all(re.match(r"^(\d+)\t(\w[\w-]*)", l) for l in r.stdout.strip().split("\n")), r.stdout + r.stderr)
ok("every row carries 5 columns (sub col 4, rc col 5)", all(len(c) == 5 for c in rows.values()), rows)
ok("non-open lines are skipped", 1 not in rows and 2 not in rows and 3 + len(E2E) not in rows, sorted(rows))
ok("e2e red-assert: red/assert rc 1", got.get("red-assert") == ("red", "assert", "1"), got.get("red-assert"))
ok("e2e passes-before rc 0", got.get("passes-before") == ("passes-before", "", "0"), got.get("passes-before"))
ok("e2e no-verify", got.get("no-verify", ("",))[0] == "no-verify", got.get("no-verify"))
ok("e2e legit new module (declared) -> red/new-target", got.get("new-module-declared", ("", ""))[:2] == ("red", "new-target"), got.get("new-module-declared"))
ok("e2e NEGATIVE: module the item never mentions -> bad-spec/crash-unexplained", got.get("new-module-undeclared", ("", ""))[:2] == ("bad-spec", "crash-unexplained"), got.get("new-module-undeclared"))
ok("e2e bare VERIFY judged (red/assert), not no-verify", got.get("bare", ("", ""))[:2] == ("red", "assert"), got.get("bare"))
ok("e2e NameError -> bad-spec/crash-unexplained", got.get("nameerror", ("", ""))[:2] == ("bad-spec", "crash-unexplained"), got.get("nameerror"))
ok("e2e unrunnable command -> bad-spec/unrunnable rc 127", got.get("unrunnable") == ("bad-spec", "unrunnable", "127"), got.get("unrunnable"))
ok("e2e denylisted -> bad-spec/denylisted", got.get("denylist", ("", ""))[:2] == ("bad-spec", "denylisted"), got.get("denylist"))
ok("e2e timeout -> bad-spec/unrunnable rc 124", got.get("timeout") == ("bad-spec", "unrunnable", "124"), got.get("timeout"))
ok("e2e GUT missing target the item creates -> red/new-target (was passes-before)", got.get("gut-declared", ("", ""))[:2] == ("red", "new-target"), got.get("gut-declared"))
ok("e2e NEGATIVE: GUT missing target not declared -> bad-spec/crash-unexplained", got.get("gut-undeclared", ("", ""))[:2] == ("bad-spec", "crash-unexplained"), got.get("gut-undeclared"))
wts = sh("git", "worktree", "list", cwd=clone).stdout.strip().split("\n")
ok("leaves no worktree behind and the live clone untouched", len(wts) == 1 and sh("git", "status", "--porcelain", cwd=clone).stdout.strip() == "", wts)
leftovers = os.listdir(PRIVATE_TMP)
ok("temp files are cleaned up (private TMPDIR is empty after the run)", not leftovers, leftovers[:3])
ok("the check really used the private TMPDIR (it created and removed files there, not in the global temp dir)", r.returncode == 0 and "spec-check" not in r.stderr, r.stderr[-200:])
_foreign = tempfile.NamedTemporaryFile(prefix="spec-check-rows-", delete=False)   # a live file of some parallel run/cron in the GLOBAL temp dir
ok("a foreign spec-check-* file in the global temp dir is invisible to the (private) cleanup check", os.listdir(PRIVATE_TMP) == [] and os.path.exists(_foreign.name))
_foreign.close()
os.unlink(_foreign.name)

# the legacy path: no classifier beside the script -> the old regex classification, rows still carry 5 columns
d2, clone2 = make_fixture()
for fn in ("ovn_spec_classify.py", "ovn_backlog_eligibility.py"):
    os.remove(os.path.join(d2, "scripts", fn))
spec2 = os.path.join(d2, "cand.md")
open(spec2, "w").write("\n".join([item("a.py", "x", 'python3 -c "import sys;sys.exit(1)"'), item("b.py", "x", "true"), "- [ ] [T2] c — none (cat:python)", item("d.py", "x", 'python3 -c "open(\'does/not/exist.py\').read()"')]) + "\n")
r2 = sh("bash", os.path.join(d2, "scripts", "ovn_spec_check.sh"), "demo", spec2, env=dict(os.environ, OVN_DIR=d2))
legacy = {int(l.split("\t")[0]): l.split("\t") for l in r2.stdout.strip().split("\n") if l}
ok("legacy fallback: verdicts as before (red / passes-before / no-verify / bad-spec)", [legacy[i][1] for i in (1, 2, 3, 4)] == ["red", "passes-before", "no-verify", "bad-spec"], legacy)
ok("legacy fallback: still 5 columns with the rc filled", all(len(c) == 5 for c in legacy.values()) and legacy[1][4] == "1", legacy)

for x in (d, d2):
    shutil.rmtree(x, ignore_errors=True)
print("\nspec classify: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
