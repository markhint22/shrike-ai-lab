#!/usr/bin/env python3
"""Stale-top-item detector (2026-09-23, age-source fixed 2026-09-28).

Root cause this closes: every cycle's prompt tells the model to "pick the single top
not-yet-done item", and run_overnight.sh's own context-budget logic (2026-09-19 fix)
GUARANTEES that item stays visible regardless of file position — but nothing verifies
the model actually complies. Found live on gitlark: a trivial T1 "delete this dead
stub file" item (line 1320 of a 1369-line OVERNIGHT_PROGRESS.md, the #1 of only 24
doable items, well within the visible context budget) sat untouched for 27+ hours
while the fleet burned ~500k+ tokens/cycle on unrelated schema/refactor/endpoint work
instead. ovn_item_guard.sh's own streak counters stayed empty the whole time — its
counters only track attempts that WERE against the top item, so it is structurally
blind to an item that is simply never picked at all.

Detection: for each repo, find the top doable item (same selector ovn_item_guard.sh
and run_overnight.sh's record_outcome() both already use) and its own target file
(the first path-looking token right after the tier tag — the file the item is about).
If that item has been sitting at the top of the backlog for longer than STALE_HOURS
(default 12 — deliberately higher than the 2h research-trigger threshold, since a hard
item legitimately taking a few hours of real attempts is a DIFFERENT, already-covered
problem, not "never touched"), check whether the target file has been committed to at
all in that same window (`git log --since`). Zero commits to the file it is supposedly
the top priority for, across that whole window, is the signal — a file WITH commits in
the window is presumably being actively iterated on even if not yet landed, and is
intentionally not flagged here.

**2026-09-28 bug fix**: staleness used to be measured via `git blame` on the roadmap
line in OVERNIGHT_PROGRESS.md — i.e. "when was this exact line last edited" — as a
proxy for "how long has this been the #1 pick". That proxy breaks the instant a bulk
edit (a backlog reformat/refill pass) touches many lines at once: every item that
LATER rotates into the #1 slot inherits that old shared blame timestamp and gets
reported as already "stale 100+ hours" the moment it first becomes #1, even though it
may have become #1 minutes earlier. Confirmed live: iptv_apps showed alerts for 7
different items across ~30 hours, several already claiming 107-113h of staleness on
their FIRST appearance, tracing back to a shared bulk-edit commit days earlier — not
to when each item actually became #1.

Fix: persist an actual "first observed as #1" timestamp per repo in
state/stale_top_item_first_seen_<repo>, keyed on the same "<line>:<text prefix>"
identity the sibling re-alert marker (state/stale_top_item_alerted_<repo>) already
uses. Each run: if the current #1 item's key matches the stored key, age = now minus
the stored first-seen time. If it does NOT match (a different item just rotated to
#1, or this is the first run ever), the clock resets to now — that item is not
alerted on this run (age 0), regardless of what git blame says about the line it
happens to occupy. This makes the metric mean what its own alert text claims
("ignoring its #1 item for N hours"), immune to unrelated bulk edits.

Never checks a DELETE item that has already been deleted (VERIFY would trivially
pass — that is a queue-hygiene gap for something else, not this).

Usage: ovn_stale_top_item_check.py <queue_root> [stale_hours=12] [repo1 repo2 ...]
Prints one line per genuinely stale item; nothing if clean.
"""
import os
import re
import subprocess
import sys
import time

QUEUE_ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/overnight-queue")
STALE_HOURS = float(sys.argv[2]) if len(sys.argv) > 2 else 12.0
REPOS = sys.argv[3:] or [
    "billwatch", "gitlark", "iptv_apps", "test-automation-agent",
    "xlite", "shrike-notify", "shrike-monitor",
]

