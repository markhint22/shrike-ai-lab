#!/usr/bin/env python3
"""scripts/ovn_work_supply.py + scripts/ovn_spec_check.sh: deterministic mechanical work items with red-before VERIFYs.
Fixture: a bare origin + clone with an origin/overnight/feature ref (what ovn_spec_check.sh checks out)."""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SUPPLY = os.path.join(ROOT, "scripts", "ovn_work_supply.py")
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import ovn_work_supply as W  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def sh(*a, cwd=None, env=None):
    return subprocess.run(a, cwd=cwd, capture_output=True, text=True, env=env)


def find_tools_py(mods):
    """A python that has every module in `mods` (ruff / pytest): $OVN_TEST_TOOLS_PY, this interpreter, the box's iptv venv, ~/aider-venv. None when genuinely absent."""
    for c in (os.environ.get("OVN_TEST_TOOLS_PY"), sys.executable, os.path.expanduser("~/overnight-queue/repos/iptv_apps/iptv-backend/.venv/bin/python"),
              os.path.expanduser("~/aider-venv/bin/python")):
        if c and os.path.exists(c) and all(subprocess.run([c, "-m", m, "--version"], capture_output=True).returncode == 0 for m in mods):
            return c
    return None


def install_venv_wrapper(clone, py):
    """<clone>/.venv/bin/python as a tiny sh wrapper that execs `py` (symlinking only an interpreter loses its site-packages)."""
    p = os.path.join(clone, ".venv", "bin", "python")
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w") as f:
        f.write('#!/bin/sh\nexec "%s" "$@"\n' % py)
    os.chmod(p, 0o755)


def skip_or_die(what, tool):
    """Tool genuinely absent: an explicit SKIP (exit stays 0) unless OVN_REQUIRE_TOOLS is set, which turns the absence into a failure."""
    if os.environ.get("OVN_REQUIRE_TOOLS"):
        ok("%s: %s is required (OVN_REQUIRE_TOOLS set) but absent" % (what, tool), False)
    else:
        print("  SKIP %s (%s not available here; set OVN_REQUIRE_TOOLS=1 to make this a failure)" % (what, tool))


GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t"]

FILES = {
    "iptv-backend/app/routers/limited.py": "from app.core.limiter import limiter\n@router.get('/a')\n@limiter.limit('5/minute')\ndef a(request):\n    return 1\n",
    "iptv-backend/app/routers/open_router.py": "@router.get('/x')\ndef x():\n    return 1\n@router.post('/y')\nasync def y(body):\n    return 2\n",
    "iptv-backend/app/routers/big_router.py": "".join("@router.get('/r%d')\ndef r%d():\n    return 1\n" % (i, i) for i in range(6)),
    "iptv-backend/app/services/swallow.py": "def f():\n    try:\n        g()\n    except Exception:\n        pass\n",
    "iptv-backend/app/services/annot.py": "def a():\n    x = 1\ndef b() -> None:\n    pass\ndef c():\n    return 5\ndef d():\n    yield 1\nasync def e():\n    await z()\n",
    "scripts/battle/thing.gd": "func do_it(a, b):\n\tprint(a)\nfunc get_it():\n\treturn 3\nfunc _private():\n\tpass\nfunc noop() -> void:\n\tpass\n",
}


def make_fixture():
    d = tempfile.mkdtemp(prefix="ws-")
    origin = os.path.join(d, "origin.git")
    sh("git", "init", "-q", "--bare", origin)
    clone = os.path.join(d, "repos", "demo")
    os.makedirs(os.path.dirname(clone))
    sh("git", "clone", "-q", origin, clone)
    for rp, body in FILES.items():
        fp = os.path.join(clone, rp)
        os.makedirs(os.path.dirname(fp), exist_ok=True)
        open(fp, "w").write(body)
    open(os.path.join(clone, "OVERNIGHT_PROGRESS.md"), "w").write("# progress\n")
    sh(*GIT, "checkout", "-q", "-b", "overnight/feature", cwd=clone)
    sh("git", "add", "-A", cwd=clone)
    sh(*GIT, "commit", "-q", "-m", "init", cwd=clone)
    sh("git", "push", "-q", "origin", "overnight/feature", cwd=clone)
    os.makedirs(os.path.join(d, "backlog"))
    os.makedirs(os.path.join(d, "state"))
    os.makedirs(os.path.join(d, "scripts"))
    shutil.copy(os.path.join(ROOT, "scripts", "lib_verify_clause.sh"), os.path.join(d, "scripts"))
    shutil.copy(os.path.join(ROOT, "scripts", "ovn_spec_check.sh"), os.path.join(d, "scripts"))
    for helper in ("lib_gut_xml.sh",):
        if os.path.exists(os.path.join(ROOT, "scripts", helper)):
            shutil.copy(os.path.join(ROOT, "scripts", helper), os.path.join(d, "scripts"))
    open(os.path.join(d, "backlog", "demo.md"), "w").write("# backlog\n")
    return d, clone


def specs_by_kind(clone):
    out = {}
    for s in W.collect_all(clone):
        out.setdefault(s["kind"], []).append(s)
    return out


def run_verify(clone, cmd):
    return subprocess.run(["bash", "-c", cmd], cwd=clone, capture_output=True, text=True).returncode


d, clone = make_fixture()
sp = specs_by_kind(clone)

# --- collectors pick exactly the right targets
ok("swallowed: finds the bare-pass handler", [s["file"] for s in sp.get("swallowed-exception", [])] == ["iptv-backend/app/services/swallow.py"], sp.keys())
ok("rate-limit: only the unlimited router with <=4 routes (not limited.py, not the 6-route router)",
   [s["file"] for s in sp.get("no-rate-limit", [])] == ["iptv-backend/app/routers/open_router.py"], [s["file"] for s in sp.get("no-rate-limit", [])])
rn = [s for s in sp.get("missing-return-none", []) if s["file"].endswith("annot.py")]
ok("returns-none: lists only value-less, unannotated, non-generator functions (a), (e) - not b (annotated), c (returns), d (yields)",
   len(rn) == 1 and "`a`" in rn[0]["text"] and "`e`" in rn[0]["text"] and "`b`" not in rn[0]["text"] and "`c`" not in rn[0]["text"] and "`d`" not in rn[0]["text"], rn[0]["text"] if rn else rn)
gd = sp.get("gd-missing-void", [])
ok("gd-void: do_it only (get_it returns a value, _private is private, noop already typed)",
   len(gd) == 1 and "`do_it`" in gd[0]["text"] and "get_it" not in gd[0]["text"] and "_private" not in gd[0]["text"] and "noop" not in gd[0]["text"], gd)

# --- every VERIFY is RED before the change and GREEN after it (the property the whole design rests on)
for s in W.collect_all(clone):
    ok("VERIFY is red before: %s %s" % (s["kind"], os.path.basename(s["file"])), run_verify(clone, s["verify"]) == 1)
fixed = {
    "iptv-backend/app/services/swallow.py": "import logging\nlogger = logging.getLogger(__name__)\ndef f():\n    try:\n        g()\n    except Exception:\n        logger.exception('x')\n",
    "iptv-backend/app/routers/open_router.py": "from app.core.limiter import limiter\n@router.get('/x')\n@limiter.limit('30/minute')\ndef x(request: Request):\n    return 1\n@router.post('/y')\n@limiter.limit('30/minute')\nasync def y(request: Request, body):\n    return 2\n",
    "iptv-backend/app/services/annot.py": "def a() -> None:\n    x = 1\ndef b() -> None:\n    pass\ndef c():\n    return 5\ndef d():\n    yield 1\nasync def e() -> None:\n    await z()\n",
    "scripts/battle/thing.gd": "func do_it(a, b) -> void:\n\tprint(a)\nfunc get_it():\n\treturn 3\nfunc _private():\n\tpass\nfunc noop() -> void:\n\tpass\n",
}
verifies = {(s["kind"], s["file"]): s["verify"] for s in W.collect_all(clone)}
VK = {"iptv-backend/app/services/swallow.py": "swallowed-exception", "iptv-backend/app/routers/open_router.py": "no-rate-limit",
      "iptv-backend/app/services/annot.py": "missing-return-none", "scripts/battle/thing.gd": "gd-missing-void"}
