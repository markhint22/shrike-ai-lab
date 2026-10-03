#!/usr/bin/env bash
# scripts/lib_run_integrity.sh - run-integrity helpers for run_overnight.sh / ovn_park_sweep.sh / deploy_watch.sh (2026-10-03, QA track "integrity",
# diagnosis actions A5 + A6). Every helper is fail-safe: on an infra problem it answers "unknown" and the caller keeps the OLD behaviour.
#
#   A5 NO-NEW-RED baseline subtraction. The NO-NEW-RED guard assumed a green baseline, so ONE landed defect (a docstring-only alembic file) turned every
#      iptv cycle into a revert: the 3 PRE-EXISTING failing migration tests + 2 new ones were all billed to the model's clean commit.
#        ovn_ri_failing_ids <log> [byte-offset]      the sorted failing test ids (pytest FAILED/ERROR, vitest/jest FAIL) from the verify output
#        ovn_ri_subtract <log> <offset> <repo> <before_sha> <state_dir>
#            sets OVN_RI_STATUS = no-ids | incomplete | baseline-unknown | baseline-green | subtracted | all-baseline
#            and OVN_RI_NEW (newline list), OVN_RI_BASE_FILE (cached baseline ids), OVN_RI_BASE_N. rc 0 only for all-baseline (NO new red).
#        The baseline is the failing-id set of the SAME verify run at BEFORE_SHA, cached in state/baseline_fail_<repo>_<sha>.txt, and is only computed
#        when the red run has parseable failures (bounded: one extra verify, deterministic, cached per sha).
#        ovn_ri_revert_repeat <state_dir> <repo> <item_hash> <ids...>   -> prints how many times THIS item was reverted for THESE (new) ids
#   A6 landing integrity.
#        ovn_ri_commit_reachable <sha> <branch>   rc 0 = sha is an ancestor of origin/<branch> after a fetch (or the fetch could not run: unknown => 0)
#        ovn_ri_cycle_mark / ovn_ri_cycle_unmark / ovn_ri_cycle_active   per-repo "a cycle is in flight" marker + stage-runner process check, so the
#        park sweep and deploy_watch's enqueue_fix SKIP a repo instead of `git reset --hard`-ing away a commit made but not yet pushed.

# ---- A5 ----------------------------------------------------------------------------------------------------------------------------------------
# failing ids from the verify output (only the bytes after <offset>, so an earlier verify in the same cycle log cannot leak in)
# Supported: pytest (FAILED/ERROR <nodeid>) and vitest (FAIL/x <file>.test.ts ...). A trailing duration ("3ms") is stripped so the id matches the
# baseline. NOT supported: jest (its summary is "Tests:       N failed" with a colon and its FAIL id is file-level, which would hide a newly broken test
# in an already-red file) - jest repos get status=incomplete and keep the old revert behaviour. Do not loosen the summary regex without parsing the
# per-test "●" lines instead.
ovn_ri_failing_ids() {
  local log="${1:-}" off="${2:-0}"
  [ -f "$log" ] || return 0
  case "$off" in ''|*[!0-9]*) off=0;; esac
  tail -c +$((off + 1)) "$log" 2>/dev/null | {
    grep -aE '^(FAILED|ERROR) [^ ]+|^ *(FAIL|×|✗) +[^ ]+\.(test|spec)\.[jt]sx?' || true
  } | sed -E 's/^(FAILED|ERROR) ([^ ]+).*/\2/; s/^ *(FAIL|×|✗) +//; s/[[:space:]]+[0-9.]+ ?m?s$//; s/[[:space:]]+$//' | cut -c1-300 | sort -u
}

# True when the verify output holds a runner SUMMARY line: a run that was killed by the 600s cap or crashed mid-way has partial FAILED lines and no
# summary, and a partial list must never be "subtracted" into a pass.
ovn_ri_has_summary() {
  local log="${1:-}" off="${2:-0}"
  [ -f "$log" ] || return 1
  case "$off" in ''|*[!0-9]*) off=0;; esac
  tail -c +$((off + 1)) "$log" 2>/dev/null | grep -aqE '[0-9]+ (failed|passed|error)[^|]* in [0-9.]+s|^ *Tests +[0-9]+ (failed|passed)|^ *Test Files +[0-9]+ (failed|passed)'
}

