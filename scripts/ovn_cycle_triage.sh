#!/usr/bin/env bash
# Per-cycle triage line (2026-08-28): record WHY each cycle ended the way it did —
# item attempted, implement attempts, whether it timed out, the scoped-test signal,
# context overflow, and the final outcome — into state/cycle_triage.log, so tuning
# is data-driven instead of guesswork.
# args: <repo_dir> <status> <task_log> <state_dir> <id>
set -uo pipefail
repo="${1:-}"; status="${2:-}"; tasklog="${3:-}"; state="${4:-}"; id="${5:-}"
[ -n "$state" ] && [ -n "$tasklog" ] || exit 0
log="$state/cycle_triage.log"
prog="$repo/OVERNIGHT_PROGRESS.md"

item="$(grep -viE 'HUMAN-ONLY|AUTO-SKIP' "$prog" 2>/dev/null | grep -m1 -E '^- \[ \]' | sed -E 's/^- \[ \] //; s/[`*]//g' | cut -c1-64)"
attempts="$(grep -c 'implement attempt' "$tasklog" 2>/dev/null || echo 0)"
flags=""
grep -qE 'exit=124|timed out|Killed|hard-killed' "$tasklog" 2>/dev/null && flags="${flags}TIMEOUT "
grep -qE 'ContextWindowExceeded' "$tasklog" 2>/dev/null && flags="${flags}CTX-OVERFLOW "
grep -qE 'UnifiedDiffNoMatch|did not conform to edit format|SearchReplaceNoExactMatch' "$tasklog" 2>/dev/null && flags="${flags}EDIT-FORMAT "
grep -qE 'Parse Error|Failed to load script|SyntaxError|IndentationError' "$tasklog" 2>/dev/null && flags="${flags}PARSE-ERR "
# last scoped-test signal
verdict="$(grep -hoiE "VERDICT:[[:space:]]*(PROCEED|ALREADY-DONE|BLOCKED|NEEDS-DECISION)" "$tasklog" 2>/dev/null | head -1 | sed -E "s/.*VERDICT:[[:space:]]*//I" | tr a-z A-Z)"
plan="$(grep -hoiE "PLAN:[[:space:]]*.+" "$tasklog" 2>/dev/null | head -1 | sed -E "s/^PLAN:[[:space:]]*//I; s/[[:space:]]*FILES:.*//I" | cut -c1-60)"
tsig="$(grep -hoE 'Tests[[:space:]]+[0-9]+ (passed|failed)|[0-9]+ passed[^,|]*|[0-9]+ failed' "$tasklog" 2>/dev/null | tail -1 | tr -s ' ')"

printf '%s | %-22s | %-26s | tries=%s | %-22s | verdict=%-13s | tests:[%s] | item="%s" | plan="%s"\n' \
  "$(date '+%F %H:%M')" "$id" "$status" "${attempts:-0}" "${flags:-clean}" "${verdict:-?}" "${tsig:-none}" "${item:-<none>}" "${plan:-}" \
  >> "$log" 2>/dev/null || true
exit 0
