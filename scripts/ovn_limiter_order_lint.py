#!/usr/bin/env python3
"""scripts/ovn_limiter_order_lint.py - static limiter-order lint (P6a, 2026-10-27).

The trap (iptv_apps auth.py, found 2026-10-11): with slowapi the rate-limit decorator must sit BELOW the route decorator,

    @router.post("/login")        # registers the function it receives
    @limiter.limit("5/minute")    # wraps the function first
    async def login(request: Request): ...

Written the other way round (limiter ABOVE the route decorator) the router registers the UNWRAPPED function and the limit is never enforced: login / register / password-reset
ran without any limit for months and every test still passed. This linter finds that shape with the ast module, so it needs no import of the target and no running app.

Rule L1: a function whose decorator list has a limiter decorator listed ABOVE (earlier than) a route decorator.
  route decorator  : a call `<anything>.get|post|put|delete|patch|options|head|route|api_route|websocket(<path>, ...)` whose first argument is a string literal (or has `path=`),
                     or a bare/called alias bound earlier in the module by `name = <obj>.get|post|...`. A call whose first argument is not a string (cache.get(key)) is not a route.
  limiter decorator: `<obj>.limit(...)` / `<obj>.shared_limit(...)` (called or bare) where <obj> is a name bound by `X = Limiter(...)` / `X = slowapi.Limiter(...)`, an imported
                     name or attribute chain whose last part contains 'limit' (limiter, rate_limiter, app.state.limiter), or an alias `lim = limiter.limit` /
                     `five = limiter.limit("5/minute")` / `from x import limiter as lm`. A bare-name decorator counts only when it is a recorded alias, so an unrelated `@limit` never fires.
  Async and sync defs, methods in classes, nested functions: all walked. Syntax errors: skipped silently (reported as 'skip' in --json), never a finding.

Modes (the CALLER's switch is OVN_LIMITER_LINT=off|shadow|enforce, default shadow, see lib_limiter_lint.sh; this script only reports):
  ovn_limiter_order_lint.py check FILE...                           exit 1 when any finding, 0 otherwise; one line per finding: path:line: L1 ...
  ovn_limiter_order_lint.py diff --repo DIR --before SHA [--after SHA]   lint the .py files the commit range touched, report only findings ABSENT from the BEFORE version (keyed by function+rule)
  add --json for one JSON object on stdout.
"""
import ast
import json
import os
import subprocess
import sys

ROUTE_ATTRS = {"get", "post", "put", "delete", "patch", "options", "head", "route", "api_route", "websocket"}
LIMIT_ATTRS = {"limit", "shared_limit"}


def _chain(node):
    """Dotted name parts of Name/Attribute chain, or None."""
    parts = []
    while isinstance(node, ast.Attribute):
        parts.append(node.attr)
        node = node.value
    if isinstance(node, ast.Name):
        parts.append(node.id)
        return list(reversed(parts))
    return None


def _is_pathlike(node, strnames):
    """A route path expression: a string literal, an f-string, a string concat/%-format, or a NAME bound to a string in this module (or an ALL_CAPS constant, e.g. imported).
    A lowercase unbound name (cache.get(key)) is NOT a path, so non-route `.get(...)` calls stay unrecognised."""
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str)
    if isinstance(node, ast.JoinedStr):
        return True
    if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mod)):
        return _is_pathlike(node.left, strnames) or (isinstance(node.op, ast.Add) and _is_pathlike(node.right, strnames))
    c = _chain(node)
    if c:
        return c[-1] in strnames or (c[-1].isupper() and len(c[-1]) > 1)
    return False


def _is_str_first(call, strnames=frozenset()):
    if call.args and _is_pathlike(call.args[0], strnames):
        return True
    return any(k.arg == "path" and _is_pathlike(k.value, strnames) for k in call.keywords)


class _Aliases(ast.NodeVisitor):
    """Names bound at ANY scope in the file (module-level in practice): limiter objects, limiter-decorator aliases, route-decorator aliases."""

    def __init__(self):
        self.limiters = set()
        self.limit_aliases = set()
        self.route_aliases = set()
        self.strnames = set()

    def visit_ImportFrom(self, node):
        for a in node.names:
            n = a.asname or a.name
            if "limit" in a.name.lower() and a.name.lower() not in ("limit", "shared_limit"):
                self.limiters.add(n)
        self.generic_visit(node)

    def visit_Import(self, node):
        for a in node.names:
            if "limit" in a.name.split(".")[-1].lower() and a.asname:
                self.limiters.add(a.asname)

    def visit_Assign(self, node):
        v = node.value
        names = [t.id for t in node.targets if isinstance(t, ast.Name)]
        if names and isinstance(v, (ast.Constant, ast.JoinedStr, ast.BinOp)) and _is_pathlike(v, frozenset()):
            self.strnames.update(names)                   # PATH = "/login"  /  PATH = PREFIX + "/login"
        if names:
            inner = v.func if isinstance(v, ast.Call) else v
            c = _chain(inner)
            if isinstance(v, ast.Call) and c and c[-1] == "Limiter":
                self.limiters.update(names)
            elif c and len(c) >= 2 and c[-1] in LIMIT_ATTRS:
                self.limit_aliases.update(names)          # lim = limiter.limit  /  five = limiter.limit("5/minute")
            elif c and len(c) >= 2 and c[-1] in ROUTE_ATTRS and not isinstance(v, ast.Call):
                self.route_aliases.update(names)          # post = router.post
        self.generic_visit(node)


def _is_limiter_base(chain, al):
    if not chain:
        return False
    return chain[-1] in al.limiters or chain[0] in al.limiters or "limit" in chain[-1].lower()


