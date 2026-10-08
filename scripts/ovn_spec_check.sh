#!/usr/bin/env bash
# scripts/ovn_spec_check.sh <repo> <file-with-item-lines> - RED-BEFORE check for queue items (architecture rework 2, "spec compiler", 2026-10-08).
#
# A queue item is only a good task if its VERIFY clause FAILS on the code as it is today and can pass after the change. The pipeline never checked the
# first half at ingest: items entered the queue with VERIFYs that (a) already passed (wasted cycle, or a false credit), (b) could not run at all
# (wrong tool/path, exit 127), (c) crashed instead of asserting (SyntaxError/NameError/missing file in a `python -c`), or (d) had no VERIFY. Each of
# those burned attempts that could never land.
#
# For every `- [ ]` line in <file> the item's own VERIFY runs (via the SAME runner the auto-credit uses: lib_verify_clause.sh shadow_check, with its
# denylist, tool-path resolution and timeouts) against a CLEAN detached worktree of origin/overnight/feature - never the live clone the fleet is editing.
# Output, one row per `- [ ]` line:   <line-number-in-file> TAB <verdict> TAB <detail>
#   red               VERIFY fails by assertion on the current code  -> GOOD spec
#   passes-before     VERIFY already passes                          -> already satisfied (drop / credit)
#   no-verify         the line has no `VERIFY: \`cmd\`` clause
#   bad-spec          cannot run (rc 126/127), timed out, denylisted, or CRASHED (Traceback/SyntaxError/missing file) instead of asserting
# Exit 0 always. Env: OVN_DIR (default ~/overnight-queue), OVN_SPEC_BASE (default origin/overnight/feature), VERIFY_TIMEOUT_SECS (default 60).
set -uo pipefail
repo="${1:-}"; file="${2:-}"
[ -n "$repo" ] && [ -f "$file" ] || { echo "usage: ovn_spec_check.sh <repo> <file>" >&2; exit 0; }
file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"   # absolute: the checks run from inside a worktree
OVN_DIR="${OVN_DIR:-$HOME/overnight-queue}"
clone="$OVN_DIR/repos/$repo"
[ -d "$clone/.git" ] || [ -f "$clone/.git" ] || { echo "ovn_spec_check: no clone for $repo" >&2; exit 0; }
base="${OVN_SPEC_BASE:-origin/overnight/feature}"
git -C "$clone" fetch -q origin 2>/dev/null || true
wt="$(mktemp -d "${TMPDIR:-/tmp}/spec-check-XXXXXX")"
cleanup(){ git -C "$clone" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"; rm -f "${SHADOW_LOG:-/nonexistent}"; }
trap cleanup EXIT
git -C "$clone" worktree add -q --detach "$wt" "$base" >/dev/null 2>&1 || { echo "ovn_spec_check: cannot create worktree of $base" >&2; exit 0; }
# the repo's real .venv is untracked; link it so `python3`/pytest VERIFYs resolve the way they do in the fleet
for v in .venv iptv-backend/.venv; do [ -e "$clone/$v" ] && [ -d "$(dirname "$wt/$v")" ] && ln -sfn "$clone/$v" "$wt/$v" 2>/dev/null; done

export SHADOW_LOG; SHADOW_LOG="$(mktemp "${TMPDIR:-/tmp}/spec-check-log-XXXXXX")"
export _REPO_LABEL="$repo"
PROG="$file"; export PROG
_VC_MEMO_ON=0
# shellcheck disable=SC1091
. "$OVN_DIR/scripts/lib_verify_clause.sh" 2>/dev/null || . "$(dirname "$0")/lib_verify_clause.sh"
cd "$wt" || exit 0
n=0
while IFS= read -r line; do
  n=$((n+1))
  case "$line" in "- [ ]"*) ;; *) continue ;; esac
  : > "$SHADOW_LOG"
  shadow_check "$n"
  tail_line="$(tail -1 "$SHADOW_LOG" 2>/dev/null | cut -c1-300)"
  case "${_LAST_VERIFY_RESULT:-}" in
    FAIL)
      if printf '%s' "$tail_line" | grep -qE 'Traceback|SyntaxError|NameError|FileNotFoundError|No such file|ModuleNotFoundError|command not found'; then
        printf '%s\tbad-spec\tcrashed instead of asserting: %s\n' "$n" "$(printf '%s' "$tail_line" | sed -E 's/.*tail=//' | cut -c1-120)"
      else
        printf '%s\tred\t\n' "$n"
      fi ;;
    PASS)             printf '%s\tpasses-before\t\n' "$n" ;;
    NO_VERIFY_CLAUSE) printf '%s\tno-verify\t\n' "$n" ;;
    *)                printf '%s\tbad-spec\t%s %s\n' "$n" "${_LAST_VERIFY_RESULT:-unknown}" "${_LAST_VERIFY_WHY:-}" ;;
  esac
done < "$file"
exit 0
