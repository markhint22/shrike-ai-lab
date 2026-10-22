#!/usr/bin/env python3
"""D1 (2026-10-18): VERIFY SHAPE linter (ovn_verify_shape_lint.py) - real box items, every shape + its rewrite, tree-confirmed rules, modes, hooks, audit CLI, mutants.

The wrapper test_verify_shape_lint.sh runs this inside a fail-closed private TMPDIR. Mutant proofs: each [mut] case copies the module into a scratch dir, reverts ONE hunk and
requires the core assertions (--core) to FAIL against the copy (exit != 0)."""
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time as _t

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.environ.get("VSL_DIR") or os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, SD)
import ovn_verify_shape_lint as L  # noqa: E402

CORE_ONLY = "--core" in sys.argv
HOOKS_ONLY = "--hooks" in sys.argv   # core + the queue_refill / generate_items hook checks only (what the hook mutants run)
PASS = FAIL = 0


def ok(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS " + name)
    else:
        FAIL += 1
        print("  FAIL %s %s" % (name, extra))


def mk(root, rel, text=""):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)


def codes(clause, tree=None):
    return [f["code"] for f in L.lint_verify(clause, tree)["findings"]]


def cls(clause, tree=None):
    return L.lint_verify(clause, tree)["class"]


T = tempfile.mkdtemp(prefix="vsl-tree-")
body = "\n".join("    x = %d" % i for i in range(30))
mk(T, "backend/app/services/github.py",
   "import x\n\nasync def get_file_content(path):\n" + body + "\n    return await _github_retry.execute(fetch)\n\n\ndef other(a: int, b: str) -> None:\n    pass\n")
mk(T, "backend/app/signed.py", "async def foo(self, a: int, b: str = 'x') -> None:\n    pass\n\ndef untyped(a, b):\n    pass\n")
mk(T, "backend/tests/test_x.py", "def test_a():\n    pass\n")
mk(T, "billwatch-backend/app/__init__.py", "")
mk(T, "same/line.py", "def run():\n    handle_error = 1  # except handle_error\n")
mk(T, "tests/test_root.py", "def test_r():\n    pass\n")
mk(T, "svc/tests/test_svc.py", "def test_s():\n    pass\n")
mk(T, "backend/spec/test_y.py", "def test_y():\n    pass\n")

# ------------------------------------------------------------------ core (also what the mutants must break)
print("== core shapes")
ok("V1 wc -l is VACUOUS", cls("grep -n 'stallCount = 0' a/b.vue | wc -l") == L.VACUOUS and codes("grep -n x f | wc -l") == ["V1"])
ok("V1 rewrite is a real assertion and re-lints OK", L.fix_clause("grep -n x f | wc -l")[0] == 'test "$(grep -n x f | wc -l)" -ge 1' and L.fix_clause("grep -n x f | wc -l")[1] == [])
ok("V1 wc inside an explicit test is OK", cls('test "$(grep -n x f | wc -l)" -ge 1') == L.OK)
ok("V1 display stage head", codes("grep -rn x src | head -5") == ["V1"] and L.fix_clause("grep -rn x src | head -5")[0] == "grep -rn x src")
ok("V2 || true / || exit 0", codes("grep -q x f || true") == ["V2"] and codes("grep -q x f || exit 0") == ["V2"] and L.fix_clause("grep -q x f || true")[0] == "grep -q x f")
ok("V3 ; echo", codes("grep -q x f ; echo done") == ["V3"] and L.fix_clause("grep -q x f ; echo done")[0] == "grep -q x f")
ok("V4 echo PASS||FAIL", codes("test -f a && echo PASS || echo FAIL") == ["V4"] and L.fix_clause("test -f a && echo PASS || echo FAIL")[0] == "test -f a")
ok("V4 inverted (FAIL first) keeps the absence meaning", L.fix_clause("grep x f && echo FAIL || echo PASS")[0] == "! ( grep x f )")
ok("U1 double prefix", codes("cd backend && python3 -m pytest backend/tests/x.py") == ["U1"] and L.fix_clause("cd backend && python3 -m pytest backend/tests/x.py")[0] == "cd backend && python3 -m pytest tests/x.py")
ok("U1 not fired for a path that is not under the cd dir", codes("cd backend && pytest tests/x.py") == [])
ok("U3 billwatch_backend import", codes('python -c "from billwatch_backend.app.x import y"') == ["U3"] and
   L.fix_clause('python -c "from billwatch_backend.app.x import y"')[0] == 'cd billwatch-backend && python -c "from app.x import y"')
ok("U3 not fired for backend.app / app.", codes('python -c "from backend.app.x import y"') == [] and codes('python -c "from app.x import y"') == [])
ok("S1 grep -n | grep <fn name>", cls("grep -n '_github_retry.execute' backend/app/services/github.py | grep -q get_file_content") == L.UNSAT)
ok("S1 same-line pattern is OK", cls("grep -n 'target=\"_blank\"' f | grep -q 'rel=\"noopener\"'") == L.OK)
ok("S1 def-line first pattern is OK (param on the def line)", cls("grep -n 'def foo' f | grep -q session_id") == L.OK)
ok("S1 pattern containing the name is OK", cls("grep -n 'get_file_content' f | grep -q get_file_content") == L.OK)
ok("unparseable clause never raises", L.lint_verify("grep 'unterminated")["class"] == L.OK)

print("== tree-confirmed rules")
gh = "backend/app/services/github.py"
w = "grep -n 'async def get_file_content' -A 15 %s | grep -q '_github_retry.execute'" % gh
ok("S2 -A 15 window shorter than the distance (31)", codes(w, T) == ["S2"], codes(w, T))
fixed, left = L.fix_clause(w, T)
ok("S2 rewrite widens the window and re-lints OK", "-A 33" in fixed and left == [] and L.lint_verify(fixed, T)["class"] == L.OK, fixed)
ok("S2 silent without a tree", codes(w) == [])
ok("S2 a window that already reaches is OK", codes(w.replace("-A 15", "-A 40"), T) == [])
ok("S2 target text absent from the file is NOT a window problem", codes(w.replace("_github_retry.execute", "zzz_nowhere"), T) == [])
ok("S1 tree: rewrite via the def window", L.lint_verify("grep -n '_github_retry.execute' %s | grep -q get_file_content" % gh, T)["findings"][0]["rewrite"] is not None)
ok("S1 tree: a line carrying both removes the finding", codes("grep -n 'except' same/line.py | grep -q handle_error", T) == [])
ok("U2 pytest tests/ path under a root the runner heals (backend/) is NOT flagged (lib_verify_clause.sh _verify_py_cwd retries it)", codes("pytest tests/test_x.py", T) == [] and codes("python3 -m pytest tests/test_x.py::test_a -q", T) == [])
ok("U2 pytest tests/ path under a root the runner does NOT heal (svc/) is flagged and rewritten", codes("pytest tests/test_svc.py", T) == ["U2"] and L.fix_clause("pytest tests/test_svc.py", T)[0] == "cd svc && pytest tests/test_svc.py")
ok("U2 python -m pytest with ::node under a non-healed root", L.fix_clause("python3 -m pytest tests/test_svc.py::test_s -q", T)[0] == "cd svc && python3 -m pytest tests/test_svc.py::test_s -q")
ok("U2 a non-tests/ path under backend/ is not healed by the runner -> flagged", codes("pytest spec/test_y.py", T) == ["U2"])
ok("U2 a path that exists at the root is OK", codes("pytest tests/test_root.py", T) == [])
ok("U2 a path that exists nowhere (item creates it) is OK", codes("pytest tests/test_new.py", T) == [])
ok("U2 silent without a tree", codes("pytest tests/test_x.py") == [])
ok("U3 stays silent when the underscore package really exists", codes('python -c "from billwatch_backend.app.x import y"', T) != [] and
   (mk(T, "billwatch_backend/__init__.py") or True) and codes('python -c "from billwatch_backend.app.x import y"', T) == [])
