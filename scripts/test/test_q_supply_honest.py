#!/usr/bin/env python3
"""pkg q-supply-honest (2026-11-11): ovn_supply_forecast runway_h must divide by items CLOSED (landed + credited + skipped/parked/retired), not distinct LANDED over 7 d.
Fixture reproduces TAA on 2026-11-11: 41 items closed (23 landed, 16 auto-credited, 2 parked) in 18 h with 80 pullable. Hermetic temp dirs; the repo clone is a real git repo whose
OVERNIGHT_PROGRESS.md history is the closure source. QSH_SCRIPTS=<dir> runs the checks against a mutated copy (mutant runner at the bottom; --no-mutants skips it)."""
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.environ.get("QSH_SCRIPTS") or os.path.abspath(os.path.join(HERE, ".."))
os.environ["TZ"] = "UTC"
time.tzset()
BASE = os.path.realpath(tempfile.mkdtemp(prefix="qsh-supply-"))
import atexit  # noqa: E402
atexit.register(lambda: shutil.rmtree(BASE, ignore_errors=True) if os.path.basename(BASE).startswith("qsh-supply-") else None)
ROOT = os.path.join(BASE, "q")
STATE = os.path.join(ROOT, "state")
os.makedirs(STATE)
for k in list(os.environ):
    if k.startswith(("OVN_FORECAST", "OVN_SUPPLY_FORECAST")):
        del os.environ[k]
os.environ["OVN_DIR"] = ROOT
os.environ["OVN_NOTIFY_STATE"] = STATE
sys.path.insert(0, SCRIPTS)

P = F = 0


def check(name, cond):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name)


def load(name):
    spec = importlib.util.spec_from_file_location(name + "_qsh", os.path.join(SCRIPTS, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    sys.modules[name] = m
    spec.loader.exec_module(m)
    return m


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w").write(text)


def iso(t):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(t))


NOW = float(time.mktime((2026, 11, 11, 22, 0, 0, 0, 0, -1)))
GENV = {k: v for k, v in os.environ.items()}
GENV.update({"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"})


class Repo:
    """A throwaway clone whose OVERNIGHT_PROGRESS.md is rewritten + committed at a chosen time."""
    def __init__(self, name):
        self.d = os.path.join(ROOT, "repos", name)
        os.makedirs(self.d)
        self.lines = []
        subprocess.run(["git", "init", "-q"], cwd=self.d, check=True, env=GENV)

    def commit(self, t, msg="chore(queue): update"):
        w(os.path.join(self.d, "OVERNIGHT_PROGRESS.md"), "# progress\n" + "\n".join(self.lines) + "\n")
        env = dict(GENV, GIT_AUTHOR_DATE="%d +0000" % t, GIT_COMMITTER_DATE="%d +0000" % t)
        subprocess.run(["git", "add", "-A"], cwd=self.d, check=True, env=env)
        subprocess.run(["git", "commit", "-qm", msg, "--allow-empty"], cwd=self.d, check=True, env=env)


def item(i, tag="[T1]"):
    return "- [ ] %s backend/app/m%d.py - change thing %d. VERIFY: `true`" % (tag, i, i)


sf = load("ovn_supply_forecast")

# ---------------------------------------------------------------- TAA replay: 41 closed (23 landed + 16 credited + 2 parked) in 18 h, 80 pullable left
taa = Repo("taa")
taa.lines = [item(i) for i in range(121)]
taa.commit(NOW - 20 * 3600, "chore(queue): refill")
rows = []
n = 0
for k in range(23):                      # 23 landings: the item's line flips to [x] and an outcomes row lands
    t = NOW - 18 * 3600 + k * 2400
    taa.lines[n] = taa.lines[n].replace("- [ ]", "- [x]")
    taa.commit(t, "feat: land")
    rows.append({"ts": iso(t), "repo": "taa", "class": "landed", "status": "pushed(tests:pass)", "item_hash": "h%d" % n, "duration_s": 100, "feat_tag": "x"})
    n += 1
for k in range(8):                       # 8 credit commits flip 2 items each (16 items): NO outcomes row for the credited items
    t = NOW - 17 * 3600 + k * 7000
    for _ in range(2):
        taa.lines[n] = taa.lines[n].replace("- [ ]", "- [x]")
        n += 1
    taa.commit(t, "chore(queue): auto-credit item(s) whose file this green change touched")
for k in range(2):                       # 2 parks: retagged AUTO-SKIP (still an unchecked line, but held)
    t = NOW - 5 * 3600 + k * 600
    taa.lines[n] = "- [ ] [AUTO-SKIP] " + taa.lines[n][6:]
    n += 1
    taa.commit(t, "chore(queue): park item after 2+ credit refusals")
# a refill adds a new open item: must NOT count as closed
taa.lines.append(item(900))
taa.commit(NOW - 4 * 3600, "chore(queue): auto-refill")
w(os.path.join(STATE, "outcomes.jsonl"), "\n".join(json.dumps(r) for r in rows) + "\n")
w(os.path.join(ROOT, "backlog", "taa.md"), "# b\n")
w(os.path.join(ROOT, "roadmap", "taa.md"), "# r\n- [ ] [P2] [decomposed] old\n")
fc = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["taa"])
T = fc["repos"]["taa"]
open_items = len([l for l in open(os.path.join(taa.d, "OVERNIGHT_PROGRESS.md")) if l.startswith("- [ ]") and "AUTO-SKIP" not in l])
check("A1 pullable is the live open count", T["pullable"] == open_items and open_items > 70)
check("A2 closed_24h counts landed + credited (39); a park is an in-place rewrite of the same item (AUTO-SKIP retag), not a closure", T["closed_24h"] == 39)
check("A3 old landed-only burn kept (23/day over a 1-day floor)", abs(T["burn_per_day_landed_only"] - 23.0) < 0.05)
check("A4 honest burn is the 24h figure (39 closed / 0.75 d = 52/d), larger than the 7d figure", abs(T["burn_per_day"] - 39 / 0.75) < 0.1 and T["burn_per_day"] > T["burn_7d_per_day"])
old_run = round(T["supply"] / (23.0 / 24.0), 1)
check("A5 runway_h_landed_only equals the old formula", abs(T["runway_h_landed_only"] - old_run) < 0.2)
check("A6 runway_h is the honest one: 2x+ below the landed-only runway and ~35h", T["runway_h"] < T["runway_h_landed_only"] / 2 and 30 <= T["runway_h"] <= 40)
check("A7 runway_h == min(runway_24h_h, runway_7d_h)", T["runway_h"] == min(T["runway_24h_h"], T["runway_7d_h"]))
check("A8 closed_source says git was used", T["closed_source"] == "outcomes+git")
check("A9 json carries the old numbers for comparison", "runway_h_landed_only" in T and "burn_per_day_landed_only" in T)

