#!/usr/bin/env bash
# Meta-test for run_all.sh itself: is its pass/fail aggregation and exit-code
# logic correct?
#
# IMPORTANT, read before editing: run_all.sh does NOT dynamically discover
# test_*.sh files - it is a fixed, hand-maintained list of `bash test_X.sh ||
# rc=1` invocations (one per line). There is no glob/discovery step to test.
# So rather than fabricate a reimplementation of "discovery logic" that doesn't
# exist in the real script, this test extracts the REAL header (everything up
# to and including the `rc=0` init line) and REAL footer (the final `[ $rc -eq
# 0 ]... ; exit $rc` line onward) verbatim from the actual run_all.sh, and
# splices in two throwaway fake "test_*.sh" scripts (one designed to pass, one
# to fail) in place of the real 29-test body. This validates the actual
# aggregation skeleton (sequential `|| rc=1` accumulation, no short-circuiting,
# final rc-gated message + `exit $rc`) against real pass/fail/missing-file
# scripts, entirely inside a sandbox dir - it never runs the real test suite.
#
# Per task instructions: this file does not modify or touch the real
# scripts/test/run_all.sh - it only reads it.
set -uo pipefail
REAL="$(cd "$(dirname "$0")" && pwd)/run_all.sh"
[ -f "$REAL" ] || { echo "  SKIP: $REAL not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
# 2026-10-15: the sandbox run_all.sh sources lib_tmp_isolation.sh, which takes a single-flight lock under OVN_TEST_TMP_BASE (default $HOME/qtmp). When this
# suite runs INSIDE a real run_all.sh, that outer run already holds the lock, so every sandbox was refused (exit 75) and all 12 assertions failed. Give the
# sandboxes a private lock base so the meta test only tests run_all's aggregation, whoever else is running.
export OVN_TEST_TMP_BASE="$tmp/tmpbase"; mkdir -p "$OVN_TEST_TMP_BASE"

# Extract the real header (shebang/comment .. `rc=0`) and real footer
# (`[ $rc -eq 0 ] && ... exit $rc` onward), verbatim, from the production file.
HEADER="$(sed -n '1,/^rc=0$/p' "$REAL")"
# 2026-10-14: run_all's verdict is now finish() (a function defined before the test list) + `echo; finish || rc=1` / `exit $rc`; the sandbox carries both
FINISH_FN="$(sed -n '/^finish(){/,/^}/p' "$REAL")"
FOOTER="$(sed -n '/^echo; finish || rc=1$/,$p' "$REAL")"
ok "extracted a non-empty header ending in rc=0 from the real script" "[ -n \"\$HEADER\" ] && echo \"\$HEADER\" | tail -1 | grep -qx 'rc=0'"
ok "extracted a non-empty footer containing the finish verdict and the rc-gated exit line" "[ -n \"\$FOOTER\" ] && echo \"\$FOOTER\" | grep -qF 'finish || rc=1' && echo \"\$FOOTER\" | grep -qF 'exit \$rc' && [ -n \"\$FINISH_FN\" ]"

ok "sandboxes use a lock base private to this meta run (not the shared run lock)" "case \"\$OVN_TEST_TMP_BASE\" in \"\$tmp\"/*) true;; *) false;; esac"

build_sandbox() {  # $1 = body (the fake test invocation lines)
  rm -rf "$tmp/sandbox"; mkdir -p "$tmp/sandbox"
  # 2026-10-14: the real header sources its helpers from its own directory (ntfy_guard, lib_live_repo_guard, lib_tmp_isolation); the sandbox must have them
  for _h in ntfy_guard.sh lib_live_repo_guard.sh lib_tmp_isolation.sh; do cp "$(dirname "$REAL")/$_h" "$tmp/sandbox/" 2>/dev/null; done
  { echo "$HEADER"; echo "NOTRUN=0"; echo "$FINISH_FN"; echo "$1"; echo "$FOOTER"; } > "$tmp/sandbox/run_all.sh"
  chmod +x "$tmp/sandbox/run_all.sh"
}

cat > "$tmp/mk_pass.sh" <<'EOS'
mk_pass(){ cat > "$1" <<'INNER'
#!/usr/bin/env bash
echo "fake pass test ran: $(basename "$0")"
exit 0
INNER
chmod +x "$1"; }
EOS
source "$tmp/mk_pass.sh"
mk_fail(){ cat > "$1" <<'INNER'
#!/usr/bin/env bash
echo "fake fail test ran: $(basename "$0")"
exit 1
INNER
chmod +x "$1"; }

# --- A: two passing fake tests -> exit 0, ALL PASS banner, both executed ----
build_sandbox 'echo; echo "===== Fake A ====="; bash test_fake_a.sh || rc=1
echo; echo "===== Fake B ====="; bash test_fake_b.sh || rc=1'
mk_pass "$tmp/sandbox/test_fake_a.sh"
mk_pass "$tmp/sandbox/test_fake_b.sh"
OUT="$(cd "$tmp/sandbox" && bash run_all.sh)"; RC=$?
ok "all-pass sandbox: exit code 0" "[ $RC -eq 0 ]"
ok "all-pass sandbox: prints the ALL PASS banner" "echo \"$OUT\" | grep -q 'ALL QUEUE TESTS PASS'"
ok "all-pass sandbox: both fake tests actually ran" "echo \"$OUT\" | grep -q 'test_fake_a.sh' && echo \"$OUT\" | grep -q 'test_fake_b.sh'"

# --- B: one passing + one failing -> exit 1, FAILED banner, AND (critically)
#        the test AFTER the failing one still runs - `|| rc=1` must not abort
#        the script the way `set -e` / `&&`-chaining or an early `exit` would --
build_sandbox 'echo; echo "===== Fake A (fails) ====="; bash test_fake_a.sh || rc=1
echo; echo "===== Fake B (after a failure) ====="; bash test_fake_b.sh || rc=1'
mk_fail "$tmp/sandbox/test_fake_a.sh"
mk_pass "$tmp/sandbox/test_fake_b.sh"
OUT="$(cd "$tmp/sandbox" && bash run_all.sh)"; RC=$?
ok "one-fail sandbox: exit code 1" "[ $RC -eq 1 ]"
ok "one-fail sandbox: prints the SOME FAILED banner" "echo \"$OUT\" | grep -q 'SOME QUEUE TESTS FAILED'"
ok "one-fail sandbox: the test AFTER the failure still ran" "echo \"$OUT\" | grep -q 'test_fake_b.sh'"
ok "one-fail sandbox: does NOT also print the ALL PASS banner" "! echo \"$OUT\" | grep -q 'ALL QUEUE TESTS PASS'"

# --- C: a referenced test file that doesn't exist (typo'd/deleted) is treated
#        as a failure too (bash's own nonzero exit trips `|| rc=1`), not
#        silently ignored ------------------------------------------------------
build_sandbox 'echo; echo "===== Missing ====="; bash test_does_not_exist.sh || rc=1
echo; echo "===== Fake A (still runs) ====="; bash test_fake_a.sh || rc=1'
mk_pass "$tmp/sandbox/test_fake_a.sh"
OUT="$(cd "$tmp/sandbox" && bash run_all.sh)"; RC=$?
ok "missing test file sandbox: exit code 1" "[ $RC -eq 1 ]"
ok "missing test file sandbox: prints the SOME FAILED banner" "echo \"$OUT\" | grep -q 'SOME QUEUE TESTS FAILED'"
ok "missing test file sandbox: the next test still ran despite the missing one" "echo \"$OUT\" | grep -q 'test_fake_a.sh'"

# --- D: two failing fake tests -> still just one clean exit 1 (not a crash,
#        not exit 2+), i.e. multiple failures don't compound the exit code ---
build_sandbox 'echo; echo "===== Fake A (fails) ====="; bash test_fake_a.sh || rc=1
echo; echo "===== Fake B (also fails) ====="; bash test_fake_b.sh || rc=1'
mk_fail "$tmp/sandbox/test_fake_a.sh"
mk_fail "$tmp/sandbox/test_fake_b.sh"
OUT="$(cd "$tmp/sandbox" && bash run_all.sh)"; RC=$?
ok "two-fail sandbox: exit code is exactly 1, not compounded" "[ $RC -eq 1 ]"

# --- E: finish() must hold no test invocations: a suite placed inside it (after its rc check) let a failure print the green banner (2026-10-15)
ok "finish() contains no bash test_ invocations (suites run before the verdict)" "[ \"\$(echo \"\$FINISH_FN\" | grep -c 'bash test_')\" -eq 0 ]"

# --- F: mutant - a failing suite injected inside finish() after its NOT VERIFIED check (the old suite position),  must NOT print ALL PASS and must exit 1 (old code: prints it)
SAVED_FN="$FINISH_FN"
FINISH_FN="$(echo "$SAVED_FN" | awk '{ print } /NOT VERIFIED/ { print "  bash test_fake_a.sh || rc=1" }')"
build_sandbox 'echo; echo "===== Fake A (fails, inside finish) ====="; true'
FINISH_FN="$SAVED_FN"
mk_fail "$tmp/sandbox/test_fake_a.sh"
OUT="$(cd "$tmp/sandbox" && bash run_all.sh)"; RC=$?
ok "finish mutant: a failing suite inside finish() gives exit code 1" "[ $RC -eq 1 ]"
ok "finish mutant: a failing suite inside finish() does NOT print the ALL PASS banner" "! echo \"$OUT\" | grep -q 'ALL QUEUE TESTS PASS'"
ok "finish mutant: the failure banner is printed instead" "echo \"$OUT\" | grep -q 'SOME QUEUE TESTS FAILED'"

rm -rf "$tmp"
echo "run_all_meta: $P passed, $F failed"
[ "$F" -eq 0 ]

# --- OBSERVATION (not a bug, just a note for whoever wires new tests in) ----
# run_all.sh has no dynamic `for f in test_*.sh` discovery loop - every test is
# a hand-written `bash test_X.sh || rc=1` line, and it also never counts total
# pass/fail *tests* across suites (only a binary rc flag: did anything fail,
# yes/no). New test files must be manually added as a new line, and "N passed,
# M failed" in the final banner is per-suite (each sub-test prints its own),
# not aggregated by run_all.sh itself.
