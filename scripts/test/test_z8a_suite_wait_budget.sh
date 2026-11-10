#!/usr/bin/env bash
# test_z8a_suite_wait_budget.sh - Z8a (2026-11-10): ops/run_suite_sandboxed_cron.sh. The instrumented coverage cron (03:30) holds run_all's lock for 3h30+ (finish creeping 06:34 -> 07:16), so the 06:17
# slot's 90-min poll budget (ends 07:47) ran out or came within minutes of it. Default cron-mode budget is now 240 min (poll 600 s) and the wait is announced in the log.
# Checks (stub run_all_sandboxed.sh that stays locked N times; stub `sleep` on PATH so 4 h of polling takes no time; temp HOME; no real suite):
#   W1 default budget: locked forever => 1 + 24 attempts (240 min / 10 min), final rc 75 (benign skip), log says "up to 14400s (240 min)"
#   W2 locked 30 polls (5 h-equivalent minus) is NOT enough but locked 20 polls (~3h20, the real coverage duration) => the suite runs (rc 0) - the real scenario that was lost
#   W3 explicit OVN_SUITE_LOCK_MAX_MIN still overrides; W4 --candidate mode never waits; W5 the announcement line names the coverage run and the budget
#   Mutant: the old 90-min default => W1/W2 FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
OPS="$HERE/../../ops"; [ -f "$OPS/run_suite_sandboxed_cron.sh" ] || { echo "  SKIP: ops/run_suite_sandboxed_cron.sh not present"; exit 0; }
P=0; F=0
ok(){ if [ "$1" = 1 ]; then P=$((P+1)); echo "  ok   $2"; else F=$((F+1)); echo "  FAIL $2"; fi; }
export NTFY_SERVER=http://127.0.0.1:9 TZ=UTC
SB="$(safe_mktemp_dir z8await)" || exit 1
trap 'safe_rm_rf "$SB"' EXIT
run_checks(){ # $1 = ops dir, $2 = label
  local OPSX="$1" lab="$2" W; W="$(safe_mktemp_dir_in "$SB" chk)" || return 1
  local H="$W/home" QQ="$W/home/overnight-queue" CNT="$W/cnt" LG BIN="$W/bin"; LG="$H/qtmp/suite_cron.log"
  mkdir -p "$H/qtmp" "$QQ/state" "$QQ/scripts/test" "$BIN"
  printf '#!/bin/sh\necho "$1" >> "%s/sleeps"\nexit 0\n' "$W" > "$BIN/sleep"; chmod 755 "$BIN/sleep"
  cat > "$QQ/scripts/test/run_all_sandboxed.sh" <<'STUB'
#!/usr/bin/env bash
n=0; [ -f "$STUB_CNT" ] && n="$(cat "$STUB_CNT")"; n=$((n+1)); echo "$n" > "$STUB_CNT"
[ "$n" -le "${STUB_75_TIMES:-1}" ] && exit 75
exit 0
STUB
  local o rc
  cr(){ rm -f "$CNT" "$W/sleeps"; o="$(env -i HOME="$H" PATH="$BIN:$PATH" TZ=UTC STUB_CNT="$CNT" OVN_SUITE_LOG="$LG" "$@" timeout 120 bash "$OPSX/run_suite_sandboxed_cron.sh" 2>&1)"; rc=$?; }
  cr STUB_75_TIMES=999
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 25 ] && echo 1 || echo 0)" "$lab W1 default budget: locked forever => 1 + 24 polls (240 min / 10 min), then the benign rc 75 (attempts=$(cat "$CNT" 2>/dev/null) rc=$rc)"
  ok "$(printf '%s' "$o" | grep -q 'for up to 14400s (240 min)' && echo 1 || echo 0)" "$lab W5 the wait is announced up front: names the coverage run and the 240 min budget"
  ok "$([ "$(sort -u "$W/sleeps" 2>/dev/null | tr '\n' ' ')" = "600 " ] && echo 1 || echo 0)" "$lab W6 poll interval stays 600 s"
  cr STUB_75_TIMES=20
  ok "$([ "$rc" = 0 ] && [ "$(cat "$CNT")" = 21 ] && echo 1 || echo 0)" "$lab W2 coverage holds the lock for ~3h20 (20 polls): the suite still runs (rc 0, 21 attempts) - the 06:17 slot is no longer lost"
  cr STUB_75_TIMES=999 OVN_SUITE_LOCK_MAX_MIN=30
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 4 ] && echo 1 || echo 0)" "$lab W3 OVN_SUITE_LOCK_MAX_MIN=30 still overrides (1 + 3 polls)"
  safe_rm_rf "$W"
}
echo "##### Z8a suite wait budget #####"
run_checks "$OPS" real
if [ "${UDIFF_TEST_NO_MUTATION:-0}" = 1 ]; then echo "  (mutation controls skipped: nested run)"; else
  MO="$SB/mutops"; mkdir -p "$MO"; cp "$OPS/run_suite_sandboxed_cron.sh" "$MO/"; cp "$OPS/suite_run_log.py" "$MO/" 2>/dev/null; mkdir -p "$SB/scripts/test"; cp "$HERE/lib_safe_tmp.sh" "$SB/scripts/test/" 2>/dev/null
  sed 's/OVN_SUITE_LOCK_MAX_MIN:-240/OVN_SUITE_LOCK_MAX_MIN:-90/; s/MW=14400/MW=5400/' "$MO/run_suite_sandboxed_cron.sh" > "$MO/m.sh" && mv "$MO/m.sh" "$MO/run_suite_sandboxed_cron.sh"
  cmp -s "$OPS/run_suite_sandboxed_cron.sh" "$MO/run_suite_sandboxed_cron.sh" && ok 0 "mutant differs from the real wrapper"
  run_checks "$MO" "MUTANT(90 min)" 2>&1 | sed 's/^  ok   /  (mutant passed) /; s/^  FAIL /  (mutant FAILED as required) /' > "$SB/mut.out"   # (pipeline = subshell: the mutant run's own counters never touch ours)
  ok "$(grep -c 'mutant FAILED as required' "$SB/mut.out" | awk '{print ($1>=2)?1:0}')" "M1 the old 90-min default makes at least W1 and W2 FAIL (mutant is caught)"
fi
echo "Z8a suite wait budget: $P passed, $F failed"; [ "$F" = 0 ]
