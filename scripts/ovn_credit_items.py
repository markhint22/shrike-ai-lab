#!/usr/bin/env python3
"""Item bookkeeping helpers for the runner's auto-credit (lib_auto_credit.sh), 2026-10-02.

  ovn_credit_items.py list <progress_file>
      one line per OPEN, non-blocked item that names a leading path:  <line-number>\\t<path-token>
  ovn_credit_items.py tick <progress_file> <line-number>
      flips ONLY that line from "- [ ] " to "- [x] " (prints TICKED, or REFUSED when the line is not an open checkbox)
  ovn_credit_items.py bare-verify <progress_file> <line-number>
      the runnable command of an item's UNBACKTICKED `VERIFY: <cmd>[.] (cat:` clause (2026-10-10, IPTV-2): lib_verify_clause.sh shadow_check only read the backticked
      form, so 56 of 99 live iptv items (and the xlite get_max_directive_value T1/T2 pair) read as NO_VERIFY_CLAUSE and were credited on a path match alone. Prints the
      command only when ovn_spec_rules.bare_verify (the R01 safety test: known tool word, balanced quotes, no prose word) accepts it; prints NOTHING for a backticked
      clause, prose, or any error (the caller then keeps its old NO_VERIFY_CLAUSE answer).

The leading path is parsed by ovn_path_gate.leading_target (the same parse the path gate uses), so "the item's named file" means one
thing everywhere. Items marked HUMAN-ONLY / AUTO-SKIP / HARD FILE BAN / BLOCKED / [CLAUDE] are never listed.
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ovn_path_gate import leading_target  # noqa: E402

SKIP = re.compile(r"HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|(?-i:BLOCKED)|\[CLAUDE\]", re.I)
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


def bare_verify_of(prog, ln):
    try:
        with open(prog, errors="surrogateescape") as f:
            lines = f.read().split("\n")
        if ln < 1 or ln > len(lines):
            return ""
        import ovn_spec_rules
        b = ovn_spec_rules.bare_verify(lines[ln - 1])
        return b[1] if b else ""
    except Exception:  # noqa: BLE001 - any failure = no fallback (NO_VERIFY_CLAUSE, the old answer)
        return ""


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "bare-verify":
        try:
            print(bare_verify_of(sys.argv[2], int(sys.argv[3])))
        except ValueError:
            print("")
    elif len(sys.argv) >= 3 and sys.argv[1] == "list":
        for n, t in list_items(sys.argv[2]):
            print("%d\t%s" % (n, t))
    elif len(sys.argv) >= 4 and sys.argv[1] == "tick":
        print("TICKED" if tick(sys.argv[2], int(sys.argv[3])) else "REFUSED")
    else:
        print("usage: ovn_credit_items.py list <prog> | tick <prog> <line> | bare-verify <prog> <line>", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
