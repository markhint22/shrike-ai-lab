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
try_llm_resolve(){  # $1=worktree $2=main-repo $3=tgt-branch $4=src-branch -> 0=resolved+verified+committed, 1=give up
  local wt="$1" repo="$2" tgt="$3" src="$4"
  local files; files="$(git -C "$wt" diff --name-only --diff-filter=U)"
  [ -z "$files" ] && return 1
  local nfiles; nfiles="$(printf '%s\n' "$files" | grep -c .)"
  [ "$nfiles" -gt 3 ] && return 1
  local fileargs=(); while IFS= read -r fl; do fileargs+=(--file "$fl"); done <<< "$files"
  ( cd "$wt" && timeout 400 "$HOME/aider-venv/bin/aider" --yes-always --no-check-update --no-auto-commits \
      --model openai/qwen-dflash-27B --openai-api-base http://localhost:4000/v1 --openai-api-key sk-shrike-local \
      "${fileargs[@]}" \
      --message "These files have UNRESOLVED git merge conflict markers (<<<<<<<, =======, >>>>>>>) from a real 'git merge' between two branches. Resolve every conflict by keeping BOTH sides' distinct real functionality wherever the two changes are compatible - never silently drop one side's real work. If one side is clearly a placeholder/stub (e.g. returns an empty value with a TODO) and the other is a complete, real implementation, keep the complete one. Remove ALL conflict markers from every file. Do not touch anything outside these exact files." \
  ) >/dev/null 2>&1
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
  local gate_src; gate_src="$(mktemp)"
  sed -n '/^run_gate() {/,/^}/p' "$HOME/overnight-queue/branch_hygiene.sh" > "$gate_src"
  log(){ :; }
  # shellcheck disable=SC1090
  source "$gate_src"; rm -f "$gate_src"
  TEST_TIMEOUT="${TEST_TIMEOUT:-600}"
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
  run_gate "$abs_repo" "$wt" > "$HOME/overnight-queue/logs/reconcile_gate_last.log" 2>&1; local grc=$?
  [ "$grc" -ne 0 ] && return 1   # reject on FAIL(1) and on NOTHING-TO-CHECK(2) alike - no gate, no trust
  git -C "$wt" add -A
  git -C "$wt" -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q \
    -m "chore(sync): reconcile ${src} -> ${tgt} (branch guard, LLM-assisted conflict resolution, gate=tests-green)" >/dev/null 2>&1
}

# merge origin/<src> into <tgt> in an isolated worktree, push (rebase-retry once). $4=1 to allow
# ONE LLM-assisted resolution attempt before giving up (see try_llm_resolve above; only passed by
# the develop<->feature call site). echoes ok|llm_resolved|conflict|pushfail|wterror|nochange
merge_into(){
  local repo="$1" tgt="$2" src="$3" allow_llm="${4:-0}"
  local ahead; ahead=$(git -C "$repo" rev-list --count "origin/${tgt}..origin/${src}" 2>/dev/null || echo 0)
  [ "${ahead:-0}" -eq 0 ] && { echo nochange; return; }
  local wt; wt="$(mktemp -d "/tmp/reconcile-$(basename "$repo").XXXX")"
  git -C "$repo" worktree add --quiet "$wt" "origin/${tgt}" 2>/dev/null || { echo wterror; return; }
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
  if git -C "$wt" -c user.email=fleet@shrike.local -c user.name=shrike-fleet merge --no-ff --no-edit -m "chore(sync): reconcile ${src} -> ${tgt} (branch guard)" "origin/${src}" >/dev/null 2>&1; then
    # timeout on every network call (2026-09-15): an unbounded git push/pull
    # here used to be able to hang indefinitely while holding fd 202
    # (run.lock) from the fleet_autofix.sh caller - see that script's own
    # 2026-09-15 comment for the "orphaned lock, fleet blocked" failure mode
    # this closes off at the source.
    if timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=ok
    elif timeout 30 git -C "$wt" pull -q --rebase origin "$tgt" >/dev/null 2>&1 && timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=ok
    else rc=pushfail; fi
  elif [ "$allow_llm" = 1 ] && try_llm_resolve "$wt" "$repo" "$tgt" "$src"; then
    if timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=llm_resolved
    elif timeout 30 git -C "$wt" pull -q --rebase origin "$tgt" >/dev/null 2>&1 && timeout 30 git -C "$wt" push -q origin "HEAD:$tgt" 2>/dev/null; then rc=llm_resolved
    else rc=pushfail; fi
  else git -C "$wt" merge --abort >/dev/null 2>&1; rc=conflict; fi
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
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
        *) log "$name: main->develop $rc";;
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
    git -C "$repo" rev-parse --verify -q "origin/$feat" >/dev/null 2>&1 || continue
    d_ahead=$(git -C "$repo" rev-list --count "origin/$feat..origin/develop" 2>/dev/null || echo 0)
    [ "${d_ahead:-0}" -eq 0 ] && continue
    if [ "$DRY" = 1 ]; then log "$name: [dry] reconcile develop->$feat (+$d_ahead)"; synced_any=1; continue; fi
    rc=$(sync_feature "$repo" "$feat")
    case "$rc" in
      ff) log "$name: fast-forwarded $feat to develop (+$d_ahead)"; synced_any=1;;
      ok) log "$name: merged develop->$feat (+$d_ahead)"; synced_any=1;;
      llm_resolved) log "$name: 🤖 auto-resolved a develop->$feat CONFLICT (LLM-assisted, gate=tests-green)"; resolved="$resolved develop→$feat:${name}"; synced_any=1;;
      conflict) log "$name: 🔴 CONFLICT develop->$feat"; conflicts="$conflicts develop→$feat:${name}"; synced_any=1;;
      pushfail) log "$name: develop->$feat pushfail (fleet racing; next pass retries)"; synced_any=1;;
      nobranch|nochange) : ;;
      *) log "$name: develop->$feat $rc";;
    esac
  done
  [ "$synced_any" = 0 ] && log "$name: in sync (main ⊆ develop ⊆ features)"
done

# Alerts — only when action is needed or something noteworthy happened.
if [ -n "$conflicts" ]; then
  curl -fsS --max-time 8 -H "Title: 🔴 Branch reconcile CONFLICT" -H "Tags: rotating_light" \
    -d "Branches diverged with CONFLICTING edits (auto-reconcile couldn't resolve, needs a human):$conflicts. Resolve the merge manually." \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
fi
if [ -n "$directs" ]; then
  curl -fsS --max-time 8 -H "Title: Reconciled a direct-to-main commit" -H "Tags: information_source" \
    -d "Found + back-merged a NON-promote commit sitting on main (a chat/hotfix pushed straight to main?):$directs. It's now on develop + feature too — nothing lost. Tip: commit app-repo work to overnight/feature so it rides the gated pipeline." \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
fi
if [ -n "$resolved" ]; then
  curl -fsS --max-time 8 -H "Title: 🤖 Branch reconcile auto-resolved a conflict" -H "Tags: robot" \
    -d "A develop<->feature conflict was resolved automatically (LLM-assisted, independently re-verified against the repo's real test/build gate before pushing — gate=tests-green):$resolved. Worth a quick look, but no action needed." \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
fi
log "reconcile complete${conflicts:+ 🔴 conflicts:$conflicts}${directs:+ ℹ direct-to-main:$directs}${resolved:+ 🤖 auto-resolved:$resolved}"
