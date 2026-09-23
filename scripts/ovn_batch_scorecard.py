#!/usr/bin/env python3
"""Research-batch scorecard (2026-09-23).

Every research/decompose pass tags the items it writes with a shared [feat:<repo>-
<date>-<slug>] tag in backlog/<repo>.md (already the established convention — see
e.g. [feat:billwatch-20260922-finish-export-webhook-dead-code]). Until now there was
no way to answer "how did that specific research batch actually perform once the
fleet worked it" without hand-grepping outcomes.jsonl for one tag at a time.

record_outcome() (run_overnight.sh) now writes the raw feat_tag (not just its hash)
onto every outcome row it can identify one for. This script groups by feat_tag and
reports landed/reverted/no-op counts and token spend per batch, so a batch that
mostly failed is visible as a batch-quality signal (e.g. "the research pass that
generated these 12 items got 2 landed / 10 reverted" points at THAT PASS's prompting
or file-grounding, not at 12 unrelated one-off failures).

Only reports batches with an outcome ROW at least min_age_hours old (default 24) so
a batch check doesn't fire before the fleet has actually had a chance to work it, per
the original ask ("~24h after landing"). Rows with no feat_tag (most T1/T2 one-off
items, and all pre-2026-09-23 history) are not part of any batch and are silently
excluded — this script answers "how are BATCHES doing," not "how is everything doing"
(that's ovn_tier_stats.py's job).

Usage: ovn_batch_scorecard.py [hours=all-time] [--min-age-hours=24] [--worst=10]
Prints nothing if there are no feat-tagged rows old enough to report on.
"""
import calendar
import re
import sys
import time
import json
import os

P = os.path.expanduser("~/overnight-queue/state/outcomes.jsonl")

_args = [a for a in sys.argv[1:] if not a.startswith("--")]
hours = float(_args[0]) if _args else 0.0
cutoff = time.time() - hours * 3600 if hours else 0.0

min_age_hours = 24.0
for a in sys.argv[1:]:
    m = re.match(r'--min-age-hours=([\d.]+)', a)
    if m:
        min_age_hours = float(m.group(1))
worst_n = 10
for a in sys.argv[1:]:
    m = re.match(r'--worst=(\d+)', a)
    if m:
        worst_n = int(m.group(1))

now = time.time()


def parse_ts(ts):
    try:
        return calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))
    except Exception:
        return None


batches = {}
try:
    with open(P) as f:
        for line in f:
            try:
                r = json.loads(line)
            except Exception:
                continue
            tag = r.get("feat_tag") or ""
            if not tag:
                continue
            t = parse_ts(r.get("ts", ""))
            if t is None or t < cutoff:
                continue
            b = batches.setdefault(tag, {"rows": [], "repo": r.get("repo", "?")})
            b["rows"].append(r)
except FileNotFoundError:
    sys.exit(0)

if not batches:
    sys.exit(0)

lines = []
for tag, b in sorted(batches.items()):
    rows = b["rows"]
    first_ts = min(parse_ts(r.get("ts", "")) or now for r in rows)
    age_h = (now - first_ts) / 3600.0
    if age_h < min_age_hours:
        continue
    landed = sum(1 for r in rows if r.get("class") == "landed")
    reverted = sum(1 for r in rows if r.get("class") == "reverted")
    noop = sum(1 for r in rows if r.get("class") == "noop")
    n = len(rows)
    pct = 100 * landed // n if n else 0
    toks = sum((r.get("tokens_sent", 0) or 0) + (r.get("tokens_recv", 0) or 0) for r in rows)
    lines.append((pct, tag, b["repo"], landed, reverted, noop, n, toks, age_h))

if not lines:
    sys.exit(0)

# Worst land-rate first — a struggling batch is the actionable signal here, not a
# clean one (a 100% batch needs no follow-up).
lines.sort(key=lambda x: x[0])

out = ["📋 Research-batch scorecard (batches >=%gh old):" % min_age_hours]
for pct, tag, repo, landed, reverted, noop, n, toks, age_h in lines[:worst_n]:
    flag = "⚠️ " if pct < 50 else ""
    out.append(
        f"  {flag}{repo}/{tag}: {landed}/{n} landed ({pct}%) · {reverted} reverted · "
        f"{noop} no-op · {toks} tok · {age_h:.0f}h old"
    )
if len(lines) > worst_n:
    out.append(f"  ...and {len(lines) - worst_n} more batch(es) not shown")

print("\n".join(out))
