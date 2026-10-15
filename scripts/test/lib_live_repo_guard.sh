# scripts/test/lib_live_repo_guard.sh - SOURCE this from any test runner / test library (run_all.sh, lib_ro_core.sh).
#
# 2026-10-14 incident: test_udiff_unanchored.sh's mkloop() did `( cd "$R/$1" && python3 ... ) ; git add -A; git commit -m "big file"` - when the cd failed the
# bare git add/commit ran in the caller's cwd = the LIVE ~/overnight-queue repo and swept logs/ (a 133 MB branch_hygiene.log) + state/ into live history
# as 't <t@t>' commits ('base' / 'big file'); GitHub then rejected every ovn_git_sync push for ~20 h.
#
# Defines a `git` shell function (NOT exported). It refuses every history/index/work-tree
# MUTATING subcommand (add commit reset checkout switch restore rm clean stash merge rebase push cherry-pick revert update-ref am apply, and branch/tag
# when they would create/delete) whose target repo toplevel is the PROTECTED repo = the repo that contains this suite (override: OVN_LIVE_GUARD_TOP).
# Test scratch repos live under mktemp dirs, so a legitimate test never trips it. On a hit it prints a LIVE-REPO-GUARD line to stderr, appends it to
# $OVN_LIVE_GUARD_LOG, SIGTERMs the guard owner (the top-level test/run_all shell - the hard abort) and returns 97 for the failing command.
# OVN_LIVE_GUARD_OFF=1 disables it (only the guard's own mutation test uses that).
# 2026-10-14 (queue fix): exporting a function named `git` made `command -v git` return the literal name "git" in every child bash, so test shims that did
# REALGIT="$(command -v git)" + `exec "$REALGIT"` looped on themselves forever (R-state spin, hung the full box run). The guard therefore no longer
# exports the function, and it calls the real binary captured by path BEFORE the function is defined. Shims must resolve git with `type -P git`.
# Children that are separate bash processes are NOT guarded by this function; in-process callers (run_all.sh, lib_ro_core.sh, subshells) are.
OVN_LIVE_GUARD_LOG="${OVN_LIVE_GUARD_LOG:-${TMPDIR:-/tmp}/ovn_live_repo_guard.log}"
# Real binary by PATH, resolved before the `git` function below exists (type -P ignores functions and aliases).
OVN_REAL_GIT="$(type -P git 2>/dev/null)"
# 2026-10-14 (box run): TOP and OWNER are per-shell state, so they are NOT exported. The old code exported both, so a child test sourced the
# parent's guard: run_all.sh's OWNER (its own pid) was inherited, the guard in a test's `( ... git commit )` then SIGTERMed run_all itself
# (the run ended silently with no banner), and TOP was the parent's repo, so a throwaway repo inside a child test was not protected.
# Each sourcing shell now protects the repo that holds this lib (unless the caller sets OVN_LIVE_GUARD_TOP in its own shell) and is the owner
# that a refused command aborts. $$ inside a ( ... ) subshell is still the main shell pid, so a subshell refusal aborts the owner.
if [ -z "${OVN_LIVE_GUARD_TOP:-}" ]; then
  OVN_LIVE_GUARD_TOP="$("${OVN_REAL_GIT:-git}" -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)"
fi
[ -n "${OVN_LIVE_GUARD_TOP:-}" ] && OVN_LIVE_GUARD_TOP="$(cd "$OVN_LIVE_GUARD_TOP" 2>/dev/null && pwd -P)"
OVN_LIVE_GUARD_OWNER="$$"
export OVN_LIVE_GUARD_LOG OVN_REAL_GIT

git() {
  if [ "${OVN_LIVE_GUARD_OFF:-0}" != "1" ] && [ -n "${OVN_LIVE_GUARD_TOP:-}" ]; then
    local dir="." sub="" a d rest=()
    local args=("$@") i=0 n=$#
    while [ "$i" -lt "$n" ]; do
      a="${args[$i]}"
      if [ -z "$sub" ]; then
        case "$a" in
          -C) i=$((i+1)); d="${args[$i]:-.}"; case "$d" in /*) dir="$d";; *) dir="$dir/$d";; esac;;
          -c|--exec-path|--namespace|--super-prefix|--config-env) i=$((i+1));;
          --git-dir|--work-tree) i=$((i+1)); dir="${args[$i]:-.}";;
          --git-dir=*|--work-tree=*) dir="${a#*=}";;
          -*) ;;
          *) sub="$a";;
        esac
      else
        rest+=("$a")
      fi
      i=$((i+1))
    done
    local mut=0
    case "$sub" in
      add|commit|reset|checkout|switch|restore|rm|clean|stash|merge|rebase|push|cherry-pick|revert|update-ref|am|apply|mv) mut=1;;
      branch|tag) for a in "${rest[@]+"${rest[@]}"}"; do case "$a" in -d|-D|-m|-M|-f|-c|-C|--delete|--move|--force|--copy|--set-upstream-to=*|-u) mut=1;; -*) ;; *) mut=1;; esac; done;;
    esac
    if [ "$mut" = 1 ]; then
      local top; top="$(cd "$dir" 2>/dev/null && "${OVN_REAL_GIT:-git}" rev-parse --show-toplevel 2>/dev/null)"
      [ -n "$top" ] && top="$(cd "$top" 2>/dev/null && pwd -P)"
      if [ -n "$top" ] && [ "$top" = "$OVN_LIVE_GUARD_TOP" ]; then
        local msg="LIVE-REPO-GUARD: refused 'git $sub' in the protected repo $top (cwd=$PWD dir=$dir, caller=${BASH_SOURCE[1]:-?}:${BASH_LINENO[0]:-?}) - a test subshell lost its cd; aborting"
        echo "$msg" >&2
        printf '%s pid=%s %s\n' "$(date '+%F %T')" "$$" "$msg" >> "$OVN_LIVE_GUARD_LOG" 2>/dev/null
        kill -TERM "$OVN_LIVE_GUARD_OWNER" 2>/dev/null
        return 97
      fi
    fi
  fi
  if [ -n "${OVN_REAL_GIT:-}" ]; then "$OVN_REAL_GIT" "$@"; else command git "$@"; fi
}
