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

# ---------------------------------------------------------------------------------------------------------------------------------
# DIRTY TRACKED LOCKFILES (2026-10-13, night review iptv F9)
# iptv_apps 09:31Z: 'auto-credit: REFUSED - working tree/index differ from AFTER ... (iptv-web/package-lock.json)', then 'push rejected; rebasing ...' and 'error: cannot pull
# with rebase: You have unstaged changes.' - a verified 3492-test cycle was discarded because some step (the npm part of the verify, or aider) re-wrote a tracked lockfile and left the
# tree dirty. Nothing in the log said which step did it.
#   ovn_tree_dirty_note <repo> <task_log> <step>
#       when the TRACKED tree is dirty, append '--- TREE-DIRTY after <step>: <paths> ---' to the task log (the log line names the command that just ran). Always returns 0.
#   ovn_reset_dirty_lockfiles <repo> <task_log> [step]
#       `git checkout --` every dirty tracked LOCKFILE (package-lock.json, yarn.lock, pnpm-lock.yaml, npm-shrinkwrap.json, Pipfile.lock, poetry.lock, uv.lock, Cargo.lock, Gemfile.lock,
#       composer.lock, Podfile.lock, Package.resolved, gradle.lockfile, bun.lock) and log each; any other dirty tracked path is left alone (and listed). Safe at the points it is called
#       from: everything the cycle meant to keep is already COMMITTED there, so a dirty lockfile is tool residue. OVN_LOCKFILE_RESET=off disables. Always returns 0.
# ---------------------------------------------------------------------------------------------------------------------------------
_ovn_is_lockfile() {
  case "${1##*/}" in
    package-lock.json|yarn.lock|pnpm-lock.yaml|npm-shrinkwrap.json|Pipfile.lock|poetry.lock|uv.lock|Cargo.lock|Gemfile.lock|composer.lock|Podfile.lock|Package.resolved|gradle.lockfile|bun.lock) return 0 ;;
  esac
  return 1
}

_ovn_dirty_tracked() {   # one path per line: tracked files with an unstaged or staged change (untracked files are not a rebase blocker)
  git -C "${1:-.}" status --porcelain --untracked-files=no 2>/dev/null | sed -e 's/^...//' -e 's/^.* -> //'
}

ovn_tree_dirty_note() {
  local repo="${1:-.}" tl="${2:-}" step="${3:-step}" paths
  [ -n "$tl" ] || return 0
  paths="$(_ovn_dirty_tracked "$repo" | head -8 | tr '\n' ' ')"
  [ -n "${paths// /}" ] && echo "--- TREE-DIRTY after ${step}: ${paths}---" >> "$tl" 2>/dev/null
  return 0
}

ovn_reset_dirty_lockfiles() {
  local repo="${1:-.}" tl="${2:-/dev/null}" step="${3:-push-retry}" p others="" n=0
  [ "${OVN_LOCKFILE_RESET:-on}" = off ] && return 0
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if _ovn_is_lockfile "$p"; then
      if git -C "$repo" checkout -q HEAD -- "$p" 2>/dev/null; then
        n=$((n + 1)); echo "--- LOCKFILE-RESET (${step}): restored tracked lockfile ${p} to HEAD (a tool left it modified) ---" >> "$tl" 2>/dev/null
      fi
    else
      others="${others}${p} "
    fi
  done < <(_ovn_dirty_tracked "$repo")
  [ -n "$others" ] && echo "--- LOCKFILE-RESET (${step}): non-lockfile tracked change(s) left in place: ${others}---" >> "$tl" 2>/dev/null
  return 0
}