for rp, body in fixed.items():
    open(os.path.join(clone, rp), "w").write(body)
for rp in fixed:
    ok("VERIFY is green after the fix: %s" % os.path.basename(rp), run_verify(clone, verifies[(VK[rp], rp)]) == 0)
# a half-done fix must NOT satisfy it
open(os.path.join(clone, "iptv-backend/app/routers/open_router.py"), "w").write(
    "from app.core.limiter import limiter\n@router.get('/x')\n@limiter.limit('30/minute')\ndef x(request):\n    return 1\n@router.post('/y')\nasync def y(body):\n    return 2\n")
ok("NEGATIVE: rate-limit VERIFY stays red when only one of two routes is fixed", run_verify(clone, verifies[("no-rate-limit", "iptv-backend/app/routers/open_router.py")]) == 1)
open(os.path.join(clone, "iptv-backend/app/routers/open_router.py"), "w").write("@router.get('/x')\n@limiter.limit('30/minute')\ndef x():\n    return 1\n")
ok("NEGATIVE: rate-limit VERIFY stays red when the decorator is present but the `request` param is missing",
   run_verify(clone, verifies[("no-rate-limit", "iptv-backend/app/routers/open_router.py")]) == 1)
# wrong decorator order and a body model named `request` must both stay RED even though a limiter decorator and an arg called request exist
open(os.path.join(clone, "iptv-backend/app/routers/open_router.py"), "w").write(
    "from app.core.limiter import limiter\n@limiter.limit('30/minute')\n@router.get('/x')\ndef x(request: Request):\n    return 1\n@router.post('/y')\n@limiter.limit('30/minute')\nasync def y(request: BodyModel):\n    return 2\n")
ok("NEGATIVE: rate-limit VERIFY stays red when the limiter is ABOVE the route decorator (inert) or `request` is a body model",
   run_verify(clone, verifies[("no-rate-limit", "iptv-backend/app/routers/open_router.py")]) == 1)
open(os.path.join(clone, "iptv-backend/app/routers/open_router.py"), "w").write(
    "from app.core.limiter import limiter\n@router.get('/x')\n@limiter.limit('30/minute')\ndef x(request: Request):\n    return 1\n@router.post('/y')\n@limiter.limit('30/minute')\nasync def y(request: Request, body: BodyModel):\n    return 2\n")
ok("rate-limit VERIFY is green for the correct shape (route first, limiter below, request: Request)",
   run_verify(clone, verifies[("no-rate-limit", "iptv-backend/app/routers/open_router.py")]) == 0)
ok("no VERIFY contains '>' (the runner refuses redirect-looking characters)", all(">" not in v for v in verifies.values()), [v for v in verifies.values() if ">" in v])
sh("git", "checkout", "-q", "--", ".", cwd=clone)
for rp in fixed:
    sh("git", "checkout", "-q", "--", rp, cwd=clone)

# --- polish collectors (typing / docstrings / GD docs): right targets, red-before, green-after
d4, clone4 = make_fixture()
os.makedirs(os.path.join(clone4, "iptv-backend/app/services"), exist_ok=True)
open(os.path.join(clone4, "iptv-backend/app/services/polish.py"), "w").write(
    "def typed_ret(x) -> int:\n    return 1\n"
    "def untyped_ret(x):\n    y = 1\n    z = 2\n    return y + z\n"
    "def _private_untyped():\n    return 5\n"
    "def documented():\n    \"\"\"ok\"\"\"\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    return a\n"
    "def undocumented_long(a):\n    b = a\n    c = b\n    d = c\n    e = d\n    f = e\n    return f\n"
    "def undocumented_short():\n    return 1\n"
    "class Public:\n    x = 1\n    y = 2\n    z = 3\n    w = 4\n    v = 5\n"
    "@router.get('/r')\ndef route_handler():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    return a\n")
open(os.path.join(clone4, "scripts/battle/gdoc.gd"), "w").write(
    "## already documented\nfunc has_doc():\n\tvar a = 1\n\tvar b = 2\n\tvar c = 3\n\tvar d = 4\n\treturn a\n"
    "func no_doc(x):\n\tvar a = 1\n\tvar b = 2\n\tvar c = 3\n\tvar d = 4\n\treturn a\n"
    "func _private_no_doc():\n\tvar a = 1\n\tvar b = 2\n\tvar c = 3\n\tvar d = 4\n\treturn a\n"
    "func tiny():\n\treturn 1\n")
sp4 = {}
os.environ["OVN_SUPPLY_GD_DOCS"] = "on"   # the gd-doc family is OFF by default (v2); this block exercises it explicitly
for s_ in W.collect_all(clone4):
    sp4.setdefault((s_["kind"], os.path.basename(s_["file"])), s_)
os.environ.pop("OVN_SUPPLY_GD_DOCS", None)
rt = sp4.get(("missing-return-type", "polish.py"))
ok("return-type: lists only value-returning unannotated public funcs (untyped_ret) - not typed_ret, not _private",
   rt and "`untyped_ret`" in rt["text"] and "`typed_ret`" not in rt["text"] and "_private" not in rt["text"], rt and rt["text"])
dc = sp4.get(("missing-docstring", "polish.py"))
ok("docstring: names the long undocumented func and the public class; not the documented, short, private or route-handler ones",
   dc and "`undocumented_long`" in dc["text"] and "`Public`" in dc["text"] and "`documented`" not in dc["text"] and "undocumented_short" not in dc["text"] and "route_handler" not in dc["text"], dc and dc["text"])
gdc = sp4.get(("gd-missing-doc", "gdoc.gd"))
ok("gd-doc: only the public function without a ## comment (no_doc)", gdc and "`no_doc`" in gdc["text"] and "has_doc" not in gdc["text"] and "_private" not in gdc["text"] and "tiny" not in gdc["text"], gdc and gdc["text"])
for k, s_ in (("return-type", rt), ("docstring", dc), ("gd-doc", gdc)):
    ok("%s VERIFY is red before" % k, s_ and run_verify(clone4, s_["verify"]) == 1)
open(os.path.join(clone4, "iptv-backend/app/services/polish.py"), "w").write(
    "def typed_ret(x) -> int:\n    return 1\n"
    "def untyped_ret(x) -> int:\n    y = 1\n    z = 2\n    return y + z\n"
    "def undocumented_long(a) -> int:\n    \"\"\"Walks a through five assignments.\"\"\"\n    b = a\n    c = b\n    d = c\n    e = d\n    f = e\n    return f\n"
    "class Public:\n    \"\"\"A public holder.\"\"\"\n    x = 1\n    y = 2\n    z = 3\n    w = 4\n    v = 5\n")
