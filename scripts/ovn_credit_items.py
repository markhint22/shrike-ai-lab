#!/usr/bin/env python3
"""Item bookkeeping helpers for the runner's auto-credit (lib_auto_credit.sh), 2026-10-02.

  ovn_credit_items.py list <progress_file>
      one line per OPEN, non-blocked item that names a leading path:  <line-number>\\t<path-token>
  ovn_credit_items.py tick <progress_file> <line-number>
      flips ONLY that line from "- [ ] " to "- [x] " (prints TICKED, or REFUSED when the line is not an open checkbox)

The leading path is parsed by ovn_path_gate.leading_target (the same parse the path gate uses), so "the item's named file" means one
thing everywhere. Items marked HUMAN-ONLY / AUTO-SKIP / HARD FILE BAN / BLOCKED / [CLAUDE] are never listed.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ovn_path_gate import leading_target  # noqa: E402

SKIP = re.compile(r"HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]", re.I)
OPEN = re.compile(r"^- \[ \] ")


def list_items(prog):
    out = []
    with open(prog, errors="surrogateescape") as f:
        for n, line in enumerate(f.read().split("\n"), 1):
            if not OPEN.match(line) or SKIP.search(line):
                continue
            tgt = leading_target(line)
            if not tgt or tgt.startswith(("http", "/")) or any(c in tgt for c in "*?[]"):
                continue
            if "/" not in tgt and "." not in tgt:
                continue
            out.append((n, tgt))
    return out


def tick(prog, ln):
    with open(prog, errors="surrogateescape") as f:
        lines = f.read().split("\n")
    if ln < 1 or ln > len(lines) or not OPEN.match(lines[ln - 1]):
        return False
    lines[ln - 1] = "- [x] " + lines[ln - 1][len("- [ ] "):]
    with open(prog, "w", errors="surrogateescape") as f:
        f.write("\n".join(lines))
    return True


def main():
    if len(sys.argv) >= 3 and sys.argv[1] == "list":
        for n, t in list_items(sys.argv[2]):
            print("%d\t%s" % (n, t))
    elif len(sys.argv) >= 4 and sys.argv[1] == "tick":
        print("TICKED" if tick(sys.argv[2], int(sys.argv[3])) else "REFUSED")
    else:
        print("usage: ovn_credit_items.py list <prog> | tick <prog> <line>", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