# ---------------------------------------------------------------- refill / re-add must not look like closure
rf = Repo("rf")
rf.lines = [item(i) for i in range(10)]
rf.commit(NOW - 30 * 3600)
rf.lines = [item(i) for i in range(10)] + [item(i) for i in range(10, 20)]   # refill only
rf.commit(NOW - 3 * 3600, "chore(queue): auto-refill")
tmp = rf.lines[3]
rf.lines[3] = tmp                                   # moved, unchanged: removed then re-added unheld in the same window
rf.lines = rf.lines[:3] + rf.lines[4:] + [tmp]
rf.commit(NOW - 2 * 3600, "chore(queue): reorder")
w(os.path.join(STATE, "outcomes.jsonl"), open(os.path.join(STATE, "outcomes.jsonl")).read() + json.dumps({"ts": iso(NOW - 3600), "repo": "rf", "class": "reverted", "status": "x", "item_hash": "rf1", "duration_s": 5, "feat_tag": "x"}) + "\n")
w(os.path.join(ROOT, "roadmap", "rf.md"), "# r\n")
fc2 = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["rf"])
check("B1 refill + a moved (re-added) line are not closures: closed == 0", fc2["repos"]["rf"]["closed_24h"] == 0)

# ---------------------------------------------------------------- no clone/progress file: outcomes only, never below the landed figure
w(os.path.join(ROOT, "roadmap", "nc.md"), "# r\n")
os.makedirs(os.path.join(ROOT, "repos", "nc"))
w(os.path.join(ROOT, "backlog", "nc.md"), "# b\n" + "".join("- [ ] [T1] scripts/f%d.py - c%d. VERIFY: `true`\n" % (i, i) for i in range(40)))
extra = []
for i in range(6):
    extra.append({"ts": iso(NOW - 3600 * (i + 1)), "repo": "nc", "class": "landed", "status": "x", "item_hash": "nc%d" % i, "duration_s": 5, "feat_tag": "x"})
for i in range(3):
    extra.append({"ts": iso(NOW - 1800 * (i + 1)), "repo": "nc", "class": "credit-only", "status": "pushed(tests:pass) [credit-only]", "item_hash": "ncc%d" % i, "duration_s": 5, "feat_tag": "x"})
