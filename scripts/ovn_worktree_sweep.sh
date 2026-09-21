#!/usr/bin/env bash
# ovn_worktree_sweep.sh — Phase 2 hardening (orphaned-worktree safety net).
#
# Problem it closes: gap #3's other failure mode. Several scripts (reconcile_branches.sh,
# ovn_stage_runner.sh, promote_to_prod.sh, sync_branches.sh, branch_hygiene.sh) hand-roll
# `git worktree add` + `git worktree remove --force` around their own happy path, with no
# trap on error/kill — if the process dies mid-merge (crash, OOM, host reboot, a stuck
# rebase left mid-conflict), the worktree is never cleaned up. Confirmed live 2026-09-21:
# /tmp/reconcile-billwatch.* sat >24h in a "still merging" state with 3 staged files 84
# commits stale, and /tmp/stage-gitlark.* sat >24h clean-but-detached — both silently
# consuming disk and registered in `git worktree list` with no owning process.
#
# This is a stopgap safety net, not a fix to every hand-rolled call site (those are
# migrated to lib_worktree.sh one at a time per the phased-hardening plan). Any worktree
# whose directory lives under /tmp, is older than SWEEP_MIN_AGE_MIN, and belongs to one of
# the repos we manage gets force-removed + pruned. Age threshold is generous (default 90
# min) versus the longest normal single-script worktree lifetime (~10-15 min) so an
# in-progress legitimate worktree is never at risk of being swept mid-use.
#
# Usage: ./scripts/ovn_worktree_sweep.sh [state_dir]   (state_dir defaults to ./state)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
STATE_DIR="${1:-state}"
ALERTS_FILE="$STATE_DIR/alerts.log"
MIN_AGE_MIN="${SWEEP_MIN_AGE_MIN:-90}"
SWEPT=0

emit_alert() {
  local sev="$1" id="$2" msg="$3"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${sev} | ${id} | ${msg}" >> "$ALERTS_FILE" 2>/dev/null || true
}

for repo_dir in repos/*/; do
  repo="${repo_dir%/}"
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  # `git worktree list --porcelain` prints blank-line-separated stanzas; the first stanza
  # is always the main worktree ($repo itself) — skip it, only sweep linked worktrees.
  while IFS= read -r wt_path; do
    [ -n "$wt_path" ] || continue
    [ "$wt_path" = "$(cd "$repo" && pwd)" ] && continue
    case "$wt_path" in
      /tmp/*) : ;;   # only ever sweep our own tmp-based worktrees, never anything else
      *) continue ;;
    esac
    [ -d "$wt_path" ] || continue
    age_min=$(( ( $(date +%s) - $(stat -c %Y "$wt_path" 2>/dev/null || echo 0) ) / 60 ))
    if [ "$age_min" -ge "$MIN_AGE_MIN" ]; then
      git -C "$wt_path" rebase --abort >/dev/null 2>&1 || true
      git -C "$wt_path" merge --abort >/dev/null 2>&1 || true
      git -C "$repo" worktree remove --force "$wt_path" >/dev/null 2>&1
      rm -rf "$wt_path" 2>/dev/null
      emit_alert warn "worktree-sweep" "removed orphaned worktree ${wt_path} for ${name} (age ${age_min}m, threshold ${MIN_AGE_MIN}m)"
      SWEPT=$((SWEPT + 1))
    fi
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
  git -C "$repo" worktree prune >/dev/null 2>&1 || true
done

[ "$SWEPT" -gt 0 ] && echo "worktree sweep: removed ${SWEPT} orphaned worktree(s)"
exit 0
