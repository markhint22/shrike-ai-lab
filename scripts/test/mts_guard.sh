#!/bin/bash
# mts_guard.sh - the guard stub behind scripts/test/lib_mac_test_sandbox.sh. Installed (symlinked) as ssh / scp / rsync / curl / nc / ntfy in a per-test dir that is FIRST on PATH, and
# called by the exported guard functions of the sandbox. It NEVER performs real I/O and never runs the real binary. It records every call to $OVN_MTS_LOG
# ("ALLOW <tool> <argv>" for a loopback / reserved-name target, "BLOCK <tool> <argv>" for anything else) and exits as the real binary (allowed) or 97 (blocked, says so loudly on stderr).
# Allowed targets: 127.x, localhost, ::1, and the RFC 2606 reserved names (*.test, *.invalid, *.example, *.localhost, example.com/org/net). Everything else (the box LAN / Tailscale
# addresses, ntfy.sh, any real host) is BLOCKed. OVN_MTS_LOG unset => a temp default so a stray call still fails loudly.
tool="$(basename "$0")"
[ "$tool" = mts_guard.sh ] && tool="${MTS_TOOL:-ssh}"
LOG="${OVN_MTS_LOG:-${TMPDIR:-/tmp}/ovn_mts_guard.log}"
host_ok() { # $1 = a bare host (maybe user@, maybe :port/path suffix)
  local h="${1##*@}"; h="${h#\[}"; h="${h%%\]*}"; h="${h%%/*}"
  case "$h" in 127.*|localhost|localhost:*|::1|"::1"*) return 0;; esac
  h="${h%%:*}"
  case "$h" in 127.*|localhost|*.localhost|*.test|*.invalid|*.example|example.com|example.org|example.net|*.example.com|*.example.org|*.example.net) return 0;; esac
  return 1
}
bad=0
case "$tool" in
  curl|ntfy)
    for a in "$@"; do
      case "$a" in
        *://*) u="${a#*://}"; host_ok "$u" || bad=1;;
        *" "*|-*) ;;   # headers / data / options
        *[A-Za-z0-9].*[A-Za-z]*|[0-9]*.[0-9]*.[0-9]*.[0-9]*|localhost*) # scheme-less host[:port][/path] (or a file name: treated as a host, conservative)
          case "$a" in /*|./*) ;; *) host_ok "$a" || { case "$a" in *.*[!A-Za-z0-9._:/@%=+,-]*) ;; *) bad=1;; esac; };; esac;;
      esac
    done ;;
  nc)
    for a in "$@"; do case "$a" in -*) ;; *) case "$a" in *[A-Za-z.]*[A-Za-z]*|[0-9]*.[0-9]*.[0-9]*.[0-9]*) host_ok "$a" || bad=1; break;; esac;; esac; done ;;
  ssh)
    # target = first non-option argument; options that take a value are skipped
    skip=0; for a in "$@"; do
      if [ "$skip" = 1 ]; then skip=0; continue; fi
      case "$a" in
        -[bcDEeFIiJLlmOopQRSWw]) skip=1;;
        -*) ;;
        *) host_ok "$a" || bad=1; break;;
      esac
    done ;;
  scp|rsync)
    for a in "$@"; do
      case "$a" in -*) ;; *:*) case "$a" in /*|./*) ;; *) host_ok "$a" || bad=1;; esac;; esac
    done ;;
esac
printf '%s pid=%s %s %s %s :: %s\n' "$(date '+%F %T')" "$$" "$([ "$bad" = 1 ] && echo BLOCK || echo ALLOW)" "$tool" "cwd=$(pwd)" "$*" >> "$LOG" 2>/dev/null
if [ "$bad" = 1 ]; then echo "MTS GUARD: $tool $* -> BLOCKED (real delivery target reached from a test; see $LOG)" >&2; exit 97; fi
for d in /usr/bin /bin /opt/homebrew/bin /usr/local/bin; do
  if [ -x "$d/$tool" ] && [ "$d/$tool" != "$0" ]; then exec "$d/$tool" "$@"; fi
done
exit 0
