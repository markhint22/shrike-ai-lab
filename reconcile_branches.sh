#!/usr/bin/env bash
# reconcile_branches.sh — comprehensive branch reconciler + divergence guard (2026-09-05).
# Supersedes sync_branches.sh. Enforces the invariant  main ⊆ develop ⊆ feature  so branches never
# drift. PREVENTION lives in daily_promote's back-merge; THIS is the occasionally-run MITIGATION that
# catches + auto-fixes any drift that slips through — a promote merge-commit, or (the accidental case)
# a chat/hotfix commit pushed straight to main — and ALERTS you when it does or when it hits a real
# conflict it can't resolve. Safe: ff-or-merge only, never force-push; a conflict is aborted + flagged.
# Idempotent: a full no-op when everything is already in sync.
#
# Wire: end of daily_promote.sh (same-run) + cron `30 */3 * * *` (every 3h, the occasional pass).
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
# shellcheck source=./scripts/lib_tree_guard.sh
[ -f "$HOME/overnight-queue/scripts/lib_tree_guard.sh" ] && . "$HOME/overnight-queue/scripts/lib_tree_guard.sh"
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
DRY="${DRY_RUN:-0}"
repos="${*:-repos/billwatch repos/gitlark repos/iptv_apps repos/test-automation-agent repos/shrike-notify repos/shrike-monitor repos/xlite repos/shrike-labs-website}"
log(){ echo "$(date '+%F %T') $*"; }
conflicts=""; directs=""; resolved=""

