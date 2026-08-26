#!/usr/bin/env python3
"""Fix the STALE speed/budget framing in run_overnight.sh's task prompt. It told the
model it runs at ~5 tok/s with a ~3000-token 600s budget (true before the 8.5x tune);
now it's ~87 tok/s (~40k tokens/call), so the model was needlessly rushing minimal /
broken diffs. Update it to encourage complete, correct changes."""
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
before = s

OLD1 = ("This model generates at roughly 5 tokens/second on this box and each call is "
        "hard-killed at 600 seconds (~3000 tokens) - if you spend more than a few hundred "
        "tokens reasoning before writing the actual diff, the call WILL be killed with no "
        "commit and the cycle is wasted. Budget yourself: a couple sentences on what you're "
        "changing and why, then the diff.")
NEW1 = ("This model now runs at roughly 85 tokens/second on this box and each call is "
        "hard-killed at 600 seconds, so you have a budget of about 40000 tokens - plenty of "
        "room to read the files you actually need and write a COMPLETE, correct change. Do not "
        "rush out a half-finished or syntactically broken diff to save budget; a working change "
        "that fully implements the item is the goal. Still do not waste budget narrating - a "
        "couple sentences of plan, then write the full change and make sure it parses/compiles.")

OLD2 = ("when adding tests to a low/zero-coverage file, write 4-6 focused test cases covering "
        "the most important behavior and stop there, then mark real, partial progress (which "
        "file, how many methods still need coverage) rather than attempting the whole file and "
        "running out of budget with nothing committed.")
NEW2 = ("when adding tests to a low/zero-coverage file, write a solid batch of focused, correct "
        "test cases (you now have budget for roughly 10-15) covering the most important "
        "behavior; for a very large file, cover the top behaviors this cycle and note what "
        "still needs coverage rather than attempting every method at once.")

n = 0
if OLD1 in s: s = s.replace(OLD1, NEW1); n += 1
if OLD2 in s: s = s.replace(OLD2, NEW2); n += 1
if s == before:
    print("NO MATCH - text may have changed; nothing modified"); sys.exit(1)
open(p, "w", encoding="utf-8").write(s)
print(f"updated {n} block(s): 85 tok/s, ~40k budget, complete diffs")
