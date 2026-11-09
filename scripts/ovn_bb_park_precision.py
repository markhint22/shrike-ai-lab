#!/usr/bin/env python3
"""ovn_bb_park_precision.py - Z5 (2026-11-08): how good would OVN_BUILD_BREAK_PARK=enforce be? Read-only, stdlib only.

A "would-park event" = the Nth (N >= --after, default 2) consecutive reverted(build-break) outcome row of the SAME item_hash since that item last landed (the counter
lib_build_break_park.sh keeps). A "false park" = the item (same item_hash) LANDED afterwards, i.e. parking it would have cost a landing the lane achieved on its own.
Precision = never-landed events / events. The rule of thumb used for the flip: >= 80% precision.

  ovn_bb_park_precision.py --outcomes state/outcomes.jsonl [--days 7] [--after 2]     -> one JSON object on stdout
"""
import argparse
import collections
import datetime
import json
import sys


def _ts(r):
    return datetime.datetime.strptime(r["ts"], "%Y-%m-%dT%H:%M:%SZ")


def analyse(rows, days=7, after=2):
    rows = sorted((r for r in rows if r.get("ts") and r.get("item_hash")), key=_ts)
    if not rows:
        return {"events": 0, "false_parks": 0, "precision": None, "items": []}
    lo = _ts(rows[-1]) - datetime.timedelta(days=days)
    cnt = collections.Counter()
    events = []
    for i, r in enumerate(rows):
        k = r["item_hash"]
        if str(r.get("class", "")).startswith("landed"):
            cnt[k] = 0
        elif "build-break" in str(r.get("status", "")):
            cnt[k] += 1
            if cnt[k] >= after and _ts(r) >= lo:
                events.append((i, k, cnt[k]))
    per = collections.OrderedDict()
    false = 0
    for i, k, n in events:
        landed = any(x["item_hash"] == k and str(x.get("class", "")).startswith("landed") for x in rows[i + 1:])
        false += landed
        d = per.setdefault(k, {"item_hash": k[:6], "repo": rows[i].get("repo"), "events": 0, "landed_later": False, "max_count": 0})
        d["events"] += 1
        d["landed_later"] = d["landed_later"] or landed
        d["max_count"] = max(d["max_count"], n)
    n_ev = len(events)
    return {"events": n_ev, "false_parks": false, "precision": (round((n_ev - false) / float(n_ev), 3) if n_ev else None), "items": list(per.values())}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--outcomes", required=True)
    ap.add_argument("--days", type=float, default=7)
    ap.add_argument("--after", type=int, default=2)
    a = ap.parse_args(argv)
    rows = []
    try:
        with open(a.outcomes, encoding="utf-8", errors="replace") as fh:
            for ln in fh:
                try:
                    rows.append(json.loads(ln))
                except ValueError:
                    pass
    except OSError as e:
        print(json.dumps({"error": str(e)}))
        return 1
    print(json.dumps(analyse(rows, a.days, a.after)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
