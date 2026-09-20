#!/usr/bin/env bash
# scripts/lib_lock.sh — shared bounded-wait lock helper.
#
# 2026-09-18: extracted from branch_hygiene.sh's hand-rolled `flock -n` block after
# root-causing a 5+ day silent failure - billwatch's 3-hourly hygiene slot fires 10
# minutes after the hourly 6-repo pass starts, that pass routinely runs longer than
# 10 minutes, so the non-blocking lock lost the race on effectively every scheduled
# tick since at least 2026-09-13. Nobody was told: the only trace was a line in a
# log file nobody tails. Two fixes baked in here, not just in branch_hygiene.sh:
#   1. Bounded WAIT instead of immediate bail, so a caller that can tolerate some
#      delay (most cron-driven passes can) just waits out the other holder instead
#      of skipping the tick outright.
#   2. An ntfy alert when the wait itself times out - that's the actual "something
#      is wrong" signal (a normal, brief overlap resolves during the wait and never
#      alerts; only a holder that's stuck past the wait window fires).
#
# 2026-09-19 FIX: fleet-autofix (wait=600) runs every 20min via cron, and
# run_overnight.sh routinely holds run.lock for a full multi-repo cycle (the
# "whole block runs holding run.lock" design in run_overnight.sh) - often well
# over an hour. That means the *normal*, everyday case became "fleet-autofix
# waits out its whole 600s window and gives up", not the rare "holder is stuck"
# case this alert was designed for. Confirmed live: ~20 identical "fleet-autofix
# lock contention" ntfy pushes in one 12h overnight window, none of them a real
# problem (every one self-resolved by the next tick once run_overnight finished
# its cycle) - this was the single largest source of the "many errors and
# warnings" the alerting was supposed to be reserved for. Same fix shape as the
# existing dry-repo/roadmap-exhausted reminders elsewhere in this codebase
# (state/qr_dry_<repo> markers): alert once when contention STARTS, stay silent
# on every immediately-following contention while it persists, and only
# re-alert once per LOCK_ALERT_COOLDOWN_SECS if it's still ongoing (a real
# "genuinely stuck" holder now reads as one alert + hourly reminders, not a
# push every 20-40 minutes). A successful acquire clears the marker so the next
# fresh contention alerts immediately, same as `recovered` in queue_refill.sh.
#
# 2026-09-19 OPERATIONAL NOTE: the 23458fb credit-loss/lock-cooldown fix above
# landed run_overnight.sh as mode 100644 (non-executable) - overnight-queue.service
# execs it directly as ExecStart, so this silently crash-looped the whole fleet for
# ~2h (10:18-12:15 CDT) before anyone noticed, fixed in 3e3982e by chmod +x only.
# Practice going forward for ANY edit to a script this systemd/cron execs directly
# (run_overnight.sh, branch_hygiene.sh, fleet_autofix.sh, ovn_stage_runner.sh,
# scripts/ovn_item_guard.sh): when using an atomic write-then-mv swap, explicitly
# `chmod --reference=<original> <new file>` (or `chmod +x`) BEFORE the `mv`, and
# verify with `test -x <file>` (or `git show HEAD --stat` after committing) - do
# not assume a heredoc/cp/mv preserves the original mode bits.
#
# 2026-09-20 NOISE FIX: fleet-autofix's contention alert on run.lock specifically (the
# ONLY caller that hits this path routinely - see fleet_autofix.sh) turned out to be pure
# noise even WITH the hourly cooldown above: ntfy history audit (48h window, 2026-09-20)
# showed 12 of 25 total messages on the topic were this one alert, and cross-checking each
# occurrence against lock_guard.sh's cron (*/10, independently `fuser`-checks run.lock and
# kills+alerts on a genuinely-orphaned holder - see its own header) showed every single
# "gave up" alert coincided with run_overnight legitimately still holding the lock, not an
# orphan - i.e. lock_guard.sh already owns "tell a human the lock is ACTUALLY stuck" for
# this exact lock file, independent of whether fleet-autofix's own wait times out. That
# makes fleet-autofix's push redundant with a real problem detector that already exists,
# not a backstop for one. Callers can now pass a 5th arg to route this to the LOG only
# (still written every time, cooldown-gated exactly as before) instead of ntfy - use this
# for a caller whose contention is independently covered by another detector; leave it as
# "ntfy" (default, unchanged) for a lock with no separate orphan-detector watching it.
#
# Usage: source this file, then:
#   acquire_lock "$STATE_DIR/some.lock" 201 "${SOME_LOCK_WAIT:-0}" "my-script"
#   # ... exit 0 here if it returned 1 - the lock was NOT acquired ...
#   acquire_lock "$STATE_DIR/some.lock" 201 "${SOME_LOCK_WAIT:-0}" "my-script" log   # ntfy push suppressed, log-only
#
# A wait of 0 behaves exactly like the old `flock -n` (immediate bail, no alert
# spam for callers that fire so often a brief overlap is routine and expected -
# e.g. the hourly 6-repo pass shouldn't wait on itself between its own repos).
LOCK_ALERT_COOLDOWN_SECS="${LOCK_ALERT_COOLDOWN_SECS:-3600}"   # 1h between repeat alerts for the SAME still-stuck lock