sig = "grep -q 'def foo(self, a, b)' backend/app/signed.py"
ok("S5 untyped signature grep vs a typed def", codes(sig, T) == ["S5"], codes(sig, T))
f5, l5 = L.fix_clause(sig, T)
ok("S5 rewrite keeps the parameter order and re-lints OK", l5 == [] and "def foo\\(" in f5 and "self" in f5, f5)
ok("S5 untyped real def is OK", codes("grep -q 'def untyped(a, b)' backend/app/signed.py", T) == [])
ok("S5 silent without a tree", codes(sig) == [])

# ------------------------------------------------------------------ real box items (read-only copies of OVERNIGHT_PROGRESS.md lines)
print("== real items from the box")
real = [l.rstrip("\n").split("\t", 1) for l in open(os.path.join(HERE, "fixtures", "verify_shape_lint_real_items.tsv")) if l.strip()]
want = {"S1": L.UNSAT, "V1": L.VACUOUS, "V2": L.VACUOUS, "V4": L.VACUOUS, "U3": L.UNRUN, "U1": L.UNRUN, "OK": L.OK}
for k, line in real:
    ex = L.extract_verify(line)
    ok("real %s item: VERIFY extracted" % k, ex is not None)
    r = L.lint_verify(ex[0])
    ok("real %s item classified %s" % (k, want[k]), r["class"] == want[k], (r["class"], ex[0][:120]))
    if k not in ("OK", "S1"):
        d, out, _ = L.lint_item_line(line, None, "enforce")
        ok("real %s item: enforce rewrites it to a clause that lints OK" % k, d == "rewritten" and L.lint_verify(L.extract_verify(out)[0])["class"] == L.OK, d)

_b = "- [ ] [T1] a.py - x. VERIFY: `grep -n foo a.py | wc -l`. (cat:python)"
ok("modes (core): off -> ok untouched; shadow -> flagged untouched; enforce -> rewritten", L.lint_item_line(_b, None, "off") == ("ok", _b, None)
   and L.lint_item_line(_b, None, "shadow")[:2] == ("flagged", _b) and L.lint_item_line(_b, None, "enforce")[0] == "rewritten")

# ------------------------------------------------------------------ D1 repair (review defects 1-7); behavioural: the rewritten clause is RUN in a sandbox dir and must keep the original's meaning
print("== D1 repair: polarity / long-hand absence / -v / cd .. / wc args")
RT = tempfile.mkdtemp(prefix="vsl-rt-", dir=T)
mk(RT, "has.py", "foo = 1\n")
mk(RT, "lacks.py", "bar = 2\n")


def sh(clause, files=()):
    return subprocess.run(["bash", "-c", clause], cwd=RT, capture_output=True, text=True).returncode


# defect 1: `cmd && exit 1 || exit 0` (pass when absent)
c1 = 'grep -q "foo" a.py && exit 1 || exit 0'
r1 = L.lint_verify(c1)["findings"][0]
ok("D1 `&& exit 1 || exit 0` is the informational V4a (class OK, not flagged, not rewritten); a rewrite suggestion `! ( cmd )` is still carried", r1["code"] == "V4a" and r1["class"] == L.OK and r1["rewrite"] == '! ( grep -q "foo" a.py )'
   and L.lint_verify(c1)["class"] == L.OK and L.lint_item_line("- [ ] [T1] a.py - x. VERIFY: `%s`. (cat:python)" % c1, None, "enforce")[0] == "ok"
   and L.lint_item_line("- [ ] [T1] a.py - x. VERIFY: `%s`. (cat:python)" % c1, None, "shadow")[0] == "ok", r1)
ok("D1 rewrite keeps the meaning: absent -> pass, present -> fail",
   sh(r1["rewrite"].replace("a.py", "lacks.py")) == 0 and sh(r1["rewrite"].replace("a.py", "has.py")) != 0 and sh(c1.replace("a.py", "lacks.py")) == 0 and sh(c1.replace("a.py", "has.py")) != 0)
ok("D1 the clause is left byte-identical (never turned into a V2 strip) and counted as OK in audit", L.fix_clause(c1) == (c1, []) and L.audit([os.path.join(T, "v4a.md")] if mk(T, "v4a.md", "- [ ] [T1] a.py - x. VERIFY: `%s`. (cat:python)\n" % c1) is None else [])[0]["class"] == L.OK)
ok("D1 multi-stage body is wrapped whole", L.lint_verify("test -f a.py && grep -q foo a.py && exit 1 || exit 0")["findings"][0]["rewrite"] == "! ( test -f a.py && grep -q foo a.py )")
ok("D1 real backlog shape (redact_secret)", L.lint_verify('grep -q "def redact_secret" backend/app/utils/redact.py && exit 1 || exit 0')["findings"][0]["rewrite"] == '! ( grep -q "def redact_secret" backend/app/utils/redact.py )')

# defect 2: polarity
pa = 'grep -q foo a.py && echo "PASS: found" || echo "FAIL: missing token"'
pb = 'grep -q foo a.py && echo "FAIL: still present" || echo "removed"'
pc = "test -f x.py && echo exists || echo removed"
fa, fb, fc = (L.lint_verify(x)["findings"][0] for x in (pa, pb, pc))
ok("D1 (a) presence check ('token' contains 'ok'): rewrite is the plain cmd, never inverted", fa["rewrite"] == "grep -q foo a.py", fa)
ok("D1 (b) absence check with 'removed': rewrite is `! ( cmd )`", fb["rewrite"] == "! ( grep -q foo a.py )", fb)
ok("D1 (c) unclear polarity: NO rewrite offered (enforce quarantines)", fc["rewrite"] is None and L.lint_item_line("- [ ] [T1] a.py - x. VERIFY: `%s`. (cat:python)" % pc, None, "enforce")[0] == "dropped", fc)
ok("D1 mixed/negated messages are unclear -> no rewrite", L.lint_verify('grep -q f a && echo "not found" || echo "ok"')["findings"][0]["rewrite"] is None
   and L.lint_verify('grep -q f a && echo "pass and fail" || echo "x"')["findings"][0]["rewrite"] is None)
