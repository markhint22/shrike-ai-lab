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

# ovn_repo_has_autotest <dir>: rc 0 when aider's in-loop --auto-test (scripts/ovn_autotest.sh, scoped to the files the model just edited) has something to run in <dir>:
#   - a pytest venv (.venv/bin/pytest, maxdepth 4), or
#   - a package.json (maxdepth 3, not under node_modules), or
#   - a Godot project (project.godot, maxdepth 3): 2026-10-09 (harness-credit-integrity item 9) - the predicate used to know only the first two, and xlite has neither, so
#     aider never ran ovn_autotest.sh's gdparse / `godot --check-only` gate in the loop: a Godot-3-ism or parse error was committed blind and only caught by the post-commit
#     verify (revert + a wasted cycle). OVN_GODOT_INLOOP_GATE=off drops the project.godot clause (the old predicate).
# Extracted from the inline test in run_overnight.sh so it can be unit-tested. Captures find output instead of `find | grep -q` (pipefail/SIGPIPE-flaky shape).
ovn_repo_has_autotest() {
  local d="${1:-.}" hit
  hit="$(find "$d" -maxdepth 4 -type f -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
  [ -n "$hit" ] && return 0
  hit="$(find "$d" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null | head -1)"
  [ -n "$hit" ] && return 0
  if [ "${OVN_GODOT_INLOOP_GATE:-on}" != off ]; then
    hit="$(find "$d" -maxdepth 3 -name project.godot -not -path '*/node_modules/*' -not -path '*/addons/*' 2>/dev/null | head -1)"
    [ -n "$hit" ] && return 0
  fi
  return 1
}
