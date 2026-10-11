#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_ovn_mutation_scan_term.py (mutation scan removes its scratch archive on SIGTERM/SIGHUP; handshake-synchronised).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_mutation_scan_term.py"
rc=$?
echo "test_ovn_mutation_scan_term.py rc=$rc"
exit $rc