ok("D1 xlite 2051 shape (File still exists / File deleted) is an absence check", L.lint_verify('test -f a.gd && echo "File still exists" || echo "File deleted"')["findings"][0]["rewrite"] == "! ( test -f a.gd )")
ok("D1 classic PASS/FAIL both ways still resolved", L.fix_clause("test -f a && echo PASS || echo FAIL")[0] == "test -f a" and L.fix_clause("grep x f && echo FAIL || echo PASS")[0] == "! ( grep x f )")

# defect 3: S1 must not fire on a negative filter
ok("D1 S1 silent for `| grep -v` (satisfiable)", codes('grep -n "tokens_per_month" backend/app/services/quota.py | grep -v "max_tokens"') == [])
ok("D1 S1 silent for -c / -L second stage", codes("grep -n quota_fn_name a.py | grep -c other_fn_name") == [] and codes("grep -n quota_fn_name a.py | grep -L other_fn_name") == [])
ok("D1 S1 still fires on a plain second grep", codes("grep -n quota_fn_name a.py | grep -q other_fn_name") == ["S1"])

# defect 4: U1 stops at a later cd
cd1 = "cd backend && python -m pytest -q tests/test_a.py && cd .. && grep -q foo backend/app/x.py"
ok("D1 U1 not fired when the prefix is used after `cd ..`", codes(cd1) == [] and codes(cd1, T) == [])
ok("D1 U1 not fired after `cd /abs`", codes("cd backend && true && cd /srv && grep -q foo backend/app/x.py") == [])
ok("D1 U1 still fires BEFORE the next cd and the rewrite leaves the tail untouched",
   L.lint_verify("cd backend && grep -q foo backend/app/x.py && cd .. && grep -q foo backend/app/y.py")["findings"][0]["rewrite"] == "cd backend && grep -q foo app/x.py && cd .. && grep -q foo backend/app/y.py")

# defect 5: lib_verify_lint.sh verify_lint_filter fail-open
FL = os.path.join(os.path.abspath(os.path.join(HERE, "..")), "lib_verify_lint.sh")
VPY = os.path.join(SD, "ovn_verify_shape_lint.py")
bad_py = os.path.join(T, "bad_filter.py")
open(bad_py, "w").write("import sys\nsys.stdin.read()\nsys.exit(3)\n")
items = "- [ ] [T1] a.py - x. VERIFY: `grep -n foo a.py | wc -l`. (cat:python)\n- [ ] [T1] b.py - y. VERIFY: `pytest -q`. (cat:python)\n"
rr = subprocess.run(["bash", "-c", '. "%s"; verify_lint_filter repo "" ' % FL], input=items, capture_output=True, text=True, env=dict(os.environ, OVN_VERIFY_LINT_PY=bad_py, OVN_VERIFY_LINT="shadow"))
ok("D1 verify_lint_filter: failing python filter -> items passed through UNCHANGED, rc 0, error on stderr", rr.stdout == items and rr.returncode == 0 and "failed" in rr.stderr, (rr.stdout, rr.returncode, rr.stderr))
rr = subprocess.run(["bash", "-c", '. "%s"; verify_lint_filter repo "" ' % FL], input=items, capture_output=True, text=True,
                    env=dict(os.environ, OVN_VERIFY_LINT_PY=VPY, OVN_VERIFY_SHAPE_LOG=os.path.join(T, "fl.log"), OVN_VERIFY_ALERTS_LOG=os.path.join(T, "fl.alerts"), OVN_VERIFY_LINT="shadow"))
ok("D1 verify_lint_filter: healthy shadow run returns the items byte-identical (no trailing-newline loss)", rr.stdout == items and rr.returncode == 0, rr.stdout)
rr = subprocess.run(["bash", "-c", '. "%s"; verify_lint_filter repo "" ' % FL], input=items, capture_output=True, text=True,
                    env=dict(os.environ, OVN_VERIFY_LINT_PY=VPY, OVN_VERIFY_SHAPE_LOG=os.path.join(T, "fl.log"), OVN_VERIFY_ALERTS_LOG=os.path.join(T, "fl.alerts"), OVN_VERIFY_LINT="enforce"))
ok("D1 verify_lint_filter: enforce rewrites the wc item, keeps the other", "-ge 1" in rr.stdout and "pytest -q" in rr.stdout and rr.stdout.count("\n") == 2, rr.stdout)

# defect 6: wc with trailing prose / extra args -> no rewrite
w1 = 'grep -n "logger.exception" a/push_sender.py | wc -l returns 2'
# P5 (2026-10-21): `| wc -l returns N` states the count itself, so the rewrite is that exact count (-eq 2), never the presence assumption (-ge 1). Trailing PROSE that is not a count still gets none.
ok("D1 `| wc -l returns 2` is flagged V1 and rewritten to the exact count (-eq 2)", L.lint_verify(w1)["findings"][0]["code"] == "V1" and L.lint_verify(w1)["findings"][0]["rewrite"] == 'test "$(grep -n "logger.exception" a/push_sender.py | wc -l)" -eq 2')
ok("D1 `| wc -l looks fine` (prose, no count) still gets NO rewrite", L.lint_verify('grep -n x a.py | wc -l looks fine')["findings"][0]["rewrite"] is None)
ok("D1 plain `| wc -l` keeps its rewrite", L.lint_verify("grep -n x f | wc -l")["findings"][0]["rewrite"] is not None)

# defect 7: window scan is not quadratic and absent target bails early
import time as _t
big = os.path.join(T, "bigtree")
mk(big, "big.py", "".join("def f%d():\n    pass\n" % i for i in range(5000)))
t0 = _t.time()
bigc = 'grep -A 1 "def " big.py | grep -q ZZZ_never'
res_big = L.lint_verify(bigc, big)
dt = _t.time() - t0
ok("D1 window: absent target on a 10k-line file is fast (<1.0s) and not a window finding", dt < 1.0 and not any(f["code"] == "S2" for f in res_big["findings"]), dt)
mk(big, "far.py", "def anchor():\n" + "    x = 1\n" * 20 + "    target_here = 1\n")
fr = L.lint_verify("grep -A 3 'def anchor' far.py | grep -q target_here", big)["findings"]
ok("D1 window: S2 result unchanged by the bisect rewrite (distance 21 -> -A 23)", fr and fr[0]["code"] == "S2" and "-A 23" in (fr[0]["rewrite"] or ""), fr)
mk(big, "back.py", "    target_b = 1\n" + "    x = 1\n" * 8 + "def anchor2():\n")
bk = L.lint_verify("grep -B 2 'def anchor2' back.py | grep -q target_b", big)["findings"]
ok("D1 window: -B direction still found", bk and bk[0]["code"] == "S2" and "-B 11" in (bk[0]["rewrite"] or ""), bk)

