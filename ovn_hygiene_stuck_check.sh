#!/usr/bin/env bash
# ovn_hygiene_stuck_check.sh — escalate a branch_hygiene.sh gate that's been stuck for hours.
#
# WHY THIS EXISTS (2026-09-10): branch_hygiene.sh already writes a
# state/branch_hygiene_review_<repo> flag file on EVERY failure (gate red, merge conflict, push
# failed, worktree failed) and clears it the instant a merge succeeds — but nothing ever READS
# that flag to tell a human. It just sits there, silently overwritten every cycle. Two real
# incidents on 2026-09-10 (gitlark: 9h, 18+ wasted cycles, one stuck OpenAPI contract test;
# billwatch: 17h, 98 commits piled up, an intermittent gate failure) were only discovered by
# manually reading through hours of log history — the exact kind of stuck-and-silent situation
# this pipeline has repeatedly hit. This closes that gap using the same marker-file dedup
# pattern already proven in queue_health.sh (qh_bad_) and queue_refill.sh (qr_dry_): first-seen
# timestamp tracked separately from the flag's own content (which gets rewritten — and its mtime
# refreshed — on every single failing cycle, so mtime alone can't tell you how long this has
# really been going on).
#
# Cron (server): 5 */1 * * * cd ~/overnight-queue && NTFY_TOPIC=shrike_ovn_311380987a ./ovn_hygiene_stuck_check.sh >> logs/ovn_hygiene_stuck_check.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
STATE_DIR="state"; mkdir -p "$STATE_DIR"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
STUCK_HOURS="${HYGIENE_STUCK_HOURS:-2}"          # first alert threshold
REMIND_HOURS="${HYGIENE_STUCK_REMIND_HOURS:-6}"  # repeat reminder cadence while still stuck
STUCK_SECS=$(( STUCK_HOURS * 3600 ))
REMIND_SECS=$(( REMIND_HOURS * 3600 ))
log(){ echo "$(date '+%F %T') $*"; }
alert(){ curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -d "$3" "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true; }

now=$(date +%s)
seen_repos=""

for flag in "$STATE_DIR"/branch_hygiene_review_*; do
  [ -f "$flag" ] || continue
  name="${flag#"$STATE_DIR"/branch_hygiene_review_}"
  seen_repos="$seen_repos $name"
  since_marker="$STATE_DIR/hygiene_stuck_since_$name"
  alerted_marker="$STATE_DIR/hygiene_stuck_alerted_$name"
  reason="$(cat "$flag" 2>/dev/null)"

  if [ ! -f "$since_marker" ]; then
    echo "$now" > "$since_marker"
    log "$name: newly stuck ($reason)"
    continue
  fi

  since="$(cat "$since_marker" 2>/dev/null || echo "$now")"
  elapsed=$(( now - since ))
  elapsed_h=$(( elapsed / 3600 ))

  if [ "$elapsed" -ge "$STUCK_SECS" ]; then
    last_alert="$(cat "$alerted_marker" 2>/dev/null || echo 0)"
    if [ "$last_alert" -eq 0 ]; then
      alert "Branch hygiene STUCK: $name" "rotating_light" \
        "$name has not merged to develop/main in ~${elapsed_h}h. Reason: $reason. This blocks EVERY fleet item for $name from ever landing until fixed — worth a look now, not at the next digest."
      echo "$now" > "$alerted_marker"
      log "$name: stuck ${elapsed_h}h — ALERTED (first)"
    elif [ $(( now - last_alert )) -ge "$REMIND_SECS" ]; then
      alert "Branch hygiene STILL STUCK: $name" "rotating_light" \
        "$name has not merged in ~${elapsed_h}h (unresolved since the first alert). Reason: $reason."
      echo "$now" > "$alerted_marker"
      log "$name: stuck ${elapsed_h}h — ALERTED (reminder)"
    else
      log "$name: stuck ${elapsed_h}h — within cooldown, no alert"
    fi
  else
    log "$name: stuck ${elapsed_h}h — below ${STUCK_HOURS}h threshold, no alert yet"
  fi
done

# recovery: any repo with a since-marker but NO current review flag has merged successfully
for since_marker in "$STATE_DIR"/hygiene_stuck_since_*; do
  [ -f "$since_marker" ] || continue
  name="${since_marker#"$STATE_DIR"/hygiene_stuck_since_}"
  case " $seen_repos " in
    *" $name "*) continue;;  # still stuck, handled above
  esac
  since="$(cat "$since_marker" 2>/dev/null || echo "$now")"
  elapsed_h=$(( (now - since) / 3600 ))
  alerted_marker="$STATE_DIR/hygiene_stuck_alerted_$name"
  if [ -f "$alerted_marker" ]; then
    alert "Branch hygiene recovered: $name" "white_check_mark" \
      "$name merged successfully after being stuck ~${elapsed_h}h."
    log "$name: recovered after ${elapsed_h}h — sent recovery note"
  else
    log "$name: recovered after ${elapsed_h}h (never crossed the alert threshold, no note needed)"
  fi
  rm -f "$since_marker" "$alerted_marker"
done

log "hygiene-stuck check complete"
