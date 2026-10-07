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

2026-09-17: prune dedup'd-but-never-removed backlog lines every run, not just pulled/credited
ones. Dedup (the `existing` set below) already refused to ever re-pull a backlog line whose
content already exists in the live queue or done archive — but until now it only REMOVED lines
from backlog/<repo>.md that were actually pulled or credited in that same run, so a line that
was dedup-excluded on every single run (because it duplicates already-completed work) just sat
in the file forever. That's not merely cosmetic: queue_refill.sh's own "is this repo's backlog
dry" check is a raw grep -c over "^- [ ] [T1-5]" lines in the file BEFORE this script ever runs,
with no idea about dedup — so N stale duplicate lines make a truly-exhausted backlog look like
it still has N items available, permanently suppressing the "backlog is dry, needs a human"
alert. Caught live on shrike-monitor: 3 lines added to backlog/shrike-monitor.md on 2026-09-10
(config.py/logging_config.py/version.py polish items) duplicated work already completed and
archived to OVERNIGHT_DONE.md five days earlier (2026-09-05) — a full week of a masked-dry
backlog with zero alerts, the same failure shape as the gitlark/billwatch exhausted-roadmap
bug found separately the same day. Fix: compute `dup` (backlog lines whose content is already
in `existing`) up front and always fold it into the lines removed from the backlog file, even
on the early-return path where nothing was pulled or credited.
"""
import sys, re, datetime, subprocess, os

SCAN_CAP = 30


def _extract_verify(line):
    m = re.search(r'VERIFY:\s*`([^`]+)`', line)
    if not m:
        m = re.search(r'VERIFY:\s*(.+?)\s*\(cat:', line)
    return m.group(1).strip() if m else None


_ALWAYS_TRUE_RE = re.compile(r'\|\|\s*(echo|printf|true)\b')
_TEST_ABSENT_RE = re.compile(r'^test\s+!\s+-([fe])\s+([A-Za-z0-9_./@-]+)\s*$')


def already_satisfied(line, repo_root, timeout=8):
    """Best-effort: True only if the item's OWN verify command already passes against the
    current repo. False (never block a pull) on any ambiguity, error, or unsupported shape.

    2026-09-23: reject a `cmd && echo A || echo B` (or `|| printf`/`|| true`) shape outright,
    without ever executing it - the final executed branch there is always the echo/printf/true
    fallback, so its exit code is always 0 regardless of what cmd actually found. Confirmed live
    on shrike-monitor and gitlark: this exact shape false-credited items as done with zero real
    work having happened. ovn_verify_direction_check.sh (shadow-mode alert) has been running clean
    against this pattern for hours with zero remaining open false positives, so promoting it here
    to an actual gate - not just an alert - closes the root vulnerability instead of only
    reporting it after the fact.
    """
    cmd = _extract_verify(line)
    if not cmd:
        return False
    if _ALWAYS_TRUE_RE.search(cmd):
        return False
    # h13 (2026-10-04): `test ! -f <path>` (a "delete X" item whose file an earlier commit already removed) is cheap and side-effect free, but
    # was never recognised, so such items were pulled into the live queue and flailed. Accept ONLY the bare single-path form (no operators), and
    # only when the path is a plain relative repo path.
    m = _TEST_ABSENT_RE.match(cmd)
    if m:
        p = m.group(2)
        if p.startswith("/") or ".." in p.split("/"):
            return False
        return not os.path.lexists(os.path.join(repo_root, p))
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
    # 2026-09-29 fix: added "HUMAN/" (catches roadmap's own "[HUMAN/design]" tag on
    # items that need a real design call before they're decomposable — see
    # roadmap/README.md convention). Confirmed live on test-automation-agent: a
    # [HUMAN/design]-tagged feature got auto-decomposed anyway (this regex only
    # matched "HUMAN-ONLY", not "HUMAN/"), then its mechanical sub-items thrashed
    # for 3 days (12+ reverts, ~450K tokens) because they conflicted with an
    # unrelated, correct, already-existing migration-drift safety-net test that
    # aider has no shell access to satisfy. run_overnight.sh's own OVERNIGHT_PROGRESS.md
    # skip-greps already use the broader "human/" pattern in several call sites
    # (see e.g. its DOABLE-count checks) - this brings queue_refill.py's backlog-pull
    # gate up to the same standard so a [HUMAN/design] item is excluded at BOTH the
    # decomposition-output stage and the live-queue-pull stage, not just one.
    parked = re.compile(r"AUTO-SKIP|HUMAN-ONLY|HUMAN/|BLOCKED", re.I)
    # Dedup guard: never pull an item whose content already exists in the live queue
    # (open OR done) — prevents duplicates when a backlog is re-shipped/overlaps progress.
    #
    # 2026-09-29 (Phase 6b, PREVENTIVE — no live miss observed on this exact path yet): strip the
    # embedded date stamp out of any [feat:<slug>] tag before comparing. A roadmap regeneration
    # mints a fresh YYYYMMDD/MMDDYY stamp on the SAME feat slug when it re-decomposes a stuck
    # feature, so a backlog line identical except for that one date used to look like brand-new
    # work and get pulled again. The bash side already collapses this (ovn_item_hash() in
    # scripts/lib_item_select.sh, same two sed rules: "-NNNNNNNN-" then "-NNNNNN-", first
    # occurrence each) — this keeps the Python and bash sides agreeing on what "the same item"
    # means (the exact cross-boundary mismatch class already found once between record_outcome()
    # and ovn_item_guard.sh). Deliberately strips ONLY the date inside the tag and keeps the rest
    # of the line: ovn_item_hash() hashes the tag alone because it answers "same FEATURE" for
    # streak tracking, but two sibling sub-items sharing one live feat tag are genuinely different
    # content here and must NOT dedup against each other.
    def _strip_feat_date(text):
        def _one(m):
            tag = re.sub(r"-\d{8}-", "-", m.group(0), count=1)
            return re.sub(r"-\d{6}-", "-", tag, count=1)
        return re.sub(r"\[feat:[^\]]+\]", _one, text)
    def _norm(line):
        # 2026-10-07: a parked line carries '[AUTO-SKIP ...]' / '[HUMAN-ONLY ...]' right after the checkbox; without stripping it the roadmap's
        # re-decomposed copy of the SAME item (identical text, no tag) looked brand new and was re-pulled as an eligible item (churn-loop guard parks
        # an item, the backlog re-adds it, the loop restarts).
        line = re.sub(r"^(\s*- \[[ xX]\] )(\[(?:AUTO-SKIP|HUMAN-ONLY)[^\]]*\]\s*)+", r"\1", line)
        m = re.search(r"\]\s*(.*)$", line)  # content after the last tag bracket
        content = _strip_feat_date((m.group(1) if m else line).strip())
        return re.sub(r"\s+", " ", content.lower())
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
    # backlog lines that are real [T1-5] items but whose content is ALREADY in the live queue
    # or done archive — permanently dedup-excluded from `eligible` above, so they'll never be
    # pulled or pre-check-credited. Left in the file, they inflate queue_refill.sh's raw
    # grep-based "backlog avail" count forever (see 2026-09-17 note in the module docstring).
    # Always pruned below, independent of whether this run pulls/credits anything.
    dup = [l for l in bl if is_item.match(l) and not parked.search(l) and _norm(l) in existing]
    # 2026-09-14 REMOVED the old "DEFAULT-PASS on godot" reroute (pulled every .gd backlog item and
    # pre-tagged it AUTO-SKIP/route-to-Claude before it ever reached the active queue) — that was the
    # SAME stale "measured 0%" assumption fixed today in ovn_stage_runner.sh/run_overnight.sh (see
    # project_godot-staging-reenabled-2026-09-14.md), just one layer further upstream. It meant fixing
    # the picker/trigger did nothing for NEW backlog items: they got auto-parked here before either
    # fixed code path ever saw them. Godot items now flow through the normal pull path below like any
    # other item, routing to whichever flow (basic scout+implement or the staged pipeline) their tier
    # naturally selects.

    # Pre-check: scan eligible items in order, crediting any that already pass their own
    # VERIFY, until either the pull quota (n) is filled or SCAN_CAP items have been examined.
    # NOTE: already_satisfied's own docstring restricts pre-checking to python-import/grep VERIFY
    # shapes (cheap, side-effect-free) — a godot item's VERIFY runs the engine, so it's heavier than
    # that restriction allows and will simply never match, falling through to `pull` normally.
    pull, credited, scanned = [], [], 0
    for l in eligible:
        if len(pull) >= n or scanned >= SCAN_CAP:
            break
        scanned += 1
        if already_satisfied(l, repo_root):
            credited.append(l)
        else:
            pull.append(l)

    if not pull and not credited and not dup:
        remaining = len(eligible)
        print(f"REFILL=0  BACKLOG_REMAINING={remaining}  CREDITED=0  PRUNED=0")
        return

    # remove pulled + credited + already-consumed-duplicate lines from the backlog (first
    # occurrence each)
    to_remove = list(pull) + list(credited) + list(dup)
    rest = []
    for l in bl:
        if to_remove and l in to_remove:
            to_remove.remove(l)
            continue
        rest.append(l)
    open(backlog, "w", encoding="utf-8").write(("\n".join(rest)).rstrip() + "\n")

    stamp = datetime.date.today().isoformat()

    # append pulled items to the live queue under a dated marker (runner scans `- [ ] [Tn]`)
    with open(progress, "a", encoding="utf-8") as f:
        if pull:
            f.write(f"\n<!-- auto-refill {stamp}: {len(pull)} items pulled from backlog -->\n")
            for l in pull:
                f.write(l + "\n")

    # credited items never enter the active queue at all — straight to the done archive, so
    # queue_refill.py's own dedup (and everyone else's) sees them as already handled.
    if credited:
        with open(done_path, "a", encoding="utf-8") as f:
            f.write(f"\n<!-- pre-verified already-satisfied {stamp}: {len(credited)} item(s), credited without a 27B cycle -->\n")
            for l in credited:
                checked = re.sub(r"^- \[ \] ", "- [x] (pre-verified: VERIFY already passed against current code) ", l, count=1)
                f.write(checked + "\n")

    remaining = len([l for l in rest if is_item.match(l) and not parked.search(l) and _norm(l) not in existing])
    print(f"REFILL={len(pull)}  CREDITED={len(credited)}  BACKLOG_REMAINING={remaining}  PRUNED={len(dup)}")


if __name__ == "__main__":
    main()
