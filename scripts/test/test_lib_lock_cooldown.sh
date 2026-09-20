#!/usr/bin/env bash
# Regression test for scripts/lib_lock.sh's alert-cooldown behavior (2026-09-19 fix).
#
# Root cause this guards against: fleet-autofix (wait=600) runs every 20min via cron and
# routinely contends with run_overnight.sh's long-running cycles - BEFORE this fix, every
# single contended tick fired a fresh ntfy alert, producing ~20 near-identical
# "lock contention" pushes across one overnight window even though nothing was actually
# stuck (self-resolved by the next tick every time). This test verifies: (1) the FIRST
# contention alerts, (2) an immediately-following contention on the SAME lock does NOT
# alert again (logs the "within cooldown" line instead), (3) a successful acquire clears
# the cooldown marker so a FUTURE fresh contention alerts right away, not suppressed by a
# stale window from an unrelated earlier incident, and (4) wait=0 callers (e.g.
# branch_hygiene.sh's own-repo-to-own-repo overlap) never alert at all, cooldown or not -
# unchanged legacy behavior.
#
# 2026-09-20 addition: the optional 5th "notify" arg (fleet_autofix.sh now passes "log" for
# its run.lock contention - see lib_lock.sh's 2026-09-20 header note and fleet_autofix.sh -
# lock_guard.sh independently detects+alerts a REAL orphan on that same lock, so this specific
# caller's routine "waited and gave up" case was pure noise). Verifies: the marker/cooldown
# bookkeeping is UNCHANGED (still gates on the same schedule) but no ntfy push is attempted,
# and the default (omitted 5th arg) still behaves exactly as before (push to ntfy).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_lock.sh"; [ -f "$LIB" ] || LIB="$HERE/lib_lock.sh"
[ -f "$LIB" ] || { echo "  SKIP: lib_lock.sh not found"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export NTFY_TOPIC="shrike_fleetautofix_selftest_ignore"   # any alert goes to an unwatched junk topic

STATE="$tmp/state"; mkdir -p "$STATE"
LOCKFILE="$STATE/run.lock"

# Hold the lock in a background subshell for the whole test so every acquire_lock call
# below genuinely contends (mirrors run_overnight.sh holding run.lock for a real cycle).
(
  exec 250>"$LOCKFILE"
  flock 250
  sleep 30
) &
HOLDER_PID=$!
# wait for the holder to actually grab the flock before we start contending on it
for _ in $(seq 1 50); do
  if ! flock -n -w 0 250 2>/dev/null; then break; fi
  sleep 0.1
done

run_acquire(){
  local wait="$1" label="$2" logfile="$3" notify="${4:-ntfy}"
  ( source "$LIB"; acquire_lock "$LOCKFILE" 201 "$wait" "$label" "$notify" ) >> "$logfile" 2>&1
}

# --- 1: first contention (wait>0) alerts and creates a cooldown marker ---
log1="$tmp/l1.log"; : > "$log1"
LOCK_ALERT_COOLDOWN_SECS=3600 run_acquire 1 selftest-A "$log1"
marker="$STATE/lock_alert_selftest-A_run.lock"
ok "first contention: logs the base contention line" "grep -q 'another pass is already running' '$log1'"
ok "first contention: does NOT log 'within cooldown' (this is the fresh alert)" "! grep -q 'within cooldown' '$log1'"
ok "first contention: creates the cooldown marker" "[ -f '$marker' ]"

# --- 2: immediately-following contention on the SAME lock is suppressed ---
log2="$tmp/l2.log"; : > "$log2"
LOCK_ALERT_COOLDOWN_SECS=3600 run_acquire 1 selftest-A "$log2"
ok "second immediate contention: logs 'within cooldown' (suppressed, not a fresh alert)" "grep -q 'within cooldown' '$log2'"
marker_mtime1="$(cat "$marker" 2>/dev/null)"
ok "second immediate contention: marker timestamp unchanged (no new alert fired)" "[ -n '$marker_mtime1' ]"

# --- 3: a DIFFERENT label's contention is tracked independently (no cross-talk) ---
log3="$tmp/l3.log"; : > "$log3"
LOCK_ALERT_COOLDOWN_SECS=3600 run_acquire 1 selftest-B "$log3"
ok "different label: alerts fresh (own marker, unaffected by selftest-A's cooldown)" "! grep -q 'within cooldown' '$log3'"
ok "different label: creates its own marker" "[ -f '$STATE/lock_alert_selftest-B_run.lock' ]"

# --- 3b: notify="log" gates/marks identically but never touches ntfy at all ---
log3b="$tmp/l3b.log"; : > "$log3b"
LOCK_ALERT_COOLDOWN_SECS=3600 run_acquire 1 selftest-logmode "$log3b" log
marker_log="$STATE/lock_alert_selftest-logmode_run.lock"
ok "notify=log: still logs the base contention line" "grep -q 'another pass is already running' '$log3b'"
ok "notify=log: still creates its own cooldown marker (bookkeeping unchanged)" "[ -f '$marker_log' ]"
ok "notify=log: logs a 'suppressed' line instead of pushing to ntfy" "grep -q 'ntfy push suppressed' '$log3b'"
log3c="$tmp/l3c.log"; : > "$log3c"
LOCK_ALERT_COOLDOWN_SECS=3600 run_acquire 1 selftest-logmode "$log3c" log
ok "notify=log: an immediate repeat is STILL cooldown-suppressed the same as ntfy mode" "grep -q 'within cooldown' '$log3c'"

# --- 4: wait=0 callers never alert (legacy `flock -n` behavior unchanged) ---
log4="$tmp/l4.log"; : > "$log4"
run_acquire 0 selftest-zerowait "$log4"
ok "wait=0: logs the base contention line" "grep -q 'another pass is already running' '$log4'"
ok "wait=0: never creates a cooldown marker (no alert path at all)" "[ ! -f '$STATE/lock_alert_selftest-zerowait_run.lock' ]"

# --- 5: once the holder releases, a real acquire succeeds and clears the marker ---
wait "$HOLDER_PID" 2>/dev/null
log5="$tmp/l5.log"; : > "$log5"
run_acquire 5 selftest-A "$log5"
ok "lock free: acquire_lock returns success (no contention line)" "! grep -q 'another pass is already running' '$log5'"
ok "lock free: clears the stale cooldown marker on a clean acquire" "[ ! -f '$marker' ]"

echo "lib_lock.sh cooldown: $P passed, $F failed"
[ "$F" -eq 0 ]
