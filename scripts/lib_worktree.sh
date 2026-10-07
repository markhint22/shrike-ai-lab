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

# wt_open <repo_dir> <branch> [--link-venv] [--link-node-modules] [--detach] [--tag=<name>]
# Creates a detached worktree of <repo_dir> at origin/<branch>, then checks out <branch>
# as a local branch INSIDE the worktree (always ends up detached-but-on-the-right-commit,
# per the note above — this is expected, not a bug, which is exactly why wt_push exists).
# Echoes the worktree path on success (caller captures via command substitution); prints
# nothing and returns 1 on failure so `wt="$(wt_open ...)" || exit` is the correct call
# pattern everywhere.
# 2026-10-02: --detach leaves the worktree on the bare origin/<branch> commit and SKIPS the `checkout -B`
# below. That -B resets the LOCAL <branch> ref whenever the main clone is not itself on <branch>, which a
# read-only caller (ovn_test_watch.sh: tests origin/overnight/feature without ever touching the live clone)
# must never do. --tag=<name> puts the name in the dir (/tmp/wt-<tag>-<repo>.XXXX) so a caller's worktrees are
# recognisable to ovn_worktree_sweep.sh / its own startup reaper. Both additive; no existing caller passes them.
wt_open(){
  local repo="$1" branch="$2"
  shift 2
  local link_venv=0 link_nm=0 detach=0 tag=""
  for a in "$@"; do
    case "$a" in
      --link-venv) link_venv=1 ;;
      --link-node-modules) link_nm=1 ;;
      --detach) detach=1 ;;
      --tag=*) tag="${a#--tag=}" ;;
    esac
  done
  [ -d "$repo/.git" ] || return 1
  local wt; wt="$(mktemp -d "/tmp/wt-${tag:+$tag-}$(basename "$repo").XXXX")" || return 1
  if ! git -C "$repo" worktree add --quiet "$wt" "origin/${branch}" 2>/dev/null; then
    rmdir "$wt" 2>/dev/null
    return 1
  fi
  # Expected to leave the worktree in DETACHED HEAD when $branch is already checked out
  # in the main clone (the common case for a script operating on the fleet's own working
  # branch) — see the file header. wt_push handles this correctly regardless.
  [ "$detach" = 1 ] || git -C "$wt" checkout -B "$branch" "origin/${branch}" --quiet 2>/dev/null
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

# wt_link_envs <repo_dir> <worktree> — symlink EVERY provisioned .venv / node_modules of the live clone
# (any depth <= 4, e.g. backend/.venv, web/node_modules) into the same relative spot of <worktree>, so a
# detached worktree can run the repo's real test suites without re-provisioning. 2026-10-02 (ovn_test_watch
# worktree redesign): wt_open's --link-venv/--link-node-modules only cover the repo ROOT, but every fleet repo
# keeps its envs in subdirs. Only links where the parent dir exists in the worktree and nothing is there yet
# (never clobbers a tracked path). Symlinks are untracked and must never be committed (no `git add -A` in a
# worktree that went through this) - wt_close/`rm -rf` removes the link, never the live env it points at.
wt_link_envs(){
  local repo="$1" wt="$2" abs rel
  repo="$(cd "$repo" 2>/dev/null && pwd)" || return 1
  while IFS= read -r abs; do
    [ -n "$abs" ] || continue
    rel="${abs#"$repo"/}"
    [ -d "$wt/$(dirname "$rel")" ] || continue
    [ -e "$wt/$rel" ] || [ -L "$wt/$rel" ] || ln -s "$abs" "$wt/$rel" 2>/dev/null
  done < <(find "$repo" -maxdepth 4 -type d \( -name .git -prune -o \( -name .venv -o -name node_modules \) -print -prune \) 2>/dev/null)
  return 0
}

# wt_seed_godot <repo_dir> <worktree> [<subdir>] — COPY (never symlink: godot writes into it, and the fleet's own
# gates run godot on the live clone at the same time) the live clone's gitignored import cache (.godot/ and
# *.import) for the project under <subdir> into the worktree, so the headless --import there is an incremental
# no-op instead of re-importing every asset inside ovn_test_watch's 90s import cap (xlite: 560 *.import + 23MB).
wt_seed_godot(){
  local repo="$1" wt="$2" sub="${3:-.}"
  command -v rsync >/dev/null 2>&1 || return 0
  git -C "$repo" ls-files -z --others --ignored --exclude-standard -- "$sub" 2>/dev/null \
    | grep -zE '(^|/)\.godot/|\.import$' \
    | rsync -a --from0 --files-from=- "$repo/" "$wt/" >/dev/null 2>&1 || true
  return 0
}