# 2026-09-16: one bounded, always-independently-verified LLM-assisted conflict resolution
# attempt, used ONLY for a develop<->feature sync (never main<->develop - that path always
# goes straight to a human, unchanged). Root incident: the fleet's ovn_recover_parked.sh
# decomposed+re-attempted an item already tagged "route to CLAUDE" (a terminal handoff, now
# fixed separately) while a Claude session was independently completing the same work via
# CLAUDE_QUEUE.md - both landed on different branches, producing a real add/add conflict at
# the next reconcile pass that sat unresolved (and alerting) until a human/Claude noticed.
# Feature branches are working branches, not production, so a bad automated resolution here
# costs a wasted cycle, not an incident - and it's NEVER trusted blind: independently
# re-verified by the repo's own real build/test gate (reusing branch_hygiene.sh's run_gate())
# before ever being pushed. Scoped conservatively: <=3 conflicted files (a bigger conflict
# needs a human, not more automation), one aider attempt, no retries. Falls back to the
# ORIGINAL abort+alert behavior on any uncertainty (still conflicted after the attempt, gate
# fails, or the gate has nothing it can even check) - this never lowers the safety bar, it
# only adds a chance to clear the easy cases before bothering a human with them.
# 2026-10-13 (package reconcile-llm-resolve-gate): the gate is run as branch_hygiene.sh's own gate-only entry (HYGIENE_GATE_ONLY=1, see the hook above its repo loop) in a SEPARATE
# process. The old text-extract (`sed -n '/^run_gate() {/,/^}/p'` + source under `set -uo pipefail`) died at the first dependency reconcile never defines ($SCRIPT_DIR, $STATE_DIR, acquire_lock,
# hyg_gate_run, ...): "SCRIPT_DIR: unbound variable", an EMPTY merge_into result, 142 aider attempts since 09-21 with 0 resolved, no alert, one orphaned /tmp worktree per attempt.
# Exit codes (unchanged): 0 green, 1 red, 2 nothing to check (no gate = no trust). NOTE: this runs inside rc=$(sync_feature ...), so stdout is the caller's result channel - messages go to stderr.
reconcile_gate_run(){  # $1=abs main clone $2=worktree dir -> the gate's exit code (stdout/stderr are the caller's to redirect)
  HYGIENE_GATE_ONLY=1 HYGIENE_GATE_REPO="$1" HYGIENE_GATE_WT="$2" TEST_TIMEOUT="${TEST_TIMEOUT:-600}" timeout "${TEST_TIMEOUT:-600}" bash "$HOME/overnight-queue/branch_hygiene.sh"
}
# The gate-only entry ends its stdout with "HYGIENE_GATE_ONLY done rc=<n>". A pre-gate-only branch_hygiene.sh (partial deploy) ignores HYGIENE_GATE_ONLY, finds no repos and exits 0 WITHOUT it,
# which must never read as a green gate. $1=captured output file $2=expected rc -> 0 = the marker is there with that rc.
reconcile_gate_ran(){ grep -qxF "HYGIENE_GATE_ONLY done rc=$2" "$1" 2>/dev/null; }
# PREFLIGHT, BEFORE any aider tokens are spent: the same gate-only call against an EMPTY dir must answer rc 2 ("nothing to check"). Anything else (a crash, an unbound variable, a missing
# script, rc 1/124) means the harness is broken and an LLM resolution could never be verified: skip the attempt, say so on stderr, and write ONE alerts.log warn per day.
# OVN_LLM_RESOLVE_PREFLIGHT=off skips the check. Returns 0 = healthy, 1 = broken.
llm_gate_preflight(){  # $1=main-repo (only names the scratch dir)
  [ "${OVN_LLM_RESOLVE_PREFLIGHT:-on}" = off ] && return 0
  local d prc="mktemp-failed" st="$HOME/overnight-queue/state" day
  d="$(mktemp -d "/tmp/reconcile-gatepre-$(basename "${1:-repo}").XXXXXX" 2>/dev/null)" || d=""
  if [ -n "$d" ]; then
    reconcile_gate_run "$d" "$d" > "$HOME/overnight-queue/logs/reconcile_gate_preflight.log" 2>&1; prc=$?
    rm -rf "$d"
    # an rc 2 only counts WITH the gate-only completion marker (see reconcile_gate_ran): anything else is not the harness we expect
    if [ "$prc" = 2 ] && ! reconcile_gate_ran "$HOME/overnight-queue/logs/reconcile_gate_preflight.log" 2; then prc="2-without-marker"; fi
  fi
  [ "$prc" = 2 ] && return 0
  echo "$(date '+%F %T') llm-resolve disabled: gate harness broken (empty-dir preflight rc=${prc}, expected 2; see logs/reconcile_gate_preflight.log) - not spending tokens, falling back to abort+alert" >&2
  day="$(date +%F)"
  if [ "$(cat "$st/reconcile_llm_gate_alerted" 2>/dev/null)" != "$day" ]; then
    mkdir -p "$st" 2>/dev/null; echo "$day" > "$st/reconcile_llm_gate_alerted" 2>/dev/null
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] warn | reconcile-llm-gate | reconcile's LLM-assisted conflict resolve is DISABLED: the gate-only harness (branch_hygiene.sh HYGIENE_GATE_ONLY=1) failed its empty-dir preflight (rc=${prc}, expected 2). Conflicts fall back to abort+alert until it is fixed; see logs/reconcile_gate_preflight.log" >> "$st/alerts.log" 2>/dev/null
  fi
  return 1
}
try_llm_resolve(){  # $1=worktree $2=main-repo $3=tgt-branch $4=src-branch -> 0=resolved+verified+committed, 1=give up
  local wt="$1" repo="$2" tgt="$3" src="$4"
  # 2026-09-21: respect a manual/GPU-testing pause. Only this LLM-assist path touches the
  # GPU (real aider/local-model call) — the rest of this script's plain git merging keeps
  # running as normal during a pause; give up gracefully here exactly like any other
  # resolve failure (caller's existing `git merge --abort` + conflict-report path handles it).
  [ -f state/PAUSED ] && return 1
  local files; files="$(git -C "$wt" diff --name-only --diff-filter=U)"
  [ -z "$files" ] && return 1
  local nfiles; nfiles="$(printf '%s\n' "$files" | grep -c .)"
  [ "$nfiles" -gt 3 ] && return 1
  llm_gate_preflight "$repo" || return 1   # harness broken -> no aider call, no token spend
  local fileargs=(); while IFS= read -r fl; do fileargs+=(--file "$fl"); done <<< "$files"
  local _llm_out; _llm_out="$( cd "$wt" && timeout 400 "$HOME/aider-venv/bin/aider" --yes-always --no-check-update --no-auto-commits \
      --model openai/qwen-dflash-27B --openai-api-base http://localhost:4000/v1 --openai-api-key sk-shrike-local \
      "${fileargs[@]}" \
      --message "These files have UNRESOLVED git merge conflict markers (<<<<<<<, =======, >>>>>>>) from a real 'git merge' between two branches. Resolve every conflict by keeping BOTH sides' distinct real functionality wherever the two changes are compatible - never silently drop one side's real work. If one side is clearly a placeholder/stub (e.g. returns an empty value with a TODO) and the other is a complete, real implementation, keep the complete one. Remove ALL conflict markers from every file. Do not touch anything outside these exact files." \
  2>&1 )"
  # 2026-09-16: this call's token spend used to be thrown away entirely (>/dev/null) - extract
  # it from aider's own "Tokens: X sent, Y received" line (same convention run_overnight.sh
  # parses) and log it, still without polluting reconcile.log with the full transcript.
  _llm_ts="$(printf '%s' "$_llm_out" | grep -oiE '[0-9.]+k? +sent' | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"
  _llm_tr="$(printf '%s' "$_llm_out" | grep -oiE '[0-9.]+k? +received' | grep -oiE '^[0-9.]+k?' | awk '/[kK]/{gsub(/[kK]/,"");s+=$1*1000;next}{s+=$1}END{print int(s)}')"
  bash "$HOME/overnight-queue/scripts/ovn_log_tokens.sh" reconcile-selfheal "$(basename "$repo")" "${_llm_ts:-0}" "${_llm_tr:-0}" 2>/dev/null || true
  # Check the FILE CONTENT for leftover markers, not git's index/unmerged state - aider edits
  # the files (with --no-auto-commits) but never runs `git add`, so `git diff --diff-filter=U`
  # keeps reporting "still unmerged" even after a fully correct text-level resolution (found
  # live in testing: aider correctly kept the real implementation over a placeholder stub,
  # markers all gone, but the AA/unmerged index entry was untouched). Once we confirm the text
  # is genuinely clean, WE tell git it's resolved by adding exactly the files that were
  # conflicted (never a broad `git add -A`, which could stage something unrelated).
  local remaining=0
  while IFS= read -r fl; do
    [ -z "$fl" ] && continue
    grep -qE '^(<{7}|={7}|>{7})' "$wt/$fl" 2>/dev/null && remaining=1
  done <<< "$files"
  [ "$remaining" = 1 ] && return 1
  while IFS= read -r fl; do [ -n "$fl" ] && git -C "$wt" add "$fl"; done <<< "$files"
  git -C "$wt" diff --name-only --diff-filter=U | grep -q . && return 1   # belt-and-suspenders
  # independently re-verify with the SAME gate branch_hygiene.sh trusts elsewhere - looking
  # "unmarked" is not the same as actually building/passing.
  # (2026-10-13: runs branch_hygiene.sh's own gate-only entry in a separate process - see reconcile_gate_run above; the old sed-extract + source died on unbound variables.)
  # run_gate's own callers (branch_hygiene.sh) always absolutize $repo before calling it -
  # every path it builds internally (e.g. venv_pytest, mainfile for the docker touched-check)
  # assumes that. reconcile_branches.sh's $repo is relative ("repos/<name>", valid only from
  # $HOME/overnight-queue), and run_gate's own subshells `cd` into the worktree first - found
  # live: this broke the pytest step with "timeout: failed to execute process: No such file or
  # directory" (execve on a relative path resolved against the wrong cwd after the cd),
  # reported as gate=fail even though the actual conflict resolution and tests were fine.
  local abs_repo; abs_repo="$(cd "$repo" 2>/dev/null && pwd || echo "$repo")"
  # run_gate's own npm/pytest/docker commands print their real output unredirected (by design,
  # for branch_hygiene.sh's own log) - here that flooded reconcile.log with a full vitest/pytest
  # transcript, found live while diagnosing the bug above. Keep just the most recent attempt for
  # debugging instead of either polluting the shared log or discarding it entirely.
  reconcile_gate_run "$abs_repo" "$wt" > "$HOME/overnight-queue/logs/reconcile_gate_last.log" 2>&1; local grc=$?
  [ "$grc" -ne 0 ] && return 1   # reject on FAIL(1) and on NOTHING-TO-CHECK(2) alike - no gate, no trust
  # rc 0 only counts when the gate-only entry itself said it ran (an old branch_hygiene.sh that ignores HYGIENE_GATE_ONLY exits 0 having checked nothing)
  reconcile_gate_ran "$HOME/overnight-queue/logs/reconcile_gate_last.log" 0 || { echo "$(date '+%F %T') llm-resolve rejected: gate rc 0 without the HYGIENE_GATE_ONLY completion marker (old branch_hygiene.sh?) - not trusting it" >&2; return 1; }
  git -C "$wt" add -A
  git -C "$wt" -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q \
    -m "chore(sync): reconcile ${src} -> ${tgt} (branch guard, LLM-assisted conflict resolution, gate=tests-green)" >/dev/null 2>&1
}

