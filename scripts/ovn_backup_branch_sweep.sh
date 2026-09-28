#!/usr/bin/env bash
# ovn_backup_branch_sweep.sh — orphaned backup-diverged-* branch safety net.
#
# Problem it closes: run_overnight.sh's divergence-heal path creates a backup-diverged-*
# branch before resetting a diverged clone, then either auto-recovers it (cherry-pick +
# push, the common case) or falls back to an alert asking for review. Confirmed live
# 2026-09-26: 14 such branches had accumulated across billwatch/iptv_apps/shrike-monitor
# over 3 weeks with ZERO follow-up — the alert-and-hope path depends on someone actually
# reading the alert, and evidently nobody had, even after the alert was made much more
# informative. This is a standalone backstop, independent of that logic ever working
# correctly: anything whose content has already landed (auto-recovered, or resolved
# another way entirely) gets cleaned up automatically; anything still unresolved after a
# grace period gets a loud, RE-ESCALATING alert with a diff summary, so it can never again
# go unnoticed for weeks — it has to be actively silenced (or fixed) to stop recurring.
#
# Deliberately a separate script, not inlined into branch_hygiene.sh: matches this
# codebase's existing convention (ovn_worktree_sweep.sh is the same shape of backstop for
# orphaned /tmp worktrees) and keeps branch_hygiene.sh's own already-long per-repo build+
# test gate from growing another concern. Cheap enough (branch listing + merge-base checks,
# no builds) to run far more often than branch_hygiene.sh itself.
#
# Usage: ./scripts/ovn_backup_branch_sweep.sh [state_dir]   (state_dir defaults to ./state)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
STATE_DIR="${1:-state}"
ALERTS_FILE="$STATE_DIR/alerts.log"
SEEN_DIR="$STATE_DIR/backup_branch_seen"
mkdir -p "$SEEN_DIR" 2>/dev/null
GRACE_MIN="${BACKUP_SWEEP_GRACE_MIN:-60}"          # skip anything younger than this (avoid alerting on something a human is mid-resolving)
REALERT_HOURS="${BACKUP_SWEEP_REALERT_HOURS:-24}"  # re-alert cadence for a still-unresolved orphan (escalating, not one-and-done)
CLEANED=0
FLAGGED=0

emit_alert() {
  local sev="$1" id="$2" msg="$3"
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${sev} | ${id} | ${msg}" >> "$ALERTS_FILE" 2>/dev/null || true
}

