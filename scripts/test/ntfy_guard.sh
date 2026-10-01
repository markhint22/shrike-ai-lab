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
    /usr/bin/curl|/bin/curl|/usr/local/bin/curl|/opt/homebrew/bin/curl)
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
