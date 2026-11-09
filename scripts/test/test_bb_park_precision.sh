#!/usr/bin/env bash
# Z5-B: scripts/ovn_bb_park_precision.py (would-park precision from outcomes.jsonl) + the pinned decision that OVN_BUILD_BREAK_PARK stays SHADOW by default
# (7-day measure 2026-11-08: 12 would-park events, 4 of them for items that LANDED afterwards = 66.7% precision < the 80% bar). Mutants must be killed.
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
SRC="$HERE/../ovn_bb_park_precision.py"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1 (expected [$2] got [$3])"; fi; }
row(){ printf '{"ts":"%s","repo":"xlite","class":"%s","status":"%s","item_hash":"%s"}\n' "$1" "$2" "$3" "$4"; }
{
  # item aaaaaa: 3 build-break reverts, then lands -> events at count 2 and 3, both FALSE parks
  row 2026-11-05T01:00:00Z reverted 'reverted(build-break)' aaaaaa111111; row 2026-11-05T02:00:00Z reverted 'reverted(build-break)' aaaaaa111111
  row 2026-11-05T03:00:00Z reverted 'reverted(build-break)' aaaaaa111111; row 2026-11-05T04:00:00Z landed 'pushed(tests:pass)' aaaaaa111111
  # item bbbbbb: 2 reverts, never lands -> 1 TRUE park
  row 2026-11-06T01:00:00Z reverted 'reverted(build-break)' bbbbbb222222; row 2026-11-06T02:00:00Z reverted 'reverted(build-break)' bbbbbb222222
  # item ffffff: landed EARLIER, then 2 reverts and never again -> 1 TRUE park (an earlier landing is not a later one)
  row 2026-11-04T00:00:00Z landed 'pushed(tests:pass)' ffffff666666; row 2026-11-07T03:00:00Z reverted 'reverted(build-break)' ffffff666666; row 2026-11-07T04:00:00Z reverted 'reverted(build-break)' ffffff666666
  # item cccccc: a landing in between RESETS the counter -> never reaches 2 -> no event
  row 2026-11-06T05:00:00Z reverted 'reverted(build-break)' cccccc333333; row 2026-11-06T06:00:00Z landed 'pushed(tests:pass)' cccccc333333; row 2026-11-06T07:00:00Z reverted 'reverted(build-break)' cccccc333333
  # item dddddd: old (outside 7 days of the newest row) -> not counted
  row 2026-10-01T01:00:00Z reverted 'reverted(build-break)' dddddd444444; row 2026-10-01T02:00:00Z reverted 'reverted(build-break)' dddddd444444
  # test-red reverts are not build-break
  row 2026-11-07T01:00:00Z reverted 'reverted(tests-red)' eeeeee555555; row 2026-11-07T02:00:00Z reverted 'reverted(tests-red)' eeeeee555555
} > "$T/o.jsonl"
run(){ "$PY" "${1:-$SRC}" --outcomes "$T/o.jsonl" "${@:2}"; }
j(){ "$PY" -c "import json,sys; d=json.load(sys.stdin); print($1)"; }
chk "P1 events: 2 (aaaaaa) + 1 (bbbbbb) + 1 (ffffff) within 7 days; cccccc reset, dddddd old, tests-red ignored" 4 "$(run | j 'd["events"]')"
chk "P2 false parks = the 2 events of the item that landed afterwards" 2 "$(run | j 'd["false_parks"]')"
chk "P3 precision = 2/4" 0.5 "$(run | j 'd["precision"]')"
chk "P4 --after 3: only the third revert of aaaaaa counts (1 event, false)" "1 1" "$(run "$SRC" --after 3 | j '"%d %d" % (d["events"], d["false_parks"])')"
chk "P5 a missing file is an error, not a crash" 1 "$("$PY" "$SRC" --outcomes "$T/none" >/dev/null; echo $?)"
chk "P6 empty rows -> precision null" None "$(: > "$T/e"; "$PY" "$SRC" --outcomes "$T/e" | j 'd["precision"]')"
# the decision is pinned: default stays SHADOW, enforce/off still selectable (lib_build_break_park.sh)
grep -q 'OVN_BUILD_BREAK_PARK:-shadow' "$HERE/../lib_build_break_park.sh" && chk "P7 default stays shadow (precision 66.7% < 80%)" 1 1 || chk "P7 default stays shadow" 1 0
grep -q 'precision' "$HERE/../lib_build_break_park.sh" && chk "P8 the lib documents the measured precision" 1 1 || chk "P8 lib documents the precision" 1 0
mutants=0; survived=0
mut(){ local label="$1" old="$2" new="$3"; mutants=$((mutants+1)); OLD="$old" NEW="$new" "$PY" - "$SRC" "$T/mut.py" <<'PYEOF' || { echo "  FAIL mutant not applicable: $label"; survived=$((survived+1)); return; }
import os, sys
s = open(sys.argv[1]).read(); old = os.environ["OLD"]
if old not in s: sys.exit(3)
open(sys.argv[2], "w").write(s.replace(old, os.environ["NEW"], 1))
PYEOF
  local a b; a="$(run "$T/mut.py" | j '"%s %s" % (d["events"], d["false_parks"])')"; b="$(run | j '"%s %s" % (d["events"], d["false_parks"])')"
  [ "$a" != "$b" ] && echo "  ok   mutant killed: $label" || { echo "  FAIL mutant SURVIVED: $label"; survived=$((survived+1)); }
}
mut "landing does not reset the counter" 'cnt[k] = 0' 'pass'
mut "any revert counts as build-break" '"build-break" in str(r.get("status", ""))' 'True'
mut "no 7-day window" 'and _ts(r) >= lo' ''
mut "landing before the event counts as landed-later" 'rows[i + 1:]' 'rows'
chk "P9 mutants survived" 0 "$survived"
echo "bb park precision: $P passed, $F failed ($mutants mutants)"
[ "$F" -eq 0 ]
