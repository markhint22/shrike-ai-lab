#!/usr/bin/env python3
"""P5b (2026-10-21): the unsatisfiable VERIFY shapes seen in 24 h of verify_gate_shadow.log (scripts/ovn_verify_shape_lint.py). Run by test_p5_shadow_evidence.sh inside a private TMPDIR.

For every new shape: the flagged fixture (real clause text from the box where possible), its SATISFIABLE twin that must NOT be flagged, and - where a rewrite exists - the rewrite is
EXECUTED against a real file and must exit 0 on a file that satisfies the item and non-zero on one that does not (a rewrite that always passes would be a new vacuous clause).
Mutants: one hunk of the module reverted at a time; each must make core() fail."""
import importlib.util, json, os, re, subprocess, sys, tempfile, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.environ.get("P5_LINT_DIR") or os.path.abspath(os.path.join(HERE, ".."))
MODPATH = os.path.join(SD, "ovn_verify_shape_lint.py")
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + (("  :: " + str(extra)[:300]) if extra else ""))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def mk(root, rel, text=""):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def sh(cmd, cwd):
    if not cmd:
        return 99
    return subprocess.run(["bash", "-c", cmd], cwd=cwd, capture_output=True, timeout=30).returncode


def core(L, work):
    bad = []

    def chk(n, c):
        if not c:
            bad.append(n)
    tree = os.path.join(work, "tree")
    shutil.rmtree(tree, ignore_errors=True)

    def codes(clause, tr=None, item=None):
        return [f["code"] for f in L.lint_verify(clause, tr, item)["findings"] if f["class"] != L.OK]

    def rw(clause, code, tr=None, item=None):
        return next((f["rewrite"] for f in L.lint_verify(clause, tr, item)["findings"] if f["code"] == code), None)
    # ---- S6 decorator -> def on ONE grep line
    mk(tree, "app/router_ok.py", '@limiter.limit("10/minute")\ndef apply_cooldown(request):\n    pass\n')
    mk(tree, "app/router_bad.py", 'def apply_cooldown(request):\n    pass\n')
    c = 'grep -q "@limiter.limit.*def apply_cooldown" app/router_ok.py'
    chk("S6 decorator.*def single grep flagged", codes(c) == ["S6"])
    c2 = "grep -qE '@router\\.get\\(.*\\)\\s*\\n\\s*(async )?def list_items' app/router_ok.py"
    chk("S6 \\n-chained decorator/def flagged", codes(c2) == ["S6"])
    chk("S6 twin: a -A window + second grep is not flagged", codes('grep -A 2 "@limiter.limit" app/router_ok.py | grep -q "def apply_cooldown"') == [])
    chk("S6 twin: a def-only pattern is not flagged", codes('grep -q "def apply_cooldown" app/router_ok.py') == [])
    chk("S6 twin: grep -Pzo multi-line is not flagged", codes('grep -Pzo "@limiter.limit[^\\n]*\\ndef apply_cooldown" app/router_ok.py') == [])
    r = rw(c, "S6")
    chk("S6 rewrite exists", bool(r))
    chk("S6 rewrite PASSES on a file that has the decorator above the def", bool(r) and sh(r, tree) == 0)
    chk("S6 rewrite FAILS on a file with the def but no decorator", bool(r) and sh(r.replace("router_ok", "router_bad"), tree) != 0)
    chk("S6 the original clause is unsatisfiable on the SATISFIED file (the defect is real)", sh(c, tree) != 0)
    # real billwatch clause (two greps; already S1): still flagged
    chk("S6/S1 real billwatch ranking clause stays flagged", codes('grep -n "limiter" billwatch-backend/app/routers/ranking.py | grep -q "apply_cooldown"') == ["S1"])
    # ---- S7 inverted raises polarity
    item = "- [ ] [T1] app/utils/severity.py — `validate_severity(\"bogus\")` raises `ValueError`. VERIFY: `%s`. (cat:test)"
    bad_c = "python -c \"from app.utils.severity import validate_severity; validate_severity('bogus')\""
    chk("S7 a python -c that calls the function the item says raises, no try/except", codes(bad_c, None, item % bad_c) == ["S7"])
    good_c = "python -c \"from app.utils.severity import validate_severity\ntry:\n    validate_severity('bogus')\nexcept ValueError:\n    pass\nelse:\n    raise SystemExit(1)\""
    chk("S7 twin: the same call inside try/except is not flagged", codes(good_c, None, item % good_c) == [])
    imp_c = 'python -c "from app.utils.severity import validate_severity"'
    chk("S7 twin: an import-only clause is not flagged", codes(imp_c, None, item % imp_c) == [])
    chk("S7 twin: no item text -> silent", codes(bad_c) == [])
    # S7 false positive (review): the clause calls the function with VALID input - a normal positive test - must stay silent
    it2 = "- [ ] [T1] x.py — Add `parse(x)` that raises ValueError on bad input. VERIFY: `%s`. (cat:test)"
    v_c = "python3 -c \"from x import parse; assert parse('3')==3\""
    chk("S7 valid-input call vs symbolic item arg is silent", codes(v_c, None, it2 % v_c) == [])
    it3 = "- [ ] [T1] x.py — `validate(x)` raises on negative. VERIFY: `%s`. (cat:test)"
    v3 = 'python3 -c "from x import validate; validate(1)"'
    chk("S7 validate(1) vs `validate(x) raises on negative` is silent", codes(v3, None, it3 % v3) == [])
    it4 = "- [ ] [T1] x.py — `validate(-1)` raises ValueError. VERIFY: `%s`. (cat:test)"
    v4 = 'python3 -c "from x import validate; validate(1)"'
    chk("S7 valid arg vs literal failing arg `validate(-1)` is silent", codes(v4, None, it4 % v4) == [])
    v5 = 'python3 -c "from x import validate; validate(-1)"'
    chk("S7 the call on the literal failing arg is still flagged", codes(v5, None, it4 % v5) == ["S7"])
    # P5 own switch OVN_VERIFY_LINT_P5
    import os as _os
    def lint_item(line, mdp5, md="enforce"):
        old = _os.environ.get("OVN_VERIFY_LINT_P5")
        if mdp5 is None: _os.environ.pop("OVN_VERIFY_LINT_P5", None)
        else: _os.environ["OVN_VERIFY_LINT_P5"] = mdp5
        try:
            return L.lint_item_line(line, None, md)
        finally:
            if old is None: _os.environ.pop("OVN_VERIFY_LINT_P5", None)
            else: _os.environ["OVN_VERIFY_LINT_P5"] = old
    s8 = "- [ ] [T2] t.py — fixtures. VERIFY: `pytest backend/tests/conftest.py -v`. (cat:test)"
    chk("P5 switch: default (shadow) with OVN_VERIFY_LINT=enforce flags S8 but leaves the item unchanged", lint_item(s8, None)[0] == "flagged" and lint_item(s8, None)[1] == s8)
    chk("P5 switch: enforce rewrites S8", lint_item(s8, "enforce")[0] == "rewritten")
    chk("P5 switch: off produces no P5 finding", lint_item(s8, "off")[0] == "ok")
    wcl = "- [ ] [T2] a.py — x. VERIFY: `grep -n x a.py | wc -l returns 3`. (cat:test)"
    chk("P5 switch: V1 `wc returns N` rewrite withheld in shadow (old behaviour: drop)", lint_item(wcl, "shadow")[0] == "dropped" and lint_item(wcl, "enforce")[0] == "rewritten")
    old_s = "- [ ] [T2] a.py — x. VERIFY: `grep -rn x app | wc -l`. (cat:x)"
    chk("P5 switch: a pre-P5 shape (V1 wc) still rewrites under shadow", lint_item(old_s, "shadow")[0] == "rewritten")
    prose = "pytest.raises(ValueError): RateLimiter(max_tokens=0, window_seconds=10) AND pytest.raises(ValueError): RateLimiter(max_tokens=10, window_seconds=0)"
    chk("S7 `pytest.raises(..)` prose as the clause is UNRUNNABLE", [f["class"] for f in L.lint_verify(prose)["findings"]] == [L.UNRUN] and codes(prose) == ["S7"])
    # ---- S8 conftest.py as the pytest target
    cc = "/home/x/repos/test-automation-agent/backend/.venv/bin/pytest backend/tests/conftest.py -v"
    chk("S8 conftest.py target flagged (real TAA clause)", codes(cc) == ["S8"])
    r8 = rw(cc, "S8")
    chk("S8 rewrite runs the directory", r8 == "/home/x/repos/test-automation-agent/backend/.venv/bin/pytest backend/tests -v")
    chk("S8 twin: a real test file is not flagged", codes("pytest backend/tests/test_a.py -v") == [])
    chk("S8 twin: `-p conftest`-free dir target is not flagged", codes("pytest backend/tests -v") == [])
    chk("S8 conftest::node form rewritten too", rw("pytest tests/conftest.py::fx -q", "S8") == "pytest tests -q")
    # ---- S9 instantiation without required args (tree-confirmed)
    mk(tree, "backend/app/schemas.py",
       "from pydantic import BaseModel, Field\n\nclass StatusOut(BaseModel):\n    status: str\n    latency_min_ms: float | None = None\n    uptime_ratio: float = Field(...)\n\nclass AllDefault(BaseModel):\n    a: int = 1\n    b: int = Field(default=2)\n")
    s9 = "python -c \"from backend.app.schemas import StatusOut; s=StatusOut(); assert hasattr(s, 'latency_min_ms')\""
    chk("S9 Model() with required fields flagged (real shrike-monitor shape)", "S9" in codes(s9, tree))
    chk("S9 twin: all-default model is not flagged", "S9" not in codes("python -c \"from backend.app.schemas import AllDefault; AllDefault()\"", tree))
    chk("S9 twin: instantiation WITH args is not flagged", "S9" not in codes("python -c \"from backend.app.schemas import StatusOut; StatusOut(status='x', uptime_ratio=1.0)\"", tree))
    chk("S9 twin: class access without a call is not flagged", "S9" not in codes("python -c \"from backend.app.schemas import StatusOut; assert 'latency_min_ms' in StatusOut.model_fields\"", tree))
    chk("S9 silent without a tree", "S9" not in codes(s9))
    # ---- U4 backend. import prefix (the backend roots its imports at app/)
    mk(tree, "backend/app/models/test_run.py", "from app.database import Base\n\nclass TestRun(Base):\n    pass\n")
    u4 = "/h/repos/taa/backend/.venv/bin/python3 -c \"from backend.app.models.test_run import TestRun; assert hasattr(TestRun, 'flaky_tests')\""
    chk("U4 backend.app prefix flagged when backend/ imports `app.` itself", codes(u4, tree) == ["U4"] or "U4" in codes(u4, tree))
    r4 = rw(u4, "U4", tree)
    chk("U4 rewrite is `cd backend &&` with the prefix dropped", bool(r4) and r4.startswith("cd backend && ") and "from app.models.test_run import TestRun" in r4 and "backend.app" not in r4)
    chk("U4 twin: a clause that already cd's is not flagged", "U4" not in codes("cd backend && " + u4.replace("backend.app", "app"), tree))
    mk(tree, "other/backend/app/m.py", "from backend.app.x import y\n")
    tree2 = os.path.join(tree, "other")
    chk("U4 twin: a backend that imports `backend.app.` itself is not flagged", "U4" not in codes("python -c \"from backend.app.x import y\"", tree2))
    chk("U4 silent without a tree", "U4" not in codes(u4))
    # ---- V4: test ! -f X && echo .. || echo ..
    v = 'test ! -f scripts/roster/level_curve.gd && echo gone || echo exists'
    chk("V4 `test ! -f` echo-chain flagged", "V4" in codes(v))
    chk("V4 rewritten to the bare test", rw(v, "V4") == "test ! -f scripts/roster/level_curve.gd")
    chk("V4 rewrite is a real check: passes when the file is absent, fails when present",
        sh(rw(v, "V4"), tree) == 0 and (mk(tree, "scripts/roster/level_curve.gd", "x") or True) and sh(rw(v, "V4"), tree) != 0)
    chk("V4 existing polarity rewrite untouched (FAIL/PASS -> ! ( cmd ))", rw("grep -q foo a.py && echo FAIL || echo PASS", "V4") == "! ( grep -q foo a.py )")
    chk("V4 non-test body with unclear messages still gets no guessed rewrite", rw("grep -q foo a.py && echo alpha || echo beta", "V4") is None)
    # ---- V1: | wc -l returns N
    w = "grep -rn old_helper app | wc -l returns 0"
    chk("V1 `wc -l returns 0` flagged", "V1" in codes(w))
    chk("V1 `returns 0` rewritten to -eq 0 (delete direction kept)", rw(w, "V1") == 'test "$(grep -rn old_helper app | wc -l)" -eq 0')
    chk("V1 `returns 3` rewritten to -eq 3", rw("grep -n x a.py | wc -l returns 3", "V1") == 'test "$(grep -n x a.py | wc -l)" -eq 3')
    mk(tree, "app/gone.py", "nothing here\n")
    chk("V1 the -eq 0 rewrite executes: passes on a clean tree", sh(rw(w, "V1"), tree) == 0)
    mk(tree, "app/still.py", "old_helper()\n")
    chk("V1 ... and fails when the helper is still there", sh(rw(w, "V1"), tree) != 0)
    delitem = "- [ ] [T2] app/x.py — Remove `old_helper`; no references remain. VERIFY: `grep -rn old_helper app | wc -l`. (cat:refactor)"
    r1 = rw("grep -rn old_helper app | wc -l", "V1", None, delitem)
    chk("V1 a delete-direction item is never rewritten to -ge 1", r1 is None or "-ge 1" not in r1)
    chk("V1 presence item keeps the historical -ge 1", rw("grep -rn x app | wc -l", "V1", None, "- [ ] [T2] a.py — add x. VERIFY: `grep -rn x app | wc -l`. (cat:x)") is not None)
    chk("V1 trailing prose that is not a count gets no rewrite", rw("grep -n x a.py | wc -l looks fine", "V1") is None)
    return bad