# True (rc 0) when the verify output carries a failure marker that is NOT a parsed pytest/vitest id: run_repo_verification ORs pytest, npm test, gradle,
# GUT and .ovn-verify.sh steps into ONE result, so ids from one red suite say nothing about a second suite (gradle, GUT, tsc, a build step) that failed
# without ids. Subtraction is only sound when the red is provably confined to the parsed ids, so any of these markers vetoes it (=> old revert).
ovn_ri_foreign_red() {
  local log="${1:-}" off="${2:-0}"
  [ -f "$log" ] || return 1
  case "$off" in ''|*[!0-9]*) off=0;; esac
  # run_repo_verification logs one "--- verify-suite-red: <kind> in <dir> rc=N ---" per red suite: more than one, or a kind that is not pytest/.ovn-verify
  # (gradle, npm, gut), means the red is not confined to the id-parsed suite. An older run_overnight without the marker falls through to the regex.
  local reds
  reds="$(tail -c +$((off + 1)) "$log" 2>/dev/null | grep -a '^--- verify-suite-red: ' || true)"
  if [ -n "$reds" ]; then
    [ "$(printf '%s\n' "$reds" | wc -l | tr -d ' ')" -gt 1 ] && return 0
    printf '%s\n' "$reds" | grep -qaE '^--- verify-suite-red: (pytest|ovn-verify|repo-script) ' || return 0
  fi
  tail -c +$((off + 1)) "$log" 2>/dev/null | grep -aqE 'FAILURE: Build failed|BUILD FAILED|> Task [^ ]+ FAILED|--- GUT RED|SCRIPT ERROR|npm ERR!|ELIFECYCLE|Command failed with exit code|error TS[0-9]+:|^error: |Build failed|error during build|timed out|Terminated$|Killed$|\[Failed\]:|^[[:space:]]*Failing[[:space:]]+[1-9]'
}

# Run the repo verification at <sha> in the live clone's own tree (detached checkout, restored afterwards) and write the cache file.
# Needs run_repo_verification() and $task_log from run_overnight.sh (dynamic scope). rc 0 = cache file ready at "$cache"; rc 1 = could not run (unknown).
ovn_ri_baseline_run() {
  local repo="$1" sha="$2" sd="$3" cache cur br tmp res saved ids n
  cache="$sd/baseline_fail_${repo}_${sha}.txt"
  if [ -s "$cache" ] && head -1 "$cache" | grep -q '^#result='; then return 0; fi
  declare -F run_repo_verification >/dev/null 2>&1 || return 1
  git cat-file -e "${sha}^{commit}" 2>/dev/null || return 1
  # a dirty tracked tree must never be disturbed
  git diff --quiet 2>/dev/null && git diff --cached --quiet 2>/dev/null || return 1
  cur="$(git rev-parse HEAD 2>/dev/null)" || return 1
  br="$(git symbolic-ref -q --short HEAD 2>/dev/null || true)"
  git checkout -q --detach "$sha" 2>/dev/null || { git checkout -q "${br:-$cur}" 2>/dev/null; return 1; }
  tmp="$(mktemp 2>/dev/null)" || tmp="/tmp/ovn_ri_base.$$"
  saved="${task_log:-}"; task_log="$tmp"
  res="$(run_repo_verification 2>/dev/null)"
  task_log="$saved"
  # restore the tree no matter what happened
  if [ -n "$br" ]; then git checkout -q "$br" 2>/dev/null || true; else git checkout -q --detach "$cur" 2>/dev/null || true; fi
  [ "$(git rev-parse HEAD 2>/dev/null)" = "$cur" ] || git reset -q --hard "$cur" 2>/dev/null
  if [ "$res" != "pass" ] && [ "$res" != "fail" ]; then rm -f "$tmp"; return 1; fi   # skip / unknown: never cache
  ids=""; if [ "$res" = "fail" ]; then
    ovn_ri_has_summary "$tmp" 0 && ids="$(ovn_ri_failing_ids "$tmp" 0)"
    [ -n "$ids" ] || { rm -f "$tmp"; printf '#result=fail-unparsed\n' > "$cache.$$" && mv -f "$cache.$$" "$cache"; return 0; }
  fi
  n=0; [ -n "$ids" ] && n="$(printf '%s\n' "$ids" | wc -l | tr -d ' ')"
  { printf '#result=%s\n#n=%s\n' "$res" "$n"; if [ -n "$ids" ]; then printf '%s\n' "$ids"; fi; } > "$cache.$$" && mv -f "$cache.$$" "$cache"
  rm -f "$tmp"
  return 0
}

