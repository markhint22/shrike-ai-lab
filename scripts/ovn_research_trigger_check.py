#!/usr/bin/env python3
"""Research-trigger detector (2026-09-23).

ovn_planner.sh already logs "<repo>: backlog low (N) but no [ready] roadmap feature
(needs Claude research?)" to ovn_planner.log every time it finds a repo with a thin
backlog and nothing decomposable in the roadmap. Nothing currently watches for this
persisting — a repo can sit starved for days before a human notices (the exact
incident behind [[project_backlog-starvation-and-shadow-checks-2026-09-22]]).

This reads ovn_planner.log and, for each repo, walks backward from its most recent
line: if that line is a "no ready feature" hit AND the unbroken streak of such hits
goes back at least STARVE_HOURS, the repo is "confirmed starving" - it has not had a
single successful planning pass in that whole window, not just one unlucky check.

Writes state/research_trigger_starving.json (a plain list of currently-starving
repos + how long each has been starving) so a SEPARATE consumer - a session-side
poller (this repo has no way to itself launch a Claude Code research pass; only an
actual interactive/API Claude session can do that) - can decide whether to act,
without re-parsing the log itself. Also prints a one-line human summary for the cron
log + ntfy alert.

2026-10-09 MONOTONIC STREAK (default; OVN_TRIGGER_MONOTONIC=off restores the walk-back rule above): the planner logs "backlog=N >= 10 - no planning
needed" for a repo whose backlog is full of duplicates/held items, so a repo alternated between "starved" and "healthy" lines and the streak (hence
`hours`, hence the Mac auto-research starvation ordering) kept resetting (iptv, shrike-*). Now `starving_since` is the first starved line after the last
CLEAR, and a streak is cleared only by (a) a decomposition event in the planner log for that repo ("appended N 27B-decomposed items" / "marked feature
[decomposed]"), or (b) the repo's PULLABLE count (ovn_work_supply.pullable_count: what the fleet can really take next) being above
OVN_TRIGGER_PULLABLE_MIN (default 10) on 2 consecutive checks. Any other line (healthy-looking or not) is ignored. (b) needs memory between runs:
state/research_trigger_streaks.json {repo: {pull_hi, cleared_after}}.

Usage: ovn_research_trigger_check.py [starve_hours=2] [log_path]
"""
import importlib.util
import json
import os
import re
import sys
import time

STARVE_HOURS = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
LOG = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/overnight-queue/logs/ovn_planner.log")
STATE = os.path.expanduser("~/overnight-queue/state/research_trigger_starving.json")
STREAK_STATE = os.path.join(os.path.dirname(STATE), "research_trigger_streaks.json")
OVN_DIR = os.environ.get("OVN_DIR") or os.path.expanduser("~/overnight-queue")
MONOTONIC = os.environ.get("OVN_TRIGGER_MONOTONIC", "on") != "off"
PULLABLE_MIN = int(os.environ.get("OVN_TRIGGER_PULLABLE_MIN", "10"))
PULLABLE_CHECKS = 2

LINE_RE = re.compile(
    r'^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) (\S+): (.*)$'
)
STARVED_RE = re.compile(r'no \[ready\] roadmap feature')
# ovn_planner.sh follows a starvation line with its OWN separate "sent needs-research
# reminder" confirmation line for the same repo (2026-09-23, found live: shrike-notify
# had been starving since 05:37, unbroken, but this script reported 1.4h because that
# reminder-sent line does not itself contain "no [ready] roadmap feature" and was
# wrongly read as a resolved/healthy event, resetting the streak). It is a SIDE EFFECT
# of continued starvation, not a resolution - treat it the same as the starvation line
# itself, not as a streak-breaker.
NON_BREAKING_RE = re.compile(r'sent needs-research reminder')
# what ovn_planner.sh logs when it decomposes a roadmap feature into backlog items ("planned N items" is the older/synthetic spelling)
DECOMP_RE = re.compile(r'appended \d+ 27B-decomposed items|marked feature \[decomposed\]|\bplanned \d+ items?')


