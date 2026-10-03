#!/usr/bin/env python3
"""claude_queue_bridge.py — the two-way bridge between the Claude queue and the 27B.

Runs MAC-SIDE (CLAUDE_QUEUE.md lives only in the shared repo). Four subcommands, orchestrated
by claude_queue_bridge.sh as Passes A-D each cycle:

  harvest    (Pass A) — REFILL the Claude queue from the 27B's ceiling failures. Reads AUTO-SKIP
             items (the ovn_item_guard tag = "tried N cycles, kept reverting") that the fleet
             surfaced, dedups against what's already in CLAUDE_QUEUE.md (+ --archive, see below),
             and appends the new ones under a dated "Auto-harvested from 27B ceiling" section.
             The 27B's proven failures become Claude's inbox — evidence-based, not a guess.

  prework    (Pass B) — SCHEDULE 27B prework for every CODE-ABLE Claude item that doesn't already
             have a briefing. Emits `<repo>\t<task>` lines (to stdout) for items lacking
             prework/<repo>-<slug>.md, so the caller can append them to the server's
             prework/queue.tsv. Skips human/hardware/account/DNS/submission items (no code to
             prework) and already-checked items. (Never needs --archive: archived items are
             checked-off by definition, so they'd never be prework candidates anyway.)

  signatures (feeds Pass C) — print `repo\tnormsig` for every checked-off item with a known
             repo, across --queue and --archive, so claude_queue_bridge.sh knows which
             server-side AUTO-SKIP lines are safe to retire.

  retire     (Pass C) — flip a single repo's unchecked AUTO-SKIP progress-file lines to `[x]`
             when their signature matches a signatures-file entry, closing the loop so the 27B
             stops re-flagging code Claude already fixed.

IMPORTANT — dedup relies on task_sig(), not bare norm_sig(): a queue-formatted line carries a
"[CLAUDE] <repo>/ — " prefix that the raw AUTO-SKIP task text never has, so norm_sig()'s
first-12-words comparison would silently never match across that boundary (this was the actual
dominant cause of a 20x+ per-item duplication bug in CLAUDE_QUEUE.md, fixed 2026-09-10 —
see cc973c1). Any new code comparing queue text against autoskip/progress text MUST use
task_sig(), never norm_sig() directly.

--archive is how harvest/signatures see items moved out of the live queue by
archive_claude_queue_done.py (run as Pass D, after retire). This is NOT optional plumbing:
without it, archiving an item would make harvest/retire treat it as unknown again and
re-introduce the exact duplication bug this file was fixed to prevent.

Usage:
  claude_queue_bridge.py prework    --queue CLAUDE_QUEUE.md --prework-list <file of existing prework basenames>
  claude_queue_bridge.py harvest    --queue CLAUDE_QUEUE.md --autoskip <file: repo<TAB>task lines> [--archive CLAUDE_QUEUE_DONE.md]
  claude_queue_bridge.py signatures --queue CLAUDE_QUEUE.md [--archive CLAUDE_QUEUE_DONE.md]
  claude_queue_bridge.py retire     --progress <repo's OVERNIGHT_PROGRESS.md> --signatures <file: one normsig per line>
"""
import argparse, re, sys, datetime

# canonical repo basenames + aliases seen in CLAUDE_QUEUE headers/inline text
REPO_ALIASES = {
    "billwatch": "billwatch", "policylogs": "billwatch",
    "gitlark": "gitlark",
    "iptv_apps": "iptv_apps", "iptv": "iptv_apps", "chickadee": "iptv_apps",
    "test-automation-agent": "test-automation-agent", "specpilot": "test-automation-agent",
    "xlite": "xlite",
    "shrike-labs-website": "shrike-labs-website", "shrike-website": "shrike-labs-website",
    "shrike-notify": "shrike-notify",
    "shrike-monitor": "shrike-monitor",
}
REPO_TOKEN_RE = re.compile(
    r"\b(billwatch|policylogs|gitlark|iptv_apps|iptv|chickadee|"
    r"test-automation-agent|specpilot|xlite|shrike-labs-website|shrike-website|"
    r"shrike-notify|shrike-monitor)\b", re.I)

