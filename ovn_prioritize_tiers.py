#!/usr/bin/env python3
"""ovn_prioritize_tiers.py — reorder a repo's OVERNIGHT_PROGRESS.md so the fleet actually ATTEMPTS
higher-tier work instead of grinding a mountain of T1/T2 trivia it never gets past.

The fleet works the single TOP not-yet-done item each cycle. If 46 T1 items sit above the first T3,
the 27B never reaches a T3 — which is exactly why 0 T3-T5 items landed in 24h. This surfaces doable
T3 items to the TOP of "## Next Steps" (they get architect plan-first + best-of-N), keeps T1/T2 next,
and pushes T4/T5 to the BOTTOM (the 27B ~can't do them; after the fail-cap they auto-park and the
Mac bridge harvests them to the Claude queue). Parked/checked/non-item lines are left exactly in place
relative to the section; only the ORDER of open unchecked items within Next Steps changes.

Usage: ovn_prioritize_tiers.py <OVERNIGHT_PROGRESS.md>   (edits in place; prints a one-line summary)
Idempotent: running twice is a no-op (already ordered).
"""
import re, sys

TIER_RE = re.compile(r'\[T([1-5])\]|·T([1-5])·')
PARKED_RE = re.compile(r'AUTO-SKIP|HUMAN-ONLY|BLOCKED')
ITEM_RE = re.compile(r'^- \[ \] ')


def tier_of(line):
    m = TIER_RE.search(line)
    if not m:
        return 2  # untiered -> treat as mid priority
    return int(m.group(1) or m.group(2))


def rank(line):
    """sort key: T3 first (0), then T2/T1 (1), then T4/T5 last (2). Stable within a bucket."""
    if PARKED_RE.search(line):
        return 3  # parked open items sink below everything actionable
    t = tier_of(line)
    if t == 3:
        return 0
    if t in (1, 2):
        return 1
    return 2  # T4/T5


def main():
    path = sys.argv[1]
    lines = open(path, encoding="utf-8").read().split("\n")
    # locate the "## Next Steps" section (reorder only the open items inside it)
    start = None
    for i, ln in enumerate(lines):
        if ln.strip().lower().startswith("## next steps"):
            start = i + 1
            break
    if start is None:
        print("no Next Steps section — nothing to do")
        return
    # section ends at the next "## " header or EOF
    end = len(lines)
    for i in range(start, len(lines)):
        if lines[i].startswith("## "):
            end = i
            break
    section = lines[start:end]
    # collect open items with their trailing continuation lines (indented / non-item lines that follow)
    blocks, cur, preamble = [], None, []
    for ln in section:
        if ITEM_RE.match(ln):
            if cur is not None:
                blocks.append(cur)
            cur = [ln]
        elif cur is not None:
            cur.append(ln)  # continuation of the current item
        else:
            preamble.append(ln)  # blank/notes before the first item
    if cur is not None:
        blocks.append(cur)
    if not blocks:
        print("no open items in Next Steps — nothing to do")
        return
    ordered = sorted(range(len(blocks)), key=lambda i: (rank(blocks[i][0]), i))
    if ordered == list(range(len(blocks))):
        print("already prioritized — no change")
        return
    new_section = preamble + [l for i in ordered for l in blocks[i]]
    lines[start:end] = new_section
    open(path, "w", encoding="utf-8").write("\n".join(lines))
    t3 = sum(1 for b in blocks if rank(b[0]) == 0)
    t45 = sum(1 for b in blocks if rank(b[0]) == 2)
    print(f"reordered {len(blocks)} items: {t3} T3 surfaced to top, {t45} T4/T5 sunk to bottom")


if __name__ == "__main__":
    main()
