#!/usr/bin/env python3
"""scripts/ovn_work_supply.py - deterministic work supply: FINISHED backlog items, no model in the loop (2026-10-08).

Why (architecture rework 1, "supply"): the roadmap -> planner -> backlog chain asks a local 27B to (a) invent work from thin evidence and (b) write
the VERIFY clause for it. Both steps were the dominant source of last night's failures: 16 of 54 bad attempts were "rate-limit X router" /
"log swallowed exception" items whose model-written tests could not pass (global limiter disabled in tests, 13-route routers, VERIFYs that
grep for strings that never occur). Mechanical gaps need neither invention nor a model-written check.

How: collectors read the checkout and emit one small, single-file spec per gap; the item text AND its VERIFY (an `ast`/regex one-liner that is
RED before the change and GREEN after, with no test authoring needed) are produced by templates. Specs only enter backlog/<repo>.md after
ovn_spec_check.sh confirms the VERIFY really FAILS on the current checkout (red-before; a spec that already passes is dropped, one that cannot
run is rejected). The existing stage-runner gates (build/tests/antigaming) still decide whether the landing is accepted.

Kinds (all single file, <= 6 symbols per item, tier T2):
  swallowed-exception   py:  `except ...: pass` handler(s) -> log them
  no-rate-limit         py:  router with <= 4 routes and no @limiter.limit -> decorate (+ `request` param)
  missing-return-none   py:  app/{services,core,jobs} functions with no `return <value>` and no `->` -> add `-> None`
  gd-missing-void       gd:  functions with no `return <value>` and no `->` -> add `-> void`
  missing-return-type   py:  functions that return a value but have no annotation -> the model infers it (typing items land ~92%)
  missing-docstring     py:  public functions/classes (>= 5 body lines) without a docstring
  gd-missing-doc        gd:  public functions without a `##` doc comment
  pure-function-tests   py:  public side-effect-free functions no test mentions -> a NEW tests/test_<module>_pure.py with concrete asserts (no mocks)
  unused-import         py:  ruff F401 unused imports (T1)
  ruff-F601/F811/F841/B904/RUF013  py:  ruff bug-class findings (allowlist OVN_SUPPLY_RUFF_RULES, default F601,F811; never B008/E712/S*)
  mission-spawn-on-obstacle  tres: xlite missions whose enemy/player spawn lies on a blocking obstacle (scripts/ovn_mission_lint.py)

v2 (2026-10-09): the "already supplied?" filter is per backlog LINE (not kind and file anywhere in the text), a done item whose gap is still there is
re-supplied after a cooldown (capped), only a conclusive verdict is remembered (a flaky spec check never poisons the seen file), the key carries a hash of
the gap's symbols, and `--on-exhausted` lets the runner kick a pass the moment a lane runs dry.

usage: ovn_work_supply.py <repo> [--dry-run] [--max N] [--no-spec-check] [--force] [--on-exhausted]
env:   OVN_DIR (default ~/overnight-queue); OVN_SUPPLY_MIN_BACKLOG (default 24: only supply when the repo's pullable items are below this)
       OVN_SUPPLY_RESUPPLY_COOLDOWN_S (7200)  OVN_SUPPLY_RUFF_RULES (F601,F811)  OVN_SUPPLY_GD_DOCS (off)  OVN_SUPPLY_MUTATION (unset: external collector off)
       OVN_WORK_SUPPLY=off kills the whole thing.
exit:  0 always; prints a "N gaps found, M filtered (...), K specs" line and an ADDED/DRY-RUN line.
"""
import ast
import datetime
import fcntl
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
MIN_BACKLOG = int(os.environ.get("OVN_SUPPLY_MIN_BACKLOG", "24"))
DEFAULT_MAX = 12
RESUPPLY_COOLDOWN_S = int(os.environ.get("OVN_SUPPLY_RESUPPLY_COOLDOWN_S", "7200"))  # a done item's gap must still exist this long after the supply before it is supplied again
RESUPPLY_CAP = 2          # re-supplies per (kind, file, gap): a fix the fleet keeps crediting without making must not loop forever
ON_EXHAUSTED_MIN_INTERVAL_S = 300
MAX_SYMBOLS = 6
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".godot", "dist", "build", "addons", "htmlcov", "alembic", "migrations"}
TTL_S = 7 * 86400  # default / passes-before TTL: a gap that already passes its VERIFY is not re-checked for this long
TTL_BY_VERDICT = {"passes-before": 7 * 86400, "red": 36 * 3600, "supplied": 36 * 3600}
# verdicts that say nothing about the SPEC (no-verdict / no-verify / bad-spec: the checker itself failed; unchecked: --no-spec-check) are never remembered and the spec
# is retried next pass; after INFRA_ALERT_AFTER consecutive passes with such a verdict one alerts.log warn names the problem
INFRA_ALERT_AFTER = 3


def walk(root, exts):
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in sorted(fns):
            if fn.endswith(exts):
                yield os.path.join(dp, fn)


def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def rel(root, p):
    return os.path.relpath(p, root)


def is_test_path(r):
    return bool(re.search(r"(^|/)(tests?|__tests__|spec)(/|$)|(^|/)test_[^/]+$|\.(test|spec)\.", r))


def _unparse(n):
    try:
        return ast.unparse(n)
    except Exception:
        return ""


def _funcs(tree):
    return [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]


def _returns_value(fn):
    """True if the function body (not nested defs) has `return <expr>` (or yields - then the annotation is a generator type, not None)."""
    stack = list(fn.body)
    while stack:
        n = stack.pop()
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)):
            continue
        if isinstance(n, ast.Return) and n.value is not None and not (isinstance(n.value, ast.Constant) and n.value.value is None):
            return True
        if isinstance(n, (ast.Yield, ast.YieldFrom)):
            return True
        stack.extend(ast.iter_child_nodes(n))
    return False


# ---------------------------------------------------------------- the VERIFY templates (also used by tests)
def verify_swallowed(path):
    return ("python3 -c \"import ast,sys;t=ast.parse(open('%s').read());"
            "n=[h for h in ast.walk(t) if isinstance(h,ast.ExceptHandler) and len(h.body)==1 and isinstance(h.body[0],ast.Pass)];"
            "sys.exit(1 if n else 0)\"" % path)


def verify_rate_limit(path):
    # every route needs: the limiter decorator BELOW the route decorator (above it the limit is inert), and a real starlette `request: Request` param
    # (slowapi cannot find the request when `request` is a body model).
    return ("python3 -c \"import ast,sys;t=ast.parse(open('%s').read());"
            "ok=lambda n:(lambda ds:[i for i,d in enumerate(ds) if d.startswith('router.')] and [i for i,d in enumerate(ds) if 'limiter.limit' in d] "
            "and max(i for i,d in enumerate(ds) if d.startswith('router.'))<min(i for i,d in enumerate(ds) if 'limiter.limit' in d) "
            "and any(a.arg=='request' and a.annotation is not None and ast.unparse(a.annotation).split('.')[-1]=='Request' for a in n.args.args))"
            "([ast.unparse(d) for d in n.decorator_list]);"
            "bad=[n.name for n in ast.walk(t) if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef)) "
            "and any(ast.unparse(d).startswith('router.') for d in n.decorator_list) and not ok(n)];"
            "sys.exit(1 if bad else 0)\"" % path)


def verify_returns_none(path, names):
    return ("python3 -c \"import ast,sys;t=ast.parse(open('%s').read());names=%r;"
            "bad=[n.name for n in ast.walk(t) if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef)) and n.name in names and n.returns is None];"
            "sys.exit(1 if bad else 0)\"" % (path, list(names)))


