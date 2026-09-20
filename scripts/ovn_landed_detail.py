#!/usr/bin/env python3
"""ovn_landed_detail.py — per-item "what actually landed" lines for the ntfy digests.

2026-09-20: digest_notify.sh (3h) and work_summary.py (24h, via supervisor.sh) only ever
showed AGGREGATE counts ("billwatch: 4 landed, 1 no-op") — no way to tell what any of it
WAS without tailing logs by hand. state/outcomes.jsonl (record_outcome() in run_overnight.sh)
does NOT carry a per-item description/target — its `id` field is just the generic
tasks.json task id (e.g. "ongoing-billwatch") for every item that repo runs. The one place a
real per-item target already exists is state/task_stats.log (the same file ovn_stats.py reads):
one line per finished item as `<epoch>\\t<repo>\\t<outcome>\\t{lang.type.tier.verif}\\t<file>`,
where <file> is the real path the model touched. This script filters that to outcome=="pass"
(landed) rows in the window and turns them into short "repo (tier·category): file" lines,
most-recent-first per repo, capped so the digest doesn't blow past ntfy's practical message
size (existing 3h digests already run ~2-3KB; this adds well under 1KB with default caps).

Usage: ovn_landed_detail.py [hours=3] [--max-per-repo N] [--max-total N] [--max-len N]
Prints an empty string (nothing to show) if there's no landed activity in the window —
callers should skip the section entirely rather than print an empty header.
"""
import os
import re
import sys
import time

P = os.environ.get("TASK_STATS", os.path.expanduser("~/overnight-queue/state/task_stats.log"))
if not os.path.exists(P) and os.path.exists("state/task_stats.log"):
    P = "state/task_stats.log"

TAG_RE = re.compile(r'\{([^.·]*)[.·]([^.·]*)[.·]([^.·]*)[.·]([^}]*)\}')


def _int_arg(args, flag, default):
    if flag in args:
        i = args.index(flag)
        if i + 1 < len(args):
            try:
                return int(args[i + 1])
            except ValueError:
                pass
    return default


def main():
    argv = sys.argv[1:]
    pos = [a for a in argv if not a.startswith('--') and not _is_flag_value(argv, a)]
    hours = float(pos[0]) if pos else 3.0
    max_per_repo = _int_arg(argv, '--max-per-repo', 3)
    max_total = _int_arg(argv, '--max-total', 12)
    max_len = _int_arg(argv, '--max-len', 70)
    cutoff = time.time() - hours * 3600

    by_repo = {}
    if os.path.exists(P):
        for ln in open(P):
            parts = ln.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            ts_raw, repo, oc, tag, fpath = parts[:5]
            if oc != 'pass':
                continue
            try:
                ts = float(ts_raw)
            except ValueError:
                continue
            if ts < cutoff:
                continue
            m = TAG_RE.match(tag)
            tier = m.group(3) if m else '?'
            cat = m.group(2) if m else '?'
            by_repo.setdefault(repo, []).append((ts, tier, cat, fpath))

    if not by_repo:
        return

    lines = [f"📝 Landed detail (last {hours:g}h):"]
    total = 0
    for repo in sorted(by_repo):
        if total >= max_total:
            break
        items = sorted(by_repo[repo], key=lambda r: r[0], reverse=True)[:max_per_repo]
        for ts, tier, cat, fpath in items:
            if total >= max_total:
                break
            fdisp = fpath if len(fpath) <= max_len else "…" + fpath[-(max_len - 1):]
            # tier is already stored WITH its "T" prefix (e.g. "T2") in task_stats.log's
            # {lang.type.tier.verif} tag — don't re-prepend one (would render as "TT2").
            tier_disp = tier if (tier == '?' or tier.upper().startswith('T')) else f"T{tier}"
            lines.append(f"  {repo} ({tier_disp}·{cat}): {fdisp}")
            total += 1
    if total == 0:
        return
    print("\n".join(lines))


def _is_flag_value(argv, a):
    """True if `a` is the value immediately following one of our --flags (so it's not
    mistaken for the positional hours arg, e.g. `ovn_landed_detail.py --max-total 5`)."""
    for flag in ('--max-per-repo', '--max-total', '--max-len'):
        if flag in argv:
            i = argv.index(flag)
            if i + 1 < len(argv) and argv[i + 1] == a:
                return True
    return False


if __name__ == "__main__":
    main()
