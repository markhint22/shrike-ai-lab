#!/usr/bin/env python3
"""Target-path sanity check for a queue item that is about to be credited as already done.

An item's own LEADING path (`- [ ] [T3] path/to/file.ext - ...`) must make sense for the claim "already satisfied":
a create/modify item whose target file does not exist cannot be satisfied; a delete/remove item whose target still exists
is not satisfied either. Used by BOTH credit paths (ovn_credit_already_satisfied.sh and the scout-verified ALREADY-DONE
credit in run_overnight.sh) - 2026-09-30, after the credit audit found ~15% of historic credits wrong.

usage: ovn_path_gate.py <progress_file> <line_number> [<repo_dir>]
stdout: OK <target> | MISSING <target> | STILL_EXISTS <target> | NA
"""
import os
import re
import sys

CODE = (".py", ".ts", ".tsx", ".js", ".vue", ".kt", ".gd", ".swift", ".sh", ".sql", ".json", ".yml", ".yaml", ".toml", ".html")
DELETE = re.compile(r"(?i)^(delete|remove|drop|prune|retire)\b")


def leading_body(line):
    """The item text with the checkbox / (tags) / [T2] prefixes stripped."""
    body = re.sub(r"^- \[[ xX]\] ", "", line.strip())
    body = re.sub(r"^\([^)]*\) ", "", body)
    return re.sub(r"^(\[[^\]]*\]\s*)+", "", body)


def leading_target(line):
    """The item's own named path token (first word of the body), no backticks / :line suffix."""
    body = leading_body(line)
    return (body.split(" ")[0] if body else "").replace("`", "").split(":")[0]


def check(line, repo_dir="."):
    body = leading_body(line)
    tgt = leading_target(line)
    if not tgt.endswith(CODE) or "*" in tgt or "?" in tgt or "[" in tgt or tgt.startswith(("http", "/")):
        return ("NA", "")
    desc = re.sub(r"^[^ ]+\s*(—|-|–)?\s*", "", body)[:120]
    exists = os.path.exists(os.path.join(repo_dir, tgt))
    if DELETE.match(desc):
        return ("STILL_EXISTS" if exists else "OK", tgt)
    return ("OK" if exists else "MISSING", tgt)


def main():
    if len(sys.argv) < 3:
        print("NA")
        return
    prog, ln = sys.argv[1], int(sys.argv[2])
    repo = sys.argv[3] if len(sys.argv) > 3 else os.path.dirname(os.path.abspath(prog))
    try:
        line = open(prog, errors="replace").read().split("\n")[ln - 1]
    except (OSError, IndexError):
        print("NA")
        return
    res, tgt = check(line, repo)
    print(res + (" " + tgt if tgt else ""))


if __name__ == "__main__":
    main()
