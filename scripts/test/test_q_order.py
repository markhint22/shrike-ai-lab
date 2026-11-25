#!/usr/bin/env python3
"""q-order (2026-11-24): four pipeline changes, each with a regression check that FAILS on the old behaviour (mutant batteries at the bottom).

  1 CLASSIFY  ovn_classify_fail.sh    status no-op(fixup-undid-item) -> fail_reason `fixup-undone` (was timeout/test-red/unknown from the log scan). Pure bugfix, ON; OVN_CLASSIFY_FIXUP_UNDONE=off.
  2 DEFER     ovn_verify_defer.py +   a GUT VERIFY clause whose -gtest file is the deliverable of a LATER open sibling step is DEFERRED (probe passed -> PASS why=gut-target-deferred), never FAIL.
              lib_verify_clause.sh    OVN_VERIFY_DEFER=off|shadow|enforce (default enforce = the probe-carrying clause), OVN_VERIFY_DEFER_ONLY (probe-less clause, default shadow).
  3 STRIP     ovn_stub_guard.py       leftover whole-line `Placeholder - the implement step fills this in` above real code is stripped by default (OVN_STUB_STRIP=shadow|off reverts).
  4 TFMS      ovn_test_first_source   `precision` measure of the shadow rule against outcomes (the rule itself stays SHADOW).
The wrapper test_q_order.sh gives this a fail-closed private TMPDIR and a perl `timeout` shim on the Mac."""
import hashlib
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.path.abspath(os.path.join(HERE, ".."))
Q = os.path.abspath(os.path.join(SD, ".."))
sys.path.insert(0, HERE)
import tmp_track  # noqa: E402
tmp_track.install()
for _k in [k for k in os.environ if k.startswith(("OVN_VERIFY_", "OVN_CLASSIFY_", "OVN_STUB_", "OVN_TEST_FIRST", "OVN_TFMS"))]:
    del os.environ[_k]
