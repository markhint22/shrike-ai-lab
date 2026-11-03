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
alert(){ curl -fsS --max-time 8 -H "Title: $1" -H "Tags: $2" -H "Priority: ${4:-default}" -d "$3" "${NTFY_SERVER:-http://127.0.0.1:8099}/$TOPIC" >/dev/null 2>&1 || true; }

now=$(date +%s)
seen_repos=""

# --- 2026-11-02 (F4): "recovered" must come from the LAST hygiene RESULT, not from the review flag disappearing ---------------------------------
# branch_hygiene.sh runs once per feature branch (overnight/feature, then claude/feature) and the in-sync path of EITHER pass deletes
# state/branch_hygiene_review_<repo> ("clear any stale flag now that it's synced"), so a red overnight/feature gate looked "recovered" the moment the claude/feature pass found nothing
# to land (iptv_apps: bogus 'recovered after 8h' at 15:05 although the gate failed at 14:04 and 15:05, then 'newly stuck' again at 16:05, one real alert in 9 h).
# hyg_verdict <repo> [feature-branch] reads logs/branch_hygiene.log (the last HYGIENE_LOG_TAIL_BYTES) and prints the repo's LAST result for the stuck feature branch (each pass prints its
# own '=== repo' section followed by 'feature branch: X'; the in-sync claude/feature pass that deleted the flag therefore cannot vouch for a red overnight/feature gate):
# merged (a MERGED line or 'already in <target>'), stuck (gate FAILED / NOT merging / MERGE CONFLICT / FLAG-ONLY), unknown (the repo ran but nothing conclusive for that branch since)
# or nolog (no log / no section for the repo: the old flag-only behaviour).
HYGIENE_LOG="${HYGIENE_LOG:-logs/branch_hygiene.log}"
hyg_verdict(){
  [ -s "$HYGIENE_LOG" ] || { echo nolog; return; }
  tail -c "${HYGIENE_LOG_TAIL_BYTES:-4000000}" "$HYGIENE_LOG" 2>/dev/null | awk -v n="$1" -v f="${2:-}" '
    /^\[branch-hygiene [^]]*\] === / { cur = (index($0, "=== " n " (") > 0); if (cur) saw = 1; sf = ""; next }
    cur && /\] +feature branch: / { sf = $NF; next }
    cur && (f == "" || sf == f) && /NOT merging|MERGE CONFLICT|FLAG-ONLY/ { v = "stuck" }
    cur && (f == "" || sf == f) && (/ MERGED / || / already in /) { v = "merged" }
    END { print (!saw ? "nolog" : (v ? v : "unknown")) }'
}
# N7: a hygiene gate stuck >= OVN_ESC_HYGIENE_H (4) h is escalated ONCE per day as an emergency-class push through ovn_notify.py escalate (flag OVN_ESC_HYGIENE: shadow (default) | on | off).
ESC_SECS=$(( ${OVN_ESC_HYGIENE_H:-4} * 3600 ))
esc(){  # <signature> <title> <body>
  OVN_NOTIFY_STATE="$PWD/$STATE_DIR" ${OVN_ESCALATE_CMD:-python3 scripts/ovn_notify.py escalate} --sig "$1" --title "$2" --body "$3" --flag OVN_ESC_HYGIENE >>"${OVN_ESC_LOG:-/dev/null}" 2>&1 || true
}