open(os.path.join(clone4, "scripts/battle/gdoc.gd"), "w").write("## already documented\nfunc has_doc():\n\tpass\n## Does the thing.\nfunc no_doc(x):\n\tpass\n")
ok("return-type VERIFY green after annotating", run_verify(clone4, rt["verify"]) == 0)
ok("docstring VERIFY green after documenting", run_verify(clone4, dc["verify"]) == 0)
ok("gd-doc VERIFY green after the ## comment", run_verify(clone4, gdc["verify"]) == 0)
open(os.path.join(clone4, "scripts/battle/gdoc.gd"), "w").write("## already documented\nfunc has_doc():\n\tpass\n\n## detached comment, blank line below\n\nfunc no_doc(x):\n\tpass\n")
ok("NEGATIVE: a ## comment separated from the function by a blank line does not satisfy the gd-doc VERIFY", run_verify(clone4, gdc["verify"]) == 1)
open(os.path.join(clone4, "iptv-backend/app/services/polish.py"), "w").write("def undocumented_long(a):\n    \"\"\" \"\"\"\n    b = a\n    return b\nclass Public:\n    \"\"\"\"\"\"\n    x = 1\n")
ok("NEGATIVE: an empty/whitespace docstring does not satisfy the docstring VERIFY", run_verify(clone4, dc["verify"]) == 1)
ok("no polish VERIFY contains '>'", all(">" not in x["verify"] for x in sp4.values()))

# --- pure-function tests + unused imports
import ast as _ast
_pure = lambda src: W._is_pure_function(_ast.parse(src).body[0], None)
ok("pure: a small arithmetic/string helper is pure", _pure("def f(a, b):\n    x = a + b\n    y = x * 2\n    return y\n"))
ok("NEGATIVE pure: takes db / self / request args", not _pure("def f(db, a):\n    x = a\n    y = x\n    return y\n") and not _pure("def f(self, a):\n    x = a\n    y = x\n    return y\n"))
ok("NEGATIVE pure: reads the clock / random / env / files", not _pure("def f(a):\n    t = datetime.now()\n    y = a\n    return y\n") and not _pure("def f(a):\n    x = random.random()\n    y = a\n    return y\n")
   and not _pure("def f(a):\n    x = os.environ.get('x')\n    y = a\n    return y\n") and not _pure("def f(a):\n    x = open(a)\n    y = 1\n    return y\n"))
ok("NEGATIVE pure: async, decorated, private, no return value, too short, try/except", not _pure("async def f(a):\n    x = a\n    y = x\n    return y\n") and not _pure("@dec\ndef f(a):\n    x = a\n    y = x\n    return y\n")
   and not _pure("def _f(a):\n    x = a\n    y = x\n    return y\n") and not _pure("def f(a):\n    x = a\n    y = x\n    print(y)\n") and not _pure("def f(a):\n    return a\n")
   and not _pure("def f(a):\n    try:\n        x = int(a)\n    except ValueError:\n        x = 0\n    return x\n"))
d5, clone5 = make_fixture()
os.makedirs(os.path.join(clone5, "iptv-backend/tests"), exist_ok=True)
os.makedirs(os.path.join(clone5, "iptv-backend/app/services"), exist_ok=True)
open(os.path.join(clone5, "iptv-backend/app/services/mathy.py"), "w").write(
    "def clamp(value, low, high):\n    if value < low:\n        return low\n    if value > high:\n        return high\n    return value\n"
    "def already_tested(a, b):\n    c = a + b\n    d = c * 2\n    return d\n"
    "def impure(a):\n    t = datetime.now()\n    y = a\n    return y\n")
open(os.path.join(clone5, "iptv-backend/tests/test_other.py"), "w").write("from app.services.mathy import already_tested\n\ndef test_x():\n    assert already_tested(1, 2) == 6\n")
pt = [s_ for s_ in W.collect_all(clone5) if s_["kind"] == "pure-function-tests"]
ok("pure-tests: exactly one item, for mathy.py, naming clamp only (already_tested is mentioned by a test, impure is impure)",
   len(pt) == 1 and "`clamp`" in pt[0]["text"] and "already_tested`" not in pt[0]["text"] and "`impure`" not in pt[0]["text"] and pt[0]["file"] == "iptv-backend/tests/test_mathy_pure.py", pt and pt[0]["text"])
ast_cmd = pt[0]["verify"].split(" && cd ")[0]
ok("pure-tests VERIFY is red before (test file missing)", run_verify(clone5, ast_cmd) == 1)
open(os.path.join(clone5, "iptv-backend/tests/test_mathy_pure.py"), "w").write("from app.services.mathy import clamp\n\ndef test_low():\n    assert clamp(-1, 0, 5) == 0\n\ndef test_high():\n    assert clamp(9, 0, 5) == 5\n")
ok("pure-tests VERIFY (assertion part) is green with real compare-asserts calling the function", run_verify(clone5, ast_cmd) == 0)
open(os.path.join(clone5, "iptv-backend/tests/test_mathy_pure.py"), "w").write("from app.services.mathy import clamp\n\ndef test_low():\n    assert True\n\ndef test_called_but_not_compared():\n    clamp(1, 0, 5)\n    assert 1\n")
ok("NEGATIVE: a tautological assert / a call with no comparison does not satisfy the VERIFY", run_verify(clone5, ast_cmd) == 1)
open(os.path.join(clone5, "iptv-backend/tests/test_mathy_pure.py"), "w").write("from app.services.mathy import clamp\n\ndef test_other():\n    assert 1 + 1 == 2\n")
ok("NEGATIVE: an assert comparing something unrelated (never calls the function) does not satisfy the VERIFY", run_verify(clone5, ast_cmd) == 1)
ok("EVERY supplied line is ONE physical line (no newline inside any text or VERIFY)", all("\n" not in W.render(x, "demo") for x in W.collect_all(clone5)))
ok("pure-tests VERIFY carries a pytest tail and no '>'", "pytest tests/test_mathy_pure.py -q" in pt[0]["verify"] and ">" not in pt[0]["verify"])
_RUFF_PY = find_tools_py(("ruff",))
_has_ruff = _RUFF_PY is not None
if _has_ruff:
    install_venv_wrapper(clone5, _RUFF_PY)   # collectors look for <root>/.venv/bin/python (or iptv-backend/.venv); the wrapper execs a python that has ruff
    open(os.path.join(clone5, "iptv-backend/app/services/imp.py"), "w").write("import os\nimport json\nfrom typing import List\n\ndef f():\n    return json.dumps({})\n")
    ui = [s_ for s_ in W.collect_all(clone5) if s_["kind"] == "unused-import" and s_["file"].endswith("imp.py")]
    ok("unused-import: names exactly the unused names (os, List), not json", ui and "`os`" in ui[0]["text"] and "`typing.List`" in ui[0]["text"] and "json" not in ui[0]["text"], ui and ui[0]["text"])
    ok("unused-import VERIFY red before", ui and run_verify(clone5, ui[0]["verify"].replace("python3 ", _RUFF_PY + " ", 1)) != 0)
    open(os.path.join(clone5, "iptv-backend/app/services/imp.py"), "w").write("import json\n\ndef f():\n    return json.dumps({})\n")
    ok("unused-import VERIFY green after removal", ui and run_verify(clone5, ui[0]["verify"].replace("python3 ", _RUFF_PY + " ", 1)) == 0)
else:
    skip_or_die("unused-import tests", "ruff")