def verify_return_types(path, names):
    """Like verify_returns_none, but the annotation must say something: a bare `Any` / `Optional[Any]` / `Any | None` return type (ast Name/Attribute
    `Any`) satisfied the old 'accurate return type' check while carrying no information. `dict[str, Any]` / `list[Any]` stay fine (the Any is an argument)."""
    return ("python3 -c \"import ast,sys;t=ast.parse(open('%s').read());names=%r;"
            "an=lambda x:(isinstance(x,ast.Name) and x.id=='Any') or (isinstance(x,ast.Attribute) and x.attr=='Any');"
            "nn=lambda x:isinstance(x,ast.Constant) and x.value is None;"
            "bad_r=lambda r:an(r) or (isinstance(r,ast.Subscript) and ast.unparse(r.value).split('.')[-1]=='Optional' and an(r.slice)) "
            "or (isinstance(r,ast.BinOp) and isinstance(r.op,ast.BitOr) and ((an(r.left) and nn(r.right)) or (nn(r.left) and an(r.right))));"
            "bad=[n.name for n in ast.walk(t) if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef)) and n.name in names and (n.returns is None or bad_r(n.returns))];"
            "sys.exit(1 if bad else 0)\"" % (path, list(names)))


def verify_ruff_rule(path, rule):
    # python3 here is the repo venv's python (the VERIFY runner substitutes it), which ships ruff; --isolated so a repo ruff config cannot hide the rule
    return "python3 -m ruff check --select %s --isolated --no-cache %s" % (rule, path)


_MISSION_CELL = r"Vector2i[(] *(-?[0-9]+) *, *(-?[0-9]+) *[)]"


def _mission_line(text, key):
    m = re.findall(r"(?m)^" + key + r" *= *(.*)", text)
    return m[0] if m else ""


def mission_keep(text):
    """What a spawn fix must leave alone, read from the mission text with the SAME regexes the inline VERIFY uses: (player spawn count, enemy spawn count, enemy_types length,
    12-hex signature of the obstacle cells + obstacle types). None for a text without any of it."""
    def cells(k):
        return [(int(a), int(b)) for a, b in re.findall(_MISSION_CELL, _mission_line(text, k))]

    def ints(k):
        return [int(x) for x in re.findall(r"-?[0-9]+", _mission_line(text, k))]
    sig = hashlib.sha1(repr((cells("obstacles"), ints("obstacle_types"))).encode()).hexdigest()[:12]
    return (len(cells("player_spawns")), len(cells("enemy_spawns")), len(ints("enemy_types")), sig)


def verify_mission_spawns(path, keep=None):
    """Self-contained (the xlite repo has no copy of scripts/ovn_mission_lint.py): exit 1 when a player/enemy spawn sits on a blocking obstacle (obstacle
    type 0 CRATE / 1 WALL / missing / unknown; 2 RUBBLE and 3 HAZARD are walkable) or outside grid_size. Same rule as ovn_mission_lint.violations(spawn_only=True).
    keep = mission_keep(<the mission text the item was written from>): when given, the VERIFY is ALSO red unless the number of player spawns, enemy spawns and enemy_types
    entries and the obstacle cells + obstacle_types are exactly what they were (the item text forbids changing them: deleting a spawn or moving the wall away would otherwise go green).
    No `$`, no backtick, no `>`: the runner executes it with bash -c and refuses redirect-looking characters."""
    keep_part = ""
    if keep is not None:
        keep_part = ("ii=lambda k:[int(x) for x in re.findall(r'-?[0-9]+',(re.findall(r'(?m)^'+k+r' *= *(.*)',s) or [''])[0])];"
                     "kp=[len(g('player_spawns')),len(g('enemy_spawns')),len(ii('enemy_types')),hashlib.sha1(repr((g('obstacles'),ii('obstacle_types'))).encode()).hexdigest()[:12]]==%r;" % (list(keep),))
    return ("python3 -c \"import re,sys,hashlib;s=open('%s').read();"
            "g=lambda k:[(int(a),int(b)) for a,b in re.findall(r'Vector2i[(] *(-?[0-9]+) *, *(-?[0-9]+) *[)]',(re.findall(r'(?m)^'+k+r' *= *(.*)',s) or [''])[0])];"
            "ty=[int(x) for x in re.findall(r'-?[0-9]+',(re.findall(r'(?m)^obstacle_types *= *(.*)',s) or [''])[0])];"
            "m=re.search(r'grid_size *= *Vector2i[(] *([0-9]+) *, *([0-9]+)',s);w,h=int(m.group(1)),int(m.group(2));"
            "bl={c for i,c in enumerate(g('obstacles')) if (ty[i] if i<len(ty) else 0) not in (2,3)};"
            "bad=[c for k in ('player_spawns','enemy_spawns') for c in g(k) if c in bl or not (0<=c[0]<w and 0<=c[1]<h)];"
            "%ssys.exit(1 if bad%s else 0)\"" % (path, keep_part, " or not kp" if keep is not None else ""))


def verify_ruff_f401(path):
    # python3 here is the repo venv's python (the VERIFY runner substitutes it), which ships ruff
    return "python3 -m ruff check --select F401 --no-cache %s" % path


def verify_pure_tests(test_path, names, pytest_cwd):
    """Red-before (the test file does not exist) / green-after: the file exists, parses, and for EVERY named function some `test_*` calls it and compares
    the result in an assert that is not a tautology; then the file's own tests pass. The existence guard exits 1 explicitly (not a crash) so the red-before check reads it as a real failure."""
    # ONE physical line (a newline would split the backlog line; the spec check rejected the first version as no-verify, which is how it was caught)
    ast_part = ("python3 -c \"import ast,os,sys;p='%s';(not os.path.exists(p)) and sys.exit(1);t=ast.parse(open(p).read());names=%r;"
                "ok=lambda n:any(isinstance(f,ast.FunctionDef) and f.name.startswith('test') and any(isinstance(c,ast.Call) and ast.unparse(c.func).split('.')[-1]==n for c in ast.walk(f)) "
                "and any(isinstance(a,ast.Assert) and isinstance(a.test,ast.Compare) for a in ast.walk(f)) for f in ast.walk(t));"
                "sys.exit(0 if all(ok(n) for n in names) else 1)\"" % (test_path, list(names)))
    return ast_part


def verify_docstrings(path, names):
    return ("python3 -c \"import ast,sys;t=ast.parse(open('%s').read());names=%r;"
            "bad=[n.name for n in ast.walk(t) if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef,ast.ClassDef)) and n.name in names and not (ast.get_docstring(n) or '').strip()];"
            "sys.exit(1 if bad else 0)\"" % (path, list(names)))


# a `##` doc-comment above a func may sit above its own-line @annotations (Godot attaches the doc comment there, the GDScript style guide puts it there):
# 2026-10-09 the VERIFY and the collector walk back over annotation-only lines (a trailing `# comment` is allowed) before looking for the `##`.
# ovn_doc_executor.py keys its default placement off the `docabove=lambda` marker below: keep that token in sync when this string changes.
_GD_ANNOT = re.compile(r"^[ \t]*@\w+[ \t]*(?:\(.*\))?[ \t]*(?:#.*)?$")


def _gd_has_doc(L, i):
    """True when a `##` line sits directly above the func at L[i], ignoring own-line @annotations between them."""
    a = i
    while a > 0 and _GD_ANNOT.match(L[a - 1]):
        a -= 1
    return a > 0 and L[a - 1].lstrip().startswith("##")