# POST-MERGE SANITY GATE (2026-09-30). A clean `git merge` (exit 0, no conflict markers from git itself) can still
# SYNTHESIZE a broken file when both branches edited the same file in different regions (duplicated blocks, a
# half-applied rename...). The plain-merge path pushed that straight to develop/feature with no check at all (only the
# LLM-assisted path re-verified). This checks ONLY the files that BOTH sides changed since the merge base - the ones
# git actually had to combine - for cheap structural validity: no leftover conflict markers, python compiles,
# shell parses, json parses. Anything failing -> do NOT push; caller reports `sanityfail` (alerts like a conflict).
# OVN_MERGE_SANITY=off disables. Returns 0 ok / 1 broken (prints the reason on stdout).
merge_sanity_ok(){
  local wt="$1" tgt="$2" src="$3" base f n=0 bad=""
  [ "${OVN_MERGE_SANITY:-on}" = "off" ] && return 0
  # absolute-symlink guard (scripts/lib_tree_guard.sh): runs on the MERGE RESULT vs the target, before the merge-base checks below
  if command -v ovn_abs_symlinks >/dev/null 2>&1; then
    bad="$(ovn_abs_symlinks "$wt" "origin/${tgt}" HEAD | head -3 | tr '\n' ' ')"
    [ -n "$bad" ] && { echo "absolute symlink(s) in merge result: $bad"; return 1; }
    bad=""
  fi
  base="$(git -C "$wt" merge-base "origin/${tgt}" "origin/${src}" 2>/dev/null)" || return 0
  [ -n "$base" ] || return 0
  while IFS= read -r f; do
    [ -f "$wt/$f" ] || continue
    n=$((n+1)); [ "$n" -gt 200 ] && break
    if grep -qE '^(<<<<<<< |>>>>>>> |=======$)' "$wt/$f" 2>/dev/null && ! printf '%s' "$f" | grep -qE '\.(md|rst|txt)$'; then bad="$f: conflict markers"; break; fi
    case "$f" in
      *.py) python3 -m py_compile "$wt/$f" >/dev/null 2>&1 || { bad="$f: python does not compile"; break; } ;;
      *.sh) bash -n "$wt/$f" >/dev/null 2>&1 || { bad="$f: shell syntax error"; break; } ;;
      *.json) python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$wt/$f" >/dev/null 2>&1 || { bad="$f: invalid json"; break; } ;;
    esac
  done < <(LC_ALL=C comm -12 <(git -C "$wt" diff --name-only "$base" "origin/${tgt}" 2>/dev/null | LC_ALL=C sort) <(git -C "$wt" diff --name-only "$base" "origin/${src}" 2>/dev/null | LC_ALL=C sort))
  [ -z "$bad" ] && return 0
  echo "$bad"; return 1
}

