#!/usr/bin/env bash
# fleet_autofix.sh — frequent self-healing watchdog (cron */20). Two parts:
#   A) DETECT + ALERT (read-only, ALWAYS runs even while the coding loop is busy): surface only
#      persistent, non-auto-fixable issues — a clone still diverged after the self-heal window,
#      or a feature->develop gate that's been red a while. Age-gated + deduped so it never spams.
#   B) FIX (needs run_overnight's lock, so it can't race the loop; skipped if the loop is
#      mid-cycle): sync branches (main ⊆ develop ⊆ feature) + refill low/empty queues.
# Everything it calls is idempotent, so running it often is cheap when nothing is wrong.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH=/usr/local/bin:/usr/bin:/bin:${PATH:-}
STATE_DIR="$HOME/overnight-queue/state"; mkdir -p "$STATE_DIR" logs
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
LOG="logs/fleet_autofix.log"
say(){ echo "$(date '+%F %T') $*" >> "$LOG"; }
alert(){ curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true; }

say "=== autofix tick ==="

# ---- A) DETECT + ALERT (read-only; always runs) ----
issues=""
# a clone still flagged diverged > 30 min after run_overnight's self-heal should have cleared it
while IFS= read -r f; do [ -n "$f" ] && issues="$issues diverged:$(basename "$f" | sed 's/^diverged_//')"; done \
  < <(find "$STATE_DIR" -maxdepth 1 -name 'diverged_*' -mmin +30 2>/dev/null)
# a feature->develop gate red > 3h (real code issue; the fleet or a human must fix, can't auto-sync away)
while IFS= read -r f; do [ -n "$f" ] && issues="$issues gate-red:$(basename "$f" | sed 's/^branch_hygiene_review_//')"; done \
  < <(find "$STATE_DIR" -maxdepth 1 -name 'branch_hygiene_review_*' -mmin +180 2>/dev/null)
if [ -n "$issues" ]; then
  sig="$(printf '%s' "$issues" | md5sum | cut -c1-12)"
  if [ "$sig" != "$(cat "$STATE_DIR/autofix_last_sig" 2>/dev/null)" ]; then
    echo "$sig" > "$STATE_DIR/autofix_last_sig"
    alert "Fleet — a couple things need a look" "wrench" "Branch-sync + queue-refill keep running automatically. These have persisted and can't self-fix — a look when convenient:$issues"
  fi
  say "persistent issues:$issues"
else
  rm -f "$STATE_DIR/autofix_last_sig" 2>/dev/null; say "no persistent issues"
fi

# ---- B) FIX (takes the loop's lock; WAITS for the cycle to finish rather than skipping,
#         since cycles are short — only gives up if the loop is busy >10min, no cron pileup) ----
# 2026-09-15 FIX: reconcile_branches.sh/queue_refill.sh ran here with NO overall
# timeout while HOLDING fd 202 (run.lock) - a single hung git network call (a
# stalled fetch/push to GitHub) held the fleet's main lock indefinitely. If
# fleet_autofix's own process then got reaped (cron/systemd) before its child
# git process did, the child kept fd 202 open with no live run_overnight OR
# fleet_autofix left to release it - exactly the "orphaned run.lock, fleet
# blocked" pattern lock_guard.sh has been force-clearing roughly daily (see its
# own header comment: "Observed 2026-09-09: a hung fleet_autofix->reconcile
# child held the lock for ~4h"). `timeout -k` sends SIGKILL after a grace
# period if SIGTERM alone doesn't stop it, so a hang can no longer outlive
# this tick indefinitely.
# 2026-09-18: migrated to the shared scripts/lib_lock.sh helper (Phase 1, day 2 - branch_hygiene.sh
# was day 1 in 9054f371, see that commit + scripts/lib_lock.sh's header for the full root-cause
# writeup). Same bounded-wait behavior as the flock -w 600 this replaces (a wait of 600 is
# byte-for-byte equivalent), plus an ntfy alert if the wait itself times out - the actual "stuck,"
# not "briefly busy," signal. Directly relevant here: lock_guard.sh has been periodically force-
# clearing orphaned run.lock holders left by a hung reconcile/refill child (see its own log) - a
# different lock than hygiene.lock, but the same anti-pattern this helper exists to replace.
# 2026-09-20 NOISE FIX: this specific call is the ONLY thing that ever fired lib_lock.sh's
# "lock contention" ntfy push in practice (48h audit: 12/25 messages on the topic) - and it's
# genuinely redundant, not a backstop, because lock_guard.sh's own cron (*/10) independently
# `fuser`-checks this exact run.lock and kills+alerts on a REAL orphan on its own, with no
# dependency on fleet-autofix's wait ever timing out. Every one of the 12 occurrences in that
# audit coincided with run_overnight simply still legitimately holding the lock (normal,
# self-resolving), not an orphan lock_guard.sh had to intervene on. Passing "log" here keeps
# the same cooldown-gated write to logs/fleet_autofix.log (nothing lost - cron already
# redirects this script's stdout there) but stops pushing the routine case to a human's phone.
source scripts/lib_lock.sh
if acquire_lock "$STATE_DIR/run.lock" 202 600 fleet-autofix log; then
  if timeout -k 30 300 bash ./reconcile_branches.sh >> "$LOG" 2>&1; then say "reconcile ok"
  else rc=$?; [ "$rc" -eq 124 ] && say "reconcile TIMED OUT after 300s (killed)" || say "reconcile nonzero ($rc)"; fi
  if MIN_DOABLE=15 timeout -k 15 120 bash ./queue_refill.sh >> "$LOG" 2>&1; then say "refill ok"
  else rc=$?; [ "$rc" -eq 124 ] && say "refill TIMED OUT after 120s (killed)" || say "refill nonzero ($rc)"; fi
else
  say "run_overnight busy >10min — detection ran; branch-sync + refill deferred to next tick"
fi
