#!/usr/bin/env bash
# lib_worktree.sh — Phase 2 (isolated worktree by default) shared helper.
#
# Problem this closes: scripts that `cd repos/<name>` and mutate the shared clone directly
# race the fleet's own continuous loop, which can rewrite the same files underneath them
# mid-edit (hit twice in one night, per the phased-hardening plan's Phase 2 writeup).
#
# Extracts the proven worktree pattern already hand-rolled in promote_to_prod.sh and
# reconcile_branches.sh's merge_into() into one shared set of functions, including the
# critical 2026-09-16 fix documented at length in reconcile_branches.sh: a worktree checked
# out via `checkout -B "$branch" ...` ends up in DETACHED HEAD (git refuses to check out a
# branch that's already checked out in the main clone), so pushing with the ambiguous
# `git push origin "$branch"` silently resolves to the MAIN CLONE's local ref instead of
# this worktree's actual HEAD — `wt_push` always pushes `HEAD:$branch` explicitly to avoid
# that class of bug by construction, not by caller discipline.
#
# Usage:
#   source scripts/lib_worktree.sh
#   wt="$(wt_open repos/billwatch overnight/feature)" || { echo "worktree failed"; exit 1; }
#   ( cd "$wt" && ... do real work, commit ... )
#   wt_push "$wt" overnight/feature || echo "push failed"
#   wt_close repos/billwatch "$wt"
set -uo pipefail

# wt_open <repo_dir> <branch> [--link-venv] [--link-node-modules]
# Creates a detached worktree of <repo_dir> at origin/<branch>, then checks out <branch>
# as a local branch INSIDE the worktree (always ends up detached-but-on-the-right-commit,
# per the note above — this is expected, not a bug, which is exactly why wt_push exists).
# Echoes the worktree path on success (caller captures via command substitution); prints
# nothing and returns 1 on failure so `wt="$(wt_open ...)" || exit` is the correct call
# pattern everywhere.
wt_open(){
  local repo="$1" branch="$2"
  shift 2
  local link_venv=0 link_nm=0
  for a in "$@"; do
    case "$a" in
      --link-venv) link_venv=1 ;;
      --link-node-modules) link_nm=1 ;;
    esac
  done
  [ -d "$repo/.git" ] || return 1
  local wt; wt="$(mktemp -d "/tmp/wt-$(basename "$repo").XXXX")" || return 1
  if ! git -C "$repo" worktree add --quiet "$wt" "origin/${branch}" 2>/dev/null; then
    rmdir "$wt" 2>/dev/null
    return 1
  fi
  # Expected to leave the worktree in DETACHED HEAD when $branch is already checked out
  # in the main clone (the common case for a script operating on the fleet's own working
  # branch) — see the file header. wt_push handles this correctly regardless.
  git -C "$wt" checkout -B "$branch" "origin/${branch}" --quiet 2>/dev/null
  # Optional dependency symlinks so a script that needs to run tests/builds inside the
  # worktree doesn't have to reinstall a fresh .venv/node_modules per invocation — purely
  # additive, a script that doesn't need this (e.g. one that only edits+commits+pushes
  # markdown, like ovn_recover_parked.sh) just never passes the flag.
  if [ "$link_venv" = 1 ] && [ -d "$repo/.venv" ] && [ ! -e "$wt/.venv" ]; then
    ln -s "$repo/.venv" "$wt/.venv" 2>/dev/null
  fi
  if [ "$link_nm" = 1 ] && [ -d "$repo/node_modules" ] && [ ! -e "$wt/node_modules" ]; then
    ln -s "$repo/node_modules" "$wt/node_modules" 2>/dev/null
  fi
  printf '%s\n' "$wt"
}

# wt_push <worktree> <branch> — always HEAD:$branch (never the ambiguous bare $branch
# form), rebase-retry once on a non-fast-forward rejection. Bounded (30s) on every network
# call — an unbounded push/pull here can hang indefinitely while a caller holds an flock'd
# fd, the exact failure mode lib_lock.sh's own bounded-wait exists to prevent one layer up
# (see fleet_autofix.sh's 2026-09-15 note). Echoes ok|pushfail.
wt_push(){
  local wt="$1" branch="$2"
  if timeout 30 git -C "$wt" push -q origin "HEAD:$branch" 2>/dev/null; then
    echo ok; return 0
  fi
  if timeout 30 git -C "$wt" pull -q --rebase origin "$branch" >/dev/null 2>&1 \
     && timeout 30 git -C "$wt" push -q origin "HEAD:$branch" 2>/dev/null; then
    echo ok; return 0
  fi
  # A genuine conflict (not just a non-fast-forward) leaves the worktree mid-rebase —
  # clean that up before returning so the caller never inherits a broken mid-rebase
  # worktree if it reuses this path (matches reconcile_branches.sh's `merge --abort` on
  # its own conflict path). This library never guesses at conflict resolution itself —
  # that's the caller's decision (retry later, escalate, or an opt-in LLM-assist step
  # like reconcile_branches.sh's own try_llm_resolve).
  git -C "$wt" rebase --abort >/dev/null 2>&1 || true
  echo pushfail; return 1
}

# wt_close <repo_dir> <worktree> — always safe to call even if wt_open/wt_push failed
# partway (git worktree remove --force is a no-op on an already-gone path).
wt_close(){
  local repo="$1" wt="$2"
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
}
