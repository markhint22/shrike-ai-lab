#!/usr/bin/env python3
"""Strip the leading <repo>/ prefix from backlog item paths so they are repo-root-relative
(what the runner + sanitizer expect). Run in the backlog dir. Idempotent.

Bug: items were authored as `- [ ] [T2] xlite/scripts/foo.gd — ...` but the pipeline works
INSIDE repos/xlite, where the file is `scripts/foo.gd`. The literal `xlite/scripts/foo.gd`
doesn't exist from the repo root, so ovn_retire_vague.py retired them all as dead-path.
"""
import os, re, glob, sys

backlog_dir = sys.argv[1] if len(sys.argv) > 1 else "."
total = 0
for path in sorted(glob.glob(os.path.join(backlog_dir, "*.md"))):
    repo = os.path.splitext(os.path.basename(path))[0]
    # strip the leading "<repo>/" that immediately follows the tier tag on an item line
    pat = re.compile(r"^(- \[ \] \[(?:T[1-5]|CLAUDE|HUMAN)\] )" + re.escape(repo) + r"/")
    lines = open(path, encoding="utf-8").read().splitlines()
    out, n = [], 0
    for ln in lines:
        new = pat.sub(r"\1", ln)
        if new != ln:
            n += 1
        out.append(new)
    if n:
        open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
        print(f"  {repo}.md: stripped '{repo}/' prefix from {n} items")
        total += n
print(f"total items fixed: {total}")