def _active_repos(queue_root):
    """Repos with at least one ENABLED lane in tasks.json (None if unreadable -> check every repo, the old behaviour). A repo whose lanes are all disabled
    (billwatch, gitlark, ... while Chickadee + xlite are the only dev lanes) is not ignoring its #1 item - nobody is working on it - so reporting
    'stale 133h' for it every hour was pure noise in the hourly update."""
    try:
        import json
        tasks = json.load(open(os.path.join(queue_root, "tasks.json")))
        return {os.path.basename(str(t.get("repo", ""))) for t in tasks if t.get("enabled") is True}
    except Exception:
        return None


if not sys.argv[3:]:
    _act = _active_repos(QUEUE_ROOT)
    if _act:
        REPOS = [r for r in REPOS if r in _act]

TOP_EXCLUDE_RE = re.compile(r'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]', re.IGNORECASE)
PATH_RE = re.compile(r'\[T[1-5]\]\s+([\w./-]+\.\w+)')


def run(args, cwd=None, timeout=15):
    try:
        return subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                               timeout=timeout, check=False)
    except Exception:
        return None


def find_top_item(repo_dir):
    prog = os.path.join(repo_dir, "OVERNIGHT_PROGRESS.md")
    if not os.path.isfile(prog):
        return None
    with open(prog, encoding="utf-8", errors="ignore") as f:
        for i, line in enumerate(f, start=1):
            if not line.startswith("- [ ]"):
                continue
            if TOP_EXCLUDE_RE.search(line):
                continue
            return i, line.strip()
    return None


def item_key(lineno, text):
    # same identity shape ovn_stale_top_item_check.sh's re-alert marker already uses:
    # "<line>:<first-60-chars-of-text>" — stable across runs as long as the SAME item
    # holds the #1 slot, and guaranteed to change the moment a different item rotates in.
    return f"{lineno}:{text[:60]}"


def first_seen_age_hours(repo, key, now, state_dir):
    """Persisted 'how long has THIS item been #1' clock — replaces the old git-blame
    proxy. Returns age in hours since this exact key was first observed as #1. If the
    key doesn't match what's stored (new item rotated in, or no prior state), resets
    the clock to now and returns 0 — never alerts a freshly-rotated-in item just
    because it happens to sit on an old, previously-bulk-edited line."""
    path = os.path.join(state_dir, f"stale_top_item_first_seen_{repo}")
    stored_key = None
    stored_ts = None
    try:
        with open(path, encoding="utf-8") as f:
            raw = f.read().strip()
        if "|" in raw:
            k, ts_str = raw.rsplit("|", 1)
            stored_key, stored_ts = k, float(ts_str)
    except (FileNotFoundError, ValueError, OSError):
        pass
    if stored_key != key or stored_ts is None:
        stored_ts = now
        try:
            with open(path, "w", encoding="utf-8") as f:
                f.write(f"{key}|{now}")
        except OSError:
            pass
    return (now - stored_ts) / 3600.0


def file_touched_since(repo_dir, target, since_hours):
    if not target:
        return True  # no clean target parsed — don't false-flag on a parsing gap
    out = run(["git", "log", f"--since={since_hours} hours ago", "--oneline", "--", target],
               cwd=repo_dir)
    if out is None:
        return True  # git failing is not evidence of staleness
    return bool(out.stdout.strip())


def main():
    now = time.time()
    state_dir = os.path.join(QUEUE_ROOT, "state")
    try:
        os.makedirs(state_dir, exist_ok=True)
    except OSError:
        pass
    for repo in REPOS:
        repo_dir = os.path.join(QUEUE_ROOT, "repos", repo)
        if not os.path.isdir(repo_dir):
            continue
        top = find_top_item(repo_dir)
        if not top:
            continue
        lineno, text = top
        key = item_key(lineno, text)
        age_h = first_seen_age_hours(repo, key, now, state_dir)
        if age_h < STALE_HOURS:
            continue
        m = PATH_RE.search(text)
        target = m.group(1) if m else None
        if file_touched_since(repo_dir, target, STALE_HOURS):
            continue
        short = text[:140]
        print(f"{repo}\t{age_h:.1f}\t{lineno}\t{short}")


if __name__ == "__main__":
    main()
