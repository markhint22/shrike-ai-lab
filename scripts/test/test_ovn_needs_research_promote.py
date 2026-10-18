#!/usr/bin/env python3
"""2026-10-18 FIX 3b: ovn_needs_research_promote.py (bounded, code-grounded [needs-research] -> [ready]). Mutation-checked."""
import os
import subprocess
import sys
import tempfile

import tmp_track  # noqa: E402
tmp_track.install()

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.abspath(os.path.join(HERE, ".."))
SRC = open(os.path.join(SCRIPTS, "ovn_needs_research_promote.py"), encoding="utf-8").read()
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:400]) if extra else ""))


GOOD = "- [ ] [P2] [needs-research] Rate limit the export router — `app/routers/export.py:10` has no limiter {cat: backend; size: M; multifile: no; research: repo}"
WEB = "- [ ] [P2] [needs-research] Competitor pricing tier — `app/routers/export.py` {cat: backend; size: M; research: web}"
NOPATH = "- [ ] [P2] [needs-research] Something vague with no file {cat: backend; size: S}"
GHOST = "- [ ] [P2] [needs-research] Fix `app/routers/ghost.py` handler {cat: backend; size: S; research: repo}"
TESTONLY = "- [ ] [P2] [needs-research] Add a test `tests/test_new.py` {cat: test; size: S}"
HELD = "- [ ] [P2] [needs-research] Wire `app/routers/export.py` HUMAN-ONLY decision {cat: backend; size: S}"
BIG = "- [ ] [P2] [needs-research] Rewrite `app/routers/export.py` {cat: backend; size: L; research: repo}"
GOOD2 = "- [ ] [P3] [needs-research] Validate input in `app/routers/export.py:40` {cat: backend; size: S}"
DONE = "- [x] [P1] [needs-research] already done `app/routers/export.py`"


def setup(lines, src=SRC):
    d = os.path.realpath(tempfile.mkdtemp(prefix="nrp-"))
    for sub in ("repos/demo/app/routers", "roadmap", "state", "scripts"):
        os.makedirs(os.path.join(d, sub), exist_ok=True)
    open(os.path.join(d, "repos/demo/app/routers/export.py"), "w").write("x = 1\n")
    open(os.path.join(d, "roadmap/demo.md"), "w").write("# roadmap\n" + "\n".join(lines) + "\n")
    sp = os.path.join(d, "scripts/ovn_needs_research_promote.py")
    open(sp, "w").write(src)
    return d, sp


def run(d, sp, mode=None, **env):
    e = dict(os.environ, OVN_DIR=d)
    e.pop("OVN_NEEDS_RESEARCH_PROMOTE", None)
    if mode is not None:
        e["OVN_NEEDS_RESEARCH_PROMOTE"] = mode
    e.update(env)
    r = subprocess.run([sys.executable, sp, "demo"], capture_output=True, text=True, env=e, timeout=60)
    return r.returncode, r.stdout.strip().split("\n")[-1], r.stdout


def rm(d):
    return open(os.path.join(d, "roadmap/demo.md")).read()


ALL = [GOOD, WEB, NOPATH, GHOST, TESTONLY, HELD, BIG, DONE]
# default (unset) = shadow
d, sp = setup(ALL)
rc, last, out = run(d, sp)
ok("default mode is shadow: reports 1 candidate, rewrites NOTHING", rc == 0 and last == "SHADOW 1" and "[ready]" not in rm(d) and "WOULD promote" in out, out)
for bad, why in ((WEB, "research:web"), (NOPATH, "no path"), (GHOST, "nonexistent path"), (TESTONLY, "test-only path"), (HELD, "held marker"), (BIG, "size L"), (DONE, "checked box")):
    d2, sp2 = setup([bad])
    ok("never promotable: %s" % why, run(d2, sp2, "enforce")[1].startswith("NONE") and "[ready]" not in rm(d2))
d, sp = setup(ALL)
ok("unknown mode value falls back to shadow (never enforce)", run(d, sp, "bogus")[1] == "SHADOW 1" and "[ready]" not in rm(d))
ok("off does nothing", run(d, sp, "off")[1] == "OFF" and "[ready]" not in rm(d))

# enforce
d, sp = setup(ALL + [GOOD2])
rc, last, out = run(d, sp, "enforce")
t = rm(d)
ok("enforce: promotes exactly ONE grounded feature per pass (the first), stamps it", last == "PROMOTED 1" and t.count("[ready]") == 1 and "AUTO-PROMOTED" in t
   and "[P2] [ready] Rate limit the export router" in t and "[P3] [needs-research] Validate input" in t, t)
