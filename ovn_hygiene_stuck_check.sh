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
# Z4 2026-11-07: the claude/feature lane logs to a SEPARATE file (logs/branch_hygiene_claude.log, "<branch> already in develop - nothing to land"); this check only read branch_hygiene.log, whose
# last section for the repo is the overnight/feature lane -> a stuck claude/feature flag could never be confirmed recovered ("recovery UNCONFIRMED" every hour, xlite 11-06 12:05 -> 11-07).
# When the main log has no conclusive result for the stuck branch, the claude-lane log is consulted too.
HYGIENE_LOG_CLAUDE="${HYGIENE_LOG_CLAUDE:-$(dirname "$HYGIENE_LOG")/branch_hygiene_claude.log}"
hyg_verdict(){
  local v; v="$(hyg_verdict_in "$HYGIENE_LOG" "$@")"
  if { [ "$v" = unknown ] || [ "$v" = nolog ]; } && [ -n "${2:-}" ]; then   # only for a NAMED branch: with no branch the claude lane's lines would match anything (F4 bogus-recovery class)
    local v2; v2="$(hyg_verdict_in "$HYGIENE_LOG_CLAUDE" "$@")"
    case "$v2" in merged|stuck) v="$v2";; esac
  fi
  echo "$v"
}
hyg_verdict_in(){ # <logfile> <repo> [feature-branch]
  local lg="$1"; shift
  [ -s "$lg" ] || { echo nolog; return; }
  tail -c "${HYGIENE_LOG_TAIL_BYTES:-4000000}" "$lg" 2>/dev/null | awk -v n="$1" -v f="${2:-}" '
    /^\[branch-hygiene [^]]*\] === / { cur = (index($0, "=== " n " (") > 0); if (cur) saw = 1; sf = ""; next }
    cur && /\] +feature branch: / { sf = $NF; next }
    cur && (f == "" || sf == f) && /NOT merging|MERGE CONFLICT|FLAG-ONLY/ { v = "stuck" }
    cur && (f == "" || sf == f) && (/ MERGED / || / already in /) { v = "merged" }
    END { print (!saw ? "nolog" : (v ? v : "unknown")) }'
}
# --- 2026-11-04 (Y6/3): measure from the LAST SUCCESSFUL MERGE, and name what is failing ------------------------------------------------------------------------------
# billwatch: last merge to develop 09:02, first red gate 11:41, the stuck marker only started at the first CHECK after the red (12:05), so '4h' was ~7h real; and the alert never said
# which tests failed. to_epoch/last_merge_epoch read the repo's last MERGED line for the stuck feature branch (same '=== repo (' section scheme as hyg_verdict); stuck_detail names
# the first failing test ids (logs/hygiene_gate/<ts>.<repo>.<kind>.<rand>, else the failing ids in the repo's last log section) or the MERGE CONFLICT files.
to_epoch(){ date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%d %H:%M:%S' "$1" +%s 2>/dev/null || true; }
last_merge_epoch(){  # <repo> [feature-branch] -> epoch of the last MERGED line (empty when none / unreadable)
  [ -s "$HYGIENE_LOG" ] || return 0
  local ts
  ts="$(tail -c "${HYGIENE_LOG_TAIL_BYTES:-4000000}" "$HYGIENE_LOG" 2>/dev/null | awk -v n="$1" -v f="${2:-}" '
    /^\[branch-hygiene [^]]*\] === / { cur = (index($0, "=== " n " (") > 0); sf = ""; next }
    cur && /\] +feature branch: / { sf = $NF; next }
    cur && (f == "" || sf == f) && /^\[branch-hygiene [^]]*\] +MERGED / { t = substr($0, 17, 19) }
    END { if (t != "") print t }')"
  [ -n "$ts" ] && to_epoch "$ts"
  return 0
}
FIXTURE_RE='(^|/)(test_fake_a|test_fail|test_does_not_exist)\.sh'
ids_from(){  # stdin: gate/log text -> failing test ids, one per line, first-seen order, fixtures dropped
  sed "s/$(printf '\033')\[[0-9;]*m//g" | grep -aE '^(FAILED|ERROR) [^ ]+::|^--- GUT-FAIL-ID: |^[^ ]+ > .* FAILED[[:space:]]*$' \
    | sed -E 's/^(FAILED|ERROR) //; s/^--- GUT-FAIL-ID: //; s/ - .*$//; s/[[:space:]]+FAILED[[:space:]]*$//' | grep -avE "$FIXTURE_RE" | awk '!s[$0]++'
}
failing_names(){  # <repo> [feature-branch] -> 'a, b, c (+N more)' (first 3), empty when the CURRENT red streak names nothing
  # Y6 fix: ONLY the gate output of the current red streak is read: the NEWEST gate file for the repo, and only when it is newer than the last MERGED line (an older file is an
  # earlier, different failure). The log fallback reads the last log section of the stuck feature branch. Never walks back through older gate files.
  local repo="$1" feat="${2:-}" dir="${OVN_HYGIENE_GATE_DIR:-logs/hygiene_gate}" f gts gep lm ids="" n
  if [ -d "$dir" ]; then
    f="$(ls -1 "$dir" 2>/dev/null | grep -E "^[0-9]{8}-[0-9]{6}\.${repo}\." | sort -r | head -1)"
    if [ -n "$f" ]; then
      gts="$(printf '%s' "$f" | sed -E 's/^([0-9]{4})([0-9]{2})([0-9]{2})-([0-9]{2})([0-9]{2})([0-9]{2}).*/\1-\2-\3 \4:\5:\6/')"
      gep="$(to_epoch "$gts")"; lm="$(last_merge_epoch "$repo" "$feat")"
      case "$gep" in ''|*[!0-9]*) gep="";; esac
      if [ -z "$gep" ] || [ -z "$lm" ] || [ "$gep" -gt "$lm" ]; then ids="$(ids_from < "$dir/$f")"; fi
    fi
  fi
  if [ -z "$ids" ] && [ -s "$HYGIENE_LOG" ]; then   # a short gate output is shown in the main log only: the failing ids of the stuck branch's LAST section for the repo
    ids="$(tail -c "${HYGIENE_LOG_TAIL_BYTES:-4000000}" "$HYGIENE_LOG" 2>/dev/null | awk -v n="$repo" -v f="$feat" '
      function flush() { if (cur && ok) keep = buf }
      /^\[branch-hygiene [^]]*\] === / { flush(); cur = (index($0, "=== " n " (") > 0); buf = ""; ok = (f == ""); next }
      cur && /\] +feature branch: / { if (f != "") ok = ($NF == f); next }
      cur { buf = buf $0 "\n" }
      END { flush(); printf "%s", keep }' | ids_from)"
  fi
  [ -n "$ids" ] || return 0
  n="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  printf '%s' "$(printf '%s\n' "$ids" | head -3 | paste -sd, - | sed 's/,/, /g')"
  [ "$n" -gt 3 ] && printf ' (+%s more)' "$((n - 3))"
  return 0
}
conflict_files(){  # <repo> -> files of the last 'MERGE CONFLICT for <repo> ... (conflicted: a b)' log line
  [ -s "$HYGIENE_LOG" ] || return 0
  tail -c "${HYGIENE_LOG_TAIL_BYTES:-4000000}" "$HYGIENE_LOG" 2>/dev/null | grep -a "MERGE CONFLICT for $1 " | tail -1 | sed -nE 's/.*\(conflicted: ([^)]*)\).*/\1/p'
  return 0
}
stuck_detail(){  # <repo> <reason> [feature-branch] -> one sentence naming the failing tests / conflicted files ('' when nothing is known)
  local cf nm
  case "$2" in
    "MERGE CONFLICT"*) cf="$(conflict_files "$1")"; [ -n "$cf" ] && { printf 'MERGE CONFLICT in: %s.' "$cf"; return 0; }; printf 'MERGE CONFLICT (conflicted files not in the log).'; return 0;;
  esac
  nm="$(failing_names "$1" "${3:-}")"
  if [ -n "$nm" ]; then printf 'First failing tests: %s.' "$nm"; else printf 'Cause unknown (see logs/hygiene_gate).'; fi
  return 0
}
fmt_ts(){ date -d "@$1" '+%F %H:%M' 2>/dev/null || date -r "$1" '+%F %H:%M' 2>/dev/null || echo "$1"; }
# N7: a hygiene gate stuck >= OVN_ESC_HYGIENE_H (4) h is escalated through ovn_notify.py escalate (flag OVN_ESC_HYGIENE: on (default) | shadow | off). Y6: ONCE per ROLLING 24 h per repo
# (--rolling-h OVN_ESC_HYGIENE_ROLL_H), not per calendar day (the 00:05 midnight roll re-armed it 8 h after the 4 h push).
ESC_SECS=$(( ${OVN_ESC_HYGIENE_H:-4} * 3600 ))
esc(){  # <signature> <title> <body>
  OVN_NOTIFY_STATE="$PWD/$STATE_DIR" ${OVN_ESCALATE_CMD:-python3 scripts/ovn_notify.py escalate} --sig "$1" --title "$2" --body "$3" --flag OVN_ESC_HYGIENE --rolling-h "${OVN_ESC_HYGIENE_ROLL_H:-24}" >>"${OVN_ESC_LOG:-/dev/null}" 2>&1 || true
}

