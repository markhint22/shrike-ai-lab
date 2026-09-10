#!/usr/bin/env python3
"""Strip a leading "<repo>/" prefix from open queue-item paths in a file, making them
repo-root-relative. Usage: strip_repo_prefix.py <repo> <file>. Prints STRIPPED=<n>."""
import re, sys
repo, path = sys.argv[1], sys.argv[2]
pat = re.compile(r"^(- \[ \] \[(?:T[1-5]|CLAUDE|HUMAN)[^\]]*\] )" + re.escape(repo) + r"/")
lines = open(path, encoding="utf-8").read().splitlines()
out, n = [], 0
for ln in lines:
    new = pat.sub(r"\1", ln)
    if new != ln:
        n += 1
    out.append(new)
if n:
    open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
print(f"STRIPPED={n}")
