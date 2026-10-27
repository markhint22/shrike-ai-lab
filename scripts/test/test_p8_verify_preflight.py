#!/usr/bin/env python3
"""P8 (2026-10-26): VERIFY / item pre-flight + observability (deterministic code only).

 A  verify lint A1: `ast.FunctionDef` with no AsyncFunctionDef used to find a function that is `async def` in the tree (gitlark add_reaction: IndexError on every run) - can never pass.
 B  verify lint H1: `python -c 'from iptv-backend.app... import x'` (a hyphen in a module path) is a SyntaxError at the clause itself.
    Both ride OVN_VERIFY_ASYNC_LINT=off|shadow|enforce (default shadow: logged, never rewritten/dropped); off = not produced.
 C  scout guard: an ABSOLUTE path outside the repo (the aider venv's python3.12 in the plan text) is not a force-load target: it was dropped as "oversize" (10 noise lines).
 D  digest: the gpu_sinks repeat counter is keyed by (feat_tag|item_hash, item_line_hash) so sibling items of one feature no longer merge (a landed sibling hid its failing twin).
 E  outcome_acct landed-late rows carry item_line_hash.

Env: P8_SD = scripts dir under test (default ..), P8_Q = queue root (default ../..). The wrapper test_p8_verify_preflight.sh runs this in a private TMPDIR and re-runs it against
mutants (one reverted hunk each) which must FAIL. Exit 0 = all pass."""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SD = os.environ.get("P8_SD") or os.path.abspath(os.path.join(HERE, ".."))
Q = os.environ.get("P8_Q") or os.path.abspath(os.path.join(SD, ".."))
sys.path.insert(0, SD)
PASS = FAIL = 0


