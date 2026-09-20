#!/usr/bin/env python3
"""ovn_noop_detail.py — grouped "what's actually stuck" lines for the ntfy digests.

2026-09-20 (full-day audit finding): the digest's ➖ no-op / ↩️ reverted counts are a raw
per-outcome-record tally, and outcome records are per-CYCLE, not per-item — a single stale
backlog item that the fleet keeps re-picking and re-failing generates one outcome record
EVERY cycle it's re-attempted. Confirmed live against state/task_stats.log on this exact
date: one billwatch item (kotlin/BillsRepositoryTest.kt, T2) alone produced 8 separate
no-op/revert records in a 24h window (7 straight fails, one eventual `pass`), and a
gitlark item (POST validation, T3) produced 5 more, all effectively the SAME unresolved
problem counted once per re-attempt. A flat "$NN no-op, $NR reverted" line (or even the
per-cause breakdown next to it) has no way to distinguish that from 8+5=13 actually-distinct
problems — which makes the fleet look far noisier/more broken than it is.

This script groups task_stats.log's non-landed rows (fail / revert / noop:*) by a stable
signature — (repo, file, tier) — and collapses repeats into one line with a count, e.g.:

    billwatch (T2): BillsRepositoryTest.kt — failed 7x, still unresolved
    iptv-apps (T2): test_search_filters.py — failed 13x, still unresolved

Tier is part of the signature (not just repo+file) so two unrelated items that happen to
touch the same file at different complexity tiers don't get merged into one misleading
count — see ovn_landed_detail.py's own tier handling for the same file for precedent.

Distinguishing "still stuck" from "self-resolved": if the SAME (repo, file, tier) key's
chronologically-LAST row in the window is a `pass`, the repeats already resolved themselves
(the struggle is over, just noisy in hindsight) — shown as "then landed" instead of "still
unresolved". This is a real, useful distinction: a stuck item still needs a human/Claude
look; a self-resolved one doesn't, even though both produced the same wall of no-op records.

Only signatures with >= --min-repeat (default 3) non-landed rows are shown — a single or
double no-op is normal fleet behavior (scout declined, or one genuine gate-revert), not the
repeat-failure pattern this exists to surface. Capped by --max-total, worst (highest count)
first, same message-size discipline as ovn_landed_detail.py.

Usage: ovn_noop_detail.py [hours=3] [--min-repeat N] [--max-total N] [--max-len N]
Prints an empty string (nothing to show) if there's no qualifying repeat activity in the
window — callers should skip the section entirely rather than print an empty header.
"""
import os
import re
import sys
import time

P = os.environ.get("TASK_STATS", os.path.expanduser("~/overnight-queue/state/task_stats.log"))
if not os.path.exists(P) and os.path.exists("state/task_stats.log"):
    P = "state/task_stats.log"

TAG_RE = re.compile(r'\{([^.·]*)[.·]([^.·]*)[.·]([^.·]*)[.·]([^}]*)\}')

# Same landed/failed/no-op partition as ovn_stats.py's c() — 'error' (network/timeout) and
# 'skip' (idle, nothing to do — deliberately not a no-op, see cycle_notify.sh) are excluded:
# neither represents a repeated STRUGGLE with an item, which is what this script surfaces.
NONLANDED_PREFIXES = ('fail', 'revert', 'noop')


def _int_arg(args, flag, default):
    if flag in args:
        i = args.index(flag)
        if i + 1 < len(args):
            try:
                return int(args[i + 1])
            except ValueError:
                pass
    return default


def _is_flag_value(argv, a):
    for flag in ('--min-repeat', '--max-total', '--max-len'):
        if flag in argv:
            i = argv.index(flag)
            if i + 1 < len(argv) and argv[i + 1] == a:
                return True
    return False


def main():
    argv = sys.argv[1:]
    pos = [a for a in argv if not a.startswith('--') and not _is_flag_value(argv, a)]
    hours = float(pos[0]) if pos else 3.0
    min_repeat = _int_arg(argv, '--min-repeat', 3)
    max_total = _int_arg(argv, '--max-total', 8)
    max_len = _int_arg(argv, '--max-len', 60)
    cutoff = time.time() - hours * 3600

    # key -> {'nonlanded': int, 'last_ts': float, 'last_oc': str}
    groups = {}
    if os.path.exists(P):
        for ln in open(P):
            parts = ln.rstrip("\n").split("\t")
            if len(parts) < 5:
                continue
            ts_raw, repo, oc, tag, fpath = parts[:5]
            try:
                ts = float(ts_raw)
            except ValueError:
                continue
            if ts < cutoff:
                continue
            if oc != 'pass' and not oc.startswith(NONLANDED_PREFIXES):
                continue  # 'error' / 'skip' / anything else — not a struggle signal
            m = TAG_RE.match(tag)
            tier = m.group(3) if m else '?'
            key = (repo, fpath, tier)
            g = groups.setdefault(key, {'nonlanded': 0, 'last_ts': -1.0, 'last_oc': ''})
            if oc != 'pass':
                g['nonlanded'] += 1
            # track the chronologically LAST row for this key (any outcome, including
            # 'pass') so we know whether the repeats ended in a landing or not.
            if ts >= g['last_ts']:
                g['last_ts'] = ts
                g['last_oc'] = oc

    rows = [(key, g) for key, g in groups.items() if g['nonlanded'] >= min_repeat]
    if not rows:
        return

    rows.sort(key=lambda kg: -kg[1]['nonlanded'])

    lines = [f"🔁 Repeat no-op/reverted (last {hours:g}h):"]
    total = 0
    for (repo, fpath, tier), g in rows:
        if total >= max_total:
            break
        fdisp = fpath if len(fpath) <= max_len else "…" + fpath[-(max_len - 1):]
        tier_disp = tier if (tier == '?' or tier.upper().startswith('T')) else f"T{tier}"
        if g['last_oc'] == 'pass':
            status = "then landed, self-resolved"
        else:
            status = "same item, still unresolved"
        lines.append(f"  {repo} ({tier_disp}): {fdisp} — failed {g['nonlanded']}x ({status})")
        total += 1
    if total == 0:
        return
    print("\n".join(lines))


if __name__ == "__main__":
    main()
