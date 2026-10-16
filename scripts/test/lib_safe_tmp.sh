# scripts/test/lib_safe_tmp.sh - SOURCE from tests that make a sandbox and later rm -rf inside it. 2026-10-16 (incident: HOME-deletion on the GPU box).
#
# Incident: tmp="$(mktemp -d)" under `set -uo pipefail` (no -e) failed (TMPDIR gone), tmp was empty, the test then did export HOME="$tmp/home" (= /home) and rm -rf "$HOME":
# the whole real home of the box user was deleted. These helpers FAIL CLOSED: nothing is created or removed unless every check passes.
#
#   tmp="$(safe_mktemp_dir)" || exit 1          # prints a canonical dir; non-zero + message on stderr when mktemp failed / empty / not a dir /
#                                               # not under TMPDIR / equal to HOME, /, /home, /tmp, /var, /Users ...
#   safe_set_sandbox_home "$tmp" || exit 1      # export HOME="$tmp/home" after a hard check that tmp is a real temp dir under the temp root (mkdir -p's it)
#   safe_rm_rf "$tmp/x" "$tmp/y"                # refuses (returns 1, removes nothing) for: empty, non-absolute, any .. component, / , /home, HOME, an ancestor of the REAL home,
#                                               # fewer than 3 path components, a git checkout / worktree root (has a .git entry), and anything not STRICTLY under an allowed sandbox root
# Allowed sandbox roots: $TMPDIR (when it is an existing dir that is not itself a dangerous path), the OS per-user temp dir when TMPDIR is unset (/tmp, or /var/folders/.. on macOS),
# and every colon-separated entry of OVN_SAFE_RM_ROOTS. NOT the shared /tmp when TMPDIR points elsewhere (other worktrees and sessions live there). A caller whose sandbox lives
# elsewhere sets OVN_SAFE_RM_ROOTS to that exact root (never to HOME or /).
# The real HOME is captured at source time (OVN_SAFE_REAL_HOME): source this BEFORE the test reassigns HOME. safe_rm_rf refuses it and every ancestor of it.
# bash 3.2 (Mac) and bash 5 safe. No `set -e` assumptions.

__st_phys(){ # physical (symlink-resolved) absolute form of an existing dir; empty when it cannot be resolved
  ( cd "$1" 2>/dev/null && pwd -P ) 2>/dev/null
}
__st_dangerous(){ # rc 0 when $1 (a path, raw or physical) is a path that must never be a sandbox root or removal target
  local p="${1%/}" h
  [ -n "$p" ] || return 0
  case "$p" in /|/home|/tmp|/private|/private/tmp|/var|/private/var|/Users|/root|/etc|/usr|/bin|/opt|/mnt|/media|/srv|/Volumes|/System|/Library|/var/tmp|/var/folders|/private/var/folders) return 0;; esac
  for h in "${HOME:-}" "${OVN_SAFE_REAL_HOME:-}"; do
    h="${h%/}"
    [ -n "$h" ] || continue
    # a HOME that safe_set_sandbox_home created under the temp root is resettable (rm -rf "$HOME" between cases); the REAL home never is
    [ "$p" = "$h" ] && [ "$p" = "${OVN_SAFE_SANDBOX_HOME:-}" ] && [ "$p" != "${OVN_SAFE_REAL_HOME:-}" ] && continue
    [ "$p" = "$h" ] && return 0
  done
  return 1
}
__st_ncomp(){ # number of path components of an absolute path
  local p="$1" n=0 IFS=/ c
  for c in $p; do [ -n "$c" ] && n=$((n+1)); done
  echo "$n"
}
__st_roots(){ # prints the allowed sandbox roots (raw and physical), one per line
  local r d
  if [ -n "${TMPDIR:-}" ]; then
    if [ -d "$TMPDIR" ] && ! __st_dangerous "$TMPDIR"; then
      echo "${TMPDIR%/}"; d="$(__st_phys "$TMPDIR")"; [ -n "$d" ] && ! __st_dangerous "$d" && echo "$d"
    fi
  else
    # TMPDIR unset: the OS default per-user temp location (what mktemp -d uses)
    for r in "$(getconf DARWIN_USER_TEMP_DIR 2>/dev/null)" /tmp; do
      [ -n "$r" ] && [ -d "$r" ] || continue
      echo "${r%/}"; d="$(__st_phys "$r")"; [ -n "$d" ] && echo "$d"
    done
  fi
  if [ -n "${OVN_SAFE_RM_ROOTS:-}" ]; then
    printf '%s\n' "$OVN_SAFE_RM_ROOTS" | tr ':' '\n' | while IFS= read -r r; do
      [ -n "$r" ] && [ -d "$r" ] && ! __st_dangerous "$r" || continue
      echo "${r%/}"; d="$(__st_phys "$r")"; [ -n "$d" ] && ! __st_dangerous "$d" && echo "$d"
    done
  fi
}
__st_under_root(){ # rc 0 when $1 is STRICTLY under one of the allowed sandbox roots
  local p="$1" r
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    case "$p" in "$r"/?*) return 0;; esac
  done <<EOF
$(__st_roots)
EOF
  return 1
}

