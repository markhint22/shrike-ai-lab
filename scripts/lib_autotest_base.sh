#!/usr/bin/env bash
# lib_autotest_base.sh - per-repo switch for the in-loop test feedback fix (see the 2026-10-01 note in scripts/ovn_autotest.sh).
#   ovn_autotest_base_export <repo-basename> <pre-implement-sha> [state-dir]
# Exports OVN_BASE_SHA=<sha> when ALL of: OVN_AUTOTEST_BASESHA != off, <state-dir>/autotest_basesha_repos.txt exists and lists this repo (or the
# word 'all') as a whole line, and <sha> is a real commit here. Otherwise it UNSETS OVN_BASE_SHA (so one repo's setting can never leak into the
# next cycle). Always returns 0. Roll back: delete the repo's line (or the file), or export OVN_AUTOTEST_BASESHA=off.
ovn_autotest_base_export() {
  local repo="${1:-}" sha="${2:-}" sd="${3:-state}" list
  list="$sd/autotest_basesha_repos.txt"
  unset OVN_BASE_SHA
  [ "${OVN_AUTOTEST_BASESHA:-on}" = off ] && return 0
  [ -n "$repo" ] && [ -n "$sha" ] && [ -f "$list" ] || return 0
  grep -qxE "all|$repo" "$list" 2>/dev/null || return 0
  git rev-parse -q --verify "${sha}^{commit}" >/dev/null 2>&1 || return 0
  export OVN_BASE_SHA="$sha"
  return 0
}
