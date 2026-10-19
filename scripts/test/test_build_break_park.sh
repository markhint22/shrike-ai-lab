#!/usr/bin/env bash
# test_build_break_park.sh - 2026-10-18: scripts/lib_build_break_park.sh (ovn_bb_escalate), wired in run_overnight.sh at the reverted(build-break) site.
# xlite "delete dead TurnManager helpers" was build-gate-reverted 3x in a row (~45 min each) and nothing re-routed it. After OVN_BUILD_BREAK_PARK_AFTER (2) build-break reverts of the SAME item
# the item is tagged `[CLAUDE] [AUTO-SKIP build-break ...]` (enforce) or only reported `would-park` (SHADOW, the default). Every behaviour has a negative control and a MUTANT.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1 (expected [$2] got [$3])"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
safe_set_sandbox_home "$T" || exit 1; mkdir -p "$HOME"
unset OVN_BUILD_BREAK_PARK OVN_BUILD_BREAK_PARK_AFTER

LIBDIR="$Q/scripts"
load(){  # <lib file to load as lib_build_break_park.sh>
  unset -f ovn_bb_escalate 2>/dev/null
  . "$LIBDIR/lib_item_select.sh"; . "$LIBDIR/lib_run_integrity.sh"; . "${1:-$LIBDIR/lib_build_break_park.sh}"
}
mkrepo(){  # fresh repo + state dir + task log naming turn_manager.gd
  rm -rf "$T/r" "$T/state"; mkdir -p "$T/r" "$T/state"
  ( cd "$T/r" && git init -q -b main && printf '# progress\n- [ ] Delete dead helpers from scripts/turn_manager.gd [feat:xlite-20261018-tm]\n- [ ] Add docs to scripts/other.gd\n' > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m base )
  printf 'VERDICT: PROCEED\nFILES: scripts/turn_manager.gd\n' > "$T/task.log"
}
esc(){ ovn_bb_escalate "$T/r" "$T/state" "$T/task.log" "" 2>/dev/null; }
load

echo "== escalation counting (SHADOW default)"
mkrepo
eq "B1: first build-break revert of an item is only counted" "count 1" "$(esc)"
eq "B2: second revert in SHADOW mode reports would-park, nothing edited" "would-park 2" "$(esc)"
ok "B3: SHADOW never edits OVERNIGHT_PROGRESS.md" "$(git -C "$T/r" diff --quiet && echo 1 || echo 0)"
eq "B4: a third revert still shadow" "would-park 3" "$(esc)"

echo "== enforce"
mkrepo; export OVN_BUILD_BREAK_PARK=enforce
eq "E1: first revert: count 1 (not parked yet)" "count 1" "$(esc)"
ok "E2: ... item line untouched" "$(grep -q '^- \[ \] Delete dead helpers' "$T/r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
eq "E3: second consecutive revert parks the item" "parked 2" "$(esc)"
ok "E4: the line carries [CLAUDE] [AUTO-SKIP build-break" "$(grep -q '^- \[ \] \[CLAUDE\] \[AUTO-SKIP build-break: reverted 2x' "$T/r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "E5: ... committed" "$(git -C "$T/r" log -1 --format=%s | grep -q 'park item for Claude - 2 consecutive build-break' && echo 1 || echo 0)"
ok "E6: the OTHER item is untouched" "$(grep -q '^- \[ \] Add docs to scripts/other.gd' "$T/r/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
ok "E7: the picker no longer offers the parked item (tag excluded by OVN_PARKED_CI_ERE)" "$(ovn_resolve_top_item "$T/r" "" | grep -q 'turn_manager' && echo 0 || echo 1)"

