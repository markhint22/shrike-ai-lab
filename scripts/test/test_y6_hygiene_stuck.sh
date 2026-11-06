#!/usr/bin/env bash
# Y6/3 (2026-11-04): ovn_hygiene_stuck_check.sh measures a stuck gate from the LAST SUCCESSFUL MERGE (not from the first check after the red), names the repo, the branch and the first
# failing test names (or the MERGE CONFLICT files), escalates once per ROLLING 24 h per repo (--rolling-h, not calendar day) and sends exactly ONE low-priority recovery notice.
# Real incident: billwatch merged 09:02, first red gate 11:41, the marker started at 12:05 ('stuck 4h' = ~7h real), the alert never named test_llm_budget::... and the once-per-day key rolled at midnight.
# Mutants: each breaks one piece in a copy of the script and the scenario must then FAIL.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
H="${OVN_HYGIENE_STUCK_CHECK:-$HERE/../../ovn_hygiene_stuck_check.sh}"
[ -f "$H" ] || H="$HOME/overnight-queue/ovn_hygiene_stuck_check.sh"
[ -f "$H" ] || { echo "  SKIP: ovn_hygiene_stuck_check.sh not found on this host"; exit 77; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
FAILS=0; PASS=0
ts_of(){ date -u -d "@$1" '+%F %H:%M:%S' 2>/dev/null || date -u -r "$1" '+%F %H:%M:%S'; }
fts(){ date -u -d "@$1" '+%Y%m%d-%H%M%S' 2>/dev/null || date -u -r "$1" '+%Y%m%d-%H%M%S'; }
hdr(){ printf '[branch-hygiene %s] === %s (/x/%s) ===\n[branch-hygiene %s]   feature branch: %s\n' "$1" "$2" "$2" "$1" "${3:-overnight/feature}"; }

scenario(){  # $1 = script path -> prints failed checks; returns their number
  local script="$1" tmp="$T/case_${RANDOM}_$$" wd f=0 alerts esc now st lm; wd="$tmp/overnight-queue"; now=$(date +%s)
  mkdir -p "$wd/state" "$wd/logs/hygiene_gate" "$tmp/bin"; cp "$script" "$wd/ovn_hygiene_stuck_check.sh"
  alerts="$tmp/alerts.log"; esc="$tmp/esc.log"; : > "$alerts"; : > "$esc"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do echo "$a" >> "%s"; done\nexit 0\n' "$alerts" > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
  printf '#!/usr/bin/env bash\necho "ESC $*" >> "%s"\nexit 0\n' "$esc" > "$tmp/esc_stub.sh"; chmod +x "$tmp/esc_stub.sh"
  run(){ ( cd "$wd" && HOME="$tmp" PATH="$tmp/bin:$PATH" OVN_ESCALATE_CMD="$tmp/esc_stub.sh" bash ovn_hygiene_stuck_check.sh >"$tmp/run.out" 2>&1 ); }
  chk(){ if ! eval "$2" >/dev/null 2>&1; then f=$((f+1)); echo "    check failed: $1"; fi; }
  st="$wd/state"
  # billwatch: last MERGED 7h ago, first red gate 4.5h ago, nothing checked since -> there is NO since-marker yet
  lm=$((now - 7*3600))
  { hdr "$(ts_of $((lm - 60)))" billwatch; echo "[branch-hygiene $(ts_of "$lm")]   MERGED billwatch overnight/feature (+3) -> develop (reconcile will bring develop back into overnight/feature)"
    hdr "$(ts_of $((now - 16200)))" billwatch; echo "[branch-hygiene $(ts_of $((now - 16200)))]   gate FAILED for billwatch - NOT merging, flagged for review"; } > "$wd/logs/branch_hygiene.log"
  echo "gate FAILED (build/tests red): overnight/feature +109 2026-11-03" > "$st/branch_hygiene_review_billwatch"
  # an OLDER gate file with other names, then the newest one with the real failures (+ the harness fixtures, which must never be named)
  printf 'FAILED tests/test_old.py::test_old - boom\n' > "$wd/logs/hygiene_gate/$(fts $((now - 17000))).billwatch.pytest.aaaaaa"
  printf '\033[31mFAILED\033[0m x\nFAILED tests/test_llm_budget.py::test_remaining - assert 1\nFAILED tests/test_summary_scheduler.py::test_a\nERROR tests/test_summary_scheduler.py::test_b - boom\nFAILED tests/test_summary_scheduler.py::test_c\nFAILED scripts/test/test_fail.sh::fixture\n' > "$wd/logs/hygiene_gate/$(fts $((now - 16000))).billwatch.pytest.bbbbbb"
  run
  chk "first sighting of an OLD failure: the marker is anchored at the LAST MERGE, not at 'now'" "[ \"\$(cat '$st/hygiene_stuck_since_billwatch')\" = '$lm' ]"
  chk "DEBOUNCE: a first red after an old merge sends NO alert and NO escalation on that run" "! grep -q 'STUCK' '$alerts' && [ ! -s '$esc' ]"
  run
  chk "... the second consecutive red check alerts (7h since the merge, past the 2h threshold)" "[ \$(grep -c 'Branch hygiene STUCK: billwatch' '$alerts') -eq 1 ]"
  chk "alert names the BRANCH" "grep -q 'billwatch (overnight/feature)' '$alerts'"
  chk "alert names the first failing tests from the NEWEST gate file" "grep -q 'tests/test_llm_budget.py::test_remaining, tests/test_summary_scheduler.py::test_a, tests/test_summary_scheduler.py::test_b (+1 more)' '$alerts'"
  chk "alert does not name an older gate file's tests or a harness fixture" "! grep -q 'test_old' '$alerts' && ! grep -q 'test_fail.sh' '$alerts'"
  chk "alert states the hours from the last merge (~7h), not from the first check" "grep -q '~7h' '$alerts'"
  chk "escalation asked once, stable per-repo signature, branch in the title" "[ \$(grep -c '^ESC ' '$esc') -eq 1 ] && grep -q -- '--sig hygiene_stuck:billwatch' '$esc' && grep -q 'STUCK: billwatch overnight/feature' '$esc'"
  chk "escalation carries a ROLLING 24h key (--rolling-h 24), not the calendar day" "grep -q -- '--rolling-h 24' '$esc'"
  chk "escalation body names the failing tests" "grep -q 'test_llm_budget.py::test_remaining' '$esc'"
  # an existing marker that started LATE (the live 12:05 one) is re-anchored backwards to the real last merge
  echo $((now - 2*3600)) > "$st/hygiene_stuck_since_billwatch"; : > "$esc"; : > "$alerts"; run
  chk "a late marker is re-anchored to the last merge" "[ \"\$(cat '$st/hygiene_stuck_since_billwatch')\" = '$lm' ]"
  # failing names: ONLY the current red streak. A gate file OLDER than the last MERGED line is a previous, different failure -> 'cause unknown'; a newest file without ids does not
  # fall back to an older file's ids
  lm=$((now - 3*3600))
  { hdr "$(ts_of $((lm - 60)))" iptv_apps; echo "[branch-hygiene $(ts_of "$lm")]   MERGED iptv_apps overnight/feature (+2) -> develop (x)"
    hdr "$(ts_of $((now - 3000)))" iptv_apps; echo "[branch-hygiene $(ts_of $((now - 3000)))]   gate FAILED for iptv_apps - NOT merging, flagged for review"; } >> "$wd/logs/branch_hygiene.log"
  echo "gate FAILED (build/tests red): overnight/feature +5 2026-11-03" > "$st/branch_hygiene_review_iptv_apps"
  printf 'FAILED tests/test_was_red_before_merge.py::test_x - boom\n' > "$wd/logs/hygiene_gate/$(fts $((now - 5*3600))).iptv_apps.pytest.cccccc"
  printf 'FAILED tests/test_older_same_streak.py::test_y - boom\n' > "$wd/logs/hygiene_gate/$(fts $((now - 2800))).iptv_apps.pytest.dddddd"
  printf 'BUILD FAILED: compile error, no test ids here\n' > "$wd/logs/hygiene_gate/$(fts $((now - 2000))).iptv_apps.gradle.eeeeee"
  : > "$alerts"; : > "$esc"; run
  chk "DEBOUNCE: first red, last merge 3h ago: silent" "[ ! -s '$alerts' ]"
  run
  chk "an older gate file of the same streak is NOT used when the newest names nothing (cause unknown)" "grep -q 'Cause unknown (see logs/hygiene_gate)' '$alerts' && ! grep -q 'test_older_same_streak\|test_was_red_before_merge' '$alerts'"
  rm -f "$wd/logs/hygiene_gate/"*.iptv_apps.gradle.* "$wd/logs/hygiene_gate/"*.iptv_apps.pytest.dddddd; 
  : > "$alerts"; echo $((now - 7*3600)) > "$st/hygiene_stuck_alerted_iptv_apps"; run
  chk "a gate file from BEFORE the last merge is another failure: not named" "! grep -q 'test_was_red_before_merge' '$alerts' && grep -q 'Cause unknown' '$alerts'"
  # time-based debounce: a single check sighting but the red is >= 1h old (first-red marker) alerts without a second pass
  echo "gate FAILED: overnight/feature +1" > "$st/branch_hygiene_review_xl2"
  { hdr "$(ts_of $((now - 20000)))" xl2; echo "[branch-hygiene $(ts_of $((now - 20000)))]   MERGED xl2 overnight/feature (+1) -> develop (x)"; } >> "$wd/logs/branch_hygiene.log"
  : > "$alerts"; run
  chk "xl2: first red, silent" "! grep -q 'STUCK: xl2' '$alerts'"
  echo $((now - 4000)) > "$st/hygiene_red_first_xl2"; echo 0 > "$st/hygiene_red_n_xl2"; run
  chk "xl2: red for >= 1h since the first red alerts even with few passes" "grep -q 'STUCK: xl2' '$alerts'"
  # MERGE CONFLICT names the conflicted files
  echo "MERGE CONFLICT: overnight/feature +4 vs develop Tue" > "$st/branch_hygiene_review_gitlark"
  { hdr "$(ts_of $((now - 30000)))" gitlark; echo "[branch-hygiene $(ts_of $((now - 3600)))]   MERGE CONFLICT for gitlark - aborted, flagged (conflicted: app/models.py docs/API.md)"; } >> "$wd/logs/branch_hygiene.log"
  : > "$esc"; : > "$alerts"; run; run
  chk "no merge ever in the log -> falls back to now (no alert on first sight)" "[ ! -s '$alerts' ] || ! grep -q 'STUCK: gitlark' '$alerts'"
  echo $((now - 5*3600)) > "$st/hygiene_stuck_since_gitlark"; echo $((now - 5*3600)) > "$st/hygiene_red_first_gitlark"; run
  chk "MERGE CONFLICT alert names the conflicted FILES" "grep -q 'MERGE CONFLICT in: app/models.py docs/API.md' '$alerts'"
  # recovery: a real MERGED line; exactly ONE low-priority notice naming repo+branch, markers cleared, and a rerun stays silent
  rm -f "$st/branch_hygiene_review_billwatch"
  { hdr "$(ts_of $((now - 600)))" billwatch; echo "[branch-hygiene $(ts_of $((now - 590)))]   MERGED billwatch overnight/feature (+109) -> develop (x)"; } >> "$wd/logs/branch_hygiene.log"
  : > "$alerts"; run; run
  chk "ONE recovery notice" "[ \$(grep -c 'Branch hygiene recovered: billwatch' '$alerts') -eq 1 ]"
  chk "recovery is priority low and names the branch" "grep -qx 'Priority: low' '$alerts' && grep -q 'billwatch (overnight/feature) merged successfully' '$alerts'"
  chk "recovery clears every marker (incl. the escalation one)" "[ ! -f '$st/hygiene_stuck_since_billwatch' ] && [ ! -f '$st/hygiene_stuck_alerted_billwatch' ] && [ ! -f '$st/hygiene_stuck_esc_billwatch' ]"
  # recovery is also sent when the repo was ONLY escalated (alert marker lost)
  echo "gate FAILED: z" > "$st/branch_hygiene_review_xlite"; echo $((now - 5*3600)) > "$st/hygiene_stuck_since_xlite"; echo "$now" > "$st/hygiene_stuck_esc_xlite"
  rm -f "$st/branch_hygiene_review_xlite"
  { hdr "$(ts_of $((now - 300)))" xlite; echo "[branch-hygiene $(ts_of $((now - 290)))]   MERGED xlite overnight/feature (+1) -> develop (x)"; } >> "$wd/logs/branch_hygiene.log"
  : > "$alerts"; run
  chk "an escalated-only repo still gets its recovery notice" "[ \$(grep -c 'Branch hygiene recovered: xlite' '$alerts') -eq 1 ]"
  return $f
}
runcase(){ # $1 label, $2 script, $3 expect: pass|fail
  local out rc; out="$(scenario "$2")"; rc=$?
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
mutate "stuck time measured from the first check, not the last merge (no last-merge lookup)" '  lm="$(last_merge_epoch "$name" "$feat")"' '  lm=""'
mutate "an existing late marker is not re-anchored" '  if [ -n "$lm" ] && [ "$lm" -lt "$since" ]; then since="$lm"; echo "$since" > "$since_marker"; fi' '  :'
mutate "no debounce: a first red after an old merge alerts at once" '  if [ "$rn" -lt "${OVN_HYG_RED_PASSES:-2}" ] && [ $(( now - rf )) -lt "${OVN_HYG_RED_SECS:-3600}" ]; then' '  if false; then'
mutate "debounce never ends (the 1h-since-first-red leg is gone)" '&& [ $(( now - rf )) -lt "${OVN_HYG_RED_SECS:-3600}" ]; then' '&& true; then'
mutate "debounce never ends (the 2-pass leg is gone)" '  if [ "$rn" -lt "${OVN_HYG_RED_PASSES:-2}" ] &&' '  if true &&'
mutate "older gate files are walked again" "sort -r | head -1" "sort -r | head -4"
mutate "gate file from before the last merge is still named" 'if [ -z "$gep" ] || [ -z "$lm" ] || [ "$gep" -gt "$lm" ]; then ids=' 'if true; then ids='
mutate "no 'cause unknown' wording" "printf 'Cause unknown (see logs/hygiene_gate).'" ":"
mutate "failing tests not named" '  detail="$(stuck_detail "$name" "$reason" "$feat")"' '  detail=""'
mutate "branch not named" '  branch_txt="${feat:+ ($feat)}"' '  branch_txt=""'
mutate "newest gate file ignored (oldest first)" 'sort -r | head -1' 'sort | head -1'
mutate "harness fixture tests are named" 'grep -avE "$FIXTURE_RE"' 'cat'
mutate "calendar-day escalation key (no --rolling-h)" ' --rolling-h "${OVN_ESC_HYGIENE_ROLL_H:-24}"' ''
mutate "conflict files not named" 'sed -nE '"'"'s/.*\(conflicted: ([^)]*)\).*/\1/p'"'" 'sed -nE '"'"'s/NEVER//p'"'"
mutate "recovery not low priority" '"$name${_rfeat:+ ($_rfeat)} merged successfully after being stuck ~${elapsed_h}h (since $(fmt_ts "$since"))." "low"' '"$name${_rfeat:+ ($_rfeat)} merged successfully after being stuck ~${elapsed_h}h (since $(fmt_ts "$since"))." "high"'
mutate "escalation marker not cleared / escalated-only recovery missing" 'if [ -f "$alerted_marker" ] || [ -f "$STATE_DIR/hygiene_stuck_esc_$name" ]; then' 'if [ -f "$alerted_marker" ]; then'
echo "  y6 hygiene stuck: $PASS passed, $FAILS failed"
[ "$FAILS" = 0 ]
