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
      clause, prose, or any error (the caller then keeps its old NO_VERIFY_CLAUSE answer). 2026-10-12 (R14): also a bare `<grep|ls|test cmd> returns no results` clause (negative
      narration, bare_verify_neg) - read it together with `polarity`.
  ovn_credit_items.py polarity <progress_file> <line-number>
      `neg grep` | `neg exit` | `pos` | `unknown`: the stated polarity of the item's VERIFY (ovn_backlog_eligibility.verify_polarity) and the class of its last command. shadow_check inverts
      the verdict for `neg` (an absence check: grep passes on rc 1, ls/test on any other non-zero), so an item is credited only when the command's exit status matches the stated polarity.

  ovn_credit_items.py canon <progress_file> <line-number>        (2026-10-12, uidcredit) the canonical identity text of one line (see canon_item)
  ovn_credit_items.py twins <progress_file> <line-number>        line numbers of the OTHER open, non-parked items whose canonical text equals that line's
  ovn_credit_items.py tick-twins <progress_file> <line-number> [on|shadow|off]
      after line N was credited by a verified path, credit its identical open twins too (so the runner does not re-serve the still-open copy). Prints
      "TICKED <n>" (mode on, default), "SHADOW <n> <lines>" (mode shadow: nothing edited), "OFF 0".
  ovn_credit_items.py filter-new <file>...                        stdin = candidate item lines; prints those whose canonical text is in NONE of the files'
      items and not already printed (refill/planner-time dedupe: never append an item that already exists in any section, open, done or parked)

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


# --- canonical identity of an item line (2026-10-12, package uidcredit) ---------------------------------------------------------------------------------------------
# ONE definition of "the same item" for refill dedupe, planner dedupe and twin crediting. Two lines are the same item when everything the runner or a human ADDED around the
# item text is removed: the checkbox, leading annotations `(already-done, scout-verified)` / `(pre-verified done ...)` (balanced parentheses: they nest), leading state tags
# `[AUTO-SKIP ...]` `[CLAUDE]` `[unworkable: ...]` `[HUMAN-ONLY ...]` (balanced brackets), the tier tag `[T1-5]` (a retier is not a different item), the YYYYMMDD / MMDDYY stamp inside
# `[feat:...]` (a regeneration of the same feature mints a new date; same rule as ovn_item_hash and queue_refill), backticks, case and whitespace; the R11 GUT path rewrite of
# the VERIFY clause is applied so a rewritten copy equals its old copy. queue_refill.py used to compare only "everything after the first ]" - which kept a done line's
# `(annotation)` prefix, so a re-shipped copy of a retired/credited item looked brand new and was pulled again (the 2026-10-07 churn-loop shape).
_TIER_TAG = re.compile(r"^\[T[1-5]\]\s*")
_FEAT_DATE8 = re.compile(r"-\d{8}-")
_FEAT_DATE6 = re.compile(r"-\d{6}-")


def _balanced_end(t, o, c):
    """Index of the bracket closing the one at t[0], honouring nesting; -1 when unbalanced."""
    depth = 0
    for i, ch in enumerate(t):
        if ch == o:
            depth += 1
        elif ch == c:
            depth -= 1
            if depth == 0:
                return i
    return -1


def canon_item(line):
    t = re.sub(r"^\s*- \[[ xX]\]\s*", "", line or "", count=1)
    while True:
        t = t.lstrip()
        before = t
        m = _TIER_TAG.match(t)
        if m:
            t = t[m.end():]
        elif t.startswith("("):
            e = _balanced_end(t, "(", ")")
            if e > 0:
                t = t[e + 1:]
        elif t.startswith("[") and not t.startswith("[feat:"):
            e = _balanced_end(t, "[", "]")
            if e > 0:
                t = t[e + 1:]
        if t == before:
            break

    def _one(m):
        return _FEAT_DATE6.sub("-", _FEAT_DATE8.sub("-", m.group(0), count=1), count=1)
    t = re.sub(r"\[feat:[^\]]+\]", _one, t)
    # review fix (r15): GDScript identifiers and shell commands are CASE-SENSITIVE. Only the free prose is lowercased; the text inside `backticks` and the whole VERIFY clause keep
    # their case, so `Foo` / `foo` (or two VERIFY clauses differing only by case) are never twins.
    vi = t.find("VERIFY:")
    head, tail = (t[:vi], t[vi:]) if vi >= 0 else (t, "")
    head = re.sub(r"`([^`]*)`|([^`]+)", lambda m: m.group(1) if m.group(1) is not None else m.group(2).lower(), head).replace("`", "")
    tail = tail.replace("`", "").replace("addons/gut/cli/gut_cli.gd", "addons/gut/gut_cmdln.gd")
    return re.sub(r"\s+", " ", head + tail).strip()


def _is_item(line):
    return bool(re.match(r"^\s*- \[[ xX]\]", line))


def open_twins(prog, ln):
    """Line numbers (1-based) of OTHER open, non-parked items whose canon equals the canon of line `ln` (any checkbox state)."""
    with open(prog, errors="surrogateescape") as f:
        lines = f.read().split("\n")
    if ln < 1 or ln > len(lines) or not _is_item(lines[ln - 1]):
        return []
    want = canon_item(lines[ln - 1])
    if not want:
        return []
    return [n for n, l in enumerate(lines, 1) if n != ln and OPEN.match(l) and not SKIP.search(l) and canon_item(l) == want]