def verify_gd_docs(path, names):
    # a `##` doc-comment line directly above each named function, or directly above its own-line @annotations (Godot's doc-comment syntax); no literal '>'
    # (the runner refuses redirect-looking characters); one regex over the whole text, no backslash that bash would eat inside the double quotes
    return ("python3 -c \"import re,sys;s=open('%s').read();names=%r;"
            "docabove=lambda n:re.search(r'^[ \\t]*##[^\\n]*\\n(?:[ \\t]*@\\w+[ \\t]*(?:[(].*[)])?[ \\t]*(?:#.*)?\\n)*(?:static )?func '+n+r'[(]',s,re.M);"
            "sys.exit(1 if [n for n in names if not docabove(n)] else 0)\"" % (path, list(names)))


def verify_gd_void(path, names):
    # no literal '>' anywhere: the VERIFY runner refuses any redirect-looking character, so the arrow is matched as \\x3e
    return ("python3 -c \"import re,sys;s=open('%s').read();names=%r;"
            "bad=[n for n in names if not re.search(r'func '+n+r'\\([^)]*\\)\\s*-\\x3e',s)];"
            "sys.exit(1 if bad else 0)\"" % (path, list(names)))


# ---------------------------------------------------------------- collectors: each yields spec dicts
def c_swallowed(root):
    for p in walk(root, (".py",)):
        r = rel(root, p)
        if is_test_path(r):
            continue
        try:
            tree = ast.parse(read(p))
        except SyntaxError:
            continue
        hs = [h for h in ast.walk(tree) if isinstance(h, ast.ExceptHandler) and len(h.body) == 1 and isinstance(h.body[0], ast.Pass)]
        if not hs or len(hs) > 4:
            continue
        lines = ", ".join(str(h.lineno) for h in sorted(hs, key=lambda h: h.lineno))
        # symbols identify the gap for the seen key: handler type + the first statement of its try body (stable when unrelated edits shift the line numbers)
        sym = []
        for t in ast.walk(tree):
            if isinstance(t, ast.Try):
                sym += ["%s:%s" % (_unparse(h.type) if h.type is not None else "bare", _unparse(t.body[0])[:60]) for h in t.handlers if h in hs]
        yield {"kind": "swallowed-exception", "file": r, "tier": "T2", "cat": "python",
               "text": "Replace the bare `pass` in the %d `except` handler(s) at line(s) %s with real handling: `logger.exception(...)` for unexpected errors, "
                       "`logger.debug(...)` for expected ones (ImportError/CancelledError/KeyError lookups). Define `logger = logging.getLogger(__name__)` at module top if the file "
                       "has none. Change nothing else in the file." % (len(hs), lines),
               "verify": verify_swallowed(r), "symbols": sym or ["L%d" % h.lineno for h in hs]}


def c_rate_limit(root):
    files = [p for p in walk(root, (".py",)) if "/routers/" in p and not is_test_path(rel(root, p))]
    if not any("limiter.limit" in read(p) for p in files):
        return
    for p in files:
        r = rel(root, p)
        t = read(p)
        try:
            tree = ast.parse(t)
        except SyntaxError:
            continue
        routes = [n for n in _funcs(tree) if any(_unparse(d).startswith("router.") for d in n.decorator_list)]
        if not routes or len(routes) > 4 or "limiter.limit" in t:
            continue
        names = ", ".join("`%s`" % n.name for n in routes)
        yield {"kind": "no-rate-limit", "file": r, "tier": "T2", "cat": "python",
               "text": "Rate-limit every route in this router (%s). For each: the limiter decorator goes DIRECTLY BELOW the `@router.<method>(...)` line (above it the limit is "
                       "silently inert); the function needs a starlette `request: Request` parameter (import `Request` from fastapi) - if a body model is already named "
                       "`request`, rename the body to `payload` first. Limits: `@limiter.limit(\"120/minute\")` on GET routes, `@limiter.limit(\"30/minute\")` on POST/PUT/PATCH/DELETE "
                       "(`from app.core.limiter import limiter`; see `app/routers/auth.py`). Do not change behaviour, response models or dependencies." % names,
               "verify": verify_rate_limit(r), "symbols": [n.name for n in routes]}


_RET_DIRS = ("/services/", "/core/", "/jobs/")


def c_returns_none(root):
    for p in walk(root, (".py",)):
        r = rel(root, p)
        if is_test_path(r) or not any(d in "/" + r for d in _RET_DIRS) or r.endswith("__init__.py") or "/app/" not in "/" + r:
            continue
        try:
            tree = ast.parse(read(p))
        except SyntaxError:
            continue
        top = set()
        for node in tree.body:
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                top.add(id(node))
            elif isinstance(node, ast.ClassDef):
                top.update(id(b) for b in node.body if isinstance(b, (ast.FunctionDef, ast.AsyncFunctionDef)))
        cand = [n for n in _funcs(tree) if id(n) in top and n.returns is None and not _returns_value(n) and not n.name.startswith("__")]
        names = []
        for n in cand:
            if n.name not in names:
                names.append(n.name)
        names = names[:MAX_SYMBOLS]
        if not names:
            continue
        yield {"kind": "missing-return-none", "file": r, "tier": "T2", "cat": "python",
               "text": "Add the return annotation `-> None` to these functions (none of them returns a value): %s. Annotations only - change no logic." %
                       ", ".join("`%s`" % n for n in names),
               "verify": verify_returns_none(r, names), "symbols": names}


def c_gd_void(root):
    for p in walk(root, (".gd",)):
        r = rel(root, p)
        if is_test_path(r) or r.startswith("addons/"):
            continue
        lines = read(p).split("\n")
        names = []
        i = 0
        while i < len(lines):
            m = re.match(r"^(?:static )?func (\w+)\(([^)]*)\)\s*:\s*(?:#.*)?$", lines[i])
            if m and not m.group(1).startswith("_"):
                j, has_ret = i + 1, False
                while j < len(lines) and (not lines[j].strip() or lines[j].startswith(("\t", " "))):
                    if re.match(r"\s*return\s+\S", lines[j]) and not re.match(r"\s*return\s*(#.*)?$", lines[j]):
                        has_ret = True
                        break
                    j += 1
                if not has_ret and m.group(1) not in names:
                    names.append(m.group(1))
                i = j
            else:
                i += 1
        names = names[:MAX_SYMBOLS]
        if names:
            yield {"kind": "gd-missing-void", "file": r, "tier": "T2", "cat": "godot",
                   "text": "Add the return type `-> void` to these GDScript functions (none of them returns a value): %s. Type annotations only - change no logic." %
                           ", ".join("`%s`" % n for n in names),
                   "verify": verify_gd_void(r, names), "symbols": names}


_POLISH_DIRS = ("/services/", "/core/", "/jobs/", "/routers/")


def _top_defs(tree, with_classes=False):
    out = []
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            out.append(node)
        elif isinstance(node, ast.ClassDef):
            if with_classes:
                out.append(node)
            out.extend(b for b in node.body if isinstance(b, (ast.FunctionDef, ast.AsyncFunctionDef)))
    return out


