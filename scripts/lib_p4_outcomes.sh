#!/usr/bin/env bash
# scripts/lib_p4_outcomes.sh - package P4 (2026-10-21): stage-unverified classification, head_before audit, NO-NEW-RED re-run-once.
# SOURCED by run_overnight.sh (and ovn_stage_runner.sh for the tag). Every function is fail-safe: a missing lib means the OLD behaviour.
#
#   ovn_stage_fail_tag <stage_runs jsonl> [verify_log]   (OVN_STAGE_FAILTAG=on|off, default off)
#       The inline stage caller's single "no-op(stage-unverified)" label hid two different things: 26 runs where no step landed and no verify ran (every step
#       no-edit / empty-file / scope-violation / timeout / context-exceeded) and 28 where the full verify ran and failed. Prints one bounded tag:
#         verify log present  -> ovn_classify_fail.sh on the verify log with a NEUTRAL status (the stage-unverified status itself short-circuits the classifier)
#         no verify log       -> the dominant failed-step fail_reason from the journal (ties: first seen), else 'blocked' when steps were blocked, else stage-unverified.
#       Off => prints nothing (caller keeps the old label). The status TEXT is never changed.
#   ovn_hb_write <task_log> <sha>  / ovn_hb_read <task_log>
#       head_before audit. The old marker went into the task log itself, and the scout step later does `aider ... > "$task_log"` (truncate), so 211 of 211 landed rows
#       in 24h had head_before=="" and commits==[]. The sha now also goes to a sidecar "<task_log>.headbefore" that nothing truncates; first write wins (best-of-N).
#   ovn_nnr_redkind <changed_all> <nontest_changed> <failing_ids>   -> the human label for the NO-NEW-RED revert (a test the commit did not touch is not "model added failing tests")
#   ovn_nnr_apply <repo_dir> <task_log> <failing_ids>   (OVN_NNR_RERUN=off|shadow|on, default off)
#       Re-run ONLY the failing pytest ids once. rc 0 = mode on AND the re-run was green (caller treats the verify as pass); anything else rc 1 (revert as before).
#       shadow logs "would have saved" but still reverts. Ids that are not pytest node ids (vitest, GUT) or more than OVN_NNR_RERUN_MAX (5) are never re-run.

ovn_stage_fail_tag() {
  local jl="${1:-}" vlog="${2:-}" here tag
  [ "${OVN_STAGE_FAILTAG:-off}" = on ] || return 0
  here="${OVN_P4_QDIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." 2>/dev/null && pwd)}"
  if [ -n "$vlog" ] && [ -s "$vlog" ]; then
    tag="$(bash "$here/ovn_classify_fail.sh" "$vlog" "verify-failed" 2>/dev/null | head -1 | tr -cd 'a-z0-9-')"
    case "$tag" in ''|unknown|landed) tag="verify-failed";; esac
    printf '%s' "$tag"; return 0
  fi
  [ -n "$jl" ] && [ -f "$jl" ] || { printf 'stage-unverified'; return 0; }
  tag="$(jq -r 'select(.step!=null and .verdict=="fail" and ((.fail_reason//"")!="")) | .fail_reason' "$jl" 2>/dev/null \
         | awk '{n[$0]++; if(!($0 in o)){o[$0]=++k}} END{best="";bn=0;bo=0; for(t in n){ if(n[t]>bn || (n[t]==bn && o[t]<bo)){best=t;bn=n[t];bo=o[t]} } print best}' | tr -cd 'a-z0-9-')"
  if [ -z "$tag" ] && jq -e 'select(.step!=null and .verdict=="blocked")' "$jl" >/dev/null 2>&1; then tag="blocked"; fi
  printf '%s' "${tag:-stage-unverified}"
}

ovn_hb_write() {  # <task_log> <sha>
  local tl="${1:-}" sha
  sha="$(printf '%s' "${2:-}" | tr -cd '0-9a-fA-F')"
  [ -n "$tl" ] && [ -n "$sha" ] || return 0
  [ -s "$tl.headbefore" ] || printf '%s\n' "$sha" > "$tl.headbefore" 2>/dev/null
  return 0
}
ovn_hb_read() {  # <task_log> -> sha or nothing; the sidecar wins, the in-log marker is the legacy fallback
  local tl="${1:-}" sha=""
  [ -n "$tl" ] || return 0
  [ -f "$tl.headbefore" ] && sha="$(head -1 "$tl.headbefore" 2>/dev/null | tr -cd '0-9a-fA-F')"
  if [ -z "$sha" ] && [ -f "$tl" ]; then sha="$(grep -a -m1 -oE '^--- ovn-head-before: [0-9a-f]{7,40} ---' "$tl" 2>/dev/null | grep -oE '[0-9a-f]{7,40}' | head -1)"; fi
  printf '%s' "$sha"
}