extra.append({"ts": iso(NOW - 60), "repo": "nc", "class": "reverted", "status": "reverted", "item_hash": "ncr", "duration_s": 5})
w(os.path.join(STATE, "outcomes.jsonl"), open(os.path.join(STATE, "outcomes.jsonl")).read() + "\n".join(json.dumps(r) for r in extra) + "\n")
fc3 = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["nc"])
N = fc3["repos"]["nc"]
check("C1 no OVERNIGHT_PROGRESS.md: closed = landed + credit-only rows (9), a revert is not closure", N["closed_24h"] == 9 and N["closed_source"] == "outcomes")
check("C2 honest burn >= landed-only burn always", N["burn_per_day"] >= N["burn_per_day_landed_only"])

# ---------------------------------------------------------------- 24h vs 7d: the more pessimistic runway wins both ways
a = [{"ts": iso(NOW - 6 * 86400 + i * 600), "repo": "wk", "class": "landed", "status": "x", "item_hash": "o%d" % i, "duration_s": 5, "feat_tag": "x"} for i in range(70)]   # 70 landed ~6 d ago
a.append({"ts": iso(NOW - 3600), "repo": "wk", "class": "landed", "status": "x", "item_hash": "recent", "duration_s": 5, "feat_tag": "x"})
rows_wk = []
import calendar  # noqa: E402
for r in a:
    r = dict(r)
    r["_t"] = calendar.timegm(time.strptime(r["ts"], "%Y-%m-%dT%H:%M:%S"))
    rows_wk.append(r)
cb = sf.closed_burn(rows_wk, "wk", NOW, 7)
check("D1 old burst, quiet day: 7d window dominates (71 in a 6-day history = 11.8/d > 1/d)", abs(cb["burn"] - 71 / 6.0) < 0.05 and cb["closed_24h"] == 1)
b = [{"ts": iso(NOW - 6 * 86400), "repo": "wk2", "class": "landed", "status": "x", "item_hash": "z0", "duration_s": 5, "feat_tag": "x"}]
b += [{"ts": iso(NOW - 3600 * (i % 20 + 1)), "repo": "wk2", "class": "landed", "status": "x", "item_hash": "n%d" % i, "duration_s": 5, "feat_tag": "x"} for i in range(30)]
rows_wk2 = [dict(r, _t=calendar.timegm(time.strptime(r["ts"], "%Y-%m-%dT%H:%M:%S"))) for r in b]
cb2 = sf.closed_burn(rows_wk2, "wk2", NOW, 7)
check("D2 busy day after a quiet week: 24h window dominates (30/d > 31/7)", abs(cb2["burn"] - 30.0) < 0.05 and cb2["burn_24h_per_day"] > cb2["burn_7d_per_day"])
check("D3 a repo with no rows in the window is unknown (None), not zero", sf.closed_burn(rows_wk, "nobody", NOW, 7) is None)

