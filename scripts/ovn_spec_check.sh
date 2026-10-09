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
# Output, one row per `- [ ]` line:   <line-number-in-file> TAB <verdict> TAB <detail> TAB <sub> TAB <rc>
#   red               VERIFY fails by assertion on the current code  -> GOOD spec
#   passes-before     VERIFY already passes                          -> already satisfied (drop / credit)
#   no-verify         the line has no VERIFY clause
#   bad-spec          cannot run (rc 126/127), timed out, denylisted, or CRASHED (Traceback/SyntaxError/missing file) instead of asserting
# spec-compiler-v2 (2026-10-09): columns 1-3 and the verdict set are unchanged (ovn_work_supply parses only `^(\d+)\t(\w[\w-]*)`); <sub> refines the verdict
# (ovn_spec_classify.py: red/assert, red/new-target, bad-spec/crash-unexplained | unrunnable | no-tests-collected | denylisted | no-rc) and <rc> is the VERIFY's exit
# code (a failure found behind exit 0 - GUT, pytest "no tests ran" - reads 1). The VERIFY is extracted with the SAME python helper queue_refill uses, so a bare
# `VERIFY: cmd (cat:` clause is judged instead of reported 'no-verify'. When ovn_spec_classify.py is not next to this script (or under $OVN_DIR/scripts) the legacy regex
# classification runs unchanged (sub empty, rc filled).
# Exit 0 always. Env: OVN_DIR (default ~/overnight-queue), OVN_SPEC_BASE (default origin/overnight/feature), VERIFY_TIMEOUT_SECS (default 60).
set -uo pipefail
repo="${1:-}"; file="${2:-}"
[ -n "$repo" ] && [ -f "$file" ] || { echo "usage: ovn_spec_check.sh <repo> <file>" >&2; exit 0; }
file="$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"   # absolute: the checks run from inside a worktree
OVN_DIR="${OVN_DIR:-$HOME/overnight-queue}"
clone="$OVN_DIR/repos/$repo"
[ -d "$clone/.git" ] || [ -f "$clone/.git" ] || { echo "ovn_spec_check: no clone for $repo" >&2; exit 0; }
base="${OVN_SPEC_BASE:-origin/overnight/feature}"
# OVN_SPEC_WT=<dir>: judge against a worktree the CALLER made and owns (ovn_spec_gate.py scan opens ONE for a whole scan via lib_worktree.sh); it is neither fetched,
# created nor removed here. Unset (every other caller): a private detached worktree of $base, as before.
_EXT_WT=0
if [ -n "${OVN_SPEC_WT:-}" ] && [ -d "$OVN_SPEC_WT" ]; then
  wt="$OVN_SPEC_WT"; _EXT_WT=1
else
  git -C "$clone" fetch -q origin 2>/dev/null || true
  wt="$(mktemp -d "${TMPDIR:-/tmp}/spec-check-XXXXXX")"
fi
cleanup(){ [ "$_EXT_WT" = 1 ] || { git -C "$clone" worktree remove --force "$wt" >/dev/null 2>&1 || rm -rf "$wt"; }; rm -f "${SHADOW_LOG:-/nonexistent}" "${_SC_CANON:-/nonexistent}" "${_SC_ROWS:-/nonexistent}"; }
trap cleanup EXIT
if [ "$_EXT_WT" = 0 ]; then
  git -C "$clone" worktree add -q --detach "$wt" "$base" >/dev/null 2>&1 || { echo "ovn_spec_check: cannot create worktree of $base" >&2; exit 0; }
fi
# the repo's real .venv is untracked; link it so `python3`/pytest VERIFYs resolve the way they do in the fleet
for v in .venv iptv-backend/.venv; do [ -e "$clone/$v" ] && [ -d "$(dirname "$wt/$v")" ] && ln -sfn "$clone/$v" "$wt/$v" 2>/dev/null; done

export SHADOW_LOG; SHADOW_LOG="$(mktemp "${TMPDIR:-/tmp}/spec-check-log-XXXXXX")"
export _REPO_LABEL="$repo"
PROG="$file"; export PROG
# the classifier + shared VERIFY extraction (python helper); absent or broken -> the legacy classification below
_SC_PY=""
for _c in "$OVN_DIR/scripts/ovn_spec_classify.py" "$(dirname "$0")/ovn_spec_classify.py"; do [ -f "$_c" ] && { _SC_PY="$_c"; break; }; done
_SC_CANON=""; _SC_ROWS=""
if [ -n "$_SC_PY" ]; then
  _SC_CANON="$(mktemp "${TMPDIR:-/tmp}/spec-check-canon-XXXXXX")"; _SC_ROWS="$(mktemp "${TMPDIR:-/tmp}/spec-check-rows-XXXXXX")"
  if python3 "$_SC_PY" canon "$file" > "$_SC_CANON" 2>/dev/null && [ -s "$_SC_CANON" ]; then PROG="$_SC_CANON"; else _SC_PY=""; fi
fi
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
  # the output tail only: the log row also carries the VERIFY text (cmd=...), which must never be read as the command's output
  tail_line="$(tail -1 "$SHADOW_LOG" 2>/dev/null | sed -E 's/.*tail=//' | tr '\t\n' '  ' | cut -c1-300)"
  if [ -n "$_SC_PY" ]; then
    printf '%s\t%s\t%s\t%s\t%s\n' "$n" "${_LAST_VERIFY_RESULT:-}" "${_LAST_VERIFY_RC:-}" "$(printf '%s' "${_LAST_VERIFY_WHY:-}" | tr '\t\n' '  ')" "$tail_line" >> "$_SC_ROWS"
    continue
  fi
  case "${_LAST_VERIFY_RESULT:-}" in
    FAIL)
      if printf '%s' "$tail_line" | grep -qE 'Traceback|SyntaxError|NameError|FileNotFoundError|No such file|ModuleNotFoundError|command not found'; then
        printf '%s\tbad-spec\tcrashed instead of asserting: %s\t\t%s\n' "$n" "$(printf '%s' "$tail_line" | cut -c1-120)" "${_LAST_VERIFY_RC:-}"
      else
        printf '%s\tred\t\t\t%s\n' "$n" "${_LAST_VERIFY_RC:-}"
      fi ;;
    PASS)             printf '%s\tpasses-before\t\t\t%s\n' "$n" "${_LAST_VERIFY_RC:-}" ;;
    NO_VERIFY_CLAUSE) printf '%s\tno-verify\t\t\t\n' "$n" ;;
    *)                printf '%s\tbad-spec\t%s %s\t\t%s\n' "$n" "${_LAST_VERIFY_RESULT:-unknown}" "${_LAST_VERIFY_WHY:-}" "${_LAST_VERIFY_RC:-}" ;;
  esac
done < "$PROG"
if [ -n "$_SC_PY" ]; then
  python3 "$_SC_PY" rows "$_SC_CANON" "$_SC_ROWS" 2>/dev/null || true
fi
exit 0