def parse_ts(s):
    try:
        return time.mktime(time.strptime(s, "%Y-%m-%d %H:%M:%S"))
    except Exception:
        return None


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def pullable(repo):
    """Items the fleet can really take next for `repo` (None if the repo's backlog/checkout is not on this box)."""
    bl = os.path.join(OVN_DIR, "backlog", repo + ".md")
    root = os.path.join(OVN_DIR, "repos", repo)
    if not os.path.isfile(bl) and not os.path.isdir(root):
        return None
    bt = _read(bl)
    pt = _read(os.path.join(root, "OVERNIGHT_PROGRESS.md"))
    dt = _read(os.path.join(root, "OVERNIGHT_DONE.md"))
    sup = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ovn_work_supply.py")
    try:
        spec = importlib.util.spec_from_file_location("ovn_work_supply_for_trigger", sup)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.pullable_count(bt, pt, dt)
    except Exception:  # supply module missing/broken: plain count of open, un-held backlog T-items
        held = re.compile(r"HUMAN-ONLY|AUTO-SKIP|BLOCKED ITEM|\(retired-|\[CLAUDE\]")
        return sum(1 for l in (bt + "\n" + pt).split("\n") if re.match(r"^- \[ \] \[T[1-5]\]", l) and not held.search(l))


def load_streaks():
    try:
        with open(STREAK_STATE) as f:
            d = json.load(f)
        return d if isinstance(d, dict) else {}
    except (OSError, ValueError):
        return {}


def main():
    try:
        with open(LOG) as f:
            lines = f.readlines()
    except FileNotFoundError:
        print("")
        return

    by_repo = {}
    for ln in lines:
        m = LINE_RE.match(ln.strip())
        if not m:
            continue
        ts_s, repo, rest = m.groups()
        t = parse_ts(ts_s)
        if t is None:
            continue
        is_starved_signal = bool(STARVED_RE.search(rest) or NON_BREAKING_RE.search(rest))
        kind = "starved" if is_starved_signal else ("decomp" if DECOMP_RE.search(rest) else "other")
        by_repo.setdefault(repo, []).append((t, is_starved_signal, kind))

    now = time.time()
    starving = []
    streaks = load_streaks() if MONOTONIC else {}
    for repo, events in by_repo.items():
        events.sort(key=lambda e: e[0])
        if not MONOTONIC:
            if not events or not events[-1][1]:
                continue  # most recent check for this repo was healthy — not starving now
            # Walk backward to find when the current unbroken "starved" streak began.
            streak_start = events[-1][0]
            for t, is_starved, _k in reversed(events):
                if not is_starved:
                    break
                streak_start = t
            hours = (now - streak_start) / 3600.0
            if hours >= STARVE_HOURS:
                starving.append({"repo": repo, "starving_since": streak_start, "hours": round(hours, 1)})
            continue
        st = streaks.setdefault(repo, {})
        last_decomp = max((t for t, _s, k in events if k == "decomp"), default=0)
        floor = max(last_decomp, st.get("cleared_after", 0))
        starved_ts = [t for t, _s, k in events if k == "starved" and t > floor]
        n = pullable(repo)
        if n is not None:
            st["pull_hi"] = st.get("pull_hi", 0) + 1 if n > PULLABLE_MIN else 0
            if st["pull_hi"] >= PULLABLE_CHECKS:
                st["pull_hi"] = 0
                if starved_ts:
                    st["cleared_after"] = now
                    starved_ts = []
        if not starved_ts:
            continue
        streak_start = min(starved_ts)  # monotonic: later starved lines never move it, healthy-looking lines never reset it
        hours = (now - streak_start) / 3600.0
        if hours >= STARVE_HOURS:
            rec = {"repo": repo, "starving_since": streak_start, "hours": round(hours, 1)}
            if n is not None:
                rec["pullable"] = n
            starving.append(rec)

    starving.sort(key=lambda r: -r["hours"])
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        json.dump({"checked_at": now, "starving": starving}, f, indent=2)
    if MONOTONIC:
        try:
            tmp = STREAK_STATE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(streaks, f, indent=2)
            os.replace(tmp, STREAK_STATE)
        except OSError:
            pass

    if starving:
        summary = ", ".join(f"{r['repo']} ({r['hours']}h)" for r in starving)
        print(f"{len(starving)} repo(s) starving >= {STARVE_HOURS}h: {summary}")
    else:
        print("")


if __name__ == "__main__":
    main()
