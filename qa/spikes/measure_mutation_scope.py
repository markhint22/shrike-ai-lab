#!/usr/bin/env python3
"""measure_mutation_scope.py - MANUAL measurement helper (NOT run in CI, NOT run by any cron): how much do the K2 scopes save on a REAL range?

    python3 qa/spikes/measure_mutation_scope.py --repo billwatch --base <sha> --head <sha> [--cap 300] [--modes none,post,pre,both]

It runs `qa/gate_mutation.py check --no-record` on the SAME range once per mode and prints a table (mutants judged, mutants mutmut generated, runtime, verdict):
    none : OVN_MUT_PRAGMA_SCOPE=0 OVN_MUT_LINE_SCOPE=0   (whole changed functions - the pre-K2 behaviour)
    post : OVN_MUT_PRAGMA_SCOPE=0                         (mutate everything, drop unchanged-line mutants afterwards: judged count shrinks, runtime does not)
    pre  : OVN_MUT_LINE_SCOPE=0                           (pragma pre-filter only: unchanged single-line statements never become mutants)
    both : defaults
Each mode costs up to --cap seconds (clamped to 600 by the gate), so a 4-mode run is up to ~40 min on a heavy repo: run it by hand on the box, outside the fleet's busy
windows (pause the queue first, resume after). It never writes state/, never records a row, never notifies. Needs mutmut in the QA venv, else every row is UNVERIFIED tool-missing.
The ratio runtime(pre) / runtime(none) on a real range is the evidence for the "pre-filter shortens the run" claim; the hermetic test only proves the mutant COUNT drops on a fixture.
"""
import argparse
import json
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GATE = os.path.join(os.path.dirname(HERE), "gate_mutation.py")
MODES = {"none": {"OVN_MUT_PRAGMA_SCOPE": "0", "OVN_MUT_LINE_SCOPE": "0"}, "post": {"OVN_MUT_PRAGMA_SCOPE": "0"}, "pre": {"OVN_MUT_LINE_SCOPE": "0"}, "both": {}}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--repo", required=True)
    ap.add_argument("--base", required=True)
    ap.add_argument("--head", required=True)
    ap.add_argument("--cap", default="300")
    ap.add_argument("--modes", default="none,post,pre,both")
    a = ap.parse_args()
    print("%-5s %-11s %8s %8s %9s  %s" % ("mode", "verdict", "judged", "wall_s", "excluded", "summary"))
    for m in a.modes.split(","):
        if m not in MODES:
            sys.exit("unknown mode %s (use %s)" % (m, ",".join(MODES)))
        env = dict(os.environ, OVN_MUT_CAP_S=str(a.cap), NTFY_SERVER="http://127.0.0.1:9", OVN_NOTIFY_DISABLE="1", **MODES[m])
        t0 = time.time()
        p = subprocess.run([sys.executable, GATE, "check", "--repo", a.repo, "--base", a.base, "--head", a.head, "--no-record"], capture_output=True, text=True, env=env)
        wall = time.time() - t0
        try:
            r = json.loads([l for l in p.stdout.splitlines() if l.strip()][-1])
        except (ValueError, IndexError):
            r = {"verdict": "NOT-JSON", "summary": p.stderr[-200:]}
        d = r.get("details", {})
        print("%-5s %-11s %8s %8.1f %9s  %s" % (m, r.get("verdict"), d.get("yield", {}).get("mutants"), wall,
                                               d.get("pragma_scope", {}).get("unchanged_lines_excluded_before_mutation", "-"), (r.get("summary") or "")[:100]))


if __name__ == "__main__":
    main()