# planner/filter contract (what ovn_planner.sh relies on): shadow leaves stdout identical; enforce can empty the list
fenv = dict(os.environ, OVN_VERIFY_SHAPE_LOG=os.path.join(T, "pl.log"), OVN_VERIFY_ALERTS_LOG=os.path.join(T, "pl.alerts"))
one = "- [ ] [T1] a.py - x. VERIFY: `test -f x.py && echo exists || echo removed`. (cat:python)\n"
for mdv, expect_same in (("shadow", True), ("enforce", False)):
    rr = subprocess.run([sys.executable, os.path.join(SD, "ovn_verify_shape_lint.py"), "filter", "--repo", "r", "--dropped", os.path.join(T, "q_%s.md" % mdv)], input=one, capture_output=True, text=True, env=dict(fenv, OVN_VERIFY_LINT=mdv))
    ok("D1 filter CLI %s: %s" % (mdv, "stdout identical" if expect_same else "unfixable item dropped (n==0 path) and quarantined"),
       (rr.stdout == one) if expect_same else (rr.stdout == "" and os.path.isfile(os.path.join(T, "q_enforce.md")) and "verify-lint:V4" in open(os.path.join(T, "q_enforce.md")).read()), rr.stdout)


# ------------------------------------------------------------------ D1 repair round 2 (review defects 1-8)
print("== D1 repair 2: wc polarity from the item text / S1 single-line + path / U1 quoted / hang guards / U2 healed / V4a info")


def li(item, md="enforce", tree=None):
    return L.lint_item_line(item, tree, md)


def itm(text, clause):
    return "- [ ] [T1] a.py - %s VERIFY: `%s`%s (cat:python)" % (text, clause, "")


def runclause(clause):
    return subprocess.run(["bash", "-c", clause], cwd=RT, capture_output=True, text=True).returncode


# defect 1: `| wc -l` polarity comes from the item text
z_item = "- [x] [T1] a.py - Ensure no remaining imports of realtime_update_service. VERIFY: `grep -rh nomatch_zz . | wc -l` returns 0. (cat:python)"
d, out, _ = li(z_item)
ok("R2-1 absence item 'returns 0': enforce rewrites to -eq 0 (never -ge 1)", d == "rewritten" and '"$(grep -rh nomatch_zz . | wc -l)" -eq 0' in out and "-ge 1" not in out, (d, out))
nz = extract = L.extract_verify(out)[0]
ok("R2-1 the -eq 0 clause keeps the meaning when RUN: absent -> pass, present -> fail", runclause(nz) == 0 and runclause(nz.replace("nomatch_zz", "foo")) != 0)
d, out, _ = li("- [ ] [T1] a.py - Remove the stale helper. VERIFY: `grep -n helper a.py | wc -l`. (cat:python)")
ok("R2-1 absence wording without an explicit count: no rewrite, enforce DROPS (never a wrong -ge 1)", d == "dropped" and "-ge 1" not in out, (d, out))
d, out, _ = li("- [ ] [T1] a.py - Add handler foo. VERIFY: `grep -n foo a.py | wc -l`. (cat:python)")
ok("R2-1 presence item keeps -ge 1", d == "rewritten" and '-ge 1' in out, (d, out))
d, out, _ = li("- [ ] [T1] a.py - Replace x (returns 0 before, returns 3 after). VERIFY: `grep -n x a.py | wc -l`. (cat:python)")
ok("R2-1 conflicting 0 and positive count -> no rewrite (dropped)", d == "dropped", (d, out))
d, out, _ = li(z_item, "shadow")
ok("R2-1 shadow mode is unaffected: flagged, text untouched", d == "flagged" and out == z_item, d)
ok("R2-1 no item text (CLI check) keeps the historical -ge 1 presence rewrite", L.lint_verify("grep -n x f | wc -l")["findings"][0]["rewrite"] == 'test "$(grep -n x f | wc -l)" -ge 1')
real_done = os.path.join(HERE, "fixtures", "verify_shape_lint_absence_wc_items.tsv")
if os.path.isfile(real_done):
    bad_rw = 0
    n_rw = 0
    for ln in open(real_done):
        ln = ln.rstrip("\n")
        if not ln:
            continue
        d, out, _ = li(ln)
        if d == "rewritten":
            n_rw += 1
            bad_rw += 1 if "-ge 1" in out and re.search(r"(?:returns?|is)\s+0", ln) else 0
    ok("R2-1 real done items (absence 'returns 0') never get a -ge 1 rewrite (%d rewritten)" % n_rw, bad_rw == 0 and n_rw > 0, bad_rw)

# defect 2: S1 single-line import / def / same-span items
mk(T, "backend/app/routers/messages.py", "from fastapi import APIRouter\n")
imp = 'grep -n "from backend.app.security.scope import" backend/app/routers/messages.py | grep -q "require_wildcard_token"'
ok("R2-2 S1 silent for a single-line `from X import name` (p1 is an import prefix)", codes(imp) == [] and codes(imp, T) == [])
ok("R2-2 enforce keeps that item (not dropped)", li("- [ ] [T1] backend/app/routers/messages.py - Add `from backend.app.security.scope import require_wildcard_token`. VERIFY: `%s`. (cat:python)" % imp, "enforce", T)[0] == "ok")
span_clause = "grep -n 'max_length=100' search.py | grep -q search_suggestions"
span_item = "- [ ] [T1] search.py - Add `max_length=100` to `search_suggestions(q: str = Query(None, max_length=100))`. VERIFY: `%s`. (cat:python)" % span_clause
ok("R2-2 S1 silent when the item asks for p1 and p2 on ONE line (same quoted span)", li(span_item, "shadow")[0] == "ok", li(span_item, "shadow")[0])
ok("R2-2 control: without that item text the same clause is still S1", codes(span_clause) == ["S1"] and li(span_item.replace("`max_length=100` to `search_suggestions(q: str = Query(None, max_length=100))`", "the limit"), "shadow")[0] == "flagged")
ok("R2-2 control: a def/anchor split across lines is still S1", codes("grep -n '_github_retry.execute' backend/app/services/github.py | grep -q get_file_content") == ["S1"])

# defect 3: S1 and path-qualified output
mk(T, "app/parental_utils.py", "def f():\n    rating = 1\n")
mk(T, "app/a.py", "x = 1\n")
mk(T, "app/b.py", "y = 1\n")
ok("R2-3 S1 silent for `grep -rn ... app | grep -q parental_utils` (path in the output)", codes('grep -rn "rating" app | grep -q parental_utils', T) == [] and codes('grep -rn "rating" app | grep -q parental_utils') == [])
ok("R2-3 S1 silent for several files / -H / a directory operand / a glob", codes("grep -n rating app/a.py app/b.py | grep -q parental_utils") == []
   and codes("grep -nH rating app/a.py | grep -q parental_utils") == [] and codes("grep -n rating app | grep -q parental_utils", T) == [] and codes("grep -n rating app/*.py | grep -q parental_utils") == [])
ok("R2-3 control: one plain file is still S1", codes("grep -n rating app/a.py | grep -q parental_utils") == ["S1"])

