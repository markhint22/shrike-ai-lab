#!/usr/bin/env python3
"""2026-10-18 backlog-out incident, FIX 3a: ovn_work_supply.py / ovn_local_research.py for the other active repos (gitlark, billwatch, test-automation-agent,
shrike-monitor, shrike-notify). Every check also runs against a MUTANT (one broken piece of logic) and must FAIL there."""
import importlib.util
import os
import sys
import tempfile

import tmp_track  # noqa: E402
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
SRC = open(os.path.join(SCRIPTS, "ovn_work_supply.py"), encoding="utf-8").read()
LR_SRC = open(os.path.join(SCRIPTS, "ovn_local_research.py"), encoding="utf-8").read()
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


_n = [0]


def load(src, fname, tag):
    _n[0] += 1
    d = os.path.realpath(tempfile.mkdtemp(prefix="extmod-"))
    p = os.path.join(d, fname)
    open(p, "w", encoding="utf-8").write(src)
    for extra in ("ovn_mission_lint.py",):
        if os.path.exists(os.path.join(SCRIPTS, extra)):
            open(os.path.join(d, extra), "w").write(open(os.path.join(SCRIPTS, extra)).read())
    spec = importlib.util.spec_from_file_location("ext_%s_%d" % (tag, _n[0]), p)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def mutated(src, fname, old, new):
    if src.count(old) != 1:
        ok("mutation anchor exists exactly once: %r" % old[:60], False, src.count(old))
        return None
    return load(src.replace(old, new), fname, "mut")


def mkrepo(files):
    d = os.path.realpath(tempfile.mkdtemp(prefix="extrepo-"))
    for rp, body in files.items():
        os.makedirs(os.path.dirname(os.path.join(d, rp)), exist_ok=True)
        open(os.path.join(d, rp), "w").write(body)
    return d


W = load(SRC, "ovn_work_supply.py", "real")
LR = load(LR_SRC, "ovn_local_research.py", "real")

SWALLOW = "def f():\n    try:\n        x = 1\n    except ValueError:\n        pass\n    return 1\n"
DOCLESS = "def g(a, b):\n    c = a + b\n    d = c * 2\n    e = d - 1\n    f = e + 1\n    return f\n"
PURE = "def clamp(value, low, high):\n    if value < low:\n        return low\n    if value > high:\n        return high\n    return value\n"
files = {"backend/app/services/pure.py": PURE + DOCLESS,
         "backend/app/routers/bad.py": SWALLOW,
         "backend/tests/test_other.py": "def test_x():\n    assert 1\n"}
r = mkrepo(files)

# ---- a: profile on -> only behavioural kinds for the five repos
env_keep = {k: os.environ.pop(k, None) for k in ("OVN_SUPPLY_PROFILE", "OVN_SUPPLY_KINDS")}
for repo in ("gitlark", "billwatch", "test-automation-agent", "shrike-monitor", "shrike-notify"):
    kinds = {s["kind"] for s in W.collect_all(r, repo)}
    ok("profile: %s gets swallowed-exception + pure-function-tests and NO docstring/return-type kinds" % repo,
       {"swallowed-exception", "pure-function-tests"} <= kinds and not (kinds & {"missing-docstring", "missing-return-type", "missing-return-none"}), kinds)
allk = {s["kind"] for s in W.collect_all(r, "iptv_apps")}
ok("unchanged: iptv_apps keeps every collector (docstring kind present)", "missing-docstring" in allk or "missing-return-type" in allk, allk)
ok("unchanged: collect_all(root) without a repo is unrestricted", {s["kind"] for s in W.collect_all(r)} == allk)
os.environ["OVN_SUPPLY_PROFILE"] = "off"
offk = {s["kind"] for s in W.collect_all(r, "gitlark")}
ok("OVN_SUPPLY_PROFILE=off restores every collector for gitlark", "missing-docstring" in offk or "missing-return-type" in offk, offk)
del os.environ["OVN_SUPPLY_PROFILE"]
os.environ["OVN_SUPPLY_KINDS"] = "swallowed-exception"
ok("OVN_SUPPLY_KINDS overrides the allowlist", {s["kind"] for s in W.collect_all(r, "gitlark")} == {"swallowed-exception"})
del os.environ["OVN_SUPPLY_KINDS"]
m = mutated(SRC, "ovn_work_supply.py", 'if repo not in EXTENDED_REPOS or os.environ.get("OVN_SUPPLY_PROFILE", "on") == "off":', "if True:")
if m:
    mk = {s["kind"] for s in m.collect_all(r, "gitlark")}
    ok("MUTANT (profile disabled) is caught: docstring kinds leak into gitlark", bool(mk & {"missing-docstring", "missing-return-type"}), mk)

# ---- b: pure-function-tests for backend/ and billwatch-backend/ layouts
pt = [s for s in W.collect_all(r, "gitlark") if s["kind"] == "pure-function-tests"]
ok("pure tests: backend/ layout -> backend/tests/test_pure_pure.py naming clamp; module path app.services.pure; cwd backend",
   len(pt) == 1 and pt[0]["file"] == "backend/tests/test_pure_pure.py" and "from app.services.pure import clamp" in pt[0]["text"]
   and "&& cd backend && python3 -m pytest tests/test_pure_pure.py -q" in pt[0]["verify"], pt and pt[0])
