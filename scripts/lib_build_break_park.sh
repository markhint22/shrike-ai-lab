#!/usr/bin/env bash
# lib_build_break_park.sh - bounded escalation for an item whose cycle keeps being reverted(build-break).
#
# Why (2026-10-18, xlite): the "delete dead TurnManager helpers" item was build-gate-reverted 3 times in a row (~45 min each, ~2h15m of lane time) because a Godot parse/compile break
# is something the 27B repeats verbatim; the existing NEEDS-DECISION park only fires for an OLDER failing TEST, never for a structural build break, so nothing ever re-routed the item.
#
# ovn_bb_escalate <repo_dir> <state_dir> <task_log> <branch> <alert_id>
#   Call it right where a cycle is reverted(build-break). It counts reverts of the SAME item (ovn_item_hash) for the fixed key "build-break" (lib_run_integrity.sh's
#   ovn_ri_revert_repeat: same 7-day TTL, reset by ovn_ri_revert_reset when the item LANDS - so the count is "build-break reverts since the item last landed"), and at
#   OVN_BUILD_BREAK_PARK_AFTER (default 2) tags the item line `[CLAUDE] [AUTO-SKIP build-break ...]` (the picker excludes both tags; Claude picks it up from the CLAUDE queue bridge).
#   OVN_BUILD_BREAK_PARK=off|shadow|enforce (default SHADOW: counts and reports `would-park`, never edits OVERNIGHT_PROGRESS.md).
#   stdout (one line, empty = nothing to say): "count N" | "would-park N" | "parked N" | "park-failed N". Never fails the caller; every error path prints nothing.
ovn_bb_escalate() {
  local repo_dir="${1:-}" sd="${2:-}" task_log="${3:-}" branch="${4:-}" mode="${OVN_BUILD_BREAK_PARK:-shadow}" after="${OVN_BUILD_BREAK_PARK_AFTER:-2}"
  local top ln text h n ids
  [ "$mode" = off ] && return 0
  [ -d "$repo_dir" ] || return 0
  declare -F ovn_resolve_top_item >/dev/null 2>&1 && declare -F ovn_item_hash >/dev/null 2>&1 && declare -F ovn_ri_revert_repeat >/dev/null 2>&1 || return 0
  case "$after" in ''|*[!0-9]*) after=2;; esac
  top="$(ovn_resolve_top_item "$repo_dir" "$task_log" nofallback 2>/dev/null)"
  [ -n "$top" ] || return 0     # no item identified for this cycle (scout named nothing): do not guess - no verdict
  ln="${top%%:*}"; text="${top#*:}"
  h="$(ovn_item_hash "$text" 2>/dev/null)"; [ -n "$h" ] || return 0
  n="$(ovn_ri_revert_repeat "$sd" "$(basename "$repo_dir")" "$h" "build-break" 2>/dev/null)"
  case "$n" in ''|*[!0-9]*) return 0;; esac
  if [ "$n" -lt "$after" ]; then printf 'count %s' "$n"; return 0; fi
  if [ "$mode" != enforce ]; then printf 'would-park %s' "$n"; return 0; fi
  sed -i.bbpark "${ln}s#^- \[ \] #- [ ] [CLAUDE] [AUTO-SKIP build-break: reverted ${n}x in a row for a structural build break (syntax/import/parse) - the 27B repeats it verbatim, Claude must do this item] #" "$repo_dir/OVERNIGHT_PROGRESS.md" 2>/dev/null
  rm -f "$repo_dir/OVERNIGHT_PROGRESS.md.bbpark" 2>/dev/null
  if git -C "$repo_dir" diff --quiet -- OVERNIGHT_PROGRESS.md 2>/dev/null; then
    printf 'park-failed %s' "$n"; return 0     # line ${ln} was not an open '- [ ]' item: nothing changed
  fi
  git -C "$repo_dir" add OVERNIGHT_PROGRESS.md 2>/dev/null && git -C "$repo_dir" commit -q -m "chore(queue): park item for Claude - ${n} consecutive build-break reverts" 2>/dev/null
  [ -n "$branch" ] && timeout 30 git -C "$repo_dir" push -q origin "$branch" 2>/dev/null || true
  printf 'parked %s' "$n"
}