# defect 4: U1 never edits quoted strings / grep patterns
for c in ('cd backend && grep -q "backend/app" app/main.py', 'cd app && grep -q "app/config" main.py', 'cd backend && grep -q "api/v1" backend_x.py',
          "cd backend && grep -q 'backend/app' app/main.py", "cd backend && grep -q backend/app app/main.py", 'cd backend && python3 -c "print(\'backend/app\')"'):
    ok("R2-4 U1 silent for a runnable clause with the dir name in a pattern: %s" % c[:60], codes(c) == [] and codes(c, T) == [], codes(c))
u1 = 'cd backend && grep -q "backend/app" backend/app/main.py'
rw = L.lint_verify(u1)["findings"][0]["rewrite"] if codes(u1) == ["U1"] else None
ok("R2-4 U1 still fires on the real double-prefix FILE operand and keeps the quoted pattern intact", rw == 'cd backend && grep -q "backend/app" app/main.py', rw)
mk(RT, "backend/app/main.py", "backend/app\n")
ok("R2-4 the original fails and the rewrite passes when RUN", rw is not None and runclause(u1) != 0 and runclause(rw) == 0)

# defect 5: hangs. Run every probe in a subprocess with a hard timeout so a regression fails instead of hanging the suite
HT = os.path.join(T, "hang")
mk(HT, "f.txt", "a" * 40 + "!\n")
mk(HT, "big.txt", "x\n" * 3000)
os.makedirs(os.path.join(HT, "d"), exist_ok=True)
fifo = os.path.join(HT, "fifo")
if not os.path.exists(fifo):
    os.mkfifo(fifo)
link0 = os.path.join(HT, "zero_link")
if not os.path.lexists(link0):
    os.symlink("/dev/zero", link0)
OUTSIDE = os.path.join(T, "outside_secret.txt")
mk(T, "outside_secret.txt", "secret\n")


def py(code, env=None, timeout=25):
    e = dict(os.environ)
    e.update(env or {})
    try:
        r = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, %r)\nimport ovn_verify_shape_lint as L\n%s" % (SD, code)], capture_output=True, text=True, timeout=timeout, env=e)
        return r.returncode, r.stdout.strip(), r.stderr[-300:]
    except subprocess.TimeoutExpired:
        return "TIMEOUT", "", ""


t0 = _t.time()
rc, o, er = py("print(L._read(%r, '/dev/zero'), L._read(%r, 'fifo'), L._read(%r, 'zero_link'), L._read(%r, '../outside_secret.txt'), L._read(%r, %r), L._read(%r, 'd'))" % ((HT,) * 3 + (HT, HT, OUTSIDE, HT)), timeout=15)
ok("R2-5 _read refuses /dev/zero, a FIFO, a symlink out of the tree, `..`, an absolute path and a directory (no hang)", rc == 0 and o == "None None None None None None", (rc, o, er))
rc, o, er = py("print(L._read(%r, 'big.txt') is None, L._read(%r, 'f.txt') is not None)" % (HT, HT), env={"OVN_VERIFY_LINT_MAX_READ": "1000"}, timeout=15)
ok("R2-5 _read refuses a file over the size cap and still reads a small one", rc == 0 and o == "True True", (rc, o, er))
rc, o, er = py("r = L.lint_verify('grep -n foo /dev/zero | grep -q my_func', %r); print(r['class'], 'S1' in [f['code'] for f in r['findings']])" % HT, timeout=15)
ok("R2-5 `grep -n foo /dev/zero | grep -q my_func --tree` returns promptly (S1 stays, evidence unreadable)", rc == 0 and o.endswith("True"), (rc, o, er))
rc, o, er = py("r = L.lint_verify('grep -n -E \"^(a+)+$\" f.txt | grep -q my_func', %r); print(r['class'], [f['code'] for f in r['findings']])" % HT, env={"OVN_VERIFY_LINT_BUDGET_S": "0"}, timeout=15)
ok("R2-5 a catastrophic-backtracking pattern is never run (heuristic alone: budget disabled) - no ReDoS", rc == 0, (rc, o, er))
rc, o, er = py("import re, time\nL._py_regex = lambda *a: re.compile(r'^(a+)+$')\nt = time.time()\nr = L.lint_verify('grep -n -E \"zz\" f.txt | grep -q my_func', %r)\nprint(r['class'], r.get('error', '')[:12], round(time.time() - t, 1) < 8)" % HT, env={"OVN_VERIFY_LINT_BUDGET_S": "1"}, timeout=25)
ok("R2-5 a regex the heuristic misses is cut by the time budget: fail-open OK + LintTimeout, bounded", rc == 0 and o.startswith("OK LintTimeout") and o.endswith("True"), (rc, o, er))
rc, o, er = py("import signal\nsignal.setitimer(signal.ITIMER_REAL, 50)\nr = L.lint_verify('grep -q x f | wc -l')\nleft = signal.getitimer(signal.ITIMER_REAL)[0]\nsignal.setitimer(signal.ITIMER_REAL, 0)\nprint(r['class'], left > 40)", timeout=15)
ok("R2-5 the budget never steals a host interval timer that is already armed", rc == 0 and o == "VACUOUS True", (rc, o, er))
rc, o, er = py("import signal\nh = signal.getsignal(signal.SIGALRM)\nL.lint_verify('grep -q x f | wc -l')\nprint(signal.getsignal(signal.SIGALRM) is h, signal.getitimer(signal.ITIMER_REAL)[0] == 0)", timeout=15)
ok("R2-5 the budget restores the previous SIGALRM handler and leaves no timer armed", rc == 0 and o == "True True", (rc, o, er))
ok("R2-5 the whole probe set stayed fast (<90s)", _t.time() - t0 < 90)

