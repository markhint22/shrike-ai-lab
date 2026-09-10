#!/usr/bin/env python3
"""Planner + queue_refill activity summary for the ntfy digest.

Both ovn_planner.sh and queue_refill.sh run at the end of EVERY fleet cycle (not just
their standalone hourly/half-hourly cron backstops), so a busy 3h window can hold 5-10+
runs per repo. Rather than list every run, this reports:
  - real activity in the window (items decomposed / refilled, and for which repos) —
    proof the mechanism is actually doing something, not just idling
  - the CURRENT stuck state (each repo's most-recent line in the window) — which repos
    are dry with nothing left to pull AND no [ready] roadmap feature to decompose, i.e.
    genuinely need a human/Claude to add roadmap work, not a transient blip

Usage: ovn_planning_stats.py [hours=3]
Prints an empty string if neither log has activity in the window.
"""
import os
import re
import sys
import time
from datetime import datetime

DIR = os.path.expanduser("~/overnight-queue")
hours = float(sys.argv[1]) if len(sys.argv) > 1 else 3.0
cutoff = time.time() - hours * 3600

LOCAL_TZ = datetime.now().astimezone().tzinfo


def read_window(path):
    """Yield (epoch, repo, rest) for each 'YYYY-MM-DD HH:MM:SS repo: rest' line in the window."""
    if not os.path.exists(path):
        return
    pat = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) ([A-Za-z0-9_-]+): (.*)$")
    for ln in open(path, encoding="utf-8", errors="ignore"):
        m = pat.match(ln.strip())
        if not m:
            continue
        try:
            dt = datetime.strptime(m.group(1), "%Y-%m-%d %H:%M:%S").replace(tzinfo=LOCAL_TZ)
        except ValueError:
            continue
        ts = dt.timestamp()
        if ts < cutoff:
            continue
        yield ts, m.group(2), m.group(3)


# ---- planner: decomposition activity + "no ready feature" stuck state ----
decomposed = {}  # repo -> total items appended this window
planner_last = {}  # repo -> last line's rest-text (most recent status)
for ts, repo, rest in read_window(os.path.join(DIR, "logs", "ovn_planner.log")):
    m = re.match(r"appended (\d+) 27B-decomposed items", rest)
    if m:
        decomposed[repo] = decomposed.get(repo, 0) + int(m.group(1))
    if repo not in planner_last or ts >= planner_last[repo][0]:
        planner_last[repo] = (ts, rest)

# ---- refill: pull activity + "backlog DRY" stuck state ----
refilled = {}  # repo -> total items pulled this window
refill_last = {}
for ts, repo, rest in read_window(os.path.join(DIR, "logs", "queue_refill.log")):
    m = re.match(r"refilled \+(\d+)", rest)
    if m:
        refilled[repo] = refilled.get(repo, 0) + int(m.group(1))
    if repo not in refill_last or ts >= refill_last[repo][0]:
        refill_last[repo] = (ts, rest)

if not decomposed and not refilled and not planner_last and not refill_last:
    print("")
    sys.exit(0)

# a repo is genuinely STUCK if its most recent planner check says "no ready feature"
# AND its most recent refill check says the backlog is DRY - both mechanisms have
# nothing left to give it. Either alone is normal/transient.
stuck = sorted(
    repo for repo, (_, rest) in planner_last.items()
    if "no [ready] roadmap feature" in rest
    and repo in refill_last and "backlog DRY" in refill_last[repo][1]
)

lines = []
if decomposed or refilled:
    bits = []
    if decomposed:
        bits.append("decomposed " + ", ".join(f"{r} +{n}" for r, n in sorted(decomposed.items())))
    if refilled:
        bits.append("refilled " + ", ".join(f"{r} +{n}" for r, n in sorted(refilled.items())))
    lines.append("🗓 Planning: " + "; ".join(bits))
else:
    lines.append("🗓 Planning: no new items decomposed or refilled this window")

if stuck:
    lines.append(f"🔴 Stuck dry (no ready roadmap feature, nothing to refill): {', '.join(stuck)} — needs Claude to add roadmap work")

print("\n".join(lines))
