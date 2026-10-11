#!/usr/bin/env bash
# 2026-10-10 (harness R10, BX-07): BUILD-GATE must not treat Godot RUNTIME errors as a structural break, and must only trust Godot-engine error tokens from THIS cycle's verify run.
#
# Live defect replayed: 3 of 9 `reverted(build-break)` xlite rows were really runtime test errors. `_BUILD_BREAK_POS_RE` contains the bare token 'SCRIPT ERROR' and the NEG list only excluded
# null-call / base-object-type shapes, so "SCRIPT ERROR: Invalid call. Nonexistent function 'X' in base 'RefCounted (stub_params.gd)'" (20261009-170821, 184000) and "... in base 'Node (GutMain)'"
# (202740, 025641) matched POS and not NEG - while GUT was RED with real failing tests (failures=2). They went to BUILD-GATE instead of the assertion-grounded Tier-2 fix-up, and the check
# grepped the CUMULATIVE task log (earlier verify runs + the fix-up's own chat).
# The regexes and the function are extracted from the real run_overnight.sh (not reimplemented), so this cannot drift from what is deployed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RO="${OVN_RUN_OVERNIGHT:-$HERE/../../run_overnight.sh}"; [ -f "$RO" ] || RO="$HOME/overnight-queue/run_overnight.sh"
[ -f "$RO" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }

_POS="$(grep -oE "_BUILD_BREAK_POS_RE=\"[^\"]+\"" "$RO" | head -1 | sed -E 's/^_BUILD_BREAK_POS_RE="//; s/"$//')"
_NEG="$(grep -oE "_BUILD_BREAK_NEG_RE=\"[^\"]+\"" "$RO" | head -1 | sed -E 's/^_BUILD_BREAK_NEG_RE="//; s/"$//')"
_GOD="$(grep -oE "_BUILD_BREAK_GODOT_RE=\"[^\"]+\"" "$RO" | head -1 | sed -E 's/^_BUILD_BREAK_GODOT_RE="//; s/"$//')"
[ -n "$_POS" ] && [ -n "$_NEG" ] || { echo "  FAIL: could not extract the POS/NEG regexes from $RO"; exit 1; }
FN="$(sed -n '/^ovn_buildbreak_hits() {/,/^}/p' "$RO")"
[ -n "$FN" ] || { echo "  FAIL: could not extract ovn_buildbreak_hits() from $RO"; exit 1; }
_BUILD_BREAK_POS_RE="$_POS"; _BUILD_BREAK_NEG_RE="$_NEG"; _BUILD_BREAK_GODOT_RE="$_GOD"
eval "$FN"

P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
hits(){ ovn_buildbreak_hits "$@" | grep -a . | wc -l | tr -d ' '; }   # number of structural-break lines

echo "== A: runtime error shapes are NOT structural breaks"
printf '%s\n' "SCRIPT ERROR: Invalid call. Nonexistent function 'get_params' in base 'RefCounted (stub_params.gd)'." > "$tmp/a1.log"
printf '%s\n' "SCRIPT ERROR: Invalid call. Nonexistent function 'add_child' in base 'Node (GutMain)'." > "$tmp/a2.log"
printf '%s\n' "SCRIPT ERROR: Invalid get index 'techs' (on base: 'Dictionary')." > "$tmp/a3.log"
printf '%s\n' "SCRIPT ERROR: Invalid set index 'x' (on base: 'Array') with value of type 'int'." > "$tmp/a4.log"
printf '%s\n' "SCRIPT ERROR: Invalid access to property or key 'foo' on a base object of type 'Dictionary'." > "$tmp/a5.log"
printf '%s\n' "SCRIPT ERROR: Invalid access to property 'bar' (on base: 'RefCounted')." > "$tmp/a6.log"
for i in 1 2 3 4 5 6; do ok "A$i: runtime error line #$i -> 0 structural hits" "[ \"\$(hits '$tmp/a$i.log' 0)\" = 0 ]"; done

echo "== B: structural breaks still trip it (no over-widening)"
printf '%s\n' 'SCRIPT ERROR: Parse Error: Expected end of statement after expression, found "," instead.' > "$tmp/b1.log"
printf '%s\n' 'ERROR: Failed to load script "res://scripts/battle/damage.gd" with error "Parse error".' > "$tmp/b2.log"
printf '%s\n' '  File "app/main.py", line 12' 'SyntaxError: invalid syntax' > "$tmp/b3.log"
printf '%s\n' "ImportError while loading conftest 'tests/conftest.py'." > "$tmp/b4.log"
for i in 1 2 3 4; do ok "B$i: structural line #$i still hits (offset 0 = whole log)" "[ \"\$(hits '$tmp/b$i.log' 0)\" -ge 1 ]"; done