def c_return_types(root):
    """Functions that DO return a value but have no return annotation (the model reads the body and picks the type); typing items land ~92%."""
    for p in walk(root, (".py",)):
        r = rel(root, p)
        if is_test_path(r) or "/app/" not in "/" + r or not any(d in "/" + r for d in _POLISH_DIRS) or r.endswith("__init__.py"):
            continue
        try:
            tree = ast.parse(read(p))
        except SyntaxError:
            continue
        names = []
        for n in _top_defs(tree):
            # public only; never route handlers (FastAPI treats a return annotation as the response model - not a mechanical change)
            if n.returns is None and _returns_value(n) and not n.name.startswith("_") and n.name not in names \
                    and not any(re.match(r"router\.", _unparse(d)) for d in n.decorator_list):
                names.append(n.name)
        names = names[:MAX_SYMBOLS]
        if names:
            yield {"kind": "missing-return-type", "file": r, "tier": "T2", "cat": "python",
                   "text": "Add accurate return type annotations to these functions: %s. Read each body to decide the type (use `typing` / builtin generics, `Optional[...]` when it can return None). "
                           "Annotations only - change no logic, add no imports other than `typing`. A bare `Any` / `Optional[Any]` return type is rejected: say what the function really returns." %
                           ", ".join("`%s`" % n for n in names),
                   "verify": verify_return_types(r, names), "symbols": names}


def c_docstrings(root):
    """Public functions/classes (>= 5 body lines) with no docstring."""
    for p in walk(root, (".py",)):
        r = rel(root, p)
        if is_test_path(r) or "/app/" not in "/" + r or r.endswith("__init__.py"):
            continue
        try:
            tree = ast.parse(read(p))
        except SyntaxError:
            continue
        names = []
        for n in _top_defs(tree, with_classes=True):
            if n.name.startswith("_") or ast.get_docstring(n) or (n.end_lineno - n.lineno) < 5 or n.name in names:
                continue
            if any(re.match(r"router\.", _unparse(d)) for d in getattr(n, "decorator_list", [])):
                continue  # route handlers: FastAPI turns the docstring into public OpenAPI text - not a mechanical call
            names.append(n.name)
        names = names[:MAX_SYMBOLS]
        if names:
            yield {"kind": "missing-docstring", "file": r, "tier": "T2", "cat": "python",
                   "text": "Add a one-to-three line docstring to each of these public functions/classes: %s. Describe what it does, its key arguments and return value, based on reading its body. "
                           "Docstrings only - change no code." % ", ".join("`%s`" % n for n in names),
                   "verify": verify_docstrings(r, names), "symbols": names}


def c_gd_docs(root):
    """Public GDScript functions with no `##` doc comment directly above. DEFAULT OFF (OVN_SUPPLY_GD_DOCS=on enables it): model-written doc items took 59 cycles /
    2.6M tokens for 17 items; they come back when the deterministic doc executor (package xlite-godot-lane, OVN_DOC_EXECUTOR=on) is live."""
    if os.environ.get("OVN_SUPPLY_GD_DOCS", "off").lower() not in ("on", "1", "true", "yes"):
        return
    for p in walk(root, (".gd",)):
        r = rel(root, p)
        if is_test_path(r) or r.startswith("addons/"):
            continue
        L = read(p).split("\n")
        names = []
        for i, l in enumerate(L):
            m = re.match(r"^(?:static )?func (\w+)\(", l)
            if m and not m.group(1).startswith("_") and i and not _gd_has_doc(L, i) and m.group(1) not in names:
                body = 0
                for l2 in L[i + 1:i + 40]:
                    if l2.startswith(("\t", " ")) or not l2.strip():
                        body += 1
                    else:
                        break
                if body >= 5:
                    names.append(m.group(1))
        names = names[:MAX_SYMBOLS]
        if names:
            yield {"kind": "gd-missing-doc", "file": r, "tier": "T2", "cat": "godot",
                   "text": "Add a `##` doc-comment (one to three lines: what it does, key arguments, return value) on the line directly above each of these GDScript functions: %s. "
                           "Comments only - change no code, no signatures." % ", ".join("`%s`" % n for n in names),
                   "verify": verify_gd_docs(r, names), "symbols": names}


_IMPURE_CALLS = {"open", "input", "exec", "eval", "compile", "__import__"}
_IMPURE_ATTR_ROOTS = {"os", "sys", "subprocess", "requests", "httpx", "random", "time", "socket", "shutil", "pathlib", "asyncio", "threading", "db", "session", "logging", "logger"}
_PURE_DIRS = ("/services/", "/core/", "/utils/")


def _is_pure_function(n, tree_names):
    """Heuristic 'pure enough to unit-test without mocks': sync, public, undecorated, returns a value, short, no self/db/request args, no I/O, clock, randomness,
    global state or logging. When in doubt it says no - a wrong 'yes' produces a mock-heavy test the antigaming gate flags."""
    if not isinstance(n, ast.FunctionDef) or n.name.startswith("_") or n.decorator_list or not _returns_value(n):
        return False
    args = [a.arg for a in n.args.args + n.args.kwonlyargs]
    if not args or any(a in ("self", "cls", "db", "session", "request", "response", "app", "client") for a in args) or n.args.vararg or n.args.kwarg:
        return False
    length = (n.end_lineno or n.lineno) - n.lineno
    if length < 3 or length > 40:
        return False
    for node in ast.walk(n):
        if isinstance(node, (ast.Await, ast.AsyncFor, ast.AsyncWith, ast.Global, ast.Nonlocal, ast.Yield, ast.YieldFrom, ast.Try)):
            return False
        if isinstance(node, ast.Call):
            f = node.func
            if isinstance(f, ast.Name) and f.id in _IMPURE_CALLS:
                return False
            root = f
            while isinstance(root, ast.Attribute):
                root = root.value
            if isinstance(root, ast.Name) and root.id in _IMPURE_ATTR_ROOTS:
                return False
            if isinstance(f, ast.Attribute) and f.attr in ("now", "utcnow", "today", "random", "uuid4", "commit", "query", "execute", "add"):
                return False
        if isinstance(node, ast.Name) and node.id in _IMPURE_ATTR_ROOTS and isinstance(node.ctx, ast.Load) and node.id not in args:
            return False
    return True


def c_pure_tests(root):
    """Public pure functions in app/{services,core,utils} that no test mentions: ask for a real test file (>= 1 concrete-output assert per function, no mocks)."""
    tests_dir = "iptv-backend/tests" if os.path.isdir(os.path.join(root, "iptv-backend", "tests")) else None
    if not tests_dir:
        return
    blob = "\n".join(read(p) for p in walk(os.path.join(root, tests_dir), (".py",)))
    for p in walk(root, (".py",)):
        r = rel(root, p)
        if is_test_path(r) or "/app/" not in "/" + r or not any(d in "/" + r for d in _PURE_DIRS) or r.endswith("__init__.py"):
            continue
        try:
            tree = ast.parse(read(p))
        except SyntaxError:
            continue
        names = []
        for n in tree.body:
            if _is_pure_function(n, None) and n.name not in names and not re.search(r"\b%s\b" % re.escape(n.name), blob):
                names.append(n.name)
        names = names[:4]
        if not names:
            continue
        mod = os.path.splitext(os.path.basename(r))[0]
        test_rel = "%s/test_%s_pure.py" % (tests_dir, mod)
        if os.path.exists(os.path.join(root, test_rel)):
            continue
        modpath = os.path.splitext(r.split("iptv-backend/", 1)[-1])[0].replace("/", ".")
        yield {"kind": "pure-function-tests", "file": test_rel, "tier": "T2", "cat": "test",
               "text": "NEW test file for `%s` (public, side-effect-free functions that no test mentions: %s). Read each function body first, then write at least 2 tests per function with CONCRETE expected outputs "
                       "for representative and edge inputs (empty, zero, boundary, invalid) using plain `assert result == expected`; no mocks, no fixtures, import with `from %s import %s`. "
                       "If a function turns out to need I/O to test, skip it and say why in a comment. Test code only - do not change `%s`." % (r, ", ".join("`%s`" % n for n in names), modpath, ", ".join(names), r),
               "verify": verify_pure_tests(test_rel, names, "iptv-backend") + " && cd iptv-backend && python3 -m pytest %s -q" % test_rel.split("iptv-backend/", 1)[-1],
               "symbols": names}


