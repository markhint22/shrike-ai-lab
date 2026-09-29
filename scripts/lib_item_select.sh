#!/usr/bin/env bash
# scripts/lib_item_select.sh — shared "which item did this cycle actually work on" resolver.
#
# 2026-09-28 ROOT CAUSE: every "find the real top item" selector in this pipeline
# (ovn_item_guard.sh's own cap-tracking selector, run_overnight.sh's record_outcome()
# item_hash, and several others) independently re-grepped OVERNIGHT_PROGRESS.md's literal
# TOPMOST unchecked line as a proxy for "the item this cycle worked on". That's the right
# thing for the scout PROMPT (which tells the model to pick the top undone item itself,
# before anything is known about what it will actually do) but wrong for anything that runs
# AFTER the cycle and needs to know what was ACTUALLY attempted — the model's own choice, a
# mid-cycle checkbox flip, or wording drift between the roadmap line and what the scout named
# can all make "literal top line, re-read fresh" diverge from "the item the fleet just spent
# a cycle on". Confirmed live on test-automation-agent: one item failed 8 times across 2
# hours while state/item_fails/ongoing-<repo>.count stayed at 1 the entire time, because the
# guard kept hashing whatever unrelated item happened to be topmost that cycle instead of the
# one actually retried — completely decoupling the consecutive-fail auto-skip and the
# grounded-failure-memory safety net from reality.
#
# The one piece of real per-cycle ground truth that already exists is the scout's own FILES:
# answer, recorded in that cycle's task_log (run_overnight.sh already extracts this as
# OVN_SCOUT_FILES for cycle_summary.log + ALREADY-DONE auto-crediting — proven, live logic,
# not a new invention). Reuse it here: if the task_log names a file the model said it would
# work on, and that file appears verbatim in an undone, non-escalated OVERNIGHT_PROGRESS.md
# line, THAT line — not the literal top-of-file line — is "the item". Falls back to the
# plain top-of-file line when there's no usable scout signal (empty/missing task_log, a cheap
# ALREADY-DONE/BLOCKED short-circuit with no FILES: line, or a scouted file that doesn't
# literally appear in the progress file) — i.e. exactly the prior behavior, unchanged.
#
# Usage: source this file, then:
#   line="$(ovn_resolve_top_item "$repo_dir" "$task_log")"   # empty if nothing doable
#   lineno="${line%%:*}"; text="${line#*:}"
# ($task_log is optional — omit it, or pass a nonexistent path, to get the old
#  top-of-file-only behavior verbatim.)
ovn_resolve_top_item() {
  local repo_dir="$1" task_log="${2:-}"
  local prog="$repo_dir/OVERNIGHT_PROGRESS.md"
  [ -f "$prog" ] || return 0
  local scouted f top
  if [ -n "$task_log" ] && [ -f "$task_log" ]; then
    # Same extraction as run_overnight.sh's OVN_SCOUT_FILES: the scout's VERDICT line + next 4
    # wrapped lines (a 27B's VERDICT/PLAN/FILES answer is one logical reply the terminal wraps
    # across ~3 lines) plus any FILES: line, harvested for real repo-file-shaped tokens.
    scouted="$( { grep -A4 -hiE "VERDICT:[[:space:]]*(PROCEED|NEEDS-DECISION)" "$task_log" 2>/dev/null; grep -hiE "FILES:" "$task_log" 2>/dev/null; } \
                | grep -oE "[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}" | grep -vE "\.md$" | sort -u)"
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      top="$(grep -nE '^- \[ \]' "$prog" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]' | grep -F -- "$f" | head -1)"
      if [ -n "$top" ]; then
        printf '%s' "$top"
        return 0
      fi
    done <<< "$scouted"
  fi
  # Fallback: no task_log, no scout signal, or the scouted file isn't literally in the
  # progress file — the original top-of-file behavior, unchanged.
  top="$(grep -nE '^- \[ \]' "$prog" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]' | head -1)"
  printf '%s' "$top"
}
