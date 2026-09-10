#!/usr/bin/env python3
"""ovn_park_sweep.py — relocate AUTO-SKIP/HUMAN-ONLY parked items out of the active flow.

The scout+implement loop shows the model the whole OVERNIGHT_PROGRESS.md and lets it pick the
next item top-down; it does NOT mechanically skip parked (AUTO-SKIP/HUMAN-ONLY-tagged) lines
itself. When one of these ends up as the first open line — which happens naturally as items
above it get completed over time — EVERY cycle wastes a full model call correctly reporting
"BLOCKED" before ever reaching real work. Confirmed 2026-09-09: xlite alone burned 73 such
calls (~2.5M tokens) over 3 days on a single stuck line (scripts/battle/battle.gd, hard-banned
for automated agents); at time of discovery 5 of 7 active repos had a parked item sitting as
their very first open line.

Moves every open AUTO-SKIP/HUMAN-ONLY line found ABOVE the "### Parked" holding-pen header
(creating it if absent) to below that header, at the end of the file. Idempotent: once
relocated, an item sits below the header and is never re-matched by a later sweep — only
newly-drifted parked items above the boundary get moved on each run.

Usage: ovn_park_sweep.py <progress_file>
Prints: SWEPT=<n moved>
"""
import sys, re, datetime

PARK_HEADER = "### Parked (AUTO-SKIP/HUMAN-ONLY sweep — needs Claude/human review, not attempted by the 27B)"
PARK_TAG = re.compile(r"^- \[ \] \[(AUTO-SKIP|HUMAN-ONLY)")


def main():
    if len(sys.argv) != 2:
        print("usage: ovn_park_sweep.py <progress_file>", file=sys.stderr)
        sys.exit(2)
    path = sys.argv[1]
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        print("SWEPT=0")
        return

    header_idx = next((i for i, l in enumerate(lines) if l.startswith(PARK_HEADER)), None)
    boundary = header_idx if header_idx is not None else len(lines)
    above, below = lines[:boundary], lines[boundary:]

    moved = [l for l in above if PARK_TAG.match(l)]
    if not moved:
        print("SWEPT=0")
        return

    kept_above = [l for l in above if not PARK_TAG.match(l)]
    stamp = datetime.date.today().isoformat()
    if header_idx is None:
        below = ["", f"{PARK_HEADER} — last swept {stamp}"]
    else:
        below[0] = f"{PARK_HEADER} — last swept {stamp}"

    out = kept_above + below + moved
    open(path, "w", encoding="utf-8").write(("\n".join(out)).rstrip() + "\n")
    print(f"SWEPT={len(moved)}")


if __name__ == "__main__":
    main()
