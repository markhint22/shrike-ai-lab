#!/usr/bin/env python3
"""Tier-sliced throughput + token-spend stats for the ntfy digest.

Reads state/outcomes.jsonl (one line per finished task attempt: tier, class,
fail_reason, tokens_sent, tokens_recv — all written by run_overnight.sh's
record_outcome()) and produces a compact, ntfy-ready summary broken out by
tier T1-T5 (+ "?" for items with no explicit [T#] tag in their text).

Usage: ovn_tier_stats.py [hours=3] [--tokens-only] [--all-time]
--tokens-only prints just a one-line token-spend summary for the window (used to show a
rolling 24h total alongside the regular 3h tier breakdown, without duplicating the whole
tier table twice in one digest).
--all-time ignores the hours cutoff entirely and reports the full history in state/outcomes.jsonl
(the user's explicit "total tokens burned, ever" request — combine with --tokens-only for a
one-liner). Every token total this script prints also breaks out how much was spent on attempts
that did NOT land (severity not in good/expected — i.e. real failures/reverts/no-ops, not an
exhausted-queue skip that never attempted anything and so never spent anything) — 2026-09-16:
this used to be impossible to answer honestly for staged/T3+ items specifically, since
run_overnight.sh's record_outcome() had no token data for them at all (each step's aider call
logs to its own per-step file, never to the stdout record_outcome parses) — fixed at the source
in run_overnight.sh (sums the real per-step tokens_sent/tokens_recv from the run's own
state/stage_runs/*.jsonl, including failed/timed-out steps, before this script ever sees the row).

Also reads state/token_ledger.jsonl (2026-09-16) — a second, separate ledger for every LLM call
that happens OUTSIDE the main task loop: ovn_recover_parked.sh (item recovery/decomposition),
groom.sh (backlog grooming), ovn_planner.sh (roadmap decomposition, runs hourly), ovn_prework.sh
(Claude-bound briefings), supervisor.sh's local-27B review pass, reconcile_branches.sh's
LLM-assisted conflict resolution, and ovn_stage_runner.sh's own decompose call. All of these used
to pipe their LiteLLM response straight into `jq '.choices[0].message.content'`, discarding the
response's own `.usage` field — that spend wasn't lost, just invisible to every total up to now.
These aren't task attempts with a landed/didn't-land verdict, so they're reported as their own
"pipeline overhead" bucket by source, and folded into one genuine grand total alongside the task
spend above — this is the actual answer to "what did the whole fleet spend, total."

Prints an empty string (nothing to show) if there's no data in the window —
callers should skip the section entirely rather than print a "0 activity" line.
"""
import calendar
import json
import os
import sys
import time

P = os.path.expanduser("~/overnight-queue/state/outcomes.jsonl")
LEDGER = os.path.expanduser("~/overnight-queue/state/token_ledger.jsonl")
_args = [a for a in sys.argv[1:] if not a.startswith("--")]
tokens_only = "--tokens-only" in sys.argv[1:]
all_time = "--all-time" in sys.argv[1:]
hours = float(_args[0]) if _args else 3.0
cutoff = 0.0 if all_time else time.time() - hours * 3600


def load_ledger():
    out = []
    if not os.path.exists(LEDGER):
        return out
    for ln in open(LEDGER, encoding="utf-8", errors="ignore"):
        ln = ln.strip()
        if not ln:
            continue
        try:
            d = json.loads(ln)
        except ValueError:
            continue
        try:
            ts = calendar.timegm(time.strptime(d["ts"], "%Y-%m-%dT%H:%M:%SZ"))
        except (KeyError, ValueError):
            continue
        if ts < cutoff:
            continue
        d["_ts"] = ts
        out.append(d)
    return out


def is_failure(row):
    # a real failure/waste: attempted something and it did NOT land. Excludes 'expected'
    # (skip(exhausted) etc. — never attempted anything, spent nothing) and 'good' (landed).
    return row.get("severity") not in ("good", "expected")

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

ledger_rows = load_ledger()

if not rows and not ledger_rows:
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


def ledger_summary():
    """-> (total_sent, total_recv, {source: [sent, recv, count]}) for every LLM call OUTSIDE
    the main task loop (recovery/planning/grooming/review/reconcile-selfheal/stage-decompose)."""
    total_sent = sum(r.get("tokens_sent", 0) or 0 for r in ledger_rows)
    total_recv = sum(r.get("tokens_recv", 0) or 0 for r in ledger_rows)
    by_source = {}
    for r in ledger_rows:
        s = r.get("source", "?")
        bs = by_source.setdefault(s, [0, 0, 0])
        bs[0] += r.get("tokens_sent", 0) or 0
        bs[1] += r.get("tokens_recv", 0) or 0
        bs[2] += 1
    return total_sent, total_recv, by_source