def classify(dec, al):
    """-> 'limit' | 'route' | None for one decorator expression."""
    call = dec if isinstance(dec, ast.Call) else None
    target = dec.func if call else dec
    c = _chain(target)
    if not c:
        return None
    if len(c) >= 2:
        attr, base = c[-1], c[:-1]
        if attr in LIMIT_ATTRS and _is_limiter_base(base, al):
            return "limit"
        if attr in ROUTE_ATTRS and call is not None and _is_str_first(call, al.strnames) and not _is_limiter_base(base, al):
            return "route"
        return None
    name = c[0]
    if name in al.limit_aliases:
        return "limit"
    if name in al.route_aliases and call is not None and _is_str_first(call, al.strnames):
        return "route"
    return None


def lint_source(src, path="<src>"):
    """-> (findings, skipped_reason). finding = {path, line, func, limit_line, route_line, rule}."""
    try:
        tree = ast.parse(src)
    except (SyntaxError, ValueError) as ex:
        return [], "syntax: %s" % type(ex).__name__
    al = _Aliases()
    al.visit(tree)
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        kinds = [(classify(d, al), d.lineno) for d in node.decorator_list]       # source order: first = topmost
        for i, (k, ln) in enumerate(kinds):
            if k != "limit":
                continue
            below = [l2 for k2, l2 in kinds[i + 1:] if k2 == "route"]
            if below:
                out.append({"path": path, "line": ln, "func": node.name, "limit_line": ln, "route_line": below[0], "rule": "L1"})
                break
    out.sort(key=lambda f: (f["line"], f["func"]))
    return out, None


def lint_files(paths):
    findings, skipped = [], []
    for p in paths:
        try:
            with open(p, encoding="utf-8", errors="replace") as f:
                src = f.read()
        except OSError as ex:
            skipped.append({"path": p, "why": "unreadable: %s" % type(ex).__name__})
            continue
        f_, why = lint_source(src, p)
        findings += f_
        if why:
            skipped.append({"path": p, "why": why})
    return findings, skipped


def touched_py(repo, before, after):
    """[(abs_path, rel_path, before_rel)] for .py files added/modified/renamed in before..after (the AFTER tree is what gets read). before_rel is None for added files."""
    rng = "%s..%s" % (before, after or "HEAD")
    try:
        r = subprocess.run(["git", "-C", repo, "diff", "--name-status", "-M", "--diff-filter=AMR", rng], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return []
    if r.returncode != 0:
        return []
    out = []
    for line in r.stdout.splitlines():
        parts = line.split("\t")
        st, new = parts[0][:1], parts[-1]
        if not new.endswith(".py") or not os.path.isfile(os.path.join(repo, new)):
            continue
        out.append((os.path.join(repo, new), new, (parts[1] if st == "R" and len(parts) > 2 else None if st == "A" else new)))
    return out


def _before_keys(repo, before, rel):
    """{(func, rule): count} of findings in the BEFORE version of a file (empty when added / unreadable / unparsable)."""
    if not rel:
        return {}
    try:
        r = subprocess.run(["git", "-C", repo, "show", "%s:%s" % (before, rel)], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return {}
    if r.returncode != 0:
        return {}
    found, _ = lint_source(r.stdout, rel)
    keys = {}
    for f in found:
        k = (f["func"], f["rule"])
        keys[k] = keys.get(k, 0) + 1
    return keys


def new_findings(repo, before, after):
    """Findings the commit range INTRODUCED: per touched file, drop findings whose (func, rule) already existed in the BEFORE version (line numbers shift, so they are not the key).
    A pre-existing offender in a file the commit merely touched is not reported, so it neither alerts on every cycle nor (enforce) reverts an unrelated good commit."""
    paths, skipped, out = [], [], []
    for ap, rel, brel in touched_py(repo, before, after):
        paths.append(ap)
        f_, sk = lint_files([ap])
        skipped += sk
        base = _before_keys(repo, before, brel)
        for f in f_:
            k = (f["func"], f["rule"])
            if base.get(k, 0) > 0:
                base[k] -= 1
                continue
            out.append(f)
    return paths, out, skipped


def fmt(f, root=None):
    p = os.path.relpath(f["path"], root) if root else f["path"]
    return "%s:%d: L1 %s(): limiter decorator (line %d) is ABOVE the route decorator (line %d) - the router registers the unwrapped function, the limit is never enforced; put the limiter BELOW the route decorator" % (
        p, f["line"], f["func"], f["limit_line"], f["route_line"])


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    js = "--json" in argv
    argv = [a for a in argv if a != "--json"]
    if not argv or argv[0] not in ("check", "diff"):
        print(__doc__.split("\n\n")[0] + "\nusage: check FILE... | diff --repo DIR --before SHA [--after SHA] [--json]", file=sys.stderr)
        return 2
    cmd, rest = argv[0], argv[1:]
    root = None
    if cmd == "check":
        paths = rest
        findings, skipped = lint_files(paths)
    else:
        opts = {}
        i = 0
        while i < len(rest):
            if rest[i] in ("--repo", "--before", "--after") and i + 1 < len(rest):
                opts[rest[i]] = rest[i + 1]
                i += 2
            else:
                print("bad argument: %s" % rest[i], file=sys.stderr)
                return 2
        if "--repo" not in opts or "--before" not in opts:
            print("diff needs --repo and --before", file=sys.stderr)
            return 2
        root = opts["--repo"]
        paths, findings, skipped = new_findings(root, opts["--before"], opts.get("--after"))
    if js:
        print(json.dumps({"files": len(paths), "findings": findings, "skipped": skipped}))
    else:
        for f in findings:
            print(fmt(f, root))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
