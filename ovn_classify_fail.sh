#!/usr/bin/env bash
# ovn_classify_fail.sh — read an item's task_log and print a SINGLE failure-cause tag, so we stop
# lumping everything as "flailing" and can see + fix the actual pain points per higher-tier item.
#
# Usage: ovn_classify_fail.sh <task_log> <status>   -> prints one of:
#   context-exceeded | diff-not-applied | no-edit | api-mismatch | syntax-error |
#   test-red | build-red | plan-only | timeout | oversized | needs-decision | model-api-error |
#   landed | unknown
#
# Ordered most-specific-first; the FIRST signature that hits wins. Signatures are drawn from real
# aider/gate output. Keep this cheap (greps only) — it runs once per item in record_outcome.
set -uo pipefail
tl="${1:-}"; status="$(printf '%s' "${2:-}" | tr 'A-Z' 'a-z')"
[ -f "$tl" ] || { echo "unknown"; exit 0; }

# landed/expected states first (not failures)
case "$status" in
  *land*|*done*|*ok*)                 echo "landed"; exit 0;;
  *needs-decision*|*needs_decision*|*blocked*) echo "needs-decision"; exit 0;;
  *oversized*)                        echo "oversized"; exit 0;;
  # 2026-09-10: run_overnight.sh's own error_status() already correctly identified these as an
  # LLM/API-layer failure (ContextWindowExceededError/BadRequestError/APIError/RateLimitError/a
  # raw Traceback, or a non-zero aider exit) BEFORE this classifier ever runs. Trust that
  # up-front signal instead of falling through to the log-content scan below — a stack trace or
  # error dump frequently contains incidental text (the word "assert", "failing", etc.) that the
  # test-red regex matches, mislabeling a genuine infra/API hiccup as a code-quality problem.
  # Confirmed 2026-09-10: 8 of billwatch's 9 overnight "test-red" entries were actually this.
  *"error(model/api"*|*"error(exit="*) echo "model-api-error"; exit 0;;
esac

# scan the tail of the log (the last attempt's output is what matters)
buf="$(tail -c 24000 "$tl" 2>/dev/null)"
has(){ printf '%s' "$buf" | grep -qiE "$1"; }

if has 'exceed_context_size|context window|contextwindowexceeded|context size has been exceeded|context.{0,15}exceeded|context_length|prompt is too long|maximum context length|reduce the (amount|number)'; then
  echo "context-exceeded"
elif has 'searchreplacenoexactmatch|unifieddiffnomatch|did not (exactly )?match|failed to apply|no exact match|the diff (block|did not)|edit block'; then
  echo "diff-not-applied"                 # model produced a diff but it didn't apply (stale/hallucinated context lines)
elif has 'timed out|timeout|hard-killed|killed by signal|SIGTERM'; then
  echo "timeout"
elif has 'attributeerror|importerror|modulenotfounderror|has no attribute|is not defined|nameerror|cannot find name|undefined (name|variable)|no such (file|module)'; then
  echo "api-mismatch"                      # guessed a wrong path / method / import that does not exist
elif has 'syntaxerror|indentationerror|parse error|unexpected (token|indent|eof|character)|invalid syntax|SCRIPT ERROR'; then
  echo "syntax-error"                      # produced code that does not parse (auto-reverted)
elif has '[0-9]+ failed|assertionerror|assert |test.*failed|FAILED tests/|✗|failing|<failure message|expected to equal|expected \[.*\] to|to equal \[|assert_eq|assert_almost|assert_true|assert_null'; then
  echo "test-red"                          # code applied + parses, but a test failed (logic wrong OR test stale). incl. GUT/godot <failure> XML + "expected X to equal Y"
elif has 'npm run build.*exited|error during build|build failed|vite.*error|tsc.*error|error ts[0-9]'; then
  echo "build-red"                         # web/type build broke
elif has 'no changes|didn.t make any changes|nothing to commit|no edits|made no changes|only 0 (file|edit)'; then
  echo "no-edit"                           # model wrote prose/plan but produced no actual diff
elif has 'architect' && ! has 'applied edit|wrote|commit'; then
  echo "plan-only"                         # architect planned but never produced an edit
else
  echo "unknown"
fi
