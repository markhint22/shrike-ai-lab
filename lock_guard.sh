#!/usr/bin/env bash
# lock_guard.sh — backstop for an ORPHANED run.lock (2026-09-09).
#
# THE BUG THIS PREVENTS: run_overnight.sh takes the fleet lock with `exec 200>state/run.lock; flock -n 200`.
# fd 200 is INHERITED by every child it forks (aider, git, reconcile, fleet_autofix subshells). If the
# parent run_overnight dies but a child is still alive, that child keeps fd 200 open → the lock stays
# HELD → every systemd restart of run_overnight bounces off "Another run_overnight is already in progress"
# and exits. The fleet then sits DEAD indefinitely while systemd restart-loops against a lock nobody
# legitimately owns. (Observed 2026-09-09: a hung fleet_autofix→reconcile child held the lock for ~4h.)
#
# THE FIX: if the lock is held but NO legitimate owner (run_overnight.sh or fleet_autofix.sh) is alive,
# the holders are orphans — kill them so the next systemd restart re-acquires the lock and the fleet runs.
# Cron: */10 * * * *  cd ~/overnight-queue && NTFY_TOPIC=... ./lock_guard.sh >> logs/lock_guard.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" 2>/dev/null || exit 0
LOCK="state/run.lock"
TOPIC="${NTFY_TOPIC:-$(cat state/ntfy_topic 2>/dev/null)}"

holders="$(fuser "$LOCK" 2>/dev/null | tr -s ' ')"
[ -z "$(printf '%s' "$holders" | tr -d ' ')" ] && exit 0     # lock not held — nothing to do

# 2026-09-09 FIX: the old check was `pgrep -f run_overnight.sh` GLOBALLY - does ANY such process
# exist anywhere on the box - not whether the ACTUAL HOLDER of the lock is one. Under systemd
# Restart=always, a crash-restart loop (each new instance dies near-instantly on the lock check,
# then a fresh one spawns 20s later) means a run_overnight.sh process is ALWAYS alive at nearly any
# instant, even though NONE of them can ever actually acquire the lock - so this guard's own
# detection was blind to exactly the failure mode it exists to catch, every single time it took this
# shape (confirmed live: two ~10min stalls in one night, 00:22-00:32 and 06:33-06:43, recovered by
# something OTHER than this script - lock_guard.log was empty through both). Fixed to check whether
# the SPECIFIC PID(s) fuser reports as holding the lock are themselves run_overnight.sh/
# fleet_autofix.sh (a legitimate owner actually using it), not just whether that process name exists
# anywhere in the process table.
legit=0
for p in $holders; do
  [ -n "$p" ] || continue
  cmd="$(ps -o cmd= -p "$p" 2>/dev/null)"
  case "$cmd" in *run_overnight.sh*|*fleet_autofix.sh*) legit=1;; esac
done
[ "$legit" = 1 ] && exit 0   # the lock's actual holder is a legitimate live owner — leave it

# Held with NO legitimate owner => orphaned holders blocking the fleet. Clear them.
killed=""
for p in $holders; do [ -n "$p" ] && kill -9 "$p" 2>/dev/null && killed="$killed $p"; done
sleep 1
still="$(fuser "$LOCK" 2>/dev/null | tr -d ' ')"
echo "$(date '+%F %T') lock_guard: killed orphaned run.lock holders [$killed ] — still-held=${still:-none} (no live run_overnight/fleet_autofix; fleet was blocked)"
[ -n "$TOPIC" ] && curl -fsS --max-time 8 \
  -H "Title: fleet lock-orphan cleared" -H "Tags: wrench" \
  -d "lock_guard killed orphaned run.lock holders that were blocking the fleet with no live owner. systemd will restart run_overnight and the fleet resumes." \
  "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