# --- spec check: red / passes-before / no-verify / bad-spec
spec = os.path.join(d, "cand.md")
lines = [
    "- [ ] [T2] a — red spec VERIFY: `python3 -c \"import sys;sys.exit(1)\"`. (cat:python)",
    "- [ ] [T2] b — already satisfied VERIFY: `python3 -c \"import sys;sys.exit(0)\"`. (cat:python)",
    "- [ ] [T2] c — no clause at all (cat:python)",
    "- [ ] [T2] d — crashes VERIFY: `python3 -c \"open('does/not/exist.py').read()\"`. (cat:python)",
    "- [ ] [T2] e — unrunnable VERIFY: `definitely_not_a_command_xyz --flag`. (cat:python)",
    "- [ ] [T2] f — denylisted VERIFY: `rm -rf /tmp/zzz`. (cat:python)",
    "  indented non-item line is skipped",
    "- [x] [T2] g — done items are skipped VERIFY: `true`. (cat:python)",
]
open(spec, "w").write("\n".join(lines) + "\n")
env = dict(os.environ, OVN_DIR=d)
r = sh("bash", os.path.join(d, "scripts", "ovn_spec_check.sh"), "demo", spec, env=env)
rows = {int(a.split("\t")[0]): a.split("\t")[1] for a in r.stdout.strip().split("\n") if a}
ok("spec-check: failing assertion -> red", rows.get(1) == "red", r.stdout + r.stderr)
ok("spec-check: already-passing VERIFY -> passes-before", rows.get(2) == "passes-before", rows)
ok("spec-check: missing clause -> no-verify", rows.get(3) == "no-verify", rows)
ok("spec-check: VERIFY that CRASHES (missing file) is bad-spec, not red", rows.get(4) == "bad-spec", rows)
ok("spec-check: unrunnable command -> bad-spec", rows.get(5) == "bad-spec", rows)
ok("spec-check: denylisted command -> bad-spec", rows.get(6) == "bad-spec", rows)
ok("spec-check: non-open lines are skipped", 7 not in rows and 8 not in rows, rows)
wts = sh("git", "worktree", "list", cwd=clone).stdout.strip().split("\n")
ok("spec-check: leaves no worktree behind and does not touch the live clone", len(wts) == 1 and sh("git", "status", "--porcelain", cwd=clone).stdout.strip() == "", wts)

# --- end to end: supply -> spec check -> backlog
d2, clone2 = make_fixture()
env = dict(os.environ, OVN_DIR=d2)
r = sh(sys.executable, SUPPLY, "demo", "--dry-run", env=env)
ok("dry-run reports red-before specs and writes nothing", "DRY-RUN" in r.stdout and open(os.path.join(d2, "backlog", "demo.md")).read() == "# backlog\n", r.stdout + r.stderr)
r = sh(sys.executable, SUPPLY, "demo", env=env)
bl = open(os.path.join(d2, "backlog", "demo.md")).read()
_nfiles = len({s_["file"] for s_ in W.collect_all(clone2)})
ok("supply appends exactly one item per gap-bearing file (one-per-file rule)", ("ADDED %d" % _nfiles) in r.stdout and bl.count("supply:") == _nfiles >= 4, r.stdout + r.stderr)
ok("every appended line has an executable VERIFY clause and a [feat:] tag", all("VERIFY: `python3 -c" in l and "[feat:demo-" in l for l in bl.split("\n") if l.startswith("- [ ]")))
passes = 0
while passes < 8:
    r = sh(sys.executable, SUPPLY, "demo", "--force", env=env)
    passes += 1
    if ", 0 specs" in r.stdout:
        break
bl2 = open(os.path.join(d2, "backlog", "demo.md")).read()
keys = [(m.group(1), m.group(2)) for m in (re.search(r"supply:([\w-]+)\) \[feat:demo-\d+-supply-([\w-]+)\]", l) for l in bl2.split("\n") if l.startswith("- [ ]")) if m]
# v2: the gaps are still in the checkout, so the log says 'N gaps found, M filtered (...), 0 specs' - never 'no new gaps' while N > 0
ok("repeated passes converge ('N gaps found, M filtered ..., 0 specs') - one item per file per pass, deferred kinds follow later", ", 0 specs" in r.stdout and "gaps found" in r.stdout and passes < 8, r.stdout)
ok("NEGATIVE: the converged log does not claim 'no new mechanical gaps' while gaps exist", "no new mechanical gaps" not in r.stdout, r.stdout)
ok("no (kind, file) pair is ever supplied twice", len(keys) == len(set(keys)) and len(keys) >= _nfiles, keys)
# already-satisfied gap is dropped, not queued
d3, clone3 = make_fixture()
open(os.path.join(clone3, "iptv-backend/app/services/swallow.py"), "w").write("def f():\n    pass\n")  # no handler: nothing to supply
r = sh(sys.executable, SUPPLY, "demo", env=dict(os.environ, OVN_DIR=d3))
ok("a file with no gap yields no swallowed-exception item", "swallowed-exception" not in open(os.path.join(d3, "backlog", "demo.md")).read())
# enough backlog -> no supply
open(os.path.join(d3, "backlog", "demo.md"), "w").write("\n".join("- [ ] [T2] x%d — y" % i for i in range(25)) + "\n")
r = sh(sys.executable, SUPPLY, "demo", env=dict(os.environ, OVN_DIR=d3))
ok("no supply when the backlog is already deep", "no supply needed" in r.stdout, r.stdout)
# the 2026-10-08 miss: backlog T-lines that are duplicates of queued items / parked do NOT count as supply
open(os.path.join(d3, "backlog", "demo.md"), "w").write("\n".join("- [ ] [T2] dup%d — y" % i for i in range(25)) + "\n- [ ] [AUTO-SKIP x] [T2] parked — y\n")
open(os.path.join(clone3, "OVERNIGHT_PROGRESS.md"), "w").write("\n".join("- [ ] [T2] dup%d — y" % i for i in range(25)) + "\n")
_n = W.pullable_count(open(os.path.join(d3, "backlog", "demo.md")).read(), open(os.path.join(clone3, "OVERNIGHT_PROGRESS.md")).read())
ok("pullable_count: backlog lines already queued are not counted twice, parked ones not at all (25 queued + 0 new)", _n == 25, _n)
ok("pullable_count: only held lines in the progress file = 0 doable", W.pullable_count("", "- [ ] [AUTO-SKIP x] [T2] a\n- [ ] [CLAUDE] [T2] b\n- [x] [T2] c\n") == 0)
r = sh(sys.executable, SUPPLY, "demo", env=dict(os.environ, OVN_DIR=d3, OVN_WORK_SUPPLY="off"))
ok("kill switch OVN_WORK_SUPPLY=off", "OVN_WORK_SUPPLY=off" in r.stdout)


# =====================================================================================================================================
# v2 families (2026-10-09): ruff bug-class (B1), xlite mission spawns (B2), external collector hook (B3), gd-docs default off.
# Every VERIFY: red before, green after the right fix, STILL RED after a wrong fix. Collector rules are mutation-checked below.
# =====================================================================================================================================
import importlib.util as _ilu


def _load_variant(old, new, tag):
    src = open(SUPPLY, encoding="utf-8").read()
    if src.count(old) != 1:
        ok("mutation anchor exists exactly once: %r" % old[:60], False, src.count(old))
        return None
    dd = os.path.realpath(tempfile.mkdtemp(prefix="supplymut-"))
    with open(os.path.join(dd, "ovn_work_supply.py"), "w", encoding="utf-8") as f:
        f.write(src.replace(old, new))
    shutil.copy(os.path.join(ROOT, "scripts", "ovn_mission_lint.py"), dd)
    sp = _ilu.spec_from_file_location("ovn_work_supply_mut_" + tag, os.path.join(dd, "ovn_work_supply.py"))
    m = _ilu.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def mut_caught(label, chk, old, new):
    """`chk(module)` is True for the real module and False (or raises) for the module with `old` replaced by `new`."""
    ok("%s (real module)" % label, bool(chk(W)))
    m = _load_variant(old, new, re.sub(r"\W", "", label)[:20])
    if m is not None:
        try:
            r = bool(chk(m))
        except Exception:
            r = False
        ok("MUTATION caught: %s" % label, not r)


