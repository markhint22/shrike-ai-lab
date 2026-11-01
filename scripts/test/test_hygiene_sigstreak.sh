#!/usr/bin/env bash
# Regression test: identical failing-test streak alert for branch_hygiene gates (package K3 item 4, 2026-11-01).
# Replay fixture: fixtures_k3/gitlark_gate_failed.txt = a gate output failing on the real gitlark test
# backend/tests/test_workspace_conversation_authz.py::test_owner_can_create_conversation (the status-code ping-pong case).
# Drives ovn_hygiene_stuck_check.sh end to end (fake curl records the relay call) and every behaviour also runs against a MUTANT of
# scripts/ovn_hygiene_sigstreak.py (one piece of logic broken) which must FAIL the matching check.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; Q="$(cd "$HERE/../.." && pwd)"
SIG0="$Q/scripts/ovn_hygiene_sigstreak.py"; CHK="$Q/ovn_hygiene_stuck_check.sh"; FIX="$HERE/fixtures_k3/gitlark_gate_failed.txt"
[ -f "$SIG0" ] && [ -f "$CHK" ] || { echo "  SKIP: sources not found"; exit 77; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
NOW="$(date +%s)"
fmt(){ date -d "@$1" +%Y%m%d-%H%M%S 2>/dev/null || date -r "$1" +%Y%m%d-%H%M%S; }
TESTID="backend/tests/test_workspace_conversation_authz.py::test_owner_can_create_conversation"

mkq(){ # $1 label $2 sigstreak.py path -> prints the queue dir (HOME = $tmp/$1/home, queue = home/overnight-queue)
  local h="$tmp/$1/home" q="$tmp/$1/home/overnight-queue"
  mkdir -p "$q/state" "$q/logs/hygiene_gate" "$q/scripts" "$q/repos/gitlark/backend/tests" "$tmp/$1/bin"
  cp "$CHK" "$q/ovn_hygiene_stuck_check.sh"; cp "$2" "$q/scripts/ovn_hygiene_sigstreak.py"
  cat > "$tmp/$1/bin/curl" <<CURL
#!/usr/bin/env bash
{ for a in "\$@"; do printf '%s\n' "\$a"; done; echo "-----"; } >> "$tmp/$1/curl.log"
exit 0
CURL
  chmod +x "$tmp/$1/bin/curl"
  ( cd "$q/repos/gitlark" && git init -q && git config user.email t@t && git config user.name fleet && printf 'def test_owner_can_create_conversation():\n    pass\n' > backend/tests/test_workspace_conversation_authz.py \
    && git add -A && git commit -q -m "feat(gitlark): staged step 0 - add test_owner_can_create_conversation" ) >/dev/null 2>&1
  echo "$q"; }
gate(){ # $1 queue $2 seconds_ago $3 content-file|"green"|"many" ; one gate file for gitlark/pytest
  local f="$1/logs/hygiene_gate/$(fmt $((NOW-$2))).gitlark.pytest.AbC123"
  case "$3" in
    green) printf '1631 passed in 400s\n' > "$f";;
    many) for i in $(seq 1 40); do echo "FAILED backend/tests/test_many.py::test_n$i - boom"; done > "$f";;
    other) sed 's/test_owner_can_create_conversation/test_something_else/g' "$FIX" > "$f";;
    *) cp "$3" "$f";;
  esac; }
flag(){ echo "gate FAILED (build/tests red)" > "$1/state/branch_hygiene_review_gitlark"; }
runchk(){ local lab="$1" q="$2"; shift 2; ( cd "$q" && env HOME="$tmp/$lab/home" PATH="$tmp/$lab/bin:$PATH" "$@" bash ovn_hygiene_stuck_check.sh >/dev/null 2>&1 ); }
cnt(){ local n; n="$(grep -c "$1" "$2" 2>/dev/null)"; echo "${n:-0}"; }
urgent(){ cnt '^Priority: urgent$' "$tmp/$1/curl.log"; }
alerts_crit(){ cnt 'crit | hygiene-sigstreak:gitlark' "$1/state/alerts.log"; }

