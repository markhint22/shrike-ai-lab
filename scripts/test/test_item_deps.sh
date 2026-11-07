#!/usr/bin/env bash
# Y4 (2026-11-05): production-before-test. Part U: ovn_item_deps.py unit + mutants. Part W: wiring in run_overnight.sh / ovn_stage_runner.sh / ovn_planner.sh.
# Part F: read_file pseudo tool-call is a file ask (empty-file stall: the architect answered '<function=read_file>' and the declared NEW test file stayed 0 bytes).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
ROOT="$(cd "$HERE/../.." && pwd)"; RUNNER="${OVN_RUNNER_SRC:-$ROOT/ovn_stage_runner.sh}"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
tmp="$(safe_mktemp_dir y4-deps)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
echo "== U: unit + mutants"
OVN_TEST_TMP="$tmp" python3 -I "$HERE/test_item_deps.py" > "$tmp/u.out" 2>&1; urc=$?
cat "$tmp/u.out"
ok "U0 test_item_deps.py exits 0" "[ $urc -eq 0 ]"
echo "== W: wiring"
RO="$ROOT/run_overnight.sh"; PL="$ROOT/ovn_planner.sh"
ok "W1 stage runner picker calls _id_item_filter before the D3 filter" "grep -n '_id_item_filter | grep' '$RUNNER' | head -1 | grep -q ."
ok "W2 stage runner default mode is shadow" "grep -q '_ID_MODE=\"\${OVN_ITEM_DEPS:-shadow}\"' '$RUNNER'"
ok "W3 scout slice pipes through _ovn_id_slice_filter" "grep -q '| _ovn_id_slice_filter' '$RO'"
ok "W4 scout filter default mode is shadow + empty-slice fail-open" "grep -q 'OVN_ITEM_DEPS:-shadow' '$RO' && sed -n '/^# >>> y4 scout item-deps filter/,/^# <<< y4 scout item-deps filter/p' '$RO' | grep -q '\[ -n \"\$_out\" \]'"
ok "W5 planner orders items before feat tagging, default on, fail-safe count check" "grep -q 'OVN_PLANNER_ITEM_ORDER:-on' '$PL' && grep -q 'ovn_item_deps.py\" order' '$PL' || grep -q 'python3 \"\$_iorder\" order' '$PL'"
ok "W6 the three scripts parse" "bash -n '$RUNNER' && bash -n '$RO' && bash -n '$PL'"
# W7: the real scout filter function, shadow vs enforce, on the real group
SD="$tmp/s"; mkdir -p "$SD/scripts" "$SD/state"
cp "$ROOT/scripts/ovn_item_deps.py" "$ROOT/scripts/ovn_stage_order.py" "$SD/scripts/"; cp "$HERE/fixtures/item_deps/group_iptv_wipe_shared.md" "$SD/OVERNIGHT_PROGRESS.md"
sed -n '/^# >>> y4 scout item-deps filter/,/^# <<< y4 scout item-deps filter/p' "$RO" > "$SD/f.sh"
grep '^- \[ \] ' "$SD/OVERNIGHT_PROGRESS.md" > "$tmp/all.txt"; tail -n +2 "$tmp/all.txt" > "$tmp/tests.txt"
sl(){ ( cd "$SD" && SCRIPT_DIR="$SD" STATE_DIR="$SD/state" OVN_ITEM_DEPS="$1" bash -c ". '$SD/f.sh'; _ovn_id_slice_filter" ); }
w7_shadow(){ sl shadow < "$tmp/all.txt" > "$tmp/o1.txt"; cmp -s "$tmp/o1.txt" "$tmp/all.txt"; }
w7_enforce(){ sl enforce < "$tmp/all.txt" > "$tmp/o2.txt"; [ "$(grep -c . "$tmp/o2.txt")" = 1 ] && head -1 "$tmp/o2.txt" | grep -q 'routers/discover.py'; }
w7_empty(){ sl enforce < "$tmp/tests.txt" > "$tmp/o3.txt"; cmp -s "$tmp/o3.txt" "$tmp/tests.txt"; }
w7_missing(){ mv "$SD/scripts/ovn_item_deps.py" "$SD/scripts/x.py"; sl enforce < "$tmp/all.txt" > "$tmp/o4.txt"; local r=0; cmp -s "$tmp/o4.txt" "$tmp/all.txt" || r=1; mv "$SD/scripts/x.py" "$SD/scripts/ovn_item_deps.py"; return $r; }
ok "W7 shadow: slice unchanged" "w7_shadow"
ok "W7 shadow: journal written under STATE_DIR" "[ -s '$SD/state/item_deps_shadow.log' ]"
ok "W7 enforce: only the production line is offered" "w7_enforce"
ok "W7 enforce: a slice that would be EMPTY returns the input" "w7_empty"
ok "W7 helper missing: unchanged (fail-open)" "w7_missing"
echo "== F: read_file pseudo tool call is a file ask"
sed -n '/^# >>> n4-stage-waste helpers: scope-learn/,/^# <<< n4-stage-waste helpers: scope-learn/p' "$RUNNER" > "$tmp/h.sh"; sed -n '/^# >>> n4-stage-waste helpers: file-feed/,/^# <<< n4-stage-waste helpers: file-feed/p' "$RUNNER" >> "$tmp/h.sh"
grep -q '^stage_feed_files()' "$tmp/h.sh" || { echo "  FAIL: feed helper block not found"; exit 1; }
W="$tmp/repo"; mkdir -p "$W/iptv-backend/tests" "$W/iptv-backend/app/core"; git -C "$W" init -q; git -C "$W" config user.email t@t; git -C "$W" config user.name t
echo "x=1" > "$W/iptv-backend/tests/conftest.py"; echo "y=1" > "$W/iptv-backend/app/core/limiter.py"; git -C "$W" add -A; git -C "$W" commit -qm i
cat > "$tmp/tc.log" <<'LOG'
I need to see the test fixtures and the limiter implementation to write a
correct test.

