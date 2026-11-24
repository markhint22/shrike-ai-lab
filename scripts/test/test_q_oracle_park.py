#!/usr/bin/env python3
"""q-oracle-park (2026-11-24): three pipeline changes + the build-break park decision.

  GU1        ovn_verify_shape_lint.py  GUT run piped into `grep` for a pass-claim GUT never prints ('0 failing', 'Failing: 0', 'Passed: N')  -> rewrite to `grep -q "All tests passed"`.
             ENFORCE by default (pure bugfix, corpus replay 0 false positives); revert: OVN_VERIFY_Z1_GU1=shadow|off.
  IMPORTS    ovn_scout_ground.py       first-party python modules named in the item / imported by the planned source files are ADDED to the planner FILES; SHADOW by default (OVN_SCOUT_IMPORTS).
  TFMS       ovn_test_first_source.py  TEST-FIRST-MISSING-SOURCE guard, SHADOW only (OVN_TEST_FIRST_SOURCE=off disables).
  BB PARK    lib_build_break_park.sh   stays SHADOW (precision 66% < 80%, false parks > 0): static + synthetic precision checks.

Every source mutant of the three modules must turn the core assertions red (counts printed). The wrapper test_q_oracle_park.sh gives it a fail-closed private TMPDIR."""
import importlib.util
import json
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
for _k in [k for k in os.environ if k.startswith(("OVN_VERIFY_", "OVN_SCOUT_", "OVN_TEST_FIRST", "OVN_TFMS"))]:
    del os.environ[_k]
os.environ.update({"NTFY_SERVER": "http://127.0.0.1:9", "OVN_NOTIFY_DISABLE": "1", "TZ": "UTC"})

T = tempfile.mkdtemp(prefix="qor-")
BANG = chr(33)
GREEN = "---- Totals ----\nScripts          1\nTests            3\n  Passing        3\nAsserts          5\n\n---- All tests passed" + BANG + " ----\n"
RED = "---- Totals ----\nScripts          1\nTests            3\n  Passing        1\n  Failing        2\n\n---- 2 failing tests ----\n"
G = "~/godot/godot4 --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_x.gd -gexit"
GOOD = 'grep -q "All tests passed"'

PASS = FAIL = 0
MUT_PASS = MUT_FAIL = 0


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


