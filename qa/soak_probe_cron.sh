#!/usr/bin/env bash
# soak_probe_cron.sh - one SHADOW soak sample per repo (qa/soak_probe.py probe), meant for a 15-minute cron on the MAC or the BOX (see qa/phase4_cron.proposed.txt; NOT installed).
#   */15 * * * * cd ~/overnight-queue && bash qa/soak_probe_cron.sh >> logs/soak_probe.log 2>&1
# Safe by construction: own path resolved before any cd, minimal PATH, ONE instance (flock -n / mkdir lock with 30 min stale takeover), ALWAYS exit 0, no push/notify,
# never takes run.lock or a verify lock, STAGING ONLY (soak_probe refuses any other host). A repo without state/staging_url_<repo> gets an UNVERIFIED row (that is the signal).
# --candidate auto = the develop head of the repo's clone (OVN_SOAK_CANDIDATE_REF, default origin/develop, off = none) so a healthy-but-STALE staging is a provenance FAIL here too.
# Kill switch: OVN_QA_SOAK=off (also read by promote_gate).  Tunables: OVN_SOAK_REPOS (default "billwatch gitlark iptv_apps"), OVN_SOAK_SLOW_MS, OVN_QA_SOAK_MIN_HOURS.
set -u
SELF="${BASH_SOURCE[0]:-$0}"; case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)" || exit 0
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
export PATH="/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
export PYTHONDONTWRITEBYTECODE=1
STATE="${QA_STATE_DIR:-$OVN_DIR/state}"; mkdir -p "$STATE" 2>/dev/null || exit 0
say(){ printf '%s soak_probe: %s\n' "$(date '+%F %T')" "$*"; }
[ "${OVN_QA_SOAK:-shadow}" = off ] && { say "disabled (OVN_QA_SOAK=off)"; exit 0; }
PY="$(command -v python3.12 || command -v python3)"; [ -n "$PY" ] || { say "no python3 - skipped"; exit 0; }
[ -f "$HERE/soak_probe.py" ] || { say "soak_probe.py missing - skipped"; exit 0; }
LOCK="$STATE/soak_probe.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK" || exit 0
  flock -n 9 || { say "previous run still holds $LOCK - skipped"; exit 0; }
else
  if ! mkdir "$LOCK.d" 2>/dev/null; then
    if [ -n "$(find "$LOCK.d" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then rmdir "$LOCK.d" 2>/dev/null; mkdir "$LOCK.d" 2>/dev/null || exit 0
    else say "previous run still holds $LOCK.d - skipped"; exit 0; fi
  fi
  trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT
fi
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout 240"; [ -z "$TO" ] && command -v gtimeout >/dev/null 2>&1 && TO="gtimeout 240"
for r in ${OVN_SOAK_REPOS:-billwatch gitlark iptv_apps}; do
  case "$r" in *[!A-Za-z0-9._-]*|"") say "skipped bad repo name"; continue ;; esac
  out="$($TO "$PY" "$HERE/soak_probe.py" probe --repo "$r" --candidate auto 2>/dev/null | tail -n 1)"
  line="$(printf '%s' "$out" | "$PY" -c 'import sys,json
try:
    d=json.loads(sys.stdin.read()); print(d.get("verdict","?"), "|", str(d.get("summary",""))[:200])
except Exception: print("NO-OUTPUT | timeout or crash")' 2>/dev/null)"
  say "$r ${line:-NO-OUTPUT}"
done
exit 0
