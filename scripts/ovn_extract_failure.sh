#!/usr/bin/env bash
# ovn_extract_failure.sh — pull a short, GROUNDED summary of the most recent real test
# failure out of a task log. Used by both the same-cycle fix-up (Tier 2) and the
# cross-cycle lastfail memory (Tier 3). Deliberately never paraphrases: Reflexion
# (arXiv:2303.11366) found that reflection WITHOUT grounded evidence can perform WORSE
# than no reflection at all (52% vs 60% in their ablation) - this only ever surfaces
# real pytest/vitest output, verbatim, truncated to keep the injected prompt small.
#
# Usage: ovn_extract_failure.sh <task_log>
# Prints a single line (empty if nothing found).
set -uo pipefail
log="${1:-}"
[ -f "$log" ] || exit 0

# pytest: "FAILED tests/foo.py::test_bar - AssertionError: ..." plus the assert/E line
# immediately above it (pytest prints the assertion detail before the FAILED summary).
py="$(grep -B2 -E '^FAILED ' "$log" 2>/dev/null | grep -E '^(FAILED |E +|>.*assert)' | head -6)"

# vitest/jest: a failing test name line (❯) plus an assertion/expectation line.
js="$(grep -E '❯ .*\.(test|spec)\.[jt]sx?|AssertionError:|expected .* to (be|equal|deep)' "$log" 2>/dev/null | head -6)"

summary="${py:-$js}"
if [ -z "$summary" ]; then
  # fallback: last few error/failed lines in the log, still real output not a paraphrase.
  summary="$(grep -iE 'error|failed' "$log" 2>/dev/null | tail -6)"
fi
[ -z "$summary" ] && exit 0

printf '%s' "$summary" | tr '\n' ' ' | tr -s ' ' | cut -c1-500