echo "== C: Godot tokens only count from the CURRENT verify run (bytes after the offset)"
# an earlier verify run printed a Parse Error (since fixed); the current run is clean apart from a runtime error
{ printf '%s\n' '--- verify: GUT tests (run 1) ---' 'SCRIPT ERROR: Parse Error: Identifier "x" not declared in the current scope.'; } > "$tmp/c.log"
voff="$(wc -c < "$tmp/c.log" | tr -d ' ')"
{ printf '%s\n' '--- verify: GUT tests (run 2) ---' "SCRIPT ERROR: Invalid call. Nonexistent function 'f' in base 'Node (GutMain)'." 'Failing 2'; } >> "$tmp/c.log"
ok "C1: stale Parse Error from the earlier run + clean current run -> 0 hits" "[ \"\$(hits '$tmp/c.log' $voff)\" = 0 ]"
ok "C2: the SAME log judged over the whole log (offset 0, the old behaviour) DOES hit the stale line" "[ \"\$(hits '$tmp/c.log' 0)\" -ge 1 ]"
ok "C3: OVN_BUILDBREAK_SCOPE=off restores the whole-log judgement" "[ \"\$(OVN_BUILDBREAK_SCOPE=off hits '$tmp/c.log' $voff)\" -ge 1 ]"
{ cat "$tmp/c.log"; printf '%s\n' 'SCRIPT ERROR: Parse Error: Unexpected "}" in class body.'; } > "$tmp/c2.log"
ok "C4: a Parse Error INSIDE the current run still hits" "[ \"\$(hits '$tmp/c2.log' $voff)\" -ge 1 ]"
# a python structural error printed BEFORE the offset (aider's own lint output / an earlier step) is judged over the whole log as before
{ printf '%s\n' 'SyntaxError: invalid syntax'; } > "$tmp/c3.log"; voff3="$(wc -c < "$tmp/c3.log" | tr -d ' ')"; printf '%s\n' 'Failing 1' >> "$tmp/c3.log"
ok "C5: non-Godot tokens (python SyntaxError) are NOT offset-scoped: still hit" "[ \"\$(hits '$tmp/c3.log' $voff3)\" -ge 1 ]"
ok "C6: empty / non-numeric offset = whole log" "[ \"\$(hits '$tmp/c.log' '')\" -ge 1 ] && [ \"\$(hits '$tmp/c.log' abc)\" -ge 1 ]"
ok "C7: a missing log yields nothing, rc 0" "[ \"\$(hits '$tmp/nonexistent.log' 0)\" = 0 ]"

echo "== D: MUTATION - the OLD regexes/greps flag exactly the live false positives"
OLD_NEG="$(printf '%s' "$_NEG" | sed -E 's/\|Invalid call\[\.\] Nonexistent function//; s/\|Invalid \(get\|set\) index//; s/\|Invalid access to property$//')"
old_hit(){ grep -aE "$_POS" "$1" | grep -avE "$OLD_NEG" | grep -aq .; }
ok "D0: the mutated NEG really lost the three new alternatives" "! printf '%s' '$OLD_NEG' | grep -q 'Nonexistent function' && printf '%s' '$_NEG' | grep -q 'Nonexistent function'"
ok "D1: OLD behaviour trips BUILD-GATE on the stub_params.gd 'Invalid call' line (the live false positive)" "old_hit '$tmp/a1.log'"
ok "D2: OLD behaviour trips BUILD-GATE on the GutMain 'Invalid call' line" "old_hit '$tmp/a2.log'"
ok "D3: OLD behaviour trips BUILD-GATE on 'Invalid get index'" "old_hit '$tmp/a3.log'"
ok "D4: OLD whole-log grep trips on the STALE Parse Error that the current run no longer has" "old_hit '$tmp/c.log'"
ok "D5: the NEW function does not trip on any of them" "[ \"\$(hits '$tmp/a1.log' 0)\" = 0 ] && [ \"\$(hits '$tmp/a2.log' 0)\" = 0 ] && [ \"\$(hits '$tmp/a3.log' 0)\" = 0 ] && [ \"\$(hits '$tmp/c.log' $voff)\" = 0 ]"

echo "== E: wiring - both BUILD-GATE sites use the function (not the cumulative-log grep)"
ok "E1: the gate condition calls ovn_buildbreak_hits with the verify offset" "grep -c 'ovn_buildbreak_hits \"\$task_log\" \"\${_ovn_voff:-0}\"' '$RO' | grep -qx 2"
ok "E2: no inline cumulative-log POS/NEG grep is left in run_overnight.sh code" "[ \"\$(grep -vE '^[[:space:]]*#' '$RO' | grep -c 'grep -aE \"\$_BUILD_BREAK_POS_RE\" \"\$task_log\"')\" = 0 ]"

echo "buildgate godot runtime scope: $P passed, $F failed"
[ "$F" -eq 0 ]
