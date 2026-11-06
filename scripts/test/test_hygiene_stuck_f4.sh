#!/usr/bin/env bash
# F4 + N7 (2026-11-02): ovn_hygiene_stuck_check.sh
#  F4: 'recovered' comes from the repo's LAST hygiene result in logs/branch_hygiene.log (MERGED / 'already in'), never from the review flag merely disappearing (the claude/feature pass's
#      in-sync path deletes the flag a red overnight/feature gate wrote: iptv_apps got a bogus 'recovered after 8h' while the gate was still red, then 'newly stuck' again an hour later).
#      A red last result keeps the stuck state alerting (reminder every HYGIENE_STUCK_REMIND_HOURS).
#  N7: stuck >= OVN_ESC_HYGIENE_H (4) h requests ONE emergency-class escalation (ovn_notify.py escalate, flag OVN_ESC_HYGIENE, shadow by default).
# Mutants: each breaks one piece in a copy of the script and the scenario must then FAIL.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
H="${OVN_HYGIENE_STUCK_CHECK:-$HERE/../../ovn_hygiene_stuck_check.sh}"
[ -f "$H" ] || H="$HOME/overnight-queue/ovn_hygiene_stuck_check.sh"
[ -f "$H" ] || { echo "  SKIP: ovn_hygiene_stuck_check.sh not found on this host"; exit 77; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
FAILS=0; PASS=0
hdr(){ printf '[branch-hygiene 2026-11-02 %s] === %s (/x/%s) ===\n[branch-hygiene 2026-11-02 %s]   feature branch: %s\n' "$1" "$2" "$2" "$1" "${3:-overnight/feature}"; }

scenario(){  # $1 = script path, $2 = case dir name -> prints FAIL lines; returns number of failures
  local script="$1" tmp="$T/case_${RANDOM}_$$" wd f=0 alerts esc now; wd="$tmp/overnight-queue"; now=$(date +%s)
  mkdir -p "$wd/state" "$wd/logs" "$tmp/bin"; cp "$script" "$wd/ovn_hygiene_stuck_check.sh"
  alerts="$tmp/alerts.log"; esc="$tmp/esc.log"; : > "$alerts"; : > "$esc"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do echo "$a" >> "%s"; done\nexit 0\n' "$alerts" > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
  printf '#!/usr/bin/env bash\necho "ESC $*" >> "%s"\nexit 0\n' "$esc" > "$tmp/esc_stub.sh"; chmod +x "$tmp/esc_stub.sh"
  run(){ ( cd "$wd" && HOME="$tmp" PATH="$tmp/bin:$PATH" OVN_ESCALATE_CMD="$tmp/esc_stub.sh" bash ovn_hygiene_stuck_check.sh >"$tmp/run.out" 2>&1 ); }
  chk(){ if ! eval "$2" >/dev/null 2>&1; then f=$((f+1)); echo "    check failed: $1"; fi; }
  st="$wd/state"
  # --- stuck 5h with an alert already sent, flag present
  echo "gate FAILED (build/tests red): overnight/feature +5" > "$st/branch_hygiene_review_iptv_apps"
  echo $((now - 5*3600)) > "$st/hygiene_stuck_since_iptv_apps"; echo $((now - 3600)) > "$st/hygiene_stuck_alerted_iptv_apps"
  { hdr 14:04:45 iptv_apps; echo '  gate FAILED for iptv_apps — NOT merging, flagged for review'; } > "$wd/logs/branch_hygiene.log"
  run
  chk "N7: stuck 5h (>= 4h) requests exactly one escalation named for the repo, flag OVN_ESC_HYGIENE" "[ \$(grep -c '^ESC ' '$esc') -eq 1 ] && grep -q -- '--sig hygiene_stuck:iptv_apps' '$esc' && grep -q -- '--flag OVN_ESC_HYGIENE' '$esc'"
  # --- the other branch pass finds nothing to land: it deletes the flag. The last result of the repo is still red.
  : > "$alerts"; : > "$esc"
  rm -f "$st/branch_hygiene_review_iptv_apps"
  # the LIVE ordering (15:05:01 / 15:05:07): the red overnight/feature pass, then the claude/feature pass finds nothing to land and deletes the flag
  { hdr 15:05:01 iptv_apps; echo '  gate FAILED for iptv_apps — NOT merging, flagged for review'; hdr 15:05:07 iptv_apps claude/feature; echo '  claude/feature already in develop — nothing to land'; } >> "$wd/logs/branch_hygiene.log"
  run
  chk "F4: flag deleted by the in-sync claude/feature pass while overnight/feature is red -> NO 'recovered' note (the iptv_apps 15:05 bug)" "! grep -q 'Branch hygiene recovered' '$alerts'"
  chk "F4: ... the stuck markers are kept (no 'newly stuck' restart later)" "[ -f '$st/hygiene_stuck_since_iptv_apps' ] && [ -f '$st/hygiene_stuck_alerted_iptv_apps' ]"
  chk "F4: ... and it is still escalated (stuck state continues without the flag)" "[ \$(grep -c '^ESC ' '$esc') -eq 1 ]"
  echo $((now - 7*3600)) > "$st/hygiene_stuck_alerted_iptv_apps"; : > "$alerts"
  run
  chk "F4: ... and a reminder goes out once the reminder window has passed (re-alert while stuck)" "[ \$(grep -c 'Branch hygiene STILL STUCK: iptv_apps' '$alerts') -eq 1 ]"
  # --- only an infra skip since: unconfirmed
  : > "$alerts"
  { hdr 17:04:45 iptv_apps; echo '  gate-infra-skip: iptv_apps overnight/feature +5 - the gate failed on host storage exhaustion'; } > "$wd/logs/branch_hygiene.log"
  run
  chk "F4: only an infra-skip since -> recovery UNCONFIRMED: no note, markers kept" "! grep -q 'Branch hygiene recovered' '$alerts' && [ -f '$st/hygiene_stuck_since_iptv_apps' ]"
  # --- a real merge: recovered once
  { hdr 18:04:45 iptv_apps; echo '  MERGED iptv_apps overnight/feature (+5) -> develop (reconcile will bring develop back into overnight/feature)'; } >> "$wd/logs/branch_hygiene.log"
  : > "$alerts"; : > "$esc"
  run
  chk "F4: last result MERGED -> exactly one recovery note" "[ \$(grep -c 'Branch hygiene recovered: iptv_apps' '$alerts') -eq 1 ]"
  chk "F4: ... markers cleared, no escalation" "[ ! -f '$st/hygiene_stuck_since_iptv_apps' ] && [ ! -s '$esc' ]"
  # --- 'already in develop' as the last result also counts
  echo "gate FAILED: x" > "$st/branch_hygiene_review_billwatch"; echo $((now - 3*3600)) > "$st/hygiene_stuck_since_billwatch"; echo $((now - 3600)) > "$st/hygiene_stuck_alerted_billwatch"
  rm -f "$st/branch_hygiene_review_billwatch"
  { hdr 19:04:45 billwatch; echo '  overnight/feature already in develop — nothing to land'; } >> "$wd/logs/branch_hygiene.log"
  : > "$alerts"; run
  chk "F4: last result 'already in <target>' -> recovered" "[ \$(grep -c 'Branch hygiene recovered: billwatch' '$alerts') -eq 1 ]"
  # --- N7: a gate stuck 3h is alerted (>= 2h) but NOT escalated (< 4h)
  echo "gate FAILED: y" > "$st/branch_hygiene_review_gitlark"; echo $((now - 3*3600)) > "$st/hygiene_stuck_since_gitlark"
  : > "$esc"; run
  chk "N7: stuck 3h (< 4h) is not escalated" "! grep -q 'hygiene_stuck:gitlark' '$esc'"
  return $f
}
runcase(){ # $1 label, $2 script, $3 expect: pass|fail
  local out rc; out="$(scenario "$2" "$1")"; rc=$?
  if [ "$3" = pass ]; then
    if [ "$rc" = 0 ]; then PASS=$((PASS+1)); echo "  ok   $1: scenario passes"; else FAILS=$((FAILS+1)); echo "  FAIL $1: $rc scenario check(s) failed"; echo "$out"; fi
  else
    if [ "$rc" -gt 0 ]; then PASS=$((PASS+1)); echo "  ok   mutation caught: $1 ($rc check(s) fail)"; else FAILS=$((FAILS+1)); echo "  FAIL mutation NOT caught: $1"; fi
  fi
}
runcase real "$H" pass
mutate(){ # $1 label $2 old $3 new
  local m="$T/mut_$RANDOM.sh"
  OLD="$2" NEW="$3" python3 - "$H" "$m" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { FAILS=$((FAILS+1)); echo "  FAIL mutation '$1' could not be applied"; return; }
  runcase "$1" "$m" fail
}
mutate "recovery taken from the flag disappearing (old behaviour)" 'verdict="$(hyg_verdict "$name" "$(cat "$STATE_DIR/hygiene_stuck_feat_$name" 2>/dev/null)")"' 'verdict=nolog'
mutate "any pass's in-sync line vouches for the repo (feature branch ignored)" 'cur && (f == "" || sf == f) && (/ MERGED / || / already in /) { v = "merged" }' 'cur && (/ MERGED / || / already in /) { v = "merged" }'
mutate "red gate in the log not recognised" 'cur && (f == "" || sf == f) && /NOT merging|MERGE CONFLICT|FLAG-ONLY/ { v = "stuck" }' 'cur && /NEVER-MATCHES-XYZ/ { v = "stuck" }'
mutate "an infra skip counts as recovered" '      log "$name: review flag gone but the last hygiene result is neither a merge nor a failure (infra skip?) — recovery UNCONFIRMED, keeping the stuck state"
      continue;;' '      :;;'
mutate "no escalation at 4h" '    if [ "$elapsed" -ge "$ESC_SECS" ]; then' '    if false; then'
mutate "escalation fires from the first alert threshold (not 4h)" 'ESC_SECS=$(( ${OVN_ESC_HYGIENE_H:-4} * 3600 ))' 'ESC_SECS=0'
mutate "escalation uses the wrong flag" '--flag OVN_ESC_HYGIENE --rolling-h' '--flag OVN_ESC_OTHER --rolling-h'
echo "  hygiene stuck F4/N7: $PASS passed, $FAILS failed"
[ "$FAILS" = 0 ]