process_stuck(){  # <repo> <reason>: age the stuck state, alert once past STUCK_HOURS, remind every REMIND_HOURS, escalate once/day past OVN_ESC_HYGIENE_H
  local name="$1" reason="$2" since_marker alerted_marker since elapsed elapsed_h last_alert
  since_marker="$STATE_DIR/hygiene_stuck_since_$name"
  alerted_marker="$STATE_DIR/hygiene_stuck_alerted_$name"

  if [ ! -f "$since_marker" ]; then
    echo "$now" > "$since_marker"
    log "$name: newly stuck ($reason)"
    return 0
  fi

  since="$(cat "$since_marker" 2>/dev/null || echo "$now")"
  elapsed=$(( now - since ))
  elapsed_h=$(( elapsed / 3600 ))

  if [ "$elapsed" -ge "$STUCK_SECS" ]; then
    last_alert="$(cat "$alerted_marker" 2>/dev/null || echo 0)"
    if [ "$last_alert" -eq 0 ]; then
      alert "Branch hygiene STUCK: $name" "rotating_light" \
        "$name has not merged to develop/main in ~${elapsed_h}h. Reason: $reason. This blocks EVERY fleet item for $name from ever landing until fixed — worth a look now, not at the next digest." "high"
      echo "$now" > "$alerted_marker"
      log "$name: stuck ${elapsed_h}h — ALERTED (first)"
    elif [ $(( now - last_alert )) -ge "$REMIND_SECS" ]; then
      alert "Branch hygiene STILL STUCK: $name" "rotating_light" \
        "$name has not merged in ~${elapsed_h}h (unresolved since the first alert). Reason: $reason." "high"
      echo "$now" > "$alerted_marker"
      log "$name: stuck ${elapsed_h}h — ALERTED (reminder)"
    else
      log "$name: stuck ${elapsed_h}h — within cooldown, no alert"
    fi
    if [ "$elapsed" -ge "$ESC_SECS" ]; then
      esc "hygiene_stuck:$name" "Branch hygiene STUCK ${elapsed_h}h: $name" "$name has not merged in ~${elapsed_h}h and nothing from it reaches develop. Reason: $reason."
      log "$name: stuck ${elapsed_h}h >= ${OVN_ESC_HYGIENE_H:-4}h — escalation requested (OVN_ESC_HYGIENE, once per day)"
    fi
  else
    log "$name: stuck ${elapsed_h}h — below ${STUCK_HOURS}h threshold, no alert yet"
  fi
}

for flag in "$STATE_DIR"/branch_hygiene_review_*; do
  [ -f "$flag" ] || continue
  name="${flag#"$STATE_DIR"/branch_hygiene_review_}"
  seen_repos="$seen_repos $name"
  reason="$(cat "$flag" 2>/dev/null)"
  # remember WHICH feature branch is red (the flag text is '<reason>: <branch> +N <date>'); a flag-only note ('<branch> is N commits ahead') names it first
  feat="$(printf '%s' "$reason" | sed -nE 's/^[^:]*: ([A-Za-z0-9_.\/-]+) \+[0-9]+.*/\1/p; s/^([A-Za-z0-9_.\/-]+) is [0-9]+ commits ahead.*/\1/p' | head -1)"
  [ -n "$feat" ] && echo "$feat" > "$STATE_DIR/hygiene_stuck_feat_$name"
  process_stuck "$name" "$reason"
done

# recovery: a repo with a since-marker but NO current review flag recovered ONLY if its last hygiene result says so (F4); a red last result is still stuck
for since_marker in "$STATE_DIR"/hygiene_stuck_since_*; do
  [ -f "$since_marker" ] || continue
  name="${since_marker#"$STATE_DIR"/hygiene_stuck_since_}"
  case " $seen_repos " in
    *" $name "*) continue;;  # still stuck, handled above
  esac
  verdict="$(hyg_verdict "$name" "$(cat "$STATE_DIR/hygiene_stuck_feat_$name" 2>/dev/null)")"
  case "$verdict" in
    stuck)
      seen_repos="$seen_repos $name"
      process_stuck "$name" "last hygiene result in branch_hygiene.log is not a merge (the review flag was cleared by another branch pass, not by a merge)"
      continue;;
    unknown)
      log "$name: review flag gone but the last hygiene result is neither a merge nor a failure (infra skip?) — recovery UNCONFIRMED, keeping the stuck state"
      continue;;
  esac
  since="$(cat "$since_marker" 2>/dev/null || echo "$now")"
  elapsed_h=$(( (now - since) / 3600 ))
  alerted_marker="$STATE_DIR/hygiene_stuck_alerted_$name"
  if [ -f "$alerted_marker" ]; then
    alert "Branch hygiene recovered: $name" "white_check_mark" \
      "$name merged successfully after being stuck ~${elapsed_h}h." "low"
    log "$name: recovered after ${elapsed_h}h — sent recovery note (last hygiene result: $verdict)"
  else
    log "$name: recovered after ${elapsed_h}h (never crossed the alert threshold, no note needed)"
  fi
  rm -f "$since_marker" "$alerted_marker" "$STATE_DIR/hygiene_stuck_feat_$name"
done