# an item is NOT code-able (no prework possible) if it's human/hardware/ops work
NON_CODEABLE_RE = re.compile(
    r"\(human\)|\bhuman/QA\b|\bhardware\b|real[- ]device|real device|"
    r"App Store|Play Store|Appstore|submission|certification|"
    r"\bDNS\b|custom domain|domain canonicaliz|registrar|"
    r"register (the |a )?(github app|account)|developer account|"
    r"ad spend|pricing decision|wire .*fly deploy|FLY_API_TOKEN|"
    r"service account|Xcode build/run|icon/top-shelf|asset-design|art assets",
    re.I)

ITEM_RE = re.compile(r"^\s*- \[ \] (.+)$")
CHECKED_ITEM_RE = re.compile(r"^\s*- \[[xX]\] (.+)$")
HEADER_RE = re.compile(r"^#{2,4}\s+(.+)$")
# 2026-10-03: an escalated manual bug ('[CLAUDE] [bug-escalated: ...]', the bug-first hand-off) is harvested/retired exactly like an AUTO-SKIP line
AUTOSKIP_LINE_RE = re.compile(r"^(\s*)- \[ \] (.*(?:AUTO-SKIP|\[CLAUDE\]\s*\[bug-escalated).*)$")
AUTOSKIP_TAG_RE = re.compile(r"\[AUTO-SKIP[^\]]*\]\s*|\[CLAUDE\]\s*\[bug-escalated[^\]]*\]\s*")
FEAT_TAG_RE = re.compile(r"\[feat:([^\]\s]+)\]")


def slug(task):
    s = re.sub(r"[^a-z0-9]+", "-", task.lower())[:50]
    return s.strip("-")


def infer_repo(item_text, current_header):
    for src in (item_text, current_header):
        m = REPO_TOKEN_RE.search(src or "")
        if m:
            return REPO_ALIASES[m.group(1).lower()]
    return None


def norm_sig(text):
    """collapse a task to a comparable signature (lowercase alnum words, first 12)."""
    words = re.findall(r"[a-z0-9]+", text.lower())
    return " ".join(words[:12])


LEADING_TAGS_RE = re.compile(r"^(\[[^\]]+\]\s*)+")
REPO_PREFIX_RE = re.compile(
    r"^(?:billwatch|policylogs|gitlark|iptv_apps|iptv|chickadee|"
    r"test-automation-agent|specpilot|xlite|shrike-labs-website|shrike-website|"
    r"shrike-notify|shrike-monitor)/\s*(?:—|-|—)?\s*", re.I)


def task_sig(text):
    """norm_sig() after stripping leading `[TAG]` markers and a `repo/ — ` prefix.

    A queue-formatted item ("[CLAUDE] gitlark/ — [T1] some task...") and the
    bare AUTO-SKIP task it was harvested from ("[T1] some task...") must
    collapse to the SAME signature, or cross-format dedup (harvest against the
    queue, retire against checked-off queue items) never actually matches —
    norm_sig()'s first-12-words comparison is offset by the extra "claude
    <repo>" words baked into every queue line, so two genuinely identical
    tasks compare unequal. Use this (not bare norm_sig) for any comparison
    between queue text and raw autoskip/task text.
    """
    # a queue line often nests tags around the repo prefix, e.g.
    # "[CLAUDE] gitlark/ — [T1] task..." — strip leading [TAG]s, then a repo/
    # prefix, then [TAG]s again (the [T1] that was hiding behind "gitlark/ — ").
    stripped = LEADING_TAGS_RE.sub("", text)
    stripped = REPO_PREFIX_RE.sub("", stripped)
    stripped = LEADING_TAGS_RE.sub("", stripped)
    sig = norm_sig(stripped)
    # 2026-10-03 (A7-1): the first 12 words of a '[T3] <long android path> ...' line are consumed by the file path, so three different bugs in
    # StreamsViewModel.kt shared ONE signature (harvest dropped two as duplicates; retire would have closed all three). A [feat:ID] tag is unique per
    # bug (and per retest round), so it is part of the signature whenever the line carries one.
    m = FEAT_TAG_RE.search(text)
    if m:
        sig += " feat " + m.group(1).lower()
    return sig