def hook_checks():
    """queue_refill enforce drop path + generate_items drop/rewrite path (review defect 8). QR/GI overridable for the hook mutants."""
    print("== hook checks: queue_refill / generate_items")
    qr = os.environ.get("VSL_QR") or os.path.abspath(os.path.join(SD, "..", "queue_refill.py"))
    gi = os.environ.get("VSL_GI") or os.path.join(SD, "ovn_generate_items.py")
    unfix_i = "- [ ] [T1] app/q.py — x. VERIFY: `grep -n '_zz.call' app/q.py | grep -q handle_everything`. (cat:python; multifile:no) [feat:t-9]"
    wc_i = "- [ ] [T1] app/x.py — add foo. VERIFY: `grep -n \"foo\" app/x.py | wc -l`. (cat:python; multifile:no) [feat:t-1]"
    keep_i = "- [ ] [T1] app/y.py — add bar. VERIFY: `grep -q \"bar\" app/y.py`. (cat:python; multifile:no) [feat:t-2]"

    def run_refill(md):
        d = tempfile.mkdtemp(prefix="vsl-hq-", dir=T)
        repo = os.path.join(d, "repo")
        os.makedirs(os.path.join(repo, "app"))
        open(os.path.join(repo, "OVERNIGHT_PROGRESS.md"), "w").write("# P\n\n## Next Steps\n")
        bl = os.path.join(d, "bl.md")
        open(bl, "w").write(unfix_i + "\n" + wc_i + "\n" + keep_i + "\n")
        env = dict(os.environ, OVN_VERIFY_LINT=md, OVN_VERIFY_SHAPE_LOG=os.path.join(d, "shape.log"), OVN_VERIFY_ALERTS_LOG=os.path.join(d, "al.log"), OVN_VERIFY_LINT_LOG=os.path.join(d, "malformed.log"))
        r = subprocess.run([sys.executable, qr, os.path.join(repo, "OVERNIGHT_PROGRESS.md"), bl, "5"], capture_output=True, text=True, env=env)
        prog = open(os.path.join(repo, "OVERNIGHT_PROGRESS.md")).read()
        qd = os.path.join(d, "quarantine")
        q = "".join(open(os.path.join(qd, f)).read() for f in sorted(os.listdir(qd))) if os.path.isdir(qd) else ""
        return r, prog, q, open(bl).read()
    r, prog, q, bl_left = run_refill("enforce")
    ok("hook queue_refill enforce: rc 0, the unfixable item is quarantined (tagged) and NOT queued", r.returncode == 0 and "QUARANTINED=1" in r.stdout and unfix_i not in prog and "handle_everything" in q and "|VL" not in prog, (r.returncode, r.stdout, r.stderr[-300:]))
    ok("hook queue_refill enforce: the fixable item is rewritten, the clean one queued untouched, the quarantined one leaves the backlog", '-ge 1' in prog and keep_i in prog and "handle_everything" not in bl_left, prog)
    r, prog, q, bl_left = run_refill("shadow")
    ok("hook queue_refill shadow: nothing quarantined, the unfixable item is still queued unchanged", r.returncode == 0 and "handle_everything" in prog and q == "" and "-ge 1" not in prog, (r.stdout, prog))
    # generate_items: the hook is a function so both outcomes are testable
    spec = importlib.util.spec_from_file_location("ovn_gi_t", gi)
    G = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(G)
    head = "\n### Auto-generated (deterministic scanner) — safe mechanical fixes"
    clean = "- [ ] [T1] [LOW] `app/m.py` (line 3): add a return type hint. One file."
    blk = head + "\n" + "\n".join([wc_i, unfix_i, clean]) + "\n"
    os.environ["OVN_VERIFY_SHAPE_LOG"] = os.path.join(T, "gi.log")
    os.environ["OVN_VERIFY_ALERTS_LOG"] = os.path.join(T, "gi.alerts")
    g_root = os.path.join(T, "gen2")
    os.makedirs(g_root, exist_ok=True)
    for md in ("off", "shadow"):
        os.environ["OVN_VERIFY_LINT"] = md
        ok("hook generate_items %s: block + count returned byte-identical" % md, G._lint_block(blk, 3, g_root) == (blk, 3))
    os.environ["OVN_VERIFY_LINT"] = "enforce"
    b2, n2 = G._lint_block(blk, 3, g_root)
    ok("hook generate_items enforce: rewrite applied AND the unfixable item dropped, count follows", n2 == 2 and "-ge 1" in b2 and "handle_everything" not in b2 and clean in b2 and b2.startswith(head), (n2, b2))
    rw_only = head + "\n" + "\n".join([wc_i, clean]) + "\n"
    b3, n3 = G._lint_block(rw_only, 2, g_root)
    ok("hook generate_items enforce: a REWRITE with no drop is applied too (was ignored)", n3 == 2 and "-ge 1" in b3 and "| wc -l`" not in b3, b3)
    b4, n4 = G._lint_block(head + "\n" + unfix_i + "\n", 1, g_root)
    ok("hook generate_items enforce: every item dropped -> empty block, count 0", (b4, n4) == ("", 0), (b4, n4))
    ok("hook generate_items enforce: a block with nothing to lint is returned untouched", G._lint_block(head + "\n" + clean + "\n", 1, g_root) == (head + "\n" + clean + "\n", 1))
    os.environ["OVN_VERIFY_LINT"] = "shadow"


if HOOKS_ONLY:
    hook_checks()
    print("hooks: %d pass, %d fail" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)


if CORE_ONLY:
    print("core: %d pass, %d fail" % (PASS, FAIL))
    sys.exit(1 if FAIL else 0)

# ------------------------------------------------------------------ modes
print("== modes + creation hooks")
LOG = os.path.join(T, "state", "shape.log")
ALR = os.path.join(T, "state", "alerts.log")
os.environ["OVN_VERIFY_SHAPE_LOG"], os.environ["OVN_VERIFY_ALERTS_LOG"] = LOG, ALR
bad = "- [ ] [T1] app/x.py — add foo. VERIFY: `grep -n \"foo\" app/x.py | wc -l`. (cat:python; multifile:no) [feat:t-1]"
vac_ok = "- [ ] [T1] app/y.py — add bar. VERIFY: `grep -q \"bar\" app/y.py`. (cat:python; multifile:no) [feat:t-2]"
nov = "- [ ] [T1] [HIGH] app/z.py — no verify clause here"
unsat = "- [ ] [T1] %s — wrap. VERIFY: `grep -n '_github_retry.execute' %s | grep -q get_file_content`. (cat:python)" % (gh, gh)
os.environ.pop("OVN_VERIFY_LINT", None)
ok("default mode is shadow", L.mode() == "shadow")
for v, exp in (("off", "off"), ("ENFORCE", "enforce"), ("bogus", "shadow")):
    os.environ["OVN_VERIFY_LINT"] = v
    ok("mode(%s) -> %s" % (v, exp), L.mode() == exp)
os.environ["OVN_VERIFY_LINT"] = "off"
k, d, n = L.process_lines([bad, vac_ok], T, "r", "t")
ok("off: untouched and nothing logged", k == [bad, vac_ok] and n == 0 and not os.path.exists(LOG) and not os.path.exists(ALR))
os.environ["OVN_VERIFY_LINT"] = "shadow"
k, d, n = L.process_lines([bad, vac_ok, nov, unsat], T, "r", "t")
ok("shadow: every line kept unchanged, 2 flagged, none dropped", k == [bad, vac_ok, nov, unsat] and n == 2 and d == [])
rows = [json.loads(x) for x in open(LOG)]
ok("shadow: JSON rows carry class, codes, reason, rewrite", [r["class"] for r in rows] == [L.VACUOUS, L.UNSAT] and rows[0]["codes"] == ["V1"] and rows[0]["rewrite"] and rows[1]["reasons"])
al = open(ALR).read().strip().split("\n")
ok("shadow: ONE alerts.log summary line for the run with the count", len(al) == 1 and "verify-lint" in al[0] and "2 of 4" in al[0], al)
os.environ["OVN_VERIFY_LINT"] = "enforce"
k, d, n = L.process_lines([bad, vac_ok, nov, unsat], T, "r", "t")
ok("enforce: V1 item rewritten, clean + no-verify items untouched", k[0] != bad and 'test \\"$(' not in k[0] and 'test "$(grep -n "foo" app/x.py | wc -l)" -ge 1' in k[0] and k[1:3] == [vac_ok, nov], k[0])
ok("enforce: the S1 item with a def-window rewrite is rewritten, not dropped", d == [] and "-A " in k[3] and L.lint_verify(L.extract_verify(k[3])[0], T)["class"] == L.OK, k[3][-160:])
unfix = "- [ ] [T1] app/q.py — x. VERIFY: `grep -n '_zz.call' app/q.py | grep -q handle_everything`. (cat:python)"
k, d, n = L.process_lines([unfix, vac_ok], T, "r", "t")
ok("enforce: an unfixable item is DROPPED (not kept, returned for quarantine)", k == [vac_ok] and len(d) == 1 and d[0][0] == unfix)
# filter CLI (planner hook) incl. dropped file
dropped_f = os.path.join(T, "q", "r.md")
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_verify_shape_lint.py"), "filter", "--tree", T, "--repo", "r", "--dropped", dropped_f],
                   input="\n".join([unfix, vac_ok, bad]) + "\n", capture_output=True, text=True, env=dict(os.environ))