# --- QA-blocked repos (2026-10-02) -----------------------------------------------------------------------------------------------------
# A gate in enforce mode that blocks the FIRST pending commit of a feature branch leaves hygiene exiting 0 with no review flag (by design: no
# failure, no lock held), so the loops above never see it and the repo could starve for days behind one alert line in alerts.log. Each
# state/qa_blocked/<repo>__<branch>.json carries a "since" that only resets when the (gate, offender) changes, so age it the same way as a stuck
# flag: one alert past STUCK_HOURS, a reminder every REMIND_HOURS, a recovery note when the record is gone. Read-only on the records.
qa_seen=""
command -v jq >/dev/null 2>&1 || log "QA-blocked check: jq missing - UNVERIFIED (cannot age state/qa_blocked records)"
for rec in "$STATE_DIR"/qa_blocked/*.json; do
  [ -f "$rec" ] || continue
  key="$(basename "$rec" .json)"
  qa_seen="$qa_seen $key"
  since="$(jq -r '.since // empty | fromdateiso8601' "$rec" 2>/dev/null)"
  case "$since" in ''|*[!0-9]*) since="$now";; esac   # unreadable record: treat as just-seen, never alert on a guess
  elapsed=$(( now - since )); elapsed_h=$(( elapsed / 3600 ))
  detail="$(jq -r '"gate=\(.gate // "?") commit=\((.commit // "") | .[0:12]) held=\(.held_commits // "?"): \((.finding // "") | .[0:160])"' "$rec" 2>/dev/null)"
  qa_marker="$STATE_DIR/qa_stuck_alerted_$key"
  if [ "$elapsed" -ge "$STUCK_SECS" ]; then
    last_alert="$(cat "$qa_marker" 2>/dev/null || echo 0)"
    if [ "$last_alert" -eq 0 ]; then
      alert "QA-blocked: $key" "no_entry" "$key has had QA-enforced commits held for ~${elapsed_h}h and nothing from them is reaching develop. $detail. Unblock: qa/qa_enforce.sh unblock, or roll the gate back with qa/qa_enforce.sh <gate> shadow." "high"
      echo "$now" > "$qa_marker"; log "$key: QA-blocked ${elapsed_h}h - ALERTED (first)"
    elif [ $(( now - last_alert )) -ge "$REMIND_SECS" ]; then
      alert "QA-blocked still: $key" "no_entry" "$key still QA-blocked after ~${elapsed_h}h. $detail." "high"
      echo "$now" > "$qa_marker"; log "$key: QA-blocked ${elapsed_h}h - ALERTED (reminder)"
    else
      log "$key: QA-blocked ${elapsed_h}h - within cooldown, no alert"
    fi
  else
    log "$key: QA-blocked ${elapsed_h}h - below ${STUCK_HOURS}h threshold, no alert yet"
  fi
done
for qa_marker in "$STATE_DIR"/qa_stuck_alerted_*; do
  [ -f "$qa_marker" ] || continue
  key="${qa_marker#"$STATE_DIR"/qa_stuck_alerted_}"
  case " $qa_seen " in *" $key "*) continue;; esac
  alert "QA-block cleared: $key" "white_check_mark" "$key is no longer QA-blocked." "low"
  log "$key: QA block cleared - sent recovery note"
  rm -f "$qa_marker"
done

# --- identical failing-test streak (2026-11-01, package K3 item 4) ------------------------------------------------------------------------------
# Three consecutive hygiene failures on the SAME failing test set = a deterministic break (gitlark: one workspace-conversation status test, pass after pass). The python helper
# parses logs/hygiene_gate/ and, once per signature, prints 'ALERT<TAB>repo<TAB>title<TAB>body' (mode OVN_HYG_SIGSTREAK=on) that is sent here as an URGENT = emergency-class relay
# alert naming the tests and the commits that last touched them; the default mode (shadow) only logs (state/hygiene_sigstreak_shadow.log + one alerts.log info line).
# OVN_HYG_SIGSTREAK=off disables. A missing helper / python3 is a log line, never a failure.
if [ "${OVN_HYG_SIGSTREAK:-shadow}" != off ]; then
  if [ -f scripts/ovn_hygiene_sigstreak.py ] && command -v python3 >/dev/null 2>&1; then
    while IFS=$'\t' read -r _tag _repo _title _body; do
      [ "$_tag" = ALERT ] || continue
      alert "$_title" "rotating_light,no_entry" "$_body" "urgent"
      log "$_repo: identical failing-test streak - EMERGENCY alert sent"
    done < <(OVN_DIR="$PWD" OVN_STATE_DIR="$STATE_DIR" python3 scripts/ovn_hygiene_sigstreak.py 2>>"${OVN_HYG_SIGSTREAK_ERR:-/dev/null}")
  else
    log "identical-failing-test check skipped: scripts/ovn_hygiene_sigstreak.py or python3 missing"
  fi
fi

log "hygiene-stuck check complete"
