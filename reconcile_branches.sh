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
conflicts=""; directs=""

# merge origin/<src> into <tgt> in an isolated worktree, push (rebase-retry once). echoes ok|conflict|pushfail|wterror|nochange
merge_into(){
  local repo="$1" tgt="$2" src="$3"
  local ahead; ahead=$(git -C "$repo" rev-list --count "origin/${tgt}..origin/${src}" 2>/dev/null || echo 0)
  [ "${ahead:-0}" -eq 0 ] && { echo nochange; return; }
  local wt; wt="$(mktemp -d "/tmp/reconcile-$(basename "$repo").XXXX")"
  git -C "$repo" worktree add --quiet "$wt" "origin/${tgt}" 2>/dev/null || { echo wterror; return; }
  git -C "$wt" checkout -B "$tgt" "origin/${tgt}" --quiet 2>/dev/null
  local rc=conflict
  if git -C "$wt" -c user.email=fleet@shrike.local -c user.name=shrike-fleet merge --no-ff --no-edit -m "chore(sync): reconcile ${src} -> ${tgt} (branch guard)" "origin/${src}" >/dev/null 2>&1; then
    if git -C "$wt" push -q origin "$tgt" 2>/dev/null; then rc=ok
    elif git -C "$wt" pull -q --rebase origin "$tgt" >/dev/null 2>&1 && git -C "$wt" push -q origin "$tgt" 2>/dev/null; then rc=ok
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
    git -C "$repo" fetch -q origin develop "$feat" 2>/dev/null
    [ "$(git -C "$repo" rev-list --count "origin/$feat..origin/develop" 2>/dev/null || echo 0)" -eq 0 ] && { echo nochange; return; }
    uniq=$(git -C "$repo" rev-list --count "origin/develop..origin/$feat" 2>/dev/null || echo 0)
    if [ "${uniq:-0}" -eq 0 ]; then
      # feature is a subset of develop -> fast-forward feature to develop's tip (no merge commit, no conflict possible)
      git -C "$repo" push -q origin "origin/develop:refs/heads/$feat" 2>/dev/null && { echo ff; return; }
      continue   # rejected = feature moved under us (fleet pushed); refetch + retry
    fi
    merge_into "$repo" "$feat" develop; return   # feature has unique commits -> real merge (never force-push)
  done
  echo pushfail
}

for repo in $repos; do
  [ -d "$repo/.git" ] || continue
  name="$(basename "$repo")"
  git -C "$repo" fetch -q origin 2>/dev/null || { log "$name: fetch failed"; continue; }
  git -C "$repo" rev-parse --verify -q origin/main    >/dev/null 2>&1 || { continue; }
  git -C "$repo" rev-parse --verify -q origin/develop >/dev/null 2>&1 || { continue; }

  # 1) main -> develop (back-merge). Flag a genuine DIRECT-to-main code commit (not a promote/merge commit).
  m_ahead=$(git -C "$repo" rev-list --count origin/develop..origin/main 2>/dev/null || echo 0)
  if [ "${m_ahead:-0}" -gt 0 ]; then
    direct=$(git -C "$repo" log --format='%s' origin/develop..origin/main 2>/dev/null | grep -vcE '^release: promote|^Merge ' || echo 0)
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
  git -C "$repo" fetch -q origin develop 2>/dev/null
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
log "reconcile complete${conflicts:+ 🔴 conflicts:$conflicts}${directs:+ ℹ direct-to-main:$directs}"
