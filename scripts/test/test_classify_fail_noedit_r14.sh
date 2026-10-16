#!/usr/bin/env bash
# R14 (xlite X7, 2026-10-12): a cycle that ended 'aider attempt N verdict: no-edit-unfenced' / '/dev/null is not in the subpath' and never ran a verification step
# must classify as no-edit, not test-red (its deliberation text contains 'assert ' / 'expected to equal'). A log that DID reach verification keeps its old class.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
C="${OVN_CLASSIFY_FAIL:-$HERE/../../ovn_classify_fail.sh}"
[ -f "$C" ] || { echo "  SKIP: $C not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)" || exit 1; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/noedit.log" <<'T'
I will assert that the helper is unused, then delete it. The test is expected to equal nothing after.
/dev/null is not in the subpath of /repo
Only 3 reflections allowed, stopping.
--- aider attempt 1 verdict: no-edit-unfenced ---
T
ok "udiff /dev/null + no-edit-unfenced, no verify step -> no-edit (old: test-red)" "[ \"\$(bash '$C' '$tmp/noedit.log' 'no-op')\" = no-edit ]"
cat > "$tmp/verified.log" <<'T'
--- aider attempt 1 verdict: no-edit-unfenced ---
--- verify: pytest in . (240s cap) ---
1 failed, 3 passed
T
ok "CONTROL: a log that reached verification keeps test-red" "[ \"\$(bash '$C' '$tmp/verified.log' 'no-op')\" = test-red ]"
printf '1 failed, 40 passed\n' > "$tmp/red.log"
ok "CONTROL: a plain red log is still test-red" "[ \"\$(bash '$C' '$tmp/red.log' 'no-op')\" = test-red ]"
echo; echo "$P passed, $F failed"; [ "$F" = 0 ]
