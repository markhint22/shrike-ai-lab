#!/usr/bin/env bash
# qa_daily_shadow.sh - BOX: once a day, just before the 09:00 promote, run the release-flow gates in SHADOW for every repo that gets promoted:
#   release_candidate plan  (which develop SHA would a release branch be cut from, and what is held back)
#   staging_check           (does staging serve that SHA?  evidence = the Mac's 10-minutely snapshot, state/staging_deploys/<repo>.json)
# 2026-10-02. Observation only: never pushes, never promotes, never takes run.lock; ALWAYS exits 0. Results -> state/qa_shadow/*.jsonl + logs/qa_daily_shadow.log.
# 2026-10-03 (A10): `qa_daily_shadow.sh --staging-only` runs ONLY the staging_check loop (hourly cron, see promote_alerting_cron.txt - NOT installed) and a
# staging FAIL (behind / diverged / latest deploy FAILED) writes ONE alerts.log WARN per (repo, candidate sha), deduped via state/qa_shadow_alerted/, so a
# shadow-gate FAIL reaches the digest instead of sitting in a jsonl nobody reads. Still observation only (no push, no block).
# 2026-10-09 (QA-N1): the full (daily) run ALSO runs qa/staging_smoke.py for billwatch gitlark iptv_apps (shadow, see the smoke block at the end; QA_DAILY_SMOKE_REPOS overrides).
# Cron: 50 8 * * *  $HOME/overnight-queue/qa/qa_daily_shadow.sh >> $HOME/overnight-queue/logs/qa_daily_shadow.out 2>&1
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
export PATH="$HOME/qa-venv/bin:$HOME/qa-tools/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
PY="$(command -v python3.12 || command -v python3)"
LOG="$OVN_DIR/logs/qa_daily_shadow.log"; mkdir -p "$OVN_DIR/logs" 2>/dev/null
RELEASE_REPOS="${QA_DAILY_REPOS:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-labs-website}"
STAGING_REPOS="${QA_DAILY_STAGING_REPOS:-billwatch gitlark iptv_apps}"
T="${QA_GATE_TIMEOUT:-300}"
log(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
verdict(){ printf '%s' "$1" | "$PY" -c 'import sys,json
try:
    d=json.loads(sys.stdin.read()); print(d.get("verdict","?"), "|", str(d.get("summary",""))[:150])
except Exception: print("NO-OUTPUT")' 2>/dev/null; }
[ "${OVN_QA_DAILY:-on}" = "off" ] && { log "disabled (OVN_QA_DAILY=off)"; exit 0; }
ONLY=0; [ "${1:-}" = "--staging-only" ] && ONLY=1
STATE_D="${QA_STATE_DIR:-$OVN_DIR/state}"
alert_once(){ # $1=repo $2=staging_check json: ONE alerts.log WARN per (repo, candidate) when the verdict is FAIL
  local line
  line="$(printf '%s' "$2" | "$PY" -c 'import sys,json
try:
    d=json.loads(sys.stdin.read())
    if d.get("verdict")=="FAIL": print(str(d.get("ref","?"))+"|"+str(d.get("summary",""))[:200])
except Exception: pass' 2>/dev/null)"
  [ -n "$line" ] || return 0
  local ref="${line%%|*}" m="$STATE_D/qa_shadow_alerted/staging_${1}_${line%%|*}"
  [ -e "$m" ] && return 0
  mkdir -p "$STATE_D/qa_shadow_alerted" 2>/dev/null; : > "$m" 2>/dev/null
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN | qa-staging-check | $1 candidate $ref: staging_check FAIL: ${line#*|}" >> "$STATE_D/alerts.log"
}
[ "$ONLY" = 1 ] && RELEASE_REPOS=""
for r in $RELEASE_REPOS; do
  out="$("$PY" "$HERE/qa_timeout.py" "$T" "$PY" "$HERE/release_candidate.py" plan --repo "$r" --fetch 2>>"$LOG" | tail -1)"
  log "release_candidate $r: $(verdict "$out")"
done
for r in $STAGING_REPOS; do
  out="$("$PY" "$HERE/qa_timeout.py" "$T" "$PY" "$HERE/staging_check.py" check --repo "$r" --release-plan --provider file 2>>"$LOG" | tail -1)"
  log "staging_check $r: $(verdict "$out")"
  alert_once "$r" "$out"
done
# 2026-10-09 (QA-N1): the REAL staging smoke (qa/staging_smoke.py: health, login, business steps, write+read-back, cors) for every repo with a staging backend, ONCE a day
# in the full run (never in --staging-only: the hourly pass must stay cheap, the smoke writes to staging). SHADOW: the gate records its own row in state/qa_shadow/staging_smoke.jsonl;
# a FAIL also writes ONE alerts.log WARN per (repo, day). gitlark has no password login, so it stays FLAG "PARTIAL" by design (not an alert). Serial with the e2e runner:
# both take the mkdir lock state/staging_e2e.lock (staging state - the canonical accounts and the rate-limit window - is shared); a busy lock is waited for
# QA_E2E_LOCK_WAIT_S (default 120 s), then that repo's smoke is SKIPPED this round (logged), never run concurrently.
SMOKE_REPOS="${QA_DAILY_SMOKE_REPOS:-billwatch gitlark iptv_apps}"
[ "$ONLY" = 1 ] && SMOKE_REPOS=""
[ -f "$HERE/staging_smoke.py" ] || SMOKE_REPOS=""
E2E_LOCK="$STATE_D/staging_e2e.lock"
lock_take(){ # $1 = max wait seconds; 0 = got it, 1 = busy
  local waited=0 swept=0
  while :; do
    if mkdir "$E2E_LOCK" 2>/dev/null; then echo "$$" > "$E2E_LOCK/pid" 2>/dev/null; return 0; fi
    if [ "$swept" = 0 ] && [ -n "$(find "$E2E_LOCK" -maxdepth 0 -mmin +"${QA_E2E_LOCK_STALE_MIN:-30}" 2>/dev/null)" ]; then swept=1; rm -rf "$E2E_LOCK"; continue; fi
    [ "$waited" -ge "$1" ] && return 1
    sleep 2; waited=$((waited+2))
  done
}
smoke_alert_once(){ # $1=repo $2=smoke json: ONE alerts.log WARN per (repo, UTC day) when the verdict is FAIL
  local line m
  line="$(printf '%s' "$2" | "$PY" -c 'import sys,json
try:
    d=json.loads(sys.stdin.read())
    if d.get("verdict")=="FAIL": print(str(d.get("summary",""))[:200])
except Exception: pass' 2>/dev/null)"
  [ -n "$line" ] || return 0
  m="$STATE_D/qa_shadow_alerted/smoke_${1}_$(date -u +%Y%m%d)"
  [ -e "$m" ] && return 0
  mkdir -p "$STATE_D/qa_shadow_alerted" 2>/dev/null; : > "$m" 2>/dev/null
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN | qa-staging-smoke | $1 staging smoke FAIL: $line" >> "$STATE_D/alerts.log"
}
for r in $SMOKE_REPOS; do
  if ! lock_take "${QA_E2E_LOCK_WAIT_S:-120}"; then log "staging_smoke $r: SKIPPED (staging e2e lock busy)"; continue; fi
  out="$("$PY" "$HERE/qa_timeout.py" "$T" "$PY" "$HERE/staging_smoke.py" check --repo "$r" 2>>"$LOG" | tail -1)"
  rm -rf "$E2E_LOCK"
  log "staging_smoke $r: $(verdict "$out")"
  smoke_alert_once "$r" "$out"
done
log "done"
exit 0
