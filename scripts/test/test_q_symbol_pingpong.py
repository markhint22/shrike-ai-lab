#!/usr/bin/env python3
"""q-mon-fixes (2026-11-23): SYMBOL-SHAPE ping-pong detector (SHADOW only) in scripts/ovn_pingpong_guard.py.
Real fixture: fixtures_qmon/taa_plan_lint_codes.patchlog = verbatim `git log -p -U0 --format=@@%H|%ct|%s` of test-automation-agent backend/app/utils/plan_lint.py, where PLAN_LINT_CODES
flipped tuple <-> dict over 17 commits (the literal detector sees nothing: those lines carry no literal). Each check is repeated against a one-line MUTANT and must FAIL there."""
import importlib.util, os, shutil, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
SRC = open(os.path.join(SCRIPTS, "ovn_pingpong_guard.py"), encoding="utf-8").read()
FIX = open(os.path.join(HERE, "fixtures_qmon", "taa_plan_lint_codes.patchlog"), encoding="utf-8").read()
P = F = 0
def ok(n, c, x=""):
    global P, F
    if c: P += 1; print("  ok   " + n)
    else: F += 1; print("  FAIL " + n + ((" :: " + str(x)[:300]) if x else ""))
_n = [0]
def load(src, state=None):
    _n[0] += 1; d = os.path.realpath(tempfile.mkdtemp(prefix="symmod-"))
    open(os.path.join(d, "ovn_pingpong_guard.py"), "w", encoding="utf-8").write(src); shutil.copy(os.path.join(SCRIPTS, "ovn_churn_guard.py"), d)
    if state: os.environ["OVN_STATE_DIR"] = state
    sys.modules.pop("ovn_churn_guard", None); sys.path.insert(0, d)
    try:
        sp = importlib.util.spec_from_file_location("sym_%d" % _n[0], os.path.join(d, "ovn_pingpong_guard.py")); m = importlib.util.module_from_spec(sp); sp.loader.exec_module(m)
    finally: sys.path.remove(d)
    return m
def mut(old, new):
    if SRC.count(old) != 1: ok("mutation anchor once: %r" % old[:50], False, SRC.count(old)); return None
    return SRC.replace(old, new)
R = load(SRC)
NOW = 10 ** 6
def commit(i, rem, add, path="a.py", t=None):
    return {"sha": "%040x" % i, "t": t or (NOW - 1000 + i), "s": "feat: c%d" % i, "hunks": [(path, rem, add)], "ctx": [""]}
def flips(shapes, path="a.py"):
    """commits replacing `X: <a> = <open>` successively; shapes = list of (annotation, opener)"""
    out = []; prev = None
    for i, (ann, op) in enumerate(shapes):
        line = "X%s = %s" % ((": " + ann) if ann else "", op)
        out.append(commit(i + 1, [prev] if prev else [], [line], path)); prev = line
    return out
