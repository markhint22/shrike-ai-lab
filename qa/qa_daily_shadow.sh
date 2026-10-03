#!/usr/bin/env bash
# qa_daily_shadow.sh - BOX: once a day, just before the 09:00 promote, run the release-flow gates in SHADOW for every repo that gets promoted:
#   release_candidate plan  (which develop SHA would a release branch be cut from, and what is held back)
#   staging_check           (does staging serve that SHA?  evidence = the Mac's 10-minutely snapshot, state/staging_deploys/<repo>.json)
# 2026-10-02. Observation only: never pushes, never promotes, never takes run.lock; ALWAYS exits 0. Results -> state/qa_shadow/*.jsonl + logs/qa_daily_shadow.log.
# 2026-10-03 (A10): `qa_daily_shadow.sh --staging-only` runs ONLY the staging_check loop (hourly cron, see promote_alerting_cron.txt - NOT installed) and a
# staging FAIL (behind / diverged / latest deploy FAILED) writes ONE alerts.log WARN per (repo, candidate sha), deduped via state/qa_shadow_alerted/, so a
# shadow-gate FAIL reaches the digest instead of sitting in a jsonl nobody reads. Still observation only (no push, no block).
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
log "done"
exit 0