bw = mkrepo({"billwatch-backend/app/core/pure.py": PURE, "billwatch-backend/tests/test_x.py": "def test_x():\n    assert 1\n"})
bp = [s for s in W.collect_all(bw, "billwatch") if s["kind"] == "pure-function-tests"]
ok("pure tests: billwatch-backend/ layout", len(bp) == 1 and bp[0]["file"] == "billwatch-backend/tests/test_pure_pure.py" and "cd billwatch-backend" in bp[0]["verify"], bp)
col = mkrepo({"backend/app/services/pure.py": PURE, "backend/tests/test_x.py": "def test_x():\n    assert 1\n", "backend/tests/unit/test_pure_pure.py": "def test_y():\n    assert 1\n"})
ok("pure tests: a test file with the same basename elsewhere in the repo is never proposed (pytest import collision)",
   [s for s in W.collect_all(col, "gitlark") if s["kind"] == "pure-function-tests"] == [])
mm = mutated(SRC, "ovn_work_supply.py", "or os.path.basename(test_rel) in taken:", ":")
if mm:
    ok("MUTANT (no basename guard) is caught", len([s for s in mm.collect_all(col, "gitlark") if s["kind"] == "pure-function-tests"]) == 1)
iptv = mkrepo({"iptv-backend/app/services/pure.py": PURE, "iptv-backend/tests/test_x.py": "def test_x():\n    assert 1\n"})
ip = [s for s in W.collect_all(iptv, "iptv_apps") if s["kind"] == "pure-function-tests"]
ok("unchanged: iptv-backend item text/verify identical shape", len(ip) == 1 and ip[0]["file"] == "iptv-backend/tests/test_pure_pure.py"
   and ip[0]["verify"].endswith("&& cd iptv-backend && python3 -m pytest tests/test_pure_pure.py -q"), ip)
nob = mkrepo({"app/services/pure.py": PURE})
ok("no backend dir with tests -> no pure-function item, no crash", [s for s in W.collect_all(nob, "gitlark") if s["kind"] == "pure-function-tests"] == [])

# ---- b2: webhook routers are never rate-limited mechanically
wh = mkrepo({"backend/app/core/rate_limiting.py": "from slowapi import Limiter\nlimiter = Limiter(key_func=None)\n",
             "backend/app/routers/ok.py": "from app.core.rate_limiting import limiter\n@router.get('/a')\n@limiter.limit('5/minute')\ndef a(request):\n    return 1\n",
             "backend/app/routers/billing.py": "@router.get('/s')\ndef get_subscription():\n    return 1\n@router.post('/webhook')\nasync def stripe_webhook(body):\n    return 2\n",
             "backend/app/routers/plain.py": "@router.get('/p')\ndef p():\n    return 1\n"})
rl = {s["file"] for s in W.collect_all(wh, "gitlark") if s["kind"] == "no-rate-limit"}
ok("webhook guard: plain router gets a rate-limit item, the router with stripe_webhook does not", rl == {"backend/app/routers/plain.py"}, rl)
mw = mutated(SRC, "ovn_work_supply.py", 'os.environ.get("OVN_SUPPLY_WEBHOOK_GUARD", "on") != "off" and any(', 'False and any(')
if mw:
    ok("MUTANT (no webhook guard) is caught", "backend/app/routers/billing.py" in {s["file"] for s in mw.collect_all(wh, "gitlark") if s["kind"] == "no-rate-limit"})
os.environ["OVN_SUPPLY_WEBHOOK_GUARD"] = "off"
ok("OVN_SUPPLY_WEBHOOK_GUARD=off restores the old behaviour", "backend/app/routers/billing.py" in {s["file"] for s in W.collect_all(wh, "gitlark") if s["kind"] == "no-rate-limit"})
del os.environ["OVN_SUPPLY_WEBHOOK_GUARD"]

# ---- c: venv resolution for billwatch + spec check linking
bv = mkrepo({"billwatch-backend/.venv/bin/python": ""})
ok("_venv_python finds billwatch-backend/.venv", (W._venv_python(bv) or "").endswith("billwatch-backend/.venv/bin/python"))
sc = open(os.path.join(SCRIPTS, "ovn_spec_check.sh")).read()
ok("ovn_spec_check.sh links backend/.venv and billwatch-backend/.venv into the red-before worktree",
   "for v in .venv iptv-backend/.venv backend/.venv billwatch-backend/.venv; do" in sc)

# ---- d: local research prompt names each repo's real tests dir
for repo, want in (("gitlark", "backend/tests/ only"), ("billwatch", "billwatch-backend/tests/ only"), ("shrike-notify", "backend/tests/ only")):
    ok("local research prompt for %s names %s" % (repo, want), want in LR.build_prompt(repo, [{"kind": "todo", "file": "a.py", "line": 1, "text": "t"}], []))
ok("unchanged: iptv_apps/xlite prompt keeps the legacy text", "(iptv_apps: iptv-backend/tests/ only; xlite: tests/ only)" in LR.build_prompt("xlite", [{"kind": "todo", "file": "a.py", "line": 1, "text": "t"}], []))
lm = mutated(LR_SRC, "ovn_local_research.py", "return TESTS_HINT.get(repo) or", "return None or")
if lm:
    ok("MUTANT (no per-repo hint) is caught", "backend/tests/ only" not in lm.build_prompt("gitlark", [{"kind": "todo", "file": "a.py", "line": 1, "text": "t"}], []))

for k, v in env_keep.items():
    if v is not None:
        os.environ[k] = v
print("test_ovn_supply_extended.py: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
