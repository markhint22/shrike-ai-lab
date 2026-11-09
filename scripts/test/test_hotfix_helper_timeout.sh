#!/usr/bin/env bash
# hotfix-scout-hang (2026-11-08): no helper the run loop shells out to may block it. lib_helper_timeout.sh (ovn_hto / ovn_hto_open) wraps each one in `timeout`; a hung
# helper is killed, one line is logged, and the cycle proceeds on the unmodified input (fail-open).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
Q="$HERE/../.."; [ -f "$Q/run_overnight.sh" ] || Q="$HERE/.."
LIB="$Q/scripts/lib_helper_timeout.sh"
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
type -P timeout >/dev/null 2>&1 || type -P gtimeout >/dev/null 2>&1 || { echo "  SKIP: no timeout binary"; exit 0; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
T="$(safe_mktemp_dir hto)" || exit 1
trap 'safe_rm_rf "$T"' EXIT
rc=0; ok(){ echo "  ok   $1"; }; bad(){ echo "  FAIL: $1"; rc=1; }
. "$LIB"
task_log="$T/task.log"; export OVN_HTO_LOG="$T/hto.log"

echo "== lib semantics"
s=$(date +%s); ovn_hto 1 stub sleep 30; r=$?; e=$(( $(date +%s) - s ))
{ [ $r -eq 124 ] && [ $e -le 4 ]; } && ok "hung helper is killed at its cap: rc=124 after ${e}s" || bad "ovn_hto rc=$r after ${e}s"
grep -q 'helper-timeout: stub exceeded 1s' "$task_log" && grep -q 'helper-timeout: stub' "$OVN_HTO_LOG" && ok "timeout is logged to the cycle log and the state log" || bad "no timeout line logged"
s=$(date +%s); ovn_hto_open 1 stub sleep 30; r=$?; e=$(( $(date +%s) - s ))
{ [ $r -eq 0 ] && [ $e -le 4 ]; } && ok "ovn_hto_open (gates): a hung checker reads as 'no verdict', rc=0" || bad "ovn_hto_open rc=$r"
ovn_hto 5 stub bash -c 'exit 3'; [ $? -eq 3 ] && ok "a helper's own non-zero rc passes through" || bad "rc not preserved"
ovn_hto_open 5 stub bash -c 'exit 3'; [ $? -eq 3 ] && ok "ovn_hto_open keeps a REAL failure (only a timeout is fail-open)" || bad "open swallowed a real failure"
[ "$(printf 'in\n' | ovn_hto 5 stub cat)" = in ] && ok "stdin/stdout pass through (pipeline + \$( ))" || bad "stdio not passed"
s=$(date +%s); OVN_HTO_MAX=1 ovn_hto 90 stub sleep 30; r=$?; e=$(( $(date +%s) - s ))
{ [ $r -eq 124 ] && [ $e -le 4 ]; } && ok "OVN_HTO_MAX caps every timeout" || bad "OVN_HTO_MAX ignored"
OVN_HTO=off ovn_hto 1 stub bash -c 'sleep 2; exit 7'; [ $? -eq 7 ] && ok "OVN_HTO=off is a plain call" || bad "kill switch"
# a helper that ignores TERM still dies (KILL after the -k grace)
s=$(date +%s); ovn_hto 1 stub bash -c 'trap "" TERM; while :; do sleep 1; done'; r=$?; e=$(( $(date +%s) - s ))
{ [ $r -eq 124 ] || [ $r -eq 137 ]; } && [ $e -le 10 ] && ok "a TERM-ignoring helper is KILLed (${e}s)" || bad "TERM-ignoring helper survived (rc=$r, ${e}s)"

echo "== wiring lint: every cycle-path helper call is wrapped"
# a line that runs one of these helpers (not a comment, not an assignment of the path, not a -f/-x test) must carry ovn_hto / ovn_hto_open / timeout
HELP='ovn_scout_ground|ovn_park_unworkable|ovn_retire_vague|ovn_fold_migration_items|ovn_generate_items|ovn_classify\.py|ovn_path_gate|ovn_progress_slice|ovn_already_done_gate|ovn_credit_already_satisfied|ovn_classify_fail|ovn_extract_failure|ovn_repeat_ids|dedupe_progress_headers|dedupe_gd_duplicate_functions|dedupe_python_duplicate_defs|update_progress|check_migrations|check_applied_migration_immutable|check_ghost_tests|lib_dep_import_check|cycle_notify|ovn_log_tokens|ovn_alembic_autogen|ovn_placeholder_scan|ovn_credit_items|ovn_udiff_anchor|ovn_limiter_order_lint'
n=0; miss=""
for f in run_overnight.sh ovn_stage_runner.sh scripts/lib_auto_credit.sh scripts/lib_item_select.sh scripts/lib_limiter_lint.sh scripts/lib_p4_outcomes.sh scripts/lib_fixup.sh scripts/lib_landing_gates.sh scripts/lib_verify_lint.sh; do
  while IFS= read -r line; do
    ln="${line%%:*}"; txt="${line#*:}"
    case "$txt" in [[:space:]]*'#'*|'#'*) continue;; esac
    printf '%s' "$txt" | grep -Eq '(python3?|bash|sh)[[:space:]]+(-I[[:space:]]+)?"?[^|;&]*('"$HELP"')' || { printf '%s' "$txt" | grep -Eq '"\$[A-Za-z_]*/(ovn_classify_fail|cycle_notify)\.sh"' || continue; }
    printf '%s' "$txt" | grep -Eq '(-f|-x|-s) +"?\$|^[[:space:]]*(_|[a-zA-Z_]+)=?"?\$?\{?[A-Za-z_]*(PY|py)\b[^=]*=' && ! printf '%s' "$txt" | grep -Eq '\$\(' && continue
    n=$((n+1))
    printf '%s' "$txt" | grep -Eq 'ovn_hto|timeout|_to\[@\]|\$to |\$\{_so_to' || miss="$miss $f:$ln"
  done < <(grep -nE "$HELP" "$Q/$f" 2>/dev/null | sed "s#^#$f:#" | sed -E 's#^[^:]+:([0-9]+):#\1:#')
