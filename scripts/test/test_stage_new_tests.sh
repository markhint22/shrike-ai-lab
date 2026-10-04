#!/usr/bin/env bash
# test_stage_new_tests.sh - the REAL ovn_stage_runner.sh end to end (lib_osr_fixture.sh) with scripts/lib_new_tests.sh INSTALLED (the older
# stage-runner harnesses never copied the lib, so they could not see the 2026-10-04 "run the cycle's new test files" step). Review fixture for QA h13:
#   green step unchanged / new test red -> unverified, not pushed / kill switch / pytest binary missing / GUT new test red / renamed + space names.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
V(){ grep -qF -- "$1" <<<"$VL"; }
vl(){ VL="$(osr_vlog)"; }
pushed(){ git -C "$O" log --format=%s overnight/feature | grep -q 'staged step 0'; }
base(){ osr_new; osr_venv backend; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0

echo "== python: normal green step is unchanged"
base
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "green: verified" G "independent full-verify: PASSED"
t "green: pushed" pushed
t "green: the full suite ran once WITHOUT file args and the new test file was ALSO run explicitly (from the package dir)" \
  bash -c "grep -c ':: -q -o addopts= -p no:cacheprovider\$' '$T/scn/pytest.calls' | grep -q '^1\$' && grep -q 'backend :: -q -o addopts= -p no:cacheprovider tests/test_foo.py' '$T/scn/pytest.calls'"
t "green: log records the explicit run" V "new/changed python tests (explicit run): tests/test_foo.py"
osr_cleanup

echo "== python: new test red ONLY when run explicitly -> unverified, never pushed"
base; echo "failfile:tests/test_foo.py" > "$T/scn/pytest.mode"
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "red new test: NOT verified" G "independent full-verify: FAILED"
t "red new test: NOT pushed" bash -c "! git -C '$O' log --format=%s overnight/feature | grep -q 'staged step 0'"
t "red new test: verify log says NEW-TESTS RED" V "NEW-TESTS RED"
osr_cleanup
base; echo "failfile:tests/test_foo.py" > "$T/scn/pytest.mode"
OVN_RUN_NEW_TESTS=off osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "kill switch OVN_RUN_NEW_TESTS=off: same red-only-explicit file lands as before" G "independent full-verify: PASSED"
t "kill switch: pushed" pushed
t "kill switch: no explicit run happened" bash -c "! grep -q 'tests/test_foo.py' '$T/scn/pytest.calls'"
osr_cleanup

echo "== python: no venv pytest at all (fail-closed disabled) -> helper cannot run, must PROCEED"
osr_new; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
OVN_VERIFY_FAIL_CLOSED=0 osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "no pytest binary: verified (new-tests step is infra => proceed)" G "independent full-verify: PASSED"
t "no pytest binary: pushed" pushed
osr_cleanup

echo "== python: a RENAMED test file and a name with a space"
base
osr_aider 1 'mkdir -p backend/app backend/tests
printf "def foo():\n    return 1\n" > backend/app/foo.py
git mv backend/tests/test_svc.py backend/tests/test_svc_renamed.py
printf "from app.foo import foo\n\ndef test_foo():\n    assert foo() == 1\n" > "backend/tests/test_foo bar.py"
echo "Applied edit to backend/app/foo.py"'
echo "failfile:test_svc_renamed.py" > "$T/scn/pytest.mode"
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "renamed test file is run explicitly (and red => unverified)" V "NEW-TESTS RED"
t "space-named test file reached pytest as one argument" bash -c "grep -q 'test_foo bar.py' '$T/scn/pytest.calls'"
osr_cleanup

echo "== GUT: new GutTest file"
GUT_SNIP='mkdir -p tests
printf "extends GutTest\n\nfunc test_a():\n\tassert_true(true)\n" > tests/test_newgut.gd
printf "def foo():\n    return 1\n" > backend/app/foo.py
printf "from app.foo import foo\n\ndef test_foo():\n    assert foo() == 1\n" > backend/tests/test_foo.py'
base; osr_tracked addons/gut/gut_cmdln.gd 'extends SceneTree\n'; osr_godot ok; osr_aider 1 "$GUT_SNIP"
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "GUT green: verified + pushed" bash -c "grep -q 'independent full-verify: PASSED' '$T/out.txt'"
t "GUT green: the new GUT file went through -gtest" bash -c "grep -q 'gtest=res://tests/test_newgut.gd' '$T/scn/godot.calls'"
t "GUT green: full GUT run carries -ginclude_subdirs" bash -c "grep -q 'gdir=res://tests -ginclude_subdirs' '$T/scn/godot.calls'"
osr_cleanup
base; osr_tracked addons/gut/gut_cmdln.gd 'extends SceneTree\n'; osr_godot failnew; osr_aider 1 "$GUT_SNIP"
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "GUT new test red only on explicit run: unverified" G "independent full-verify: FAILED"
t "GUT new test red: verify log says NEW-TESTS RED" V "NEW-TESTS RED"
osr_cleanup
base; osr_tracked addons/gut/gut_cmdln.gd 'extends SceneTree\n'; osr_godot failnew; osr_aider 1 "$GUT_SNIP"
OVN_GUT_SUBDIRS=off osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "OVN_GUT_SUBDIRS=off: the full GUT run has no -ginclude_subdirs" bash -c "grep -q 'gdir=res://tests -gexit' '$T/scn/godot.calls' && ! grep -q 'include_subdirs' '$T/scn/godot.calls'"
osr_cleanup
base; osr_tracked addons/gut/gut_cmdln.gd 'extends SceneTree\n'; osr_godot failnew; osr_aider 1 "$GUT_SNIP"
rm -f "$H/godot/godot4.keep"; OVN_RUN_NEW_TESTS=off osr_run "$OSR_REPO" "$ITEM_PY"
t "GUT red-only-explicit + kill switch: lands as before" G "independent full-verify: PASSED"
osr_cleanup

osr_summary
