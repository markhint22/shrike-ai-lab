#!/usr/bin/env python3
"""lane_report.py - turn a device-lane outcome into the canonical QA verdict (shadow log + one JSON line).

  lane_report.py infra   --reason TEXT [--sha S] [--run-dir D]       -> UNVERIFIED (could not run: never PASS, never FAIL)
  lane_report.py results --results results.json [--sha S] [--run-dir D] [--boot-seconds N] [--build-seconds N]

The device lane is ADVISORY: it can say PASS, FLAG or UNVERIFIED, never FAIL (so nothing can ever block on it).
  PASS        every non-skipped spec passed on the first attempt, no app crash/ANR in logcat
  FLAG        some spec failed twice / timed out / was flaky (failed then passed) / the app crashed during a passing spec
  UNVERIFIED  infra problem, or EVERY spec failed (that pattern means the environment, not the app, is broken)
Also appends one line per run to <state>/qa_devicelane/history.jsonl (per-spec first/final status) for flake_stats.py.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import qa_common  # noqa: E402

GATE = "devicelane"


def lane_state():
    d = os.path.join(qa_common.state_dir(), "qa_devicelane")
    os.makedirs(d, exist_ok=True)
    return d


def load_quarantine():
    """known_issues.json -> {spec: {category, reason}} minus entries whose `unless_env` variable is set (fixture now available)."""
    try:
        with open(os.path.join(HERE, "known_issues.json")) as f:
            raw = json.load(f)
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in raw.items() if not k.startswith("_") and isinstance(v, dict)
            and not (v.get("unless_env") and os.environ.get(v["unless_env"]))}


def build(args):
    ref = (args.sha or "?")[:12]
    if args.cmd == "infra":
        return qa_common.verdict("UNVERIFIED", GATE, "iptv_apps", ref, "device lane could not run: %s" % args.reason,
                                 {"run_dir": args.run_dir, "advisory": True})
    with open(args.results) as f:
        doc = json.load(f)
    specs = doc.get("specs", [])
    quarantine = load_quarantine()
    all_ran = [s for s in specs if s["status"] not in ("skip", "not_run")]
    ran = [s for s in all_ran if s["spec"] not in quarantine]
    quarantined_failing = [s["spec"] for s in all_ran if s["spec"] in quarantine and s["status"] in ("fail", "timeout")]
    recovered = [s["spec"] for s in all_ran if s["spec"] in quarantine and s["status"] in ("pass", "flaky")]
    bad = [s["spec"] for s in ran if s["status"] in ("fail", "timeout")]
    flaky = [s["spec"] for s in ran if s["status"] == "flaky"]
    crashed = [s["spec"] for s in ran if s.get("app_crash_in_logcat")]
    details = {"counts": doc.get("counts", {}), "failed": bad, "flaky": flaky, "app_crash_or_anr": crashed,
               "seconds": doc.get("seconds"), "boot_seconds": args.boot_seconds, "build_seconds": args.build_seconds,
               "run_dir": args.run_dir, "advisory": True,
               "quarantined_failing": {k: quarantine[k].get("category") for k in quarantined_failing},
               "quarantine_recovered_remove_from_known_issues": recovered}
    if not ran:
        return qa_common.verdict("UNVERIFIED", GATE, "iptv_apps", ref, "no spec produced a pass/fail result", details)
    if len(bad) == len(ran) and len(ran) >= 3:
        return qa_common.verdict("UNVERIFIED", GATE, "iptv_apps", ref,
                                 "ALL %d specs failed - environment (staging/emulator/appium) suspected, not the app" % len(ran), details)
    if bad or flaky or crashed:
        parts = []
        if bad:
            parts.append("%d failed twice/timed out (%s)" % (len(bad), ", ".join(bad[:5])))
        if flaky:
            parts.append("%d flaky" % len(flaky))
        if crashed:
            parts.append("app crash/ANR in logcat during %d spec(s)" % len(crashed))
        return qa_common.verdict("FLAG", GATE, "iptv_apps", ref, "; ".join(parts), details)
    return qa_common.verdict("PASS", GATE, "iptv_apps", ref, "%d specs passed first try" % len(ran), details)


def history_line(args, res):
    if args.cmd != "results":
        return None
    with open(args.results) as f:
        doc = json.load(f)
    return {"ts": res["ts"], "sha": (args.sha or "?")[:12], "verdict": res["verdict"], "seconds": doc.get("seconds"),
            "specs": {s["spec"]: {"first": (s["attempts"][0]["status"] if s["attempts"] else s["status"]), "final": s["status"]}
                      for s in doc.get("specs", [])}}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("cmd", choices=["infra", "results"])
    ap.add_argument("--reason", default="")
    ap.add_argument("--results")
    ap.add_argument("--sha", default="")
    ap.add_argument("--run-dir", default="")
    ap.add_argument("--boot-seconds", type=float, default=None)
    ap.add_argument("--build-seconds", type=float, default=None)
    ap.add_argument("--no-record", action="store_true")
    args = ap.parse_args(argv)
    res = build(args)
    if not args.no_record:
        qa_common.record(res)
        try:
            h = history_line(args, res)
            if h:
                with open(os.path.join(lane_state(), "history.jsonl"), "a") as f:
                    f.write(json.dumps(h, sort_keys=True) + "\n")
            with open(os.path.join(lane_state(), "last_run.json"), "w") as f:
                json.dump(res, f, indent=1)
        except OSError:
            pass
    print(json.dumps(res, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception as ex:  # noqa: BLE001
        print(json.dumps(qa_common.verdict("UNVERIFIED", GATE, "?", "?", "report crashed: %s: %s" % (type(ex).__name__, ex))))
        sys.exit(0)