def mkroot(files):
    r = os.path.realpath(tempfile.mkdtemp(prefix="b-root-"))
    for rp, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(r, rp)), exist_ok=True)
        with open(os.path.join(r, rp), "w") as f:
            f.write(body)
    return r


def vrun(root, cmd, py=None):
    if py:
        cmd = cmd.replace("python3 -m ruff", "%s -m ruff" % py, 1)
    return subprocess.run(["bash", "-c", cmd], cwd=root, capture_output=True, text=True).returncode


RUFF_CASES = [
    ("F601", "iptv-backend/app/services/dupkey.py",
     "STATES = {\n    'PUERTORICAN': 1,\n    'TEXAS': 2,\n    'PUERTORICAN': 3,\n}\n",
     "STATES = {\n    'PUERTORICAN': 3,\n    'TEXAS': 2,\n}\n",
     "STATES = {\n    'PUERTORICAN': 9,\n    'TEXAS': 2,\n    'PUERTORICAN': 8,\n}\n"),
    ("F811", "iptv-backend/app/services/redef.py",
     "def helper():\n    return 1\n\n\ndef helper():\n    return 2\n",
     "def helper():\n    return 2\n",
     "def helper():\n    return 7\n\n\ndef helper():\n    return 2\n"),
    ("F841", "iptv-backend/app/services/unusedvar.py",
     "def f():\n    x = compute()\n    return 1\n", "def f():\n    compute()\n    return 1\n", "def f():\n    x = other()\n    return 1\n"),
    ("B904", "iptv-backend/app/services/chain.py",
     "def f():\n    try:\n        g()\n    except ValueError:\n        raise RuntimeError('x')\n",
     "def f():\n    try:\n        g()\n    except ValueError as err:\n        raise RuntimeError('x') from err\n",
     "def f():\n    try:\n        g()\n    except ValueError as err:\n        raise RuntimeError('x')\n"),
    ("RUF013", "iptv-backend/app/services/optional.py",
     "def g(a: int = None):\n    return a\n",
     "from typing import Optional\n\n\ndef g(a: Optional[int] = None):\n    return a\n",
     "def g(a: int = None, b: int = 1):\n    return a\n"),
]
NOISE_FILES = {
    "iptv-backend/app/routers/deps.py": "def r(db=Depends(get_db)):\n    return db\n",                      # B008 (FastAPI Depends): never an item
    "iptv-backend/app/services/eq.py": "def f(x):\n    return x == True\n",                               # E712 (SQLAlchemy idiom): never an item
    "iptv-backend/app/services/many.py": "D = {\n" + "".join("    'k%d': 1,\n    'k%d': 2,\n" % (i, i) for i in range(5)) + "}\n",   # 5 findings > 4: skipped
    "iptv-backend/app/alembic/versions/m1.py": "D = {'a': 1, 'a': 2}\n",                                    # migrations are never touched
    "iptv-backend/app/tests/test_dup.py": "D = {'a': 1, 'a': 2}\n",                                        # neither are tests
    "iptv-backend/app/services/two_rules.py": "D = {'a': 1, 'a': 2}\n\n\ndef h():\n    return 1\n\n\ndef h():\n    return 2\n",   # F601 + F811 in ONE file
}

TOOLS_PY = find_tools_py(("ruff",))
if TOOLS_PY is None:
    skip_or_die("ruff bug-class family tests (B1)", "ruff")
