#!/usr/bin/env python3
"""Stale-top-item detector (2026-09-23).

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
`git blame` that exact line to find when it FIRST became the top item. If that is
older than STALE_HOURS (default 12 — deliberately higher than the 2h research-trigger
threshold, since a hard item legitimately taking a few hours of real attempts is a
DIFFERENT, already-covered problem, not "never touched"), check whether the target
file has been committed to at all in that same window (`git log --since`). Zero
commits to the file it is supposedly the top priority for, across that whole window,
is the signal — a file WITH commits in the window is presumably being actively
iterated on even if not yet landed, and is intentionally not flagged here.

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


def blame_time(repo_dir, lineno):
    out = run(["git", "blame", "-L", f"{lineno},{lineno}", "--porcelain", "OVERNIGHT_PROGRESS.md"],
               cwd=repo_dir)
    if not out or out.returncode != 0:
        return None
    for ln in out.stdout.splitlines():
        if ln.startswith("author-time "):
            try:
                return int(ln.split()[1])
            except (IndexError, ValueError):
                return None
    return None


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
    for repo in REPOS:
        repo_dir = os.path.join(QUEUE_ROOT, "repos", repo)
        if not os.path.isdir(repo_dir):
            continue
        top = find_top_item(repo_dir)
        if not top:
            continue
        lineno, text = top
        ts = blame_time(repo_dir, lineno)
        if ts is None:
            continue
        age_h = (now - ts) / 3600.0
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
