#!/usr/bin/env bash
# test_suite_candidate.sh - ops/run_suite_sandboxed_cron.sh --candidate <sha> and its PASS/FAIL records (package L4, 2026-10-18).
# box_autodeploy.sh deploys only a commit with state/suite_pass_<sha>; this proves that file is written ONLY when the CANDIDATE's own tree passed the suite (the stub run_all_sandboxed.sh
# of the candidate decides rc), names exactly that sha, never for a failed/contended run, that files the candidate deleted do not linger in the scratch tree, that the live tree is
# never modified, and that the legacy six-hourly run proves the deployed sha only when the live tree is byte-identical to it.
# Fake remote + fake live tree (see lib_deploy_fixture.sh); HOME is a sandbox; the suite itself is a stub.
# usage: test_suite_candidate.sh   env: L4_OPS_DIR, L4_CASES, L4_NO_MUTANTS=1
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/lib_deploy_fixture.sh"
export OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
command -v rsync >/dev/null 2>&1 || { echo "  SKIP: rsync missing"; exit 77; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
want(){ [ -z "${L4_CASES:-}" ] && return 0; case " $L4_CASES " in *" $1 "*) return 0;; esac; return 1; }
trap 'df_cleanup' EXIT
OPS="$DF_OPS"
[ -f "$OPS/run_suite_sandboxed_cron.sh" ] || { echo "  FAIL: wrapper missing in $OPS"; exit 1; }
mk(){ df_cleanup; df_init 1 || exit 1; df_env; safe_set_sandbox_home "$DF_T" || exit 1
  Q="$DF_Q"; mkdir -p "$HOME/qtmp"
  df_commit "add gone" scripts/gone.sh "#!/usr/bin/env bash
echo g" exec >/dev/null; B="$DF_SHA"; df_install "$B"
  df_git clone -q --bare "$DF_REMOTE" "$DF_CL" 2>/dev/null
  export OVN_SUITE_SCRATCH="$HOME/qtmp/suite"; unset OVN_FAKE_SUITE_RC; }
csync(){ df_git -C "$DF_CL" fetch -q origin +refs/heads/claude/feature:refs/heads/claude/feature; }
run(){ bash "$Q/ops/run_suite_sandboxed_cron.sh" "$@" > "$DF_T/out" 2>&1; RC=$?; }
snap0(){ SNAP="$(df_snap)"; }
same(){ [ "$(df_snap)" = "$SNAP" ] && echo 1 || echo 0; }

if want S1; then mk
  df_commit "c2" VERSION v2 scripts/gone.sh -DELETE- >/dev/null; C2="$DF_SHA"; csync; snap0
  OVN_FAKE_SUITE_RC=0 run --candidate "$C2"
  ok "S1 candidate suite PASS: rc 0 and state/suite_pass_<sha> records sha, rc=0, mode=candidate" "$([ $RC = 0 ] && grep -qx "sha=$C2" "$Q/state/suite_pass_$C2" && grep -qx 'rc=0' "$Q/state/suite_pass_$C2" && grep -qx 'mode=candidate' "$Q/state/suite_pass_$C2" && echo 1 || echo 0)"
  ok "S1 the suite ran on the CANDIDATE's tree (VERSION v2), not the live tree (v1)" "$(grep -q 'tree=v2' "$DF_T/out" && echo 1 || echo 0)"
  ok "S1 a file the candidate DELETED is gone from the scratch tree (gone=no) while the live tree still has it" "$(grep -q 'gone=no' "$DF_T/out" && [ -e "$Q/scripts/gone.sh" ] && echo 1 || echo 0)"
  ok "S1 the live queue tree is NOT modified by the run (byte-identical)" "$([ "$(same)" = 1 ] && echo 1 || echo 0)"