else:
    os.environ.pop("OVN_SUPPLY_RUFF_RULES", None)
    root = mkroot(dict({c[1]: c[2] for c in RUFF_CASES}, **NOISE_FILES))
    install_venv_wrapper(root, TOOLS_PY)
    default = list(W.c_ruff_bugclass(root))
    ok("B1 default allowlist is F601,F811 only", {s["kind"] for s in default} == {"ruff-F601", "ruff-F811"}, sorted({s["kind"] for s in default}))
    os.environ["OVN_SUPPLY_RUFF_RULES"] = "F601,F811,F841,B904,RUF013,B008,E712,S314"
    allk = list(W.c_ruff_bugclass(root))
    by = {(s["kind"], s["file"]): s for s in allk}
    ok("B1 widened allowlist yields the five kinds, B008/E712/S314 never", {s["kind"] for s in allk} == {"ruff-" + c[0] for c in RUFF_CASES}, sorted({s["kind"] for s in allk}))
    ok("B1 NEGATIVE: B008 (Depends) and E712 (== True) files produce nothing even when named in the allowlist",
       not any(s["file"].endswith(("deps.py", "eq.py")) for s in allk))
    ok("B1 more than 4 findings in a file => skipped; alembic/migrations and tests skipped",
       not any(s["file"].endswith(("many.py", "m1.py", "test_dup.py")) for s in allk))
    tw = sorted(s["kind"] for s in allk if s["file"].endswith("two_rules.py"))
    ok("B1 a file with two rules yields one spec per rule from the collector (two_rules.py)", tw == ["ruff-F601", "ruff-F811"], tw)
    # main(): one item per file per pass (the same rule the old collectors rely on)
    import contextlib as _cl
    import io as _io
    od = mkroot({})
    os.makedirs(os.path.join(od, "repos"))
    shutil.move(root, os.path.join(od, "repos", "demo"))
    os.makedirs(os.path.join(od, "backlog"))
    os.makedirs(os.path.join(od, "state"))
    open(os.path.join(od, "backlog", "demo.md"), "w").write("# backlog\n")
    W.OVN_DIR = od
    W.spec_check = lambda repo, lines: {i: "red" for i in range(len(lines))}
    buf = _io.StringIO()
    with _cl.redirect_stdout(buf):
        W.main(["x", "demo", "--force", "--max", "50"])
    bl_txt = open(os.path.join(od, "backlog", "demo.md")).read()
    tw_lines = [l for l in bl_txt.split("\n") if "two_rules.py" in l and l.startswith("- [ ]")]
    ok("B1 one item per file per pass: exactly one backlog line for two_rules.py", len(tw_lines) == 1, tw_lines)
    root = os.path.join(od, "repos", "demo")
    os.environ["OVN_SUPPLY_RUFF_RULES"] = "F601,F811,F841,B904,RUF013"
    for rule, path, bad, good, wrong in RUFF_CASES:
        s = by[("ruff-" + rule, path)]
        ok("B1 %s: item shape (tier T2, one physical line, VERIFY has no '>' / backtick, names the rule)" % rule,
           s["tier"] == "T2" and "\n" not in W.render(s, "demo") and ">" not in s["verify"] and "`" not in s["verify"] and rule in s["verify"] and ("ruff %s" % rule) in s["text"], s["text"][:150])
        ok("B1 %s: VERIFY is red before" % rule, vrun(root, s["verify"], TOOLS_PY) != 0)
        full = os.path.join(root, path)
        open(full, "w").write(wrong)
        ok("B1 %s: MUTATION - a wrong fix keeps the VERIFY red" % rule, vrun(root, s["verify"], TOOLS_PY) != 0)
        open(full, "w").write(good)
        ok("B1 %s: VERIFY is green after the right fix" % rule, vrun(root, s["verify"], TOOLS_PY) == 0)
        open(full, "w").write(bad)
    f601 = by[("ruff-F601", "iptv-backend/app/services/dupkey.py")]
    ok("B1 F601 text names the repeated key (PUERTORICAN)", "PUERTORICAN" in f601["text"], f601["text"][:200])
    # F811 on registered route handlers is not dead code (review defect): never an item, the undecorated redefinition next to it still is
    R_DIFF = ("from fastapi import APIRouter\n\nrouter = APIRouter()\n\n\n@router.get('/a')\ndef h():\n    return 'a'\n\n\n@router.get('/b')\ndef h():\n    return 'b'\n")
    R_SAME = ("from fastapi import APIRouter\n\nrouter = APIRouter()\n\n\n@router.get('')\ndef get_vod_catalog():\n    return 1\n\n\n@router.get('')\ndef get_vod_catalog():\n    return 2\n")
    R_ASYNC = ("app = object()\n\n\n@app.post('/x')\nasync def create():\n    return 1\n\n\n@app.post('/y')\nasync def create():\n    return 2\n")
    R_MIXED = R_DIFF + "\n\ndef plain():\n    return 1\n\n\ndef plain():\n    return 2\n"
    froot = mkroot({"iptv-backend/app/routers/diff.py": R_DIFF, "iptv-backend/app/routers/same.py": R_SAME, "iptv-backend/app/routers/asyncs.py": R_ASYNC,
                    "iptv-backend/app/routers/mixed.py": R_MIXED, "iptv-backend/app/services/redef.py": RUFF_CASES[1][2]})
    install_venv_wrapper(froot, TOOLS_PY)
    os.environ["OVN_SUPPLY_RUFF_RULES"] = "F811"
    def _f811(M):
        return {s["file"]: s for s in M.c_ruff_bugclass(froot)}
    fm = _f811(W)
    ok("B1 F811 sanity: ruff really flags the decorated handlers (so the guard, not ruff, is what hides them)",
       all(vrun(froot, "python3 -m ruff check --select F811 --isolated --no-cache iptv-backend/app/routers/%s" % n, TOOLS_PY) != 0 for n in ("diff.py", "same.py", "asyncs.py")))
    ok("B1 F811 NEGATIVE: two @router.get / @app.post handlers with the same name (different paths, or the real vod.py shape with the same path) are never an item",
       not any(k.endswith(("routers/diff.py", "routers/same.py", "routers/asyncs.py")) for k in fm), sorted(fm))
    ok("B1 F811: an undecorated redefinition still yields an item", "iptv-backend/app/services/redef.py" in fm, sorted(fm))
    ok("B1 F811: in a file with both, only the undecorated name is reported (no mention of the handler h)",
       "iptv-backend/app/routers/mixed.py" in fm and "`plain`" in fm["iptv-backend/app/routers/mixed.py"]["text"] and "`h`" not in fm["iptv-backend/app/routers/mixed.py"]["text"],
       fm.get("iptv-backend/app/routers/mixed.py", {}).get("text", "")[:200])
    mut_caught("B1 F811 never proposes deleting a registered route handler", lambda M: not any(k.endswith(("routers/diff.py", "routers/same.py", "routers/asyncs.py")) for k in _f811(M))
               and "`h`" not in _f811(M).get("iptv-backend/app/routers/mixed.py", {"text": ""})["text"],
               '            if fs and rule == "F811":', '            if False:')
    # round-3 review: the two guards below were unpinned (mutants survived). (a) a file this python cannot parse (ruff may know newer syntax) is skipped, never supplied;
    # (b) every branch of the route-decorator heuristic (known root / *router name / registering attribute) independently hides a same-name handler.
    def _two(deco_a, deco_b, name="h"):
        return "r = object()\n\n\n%s\ndef %s():\n    return 'a'\n\n\n%s\ndef %s():\n    return 'b'\n" % (deco_a, name, deco_b, name)
    D_ROOT = _two("@bp.frob('/a')", "@bp.frob('/b')")                  # only the known-root branch (bp is a root, frob is no registering attribute)
    D_ENDS = _two("@users_router.frob('/a')", "@users_router.frob('/b')")   # only the endswith('router') branch
    D_ATTR = _two("@r.get('/a')", "@r.get('/b')", "g") + "\n\n" + _two("@celery.task", "@celery.task", "t").split("\n\n\n", 1)[1]   # only the registering-attribute branch (+ a bare attribute decorator)
    D_PLAIN = _two("@functools.lru_cache", "@functools.lru_cache", "cached")   # a decorator that registers nothing: still an ordinary redefinition
    droot = mkroot({"iptv-backend/app/routers/d_root.py": D_ROOT, "iptv-backend/app/routers/d_ends.py": D_ENDS, "iptv-backend/app/routers/d_attr.py": D_ATTR,
                    "iptv-backend/app/services/d_plain.py": D_PLAIN, "iptv-backend/app/services/redef.py": RUFF_CASES[1][2]})
    install_venv_wrapper(droot, TOOLS_PY)
    ok("B1 F811 sanity: ruff flags every decorated fixture (so only the heuristic hides them)",
       all(vrun(droot, "python3 -m ruff check --select F811 --isolated --no-cache iptv-backend/app/%s" % n, TOOLS_PY) != 0
           for n in ("routers/d_root.py", "routers/d_ends.py", "routers/d_attr.py", "services/d_plain.py")))

    def _route_files(M):
        return {s["file"].split("/app/", 1)[1] for s in M.c_ruff_bugclass(droot)}
    ok("B1 F811 route heuristic: the root/endswith/attribute fixtures are hidden, the plain-decorator one and the undecorated one are items",
       _route_files(W) == {"services/d_plain.py", "services/redef.py"}, sorted(_route_files(W)))
    _RD = '    return rid in _ROUTE_ROOTS or rid.endswith("router") or node.attr in _ROUTE_ATTRS'
    for lbl, new in (("known-root branch dropped", '    return rid.endswith("router") or node.attr in _ROUTE_ATTRS'),
                     ("endswith('router') branch dropped", '    return rid in _ROUTE_ROOTS or node.attr in _ROUTE_ATTRS'),
                     ("registering-attribute branch dropped", '    return rid in _ROUTE_ROOTS or rid.endswith("router")'),
                     ("everything is a route decorator", '    return True')):
        mut_caught("B1 F811 route heuristic pinned (%s)" % lbl, lambda M: _route_files(M) == {"services/d_plain.py", "services/redef.py"}, _RD, new)

    def _unparseable(M):
        saved = M._registered_names
        M._registered_names = lambda root, path: None      # what _registered_names returns for a file ast.parse rejects
        try:
            return sorted(s["file"] for s in M.c_ruff_bugclass(froot))
        finally:
            M._registered_names = saved
    badsyn = mkroot({"iptv-backend/app/services/bad.py": "def f(:\n"})
    ok("B1 F811: _registered_names is None for a file that does not parse, a set for one that does",
       W._registered_names(badsyn, "iptv-backend/app/services/bad.py") is None and isinstance(W._registered_names(froot, "iptv-backend/app/routers/diff.py"), set))
    mut_caught("B1 F811 a file this python cannot parse never yields an item (not even an undecorated redefinition)", lambda M: _unparseable(M) == [],
               '                fs = [] if reg is None else [f for f in fs if _finding_name(f) and _finding_name(f) not in reg]',
               '                fs = [f for f in fs if _finding_name(f) not in (reg or set())]')
    os.environ.pop("OVN_SUPPLY_RUFF_RULES", None)
    # ruff absent / unusable => no collector output, no crash
    broken = mkroot({"iptv-backend/app/services/dupkey.py": RUFF_CASES[0][2]})
    os.makedirs(os.path.join(broken, ".venv", "bin"))
    with open(os.path.join(broken, ".venv", "bin", "python"), "w") as f:
        f.write("#!/bin/sh\nexit 3\n")
    os.chmod(os.path.join(broken, ".venv", "bin", "python"), 0o755)
    ok("B1 ruff absent/broken: the collectors yield nothing and do not raise (ruff-bugclass + unused-import)",
       list(W.c_ruff_bugclass(broken)) == [] and list(W.c_unused_imports(broken)) == [])
    broken2 = mkroot({"iptv-backend/app/services/dupkey.py": RUFF_CASES[0][2]})   # a venv python that cannot even be executed (no x bit): subprocess raises PermissionError
    os.makedirs(os.path.join(broken2, ".venv", "bin"))
    with open(os.path.join(broken2, ".venv", "bin", "python"), "w") as f:
        f.write("#!/bin/sh\nexit 0\n")
    os.chmod(os.path.join(broken2, ".venv", "bin", "python"), 0o644)
    ok("B1 a venv python that cannot be executed: nothing, no crash", list(W.c_ruff_bugclass(broken2)) == [] and list(W.c_unused_imports(broken2)) == [])
    nov = mkroot({"iptv-backend/app/services/dupkey.py": RUFF_CASES[0][2]})
    ok("B1 no venv python at all: nothing, no crash", list(W.c_ruff_bugclass(nov)) == [] and isinstance(W.collect_all(nov), list))
    # mutation checks on the collector rules
    os.environ["OVN_SUPPLY_RUFF_RULES"] = "F601,F811,F841,B904,RUF013,B008,E712"
    def _kinds(M):
        return {s["kind"] for s in M.c_ruff_bugclass(root)}
    def _files(M):
        return {s["file"] for s in M.c_ruff_bugclass(root)}
    mut_caught("B1 B008/E712 can never become items (allowlist guard)", lambda M: not ({"ruff-B008", "ruff-E712"} & _kinds(M)) and not any(f.endswith(("deps.py", "eq.py")) for f in _files(M)),
               'if r in _RUFF_KINDS and r not in _RUFF_NEVER and r not in out:', 'if r and r not in out:')
    mut_caught("B1 more than 4 findings per file is skipped", lambda M: not any(f.endswith("many.py") for f in _files(M)), '_RUFF_MAX_FINDINGS = 4', '_RUFF_MAX_FINDINGS = 99')
    mut_caught("B1 alembic/migrations/tests are skipped", lambda M: not any(f.endswith(("m1.py", "test_dup.py")) for f in _files(M)),
               'return is_test_path(path) or "alembic" in parts or "migrations" in parts', 'return False')
    mut_caught("B1 a broken ruff must not raise out of the collector", lambda M: list(M.c_ruff_bugclass(broken2)) == [],
               '    except Exception:\n        return []\n    return out if isinstance(out, list) else []', '    except ValueError:\n        return []\n    return out if isinstance(out, list) else []')
    os.environ.pop("OVN_SUPPLY_RUFF_RULES", None)

