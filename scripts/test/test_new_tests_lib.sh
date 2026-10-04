#!/usr/bin/env bash
# Tests for scripts/lib_new_tests.sh (stage runner step H: explicitly run the cycle's new/changed test files). Fake pytest/godot shims + temp git repo;
# one real-pytest pair when python3 has pytest. Every RED case has a benign control; infra trouble must PROCEED (return 0).
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
source "$ROOT/scripts/lib_gut_xml.sh"; source "$ROOT/scripts/lib_new_tests.sh"
G(){ git -C "$W" -c user.name=t -c user.email=t@t "$@"; }
newrepo(){ W="$T/w$RANDOM"; mkdir -p "$W/iptv-backend/tests" "$W/addons/gut"; git -C "$W" init -q; touch "$W/project.godot" "$W/addons/gut/gut_cmdln.gd"
  echo 'def test_x():
    assert 1' > "$W/iptv-backend/tests/test_old.py"; G add -A >/dev/null; G commit -q -m base; BASE="$(G rev-parse HEAD)"; LOG="$T/log.$RANDOM"; : > "$LOG"; rm -f "$T/args"; }
cat > "$T/fakepytest" <<'EOS'
#!/usr/bin/env bash
echo "$PWD :: $*" >> "$FAKE_ARGS"; exit "${FAKE_RC:-0}"
EOS
cat > "$T/fakegodot" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -gjunit_xml_file=*) x="${a#-gjunit_xml_file=}";; -gtest=*) echo "${a#-gtest=}" >> "$FAKE_ARGS";; esac; done
case "${GODOT_MODE:-green}" in
  green) printf '<testsuites failures="0" tests="1"><testsuite name="t" failures="0"></testsuite></testsuites>\n' > "$x";;
  red)   printf '<testsuites failures="1" tests="1"><testsuite name="t" failures="1"><testcase name="a"><failure/></testcase></testsuite></testsuites>\n' > "$x";;
  none)  : ;;
  parse) printf '<testsuites failures="0" tests="1"></testsuites>\n' > "$x"; echo "Parse Error: bad" ;;
esac
exit 0
EOS
chmod +x "$T/fakepytest" "$T/fakegodot"; export FAKE_ARGS="$T/args"
PYT="$T/fakepytest"; GOD="$T/fakegodot"

newrepo; echo 'def test_n():
    assert 1' > "$W/iptv-backend/app_test_ghost.py"; mkdir -p "$W/iptv-backend/app/svc"; echo 'def test_n():
    assert 1' > "$W/iptv-backend/app/svc/test_new.py"; echo "x=1" > "$W/iptv-backend/app/svc/plain.py"
ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "BENIGN green: new python tests (untracked) are run explicitly, rc 0" "$([ "$rc" = 0 ] && grep -q 'app/svc/test_new.py' "$FAKE_ARGS" && echo 1 || echo 0)"
ok "pytest is run from the package dir with paths relative to it, and ONLY the new/changed test files" "$(grep -q "iptv-backend :: -q -o addopts= -p no:cacheprovider.*app/svc/test_new.py" "$FAKE_ARGS" && ! grep -q 'plain.py\|test_old' "$FAKE_ARGS" && echo 1 || echo 0)"
FAKE_RC=1 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "NEGATIVE: failing new test (pytest rc=1) => returns 1 and logs NEW-TESTS RED" "$([ "$rc" = 1 ] && grep -q 'NEW-TESTS RED' "$LOG" && echo 1 || echo 0)"
FAKE_RC=2 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; ok "NEGATIVE: collection error (rc=2) => red" "$([ $? = 1 ] && echo 1 || echo 0)"
for r in 3 4 124 127; do FAKE_RC=$r ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; ok "INFRA: pytest rc=$r (internal/usage/timeout/missing) => PROCEED (0)" "$([ $? = 0 ] && echo 1 || echo 0)"; done
FAKE_RC=5 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; ok "BENIGN: rc=5 (nothing collected in a file) => 0" "$([ $? = 0 ] && echo 1 || echo 0)"
rm -f "$FAKE_ARGS"; OVN_RUN_NEW_TESTS=off FAKE_RC=1 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "kill switch OVN_RUN_NEW_TESTS=off => no run, rc 0" "$([ "$rc" = 0 ] && [ ! -f "$FAKE_ARGS" ] && echo 1 || echo 0)"
ovn_run_new_tests "$W" iptv-backend "$T/nonexistent-pytest" "" "$BASE" "$LOG"; ok "INFRA: pytest binary missing => PROCEED" "$([ $? = 0 ] && echo 1 || echo 0)"
ovn_run_new_tests "$T/no-such-dir" . "$PYT" "" "$BASE" "$LOG"; ok "INFRA: worktree missing => PROCEED" "$([ $? = 0 ] && echo 1 || echo 0)"

