#!/usr/bin/env python3
"""Per-commit helper for ovn_citation_check.sh — flags backlog items that cite a file
that does not exist anywhere in the repo (a hallucinated-path/filename bug from the
research/decompose pass, distinct from ovn_backlog_format_check.sh's header-only bug
and ovn_verify_direction_check.sh's always-true bug).

A backlog line's own leading path (e.g. "[T2] path/to/NewTest.kt — Create this new
test file...") is the item's CREATION TARGET and is deliberately never checked here —
it is expected to not exist yet. What this checks is every OTHER file the item's own
description leans on as already existing (e.g. "...mirroring AuthRepositoryTest.kt's
mockk pattern" or "...covering TopicsViewModel.kt's methods") — these are frequently
referenced by bare filename only (the research pass names the pattern, not its full
path), so existence is checked by filename anywhere in the repo tree (`find -name`),
not by an exact relative path.

Three false-positive shapes found live against real production backlog history
(2026-09-23, first full-history run: 43 hits -> 10 -> down further with these) and
filtered here rather than left for a human to keep re-discovering:
  1. VERIFY: clauses name a test file the model is expected to CREATE while landing
     this item (e.g. "VERIFY: pytest tests/test_foo.py::test_bar") - not a pre-existing
     pattern. Dropped entirely before scanning (was 38 of the first 43 hits).
  2. Deletion/removal items ("Delete the test file for the now-deleted X.py", "already
     deleted in an earlier commit") correctly report the referenced file as gone - that
     IS the item's premise, not a hallucination. Skipped via delete/deleted/removed/
     removal keyword match on the item body.
  3. Sibling items in the SAME commit/batch often create the file another item in that
     batch references ahead of time (e.g. one item wires a route to CodeInsightsPage.vue,
     the very next item in the same commit creates CodeInsightsPage.vue). Checked by
     collecting every sibling line's own target basename in the same commit before
     flagging anything.

Usage: ovn_citation_check.py <repo_dir> < commit_added_lines.txt
(one "+- [ ] [T#] ..." line per line, all lines added in ONE commit's backlog diff)
Prints one "<original line>\tMISSING: <filename>" per citation that survives all
three filters (tab-separated so the shell driver can build a report without a second
parse pass); prints nothing if clean. Never raises on malformed input — this is a
shadow/alert-only check, a false negative here just means one fewer citation flagged,
never a block or a crash.
"""
import os
import re
import subprocess
import sys

PATH_RE = re.compile(
    r'\b[\w][\w./-]*\.(?:py|ts|tsx|js|jsx|vue|kt|java|swift|gd|go|rs|rb|php|css|scss|html)\b'
)
DELETE_RE = re.compile(r'\b(delete|deleted|removed|removal)\b', re.IGNORECASE)


def find_by_basename(repo_dir, basename):
    try:
        out = subprocess.run(
            ["find", repo_dir, "-name", basename, "-not", "-path", "*/node_modules/*",
             "-not", "-path", "*/.venv/*", "-not", "-path", "*/.git/*"],
            capture_output=True, text=True, timeout=10, check=False,
        )
        return bool(out.stdout.strip())
    except Exception:
        return True  # find failing is not evidence of a missing file — don't false-flag


def item_body(line):
    body = re.sub(r'^\+?- \[ \] \[T[1-5]\]\s*', '', line.strip())
    return re.split(r'\bVERIFY:', body, maxsplit=1)[0]


def main():
    if len(sys.argv) < 2:
        return
    repo_dir = sys.argv[1]
    raw_lines = [ln for ln in sys.stdin.read().splitlines() if ln.strip()]
    bodies = [(ln, item_body(ln)) for ln in raw_lines]
    sibling_targets = set()
    for _, body in bodies:
        m = PATH_RE.findall(body)
        if m:
            sibling_targets.add(os.path.basename(m[0]))

    for raw_line, body in bodies:
        if DELETE_RE.search(body):
            continue
        matches = PATH_RE.findall(body)
        if not matches:
            continue
        target = matches[0]
        seen = {target, os.path.basename(target)}
        for m in matches[1:]:
            base = os.path.basename(m)
            if base in seen:
                continue
            seen.add(base)
            if base in sibling_targets:
                continue
            if not find_by_basename(repo_dir, base):
                print(f"{raw_line}\tMISSING: {base} (referenced, not found anywhere in repo)")


if __name__ == "__main__":
    main()
