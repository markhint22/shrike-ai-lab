#!/usr/bin/env python3
"""Move completed `- [x]` items out of CLAUDE_QUEUE.md into CLAUDE_QUEUE_DONE.md, so the
live queue stays scannable as it accumulates months of history (mirrors archive_done.py's
role for OVERNIGHT_PROGRESS.md). Keeps all non-`[x]` lines (headers, open items, narrative)
in the live queue; appends the `[x]` lines to the archive verbatim, in order.

Safe for claude_queue_bridge.py's dedup: harvest/signatures both accept --archive and read
archived items' signatures too, so moving an item here does NOT make the harvester think it's
new again. Do not archive by any other means (hand-deleting, moving to a different file) —
that bypasses the dedup fix and reproduces the duplication bug this pipeline had before.

Prints MOVED=<n> KEPT_OPEN=<n>.

Usage: archive_claude_queue_done.py <queue_file> <archive_file>
"""
import sys
import re
import datetime

queue, archive = sys.argv[1], sys.argv[2]
lines = open(queue, encoding="utf-8").read().splitlines()
done_re = re.compile(r"^\s*- \[[xX]\]")
kept, moved = [], []
for ln in lines:
    (moved if done_re.match(ln) else kept).append(ln)
if not moved:
    print("MOVED=0 KEPT_OPEN=%d" % sum(1 for l in kept if l.strip().startswith("- [ ]")))
    sys.exit(0)
open(queue, "w", encoding="utf-8").write("\n".join(kept).rstrip() + "\n")
stamp = datetime.date.today().isoformat()
with open(archive, "a", encoding="utf-8") as f:
    f.write(f"\n<!-- archived {stamp}: {len(moved)} completed items moved out of CLAUDE_QUEUE.md -->\n")
    f.write("\n".join(moved) + "\n")
open_n = sum(1 for l in kept if l.strip().startswith("- [ ]"))
print(f"MOVED={len(moved)} KEPT_OPEN={open_n}")