safe_mktemp_dir(){ # [mktemp args...] -> prints the new dir; non-zero (and nothing printed) on any failed check
  local d p
  d="$(mktemp -d "$@" 2>/dev/null)" || { echo "safe_mktemp_dir: mktemp -d failed (TMPDIR='${TMPDIR:-}') - refusing to continue" >&2; return 1; }
  [ -n "$d" ] || { echo "safe_mktemp_dir: mktemp returned an empty path" >&2; return 1; }
  [ -d "$d" ] || { echo "safe_mktemp_dir: '$d' is not a directory" >&2; return 1; }
  p="$(__st_phys "$d")"
  [ -n "$p" ] || { echo "safe_mktemp_dir: cannot resolve '$d'" >&2; return 1; }
  if __st_dangerous "$d" || __st_dangerous "$p"; then
    echo "safe_mktemp_dir: '$d' is a protected path (HOME, /, /home, /tmp ...)" >&2; rmdir "$d" 2>/dev/null; return 1
  fi
  if [ -n "${TMPDIR:-}" ]; then
    # TMPDIR set: the new dir must be under it (raw or physical) - mktemp silently falling back elsewhere is not acceptable
    local t tp ok=0; t="${TMPDIR%/}"; tp="$(__st_phys "$TMPDIR")"
    case "$d" in "$t"/?*) ok=1;; esac
    if [ "$ok" = 0 ] && [ -n "$tp" ]; then case "$p" in "$tp"/?*) ok=1;; esac; fi
    [ "$ok" = 1 ] || { echo "safe_mktemp_dir: '$d' is not under TMPDIR '$TMPDIR'" >&2; return 1; }
  else
    __st_under_root "$p" || { echo "safe_mktemp_dir: '$d' is not under a temp root" >&2; return 1; }
  fi
  [ "$(__st_ncomp "$p")" -ge 3 ] || { echo "safe_mktemp_dir: '$p' has fewer than 3 path components" >&2; return 1; }
  printf '%s\n' "$p"
}

safe_set_sandbox_home(){ # $1 = a dir returned by safe_mktemp_dir -> export HOME="$1/home" (created); hard check before the assignment
  local t="$1" p
  [ -n "$t" ] || { echo "safe_set_sandbox_home: empty sandbox root - refusing (HOME would become /home)" >&2; return 1; }
  [ -d "$t" ] || { echo "safe_set_sandbox_home: '$t' is not a directory" >&2; return 1; }
  p="$(__st_phys "$t")"
  if [ -z "$p" ] || __st_dangerous "$p" || ! __st_under_root "$p"; then
    echo "safe_set_sandbox_home: '$t' is not strictly under a temp root - refusing" >&2; return 1
  fi
  [ "$(__st_ncomp "$p")" -ge 3 ] || { echo "safe_set_sandbox_home: '$p' too shallow" >&2; return 1; }
  mkdir -p "$p/home" || return 1
  export HOME="$p/home"; OVN_SAFE_SANDBOX_HOME="$HOME"
  # post-condition: HOME is under the sandbox and is not the real home
  case "$HOME" in "$p"/home) :;; *) echo "safe_set_sandbox_home: post-check failed" >&2; return 1;; esac
  [ "$HOME" != "${OVN_SAFE_REAL_HOME:-}" ] || return 1
  return 0
}

safe_rm_rf(){ # paths... -> rm -rf each one that passes every check; returns 1 if ANY was refused (the others are still processed)
  local rc=0 a p d b ncomp h
  [ "$#" -gt 0 ] || { echo "safe_rm_rf: no path given" >&2; return 1; }
  for a in "$@"; do
    [ -n "$a" ] || { echo "safe_rm_rf: refusing empty path" >&2; rc=1; continue; }
    case "$a" in /*) :;; *) echo "safe_rm_rf: refusing non-absolute path '$a'" >&2; rc=1; continue;; esac
    case "$a" in */..|*/../*|../*|*/.) echo "safe_rm_rf: refusing path with a dot component '$a'" >&2; rc=1; continue;; esac
    a="${a%/}"
    [ -n "$a" ] || { echo "safe_rm_rf: refusing /" >&2; rc=1; continue; }
    if [ ! -e "$a" ] && [ ! -L "$a" ]; then continue; fi          # nothing to remove: not an error
    d="$(dirname "$a")"; b="$(basename "$a")"
    p="$(__st_phys "$d")"
    [ -n "$p" ] || { echo "safe_rm_rf: cannot resolve parent of '$a'" >&2; rc=1; continue; }
    p="${p%/}/$b"
    if __st_dangerous "$a" || __st_dangerous "$p"; then echo "safe_rm_rf: refusing protected path '$a'" >&2; rc=1; continue; fi
    ncomp="$(__st_ncomp "$p")"
    [ "$ncomp" -ge 3 ] || { echo "safe_rm_rf: refusing '$p' (fewer than 3 path components)" >&2; rc=1; continue; }
    # an ancestor of the REAL home is never removable
    h="${OVN_SAFE_REAL_HOME:-}"
    if [ -n "$h" ]; then
      case "${h%/}/" in "$p"/*) echo "safe_rm_rf: refusing '$p' (it contains the real home '$h')" >&2; rc=1; continue;; esac
    fi
    # a git checkout / worktree root is never a throwaway sandbox
    if [ -e "$p/.git" ] && [ ! -L "$p" ]; then echo "safe_rm_rf: refusing '$p' (it is a git checkout or worktree root)" >&2; rc=1; continue; fi
    if ! __st_under_root "$p"; then echo "safe_rm_rf: refusing '$p' (not under an allowed sandbox root)" >&2; rc=1; continue; fi
    rm -rf -- "$p"
  done
  return "$rc"
}

# capture the real home once (exported so nested shells keep the ORIGINAL, not a sandbox, value)
if [ -z "${OVN_SAFE_REAL_HOME:-}" ] && [ -n "${HOME:-}" ]; then OVN_SAFE_REAL_HOME="$HOME"; export OVN_SAFE_REAL_HOME; fi