ovn_ri_subtract() {
  local log="$1" off="$2" repo="$3" sha="$4" sd="$5" cur cache res
  OVN_RI_STATUS="no-ids"; OVN_RI_NEW=""; OVN_RI_BASE_FILE=""; OVN_RI_BASE_N=0
  [ "${OVN_BASELINE_SUBTRACT:-on}" = off ] && { OVN_RI_STATUS="disabled"; return 1; }
  cur="$(ovn_ri_failing_ids "$log" "$off")"
  [ -n "$cur" ] || return 1                                   # nothing parseable: old behaviour
  OVN_RI_NEW="$cur"
  ovn_ri_has_summary "$log" "$off" || { OVN_RI_STATUS="incomplete"; return 1; }
  ovn_ri_foreign_red "$log" "$off" && { OVN_RI_STATUS="other-suite-red"; return 1; }   # a second suite failed without ids: never subtract
  [ -n "$sha" ] && [ -d "$sd" ] || { OVN_RI_STATUS="baseline-unknown"; return 1; }
  ovn_ri_baseline_run "$repo" "$sha" "$sd" || { OVN_RI_STATUS="baseline-unknown"; return 1; }
  cache="$sd/baseline_fail_${repo}_${sha}.txt"
  res="$(head -1 "$cache" 2>/dev/null | sed 's/^#result=//')"
  case "$res" in
    pass) OVN_RI_STATUS="baseline-green"; return 1;;          # baseline green: every failing id is new red
    fail) ;;
    *) OVN_RI_STATUS="baseline-unknown"; return 1;;
  esac
  OVN_RI_BASE_FILE="$cache"
  OVN_RI_BASE_N="$(grep -v '^#' "$cache" 2>/dev/null | wc -l | tr -d ' ')"
  OVN_RI_NEW="$(printf '%s\n' "$cur" | grep -vxFf <(grep -v '^#' "$cache") || true)"
  if [ -z "$OVN_RI_NEW" ]; then OVN_RI_STATUS="all-baseline"; return 0; fi
  OVN_RI_STATUS="subtracted"; return 1
}

# usage: n="$(ovn_ri_revert_repeat <state_dir> <repo> <item_hash> <ids>)"  - records this revert and prints the count of reverts of the same item
# for the same new-id set (ids hashed, order-independent). Empty hash/ids => prints 1 (nothing to compare).
ovn_ri_revert_repeat() {
  local sd="$1" repo="$2" h="$3" ids="$4" key f n
  [ -n "$h" ] && [ -n "$ids" ] && [ -d "$sd" ] || { printf '1'; return 0; }
  key="$(printf '%s\n' "$ids" | sort -u | md5sum 2>/dev/null | cut -d' ' -f1)"
  mkdir -p "$sd/nr_reverts" 2>/dev/null || { printf '1'; return 0; }
  f="$sd/nr_reverts/${repo}.${h}.${key}"
  # counters expire (default 7 days): two ordinary breakages a week apart are not "the test asserts the opposite"
  [ -f "$f" ] && [ -n "$(find "$f" -mtime +"${OVN_NR_REVERT_TTL_DAYS:-7}" 2>/dev/null)" ] && rm -f "$f"
  n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$n" > "$f" 2>/dev/null
  printf '%s' "$n"
}

# usage: ovn_ri_revert_reset <state_dir> <repo> <item_hash>  - the item landed: forget its revert counters
ovn_ri_revert_reset() {
  local sd="$1" repo="$2" h="$3"
  [ -n "$h" ] && [ -d "$sd/nr_reverts" ] || return 0
  rm -f "$sd/nr_reverts/${repo}.${h}."* 2>/dev/null
  return 0
}

# ---- A6 ----------------------------------------------------------------------------------------------------------------------------------------
ovn_ri_commit_reachable() {
  local sha="${1:-}" branch="${2:-}"
  [ -n "$sha" ] && [ -n "$branch" ] || return 0
  timeout 30 git fetch -q origin "$branch" 2>/dev/null || return 0   # cannot fetch (network): unknown => do not reclassify a real push
  git rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null 2>&1 || return 0
  git merge-base --is-ancestor "$sha" "origin/$branch" 2>/dev/null
}

ovn_ri_cycle_mark() {   # <state_dir> <repo basename>   (call inside the cycle's own subshell; $BASHPID is the cycle's pid)
  local f="$1/cycle_active_$2"
  mkdir -p "$1" 2>/dev/null
  printf '%s\n' "${BASHPID:-$$}" > "$f" 2>/dev/null
}
ovn_ri_cycle_unmark() { rm -f "$1/cycle_active_$2" 2>/dev/null; }

# rc 0 = a run_overnight cycle or a stage runner is active for this repo. Marker pid must be alive and the marker younger than
# OVN_CYCLE_MARK_MAX_MIN (default 240) so a SIGKILLed cycle's stale marker cannot freeze a repo forever.
ovn_ri_cycle_active() {   # <state_dir> <repo basename>
  local sd="$1" repo="$2" f pid
  f="$sd/cycle_active_$repo"
  if [ -f "$f" ]; then
    pid="$(head -1 "$f" 2>/dev/null)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && [ -z "$(find "$f" -mmin +"${OVN_CYCLE_MARK_MAX_MIN:-240}" 2>/dev/null)" ]; then return 0; fi
  fi
  # a stage runner started by hand/cron names its repo as the first argument
  if command -v pgrep >/dev/null 2>&1 && pgrep -af 'ovn_stage_runner\.sh' 2>/dev/null | grep -v 'pgrep' | grep -qE "ovn_stage_runner\.sh([[:space:]]+[^ ]+)*[[:space:]]+${repo}([[:space:]]|\$)"; then return 0; fi
  return 1
}
