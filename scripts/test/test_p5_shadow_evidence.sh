#!/usr/bin/env bash
# P5 (2026-10-21): shadow-evidence quality for the two shadow gates, so enforcement can be decided on evidence.
#   J  stage-order journal: ts / run / item_hash / prereq state / decision_id, count merge, rotation, outcome join   (test_stage_order_journal.py, incl. its own mutants)
#   L  verify-lint unsatisfiable shapes S6 S7 S8 S9 U4 + V4/V1 rewrites                                                (test_p5_lint_shapes.py, incl. its own mutants)
#   U  verify_gate_shadow.log: UNRUNNABLE (rc 126/127, npx "To get access to the TypeScript compiler", ModuleNotFoundError at the clause itself) logged apart from FAIL;
#      _LAST_VERIFY_RESULT stays FAIL (log-only, no decision changes); mutants collapsing the two are caught
#   H  the record_outcome hook (REAL function extracted from run_overnight.sh) writes the joined outcome row; a copy without the hook does not
# Shadow only: nothing here turns enforcement on.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$(cd "$HERE/.." && pwd)"; Q="$(cd "$S/.." && pwd)"
PY="$(command -v python3.12 || command -v python3)"
P=0; F=0
t(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $n"; else F=$((F+1)); echo "  FAIL $n"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME" "$W/tmp"
export PYTHONDONTWRITEBYTECODE=1
unset OVN_STAGE_ORDER OVN_STAGE_ORDER_LOG OVN_VERIFY_UNRUNNABLE_SHAPES NTFY_SERVER NTFY_TOPIC

echo "== J: stage-order journal evidence"
mkdir -p "$W/j"; OVN_TEST_TMP="$W/j" "$PY" -I "$HERE/test_stage_order_journal.py" > "$W/j.out" 2>&1; jrc=$?
grep -vE '^  ok   ' "$W/j.out"
t "J: test_stage_order_journal.py exits 0 (contract + 7 mutants)" test "$jrc" -eq 0

echo "== L: verify-lint shapes"
"$PY" "$HERE/test_p5_lint_shapes.py" > "$W/l.out" 2>&1; lrc=$?
grep -vE '^  ok   ' "$W/l.out"
t "L: test_p5_lint_shapes.py exits 0 (contract + 13 mutants)" test "$lrc" -eq 0

echo "== U: UNRUNNABLE vs FAIL in verify_gate_shadow.log"
[ -f "$S/lib_verify_clause.sh" ] || { echo "  FAIL: lib_verify_clause.sh missing"; exit 1; }
mkdir -p "$W/bin" "$W/repo"
# npx stub: what npx prints (and its exit status 1) when typescript is not installed in the project
printf '#!/bin/sh\necho "                         To get access to the TypeScript compiler, tsc, from the command line either:"\necho "  - Use npm install typescript to first add TypeScript to your project before using npx"\nexit 1\n' > "$W/bin/npx"; chmod +x "$W/bin/npx"
export PATH="$W/bin:$PATH"
cat > "$W/prog.md" <<'EOP'
- [ ] [T2] a.ts - tsc. VERIFY: `npx tsc --noEmit`
- [ ] [T2] a.py - import of a root that does not exist. VERIFY: `python3 -c "from nosuchroot_p5.app import x"`
- [ ] [T2] a.py - command that does not exist. VERIFY: `nosuchcommand_p5_xyz --version`
- [ ] [T2] a.py - a genuine red assertion. VERIFY: `python3 -c "assert 1 == 2"`
- [ ] [T2] a.sh - a genuine failing command. VERIFY: `false`
- [ ] [T2] a.py - green. VERIFY: `python3 -c "assert 1 == 1"`
EOP
runlib(){  # $1 = lib file, $2.. = env assignments; prints the rows of the six clauses ("<n>|<row result=..>|<_LAST_VERIFY_RESULT>")
  local lib="$1"; shift
  ( cd "$W/repo" || exit 1
    export OVN_VERIFY_SHADOW_LOG="$W/shadow.$$.log"; : > "$OVN_VERIFY_SHADOW_LOG"
    for kv in "$@"; do export "$kv"; done
    . "$lib"
    PROG="$W/prog.md"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
    for n in 1 2 3 4 5 6; do
      shadow_check "$n"
      printf '%s|%s|%s\n' "$n" "$(grep -a "line=$n " "$SHADOW_LOG" | tail -1 | grep -aoE 'result=[A-Z_]+( rc=[0-9]+)?( why=[a-z0-9-]+)?')" "$_LAST_VERIFY_RESULT"
    done )
}
OUT="$(runlib "$S/lib_verify_clause.sh")"
echo "$OUT" | sed 's/^/    /'
row(){ printf '%s\n' "$1" | grep -a "^$2|" | cut -d'|' -f2; }
res(){ printf '%s\n' "$1" | grep -a "^$2|" | cut -d'|' -f3; }
unr_ok(){  # $1=output; the contract
  [ "$(row "$1" 1)" = "result=UNRUNNABLE rc=127" ] && [ "$(row "$1" 2)" = "result=UNRUNNABLE rc=1 why=module-not-found-clause" ] \
  && [ "$(row "$1" 3)" = "result=UNRUNNABLE rc=127" ] && [ "$(row "$1" 4)" = "result=FAIL rc=1" ] && [ "$(row "$1" 5)" = "result=FAIL rc=1" ] && [ "$(row "$1" 6)" = "result=PASS" ]
}
# 2026-10-22 integration: PKG-B (merged first) made a missing `npx tsc` a real decision change (rc 127, tool-not-installed), which supersedes the P5 shadow-only npx-tsc-missing tag.
t "U1 npx 'To get access to the TypeScript compiler' -> UNRUNNABLE rc=127 (PKG-B tool-not-installed)" test "$(row "$OUT" 1)" = "result=UNRUNNABLE rc=127"
t "U2 ModuleNotFoundError at the clause itself -> UNRUNNABLE why=module-not-found-clause" test "$(row "$OUT" 2)" = "result=UNRUNNABLE rc=1 why=module-not-found-clause"
t "U3 command not found (rc 127) -> UNRUNNABLE (unchanged)" test "$(row "$OUT" 3)" = "result=UNRUNNABLE rc=127"
t "U4 a genuine red assertion stays FAIL" test "$(row "$OUT" 4)" = "result=FAIL rc=1"
t "U5 a genuine failing command stays FAIL" test "$(row "$OUT" 5)" = "result=FAIL rc=1"
t "U6 a green clause stays PASS" test "$(row "$OUT" 6)" = "result=PASS"
t "U7 LOG-ONLY: the import row decision variable is still FAIL (no decision change; npx row is UNRUNNABLE via PKG-B)" test "$(res "$OUT" 1)" = UNRUNNABLE -a "$(res "$OUT" 2)" = FAIL
t "U8 the rc-127 row keeps its UNRUNNABLE decision variable" test "$(res "$OUT" 3)" = UNRUNNABLE
OFF="$(runlib "$S/lib_verify_clause.sh" OVN_VERIFY_UNRUNNABLE_SHAPES=off)"
t "U9 kill switch OVN_VERIFY_UNRUNNABLE_SHAPES=off restores the FAIL import row (npx stays PKG-B UNRUNNABLE)" test "$(row "$OFF" 1)" = "result=UNRUNNABLE rc=127" -a "$(row "$OFF" 2)" = "result=FAIL rc=1"
unr_bad(){ ! unr_ok "$1"; }
# mutants: each broken copy of the library must FAIL the contract
LIBDIR="$W/libm"; mkdir -p "$LIBDIR"
sed "s/printf 'npx-tsc-missing'; return 0/:/" "$S/lib_verify_clause.sh" > "$LIBDIR/m1.sh"
t "U10 npx row is decided by PKG-B, independent of the P5 classifier (mutant still UNRUNNABLE rc=127)" unr_ok "$(runlib "$LIBDIR/m1.sh")"
sed "s/\[ -n \"\$_unrk\" \]/true/" "$S/lib_verify_clause.sh" > "$LIBDIR/m2.sh"
t "U11 mutant (every non-zero outcome logged UNRUNNABLE) is caught" unr_bad "$(runlib "$LIBDIR/m2.sh")"
sed "s/\[ -n \"\$_unrk\" \]/false/" "$S/lib_verify_clause.sh" > "$LIBDIR/m3.sh"
t "U12 mutant (UNRUNNABLE never logged: collapsed into FAIL) is caught" unr_bad "$(runlib "$LIBDIR/m3.sh")"
sed "s/grep -aq 'ModuleNotFoundError' <<< \"\$_o\" \&\&/true \&\&/" "$S/lib_verify_clause.sh" > "$LIBDIR/m4.sh"
t "U13 mutant (a python -c with ANY failure is 'import error') is caught" unr_bad "$(runlib "$LIBDIR/m4.sh")"
t "U14 the real contract holds on the real library" unr_ok "$OUT"

echo "== H: record_outcome writes the joined outcome row"
RO="$Q/run_overnight.sh"
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$RO")"
t "H0 record_outcome extracted" test -n "$FN_SRC"
hook(){  # $1 = function source; $2 = "staged" -> a staged cycle (task log carries a stage-item-hash that differs from the line hash); prints the number of rows in stage_order_outcomes.jsonl after one outcome for a flagged item
  ( SCRIPT_DIR="$Q"; STATE_DIR="$W/h/state.$RANDOM"; mkdir -p "$STATE_DIR"
    . "$S/lib_item_select.sh" 2>/dev/null
    eval "$1"
    local rd="$W/h/repo.$RANDOM"; mkdir -p "$rd"
    cp "$HERE/fixtures/stage_order/group_taa_get_live_role.md" "$rd/OVERNIGHT_PROGRESS.md"
    # a flagged item = one of the 3 test lines the shadow filter would skip; put it first so the legacy attribution resolves it
    local tl; tl="$(grep -a '^- \[ \] \[T[345]\]' "$rd/OVERNIGHT_PROGRESS.md" | head -1)"
    printf '# progress\n%s\n' "$tl" > "$rd/OVERNIGHT_PROGRESS.md"
    cp "$HERE/fixtures/stage_order/group_taa_get_live_role.md" "$W/h/full.md"
    printf '%s\n' "$(grep -a '^- \[ \] \[T' "$W/h/full.md")" | "$PY" -I "$Q/scripts/ovn_stage_order.py" item-filter --progress "$W/h/full.md" --repo taa --log "$STATE_DIR/stage_order_shadow.log" >/dev/null 2>&1
    local st="reverted(red-tests)" tlog=/dev/null
    if [ "${2:-}" = staged ]; then
      st="reverted(red-tests) stage(higher-tier)"; tlog="$W/h/stage.$RANDOM.log"
      { echo "stage-item-hash 0123456789abcdef0123456789abcdef"; echo "stage-item-line $(printf '%s' "$tl" | sed 's/^- \[ \] //; s/^/- [ ] /')"; } > "$tlog"
    fi
    OVN_OUTCOME_ATTRIB=legacy record_outcome "t-1" taa "$st" "" aider_fix 1 "$tlog" 61 "$rd" >/dev/null 2>&1
    n=0; [ -f "$STATE_DIR/stage_order_outcomes.jsonl" ] && n="$(wc -l < "$STATE_DIR/stage_order_outcomes.jsonl" | tr -d ' ')"
    echo "$n $( [ -f "$STATE_DIR/stage_order_outcomes.jsonl" ] && "$PY" -c "import json,sys;r=json.loads(open(sys.argv[1]).readline());print(r['class'],r['credited'],r['verified'],r['duration_s'],len(r['decision_ids']))" "$STATE_DIR/stage_order_outcomes.jsonl")" )
}
HOUT="$(hook "$FN_SRC")"
echo "    $HOUT"
t "H1 one outcome row was written for the flagged item" test "${HOUT%% *}" = 1
t "H2 it carries class reverted, credited False, verified False, duration_s 61 and 3 joined decision ids" test "$HOUT" = "1 reverted False False 61 3"
NOHOOK="$(printf '%s\n' "$FN_SRC" | sed '/P5, shadow evidence/,/^  fi$/d')"
t "H3 mutant (hook removed from record_outcome) is caught" test "$(hook "$NOHOOK" | cut -d' ' -f1)" = 0
HSTG="$(hook "$FN_SRC" staged)"
echo "    staged: $HSTG"
t "H5 a STAGED item's outcome joins by the line hash, not the stage-billing hash" test "$HSTG" = "1 reverted False False 61 3"
BADJ="$(printf '%s\n' "$FN_SRC" | sed 's/--item-hash "${_line_hash:-$item_hash}"/--item-hash "$item_hash"/')"
t "H6 mutant (hook passes the stage-billing hash) is caught" test "$(hook "$BADJ" staged | cut -d' ' -f1)" = 0
t "H4 record_outcome still parses with the hook (bash -n on the runner)" bash -n "$RO"

echo "test_p5_shadow_evidence: pass=$P fail=$F"
[ "$F" -eq 0 ]
