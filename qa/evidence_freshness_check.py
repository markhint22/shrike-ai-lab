#!/usr/bin/env python3
"""evidence_freshness_check.py - alert when the evidence the promote gate relies on goes STALE. (QA-N1 / folded QA-N4, 2026-10-09)

  python3 qa/evidence_freshness_check.py          cron: 35 * * * * cd ~/overnight-queue && python3 qa/evidence_freshness_check.py >> logs/evidence_freshness.log 2>&1

WHY: on 2026-10-07 the Mac stopped exporting staging deploys, the evidence went stale for ~39 h and the (enforcing) promote gate blocked three days of promotes before
anybody noticed - the hourly staging_check shadow cron that would have said so was documented "NOT installed". This job turns every stale source into ONE alerts.log
line (the digest channel) that already contains the fix.

Sources and limits (age = now - the file's own timestamp; a missing file counts as stale):
  deploy_export       newest state/staging_deploys/*.json `fetched_at`                        max 1800 s (QA_STAGING_MAX_AGE_S, the promote gate's own limit)
                      -> "Mac qa-staging-export not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-export"
  deploy_file:<repo>  one repo's staging_deploys/<repo>.json while the newest is fresh        max 1800 s  -> that repo's export is failing (Railway login / link)
  e2e_mac             state/qa_staging_e2e.json (the Mac RevenueCat lifecycle, copied over)   max 12 h     -> "Mac qa-staging-e2e not running: launchctl kickstart ..."
  e2e_box             state/staging_e2e_box.json (qa/staging_e2e_run.sh)                      max 12 h     -> box cron / runner hint
The two e2e sources are skipped when the staging_e2e gate is off (OVN_QA_STAGING_E2E=off / qa_enforce.sh staging_e2e off). OVN_EVIDENCE_FRESHNESS=off disables the job.
Dedupe: state/evidence_freshness_alerted.json {source: last alert epoch} - one WARN per stale source per 6 h; a source that is fresh again is forgotten, so the next
outage alerts at once. Nothing here blocks, locks or touches a repo; always exits 0; prints one JSON summary line. EVIDENCE_FRESHNESS_NOW=<epoch> is a test clock.
"""
import calendar
import glob
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402

DEPLOY_MAX_S = 1800
E2E_MAX_S = 12 * 3600
REALERT_S = 6 * 3600
HINTS = {
    "deploy_export": "Mac qa-staging-export not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-export (log ~/.qa_staging_export.log; needs the Railway CLI login)",
    "e2e_mac": "Mac qa-staging-e2e not running: launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-e2e (log ~/.qa_staging_e2e.log; needs the Railway CLI login)",
    "e2e_box": "box staging_e2e_run.sh produced no fresh result: check ~/overnight-queue/logs/staging_e2e.log and that the cron line '25 * * * * ... qa/staging_e2e_run.sh' is installed",
}


def _ts_iso(v):
    try:
        return float(calendar.timegm(time.strptime(str(v), "%Y-%m-%dT%H:%M:%SZ")))
    except (ValueError, TypeError, OverflowError):
        return None


def _age_of_json(path, key, now, iso=False):
    """-> age in seconds, or None when the file is missing / unreadable / has no usable timestamp."""
    try:
        with open(path) as f:
            j = json.load(f)
        t = _ts_iso(j.get(key)) if iso else float(j.get(key))
        return None if t is None else max(0.0, now - t)
    except (OSError, ValueError, TypeError, AttributeError):
        return None


def stale_sources(state_d, now, deploy_max=None, e2e_on=True):
    """-> list of (source key, message). Pure apart from reading files (unit-tested with an injected `now`)."""
    deploy_max = float(os.environ.get("QA_STAGING_MAX_AGE_S", DEPLOY_MAX_S)) if deploy_max is None else deploy_max
    out = []
    files = sorted(glob.glob(os.path.join(state_d, "staging_deploys", "*.json")))
    ages = {os.path.basename(p)[:-5]: _age_of_json(p, "fetched_at", now) for p in files}
    known = [a for a in ages.values() if a is not None]
    if not known:
        out.append(("deploy_export", "staging deploy snapshots are MISSING (state/staging_deploys has no usable file). " + HINTS["deploy_export"]))
    elif min(known) > deploy_max:
        out.append(("deploy_export", "staging deploy snapshots are stale: newest is %d min old (max %d). %s" % (min(known) // 60, deploy_max // 60, HINTS["deploy_export"])))
    else:
        for repo, a in sorted(ages.items()):
            if a is None or a > deploy_max:
                out.append(("deploy_file:" + repo, "staging deploy snapshot for %s is %s (max %d min) while the others are fresh: that repo's export is failing "
                            "(Railway link/login?) - see ~/.qa_staging_export.log on the Mac" % (repo, "unreadable" if a is None else "%d min old" % (a // 60), deploy_max // 60)))
    if e2e_on:
        for key, fname in (("e2e_mac", "qa_staging_e2e.json"), ("e2e_box", "staging_e2e_box.json")):
            a = _age_of_json(os.path.join(state_d, fname), "ts", now, iso=True)
            if a is None:
                out.append((key, "%s evidence state/%s is MISSING or unreadable. %s" % (key, fname, HINTS[key])))
            elif a > E2E_MAX_S:
                out.append((key, "%s evidence state/%s is stale: %.1f h old (max %d h). %s" % (key, fname, a / 3600.0, E2E_MAX_S // 3600, HINTS[key])))
    return out


def run(state_d=None, now=None):
    """Append the due alerts. -> (stale keys, alerted keys). Never raises on a bad dedupe file."""
    state_d = state_d or qc.state_dir()
    now = time.time() if now is None else now
    e2e_on = qc.mode("staging_e2e") != "off"
    stale = stale_sources(state_d, now, e2e_on=e2e_on)
    dpath = os.path.join(state_d, "evidence_freshness_alerted.json")
    try:
        with open(dpath) as f:
            seen = json.load(f)
        seen = seen if isinstance(seen, dict) else {}
    except (OSError, ValueError):
        seen = {}
    keys = set(k for k, _ in stale)
    seen = {k: v for k, v in seen.items() if k in keys}  # fresh again => forgotten: the next outage alerts at once
    alerted = []
    for key, msg in stale:
        last = seen.get(key)
        if isinstance(last, (int, float)) and now - last < REALERT_S:
            continue
        os.makedirs(state_d, exist_ok=True)
        with open(os.path.join(state_d, "alerts.log"), "a") as f:
            f.write("[%s] WARN | evidence-freshness | %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), msg.replace("\n", " ")))
        seen[key] = now  # only after the line is on disk
        alerted.append(key)
    os.makedirs(state_d, exist_ok=True)
    tmp = dpath + ".tmp"
    with open(tmp, "w") as f:
        json.dump(seen, f, sort_keys=True)
    os.replace(tmp, dpath)
    return [k for k, _ in stale], alerted


def main(argv):
    if os.environ.get("OVN_EVIDENCE_FRESHNESS", "on") == "off":
        print(json.dumps({"disabled": True}))
        return 0
    try:
        now = float(os.environ["EVIDENCE_FRESHNESS_NOW"]) if os.environ.get("EVIDENCE_FRESHNESS_NOW") else None
        stale, alerted = run(now=now)
        print(json.dumps({"stale": stale, "alerted": alerted}, sort_keys=True))
    except Exception as ex:  # noqa: BLE001 - a monitor must never fail loudly into cron mail
        print(json.dumps({"error": "%s: %s" % (type(ex).__name__, ex)}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