def tick_twins(prog, ln, mode="on"):
    """-> (n, [lines]); edits only in mode 'on'. A twin is ticked with an annotation naming the line it was credited with."""
    if mode == "off":
        return 0, []
    tw = open_twins(prog, ln)
    if not tw or mode != "on":
        return len(tw), tw
    with open(prog, errors="surrogateescape") as f:
        lines = f.read().split("\n")
    done = []
    for n in tw:
        if OPEN.match(lines[n - 1]):
            lines[n - 1] = "- [x] (identical twin of the item credited at line %d) " % ln + lines[n - 1][len("- [ ] "):]
            done.append(n)
    if done:
        with open(prog, "w", errors="surrogateescape") as f:
            f.write("\n".join(lines))
    return len(done), done


def filter_new(cands, files):
    """Candidate item lines whose canon exists in none of `files` (any checkbox state, parked or not) and was not already kept."""
    seen = set()
    for fp in files:
        try:
            with open(fp, errors="surrogateescape") as f:
                for l in f:
                    if _is_item(l):
                        seen.add(canon_item(l))
        except OSError:
            pass
    out = []
    for l in cands:
        if not _is_item(l):
            out.append(l)
            continue
        c = canon_item(l)
        if c and c in seen:
            continue
        seen.add(c)
        out.append(l)
    return out


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
        b = ovn_spec_rules.bare_verify(lines[ln - 1]) or ovn_spec_rules.bare_verify_neg(lines[ln - 1])   # the 2nd: `cmd returns no results` (R14: read with its polarity)
        return b[1] if b else ""
    except Exception:  # noqa: BLE001 - any failure = no fallback (NO_VERIFY_CLAUSE, the old answer)
        return ""


def polarity_of(prog, ln):
    """'neg grep' | 'neg exit' | 'pos' | 'unknown' for the VERIFY of line `ln` (see ovn_backlog_eligibility.verify_polarity)."""
    try:
        with open(prog, errors="surrogateescape") as f:
            lines = f.read().split("\n")
        if ln < 1 or ln > len(lines):
            return "unknown"
        import ovn_backlog_eligibility as E
        cmd, pol = E.verify_clause_and_polarity(lines[ln - 1])
        return ("neg " + E.verify_tool_class(cmd)) if pol == "neg" else pol
    except Exception:  # noqa: BLE001 - unknown = today's behaviour
        return "unknown"


def main():
    if len(sys.argv) >= 4 and sys.argv[1] == "polarity":
        try:
            print(polarity_of(sys.argv[2], int(sys.argv[3])))
        except ValueError:
            print("unknown")
    elif len(sys.argv) >= 4 and sys.argv[1] == "bare-verify":
        try:
            print(bare_verify_of(sys.argv[2], int(sys.argv[3])))
        except ValueError:
            print("")
    elif len(sys.argv) >= 4 and sys.argv[1] == "canon":
        with open(sys.argv[2], errors="surrogateescape") as f:
            ls = f.read().split("\n")
        n = int(sys.argv[3])
        print(canon_item(ls[n - 1]) if 1 <= n <= len(ls) else "")
    elif len(sys.argv) >= 4 and sys.argv[1] == "twins":
        for n in open_twins(sys.argv[2], int(sys.argv[3])):
            print(n)
    elif len(sys.argv) >= 4 and sys.argv[1] == "tick-twins":
        mode = sys.argv[4] if len(sys.argv) >= 5 else "on"
        try:
            n, lines = tick_twins(sys.argv[2], int(sys.argv[3]), mode)
        except (OSError, ValueError):
            print("OFF 0")
            return
        if mode == "off":
            print("OFF 0")
        elif mode == "on":
            print("TICKED %d" % n)
        else:
            print("SHADOW %d %s" % (n, " ".join(str(x) for x in lines)))
    elif len(sys.argv) >= 3 and sys.argv[1] == "filter-new":
        cands = sys.stdin.read().split("\n")
        trail = cands and cands[-1] == ""
        if trail:
            cands = cands[:-1]
        kept = filter_new(cands, sys.argv[2:])
        sys.stderr.write("kept %d of %d\n" % (sum(1 for x in kept if _is_item(x)), sum(1 for x in cands if _is_item(x))))
        sys.stdout.write("\n".join(kept) + ("\n" if kept else ""))
    elif len(sys.argv) >= 3 and sys.argv[1] == "list":
        for n, t in list_items(sys.argv[2]):
            print("%d\t%s" % (n, t))
    elif len(sys.argv) >= 4 and sys.argv[1] == "tick":
        print("TICKED" if tick(sys.argv[2], int(sys.argv[3])) else "REFUSED")
    else:
        print("usage: ovn_credit_items.py list <prog> | tick <prog> <line> | bare-verify <prog> <line> | canon <prog> <line> | twins <prog> <line> | tick-twins <prog> <line> [on|shadow|off] | filter-new <file>... (stdin)", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