fi
if want S2; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; csync
  OVN_FAKE_SUITE_RC=3 run --candidate "$C2"
  ok "S2 candidate suite FAIL (rc 3): rc 3 propagated, NO pass file, suite_fail_<sha> with rc=3, WARN in alerts.log" "$([ $RC = 3 ] && [ ! -e "$Q/state/suite_pass_$C2" ] && grep -qx 'rc=3' "$Q/state/suite_fail_$C2" && grep -q 'candidate' "$Q/state/alerts.log" && echo 1 || echo 0)"
  OVN_FAKE_SUITE_RC=0 run --candidate "$C2"
  ok "S2b a later PASS replaces the FAIL record" "$([ -e "$Q/state/suite_pass_$C2" ] && [ ! -e "$Q/state/suite_fail_$C2" ] && echo 1 || echo 0)"
fi
if want S3; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; csync; echo "$C2 1" > "$Q/state/autodeploy_suite_trigger"
  OVN_FAKE_SUITE_RC=75 run --candidate "$C2"
  ok "S3 rc 75 (another run holds the lock): no pass, no fail record, no alert, the auto-deploy trigger is cleared so it retries" "$([ $RC = 75 ] && [ ! -e "$Q/state/suite_pass_$C2" ] && [ ! -e "$Q/state/suite_fail_$C2" ] && [ ! -e "$Q/state/autodeploy_suite_trigger" ] && ! grep -q 'rc=75' "$Q/state/alerts.log" 2>/dev/null && echo 1 || echo 0)"
fi
if want S4; then mk
  run --candidate deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  ok "S4 a commit that is not in the deploy clone is refused (rc 78) and records nothing" "$([ $RC = 78 ] && ! ls "$Q"/state/suite_* >/dev/null 2>&1 && echo 1 || echo 0)"
  run --candidate 'not-hex!'
  ok "S4b a non-hex candidate is refused (rc 78)" "$([ $RC = 78 ] && echo 1 || echo 0)"
fi
if want S5; then mk
  snap0; OVN_FAKE_SUITE_RC=0 run
  ok "S5 legacy six-hourly run on a tree byte-identical to deployed_sha records the PASS for deployed_sha (mode=deployed-tree-identical)" "$([ $RC = 0 ] && grep -qx "sha=$B" "$Q/state/suite_pass_$B" && grep -qx 'mode=deployed-tree-identical' "$Q/state/suite_pass_$B" && echo 1 || echo 0)"
  rm -f "$Q/state/suite_pass_$B"; printf '#!/usr/bin/env bash\necho hot\n' > "$Q/run_overnight.sh"
  OVN_FAKE_SUITE_RC=0 run
  ok "S5b legacy run on a HOT-PATCHED live tree proves nothing about deployed_sha: no pass recorded" "$([ $RC = 0 ] && [ ! -e "$Q/state/suite_pass_$B" ] && echo 1 || echo 0)"
  df_install "$B"; OVN_FAKE_SUITE_RC=3 run
  ok "S5c legacy run that FAILS records nothing" "$([ $RC = 3 ] && [ ! -e "$Q/state/suite_pass_$B" ] && echo 1 || echo 0)"
