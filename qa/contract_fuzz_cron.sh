#!/usr/bin/env bash
# contract_fuzz_cron.sh - BOX: nightly hermetic contract fuzz of the release candidate (QA-N2, SHADOW only; see qa/contract_fuzz.README.md).
# Runs `contract_fuzz.py check --repo iptv_apps` (candidate = origin/develop by default) and appends ONE summary line to logs/contract_fuzz.log.
# Cron (NOT installed; install only after the first manual run and a reviewed --accept-baseline):
#   20 4 * * * cd ~/overnight-queue && bash qa/contract_fuzz_cron.sh >> logs/contract_fuzz.log 2>&1
# Safe by construction: own path resolved BEFORE any cd, minimal PATH, ONE instance (flock -n on state/contract_fuzz.lock; mkdir fallback where
# there is no flock), skips while the fleet is paused (state/PAUSED) or the box is busy (1-min load average > OVN_FUZZ_LOAD_MAX, default 6),
# CPU-polite (nice 15 inside contract_fuzz.py; no GPU), never takes run.lock or a verify lock, never touches a live clone's working tree
# (detached worktree only), never pushes/notifies, ALWAYS exits 0 (a broken fuzz run must not become a cron alert).
# Kill switch: OVN_CONTRACT_FUZZ=off.  Tunables: OVN_FUZZ_REPOS (default "iptv_apps"), OVN_FUZZ_REF (default origin/develop),
# OVN_FUZZ_TIMEOUT_S (default 600, passed through to contract_fuzz.py), OVN_FUZZ_LOAD_MAX.
set -u
SELF="${BASH_SOURCE[0]:-$0}"
case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)" || exit 0
export OVN_DIR="${OVN_DIR:-$(cd "$HERE/.." && pwd)}"
export PATH="$HOME/qa-venv/bin:/usr/local/bin:/usr/bin:/bin:/opt/homebrew/bin"
export PYTHONDONTWRITEBYTECODE=1
STATE="${QA_STATE_DIR:-$OVN_DIR/state}"; LOGD="$OVN_DIR/logs"
mkdir -p "$STATE" "$LOGD" 2>/dev/null || exit 0
LOG="$LOGD/contract_fuzz.log"
say(){ printf '%s contract_fuzz: %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }

[ "${OVN_CONTRACT_FUZZ:-on}" = off ] && { say "disabled (OVN_CONTRACT_FUZZ=off)"; exit 0; }
[ -e "$STATE/PAUSED" ] && { say "skipped (state/PAUSED exists)"; exit 0; }
PY="$(command -v python3.12 || command -v python3)"
[ -n "$PY" ] || { say "no python3 - skipped"; exit 0; }
[ -f "$HERE/contract_fuzz.py" ] && [ -f "$HERE/qa_common.py" ] || { say "contract_fuzz.py/qa_common.py missing - skipped"; exit 0; }

# load average (1 min): /proc/loadavg on the box, uptime elsewhere. Unreadable => treated as idle.
LOAD="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
[ -n "$LOAD" ] || LOAD="$(uptime 2>/dev/null | sed -e 's/.*load averages*: *//' -e 's/,/ /g' | awk '{print $1}')"
LMAX="${OVN_FUZZ_LOAD_MAX:-6}"
if [ -n "$LOAD" ] && awk -v l="$LOAD" -v m="$LMAX" 'BEGIN{exit !(l+0 > m+0)}'; then
  say "skipped (1-min load average $LOAD > $LMAX)"; exit 0
fi

# OUR OWN lock only: one fuzz run at a time. flock on the box; mkdir lock with 2h stale takeover elsewhere.
LOCK="$STATE/contract_fuzz.lock"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK" || exit 0
  flock -n 9 || { say "previous run still holds $LOCK - skipped"; exit 0; }
else
  if ! mkdir "$LOCK.d" 2>/dev/null; then
    if [ -n "$(find "$LOCK.d" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rmdir "$LOCK.d" 2>/dev/null; mkdir "$LOCK.d" 2>/dev/null || exit 0
    else say "previous run still holds $LOCK.d - skipped"; exit 0; fi
  fi
  trap 'rmdir "$LOCK.d" 2>/dev/null' EXIT
fi

CAP="${OVN_FUZZ_TIMEOUT_S:-600}"; export OVN_FUZZ_TIMEOUT_S="$CAP"
TO=""; command -v timeout >/dev/null 2>&1 && TO="timeout $((CAP + 180))"; command -v gtimeout >/dev/null 2>&1 && [ -z "$TO" ] && TO="gtimeout $((CAP + 180))"
REF="${OVN_FUZZ_REF:-origin/develop}"
for r in ${OVN_FUZZ_REPOS:-iptv_apps}; do
  case "$r" in *[!A-Za-z0-9._-]*|"") say "skipped bad repo name"; continue ;; esac
  t0=$(date +%s)
  out="$($TO "$PY" "$HERE/contract_fuzz.py" check --repo "$r" --ref "$REF" 2>>"$LOG" | tail -n 1)"
  line="$(printf '%s' "$out" | "$PY" -c 'import sys,json
try:
    d=json.loads(sys.stdin.read()); print(d.get("verdict","?"), "|", str(d.get("summary",""))[:220])
except Exception: print("NO-OUTPUT | timeout or crash")' 2>/dev/null)"
  say "$r ref=$REF ${line:-NO-OUTPUT} ($(( $(date +%s) - t0 ))s)"
done
exit 0
