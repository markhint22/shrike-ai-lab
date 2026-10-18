#!/usr/bin/env bash
# scripts/lib_outcome_acct.sh - outcome accounting helpers (package D4, 2026-10-18). Every helper is fail-safe: on any infra problem it answers "nothing"
# ([] / empty / rc 1) and the caller keeps the OLD behaviour. Additive only: nothing here changes an existing outcomes.jsonl field.
#
#   1. Commit attribution.
#        ovn_oa_commits <repo_dir> <head_before> <head_after> [since_epoch]   -> prints a JSON array of full shas (oldest first, at most OVN_OA_MAX_COMMITS=20) of the
#            commits reachable from head_after and not from head_before: the commits THIS cycle made (a revert leaves before==after => []).
#        ovn_oa_head <repo_dir>                                 -> the current HEAD sha, or empty.
#        record_outcome() adds  commits / head_before / head_after  to every row; scripts/ovn_outcome_acct.py reconcile later turns a HELD commit
#        (VERIFY-SKIP, lock-contended, verify-timeout hold) that finally reaches origin into a class "landed-late" row.
#   2. Bounded verify-timeout hold (OVN_VERIFY_TIMEOUT_HOLD=off|shadow|enforce, default shadow).
#        An rc=124 verify (the 600s cap killed the suite) that produced ZERO failing test ids proves nothing about the commit; reverting it burned
#        good work (c33bf17 only re-labelled the alert). With enforce the cycle's commit is HELD unpushed (like the lock-skip path) instead of reverted,
#        bounded: at most OVN_VT_HOLD_MAX holds per streak (default 3) and at most OVN_VT_HOLD_MAX_HOURS hours since the streak's first hold (default 6);
#        past either bound the verdict is "escalate": the caller reverts as before (to the streak's base sha, so the held commits go too) and alerts.
#          ovn_vt_classify <log> <byte-offset>                  rc 0 = the verify output after <offset> is a pure timeout (>=1 marker, every marker rc=124, no failing id)
#          ovn_vt_decide <state_dir> <repo> <log> <offset> <before_sha>
#              sets OVN_VT_VERDICT = off | not-timeout | shadow-hold | hold | escalate, OVN_VT_COUNT (holds so far incl. this one), OVN_VT_BASE (streak base sha),
#              OVN_VT_MSG (one-line reason). `off` and `not-timeout` never mutate state; shadow keeps a separate <repo>.shadow.state counter (never the enforce streak).
#          ovn_vt_reset <state_dir> <repo>                      a verified landing ends the streak (forget the counter)

# ---- 1. commit attribution ---------------------------------------------------------------------------------------------------------------------
ovn_oa_head() { [ -n "${1:-}" ] && git -C "$1" rev-parse -q --verify HEAD 2>/dev/null; return 0; }

ovn_oa_commits() {
  local rd="${1:-}" b="${2:-}" a="${3:-}" since="${4:-}" cap="${OVN_OA_MAX_COMMITS:-20}" out raw
  case "$cap" in ''|*[!0-9]*) cap=20;; esac
  case "$since" in ''|*[!0-9]*) since="";; esac
  if [ -z "$rd" ] || [ -z "$b" ] || [ -z "$a" ] || [ "$b" = "$a" ]; then printf '[]'; return 0; fi
  # sha-shaped arguments only: they go to git as revisions
  case "$b$a" in *[!0-9a-fA-F]*) printf '[]'; return 0;; esac
  if [ -n "$since" ]; then
    # `a --not b` is wrong whenever the branch moved under the cycle: the landing path's `git push || git pull --rebase && git push` (and reconcile_branches.sh merging develop in every
    # ~20 min) puts every UPSTREAM commit between head_before and head_after - even though head_before stays an ancestor. Keep only NON-MERGE commits AUTHORED since the cycle started
    # (author date survives a rebase; upstream commits are older than the cycle, merges are never a cycle's own). Newest <cap> kept, oldest first. Residual: a foreign commit authored
    # DURING this very cycle by another pusher still counts.
    raw="$(git -C "$rd" log --reverse --no-merges --max-count=500 --format='%H %at' "$a" --not "$b" 2>/dev/null)" || { printf '[]'; return 0; }
    out="$(printf '%s\n' "$raw" | awk -v s="$since" '$2 + 0 >= s + 0 { print $1 }' | tail -n "$cap")"
  else
    out="$(git -C "$rd" rev-list --reverse --max-count="$cap" "$a" --not "$b" 2>/dev/null)" || { printf '[]'; return 0; }
  fi
  if [ -z "$out" ]; then printf '[]'; return 0; fi
  if command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$out" | jq -Rnc '[inputs | select(length > 0)]' 2>/dev/null || printf '[]'
  else
    printf '%s\n' "$out" | awk 'BEGIN{printf "["} NF{printf "%s\"%s\"", (n++?",":""), $1} END{printf "]"}'
  fi
}