# PROGRESS-FILE CONFLICT: DEFERRED TO HYGIENE (2026-10-12, package conflict; r12 fix). OVERNIGHT_PROGRESS.md / OVERNIGHT_DONE.md are edited by the fleet, claude/feature
# sessions and this script at once; a text merge conflicts on them constantly (iptv_apps develop->overnight/feature conflicted on every 20-min pass 05:30-07:50 on 2026-10-12).
# scripts/ovn_progress_merge.py can merge them deterministically, but a LANDING needs the repo's build/test gate, and reconcile runs inside fleet_autofix.sh's run.lock under
# `timeout -k 30 300`: a gradle/pytest gate there can be SIGKILLed (stray /tmp/reconcile-* worktree, orphaned children, fleet lock blocked) and would re-run every 20 minutes
# for as long as the conflict persists. So reconcile does NOT gate and does NOT merge: when EVERY conflicted path is a progress file (read-only --check-index) it only flags
# + logs the conflict and leaves it for the hourly branch_hygiene.sh pass, which has its own time budget, resolves the same conflict under the gate (resolve -> gate -> commit)
# when it merges feature -> develop, after which the next reconcile pass simply fast-forwards feature to develop. Anything else = the original abort + alert / LLM path.
pm_flag_file(){  # $1=main-repo $2=tgt (branch) -> per-lane deferral flag path (line 1 = first-seen epoch, optional line 2 = 'alerted')
  printf '%s/reconcile_progress_deferred_%s__%s' "$HOME/overnight-queue/state" "$(basename "$1")" "${2//[^A-Za-z0-9._-]/_}"
}
pm_flag_clear(){ rm -f "$(pm_flag_file "$1" "$2")" 2>/dev/null; true; }   # the conflict is gone (feature caught up / merged / became a different kind of conflict)
# 2026-10-12 (review fix M1): the flag keeps its FIRST-SEEN epoch (created only when absent). A deferral that outlives OVN_PM_DEFER_ALERT_H (default 6) hours means hygiene is
# not landing it (red gate, QA hold, tree guard, QA-clean-prefix failure): escalate ONCE per flag to the normal reconcile CONFLICT alert (return 3 = stale), then stay quiet.
# OVN_PM_NOW overrides the clock (tests only).
progress_conflict_deferred(){  # $1=worktree $2=main-repo $3=tgt $4=src -> 0 = deferred (flag+log) | 3 = deferred AND stale (caller alerts as a conflict, once) | 1 = not progress-only
  local wt="$1" repo="$2" tgt="$3" src="$4" pm="$HOME/overnight-queue/scripts/ovn_progress_merge.py" nm fdir flag now first age lim
  [ "${OVN_PROGRESS_MERGE:-on}" = off ] && return 1
  [ -f "$pm" ] || return 1
  nm="$(basename "$repo")"
  timeout 60 python3 "$pm" --check-index "$wt" --log "$HOME/overnight-queue/state/progress_merge.log" --tag "reconcile:${nm}:${src}->${tgt}" >/dev/null 2>&1 || return 1
  fdir="$HOME/overnight-queue/state"; mkdir -p "$fdir" 2>/dev/null
  flag="$(pm_flag_file "$repo" "$tgt")"; now="${OVN_PM_NOW:-$(date +%s)}"
  if [ ! -f "$flag" ]; then
    printf '%s\n' "$now" > "$flag" 2>/dev/null
    echo "$(date '+%F %T') ${nm}: reconcile ${src}->${tgt}: progress-file-only conflict DEFERRED to hygiene (no gate run in reconcile)" >> "$fdir/progress_merge.log" 2>/dev/null
  fi
  first="$(head -n1 "$flag" 2>/dev/null)"; case "$first" in ''|*[!0-9]*) first="$now"; printf '%s\n' "$now" > "$flag" 2>/dev/null;; esac
  age=$(( now - first )); lim=$(( ${OVN_PM_DEFER_ALERT_H:-6} * 3600 ))
  if [ "$age" -ge "$lim" ] && ! grep -qx alerted "$flag" 2>/dev/null; then
    echo alerted >> "$flag" 2>/dev/null
    echo "$(date '+%F %T') ${nm}: reconcile ${src}->${tgt}: progress-file conflict still deferred after $(( age / 3600 ))h - escalating to the conflict alert" >> "$fdir/progress_merge.log" 2>/dev/null
    return 3
  fi
  return 0
}