os.environ.update({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t", "NTFY_SERVER": "http://127.0.0.1:9", "OVN_NOTIFY_DISABLE": "1", "TZ": "UTC", "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1"})

T = tempfile.mkdtemp(prefix="qord-")
PASS = FAIL = 0
_N = [0]


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


def sh(cmd, cwd=None, env=None):
    e = dict(os.environ)
    e.update(env or {})
    return subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, cwd=cwd, env=e, timeout=120)


def mk(root, rel, text=""):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def clone_tree(dst, subs=None):
    """a private copy of the pipeline files this test exercises: dst/ovn_classify_fail.sh, dst/ovn_test_first_source.py, dst/scripts/*.{sh,py}"""
    os.makedirs(os.path.join(dst, "scripts"))
    for f in ("ovn_classify_fail.sh", "ovn_test_first_source.py", "ovn_gate_evidence_report.py"):
        shutil.copy(os.path.join(Q, f), os.path.join(dst, f))
    for f in os.listdir(SD):
        if f.endswith((".sh", ".py")):
            shutil.copy(os.path.join(SD, f), os.path.join(dst, "scripts", f))


PROG = (
    "- [ ] [T1] scripts/battle/overkill_text.gd — Add `static func wasted_text`. VERIFY: `{clause}`. (cat:gdscript) [feat:xlite-ovk]\n"
    "- [ ] [T2] tests/test_overkill_text_wasted.gd — Create the test file for wasted_text. VERIFY: `echo ok`. (cat:test) [feat:xlite-ovk]\n"
)
GOOD_CLAUSE = ("grep -q 'static func wasted_text' scripts/battle/overkill_text.gd && echo \"Could not find script res://tests/test_overkill_text_wasted.gd Nothing was run\" "
               "gut_cmdln.gd -gtest=res://tests/test_overkill_text_wasted.gd")
NOPROBE_CLAUSE = "echo \"Could not find script res://tests/test_overkill_text_wasted.gd Nothing was run\" gut_cmdln.gd -gtest=res://tests/test_overkill_text_wasted.gd"


def verify(root, prog_text, clause_vars=None, env=None, tree_files=None):
    """run shadow_check on line 1 of prog_text in a fresh tree; -> (result, why, shadow-log text, defer-log text)"""
    _N[0] += 1
    t = os.path.join(T, "v%d" % _N[0])
    os.makedirs(t)
    for rel, txt in (tree_files if tree_files is not None else {"scripts/battle/overkill_text.gd": "static func wasted_text(x):\n\treturn 1\n"}).items():
        mk(t, rel, txt)
    mk(t, "OVERNIGHT_PROGRESS.md", prog_text)
    script = ('. "%s/scripts/lib_verify_clause.sh"; export PROG="$PWD/OVERNIGHT_PROGRESS.md" SHADOW_LOG="$PWD/slog" _REPO_LABEL=xlite; shadow_check 1; '
              'echo "RESULT=$_LAST_VERIFY_RESULT WHY=$_LAST_VERIFY_WHY"') % root
    r = sh(script, cwd=t, env=env)
    m = re.search(r"RESULT=(\S*) WHY=(.*)", r.stdout)
    rd = lambda n: open(os.path.join(t, n)).read() if os.path.exists(os.path.join(t, n)) else ""
    return (m.group(1) if m else "ERR:" + r.stderr[-200:]), (m.group(2) if m else ""), rd("slog"), rd("verify_defer_shadow.log")


STRIP_PY = '"""Placeholder - the implement step fills this in."""\n"""Tests for the thing."""\nimport pytest\n\n\ndef test_a():\n    assert 1\n'


def checks(root):
    """-> {name: bool}; every entry must be True on the real tree and the named ones flip on the mutants"""
    R = {}
    # ---- 1 classify
    log = os.path.join(T, "cl.log")
    open(log, "w").write("--- fixup round ---\nbuild gate: timed out waiting; FAILED tests/x.py::t 2 failed\n")
    cf = os.path.join(root, "ovn_classify_fail.sh")
    R["C1 fixup-undid-item -> fixup-undone (not timeout/test-red)"] = sh("bash '%s' '%s' 'no-op(fixup-undid-item)'" % (cf, log)).stdout.strip() == "fixup-undone"
    R["C2 OVN_CLASSIFY_FIXUP_UNDONE=off restores the log scan (timeout)"] = sh("bash '%s' '%s' 'no-op(fixup-undid-item)'" % (cf, log), env={"OVN_CLASSIFY_FIXUP_UNDONE": "off"}).stdout.strip() == "timeout"
    R["C3 control: no-op(net-zero) and reverted-red unchanged"] = (sh("bash '%s' '%s' 'no-op(net-zero)'" % (cf, log)).stdout.strip() == "net-zero"
                                                                   and sh("bash '%s' '%s' 'no-op(reverted-red)'" % (cf, log)).stdout.strip() == "test-red")
    # ---- 2 defer: pure module
    D = load(os.path.join(root, "scripts", "ovn_verify_defer.py"), "vd_%d" % _N[0])
    _N[0] += 1
    lines = PROG.format(clause=GOOD_CLAUSE).split("\n")
    empty = os.path.join(T, "empty")
    os.makedirs(empty, exist_ok=True)
    R["D1 later open sibling creates the missing test -> DEFER-ARTIFACT"] = D.check(lines, 1, GOOD_CLAUSE, empty).startswith("DEFER-ARTIFACT")
    R["D2 a target no sibling creates (hallucinated path) is NOT deferred"] = D.check(lines, 1, GOOD_CLAUSE.replace("tests/test_overkill_text_wasted.gd", "xlite/tests/test_nope.gd"), empty).startswith("NO")
    parked = [lines[0], lines[1].replace("- [ ]", "- [ ] [AUTO-SKIP x]"), ""]
    R["D3 a PARKED later sibling does not count"] = D.check(parked, 1, GOOD_CLAUSE, empty).startswith("NO")
    earlier = [lines[1], lines[0], ""]
    R["D4 an EARLIER sibling does not count (only later steps are deferred to)"] = D.check(earlier, 2, GOOD_CLAUSE, empty).startswith("NO")
    R["D5 no probe in the clause -> DEFER-ONLY"] = D.check(lines, 1, NOPROBE_CLAUSE, empty).startswith("DEFER-ONLY")
    other = [lines[0], lines[1].replace("[feat:xlite-ovk]", "[feat:other]"), ""]
    R["D6 a sibling of ANOTHER feature does not count"] = D.check(other, 1, GOOD_CLAUSE, empty).startswith("NO")
    present = os.path.join(T, "present")
    mk(present, "tests/test_overkill_text_wasted.gd", "extends GutTest\n")
    R["D7 a target that exists is never deferred"] = D.check(lines, 1, GOOD_CLAUSE, present).startswith("NO")
    # ---- 2 defer: through shadow_check
    p = PROG.format(clause=GOOD_CLAUSE)
    res, why, slog, dlog = verify(root, p)
    R["D8 shadow_check: probe passed + later sibling creates the test -> PASS why=gut-target-deferred (credit not refused)"] = res == "PASS" and why == "gut-target-deferred" and "kind=DEFER-ARTIFACT action=enforce" in dlog and "why=gut-target-deferred" in slog
    res, why, slog, dlog = verify(root, p, env={"OVN_VERIFY_DEFER": "off"})
    R["D9 OVN_VERIFY_DEFER=off restores FAIL (GUT target missing)"] = res == "FAIL" and "GUT-target-missing" in slog and dlog == ""
    res, why, slog, dlog = verify(root, p, env={"OVN_VERIFY_DEFER": "shadow"})
    R["D10 OVN_VERIFY_DEFER=shadow logs the would-defer row but keeps FAIL"] = res == "FAIL" and "action=shadow" in dlog
    res, why, slog, dlog = verify(root, PROG.format(clause=GOOD_CLAUSE).split("\n")[0] + "\n")
    R["D11 no later sibling creates the test -> still FAIL"] = res == "FAIL" and dlog == ""
    res, why, slog, dlog = verify(root, p, tree_files={"scripts/battle/overkill_text.gd": "# the step never added the function\n"})
    R["D12 the step's own artifact missing (probe fails) -> FAIL, never credited"] = res == "FAIL"
    res, why, slog, dlog = verify(root, PROG.format(clause=NOPROBE_CLAUSE))
    R["D13 probe-less clause: default shadow keeps FAIL, row logged DEFER-ONLY"] = res == "FAIL" and "kind=DEFER-ONLY action=shadow" in dlog
    res, why, slog, dlog = verify(root, PROG.format(clause=NOPROBE_CLAUSE), env={"OVN_VERIFY_DEFER_ONLY": "enforce"})
    R["D14 probe-less clause under OVN_VERIFY_DEFER_ONLY=enforce is UNRUNNABLE (indeterminate: not FAIL, not credited)"] = res == "UNRUNNABLE"
    bad = GOOD_CLAUSE.replace('echo "Could not find script res://tests/test_overkill_text_wasted.gd Nothing was run"', "printf 'Could not find script\\nNothing was run\\n[Failed]: res://tests/test_other.gd\\n'")
    res, why, slog, dlog = verify(root, PROG.format(clause=bad))
    R["D15 a clause whose output also reports a real [Failed] is never deferred"] = res == "FAIL"
    # ---- 2b defer: probe must be ONE simple command (review 2026-11-24 BLOCKER)
    TGT = "-gtest=res://tests/test_overkill_text_wasted.gd"
    def dclause(pre):
        return "%s && godot --headless -s addons/gut/gut_cmdln.gd %s -gexit" % (pre, TGT)
    R["D16 valid shape `grep -q 'static func X' file && godot -gtest=missing` still DEFER-ARTIFACT"] = D.check(lines, 1, dclause("grep -q 'static func wasted_text' scripts/battle/overkill_text.gd"), empty).startswith("DEFER-ARTIFACT")
    R["D16b `test -f f` and `[ -f f ]` probes still DEFER-ARTIFACT"] = all(D.check(lines, 1, dclause(x), empty).startswith("DEFER-ARTIFACT") for x in ("test -f scripts/battle/overkill_text.gd", "[ -f scripts/battle/overkill_text.gd ]"))
    R["D17 `grep -q x f | cat && godot` is NOT DEFER-ARTIFACT"] = not D.check(lines, 1, dclause("grep -q 'x' f | cat"), empty).startswith("DEFER-ARTIFACT")
    R["D18 `cd . && godot` is NOT DEFER-ARTIFACT"] = not D.check(lines, 1, dclause("cd ."), empty).startswith("DEFER-ARTIFACT")
    R["D19 `true && godot` is NOT DEFER-ARTIFACT"] = not D.check(lines, 1, dclause("true"), empty).startswith("DEFER-ARTIFACT")
    R["D20 probe with `;` / `||` / command substitution / backticks is NOT DEFER-ARTIFACT"] = not any(
        D.check(lines, 1, dclause(x), empty).startswith("DEFER-ARTIFACT") for x in ("grep -q x f; true", "grep -q x f || true", "grep -q $(echo x) f", "grep -q `echo x` f", "grep -q x f &"))
    R["D20b a quoted `|` / `&&` inside the grep pattern is not an operator (still DEFER-ARTIFACT)"] = D.check(lines, 1, dclause("grep -q 'a|b' f"), empty).startswith("DEFER-ARTIFACT")
    # through shadow_check: a broken source never defers
    for tag, outtxt in (("D21 Parse Error", "Parse Error: Expected expression"), ("D22 Failed to load script", "Failed to load script res://scripts/battle/overkill_text.gd"), ("D22b SCRIPT ERROR", "SCRIPT ERROR: Invalid call. Nonexistent function")):
        broken = GOOD_CLAUSE.replace('&& echo "Could not find script', '&& echo "%s Could not find script' % outtxt)
        res, why, slog, dlog = verify(root, PROG.format(clause=broken))
        R["%s in the clause output: never deferred, FAIL stays FAIL" % tag] = res == "FAIL" and dlog == ""
    res, why, slog, dlog = verify(root, PROG.format(clause=GOOD_CLAUSE.replace("grep -q 'static func wasted_text' scripts/battle/overkill_text.gd", "grep -q 'static func wasted_text' scripts/battle/overkill_text.gd | cat")))
    R["D23 shadow_check: `grep ... | cat && godot` is not credited as deferred (FAIL, no enforce row)"] = res == "FAIL" and "action=enforce" not in dlog
    # ---- 3 strip default
    SG = load(os.path.join(root, "scripts", "ovn_stub_guard.py"), "sg_%d" % _N[0])
    _N[0] += 1
    r = os.path.join(T, "sg%d" % _N[0])
    os.makedirs(r)
    mk(r, "backend/tests/test_x.py", STRIP_PY)
    sh("git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm i", cwd=r)
    notes = []
    out = SG.strip_filled(r, "backend/tests/test_x.py", "", notes.append)
    body = open(os.path.join(r, "backend/tests/test_x.py")).read()
    R["S1 default mode strips the leftover marker in a follow-up commit, real code untouched"] = out == "stripped" and "Placeholder" not in body and "def test_a" in body and body.startswith('"""Tests for the thing."""')
    os.environ["OVN_STUB_STRIP"] = "shadow"
    try:
        mk(r, "backend/tests/test_y.py", STRIP_PY)
        sh("git add -A && git -c user.email=t@t -c user.name=t commit -qm y", cwd=r)
        R["S2 OVN_STUB_STRIP=shadow restores log-only"] = SG.strip_filled(r, "backend/tests/test_y.py", "", notes.append) == "strip-shadow" and "Placeholder" in open(os.path.join(r, "backend/tests/test_y.py")).read()
    finally:
        os.environ.pop("OVN_STUB_STRIP")
    only = '"""Placeholder - the implement step fills this in."""\n'
    R["S3 a marker-only file is never touched (undo's job)"] = SG.strip_marker_text(only) == (only, 0)
    gd = "# Placeholder - the implement step fills this in.\nextends GutTest\n\nfunc test_a():\n\tassert_true(true)\n"
    R["S4 gd comment form stripped, code kept"] = SG.strip_marker_text(gd) == ("extends GutTest\n\nfunc test_a():\n\tassert_true(true)\n", 1)
    # ---- 3b strip: indented sole-body markers (review 2026-11-24 ADVISORY)
    ind_py = 'def test_a():\n    """Placeholder - the implement step fills this in."""\n\n\ndef test_b():\n    assert 1\n'
    R["S5 indented sole-body docstring in a python def is left alone (no IndentationError)"] = SG.strip_marker_text(ind_py, "t.py") == (ind_py, 0)
    ind_cm = 'class T:\n    # Placeholder - the implement step fills this in\n\n\nx = 1\n'
    R["S6 indented sole-body comment in a python class is left alone"] = SG.strip_marker_text(ind_cm, "t.py") == (ind_cm, 0)
    ind_gd = "extends GutTest\n\nfunc test_a():\n\t# Placeholder - the implement step fills this in\n\nfunc test_b():\n\tassert_true(true)\n"
    R["S7 indented sole-body marker in a gdscript func is left alone"] = SG.strip_marker_text(ind_gd, "t.gd") == (ind_gd, 0) and SG.strip_marker_text(ind_gd) == (ind_gd, 0)
    ind_ok = 'def test_a():\n    # Placeholder - the implement step fills this in\n    assert 1\n'
    R["S8 indented marker with a non-empty remaining python block is stripped"] = SG.strip_marker_text(ind_ok, "t.py") == ('def test_a():\n    assert 1\n', 1)
    R["S9 column-0 marker stripped as before (py / gd / no path)"] = (SG.strip_marker_text(STRIP_PY, "t.py")[1] == 1 and SG.strip_marker_text(gd, "t.gd")[1] == 1 and SG.strip_marker_text(gd)[1] == 1)
    bom = "\ufeff" + 'import os\n# Placeholder - the implement step fills this in\n\n\ndef f():\n    return os.sep\n'
    crlf = '# Placeholder - the implement step fills this in\r\nimport os\r\n\r\ndef f():\r\n    return 1\r\n'
    shebang = '#!/usr/bin/env python3\n# Placeholder - the implement step fills this in\nimport os\n'
    R["S10 BOM / CRLF / shebang / module-docstring cases still strip cleanly"] = (
        (SG.strip_marker_text(bom, "t.py")[1] == 1 and "Placeholder" not in SG.strip_marker_text(bom, "t.py")[0]
         and SG.strip_marker_text(crlf, "t.py") == ('import os\r\n\r\ndef f():\r\n    return 1\r\n', 1)
         and SG.strip_marker_text(shebang, "t.py") == ('#!/usr/bin/env python3\nimport os\n', 1)
         and SG.strip_marker_text(STRIP_PY, "t.py")[0].startswith('"""Tests for the thing."""')))
    # py_compile gate: a column-0 strip that would break the file (marker docstring is the ONLY thing before an indented block) is skipped and logged
    R["S11 py_compile gate: a strip that turns a compiling file into a non-compiling one is skipped"] = (
        SG._py_compiles("if True:\n    x = 1\n", "t.py") and SG.strip_marker_text('def f():\n    """Placeholder - the implement step fills this in."""\n', "t.py")[1] == 0)
    r2 = os.path.join(T, "sg2_%d" % _N[0])
    os.makedirs(r2)
    mk(r2, "backend/tests/test_z.py", ind_py)
    sh("git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm i", cwd=r2)
    R["S12 strip_filled on an indented sole-body marker: nothing committed, file unchanged"] = (
        SG.strip_filled(r2, "backend/tests/test_z.py", "", notes.append) == "strip-none" and open(os.path.join(r2, "backend/tests/test_z.py")).read() == ind_py
        and sh("git rev-list --count HEAD", cwd=r2).stdout.strip() == "1")
    # ---- 3c gate evidence report consumer: fixup-undone is a bad outcome
    GE = load(os.path.join(root, "ovn_gate_evidence_report.py"), "ge_%d" % _N[0])
    _N[0] += 1
    R["G1 fixup-undone is in BAD_FAIL_REASONS and a no-op row with it is a bad outcome"] = (
        "fixup-undone" in GE.BAD_FAIL_REASONS and GE.outcome_kind({"class": "noop", "status": "no-op(fixup-undid-item)", "fail_reason": "fixup-undone"}) == "bad"
        and GE.outcome_kind({"class": "noop", "status": "no-op(net-zero)", "fail_reason": "net-zero"}) != "bad")
    # ---- 4 precision measure
    TF = load(os.path.join(root, "ovn_test_first_source.py"), "tf_%d" % _N[0])
    _N[0] += 1
    mkline = lambda i: "- [ ] [T2] src/__tests__/m%d.test.ts — Add test %d. VERIFY: `x`. [feat:f]" % (i, i)
    ilh = lambda l: hashlib.md5(re.sub(r"^- \[[ xX]\]\s?", "", l).encode()).hexdigest()
    rows = [{"repo": "r", "ts": "2026-11-24T00:00:00Z", "line": i, "test": "t%d" % i} for i in range(1, 7)]
    outs = [{"ts": "2026-11-24T01:00:00Z", "item_line_hash": ilh(mkline(1)), "class": "reverted", "fail_reason": "ts-regression"},
            {"ts": "2026-11-24T01:00:00Z", "item_line_hash": ilh(mkline(2)), "class": "noop", "fail_reason": "test-red"},
            {"ts": "2026-11-24T01:00:00Z", "item_line_hash": ilh(mkline(3)), "class": "landed", "fail_reason": ""},
            {"ts": "2026-11-24T01:00:00Z", "item_line_hash": ilh(mkline(4)), "class": "noop", "fail_reason": "landed"},
            {"ts": "2026-11-23T01:00:00Z", "item_line_hash": ilh(mkline(5)), "class": "landed", "fail_reason": ""}]   # row 5: outcome BEFORE the hit, ignored
    pr = TF.precision(rows, outs, lambda r: mkline(r["line"]) if r["line"] != 6 else "")
    R["T1 precision counts: 2 confirmed, 1 false-positive, 1 neutral, 1 unexecuted (outcome before the hit ignored), 1 unknown-line"] = (
        pr["counts"] == {"confirmed": 2, "false-positive": 1, "neutral": 1, "unexecuted": 1, "unknown-line": 1} and pr["precision"] == 0.667 and pr["enforce_ready"] is False)
    many = [{"repo": "r", "ts": "2026-11-24T00:00:00Z", "line": i, "test": "t"} for i in range(1, 13)]
    mouts = [{"ts": "2026-11-24T01:00:00Z", "item_line_hash": ilh(mkline(i)), "class": "reverted", "fail_reason": "ts-regression"} for i in range(1, 13)]
    pm = TF.precision(many, mouts, lambda r: mkline(r["line"]))
    R["T2 enforce_ready only with n>=10 and zero false positives"] = pm["enforce_ready"] is True and pm["precision"] == 1.0 and TF.precision(many[:9], mouts[:9], lambda r: mkline(r["line"]))["enforce_ready"] is False
    fp = mouts[:10] + [{"ts": "2026-11-24T01:00:00Z", "item_line_hash": ilh(mkline(11)), "class": "landed", "fail_reason": ""}]
    R["T2b ten confirmed plus ONE false positive is not enforce_ready"] = TF.precision(many[:11], fp, lambda r: mkline(r["line"]))["enforce_ready"] is False
    R["T3 the rule itself has no enforce mode (shadow/off only)"] = 'in ("off", "shadow")' in open(os.path.join(root, "ovn_test_first_source.py")).read()
    return R


def report(tag, R, expect_all=True, flip=()):
    global PASS, FAIL
    for name, ok in R.items():
        if expect_all:
            if ok:
                PASS += 1
                print("  ok   %s" % name)
            else:
                FAIL += 1
                print("  FAIL %s" % name)
    return R


# ------------------------------------------------------------------ real tree
real = os.path.join(T, "real")
clone_tree(real)
R0 = report("real", checks(real))

# ------------------------------------------------------------------ mutants: each must turn the named checks red
MUTANTS = [
    ("classifier tag removed", "ovn_classify_fail.sh", '*"no-op(fixup-undid-item"*)         if', '*"no-op(fixup-undid-item-X"*)         if', ["C1"]),
    ("classifier switch ignored", "ovn_classify_fail.sh", '${OVN_CLASSIFY_FIXUP_UNDONE:-on}" != off ]; then echo "fixup-undone"', '${OVN_CLASSIFY_FIXUP_UNDONE:-on}" != OFFX ]; then echo "fixup-undone"', ["C2"]),
    ("defer: any sibling counts (even earlier)", "scripts/ovn_verify_defer.py", 'for l in prog_lines[ln:] if OPEN', 'for l in prog_lines if OPEN', ["D4"]),
    ("defer: parked sibling counts", "scripts/ovn_verify_defer.py", "if OPEN.match(l) and not PARKED.search(l) and", "if OPEN.match(l) and", ["D3"]),
    ("defer: sibling of another feature counts", "scripts/ovn_verify_defer.py", '("[feat:%s]" % feat) in l]', '"[feat:" in l]', ["D6"]),
    ("defer: existing target deferred", "scripts/ovn_verify_defer.py", 'if not missing:\n        return "NO target-exists"', "if False:\n        return 'x'", ["D7"]),
    ("defer: hallucinated target deferred", "scripts/ovn_verify_defer.py", "        if t not in leads:\n            return", "        if False:\n            return", ["D2", "D11"]),
    ("defer: probe-less treated as artifact", "scripts/ovn_verify_defer.py", "artifact = _has_artifact_probe(pre)", "artifact = True", ["D5", "D13"]),
    ("verify: deferral never applied", "scripts/lib_verify_clause.sh", 'if [ "$_dact" = enforce ] && [ "$_dvk" = DEFER-ARTIFACT ]; then', 'if false; then', ["D8"]),
    ("verify: kill switch ignored", "scripts/lib_verify_clause.sh", 'local _dmode="${OVN_VERIFY_DEFER:-enforce}"', 'local _dmode=enforce', ["D9", "D10"]),
    ("verify: default shadow", "scripts/lib_verify_clause.sh", 'local _dmode="${OVN_VERIFY_DEFER:-enforce}"', 'local _dmode="${OVN_VERIFY_DEFER:-shadow}"', ["D8"]),
    ("verify: defers even when the output has a real failure", "scripts/lib_verify_clause.sh", '! _verify_gut_output_failed "$(grep -av \'Nothing was run\' <<< "$out")" && ', "", ["D15"]),
    ("verify: probe-less enforce ignored", "scripts/lib_verify_clause.sh", "elif [ \"$_dact\" = enforce ]; then\n            rc=127", "elif false; then\n            rc=127", ["D14"]),
    ("strip: default shadow", "scripts/ovn_stub_guard.py", 'os.environ.get("OVN_STUB_STRIP", "enforce")', 'os.environ.get("OVN_STUB_STRIP", "shadow")', ["S1"]),
    ("strip: eats a marker-only stub", "scripts/ovn_stub_guard.py", "    if is_placeholder_only(text):\n        return text, 0\n    is_py", "    is_py", ["S3"]),
    ("strip: indented marker stripped in python regardless of the gate", "scripts/ovn_stub_guard.py", "if n and is_py and not _py_compiles(new, path):", "if False:", ["S11"]),
    ("strip: indented marker stripped in non-python", "scripts/ovn_stub_guard.py", "if body[:1] in (\" \", \"\\t\") and not is_py:", "if False:", ["S7"]),
    ("strip: nothing indented ever stripped", "scripts/ovn_stub_guard.py", "if body[:1] in (\" \", \"\\t\") and not is_py:", "if body[:1] in (\" \", \"\\t\"):", ["S8"]),
    ("defer: any && prefix is a probe (old rule)", "scripts/ovn_verify_defer.py", "artifact = _has_artifact_probe(pre)", 'artifact = "&&" in pre and ";" not in pre and "||" not in pre and bool(pre.split("&&")[0].strip())', ["D17", "D18", "D19", "D23"]),
    ("defer: probe may contain a pipe", "scripts/ovn_verify_defer.py", 'elif c in ";|&\\n\\r":\n            return None', 'elif c in ";&\\n\\r":\n            return None', ["D17", "D23"]),
    ("defer: probe command not checked", "scripts/ovn_verify_defer.py", "    return all(_simple_probe(s) for s in segs[:-1])", "    return all(s.strip() for s in segs[:-1])", ["D18", "D19"]),
    ("defer: command substitution allowed", "scripts/ovn_verify_defer.py", 'elif c == "`" or (c == "$" and text[i + 1:i + 2] == "("):\n            return None\n        elif q == \'"\':', 'elif q == \'"\':', ["D20"]),
    ("verify: Parse Error output still deferred", "scripts/lib_verify_clause.sh", " && ! grep -aEq 'Parse Error|Failed to load script|SCRIPT ERROR' <<< \"$out\"; then", "; then", ["D21", "D22"]),
    ("verify: SCRIPT ERROR not in the guard", "scripts/lib_verify_clause.sh", "Parse Error|Failed to load script|SCRIPT ERROR' <<< \"$out\"; then", "Parse Error|Failed to load script' <<< \"$out\"; then", ["D22b"]),
    ("report: fixup-undone not a bad fail_reason", "ovn_gate_evidence_report.py", '"test-red", "fixup-undone"}', '"test-red"}', ["G1"]),
    ("precision: false positives not counted", "ovn_test_first_source.py", 'elif cls == "landed":\n                v = "false-positive"', 'elif cls == "landed":\n                v = "neutral"', ["T1", "T2"]),
    ("precision: enforce_ready ignores false positives", "ovn_test_first_source.py", 'judged >= 10 and res["false-positive"] == 0', "judged >= 10", ["T2b"]),
    ("precision: outcomes before the hit counted", "ovn_test_first_source.py", 'if str(o.get("ts", "")) >= str(r.get("ts", "")))', 'if True)', ["T1"]),
]
MP = MF = 0
for i, (name, rel, old, new, flips) in enumerate(MUTANTS):
    mroot = os.path.join(T, "mut%d" % i)
    clone_tree(mroot)
    path = os.path.join(mroot, rel)
    src = open(path).read()
    if old not in src:
        FAIL += 1
        print("  FAIL mutant %-55s: anchor not found in %s" % (name, rel))
        continue
    open(path, "w").write(src.replace(old, new, 1))
    try:
        RM = checks(mroot)
    except Exception as e:  # a mutant that breaks the module outright is killed too
        RM = {k: False for k in R0}
        print("    (mutant raised %s)" % type(e).__name__)
    red = [k for k, v in RM.items() if not v]
    killed = any(any(k.startswith(f + " ") for f in flips) for k in red)
    if killed:
        MP += 1
        print("  ok   mutant killed: %-52s -> red: %s" % (name, ", ".join(k.split(" ")[0] for k in red)))
    else:
        MF += 1
        FAIL += 1
        print("  FAIL mutant SURVIVED: %-50s (expected %s red)" % (name, flips))
    shutil.rmtree(mroot, ignore_errors=True)

print("\ntest_q_order: %d checks passed, %d failed; mutants killed %d/%d" % (PASS, FAIL, MP, len(MUTANTS)))
shutil.rmtree(T, ignore_errors=True)
sys.exit(1 if FAIL else 0)
