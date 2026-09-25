#!/usr/bin/env python3
"""Research-batch scorecard (2026-09-23, letter-grade redesign 2026-09-25).

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

2026-09-25: the original "worst 10, sorted worst-first" view made a healthy fleet
look alarming — the ntfy title ("N struggling batches") only ever reflected how many
of the shown top-10 were bad, not the true count or the overall shape of the
distribution (a batch at 91% landed looks identical in the alert to one at 9% until
you read every line). Real data pulled once found 22 total batches, 11 flagged, and
several sitting at 90-100% — a materially better picture than "10 struggling
batches" suggested standalone. Added a letter-grade distribution (computed over
EVERY batch in scope, not just the ones shown in detail) so the top-line number
answers "how healthy is the research pipeline as a whole," and the flagged-batch
detail list is no longer artificially capped at 10 — every D/F batch is listed
(the thing that needs a look), and only a genuinely large detail list gets an
explicit "...and N more" footer instead of the previous silent `head -c 800` cutoff
in the ntfy wrapper.

Grade scale (of item land-rate within the batch): A >=90%, B >=75%, C >=50%,
D >=25%, F <25%. C/D/F all used to trip the old "<50% = struggling" flag; kept D/F
as the actionable "needs a look" bucket (below is-mostly-working) and split out C as
"landing, but below half its stated items and worth a glance" — shown in the summary
counts but not in the per-item detail list, to keep the alert focused on the batches
that actually need attention.

Usage: ovn_batch_scorecard.py [hours=all-time] [--min-age-hours=24] [--worst=N]
`--worst` now bounds the D/F *detail* list only (default: no cap — show them all).
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
worst_n = None  # None = show every D/F batch, no cap
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


def grade(pct):
    if pct >= 90:
        return "A"
    if pct >= 75:
        return "B"
    if pct >= 50:
        return "C"
    if pct >= 25:
        return "D"
    return "F"


GRADE_LABEL = {
    "A": "A (90-100%)",
    "B": "B (75-89%)",
    "C": "C (50-74%)",
    "D": "D (25-49%)",
    "F": "F (0-24%)",
}

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
    g = grade(pct)
    lines.append((pct, g, tag, b["repo"], landed, reverted, noop, n, toks, age_h))

if not lines:
    sys.exit(0)

total = len(lines)
counts = {"A": 0, "B": 0, "C": 0, "D": 0, "F": 0}
for pct, g, *_ in lines:
    counts[g] += 1

# Worst land-rate first for the detail list — a struggling batch is the actionable
# signal, a clean one needs no follow-up.
lines.sort(key=lambda x: x[0])

out = ["📋 Research-batch scorecard: %d batch(es) >=%gh old" % (total, min_age_hours)]
out.append("")
out.append("Grade distribution:")
for g in ("A", "B", "C", "D", "F"):
    n = counts[g]
    pct_of_total = round(100 * n / total) if total else 0
    bar = "█" * round(pct_of_total / 5)
    out.append(f"  {GRADE_LABEL[g]:<13} {n:>3} batch(es)  {pct_of_total:>3}%  {bar}")

flagged = [l for l in lines if l[1] in ("D", "F")]
out.append("")
if flagged:
    shown = flagged[:worst_n] if worst_n else flagged
    out.append(f"⚠️  {len(flagged)} batch(es) graded D/F — worth a look:")
    for pct, g, tag, repo, landed, reverted, noop, n, toks, age_h in shown:
        out.append(
            f"  {g} {repo}/{tag}: {landed}/{n} landed ({pct}%) · {reverted} reverted · "
            f"{noop} no-op · {toks} tok · {age_h:.0f}h old"
        )
    if len(flagged) > len(shown):
        out.append(f"  ...and {len(flagged) - len(shown)} more D/F batch(es) not shown")
else:
    out.append("No D/F batches — nothing needs a look right now.")

# Machine-parseable summary line for the ntfy wrapper (avoids re-deriving counts by
# grepping the human-readable text above, which is what made the old title
# undercount whenever the detail list was capped or truncated).
out.append("")
out.append(
    "#SUMMARY total=%d A=%d B=%d C=%d D=%d F=%d flagged=%d"
    % (total, counts["A"], counts["B"], counts["C"], counts["D"], counts["F"], len(flagged))
)

print("\n".join(out))