newrepo; echo "y=2" > "$W/iptv-backend/plain.py"; echo "# not a test" > "$W/README.md"
rm -f "$FAKE_ARGS"; FAKE_RC=1 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "BENIGN: cycle changed no test file => pytest not invoked, rc 0 (even if it would fail)" "$([ "$rc" = 0 ] && [ ! -f "$FAKE_ARGS" ] && echo 1 || echo 0)"
newrepo; echo 'def test_x():
    assert 2' > "$W/iptv-backend/tests/test_old.py"; rm -f "$FAKE_ARGS"
FAKE_RC=1 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "NEGATIVE: a MODIFIED existing test file is also re-run explicitly (red => 1)" "$([ "$rc" = 1 ] && grep -q 'tests/test_old.py' "$FAKE_ARGS" && echo 1 || echo 0)"
newrepo; mkdir -p "$W/addons/gut" "$W/vendor"; echo 'def test_v():
    assert 1' > "$W/addons/gut/test_vendor.py"; rm -f "$FAKE_ARGS"
FAKE_RC=1 ovn_run_new_tests "$W" . "$PYT" "" "$BASE" "$LOG"; ok "BENIGN: vendored addons/ test files are never run" "$([ $? = 0 ] && [ ! -f "$FAKE_ARGS" ] && echo 1 || echo 0)"
newrepo; echo 'def test_n():
    assert 1' > "$W/other_test.py"; rm -f "$FAKE_ARGS"; ovn_run_new_tests "$W" . "$PYT" "" "$BASE" "$LOG"
ok "pkg '.' (repo-root python project): *_test.py file passed by repo-relative path" "$(grep -q ':: .*other_test.py' "$FAKE_ARGS" && echo 1 || echo 0)"

newrepo; G mv iptv-backend/tests/test_old.py iptv-backend/tests/test_renamed.py; rm -f "$FAKE_ARGS"
FAKE_RC=1 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "REVIEW FIX NEGATIVE: a RENAMED test file (git status R) is run explicitly (red => 1)" "$([ "$rc" = 1 ] && grep -q 'tests/test_renamed.py' "$FAKE_ARGS" && echo 1 || echo 0)"
newrepo; mkdir -p "$W/iptv-backend/tests"; echo 'def test_s():
    assert 1' > "$W/iptv-backend/tests/test_with space.py"; rm -f "$FAKE_ARGS"
FAKE_RC=0 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "BENIGN: a test file name with a space is passed as ONE argument (no word-splitting)" "$([ "$rc" = 0 ] && grep -q 'tests/test_with space.py' "$FAKE_ARGS" && echo 1 || echo 0)"
newrepo; G rm -q iptv-backend/tests/test_old.py; rm -f "$FAKE_ARGS"
FAKE_RC=1 ovn_run_new_tests "$W" iptv-backend "$PYT" "" "$BASE" "$LOG"; rc=$?
ok "BENIGN: a DELETED test file is not run (rc 0, pytest not invoked)" "$([ "$rc" = 0 ] && [ ! -f "$FAKE_ARGS" ] && echo 1 || echo 0)"

# ---- GUT ----
GUTOK='extends GutTest

func test_a():
	assert_true(true)
