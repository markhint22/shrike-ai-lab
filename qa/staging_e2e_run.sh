#!/usr/bin/env bash
# staging_e2e_run.sh - BOX: run the live-staging e2e cells (scripts/qa/e2e/chickadee_staging_e2e.py) ONLY when there is something new to say about staging.
# QA-N1, 2026-10-09. Cron (box): 25 * * * * cd ~/overnight-queue && bash qa/staging_e2e_run.sh >> logs/staging_e2e.log 2>&1
#
# RUNS when (first match):  QA_E2E_FORCE=1 | no previous result | the latest SUCCESS deploy commit in state/staging_deploys/iptv_apps.json differs from the
#   `deploy_commit` of the last result | the last result is >= 6 h old (QA_E2E_MAX_AGE_S) | the last result was inconclusive (every cell UNVERIFIED -> retried hourly).
# SKIPS when: the gate is off (OVN_QA_STAGING_E2E=off or `qa_enforce.sh staging_e2e off`) | the latest staging deploy is still BUILDING (unless the result is >= 6 h old)
#   | another run (or the daily smoke) holds state/staging_e2e.lock | nothing changed.
# Serial: staging state (the two canonical accounts, the rate-limit window) is shared, so a mkdir lock (portable: no flock on a Mac) serialises this runner with the
#   daily staging_smoke in qa_daily_shadow.sh. A lock older than QA_E2E_LOCK_STALE_MIN (30) is taken over. It is removed on exit.
# Result -> state/staging_e2e_box.json (atomic). qa/staging_e2e_ingest.py (cron */30) turns it into shadow rows + alerts; qa/promote_gate.py reads it (shadow).
# ALWAYS exits 0 (cron mail stays quiet); one line per decision on stdout. Never touches a repo, never takes run.lock, never pushes anything.
# RUNNER LOCATION (box): $OVN_DIR/scripts/qa/e2e/chickadee_staging_e2e.py (= ~/overnight-queue/scripts/qa/e2e/). That directory does NOT exist until the deploy creates it
#   (`mkdir -p ~/overnight-queue/scripts/qa/e2e`); a missing runner is NOT silent: the script writes a harness-error result (cell `harness` UNVERIFIED 'runner not found at ...')
#   so the freshness / no-usable-evidence alerts see it. Also looked at: QA_E2E_RUNNER, and ../../qa/e2e next to this script (the repo tree).
# TIME: the runner keeps its own deadline (QA_E2E_DEADLINE_S 600 + cleanup grace 120) and stops on SIGTERM; qa_timeout.py (QA_E2E_TIMEOUT_S, default 900) sends SIGTERM first
#   and SIGKILL only QA_E2E_KILL_GRACE_S (30) later, so a degraded staging yields a PARTIAL result with the cleanup done, never a mid-run SIGKILL.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
PY="$(command -v python3.12 || command -v python3)"
[ -n "$PY" ] || { echo "$(date '+%F %T') staging_e2e_run: no python3"; exit 0; }
STATE="${QA_STATE_DIR:-$OVN_DIR/state}"; export QA_STATE_DIR="$STATE"
OUT="$STATE/staging_e2e_box.json"
LOCK="$STATE/staging_e2e.lock"
MAXAGE="${QA_E2E_MAX_AGE_S:-21600}"
say(){ echo "$(date '+%F %T') staging_e2e_run: $*"; }
mkdir -p "$STATE" 2>/dev/null
post(){  # $1 = runner rc (unused), $2 = detail for the harness-error result written when the runner produced no result file
HARNESS_DETAIL="$2" "$PY" - "$TMP" "$OUT" <<'PY'
import json, os, sys, time
tmp, out = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(tmp))
    assert isinstance(d.get("cells"), list)
except Exception:
    d = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "base": None, "staging_commit": None, "deploy_commit": None,
         "cells": [{"cell": "harness", "verdict": "UNVERIFIED", "ms": 0, "detail": os.environ.get("HARNESS_DETAIL") or "runner produced no result"}]}
conclusive = any(c.get("verdict") in ("PASS", "FAIL", "NA") for c in d["cells"] if isinstance(c, dict))
if not conclusive or d.get("retry") or d.get("partial"):
    d["deploy_commit"] = None    # retried at the next tick: inconclusive, a first-sighting retry (unlisted commit) or a partial run (deadline / SIGTERM)
with open(out + ".tmp", "w") as f:
    json.dump(d, f, sort_keys=True)
os.replace(out + ".tmp", out)
tally = {}
for c in d["cells"]:
    tally[c.get("verdict")] = tally.get(c.get("verdict"), 0) + 1
print("%s staging_e2e_run: wrote %s: %s; requests=%s staging=%s conclusive=%s" % (time.strftime("%F %T"), os.path.basename(out), ", ".join("%d %s" % (n, v) for v, n in sorted(tally.items())),
      d.get("requests", "?"), str(d.get("staging_commit"))[:10], conclusive))
PY
}

