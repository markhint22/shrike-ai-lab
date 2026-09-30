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
