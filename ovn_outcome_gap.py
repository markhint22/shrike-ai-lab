#!/usr/bin/env python3
"""Outcome-gap monitor (2026-10-15, SHADOW only).

The 2026-10-14 night wrote zero outcomes from 21:00 to 05:00 CDT and nothing flagged it until a human read the archive. This watches the
newest row in state/outcomes.jsonl (ts is UTC, ISO 8601 with a Z) and, when it is older than --max-min and the queue is NOT deliberately
paused, appends a WOULD-ALERT line to --log. It never pages and never changes queue behaviour: the mode is fixed to shadow until a human
decides otherwise (see the 2026-10-14 review).

usage: ovn_outcome_gap.py --outcomes FILE --pause-flag FILE --log FILE [--max-min 60] [--now EPOCH] [--mode shadow]
exit: 0 always for a normal check (including a gap or a pause); 2 for bad arguments.
"""
import argparse
import datetime as _dt
import json
import os
import sys
import time


def last_ts(path):
    """Epoch seconds of the newest outcome row that has a parseable ts, or None when there is none."""
    if not os.path.isfile(path):
        return None
    newest = None
    with open(path, "rb") as fh:
        # the file is append-only and can be large; the last ~64 KB holds the newest rows
        try:
            fh.seek(0, os.SEEK_END)
            size = fh.tell()
            fh.seek(max(0, size - 65536))
        except OSError:
            fh.seek(0)
        for raw in fh.read().decode("utf-8", "replace").splitlines():
            raw = raw.strip()
            if not raw:
                continue
            try:
                ts = json.loads(raw).get("ts", "")
                dt = _dt.datetime.strptime(ts, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=_dt.timezone.utc)
            except (ValueError, AttributeError, TypeError):
                continue
            epoch = dt.timestamp()
            if newest is None or epoch > newest:
                newest = epoch
    return newest


def decide(now, last, paused, max_min):
    """Return (state, gap_min). state is one of: paused, no-outcomes, ok, WOULD-ALERT."""
    if paused:
        return "paused", None
    if last is None:
        return "no-outcomes", None
    gap_min = (now - last) / 60.0
    if gap_min > max_min:
        return "WOULD-ALERT", gap_min
    return "ok", gap_min


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--outcomes", required=True)
    ap.add_argument("--pause-flag", required=True)
    ap.add_argument("--log", required=True)
    ap.add_argument("--max-min", type=float, default=60.0)
    ap.add_argument("--now", type=float, default=None)
    ap.add_argument("--mode", default="shadow")
    args = ap.parse_args(argv)
    if args.mode != "shadow":
        print("ovn_outcome_gap: only --mode shadow is supported (no enforcement without a human decision)", file=sys.stderr)
        return 2
    if args.max_min <= 0:
        print("ovn_outcome_gap: --max-min must be positive", file=sys.stderr)
        return 2
    now = args.now if args.now is not None else time.time()
    paused = os.path.exists(args.pause_flag)
    state, gap = decide(now, last_ts(args.outcomes), paused, args.max_min)
    if state in ("WOULD-ALERT", "no-outcomes"):
        detail = "gap_min=%.0f max_min=%.0f" % (gap, args.max_min) if gap is not None else "outcomes.jsonl empty or missing"
        line = "%s %s %s\n" % (_dt.datetime.fromtimestamp(now, _dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), state, detail)
        os.makedirs(os.path.dirname(os.path.abspath(args.log)), exist_ok=True)
        with open(args.log, "a", encoding="utf-8") as fh:
            fh.write(line)
    print(state if gap is None else "%s gap_min=%.1f" % (state, gap))
    return 0


if __name__ == "__main__":
    sys.exit(main())
