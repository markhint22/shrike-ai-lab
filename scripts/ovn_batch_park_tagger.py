#!/usr/bin/env python3
"""Applies an AUTO-SKIP park tag to a chronically-F batch's straggler items
(2026-09-25). Companion to ovn_batch_stragglers.py (finds candidates) and
ovn_batch_park_stragglers.sh (drives this against a worktree, commits, pushes,
alerts, and tracks dedup so a batch is only ever processed once).

Uses the exact same reversible convention as ovn_item_guard.sh's own AUTO-SKIP
tagging: prepend a bracketed marker right after "- [ ] " and leave the checkbox
itself unchecked. run_overnight.sh's existing doable-item picker already
excludes any line containing "AUTO-SKIP" (case-insensitive) from pickup — no
runner changes needed, and reversing this is a one-line manual edit (delete the
bracketed prefix) rather than a data-losing operation.

Usage: ovn_batch_park_tagger.py <progress_md_path> <batch_json_path>
<batch_json_path> is one line of ovn_batch_stragglers.py's JSONL output for a
single batch (repo/tag/landed/n/pct/stragglers). Prints the number of lines
actually tagged (0 if none of the given straggler texts were found unchanged,
e.g. because a previous run already tagged them).
"""
import json
import sys

path, batch_json_path = sys.argv[1], sys.argv[2]
with open(batch_json_path) as f:
    batch = json.load(f)

tag = batch["tag"]
landed, n, pct = batch["landed"], batch["n"], batch["pct"]
straggler_set = set(batch["stragglers"])
marker = f"[AUTO-SKIP batch-graded-F — {tag} landed {landed}/{n} ({pct}%); review] "

lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
new_lines = []
tagged = 0
for ln in lines:
    if ln.startswith("- [ ] "):
        text = ln[len("- [ ] "):]
        if text in straggler_set and "AUTO-SKIP" not in ln:
            new_lines.append("- [ ] " + marker + text)
            tagged += 1
            continue
    new_lines.append(ln)

if tagged:
    open(path, "w", encoding="utf-8").write("\n".join(new_lines))
print(tagged)
