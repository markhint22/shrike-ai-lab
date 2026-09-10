#!/usr/bin/env python3
"""Move completed `- [x]` items out of OVERNIGHT_PROGRESS.md into OVERNIGHT_DONE.md, so the
read-only progress file fed to the model each cycle stays small. A bloated progress file
(xlite hit 788 lines ≈ 40K tokens) blows the 55K input limit -> ContextWindowExceeded ->
the repo can never do any work. Keeps all non-`[x]` lines (headers, open items, comments)
in progress; appends the `[x]` lines to the archive. Prints MOVED=<n> KEPT=<n>.

Usage: archive_done.py <progress_file> <archive_file>
"""
import sys, re, datetime
prog, arch = sys.argv[1], sys.argv[2]
lines = open(prog, encoding="utf-8").read().splitlines()
done_re = re.compile(r"^\s*- \[x\]", re.I)
kept, moved = [], []
for ln in lines:
    (moved if done_re.match(ln) else kept).append(ln)
if not moved:
    print("MOVED=0 KEPT=%d" % sum(1 for l in kept if l.strip().startswith("- [")))
    sys.exit(0)
open(prog, "w", encoding="utf-8").write("\n".join(kept).rstrip() + "\n")
stamp = datetime.date.today().isoformat()
with open(arch, "a", encoding="utf-8") as f:
    f.write(f"\n<!-- archived {stamp}: {len(moved)} completed items moved out of OVERNIGHT_PROGRESS.md -->\n")
    f.write("\n".join(moved) + "\n")
open_n = sum(1 for l in kept if l.strip().startswith("- [ ]"))
print(f"MOVED={len(moved)} KEPT_OPEN={open_n}")
