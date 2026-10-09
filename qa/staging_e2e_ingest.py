#!/usr/bin/env python3
"""staging_e2e_ingest.py - turn the live-staging e2e RESULT FILES into qa_common shadow rows + ONE alerts.log warn per (cell, commit) on FAIL. (QA-N1, 2026-10-09)

  python3 qa/staging_e2e_ingest.py [--no-record]          cron: */30 * * * * cd ~/overnight-queue && python3 qa/staging_e2e_ingest.py >> logs/staging_e2e.log 2>&1

Sources (state/, written elsewhere; this script only READS them):
  qa_staging_e2e.json     Mac: the RevenueCat lifecycle cell (scripts/qa-staging-e2e.sh -> scp). Legacy {ts, passed, total, failed} files are understood too.
  staging_e2e_box.json    box: the runner cells (qa/staging_e2e_run.sh -> scripts/qa/e2e/chickadee_staging_e2e.py)
Output
  state/qa_shadow/staging_e2e.jsonl   one qa_common row per NEW result (gate key staging_e2e, repo iptv_apps, ref = the staging commit the cells ran against (10 chars)).
        verdict = FAIL if any cell FAILed, else UNVERIFIED if any could not run, else FLAG ("PARTIAL": some cells N/A beside passing ones), else PASS, all-NA = NA.
        details = {source, result_ts, commit, cells:[{cell, verdict, ms, detail}], counts}. A result already ingested (same source + ts) is never written twice.
  state/alerts.log                    ONE WARN line per (cell, commit) that FAILed (marker files in state/staging_e2e_alerted/); the marker is written only after the line.
        Also ONE WARN per (source, UTC day) when a result reports cleanup.failed > 0 (qa-e2e-* leftovers on staging), and ONE per 6 h once a source has given NO usable
        evidence (no PASS/FAIL cell) for 3 consecutive results (state/staging_e2e_streak.json) - e.g. the Mac lifecycle with an expired Railway login - and ONE per (box, UTC day)
        while the box runner's auth_login says 'credentials not provisioned' (health_provenance may still PASS, so the streak alert would stay silent).
        A FAIL on a result with no usable staging commit is keyed on the failure signature + UTC day, not on the constant 'unknown'.
Kill switch: OVN_QA_STAGING_E2E=off (cron env) or `qa/qa_enforce.sh staging_e2e off`. SHADOW only: nothing here ever blocks anything (the promote-time use is
qa/promote_gate.py, itself shadow until `qa_enforce.sh staging_e2e enforce`). Always exits 0; prints one JSON summary line. No credential is ever copied: every
detail passes a redactor (JWT / bearer / password= / token= shapes) on the way in, so even a leaky result file cannot reach alerts.log or the shadow rows.
"""
import hashlib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qa_common as qc  # noqa: E402
import promote_gate as pg  # noqa: E402

GATE = pg.E2E_GATE
REPO = "iptv_apps"
SCRUBS = [(re.compile(r"eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]*"), "[jwt]"),
          (re.compile(r"(?i)(bearer\s+)[A-Za-z0-9._~+/=-]{8,}"), r"\1[redacted]"),
          (re.compile(r"(?i)([\"']?(?:password|passwd|secret|access_token|refresh_token|token|authorization)[\"']?\s*[:=]\s*[\"']?)[^\"'&\s,}]{3,}"), r"\1[redacted]"),
          (re.compile(r"([?&]token=)[^&\s\"']+"), r"\1[redacted]")]


def scrub(s):
    s = str(s)
    for rx, rep in SCRUBS:
        s = rx.sub(rep, s)
    return s


def iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def _load_json(path, default):
    try:
        with open(path) as f:
            j = json.load(f)
        return j if isinstance(j, dict) else default
    except (OSError, ValueError):
        return default


def _save_json_atomic(path, obj):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, sort_keys=True)
    os.replace(tmp, path)


