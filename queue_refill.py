#!/usr/bin/env python3
"""queue_refill.py — move pre-decomposed items from a backlog into a live overnight queue.

The intelligence (deciding WHAT to do, broken into 27B-sized self-verifying subtasks) is
invested ONCE, in backlog/<repo>.md, by Claude or the release-polish drafters. This script
is the DUMB pull: it takes the top N unconsumed backlog items and appends them to the repo's
OVERNIGHT_PROGRESS.md, then removes them from the backlog. $0, deterministic, no repo scan,
no LLM — which is exactly what kills the recurring "expensive repo survey -> no-op" loop.

An item is any line matching `- [ ] [T` or `- [ ] [CLAUDE`. CLAUDE items are NOT pulled into
the 27B queue (they're for the Claude queue); only [T1..T5] items are moved here.

Usage: queue_refill.py <progress_file> <backlog_file> <max_items>
Prints: REFILL=<n moved>  BACKLOG_REMAINING=<n left>  CREDITED=<n already-satisfied>

2026-09-10: pre-check before pulling. shrike-monitor alone had 19 backlog-authored items that
turned out to already be implemented in current code (a stale decomposition snapshot) — every
one of them cost N wasted no-op cycles before the existing AUTO-SKIP-after-N-cycles safety net
finally parked it. Most items' own VERIFY command is a cheap, side-effect-free existence/import
check (`python -c "from X import Y; ..."` or `grep -q "..."`); running that ONCE against the
CURRENT repo before ever queueing the item is nearly free and catches this class at zero cost
instead of N wasted cycles. Restricted to those two safe shapes — anything heavier (pytest, npm
test, godot) is left to the existing cycle-based safety net, which is reliable if slower. Only
the first SCAN_CAP eligible items are pre-checked per run, bounding worst-case time even if a
run of items all happen to time out.
"""
import sys, re, datetime, subprocess, os

SCAN_CAP = 30


def _extract_verify(line):
    m = re.search(r'VERIFY:\s*`([^`]+)`', line)
    if not m:
        m = re.search(r'VERIFY:\s*(.+?)\s*\(cat:', line)
    return m.group(1).strip() if m else None


def already_satisfied(line, repo_root, timeout=8):
    """Best-effort: True only if the item's OWN verify command already passes against the
    current repo. False (never block a pull) on any ambiguity, error, or unsupported shape."""
    cmd = _extract_verify(line)
    if not cmd:
        return False
    if not (cmd.startswith("python -c") or cmd.startswith("python3 -c") or cmd.startswith("grep -")):
        return False
    try:
        r = subprocess.run(cmd, shell=True, cwd=repo_root, timeout=timeout,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return r.returncode == 0
    except Exception:
        return False


def main():
    if len(sys.argv) != 4:
        print("usage: queue_refill.py <progress_file> <backlog_file> <max_items>", file=sys.stderr)
        sys.exit(2)
    progress, backlog, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
    repo_root = os.path.dirname(progress) or "."
    try:
        bl = open(backlog, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        print("REFILL=0  BACKLOG_REMAINING=0  CREDITED=0")
        return
    # 27B-eligible open items only (skip CLAUDE-tagged and already-parked lines)
    is_item = re.compile(r"^- \[ \] \[T[1-5]\]")
    parked = re.compile(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED", re.I)
    # Dedup guard: never pull an item whose content already exists in the live queue
    # (open OR done) — prevents duplicates when a backlog is re-shipped/overlaps progress.
    def _norm(line):
        m = re.search(r"\]\s*(.*)$", line)  # content after the last tag bracket
        return re.sub(r"\s+", " ", (m.group(1) if m else line).strip().lower())
    done_path = os.path.join(repo_root, "OVERNIGHT_DONE.md")
    existing = set()
    # dedup against the live queue AND the completed-items archive (OVERNIGHT_DONE.md), so an
    # item that was completed then archived out of the progress file is never re-pulled.
    for fp in (progress, done_path):
        try:
            for pl in open(fp, encoding="utf-8"):
                if pl.lstrip().startswith("- ["):
                    existing.add(_norm(pl))
        except FileNotFoundError:
            pass
    eligible = [l for l in bl if is_item.match(l) and not parked.search(l) and _norm(l) not in existing]
    # DEFAULT-PASS on godot: the 27B is measured ~0% on Godot (.gd), so never pull it as 27B work.
    # Instead pull ALL eligible godot items and write them PRE-TAGGED for Claude — they leave the
    # backlog and land in the progress file already AUTO-SKIP'd, so the claude_queue_bridge harvests
    # them to CLAUDE_QUEUE.md and the 27B's item picker skips them. This is the durable reroute:
    # godot can never re-clog the 27B queue via refill.
    godot_re = re.compile(r"\.gd\b", re.I)
    godot = [l for l in eligible if godot_re.search(l)]
    eligible = [l for l in eligible if not godot_re.search(l)]

    # Pre-check: scan eligible items in order, crediting any that already pass their own
    # VERIFY, until either the pull quota (n) is filled or SCAN_CAP items have been examined.
    pull, credited, scanned = [], [], 0
    for l in eligible:
        if len(pull) >= n or scanned >= SCAN_CAP:
            break
        scanned += 1
        if already_satisfied(l, repo_root):
            credited.append(l)
        else:
            pull.append(l)

    if not pull and not godot and not credited:
        remaining = len(eligible)
        print(f"REFILL=0  BACKLOG_REMAINING={remaining}  CREDITED=0")
        return

    # remove pulled + credited + all-godot lines from the backlog (first occurrence each)
    to_remove = list(pull) + list(credited) + list(godot)
    rest = []
    for l in bl:
        if to_remove and l in to_remove:
            to_remove.remove(l)
            continue
        rest.append(l)
    open(backlog, "w", encoding="utf-8").write(("\n".join(rest)).rstrip() + "\n")

    stamp = datetime.date.today().isoformat()

    def _claude_tag(l):  # turn "- [ ] [T3] foo.gd — ..." into an AUTO-SKIP route-to-Claude line
        return l.replace("- [ ] ", "- [ ] [AUTO-SKIP godot(.gd) — 27B measured 0%, route to CLAUDE] ", 1)

    # append pulled items to the live queue under a dated marker (runner scans `- [ ] [Tn]`)
    with open(progress, "a", encoding="utf-8") as f:
        if pull:
            f.write(f"\n<!-- auto-refill {stamp}: {len(pull)} items pulled from backlog -->\n")
            for l in pull:
                f.write(l + "\n")
        if godot:
            f.write(f"\n<!-- auto-refill {stamp}: {len(godot)} godot items routed to CLAUDE (27B can't do Godot) -->\n")
            for l in godot:
                f.write(_claude_tag(l) + "\n")

    # credited items never enter the active queue at all — straight to the done archive, so
    # queue_refill.py's own dedup (and everyone else's) sees them as already handled.
    if credited:
        with open(done_path, "a", encoding="utf-8") as f:
            f.write(f"\n<!-- pre-verified already-satisfied {stamp}: {len(credited)} item(s), credited without a 27B cycle -->\n")
            for l in credited:
                checked = re.sub(r"^- \[ \] ", "- [x] (pre-verified: VERIFY already passed against current code) ", l, count=1)
                f.write(checked + "\n")

    remaining = len([l for l in rest if is_item.match(l) and not parked.search(l) and not godot_re.search(l) and _norm(l) not in existing])
    print(f"REFILL={len(pull)}  GODOT_TO_CLAUDE={len(godot)}  CREDITED={len(credited)}  BACKLOG_REMAINING={remaining}")


if __name__ == "__main__":
    main()