# ---------------------------------------------------------------- B2: xlite mission spawns (stdlib only; runs everywhere)
MISSION = """[gd_resource type="Resource" script_class="MissionData" load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/mission/mission_data.gd" id="1"]

[resource]
script = ExtResource("1")
grid_size = Vector2i(%(grid)s)
objective_type = 3
obstacles = Array[Vector2i]([%(obs)s])
obstacle_types = Array[int]([%(otypes)s])
player_spawns = Array[Vector2i]([%(players)s])
enemy_spawns = Array[Vector2i]([%(enemies)s])
enemy_types = Array[int]([%(etypes)s])
extraction_zone = Vector2i(10, 10)
extraction_radius = 1
"""
BASE = dict(grid="13, 13", obs="Vector2i(6, 6), Vector2i(7, 6), Vector2i(6, 7), Vector2i(7, 7), Vector2i(3, 9), Vector2i(9, 3), Vector2i(2, 2), Vector2i(10, 10)",
            otypes="1, 1, 0, 0, 2, 2, 0, 0", players="Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2)", enemies="Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10)", etypes="7, 5, 5")


def mission(**kw):
    d = dict(BASE)
    d.update(kw)
    return MISSION % d


M_CASES = {
    "missions/clean.tres": (mission(), False),
    "missions/enemy_on_wall.tres": (mission(enemies="Vector2i(6, 6), Vector2i(10, 11), Vector2i(7, 6)"), True),         # wall (type 1) + crate (type 0 index 3 is (7,7); (7,6) is type 1)
    "missions/player_on_crate.tres": (mission(players="Vector2i(2, 2), Vector2i(2, 1)"), True),                          # index 6 -> type 0 (CRATE), like mission_46 (2,2)
    "missions/enemy_on_rubble.tres": (mission(enemies="Vector2i(3, 9), Vector2i(9, 3), Vector2i(11, 11)"), False),        # types 2 (RUBBLE) are walkable
    "missions/spawn_out_of_grid.tres": (mission(enemies="Vector2i(20, 3), Vector2i(11, 11)"), True),
    "missions/length_mismatch_only.tres": (mission(otypes="1, 1, 0, 0, 2, 2, 0, 0, 1, 1"), False),                       # parallel array too long: the lint reports it, no spawn item
}
mroot_ = mkroot({k: v[0] for k, v in M_CASES.items()})
mspecs = {s["file"]: s for s in W.c_mission_spawns(mroot_)}
for path, (_, bad) in M_CASES.items():
    ok("B2 collector %s: %s" % (os.path.basename(path), "yields an item" if bad else "yields nothing"), (path in mspecs) == bad, sorted(mspecs))
for path, (txt, bad) in M_CASES.items():
    rc = vrun(mroot_, W.verify_mission_spawns(path))
    ok("B2 inline VERIFY exit code agrees with the lint on %s (%s)" % (os.path.basename(path), "red" if bad else "green"), rc == (1 if bad else 0), rc)
s = mspecs["missions/enemy_on_wall.tres"]
ok("B2 item: kind, tier T2, exact coordinates and the instruction in the text",
   s["kind"] == "mission-spawn-on-obstacle" and s["tier"] == "T2" and "enemy_spawns (6,6)" in s["text"] and "enemy_spawns (7,6)" in s["text"] and "(10,11)" not in s["text"]
   and "move the spawn to the nearest free in-grid cell" in s["text"].lower() and ">" not in s["verify"] and "`" not in s["verify"] and "$" not in s["verify"] and "\n" not in W.render(s, "demo"), s["text"][:300])
mfile = os.path.join(mroot_, "missions/enemy_on_wall.tres")
open(mfile, "w").write(mission(enemies="Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10)"))
ok("B2 VERIFY is green after the spawns are moved to free cells", vrun(mroot_, s["verify"]) == 0)
open(mfile, "w").write(mission(enemies="Vector2i(6, 6), Vector2i(10, 11), Vector2i(7, 6)", players="Vector2i(5, 5)"))
ok("B2 MUTATION - moving a different spawn (the wall spawns stay) keeps the VERIFY red", vrun(mroot_, s["verify"]) == 1)
open(mfile, "w").write(mission(enemies="Vector2i(6, 6), Vector2i(10, 11), Vector2i(7, 6)", obs="Vector2i(2, 2)", otypes="0"))
ok("B2 moving the OBSTACLES away is NOT accepted: the item forbids it (obstacle cells + types are pinned in the VERIFY)", vrun(mroot_, s["verify"]) == 1)
ok("B2 (bare helper, no keep) still accepts it - the pin comes only from the collector's item", vrun(mroot_, W.verify_mission_spawns("missions/enemy_on_wall.tres")) == 0)
# a "fix" that only deletes the offending spawns (arrays shortened), shortens enemy_types, or drops a player - the item text forbids changing array lengths
def _spawn_fix_variants(M):
    root3 = mkroot({"missions/w.tres": mission(enemies="Vector2i(6, 6), Vector2i(10, 11), Vector2i(7, 6)")})
    sp = [x for x in M.c_mission_spawns(root3)][0]
    out = {}
    for name, txt in (("ok-moved", mission(enemies="Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10)")),
                      ("deleted-spawns", mission(enemies="Vector2i(10, 11)", etypes="7, 5, 5")),                       # enemy_spawns shorter, enemy_types longer
                      ("deleted-spawns-and-types", mission(enemies="Vector2i(10, 11)", etypes="5")),                  # parallel arrays shortened consistently
                      ("types-shortened", mission(enemies="Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10)", etypes="7")),
                      ("player-dropped", mission(enemies="Vector2i(11, 11), Vector2i(10, 11), Vector2i(11, 10)", players="Vector2i(1, 1), Vector2i(2, 1)")),
                      ("obstacle-removed", mission(enemies="Vector2i(6, 6), Vector2i(10, 11), Vector2i(7, 6)", obs="Vector2i(2, 2)", otypes="0"))):
        open(os.path.join(root3, "missions/w.tres"), "w").write(txt)
        out[name] = vrun(root3, sp["verify"])
    return out


