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
exec 202>"$STATE_DIR/run.lock"
if flock -w 600 202; then
  if bash ./reconcile_branches.sh >> "$LOG" 2>&1; then say "reconcile ok"; else say "reconcile nonzero"; fi
  if MIN_DOABLE=15 bash ./queue_refill.sh >> "$LOG" 2>&1; then say "refill ok"; else say "refill nonzero"; fi
else
  say "run_overnight busy >10min — detection ran; branch-sync + refill deferred to next tick"
fi
