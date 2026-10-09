#!/usr/bin/env python3
"""flake_stats.py - per-spec reliability from <state>/qa_devicelane/history.jsonl (one line per nightly run).

  flake_stats.py [--history FILE] [--json] [--min-runs 5]

Per spec over N runs:  first_fail = attempt 1 failed;  flaky = failed then passed on retry;  hard_fail = failed both attempts.
  reliable   0 first-attempt failures over >= min-runs runs
  flaky      some first-attempt failures but passes after retry at least once, never hard-failed in a majority of runs
  broken     hard-failed in a majority of runs
  skipped    always skipped (feature absent in the build)
Overall flake rate = spec-runs with a first-attempt failure / spec-runs that were not skipped. The plan promotes the lane out of
advisory only when this stays under 2% for two weeks.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import qa_common  # noqa: E402


def load(path):
    rows = []
    try:
        with open(path) as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        rows.append(json.loads(line))
                    except ValueError:
                        pass
    except OSError:
        pass
    return rows


def stats(rows, min_runs=5):
    per = {}
    for r in rows:
        for spec, st in r.get("specs", {}).items():
            d = per.setdefault(spec, {"runs": 0, "skipped": 0, "first_fail": 0, "flaky": 0, "hard_fail": 0, "pass_first": 0})
            if st["final"] == "skip":
                d["skipped"] += 1
                continue
            if st["final"] == "not_run":
                continue
            d["runs"] += 1
            if st["first"] in ("fail", "timeout"):
                d["first_fail"] += 1
            if st["final"] == "flaky":
                d["flaky"] += 1
            if st["final"] in ("fail", "timeout"):
                d["hard_fail"] += 1
            if st["first"] == "pass":
                d["pass_first"] += 1
    for spec, d in per.items():
        n = d["runs"]
        if n == 0:
            d["class"] = "skipped"
        elif d["hard_fail"] * 2 > n:
            d["class"] = "broken"
        elif d["first_fail"] == 0 and n >= min_runs:
            d["class"] = "reliable"
        elif d["first_fail"] == 0:
            d["class"] = "reliable_so_far(<%d runs)" % min_runs
        else:
            d["class"] = "flaky"
    tot = sum(d["runs"] for d in per.values())
    ff = sum(d["first_fail"] for d in per.values())
    return {"runs": len(rows), "spec_runs": tot, "first_attempt_failures": ff,
            "flake_rate_pct": round(100.0 * ff / tot, 2) if tot else None, "per_spec": per}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--history", default=os.path.join(qa_common.state_dir(), "qa_devicelane", "history.jsonl"))
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--min-runs", type=int, default=5)
    a = ap.parse_args(argv)
    s = stats(load(a.history), a.min_runs)
    if a.json:
        print(json.dumps(s, indent=1, sort_keys=True))
        return 0
    print("runs=%d spec-runs=%d first-attempt failures=%d flake rate=%s%%" % (s["runs"], s["spec_runs"], s["first_attempt_failures"], s["flake_rate_pct"]))
    print("%-36s %5s %5s %5s %5s  %s" % ("spec", "runs", "1stF", "flaky", "hardF", "class"))
    for spec, d in sorted(s["per_spec"].items(), key=lambda kv: (kv[1]["class"], kv[0])):
        print("%-36s %5d %5d %5d %5d  %s" % (spec, d["runs"], d["first_fail"], d["flaky"], d["hard_fail"], d["class"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
