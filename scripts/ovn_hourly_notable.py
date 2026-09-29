#!/usr/bin/env python3
"""Notability gate for hourly_notify.sh (2026-09-28).

Problem this closes: hourly_notify.sh used to push a phone notification for EVERY
hour that had ANY activity at all — which on a continuously-running fleet is nearly
every hour, so in practice it tallied every single hour regardless of content. That
made it functionally indistinguishable from a plain hourly heartbeat and was one of
two scripts (with digest_notify.sh) responsible for the bulk of daily message volume
(26-30 of ~30-40/day on a normal day).

Fix: only call an hour "notable" — worth a phone push — when one of two things is
true, using the same canonical GOOD/BAD/BENIGN split as ovn_outcome_buckets.py:
  1. The hour was a genuine washout: zero landings (good=0) AND at least one wasted
     attempt (bad>=1 — a revert, a gate-reverted no-op, or a flailed no-op).
  2. The bad-bucket RATE this hour spikes meaningfully above the trailing baseline
     rate (computed over the window immediately preceding this hour, so the current
     hour's own bad events don't dilute the thing they're being compared against) —
     requires at least MIN_BAD_FOR_SPIKE bad events so a single unlucky attempt in an
     otherwise-quiet hour doesn't read as a "spike" off a near-zero baseline.
A normal hour of clean landings (the common case on a healthy fleet) is NOT notable
and prints nothing — that's the whole point of this gate.

Reads state/task_stats.log rows: <epoch>\\t<repo>\\t<oc>\\t{tag}\\t<file>  (same file
and format ovn_stats.py already reads). Honors the TASK_STATS env var override and a
cwd-relative "state/task_stats.log" fallback (same fallback shape as
ovn_landed_detail.py) so tests can point this at a fixture without touching $HOME.

Usage: ovn_hourly_notable.py [hours=1] [baseline_hours=24] [spike_margin=0.35] [min_bad_for_spike=2]
Prints "NOTABLE: <reason>" if this window is worth a push; prints nothing otherwise.
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ovn_outcome_buckets import bucket  # canonical GOOD/BAD/BENIGN split

P = os.environ.get("TASK_STATS", os.path.expanduser("~/overnight-queue/state/task_stats.log"))
if not os.path.exists(P) and os.path.exists("state/task_stats.log"):
    P = "state/task_stats.log"

args = sys.argv[1:]
hours = float(args[0]) if len(args) > 0 else 1.0
baseline_hours = float(args[1]) if len(args) > 1 else 24.0
spike_margin = float(args[2]) if len(args) > 2 else 0.35
min_bad_for_spike = int(args[3]) if len(args) > 3 else 2

now = time.time()
window_cutoff = now - hours * 3600
baseline_cutoff = now - baseline_hours * 3600


def load_rows():
    rows = []
    if not os.path.exists(P):
        return rows
    for ln in open(P):
        p = ln.rstrip("\n").split("\t")
        if len(p) < 3:
            continue
        ts_s, oc = p[0], p[2]
        try:
            ts = float(ts_s)
        except ValueError:
            continue
        rows.append((ts, oc))
    return rows


def counts(rows, lo, hi):
    good = bad = 0
    for ts, oc in rows:
        if not (lo <= ts < hi):
            continue
        b = bucket(oc)
        if b == "good":
            good += 1
        elif b == "bad":
            bad += 1
    return good, bad


def main():
    rows = load_rows()
    if not rows:
        return  # nothing recorded at all -> nothing to push
    good_w, bad_w = counts(rows, window_cutoff, now)

    # condition 1: a fully-wasted hour
    if good_w == 0 and bad_w >= 1:
        print(f"NOTABLE: a fully-wasted window — 0 landed, {bad_w} wasted attempt(s) "
              f"(reverted/gate-reverted/flailed)")
        return

    # condition 2: bad-rate spike vs. the trailing baseline (baseline excludes the
    # current window so a spike can't be diluted by/compared against itself)
    if bad_w >= min_bad_for_spike and (good_w + bad_w) > 0:
        rate_w = bad_w / (good_w + bad_w)
        good_b, bad_b = counts(rows, baseline_cutoff, window_cutoff)
        rate_b = (bad_b / (good_b + bad_b)) if (good_b + bad_b) > 0 else 0.0
        if rate_w - rate_b >= spike_margin:
            print(f"NOTABLE: wasted-attempt rate spiking — {rate_w*100:.0f}% this window "
                  f"vs {rate_b*100:.0f}% baseline ({bad_w} wasted of {good_w+bad_w})")
            return
    # otherwise: not notable, print nothing


if __name__ == "__main__":
    main()