def mk(root, rel, text=""):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def git_repo(name, files):
    r = os.path.join(T, name)
    os.makedirs(r)
    for rel, txt in files.items():
        mk(r, rel, txt)
    subprocess.run("git init -q && git add -A && git -c user.email=t@t -c user.name=t commit -qm i", shell=True, cwd=r, check=True, env=dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null"))
    return r


# stub godot / godot4: print GREEN / RED / nothing by $GODOT_MODE
STUB = os.path.join(T, "bin")
os.makedirs(STUB)
for nm, txt in (("green.txt", GREEN), ("red.txt", RED)):
    with open(os.path.join(STUB, nm), "w") as f:
        f.write(txt)
for nm in ("godot", "godot4"):
    with open(os.path.join(STUB, nm), "w") as f:
        f.write('#!/bin/bash\ncase "$GODOT_MODE" in green) cat "%s/green.txt";; red) cat "%s/red.txt";; esac\n' % (STUB, STUB))
    os.chmod(os.path.join(STUB, nm), 0o755)


def run_clause(clause, mode):
    env = dict(os.environ, PATH=STUB + ":" + os.environ["PATH"], GODOT_MODE=mode, HOME=STUB)
    r = subprocess.run(["bash", "-c", clause.replace("~/godot/godot4", "godot4")], capture_output=True, text=True, timeout=30, env=env, cwd=T)
    return r.returncode


def check(name, cond, sink, extra=""):
    sink.append((name, bool(cond), extra))


def core(L, SG, TF, lbl):
    """-> list of (name, ok, extra). Pure function of the three modules (original or a mutant)."""
    out = []
    env0 = {k: os.environ.pop(k) for k in list(os.environ) if k.startswith(("OVN_VERIFY_", "OVN_SCOUT_", "OVN_TEST_FIRST", "OVN_TFMS"))}

    def codes(c):
        return [f["code"] for f in L.lint_verify(c, None, None)["findings"] if f["class"] != L.OK]

    def rw(c):
        return next((f["rewrite"] for f in L.lint_verify(c, None, None)["findings"] if f["code"] == "GU1"), None)
    # ---- GU1 flagged shapes
    flagged = {
        "q0": (G + ' | grep -q "0 failing"', G + " | " + GOOD),
        "sq": (G + " | grep -q '0 failing'", G + " | " + GOOD),
        "nq": (G + ' | grep "0 failing"', G + " | " + GOOD),
        "fl": (G + ' 2>&1 | grep -q "Failing: 0"', G + " 2>&1 | " + GOOD),
        "pa": (G + " | grep -q 'Passed: 3'", G + " | " + GOOD),
        "ic": (G + ' | grep -qi "0 failing tests"', G + " | " + GOOD),
        "tl": (G + ' | tail -20 | grep -q "Passed: 2"', G + " | tail -20 | " + GOOD),
        "pre": ("grep -q 'static func x' a.gd && " + G + ' | grep -q "0 failing"', "grep -q 'static func x' a.gd && " + G + " | " + GOOD),
        "gut": ('gut -gdir=res://tests | grep -q "0 failing"', "gut -gdir=res://tests | " + GOOD),
        "g3": ('godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit | grep -q "0 failing"', 'godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit | ' + GOOD),
    }
    for k, (c, want) in flagged.items():
        check("GU1 flags+rewrites [%s]" % k, rw(c) == want and "GU1" in codes(c), out, "%r -> %r" % (c, rw(c)))
    # ---- silent shapes
    silent = {
        "correct": G + " | " + GOOD,
        "npassed_can_match": G + ' | grep -q "3 passed"',
        "negated": "! " + G + ' | grep -q "0 failing"',
        "alt": G + ' | grep -E -q "0 failing|All tests passed"',
        "passing": G + ' | grep -q "Passing"',
        "not_gut": 'pytest -q | grep -q "0 failing"',
        "count": G + ' | grep -c "0 failing"',
        "vacuous_or": G + ' | grep -q "0 failing" || true',
        "file_arg": G + ' | grep -q "0 failing" out.txt',
        "zero_passed": G + ' | grep -q "Passed: 0"',
        "middle_head": G + ' | head -3 | grep -q "0 failing"',
        "plain_godot": "godot --headless --check-only res://a.gd | grep -q '0 failing'",
    }
    for k, c in silent.items():
        check("GU1 silent [%s]" % k, "GU1" not in codes(c), out, c)
    # ---- behaviour: the old clause cannot pass, the rewritten one tracks GUT's real result
    old = G + ' | grep -q "0 failing"'
    new = rw(old) or old
    check("old clause fails on a GREEN run (the defect)", run_clause(old, "green") != 0, out)
    check("rewritten clause passes on a GREEN run", run_clause(new, "green") == 0, out)
    check("rewritten clause fails on a RED run", run_clause(new, "red") != 0, out)
    check("rewritten clause fails on an empty run (crash)", run_clause(new, "none") != 0, out)
    check("no exclamation mark in any rewrite", all(BANG not in (rw(c) or "") for c, _w in flagged.values()), out)
    # the green-sample guard is the second line of defence if the claim family is ever widened: a widened family that matches GUT's real success line must stay silent
    _save = L._GU1_CLAIM
    L._GU1_CLAIM = re.compile(r"all tests passed|" + _save.pattern, re.I)
    check("GU1 green-sample guard: a widened family never flags the real success grep", "GU1" not in codes(G + " | " + GOOD), out)
    L._GU1_CLAIM = _save
    # ---- policy / switches
    check("GU1 is a Z1 code and defaults to enforce", "GU1" in L.Z1_CODES and L.z1_mode("GU1") == "enforce", out)
    line = "- [ ] [T2] tests/test_x.gd - add the test. VERIFY: `" + old + "`. (cat:test; multifile:no) [feat:f1]"
    d, outline, _r = L.lint_item_line(line, None, "shadow")
    check("default: item REWRITTEN at creation even while OVN_VERIFY_LINT=shadow", d == "rewritten" and GOOD in outline and "0 failing" not in outline, out, "%s %s" % (d, outline))
    os.environ["OVN_VERIFY_Z1_GU1"] = "shadow"
    d, outline, _r = L.lint_item_line(line, None, "shadow")
    check("OVN_VERIFY_Z1_GU1=shadow reverts to flag-only (text unchanged)", d == "flagged" and outline == line, out, d)
    os.environ["OVN_VERIFY_Z1_GU1"] = "off"
    d, outline, _r = L.lint_item_line(line, None, "shadow")
    check("OVN_VERIFY_Z1_GU1=off: not even flagged", d == "ok" and outline == line, out, d)
    os.environ.pop("OVN_VERIFY_Z1_GU1")
    os.environ["OVN_VERIFY_Z1"] = "shadow"
    d, outline, _r = L.lint_item_line(line, None, "shadow")
    check("group switch OVN_VERIFY_Z1=shadow also reverts", d == "flagged" and outline == line, out, d)
    os.environ.pop("OVN_VERIFY_Z1")
    d, outline, _r = L.lint_item_line(line, None, "off")
    check("OVN_VERIFY_LINT=off disables everything", d == "ok" and outline == line, out, d)
    # advisory 1: only OPEN `- [ ]` item lines are rewritten; [x]/[~] lines and prose quoting a clause stay byte-identical
    for lbl2, pre in (("done [x]", "- [x] "), ("parked [~]", "- [~] "), ("prose", "Note: "), ("quoted prose", "  > see: "), ("bare", "")):
        ln2 = pre + "[T2] tests/test_x.gd - add the test. VERIFY: `" + old + "`. (cat:test; multifile:no) [feat:f1]"
        d, outline, _r = L.lint_item_line(ln2, None, "shadow")
        check("lint_item_line leaves a non-open line untouched (%s)" % lbl2, d == "ok" and outline == ln2 and _r is None, out, "%s %s" % (d, outline))
    d, outline, _r = L.lint_item_line("  - [ ] [T2] tests/test_x.gd - add the test. VERIFY: `" + old + "`. (cat:test; multifile:no) [feat:f1]", None, "shadow")
    check("lint_item_line still rewrites an indented open item", d == "rewritten" and GOOD in outline, out, d)
    # the planner/supply path (process_lines) rewrites too
    os.environ["OVN_VERIFY_SHAPE_LOG"] = os.path.join(T, "vsl-%s.log" % lbl)
    os.environ["OVN_VERIFY_ALERTS_LOG"] = os.path.join(T, "vsl-alerts-%s.log" % lbl)
    _se = sys.stderr
    sys.stderr = open(os.devnull, "w")
    try:
        kept, dropped, n = L.process_lines([line, "- [ ] [T1] a.py - x. VERIFY: `true`. (cat:t) [feat:f1]"], None, repo="xlite", where="planner")
    finally:
        sys.stderr.close()
        sys.stderr = _se
    check("process_lines (planner / supply / generate hook path) rewrites + keeps both items", n == 1 and not dropped and GOOD in kept[0] and len(kept) == 2, out, str(kept))
    for k in ("OVN_VERIFY_SHAPE_LOG", "OVN_VERIFY_ALERTS_LOG"):
        os.environ.pop(k, None)

    # ---- IMPORTS (scout grounding)
    repo = git_repo("scout-%s" % lbl, {"backend/app/main.py": "from app.config import settings\nfrom .store import Store\nfrom app.big import Huge\n", "backend/app/config.py": "settings = 1\n",
                                       "backend/app/store.py": "class Store: pass\n", "backend/app/big.py": "x = 1\n" + "#" * 9000 + "\n", "backend/app/__init__.py": "", "backend/tests/test_x.py": "",
                                       "backend/app/other.py": "y=1\n"})
    log = "x\nFILES: backend/app/main.py backend/tests/test_x.py\n"
    item = "wire the router into main; do not touch app.other"

    def ground(env=None, itm=item):
        old_env = {k: os.environ.get(k) for k in (env or {})}
        os.environ.update(env or {})
        import io
        buf, sys_err = io.StringIO(), sys.stderr
        sys.stderr = buf
        try:
            rows = SG._run(repo, log, itm, 120000)
        finally:
            sys.stderr = sys_err
            for k, v in old_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
        return rows, buf.getvalue()
    rows, err = ground()
    adds = [r[1] for r in rows if r[0] == "ADD"]
    check("IMPORTS default SHADOW: adds nothing", adds == [], out, str(rows))
    check("IMPORTS shadow reports what enforce would add (config + store, not the 9 KB module)", "scout-import-shadow" in err and "backend/app/config.py" in err and "backend/app/store.py" in err and "big.py" not in err, out, err)
    rows, err = ground({"OVN_SCOUT_IMPORTS": "enforce"})
    adds = [r[1] for r in rows if r[0] == "ADD"]
    check("IMPORTS enforce adds config.py + store.py (absolute + relative import), never the oversized one", sorted(adds) == ["backend/app/config.py", "backend/app/store.py"], out, str(rows))
    rows, err = ground({"OVN_SCOUT_IMPORTS": "off"})
    check("IMPORTS off: nothing and no report", [r for r in rows if r[0] == "ADD"] == [] and "scout-import-shadow" not in err, out, err)
    rows, err = ground({"OVN_SCOUT_IMPORTS": "enforce"}, "add the route; from app.other import y")
    check("IMPORTS item-text import named: added", "backend/app/other.py" in [r[1] for r in rows if r[0] == "ADD"], out, str(rows))
    rows, err = ground({"OVN_SCOUT_IMPORTS": "enforce", "OVN_SCOUT_MAX_EXTRA": "1"})
    check("IMPORTS shares the OVN_SCOUT_MAX_EXTRA cap", len([r for r in rows if r[0] == "ADD"]) == 1, out, str(rows))
    lg = os.path.join(T, "imp-%s.tsv" % lbl)
    ground({"OVN_SCOUT_IMPORT_SHADOW_LOG": lg})
    check("IMPORTS shadow log row", os.path.exists(lg) and "backend/app/config.py" in open(lg).read(), out)
    # a clean tree / an unplanned plan is never rescued
    rows, err = SG.ground(repo, "x\nFILES: NONE\n", item), ""
    check("IMPORTS: no workable plan => still no ADD (ungrounded plan not rescued)", [r for r in rows if r[0] == "ADD"] == [], out)

    # ---- TFMS (test-first missing source)
    ts_repo = git_repo("tf-%s" % lbl, {"iptv-web/src/api/other.ts": "export const a = 1\n", "iptv-web/src/api/__tests__/nowPlayingTexts.test.ts": "import { f } from '../nowPlayingTexts'\nimport { a } from '@/api/other'\n",
                                       "backend/app/__init__.py": "", "backend/app/real.py": "x=1\n", "backend/tests/test_a.py": "from app.real import x\nfrom app.gone import y\n"})
    prog = os.path.join(T, "P-%s.md" % lbl)

    def scan(text, repo_dir=ts_repo, env=None):
        with open(prog, "w") as f:
            f.write(text)
        before = open(prog).read()
        st = os.path.join(T, "st-%s-%d" % (lbl, len(os.listdir(T))))
        if env is None and text == getattr(scan, "_last", None):
            st = scan._st   # an identical repeat scan shares the journal (dedupe check)
        scan._last, scan._st = text, st
        old_env = {k: os.environ.get(k) for k in (env or {})}
        os.environ.update(env or {})
        os.environ["OVN_TFMS_LOG"] = os.path.join(st, "tf.log")
        import io
        buf, so = io.StringIO(), sys.stdout
        sys.stdout = buf
        try:
            rows = TF.scan(prog, repo_dir, "iptv_apps", st)
        finally:
            sys.stdout = so
            os.environ.pop("OVN_TFMS_LOG", None)
            for k, v in old_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
        return rows, buf.getvalue(), before == open(prog).read(), os.path.join(st, "tf.log")
    T1 = "- [x] (retired-dead-path) [T1] iptv-web/src/api/nowPlayingTexts.ts - Add `loadNowPlayingTexts` VERIFY: `true`. (cat:typescript) [feat:f1]\n"
    T2 = "- [ ] [T2] iptv-web/src/api/__tests__/nowPlayingTexts.test.ts - Add test VERIFY: `true`. (cat:test) [feat:f1]\n"
    rows, printed, same, lgp = scan(T1 + T2)
    check("TFMS fires: test imports a source no open step creates (retired T1)", len(rows) == 1 and rows[0]["missing"] == "iptv-web/src/api/nowPlayingTexts.ts" and "TEST-FIRST-MISSING-SOURCE" in printed, out, printed)
    check("TFMS shadow never edits the progress file", same, out)
    check("TFMS row is logged as JSON with the rule name", os.path.exists(lgp) and json.loads(open(lgp).read().split("\n")[0])["rule"] == "TEST-FIRST-MISSING-SOURCE", out)
    rows2, printed2, _s, _l = scan(T1 + T2)
    check("TFMS dedupes a repeat scan of the same (line, missing)", len(rows2) == 0 and printed2 == "", out)
    # a creator step earlier in the same group that is OPEN exempts it
    CRE = "- [ ] [T1] iptv-web/src/api/nowPlayingTexts.ts - Add `loadNowPlayingTexts` VERIFY: `true`. (cat:typescript) [feat:f1]\n"
    rows, printed, _s, _l = scan(CRE + T2)
    check("TFMS silent when an earlier OPEN step creates the module", rows == [], out, printed)
    rows, printed, _s, _l = scan(T2 + CRE)
    check("TFMS fires when the creator step comes AFTER the test step", len(rows) == 1, out, printed)
    rows, printed, _s, _l = scan(T1 + T2.replace("- [ ] [T2]", "- [ ] [AUTO-SKIP x] [T2]"))
    check("TFMS silent for a parked test step", rows == [], out)
    rows, printed, _s, _l = scan(CRE.replace("- [ ]", "- [ ] [CLAUDE]") + T2)
    check("TFMS: a parked creator does not exempt", len(rows) == 1, out)
    mk(ts_repo, "iptv-web/src/api/nowPlayingTexts.ts", "export const f = 1\n")
    rows, printed, _s, _l = scan(T1 + T2)
    check("TFMS silent once the source exists", rows == [], out)
    os.remove(os.path.join(ts_repo, "iptv-web/src/api/nowPlayingTexts.ts"))
    PY = "- [ ] [T2] backend/tests/test_a.py - Add test VERIFY: `true`. (cat:test) [feat:f2]\n"
    rows, printed, _s, _l = scan(PY)
    check("TFMS python: `from app.gone import y` flagged, `from app.real import x` not", [r["missing"] for r in rows] == ["backend/app/gone.py"], out, str(rows))
    rows, printed, _s, _l = scan(T1 + T2, env={"OVN_TEST_FIRST_SOURCE": "off"})
    check("TFMS off: no rows", rows == [], out)
    sib = "- [x] (retired-dead-path) [T1] iptv-web/src/api/zzz.ts - Add f VERIFY: `true`. (cat:t) [feat:f3]\n- [ ] [T2] iptv-web/src/api/__tests__/zzz.test.ts - Create test file VERIFY: `true`. (cat:test) [feat:f3]\n"
    rows, printed, _s, _l = scan(sib)
    check("TFMS sibling evidence: test file not yet created, group planned the source", [r["kind"] for r in rows] == ["sibling"], out, str(rows))
    rows, printed, _s, _l = scan("- [ ] [T2] iptv-web/src/api/__tests__/zzz.test.ts - Create test file VERIFY: `true`. (cat:test) [feat:f9]\n")
    check("TFMS no group evidence + no file: silent (conservative)", rows == [], out)
    try:
        with open(prog, "wb") as f:
            f.write(b"\xff\xfe- [ ] \x00 garbage\n" * 50)
        TF.scan(prog, ts_repo, "r", os.path.join(T, "stg"))
        TF.scan(os.path.join(T, "nope.md"), ts_repo, "r", os.path.join(T, "stg"))
        TF.scan(prog, os.path.join(T, "no-such-root"), "r", os.path.join(T, "stg"))
        ok_never = True
    except Exception as e:  # noqa
        ok_never = False
    check("TFMS never raises on garbage / missing files", ok_never, out)
    # advisory 3: bounded dedupe read + atomic trim of the log
    big = os.path.join(T, "tfbig-%s.log" % lbl)
    rowj = lambda i: json.dumps({"repo": "iptv_apps", "line_hash": "h%d" % i, "missing": "m%d" % i, "n": i})
    with open(big, "w") as f:
        f.write("\n".join(rowj(i) for i in range(6000)) + "\n")
    check("TFMS log trim: 6000 lines -> trimmed to last 4000", TF._trim_log(big) is True and len(open(big).read().split("\n")) - 1 == 4000 and json.loads(open(big).read().split("\n")[0])["n"] == 2000, out)
    check("TFMS log trim: no tmp file left behind", [x for x in os.listdir(T) if x.startswith("tfbig-%s.log.tmp" % lbl)] == [], out)
    with open(big, "w") as f:
        f.write("\n".join(rowj(i) for i in range(5000)) + "\n")
    check("TFMS log trim: exactly 5000 lines is left alone", TF._trim_log(big) is False and len(open(big).read().split("\n")) - 1 == 5000, out)
    # dedupe window = last 4000 lines only: a key in the first 1000 of 5000 is forgotten, one in the last 4000 is remembered
    with open(big, "w") as f:
        f.write("\n".join(rowj(i) for i in range(5000)) + "\n")
    os.environ["OVN_TFMS_LOG"] = big
    try:
        seen_old = TF.scan.__globals__["json"]  # noqa (keeps json bound)
        pr = os.path.join(T, "P-win-%s.md" % lbl)
        with open(pr, "w") as f:
            f.write("- [ ] [T2] iptv-web/src/api/__tests__/nowPlayingTexts.test.ts - Add test VERIFY: `true`. (cat:test) [feat:f1]\n")
        ln0 = open(pr).read().split("\n")[0]
        hh = TF._h(ln0)
        with open(big, "a") as f:
            f.write(json.dumps({"repo": "iptv_apps", "line_hash": hh, "missing": "iptv-web/src/api/nowPlayingTexts.ts"}) + "\n" + "\n".join(rowj(i) for i in range(5000, 5100)) + "\n")
        import io
        so = sys.stdout
        sys.stdout = io.StringIO()
        try:
            r1 = TF.scan(pr, ts_repo, "iptv_apps", os.path.join(T, "stw"))
        finally:
            sys.stdout = so
        n_after = len(open(big).read().split("\n")) - 1
        check("TFMS scan: a key inside the last 4000 lines is deduped; scan trims an over-5000 log", r1 == [] and n_after == 4000 + 0 and True, out, "%s lines=%d" % (r1, n_after))
    finally:
        os.environ.pop("OVN_TFMS_LOG", None)
    os.environ.update(env0)
    return out


def report(res, lbl):
    bad = [(n, e) for n, ok, e in res if not ok]
    return bad


# ---- original
L0 = load(os.path.join(SD, "ovn_verify_shape_lint.py"), "vsl_orig")
sys.path.insert(0, Q)
SG0 = load(os.path.join(Q, "ovn_scout_ground.py"), "sg_orig")
TF0 = load(os.path.join(Q, "ovn_test_first_source.py"), "tf_orig")
res = core(L0, SG0, TF0, "orig")
for n, ok, e in res:
    if ok:
        PASS += 1
    else:
        FAIL += 1
        print("  FAIL %s %s" % (n, e[:300]))
print("  core assertions: %d passed, %d failed" % (PASS, FAIL))

# ---- static checks
def src(p):
    return open(p, encoding="utf-8").read()


def sok(name, cond):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print("  FAIL " + name)


RUN = src(os.path.join(Q, "run_overnight.sh"))
sok("run_overnight: TFMS hook default shadow, off honoured, ovn_hto-capped, never fatal", 'OVN_TEST_FIRST_SOURCE:-shadow}" != off' in RUN and "ovn_hto 30 test_first_source" in RUN and "ovn_test_first_source.py\" scan OVERNIGHT_PROGRESS.md" in RUN)
sok("run_overnight: TFMS hook sits right after the item-hazard hook", RUN.index("ovn_item_hazards.py\" scan") < RUN.index("ovn_test_first_source.py\" scan"))
sok("TFMS module has no enforce mode (shadow/off only)", 'in ("off", "shadow")' in src(os.path.join(Q, "ovn_test_first_source.py")))
BB = src(os.path.join(SD, "lib_build_break_park.sh"))
sok("build-break park DEFAULT stays shadow (precision < 80%, false parks > 0)", "OVN_BUILD_BREAK_PARK:-shadow" in BB)
sok("scout imports default is shadow in source", 'os.environ.get("OVN_SCOUT_IMPORTS", "shadow")' in src(os.path.join(Q, "ovn_scout_ground.py")))
sok("GU1 default is enforce in source", '"GU1": "enforce"' in src(os.path.join(SD, "ovn_verify_shape_lint.py")))
sok("no exclamation-mark pass text in the shape-lint source", "tests passed" + BANG not in src(os.path.join(SD, "ovn_verify_shape_lint.py")))
# synthetic precision tool check (the decision numbers come from the real outcomes: docs/Q_ORACLE_PARK_2026-11-24.md)
PR = load(os.path.join(SD, "ovn_bb_park_precision.py"), "bbp")
rows = []
for i, (h, cls, st) in enumerate([("a", "reverted", "reverted(build-break)"), ("a", "reverted", "reverted(build-break)"), ("a", "landed", "pushed"), ("b", "reverted", "reverted(build-break)"), ("b", "reverted", "reverted(build-break)")]):
    rows.append({"ts": "2026-11-20T00:%02d:00Z" % i, "repo": "r", "item_hash": h, "class": cls, "status": st})
a = PR.analyse(rows, days=30, after=2)
sok("precision tool: 2 would-park events, 1 landed later => precision 0.5", a["events"] == 2 and a["false_parks"] == 1 and a["precision"] == 0.5)
a = PR.analyse(rows, days=30, after=3)
sok("precision tool: threshold 3 => no events", a["events"] == 0 and a["precision"] is None)

# ---- mutants
SRC_MAP = {"vsl": os.path.join(SD, "ovn_verify_shape_lint.py"), "sg": os.path.join(Q, "ovn_scout_ground.py"), "tf": os.path.join(Q, "ovn_test_first_source.py")}
MUTANTS = [
    ("GU1 rule removed from _RULES", "vsl", "_RULES = _RULES + (_rule_gut_summary,)", "_RULES = _RULES + ()"),
    ("GU1 default shadow", "vsl", '"GU1": "enforce"}', '"GU1": "shadow"}'),
    ("GU1 not a Z1 code (no enforce promotion)", "vsl", '"R1", "GU1"))', '"R1"))'),
    ("GU1 pattern family includes 'N passed'", "vsl", "|passed:? ?[1-9][0-9]*\", re.I)", "|passed:? ?[1-9][0-9]*|[1-9][0-9]* passed\", re.I)"),
    ("GU1 ignores the green sample guard", "vsl", "if rx is None or rx.search(_GUT_GREEN_SAMPLE):", "if rx is None:"),
    ("GU1 rewrite keeps the old pattern", "vsl", "'grep -q \"%s\"' % _GU1_PASS_TEXT", "'grep -q \"0 failing\"'"),
    ("GU1 fires on non-GUT godot runs", "vsl", "return b in (\"godot\", \"godot4\", \"godot3\") and any(_GUT_ARGS.search(a) for a in argv[1:])", "return b in (\"godot\", \"godot4\", \"godot3\")"),
    ("GU1 fires despite || tail", "vsl", "    if not _stage_ops_plain(stages):\n        return out\n    for pl in pls:\n        if len(pl) < 2 or not _is_gut_run", "    for pl in pls:\n        if len(pl) < 2 or not _is_gut_run"),
    ("IMPORTS default enforce", "sg", 'os.environ.get("OVN_SCOUT_IMPORTS", "shadow")', 'os.environ.get("OVN_SCOUT_IMPORTS", "enforce")'),
    ("IMPORTS stage removed", "sg", "    if workable and imode != \"off\":", "    if False:"),
    ("IMPORTS shadow also adds", "sg", "            if imode == \"enforce\":\n                for path, why in would:", "            if imode != \"off\":\n                for path, why in would:"),
    ("IMPORTS ignores size cap", "sg", "if sz > IMPORT_HOP_MAX_MOD or hop >= IMPORT_HOP_MAX_FILES:", "if False:"),
    ("IMPORTS relative imports dropped", "sg", "        for m in RELIMP_RE.finditer(txt):", "        for m in []:"),
    ("IMPORTS ignores max_extra", "sg", "if len(extras) + len(would) >= max_extra or too_big_or_banned(path):", "if too_big_or_banned(path):"),
    ("TFMS creator exemption removed", "tf", "        if not _created_by_open_earlier(c[\"missing\"], earlier):", "        if True:"),
    ("TFMS parked creators count", "tf", "if re.match(r\"^- \\[ \\]\", t.strip()) and not PARKED.search(t):\n            earlier.append", "if re.match(r\"^- \\[ \\]\", t.strip()):\n            earlier.append"),
    ("TFMS no dedupe", "tf", "                if key in seen:\n                    continue", "                if False:\n                    continue"),
    ("TFMS parked test step flagged", "tf", "or PARKED.search(line) or not re.match", "or not re.match"),
    ("TFMS off ignored", "tf", "        if mode() == \"off\":\n            return rows", "        if False:\n            return rows"),
    ("TFMS python imports ignored", "tf", "    if testfile.endswith(\".py\"):", "    if False:"),
    ("TFMS sibling evidence dropped", "tf", "    if sib and not _exists(root, sib, tracked):", "    if False:"),
    ("TFMS existing source still flagged", "tf", "            if base.startswith(\"..\") or _ts_found(root, base, tracked):\n                continue", "            if base.startswith(\"..\"):\n                continue"),
]
for lbl, which, old, new in MUTANTS:
    d = os.path.join(T, "mut_" + re.sub(r"\W+", "_", lbl))
    os.makedirs(d)
    s = src(SRC_MAP[which])
    if old not in s:
        FAIL += 1
        print("  FAIL mutant '%s': pattern not found in source" % lbl)
        continue
    mods = {}
    for k, p in SRC_MAP.items():
        text = src(p)
        if k == which:
            text = text.replace(old, new, 1)
        dst = os.path.join(d, os.path.basename(p))
        with open(dst, "w") as f:
            f.write(text)
        mods[k] = dst
    if os.path.exists(os.path.join(Q, "ovn_park_unworkable.py")):
        shutil.copy(os.path.join(Q, "ovn_park_unworkable.py"), d)
    try:
        sys.path.insert(0, d)
        tag = "m%d" % (MUT_PASS + MUT_FAIL)
        Lm, SGm, TFm = load(mods["vsl"], "vsl_" + tag), load(mods["sg"], "sg_" + tag), load(mods["tf"], "tf_" + tag)
        r = core(Lm, SGm, TFm, tag)
        killed = any(not ok for _n, ok, _e in r)
    except Exception as e:  # a mutant that no longer even runs is dead
        killed = True
    finally:
        if sys.path and sys.path[0] == d:
            sys.path.pop(0)
    if killed:
        MUT_PASS += 1
    else:
        MUT_FAIL += 1
        print("  FAIL mutant SURVIVED: %s" % lbl)
print("  mutants: %d killed, %d survived of %d" % (MUT_PASS, MUT_FAIL, len(MUTANTS)))
shutil.rmtree(T, ignore_errors=True)
print("q-oracle-park: %d passed, %d failed (core+static), mutants %d/%d killed" % (PASS, FAIL, MUT_PASS, len(MUTANTS)))
sys.exit(0 if FAIL == 0 and MUT_FAIL == 0 else 1)
