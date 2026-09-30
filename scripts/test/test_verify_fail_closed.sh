#!/usr/bin/env bash
# FAIL-CLOSED verification (2026-09-30 incident): a repo with python tests whose venv pytest is missing/broken must NOT be reported as
# verified. (Four repos' venvs were destroyed 11:46-12:24; two red staged steps landed in shrike-notify because full_verify() found no
# pytest and returned "verified", and run_repo_verification() fell through to "none" -> pushed.)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }

# ---- run_overnight.sh: run_repo_verification ----
( . "$HERE/lib_ro_core.sh"; ro_init; ro_tasks '[]'; ro_source; set +e
  task_log="$T/v.log"; : > "$task_log"; V="$T/v"
  newrepo(){ rm -rf "$V"; mkdir -p "$V"; cd "$V" || exit 1; git init -q; echo base > README; git add -A; git commit -q -m base; BEFORE_SHA="$(git rev-parse HEAD)"; }
  newrepo; mkdir -p backend/tests; echo 'def test_a(): pass' > backend/tests/test_a.py; git add -A; git commit -q -m t
  r="$(run_repo_verification)"; echo "R1=$r"
  grep -q "fail-closed" "$task_log" && echo "LOG1=yes"
  r="$(OVN_VERIFY_FAIL_CLOSED=0 run_repo_verification)"; echo "R2=$r"
  mkdir -p backend/.venv/bin; printf '#!/bin/bash\necho "1 passed"\nexit 0\n' > backend/.venv/bin/pytest; chmod +x backend/.venv/bin/pytest
  r="$(run_repo_verification)"; echo "R3=$r"
  printf '#!/bin/bash\necho "1 failed"\nexit 1\n' > backend/.venv/bin/pytest
  r="$(run_repo_verification)"; echo "R4=$r"
  newrepo; echo x > f; git add -A; git commit -q -m x; r="$(run_repo_verification)"; echo "R5=$r"
  newrepo; mkdir -p web; printf '{"scripts":{"test":"echo"}}' > web/package.json; mkdir -p backend/tests; echo 'def test_a(): pass' > backend/tests/test_a.py; git add -A; git commit -q -m y
  r="$(run_repo_verification)"; echo "R6=$r"
) > /tmp/vfc.$$ 2>&1
get(){ grep "^$1=" /tmp/vfc.$$ | head -1 | cut -d= -f2; }
ok "python tests exist + no venv pytest -> skip (held, NOT pass/none)" "$([ "$(get R1)" = skip ] && echo 1 || echo 0)"
ok "the skip is explained in the task log as fail-closed" "$(grep -q LOG1=yes /tmp/vfc.$$ && echo 1 || echo 0)"
ok "OVN_VERIFY_FAIL_CLOSED=0 restores the old fall-through (none)" "$([ "$(get R2)" = none ] && echo 1 || echo 0)"
ok "with a working venv pytest the result is a normal pass" "$([ "$(get R3)" = pass ] && echo 1 || echo 0)"
ok "with a failing venv pytest the result is fail (fail wins over skip)" "$([ "$(get R4)" = fail ] && echo 1 || echo 0)"
ok "a repo with no python tests is unaffected (none)" "$([ "$(get R5)" = none ] && echo 1 || echo 0)"
ok "python tests exist but only a non-python suite could run -> still skip (web green must not mask missing python verification)" "$([ "$(get R6)" = skip ] && echo 1 || echo 0)"
rm -f /tmp/vfc.$$

# ---- ovn_stage_runner.sh: full_verify ----
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
pushed(){ git -C "$O" log --format=%s overnight/feature | grep -q 'staged step'; }
osr_new; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"      # NOTE: no osr_venv -> no live venv pytest, but the fixture repo has backend/tests
osr_run "$OSR_REPO" "$ITEM_PY"
t "no live venv pytest but python tests exist -> independent verify FAILED, NOT pushing" bash -c "grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_vlog | grep -q 'CANNOT verify (fail-closed)' && ok "verify log says it could not verify (fail-closed)" 1 || ok "verify log says it could not verify (fail-closed)" 0
t "nothing was pushed to overnight/feature" bash -c "! git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
osr_cleanup
osr_new; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
OVN_VERIFY_FAIL_CLOSED=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "OVN_VERIFY_FAIL_CLOSED=0 restores the old behavior (verified + pushed)" bash -c "git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
osr_cleanup
osr_new; osr_venv backend; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO" "$ITEM_PY"
t "with a live venv pytest the staged run verifies and pushes as before" bash -c "git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
echo "  $pass passed, $fail failed"; osr_summary >/dev/null 2>&1; [ "$fail" -eq 0 ] && [ "${fail:-0}" = 0 ]
