#!/usr/bin/env bash
# qa_mode.sh - switch the fleet between DEV mode and QA mode (2026-10-01, user decision: ~100% QA until the QA gates are built and proven).
#
#   qa_mode.sh on              disable every enabled ongoing-* DEV lane (remembers which were enabled in state/qa_mode.json)
#   qa_mode.sh off             re-enable exactly the lanes that `on` disabled
#   qa_mode.sh lane <repo>     temporarily enable ONE repo's dev lane (e.g. to produce real traffic for a gate trial)
#   qa_mode.sh unlane <repo>   disable it again
#   qa_mode.sh status          show mode + which dev lanes are enabled
#
# Why not `queue.sh hold`: a hold auto-expires after 6h. Why not a global pause: pause_guard.sh auto-resumes it. This only flips
# `enabled` on the ongoing-* aider_fix tasks in tasks.json (atomic jq rewrite) and records what it touched, so `off` restores the
# exact prior state. Non-dev machinery (hygiene, reconcile, promote, test-watch, deploy checks, planner/refill, QA jobs) is untouched.
set -uo pipefail
DIR="${OVN_DIR:-$HOME/overnight-queue}"; T="$DIR/tasks.json"; S="$DIR/state/qa_mode.json"
mkdir -p "$DIR/state"
cmd="${1:-status}"
enabled_lanes(){ jq -r '.[] | select(.type=="aider_fix" and (.id|startswith("ongoing-")) and (.enabled != false)) | .id' "$T"; }
set_enabled(){ # $1=true|false  rest=ids
  local val="$1"; shift; local ids; ids="$(printf '%s\n' "$@" | jq -R . | jq -s .)"
  local tmp; tmp="$(mktemp "$T.XXXXXX")" || return 1
  if jq --argjson ids "$ids" --argjson v "$val" 'map(if (.id as $i | $ids | index($i)) then .enabled=$v else . end)' "$T" > "$tmp" && jq -e . "$tmp" >/dev/null; then mv "$tmp" "$T"; else rm -f "$tmp"; echo "jq rewrite failed - tasks.json untouched" >&2; return 1; fi
}
case "$cmd" in
  on)
    [ -f "$S" ] && jq -e '.mode=="qa"' "$S" >/dev/null 2>&1 && { echo "already in QA mode"; exit 0; }
    mapfile -t lanes < <(enabled_lanes)
    [ "${#lanes[@]}" -gt 0 ] || { echo "no enabled dev lanes found"; exit 1; }
    printf '%s\n' "${lanes[@]}" | jq -R . | jq -s --arg ts "$(date '+%Y-%m-%dT%H:%M:%S%z')" '{mode:"qa",since:$ts,disabled_lanes:.,temp_lanes:[]}' > "$S"
    set_enabled false "${lanes[@]}" && echo "QA mode ON - disabled ${#lanes[@]} dev lane(s): ${lanes[*]}" ;;
  off)
    [ -f "$S" ] || { echo "not in QA mode"; exit 0; }
    mapfile -t lanes < <(jq -r '.disabled_lanes[]' "$S")
    set_enabled true "${lanes[@]}" && rm -f "$S" && echo "QA mode OFF - re-enabled ${#lanes[@]} dev lane(s): ${lanes[*]}" ;;
  lane)
    r="${2:?usage: qa_mode.sh lane <repo>}"; id="ongoing-${r//_/-}"
    jq -e --arg id "$id" '.[]|select(.id==$id)' "$T" >/dev/null || { echo "no such lane: $id"; exit 1; }
    set_enabled true "$id" && { [ -f "$S" ] && jq --arg id "$id" '.temp_lanes=((.temp_lanes+[$id])|unique)' "$S" > "$S.tmp" && mv "$S.tmp" "$S"; echo "temporarily enabled $id"; } ;;
  unlane)
    r="${2:?usage: qa_mode.sh unlane <repo>}"; id="ongoing-${r//_/-}"
    set_enabled false "$id" && { [ -f "$S" ] && jq --arg id "$id" '.temp_lanes=(.temp_lanes-[$id])' "$S" > "$S.tmp" && mv "$S.tmp" "$S"; echo "disabled $id"; } ;;
  status)
    if [ -f "$S" ]; then echo "mode: QA (since $(jq -r .since "$S")); remembered lanes: $(jq -r '.disabled_lanes|join(" ")' "$S"); temp lanes: $(jq -r '.temp_lanes|join(" ")' "$S")"; else echo "mode: DEV"; fi
    echo "enabled dev lanes: $(enabled_lanes | tr '\n' ' ')" ;;
  *) echo "usage: qa_mode.sh on|off|lane <repo>|unlane <repo>|status"; exit 2 ;;
esac
