#!/usr/bin/env bash
# run_all_sandboxed.sh - run the full queue suite (run_all.sh) inside bubblewrap with the REAL home mounted READ-ONLY.
# 2026-10-16 incident: a test did tmp=$(mktemp); export HOME=$tmp/home; rm -rf $HOME. mktemp failed, HOME became /home and the whole box home
# directory was deleted. Under this wrapper the same command fails with "Read-only file system" and nothing is lost.
#
# Mounts, in this order (order matters: a later mount covers an earlier one):
#   / read-only; /dev, /proc; tmpfs over /run and /run/user (docker.sock, the user dbus socket, /run/media and every other runtime socket are UNREACHABLE);
#   /tmp writable; $HOME read-only; the private TMPDIR base (default $HOME/qtmp, OVN_SANDBOX_TMPBASE) writable; network allowed.
# Explicit, documented openings (all validated, see "Refusals"):
#   OVN_SANDBOX_RUN_ALLOW="/run/a:/run/b"   paths under /run bound back READ-ONLY (e.g. /run/systemd/resolve when a test needs DNS). Default: none.
#                                           Never accepted: /run itself, /run/user and below, anything docker/containerd/podman/crio/dbus/bus/agent-named.
#   OVN_SANDBOX_EXTRA_BIND="/path/a:/path/b" extra WRITABLE paths. Must live under the qtmp base or strictly under /tmp. Default: none.
#   OVN_SANDBOX_TMPBASE=/dir                private TMPDIR base. Must be $HOME/qtmp (or below) or strictly under /tmp, and must not be a symlink.
#   OVN_SANDBOX_OVERLAY="/src=/dst"         bind a scratch copy (src, writable, under qtmp or /tmp) over the live path dst INSIDE the namespace only, for tests that
#                                           hard-code $HOME/overnight-queue. Both must exist; no '=' is rejected.
# Refusals (exit 78, nothing created, nothing run): HOME unset or /; any writable bind whose CANONICAL (symlink-resolved) path is HOME, /, an ancestor of HOME,
#   a symlink (QBASE), or outside qtmp and /tmp; a bad OVN_SANDBOX_RUN_ALLOW entry; a malformed overlay. bwrap missing is also 78 unless OVN_ALLOW_UNSANDBOXED=1 (manual one-off).
# NOT CONTAINED (read this): the network stays open and $HOME (including ~/.ssh) is readable, so a test that runs `ssh mhintermeister@<this box>` or `ssh localhost`
#   with the box's own key gets a NORMAL, UNSANDBOXED login as the user. bwrap does not and cannot stop that. Tests must never ssh to the box they run on.
# A bwrap-less host (macOS) cannot run the sandbox at all: tests that need real bwrap are reported as SKIP by test_run_all_sandboxed.sh, and a SKIP is NOT a pass
#   (run it with OVN_REQUIRE_LINUX_BWRAP=1 to make any SKIP a failure; do that wherever the result gates a deploy).
# Inside the sandbox the wrapper exports OVN_SANDBOXED=1 and OVN_REQUIRE_LINUX_BWRAP=1: bwrap cannot nest, so test_run_all_sandboxed.sh there verifies the REAL enclosing
#   sandbox live (HOME read-only, qtmp writable, /run hidden) instead of silently skipping; any other skip is a failure (a SKIP is never a pass).
# Args are passed to run_all.sh. Test hooks, honoured ONLY when OVN_SANDBOX_TEST_HOOKS=1 (otherwise a stray OVN_SANDBOX_BWRAP / OVN_SANDBOX_TARGET in a developer or cron
#   environment is IGNORED with a warning, so it can never turn the run green without a sandbox or a suite): OVN_SANDBOX_BWRAP (bwrap binary, default bwrap),
#   OVN_SANDBOX_TARGET (script to run, default run_all.sh next to this file).
HERE_SB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${OVN_SANDBOX_TEST_HOOKS:-}" = "1" ]; then
  BWRAP="${OVN_SANDBOX_BWRAP:-bwrap}"
  TARGET="${OVN_SANDBOX_TARGET:-$HERE_SB/run_all.sh}"
else
  if [ -n "${OVN_SANDBOX_BWRAP:-}${OVN_SANDBOX_TARGET:-}" ]; then
    echo "run_all_sandboxed: WARNING: ignoring OVN_SANDBOX_BWRAP / OVN_SANDBOX_TARGET (they are test hooks, honoured only with OVN_SANDBOX_TEST_HOOKS=1)" >&2
  fi
  BWRAP="bwrap"
  TARGET="$HERE_SB/run_all.sh"
fi
refuse(){ echo "run_all_sandboxed: REFUSED: $*" >&2; exit 78; }

