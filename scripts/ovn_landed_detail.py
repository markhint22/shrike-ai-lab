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

2026-09-20: each landed line now also shows which FEATURE the item belongs to, when it
has one — "billwatch (T2, feature: "Bill Summary Caching"): trending_service.py" instead
of just "billwatch (T2·other): trending_service.py" — by asking ovn_feature_groups.py
(same directory) which real [feat:ID] group (if any) contains this repo+file, then
resolving that id to a human title from roadmap/<repo>.md. Items with no feature tag
(older/ungrouped backlog, or a title that can't be resolved) keep the original
file-only format unchanged — never fabricated.
"""
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    import ovn_feature_groups as _ofg
except Exception:
    _ofg = None

P = os.environ.get("TASK_STATS", os.path.expanduser("~/overnight-queue/state/task_stats.log"))
if not os.path.exists(P) and os.path.exists("state/task_stats.log"):
    P = "state/task_stats.log"

# 2026-10-09 (harness-credit-integrity item 4): task_stats.log (the source below) cannot tell a credited landing from a green push the auto-credit refused to
# tick, so the uncredited pushes are counted from state/outcomes.jsonl (class landed-uncredited) and shown as their own line.
OUTCOMES = os.environ.get("OUTCOMES", os.path.join(os.path.dirname(os.path.abspath(P)), "outcomes.jsonl"))
UNCREDITED_CLASS = "landed-uncredited"

TAG_RE = re.compile(r'\{([^.·]*)[.·]([^.·]*)[.·]([^.·]*)[.·]([^}]*)\}')

_feat_cache = {}


def _feature_for(repo, fpath):
    """-> (feat_id, title_or_None) for this repo+file, or None — memoized per repo so a
    digest with several landed lines from the same repo only parses that repo's
    OVERNIGHT_PROGRESS.md/OVERNIGHT_DONE.md/roadmap once. Any failure (missing module,
    malformed data) degrades to "no attribution" rather than breaking the whole listing —
    this is enrichment, not the core function of this script."""
    if _ofg is None:
        return None
    if repo not in _feat_cache:
        try:
            _feat_cache[repo] = {
                r["key"]: r for r in _ofg.repo_groups(repo, min_total=2) if r["kind"] == "feat"
            }
        except Exception:
            _feat_cache[repo] = {}
    for feat_id, r in _feat_cache[repo].items():
        if fpath in r["_files"]:
            try:
                return feat_id, _ofg.feature_title(repo, feat_id)
            except Exception:
                return feat_id, None
    return None


def _uncredited_by_repo(cutoff):
    """{repo: n} of landed-uncredited rows newer than cutoff (epoch seconds) in outcomes.jsonl; any read/parse problem => {} (enrichment only)."""
    out = {}
    try:
        import datetime
        with open(OUTCOMES, errors="replace") as fh:
            for ln in fh:
                if UNCREDITED_CLASS not in ln:
                    continue
                try:
                    o = json.loads(ln)
                    t = datetime.datetime.fromisoformat(str(o.get("ts", "")).replace("Z", "+00:00")).timestamp()
                except Exception:
                    continue
                if o.get("class") != UNCREDITED_CLASS or t < cutoff:
                    continue
                out[o.get("repo", "?")] = out.get(o.get("repo", "?"), 0) + 1
    except OSError:
        return {}
    return out


def _uncredited_line(by_repo):
    n = sum(by_repo.values())
    if not n:
        return ""
    top = ", ".join("%s %d" % (r, c) for r, c in sorted(by_repo.items(), key=lambda kv: -kv[1])[:4])
    return "⚠️ %d uncredited push%s (green, item not ticked: %s)" % (n, "" if n == 1 else "es", top)


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
    _fv = _flag_value_indexes(argv)
    pos = [a for i, a in enumerate(argv) if not a.startswith('--') and i not in _fv]
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

    unc = _uncredited_line(_uncredited_by_repo(cutoff))
    if not by_repo:
        if unc:
            print(unc)
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
            feat = _feature_for(repo, fpath)
            if feat and feat[1]:
                lines.append(f'  {repo} ({tier_disp}, feature: "{feat[1]}"): {fdisp}')
            elif feat:
                # has a real [feat:ID] tag but the title couldn't be resolved (e.g. the
                # roadmap line was since edited/removed) — show the real id rather than
                # silently reverting to the plain format OR fabricating a name.
                lines.append(f"  {repo} ({tier_disp}, feature: {feat[0]}): {fdisp}")
            else:
                lines.append(f"  {repo} ({tier_disp}·{cat}): {fdisp}")
            total += 1
    if total == 0:
        if unc:
            print(unc)
        return
    if unc:
        lines.append(unc)
    print("\n".join(lines))


def _flag_value_indexes(argv):
    """Indexes of argv elements that are the VALUE of a flag (2026-09-30: matching by value swallowed a positional equal to a flag's value)."""
    idx = set()
    for flag in ('--max-per-repo', '--max-total', '--max-len'):
        if flag in argv:
            i = argv.index(flag)
            if i + 1 < len(argv):
                idx.add(i + 1)
    return idx


if __name__ == "__main__":
    main()
