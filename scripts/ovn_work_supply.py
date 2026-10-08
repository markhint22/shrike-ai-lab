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

usage: ovn_work_supply.py <repo> [--dry-run] [--max N] [--no-spec-check] [--force]
env:   OVN_DIR (default ~/overnight-queue); OVN_SUPPLY_MIN_BACKLOG (default 20: only supply when the repo's open T-items are below this)
exit:  0 always; prints one summary line.
"""
import ast
import datetime
import os
import re
import subprocess
import sys
import time

OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
MIN_BACKLOG = int(os.environ.get("OVN_SUPPLY_MIN_BACKLOG", "20"))
MAX_SYMBOLS = 6
SKIP_DIRS = {".git", "node_modules", ".venv", "venv", "__pycache__", ".godot", "dist", "build", "addons", "htmlcov", "alembic", "migrations"}
TTL_S = 7 * 86400  # a key is not re-supplied for this long after being supplied (a failed/parked item must not be re-added every pass)


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


def verify_docstrings(path, names):
    return ("python3 -c \"import ast,sys;t=ast.parse(open('%s').read());names=%r;"
            "bad=[n.name for n in ast.walk(t) if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef,ast.ClassDef)) and n.name in names and not (ast.get_docstring(n) or '').strip()];"
            "sys.exit(1 if bad else 0)\"" % (path, list(names)))


def verify_gd_docs(path, names):
    # a `##` doc-comment line directly above each named function (Godot's doc-comment syntax); no literal '>' (the runner refuses redirect-looking characters)
    return ("python3 -c \"import re,sys;L=open('%s').read().split(chr(10));names=%r;"
            "bad=[n for n in names if not any(re.match(r'(static )?func '+n+r'[(]',l) and i and L[i-1].lstrip().startswith('##') for i,l in enumerate(L))];"
            "sys.exit(1 if bad else 0)\"" % (path, list(names)))


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
        yield {"kind": "swallowed-exception", "file": r, "tier": "T2", "cat": "python",
               "text": "Replace the bare `pass` in the %d `except` handler(s) at line(s) %s with real handling: `logger.exception(...)` for unexpected errors, "
                       "`logger.debug(...)` for expected ones (ImportError/CancelledError/KeyError lookups). Define `logger = logging.getLogger(__name__)` at module top if the file "
                       "has none. Change nothing else in the file." % (len(hs), lines),
               "verify": verify_swallowed(r)}


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
               "verify": verify_rate_limit(r)}


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
               "verify": verify_returns_none(r, names)}


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
                   "verify": verify_gd_void(r, names)}


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
                           "Annotations only - change no logic, add no imports other than `typing`." % ", ".join("`%s`" % n for n in names),
                   "verify": verify_returns_none(r, names)}


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
                   "verify": verify_docstrings(r, names)}


def c_gd_docs(root):
    """Public GDScript functions with no `##` doc comment directly above."""
    for p in walk(root, (".gd",)):
        r = rel(root, p)
        if is_test_path(r) or r.startswith("addons/"):
            continue
        L = read(p).split("\n")
        names = []
        for i, l in enumerate(L):
            m = re.match(r"^(?:static )?func (\w+)\(", l)
            if m and not m.group(1).startswith("_") and i and not L[i - 1].lstrip().startswith("##") and m.group(1) not in names:
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
                   "verify": verify_gd_docs(r, names)}


COLLECTORS = [c_swallowed, c_rate_limit, c_returns_none, c_gd_void, c_return_types, c_docstrings, c_gd_docs]


def collect_all(root):
    """Round-robin the collectors so one kind cannot crowd out the rest."""
    per = []
    for fn in COLLECTORS:
        try:
            per.append(list(fn(root)))
        except Exception as e:  # a broken collector must not kill the pass
            sys.stderr.write("collector %s failed: %s\n" % (fn.__name__, e))
            per.append([])
    out = []
    while any(per):
        for lst in per:
            if lst:
                out.append(lst.pop(0))
    return out


def spec_key(s):
    return "%s|%s" % (s["kind"], s["file"])


def render(s, repo):
    slug = re.sub(r"[^a-z0-9]+", "-", ("%s-%s" % (s["kind"], s["file"])).lower()).strip("-")[:48]
    return "- [ ] [%s] %s — %s VERIFY: `%s`. (cat:%s; multifile:no; supply:%s) [feat:%s-%s-supply-%s]" % (
        s["tier"], s["file"], s["text"], s["verify"], s["cat"], s["kind"], repo, datetime.date.today().strftime("%Y%m%d"), slug)


_HELD = re.compile(r"HUMAN-ONLY|AUTO-SKIP|BLOCKED ITEM|\(retired-|\[CLAUDE\]")


def open_count(text):
    """Open items the fleet can actually take (same exclusions as the queue's doable count): held/escalated/retired lines do not count."""
    return sum(1 for l in text.split("\n") if re.match(r"^- \[ \] \[T[1-5]\]", l) and not _HELD.search(l))


def _norm_line(l):
    """Same identity idea as queue_refill._norm: content after the tags, date-stamp-free [feat:] tag, whitespace-collapsed."""
    l = re.sub(r"^(\s*- \[[ xX]\] )(\[(?:AUTO-SKIP|HUMAN-ONLY)[^\]]*\]\s*)+", r"\1", l)
    m = re.search(r"\]\s*(.*)$", l)
    c = re.sub(r"-\d{8}-", "-", (m.group(1) if m else l).strip())
    return re.sub(r"\s+", " ", c.lower())


def pullable_count(backlog_text, progress_text, done_text=""):
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


def load_seen(path):
    seen, now = {}, time.time()
    for l in read(path).split("\n"):
        k, _, ts = l.rpartition("\t")
        try:
            if k and now - float(ts) < TTL_S:
                seen[k] = float(ts)
        except ValueError:
            pass
    return seen


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


def main(argv):
    if len(argv) < 2 or argv[1].startswith("-"):
        print("usage: ovn_work_supply.py <repo> [--dry-run] [--max N] [--no-spec-check] [--force]")
        return 0
    repo, flags = argv[1], argv[2:]
    mx = int(flags[flags.index("--max") + 1]) if "--max" in flags else 8
    if os.environ.get("OVN_WORK_SUPPLY", "on") == "off":
        print("%s: OVN_WORK_SUPPLY=off - skip" % repo)
        return 0
    root = os.path.join(OVN_DIR, "repos", repo)
    bl = os.path.join(OVN_DIR, "backlog", repo + ".md")
    prog = os.path.join(root, "OVERNIGHT_PROGRESS.md")
    if not os.path.isdir(root):
        print("%s: no checkout - skip" % repo)
        return 0
    existing = read(bl) + "\n" + read(prog)
    have = pullable_count(read(bl), read(prog), read(os.path.join(root, "OVERNIGHT_DONE.md")))
    if "--force" not in flags and have >= MIN_BACKLOG:
        print("%s: %d pullable items >= %d - no supply needed" % (repo, have, MIN_BACKLOG))
        return 0
    seen_path = os.path.join(OVN_DIR, "state", "work_supply_seen_%s" % repo)
    seen = load_seen(seen_path)
    specs, files_taken = [], set()
    for s in collect_all(root):
        k = spec_key(s)
        if k in seen or ("supply:%s" % s["kind"] in existing and s["file"] in existing):
            continue
        if s["file"] in files_taken:  # one item per file per pass: two queued edits to one file collide (rebase conflicts, revert loops)
            continue
        files_taken.add(s["file"])
        specs.append(s)
        if len(specs) >= mx * 3:  # over-collect: some will be dropped by the red-before check
            break
    if not specs:
        print("%s: no new mechanical gaps found" % repo)
        return 0
    lines = [render(s, repo) for s in specs]
    verdicts = None if "--no-spec-check" in flags else spec_check(repo, lines)
    keep = []
    dropped = {}
    for i, (s, l) in enumerate(zip(specs, lines)):
        v = "unchecked" if verdicts is None else verdicts.get(i, "no-verdict")
        if verdicts is not None and v != "red":
            dropped[v] = dropped.get(v, 0) + 1
            seen[spec_key(s)] = time.time()  # already satisfied / bad spec: do not retry for TTL
            continue
        keep.append((s, l))
        if len(keep) >= mx:
            break
    if "--dry-run" in flags:
        print("%s: DRY-RUN %d specs, %d red-before, dropped %s" % (repo, len(specs), len(keep), dropped or "none"))
        for _, l in keep:
            print("  " + l[:200])
        return 0
    if keep:
        with open(bl, "a") as f:
            f.write("\n# --- deterministic work supply %s (ovn_work_supply.py; VERIFY is red-before, mechanical) ---\n" % datetime.date.today().isoformat())
            f.write("\n".join(l for _, l in keep) + "\n")
        for s, _ in keep:
            seen[spec_key(s)] = time.time()
    os.makedirs(os.path.dirname(seen_path), exist_ok=True)
    with open(seen_path, "w") as f:
        for k, ts in seen.items():
            f.write("%s\t%s\n" % (k, ts))
    try:
        with open(os.path.join(OVN_DIR, "state", "alerts.log"), "a") as f:
            if keep:
                f.write("[%s] info | work-supply:%s | added %d mechanical item(s) (dropped %s)\n" % (time.strftime("%Y-%m-%d %H:%M:%S"), repo, len(keep), dropped or "none"))
    except OSError:
        pass
    print("%s: ADDED %d deterministic item(s) to backlog (%d specs, dropped %s)" % (repo, len(keep), len(specs), dropped or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
