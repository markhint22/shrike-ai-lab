#!/usr/bin/env bash
# 2026-10-17 (iptv review): a reverted-red cycle whose verify ended rc=124 (cap hit) classifies as verify-timeout, not test-red. Other reds stay test-red.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
C="${OVN_CLASSIFY_FAIL:-$HERE/../../ovn_classify_fail.sh}"
[ -f "$C" ] || { echo "  SKIP: $C not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
printf -- '--- verify done in 600s ---\n--- verify-suite-red: repo-script in . rc=124 ---\n--- NO-NEW-RED GUARD: commit left the suite red ---\n' > "$tmp/to.log"
ok "reverted-red + rc=124 marker -> verify-timeout" "[ \"\$(bash '$C' '$tmp/to.log' 'no-op(reverted-red)')\" = verify-timeout ]"
printf -- '--- verify-suite-red: repo-script in . rc=1 ---\nFAILED tests/x.py::t\n1 failed, 3 passed\n' > "$tmp/red.log"
ok "CONTROL: reverted-red + rc=1 stays test-red" "[ \"\$(bash '$C' '$tmp/red.log' 'no-op(reverted-red)')\" = test-red ]"
printf -- '--- verify-suite-red: repo-script in . rc=124 ---\n' > "$tmp/other.log"
ok "CONTROL: rc=124 under a non-reverted-red status is untouched (legacy scan -> unknown)" "[ \"\$(bash '$C' '$tmp/other.log' 'no-op')\" = unknown ]"
echo; echo "$P passed, $F failed"; [ "$F" = 0 ]