def _venv_python(root):
    for cand in ("iptv-backend/.venv/bin/python", ".venv/bin/python", "backend/.venv/bin/python"):
        p = os.path.join(root, cand)
        if os.path.exists(p):
            return p
    return None


def _relpath(root, filename):
    """Repo-relative path of a ruff-reported filename (absolute, or relative to the repo root); realpath on both sides so macOS /var vs /private/var cannot skew it."""
    return os.path.relpath(os.path.realpath(os.path.join(root, filename)), os.path.realpath(root))


def _ruff_json(py, root, args):
    """ruff findings as a list of dicts; [] when ruff is missing or its output is not JSON (a collector then simply yields nothing - no noise)."""
    try:
        r = subprocess.run([py, "-m", "ruff", "check", "--output-format", "json", "--no-cache"] + args, cwd=root, capture_output=True, text=True, timeout=120)
        out = json.loads(r.stdout or "[]")
    except Exception:
        return []
    return out if isinstance(out, list) else []


# the delete-the-file pattern from the v2 spec (the old 'Remove the unused import(s) in this file' wording tripped the harness' delete-file path): no item text may match it
DELETE_FILE_RE = re.compile(r"\b(remove|delete)\b.{0,60}\bfiles?\b", re.I | re.S)


def _skip_py_path(path):
    parts = path.split("/")
    return is_test_path(path) or "alembic" in parts or "migrations" in parts


def c_unused_imports(root):
    """F401 unused imports (ruff, JSON output), per file, <= 6 per item. __init__.py (re-exports) and `# noqa` lines are never touched (ruff already honours noqa).
    Wording (2026-10-09): 'Delete the unused import(s) from the import statement(s) in <path>' - the old 'Remove the unused import(s) in this file' put 'remove ... file'
    into the item and the harness read it as a delete-the-file request (5 wasted NEEDS-DECISION scout cycles)."""
    py = _venv_python(root)
    if not py:
        return
    by_file = {}
    for f in _ruff_json(py, root, ["--select", "F401", "--exclude", "tests,alembic,migrations", "."]):
        path = _relpath(root, f.get("filename", ""))
        if path.endswith("__init__.py") or is_test_path(path):
            continue
        by_file.setdefault(path, []).append(f)
    for path, fs in sorted(by_file.items()):
        names = []
        for f in fs:
            m = re.search(r"`([^`]+)`", f.get("message", ""))
            if m and m.group(1) not in names:
                names.append(m.group(1))
        if not names or len(fs) > 6:
            continue
        nm = ", ".join("`%s`" % n for n in names)
        text = ("Delete the unused import(s) from the import statement(s) in %s (ruff F401): %s. Delete only these names from their import lines "
                "(drop a whole import statement when nothing is left in it); change nothing else." % (path, nm))
        if DELETE_FILE_RE.search(text):
            # a path with a `file`/`files` segment right after 'Delete': leave the path out (the item line already starts with it), never let it read as delete-the-file
            text = ("Delete the unused import(s) from the import statements at the top of this module (ruff F401): %s. Only the names listed are removed from their import lines "
                    "(drop a whole import statement when nothing is left in it); change nothing else." % nm)
        yield {"kind": "unused-import", "file": path, "tier": "T1", "cat": "python", "text": text,
               "verify": verify_ruff_f401(path), "symbols": names}


# ruff bug-class families. B008 (FastAPI Depends defaults) and E712 (SQLAlchemy `== True`) are idiomatic here and never become items; S314/S104/S105 are advisories.
_RUFF_KINDS = ("F601", "F811", "F841", "B904", "RUF013")
_RUFF_NEVER = ("B008", "E712", "S314", "S104", "S105")
_APP_DIRS = ("iptv-backend/app", "backend/app", "app")
_RUFF_MAX_FINDINGS = 4
_RUFF_TEXT = {
    "F601": "Fix the duplicate dictionary key(s) %(names)sat line(s) %(rows)s (ruff F601: a repeated key silently discards the earlier value). Read the neighbouring entries and keep the "
            "value that is correct, deleting the other entry; if both entries are meant to exist, one of the keys is a typo - rename it. Change nothing else.",
    "F811": "Resolve the redefinition(s) of an unused name %(names)sat line(s) %(rows)s (ruff F811: the later definition or import shadows the earlier one). Delete the dead earlier "
            "definition; if both are needed, rename one and update its callers. Change nothing else.",
    "F841": "Fix the unused local variable(s) %(names)sat line(s) %(rows)s (ruff F841): delete the assignment, or keep the right-hand side as a bare statement when the call has side "
            "effects; if the value was meant to be used, use it. Change nothing else.",
    "B904": "In the `except` block(s) at line(s) %(rows)s chain the exception that is raised (ruff B904): bind the handler (`except X as err`) and write `raise NewError(...) from err`, "
            "or `from None` when hiding the cause is intended. Change nothing else.",
    "RUF013": "Make the implicit Optional parameter annotation(s) %(names)sat line(s) %(rows)s explicit (ruff RUF013): `Optional[T]` (or `T | None`) for every parameter whose default is None. "
              "Annotations only - change no logic.",
}


_ROUTE_ROOTS = ("router", "app", "api", "bp", "blueprint")
_ROUTE_ATTRS = frozenset(("get", "post", "put", "delete", "patch", "head", "options", "trace", "api_route", "route", "websocket", "on_event", "middleware",
                          "exception_handler", "task", "command", "callback", "listens_for"))


def _is_route_decorator(d):
    """`@router.get(...)`, `@app.post(...)`, `@bp.route(...)`, `@celery.task` ...: a decorator that REGISTERS the function somewhere, so a second function of the same name is not
    automatically dead code (two handlers with different paths are both live; with the same path only the FIRST registered route is live)."""
    node = d.func if isinstance(d, ast.Call) else d
    if not isinstance(node, ast.Attribute):
        return False
    root = node
    while isinstance(root, ast.Attribute):
        root = root.value
    rid = root.id if isinstance(root, ast.Name) else ""
    return rid in _ROUTE_ROOTS or rid.endswith("router") or node.attr in _ROUTE_ATTRS


def _finding_name(f):
    m = re.search(r"`([^`]+)`", f.get("message", ""))
    return m.group(1) if m else ""


def _registered_names(root, path):
    """Names of the functions in <path> that carry a route/registration decorator; None when the file cannot be read or parsed (the caller then skips conservatively)."""
    try:
        tree = ast.parse(read(os.path.join(root, path)))
    except (SyntaxError, ValueError, OSError):
        return None
    return {n.name for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and any(_is_route_decorator(d) for d in n.decorator_list)}


def _ruff_rules():
    out = []
    for r in os.environ.get("OVN_SUPPLY_RUFF_RULES", "F601,F811").split(","):
        r = r.strip().upper()
        if r in _RUFF_KINDS and r not in _RUFF_NEVER and r not in out:
            out.append(r)
    return out


