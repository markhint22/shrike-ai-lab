#!/usr/bin/env python3
"""tools/fix_router_limiters.py - normalise slowapi `@limiter.limit` decorators on FastAPI routes to the documented shape (2026-10-08).

CAVEAT - read before applying (learned the hard way the same day): with app.add_middleware(SlowAPIMiddleware) the limits are ALSO enforced from the registry
`limiter.limit` fills at decoration time, whatever the decorator order, so a mis-ordered decorator is NOT inert in production. Reordering switches a route to the
wrapper path, which is enforced in the test suite too (applying this to auth.py made login's 10/min limit 429 the test fixtures). Use it on NEW/unsafe routers
(or with the suite as the judge), never as a blind bulk pass. The numbers matter more than the shape: see tests/test_rate_limit_sanity.py.

Found while debugging last night's red gate: the fleet's model-written rate-limit changes were INERT or broken in three ways, and its tests could not see it
(the limiter is disabled under test):
  1. decorator ORDER: `@limiter.limit(..)` written ABOVE `@router.post(..)` wraps the already-registered route, so FastAPI never sees the limit.
  2. NAME CLASH: slowapi needs a starlette `request: Request` parameter; 13 routes already used `request` for their JSON body model.
  3. missing `request: Request` altogether.
This codemod fixes all three, idempotently, without reformatting the file (token/line based; comments and layout untouched):
  * the limiter decorator is moved directly BELOW the route decorator(s);
  * an arg named `request` that is NOT annotated `Request` is renamed `payload` everywhere in that function (NAME tokens only) and `request: Request,` is added first;
  * `request: Request,` is added first when absent; `Request` is added to the file's `from fastapi import ...` line when missing.

usage: fix_router_limiters.py <router.py> [<router.py> ...] [--check]     (--check: report problems, change nothing, exit 1 if any)
"""
import ast
import io
import re
import sys
import tokenize


def _dec_src(d):
    return ast.unparse(d)


def route_functions(tree):
    out = []
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
            has_route = any(re.match(r"router\.(get|post|put|patch|delete)\(", _dec_src(d)) for d in n.decorator_list)
            has_lim = any("limiter.limit" in _dec_src(d) for d in n.decorator_list)
            if has_route and has_lim:
                out.append(n)
    return out


def problems(src):
    """-> list of (function name, problem) for a router module's source."""
    tree = ast.parse(src)
    out = []
    for n in route_functions(tree):
        idx_route = max(i for i, d in enumerate(n.decorator_list) if re.match(r"router\.", _dec_src(d)))
        idx_lim = min(i for i, d in enumerate(n.decorator_list) if "limiter.limit" in _dec_src(d))
        if idx_lim < idx_route:
            out.append((n.name, "limiter decorator is above the route decorator (inert)"))
        args = {a.arg: a for a in n.args.args + n.args.kwonlyargs}
        r = args.get("request")
        if r is None:
            out.append((n.name, "no `request: Request` parameter"))
        elif not (r.annotation is not None and _dec_src(r.annotation).split(".")[-1] == "Request"):
            out.append((n.name, "`request` is not a starlette Request (body model named request)"))
    return out


def _rename_name_tokens(lines, first, last, old, new, body_from):
    """Rename NAME tokens `old` -> `new` in lines[first-1:last] (1-based inclusive); attribute names (`x.request`), keyword-argument names in calls
    (`foo(request=...)`, body lines only) and strings/comments are untouched. Lines before `body_from` are the signature: renamed unconditionally."""
    seg = "\n".join(lines[first - 1:last]) + "\n"
    toks = list(tokenize.generate_tokens(io.StringIO(seg).readline))
    edits = []
    for i, t in enumerate(toks):
        if t.type == tokenize.NAME and t.string == old:
            prev = toks[i - 1] if i else None
            nxt = toks[i + 1] if i + 1 < len(toks) else None
            if prev is not None and prev.type == tokenize.OP and prev.string == ".":
                continue
            in_body = (first - 1) + t.start[0] >= body_from
            if in_body and nxt is not None and nxt.type == tokenize.OP and nxt.string == "=" and prev is not None and prev.type == tokenize.OP and prev.string in ("(", ","):
                continue  # keyword argument name in a call
            edits.append((t.start, t.end))
    seg_lines = seg.split("\n")
    for (sr, sc), (er, ec) in sorted(edits, reverse=True):
        l = seg_lines[sr - 1]
        seg_lines[sr - 1] = l[:sc] + new + l[ec:]
    lines[first - 1:last] = seg_lines[:last - first + 1]


