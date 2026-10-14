#!/usr/bin/env python3
"""cycle-walltime alert wording (2026-10-14, billwatch alert).

The alert read: "billwatch spent 75% of its last 3 cycles outside model generation (gen 306s, logged verify timeouts 408s, ...)".
The 408s was verify_s, which is the sum of VERIFY timeouts AND passing suite runs ("--- verify done in Ns ---" markers). billwatch's
cycle logs held ZERO "VERIFY timed out" lines: the 3 cycles each ran the full green backend suite (~134s, 600s cap, never reached).
The message therefore blamed timeouts for a passing suite. Fix: the ledger row carries timeout_s on its own, and the alert names the
timeout share separately (verify Ns of which logged VERIFY timeouts Ns). Old rows without timeout_s keep the plain "verify Ns" wording.

Each case writes a throwaway state/ + logs/ tree, runs ovn_cycle_walltime.run() on it (the real code) and reads the alert line.
Run: python3 scripts/test/test_walltime_alert_split.py   (exit 0 = all pass)
"""
import json
import os
import shutil
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OQ = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(OQ, "scripts"))
import ovn_cycle_walltime as W  # noqa: E402

P = F = 0


def ok(name, cond, extra=""):
    global P, F
    if cond:
        P += 1
        print("  ok   " + name)
    else:
        F += 1
        print("  FAIL " + name + ((" :: " + str(extra)[:300]) if extra else ""))


def iso(e):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))


def local_dir(e):
    return time.strftime("%Y%m%d-%H%M%S", time.localtime(e))


def scenario(cycles, tokens_recv=0):
    """cycles: list of cycle-log texts (oldest first). Each cycle: 450s duration. tokens_recv (decode tokens, 25 tok/s estimate) sets the
    generation share: 0 -> gen 0, nongen 100% (alerts); 10000 -> gen-bound (400s of model time, nongen below the 50% bar).
    Returns the alert lines written by the real run()."""
    d = tempfile.mkdtemp(prefix="walltime-split-")
    try:
        st, lg = os.path.join(d, "state"), os.path.join(d, "logs")
        os.makedirs(st)
        os.makedirs(lg)
        now = time.time()
        rows = []
        for i, text in enumerate(cycles):
            e = now - 3600 + i * 600
            p = os.path.join(lg, local_dir(e - 60))
            os.makedirs(p)
            with open(os.path.join(p, "ongoing-billwatch.log"), "w") as fh:
                fh.write(text)
            rows.append(json.dumps({"ts": iso(e), "repo": "billwatch", "id": "ongoing-billwatch", "type": "aider_fix", "tier": "2",
                                    "category": "api", "class": "landed", "severity": "good", "attempt": 1, "attempts": 1,
                                    "status": "pushed(tests:pass)", "tokens_sent": 0, "tokens_recv": tokens_recv, "duration_s": 450,
                                    "item_hash": "", "feat_tag": ""}))
        with open(os.path.join(st, "outcomes.jsonl"), "w") as fh:
            fh.write("\n".join(rows) + "\n")
        res = W.run(st, lg, now)
        alerts_path = os.path.join(st, "alerts.log")
        lines = []
        if os.path.exists(alerts_path):
            with open(alerts_path) as fh:
                lines = [ln for ln in fh if "cycle-walltime" in ln]
        ledger = []
        with open(os.path.join(st, "cycle_walltime.jsonl")) as fh:
            ledger = [json.loads(ln) for ln in fh if ln.strip()]
        return res, lines, ledger
    finally:
        shutil.rmtree(d, ignore_errors=True)


PASS_CYCLE = "--- verify: ./.ovn-verify.sh (repo-owned, 600s cap) ---\n--- verify done in 136s ---\n"
TIMEOUT_CYCLE = "--- auto-credit: INDETERMINATE line 3 - VERIFY timed out (rc=124) after 100s; item left open ---\n--- verify done in 30s ---\n"

# 1. the billwatch shape: three green full-suite verifies, no timeouts at all
res, lines, ledger = scenario([PASS_CYCLE] * 3)
ok("billwatch shape: one alert fires", len(lines) == 1 and res["alerts"] == [ln.rstrip("\n") for ln in lines], lines)
msg = lines[0] if lines else ""
ok("billwatch shape: the verify time is reported as verify, not as timeouts", "verify 408s" in msg, msg)
ok("billwatch shape: the timeout share is reported as 0s", "logged VERIFY timeouts 0s" in msg, msg)
ok("billwatch shape: the alert no longer claims 408s of timeouts", "logged verify timeouts 408s" not in msg, msg)
ok("billwatch shape: ledger rows carry timeout_s 0 and verify_s 136", all(r.get("timeout_s") == 0 and r.get("verify_s") == 136 for r in ledger), ledger)

# 2. real timeouts are still named as timeouts (and split from the passing suite time)
res, lines, ledger = scenario([TIMEOUT_CYCLE] * 3)
msg = lines[0] if lines else ""
ok("timeouts: the alert fires and splits 300s of logged timeouts out of 390s verify", "verify 390s of which logged VERIFY timeouts 300s" in msg, msg)
ok("timeouts: ledger timeout_s is the timeout part only (100 per cycle)", all(r.get("timeout_s") == 100 and r.get("verify_s") == 130 for r in ledger), ledger)

# 3. benign twin: the same real timeouts on a GENERATION-BOUND lane (400s of model time, nongen 29%) do not alert, yet the ledger still
#    carries the timeout share on its own. Deleting the timeout_s split makes the ledger assertion fail (the alert assertion alone would not).
res, lines, ledger = scenario([TIMEOUT_CYCLE] * 3, tokens_recv=10000)
ok("benign: generation-bound cycles with logged timeouts do not alert", lines == [] and res["alerts"] == [], lines)
ok("benign: the ledger still records timeout_s 100 and verify_s 130 per cycle", all(r.get("timeout_s") == 100 and r.get("verify_s") == 130 for r in ledger), ledger)

print("test_walltime_alert_split: %d passed, %d failed" % (P, F))
sys.exit(1 if F else 0)