out_lines = r.stdout.strip().split("\n")
ok("filter CLI (enforce): drops the unfixable, rewrites V1, keeps the clean one", r.returncode == 0 and len(out_lines) == 2 and out_lines[0] == vac_ok and "-ge 1" in out_lines[1], r.stdout + r.stderr)
ok("filter CLI wrote the dropped item to the quarantine file with a verify-lint tag", os.path.exists(dropped_f) and "verify-lint:S1" in open(dropped_f).read())

# ------------------------------------------------------------------ queue_refill integration (real script, tmp progress/backlog)
print("== queue_refill hook")
QR = os.path.abspath(os.path.join(SD, "..", "queue_refill.py"))


def refill(mode_):
    d = tempfile.mkdtemp(prefix="vsl-qr-", dir=T)
    repo = os.path.join(d, "repo")
    os.makedirs(os.path.join(repo, "app"))
    open(os.path.join(repo, "OVERNIGHT_PROGRESS.md"), "w").write("# P\n\n## Next Steps\n")
    bl = os.path.join(d, "bl.md")
    open(bl, "w").write(bad + "\n" + vac_ok + "\n")
    env = dict(os.environ, OVN_VERIFY_LINT=mode_, OVN_VERIFY_SHAPE_LOG=os.path.join(d, "shape.log"), OVN_VERIFY_ALERTS_LOG=os.path.join(d, "al.log"))
    r = subprocess.run([sys.executable, QR, os.path.join(repo, "OVERNIGHT_PROGRESS.md"), bl, "5"], capture_output=True, text=True, env=env)
    prog = open(os.path.join(repo, "OVERNIGHT_PROGRESS.md")).read()
    done = os.path.join(repo, "OVERNIGHT_DONE.md")
    return r, prog, (open(done).read() if os.path.exists(done) else ""), d


r, prog, done, d = refill("shadow")
ok("refill shadow: the vacuous item is logged and (old behaviour) still flows; alert count written", os.path.exists(os.path.join(d, "shape.log")) and "V1" in open(os.path.join(d, "shape.log")).read()
   and "verify-lint" in open(os.path.join(d, "al.log")).read(), r.stdout + r.stderr)
ok("refill shadow: item text is NOT rewritten", "| wc -l`" in prog + done)
r, prog, done, d = refill("enforce")
ok("refill enforce: the vacuous clause is rewritten BEFORE the credit check (no false pre-credit)", "-ge 1" in prog + done and "| wc -l`" not in prog + done, prog + done)
ok("refill enforce: the item with the rewritten clause was pulled, not credited", "pre-verified" not in done and "-ge 1" in prog, done)
r, prog, done, d = refill("off")
ok("refill off: no lint log at all", not os.path.exists(os.path.join(d, "shape.log")))

# ------------------------------------------------------------------ work_supply + generate_items hooks
print("== work_supply / generate_items hooks")
sys.path.insert(0, SD)
import importlib.util
spec = importlib.util.spec_from_file_location("ovn_work_supply_t", os.path.join(SD, "ovn_work_supply.py"))
WS = importlib.util.module_from_spec(spec)
spec.loader.exec_module(WS)
os.environ["OVN_VERIFY_LINT"] = "shadow"
keep = [({"k": 1}, bad, "red"), ({"k": 2}, vac_ok, "red")]
ok("work_supply shadow keeps both", [x[1] for x in WS._shape_lint_keep(keep, T, "r")] == [bad, vac_ok])
os.environ["OVN_VERIFY_LINT"] = "enforce"
res = WS._shape_lint_keep(keep + [({"k": 3}, unfix, "red")], T, "r")
ok("work_supply enforce rewrites V1 and drops the unfixable spec", len(res) == 2 and "-ge 1" in res[0][1] and res[1][1] == vac_ok)
GI = os.path.join(SD, "ovn_generate_items.py")
g = os.path.join(T, "gen")
mk(g, "app/m.py", "class A:\n    def __repr__(self):\n        return 'a'\n")
r = subprocess.run([sys.executable, GI, g, "5"], capture_output=True, text=True, env=dict(os.environ, OVN_VERIFY_LINT="enforce"))
hook_checks()
os.environ["OVN_VERIFY_LINT"] = "enforce"
ok("generate_items still emits its items with the hook in place", "GENERATED=" in r.stdout and r.returncode == 0, r.stdout + r.stderr)

# ------------------------------------------------------------------ audit CLI
print("== audit command")
au = os.path.join(T, "au")
os.makedirs(os.path.join(au, "backlog"))
open(os.path.join(au, "OVERNIGHT_PROGRESS.md"), "w").write("# P\n" + bad + "\n" + vac_ok + "\n- [x] done item. VERIFY: `grep -q x f || true`. (cat:x)\n")
open(os.path.join(au, "backlog", "r.md"), "w").write(unsat + "\n")
jf = os.path.join(au, "out.json")
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_verify_shape_lint.py"), "audit", au, "--tree", T, "--json", jf], capture_output=True, text=True)
rows = json.load(open(jf))
ok("audit: open items only (done [x] skipped), summary line counts", r.returncode == 0 and len(rows) == 3 and "items with VERIFY=3" in r.stdout and "VACUOUS=1" in r.stdout and "UNSATISFIABLE=1" in r.stdout, r.stdout)
ok("audit: prints reason and a rewrite suggestion", "rewrite:" in r.stdout and "V1" in r.stdout)
r = subprocess.run([sys.executable, os.path.join(SD, "ovn_verify_shape_lint.py"), "audit", au, "--all"], capture_output=True, text=True)
ok("audit --all includes the done item", "items with VERIFY=4" in r.stdout, r.stdout)

