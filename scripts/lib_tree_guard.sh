#!/usr/bin/env bash
# scripts/lib_tree_guard.sh - shared tree-content guards for the merge paths (2026-09-30).
#
# ovn_abs_symlinks <repo> <base_ref> <head_ref>
#   Prints every path that <head_ref> ADDS/CHANGES as a symlink whose target is an ABSOLUTE path (one per line), relative to
#   <base_ref>. Such a link is a machine-local artifact: a scratch-worktree helper that symlinks a live .venv/node_modules into
#   its worktree and `git add -A`s it commits one (gitignore `.venv/` with a trailing slash does NOT match a symlink). Merged into
#   the working clones it REPLACES the real .venv directory with a self-referencing link (2026-09-30: four repos' venvs destroyed,
#   verification silently broken). Callers refuse to merge/push when this prints anything.
ovn_abs_symlinks() {
  local repo="$1" base="$2" head="$3" line mode path target
  git -C "$repo" diff --raw --no-renames "$base" "$head" 2>/dev/null | while IFS= read -r line; do
    mode="$(printf '%s' "$line" | awk '{print $2}')"
    [ "$mode" = "120000" ] || continue
    path="$(printf '%s' "$line" | cut -f2)"
    target="$(git -C "$repo" show "$head:$path" 2>/dev/null)"
    case "$target" in /*) printf '%s\n' "$path" ;; esac
  done
}

# ovn_unstage_abs_symlinks <worktree>
#   After a scripted `git add -A` inside a worktree, drop every STAGED symlink whose target is an absolute path from the index (the file
#   stays on disk). The stage runner symlinks the live node_modules into its scratch worktree and commits with `git add -A`; a
#   `.gitignore` entry like `node_modules/` (trailing slash) does not match a symlink, so the link was committed and, when merged into
#   the working clone, replaced the real directory with a self-referencing link (the historic node_modules incident and the 2026-09-30
#   .venv incident). Always returns 0.
ovn_unstage_abs_symlinks() {
  local wt="$1" line mode path target
  git -C "$wt" diff --cached --raw --no-renames 2>/dev/null | while IFS= read -r line; do
    mode="$(printf '%s' "$line" | awk '{print $2}')"
    [ "$mode" = "120000" ] || continue
    path="$(printf '%s' "$line" | cut -f2)"
    target="$(git -C "$wt" show ":$path" 2>/dev/null)"
    case "$target" in /*) git -C "$wt" reset -q -- "$path" 2>/dev/null ;; esac
  done
  return 0
}