def ok(name, cond, extra=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print("  PASS " + name)
    else:
        FAIL += 1
        print("  FAIL %s %s" % (name, extra))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


L = load(os.path.join(SD, "ovn_verify_shape_lint.py"), "p8_lint")
TMP = tempfile.mkdtemp(prefix="p8t.")


def mk(rel, text=""):
    p = os.path.join(TMP, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write(text)
    return p


def codes(r):
    return sorted(f["code"] for f in r["findings"])


class with_env:
    def __init__(self, **kw):
        self.kw = kw

    def __enter__(self):
        self.old = {k: os.environ.get(k) for k in self.kw}
        for k, v in self.kw.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def __exit__(self, *a):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


# ---------------------------------------------------------------- A: async-aware AST lint
tree = os.path.join(TMP, "gl")
mk("gl/app/services/reactions.py", "class R:\n    async def add_reaction(self, x):\n        return x\n\n    def plain(self):\n        return 1\n")
SYNC_CLAUSE = ("python3 -c \"import ast;t=ast.parse(open('app/services/reactions.py').read());"
               "print([n for n in ast.walk(t) if isinstance(n, ast.FunctionDef) and n.name=='add_reaction'][0].name)\"")
ASYNC_CLAUSE = SYNC_CLAUSE.replace("ast.FunctionDef", "(ast.FunctionDef, ast.AsyncFunctionDef)")
PLAIN_CLAUSE = SYNC_CLAUSE.replace("add_reaction", "plain")
with with_env(OVN_VERIFY_ASYNC_LINT=None):
    r = L.lint_verify(SYNC_CLAUSE, tree)
    ok("A1 FunctionDef-only search for an `async def` target (tree) is flagged A1 UNSATISFIABLE", codes(r) == ["A1"] and r["class"] == L.UNSAT, str(r))
    ok("A2 the AsyncFunctionDef variant is NOT flagged", codes(L.lint_verify(ASYNC_CLAUSE, tree)) == [])
    ok("A3 FunctionDef search for a plain `def` target is NOT flagged", codes(L.lint_verify(PLAIN_CLAUSE, tree)) == [])
    item = "- [ ] [T2] app/services/reactions.py - make `async def add_reaction` idempotent. VERIFY: `%s` (cat:python)" % SYNC_CLAUSE
    ok("A4 no tree: the item text saying `async def add_reaction` is the evidence", codes(L.lint_verify(SYNC_CLAUSE, None, item)) == ["A1"])
    ok("A5 no tree and no async evidence: silent (rules only fire on evidence)", codes(L.lint_verify(SYNC_CLAUSE, None, "- [ ] [T2] x. VERIFY: `true`")) == [])
    rw = ((r["findings"] or [{}])[0].get("rewrite")) or ""
    ok("A6 mechanical rewrite widens isinstance to (FunctionDef, AsyncFunctionDef) and re-lints OK", "AsyncFunctionDef" in rw and codes(L.lint_verify(rw, tree)) == [], rw)
    fx, left = L.fix_clause(SYNC_CLAUSE, tree, gate=False)
    ok("A7 fix_clause converges when the gate is open", not left and "AsyncFunctionDef" in fx)
    # the rewritten clause really finds the function (end to end, real python)
    out = subprocess.run(["bash", "-c", "cd '%s' && %s" % (tree, rw)], capture_output=True, text=True)
    orig = subprocess.run(["bash", "-c", "cd '%s' && %s" % (tree, SYNC_CLAUSE)], capture_output=True, text=True)
    ok("A8 the rewritten clause actually exits 0 on the real tree; the original exits non-zero", out.returncode == 0 and orig.returncode != 0, out.stderr[-200:])
    nr = L.lint_verify(SYNC_CLAUSE.replace("isinstance(n, ast.FunctionDef)", "type(n) == ast.FunctionDef"), tree)
    ok("A9 `type(n) == ast.FunctionDef` (not an isinstance arg) is flagged but gets NO rewrite", codes(nr) == ["A1"] and not nr["findings"][0].get("rewrite"))
    NAMEF = SYNC_CLAUSE.replace("isinstance(n, ast.FunctionDef)", "type(n).__name__=='FunctionDef'")
    nf = L.lint_verify(NAMEF, tree)
    ok("A10 `type(n).__name__=='FunctionDef'` is flagged A1, no rewrite", codes(nf) == ["A1"] and not nf["findings"][0].get("rewrite"), str(nf))
    nf = L.lint_verify(SYNC_CLAUSE.replace("isinstance(n, ast.FunctionDef)", "n.__class__ is ast.FunctionDef"), tree)
    ok("A11 `n.__class__ is ast.FunctionDef` is flagged A1, no rewrite", codes(nf) == ["A1"] and not nf["findings"][0].get("rewrite"), str(nf))
    ok("A12 the by-name form with AsyncFunctionDef also matched is NOT flagged", codes(L.lint_verify(NAMEF.replace("'FunctionDef'", "'FunctionDef' or n.__class__.__name__=='AsyncFunctionDef'"), tree)) == [])
    ok("A13 a plain-def target by name is NOT flagged", codes(L.lint_verify(NAMEF.replace("add_reaction", "plain"), tree)) == [])

# ---------------------------------------------------------------- B: hyphenated import
HY = "python3 -c 'from iptv-backend.app.main import app; print(app.title)'"
with with_env(OVN_VERIFY_ASYNC_LINT=None):
    for nm, cl in (("B10 prose `removed from user-facing text` in print()", "python3 -c \"print('removed from user-facing text')\""),
                   ("B11 prose `copy from foo-bar now` in print()", "python3 -c \"print('copy from foo-bar now')\""),
                   ("B12 import word inside a string literal", "python3 -c \"x='import foo-bar'; print(x)\"")):
        ok(nm + " is NOT flagged H1", codes(L.lint_verify(cl, None)) == [], str(L.lint_verify(cl, None)))
    ok("B13 real import after `;` is still flagged", codes(L.lint_verify("python3 -c \"import os; from foo-bar.x import y\"", None)) == ["H1"])
    ok("B14 real import on a later line of a multi-line source is still flagged", codes(L.lint_verify("python3 -c 'import os\nimport foo-bar.x'", None)) == ["H1"])
    r = L.lint_verify(HY, None)
    ok("B1 `from iptv-backend.app.main import app` is flagged H1 UNRUNNABLE", codes(r) == ["H1"] and r["class"] == L.UNRUN, str(r))
    mk("hy/iptv-backend/app/__init__.py", "")
    r = L.lint_verify(HY, os.path.join(TMP, "hy"))
    rw = ((r["findings"] or [{}])[0].get("rewrite")) or ""
    ok("B2 with the tree: rewrite is cd iptv-backend && ... from app.main import app", rw.startswith("cd iptv-backend && python3 -c 'from app.main import app"), str(r))
    ok("B3 the rewrite re-lints OK", codes(L.lint_verify(rw, os.path.join(TMP, "hy"))) == [] if rw else False)
    ok("B4 `import billwatch-backend.app` flagged too", codes(L.lint_verify("python -c 'import billwatch-backend.app'", None)) == ["H1"])
    ok("B5 underscore package is NOT H1", codes(L.lint_verify("python3 -c 'from iptv_backend_x import app'", None)) == [])
    ok("B6 hyphenated text inside a grep pattern (no python -c) is NOT H1", codes(L.lint_verify("grep -n 'from some-thing import' a.py", None)) == [])
    ok("B7 an already-correct `cd iptv-backend && python -c 'from app.x import y'` is NOT H1", codes(L.lint_verify("cd iptv-backend && python -c 'from app.x import y'", None)) == [])

# ---------------------------------------------------------------- modes
CL = SYNC_CLAUSE
with with_env(OVN_VERIFY_ASYNC_LINT="off"):
    ok("M1 OVN_VERIFY_ASYNC_LINT=off: A1/H1 not produced", codes(L.lint_verify(CL, tree)) == [] and codes(L.lint_verify(HY, None)) == [])
with with_env(OVN_VERIFY_ASYNC_LINT="bogus"):
    ok("M2 unknown value falls back to shadow (produced)", codes(L.lint_verify(CL, tree)) == ["A1"])
line = "- [ ] [T2] app/services/reactions.py - x. VERIFY: `%s` (cat:python)" % CL
with with_env(OVN_VERIFY_ASYNC_LINT=None, OVN_VERIFY_LINT="enforce", OVN_VERIFY_LINT_P5=None):
    d, out, res = L.lint_item_line(line, tree)
    ok("M3 shadow (default) under OVN_VERIFY_LINT=enforce: flagged, line UNCHANGED", d == "flagged" and out == line and codes(res) == ["A1"], d)
    d, out, res = L.lint_item_line("- [ ] [T2] x. VERIFY: `%s` (cat:python)" % HY, None)
    ok("M4 shadow H1: flagged, line unchanged", d == "flagged" and "iptv-backend" in out, d)
with with_env(OVN_VERIFY_ASYNC_LINT="enforce", OVN_VERIFY_LINT="enforce", OVN_VERIFY_LINT_P5=None):
    d, out, res = L.lint_item_line(line, tree)
    ok("M5 enforce: A1 rewritten at creation", d == "rewritten" and "AsyncFunctionDef" in out, d)
with with_env(OVN_VERIFY_ASYNC_LINT="enforce", OVN_VERIFY_LINT="enforce", OVN_VERIFY_LINT_P5="off"):
    d, out, res = L.lint_item_line(line, tree)
    ok("M6 P5 switch off does not disable A1 enforcement (independent switches)", d == "rewritten", d)
with with_env(OVN_VERIFY_ASYNC_LINT=None, OVN_VERIFY_LINT="enforce", OVN_VERIFY_LINT_P5="enforce"):
    d, out, res = L.lint_item_line(line, tree)
    ok("M7 P5=enforce does not drag A1 into enforcement", d == "flagged" and out == line, d)

# ---------------------------------------------------------------- C: scout guard absolute path
pu = load(os.path.join(Q, "ovn_park_unworkable.py"), "p8_park")
repo = os.path.join(TMP, "repo")
mk("repo/app/ok.py", "x\n")
mk("repo/app/big.py", "a" * 130000)
mk("outside/aider-venv/bin/python3.12", "a" * 400000)
OUT = os.path.join(TMP, "outside/aider-venv/bin/python3.12")
ITEM = "- [ ] [T2] app/ok.py - x"
d, why = pu.scout_guard(repo, [OUT], ITEM, 120000)
ok("C1 absolute path OUTSIDE the repo (aider venv python) is rejected: not dropped, not unworkable", d == [] and why is None, str((d, why)))
d, why = pu.scout_guard(repo, [OUT, "app/ok.py"], ITEM, 120000)
ok("C2 ... and with a real sibling the verdict is unchanged", d == [] and why is None)
d, why = pu.scout_guard(repo, ["../outside/aider-venv/bin/python3.12", "app/ok.py"], ITEM, 120000)
ok("C3 a ../ escape out of the repo is rejected too", d == [] and why is None, str((d, why)))
d, why = pu.scout_guard(repo, ["app/big.py", "app/ok.py"], ITEM, 120000)
ok("C4 in-repo relative oversize path is still DROPPED", [t for t, _ in d] == ["app/big.py"] and why is None, str((d, why)))
d, why = pu.scout_guard(repo, [os.path.join(repo, "app/big.py"), "app/ok.py"], ITEM, 120000)
ok("C5 in-repo ABSOLUTE oversize path is kept as a candidate (checked repo-relative) and still dropped under its ORIGINAL spelling (the shell removes it by that token)", [t for t, _ in d] == [os.path.join(repo, "app/big.py")], str((d, why)))
mk("repo/.queue-hard-banned-files", "app/banned.py\n")
mk("repo/app/banned.py", "x\n")
d, why = pu.scout_guard(repo, [os.path.join(repo, "app/banned.py")], "- [ ] [T2] app/banned.py - x", 120000)
ok("C6 in-repo absolute path matches the ban list after normalisation", bool(d) and "hard-banned" in d[0][1] and bool(why), str((d, why)))
cp = subprocess.run([sys.executable, os.path.join(Q, "ovn_park_unworkable.py"), "--scout-guard", repo, "120000", os.devnull], input=OUT + "\napp/ok.py\n", capture_output=True, text=True)
ok("C7 CLI: nothing printed for an out-of-repo absolute path", cp.stdout.strip() == "", cp.stdout)
ok("C8 benign twin: _check on a missing in-repo file is still None", pu._check("app/nope.py", repo, [], 120000) is None)

# ---------------------------------------------------------------- D: digest line-hash split
dg = load(os.path.join(SD, "ovn_daily_fail_digest.py"), "p8_digest")
NOW = 1760200000.0


def iso(h):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(NOW - h * 3600))


def row(h, cls, dur, feat="F-feat", ih="ffff", lh=None):
    r = {"ts": iso(h), "repo": "iptv_apps", "id": "ongoing-iptv_apps", "type": "aider_fix", "tier": "2", "category": "python", "class": cls, "severity": "bad" if cls != "landed" else "good",
         "attempt": 1, "attempts": 1, "bestn_stop": "", "fail_reason": "", "status": "x", "tokens_sent": 10, "tokens_recv": 10, "duration_s": dur, "item_hash": ih, "feat_tag": feat}
    if lh is not None:
        r["item_line_hash"] = lh
    return r


def digest(rows, **env):
    st = os.path.join(tempfile.mkdtemp(dir=TMP), "state")
    os.makedirs(st)
    with open(os.path.join(st, "outcomes.jsonl"), "w") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    with with_env(**env):
        return dg.build(st, hours=24.0, now=NOW, top=10)


sib = [row(5, "noop", 400, lh="aaaa1111"), row(4, "noop", 300, lh="aaaa1111"), row(3, "landed", 100, lh="bbbb2222")]
d = digest(sib)
sinks = d["gpu_sinks"]
ok("D1 two siblings of ONE feature (one landed, one only failing): the failing sibling is a sink", len(sinks) == 1 and sinks[0]["seconds"] == 700 and sinks[0]["cycles"] == 2, str(sinks))
ok("D2 the sink label carries the line hash so siblings are distinguishable", bool(sinks) and "aaaa1111" in sinks[0]["item"], str(sinks))
d = digest([row(5, "noop", 400, lh="aaaa1111"), row(4, "noop", 300, lh="cccc3333")])
ok("D3 two failing siblings are TWO sinks with their own cycle counts", sorted((s["cycles"], s["seconds"]) for s in d["gpu_sinks"]) == [(1, 300), (1, 400)], str(d["gpu_sinks"]))
d = digest([row(5, "noop", 400), row(4, "noop", 300)])
ok("D4 legacy rows without item_line_hash still group exactly as before (label = feat_tag)", len(d["gpu_sinks"]) == 1 and d["gpu_sinks"][0]["item"] == "F-feat" and d["gpu_sinks"][0]["cycles"] == 2, str(d["gpu_sinks"]))
d = digest(sib, OVN_DIGEST_LINE_SPLIT="off")
ok("D5 OVN_DIGEST_LINE_SPLIT=off restores the old merge (landed sibling hides the failing one)", d["gpu_sinks"] == [], str(d["gpu_sinks"]))
d = digest([row(5, "noop", 400, feat="", ih="h1", lh="aaaa1111"), row(4, "noop", 300, feat="", ih="h1", lh="aaaa1111")])
ok("D6 no feat_tag: keyed by item_hash + line hash, one entry", len(d["gpu_sinks"]) == 1 and d["gpu_sinks"][0]["cycles"] == 2, str(d["gpu_sinks"]))

# ---------------------------------------------------------------- E: outcome_acct landed-late copies item_line_hash
src = open(os.path.join(SD, "ovn_outcome_acct.py")).read()
ok("E1 ovn_outcome_acct landed-late row copies item_line_hash", "item_line_hash" in src)

print("p8 verify preflight (python): pass=%d fail=%d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