def fix(src):
    """-> (new_src, [(function, what)]). Idempotent."""
    tree = ast.parse(src)
    lines = src.split("\n")
    changes = []
    # bottom-up so earlier line numbers stay valid
    for n in sorted(route_functions(tree), key=lambda n: -n.lineno):
        decs = n.decorator_list
        first = min(d.lineno for d in decs)
        def_line = n.lineno  # the `def` line (decorators precede it in py3.8+ lineno semantics: FunctionDef.lineno is the def line)
        # 1. rename a clashing body arg inside the function (before touching signature text)
        args = {a.arg: a for a in n.args.args + n.args.kwonlyargs}
        r = args.get("request")
        clash = r is not None and not (r.annotation is not None and _dec_src(r.annotation).split(".")[-1] == "Request")
        if clash:
            new = "payload"
            while new in args:
                new += "_"
            _rename_name_tokens(lines, def_line, n.end_lineno, "request", new, n.body[0].lineno)
            changes.append((n.name, "renamed body arg request -> %s" % new))
        # 2. add `request: Request,` as the first parameter when there is no real Request param
        if r is None or clash:
            # signature starts at the `def` line: insert right after the first '(' of `def name(`
            for k in range(def_line - 1, min(def_line + 3, len(lines))):
                m = re.search(r"def\s+%s\s*\(" % re.escape(n.name), lines[k])
                if m:
                    after = lines[k][m.end():]
                    if after.strip() == "":  # multi-line signature: new line with the next line's indentation
                        indent = re.match(r"\s*", lines[k + 1]).group(0) or "    "
                        lines.insert(k + 1, "%srequest: Request," % indent)
                    else:
                        lines[k] = lines[k][:m.end()] + "request: Request, " + after
                    changes.append((n.name, "added request: Request"))
                    break
        # 3. decorator order: every limiter decorator goes directly below the last route decorator
        spans = [(d.lineno, d.end_lineno, _dec_src(d)) for d in decs]
        # recompute spans if lines were inserted ABOVE decorators (they never are: inserts happen at/after def)
        route_spans = [s for s in spans if re.match(r"router\.", s[2])]
        lim_spans = [s for s in spans if "limiter.limit" in s[2]]
        last_route_end = max(s[1] for s in route_spans)
        if any(s[0] < last_route_end for s in lim_spans):
            blocks = [lines[s[0] - 1:s[1]] for s in lim_spans]
            for s in sorted(lim_spans, reverse=True):
                del lines[s[0] - 1:s[1]]
            removed_before = sum(s[1] - s[0] + 1 for s in lim_spans if s[0] < last_route_end)
            ins_at = last_route_end - removed_before  # 0-based index just after the last route decorator
            for b in reversed(blocks):
                lines[ins_at:ins_at] = b
            changes.append((n.name, "moved limiter decorator below the route decorator"))
    new_src = "\n".join(lines)
    if changes and not re.search(r"from fastapi import[^\n]*\bRequest\b", new_src) and not re.search(r"^from starlette\.requests import[^\n]*\bRequest\b", new_src, re.M):
        m = re.search(r"^from fastapi import ([^\n(]+)$", new_src, re.M)
        if m:
            new_src = new_src[:m.start(1)] + m.group(1).rstrip() + ", Request" + new_src[m.end(1):]
        else:
            new_src = "from fastapi import Request\n" + new_src
        changes.append(("<module>", "imported Request"))
    ast.parse(new_src)  # never emit something that does not parse
    return new_src, changes


def main(argv):
    check = "--check" in argv
    files = [a for a in argv[1:] if not a.startswith("--")]
    bad = 0
    for p in files:
        src = open(p).read()
        if check:
            for name, what in problems(src):
                print("%s: %s: %s" % (p, name, what))
                bad += 1
            continue
        new, ch = fix(src)
        if ch:
            open(p, "w").write(new)
            print("%s: %d change(s): %s" % (p, len(ch), "; ".join("%s: %s" % c for c in ch)[:300]))
        else:
            print("%s: already correct" % p)
    return 1 if (check and bad) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