fi
if want S6; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; csync
  ( OVN_FAKE_SUITE_SLEEP=4 OVN_FAKE_SUITE_RC=0 bash "$Q/ops/run_suite_sandboxed_cron.sh" --candidate "$C2" > "$DF_T/out1" 2>&1; echo $? > "$DF_T/rc1" ) &
  P1=$!; sleep 2
  bash "$Q/ops/run_suite_sandboxed_cron.sh" > "$DF_T/out2" 2>&1; RC2=$?
  V_MID="$(cat "$HOME/qtmp/suite/oq/VERSION" 2>/dev/null)"
  wait "$P1"
  ok "S6 a second run (the 6-hourly cron, live tree) while a candidate suite is running exits 75 and says who holds the lock" "$([ $RC2 = 75 ] && grep -q 'holds' "$DF_T/out2" && echo 1 || echo 0)"
  ok "S6 ...and it did NOT swap the scratch tree under the running suite: the tree is still the candidate's (v2) mid-run and at the end of the run" "$([ "$V_MID" = v2 ] && grep -q 'end tree=v2' "$DF_T/out1" && [ "$(cat "$DF_T/rc1")" = 0 ] && echo 1 || echo 0)"
  ok "S6 the candidate's PASS (recorded for c2) was earned on c2's tree; the lock is released afterwards" "$(grep -qx "sha=$C2" "$Q/state/suite_pass_$C2" && [ ! -d "$HOME/qtmp/suite.lock.d" ] && echo 1 || echo 0)"
  df_commit "c3" VERSION v3 >/dev/null; C3="$DF_SHA"; csync
  ( OVN_FAKE_SUITE_SLEEP=4 bash "$Q/ops/run_suite_sandboxed_cron.sh" --candidate "$C2" > "$DF_T/out1" 2>&1 ) &
  P1=$!; sleep 2; echo "$C3 1" > "$Q/state/autodeploy_suite_trigger"
  bash "$Q/ops/run_suite_sandboxed_cron.sh" --candidate "$C3" > "$DF_T/out2" 2>&1; RC2=$?
  wait "$P1"
  ok "S6b a contended CANDIDATE run exits 75, records nothing for its sha and clears the auto-deploy trigger (retry next hour)" "$([ $RC2 = 75 ] && [ ! -e "$Q/state/suite_pass_$C3" ] && [ ! -e "$Q/state/suite_fail_$C3" ] && [ ! -e "$Q/state/autodeploy_suite_trigger" ] && echo 1 || echo 0)"
  mkdir -p "$HOME/qtmp/suite.lock.d"; echo 2147483 > "$HOME/qtmp/suite.lock.d/pid"
  OVN_FAKE_SUITE_RC=0 run --candidate "$C3"
  ok "S6c a STALE lock (dead pid) is taken over and the run completes" "$([ $RC = 0 ] && [ -e "$Q/state/suite_pass_$C3" ] && echo 1 || echo 0)"
fi
if want S7; then mk
  echo "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef 1" > "$Q/state/autodeploy_suite_trigger"
  run --candidate deadbeefdeadbeefdeadbeefdeadbeefdeadbeef
  ok "S7 a setup failure before any verdict (commit missing from the clone, rc 78) CLEARS the 12 h trigger so the next hourly pass retries" "$([ $RC = 78 ] && [ ! -e "$Q/state/autodeploy_suite_trigger" ] && echo 1 || echo 0)"
  ok "S7 ...and records state/autodeploy_suite_error (sha, rc=78, reason) for the report, but no suite_fail/suite_pass" "$(grep -qx 'sha=deadbeefdeadbeefdeadbeefdeadbeefdeadbeef' "$Q/state/autodeploy_suite_error" && grep -qx 'rc=78' "$Q/state/autodeploy_suite_error" && grep -q '^reason=.*deploy clone' "$Q/state/autodeploy_suite_error" && ! ls "$Q"/state/suite_pass_* "$Q"/state/suite_fail_* >/dev/null 2>&1 && echo 1 || echo 0)"
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; csync
  OVN_FAKE_SUITE_RC=0 run --candidate "$C2"
  ok "S7b a later successful verdict removes the stale setup-error note" "$([ ! -e "$Q/state/autodeploy_suite_error" ] && [ -e "$Q/state/suite_pass_$C2" ] && echo 1 || echo 0)"
fi
if want S8; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; csync; echo "$C2 1" > "$Q/state/autodeploy_suite_trigger"
  OVN_FAKE_SUITE_RC=3 run --candidate "$C2"
  ok "S8 a failing suite records attempts=1 and clears the trigger (the hourly pass decides whether to retry)" "$([ $RC = 3 ] && grep -qx 'attempts=1' "$Q/state/suite_fail_$C2" && [ ! -e "$Q/state/autodeploy_suite_trigger" ] && echo 1 || echo 0)"
  OVN_FAKE_SUITE_RC=3 run --candidate "$C2"
  ok "S8 the next failing attempt counts up (attempts=2)" "$([ $RC = 3 ] && grep -qx 'attempts=2' "$Q/state/suite_fail_$C2" && echo 1 || echo 0)"
fi