# merge origin/<src> into <tgt> in an isolated worktree, push (rebase-retry once). $4=1 to allow
# ONE LLM-assisted resolution attempt before giving up (see try_llm_resolve above; only passed by
# the develop<->feature call site). echoes ok|llm_resolved|conflict|pushfail|wterror|nochange
merge_into(){
  local repo="$1" tgt="$2" src="$3" allow_llm="${4:-0}"
  local ahead _pcd; ahead=$(git -C "$repo" rev-list --count "origin/${tgt}..origin/${src}" 2>/dev/null || echo 0)
  [ "${ahead:-0}" -eq 0 ] && { echo nochange; return; }
  local wt; wt="$(mktemp -d "/tmp/reconcile-$(basename "$repo").XXXX")"
  git -C "$repo" worktree add --quiet "$wt" "origin/${tgt}" 2>/dev/null || { rm -rf "$wt"; echo wterror; return; }   # 2026-10-13: the mktemp dir leaked here (an inode per failed pass while /tmp was full)
  # 2026-10-13: merge_into always runs inside a $(...) subshell; if anything below kills that subshell (set -u, a signal, a failing helper) the `worktree remove` at the end never ran and
  # the worktree (~800 inodes) leaked: 11 orphaned /tmp/reconcile-test-automation-agent.* on 10-13 helped exhaust the box's /tmp inodes. The EXIT trap removes it on ANY exit; it is cleared
  # again on the normal path. The path/repo are baked into the trap text now (locals are gone by the time a subshell's EXIT trap fires).
  # shellcheck disable=SC2064
  trap "$(printf 'git -C %q worktree remove --force %q >/dev/null 2>&1; rm -rf %q' "$repo" "$wt" "$wt")" EXIT
  # 2026-09-16 CRITICAL FIX: this `checkout -B "$tgt" ...` almost ALWAYS fails silently
  # ("'$tgt' is already used by worktree at <main clone>" - git refuses to check out the
  # same branch in two worktrees at once, and the main clone always has $tgt checked out).
  # The worktree is then left in DETACHED HEAD. Every push below used the AMBIGUOUS form
  # `git push origin "$tgt"`, which - while detached - resolves "$tgt" as a LOCAL ref
  # lookup first: it finds the MAIN CLONE's OWN `refs/heads/$tgt` (shared across all
  # worktrees of one repo) and pushes THAT commit, completely ignoring this worktree's
  # actual (correctly merged/resolved) HEAD. Confirmed live: this either (a) silently
  # reports "Everything up-to-date" -> exit 0 -> falsely reported as ok/llm_resolved while
  # NOTHING actually reached origin (the common case, since the main clone is usually kept
  # fetched-current), or (b) gets flat-out REJECTED as non-fast-forward if the main clone's
  # ref happens to be stale. Root-caused a REAL incident: the same develop<->overnight/feature
  # conflict on test-automation-agent got reported "🤖 auto-resolved" three separate times
  # 20 minutes apart, and NONE of them ever actually landed - the divergence was identical
  # each time because every "successful" push was silently discarding the real fix. This bug
  # predates today's LLM-resolve work entirely (present in merge_into() since 2026-09-05) and
  # affects BOTH this function's plain-merge path AND the LLM-assisted path, for BOTH the
  # main<->develop and develop<->feature directions - any time an actual merge (not a plain
  # fast-forward) was needed. Fix: push `HEAD:"$tgt"` explicitly everywhere below - this
  # unambiguously pushes THIS WORKTREE'S OWN CURRENT COMMIT regardless of detached state,
  # never the unrelated shared local ref.
  git -C "$wt" checkout -B "$tgt" "origin/${tgt}" --quiet 2>/dev/null
  local rc=conflict
  if OVN_PM_DEFER=1 git -C "$wt" -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet merge --no-ff --no-edit -m "chore(sync): reconcile ${src} -> ${tgt} (branch guard)" "origin/${src}" >/dev/null 2>&1; then
    # timeout on every network call (2026-09-15): an unbounded git push/pull
    # here used to be able to hang indefinitely while holding fd 202
    # (run.lock) from the fleet_autofix.sh caller - see that script's own
    # 2026-09-15 comment for the "orphaned lock, fleet blocked" failure mode
    # this closes off at the source.
    if ! _sanity_why="$(merge_sanity_ok "$wt" "$tgt" "$src")"; then
      rc=sanityfail; echo "$(date '+%F %T') $(basename "$repo"): merge ${src}->${tgt} SYNTHESIZED a broken file, NOT pushed: ${_sanity_why}" >> "${SANITY_LOG:-logs/reconcile_sanity.log}" 2>/dev/null
    elif timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=ok
    elif OVN_PM_DEFER=1 timeout 30 git -C "$wt" pull -q --rebase origin "$tgt" >/dev/null 2>&1 && timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=ok
    else rc=pushfail; fi
  elif [ "$allow_llm" = 1 ] && { progress_conflict_deferred "$wt" "$repo" "$tgt" "$src"; _pcd=$?; [ "$_pcd" -ne 1 ]; }; then
    # progress-files-only conflict: flagged + logged, left for hygiene's gated landing (see progress_conflict_deferred); abort this merge; no alert until the flag is stale (rc 3)
    git -C "$wt" merge --abort >/dev/null 2>&1; rc=pm_deferred; [ "$_pcd" = 3 ] && rc=pm_stale
  elif [ "$allow_llm" = 1 ] && try_llm_resolve "$wt" "$repo" "$tgt" "$src"; then
    if timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=llm_resolved
    elif OVN_PM_DEFER=1 timeout 30 git -C "$wt" pull -q --rebase origin "$tgt" >/dev/null 2>&1 && timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=llm_resolved
    else rc=pushfail; fi
  else git -C "$wt" merge --abort >/dev/null 2>&1; rc=conflict; fi
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
  rm -rf "$wt"; trap - EXIT
  echo "$rc"
}

