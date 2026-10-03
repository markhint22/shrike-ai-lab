#!/usr/bin/env bash
# lib_fixup.sh - cause-aware direction for the Tier-2 fix-up (2026-10-01, feedback-loops analysis).
# The old prompt always said "prefer fixing the TEST's expectation, do not change the source unless clearly the bug". That is right for a test the
# model JUST ADDED, and exactly backwards for a test that PASSED before the change: there the model's own source edit broke existing behaviour
# (230 NO-NEW-RED 'source broke a previously-green test' cases in 14 days; the fix-up rescued 3).
#   ovn_fixup_kind <failure-summary> <newline-separated list of test files ADDED by the red commit>
#     -> prints "own-test"  when the failure names one of the added test files (the model's new test is wrong or mis-mocked)
#     -> prints "source-broke-green" otherwise (no new tests, or the failing test is an older one)
ovn_fixup_kind() {
  local summary="${1:-}" newtests="${2:-}" nt base
  while IFS= read -r nt; do
    [ -n "$nt" ] || continue
    base="$(basename "$nt")"
    case "$summary" in *"$base"*) echo "own-test"; return 0;; esac
  done <<< "$newtests"
  echo "source-broke-green"
}
# ovn_fixup_direction <kind> -> the sentence appended to the fix-up prompt
ovn_fixup_direction() {
  case "${1:-}" in
    own-test) echo "The failing test is one that the committed change just added: prefer fixing the TEST's expectation/mocks to match the real behaviour of the source shown; do not change the source unless it is clearly the bug." ;;
    *) echo "This failing test PASSED before the committed change, so that change broke existing behaviour. Fix the SOURCE change so the existing test passes again (restore the old behaviour). Only edit that existing test if the item text explicitly says this behaviour must change." ;;
  esac
}
