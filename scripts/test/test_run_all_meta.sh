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
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"

# Extract the real header (shebang/comment .. `rc=0`) and real footer
# (`[ $rc -eq 0 ] && ... exit $rc` onward), verbatim, from the production file.
HEADER="$(sed -n '1,/^rc=0$/p' "$REAL")"
FOOTER="$(sed -n '/\[ \$rc -eq 0 \]/,$p' "$REAL")"
ok "extracted a non-empty header ending in rc=0 from the real script" "[ -n \"\$HEADER\" ] && echo \"\$HEADER\" | tail -1 | grep -qx 'rc=0'"
ok "extracted a non-empty footer containing the rc-gated exit line" "[ -n \"\$FOOTER\" ] && echo \"\$FOOTER\" | grep -qF 'rc -eq 0'"

build_sandbox() {  # $1 = body (the fake test invocation lines)
  rm -rf "$tmp/sandbox"; mkdir -p "$tmp/sandbox"
  { echo "$HEADER"; echo "$1"; echo "$FOOTER"; } > "$tmp/sandbox/run_all.sh"
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