def mutants():
    return {
        "L1 S6 rule not registered": ("_rule_decorator_def, _rule_raises_polarity", "_rule_raises_polarity"),
        "L2 S7 rule not registered": ("_rule_raises_polarity, _rule_conftest_target", "_rule_conftest_target"),
        "L3 S8 rule not registered": ("_rule_conftest_target, _rule_bare_instantiation", "_rule_bare_instantiation"),
        "L4 S9 rule not registered": ("_rule_bare_instantiation, _rule_backend_prefix", "_rule_backend_prefix"),
        "L5 U4 rule not registered": ("_rule_bare_instantiation, _rule_backend_prefix)", "_rule_bare_instantiation)"),
        "L6 test-body V4 rewrite dropped": ('and not (pb == "good" and pa != "good") and pa != "bad":', "and False:"),
        "L7 wc returns N rewrite dropped": ('elif extra[-1].isdigit() and all(w.lower() in _WC_WORDS for w in extra[:-1]):', "elif False:"),
        "L8 wc returns N rewritten to presence": ("""'test "$(%s | %s)" -eq %d' % (body, flags, int(extra[-1]))""", """'test "$(%s | %s)" -ge 1' % (body, flags)"""),
        "L9 S6 flags the -Pz multi-line twin": ('(g["flags"] & set("zP"))', "False"),
        "L10 S7 ignores try/except": ('if re.search(r"\\btry\\s*:|\\bexcept\\b|\\braises?\\b|assertRaises|\\bwith\\s+\\w+\\.raises|suppress\\(", clause):', "if False:"),
        "L11 S9 treats defaulted fields as required": ("""if v is None:
                req.append(n.target.id)""", """if True:
                req.append(n.target.id)"""),
        "L12 S6 rewrite drops the -A window": ('"grep %s-A 6 %s %s | grep %s %s"', '"grep %s %s %s | grep %s %s"'),
        "L14 S7 fires on any call of the callee": ("any(_norm_args(c) == iargs for c in", "any(True for c in"),
        "L15 P5 switch ignored (always enforce)": ('gate = p5_mode() != "enforce"', "gate = False"),
        "L13 S8 rewrite keeps conftest": ('lambda m: (m.group(1).rstrip("/") or ".")', "lambda m: m.group(0)"),
    }


def main():
    L = load(MODPATH, "vsl_p5")
    work = tempfile.mkdtemp(prefix="p5lint-")
    bad = core(L, work)
    for b in bad:
        ok(b, False)
    ok("core contract on the real module: %d failed" % len(bad), not bad)
    if "--core" in sys.argv:
        shutil.rmtree(work, ignore_errors=True)
        return 1 if bad else 0
    src = open(MODPATH, encoding="utf-8").read()
    for name, (old, new) in mutants().items():
        if old not in src:
            ok("mutant %s: hunk present" % name, False)
            continue
        d = os.path.join(work, "m_" + name.split()[0])
        os.makedirs(d)
        mp = os.path.join(d, "ovn_verify_shape_lint.py")
        open(mp, "w", encoding="utf-8").write(src.replace(old, new, 1))
        mb = core(load(mp, "vsl_mut_" + name.split()[0]), work)
        ok("mutant %s is caught (%d check(s) failed)" % (name, len(mb)), len(mb) > 0)
    shutil.rmtree(work, ignore_errors=True)
    print("test_p5_lint_shapes: pass=%d fail=%d" % (P, F))
    return 1 if F else 0


if __name__ == "__main__":
    sys.exit(main())
