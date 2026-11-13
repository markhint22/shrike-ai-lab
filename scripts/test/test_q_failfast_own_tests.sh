#!/usr/bin/env bash
# test_q_failfast_own_tests.sh - q-landing-quality (2026-11-12): the stage runner's full_verify runs the cycle's OWN new/changed test files BEFORE the full suite and stops on red
# (OVN_VERIFY_FAILFAST_OWN_TESTS, default on). Ordering optimisation only: the verdict must be identical with the flag on and off for green, own-red and full-red trees.
# Runs the REAL ovn_stage_runner.sh in the hermetic fixture (fake pytest: mode failfile:<substr> fails only when the args name that file). Mutants of the runner must each be caught.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
REAL_RUNNER="$RUNNER"
if [ "${QFF_RUNNER:-}" ]; then RUNNER="$QFF_RUNNER"; fi
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
unset OVN_VERIFY_FAILFAST_OWN_TESTS OVN_FAILFAST_TIMEOUT
base(){ osr_new; osr_venv backend; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"; }
ncalls(){ wc -l < "$T/scn/pytest.calls" 2>/dev/null | tr -d ' '; }
fullcalls(){ grep -vc 'tests/test_foo.py' "$T/scn/pytest.calls" 2>/dev/null || true; }   # invocations that did NOT name the own file = the full suite
verdict(){ if grep -q 'independent full-verify: PASSED' "$T/out.txt"; then echo PASS; elif grep -q 'independent full-verify: FAILED' "$T/out.txt"; then echo FAIL; else echo OTHER; fi; }

echo "== green tree: identical verdict on/off, own file runs first"
base; echo ok > "$T/scn/pytest.mode"; osr_run "$OSR_REPO" "$ITEM_PY"; V_ON="$(verdict)"; N_ON="$(ncalls)"; F_ON="$(fullcalls)"
t "green: verified (flag on)" [ "$V_ON" = PASS ]
t "green: own-test run comes BEFORE the full suite" bash -c "head -1 '$T/scn/pytest.calls' | grep -q 'tests/test_foo.py'"
t "green: the full suite still runs (never skipped when the own file is green)" [ "$F_ON" -ge 1 ]
t "green: verify log names the fail-fast step with timeout 120" bash -c "grep -q 'fail-fast: cycle.s own new/changed test files first (timeout 120s)' '$T/state_dummy' 2>/dev/null || cat '$Q'/state/stage_runs/*.verify.log | grep -q 'fail-fast: cycle.s own new/changed test files first (timeout 120s)'"
ownruns(){ grep -c 'tests/test_foo.py' "$T/scn/pytest.calls" 2>/dev/null || true; }
t "green: the own file ran exactly ONCE (the late NEW/CHANGED TESTS step does not repeat a green early run)" [ "$(ownruns)" = 1 ]
t "green: verify log says the late python re-run was skipped" bash -c "cat '$Q'/state/stage_runs/*.verify.log | grep -q 'already green in the fail-fast step'"
osr_cleanup
base; echo ok > "$T/scn/pytest.mode"; OVN_VERIFY_FAILFAST_OWN_TESTS=off osr_run "$OSR_REPO" "$ITEM_PY"; V_OFF="$(verdict)"
t "green: flag off runs the own file once (late step only, nothing skipped)" [ "$(ownruns)" = 1 ]
t "green: flag off gives the same verdict" [ "$V_OFF" = "$V_ON" ]
t "green: flag off keeps the old order (full suite first, no fail-fast line)" bash -c "! head -1 '$T/scn/pytest.calls' | grep -q 'tests/test_foo.py' && ! cat '$Q'/state/stage_runs/*.verify.log | grep -q 'fail-fast'"
osr_cleanup

echo "== own file red, full suite would be green: stop early, same RED verdict"
base; echo "failfile:tests/test_foo.py" > "$T/scn/pytest.mode"; osr_run "$OSR_REPO" "$ITEM_PY"; V_ON="$(verdict)"; N_ON="$(ncalls)"; F_ON="$(fullcalls)"
t "own-red: FAILED, nothing pushed (flag on)" bash -c "[ '$V_ON' = FAIL ] && ! git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
t "own-red: the full suite was NOT run (only the own file)" bash -c "[ '$F_ON' = 0 ] && [ '$N_ON' = 1 ]"
t "own-red: verify log carries FAIL-FAST + NEW-TESTS RED (the repair loop reads these)" bash -c "cat '$Q'/state/stage_runs/*.verify.log | grep -q 'FAIL-FAST: the cycle.s own test file' && cat '$Q'/state/stage_runs/*.verify.log | grep -q 'NEW-TESTS RED'"
osr_cleanup
base; echo "failfile:tests/test_foo.py" > "$T/scn/pytest.mode"; OVN_VERIFY_FAILFAST_OWN_TESTS=off osr_run "$OSR_REPO" "$ITEM_PY"; V_OFF="$(verdict)"; N_OFF="$(ncalls)"
t "own-red: flag off is ALSO red (cannot turn red into green or green into red)" [ "$V_OFF" = FAIL ]
t "own-red: flag off ran the full suite first, then the own file (2 calls: the waste being removed)" [ "$N_OFF" -ge 2 ]
osr_cleanup

echo "== early run hit an infra trouble (rc 124): the late step must still run the own file (never skip on unproven green)"
base; echo "own124:tests/test_foo.py" > "$T/scn/pytest.mode"; osr_run "$OSR_REPO" "$ITEM_PY"
t "infra: own file attempted early AND again late (2 runs), no skip line" bash -c "[ '$(ownruns)' = 2 ] && ! cat '$Q'/state/stage_runs/*.verify.log | grep -q 'already green in the fail-fast step'"
t "infra: the full suite still ran" [ "$(fullcalls)" -ge 1 ]
osr_cleanup

echo "== whole suite red: same verdict on/off"
base; echo fail > "$T/scn/pytest.mode"; osr_run "$OSR_REPO" "$ITEM_PY"; V_ON="$(verdict)"
osr_cleanup
base; echo fail > "$T/scn/pytest.mode"; OVN_VERIFY_FAILFAST_OWN_TESTS=off osr_run "$OSR_REPO" "$ITEM_PY"; V_OFF="$(verdict)"
t "all-red: both FAIL" bash -c "[ '$V_ON' = FAIL ] && [ '$V_OFF' = FAIL ]"
osr_cleanup

echo "== OVN_RUN_NEW_TESTS=off disables the early run too (no own-file invocation at all)"
base; echo ok > "$T/scn/pytest.mode"; OVN_RUN_NEW_TESTS=off osr_run "$OSR_REPO" "$ITEM_PY"
t "kill switch: no call names the own file" bash -c "! grep -q 'tests/test_foo.py' '$T/scn/pytest.calls'"
osr_cleanup

echo "== structure"
t "an untracked alembic stub skips the early stop (the later drop-stubs helper could change the own-test result)" grep -q "alembic/versions/" "$RUNNER"
t "early run uses OVN_NEW_TESTS_TIMEOUT=\${OVN_FAILFAST_TIMEOUT:-120}" grep -q 'OVN_NEW_TESTS_TIMEOUT="${OVN_FAILFAST_TIMEOUT:-120}"' "$RUNNER"
t "the early run never covers GUT (godot arg empty: GUT must not run before godot --import; it keeps its single late run)" grep -qF 'ovn_run_new_tests "$wt" "${pkg:-.}" "$HOME/overnight-queue/$vp" "" ' "$RUNNER"
t "the late step skips python only after a proven-green early run" grep -q '_ff_py_green' "$RUNNER"
t "the full pytest is gated on _ff_red" grep -q '"${_ff_red:-0}" != 1' "$RUNNER"

# ---- mutants: run this body against a modified runner; each must go red
if [ -z "${QFF_RUNNER:-}" ] && [ "${1:-}" != "--no-mutants" ]; then
  mut(){ local name="$1" a="$2" b="$3" f; f="$(safe_mktemp_dir)/ovn_stage_runner.$name.sh"; OSR_ALL_T+=("$(dirname "$f")")
    python3 - "$REAL_RUNNER" "$f" "$a" "$b" <<'PYEOF' || { fail=$((fail+1)); echo "  FAIL mutant $name did not apply"; return; }
import sys
src, dst, a, b = sys.argv[1:5]; s = open(src).read(); assert s.count(a) >= 1, a; open(dst, "w").write(s.replace(a, b, 1))
PYEOF
    if QFF_RUNNER="$f" bash "$0" --no-mutants >/dev/null 2>&1; then fail=$((fail+1)); echo "  FAIL mutant $name SURVIVED"; else pass=$((pass+1)); echo "  ok   mutant $name caught"; fi; }
  mut no_early_stop 'vok=0; _ff_red=1' 'vok=0'
  mut early_run_never_checked 'if ! OVN_NEW_TESTS_TIMEOUT="${OVN_FAILFAST_TIMEOUT:-120}" ovn_run_new_tests' 'if false && ! OVN_NEW_TESTS_TIMEOUT="${OVN_FAILFAST_TIMEOUT:-120}" ovn_run_new_tests'
  mut skip_full_always '[ "${_ff_red:-0}" != 1 ] && [ -d "$wt/$pkg" ]' 'false && [ -d "$wt/$pkg" ]'
  mut flag_ignored '[ "${OVN_VERIFY_FAILFAST_OWN_TESTS:-on}" != "off" ] &&' 'true &&'
  mut wrong_timeout 'OVN_NEW_TESTS_TIMEOUT="${OVN_FAILFAST_TIMEOUT:-120}"' 'OVN_NEW_TESTS_TIMEOUT="${OVN_FAILFAST_TIMEOUT:-300}"'
  mut late_always_reruns '[ "${_ff_py_green:-0}" = 1 ] && { _late_py=""' '[ "${_ff_py_green:-0}" = 9 ] && { _late_py=""'
  mut skip_on_infra "'infra rc=|\\(shadow\\)'" "'NEVERMATCHZZ'"
  mut early_covers_gut 'ovn_run_new_tests "$wt" "${pkg:-.}" "$HOME/overnight-queue/$vp" "" ' 'ovn_run_new_tests "$wt" "${pkg:-.}" "$HOME/overnight-queue/$vp" "$HOME/godot/godot4" '
  mut red_ignored 'vok=0; _ff_red=1' '_ff_red=0'
fi
osr_summary