def alert_once(state_d, cell, commit, detail, now=None):
    """ONE alerts.log WARN per (cell, commit). Returns True when a line was written.
    A result without a usable staging commit (/health answered without one) is keyed on the failure SIGNATURE (the detail with its numbers blanked) and the UTC day instead of
    the constant 'unknown': one marker for 'unknown' would silence every later commit-less FAIL of that cell for good."""
    d = os.path.join(state_d, "staging_e2e_alerted")
    if commit:
        tail = commit[:12]
    else:
        sig = hashlib.sha1(re.sub(r"\d+", "#", scrub(detail)).encode()).hexdigest()[:8]
        tail = "unknown_%s_%s" % (sig, time.strftime("%Y%m%d", time.gmtime(time.time() if now is None else now)))
    key = "%s_%s" % (re.sub(r"[^A-Za-z0-9_.-]", "_", cell)[:40], tail)
    marker = os.path.join(d, key)
    if os.path.exists(marker):
        return False
    os.makedirs(d, exist_ok=True)
    line = "[%s] WARN | qa-staging-e2e | %s cell %s FAIL at staging %s: %s\n" % (time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), REPO, cell, (commit or "unknown")[:10],
                                                                             scrub(detail)[:160].replace("\n", " "))
    with open(os.path.join(state_d, "alerts.log"), "a") as f:
        f.write(line)
    with open(marker, "w"):
        pass  # only after the line is on disk: a failed append is retried on the next run
    return True


STREAK_N = 3            # consecutive results without a single PASS/FAIL cell before a source counts as silently broken
STREAK_REALERT_S = 6 * 3600
UNUSABLE_HINTS = {
    "mac": "Mac RevenueCat lifecycle: check the Railway CLI login (railway whoami), ~/.qa_staging_e2e.log, then launchctl kickstart gui/$(id -u)/com.shrike.qa-staging-e2e",
    "box": "box e2e runner: check state/qa_creds/iptv_apps.json (mode 600), the staging URL and logs/staging_e2e.log",
}


def cleanup_alert_once(state_d, source, cleanup, now=None):
    """ONE alerts.log WARN per (source, UTC day) when a run could not delete everything it created on staging (qa-e2e-* users / streams are left behind).
    DELETE /api/account/me is limited to 5/hour per IP, so repeated or forced runs from one egress IP can hit it. True when a line was written."""
    failed = (cleanup or {}).get("failed")
    if not isinstance(failed, int) or failed <= 0:
        return False
    now = time.time() if now is None else now
    d = os.path.join(state_d, "staging_e2e_alerted")
    marker = os.path.join(d, "cleanup_%s_%s" % (re.sub(r"[^A-Za-z0-9_.-]", "_", source)[:20], time.strftime("%Y%m%d", time.gmtime(now))))
    if os.path.exists(marker):
        return False
    os.makedirs(d, exist_ok=True)
    line = "[%s] WARN | qa-staging-e2e | %s e2e cleanup FAILED for %d of %s delete(s) on staging: qa-e2e-* users / streams are left behind - purge them (account delete is limited to 5/hour per IP)\n" % (
        time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), REPO, failed, (cleanup or {}).get("attempted", "?"))
    with open(os.path.join(state_d, "alerts.log"), "a") as f:
        f.write(line)
    with open(marker, "w"):
        pass
    return True


def creds_alert_once(state_d, source, cells, now=None):
    """ONE alerts.log WARN per (source, UTC day) when the BOX runner's auth_login cell says the canonical credentials are not provisioned: then every login-dependent cell is
    UNVERIFIED and only the aggregate shows it (the streak alert needs every cell to lack PASS/FAIL, but health_provenance can still PASS). True when a line was written."""
    if source != "box":
        return False
    hit = next((c for c in cells if c.get("cell") == "auth_login" and c.get("verdict") == "UNVERIFIED" and "credentials not provisioned" in str(c.get("detail", ""))), None)
    if not hit:
        return False
    now = time.time() if now is None else now
    d = os.path.join(state_d, "staging_e2e_alerted")
    marker = os.path.join(d, "creds_%s_%s" % (source, time.strftime("%Y%m%d", time.gmtime(now))))
    if os.path.exists(marker):
        return False
    os.makedirs(d, exist_ok=True)
    n = sum(1 for c in cells if c.get("verdict") == "UNVERIFIED")
    line = "[%s] WARN | qa-staging-e2e | %s box e2e runner has no usable canonical credentials (%d of %d cells UNVERIFIED): create state/qa_creds/iptv_apps.json (mode 600) on the box\n" % (
        time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), REPO, n, len(cells))
    with open(os.path.join(state_d, "alerts.log"), "a") as f:
        f.write(line)
    with open(marker, "w"):
        pass
    return True


def unusable(cells):
    """No cell produced evidence (no PASS, no FAIL) and at least one could not run: the source is running but telling us nothing."""
    vs = [c["verdict"] for c in cells]
    return bool(vs) and "PASS" not in vs and "FAIL" not in vs and "UNVERIFIED" in vs