def iter_items(lines):
    """yield (item_text, current_header) for each unchecked item."""
    header = ""
    for ln in lines:
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
            continue
        m = ITEM_RE.match(ln)
        if m:
            yield m.group(1).strip(), header


def iter_all_items(lines):
    """yield (item_text, current_header) for every item, checked or not.

    Harvest dedup must see checked-off items too: an AUTO-SKIP task that was
    resolved and flipped to `- [x]` in CLAUDE_QUEUE.md would otherwise drop out
    of the "already have this" signature set, and the next harvest re-adds it
    as a fresh `- [ ]` duplicate the moment the server re-surfaces the same
    AUTO-SKIP line (which it does every cycle by design, since AUTO-SKIP items
    are never auto-credited server-side).
    """
    header = ""
    for ln in lines:
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
            continue
        m = ITEM_RE.match(ln) or CHECKED_ITEM_RE.match(ln)
        if m:
            yield m.group(1).strip(), header


def strip_autoskip_task(line):
    """Extract the task text from an unchecked AUTO-SKIP progress-file line,
    mirroring claude_queue_bridge.sh's sed extraction exactly (same source of
    truth as what gets harvested into CLAUDE_QUEUE.md). Returns None if the
    line isn't an unchecked AUTO-SKIP item.
    """
    m = AUTOSKIP_LINE_RE.match(line)
    if not m:
        return None
    task = AUTOSKIP_TAG_RE.sub("", m.group(2)).strip()
    return task


def checked_signatures_by_repo(lines):
    """yield (repo, norm_sig) for every CHECKED `- [x]` item whose repo can be
    inferred — used to know which AUTO-SKIP tasks are safe to retire server-side.
    """
    header = ""
    for ln in lines:
        h = HEADER_RE.match(ln)
        if h:
            header = h.group(1).strip()
            continue
        m = CHECKED_ITEM_RE.match(ln)
        if not m:
            continue
        text = m.group(1).strip()
        repo = infer_repo(text, header)
        if repo:
            yield repo, task_sig(text)


