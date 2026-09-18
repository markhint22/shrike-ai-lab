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
# Usage: source this file, then:
#   acquire_lock "$STATE_DIR/some.lock" 201 "${SOME_LOCK_WAIT:-0}" "my-script"
#   # ... exit 0 here if it returned 1 - the lock was NOT acquired ...
#
# A wait of 0 behaves exactly like the old `flock -n` (immediate bail, no alert
# spam for callers that fire so often a brief overlap is routine and expected -
# e.g. the hourly 6-repo pass shouldn't wait on itself between its own repos).
acquire_lock() {
  local lock_file="$1" fd="$2" wait_seconds="${3:-0}" label="${4:-lock}"
  mkdir -p "$(dirname "$lock_file")" 2>/dev/null
  eval "exec ${fd}>\"\$lock_file\""
  if ! flock -w "$wait_seconds" "$fd"; then
    echo "[$label $(date '+%F %H:%M:%S')] another pass is already running — skipping this tick (waited ${wait_seconds}s)."
    if [ "$wait_seconds" -gt 0 ] 2>/dev/null; then
      local _lock_dir; _lock_dir="$(dirname "$lock_file")"
      local _state_dir; _state_dir="$(dirname "$_lock_dir")"
      [ "$(basename "$_lock_dir")" = "state" ] && _state_dir="$_lock_dir"
      local topic="${NTFY_TOPIC:-$(cat "$_state_dir/ntfy_topic" 2>/dev/null)}"
      if [ -n "$topic" ]; then
        curl -fsS --max-time 8 -H "Title: $label lock contention" -H "Tags: warning" \
          -d "$label waited ${wait_seconds}s for $(basename "$lock_file") and gave up — another pass is still holding it. If this repeats, either the holder is stuck or the wait window is too short." \
          "https://ntfy.sh/$topic" >/dev/null 2>&1 || true
      fi
    fi
    return 1
  fi
  return 0
}