'
newrepo; mkdir -p "$W/tests/battle" "$W/test/battle"; printf '%s' "$GUTOK" > "$W/tests/battle/test_new.gd"; printf '%s' "$GUTOK" > "$W/test/battle/aoe_test.gd"
printf 'extends Node\nfunc test_z():\n\tpass\n' > "$W/tests/test_notgut.gd"; rm -f "$FAKE_ARGS"
GODOT_MODE=green ovn_run_new_tests "$W" . "" "$GOD" "$BASE" "$LOG"; rc=$?
ok "BENIGN GUT: new GUT tests are run via explicit -gtest (incl. test/ and subdir ones), non-GutTest file skipped, green => 0" "$([ "$rc" = 0 ] && grep -q 'res://tests/battle/test_new.gd' "$FAKE_ARGS" && grep -q 'res://test/battle/aoe_test.gd' "$FAKE_ARGS" && ! grep -q notgut "$FAKE_ARGS" && echo 1 || echo 0)"
GODOT_MODE=red ovn_run_new_tests "$W" . "" "$GOD" "$BASE" "$LOG"; rc=$?
ok "NEGATIVE GUT: failing new test => 1 + NEW-TESTS RED" "$([ "$rc" = 1 ] && grep -q 'NEW-TESTS RED: explicit GUT' "$LOG" && echo 1 || echo 0)"
GODOT_MODE=parse ovn_run_new_tests "$W" . "" "$GOD" "$BASE" "$LOG"; ok "NEGATIVE GUT: parse error in a new test => red" "$([ $? = 1 ] && echo 1 || echo 0)"
GODOT_MODE=none ovn_run_new_tests "$W" . "" "$GOD" "$BASE" "$LOG"; ok "INFRA GUT: no junit xml => PROCEED" "$([ $? = 0 ] && echo 1 || echo 0)"
ovn_run_new_tests "$W" . "" "$T/no-godot" "$BASE" "$LOG"; ok "INFRA GUT: godot binary missing => PROCEED" "$([ $? = 0 ] && echo 1 || echo 0)"

# ---- real pytest (only when available) ----
if python3 -c 'import pytest' >/dev/null 2>&1; then
  printf '#!/usr/bin/env bash\nexec python3 -m pytest "$@"\n' > "$T/realpytest"; chmod +x "$T/realpytest"
  newrepo; echo 'def test_pass():
    assert 1 == 1' > "$W/iptv-backend/test_real_ok.py"
  ovn_run_new_tests "$W" iptv-backend "$T/realpytest" "" "$BASE" "$LOG"; ok "REAL pytest BENIGN: passing new test file => 0" "$([ $? = 0 ] && echo 1 || echo 0)"
  echo 'def test_fail():
    assert 1 == 2' > "$W/iptv-backend/test_real_bad.py"
  ovn_run_new_tests "$W" iptv-backend "$T/realpytest" "" "$BASE" "$LOG"; ok "REAL pytest NEGATIVE: failing new test file => 1" "$([ $? = 1 ] && echo 1 || echo 0)"
else echo "  skip real pytest cases (python3 has no pytest)"; fi
# ---- (C) GUT -ginclude_subdirs wiring: default ON at all three call sites, OVN_GUT_SUBDIRS=off kill switch ----
for f in branch_hygiene.sh ovn_stage_runner.sh ovn_test_watch.sh; do
  ok "$f: GUT command carries \$GUT_SUBDIRS after -gdir=res://tests" "$(grep -q 'gdir=res://tests \$GUT_SUBDIRS -gexit' "$ROOT/$f" && echo 1 || echo 0)"
  v="$(OVN_GUT_SUBDIRS= bash -c 'eval "$(grep -E "^GUT_SUBDIRS=" "'"$ROOT/$f"'")"; echo "[$GUT_SUBDIRS]"')"
  ok "$f: default flag is -ginclude_subdirs" "$([ "$v" = "[-ginclude_subdirs]" ] && echo 1 || echo 0)"
  v="$(OVN_GUT_SUBDIRS=off bash -c 'eval "$(grep -E "^GUT_SUBDIRS=" "'"$ROOT/$f"'")"; echo "[$GUT_SUBDIRS]"')"
  ok "$f: OVN_GUT_SUBDIRS=off empties the flag (kill switch)" "$([ "$v" = "[]" ] && echo 1 || echo 0)"
done
ok "stage runner calls ovn_run_new_tests behind OVN_RUN_NEW_TESTS and sources the lib" "$(grep -q 'source scripts/lib_new_tests.sh' "$ROOT/ovn_stage_runner.sh" && grep -q 'OVN_RUN_NEW_TESTS:-on' "$ROOT/ovn_stage_runner.sh" && grep -q 'ovn_run_new_tests "\$wt"' "$ROOT/ovn_stage_runner.sh" && echo 1 || echo 0)"
echo; echo "new-tests lib tests: $pass passed, $fail failed"; [ "$fail" = 0 ]
