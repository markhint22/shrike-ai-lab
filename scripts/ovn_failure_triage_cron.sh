#!/usr/bin/env bash
# ovn_failure_triage_cron.sh — hourly runner for scripts/ovn_failure_triage.py (Phase 6c).
#
# Runs the detection pass (clusters new BAD-bucket outcomes by error signature into
# state/failure_clusters.json) and pushes ONE high-priority notification when — and only when —
# a failure pattern we already marked "fixed" has come back. That is the single rare, always
# actionable signal this whole phase exists to surface: it means a fix didn't cover the real
# cause, or got undone.
#
# Brand-new (never-seen) patterns are deliberately NOT pushed from here. They are folded into the
# routine 3-hourly digest (digest_notify.sh calls `ovn_failure_triage.py --digest`), because the
# 2026-09-28 notification redesign consolidated four scripts that each alerted on the same fact
# into one and this must not re-fragment that. This script is the only place a REGRESSION is
# pushed, so there is no second reporter to duplicate it.
#
# Why the regression push lives HERE and not in the digest: the detection cursor
# (state/.failure_triage.cursor) means each outcomes.jsonl record is processed exactly once, so
# each regression event is reported exactly once for free — no overlapping-window duplicates, no
# dependence on the digest buffer being non-empty, and it reaches the phone within the hour
# instead of up to 3h later.
#
# A failed push is never dropped: the cursor has already advanced, so the un-sent lines are kept
# in state/failure_triage_pending_push.txt and re-attempted on the next run (same lesson as the
# digest's 2026-09-19 "don't wipe the buffer if the send failed" fix).
#
# Pure observability: never blocks, reverts, or modifies anything else in the pipeline, and always
# exits 0 so a broken triage run can never turn into a cron-failure alert of its own.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
# Append (not prepend) the standard dirs: cron's PATH is minimal so they are still needed, but a
# caller-supplied earlier entry must win — the regression test relies on that to substitute a stub
# curl, and prepending would send the test's fake pushes to the real network.
export PATH="${PATH:-}:/usr/local/bin:/usr/bin:/bin"
DIR="$PWD"
STATE_DIR="state"
LOG="logs/ovn_failure_triage.log"
PENDING="$STATE_DIR/failure_triage_pending_push.txt"
mkdir -p logs "$STATE_DIR" 2>/dev/null
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }

# shellcheck disable=SC1091
[ -f "$DIR/scripts/lib_lock.sh" ] && source "$DIR/scripts/lib_lock.sh"
if command -v acquire_lock >/dev/null 2>&1; then
  acquire_lock "$STATE_DIR/failure_triage.lock" 227 60 "failure-triage" log >> "$LOG" 2>&1 \
    || { say "another triage pass holds the lock — skipping this run"; exit 0; }
fi

OUT="$(python3 "$DIR/scripts/ovn_failure_triage.py" "$STATE_DIR" "$DIR/logs" 2>&1)"; rc=$?
say "detection pass rc=$rc"
printf '%s\n' "$OUT" | sed 's/^/    /' >> "$LOG"
[ "$rc" -ne 0 ] && exit 0

# Lines look like: "  REGRESSION  <repo> :: <signature> (previously fixed by <commit>, now seen Nx total)"
REG="$(printf '%s\n' "$OUT" | grep -E '^ +REGRESSION +' | head -5 \
        | sed -E 's/^ +REGRESSION +/  • /; s/ :: /: /')"
if [ -f "$PENDING" ]; then
  REG="$(printf '%s\n%s\n' "$(cat "$PENDING")" "$REG" | sed '/^$/d' | head -8)"
fi
[ -z "$REG" ] && exit 0

TOPIC="${NTFY_TOPIC:-$(cat "$STATE_DIR/ntfy_topic" 2>/dev/null)}"
if [ -z "$TOPIC" ]; then
  say "regression(s) found but no ntfy topic configured — kept pending"
  printf '%s\n' "$REG" > "$PENDING"
  exit 0
fi

BODY="These failure patterns were marked fixed, but just happened again — so the fix either did not cover the real cause or was undone:
$REG

After re-fixing, record it: ovn_failure_triage.py --ack <repo> <part-of-signature> --commit <hash> --generator-addressed <yes|no|unsure>"

sent=0
for attempt in 1 2 3; do
  if curl -fsS --max-time 8 -H "Title: A bug we already fixed is back" -H "Tags: warning" \
       -H "Priority: high" -d "$BODY" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1; then
    sent=1; break
  fi
  sleep 2
done
if [ "$sent" = 1 ]; then
  rm -f "$PENDING"
  say "pushed regression alert ($(printf '%s\n' "$REG" | wc -l | tr -d ' ') pattern(s))"
else
  printf '%s\n' "$REG" > "$PENDING"
  say "regression push FAILED after 3 attempts — kept in $PENDING for the next run"
fi
exit 0