for repo_dir in repos/*/; do
  repo="${repo_dir%/}"
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"

  branches="$(git -C "$repo" branch --format='%(refname:short)' 2>/dev/null | grep '^backup-diverged-' || true)"
  [ -n "$branches" ] || continue

  git -C "$repo" fetch -q origin overnight/feature claude/feature develop 2>/dev/null

  while IFS= read -r b; do
    [ -n "$b" ] || continue
    # backup-diverged-<id>-<YYYYMMDD>-<HHMMSS> — parse the trailing timestamp for age,
    # independent of any filesystem mtime (git refs don't reliably carry one, and
    # packed-refs vs loose-ref storage would make that inconsistent anyway).
    ts="$(printf '%s' "$b" | grep -oE '[0-9]{8}-[0-9]{6}$')"
    [ -n "$ts" ] || continue
    b_epoch="$(date -d "${ts:0:8} ${ts:9:2}:${ts:11:2}:${ts:13:2}" +%s 2>/dev/null || echo 0)"
    [ "$b_epoch" -gt 0 ] || continue
    age_min=$(( ( $(date +%s) - b_epoch ) / 60 ))

    tip="$(git -C "$repo" rev-parse "$b" 2>/dev/null)"
    [ -n "$tip" ] || continue

    # "Landed" = an ancestor of ANY currently-tracked branch, not just the one it
    # diverged from — content can reach the mainline via auto-recovery, a manual
    # cherry-pick, or a completely different resolution path.
    #
    # 2026-09-28 FIX: the ancestor check alone misses the MOST COMMON resolution path -
    # run_overnight.sh's own auto-recovery uses `git cherry-pick -x`, which creates a
    # NEW commit (different hash, different parent) carrying a standard
    # "(cherry picked from commit $tip)" trailer. Confirmed live: a billwatch backup
    # branch was successfully auto-recovered and even auto-retired downstream, yet this
    # script still alerted "never auto-recovered" an hour later, because is-ancestor can
    # never match a cherry-picked commit by construction - it has a different hash. Check
    # every commit unique to the backup branch (not just its tip - a multi-commit
    # divergence needs every one of its commits accounted for, not just the last) against
    # both detection paths before concluding it is genuinely unresolved.
    landed=0
    origin_base=""
    for probe in origin/overnight/feature origin/claude/feature origin/develop; do
      git -C "$repo" rev-parse --verify --quiet "$probe" >/dev/null 2>&1 && { origin_base="$probe"; break; }
    done
    if [ -n "$origin_base" ]; then
      div_mb="$(git -C "$repo" merge-base "$origin_base" "$b" 2>/dev/null)"
      div_commits="$(git -C "$repo" log --format=%H "${div_mb}..${b}" 2>/dev/null)"
    else
      div_commits="$tip"
    fi
    [ -n "$div_commits" ] || div_commits="$tip"
    for target in origin/overnight/feature origin/claude/feature origin/develop; do
      git -C "$repo" rev-parse --verify --quiet "$target" >/dev/null 2>&1 || continue
      all_landed=1
      # Only scan commits target gained SINCE this backup diverged - a cherry-picked
      # replay can only ever land after that point, and this keeps the scan bounded
      # instead of walking the target's entire history on every sweep.
      target_new="$(git -C "$repo" log --format=%B "${div_mb}..${target}" 2>/dev/null)"
      while IFS= read -r c; do
        [ -n "$c" ] || continue
        if git -C "$repo" merge-base --is-ancestor "$c" "$target" 2>/dev/null; then
          continue
        fi
        if printf '%s' "$target_new" | grep -qF "cherry picked from commit $c"; then
          continue
        fi
        all_landed=0
        break
      done <<< "$div_commits"
      [ "$all_landed" = 1 ] && { landed=1; break; }
    done

    if [ "$landed" = 1 ]; then
      git -C "$repo" branch -D "$b" >/dev/null 2>&1
      rm -f "$SEEN_DIR/${name}__${b}" 2>/dev/null
      CLEANED=$((CLEANED + 1))
      continue
    fi

    [ "$age_min" -lt "$GRACE_MIN" ] && continue

    seenf="$SEEN_DIR/${name}__${b}"
    last_alert="$(cat "$seenf" 2>/dev/null || echo 0)"
    if [ $(( $(date +%s) - last_alert )) -ge $(( REALERT_HOURS * 3600 )) ]; then
      # merge-base-relative, NOT a raw two-endpoint diff — a raw diff against the current
      # tip would also pick up whatever origin changed in parallel since the divergence,
      # misrepresenting what this branch itself actually contains.
      base_ref="origin/overnight/feature"
      git -C "$repo" rev-parse --verify --quiet "$base_ref" >/dev/null 2>&1 || base_ref="origin/develop"
      mb="$(git -C "$repo" merge-base "$base_ref" "$b" 2>/dev/null)"
      subjects="$(git -C "$repo" log --oneline "${mb}..${b}" 2>/dev/null | tr '\n' ';' | cut -c1-300)"
      diffstat="$(git -C "$repo" diff --stat "$mb" "$b" 2>/dev/null | tail -3 | tr '\n' ' ' | cut -c1-200)"
      emit_alert warn "backup-branch-sweep-${name}" "${name}: unresolved backup branch ${b} (age ${age_min}m, not yet landed on overnight/feature|claude/feature|develop) — was never auto-recovered and nobody has acted on it. Commits: ${subjects} | Files: ${diffstat}"
      date +%s > "$seenf"
      FLAGGED=$((FLAGGED + 1))
    fi
  done <<< "$branches"
done

[ "$CLEANED" -gt 0 ] && echo "backup-branch sweep: cleaned up ${CLEANED} already-landed branch(es)"
[ "$FLAGGED" -gt 0 ] && echo "backup-branch sweep: flagged ${FLAGGED} unresolved orphan(s)"
exit 0