def c_ruff_bugclass(root):
    """ruff findings that are real bugs (silent data loss, shadowed definitions, lost tracebacks): one item per (file, rule) with <= 4 findings; the rule allowlist is
    OVN_SUPPLY_RUFF_RULES (default F601,F811 - widened by the lead after a clean week). The VERIFY is the same ruff rule run on that file alone (rc 0)."""
    py = _venv_python(root)
    rules = _ruff_rules()
    dirs = [d for d in _APP_DIRS if os.path.isdir(os.path.join(root, d))]
    if not py or not rules or not dirs:
        return
    by_file = {}
    for f in _ruff_json(py, root, ["--isolated", "--select", ",".join(rules)] + dirs):
        path = _relpath(root, f.get("filename", ""))
        if _skip_py_path(path) or f.get("code") not in rules:
            continue
        by_file.setdefault(path, {}).setdefault(f["code"], []).append(f)
    for path, codes in sorted(by_file.items()):
        for rule in rules:
            fs = codes.get(rule)
            if fs and rule == "F811":
                # F811 on route handlers is NOT a dead-code finding: `@router.get("/a") def h` + `@router.get("/b") def h` are both live, and deleting "the earlier one" removes an
                # endpoint while the ruff VERIFY goes green. Findings about a registered (decorated) name, or about a file we cannot parse, never become items.
                reg = _registered_names(root, path)
                fs = [] if reg is None else [f for f in fs if _finding_name(f) and _finding_name(f) not in reg]
            if not fs or len(fs) > _RUFF_MAX_FINDINGS:
                continue
            names, rows = [], []
            for f in fs:
                row = int((f.get("location") or {}).get("row") or 0)
                rows.append(row)
                m = re.search(r"`([^`]+)`", f.get("message", ""))
                nm = re.sub(r"[^\w.'\" -]", "", m.group(1)) if m else ""
                if nm and nm not in names:
                    names.append(nm)
            fmt = {"names": ("%s " % ", ".join("`%s`" % n for n in names)) if names else "",
                   "rows": ", ".join(str(x) for x in sorted(set(rows)))}
            yield {"kind": "ruff-%s" % rule, "file": path, "tier": "T2", "cat": "python", "text": _RUFF_TEXT[rule] % fmt,
                   "verify": verify_ruff_rule(path, rule), "symbols": names or ["L%d" % x for x in rows]}


_MISSION_LINT = None


def _mission_lint():
    """scripts/ovn_mission_lint.py loaded from next to this file (stdlib only); None when it is not deployed."""
    global _MISSION_LINT
    if _MISSION_LINT is None:
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ovn_mission_lint.py")
        if not os.path.exists(p):
            return None
        spec = importlib.util.spec_from_file_location("ovn_mission_lint", p)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        _MISSION_LINT = mod
    return _MISSION_LINT


def c_mission_spawns(root):
    """xlite missions/*.tres whose player/enemy spawn lies on a blocking obstacle (crate/wall) or outside the grid: 11 spawns in 5 shipped missions on 2026-10-09."""
    files = [p for p in walk(root, (".tres",)) if "/missions/" in "/" + rel(root, p)]
    if not files:
        return
    lint = _mission_lint()
    if lint is None:
        sys.stderr.write("collector c_mission_spawns: ovn_mission_lint.py not found next to ovn_work_supply.py - skipped\n")
        return
    for p in sorted(files):
        r = rel(root, p)
        fields = lint.parse(read(p))
        v = lint.violations(fields, spawn_only=True)
        if not v or len(v) > _RUFF_MAX_FINDINGS:
            continue
        gs = lint.grid_size(fields)
        where = ", ".join("%s (%d,%d) %s" % (f, c[0], c[1], why) for f, c, why in v)
        yield {"kind": "mission-spawn-on-obstacle", "file": r, "tier": "T2", "cat": "godot",
               "text": "Fix the spawn position(s) in this mission: %s. Each one lies on a blocking obstacle cell (crate or wall) or outside the grid (grid_size %dx%d), so the unit starts "
                       "stuck inside cover or off the map. Move the spawn to the nearest free in-grid cell: a cell inside grid_size that is not in `obstacles` (treat rubble and hazard cells "
                       "as occupied too) and not used by another spawn. Edit only the `player_spawns` / `enemy_spawns` entries named here: do not move obstacles and do not change array "
                       "lengths or any other field." % (where, gs[0], gs[1]),
               "verify": verify_mission_spawns(r, mission_keep(read(p))), "symbols": ["%s@%d,%d" % (f, c[0], c[1]) for f, c, _ in v]}


COLLECTORS = [c_swallowed, c_rate_limit, c_returns_none, c_gd_void, c_return_types, c_docstrings, c_gd_docs, c_pure_tests, c_unused_imports, c_ruff_bugclass, c_mission_spawns]


def _load_external_collectors():
    """OVN_SUPPLY_MUTATION=1: append `collect(root)` of the module ovn_mutation_supply (built by package xlite-godot-lane; it yields the same spec dicts).
    A missing module or any error while importing it is a stderr line, never a failed pass."""
    if os.environ.get("OVN_SUPPLY_MUTATION") != "1":
        return []
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.append(here)
    try:
        import ovn_mutation_supply  # noqa: PLC0415
        fn = ovn_mutation_supply.collect
        if not callable(fn):
            raise TypeError("collect is not callable")
        return [fn]
    except Exception as e:
        sys.stderr.write("external collector ovn_mutation_supply skipped: %s: %s\n" % (type(e).__name__, e))
        return []


def collect_all(root):
    """Round-robin the collectors so one kind cannot crowd out the rest."""
    per = []
    for fn in COLLECTORS + _load_external_collectors():
        try:
            per.append(list(fn(root)))
        except Exception as e:  # a broken collector must not kill the pass
            sys.stderr.write("collector %s failed: %s\n" % (getattr(fn, "__name__", fn), e))
            per.append([])
    out = []
    while any(per):
        for lst in per:
            if lst:
                out.append(lst.pop(0))
    return out


def spec_key(s):
    """kind|file|sha1(sorted gap symbols)[:10]: a gap whose symbol set changed (some names fixed, new ones found) is a NEW gap and re-qualifies; the old
    two-part keys of v1 never match, so the poisoned ones simply expire."""
    syms = sorted({str(x) for x in (s.get("symbols") or [])}) or [s.get("text", "")]
    return "%s|%s|%s" % (s["kind"], s["file"], hashlib.sha1("\n".join(syms).encode("utf-8", "replace")).hexdigest()[:10])


def render(s, repo):
    slug = re.sub(r"[^a-z0-9]+", "-", ("%s-%s" % (s["kind"], s["file"])).lower()).strip("-")[:48]
    return "- [ ] [%s] %s — %s VERIFY: `%s`. (cat:%s; multifile:no; supply:%s) [feat:%s-%s-supply-%s]" % (
        s["tier"], s["file"], s["text"], s["verify"], s["cat"], s["kind"], repo, datetime.date.today().strftime("%Y%m%d"), slug)


_HELD = re.compile(r"HUMAN-ONLY|AUTO-SKIP|BLOCKED|\(retired-|\[CLAUDE\]")  # BLOCKED is case-sensitive on purpose (an item's prose may say 'blocked')


def open_count(text):
    """Open items the fleet can actually take (same exclusions as the queue's doable count): held/escalated/retired lines do not count."""
    return sum(1 for l in text.split("\n") if re.match(r"^- \[ \] \[T[1-5]\]", l) and not _HELD.search(l))


