#!/usr/bin/env bash
# P6c (2026-10-27): the no-edit short-circuit in ovn_classify_fail.sh covered only 'verdict: no-edit-unfenced' / udiff '/dev/null'. The plain 'aider attempt N verdict: no-edit' line (the
# runner writes it for every attempt that produced nothing) fell through to the test-red regex on the model's own prose ("assert ", "expected to equal"): 4 rows in the 10-26 window were
# test-red for a cycle that edited nothing. Same guard as before: a verification marker ('--- verify', GUT-FAIL-ID, verify-suite-red) keeps the old scan; OVN_CLASSIFY_NOEDIT_FIRST=off restores it.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
C="${OVN_CLASSIFY_FAIL:-$HERE/../../ovn_classify_fail.sh}"
[ -f "$C" ] || { echo "  SKIP: $C not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
cat > "$tmp/plain.log" <<'T'
I will assert that the helper is unused, then delete it. The test is expected to equal nothing after.
I could not find a safe place to edit; stopping here.
--- aider attempt 1 verdict: no-edit ---
T
ok "plain 'verdict: no-edit' + prose 'assert ' and no verify marker -> no-edit (old: test-red)" "[ \"\$(bash '$C' '$tmp/plain.log' 'no-op')\" = no-edit ]"
ok "OVN_CLASSIFY_NOEDIT_FIRST=off restores the old scan (test-red)" "[ \"\$(OVN_CLASSIFY_NOEDIT_FIRST=off bash '$C' '$tmp/plain.log' 'no-op')\" = test-red ]"
cat > "$tmp/verified.log" <<'T'
--- aider attempt 1 verdict: no-edit ---
--- verify: pytest in . (240s cap) ---
1 failed, 3 passed
T
ok "CONTROL: plain no-edit but the log reached verification -> keeps test-red" "[ \"\$(bash '$C' '$tmp/verified.log' 'no-op')\" = test-red ]"
cat > "$tmp/gut.log" <<'T'
--- aider attempt 1 verdict: no-edit ---
GUT-FAIL-ID test_x.gd::test_a
assert_eq failed
T
ok "CONTROL: GUT-FAIL-ID marker keeps the old scan" "[ \"\$(bash '$C' '$tmp/gut.log' 'no-op')\" = test-red ]"
cat > "$tmp/applied.log" <<'T'
Applied edit to app/x.py
--- aider attempt 1 verdict: applied ---
2 failed, 1 passed
T
ok "CONTROL: verdict applied + red tests stays test-red" "[ \"\$(bash '$C' '$tmp/applied.log' 'no-op')\" = test-red ]"
cat > "$tmp/unf.log" <<'T'
assert something expected to equal x
--- aider attempt 1 verdict: no-edit-unfenced ---
T
ok "CONTROL: no-edit-unfenced still no-edit" "[ \"\$(bash '$C' '$tmp/unf.log' 'no-op')\" = no-edit ]"
printf '1 failed, 40 passed\n' > "$tmp/red.log"
ok "CONTROL: a plain red log is still test-red" "[ \"\$(bash '$C' '$tmp/red.log' 'no-op')\" = test-red ]"
# the verdict token must be the whole word: 'verdict: no-edits-here' is not a verdict line
printf 'assert x\nverdict: no-editor-config\n' > "$tmp/word.log"
ok "CONTROL: 'verdict: no-editor...' is not a no-edit verdict (stays test-red)" "[ \"\$(bash '$C' '$tmp/word.log' 'no-op')\" = test-red ]"
echo; echo "test_classify_noedit_plain: $P passed, $F failed"; [ "$F" = 0 ]
