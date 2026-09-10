#!/usr/bin/env python3
"""Tier-sliced throughput + token-spend stats for the ntfy digest.

Reads state/outcomes.jsonl (one line per finished task attempt: tier, class,
fail_reason, tokens_sent, tokens_recv — all written by run_overnight.sh's
record_outcome()) and produces a compact, ntfy-ready summary broken out by
tier T1-T5 (+ "?" for items with no explicit [T#] tag in their text).

Usage: ovn_tier_stats.py [hours=3] [--tokens-only]
--tokens-only prints just a one-line token-spend summary for the window (used to show a
rolling 24h total alongside the regular 3h tier breakdown, without duplicating the whole
tier table twice in one digest).
Prints an empty string (nothing to show) if there's no data in the window —
callers should skip the section entirely rather than print a "0 activity" line.
"""
import calendar
import json
import os
import sys
import time

P = os.path.expanduser("~/overnight-queue/state/outcomes.jsonl")
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
tokens_only = "--tokens-only" in sys.argv[1:]
hours = float(_args[0]) if _args else 3.0
cutoff = time.time() - hours * 3600

rows = []
if os.path.exists(P):
    for ln in open(P, encoding="utf-8", errors="ignore"):
        ln = ln.strip()
        if not ln:
            continue
        try:
            d = json.loads(ln)
        except ValueError:
            continue
        try:
            # timegm (not mktime) - the "Z" suffix means this IS UTC; mktime would
            # misinterpret it as local time and need a DST-unsafe manual correction.
            ts = calendar.timegm(time.strptime(d["ts"], "%Y-%m-%dT%H:%M:%SZ"))
        except (KeyError, ValueError):
            continue
        if ts < cutoff:
            continue
        d["_ts"] = ts
        rows.append(d)

if not rows:
    print("")
    sys.exit(0)


def fmt_toks(n):
    n = int(n)
    if n >= 1_000_000:
        return "%.1fM" % (n / 1_000_000)
    if n >= 100_000:
        return "%.0fk" % (n / 1_000)   # e.g. 250k - a decimal adds no real info at this scale
    if n >= 1_000:
        return "%.1fk" % (n / 1_000)   # e.g. 1.8k - zero decimals would round 1800 -> "2k"
    return str(n)


if tokens_only:
    total_sent = sum(r.get("tokens_sent", 0) or 0 for r in rows)
    total_recv = sum(r.get("tokens_recv", 0) or 0 for r in rows)
    if not (total_sent or total_recv):
        print("")
        sys.exit(0)
    print(f"🔤 Last {hours:g}h tokens: {fmt_toks(total_sent)} sent / {fmt_toks(total_recv)} received ({len(rows)} tasks)")
    sys.exit(0)


TIER_ORDER = ["1", "2", "3", "4", "5", "?"]
by_tier = {t: [] for t in TIER_ORDER}
for r in rows:
    t = str(r.get("tier") or "?")
    if t not in by_tier:
        t = "?"
    by_tier[t].append(r)

lines = []
total_sent = sum(r.get("tokens_sent", 0) or 0 for r in rows)
total_recv = sum(r.get("tokens_recv", 0) or 0 for r in rows)
total_timeouts = sum(1 for r in rows if r.get("fail_reason") == "timeout")

for t in TIER_ORDER:
    sub = by_tier[t]
    if not sub:
        continue
    # rate denominator excludes 'skipped' (an exhausted/empty repo never attempted
    # anything) so an idle repo doesn't drag down the tier's real success rate.
    attempted = [r for r in sub if r.get("class") != "skipped"]
    landed = sum(1 for r in attempted if r.get("class") == "landed")
    noop = sum(1 for r in attempted if r.get("class") == "noop")
    reverted = sum(1 for r in attempted if r.get("class") == "reverted")
    other_bad = sum(1 for r in attempted if r.get("class") in ("error", "oversized", "unknown", "held"))
    timeouts = sum(1 for r in attempted if r.get("fail_reason") == "timeout")
    n = len(attempted)
    if n == 0:
        continue
    pct = 100 * landed // n
    label = f"T{t}" if t != "?" else "T?"
    bits = [f"{label}: {landed}/{n} ({pct}%)"]
    extra = []
    if noop:
        extra.append(f"{noop} no-op")
    if reverted:
        extra.append(f"{reverted} reverted")
    if timeouts:
        extra.append(f"{timeouts} timeout")
    if other_bad:
        extra.append(f"{other_bad} other")
    if extra:
        bits.append(" · ".join(extra))
    lines.append("  " + "  ·  ".join(bits))

if not lines:
    print("")
    sys.exit(0)

out = ["📊 By tier (last %gh):" % hours] + lines
if total_timeouts:
    out.append(f"⏱ {total_timeouts} timeout(s) total this window")
if total_sent or total_recv:
    out.append(f"🔤 Tokens: {fmt_toks(total_sent)} sent / {fmt_toks(total_recv)} received")

print("\n".join(out))