def _norm_line(l):
    """Same identity idea as queue_refill._norm: content after the tags, date-stamp-free [feat:] tag, whitespace-collapsed."""
    l = re.sub(r"^(\s*- \[[ xX]\] )(\[(?:AUTO-SKIP|HUMAN-ONLY)[^\]]*\]\s*)+", r"\1", l)
    m = re.search(r"\]\s*(.*)$", l)
    c = re.sub(r"-\d{8}-", "-", (m.group(1) if m else l).strip())
    return re.sub(r"\s+", " ", c.lower())


def _local_pullable_count(backlog_text, progress_text, done_text=""):
    """Items the fleet can really take next: doable open lines already in the progress file + backlog lines queue_refill would actually pull (open, not
    held, not already queued/done). 2026-10-08: gating on the raw count of backlog T-lines (10 of them, all duplicates of queued/parked items) said 20 open
    >= 20 'no supply needed' while the lane had ZERO doable items and sat idle."""
    queued = {_norm_line(l) for l in (progress_text + "\n" + done_text).split("\n") if l.lstrip().startswith("- [")}
    n = open_count(progress_text)
    seen = set()
    for l in backlog_text.split("\n"):
        if re.match(r"^- \[ \] \[T[1-5]\]", l) and not _HELD.search(l) and not re.search(r"HUMAN/", l):
            k = _norm_line(l)
            if k not in queued and k not in seen:
                seen.add(k)
                n += 1
    return n


def _external_pullable():
    """scripts/ovn_backlog_eligibility.py `pullable(backlog_text, progress_text, done_text)` (package spec-compiler-v2) - the one definition of 'what the lane can pull'
    shared with queue_refill. Looked up next to this file, then in $OVN_DIR/scripts; None when it is not deployed yet."""
    for d in (os.path.dirname(os.path.abspath(__file__)), os.path.join(OVN_DIR, "scripts")):
        p = os.path.join(d, "ovn_backlog_eligibility.py")
        if os.path.exists(p):
            try:
                spec = importlib.util.spec_from_file_location("ovn_backlog_eligibility", p)
                mod = importlib.util.module_from_spec(spec)
                spec.loader.exec_module(mod)
                fn = getattr(mod, "pullable", None)
                if callable(fn):
                    return fn
            except Exception as e:
                sys.stderr.write("ovn_backlog_eligibility unusable (%s: %s) - local pullable_count used\n" % (type(e).__name__, e))
    return None


def pullable_count(backlog_text, progress_text, done_text=""):
    fn = _external_pullable()
    if fn is not None:
        try:
            n = fn(backlog_text, progress_text, done_text)
            if isinstance(n, int) and not isinstance(n, bool):
                return n
            raise TypeError("pullable() returned %r, not an int" % (n,))
        except Exception as e:
            sys.stderr.write("ovn_backlog_eligibility.pullable failed (%s: %s) - local pullable_count used\n" % (type(e).__name__, e))
    return _local_pullable_count(backlog_text, progress_text, done_text)


# ---------------------------------------------------------------- state: seen (key -> (ts, verdict)), resupplied counts, infra-failure counter
def load_seen(path, now=None):
    """Both formats: v2 `key<TAB>verdict<TAB>ts` and the old `key<TAB>ts` (read as passes-before). TTL per verdict: passes-before 7 d, red/supplied 36 h."""
    seen, now = {}, (time.time() if now is None else now)
    for l in read(path).split("\n"):
        parts = l.split("\t")
        try:
            ts = float(parts[-1])
        except ValueError:
            continue
        if len(parts) >= 3:
            k, verdict = parts[0], parts[1]
        elif len(parts) == 2:
            k, verdict = parts[0], "passes-before"
        else:
            continue
        if k and now - ts < TTL_BY_VERDICT.get(verdict, TTL_S):
            seen[k] = (ts, verdict)
    return seen


def save_seen(path, seen):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for k, (ts, verdict) in seen.items():
            f.write("%s\t%s\t%s\n" % (k, verdict, ts))


def load_resupplied(path):
    out = {}
    for l in read(path).split("\n"):
        k, _, n = l.rpartition("\t")
        if k and n.isdigit():
            out[k] = int(n)
    return out


def save_resupplied(path, d):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        for k, n in sorted(d.items()):
            f.write("%s\t%d\n" % (k, n))


def _supplied(seen, spec):
    """{key: ts} of the gaps of this (kind, file) that we put into the backlog (any gap hash) and still remember."""
    pre = "%s|%s|" % (spec["kind"], spec["file"])
    return {k: t for k, (t, v) in seen.items() if k.startswith(pre) and v in ("supplied", "red")}


def _last_supplied(seen, spec):
    """When this (kind, file) was last put into the backlog by us (any gap hash), or None."""
    ts = list(_supplied(seen, spec).values())
    return max(ts) if ts else None


_OPEN_RE = re.compile(r"^\s*- \[ \]")


def _filter(spec, lines, seen, resupplied, now=None, gap_present=True):
    """Why this gap must NOT be supplied right now, or None / 'resupply' when it may be.

    v1 suppressed on `kind in seen or (supply:<kind> in <whole backlog+progress text> and <file> in <whole text>)` - the two substrings could come from two
    unrelated lines, which hid 89 real red-before gaps. v2 looks at single LINES (backlog + progress + done):
      held-by-file   another OPEN supply item (any kind) already targets this file - two queued edits to one file collide
      open           an open line of this kind names this file
      done-cooldown  only [x] lines match: the gap is still there, but it was supplied < RESUPPLY_COOLDOWN_S ago, or its gap was re-supplied RESUPPLY_CAP times
                     already (a credit the fleet keeps giving without making the change must not loop), or the gap is gone (gap_present False)
      resupply       only [x] lines match, the SAME gap persists past the cooldown and the cap is not reached -> supply it again
      (new)          only [x] lines match but the gap's symbols differ from what we supplied: progress was made, the rest is a new serial item (returns None)
      seen           no line mentions it but a remembered verdict does (passes-before 7 d, supplied/red 36 h)
    """
    now = time.time() if now is None else now
    tag = "supply:%s)" % spec["kind"]
    pat = re.compile(r"(?<![\w./-])%s(?![\w./-])" % re.escape(spec["file"]))
    on_file = [l for l in lines if "supply:" in l and pat.search(l)]
    mine = [l for l in on_file if tag in l]
    if any(_OPEN_RE.match(l) for l in mine):
        return "open"
    if any(_OPEN_RE.match(l) for l in on_file):
        return "held-by-file"
    key = spec_key(spec)
    if mine:
        if not gap_present:
            return "done-cooldown"
        prior = _supplied(seen, spec)
        if prior and key not in prior:
            return None   # a DIFFERENT gap than the one we supplied: that item landed (serial items for a file with more than MAX_SYMBOLS symbols) - no cooldown, no cap
        ts = _last_supplied(seen, spec)
        if ts is not None and now - ts < RESUPPLY_COOLDOWN_S:
            return "done-cooldown"
        if resupplied.get(key, 0) >= RESUPPLY_CAP:
            return "done-cooldown"
        return "resupply"
    if key in seen:
        return "seen"
    return None


def spec_check(repo, lines):
    """Run ovn_spec_check.sh on candidate lines; returns {index: verdict}. verdict 'red' = VERIFY fails on the current checkout (good)."""
    sh = os.path.join(OVN_DIR, "scripts", "ovn_spec_check.sh")
    if not os.path.exists(sh):
        return None
    tmp = "/tmp/supply_spec_%d.md" % os.getpid()
    with open(tmp, "w") as f:
        f.write("\n".join(lines) + "\n")
    try:
        r = subprocess.run(["bash", sh, repo, tmp], capture_output=True, text=True, timeout=900, cwd=OVN_DIR)
    except Exception as e:
        sys.stderr.write("spec check failed: %s\n" % e)
        return None
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    out = {}
    for l in r.stdout.split("\n"):
        m = re.match(r"^(\d+)\t(\w[\w-]*)", l)
        if m:
            out[int(m.group(1)) - 1] = m.group(2)
    return out