# Bring overnight/feature up to develop. Feature is a superset of develop that only ADDS
# fleet commits, so the common case (feature has no commit develop lacks) is a clean
# fast-forward — do it with a fetch+retry loop so the constantly-pushing fleet can't
# livelock the push (this was the recurring "develop->feature pushfail"). Only when
# feature has its OWN commits do we fall back to a merge. echoes ff|ok|conflict|pushfail|nochange
sync_feature(){  # $1=repo $2=feat-branch — bring origin/<feat> up to origin/develop
  local repo="$1" feat="$2" i uniq
  git -C "$repo" rev-parse --verify -q "origin/$feat" >/dev/null 2>&1 || { echo nobranch; return; }
  for i in 1 2 3 4 5; do
    timeout 30 git -C "$repo" fetch -q origin develop "$feat" 2>/dev/null
    [ "$(git -C "$repo" rev-list --count "origin/$feat..origin/develop" 2>/dev/null || echo 0)" -eq 0 ] && { echo nochange; return; }
    uniq=$(git -C "$repo" rev-list --count "origin/develop..origin/$feat" 2>/dev/null || echo 0)
    if [ "${uniq:-0}" -eq 0 ]; then
      # feature is a subset of develop -> fast-forward feature to develop's tip (no merge commit, no conflict possible)
      timeout 30 git -C "$repo" push -q origin "origin/develop:refs/heads/$feat" 2>/dev/null && { echo ff; return; }
      continue   # rejected = feature moved under us (fleet pushed); refetch + retry
    fi
    merge_into "$repo" "$feat" develop 1; return   # feature has unique commits -> real merge (never force-push); 1=allow one LLM-assisted conflict resolution attempt (feature branch, not production)
  done
  echo pushfail
}

