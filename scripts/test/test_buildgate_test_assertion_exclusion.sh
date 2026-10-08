#!/usr/bin/env bash
# Regression test for run_overnight.sh's BUILD-GATE test-assertion exclusion fix
# (2026-09-29). Before this, a plain Gradle unit-test AssertionError (the code
# compiled fine, a test just asserted wrong) was swept into the harsher BUILD-GATE
# revert path because Gradle's generic "FAILURE: Build failed with an exception."
# banner - printed for EVERY failing `gradlew test` invocation, compile break or
# not - matched the "Build failed" POS-regex token meant for genuine structural
# breaks. Confirmed live 2026-09-28 22:45 CDT: billwatch's
# LegislatorsViewModelTest.kt java.lang.AssertionError at line 147 got reverted via
# BUILD-GATE with zero compile-specific signal in the log, and the blind fix-up
# round burned a full aider call hunting for a "structural" issue that never
# existed. Mirrors the deployed POS/NEG regex + new "tests completed" guard
# exactly so this can't drift.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

grep -q "tests? completed," "$RO" || { echo "  FAIL: 'tests completed' guard not found in $RO"; exit 1; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed BUILD-GATE trigger condition exactly
_BUILD_BREAK_POS_RE="SyntaxError|IndentationError|invalid syntax|ImportError while loading|cannot import name|ERROR collecting|errors during collection|SCRIPT ERROR|Parse Error|ERROR: Failed to load|Cannot find module|error TS[0-9]|Build failed|Compilation error|compile[A-Za-z]*Kotlin FAILED|compile[A-Za-z]*JavaWithJavac FAILED"
_BUILD_BREAK_NEG_RE="has no resource loaders|Cannot call method '[^']*' on a null value|AudioStreamOggVorbis|base object of type '[A-Za-z_][A-Za-z0-9_]*'|Attempted to free a RefCounted|Parameter .* is null"

is_build_gate_triggered(){ # $1=task_log
  local tests_ran=0
  grep -qE '[0-9]+ tests? completed,' "$1" && tests_ran=1
  if [ "$tests_ran" = "1" ]; then
    return 1
  fi
  grep -E "$_BUILD_BREAK_POS_RE" "$1" | grep -vE "$_BUILD_BREAK_NEG_RE" | grep -q .
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ---- 1. real-shaped case confirmed live: plain test-ASSERTION failure, only the
#      generic Gradle banner as a POS signal, no compile-specific diagnostic ----
log="$tmp/task_log_assertion_only.log"
cat > "$log" <<EOF
> Task :app:testDebugUnitTest

com.billwatch.app.ui.screens.LegislatorsViewModelTest > toggleFollowLegislator calls unfollowLegislator when id already followed FAILED
    java.lang.AssertionError at LegislatorsViewModelTest.kt:147

93 tests completed, 1 failed

> Task :app:testDebugUnitTest FAILED

FAILURE: Build failed with an exception.
* What went wrong:
Execution failed for task ':app:testDebugUnitTest'.
> There were failing tests. See the report at: file:///x/index.html

BUILD FAILED in 7s
EOF
if is_build_gate_triggered "$log"; then r=1; else r=0; fi
ok "plain test-assertion failure (tests ran to completion) does NOT trigger BUILD-GATE" "[ $r -eq 0 ]"

# ---- 2. real compile break MUST still trigger BUILD-GATE (no regression) ----
log="$tmp/task_log_compile_break.log"
cat > "$log" <<EOF
> Task :app:compileDebugUnitTestKotlin FAILED
e: file:///x/LegislatorsViewModelTest.kt:153:13 No parameter with name 'id' found.
FAILURE: Build failed with an exception.
> Compilation error. See log for more details
BUILD FAILED in 4s
EOF
if is_build_gate_triggered "$log"; then r=1; else r=0; fi
ok "real Kotlin compile break (no tests ran) STILL triggers BUILD-GATE" "[ $r -eq 1 ]"

# ---- 3. Python collection error (no test-completion line) still triggers BUILD-GATE ----
log="$tmp/task_log_python_import.log"
cat > "$log" <<EOF
_____________ ERROR collecting tests/test_bill_summary_service.py ______________
ImportError while importing test module '/x/tests/test_bill_summary_service.py'.
EOF
if is_build_gate_triggered "$log"; then r=1; else r=0; fi
ok "Python import-collection error still triggers BUILD-GATE" "[ $r -eq 1 ]"

# ---- 4. pytest run with real assertion failures (not Gradle) is unaffected either way
#      (no "Build failed"-shaped token present at all) ----
log="$tmp/task_log_pytest_assertion.log"
cat > "$log" <<EOF
FAILED tests/test_foo.py::test_bar - AssertionError: assert 1 == 2
1 failed, 20 passed in 0.42s
EOF
if is_build_gate_triggered "$log"; then r=1; else r=0; fi
ok "pytest assertion failure (no build-break token) does not trigger BUILD-GATE" "[ $r -eq 0 ]"

echo "buildgate test-assertion exclusion: $P passed, $F failed"
[ "$F" -eq 0 ]