def _state(name):
    return os.path.join(OVN_DIR, "state", name)


def _alert(level, repo, msg):
    try:
        with open(_state("alerts.log"), "a") as f:
            f.write("[%s] %s | work-supply:%s | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), level, repo, msg))
    except OSError:
        pass


def _bump_infra(repo, bad):
    """Consecutive passes whose spec check gave no usable verdict: one alerts.log warn when the counter reaches INFRA_ALERT_AFTER (exactly once per streak); a clean pass resets it."""
    path = _state("work_supply_infra_fail_%s" % repo)
    try:
        n = int(read(path).strip() or "0")
    except ValueError:
        n = 0
    n = n + 1 if bad else 0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write("%d\n" % n)
    if bad and n == INFRA_ALERT_AFTER:
        _alert("warn", repo, "spec check gave no usable verdict for %d consecutive passes (no-verdict/no-verify/bad-spec): specs are retried, not remembered - check ovn_spec_check.sh and the repo's origin/overnight/feature" % n)
    return n


def _acquire_lock(repo):
    os.makedirs(_state(""), exist_ok=True)
    fd = open(_state("work_supply_%s.lock" % repo), "a+")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fd.close()
        return None
    return fd


def _touch(path):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a"):
            pass
        os.utime(path, None)
    except OSError:
        pass


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        print("usage: ovn_work_supply.py <repo> [--dry-run] [--max N] [--no-spec-check] [--force] [--on-exhausted]")
        return 0
    repo, flags = argv[1], argv[2:]
    mx = int(flags[flags.index("--max") + 1]) if "--max" in flags else DEFAULT_MAX
    dry, on_exh = "--dry-run" in flags, "--on-exhausted" in flags
    if os.environ.get("OVN_WORK_SUPPLY", "on") == "off":
        print("%s: OVN_WORK_SUPPLY=off - skip" % repo)
        return 0
    root = os.path.join(OVN_DIR, "repos", repo)
    bl = os.path.join(OVN_DIR, "backlog", repo + ".md")
    prog = os.path.join(root, "OVERNIGHT_PROGRESS.md")
    if not os.path.isdir(root):
        print("%s: no checkout - skip" % repo)
        return 0
    lock = None
    if not dry:
        lock = _acquire_lock(repo)  # held until return: a cron pass and a runner-kicked pass must not write the backlog at the same time
        if lock is None:
            print("%s: another supply pass holds the lock - skip" % repo)
            return 0
    last_path = _state("work_supply_last_%s" % repo)
    if on_exh and os.path.exists(last_path) and time.time() - os.path.getmtime(last_path) < ON_EXHAUSTED_MIN_INTERVAL_S:
        print("%s: on-exhausted pass skipped - last pass %ds ago (< %ds)" % (repo, time.time() - os.path.getmtime(last_path), ON_EXHAUSTED_MIN_INTERVAL_S))
        return 0
    backlog_t, progress_t, done_t = read(bl), read(prog), read(os.path.join(root, "OVERNIGHT_DONE.md"))
    have = pullable_count(backlog_t, progress_t, done_t)
    if on_exh:
        if have != 0:
            print("%s: %d pullable items - lane not exhausted, nothing to kick" % (repo, have))
            return 0
    elif "--force" not in flags and have >= MIN_BACKLOG:
        print("%s: %d pullable items >= %d - no supply needed" % (repo, have, MIN_BACKLOG))
        return 0
    now = time.time()
    seen_path = _state("work_supply_seen_%s" % repo)
    resup_path = _state("work_supply_resupplied_%s" % repo)
    seen, resupplied = load_seen(seen_path, now), load_resupplied(resup_path)
    lines_all = (backlog_t + "\n" + progress_t + "\n" + done_t).split("\n")
    found = collect_all(root)
    stat = {"seen": 0, "open": 0, "done-cooldown": 0, "held-by-file": 0}
    specs, files_taken, resup_keys = [], set(), set()
    for s in found:
        why = _filter(s, lines_all, seen, resupplied, now)
        if why in stat:
            stat[why] += 1
            continue
        if s["file"] in files_taken:  # one item per file per pass: two queued edits to one file collide (rebase conflicts, revert loops)
            stat["held-by-file"] += 1
            continue
        if len(specs) >= mx * 3:  # over-collect: some will be dropped by the red-before check
            continue
        files_taken.add(s["file"])
        specs.append(s)
        if why == "resupply":
            resup_keys.add(spec_key(s))
    if not found:
        print("%s: no new mechanical gaps found" % repo)
        if not dry:
            _touch(last_path)
        return 0
    print("%s: %d gaps found, %d filtered (seen=%d open=%d done-cooldown=%d held-by-file=%d), %d specs" % (
        repo, len(found), sum(stat.values()), stat["seen"], stat["open"], stat["done-cooldown"], stat["held-by-file"], len(specs)))
    if not specs:
        if not dry:
            _touch(last_path)
        return 0
    lines = [render(s, repo) for s in specs]
    explicit_skip = "--no-spec-check" in flags
    verdicts = None if explicit_skip else spec_check(repo, lines)
    keep, dropped, infra = [], {}, 0
    for i, (s, l) in enumerate(zip(specs, lines)):
        v = "unchecked" if explicit_skip else (verdicts.get(i, "no-verdict") if verdicts is not None else "no-verdict")
        if v == "unchecked":
            keep.append((s, l, v))  # explicit --no-spec-check: the operator took responsibility; not remembered either
        elif v == "red":
            keep.append((s, l, v))
        elif v == "passes-before":
            dropped[v] = dropped.get(v, 0) + 1
            seen[spec_key(s)] = (now, v)  # already satisfied: do not re-check for the TTL
        else:
            # no-verdict / no-verify / bad-spec: the CHECKER is not conclusive about this spec - never remember it, retry next pass
            dropped[v] = dropped.get(v, 0) + 1
            infra += 1
    keep = keep[:mx]
    if dry:
        print("%s: DRY-RUN %d specs, %d red-before, dropped %s" % (repo, len(specs), len(keep), dropped or "none"))
        for _, l, _ in keep:
            print("  " + l[:200])
        return 0
    if not explicit_skip:
        _bump_infra(repo, infra > 0 or verdicts is None)
    if keep:
        with open(bl, "a") as f:
            f.write("\n# --- deterministic work supply %s (ovn_work_supply.py; VERIFY is red-before, mechanical) ---\n" % datetime.date.today().isoformat())
            f.write("\n".join(l for _, l, _ in keep) + "\n")
        for s, _, v in keep:
            if v != "unchecked":
                seen[spec_key(s)] = (now, "supplied")
            if spec_key(s) in resup_keys:
                resupplied[spec_key(s)] = resupplied.get(spec_key(s), 0) + 1
        save_resupplied(resup_path, resupplied)
        _alert("info", repo, "added %d mechanical item(s) (dropped %s)" % (len(keep), dropped or "none"))
        _touch(_state("supply_kick"))  # the runner's idle sleep exits early on this
    save_seen(seen_path, seen)
    _touch(last_path)
    print("%s: ADDED %d deterministic item(s) to backlog (%d specs, dropped %s)" % (repo, len(keep), len(specs), dropped or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