for repo in $repos; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  timeout 30 git -C "$repo" fetch -q origin 2>/dev/null || { log "$name: fetch failed/timed out"; continue; }
  [ "$DRY" = 1 ] || { [ -f "$HOME/overnight-queue/scripts/ovn_progress_merge.py" ] && timeout 30 python3 "$HOME/overnight-queue/scripts/ovn_progress_merge.py" --setup-clone "$repo" >/dev/null 2>&1; true; }   # 2026-10-12: per-clone progress-file merge driver (never global config)
  git -C "$repo" rev-parse --verify -q origin/main    >/dev/null 2>&1 || { continue; }
  git -C "$repo" rev-parse --verify -q origin/develop >/dev/null 2>&1 || { continue; }

  # 1) main -> develop (back-merge). Flag a genuine DIRECT-to-main code commit (not a promote/merge commit).
  m_ahead=$(git -C "$repo" rev-list --count origin/develop..origin/main 2>/dev/null || echo 0)
  if [ "${m_ahead:-0}" -gt 0 ]; then
    # NOTE: no `|| echo 0` here - grep -c ALWAYS prints a valid count (even "0")
    # and only exits 1 to signal "zero matches", which isn't a real failure. The
    # old `|| echo 0` fired on that harmless exit 1 and appended a SECOND "0"
    # line, so $direct became the two-line string "0\n0" whenever a back-merge
    # had zero direct-to-main commits (a pure promote) - `[ "$direct" -gt 0 ]`
    # below then choked with "integer expected" every time that happened.
    direct=$(git -C "$repo" log --format='%s' origin/develop..origin/main 2>/dev/null | grep -vcE '^release: promote|^Merge ')
    if [ "$DRY" = 1 ]; then log "$name: [dry] back-merge main->develop (+$m_ahead, direct=$direct)"
    else
      rc=$(merge_into "$repo" develop main)
      case "$rc" in
        ok) log "$name: back-merged main->develop (+$m_ahead)"; [ "${direct:-0}" -gt 0 ] && directs="$directs ${name}(${direct})";;
        conflict) log "$name: 🔴 CONFLICT main->develop"; conflicts="$conflicts main→develop:${name}";;
        sanityfail) log "$name: 🔴 main->develop merge would have pushed a BROKEN file (see logs/reconcile_sanity.log) - NOT pushed"; conflicts="$conflicts main→develop(sanity):${name}";;
        nochange|pushfail|wterror) log "$name: main->develop $rc";;
        *) _rcs="$(printf '%s' "$rc" | tr '\n' ' ' | cut -c1-60)"; _rcs="${_rcs:-<empty>}"   # 2026-10-13: an EMPTY/unknown result (merge_into died) used to be logged blank and never alert
           log "$name: 🔴 main->develop rc=${_rcs} (unknown/empty result - merge_into died before reporting; treated as a CONFLICT so it alerts)"; conflicts="$conflicts main→develop(rc=${_rcs}):${name}";;
      esac
    fi
  fi

  # 2) develop -> EACH feature branch (overnight/feature = 27B, claude/feature = Claude). Keep both
  #    current so neither falls behind develop when the OTHER branch (or a promote back-merge) lands
  #    on develop. reconcile is the SOLE owner of develop->feature (hygiene no longer pushes feature),
  #    so this runs frequently (every ~20min) and heals the benign two-features-into-develop drift.
  timeout 30 git -C "$repo" fetch -q origin develop 2>/dev/null
  synced_any=0
  for feat in overnight/feature claude/feature; do
    git -C "$repo" rev-parse --verify -q "origin/$feat" >/dev/null 2>&1 || { [ "$DRY" = 1 ] || pm_flag_clear "$repo" "$feat"; continue; }
    d_ahead=$(git -C "$repo" rev-list --count "origin/$feat..origin/develop" 2>/dev/null || echo 0)
    [ "${d_ahead:-0}" -eq 0 ] && { [ "$DRY" = 1 ] || pm_flag_clear "$repo" "$feat"; continue; }   # feature has everything develop has (hygiene landed it): no conflict left
    if [ "$DRY" = 1 ]; then log "$name: [dry] reconcile develop->$feat (+$d_ahead)"; synced_any=1; continue; fi
    rc=$(sync_feature "$repo" "$feat")
    case "$rc" in pm_deferred|pm_stale|pushfail) : ;; *) pm_flag_clear "$repo" "$feat";; esac   # the progress-deferral flag only lives while the progress-only conflict does
    case "$rc" in
      ff) log "$name: fast-forwarded $feat to develop (+$d_ahead)"; synced_any=1;;
      ok) log "$name: merged develop->$feat (+$d_ahead)"; synced_any=1;;
      llm_resolved) log "$name: 🤖 auto-resolved a develop->$feat CONFLICT (LLM-assisted, gate=tests-green)"; resolved="$resolved develop→$feat:${name}"; synced_any=1;;
      pm_deferred) log "$name: develop->$feat conflicts ONLY on progress files - deferred to the hourly hygiene pass (gated deterministic merge; see state/progress_merge.log)"; synced_any=1;;
      pm_stale) log "$name: 🔴 CONFLICT develop->$feat (progress files only; deferred to hygiene for over ${OVN_PM_DEFER_ALERT_H:-6}h and still not landed - check state/progress_merge.log, hygiene gate/QA hold/tree guard)"; conflicts="$conflicts develop→$feat(progress-deferred ${OVN_PM_DEFER_ALERT_H:-6}h+):${name}"; synced_any=1;;
      conflict) log "$name: 🔴 CONFLICT develop->$feat"; conflicts="$conflicts develop→$feat:${name}"; synced_any=1;;
      sanityfail) log "$name: 🔴 develop->$feat merge would have pushed a BROKEN file (see logs/reconcile_sanity.log) - NOT pushed"; conflicts="$conflicts develop→$feat(sanity):${name}"; synced_any=1;;
      pushfail) log "$name: develop->$feat pushfail (fleet racing; next pass retries)"; synced_any=1;;
      nobranch|nochange) : ;;
      wterror) log "$name: develop->$feat $rc";;
      *) _rcs="$(printf '%s' "$rc" | tr '\n' ' ' | cut -c1-60)"; _rcs="${_rcs:-<empty>}"   # 2026-10-13: an EMPTY/unknown result (sync_feature/merge_into died: 7 blank lines on 10-13, no alert) now alerts like a conflict
         log "$name: 🔴 develop->$feat rc=${_rcs} (unknown/empty result - sync_feature/merge_into died before reporting; treated as a CONFLICT so it alerts)"; conflicts="$conflicts develop→$feat(rc=${_rcs}):${name}"; synced_any=1;;
    esac
  done
  [ "$synced_any" = 0 ] && log "$name: in sync (main ⊆ develop ⊆ features)"
