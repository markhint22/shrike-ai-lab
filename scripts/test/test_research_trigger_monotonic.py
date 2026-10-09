#!/usr/bin/env python3
"""scripts/ovn_research_trigger_check.py: monotonic starvation streak (2026-10-09).

Bug: the streak was re-derived from the planner log by walking back from the LAST line, so any non-starved line reset it. The planner logs
"backlog=N >= 10 - no planning needed" for a repo whose backlog holds duplicates/held items, so iptv and shrike-* flapped between starved and
healthy and their `hours` (the Mac auto-research ordering key) kept restarting from ~0.
Now `starving_since` = first starved line after the last CLEAR; clear only on (a) a decomposition event in the planner log for that repo or
(b) the repo's pullable count above OVN_TRIGGER_PULLABLE_MIN on 2 consecutive checks.

Hermetic: temp HOME with a synthetic planner log and backlog; timestamps are relative to now (computed in python, no GNU/BSD `date` differences).
Mutation checks at the bottom prove each rule is load-bearing.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.normpath(os.path.join(HERE, ".."))
SCRIPT = os.path.join(SCRIPTS, "ovn_research_trigger_check.py")
if not os.path.exists(SCRIPT):
    SCRIPTS = os.path.expanduser("~/overnight-queue/scripts")
    SCRIPT = os.path.join(SCRIPTS, "ovn_research_trigger_check.py")
P = F = 0
H = 3600
STARVE = "no [ready] roadmap feature (needs Claude research?)"
HEALTHY = "backlog=15 >= 10 — no planning needed"
DECOMP = "appended 8 27B-decomposed items to backlog; marked feature [decomposed]"
REMINDER = "sent needs-research reminder"


def ok(name, cond, detail=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(detail)[:300]) if detail else ""))


def ts(secs_ago):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - secs_ago))


class Box:
    """A throwaway ~ with overnight-queue/{logs,state,backlog,repos}; scripts_dir is where the checker (and the sibling ovn_work_supply.py) live."""

    def __init__(self, script=SCRIPT):
        self.home = tempfile.mkdtemp(prefix="trig-")
        self.q = os.path.join(self.home, "overnight-queue")
        for sub in ("logs", "state", "backlog", "repos"):
            os.makedirs(os.path.join(self.q, sub))
        self.script = script
        self.log = os.path.join(self.q, "logs", "ovn_planner.log")
        self.state = os.path.join(self.q, "state", "research_trigger_starving.json")
        self.streaks = os.path.join(self.q, "state", "research_trigger_streaks.json")

    def write_log(self, rows):
        """rows: [(secs_ago, repo, text)]"""
        with open(self.log, "w") as f:
            for ago, repo, text in rows:
                f.write("%s %s: %s\n" % (ts(ago), repo, text))

    def write_backlog(self, repo, n_open):
        with open(os.path.join(self.q, "backlog", repo + ".md"), "w") as f:
            for i in range(n_open):
                f.write("- [ ] [T2] app/mod%d.py — change number %d VERIFY: true.\n" % (i, i))

    def run(self, hours="0.5", env_extra=None):
        env = dict(os.environ, HOME=self.home, OVN_DIR=self.q)
        for k in ("OVN_TRIGGER_MONOTONIC", "OVN_TRIGGER_PULLABLE_MIN"):
            env.pop(k, None)
        env.update(env_extra or {})
        r = subprocess.run([sys.executable, self.script, hours, self.log], capture_output=True, text=True, env=env)
        if r.returncode != 0:
            raise RuntimeError(r.stderr)
        return r.stdout.strip()

    def starving(self):
        with open(self.state) as f:
            return {r["repo"]: r for r in json.load(f)["starving"]}

    def cleanup(self):
        shutil.rmtree(self.home, ignore_errors=True)


def scenarios(script):
    """Runs every scenario against `script`; returns {name: bool}. All True for the real script; each mutant must break at least one."""
    r = {}
    boxes = []

    def box():
        b = Box(script)
        boxes.append(b)
        return b

    # --- flapping: starved / healthy alternate every 30 min for 5h, ending on a healthy line
    flap = []
    for i in range(10):
        flap.append((5 * H - i * 1800, "iptv_apps", "backlog low (2/10) but " + STARVE))
        flap.append((5 * H - i * 1800 - 900, "iptv_apps", HEALTHY))
    b = box()
    b.write_log(flap)
    b.run()
    s1 = b.starving().get("iptv_apps")
    r["flapping ending on a healthy line is still starving"] = s1 is not None
    r["flapping: hours reflect the FIRST starved line (~5h), not the last flap"] = bool(s1) and 4.9 <= s1["hours"] <= 5.1
    since1 = s1["starving_since"] if s1 else None
    # a later run with more flapping lines appended keeps the SAME starving_since
    with open(b.log, "a") as f:
        f.write("%s iptv_apps: %s\n" % (ts(300), HEALTHY))
        f.write("%s iptv_apps: backlog low (2/10) but %s\n" % (ts(100), STARVE))
    b.run()
    s2 = b.starving().get("iptv_apps")
    r["starving_since is stable across runs and appended flapping"] = bool(s2) and s2["starving_since"] == since1
    # healthy line as the very latest, then the checker is run again
    with open(b.log, "a") as f:
        f.write("%s iptv_apps: %s\n" % (ts(10), HEALTHY))
    b.run()
    r["a latest healthy-looking line does not clear the streak"] = "iptv_apps" in b.starving()
    # the planner's reminder line is part of the streak, not a break
    b = box()
    b.write_log([(5 * H, "x", "backlog low (2) but " + STARVE), (4 * H, "x", REMINDER), (3 * H, "x", HEALTHY), (2 * H, "x", REMINDER)])
    b.run()
    sx = b.starving().get("x")
    r["reminder lines do not reset the streak (5h)"] = bool(sx) and 4.9 <= sx["hours"] <= 5.1
    # a reminder is itself a starvation signal: after a decomposition, a lone reminder line starts the next streak
    b = box()
    b.write_log([(6 * H, "y", DECOMP), (3 * H, "y", REMINDER)])
    b.run()
    sr = b.starving().get("y")
    r["a reminder line after a decomposition starts a streak (~3h)"] = bool(sr) and 2.9 <= sr["hours"] <= 3.1

    # --- decomposition clears
    b = box()
    b.write_log([(8 * H, "xlite", STARVE), (6 * H, "xlite", STARVE), (4 * H, "xlite", DECOMP), (3 * H, "xlite", HEALTHY)])
    b.run()
    r["decomposition event clears the streak (nothing starving after it)"] = "xlite" not in b.starving()
    b.write_log([(8 * H, "xlite", STARVE), (4 * H, "xlite", DECOMP), (3 * H, "xlite", STARVE), (1 * H, "xlite", HEALTHY), (1800, "xlite", STARVE)])
    b.run()
    sy = b.starving().get("xlite")
    r["after a decomposition a NEW streak starts at the next starved line (~3h)"] = bool(sy) and 2.9 <= sy["hours"] <= 3.1
    b = box()
    b.write_log([(6 * H, "a", STARVE), (6 * H, "b", STARVE), (3 * H, "a", DECOMP)])
    b.run()
    st = b.starving()
    r["a decomposition for repo A does not clear repo B"] = "a" not in st and "b" in st

    # --- pullable above the threshold on 2 consecutive checks clears
    b = box()
    b.write_log([(6 * H, "iptv_apps", STARVE), (3 * H, "iptv_apps", STARVE)])
    b.write_backlog("iptv_apps", 12)
    b.run()
    r["1st check with pullable>10: still starving"] = "iptv_apps" in b.starving()
    b.run()
    r["2nd consecutive check with pullable>10: cleared"] = "iptv_apps" not in b.starving()
    b.run()
    r["stays cleared on the 3rd check (old starved lines are below the clear mark)"] = "iptv_apps" not in b.starving()
    # not consecutive: high, low, high -> never cleared
    b = box()
    b.write_log([(6 * H, "iptv_apps", STARVE)])
    b.write_backlog("iptv_apps", 12)
    b.run()
    b.write_backlog("iptv_apps", 4)
    b.run()
    b.write_backlog("iptv_apps", 12)
    b.run()
    r["non-consecutive high checks (12,4,12) do not clear"] = "iptv_apps" in b.starving()
    # the boundary: exactly the threshold is not 'above'
    b = box()
    b.write_log([(6 * H, "iptv_apps", STARVE)])
    b.write_backlog("iptv_apps", 10)
    b.run()
    b.run()
    b.run()
    r["pullable == threshold (10) never clears"] = "iptv_apps" in b.starving()
    # env threshold
    b = box()
    b.write_log([(6 * H, "iptv_apps", STARVE)])
    b.write_backlog("iptv_apps", 5)
    b.run(env_extra={"OVN_TRIGGER_PULLABLE_MIN": "3"})
    b.run(env_extra={"OVN_TRIGGER_PULLABLE_MIN": "3"})
    r["OVN_TRIGGER_PULLABLE_MIN=3: pullable 5 on 2 checks clears"] = "iptv_apps" not in b.starving()
    # held / queued items are not pullable (supply's own definition): 12 AUTO-SKIP lines -> 0 pullable -> never clears
    b = box()
    b.write_log([(6 * H, "iptv_apps", STARVE)])
    with open(os.path.join(b.q, "backlog", "iptv_apps.md"), "w") as f:
        for i in range(12):
            f.write("- [ ] [T2] [AUTO-SKIP: parked] app/m%d.py — x%d VERIFY: true.\n" % (i, i))
    b.run()
    b.run()
    b.run()
    r["12 held (AUTO-SKIP) backlog lines are not pullable: never clears"] = "iptv_apps" in b.starving()
    # a new starved line after a pullable clear starts a fresh streak at that line
    b = box()
    b.write_log([(6 * H, "iptv_apps", STARVE), (5 * H, "iptv_apps", STARVE)])
    b.write_backlog("iptv_apps", 12)
    b.run()
    b.run()
    try:
        cleared = json.load(open(b.streaks))["iptv_apps"]["cleared_after"]
    except (OSError, KeyError, ValueError):
        cleared = 0
    # simulate the clear having happened 3h ago, with fresh starved lines 2h and 1h ago
    json.dump({"iptv_apps": {"pull_hi": 0, "cleared_after": time.time() - 3 * H}}, open(b.streaks, "w"))
    b.write_backlog("iptv_apps", 2)
    b.write_log([(6 * H, "iptv_apps", STARVE), (5 * H, "iptv_apps", STARVE), (2 * H, "iptv_apps", STARVE), (1 * H, "iptv_apps", STARVE)])
    b.run()
    sz = b.starving().get("iptv_apps")
    r["after a clear, the new streak starts at the first starved line after it (~2h)"] = bool(sz) and 1.9 <= sz["hours"] <= 2.1 and cleared > 0
    # no backlog / checkout for the repo on this box -> pullable unknown -> no clearing, no crash
    b = box()
    b.write_log([(6 * H, "ghost", STARVE)])
    b.run()
    b.run()
    b.run()
    r["unknown repo (no backlog on the box): never cleared by pullable"] = "ghost" in b.starving()
    # state file contract unchanged
    r["state json keeps repo/starving_since/hours"] = all(k in b.starving()["ghost"] for k in ("repo", "starving_since", "hours"))
    for x in boxes:
        x.cleanup()
    return r


def legacy_flap_shows_the_bug():
    b = Box()
    flap = [(4 * H, "iptv_apps", STARVE), (3 * H, "iptv_apps", HEALTHY), (2 * H, "iptv_apps", STARVE), (1 * H, "iptv_apps", HEALTHY)]
    b.write_log(flap)
    b.run(env_extra={"OVN_TRIGGER_MONOTONIC": "off"})
    legacy = "iptv_apps" in b.starving()
    b.run()
    new = "iptv_apps" in b.starving()
    b.cleanup()
    return legacy, new


print("== monotonic streak: scenarios on the real script ==")
for k, v in scenarios(SCRIPT).items():
    ok(k, v)

print("== kill switch / legacy reproduces the old (buggy) behaviour ==")
legacy, new = legacy_flap_shows_the_bug()
ok("OVN_TRIGGER_MONOTONIC=off: a latest healthy line clears the streak (the old behaviour)", legacy is False)
ok("default: the same log is still starving", new is True)

print("== mutation checks: every rule must be load-bearing ==")
src = open(SCRIPT).read()
mutants = {
    "walk-back (monotonic off by default)": ('os.environ.get("OVN_TRIGGER_MONOTONIC", "on") != "off"', "False"),
    "decomposition events are ignored": ('kind = "starved" if is_starved_signal else ("decomp" if DECOMP_RE.search(rest) else "other")', 'kind = "starved" if is_starved_signal else "other"'),
    "decomposition clears every repo": ("last_decomp = max((t for t, _s, k in events if k == \"decomp\"), default=0)",
                                       "last_decomp = max((t for evs in by_repo.values() for t, _s, k in evs if k == \"decomp\"), default=0)"),
    "pullable boundary >= instead of >": ('1 if n > PULLABLE_MIN else 0', '1 if n >= PULLABLE_MIN else 0'),
    "one pullable check is enough": ("PULLABLE_CHECKS = 2", "PULLABLE_CHECKS = 1"),
    "pullable counter never resets": ('if n > PULLABLE_MIN else 0', 'if n > PULLABLE_MIN else st.get("pull_hi", 0)'),
    "streak start = LAST starved line": ("streak_start = min(starved_ts)", "streak_start = max(starved_ts)"),
    "clear mark ignored": ('floor = max(last_decomp, st.get("cleared_after", 0))', "floor = last_decomp"),
    "reminder line breaks the streak": ("is_starved_signal = bool(STARVED_RE.search(rest) or NON_BREAKING_RE.search(rest))", "is_starved_signal = bool(STARVED_RE.search(rest))"),
    "raw backlog count instead of pullable_count": ("return mod.pullable_count(bt, pt, dt)", 'return sum(1 for l in bt.split("\\n") if l.startswith("- [ ]"))'),
}
tmpd = tempfile.mkdtemp(prefix="trig-mut-")
try:
    shutil.copy(os.path.join(SCRIPTS, "ovn_work_supply.py"), os.path.join(tmpd, "ovn_work_supply.py"))
    for name, (a, b_) in mutants.items():
        assert a in src, "mutation anchor missing for %r - update the test" % name
        mp = os.path.join(tmpd, "ovn_research_trigger_check.py")
        open(mp, "w").write(src.replace(a, b_, 1))
        broken = [k for k, v in scenarios(mp).items() if not v]
        ok("mutant '%s' is caught (%d scenario(s) fail)" % (name, len(broken)), len(broken) >= 1)
finally:
    shutil.rmtree(tmpd, ignore_errors=True)

print("research trigger monotonic: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