case "${HOME:-}" in ""|/) echo "run_all_sandboxed: HOME is unset or / - refusing."; exit 78;; esac
canon_dir(){ ( cd -P "$1" 2>/dev/null && pwd -P ) 2>/dev/null; }
canon_any(){   # canonical path of an existing dir, or of a not-yet-existing leaf under an existing dir
  local p="$1" d b
  if [ -d "$p" ]; then canon_dir "$p"; return; fi
  d="$(dirname "$p")"; b="$(basename "$p")"; d="$(canon_dir "$d")"; [ -n "$d" ] || return 1
  if [ "$d" = / ]; then echo "/$b"; else echo "$d/$b"; fi
}
HOME_REAL="$(canon_dir "$HOME")"; [ -n "$HOME_REAL" ] && [ "$HOME_REAL" != / ] || refuse "HOME ($HOME) does not resolve to a real directory"
TMP_REAL="$(canon_dir /tmp)"; [ -n "$TMP_REAL" ] || refuse "/tmp does not resolve"
is_ancestor_or_home(){   # rc 0 when $1 is /, HOME, or an ancestor of HOME
  [ "$1" = "/" ] && return 0
  [ "$1" = "$HOME_REAL" ] && return 0
  case "$HOME_REAL/" in "$1"/*) return 0;; esac
  return 1
}
under(){ case "$1" in "$2"/*) return 0;; esac; return 1; }   # strictly under

# ---- QBASE: never a symlink, canonical path must be $HOME/qtmp(-or-below) or strictly under /tmp
QBASE_RAW="${OVN_SANDBOX_TMPBASE:-$HOME/qtmp}"
case "$QBASE_RAW" in /*) ;; *) refuse "OVN_SANDBOX_TMPBASE '$QBASE_RAW' is not an absolute path";; esac
while [ "${#QBASE_RAW}" -gt 1 ] && [ "${QBASE_RAW%/}" != "$QBASE_RAW" ]; do QBASE_RAW="${QBASE_RAW%/}"; done
[ -L "$QBASE_RAW" ] && refuse "OVN_SANDBOX_TMPBASE / qtmp base $QBASE_RAW is a symlink"
QBASE="$(canon_any "$QBASE_RAW")" || refuse "cannot resolve the private TMPDIR base $QBASE_RAW (its parent must exist)"
is_ancestor_or_home "$QBASE" && refuse "private TMPDIR base resolves to $QBASE (HOME, /, or an ancestor of HOME)"
QROOT="$HOME_REAL/qtmp"
if [ "$QBASE" = "$QROOT" ] || under "$QBASE" "$QROOT" || { under "$QBASE" "$TMP_REAL" && ! under "$QBASE" "$HOME_REAL"; }; then :; else
  refuse "private TMPDIR base resolves to $QBASE: must be $QROOT (or below) or strictly under $TMP_REAL (and not inside HOME)"
fi
[ -L "$QROOT" ] && refuse "$QROOT is a symlink"
writable_ok(){   # writable_ok <canonical path> <label>: refuse unless equal-or-under QBASE or strictly under /tmp, and never HOME, /, or an ancestor of HOME
  is_ancestor_or_home "$1" && refuse "$2 resolves to $1 (HOME, /, or an ancestor of HOME)"
  if [ "$1" = "$QBASE" ] || under "$1" "$QBASE" || { under "$1" "$TMP_REAL" && ! under "$1" "$HOME_REAL"; }; then return 0; fi
  refuse "$2 resolves to $1: outside the qtmp base ($QBASE) and /tmp"
}

# ---- extra writable binds
EXTRA_PATHS=()
if [ -n "${OVN_SANDBOX_EXTRA_BIND:-}" ]; then
  IFS=: read -r -a _xb <<< "$OVN_SANDBOX_EXTRA_BIND"
  for p in "${_xb[@]}"; do
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) refuse "OVN_SANDBOX_EXTRA_BIND entry '$p' is not an absolute path";; esac
    [ -e "$p" ] || { echo "run_all_sandboxed: OVN_SANDBOX_EXTRA_BIND entry $p does not exist: skipped"; continue; }
    [ -L "$p" ] && [ ! -d "$p" ] && refuse "OVN_SANDBOX_EXTRA_BIND entry $p is a symlink to a non-directory"
    if [ -d "$p" ]; then c="$(canon_dir "$p")"; else c="$(canon_any "$p")"; fi
    [ -n "$c" ] || refuse "cannot resolve OVN_SANDBOX_EXTRA_BIND entry $p"
    writable_ok "$c" "OVN_SANDBOX_EXTRA_BIND entry $p"
    EXTRA_PATHS+=("$c")
  done
fi

# ---- overlay
OV_SRC=""; OV_DST=""
if [ -n "${OVN_SANDBOX_OVERLAY:-}" ]; then
  case "$OVN_SANDBOX_OVERLAY" in *=*) ;; *) refuse "OVN_SANDBOX_OVERLAY must be src=dst (no '=' in '$OVN_SANDBOX_OVERLAY')";; esac
  _s="${OVN_SANDBOX_OVERLAY%%=*}"; _d="${OVN_SANDBOX_OVERLAY#*=}"
  [ -n "$_s" ] && [ -n "$_d" ] || refuse "OVN_SANDBOX_OVERLAY has an empty side ('$OVN_SANDBOX_OVERLAY')"
  case "$_s" in /*) ;; *) refuse "OVN_SANDBOX_OVERLAY src '$_s' is not absolute";; esac
  case "$_d" in /*) ;; *) refuse "OVN_SANDBOX_OVERLAY dst '$_d' is not absolute";; esac
  [ -d "$_s" ] && [ -d "$_d" ] || refuse "OVN_SANDBOX_OVERLAY src and dst must both be existing directories ('$OVN_SANDBOX_OVERLAY')"
  OV_SRC="$(canon_dir "$_s")"; OV_DST="$(canon_dir "$_d")"
  [ -n "$OV_SRC" ] && [ -n "$OV_DST" ] || refuse "cannot resolve OVN_SANDBOX_OVERLAY"
  writable_ok "$OV_SRC" "OVN_SANDBOX_OVERLAY src"
  is_ancestor_or_home "$OV_DST" && refuse "OVN_SANDBOX_OVERLAY dst resolves to $OV_DST (HOME, /, or an ancestor of HOME)"
  [ "$OV_SRC" != "$OV_DST" ] || refuse "OVN_SANDBOX_OVERLAY src and dst are the same directory"
fi

# ---- /run allowlist (read-only)
RUN_BACK=()
if [ -n "${OVN_SANDBOX_RUN_ALLOW:-}" ]; then
  RUN_REAL="$(canon_dir /run)"
  IFS=: read -r -a _ra <<< "$OVN_SANDBOX_RUN_ALLOW"
  for p in "${_ra[@]}"; do
    [ -n "$p" ] || continue
    case "$p" in /*) ;; *) refuse "OVN_SANDBOX_RUN_ALLOW entry '$p' is not absolute";; esac
    [ -n "$RUN_REAL" ] || refuse "OVN_SANDBOX_RUN_ALLOW given but /run does not exist here"
    [ -e "$p" ] || { echo "run_all_sandboxed: OVN_SANDBOX_RUN_ALLOW entry $p does not exist: skipped"; continue; }
    [ -L "$p" ] && [ ! -d "$p" ] && refuse "OVN_SANDBOX_RUN_ALLOW entry $p is a symlink to a non-directory"
    if [ -d "$p" ]; then c="$(canon_dir "$p")"; else c="$(canon_any "$p")"; fi
    [ -n "$c" ] || refuse "cannot resolve OVN_SANDBOX_RUN_ALLOW entry $p"
    under "$c" "$RUN_REAL" || refuse "OVN_SANDBOX_RUN_ALLOW entry $p resolves to $c: not strictly under $RUN_REAL"
    case "$c" in "$RUN_REAL"/user|"$RUN_REAL"/user/*) refuse "OVN_SANDBOX_RUN_ALLOW entry $c is under /run/user (the user dbus/session sockets)";; esac
    case "$c" in *docker*|*containerd*|*podman*|*crio*|*dbus*|*/bus|*/bus/*|*agent*|*/ssh*) refuse "OVN_SANDBOX_RUN_ALLOW entry $c looks like a container/dbus/agent socket path";; esac
    RUN_BACK+=("$c")
  done