<tool_call> <function=read_file> <parameter=path> iptv-backend/tests/conftest.py
</tool_call> <tool_call> <function=read_file> <parameter=path>
iptv-backend/app/core/limiter.py   </tool_call>

Tokens: 19k sent, 83 received.
iptv-backend/app/core/limiter.py
LOG
. "$tmp/h.sh"
ok "F1 stage_feed_asked sees the read_file tool call" "stage_feed_asked '$tmp/tc.log'"
ok "F2 both named files are fed (same-line path and next-line path)" "o=\$(stage_feed_files '$tmp/tc.log' '$W' '' 3 | sort | tr '\n' ' '); [ \"\$o\" = 'iptv-backend/app/core/limiter.py iptv-backend/tests/conftest.py ' ]"
ok "F3 an already-loaded file is not fed twice" "o=\$(stage_feed_files '$tmp/tc.log' '$W' 'iptv-backend/tests/conftest.py' 3); [ \"\$o\" = iptv-backend/app/core/limiter.py ]"
printf 'I read the code and it looks fine.\n' > "$tmp/no.log"
nok "F4 no ask -> nothing fed" "stage_feed_asked '$tmp/no.log' || [ -n \"\$(stage_feed_files '$tmp/no.log' '$W' '' 3)\" ]"
# mutant: the old regex (prose ask only) misses the tool call
sed "s/|<function=read_file>//" "$tmp/h.sh" > "$tmp/m.sh"
nok "F5 MUTANT old regex is caught by F1" "( . '$tmp/m.sh'; stage_feed_asked '$tmp/tc.log' )"
sed 's/(i if "function=read_file" in ln else i + 1)/(i + 1)/' "$tmp/h.sh" > "$tmp/m2.sh"
nok "F6 MUTANT scan-from-next-line (loses the same-line path) is caught by F2" "( . '$tmp/m2.sh'; o=\$(stage_feed_files '$tmp/tc.log' '$W' '' 3 | sort | tr '\n' ' '); [ \"\$o\" = 'iptv-backend/app/core/limiter.py iptv-backend/tests/conftest.py ' ] )"
echo; echo "item deps: passed $P failed $F"
[ "$F" -eq 0 ]