# ------------------------------------------------------------------ mutants
print("== mutants (each reverts one hunk; the core assertions must go red)")
SRC = open(os.path.join(SD, "ovn_verify_shape_lint.py")).read()
MUT = [
    ("V1 wc rule disabled", 'if base in ("wc", "head"', 'if base in ("zzz", "head"'),
    ("S2 window never fires", "p = bisect.bisect_left(m2, i + A + 1)", "p = bisect.bisect_left(m2, i + A + 1001)"),
    ("U1 rewrite no-op", "new = new[:a0] + new[b0:]", "new = new"),
    ("U2 candidate never unique", "len(cands) == 1", "len(cands) == 99"),
    ("V4 polarity lost", 'rw = "! ( %s )" % body   # `cmd', 'rw = body   # `cmd'),
    ("D1 exit1/exit0 pair handled as V2 again", 'argvs[-1][:2] == ["exit", "0"] and len(argvs[-1]) == 2 and argvs[-2][:2]', 'False and argvs[-2][:2]'),
    ("D1 polarity guesses on unclear", "    if g == b:\n        return None", "    if False:\n        return None"),
    ("D1 leading verdict ignored", "if words[0] in _GOOD_V:", "if False:"),
    ("D1 S1 fires on grep -v", 'if (g2["flags"] & set("vcLl"))', 'if False and (g2["flags"] & set("vcLl"))'),
    ("D1 U1 ignores cd ..", 'if _argv(s2[1])[:1] == ["cd"]:\n                break', 'if False:\n                break'),
    ("D1 wc extra args rewritten", 'elif extra[-1].isdigit() and all(w.lower() in _WC_WORDS for w in extra[:-1]):', 'elif True:'),

    ("S1 rule disabled", "if not (_is_literal(p2) and _fn_name_shape(p2)) or p2 in p1", "if True or p2 in p1"),
    ("enforce acts as shadow", 'if md != "enforce":\n        return "flagged", line, res', 'if True:\n        return "flagged", line, res'),
    ("off mode still lints", 'if md == "off":\n        return "ok", line, None', 'if False:\n        return "ok", line, None'),
    ("S5 rule disabled", "if not real or pat_s in real", "if True or pat_s in real"),
    ("R2 wc ignores an explicit 0 (always -ge 1)", 'if zero and not pos:\n        return "-eq 0"', 'if False:\n        return "-eq 0"'),
    ("R2 wc rewrites unclear/absence wording", "    if zero or absent:\n        return None", "    if False:\n        return None"),
    ("R2 S1 fires on import/def-prefix patterns", "if _DECL_PREFIX.match(p1):", "if False:"),
    ("R2 S1 fires on recursive/multi-file grep", "if _multi_path_grep(g1, tree):", "if False:"),
    ("R2 S1 ignores the item's same-line span", "if item is not None and _item_pairs(item, clause, p1, p2):", "if False:"),
    ("R2 U1 edits quoted strings", "if _quoted_at(seg, m.start()):", "if False:"),
    ("R2 U1 edits grep patterns", "if files is not None and m.group(0) not in files:", "if False:"),
    ("R2 _read follows a symlink/.. out of the tree", "if real != root and not real.startswith(root + os.sep):\n            return None", "if False:\n            return None"),
    ("R2 _read opens non-regular files", "if not _stat.S_ISREG(st.st_mode) or st.st_size > _MAX_READ:", "if st.st_size > _MAX_READ:"),
    ("R2 _read has no size cap", "or st.st_size > _MAX_READ:", "or False:"),
    ("R2 ReDoS heuristic off", "if _REDOS.search(rx) or len(rx) > 500:", "if False:"),
    ("R2 time budget never armed", "signal.setitimer(signal.ITIMER_REAL, seconds)\n                armed = True", "signal.setitimer(signal.ITIMER_REAL, 0)\n                armed = True"),
    ("R2 time budget steals a host timer", "if signal.getitimer(signal.ITIMER_REAL)[0] == 0:", "if True:"),
    ("R2 budget leaves the handler installed", "signal.signal(signal.SIGALRM, old_h if old_h is not None else signal.SIG_DFL)", "pass"),
    ("R2 U2 flags what the runner heals", "and _runner_heals_py_root(clause, tree, next(iter(cands)), missing):", "and False:"),
    ("R2 V4a counted as VACUOUS again", 'out.append(_find(clause, OK, "V4a"', 'out.append(_find(clause, VACUOUS, "V4a"'),
    ("U3 package check inverted", 'if tree and (os.path.isdir(os.path.join(tree, root + "_backend"))', 'if not tree or (os.path.isdir(os.path.join(tree, root + "_backend"))'),
]
for name, old, new in MUT:
    if old not in SRC:
        ok("[mut] %s: hunk present in source" % name, False, old)
        continue
    md = tempfile.mkdtemp(prefix="vsl-mut-", dir=T)
    open(os.path.join(md, "ovn_verify_shape_lint.py"), "w").write(SRC.replace(old, new, 1))
    r = subprocess.run([sys.executable, os.path.abspath(__file__), "--core"], capture_output=True, text=True, env=dict(os.environ, VSL_DIR=md))
    ok("[mut] %s -> core goes red" % name, r.returncode != 0)

# hook mutants (queue_refill / generate_items): each reverts one hunk in a COPY of the hook file; the --hooks checks must go red
HMUT = [
    ("queue_refill ignores a dropped item (None)", "queue_refill.py", os.path.abspath(os.path.join(SD, "..", "queue_refill.py")), "        if l2 is None:\n            continue", "        if False:\n            continue", "VSL_QR"),
    ("queue_refill never quarantines a dropped item", "queue_refill.py", os.path.abspath(os.path.join(SD, "..", "queue_refill.py")), 'quarantined.append((orig, "VL",', 'flagged.append((orig, "VL",', "VSL_QR"),
    ("generate_items ignores rewrites (drop-only condition)", "ovn_generate_items.py", os.path.join(SD, "ovn_generate_items.py"), "if _dropped or _kept != _lines:", "if _dropped:", "VSL_GI"),
    ("generate_items hook never applies", "ovn_generate_items.py", os.path.join(SD, "ovn_generate_items.py"), "if _dropped or _kept != _lines:", "if False:", "VSL_GI"),
    ("generate_items keeps an empty header", "ovn_generate_items.py", os.path.join(SD, "ovn_generate_items.py"), "            if not _kept:\n                return \"\", 0\n", "", "VSL_GI"),
]
for name, base, path, old, new, envk in HMUT:
    src = open(path).read()
    if old not in src:
        ok("[mut] %s: hunk present in source" % name, False, old)
        continue
    md = tempfile.mkdtemp(prefix="vsl-hmut-", dir=T)
    os.symlink(SD, os.path.join(md, "scripts"))   # queue_refill resolves its helper modules via <its dir>/scripts
    open(os.path.join(md, base), "w").write(src.replace(old, new, 1))
    r = subprocess.run([sys.executable, os.path.abspath(__file__), "--hooks"], capture_output=True, text=True, env=dict(os.environ, **{envk: os.path.join(md, base)}), timeout=300)
    ok("[mut] %s -> hook checks go red" % name, r.returncode != 0)

print("RESULT: %d pass, %d fail" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
