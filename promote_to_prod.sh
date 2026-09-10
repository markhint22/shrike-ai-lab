#!/usr/bin/env bash
# Gated promotion of develop (staging) -> main (prod). This is the ONLY path to
# production now that branch_hygiene merges the fleet's work into develop, not main.
#
# For each repo it:
#   1. fetches, shows what would ship (develop..main commit + file diff)
#   2. runs the staging smoke test IF a staging URL is configured for that repo
#      (state/staging_url_<repo> = "<backend_url> [frontend_origin]") — a red smoke
#      test blocks the promote unless --force
#   3. requires typed confirmation (skip with --yes for a scheduled daily promote)
#   4. merges develop -> main --no-ff, pushes (triggers the Railway/Vercel PROD deploy),
#      and tags prod-YYYYMMDD-HHMM-<repo> for one-command rollback
#
# Usage:
#   promote_to_prod.sh repos/billwatch                 # interactive, smoke-gated
#   promote_to_prod.sh --yes repos/billwatch           # non-interactive (cron)
#   promote_to_prod.sh --force repos/billwatch         # promote even if smoke fails
#   promote_to_prod.sh --dry-run repos/billwatch       # show only
set -uo pipefail
DIR="$HOME/overnight-queue"; STATE="$DIR/state"; SMOKE="$DIR/staging_smoke.sh"
YES=0; FORCE=0; DRY=0; NOW="$(date +%Y%m%d-%H%M)"
args=()
for a in "$@"; do case "$a" in
  --yes) YES=1;; --force) FORCE=1;; --dry-run) DRY=1;; *) args+=("$a");; esac; done
[ "${#args[@]}" -gt 0 ] || { echo "usage: promote_to_prod.sh [--yes|--force|--dry-run] repos/<name> ..."; exit 2; }

for repo in "${args[@]}"; do
  name="$(basename "$repo")"
  [ -d "$repo/.git" ] || { echo "SKIP $name (no checkout)"; continue; }
  git -C "$repo" fetch -q origin 2>/dev/null
  DEF="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"; DEF="${DEF:-main}"
  if ! git -C "$repo" rev-parse --verify -q origin/develop >/dev/null; then echo "SKIP $name (no develop)"; continue; fi
  ahead="$(git -C "$repo" rev-list --count origin/$DEF..origin/develop 2>/dev/null || echo 0)"
  echo "=================================================================="
  echo "$name: develop is +$ahead ahead of $DEF"
  [ "${ahead:-0}" -eq 0 ] && { echo "  nothing to promote."; continue; }
  git -C "$repo" log --oneline "origin/$DEF..origin/develop" | sed 's/^/    /' | head -20
  echo "  files:"; git -C "$repo" diff --stat "origin/$DEF..origin/develop" | tail -12 | sed 's/^/    /'

  # staging smoke gate
  surl="$STATE/staging_url_${name}"
  if [ -f "$surl" ]; then
    echo "  -- staging smoke ($(cat "$surl")) --"
    if bash "$SMOKE" $(cat "$surl"); then smoke_ok=1; else smoke_ok=0; fi
    if [ "$smoke_ok" -ne 1 ] && [ "$FORCE" -ne 1 ]; then echo "  🔴 smoke failed — NOT promoting $name (use --force to override)"; continue; fi
  else
    echo "  ⚠️  no staging URL configured (state/staging_url_${name}) — smoke test SKIPPED."
    [ "$YES" -ne 1 ] && [ "$FORCE" -ne 1 ] && echo "     (promoting without a staging check — configure staging to make this safe)"
  fi

  # migration safety gate before prod (2026-09-03)
  if [ -f "$DIR/scripts/check_migrations.py" ] && ! python3 "$DIR/scripts/check_migrations.py" "$repo" >/dev/null 2>&1; then
    echo "  🔴 migration safety FAILED — NOT promoting $name"; python3 "$DIR/scripts/check_migrations.py" "$repo" 2>&1 | grep "✗" | head -3 | sed "s/^/    /"; continue
  fi
  [ "$DRY" -eq 1 ] && { echo "  [dry-run] would merge develop -> $DEF, push (PROD deploy), tag prod-$NOW-$name"; continue; }

  if [ "$YES" -ne 1 ]; then
    printf "  Type 'ship %s' to promote to PROD: " "$name"; read -r ans
    [ "$ans" = "ship $name" ] || { echo "  aborted."; continue; }
  fi

  wt="$(mktemp -d "/tmp/promote-${name}.XXXX")"
  if ! git -C "$repo" worktree add -q "$wt" "origin/$DEF" 2>/dev/null; then echo "  worktree failed"; continue; fi
  git -C "$wt" checkout -qB "$DEF" "origin/$DEF"
  if git -C "$wt" merge --no-ff --no-edit -m "release: promote develop -> $DEF ($NOW)" origin/develop >/dev/null 2>&1; then
    git -C "$wt" tag "prod-$NOW-$name" 2>/dev/null || true
    if git -C "$wt" push -q origin "$DEF" && git -C "$wt" push -q origin "prod-$NOW-$name" 2>/dev/null; then
      echo "  ✅ PROMOTED $name develop -> $DEF (+$ahead). Prod deploy triggered. Rollback: git checkout prod-$NOW-$name"
    else echo "  ⚠️ push failed"; fi
  else
    git -C "$wt" merge --abort >/dev/null 2>&1; echo "  🔴 merge conflict develop vs $DEF — resolve manually"
  fi
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
done
