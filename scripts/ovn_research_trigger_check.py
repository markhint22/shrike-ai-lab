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

Usage: ovn_research_trigger_check.py [starve_hours=2] [log_path]
"""
import json
import os
import re
import sys
import time

STARVE_HOURS = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
LOG = sys.argv[2] if len(sys.argv) > 2 else os.path.expanduser("~/overnight-queue/logs/ovn_planner.log")
STATE = os.path.expanduser("~/overnight-queue/state/research_trigger_starving.json")

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


def parse_ts(s):
    try:
        return time.mktime(time.strptime(s, "%Y-%m-%d %H:%M:%S"))
    except Exception:
        return None


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
        by_repo.setdefault(repo, []).append((t, is_starved_signal))

    now = time.time()
    starving = []
    for repo, events in by_repo.items():
        events.sort(key=lambda e: e[0])
        if not events or not events[-1][1]:
            continue  # most recent check for this repo was healthy — not starving now
        # Walk backward to find when the current unbroken "starved" streak began.
        streak_start = events[-1][0]
        for t, is_starved in reversed(events):
            if not is_starved:
                break
            streak_start = t
        hours = (now - streak_start) / 3600.0
        if hours >= STARVE_HOURS:
            starving.append({"repo": repo, "starving_since": streak_start, "hours": round(hours, 1)})

    starving.sort(key=lambda r: -r["hours"])
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        json.dump({"checked_at": now, "starving": starving}, f, indent=2)

    if starving:
        summary = ", ".join(f"{r['repo']} ({r['hours']}h)" for r in starving)
        print(f"{len(starving)} repo(s) starving >= {STARVE_HOURS}h: {summary}")
    else:
        print("")


if __name__ == "__main__":
    main()
