#!/usr/bin/env bash
# sync_branches.sh — back-merge main -> develop so branches never diverge (2026-09-05).
#
# ROOT CAUSE this fixes: promote_to_prod.sh merges develop -> main with --no-ff, which creates a
# merge commit that lives ONLY on main and is never merged back down. So every promote pushes main
# one commit ahead of develop/feature — forever. Any code committed DIRECTLY to main (e.g. a chat/
# hotfix commit) has the same effect and, worse, never reaches the fleet's working branch.
#
# The Git-Flow fix is a release BACK-MERGE: after main moves, merge main -> develop so develop always
# contains everything main has. overnight/feature then re-converges to develop automatically via
# branch_hygiene's feature-sync step (it force-syncs feature to develop's tip each run). We deliberately
# do NOT touch overnight/feature here (the fleet is actively committing to it) — develop ⊇ main is the
# only invariant needed for clean once-a-day promotes + no drift.
#
# Idempotent: a no-op when develop already contains main. Only alerts on a real conflict (needs a human).
# Wire: called at the end of daily_promote.sh (same-run reconcile) AND on an hourly cron (self-heals an
# accidental direct-to-main commit within the hour).
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH="/usr/local/bin:/usr/bin:/bin:${PATH:-}"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
DRY="${DRY_RUN:-0}"
repos="${*:-repos/billwatch repos/gitlark repos/iptv_apps repos/test-automation-agent repos/shrike-notify repos/shrike-monitor repos/xlite repos/shrike-labs-website}"
log(){ echo "$(date '+%F %T') $*"; }
reconciled=""; conflicts=""

for repo in $repos; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  git -C "$repo" fetch -q origin 2>/dev/null || { log "$name: fetch failed"; continue; }
  git -C "$repo" rev-parse --verify -q origin/main    >/dev/null 2>&1 || { log "$name: no main"; continue; }
  git -C "$repo" rev-parse --verify -q origin/develop >/dev/null 2>&1 || { log "$name: no develop"; continue; }
  behind="$(git -C "$repo" rev-list --count origin/develop..origin/main 2>/dev/null || echo 0)"
  if [ "${behind:-0}" -eq 0 ]; then log "$name: develop already contains main (in sync)"; continue; fi
  if [ "$DRY" = 1 ]; then log "$name: [dry-run] would back-merge main -> develop (+$behind)"; continue; fi
  wt="$(mktemp -d "/tmp/sync-${name}.XXXX")"
  if ! git -C "$repo" worktree add --quiet "$wt" origin/develop 2>/dev/null; then log "$name: worktree add failed"; continue; fi
  git -C "$wt" checkout -B develop origin/develop --quiet 2>/dev/null
  if git -C "$wt" merge --no-ff --no-edit -m "chore(sync): back-merge main -> develop (+$behind: promote/hotfix reconcile)" origin/main >/dev/null 2>&1; then
    if git -C "$wt" push -q origin develop 2>/dev/null; then
      log "$name: back-merged main -> develop (+$behind) — reconciled"; reconciled="$reconciled $name"
    else log "$name: push to develop FAILED"; fi
  else
    git -C "$wt" merge --abort >/dev/null 2>&1
    log "$name: CONFLICT back-merging main -> develop — needs a human"; conflicts="$conflicts $name"
  fi
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
done

if [ -n "$conflicts" ]; then
  curl -fsS --max-time 8 -H "Title: Branch back-merge conflict" -H "Tags: warning" \
    -d "main->develop back-merge conflicted (needs a human):$conflicts. develop and main have conflicting edits — likely a chat/hotfix commit to main touched a file develop also changed." \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
fi
log "sync_branches complete (reconciled:${reconciled:- none})"