if [ -z "${L4_NO_MUTANTS:-}" ] && [ -z "${L4_CASES:-}" ]; then
  MT="$(safe_mktemp_dir dfm)" || exit 1
  trap 'df_cleanup; safe_rm_rf "$MT"' EXIT
  mutant(){ # label old new cases
    local lab="$1" old="$2" new="$3" cases="$4" d="$MT/m$RANDOM"
    mkdir -p "$d"; cp -p "$OPS"/*.sh "$OPS"/*.py "$d"/
    OLD="$old" NEW="$new" python3 - "$OPS/run_suite_sandboxed_cron.sh" "$d/run_suite_sandboxed_cron.sh" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"][:70])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
    [ $? -eq 0 ] || { ok "mutant '$lab' could not be applied" 0; return; }
    L4_OPS_DIR="$d" L4_CASES="$cases" L4_NO_MUTANTS=1 bash "$HERE/test_suite_candidate.sh" > "$MT/mut.out" 2>&1
    if [ "$(grep -c '^  FAIL ' "$MT/mut.out")" -gt 0 ] && [ "$(grep -c Traceback "$MT/mut.out")" -eq 0 ]; then ok "mutant caught: $lab" 1; else ok "mutant NOT caught: $lab" 0; sed -n 1,10p "$MT/mut.out"; fi
  }
  mutant "pass recorded whatever the suite rc" '  if [ $rc -eq 0 ]; then record "suite_pass_$CAND"' '  if true; then record "suite_pass_$CAND"' "S2"
  mutant "candidate tree not laid over the scratch copy (tests the live tree)" '  git -C "$CLONE" archive --format=tar "$CAND:scripts/overnight-queue" 2>/dev/null | tar -xf - -C "$S/oq"' '  true | true' "S1"
  mutant "files deleted by the candidate linger in the scratch tree" '      rm -f "${S:?}/oq/$df"' '      :' "S1"
  mutant "rc 75 leaves the trigger (the retry never happens)" 'elif [ $rc -eq 75 ]; then rm -f "$Q/state/autodeploy_suite_trigger"' 'elif [ $rc -eq 75 ]; then :' "S3"
  mutant "legacy run records a pass for a hot-patched tree" ')" = True ]; then' ')" != zzz ]; then' "S5"
  mutant "a failed run is recorded as fail only when rc is 1 (rc 3 leaves no record)" '    record "suite_fail_$CAND" "sha=$CAND" "rc=$rc" "ts=$TSNOW" "attempts=$((PA+1))"' '    :' "S2"
  mutant "no run lock (a second run swaps the scratch tree mid-run)" 'if ! lock_take; then' 'if false; then' "S6"
  mutant "the lock lives INSIDE the scratch tree (the rsync --delete wipes it)" 'LOCKD="$S.lock.d"' 'LOCKD="$S/oq/.lock.d"' "S6"
  mutant "a contended candidate run leaves the trigger" '    rm -f "$Q/state/autodeploy_suite_trigger"          # no verdict was reached' '    :          # no verdict was reached' "S6 S7"
  mutant "stale lock never taken over" '  if [ -n "$p" ] && kill -0 "$p" 2>/dev/null; then return 1; fi
  rm -f "$LOCKD/pid"; rmdir "$LOCKD" 2>/dev/null; mkdir "$LOCKD" 2>/dev/null || return 1; echo "$$" > "$LOCKD/pid"; return 0' '  return 1' "S6"
  mutant "setup failure leaves no error note" "if [ \"\$rc\" -eq 78 ] && [ -n \"\$ERRMSG\" ]; then" 'if false; then' "S7"
  mutant "failing suite does not clear the trigger" '    rm -f "$Q/state/autodeploy_suite_trigger"          # the hourly pass decides' '    :          # the hourly pass decides' "S8"
  mutant "attempt counter never increments" 'attempts=$((PA+1))"
    rm -f' 'attempts=1"
    rm -f' "S8"
fi
echo "  suite_candidate: $P passed, $F failed"
[ "$F" -eq 0 ]
