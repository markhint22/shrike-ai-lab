#!/usr/bin/env bash
# test_z4_suite_cron_poll.sh - Z4 (2026-11-07): ops/run_suite_sandboxed_cron.sh default lock handling. The 06:17 suite slot was lost because the 03:30 coverage run held run_all's lock until 06:42
# and the single 20-min wait ended at 06:37. Default is now: poll every OVN_SUITE_LOCK_POLL_MIN (10) min up to OVN_SUITE_LOCK_MAX_MIN (90) min while run_all returns 75, cron mode only.
# P1 poll until the lock frees -> suite runs (rc 0); P2 bounded: never frees -> rc 75 after the budget; P3 MAX 0 = no waiting; P4 --candidate never polls; P5 explicit RETRY_SEC keeps the S1 single retry.
# Mutants: M1 only one poll; M2 unbounded loop; M3 candidate mode polls too.
# Deterministic: TZ pinned, ntfy dead port, temp dirs via lib_safe_tmp.sh, stub run_all_sandboxed.sh (no real suite).
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
OPS="$HERE/../../ops"
P=0; F=0
ok(){ if [ "$1" = 1 ]; then P=$((P+1)); echo "  ok   $2"; else F=$((F+1)); echo "  FAIL $2"; fi; }
export NTFY_SERVER=http://127.0.0.1:9 TZ=UTC
SB="$(safe_mktemp_dir z4poll)" || exit 1
. "$(cd "$(dirname "$0")" && pwd)/lib_mac_test_sandbox.sh" && mts_sandbox_init "$SB" || { echo "  FAIL: Z10 mac test sandbox"; exit 1; }   # Z10: real ssh/curl/ntfy delivery impossible from this test
trap 'safe_rm_rf "$SB"' EXIT
run_checks(){ # $1 = ops dir
  local OPSX="$1" W; W="$(safe_mktemp_dir_in "$SB" chk)" || return 1
  local H="$W/home" QQ="$W/home/overnight-queue" CNT="$W/cnt" LG; LG="$H/qtmp/suite_cron.log"
  mkdir -p "$H/qtmp" "$QQ/state" "$QQ/scripts/test"
  cat > "$QQ/scripts/test/run_all_sandboxed.sh" <<'STUB'
#!/usr/bin/env bash
n=0; [ -f "$STUB_CNT" ] && n="$(cat "$STUB_CNT")"; n=$((n+1)); echo "$n" > "$STUB_CNT"
echo "stub attempt $n"
[ "$n" -le "${STUB_75_TIMES:-1}" ] && exit 75
exit 0
STUB
  local o rc
  cr(){ rm -f "$CNT"; o="$(env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" OVN_SUITE_LOG="$LG" "$@" timeout 60 bash "$OPSX/run_suite_sandboxed_cron.sh" 2>&1)"; rc=$?; }
  cr STUB_75_TIMES=3 OVN_SUITE_LOCK_POLL_SEC=1 OVN_SUITE_LOCK_MAX_SEC=10
  ok "$([ "$rc" = 0 ] && [ "$(cat "$CNT")" = 4 ] && printf '%s' "$o" | grep -q 'polling again in 1s' && echo 1 || echo 0)" "P1 locked 3 times then free: polled until it freed, suite ran, rc 0 (4 attempts), waits logged"
  cr STUB_75_TIMES=99 OVN_SUITE_LOCK_POLL_SEC=1 OVN_SUITE_LOCK_MAX_SEC=3
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 4 ] && echo 1 || echo 0)" "P2 never frees: bounded by the budget (1 + 3 polls = 4 attempts), then the benign rc 75"
  cr STUB_75_TIMES=1 OVN_SUITE_LOCK_POLL_SEC=1 OVN_SUITE_LOCK_MAX_SEC=0
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 1 ] && echo 1 || echo 0)" "P3 MAX 0 disables waiting (1 attempt, rc 75)"
  cr STUB_75_TIMES=1 OVN_SUITE_LOCK_RETRY_SEC=1
  ok "$([ "$rc" = 0 ] && [ "$(cat "$CNT")" = 2 ] && printf '%s' "$o" | grep -q 'retrying once' && echo 1 || echo 0)" "P5 explicit OVN_SUITE_LOCK_RETRY_SEC keeps the S1 single retry"
  # P4: candidate mode never polls
  local WR="$W/wr"; mkdir -p "$WR/scripts/overnight-queue/scripts/test"; cp "$QQ/scripts/test/run_all_sandboxed.sh" "$WR/scripts/overnight-queue/scripts/test/"
  git -C "$WR" init -q && git -C "$WR" add -A && git -C "$WR" -c user.email=t@t -c user.name=t commit -q -m c && git clone -q --bare "$WR" "$H/deploy-clone" 2>/dev/null
  local SHA; SHA="$(git -C "$WR" rev-parse HEAD)"
  rm -f "$CNT"; env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" STUB_75_TIMES=5 OVN_DEPLOY_CLONE="$H/deploy-clone" OVN_SUITE_LOCK_POLL_SEC=1 OVN_SUITE_LOCK_MAX_SEC=5 timeout 60 bash "$OPSX/run_suite_sandboxed_cron.sh" --candidate "$SHA" >/dev/null 2>&1; rc=$?
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 1 ] && echo 1 || echo 0)" "P4 --candidate mode never polls (its caller retries hourly)"
  safe_rm_rf "$W"
}
echo "##### Z4 suite cron poll #####"
run_checks "$OPS"
echo "== M. mutants (each must make a check fail)"
mutant(){ # name, anchor=>replacement in ops/run_suite_sandboxed_cron.sh
  local name="$1" expr="$2" M; M="$(safe_mktemp_dir_in "$SB" mut)" || return
  mkdir -p "$M/ops"; cp -p "$OPS"/*.sh "$OPS"/*.py "$M/ops/" 2>/dev/null; mkdir -p "$M/scripts/test"; cp -p "$HERE/lib_safe_tmp.sh" "$M/scripts/test/"
  python3 -I - "$M/ops/run_suite_sandboxed_cron.sh" "$expr" <<'PY'
import sys
p,e=sys.argv[1],sys.argv[2]; a,b=e.split("=>",1)
s=open(p).read(); n=s.replace(a,b,1); assert n!=s,"mutation anchor not found: "+a; open(p,"w").write(n)
PY
  local res; res="$( (run_checks "$M/ops") 2>&1 | grep -c '^  FAIL')"
  ok "$([ "$res" -ge 1 ] && echo 1 || echo 0)" "MUTANT $name -> $res check(s) fail"
}
mutant "poll loop runs once only" 'while [ $rc -eq 75 ] && [ "$waited" -lt "$MW" ]; do=>while [ $rc -eq 75 ] && [ "$waited" -lt 1 ]; do'
mutant "poll loop unbounded" 'while [ $rc -eq 75 ] && [ "$waited" -lt "$MW" ]; do=>while [ $rc -eq 75 ]; do'
mutant "candidate mode polls too" 'if [ $rc -eq 75 ] && [ -z "$CAND" ]; then=>if [ $rc -eq 75 ]; then'
echo "  $P passed, $F failed"; [ "$F" = 0 ]