done
[ -z "$miss" ] && ok "all $n helper invocations in run_overnight.sh / ovn_stage_runner.sh / lib_*.sh carry a timeout wrapper" || bad "unwrapped helper call(s):$miss"
[ "$n" -ge 40 ] && ok "lint saw $n invocations (not vacuous)" || bad "lint saw only $n invocations - its pattern is broken"

echo "== behaviour: the REAL call sites proceed when the helper hangs"
# extract the real scout call line from run_overnight.sh and run it against a stub that never returns
STUBD="$T/stub"; mkdir -p "$STUBD"; printf 'import time\nwhile True:\n    time.sleep(1)\n' > "$STUBD/ovn_scout_ground.py"
call="$(grep -E '^[[:space:]]*_sgr_out="\$\(' "$Q/run_overnight.sh" | head -1)"
[ -n "$call" ] || bad "scout call line not found in run_overnight.sh"
run_scout(){ ( set +u; . "$LIB"; SCRIPT_DIR="$STUBD"; task_log="$T/cycle.log"; : > "$task_log"; _sgr_item_f="$T/i"; : > "$_sgr_item_f"; OVN_MAX_FILE_BYTES=1; _sgr_out="SENTINEL"
  eval "$call"; echo "proceeded:[$_sgr_out]" ); }
s=$(date +%s); res="$(OVN_HTO_MAX=2 timeout 20 bash -c "$(declare -f run_scout); T='$T'; LIB='$LIB'; STUBD='$STUBD'; call=$(printf '%q' "$call"); run_scout" 2>/dev/null)"; e=$(( $(date +%s) - s ))
{ [ "$res" = "proceeded:[]" ] && [ $e -le 10 ]; } && ok "scout call returns empty (= plan unchanged) and the cycle proceeds in ${e}s" || bad "scout call blocked or odd result '$res' after ${e}s"
grep -q 'helper-timeout: scout_ground' "$T/cycle.log" && ok "the scout hang left a line in the cycle log" || bad "no cycle-log line"
# mutant: take the wrapper off the real line -> it blocks (proves this test fails on the old code)
unwrapped="${call//ovn_hto 60 scout_ground /}"
res="$(OVN_HTO_MAX=2 timeout 6 bash -c "$(declare -f run_scout); T='$T'; LIB='$LIB'; STUBD='$STUBD'; call=$(printf '%q' "$unwrapped"); run_scout" 2>/dev/null)"; r=$?
[ -z "$res" ] && ok "WITHOUT the wrapper the same call never returns (killed by the outer 6 s timeout): the test can fail" || bad "unwrapped mutant returned '$res'"
# a stage-runner filter keeps its input when the filter hangs
fl="$(grep -E 'ovn_hto 60 so_item_filter' "$Q/ovn_stage_runner.sh" | head -1)"
[ -n "$fl" ] && printf '%s' "$fl" | grep -q 'else printf' || bad "stage-runner item-filter line not found"
res="$( ( set +u; . "$LIB"; _SO_PY="$STUBD/ovn_scout_ground.py"; _SO_MODE=enforce; _SO_LOG=/dev/null; rd=/nonexistent; repo=r; _in=$'line one\nline two'; export OVN_HTO_MAX=2
  _f(){ eval "$fl"; }; _f ) 2>/dev/null )"
[ "$res" = $'line one\nline two' ] && ok "stage-runner item filter falls back to the unmodified input on a hang" || bad "filter fallback gave '$res'"
exit $rc