acquire_lock() {
  local lock_file="$1" fd="$2" wait_seconds="${3:-0}" label="${4:-lock}" notify="${5:-ntfy}"
  mkdir -p "$(dirname "$lock_file")" 2>/dev/null
  eval "exec ${fd}>\"\$lock_file\""
  if ! flock -w "$wait_seconds" "$fd"; then
    echo "[$label $(date '+%F %H:%M:%S')] another pass is already running — skipping this tick (waited ${wait_seconds}s)."
    if [ "$wait_seconds" -gt 0 ] 2>/dev/null; then
      local _lock_dir; _lock_dir="$(dirname "$lock_file")"
      local _state_dir; _state_dir="$(dirname "$_lock_dir")"
      [ "$(basename "$_lock_dir")" = "state" ] && _state_dir="$_lock_dir"
      local _marker="$_state_dir/lock_alert_${label}_$(basename "$lock_file")"
      local _now; _now=$(date +%s)
      local _last=0; [ -f "$_marker" ] && _last="$(cat "$_marker" 2>/dev/null || echo 0)"
      if [ $(( _now - ${_last:-0} )) -ge "$LOCK_ALERT_COOLDOWN_SECS" ]; then
        echo "$_now" > "$_marker" 2>/dev/null
        if [ "$notify" = "ntfy" ]; then
          local topic="${NTFY_TOPIC:-$(cat "$_state_dir/ntfy_topic" 2>/dev/null)}"
          if [ -n "$topic" ]; then
            curl -fsS --max-time 8 -H "Title: $label lock contention" -H "Tags: warning" \
              -d "$label waited ${wait_seconds}s for $(basename "$lock_file") and gave up — another pass is still holding it. If this repeats, either the holder is stuck or the wait window is too short. (silent on immediate repeats — reminder repeats at most every $((LOCK_ALERT_COOLDOWN_SECS/60))min while it stays stuck)" \
              "https://ntfy.sh/$topic" >/dev/null 2>&1 || true
          fi
        else
          echo "[$label $(date '+%F %H:%M:%S')] contention persisted past the ${LOCK_ALERT_COOLDOWN_SECS}s cooldown — logged only, ntfy push suppressed for this caller (a genuinely orphaned lock is independently caught+alerted by lock_guard.sh; see this file's 2026-09-20 header note)."
        fi
      else
        echo "[$label $(date '+%F %H:%M:%S')] contention persists (no alert, within cooldown)."
      fi
    fi
    return 1
  fi
  # Lock acquired cleanly this tick - clear any stale contention marker so the
  # NEXT genuinely-new contention alerts right away instead of inheriting an
  # old cooldown window from an unrelated earlier incident.
  if [ "$wait_seconds" -gt 0 ] 2>/dev/null; then
    local _lock_dir2; _lock_dir2="$(dirname "$lock_file")"
    local _state_dir2; _state_dir2="$(dirname "$_lock_dir2")"
    [ "$(basename "$_lock_dir2")" = "state" ] && _state_dir2="$_lock_dir2"
    rm -f "$_state_dir2/lock_alert_${label}_$(basename "$lock_file")" 2>/dev/null
  fi
  return 0
}
