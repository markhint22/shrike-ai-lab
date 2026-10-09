#!/usr/bin/env python3
"""tools/fix_router_limiters.py: inert / clashing slowapi decorators are repaired without reformatting; correct code is untouched (idempotent)."""
import ast
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "tools"))
import fix_router_limiters as F  # noqa: E402

P = Fl = 0


def ok(name, cond, extra=""):
    global P, Fl
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        Fl += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


SRC = '''from fastapi import APIRouter, Depends, HTTPException
from app.core.limiter import limiter

router = APIRouter()


@limiter.limit("100/hour")
@router.post("/identify", response_model=Out)
async def identify_content(
    request: IdentifyRequest,
    db=Depends(get_db),
):
    """Handle the request body."""
    x = request.stream_id  # the request id
    y = other.request
    return foo(request=request, name="request")


@limiter.limit("100/hour")
@router.get("/plain")
def plain(db=Depends(get_db)):
    return 1


@router.get("/ok")
@limiter.limit("60/minute")
def already_ok(request: Request, db=Depends(get_db)):
    return 2


@limiter.limit("5/minute")
@router.get(
    "/multi",
    response_model=Out,
)
def multi_line_route(
    db=Depends(get_db),
):
    return 3


@router.get("/nolimit")
def not_limited():
    return 4
'''

probs = dict(F.problems(SRC))
ok("detects the inert order + body-named-request on identify_content", "identify_content" in probs)
ok("detects missing request param + inert order on plain", "plain" in probs)
ok("does not flag an already-correct route", "already_ok" not in probs)
ok("does not touch a route with no limiter", "not_limited" not in probs)

new, ch = F.fix(SRC)
tree = ast.parse(new)
fn = {n.name: n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}


def decs(n):
    return [ast.unparse(d) for d in n.decorator_list]


def argn(n):
    return [a.arg for a in n.args.args]


ok("identify_content: limiter now BELOW the route decorator", decs(fn["identify_content"])[0].startswith("router.post") and "limiter.limit" in decs(fn["identify_content"])[1], decs(fn["identify_content"]))
ok("identify_content: params are request: Request first, then payload (renamed body), db", argn(fn["identify_content"]) == ["request", "payload", "db"], argn(fn["identify_content"]))
ok("identify_content: request annotated Request", ast.unparse(fn["identify_content"].args.args[0].annotation) == "Request")
ok("body usages renamed (payload.stream_id) ...", "payload.stream_id" in new and "x = payload.stream_id" in new)
ok("... but attribute `other.request`, the comment text and the string 'request' are untouched", "other.request" in new and "# the request id" in new and 'name="request"' in new, new)
ok("... and the call keyword/value `foo(request=request)` renamed only on the value side", "foo(request=payload" in new, new)
ok("plain: gets request: Request first and the limiter below the route", argn(fn["plain"]) == ["request", "db"] and decs(fn["plain"])[0].startswith("router.get") and "limiter.limit" in decs(fn["plain"])[1], (argn(fn["plain"]), decs(fn["plain"])))
ok("multi-line route decorator: limiter moved below the WHOLE decorator, request added to a multi-line signature",
   decs(fn["multi_line_route"])[0].startswith("router.get") and "limiter.limit" in decs(fn["multi_line_route"])[1] and argn(fn["multi_line_route"]) == ["request", "db"], (decs(fn["multi_line_route"]), argn(fn["multi_line_route"])))
ok("already-correct route is byte-for-byte unchanged", "def already_ok(request: Request, db=Depends(get_db)):\n    return 2" in new and "@router.get(\"/ok\")\n@limiter.limit(\"60/minute\")\ndef already_ok" in new)
ok("route without a limiter is untouched", "@router.get(\"/nolimit\")\ndef not_limited():" in new)
ok("`Request` imported from fastapi", "from fastapi import APIRouter, Depends, HTTPException, Request" in new, new[:200])
ok("docstring text is not rewritten", '"""Handle the request body."""' in new)
ok("no problems remain after the fix", F.problems(new) == [])
new2, ch2 = F.fix(new)
ok("idempotent: a second run changes nothing", new2 == new and ch2 == [])

# name collision: a function that already has `payload`
SRC2 = 'from fastapi import APIRouter\nfrom app.core.limiter import limiter\nrouter = APIRouter()\n@limiter.limit("60/minute")\n@router.post("/x")\ndef f(request: Body, payload: int):\n    return request.a + payload\n'
n3, _ = F.fix(SRC2)
ok("rename avoids colliding with an existing `payload` parameter (uses payload_)", "payload_" in n3 and "payload_.a + payload" in n3 and F.problems(n3) == [], n3)

# starlette import variant
SRC3 = 'from starlette.requests import Request\nfrom fastapi import APIRouter\nfrom app.core.limiter import limiter\nrouter = APIRouter()\n@limiter.limit("60/minute")\n@router.get("/x")\ndef g():\n    return 1\n'
n4, _ = F.fix(SRC3)
ok("does not add a fastapi import when Request already comes from starlette", n4.count("import") == 3 and "from fastapi import APIRouter\n" in n4, n4)

# --check mode on a real-shaped file
import tempfile, subprocess
d = tempfile.mkdtemp()
p = os.path.join(d, "r.py")
open(p, "w").write(SRC)
r = subprocess.run([sys.executable, os.path.join(HERE, "..", "..", "tools", "fix_router_limiters.py"), p, "--check"], capture_output=True, text=True)
ok("--check reports problems and exits 1 without modifying the file", r.returncode == 1 and open(p).read() == SRC and "identify_content" in r.stdout, r.stdout)
r = subprocess.run([sys.executable, os.path.join(HERE, "..", "..", "tools", "fix_router_limiters.py"), p], capture_output=True, text=True)
r2 = subprocess.run([sys.executable, os.path.join(HERE, "..", "..", "tools", "fix_router_limiters.py"), p, "--check"], capture_output=True, text=True)
ok("fixing then --check exits 0", r2.returncode == 0, r2.stdout + r.stdout)

print("\n%d passed, %d failed" % (P, Fl))
sys.exit(1 if Fl else 0)
