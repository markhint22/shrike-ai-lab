# scripts/test/ntfy_guard.sh - SOURCE this from any test runner (run_all.sh, run_coverage.sh).
#
# 2026-09-30 incident: the test suite sent REAL messages to ntfy.sh (junk topics, from the same IP as production alerts). ntfy.sh
# rate-limits anonymous publishers per IP (HTTP 429 "daily message quota reached"), so repeated suite runs (cron every 6h + every
# manual/agent run) exhausted the quota and ALL production pushes (digest, regressions, deploy alerts) were silently dropped for ~24h.
#
# Defines and EXPORTS a `curl` shell function (functions beat PATH lookups, so it also wins over scripts that reset PATH to
# /usr/bin first). It swallows any call whose URL contains ntfy.sh, but ONLY when the curl that would run is the real system binary -
# a test that puts its own stub curl first on PATH still sees every call and can assert on it. Swallowed attempts are appended to
# $OVN_NTFY_GUARD_LOG so a suite run can be audited for tests that still try to reach the network.
OVN_NTFY_GUARD_LOG="${OVN_NTFY_GUARD_LOG:-/tmp/ovn_ntfy_guard.log}"
export OVN_NTFY_GUARD_LOG
curl() {
  local real; real="$(type -P curl 2>/dev/null)"
  case "$real" in
    /usr/bin/curl|/bin/curl|/usr/local/bin/curl|/opt/homebrew/bin/curl|/opt/homebrew/opt/curl/bin/curl)   # 2026-10-10: + the Homebrew keg path (what `type -P curl` returns on the dev Mac; it was NOT swallowed there)
      case "$*" in
        *ntfy.sh*) printf '%s pid=%s %s :: %s\n' "$(date '+%F %T')" "$$" "${BASH_SOURCE[1]:-?}" "$*" >> "$OVN_NTFY_GUARD_LOG" 2>/dev/null; return 0 ;;
      esac ;;
  esac
  command curl "$@"
}
export -f curl

# 2026-10-01: the CRON environment exports NTFY_SERVER=<relay> (the notification redesign) so production scripts publish through the
# relay. Tests assume the default server (https://ntfy.sh, which the guard above swallows); inheriting the relay made 4+ tests fail
# only under cron ("Queue tests FAILED" at 00:09 and 06:09) while every manual run passed, and let test traffic reach the real
# relay. Tests must run in the same environment whether started by cron or by hand.
unset NTFY_SERVER

# 2026-10-10 (qacov F7): the same class of leak for the BOX. A suite run on the Mac once appended a synthetic alert ("RevenueCat lifecycle E2E on staging FAILED: 1/2 passed;
# failed=['x']; staging=abcdef12", 2026-10-09 12:19) to the REAL box's state/alerts.log through the real `ssh` (fixed 4 minutes later by the QA_E2E_SSH shim override, 9c1988a). This
# guard makes the class impossible: ssh/scp/rsync to a box address (OVN_GUARD_BOX_HOSTS, default the Tailscale + LAN addresses of the GPU box) are swallowed and logged to
# $OVN_SSH_GUARD_LOG (return 255 = "unreachable", which every caller already handles) - but ONLY when the binary that would run is the real system one, so a test that puts its own
# stub ssh/scp first on PATH (or passes one by absolute path, like QA_E2E_SSH) still sees every call. OVN_SSH_GUARD=off disables it (a deliberate live check from a person).
OVN_SSH_GUARD_LOG="${OVN_SSH_GUARD_LOG:-/tmp/ovn_ssh_guard.log}"; export OVN_SSH_GUARD_LOG
__ovn_box_guard() {   # $1 = ssh|scp|rsync, rest = its arguments
  local cmd="$1" real h; shift
  if [ "${OVN_SSH_GUARD:-on}" != "off" ]; then
    real="$(type -P "$cmd" 2>/dev/null)"
    case "$real" in
      /usr/bin/ssh|/bin/ssh|/usr/local/bin/ssh|/opt/homebrew/bin/ssh|/usr/bin/scp|/bin/scp|/usr/local/bin/scp|/opt/homebrew/bin/scp|/usr/bin/rsync|/bin/rsync|/usr/local/bin/rsync|/opt/homebrew/bin/rsync)
        for h in ${OVN_GUARD_BOX_HOSTS:-100.79.64.64 192.168.68.145}; do
          case "$*" in
            *"$h"*) printf '%s pid=%s %s :: %s %s\n' "$(date '+%F %T')" "$$" "${BASH_SOURCE[2]:-?}" "$cmd" "$*" >> "$OVN_SSH_GUARD_LOG" 2>/dev/null; return 255 ;;
          esac
        done ;;
    esac
  fi
  command "$cmd" "$@"
}
ssh() { __ovn_box_guard ssh "$@"; }
scp() { __ovn_box_guard scp "$@"; }
rsync() { __ovn_box_guard rsync "$@"; }
export -f __ovn_box_guard ssh scp rsync
