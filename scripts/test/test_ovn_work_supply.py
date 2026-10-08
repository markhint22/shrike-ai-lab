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
    "iptv-backend/app/routers/open_router.py": "from app.core.limiter import limiter\n@router.get('/x')\n@limiter.limit('30/minute')\ndef x(request):\n    return 1\n@router.post('/y')\n@limiter.limit('30/minute')\nasync def y(request, body):\n    return 2\n",
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
ok("no VERIFY contains '>' (the runner refuses redirect-looking characters)", all(">" not in v for v in verifies.values()), [v for v in verifies.values() if ">" in v])
sh("git", "checkout", "-q", "--", ".", cwd=clone)
for rp in fixed:
    sh("git", "checkout", "-q", "--", rp, cwd=clone)

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
ok("supply appends the 4 mechanical items", r.stdout.count("ADDED 4") == 1 and bl.count("supply:") == 4, r.stdout + r.stderr)
ok("every appended line has an executable VERIFY clause and a [feat:] tag", all("VERIFY: `python3 -c" in l and "[feat:demo-" in l for l in bl.split("\n") if l.startswith("- [ ]")))
r = sh(sys.executable, SUPPLY, "demo", "--force", env=env)
bl2 = open(os.path.join(d2, "backlog", "demo.md")).read()
ok("second pass adds nothing (same gaps are not re-supplied)", bl2 == bl and "no new mechanical gaps" in r.stdout, r.stdout)
# already-satisfied gap is dropped, not queued
d3, clone3 = make_fixture()
open(os.path.join(clone3, "iptv-backend/app/services/swallow.py"), "w").write("def f():\n    pass\n")  # no handler: nothing to supply
r = sh(sys.executable, SUPPLY, "demo", env=dict(os.environ, OVN_DIR=d3))
ok("a file with no gap yields no swallowed-exception item", "swallowed-exception" not in open(os.path.join(d3, "backlog", "demo.md")).read())
# enough backlog -> no supply
open(os.path.join(d3, "backlog", "demo.md"), "w").write("\n".join("- [ ] [T2] x%d — y" % i for i in range(25)) + "\n")
r = sh(sys.executable, SUPPLY, "demo", env=dict(os.environ, OVN_DIR=d3))
ok("no supply when the backlog is already deep", "no supply needed" in r.stdout, r.stdout)
r = sh(sys.executable, SUPPLY, "demo", env=dict(os.environ, OVN_DIR=d3, OVN_WORK_SUPPLY="off"))
ok("kill switch OVN_WORK_SUPPLY=off", "OVN_WORK_SUPPLY=off" in r.stdout)

print("\n%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