# ---- 2. bounded verify-timeout hold ------------------------------------------------------------------------------------------------------------
# pure timeout: at least one "--- verify-suite-red: <kind> in <dir> rc=N ---" marker after <offset>, EVERY marker rc=124, and no parseable failing test id
ovn_vt_classify() {
  local log="${1:-}" off="${2:-0}" marks n124 nall ids
  [ -f "$log" ] || return 1
  case "$off" in ''|*[!0-9]*) off=0;; esac
  marks="$(tail -c +$((off + 1)) "$log" 2>/dev/null | grep -aE '^--- verify-suite-red: .* rc=[0-9?]+ ---')"
  [ -n "$marks" ] || return 1
  nall="$(printf '%s\n' "$marks" | grep -c .)"
  n124="$(printf '%s\n' "$marks" | grep -cE ' rc=124 ---$')"
  [ "$nall" -ge 1 ] && [ "$n124" = "$nall" ] || return 1
  # fail-CLOSED: without the id parser we cannot prove "no failing test", so it is not a pure timeout (the old behaviour: revert)
  declare -F ovn_ri_failing_ids >/dev/null 2>&1 || return 1
  ids="$(ovn_ri_failing_ids "$log" "$off" 2>/dev/null)"
  [ -z "$ids" ] || return 1
  # a run killed before its summary prints no FAILED line, but pytest's progress lines (".F..", "tests/test_a.py ..F.  [ 10%]"), jest/vitest FAIL/x lines and "●" case
  # headers already show a red test: any of those is NOT a pure timeout (a commit that broke a test then hit the cap must be reverted, not held)
  # (ANSI colour codes are stripped first: a coloured F / FAILED must not hide from the patterns.) Other runners' red markers count too: xdist/-v pytest "FAILED"/"ERROR" lines,
  # unittest "FAIL:/ERROR:", gradle "<Class> > <case> FAILED", tsc "error TS", GUT "[Failed]", xcode "Test Case ... failed".
  tail -c +$((off + 1)) "$log" 2>/dev/null | LC_ALL=C sed $'s/\033\\[[0-9;]*[A-Za-z]//g' | grep -aqE \
    -e '^([^ ]+\.[a-z]+ +)?(\[gw[0-9]+\] +)?[.sxXFE]*[FE][.sxXFE]*( +\[ *[0-9]+%\])?$' \
    -e '^ *(FAIL|✕|×|✗) ' \
    -e '^ *● .+ › ' \
    -e '(^|[] ])(FAILED|ERROR)( |$)' \
    -e '::[^ ]+ +(FAILED|ERROR)' \
    -e '^(FAIL|ERROR): ' \
    -e ' > .+ FAILED$' \
    -e 'error TS[0-9]+' \
    -e '^ *\[Failed\]' \
    -e '^Test Case .* failed' && return 1
  return 0
}

_ovn_vt_file() { printf '%s/verify_timeout_holds/%s.state' "$1" "$2"; }