suite(){ # $1 label  $2 sigstreak.py ; prints "key=0|1" lines
  local L="$1" S="$2" q
  # S1/S2 positive then once-per-signature
  q="$(mkq "$L-s1" "$S")"; gate "$q" 10800 "$FIX"; gate "$q" 7200 "$FIX"; gate "$q" 3600 "$FIX"; flag "$q"
  runchk "$L-s1" "$q" OVN_HYG_SIGSTREAK=on
  if [ "$(urgent "$L-s1")" = 1 ] && grep -q "Hygiene gate stuck on the SAME tests: gitlark" "$tmp/$L-s1/curl.log" && grep -qF "$TESTID" "$tmp/$L-s1/curl.log" \
     && grep -q "3 consecutive passes" "$tmp/$L-s1/curl.log" && grep -q "test_workspace_conversation_authz.py <- " "$tmp/$L-s1/curl.log" && grep -q "staged step 0" "$tmp/$L-s1/curl.log" \
     && [ "$(alerts_crit "$q")" = 1 ]; then echo "P1_alerts_urgent_naming_tests_and_commits=1"; else echo "P1_alerts_urgent_naming_tests_and_commits=0"; fi
  runchk "$L-s1" "$q" OVN_HYG_SIGSTREAK=on; runchk "$L-s1" "$q" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s1")" = 1 ] && [ "$(alerts_crit "$q")" = 1 ] && echo "P2_once_per_signature=1" || echo "P2_once_per_signature=0"
  # S9 re-arm after the streak ends (flag cleared by a successful merge) and returns
  rm -f "$q/state/branch_hygiene_review_gitlark"; runchk "$L-s1" "$q" OVN_HYG_SIGSTREAK=on; flag "$q"; runchk "$L-s1" "$q" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s1")" = 2 ] && echo "P3_rearms_after_streak_ends=1" || echo "P3_rearms_after_streak_ends=0"
  # S3 differing sets (A,A,B) and (A,B,A)
  q="$(mkq "$L-s3" "$S")"; gate "$q" 10800 "$FIX"; gate "$q" 7200 "$FIX"; gate "$q" 3600 other; flag "$q"; runchk "$L-s3" "$q" OVN_HYG_SIGSTREAK=on
  q2="$(mkq "$L-s3b" "$S")"; gate "$q2" 10800 "$FIX"; gate "$q2" 7200 other; gate "$q2" 3600 "$FIX"; flag "$q2"; runchk "$L-s3b" "$q2" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s3")" = 0 ] && [ "$(urgent "$L-s3b")" = 0 ] && echo "N1_different_sets_never_alert=1" || echo "N1_different_sets_never_alert=0"
  # S4 only two passes
  q="$(mkq "$L-s4" "$S")"; gate "$q" 7200 "$FIX"; gate "$q" 3600 "$FIX"; flag "$q"; runchk "$L-s4" "$q" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s4")" = 0 ] && echo "N2_two_passes_not_enough=1" || echo "N2_two_passes_not_enough=0"
  # S5 a retry-on-timeout re-run (two files within minutes) is ONE pass
  q="$(mkq "$L-s5" "$S")"; gate "$q" 7200 "$FIX"; gate "$q" 3600 "$FIX"; gate "$q" 3540 "$FIX"; flag "$q"; runchk "$L-s5" "$q" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s5")" = 0 ] && echo "N3_retry_rerun_is_one_pass=1" || echo "N3_retry_rerun_is_one_pass=0"
  # S6 a green gate between breaks the run
  q="$(mkq "$L-s6" "$S")"; gate "$q" 10800 "$FIX"; gate "$q" 7200 green; gate "$q" 3600 "$FIX"; flag "$q"; runchk "$L-s6" "$q" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s6")" = 0 ] && echo "N4_green_between_breaks_run=1" || echo "N4_green_between_breaks_run=0"
  # S7 no review flag = streak over
  q="$(mkq "$L-s7" "$S")"; gate "$q" 10800 "$FIX"; gate "$q" 7200 "$FIX"; gate "$q" 3600 "$FIX"; runchk "$L-s7" "$q" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s7")" = 0 ] && echo "N5_no_review_flag_no_alert=1" || echo "N5_no_review_flag_no_alert=0"
  # S10 baseline break (> 30 failing ids) is not a signature
  q="$(mkq "$L-s10" "$S")"; gate "$q" 10800 many; gate "$q" 7200 many; gate "$q" 3600 many; flag "$q"; runchk "$L-s10" "$q" OVN_HYG_SIGSTREAK=on
  [ "$(urgent "$L-s10")" = 0 ] && echo "N6_mass_failure_is_not_a_signature=1" || echo "N6_mass_failure_is_not_a_signature=0"
  # S8 default (shadow): no page, one shadow log line, one info alert
  q="$(mkq "$L-s8" "$S")"; gate "$q" 10800 "$FIX"; gate "$q" 7200 "$FIX"; gate "$q" 3600 "$FIX"; flag "$q"; runchk "$L-s8" "$q"; runchk "$L-s8" "$q"
  if [ "$(urgent "$L-s8")" = 0 ] && [ "$(cnt '' "$q/state/hygiene_sigstreak_shadow.log")" = 1 ] && [ "$(cnt 'info | hygiene-sigstreak:gitlark' "$q/state/alerts.log")" = 1 ] \
     && [ "$(alerts_crit "$q")" = 0 ]; then echo "D1_shadow_default_logs_only=1"; else echo "D1_shadow_default_logs_only=0"; fi
  # S11 off
  q="$(mkq "$L-s11" "$S")"; gate "$q" 10800 "$FIX"; gate "$q" 7200 "$FIX"; gate "$q" 3600 "$FIX"; flag "$q"; runchk "$L-s11" "$q" OVN_HYG_SIGSTREAK=off
  [ ! -e "$q/state/hygiene_sigstreak_shadow.log" ] && [ "$(urgent "$L-s11")" = 0 ] && [ ! -s "$q/state/alerts.log" ] && echo "D2_off_disabled=1" || echo "D2_off_disabled=0"
}
REAL_OUT="$(suite real "$SIG0")"
for k in P1_alerts_urgent_naming_tests_and_commits P2_once_per_signature P3_rearms_after_streak_ends N1_different_sets_never_alert N2_two_passes_not_enough N3_retry_rerun_is_one_pass N4_green_between_breaks_run N5_no_review_flag_no_alert N6_mass_failure_is_not_a_signature D1_shadow_default_logs_only D2_off_disabled; do
  ok "real helper: $k" "printf '%s\n' '$REAL_OUT' | grep -qx '$k=1'"