ok("enforce: ungrounded lines are left byte-identical", all(x in t for x in (WEB, NOPATH, GHOST, TESTONLY, HELD, BIG, DONE)))
rc, last, _ = run(d, sp, "enforce")
ok("enforce: second pass promotes the next one (P3)", last == "PROMOTED 1" and "[P3] [ready] Validate input" in rm(d))
d3, sp3 = setup([GOOD, GOOD2, GOOD.replace("export router", "third thing")])
run(d3, sp3, "enforce"); run(d3, sp3, "enforce")
rc, last, _ = run(d3, sp3, "enforce")
ok("enforce: daily quota (default 2) stops the third promotion", last.startswith("NONE daily quota") and rm(d3).count("[ready]") == 2, last)
d4, sp4 = setup([GOOD, GOOD2])
run(d4, sp4, "enforce", OVN_NRP_QUOTA="1")
ok("OVN_NRP_QUOTA=1 honoured", run(d4, sp4, "enforce", OVN_NRP_QUOTA="1")[1].startswith("NONE daily quota") and rm(d4).count("[ready]") == 1)
d5, sp5 = setup([GOOD])
run(d5, sp5, "shadow"); run(d5, sp5, "shadow"); run(d5, sp5, "shadow")
ok("shadow never consumes quota", not [f for f in os.listdir(os.path.join(d5, "state")) if f.startswith("nrp_count")])
ok("alerts.log gets an info line on enforce", "needs-research-promote:demo" in open(os.path.join(d, "state/alerts.log")).read())
d6 = os.path.realpath(tempfile.mkdtemp(prefix="nrp-"))
sp6 = os.path.join(d6, "p.py")
open(sp6, "w").write(SRC)
ok("missing checkout/roadmap -> NONE, exit 0", run(d6, sp6, "enforce")[:2] == (0, "NONE no checkout or roadmap"))

# mutants: each must flip a verdict above
def mut(old, new):
    if SRC.count(old) != 1:
        ok("mutation anchor exactly once: %r" % old[:50], False, SRC.count(old))
        return None
    return SRC.replace(old, new)


m = mut('return m if m in MODES else "shadow"', 'return m if m in MODES else "enforce"')
if m:
    dm, spm = setup(ALL, m); run(dm, spm, "bogus") ; ok("MUTANT (unknown->enforce) is caught", "[ready]" in rm(dm))
m = mut('if not real:\n        return False, "cites no existing non-test path"', "if False:\n        pass")
m = m and m.replace('if not paths:\n        return False, "cites no path"', "if False:\n        pass")
m = m and m.replace('"grounded in %s" % real[0]', '"grounded"')
if m:
    dm, spm = setup([NOPATH], m); ok("MUTANT (ungrounded allowed) is caught", run(dm, spm, "enforce")[1] == "PROMOTED 1" or "[ready]" in rm(dm))
m = mut("if m and m.group(1) not in OK_RESEARCH:", "if False:")
if m:
    dm, spm = setup([WEB], m); ok("MUTANT (research:web allowed) is caught", "[ready]" in (run(dm, spm, "enforce") and rm(dm)))
m = mut('if md == "enforce" and used >= quota:', "if False:")
m = m and m.replace("take = min(per_pass, max(quota - used, 0) if md == \"enforce\" else per_pass)", "take = per_pass")
if m and "take = per_pass" not in m:
    ok("quota mutant anchor for take applies", False)
elif m:
    dm, spm = setup([GOOD, GOOD2, GOOD.replace("export router", "third thing")], m); [run(dm, spm, "enforce") for _ in range(3)]
    ok("MUTANT (no quota) is caught", rm(dm).count("[ready]") == 3)
m = mut('if md == "shadow":\n        print("SHADOW %d" % len(hits))\n        return 0', "if False:\n        return 0")
if m:
    dm, spm = setup([GOOD], m); run(dm, spm, "shadow"); ok("MUTANT (shadow writes) is caught", "[ready]" in rm(dm))
m = mut("if HELD_RE.search(rest):", "if False:")
if m:
    dm, spm = setup([HELD], m); run(dm, spm, "enforce"); ok("MUTANT (held marker ignored) is caught", "[ready]" in rm(dm))
print("test_ovn_needs_research_promote.py: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