ovn_vt_decide() {
  local sd="${1:-}" repo="${2:-}" log="${3:-}" off="${4:-0}" before="${5:-}"
  local mode="${OVN_VERIFY_TIMEOUT_HOLD:-shadow}" max="${OVN_VT_HOLD_MAX:-3}" maxh="${OVN_VT_HOLD_MAX_HOURS:-6}" f now count first base
  OVN_VT_VERDICT=off; OVN_VT_COUNT=0; OVN_VT_BASE=""; OVN_VT_MSG=""
  case "$mode" in off|shadow|enforce) ;; *) mode=shadow;; esac   # a typo must never enforce
  case "$max" in ''|*[!0-9]*) max=3;; esac
  case "$maxh" in ''|*[!0-9]*) maxh=6;; esac
  [ "$mode" = off ] && return 0
  if ! ovn_vt_classify "$log" "$off"; then OVN_VT_VERDICT=not-timeout; return 0; fi
  now="$(date +%s)"; f="$(_ovn_vt_file "$sd" "$repo")"
  # shadow keeps its OWN counter file (<repo>.shadow.state) so the bound / escalate path is exercised on the live box before enforce, without ever touching an enforce streak
  [ "$mode" = shadow ] && f="$f.shadow"
  count=0; first="$now"; base=""
  if [ -f "$f" ]; then
    # state file: "<count> <first_epoch> <last_epoch> <base_sha>"
    read -r count first _last base < "$f" 2>/dev/null || true
    case "$count" in ''|*[!0-9]*) count=0;; esac
    case "$first" in ''|*[!0-9]*) first="$now";; esac
    # an idle streak (no hold for OVN_VT_HOLD_RESET_HOURS, default 12) is over: start fresh
    case "${_last:-}" in ''|*[!0-9]*) _last="$first";; esac
    if [ $(( now - _last )) -gt $(( ${OVN_VT_HOLD_RESET_HOURS:-12} * 3600 )) ]; then count=0; first="$now"; base=""; fi
  fi
  [ -n "$base" ] || base="$before"
  OVN_VT_BASE="$base"
  if [ "$count" -ge "$max" ] || [ $(( now - first )) -gt $(( maxh * 3600 )) ]; then
    OVN_VT_VERDICT=escalate; OVN_VT_COUNT="$count"
    OVN_VT_MSG="hold bound reached (${count}/${max} holds, streak age $(( (now - first) / 60 ))m of ${maxh}h cap): reverting"
    rm -f "$f" 2>/dev/null   # the revert ends the streak; the next timeout starts a fresh one
    if [ "$mode" != enforce ]; then
      OVN_VT_VERDICT=shadow-hold; OVN_VT_MSG="shadow: would ESCALATE (${OVN_VT_MSG})"
    fi
    return 0
  fi
  count=$((count + 1))
  mkdir -p "$(dirname "$f")" 2>/dev/null || { OVN_VT_VERDICT=not-timeout; return 0; }   # cannot bound the hold => never hold
  if ! { printf '%s %s %s %s\n' "$count" "$first" "$now" "$base" > "$f.tmp.$$" 2>/dev/null && mv -f "$f.tmp.$$" "$f" 2>/dev/null; }; then
    rm -f "$f.tmp.$$" 2>/dev/null; OVN_VT_VERDICT=not-timeout; return 0
  fi
  if [ "$mode" = shadow ]; then
    OVN_VT_VERDICT=shadow-hold; OVN_VT_COUNT="$count"
    OVN_VT_MSG="shadow: would HOLD this timed-out commit unpushed (hold ${count}/${max}); reverting as before"
    return 0
  fi
  OVN_VT_VERDICT=hold; OVN_VT_COUNT="$count"
  OVN_VT_MSG="verify timed out (rc=124, no failing test id): holding the commit unpushed (hold ${count}/${max})"
  return 0
}

ovn_vt_reset() { [ -n "${1:-}" ] && [ -n "${2:-}" ] && rm -f "$(_ovn_vt_file "$1" "$2")" "$(_ovn_vt_file "$1" "$2").shadow" 2>/dev/null; return 0; }

# Escalation revert of HELD (never verified) commits. The streak base is where the first hold started; the held commits sit between it and BEFORE_SHA, interleaved with the runner's
# own queue bookkeeping commits (parks, credits, refills) that must survive. Usage: ovn_vt_revert_held <base_sha> <before_sha> <log>  (run inside the repo, HEAD == before_sha, tree clean)
#   rc 0 = the held commits are gone from the tree (reset to base when no bookkeeping intervened, else a local revert commit of every non-bookkeeping path)
#   rc 1 = could not (base unknown / not an ancestor / apply failed): the tree is left at before_sha and the CALLER must say the held commits remain
ovn_vt_revert_held() {
  local base="${1:-}" before="${2:-}" log="${3:-/dev/null}"
  case "$base$before" in ''|*[!0-9a-fA-F]*) return 1;; esac
  [ -n "$base" ] && [ -n "$before" ] || return 1
  [ "$base" = "$before" ] && return 0
  git merge-base --is-ancestor "$base" "$before" 2>/dev/null || return 1
  if git diff --quiet "$base" "$before" -- OVERNIGHT_PROGRESS.md OVERNIGHT_DONE.md 2>/dev/null; then
    echo "--- VERIFY-TIMEOUT HOLD: reverting the held commits too (reset to streak base ${base:0:12}) ---" >> "$log"
    git reset --hard "$base" --quiet && return 0
    return 1
  fi
  # bookkeeping was committed in between: undo only the held commits' effect on every OTHER path, keep the bookkeeping
  if git diff --binary "$base" "$before" -- . ':!OVERNIGHT_PROGRESS.md' ':!OVERNIGHT_DONE.md' 2>/dev/null | git apply -R --index 2>/dev/null; then
    if git diff --cached --quiet 2>/dev/null; then return 0; fi
    git commit -q -m "revert(queue): drop unverified verify-timeout-held commits (hold bound reached)" 2>/dev/null && {
      echo "--- VERIFY-TIMEOUT HOLD: reverted the held commits' changes (bookkeeping commits kept; base ${base:0:12}) ---" >> "$log"; return 0; }
  fi
  git reset --hard "$before" --quiet 2>/dev/null; git clean -fd --quiet 2>/dev/null
  return 1
}