# ---------------------------------------------------------------- consumers: nothing flooded or silently disabled by the honest numbers
check("E1 honest 35h runway is NOT short at the 24h floor (no new request/alert flood)", T["short"] is False and T["priority"] is None and T["shortfall_items"] == 0)
os.environ["OVN_FORECAST_RUNWAY_H"] = "48"
fc4 = sf.collect(now=NOW, root=ROOT, state=STATE, repos=["taa"])
del os.environ["OVN_FORECAST_RUNWAY_H"]
check("E2 a repo is short when the honest runway is under the floor (floor 48h -> short, NORMAL priority, not high)", fc4["repos"]["taa"]["short"] and fc4["repos"]["taa"]["priority"] == "normal")
check("E3 shortfall is sized from the honest burn (burn x 48h - supply)", fc4["repos"]["taa"]["shortfall_items"] == int(-(-(T["burn_per_day"] * 2 - T["supply"]) // 1)))
check("E4 shadow mode: digest empty, no research_requests dir", sf.digest_lines(fc4) == [] and not os.path.isdir(os.path.join(STATE, "research_requests")))
sf.write_outputs(fc4, root=ROOT, state=STATE)
check("E5 shadow write_outputs leaves research_requests absent", not os.path.isdir(os.path.join(STATE, "research_requests")))
on = dict(fc4, mode="on")
sf.write_outputs(on, root=ROOT, state=STATE)
req = json.load(open(os.path.join(STATE, "research_requests", "taa.json")))
check("E6 mode on: request carries the honest runway_h and burn", req["runway_h"] == fc4["repos"]["taa"]["runway_h"] and abs(req["burn_per_day"] - fc4["repos"]["taa"]["burn_per_day"]) < 1e-9)
check("E7 mode on: digest bullet shows the honest runway", "taa %gh" % fc4["repos"]["taa"]["runway_h"] in sf.digest_lines(on)[0])
check("E8 legacy callers of forecast_repo (no honest args) keep the old behaviour: runway_h == runway_h_landed_only",
      (lambda r: r["runway_h"] == r["runway_h_landed_only"] == 48.0)(sf.forecast_repo("r", 8, 0, 4.0, 5, 24, 6, 48)))

# ---------------------------------------------------------------- q-supply-honest 2: rewrites are NOT closures (net-removed keys), true landings are
AS = "[AUTO-SKIP after 3 failed-to-land cycles - kept reverting; review - NOT necessarily human-only] "


def closed_of(repo, window_h=24):
    ev = sf.git_progress_closures(repo.d, NOW - 7 * 86400)
    return sf._git_closed_count(ev, NOW - window_h * 3600)


def scen(name):
    r = Repo(name)
    r.lines = [item(i) for i in range(4)]
    r.commit(NOW - 30 * 3600, "chore(queue): seed")
    return r


def mark_done(r, i, t, msg):
    r.lines[i] = r.lines[i].replace("- [ ]", "- [x]", 1)
    r.commit(t, msg)


r1 = scen("rw1")   # parked item gets recovery-attempted: AUTO-SKIP variant of the same item, same key
r1.lines[0] = "- [ ] " + AS + r1.lines[0][6:]
r1.commit(NOW - 5 * 3600, "chore(queue): update")                       # neutral subject: only the key rule can save this
r1.lines[0] = r1.lines[0].replace("[AUTO-SKIP after", "[AUTO-SKIP recovery:none after")
r1.commit(NOW - 4 * 3600, "chore(queue): mark rw1 parked item recovery-attempted (no decomposition)")
check("F1 park + recovery-attempted rewrites of one item: 0 closures", closed_of(r1) == 0)
r1b = scen("rw1b")
r1b.lines[0] = "- [ ] " + AS + r1b.lines[0][6:]
r1b.commit(NOW - 5 * 3600, "chore(queue): auto-skip item after 3 failed-to-land cycles (needs a human)")
check("F1b auto-skip retag (held variant of the same key, neutral-looking subject): 0 closures", closed_of(r1b) == 0)

r2 = scen("rw2")   # recover parked -> N smaller sub-items: supply GROWS
r2.lines[1] = "- [ ] " + AS + r2.lines[1][6:]
r2.commit(NOW - 6 * 3600, "chore(queue): auto-skip item")
r2.lines[1] = r2.lines[1].replace("- [ ]", "- [x]", 1)
r2.lines += [item(50), item(51), item(52)]
r2.commit(NOW - 5 * 3600, "feat(queue): recover parked rw2 item -> 3 smaller sub-item(s)")
check("F2 recover parked item -> sub-items: 0 closures (supply grew)", closed_of(r2) == 0)

r3 = scen("rw3")   # mark staged TN item so it isn't re-run: unchecked -> [x] but not a landing
mark_done(r3, 2, NOW - 5 * 3600, "chore(queue): mark staged T3 item (2/2) so it isn't re-run")
check("F3 mark staged item: 0 closures", closed_of(r3) == 0)

r4 = scen("rw4")   # escalate staged item to Claude: unheld line -> [AUTO-SKIP staged ...] route to CLAUDE
r4.lines[3] = "- [ ] [AUTO-SKIP staged: 27B could not land this - route to CLAUDE] " + r4.lines[3][6:]
r4.commit(NOW - 5 * 3600, "chore(queue): escalate staged T3 item to Claude (27B couldn't land it)")
check("F4 escalate staged item: 0 closures", closed_of(r4) == 0)
r4b = scen("rw4b")
r4b.lines[3] = "- [ ] [CLAUDE] " + r4b.lines[3][6:]
r4b.commit(NOW - 5 * 3600, "chore(queue): update")
check("F4b [CLAUDE] retag with a neutral subject: 0 closures (key rule alone)", closed_of(r4b) == 0)

r5 = scen("rw5")   # TRUE landings: [x] flip by an auto-credit, and a plain deletion of an open line
mark_done(r5, 0, NOW - 5 * 3600, "chore(queue): auto-credit item(s) whose file this green change touched")
del r5.lines[1]
r5.commit(NOW - 4 * 3600, "chore(queue): retire vague no-file items (auto-sanitizer)")
check("F5 true landing ([x]) + deletion (retire) count: 2 closures", closed_of(r5) == 2)

r6 = scen("rw6")   # removed in one commit, re-added unchecked in a LATER commit
mark_done(r6, 0, NOW - 6 * 3600, "chore(queue): auto-credit item(s)")
r6.lines[0] = r6.lines[0].replace("- [x]", "- [ ]", 1)
r6.commit(NOW - 3 * 3600, "chore(queue): reopen")
check("F6 removal followed by a later re-add of the same item: 0 closures", closed_of(r6) == 0)

r7 = scen("rw7")   # a held line leaving the file is not supply being consumed
r7.lines[0] = "- [ ] " + AS + r7.lines[0][6:]
r7.commit(NOW - 29 * 3600 + 3600, "chore(queue): auto-skip item")
del r7.lines[0]
r7.commit(NOW - 4 * 3600, "chore(queue): cleanup")
check("F7 deleting an already-held (parked) line: 0 closures", closed_of(r7) == 0)

# ---------------------------------------------------------------- real-world replay hook: QSH_REPLAY=<outcomes.jsonl copy> prints old vs new runway (read-only, informational)
print("\n  %d passed, %d failed" % (P, F))
if F:
    sys.exit(1)

if "--no-mutants" in sys.argv or os.environ.get("QSH_SCRIPTS"):
    sys.exit(0)
MUT = [
    ("honest burn counts landed only", "ovn_supply_forecast.py", 'CLOSED_CLASSES = ("landed", "landed-uncredited", "credit-only")', 'CLOSED_CLASSES = ("landed",)'),
    ("git closures ignored", "ovn_supply_forecast.py", "n = max(n, _git_closed_count(git_events, lo))", "pass"),
    ("runway uses the optimistic (smaller) of the two burns", "ovn_supply_forecast.py", "best = max(best, n / days)", "best = n / days if best == 0 else min(best, n / days)"),
    ("same-commit move (removed and re-added) counts as closure", "ovn_supply_forecast.py", "if k not in a_set and not skip_commit:", "if not skip_commit:"),
    ("held removal counted as closure", "ovn_supply_forecast.py", "if m and not HELD_RE.search(m.group(1)):   # a held", "if m:   # a held"),
    ("rewrite-subject commits count their removals", "ovn_supply_forecast.py", "if k not in a_set and not skip_commit:", "if k not in a_set:"),
    ("held re-add does not cancel the removal (held adds not recorded)", "ovn_supply_forecast.py", "            if m:\n                add.append(_item_key(m.group(1)))", "            if m and not HELD_RE.search(m.group(1)):\n                add.append(_item_key(m.group(1)))"),
    ("landed-only runway field dropped", "ovn_supply_forecast.py", 'rec["runway_h_landed_only"] = round(supply / (burn_landed / 24.0), 1)', "pass"),
    ("runway_h still driven by the landed-only burn", "ovn_supply_forecast.py", "burn = None if hb is None else max(hb[\"burn\"], landed_burn or 0.0)", "burn = landed_burn"),
    ("24h window days not floored (history shorter than a day)", "ovn_supply_forecast.py", "min(1.0, max(0.25, history_d))", "1.0"),
    ("refill adds counted as closure", "ovn_supply_forecast.py", "return sum(1 for d in last.values() if d == 1)", "return len(last)"),
    ("oldest event wins instead of the newest", "ovn_supply_forecast.py", "if t >= lo and k not in last:", "if t >= lo:"),
]
tmpd = tempfile.mkdtemp(prefix="qsh-mut-")
bad = 0
try:
    for fn in os.listdir(SCRIPTS):
        if fn.endswith(".py"):
            shutil.copy(os.path.join(SCRIPTS, fn), tmpd)
    for name, f, old, new in MUT:
        src = open(os.path.join(SCRIPTS, f)).read()
        if old not in src:
            print("  MUTANT SETUP FAIL (pattern not found): " + name)
            bad += 1
            continue
        open(os.path.join(tmpd, f), "w").write(src.replace(old, new, 1))
        r = subprocess.run([sys.executable, os.path.abspath(__file__), "--no-mutants"], env=dict(os.environ, QSH_SCRIPTS=tmpd), capture_output=True, text=True, timeout=300)
        killed = r.returncode != 0
        print("  %s mutant: %s" % ("killed  " if killed else "SURVIVED", name))
        bad += 0 if killed else 1
        shutil.copy(os.path.join(SCRIPTS, f), os.path.join(tmpd, f))
finally:
    shutil.rmtree(tmpd, ignore_errors=True)
sys.exit(1 if bad else 0)