MODE="$("$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import qa_common as qc; print(qc.mode("staging_e2e"))' "$HERE" 2>/dev/null)"
[ "$MODE" = "off" ] && { say "disabled (staging_e2e mode off)"; exit 0; }

# the runner lives next to the other box scripts (OVN_DIR/scripts/qa/e2e) or, in the repo tree, at scripts/qa/e2e (HERE = scripts/overnight-queue/qa)
RUNNER="${QA_E2E_RUNNER:-}"
if [ -z "$RUNNER" ]; then
  for c in "$OVN_DIR/scripts/qa/e2e/chickadee_staging_e2e.py" "$HERE/../../qa/e2e/chickadee_staging_e2e.py"; do [ -f "$c" ] && { RUNNER="$c"; break; }; done
fi
if [ -z "$RUNNER" ] || [ ! -f "$RUNNER" ]; then
  W="$OVN_DIR/scripts/qa/e2e/chickadee_staging_e2e.py"
  say "runner not found at ${QA_E2E_RUNNER:-$W} (looked in $OVN_DIR/scripts/qa/e2e and next to the repo qa dir): deploy it with mkdir -p $OVN_DIR/scripts/qa/e2e and copy chickadee_staging_e2e.py there"
  TMP="$STATE/.staging_e2e_box.json.$$"; rm -f "$TMP"
  post 127 "runner not found at ${QA_E2E_RUNNER:-$W}: deploy scripts/qa/e2e/chickadee_staging_e2e.py to the box (mkdir -p scripts/qa/e2e)"
  exit 0
fi

# ---- decide: run or skip
DEC="$(QA_E2E_RUNNER_PATH="$RUNNER" QA_E2E_MAXAGE="$MAXAGE" "$PY" - "$STATE" <<'PY' 2>/dev/null
import importlib.util, json, os, sys, time, calendar
state = sys.argv[1]
spec = importlib.util.spec_from_file_location("e2e_runner", os.environ["QA_E2E_RUNNER_PATH"])
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)
maxage = float(os.environ["QA_E2E_MAXAGE"])
if os.environ.get("QA_E2E_FORCE") == "1":
    print("run|forced"); sys.exit(0)
try:
    last = json.load(open(os.path.join(state, "staging_e2e_box.json")))
    ts = float(calendar.timegm(time.strptime(last["ts"], "%Y-%m-%dT%H:%M:%SZ")))
except Exception:
    print("run|no previous result"); sys.exit(0)
age = time.time() - ts
d = r.load_deploy(state)
if d["state"] == "building" and age < maxage:
    print("skip|latest staging deploy is %s (waiting for it to finish)" % d["latest_status"]); sys.exit(0)
if not last.get("deploy_commit"):
    print("run|last result was inconclusive (retry)"); sys.exit(0)
if d["state"] == "ok" and last.get("deploy_commit") != d["commit"]:
    print("run|new staging deploy %s (last result ran for %s)" % (d["commit"][:10], str(last.get("deploy_commit"))[:10])); sys.exit(0)
if age >= maxage:
    print("run|last result is %d min old (max %d)" % (age // 60, maxage // 60)); sys.exit(0)
print("skip|nothing new: deploy %s already covered, result %d min old" % (str(last.get("deploy_commit"))[:10], age // 60))
PY
)"
ACT="${DEC%%|*}"; WHY="${DEC#*|}"
[ -n "$DEC" ] || { ACT=run; WHY="decision helper failed (running anyway)"; }
[ "$ACT" = "skip" ] && { say "skip: $WHY"; exit 0; }

# ---- serial lock (mkdir is atomic; stale takeover by mtime)
STALE_MIN="${QA_E2E_LOCK_STALE_MIN:-30}"
if ! mkdir "$LOCK" 2>/dev/null; then
  if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +"$STALE_MIN" 2>/dev/null)" ]; then
    say "taking over a stale lock (older than ${STALE_MIN} min)"; rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || { say "skip: lost the lock race"; exit 0; }
  else
    say "skip: busy (another e2e or the daily smoke holds $LOCK)"; exit 0
  fi
fi
echo "$$" > "$LOCK/pid" 2>/dev/null
TMP="$STATE/.staging_e2e_box.json.$$"
trap 'rm -rf "$LOCK"; rm -f "$TMP"' EXIT

say "run: $WHY"
rm -f "$TMP"
QA_TIMEOUT_TERM_GRACE_S="${QA_E2E_KILL_GRACE_S:-30}" "$PY" "$HERE/qa_timeout.py" "${QA_E2E_TIMEOUT_S:-900}" "$PY" "$RUNNER" --out "$TMP" --state-dir "$STATE" ${QA_E2E_BASE:+--base "$QA_E2E_BASE"}
rc=$?
# post-process: keep the runner's result, or write an honest harness-error result; record deploy_commit ONLY when the run was conclusive (some cell PASS/FAIL/NA),
# so an all-UNVERIFIED run is retried next hour instead of being treated as "covered" for 6 h
post "$rc" "runner produced no result (rc=$rc)"
exit 0