fi

# ---- bwrap present? (validation above is pure shell and runs on every host, so refusals are testable on macOS too)
if ! command -v "$BWRAP" >/dev/null 2>&1; then
  echo "run_all_sandboxed: bubblewrap ($BWRAP) is not installed - the suite cannot be sandboxed."
  if [ "${OVN_ALLOW_UNSANDBOXED:-}" = "1" ]; then
    echo "run_all_sandboxed: OVN_ALLOW_UNSANDBOXED=1 set - running UNSANDBOXED at your own risk."
    exec bash "$TARGET" "$@"
  fi
  echo "run_all_sandboxed: REFUSING to run unsandboxed (set OVN_ALLOW_UNSANDBOXED=1 to override explicitly)."
  exit 78
fi
mkdir -p "$QBASE" || { echo "run_all_sandboxed: cannot create $QBASE - refusing."; exit 78; }
[ -L "$QBASE" ] && refuse "$QBASE became a symlink"
args=(--ro-bind / / --dev /dev --proc /proc)
args+=(--tmpfs /run --tmpfs /run/user)                 # MOUNT-RUN
args+=(--bind /tmp /tmp)                               # MOUNT-TMP
args+=(--ro-bind "$HOME" "$HOME")                      # MOUNT-HOME
[ "$HOME_REAL" != "$HOME" ] && args+=(--ro-bind "$HOME_REAL" "$HOME_REAL")
args+=(--bind "$QBASE" "$QBASE")                       # MOUNT-QBASE
for c in ${EXTRA_PATHS[@]+"${EXTRA_PATHS[@]}"}; do args+=(--bind "$c" "$c"); done
[ -n "$OV_SRC" ] && args+=(--bind "$OV_SRC" "$OV_DST")
for c in ${RUN_BACK[@]+"${RUN_BACK[@]}"}; do args+=(--ro-bind "$c" "$c"); done
args+=(--die-with-parent --unshare-pid --chdir "$HERE_SB")
export OVN_TEST_TMP_BASE="$QBASE"
export OVN_SANDBOXED=1 OVN_REQUIRE_LINUX_BWRAP=1   # only on the real-bwrap path (the unsandboxed override above never sets them)
exec "$BWRAP" "${args[@]}" bash "$TARGET" "$@"
