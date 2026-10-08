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
for s_ in W.collect_all(clone4):
    sp4.setdefault((s_["kind"], os.path.basename(s_["file"])), s_)
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
_RUFF_PY = next((c for c in (sys.executable, os.path.expanduser("~/overnight-queue/repos/iptv_apps/iptv-backend/.venv/bin/python"), os.path.expanduser("~/aider-venv/bin/python"))
                 if os.path.exists(c) and subprocess.run([c, "-m", "ruff", "--version"], capture_output=True).returncode == 0), None)
_has_ruff = _RUFF_PY is not None and _RUFF_PY != sys.executable   # only venv pythons are exercised here (the collector needs <root>/.venv)
if _has_ruff:
    # the repo's .venv is a SYMLINK to the provisioned venv dir in production; symlinking only the interpreter loses site-packages (pyvenv.cfg lookup)
    _venv_dir = os.path.dirname(os.path.dirname(_RUFF_PY)) if _RUFF_PY != sys.executable else None
    if _venv_dir and os.path.exists(os.path.join(_venv_dir, "pyvenv.cfg")):
        try:
            os.symlink(_venv_dir, os.path.join(clone5, ".venv"))
        except FileExistsError:
            pass
    open(os.path.join(clone5, "iptv-backend/app/services/imp.py"), "w").write("import os\nimport json\nfrom typing import List\n\ndef f():\n    return json.dumps({})\n")
    ui = [s_ for s_ in W.collect_all(clone5) if s_["kind"] == "unused-import" and s_["file"].endswith("imp.py")]
    ok("unused-import: names exactly the unused names (os, List), not json", ui and "`os`" in ui[0]["text"] and "`typing.List`" in ui[0]["text"] and "json" not in ui[0]["text"], ui and ui[0]["text"])
    ok("unused-import VERIFY red before", ui and run_verify(clone5, ui[0]["verify"].replace("python3 ", _RUFF_PY + " ", 1)) != 0)
    open(os.path.join(clone5, "iptv-backend/app/services/imp.py"), "w").write("import json\n\ndef f():\n    return json.dumps({})\n")
    ok("unused-import VERIFY green after removal", ui and run_verify(clone5, ui[0]["verify"].replace("python3 ", _RUFF_PY + " ", 1)) == 0)
else:
    print("  skip unused-import tests (ruff not importable here)")

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
    if "no new mechanical gaps" in r.stdout:
        break
bl2 = open(os.path.join(d2, "backlog", "demo.md")).read()
keys = [(m.group(1), m.group(2)) for m in (re.search(r"supply:([\w-]+)\) \[feat:demo-\d+-supply-([\w-]+)\]", l) for l in bl2.split("\n") if l.startswith("- [ ]")) if m]
ok("repeated passes converge ('no new mechanical gaps') - one item per file per pass, deferred kinds follow later", "no new mechanical gaps" in r.stdout and passes < 8, r.stdout)
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

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
