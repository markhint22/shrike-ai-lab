#!/usr/bin/env python3
"""P5 (2026-10-26): box_deadman live-attempt heartbeat. Staged runs of 30-54 min write no outcomes row and no reports/*.md, but state/stage_runs/*.log and
logs/<run>/ongoing-*.log keep growing; that mtime (probe key act=) must count as a heartbeat, otherwise 'Fleet stalled: no outcomes' fires falsely (10-25 x2).
A real stall (no fresh log either) must still be stalled. Pure evaluate() checks + the real PROBE snippet against a fake $HOME/overnight-queue + a mutation proof."""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.abspath(os.path.join(HERE, "..", "box_deadman.py"))
if not os.path.isfile(SRC):
    print("  SKIP: scripts/box_deadman.py not installed here (Mac-side job; queue-only mirror has no copy)")
    sys.exit(0)
P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


for k in list(os.environ):
    if k.startswith("DEADMAN_"):
        os.environ.pop(k)
T = os.path.realpath(tempfile.mkdtemp(prefix="deadman-hb-"))
import atexit
atexit.register(lambda: shutil.rmtree(T, ignore_errors=True))
NOW = 1_800_000_000


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))


def probe(gap, act_age=None, **kw):
    """box 'gap' seconds since the last outcomes row/report; act_age = age of the newest stage_runs/ongoing log (None = no such log)."""
    p = {"now": str(NOW), "up": "99999", "unit": "active", "paused": "0", "llm": "200",
         "last": iso(NOW - gap), "mtime": str(NOW - gap), "rep": str(NOW - gap)}
    if act_age is not None:
        p["act"] = str(NOW - act_age)
    p.update(kw)
    return p


def run_all(path, label):
    D = load(path, "bd_" + label)
    ok(label + " 50 min outcomes/report gap + 30 s old stage log -> NOT stalled", "stalled" not in D.evaluate(probe(3000, act_age=30)))
    ok(label + " 54 min gap + ongoing log 10 min old -> NOT stalled", "stalled" not in D.evaluate(probe(3240, act_age=600)))
    ok(label + " 50 min gap and NO activity key -> still stalled (threshold semantics kept)", "stalled" in D.evaluate(probe(3000)))
    ok(label + " 50 min gap + activity log older than the threshold (25 min) -> still stalled", "stalled" in D.evaluate(probe(3000, act_age=1500)))
    ok(label + " empty act= value (no logs found) behaves as absent", "stalled" in D.evaluate(probe(3000, act="")))
    ok(label + " fractional/garbage act values do not crash", "stalled" not in D.evaluate(probe(3000, act=str(NOW - 5) + ".7")) and "stalled" in D.evaluate(probe(3000, act="x")))
    ok(label + " activity does not mask unit_down (unit inactive, not paused)", "unit_down" in D.evaluate(probe(3000, act_age=30, unit="failed")))
    ok(label + " activity does not mask llm_down", "llm_down" in D.evaluate(probe(3000, act_age=30, llm="000")))
    ok(label + " no activity, 1300 s gap -> stalled; 1100 s -> not", "stalled" in D.evaluate(probe(1300)) and "stalled" not in D.evaluate(probe(1100)))
    return D


D = run_all(SRC, "real")
OPS = os.path.abspath(os.path.join(HERE, "..", "..", "ops", "fleet_review", "box_deadman.py"))
if os.path.isfile(OPS):
    run_all(OPS, "ops-copy")
else:
    print("  note: ops/fleet_review/box_deadman.py absent here (queue-only mirror)")

# ---- real PROBE snippet: act= must be the epoch of the newest stage_runs/*.log or logs/*/ongoing-*.log (GNU find -printf; the box is Linux)
SHIM = os.path.join(T, "shim")
os.makedirs(SHIM)
for cand in ("find", "gfind"):
    w = shutil.which(cand)
    if w and subprocess.run([w, T, "-maxdepth", "0", "-printf", "x"], capture_output=True, text=True).stdout == "x":
        os.symlink(w, os.path.join(SHIM, "find"))   # GNU find (on the Mac: findutils' gfind) stands in for the box's find
        break
os.environ["PATH"] = SHIM + os.pathsep + os.environ["PATH"]
probe_ok = subprocess.run(["find", T, "-maxdepth", "0", "-printf", "x"], capture_output=True, text=True).stdout == "x"
if not probe_ok:
    print("  SKIP: PROBE act= checks need GNU find -printf (install findutils for gfind on the Mac)")
else:
    fh = os.path.join(T, "home")
    q = os.path.join(fh, "overnight-queue")
    for d in ("state/stage_runs", "reports", "logs/20261026-080336", "logs/20261025-010000"):
        os.makedirs(os.path.join(q, d))
    open(os.path.join(q, "state", "outcomes.jsonl"), "w").write('{"ts":"2026-10-26T01:00:00Z"}\n')
    now = time.time()

    def touch(rel, age):
        p = os.path.join(q, rel)
        open(p, "w").write("x\n")
        os.utime(p, (now - age, now - age))
    touch("state/stage_runs/xlite-1-s1.log", 600)
    touch("state/stage_runs/xlite-1.jsonl", 5)            # not a .log: must not count
    touch("state/stage_runs/xlite-1.verify.log", 300)     # newest .log
    touch("logs/20261026-080336/ongoing-iptv_apps.log", 900)
    touch("logs/20261026-080336/other.log", 2)            # not an ongoing log: must not count
    touch("logs/20261025-010000/ongoing-xlite.log", 400000)   # ancient: outside the lookback window

    def kv(env_home):
        r = subprocess.run(["sh", "-c", D.PROBE], capture_output=True, text=True, env=dict(os.environ, HOME=env_home), timeout=60)
        return dict(l.split("=", 1) for l in r.stdout.splitlines() if "=" in l), r
    d, r = kv(fh)
    act = d.get("act", "")
    ok("PROBE: act= is numeric", act.isdigit(), (d, r.stderr))
    ok("PROBE: act= is the newest stage_runs/*.log or ongoing-*.log (300 s old), ignoring .jsonl / other.log / ancient",
       act.isdigit() and 250 <= now - int(act) <= 360, (act, now - int(act) if act.isdigit() else None))
    os.remove(os.path.join(q, "state/stage_runs/xlite-1.verify.log"))
    d2, _ = kv(fh)
    ok("PROBE: next newest is the 600 s stage log, not the ongoing 900 s one", d2.get("act", "").isdigit() and 550 <= now - int(d2["act"]) <= 660, d2)
    shutil.rmtree(os.path.join(q, "state", "stage_runs"))
    shutil.rmtree(os.path.join(q, "logs", "20261026-080336"))
    d3, r3 = kv(fh)
    ok("PROBE: no fresh logs -> act= empty and the probe still succeeds", r3.returncode == 0 and d3.get("act", "") == "" and "now" in d3, (d3, r3.stderr))

# ---- mutation proof: drop the new beat from evaluate() in a temp copy -> the no-stall scenario must fail
src = open(SRC).read()
mut = src.replace('_num(p.get("act"))', 'None')
if mut == src:
    ok("mutation: anchor present in box_deadman.py (act beat)", False)
else:
    mp = os.path.join(T, "box_deadman_mut.py")
    open(mp, "w").write(mut)
    M = load(mp, "bd_mut")
    ok("mutation: without the act beat the 50 min gap + fresh log scenario IS (wrongly) stalled", "stalled" in M.evaluate(probe(3000, act_age=30)))

print("%d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