def read_lines_optional(path):
    """Read a file's lines, or return [] if path is falsy/missing.

    Used for --archive: CLAUDE_QUEUE_DONE.md may not exist yet, and callers
    that don't care about archived history (e.g. cmd_prework, which only
    ever looks at open items) never pass --archive at all.
    """
    if not path:
        return []
    try:
        return open(path, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        return []


def cmd_signatures(args):
    """Print `repo\\tnormsig` for every checked-off item with a known repo,
    across --queue and (if given) --archive — consumed by the bridge shell
    script to know what's safe to retire. Archived items must still count:
    they were checked off for a real reason and shouldn't become "unknown"
    (and therefore un-retirable on the server) just because they moved out
    of the live queue file.
    """
    lines = open(args.queue, encoding="utf-8").read().splitlines() + read_lines_optional(args.archive)
    seen = set()
    for repo, sig in checked_signatures_by_repo(lines):
        key = (repo, sig)
        if key in seen:
            continue
        seen.add(key)
        sys.stdout.write(f"{repo}\t{sig}\n")


def cmd_retire(args):
    """Flip unchecked AUTO-SKIP lines in a single repo's OVERNIGHT_PROGRESS.md
    to `- [x]` when their task signature matches an already-checked-off
    CLAUDE_QUEUE.md item — closes the loop so the 27B stops re-flagging code
    Claude already fixed. Rewrites --progress in place if anything changed.
    Prints RETIRED=<n>.
    """
    sigs = {
        s.strip() for s in open(args.signatures, encoding="utf-8").read().splitlines() if s.strip()
    }
    lines = open(args.progress, encoding="utf-8").read().splitlines()
    retired = 0
    out = []
    for ln in lines:
        task = strip_autoskip_task(ln)
        if task and len(task) >= 20 and task_sig(task) in sigs:
            m = AUTOSKIP_LINE_RE.match(ln)
            indent = m.group(1)
            out.append(
                f"{indent}- [x] {m.group(2)} "
                f"(retired {args.today}: resolved via Claude, see shared/CLAUDE_QUEUE.md)"
            )
            retired += 1
        else:
            out.append(ln)
    if retired:
        with open(args.progress, "w", encoding="utf-8") as f:
            f.write("\n".join(out) + "\n")
    sys.stderr.write(f"RETIRED={retired}\n")


def cmd_prework(args):
    lines = open(args.queue, encoding="utf-8").read().splitlines()
    existing = set()
    if args.prework_list:
        for b in open(args.prework_list, encoding="utf-8").read().splitlines():
            b = b.strip()
            if b.endswith(".md"):
                existing.add(b[:-3])  # strip .md -> "<repo>-<slug>"
    emitted = 0
    seen = set()
    for item, header in iter_items(lines):
        # strip leading [P1]/[CLAUDE]/[CLAUDE/HUMAN] tags for the task body
        body = re.sub(r"^(\[[^\]]+\]\s*)+", "", item).strip()
        body = re.sub(r"~\d+d\s*(\(human[^)]*\))?", "", body).strip()
        if NON_CODEABLE_RE.search(item):
            continue
        repo = infer_repo(item, header)
        if not repo:
            continue
        key = f"{repo}-{slug(body)}"
        if key in existing or key in seen:
            continue
        seen.add(key)
        # keep the task text single-line + reasonably short for the prework prompt
        task = re.sub(r"\s+", " ", body)[:400]
        sys.stdout.write(f"{repo}\t{task}\n")
        emitted += 1
    sys.stderr.write(f"prework: emitted {emitted} code-able items lacking a briefing\n")


def cmd_harvest(args):
    lines = open(args.queue, encoding="utf-8").read().splitlines() + read_lines_optional(args.archive)
    existing_sigs = {task_sig(t) for t, _ in iter_all_items(lines)}
    new_items = []
    for ln in open(args.autoskip, encoding="utf-8").read().splitlines():
        if "\t" not in ln:
            continue
        repo, task = ln.split("\t", 1)
        repo, task = repo.strip(), task.strip()
        if not repo or len(task) < 20:   # guard: never harvest a stub/garbage task
            continue
        if task_sig(task) in existing_sigs:
            continue
        existing_sigs.add(task_sig(task))
        new_items.append((repo, task))
    if not new_items:
        sys.stderr.write("harvest: nothing new to add\n")
        return
    today = args.today
    block = [f"\n## Auto-harvested from 27B ceiling [{today}] — the fleet tried these N cycles and kept reverting; Claude to implement\n"]
    for repo, task in new_items:
        block.append(f"- [ ] [CLAUDE] {repo}/ — {task}\n")
    with open(args.queue, "a", encoding="utf-8") as f:
        f.write("".join(block))
    sys.stderr.write(f"harvest: appended {len(new_items)} new items to {args.queue}\n")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    pp = sub.add_parser("prework")
    pp.add_argument("--queue", required=True)
    pp.add_argument("--prework-list", default="")
    hp = sub.add_parser("harvest")
    hp.add_argument("--queue", required=True)
    hp.add_argument("--autoskip", required=True)
    hp.add_argument("--archive", default="")
    hp.add_argument("--today", default=datetime.date.today().isoformat())
    sp = sub.add_parser("signatures")
    sp.add_argument("--queue", required=True)
    sp.add_argument("--archive", default="")
    rp = sub.add_parser("retire")
    rp.add_argument("--progress", required=True)
    rp.add_argument("--signatures", required=True)
    rp.add_argument("--today", default=datetime.date.today().isoformat())
    args = p.parse_args()
    {
        "prework": cmd_prework,
        "harvest": cmd_harvest,
        "signatures": cmd_signatures,
        "retire": cmd_retire,
    }[args.cmd](args)


if __name__ == "__main__":
    main()