ovn_nnr_redkind() {  # <changed_all> <nontest_changed> <failing_ids>
  local changed="${1:-}" nontest="${2:-}" ids="${3:-}" id f touched=0
  if [ -n "$nontest" ]; then printf 'a source change broke a previously-green test'; return 0; fi
  if [ -n "$ids" ]; then
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      f="${id%%::*}"
      if printf '%s\n' "$changed" | grep -qxF -- "$f" || printf '%s\n' "$changed" | grep -qE -- "(^|/)${f##*/}\$"; then touched=1; break; fi
    done <<< "$ids"
    if [ "$touched" = 0 ]; then printf 'a test this commit did not touch failed (flaky or pre-existing, not the model'"'"'s new test)'; return 0; fi
  fi
  printf 'the model added failing tests'
}

ovn_nnr_apply() {  # <repo_dir> <task_log> <failing_ids>
  local repo="${1:-}" tl="${2:-/dev/null}" ids="${3:-}" mode="${OVN_NNR_RERUN:-off}" n id f d dirs="" green=1 py cap="${OVN_NNR_RERUN_MAX:-5}" sub nnrlog
  nnrlog="$tl.nnr"; [ "$tl" = /dev/null ] && nnrlog=/dev/null
  [ "$mode" = off ] && return 1
  [ -n "$ids" ] && [ -d "$repo" ] || return 1
  n="$(printf '%s\n' "$ids" | grep -c .)"
  if [ "$n" -gt "$cap" ] 2>/dev/null; then echo "--- NNR-RERUN: ${n} failing ids > cap ${cap}, not re-running ---" >> "$tl"; return 1; fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$id" in *::*) ;; *) echo "--- NNR-RERUN: id '${id}' is not a pytest node id, not re-running ---" >> "$tl"; return 1;; esac
    f="${id%%::*}"; case "$f" in *.py) ;; *) echo "--- NNR-RERUN: id '${id}' is not a pytest file, not re-running ---" >> "$tl"; return 1;; esac
    d=""
    if [ -f "$repo/$f" ]; then d="$repo"; else for sub in "$repo"/*/; do [ -f "${sub}$f" ] && { d="${sub%/}"; break; }; done; fi
    [ -n "$d" ] || { echo "--- NNR-RERUN: ${f} not found under the repo, not re-running ---" >> "$tl"; return 1; }
    dirs="$dirs$d"$'\n'
  done <<< "$ids"
  for d in $(printf '%s' "$dirs" | sort -u); do
    local want=() 
    while IFS= read -r id; do [ -n "$id" ] || continue; f="${id%%::*}"; [ -f "$d/$f" ] && want+=("$id"); done <<< "$ids"
    py="${OVN_NNR_PYTEST:-}"
    if [ -z "$py" ]; then
      if [ -x "$d/.venv/bin/pytest" ]; then py="$d/.venv/bin/pytest"; elif [ -x "$repo/.venv/bin/pytest" ]; then py="$repo/.venv/bin/pytest"; else py="python3 -m pytest"; fi
    fi
    # shellcheck disable=SC2086
    if ! ( cd "$d" && if command -v timeout >/dev/null 2>&1; then timeout "${OVN_NNR_RERUN_TIMEOUT:-240}" $py -q --no-cov -p no:cacheprovider "${want[@]}"; else $py -q --no-cov -p no:cacheprovider "${want[@]}"; fi ) >> "$nnrlog" 2>&1; then green=0; fi
  done
  if [ "$green" = 1 ]; then
    if [ "$mode" = on ]; then echo "--- NNR-RERUN: the ${n} failing test(s) PASSED on a re-run (flaky) - not reverting ---" >> "$tl"; return 0; fi
    echo "--- NNR-RERUN (shadow): the ${n} failing test(s) PASSED on a re-run - would have saved this commit (OVN_NNR_RERUN=on enables) ---" >> "$tl"; return 1
  fi
  echo "--- NNR-RERUN: still red on the re-run - reverting ---" >> "$tl"; return 1
}