done

# Alerts — only when action is needed or something noteworthy happened.
if [ -n "$conflicts" ]; then
  curl -fsS --max-time 8 -H "Title: 🔴 Branch reconcile CONFLICT" -H "Tags: rotating_light" -H "Priority: high" \
    -d "Branches diverged with CONFLICTING edits (auto-reconcile couldn't resolve, needs a human):$conflicts. Resolve the merge manually." \
    "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true
fi
if [ -n "$directs" ]; then
  curl -fsS --max-time 8 -H "Title: Reconciled a direct-to-main commit" -H "Tags: information_source" -H "Priority: low" \
    -d "Found + back-merged a NON-promote commit sitting on main (a chat/hotfix pushed straight to main?):$directs. It's now on develop + feature too — nothing lost. Tip: commit app-repo work to overnight/feature so it rides the gated pipeline." \
    "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true
fi
if [ -n "$resolved" ]; then
  curl -fsS --max-time 8 -H "Title: 🤖 Branch reconcile auto-resolved a conflict" -H "Tags: robot" -H "Priority: default" \
    -d "A develop<->feature conflict was resolved automatically (LLM-assisted, independently re-verified against the repo's real test/build gate before pushing — gate=tests-green):$resolved. Worth a quick look, but no action needed." \
    "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true
fi
log "reconcile complete${conflicts:+ 🔴 conflicts:$conflicts}${directs:+ ℹ direct-to-main:$directs}${resolved:+ 🤖 auto-resolved:$resolved}"
