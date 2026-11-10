#!/usr/bin/env bash
# lib_mac_test_sandbox.sh - SOURCE from every Mac-side test (test_mac_*, z4/z6/z8a Mac tests, k1, p1, fxp1, deploy_watch ...). Z10 (2026-11-10).
#
# Incident: at 2026-11-10 08:25:58-08:26:02 four WARN rows ("live-sync-missing: live checkout /private/var/folders/.../z6.XXXX/nolive missing", "commit-push-branch: bridge not committing from
# /private/var/folders/.../z6.XXXX/repo: it is on claude/feature, not develop") landed in the REAL box alerts.log. Root cause: test_z6_notify_guard.sh scenario B (the CONTROL that clears the
# disable switch) relied on stub ssh/curl first on PATH, but mac_live_sync.sh / mac_live_commit_push.sh did `export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH`, which put the REAL
# /usr/bin/ssh ahead of the stub, so mac_alert -> pick_srv/_mac_ssh_alert reached the real box (a PATH stub cannot win against a script that prepends system dirs).
#
# Contract: sourcing this makes real delivery impossible for the test process AND every child (bash scripts, python subprocesses):
#   - mts_sandbox_init <tmpdir>: guard stubs (mts_guard.sh symlinked as ssh scp rsync curl nc ntfy) in <tmpdir>/.mts_bin FIRST on PATH; exported shell functions ssh/scp/rsync/curl/nc that route to the
#     guard when the binary that would run is a SYSTEM one (so a script that resets PATH to /usr/bin first is still caught; a test's own stub earlier on PATH is untouched);
#     BASH_ENV re-defines those functions in every child bash (so even `unset -f` in the test or a fresh bash does not lose them);
#   - OVN_NOTIFY_DISABLE=1 and NTFY_SERVER=http://127.0.0.1:9 by default; MAC_SSH/MAC_CURL are left alone (a test that wants delivery sets an explicit stub ABSOLUTE path, never clears the switch alone);
#   - guard calls to a non-loopback / non-reserved target are recorded as BLOCK in $OVN_MTS_LOG and exit 97; mts_blocked_calls prints them, mts_assert_no_real_calls returns non-zero when any exist.
# A test that exercises delivery opts in with `OVN_NOTIFY_DISABLE=` PLUS its own stub ssh/curl (PATH or MAC_SSH/MAC_CURL): the guard still stands behind the stub.
MTS_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mts_sandbox_init() { # <tmpdir> : the tmpdir must be a real temp sandbox the test owns
  local t="$1"
  [ -n "$t" ] && [ -d "$t" ] || { echo "  FAIL: mts_sandbox_init needs an existing tmp dir" >&2; return 1; }
  MTS_BIN="$t/.mts_bin"; mkdir -p "$MTS_BIN" || return 1
  local n; for n in ssh scp rsync curl nc ntfy; do ln -sf "$MTS_HERE/mts_guard.sh" "$MTS_BIN/$n"; done
  export OVN_MTS_LOG="${OVN_MTS_LOG:-$t/mts_guard.log}"; : >> "$OVN_MTS_LOG"
  export OVN_MTS_BIN="$MTS_BIN" OVN_MTS_GUARD="$MTS_HERE/mts_guard.sh"
  case ":$PATH:" in *":$MTS_BIN:"*) ;; *) export PATH="$MTS_BIN:$PATH";; esac
  # functions: route to the guard only when the resolved binary is a system one (a test stub / the guard dir resolves elsewhere and is left alone)
  cat > "$t/.mts_env" <<'ENVEOF'
__mts_route() { # <tool> args...
  local tool="$1" real; shift
  real="$(type -P "$tool" 2>/dev/null)"
  case "$real" in
    /usr/bin/*|/bin/*|/usr/local/bin/*|/opt/homebrew/bin/*|/opt/homebrew/opt/*|/usr/sbin/*|/sbin/*) MTS_TOOL="$tool" "$OVN_MTS_GUARD" "$@"; return $?;;
  esac
  command "$tool" "$@"
}
# a function a test ALREADY exported (its own stub, e.g. test_deploy_watch_run.sh) is never replaced: only a missing one is defined
[ "$(type -t ssh)" = function ] || ssh() { __mts_route ssh "$@"; }
[ "$(type -t scp)" = function ] || scp() { __mts_route scp "$@"; }
[ "$(type -t rsync)" = function ] || rsync() { __mts_route rsync "$@"; }
[ "$(type -t curl)" = function ] || curl() { __mts_route curl "$@"; }
[ "$(type -t nc)" = function ] || nc() { __mts_route nc "$@"; }
export -f __mts_route ssh scp rsync curl nc
ENVEOF
  export OVN_MTS_ENVFILE="$t/.mts_env"
  . "$OVN_MTS_ENVFILE"
  export BASH_ENV="$OVN_MTS_ENVFILE"
  # default: delivery switched OFF and the relay pointed at the closed port 9. MTS_KEEP_SWITCH=1 (lib_mac_fixture: tests whose delivery goes ONLY to explicit absolute stubs MAC_SSH/MAC_CURL)
  # leaves the inherited switch / NTFY_SERVER alone; the guard stands behind either way.
  if [ "${MTS_KEEP_SWITCH:-}" != 1 ]; then export OVN_NOTIFY_DISABLE=1; export NTFY_SERVER="http://127.0.0.1:9"; fi
  return 0
}
mts_blocked_calls() { grep -E ' BLOCK ' "${OVN_MTS_LOG:-/dev/null}" 2>/dev/null; }
mts_calls() { cat "${OVN_MTS_LOG:-/dev/null}" 2>/dev/null; }
mts_assert_no_real_calls() { local b; b="$(mts_blocked_calls)"; if [ -n "$b" ]; then printf '%s\n' "$b" >&2; return 1; fi; return 0; }
