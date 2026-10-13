#!/usr/bin/env bash
# R14 verify package (2026-10-12), bash side: lib_verify_clause.sh shadow_check
#   X1 POLARITY  an item whose VERIFY states an ABSENCE ("returns no matches", "fails with No such file") passes only when the command's exit status says absent.
#                Every credit path (auto-credit, credit_already_satisfied, scout ALREADY-DONE gate, fix-up reverify, spec check) goes through shadow_check.
#   X2 GUT       clauses GUT cannot run (-gdir=<file>.gd, bare -gtest=<name>.gd, -gselect=<function>) are normalised before they run; "Nothing was run" is a FAIL.
# A fake `godot` (at $HOME/godot/godot4, where the lib resolves it) emulates the GUT 9.4 behaviours reproduced on the box:
#   -gdir=<file>.gd            "[ERROR]: The path [..] does not exist." (+ "Could not find script matching" with -gselect)   rc 0, nothing run
#   -gtest=<bare>.gd           "Could not find script: <bare>" and then the WHOLE suite runs                                    rc 0
#   -gtest=[res://]<path>.gd   exactly that file (existing) / "Could not find script" (missing)
#   -gselect=<x>               matches script FILE names only
#   -gunit_test_name=<n>       one test when the function exists in the file, else "Nothing was run."                           rc 0
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIBDIR="${OVN_LIB_DIR:-$HERE/..}"
[ -f "$LIBDIR/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"
mkdir -p "$tmp/home/godot" "$tmp/work/tests" "$tmp/work/scripts" "$tmp/work/addons/gut"
cat > "$tmp/home/godot/godot4" <<'EOT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SHIM_ARGS:-/dev/null}"
gdir=""; gtest=""; gsel=""; gut=""
for a in "$@"; do case "$a" in -gdir=*) gdir="${a#-gdir=}";; -gtest=*) gtest="${a#-gtest=}";; -gselect=*) gsel="${a#-gselect=}";; -gunit_test_name=*) gut="${a#-gunit_test_name=}";; esac; done
if [ -n "$gdir" ]; then case "$gdir" in *.gd) echo "[ERROR]: The path [$gdir] does not exist."; [ -n "$gsel" ] && echo "Could not find script matching $gsel"; exit 0;; esac; fi
if [ -n "$gtest" ]; then
  case "$gtest" in
    */*) f="${gtest#res://}"; if [ ! -f "$f" ]; then echo "[ERROR]: Could not find script: $gtest"; exit 0; fi
         if [ -n "$gsel" ]; then case "$f" in *"$gsel"*) ;; *) echo "Could not find script matching $gsel"; exit 0;; esac; fi
         if [ -n "$gut" ]; then if grep -q "func test_$gut\|func $gut" "$f"; then echo "Totals"; echo "  Scripts        1"; echo "  Passing Tests  1"; else echo "Nothing was run."; fi; exit 0; fi
         echo "Totals"; echo "  Scripts        1"; echo "  Passing Tests  2"; exit 0 ;;
    *)   echo "[ERROR]: Could not find script: $gtest"; echo "Totals"; echo "  Scripts        2"; echo "  Passing Tests  9"; exit 0 ;;
  esac
fi
echo "Totals"; echo "  Scripts        1"; echo "  Passing Tests  1"; exit 0
EOT
chmod +x "$tmp/home/godot/godot4"
printf 'func test_faction_for_returns_correct_string():\n\tpass\n' > "$tmp/work/tests/test_enemy_faction_map.gd"
: > "$tmp/work/tests/test_aggro.gd"
printf 'static func is_destructible_type(x):\n\treturn true\n' > "$tmp/work/scripts/aoe.gd"

run_sc(){  # $1 = lib dir, $2 = item line  -> RESULT|WHY|RC
  printf '%s\n' "$2" > "$tmp/prog.md"
  ( cd "$tmp/work" || exit 9
    export HOME="$tmp/home"
    PROG="$tmp/prog.md"; SHADOW_LOG="$tmp/shadow.log"; _REPO_LABEL=t; _VC_MEMO_ON=0; : > "$SHADOW_LOG"
    # shellcheck disable=SC1091
    . "$1/lib_verify_clause.sh"
    shadow_check 1
    printf '%s|%s|%s\n' "$_LAST_VERIFY_RESULT" "${_LAST_VERIFY_WHY:-}" "${_LAST_VERIFY_RC:-}" )
}
res(){ printf '%s' "${1%%|*}"; }
it(){ printf -- '- [ ] [T2] scripts/aoe.gd — x. VERIFY: %s (cat:gd; multifile:no)' "$1"; }

echo "== X1: negative polarity"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "is_destructible_type" scripts/aoe.gd` returns no matches.')")"
ok "symbol STILL present + 'returns no matches' -> FAIL (old code: PASS = the live false credit)" "[ \"\$(res '$r')\" = FAIL ]"
ok "... WHY says the thing is still present" "printf '%s' '$r' | grep -c 'still present' | grep -qx 1"
ok "... and the shadow row is tagged polarity=neg" "grep -c 'result=FAIL rc=1 polarity=neg' '$tmp/shadow.log' | grep -qx 1"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "no_such_symbol_zz" scripts/aoe.gd` returns no matches.')")"
ok "symbol absent + 'returns no matches' -> PASS (old code: FAIL, correct work refused)" "[ \"\$(res '$r')\" = PASS ]"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "x" scripts/missing_file.gd` returns no matches.')")"
ok "grep error rc 2 (file missing) is NOT an absence -> FAIL" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it '`ls scripts/aoe.gd` fails with "No such file or directory".')")"
ok "file STILL exists + 'fails with No such file' -> FAIL (old: PASS)" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it '`ls scripts/gone.gd` fails with "No such file or directory".')")"
ok "file absent + 'fails with No such file' -> PASS (old: FAIL)" "[ \"\$(res '$r')\" = PASS ]"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "is_destructible_type" scripts/aoe.gd | grep -v "zz"` returns no lines containing is_destructible_type.')")"
ok "pipeline that still has lines + 'returns no lines' -> FAIL" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" '- [ ] [T2] scripts/aoe.gd — x. VERIFY: grep -n "no_such_symbol_zz" scripts/aoe.gd returns no results. (cat:gd)')"
ok "BARE 'grep ... returns no results' with the symbol absent is read and PASSes (was 'no VERIFY clause')" "[ \"\$(res '$r')\" = PASS ]"
r="$(run_sc "$LIBDIR" '- [ ] [T2] scripts/aoe.gd — x. VERIFY: grep -n "is_destructible_type" scripts/aoe.gd returns no results. (cat:gd)')"
ok "BARE form with the symbol still present -> FAIL" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "is_destructible_type" scripts/aoe.gd`')")"
ok "CONTROL unknown polarity: grep rc 0 still PASSes (unchanged)" "[ \"\$(res '$r')\" = PASS ]"
# R15: stage errors are not absences (a pipeline exits with its LAST stage's status)
r="$(run_sc "$LIBDIR" "$(it '`grep -n "x" scripts/nodir_zz | grep -v "y"` returns no lines.')")"
ok "R15 earlier-stage grep error (missing dir | grep -v) is NOT an absence -> FAIL (old: PASS)" "[ \"\$(res '$r')\" = FAIL ]"
ok "... WHY names the stage error" "printf '%s' '$r' | grep -c 'stage errored' | grep -qx 1"
r="$(run_sc "$LIBDIR" "$(it '`cd nodir_zz && grep -n "x" aoe.gd` returns no matches.')")"
ok "R15 cd into a missing dir && grep (rc 1) is NOT an absence -> FAIL (old: PASS)" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it '`cd scripts && grep -n "no_such_symbol_zz" aoe.gd` returns no matches.')")"
ok "R15 CONTROL cd into an existing dir && grep, symbol absent -> PASS" "[ \"\$(res '$r')\" = PASS ]"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "no_such_symbol_zz" scripts/aoe.gd | grep -v "y"` returns no lines.')")"
ok "R15 CONTROL pipeline of two healthy greps, symbol absent -> PASS" "[ \"\$(res '$r')\" = PASS ]"
r="$(OVN_VERIFY_NEG_STAGES=off run_sc "$LIBDIR" "$(it '`grep -n "x" scripts/nodir_zz | grep -v "y"` returns no lines.')")"
ok "R15 kill switch OVN_VERIFY_NEG_STAGES=off restores the old reading (PASS)" "[ \"\$(res '$r')\" = PASS ]"
# R15 livelock: a grep on the file the item itself deletes
dl='- [ ] [T2] scripts/gone_by_item.gd — Delete scripts/gone_by_item.gd entirely. VERIFY: `grep -n "x" scripts/gone_by_item.gd` returns no matches. (cat:gd)'
r="$(run_sc "$LIBDIR" "$dl")"
ok "R15 delete item + grep on the (deleted) file, rc 2 -> PASS satisfied-absent (old: FAIL forever)" "[ \"\$(res '$r')\" = PASS ]"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "x" scripts/missing_file.gd` returns no matches.')")"
ok "R15 a NON-delete item with a missing grep target stays FAIL (conservative)" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" '- [ ] [T2] scripts/never_was.gd — Verify that no test calls A.b or references the removed function. VERIFY: `grep -n "x" scripts/never_was.gd` returns no matches. (cat:gd)')"
ok "R15 'references the removed function' on a path that never existed is NOT a delete item -> stays FAIL (xlite addons/gut/test_aoe*.gd)" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" '- [ ] [T2] scripts/gone_by_item.gd — Delete scripts/gone_by_item.gd entirely. VERIFY: `grep -n "x" scripts/gone_by_item.gd scripts/other_missing.gd` returns no matches. (cat:gd)')"
ok "R15 delete item but an operand the item never names is missing too -> stays FAIL" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" '- [ ] [T2] scripts/aoe.gd — Delete scripts/aoe.gd entirely. VERIFY: `grep -n "no_such_symbol_zz" scripts/aoe.gd` returns no matches. (cat:gd)')"
ok "R15 delete item whose file STILL exists, symbol absent -> PASS via the normal rc 1 path (unchanged)" "[ \"\$(res '$r')\" = PASS ]"
r="$(run_sc "$LIBDIR" "$(it '`grep -n "is_destructible_type" scripts/aoe.gd` returns matches.')")"
ok "CONTROL pos polarity: PASS" "[ \"\$(res '$r')\" = PASS ]"
r="$(run_sc "$LIBDIR" "$(it '`! grep -n "is_destructible_type" scripts/aoe.gd` fails with no such file.')")"
ok "CONTROL an already-negated command (R03 output) is not inverted twice: still present -> FAIL" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it '`bash -c "exit 127"` returns no output.')")"
ok "a runner/other tool never gets neg polarity (rc 127 stays UNRUNNABLE)" "[ \"\$(res '$r')\" = UNRUNNABLE ]"
r="$(OVN_VERIFY_POLARITY=off run_sc "$LIBDIR" "$(it '`grep -n "is_destructible_type" scripts/aoe.gd` returns no matches.')")"
ok "kill switch OVN_VERIFY_POLARITY=off restores the old reading (PASS)" "[ \"\$(res '$r')\" = PASS ]"
# the memo must not cross polarities: same command, two items, opposite narration, ONE call
printf '%s\n%s\n' "$(it '`grep -n "is_destructible_type" scripts/aoe.gd` returns no matches.')" "$(it '`grep -n "is_destructible_type" scripts/aoe.gd` returns matches.')" > "$tmp/prog2.md"
memo="$( cd "$tmp/work" && export HOME="$tmp/home" && PROG="$tmp/prog2.md"; SHADOW_LOG="$tmp/shadow2.log"; _REPO_LABEL=t; _VC_MEMO_ON=1; : > "$SHADOW_LOG"; . "$LIBDIR/lib_verify_clause.sh"; shadow_check 1; a="$_LAST_VERIFY_RESULT"; shadow_check 2; echo "$a $_LAST_VERIFY_RESULT" )"
ok "memo is keyed on polarity too: neg item FAIL, pos item PASS in one call" "[ '$memo' = 'FAIL PASS' ]"

echo "== X2: GUT clause normalisation"
G='godot --headless -s addons/gut/gut_cmdln.gd'
r="$(run_sc "$LIBDIR" "$(it "\`$G -gdir=tests/test_enemy_faction_map.gd -gexit -gselect=faction_for_returns_correct_string\`")")"
ok "-gdir=<existing file>.gd + -gselect=<function> -> PASS after normalisation (old: FAIL, GUT target missing)" "[ \"\$(res '$r')\" = PASS ]"
: > "$tmp/args.log"; SHIM_ARGS="$tmp/args.log" run_sc "$LIBDIR" "$(it "\`$G -gdir=tests/test_enemy_faction_map.gd -gexit\`")" >/dev/null
ok "the engine really got -gtest=res://tests/test_enemy_faction_map.gd and no -gdir" "grep -c -- '-gtest=res://tests/test_enemy_faction_map.gd' '$tmp/args.log' | grep -qx 1 && ! grep -q -- '-gdir=' '$tmp/args.log'"
r="$(run_sc "$LIBDIR" "$(it "\`$G -gdir=tests -gtest=test_aggro.gd -gexit\`")")"
ok "-gdir=tests -gtest=<bare>.gd resolves to res://tests/test_aggro.gd and PASSes" "[ \"\$(res '$r')\" = PASS ]"
: > "$tmp/args.log"; SHIM_ARGS="$tmp/args.log" run_sc "$LIBDIR" "$(it "\`$G -gdir=tests -gtest=test_aggro.gd -gexit\`")" >/dev/null
ok "... the engine got the resolved path (not the bare name that makes GUT run the whole suite)" "grep -c -- '-gtest=res://tests/test_aggro.gd' '$tmp/args.log' | grep -qx 1"
r="$(run_sc "$LIBDIR" "$(it "\`$G -gtest=test_no_such_file.gd -gexit\`")")"
ok "a bare -gtest name that resolves to nothing stays FAIL (target missing)" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it "\`$G -gdir=res://tests/test_not_created.gd -gexit\`")")"
ok "a -gdir file that does not exist is still 'GUT target missing' (never rewritten into a vacuous pass)" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it "\`$G -gtest=res://tests/test_enemy_faction_map.gd -gunit_test_name=no_such_function -gexit\`")")"
ok "'Nothing was run.' (rc 0) is a FAIL" "[ \"\$(res '$r')\" = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it "\`$G -gtest=res://tests/test_enemy_faction_map.gd -gunit_test_name=faction_for_returns_correct_string -gexit\`")")"
ok "CONTROL: a real -gunit_test_name PASSes" "[ \"\$(res '$r')\" = PASS ]"
r="$(OVN_GUT_CLAUSE_NORMALIZE=off run_sc "$LIBDIR" "$(it "\`$G -gdir=tests/test_enemy_faction_map.gd -gexit -gselect=faction_for_returns_correct_string\`")")"
ok "kill switch OVN_GUT_CLAUSE_NORMALIZE=off restores the old FAIL" "[ \"\$(res '$r')\" = FAIL ]"
r="$(OVN_GUT_CLAUSE_NORMALIZE=off run_sc "$LIBDIR" "$(it "\`$G -gtest=res://tests/test_enemy_faction_map.gd -gunit_test_name=no_such_function -gexit\`")")"
ok "kill switch also restores the old 'Nothing was run' PASS" "[ \"\$(res '$r')\" = PASS ]"
mkdir -p "$tmp/mut"; cp "$LIBDIR"/lib_*.sh "$LIBDIR"/ovn_*.py "$tmp/mut/" 2>/dev/null
sed -i.bak 's/^_verify_normalize_gut(){/_verify_normalize_gut(){ printf "%s" "$1"; return 0/' "$tmp/mut/lib_verify_clause.sh"
r="$(run_sc "$tmp/mut" "$(it "\`$G -gdir=tests/test_enemy_faction_map.gd -gexit -gselect=faction_for_returns_correct_string\`")")"
ok "MUTATION (normaliser neutered): the unrunnable shape FAILs again" "[ \"\$(res '$r')\" = FAIL ]"

echo; echo "$P passed, $F failed"
[ "$F" = 0 ]