def streak_alert(state_d, src, now=None):
    """Count consecutive unusable results per source (state/staging_e2e_streak.json); from STREAK_N on, ONE alerts.log WARN per STREAK_REALERT_S. A result with a
    PASS/FAIL cell resets the count. Without this, a Mac lifecycle with an expired Railway login (harness error -> UNVERIFIED, freshly written file) is silent. True when alerted."""
    now = time.time() if now is None else now
    path = os.path.join(state_d, "staging_e2e_streak.json")
    st = _load_json(path, {})
    cur = st.get(src["source"]) if isinstance(st.get(src["source"]), dict) else {}
    alerted = False
    if unusable(src["cells"]):
        n = int(cur.get("n", 0)) + 1
        last = cur.get("last_alert", 0)
        if n >= STREAK_N and now - (last if isinstance(last, (int, float)) else 0) >= STREAK_REALERT_S:
            first = next((c for c in src["cells"] if c["verdict"] == "UNVERIFIED"), {})
            line = "[%s] WARN | qa-staging-e2e | %s e2e source gave NO usable evidence for %d consecutive results (every cell UNVERIFIED/NA; e.g. %s: %s). %s\n" % (
                time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)), src["source"], n, first.get("cell", "?"), scrub(first.get("detail", ""))[:100].replace("\n", " "),
                UNUSABLE_HINTS.get(src["source"], ""))
            with open(os.path.join(state_d, "alerts.log"), "a") as f:
                f.write(line)
            last, alerted = now, True
        st[src["source"]] = {"n": n, "last_alert": last}
    else:
        st.pop(src["source"], None)
    _save_json_atomic(path, st)
    return alerted


def row_for(src):
    cells = [{"cell": c["cell"], "verdict": c["verdict"], "ms": c["ms"], "detail": scrub(c["detail"])[:240]} for c in src["cells"]]
    counts = {}
    for c in cells:
        counts[c["verdict"]] = counts.get(c["verdict"], 0) + 1
    v = pg.aggregate_cells(cells)
    fails = [c["cell"] for c in cells if c["verdict"] == "FAIL"]
    summary = "%s result: %s%s" % (src["source"], ", ".join("%d %s" % (n, k) for k, n in sorted(counts.items())) or "no cells", ("; FAIL: " + ",".join(fails)) if fails else "")
    return qc.verdict(v, GATE, REPO, (src["commit"] or "?")[:10], summary, {"source": src["source"], "result_ts": iso(src["ts"]), "commit": src["commit"], "cells": cells,
                                                                      "counts": counts})


def ingest(state_d=None, now=None):
    state_d = state_d or qc.state_dir()
    now = time.time() if now is None else now
    sources, bad = pg.read_e2e_sources(state_d)
    seen_path = os.path.join(state_d, "staging_e2e_ingested.json")
    seen = _load_json(seen_path, {})
    rows = alerts = 0
    for src in sorted(sources, key=lambda s: s["ts"]):
        if seen.get(src["source"], 0) >= src["ts"]:
            continue
        res = row_for(src)
        qc.record(res)
        rows += 1
        for c in res["details"]["cells"]:
            if c["verdict"] == "FAIL" and alert_once(state_d, c["cell"], src["commit"], c["detail"], now):
                alerts += 1
        if cleanup_alert_once(state_d, src["source"], src.get("cleanup"), now):
            alerts += 1
        if streak_alert(state_d, src, now):
            alerts += 1
        if creds_alert_once(state_d, src["source"], res["details"]["cells"], now):
            alerts += 1
        seen[src["source"]] = src["ts"]
        _save_json_atomic(seen_path, seen)
    return rows, alerts, bad


def run(argv):
    if qc.mode(GATE) == "off":
        return qc.verdict("NA", GATE, REPO, "ingest", "staging_e2e is off (OVN_QA_STAGING_E2E / qa_enforce.sh): nothing ingested")
    rows, alerts, bad = ingest()
    return qc.verdict("NA", GATE, REPO, "ingest", "ingested %d new result(s), %d alert(s)%s" % (rows, alerts, ("; unreadable: " + ",".join(bad)) if bad else ""),
                      {"rows": rows, "alerts": alerts, "unreadable": bad})


def main(argv):
    return qc.main_guard(GATE, run, list(argv) + ["--no-record"])  # the summary line is not a shadow row (the ingested results are)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