process_stuck(){  # <repo> <reason>: age the stuck state (from the last merge), alert once past STUCK_HOURS, remind every REMIND_HOURS, escalate once per rolling 24 h past OVN_ESC_HYGIENE_H
  local name="$1" reason="$2" red_first red_n rn rf since_marker alerted_marker since elapsed elapsed_h last_alert feat lm detail since_txt branch_txt
  since_marker="$STATE_DIR/hygiene_stuck_since_$name"
  alerted_marker="$STATE_DIR/hygiene_stuck_alerted_$name"
  feat="$(cat "$STATE_DIR/hygiene_stuck_feat_$name" 2>/dev/null)"
  lm="$(last_merge_epoch "$name" "$feat")"
  case "$lm" in ''|*[!0-9]*) lm="";; esac
  [ -n "$lm" ] && [ "$lm" -gt "$now" ] && lm=""

  # Y6 fix: debounce. A red must be seen on >= OVN_HYG_RED_PASSES (2) consecutive checks OR persist >= OVN_HYG_RED_SECS (1h) since its first sighting before ANY alert/escalation,
  # however old the last merge is (a repo idle 10 h whose gate flaked red once 60 s ago is not 'stuck ~10h'). The since-marker still anchors the age text at the last merge.
  red_first="$STATE_DIR/hygiene_red_first_$name"; red_n="$STATE_DIR/hygiene_red_n_$name"
  if [ ! -f "$since_marker" ]; then
    echo "${lm:-$now}" > "$since_marker"
    log "$name: newly stuck ($reason)${lm:+ - last successful merge $(fmt_ts "$lm")}"
    echo "$now" > "$red_first"; echo 0 > "$red_n"
  elif [ ! -f "$red_n" ]; then   # a marker from before the debounce existed = an earlier check already saw the red
    echo "$now" > "$red_first"; echo 1 > "$red_n"
  fi
  rn="$(cat "$red_n" 2>/dev/null)"; case "$rn" in ''|*[!0-9]*) rn=0;; esac
  rn=$((rn + 1)); echo "$rn" > "$red_n"
  rf="$(cat "$red_first" 2>/dev/null)"; case "$rf" in ''|*[!0-9]*) rf="$now"; echo "$now" > "$red_first";; esac
  if [ "$rn" -lt "${OVN_HYG_RED_PASSES:-2}" ] && [ $(( now - rf )) -lt "${OVN_HYG_RED_SECS:-3600}" ]; then
    log "$name: red seen on $rn check(s), ${OVN_HYG_RED_SECS:-3600}s not elapsed since first red - debouncing, no alert yet"
    return 0
  fi

  since="$(cat "$since_marker" 2>/dev/null || echo "$now")"
  case "$since" in ''|*[!0-9]*) since="$now";; esac
  if [ -n "$lm" ] && [ "$lm" -lt "$since" ]; then since="$lm"; echo "$since" > "$since_marker"; fi   # re-anchor an existing marker to the real last merge
  elapsed=$(( now - since ))
  elapsed_h=$(( elapsed / 3600 ))
  detail="$(stuck_detail "$name" "$reason" "$feat")"
  branch_txt="${feat:+ ($feat)}"
  since_txt="$(fmt_ts "$since")"

  if [ "$elapsed" -ge "$STUCK_SECS" ]; then
    last_alert="$(cat "$alerted_marker" 2>/dev/null || echo 0)"
    if [ "$last_alert" -eq 0 ]; then
      alert "Branch hygiene STUCK: $name" "rotating_light" \
        "$name${branch_txt} has not merged to develop/main since $since_txt (~${elapsed_h}h). Reason: $reason. ${detail} This blocks EVERY fleet item for $name from ever landing until fixed - worth a look now, not at the next digest." "high"
      echo "$now" > "$alerted_marker"
      log "$name: stuck ${elapsed_h}h - ALERTED (first)"
    elif [ $(( now - last_alert )) -ge "$REMIND_SECS" ]; then
      alert "Branch hygiene STILL STUCK: $name" "rotating_light" \
        "$name${branch_txt} has not merged since $since_txt (~${elapsed_h}h, unresolved since the first alert). Reason: $reason. ${detail}" "high"
      echo "$now" > "$alerted_marker"
      log "$name: stuck ${elapsed_h}h - ALERTED (reminder)"
    else
      log "$name: stuck ${elapsed_h}h - within cooldown, no alert"
    fi
    if [ "$elapsed" -ge "$ESC_SECS" ]; then
      # stable title (no hour count: the relay's per-title cooldown keys on it); the repo, branch, age and failing tests/conflict files are in the title/body
      esc "hygiene_stuck:$name" "Branch hygiene STUCK: $name${feat:+ $feat}" "$name${branch_txt} has not merged since $since_txt (~${elapsed_h}h) and nothing from it reaches develop. ${detail:-Reason: $reason.}"
      echo "$now" > "$STATE_DIR/hygiene_stuck_esc_$name"
      log "$name: stuck ${elapsed_h}h >= ${OVN_ESC_HYGIENE_H:-4}h - escalation requested (OVN_ESC_HYGIENE, once per rolling ${OVN_ESC_HYGIENE_ROLL_H:-24}h)"
    fi
  else
    log "$name: stuck ${elapsed_h}h - below ${STUCK_HOURS}h threshold, no alert yet"
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
  _rfeat="$(cat "$STATE_DIR/hygiene_stuck_feat_$name" 2>/dev/null)"
  if [ -f "$alerted_marker" ] || [ -f "$STATE_DIR/hygiene_stuck_esc_$name" ]; then
    # Y6/3: ONE recovery notice (priority low), naming the repo + branch; the markers are removed right below so it cannot repeat
    alert "Branch hygiene recovered: $name" "white_check_mark" \
      "$name${_rfeat:+ ($_rfeat)} merged successfully after being stuck ~${elapsed_h}h (since $(fmt_ts "$since"))." "low"
    log "$name: recovered after ${elapsed_h}h — sent recovery note (last hygiene result: $verdict)"
  else
    log "$name: recovered after ${elapsed_h}h (never crossed the alert threshold, no note needed)"
  fi
  rm -f "$since_marker" "$alerted_marker" "$STATE_DIR/hygiene_red_first_$name" "$STATE_DIR/hygiene_red_n_$name" "$STATE_DIR/hygiene_stuck_feat_$name" "$STATE_DIR/hygiene_stuck_esc_$name"
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
