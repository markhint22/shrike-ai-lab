#!/usr/bin/env python3
# Unjam the queue: move every TAGGED open item (HUMAN-ONLY / AUTO-SKIP / BLOCKED ITEM)
# out of its position and append it under a "Parked" section at EOF, so doable
# open items float to the top and the runner's scout stops no-op'ing on a blocked
# top item. Done items ([x]) and section headers are untouched.
import re, sys
p = "OVERNIGHT_PROGRESS.md"
lines = open(p, encoding="utf-8").read().splitlines(keepends=True)
TAG = re.compile(r"HUMAN-ONLY|AUTO-SKIP|BLOCKED ITEM")
kept, parked = [], []
for l in lines:
    if l.startswith("- [ ]") and TAG.search(l):
        parked.append(l)
    else:
        kept.append(l)
if not parked:
    print("nothing to sink"); sys.exit(0)
# strip any prior parked section so this is idempotent
MARK = "## Parked — auto-skipped / human-only (sunk to keep doable work on top)\n"
out = []
skip = False
for l in kept:
    if l == MARK:
        skip = True; continue
    if skip and (l.startswith("## ") and l != MARK):
        skip = False
    if not skip:
        out.append(l)
if not out[-1].endswith("\n"):
    out[-1] += "\n"
out.append("\n" + MARK)
out.extend(parked)
open(p, "w", encoding="utf-8").write("".join(out))
print(f"sank {len(parked)} tagged items to a Parked section at EOF")
