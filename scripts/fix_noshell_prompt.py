#!/usr/bin/env python3
"""Add a NO-SHELL directive to the task prompt. Logs show the model burning whole
cycles on 'let me run the tests / check pytest / cd && cat ...' — it has no shell,
so it loops on setup/verification and commits nothing (no-op). Tell it plainly:
you can't run anything, just read the target file and write the fix; the runner
runs the tests after you commit."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
before = s

ANCHOR = ("Be decisive: pick the files you need in ONE pass and stop - do not narrate a long "
          "chain of 'let me also check this file... and this one... and this one' before ever "
          "writing code.")
ADD = (" CRITICAL: you have NO shell and CANNOT run anything - never try to run the tests, "
       "pytest, npm, the app, or any command, and never write 'let me run the tests', 'let me "
       "check if it's importable', 'cd X && cat ...', or attempt to set up/inspect the "
       "environment. Doing so burns the entire call and commits NOTHING (the #1 cause of wasted "
       "no-op cycles). The runner automatically runs the real test suite for you AFTER you "
       "commit, so you never need to verify by running - just open the specific file named in "
       "the item, make the code change, and let your commit stand.")

if ANCHOR not in s:
    print("ANCHOR not found; nothing modified"); sys.exit(1)
if "you have NO shell and CANNOT run anything" in s:
    print("already present"); sys.exit(0)
s = s.replace(ANCHOR, ANCHOR + ADD, 1)
open(p, "w", encoding="utf-8").write(s)
print("no-shell directive added")