# 1 real fixture
cs = R.parse_patches(FIX); f = R.detect_symbol_shape(cs, max(c["t"] for c in cs) + 1, window_h=10 ** 6)
ok("1 real PLAN_LINT_CODES history -> one symbol-shape finding", len(f) == 1 and f[0]["name"] == "PLAN_LINT_CODES" and f[0]["file"].endswith("plan_lint.py"), f)
ok("2 finding counts >= 3 commits with revisits (dict<->tuple)", f and f[0]["n"] >= 3 and f[0]["revisits"] >= 1 and "dict|{" in f[0]["shapes"] and "tuple|(" in f[0]["shapes"])
ok("3 the LITERAL detector is blind to it (why this detector exists)", R.detect(cs, max(c["t"] for c in cs) + 1, window_h=10 ** 6) == [])
# synthetic
A, B = ("dict[str, str]", "{"), ("tuple[str, ...]", "(")
ok("4 A,B,A,B over 4 commits fires", len(R.detect_symbol_shape(flips([A, B, A, B]), NOW)) == 1)
ok("5 A,B,A (3 commits, revisit) fires at default min 3", len(R.detect_symbol_shape(flips([A, B, A]), NOW)) == 1)
ok("6 forward-only A,B,C is progress, never a ping-pong", R.detect_symbol_shape(flips([A, B, ("list[str]", "[")]), NOW) == [])
LA, LB = "X: dict[str, str] = {", "X: tuple[str, ...] = ("
TWO = [commit(1, [LA], [LB]), commit(2, [LB], [LA])]   # seed A -> B -> A: two flips WITH a revisit, still below the 3-commit minimum
ok("7 two flips with a revisit stay quiet (< 3 commits)", R.detect_symbol_shape(TWO, NOW) == [])
ok("8 the same shape restated is not a flip", R.detect_symbol_shape(flips([A, A, A, A]), NOW) == [])
ok("9 a non-structural scalar (X = 5 <-> X = {) is NOT a symbol-shape finding (literal detector's job)", R.detect_symbol_shape(flips([("", "5"), ("", "{"), ("", "5"), ("", "{")]), NOW) == [])
ok("10 non-code files (yaml) are ignored", R.detect_symbol_shape(flips([A, B, A, B], path="conf.yaml"), NOW) == [])
ok("11 two different files with the same symbol name do not merge", R.detect_symbol_shape(flips([A, B], "a.py")[:2] + flips([A, B], "b.py")[:0] + [commit(9, ["X: dict[str, str] = {"], ["X: tuple[str, ...] = ("], "b.py")], NOW) == [])
ok("12 bookkeeping-only / out-of-window commits are ignored", R.detect_symbol_shape(flips([A, B, A, B]), NOW + 10 ** 7) == [])
def tsflips():
    out = []; prev = None
    for i, op in enumerate(["{", "[", "{", "["]):
        line = "export const K = " + op; out.append(commit(i + 1, [prev] if prev else [], [line], "k.ts")); prev = line
    return out
ok("13 TS const object<->array flip fires", len(R.detect_symbol_shape(tsflips(), NOW)) == 1)
# mutants
m1 = load(mut("        if revisits < 1:\n            continue\n        bysha = collections.OrderedDict((c[\"sha\"], c) for c, _ in st[\"events\"])", "        bysha = collections.OrderedDict((c[\"sha\"], c) for c, _ in st[\"events\"])"))
ok("15 MUTANT without the revisit rule flags forward-only edits (check 6 fails)", m1.detect_symbol_shape(flips([A, B, ("list[str]", "[")]), NOW) != [])
m2 = load(mut("        if len(shas) < min_n:\n            continue\n        walk, revisits", "        if len(shas) < 1:\n            continue\n        walk, revisits"))
ok("16 MUTANT without the min-commits rule flags two flips (check 7 fails)", m2.detect_symbol_shape(TWO, NOW) != [])
m3 = load(mut('    if opener in ("scalar", "?") and not base:\n        return None, None', "    pass"))
ok("17 MUTANT that tracks bare scalars flags scalar<->dict (check 9 fails)", m3.detect_symbol_shape(flips([("", "5"), ("", "{"), ("", "5"), ("", "{")]), NOW) != [])
m4 = load(mut('or not path.endswith((".py", ".ts", ".tsx", ".js", ".jsx", ".mjs"))', ""))
ok("18 MUTANT without the file-type filter flags a .yaml file (check 10 fails)", m4.detect_symbol_shape(flips([A, B, A, B], path="conf.yaml"), NOW) != [])
# shadow-only: no enforce path, logs only
st = os.path.realpath(tempfile.mkdtemp(prefix="symstate-")); S = load(SRC, st)
S.symbol_shadow_log("taa", f[0]); S.symbol_shadow_log("taa", f[0])
lg = open(os.path.join(st, "pingpong_shadow.log")).read().splitlines() if os.path.exists(os.path.join(st, "pingpong_shadow.log")) else []
ok("19 shadow log: exactly ONE row per (repo, symbol, commit set), kind symbol-shape, would-park=0", len(lg) == 1 and "symbol-shape-pingpong" in lg[0] and "would-park=0" in lg[0] and "PLAN_LINT_CODES" in lg[0], lg)
ok("20 default mode is shadow and there is no enforce branch for symbol findings", R.SYMBOL_MODE == "shadow" and "SYMBOL_MODE == \"enforce\"" not in SRC and "symbol" not in SRC.split("def apply_and_push")[1].split("def once")[0])
ok("21 py_compile clean", __import__("py_compile").compile(os.path.join(SCRIPTS, "ovn_pingpong_guard.py"), doraise=True) is not None)
print("q-symbol-pingpong: %d passed, %d failed" % (P, F)); sys.exit(1 if F else 0)