echo "== separate items / landing / switches"
mkrepo; export OVN_BUILD_BREAK_PARK=enforce
esc >/dev/null   # turn_manager: 1
printf 'VERDICT: PROCEED\nFILES: scripts/other.gd\n' > "$T/task.log"
eq "S1: a DIFFERENT item has its own counter (count 1, not parked)" "count 1" "$(esc)"
printf 'VERDICT: PROCEED\nFILES: scripts/turn_manager.gd\n' > "$T/task.log"
h="$(ovn_item_hash "Delete dead helpers from scripts/turn_manager.gd [feat:xlite-20261018-tm]")"
ovn_ri_revert_reset "$T/state" r "$h"
eq "S2: after the item LANDS (ovn_ri_revert_reset) the count restarts" "count 1" "$(esc)"
mkrepo; export OVN_BUILD_BREAK_PARK=off
eq "S3: OVN_BUILD_BREAK_PARK=off prints nothing" "" "$(esc)"
ok "S3b: ... and counts nothing" "$([ -z "$(ls "$T/state/nr_reverts" 2>/dev/null)" ] && echo 1 || echo 0)"
mkrepo; export OVN_BUILD_BREAK_PARK=enforce OVN_BUILD_BREAK_PARK_AFTER=3
eq "S4: OVN_BUILD_BREAK_PARK_AFTER=3: second revert is still just a count" "count 2" "$( esc >/dev/null; esc)"
eq "S4b: third parks" "parked 3" "$(esc)"
unset OVN_BUILD_BREAK_PARK_AFTER
mkrepo; export OVN_BUILD_BREAK_PARK=enforce; printf 'VERDICT: PROCEED\nFILES: scripts/nothing_matches.gd\n' > "$T/task.log"
eq "S5: the scout named no item in the queue: no verdict, no guessing at the top line" "" "$(esc)"
ok "S5b: ... and nothing counted" "$([ -z "$(ls "$T/state/nr_reverts" 2>/dev/null)" ] && echo 1 || echo 0)"
mkrepo; export OVN_BUILD_BREAK_PARK=enforce
ovn_resolve_top_item(){ printf '99:- [ ] ghost item'; }; esc >/dev/null
eq "S6: the line is not an open item any more: park-failed, tree clean" "park-failed 2" "$(esc)"
ok "S6b: ... nothing committed or edited" "$(git -C "$T/r" diff --quiet && [ "$(git -C "$T/r" log --oneline | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
load
eq "S7: a missing repo dir is a silent no-op" "" "$(ovn_bb_escalate "$T/nodir" "$T/state" "" "" 2>/dev/null)"

echo "== wiring in run_overnight.sh"
RO="$Q/run_overnight.sh"
ok "W1: run_overnight.sh sources the library" "$(grep -q 'source "\$SCRIPT_DIR/scripts/lib_build_break_park.sh"' "$RO" && echo 1 || echo 0)"
ok "W2: ovn_bb_escalate is called immediately before the reverted(build-break) status" "$(awk '/ovn_bb_escalate "\$PWD"/{c=1} c && /echo "reverted\(build-break\)"/{print "y"; exit}' "$RO" | grep -q y && echo 1 || echo 0)"
ok "W3: run_overnight.sh parses" "$(bash -n "$RO" 2>/dev/null && echo 1 || echo 0)"
ok "W4: the default is SHADOW (documented switch)" "$(grep -q 'OVN_BUILD_BREAK_PARK:-shadow' "$Q/scripts/lib_build_break_park.sh" && echo 1 || echo 0)"

echo "== MUTANTS"
mutlib(){  # <anchor> <replacement>
  python3 -I - "$LIBDIR/lib_build_break_park.sh" "$T/mut_lib.sh" "$1" "$2" <<'PY'
import sys
s=open(sys.argv[1]).read(); assert sys.argv[3] in s, "anchor missing: "+sys.argv[3]
open(sys.argv[2],"w").write(s.replace(sys.argv[3],sys.argv[4],1))
PY
}
mutlib 'if [ "$mode" != enforce ]; then' 'if false; then' || { F=$((F+1)); echo "  FAIL mutation anchor"; }; load "$T/mut_lib.sh"
mkrepo; export OVN_BUILD_BREAK_PARK=shadow; esc >/dev/null; esc >/dev/null
ok "M1: MUTANT (shadow guard removed) edits the progress file in shadow mode - the B3 case catches it" "$(git -C "$T/r" diff --quiet HEAD && [ "$(git -C "$T/r" log --oneline | wc -l | tr -d ' ')" = 1 ] && echo 0 || echo 1)"
mutlib 'if [ "$n" -lt "$after" ]; then' 'if [ "$n" -lt 99 ]; then' || { F=$((F+1)); echo "  FAIL mutation anchor"; }; load "$T/mut_lib.sh"
mkrepo; export OVN_BUILD_BREAK_PARK=enforce; esc >/dev/null
ok "M2: MUTANT (threshold ignored) no longer parks at the 2nd revert - E3 catches it" "$([ "$(esc)" = "parked 2" ] && echo 0 || echo 1)"
mutlib '"$task_log" nofallback' '"$task_log"' || { F=$((F+1)); echo "  FAIL mutation anchor"; }; load "$T/mut_lib.sh"
mkrepo; export OVN_BUILD_BREAK_PARK=enforce; printf 'VERDICT: PROCEED\nFILES: scripts/nothing_matches.gd\n' > "$T/task.log"
ok "M3: MUTANT (top-of-file fallback) guesses an item when the scout named none - S5 catches it" "$([ -n "$(esc)" ] && echo 1 || echo 0)"
mutlib '"$h" "build-break"' '"$h" "build-break-$RANDOM"' || { F=$((F+1)); echo "  FAIL mutation anchor"; }; load "$T/mut_lib.sh"
mkrepo; export OVN_BUILD_BREAK_PARK=enforce; esc >/dev/null
ok "M4: MUTANT (counter never accumulates) never reaches the threshold - E3 catches it" "$([ "$(esc)" = "parked 2" ] && echo 0 || echo 1)"
mutlib '[ "$mode" = off ] && return 0' ':' || { F=$((F+1)); echo "  FAIL mutation anchor"; }; load "$T/mut_lib.sh"
mkrepo; export OVN_BUILD_BREAK_PARK=off
ok "M5: MUTANT (off switch ignored) still counts - S3 catches it" "$([ -n "$(esc)" ] && echo 1 || echo 0)"

echo "build-break-park: $P passed, $F failed"
[ "$F" -eq 0 ]