if tokens_only:
    total_sent = sum(r.get("tokens_sent", 0) or 0 for r in rows)
    total_recv = sum(r.get("tokens_recv", 0) or 0 for r in rows)
    ledger_sent, ledger_recv, by_source = ledger_summary()
    if not (total_sent or total_recv or ledger_sent or ledger_recv):
        print("")
        sys.exit(0)
    fail_rows = [r for r in rows if is_failure(r)]
    fail_sent = sum(r.get("tokens_sent", 0) or 0 for r in fail_rows)
    fail_recv = sum(r.get("tokens_recv", 0) or 0 for r in fail_rows)
    window = "all-time" if all_time else f"last {hours:g}h"
    line = f"🔤 {window} tokens: {fmt_toks(total_sent)} sent / {fmt_toks(total_recv)} received ({len(rows)} tasks)"
    if fail_sent or fail_recv:
        pct = 100 * (fail_sent + fail_recv) // max(total_sent + total_recv, 1)
        line += f"\n   💸 of which on non-landed attempts: {fmt_toks(fail_sent)} sent / {fmt_toks(fail_recv)} received ({pct}%, {len(fail_rows)} tasks)"
    if ledger_sent or ledger_recv:
        line += (f"\n   🔧 pipeline overhead (planning/grooming/recovery/review, outside task "
                 f"attempts): {fmt_toks(ledger_sent)} sent / {fmt_toks(ledger_recv)} received "
                 f"({len(ledger_rows)} calls)")
        top_src = sorted(by_source.items(), key=lambda kv: -(kv[1][0] + kv[1][1]))[:5]
        line += "\n      " + " · ".join(f"{s} {fmt_toks(v[0] + v[1])}" for s, v in top_src)
        grand_sent, grand_recv = total_sent + ledger_sent, total_recv + ledger_recv
        line += f"\n   Σ overall (tasks + overhead): {fmt_toks(grand_sent)} sent / {fmt_toks(grand_recv)} received"
    print(line)
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
    # 2026-09-17: "T?" looked like a data-quality gap (untagged/unknown work) but is
    # actually just the ongoing-* background lanes, which never carry a [T#] queue-item
    # tag by design (they are not sourced from OVERNIGHT_PROGRESS.md items). The denominator
    # here already excludes skip(exhausted) noise - this bucket is real, correctly-measured
    # ongoing-lane activity, not unclassified mystery work. Label it plainly so a digest
    # reader does not mistake it for a bug.
    label = f"T{t}" if t != "?" else "Ongoing-lane"
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

ledger_sent, ledger_recv, by_source = ledger_summary()

if not lines and not (ledger_sent or ledger_recv):
    print("")
    sys.exit(0)

window_label = "all-time" if all_time else "last %gh" % hours
out = ["📊 By tier (%s):" % window_label] + lines if lines else []
if total_timeouts:
    out.append(f"⏱ {total_timeouts} timeout(s) total this window")
if total_sent or total_recv:
    out.append(f"🔤 Tokens: {fmt_toks(total_sent)} sent / {fmt_toks(total_recv)} received")
    fail_rows = [r for r in rows if is_failure(r)]
    fail_sent = sum(r.get("tokens_sent", 0) or 0 for r in fail_rows)
    fail_recv = sum(r.get("tokens_recv", 0) or 0 for r in fail_rows)
    if fail_sent or fail_recv:
        pct = 100 * (fail_sent + fail_recv) // max(total_sent + total_recv, 1)
        out.append(f"💸 On non-landed attempts: {fmt_toks(fail_sent)} sent / {fmt_toks(fail_recv)} received ({pct}%)")
if ledger_sent or ledger_recv:
    out.append(f"🔧 Pipeline overhead (planning/grooming/recovery/review): "
               f"{fmt_toks(ledger_sent)} sent / {fmt_toks(ledger_recv)} received ({len(ledger_rows)} calls)")
    top_src = sorted(by_source.items(), key=lambda kv: -(kv[1][0] + kv[1][1]))[:5]
    out.append("   " + " · ".join(f"{s} {fmt_toks(v[0] + v[1])}" for s, v in top_src))
if (total_sent or total_recv) and (ledger_sent or ledger_recv):
    out.append(f"Σ Overall (tasks + overhead): {fmt_toks(total_sent + ledger_sent)} sent / "
               f"{fmt_toks(total_recv + ledger_recv)} received")

print("\n".join(out))