_v = _spawn_fix_variants(W)
ok("B2 only a real move of the spawn is green; deleting spawns, shortening enemy_types, dropping a player or removing the obstacle stay red",
   _v == {"ok-moved": 0, "deleted-spawns": 1, "deleted-spawns-and-types": 1, "types-shortened": 1, "player-dropped": 1, "obstacle-removed": 1}, _v)
mut_caught("B2 the VERIFY pins the array lengths and the obstacles", lambda M: _spawn_fix_variants(M) == _v, '" or not kp" if keep is not None else ""', '""')
_lint_src = open(os.path.join(ROOT, "scripts", "ovn_mission_lint.py")).read()
_lint_mut = _lint_src.replace("def _blocks(t):\n    return t in BLOCKING or t not in (0, 1, 2, 3)", "def _blocks(t):\n    return True")
ok("B2 lint mutation applies", _lint_mut != _lint_src)
_md = os.path.realpath(tempfile.mkdtemp(prefix="lintmut-"))
shutil.copy(SUPPLY, _md)
open(os.path.join(_md, "ovn_mission_lint.py"), "w").write(_lint_mut)
_sp = _ilu.spec_from_file_location("ovn_work_supply_lintmut", os.path.join(_md, "ovn_work_supply.py"))
_Mm = _ilu.module_from_spec(_sp)
_sp.loader.exec_module(_Mm)
ok("B2 MUTATION caught: a lint that treats RUBBLE/HAZARD as blocking flags the rubble mission (collector disagrees with the VERIFY)",
   any(x["file"].endswith("enemy_on_rubble.tres") for x in _Mm.c_mission_spawns(mroot_)) and vrun(mroot_, W.verify_mission_spawns("missions/enemy_on_rubble.tres")) == 0)
mroot2_ = mkroot({k: v[0] for k, v in M_CASES.items()})   # pristine copies (the root above had files rewritten by the fix/wrong-fix steps)
mut_caught("B2 inline VERIFY: rubble/hazard walkable, crate/wall/unknown blocking, out-of-grid bad", lambda M: all(vrun(mroot2_, M.verify_mission_spawns(p)) == (1 if b else 0) for p, (_, b) in M_CASES.items()),
           "not in (2,3)}", "not in (3,)}")
_real_missions = os.path.join(os.path.expanduser("~/LocalProjects/xlite/missions"))
if os.path.isdir(_real_missions):
    agree, n = 0, 0
    for fn in sorted(os.listdir(_real_missions)):
        if fn.endswith(".tres"):
            p = os.path.join(_real_missions, fn)
            lint_bad = bool(W._mission_lint().violations(W._mission_lint().parse(open(p).read()), spawn_only=True))
            rc = subprocess.run(["bash", "-c", W.verify_mission_spawns(p)], capture_output=True, text=True).returncode
            n += 1
            agree += (rc == (1 if lint_bad else 0))
    ok("B2 on the %d real xlite missions the inline VERIFY and the lint agree" % n, n > 0 and agree == n, "%d/%d" % (agree, n))
else:
    print("  skip real-mission cross-check (no ~/LocalProjects/xlite checkout here)")
_nl = os.path.realpath(tempfile.mkdtemp(prefix="nolint-"))
shutil.copy(SUPPLY, _nl)
_sp2 = _ilu.spec_from_file_location("ovn_work_supply_nolint", os.path.join(_nl, "ovn_work_supply.py"))
_Mn = _ilu.module_from_spec(_sp2)
_sp2.loader.exec_module(_Mn)
_oe = sys.stderr
sys.stderr = _e4 = __import__("io").StringIO()
try:
    _r4 = list(_Mn.c_mission_spawns(mroot_))
finally:
    sys.stderr = _oe
ok("B2 no ovn_mission_lint.py next to the supply => the collector skips with a stderr line, no crash", _r4 == [] and "ovn_mission_lint.py not found" in _e4.getvalue(), _e4.getvalue())

# ---------------------------------------------------------------- B3: external collector hook
_ext_dir = os.path.realpath(tempfile.mkdtemp(prefix="extcol-"))
open(os.path.join(_ext_dir, "ovn_mutation_supply.py"), "w").write(
    "def collect(root):\n    yield {'kind': 'mutation-survivor', 'file': 'a/b.gd', 'tier': 'T2', 'cat': 'godot', 'text': 't', 'verify': 'true', 'symbols': ['x']}\n")
sys.path.insert(0, _ext_dir)
_clean = mkroot({"iptv-backend/app/services/clean.py": "x = 1\n"})
os.environ.pop("OVN_SUPPLY_MUTATION", None)
sys.modules.pop("ovn_mutation_supply", None)
ok("B3 hook is OFF unless OVN_SUPPLY_MUTATION=1", [s["kind"] for s in W.collect_all(_clean)] == [])
os.environ["OVN_SUPPLY_MUTATION"] = "1"
ok("B3 OVN_SUPPLY_MUTATION=1 appends the module's collect(root) specs", [s["kind"] for s in W.collect_all(_clean)] == ["mutation-survivor"])
os.environ.pop("OVN_SUPPLY_MUTATION", None)
mut_caught("B3 the hook honours OVN_SUPPLY_MUTATION (off by default even when the module exists)", lambda M: M._load_external_collectors() == [],
           'if os.environ.get("OVN_SUPPLY_MUTATION") != "1":\n        return []', 'if False:\n        return []')
sys.modules.pop("ovn_mutation_supply", None)
os.environ["OVN_SUPPLY_MUTATION"] = "1"
open(os.path.join(_ext_dir, "ovn_mutation_supply.py"), "w").write("def collect(root):\n    raise RuntimeError('boom')\n")
sys.modules.pop("ovn_mutation_supply", None)
_old_err = sys.stderr
sys.stderr = _io2 = __import__("io").StringIO()
try:
    r_exc = W.collect_all(_clean)
finally:
    sys.stderr = _old_err
ok("B3 a collect() that raises is skipped with a stderr line", r_exc == [] and "collector collect failed" in _io2.getvalue(), _io2.getvalue())
open(os.path.join(_ext_dir, "ovn_mutation_supply.py"), "w").write("raise ImportError('no deps')\n")
sys.modules.pop("ovn_mutation_supply", None)
sys.stderr = _io3 = __import__("io").StringIO()
try:
    r_imp = W.collect_all(_clean)
finally:
    sys.stderr = _old_err
ok("B3 an ImportError while loading the module is skipped with a stderr line", r_imp == [] and "ovn_mutation_supply skipped" in _io3.getvalue(), _io3.getvalue())
sys.path.remove(_ext_dir)
sys.modules.pop("ovn_mutation_supply", None)
os.environ.pop("OVN_SUPPLY_MUTATION", None)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