done
mut(){ # name key python-old python-new
  local name="$1" key="$2" old="$3" new="$4" f="$tmp/mut_$1.py"
  python3 - "$SIG0" "$f" "$old" "$new" <<'PY'
import sys
src=open(sys.argv[1]).read()
if src.count(sys.argv[3])!=1: sys.exit(3)
open(sys.argv[2],"w").write(src.replace(sys.argv[3],sys.argv[4]))
PY
  ok "mutation $name applies exactly once" "[ \$? -eq 0 ] && ! cmp -s '$SIG0' '$f'"
  out="$(suite "$name" "$f")"
  ok "MUTATION caught ($name): $key FAILS when the logic is broken" "printf '%s\n' '$out' | grep -qx '$key=0'"; }
mut m_anyset      N1_different_sets_never_alert  '        if ids != last:
            break' '        if not ids:
            break'
mut m_n1          N2_two_passes_not_enough       'if run < N or not fresh' 'if run < 1 or not fresh'
mut m_noonce      P2_once_per_signature          'if f.read().strip() == sig:
                    continue' 'if False:
                    continue'
mut m_nomerge     N3_retry_rerun_is_one_pass     'if seq and t - seq[-1][0] <= MERGE_S:' 'if False:'
mut m_noflag      N5_no_review_flag_no_alert     'or not os.path.exists(flag):' 'or False:'
mut m_skipgreen   N4_green_between_breaks_run    '        if ids != last:
            break' '        if ids and ids != last:
            break'
mut m_shadowpages D1_shadow_default_logs_only    'if MODE == "on":' 'if True:'
mut m_notouch     P1_alerts_urgent_naming_tests_and_commits 'if not os.path.isdir(clone):
        return []' 'if True:
        return []'
mut m_massok      N6_mass_failure_is_not_a_signature 'if not last or len(last) > MAX_IDS:' 'if not last:'
mut m_norearm     P3_rearms_after_streak_ends    'if n.startswith(SEEN_PREFIX) and os.path.join(seen_dir, n) not in live:' 'if False:'
safe_rm_rf "$tmp"
echo "Hygiene same-failing-tests streak: $P passed, $F failed"
[ "$F" -eq 0 ]
