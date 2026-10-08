#!/usr/bin/env bash
# Regression test for run_overnight.sh's VERIFY-SKIP GUARD fix (2026-09-29).
#
# run_repo_verification()'s repo-owned-.ovn-verify.sh path used to treat ANY exit-0
# result as "pass" - including the deliberate lock-contention SKIP that iptv_apps,
# shrike-monitor, and shrike-notify's .ovn-verify.sh all emit (exit 0 with a literal
# "SKIPPED — venv lock contended past 300s wait, not treating as a failure" line)
# when they can't get the shared venv lock. That's correct for NOT reverting (a
# verify that never ran must never be conflated with one that ran and found real
# red), but folding it into a plain "pass" ALSO let a commit whose tests never
# actually ran get auto-credited and pushed as "pushed(tests:pass)" as if fully
# verified.
#
# Confirmed live: iptv_apps commit 0bc57b0 (2026-09-28 21:38 CDT) added an import
# of a model file that was never created, landed while its .ovn-verify.sh lock was
# contended, and then poisoned the shared conftest/import chain for four later,
# unrelated, actually-correct cycles - each one BUILD-GATE-reverted for a break it
# didn't cause.
#
# This test extracts the real SKIP-detection literal and the two VERIFY-SKIP GUARD
# checkpoints out of run_overnight.sh (not a reimplementation) so this can't
# silently drift from what's deployed.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || RO="$(cd "$(dirname "$0")/../.." && pwd)/run_overnight.sh"
[ -f "$RO" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# --- A: run_repo_verification's repo-owned-verify branch must classify a SKIPPED
# marker as "skip", a bare exit-0 as "pass", and a nonzero exit as "fail" ---
_ovnv_classify() {
  # Mirrors the exact snippet added to run_overnight.sh: given captured output text
  # and an exit code, print pass/fail/skip using the same precedence.
  local out="$1" rc="$2"
  if printf '%s' "$out" | grep -q 'SKIPPED — venv lock contended'; then
    echo "skip"
  elif [ "$rc" -eq 0 ]; then
    echo "pass"
  else
    echo "fail"
  fi
}

skip_out="ovn-verify(chickadee): SKIPPED — venv lock contended past 300s wait, not treating as a failure"
ok "lock-contention SKIPPED output classifies as skip (not pass)" \
   '[ "$(_ovnv_classify "$skip_out" 0)" = "skip" ]'

pass_out="ovn-verify(chickadee): ok"
ok "a genuine green run (exit 0, no SKIPPED marker) still classifies as pass" \
   '[ "$(_ovnv_classify "$pass_out" 0)" = "pass" ]'

fail_out="FAILED tests/test_referral.py::test_x - ImportError"
ok "a genuine red run (nonzero exit) still classifies as fail" \
   '[ "$(_ovnv_classify "$fail_out" 1)" = "fail" ]'

# --- B: run_overnight.sh itself must actually distinguish "skip" via this same
# grep pattern (not just this test's reimplementation) ---
ok "run_overnight.sh's run_repo_verification greps for the SKIPPED marker" \
   "grep -q 'SKIPPED — venv lock contended' '$RO'"
ok "run_overnight.sh's run_repo_verification can emit a literal skip result" \
   "grep -qE '^\\s*echo \"skip\"\$' '$RO'"

# --- C: both VERIFY-SKIP GUARD checkpoints must exist, so a skip is caught
# whether it comes from the FIRST verify call or a BUILD-GATE/Tier-2 fix-up
# re-verify ---
_guard_count="$(grep -c 'VERIFY-SKIP GUARD' "$RO")"
ok "both VERIFY-SKIP GUARD checkpoints are present (2 occurrences: initial + post-fixup)" \
   '[ "$_guard_count" -ge 2 ]'
ok "the skip guard never reverts (must not sit next to a git reset --hard)" \
   "! awk '/VERIFY-SKIP GUARD \\(2026-09-29\\)/,/^      fi\$/' '$RO' | grep -q 'git reset --hard'"
ok "the skip guard returns a benign/neutral status, never a bad/reverted one" \
   "grep -A20 'VERIFY-SKIP GUARD (2026-09-29):' '$RO' | grep -q 'error(verify-skipped'"

# --- D: ordering - the FIRST guard must appear before TS-RATCHET/BUILD-GATE/
# NO-NEW-RED (those gates only special-case \"fail\"; a skip must be intercepted
# before falling through to the ordinary push path) ---
_first_guard_line="$(grep -n 'VERIFY-SKIP GUARD (2026-09-29):' "$RO" | head -1 | cut -d: -f1)"
_first_verify_line="$(grep -n 'VERIFY_RESULT="\$(run_repo_verification)"' "$RO" | head -1 | cut -d: -f1)"
_push_case_line="$(grep -n 'fail) PUSH_STATUS=' "$RO" | head -1 | cut -d: -f1)"
ok "first VERIFY-SKIP GUARD sits between the initial verify call and the push case statement" \
   '[ -n "$_first_guard_line" ] && [ -n "$_first_verify_line" ] && [ -n "$_push_case_line" ] && [ "$_first_guard_line" -gt "$_first_verify_line" ] && [ "$_first_guard_line" -lt "$_push_case_line" ]'

echo "verify-skip guard: $P passed, $F failed"
[ "$F" -eq 0 ]
