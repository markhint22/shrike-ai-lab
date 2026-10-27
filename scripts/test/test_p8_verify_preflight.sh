#!/usr/bin/env bash
# P8 (2026-10-26): VERIFY / item pre-flight + observability (deterministic code only; every enforcement default is shadow/off).
#   P  test_p8_verify_preflight.py: verify lint A1 (async-blind ast.FunctionDef) + H1 (hyphenated import) + OVN_VERIFY_ASYNC_LINT modes, scout-guard abs-path rejection, digest line-hash split, outcome_acct copy
#   L  ovn_item_line_hash (sibling items of one feature differ, checkbox does not matter, ovn_item_hash for them is UNCHANGED) + the REAL record_outcome writes item_line_hash (and a copy without it does not)
#   R  stage_item_verify_run: pytest rc 4/5 -> note=rc45-spec-problem in the item-verify shadow log (default shadow, verdict stays FAIL), SPEC_PROBLEM with OVN_STAGE_IV_RC45=on, rc 1 stays FAIL
#   M  mutants: each reverts ONE hunk in a scratch copy and the matching suite must FAIL
# Works on the Mac and on the box's queue-only mirror (GNU sed): no sed -i, no Mac-only script.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$(cd "$HERE/.." && pwd)"; Q="$(cd "$S/.." && pwd)"
PY="$(command -v python3.12 || command -v python3)"
P=0; F=0
t(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $n"; else F=$((F+1)); echo "  FAIL $n"; fi; }
W="$(safe_mktemp_dir p8)" || exit 1; trap 'safe_rm_rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME" "$W/tmp"
export PYTHONDONTWRITEBYTECODE=1
unset OVN_VERIFY_ASYNC_LINT OVN_VERIFY_LINT OVN_VERIFY_LINT_P5 OVN_DIGEST_LINE_SPLIT OVN_STAGE_IV_RC45 NTFY_SERVER NTFY_TOPIC

echo "== P: python suite"
"$PY" "$HERE/test_p8_verify_preflight.py" > "$W/p.out" 2>&1; prc=$?
grep -vE '^  PASS ' "$W/p.out"
t "P: test_p8_verify_preflight.py exits 0" test "$prc" -eq 0

echo "== L: item_line_hash"
. "$S/lib_item_select.sh" 2>/dev/null
A='- [ ] [T2] [feat:iptv-20261024-x] app/a.py - add foo. VERIFY: `pytest tests/test_a.py` (cat:python)'
B='- [ ] [T2] [feat:iptv-20261024-x] app/b.py - add bar. VERIFY: `pytest tests/test_b.py` (cat:python)'
t "L1 sibling items of one feature share ovn_item_hash (UNCHANGED: state/item_fails keys depend on it)" test "$(ovn_item_hash "$A")" = "$(ovn_item_hash "$B")"
t "L2 ... but have different ovn_item_line_hash" test "$(ovn_item_line_hash "$A")" != "$(ovn_item_line_hash "$B")"
t "L3 the line hash ignores the checkbox state" test "$(ovn_item_line_hash "$A")" = "$(ovn_item_line_hash "${A/- \[ \] /- [x] }")"
t "L4 line hash is 32 hex" bash -c '[[ "$1" =~ ^[0-9a-f]{32}$ ]]' _ "$(ovn_item_line_hash "$A")"
echo "== L: the REAL record_outcome"
RO="$Q/run_overnight.sh"
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$RO")"
t "L5 record_outcome extracted" test -n "$FN_SRC"
rec(){  # $1 = function source, $2 = item line -> prints the outcome row's "item_hash item_line_hash"
  ( SCRIPT_DIR="$Q"; STATE_DIR="$W/h/state.$RANDOM"; mkdir -p "$STATE_DIR"
    . "$S/lib_item_select.sh" 2>/dev/null
    eval "$1"
    local rd="$W/h/repo.$RANDOM"; mkdir -p "$rd"
    printf '# progress\n%s\n' "$2" > "$rd/OVERNIGHT_PROGRESS.md"
    OVN_OUTCOME_ATTRIB=legacy record_outcome "t-1" taa "reverted(red-tests)" "" aider_fix 1 /dev/null 61 "$rd" >/dev/null 2>&1
    "$PY" -c "import json,sys;r=json.loads(open(sys.argv[1]).readline());print(r.get('item_hash',''),r.get('item_line_hash','-'))" "$STATE_DIR/outcomes.jsonl" )
}
RA="$(rec "$FN_SRC" "$A")"; RB="$(rec "$FN_SRC" "$B")"
echo "    A: $RA"; echo "    B: $RB"
t "L6 sibling rows carry the SAME item_hash" test "${RA%% *}" = "${RB%% *}"
t "L7 ... and DIFFERENT item_line_hash (a real 32-hex value)" bash -c '[ "$1" != "$2" ] && [ "${#1}" -gt 40 ] && [[ "${1#* }" =~ ^[0-9a-f]{32}$ ]]' _ "$RA" "$RB"
t "L8 the row's item_line_hash equals ovn_item_line_hash of the line" test "${RA#* }" = "$(ovn_item_line_hash "${A#- \[ \] }")"
NOLH="$(printf '%s\n' "$FN_SRC" | sed 's/_item_line_hash="$(ovn_item_line_hash "$_text")"/_item_line_hash=""/')"
t "L9 mutant (record_outcome stops computing it): the field is absent" test "$(rec "$NOLH" "$A" | cut -d' ' -f2)" = "-"
t "L10 record_outcome / stage runner still parse" bash -c 'bash -n "$1" && bash -n "$2"' _ "$RO" "$Q/ovn_stage_runner.sh"

echo "== R: stage_item_verify rc 4/5"
. "$S/lib_stage_guards.sh" 2>/dev/null
mkdir -p "$W/bin" "$W/wt"
mkstub(){ printf '#!/bin/sh\necho "%s"\nexit %s\n' "$2" "$3" > "$W/bin/$1"; chmod +x "$W/bin/$1"; }
runiv(){  # $1 = exit code of the stub python3, $2 = item; extra env via the caller; prints the stage_item_verify_run output
  mkstub python3 "collected 0 items / no tests ran" "$1"
  ( export PATH="$W/bin:$PATH" OVN_STAGE_REPO=r OVN_STAGE_REPO_DIR="$W/none" OVN_STAGE_IV_SHADOW_LOG="$W/iv.log"; : > "$W/iv.log"; stage_item_verify_run "$W/wt" "$2" )
}
ITEM='[T2] tests/test_new.py - add a test. VERIFY: `python3 -m pytest tests/test_new.py -q` (cat:python)'
o5="$(runiv 5 "$ITEM")"
t "R1 default (shadow): pytest rc 5 verdict is unchanged (FAIL)" test "${o5%%|*}" = FAIL
t "R2 ... and the shadow log records note=rc45-spec-problem would=SPEC_PROBLEM rc=5" grep -q 'note=rc45-spec-problem mode=shadow would=SPEC_PROBLEM rc=5' "$W/iv.log"
o4="$(runiv 4 "$ITEM")"
t "R3 rc 4 (usage / node id does not resolve) is recorded too" grep -q 'would=SPEC_PROBLEM rc=4' "$W/iv.log"
o1="$(runiv 1 "$ITEM")"
t "R4 rc 1 (a real red test) is FAIL and NOT classified as a spec problem" bash -c '[ "${1%%|*}" = FAIL ] && ! grep -q rc45 "$2"' _ "$o1" "$W/iv.log"
t "R5 a non-pytest rc 5 is not touched" bash -c 'o="$2"; [ "${o%%|*}" = FAIL ] && ! grep -q rc45 "$1"' _ "$W/iv.log" "$(runiv 5 '[T2] a.py - x. VERIFY: `python3 check.py` (cat:python)')"
oon="$(OVN_STAGE_IV_RC45=on runiv 5 "$ITEM")"
t "R6 OVN_STAGE_IV_RC45=on: SPEC_PROBLEM verdict" test "${oon%%|*}" = SPEC_PROBLEM
t "R7 on: rc 1 is still FAIL" test "$(OVN_STAGE_IV_RC45=on runiv 1 "$ITEM" | cut -d'|' -f1)" = FAIL
ooff="$(OVN_STAGE_IV_RC45=off runiv 5 "$ITEM")"
t "R8 off: no log line, verdict FAIL" bash -c '[ "${1%%|*}" = FAIL ] && ! grep -q rc45 "$2"' _ "$ooff" "$W/iv.log"
t "R9 decision: pre SPEC_PROBLEM (red expected of a create-the-test item) + post PASS -> OK" test "$(stage_item_verify_decision 'SPEC_PROBLEM|x' 'PASS|')" = OK
t "R10 decision: post SPEC_PROBLEM is refused with a DISTINCT item-vs-spec reason" bash -c 'd="$1"; [ "${d%%:*}" = refuse ] && case "$d" in *"item-vs-spec"*) true;; *) false;; esac' _ "$(stage_item_verify_decision 'FAIL|' 'SPEC_PROBLEM|x')"
dfail="$(stage_item_verify_decision 'FAIL|' 'FAIL|x')"; dpp="$(stage_item_verify_decision 'FAIL|' 'PASS|')"
t "R11 decision: post FAIL still refused with the old RED reason; FAIL->PASS unchanged" bash -c 'case "$1" in "refuse:the item'"'"'s own VERIFY is RED after the change") [ "$2" = OK ];; *) false;; esac' _ "$dfail" "$dpp"
t "R12 the stage runner journals SPEC_PROBLEM through the same item_verify block" grep -q 'PASS|FAIL|SPEC_PROBLEM)' "$Q/ovn_stage_runner.sh"

echo "== M: mutants (one reverted hunk each; the suite must FAIL)"
mut(){  # $1=src $2=dst $3=old $4=new : copy with EXACTLY one occurrence replaced
  "$PY" - "$1" "$2" "$3" "$4" <<'EOF'
import sys
s = open(sys.argv[1]).read()
if s.count(sys.argv[3]) != 1:
    sys.stderr.write("mutation anchor not unique: %r (%d)\n" % (sys.argv[3][:50], s.count(sys.argv[3]))); sys.exit(3)
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4]))
EOF
}
MD="$W/mut"; mkdir -p "$MD"
mk_sd(){ rm -rf "$MD/$1"; mkdir -p "$MD/$1/scripts"; cp "$S"/ovn_verify_shape_lint.py "$S"/ovn_daily_fail_digest.py "$S"/ovn_outcome_acct.py "$MD/$1/scripts/"; cp "$Q/ovn_park_unworkable.py" "$MD/$1/"; }
msuite(){ P8_SD="$MD/$1/scripts" P8_Q="$MD/$1" "$PY" "$HERE/test_p8_verify_preflight.py" >/dev/null 2>&1; }
caught(){ # $1 = label, $2 = mutant dir name: the python suite must FAIL against it
  if msuite "$2"; then F=$((F+1)); echo "  FAIL $1 (suite still passes against the mutant)"; else P=$((P+1)); echo "  ok   $1"; fi
}
SL="$S/ovn_verify_shape_lint.py"
mk_sd m1; mut "$SL" "$MD/m1/scripts/ovn_verify_shape_lint.py" '_RULES = _RULES + (_rule_async_ast, _rule_hyphen_import)' '_RULES = _RULES + (_rule_hyphen_import,)' && caught "M1 mutant (A1 rule not registered)" m1
mk_sd m2; mut "$SL" "$MD/m2/scripts/ovn_verify_shape_lint.py" '_RULES = _RULES + (_rule_async_ast, _rule_hyphen_import)' '_RULES = _RULES + (_rule_async_ast,)' && caught "M2 mutant (H1 rule not registered)" m2
mk_sd m3; mut "$SL" "$MD/m3/scripts/ovn_verify_shape_lint.py" 'or "AsyncFunctionDef" in clause or not _PY_C.search(clause):' 'or not _PY_C.search(clause):' && caught "M3 mutant (A1 ignores an AsyncFunctionDef-aware clause)" m3
mk_sd m4; mut "$SL" "$MD/m4/scripts/ovn_verify_shape_lint.py" '(P8_CODES if p8_mode() != "enforce" else frozenset())' 'frozenset()' && caught "M4 mutant (P8 shapes enforced under OVN_VERIFY_LINT=enforce without their own switch)" m4
mk_sd m5; mut "$SL" "$MD/m5/scripts/ovn_verify_shape_lint.py" '    if p8_mode() == "off":
        findings = [f for f in findings if f["code"] not in P8_CODES]
' '' && caught "M5 mutant (OVN_VERIFY_ASYNC_LINT=off does not switch the shapes off)" m5
mk_sd m6; mut "$Q/ovn_park_unworkable.py" "$MD/m6/ovn_park_unworkable.py" 'if full != r and full.startswith(r + os.sep):' 'if True:' && caught "M6 mutant (scout guard accepts paths outside the repo)" m6
mk_sd m7; mut "$S/ovn_daily_fail_digest.py" "$MD/m7/scripts/ovn_daily_fail_digest.py" '            k = "%s #%s" % (k, lh[:8])' '            pass' && caught "M7 mutant (digest ignores item_line_hash)" m7
mk_sd m8; mut "$S/ovn_outcome_acct.py" "$MD/m8/scripts/ovn_outcome_acct.py" '**({"item_line_hash": r["item_line_hash"]} if r.get("item_line_hash") else {}),' '' && caught "M8 mutant (landed-late rows drop item_line_hash)" m8
mk_sd m10; mut "$SL" "$MD/m10/scripts/ovn_verify_shape_lint.py" 'm = _hyphen_import_stmt(st[1])' 'm = (lambda mm: (mm.group(1), mm.group(2)) if mm else None)(re.search(r"\\b(?:from|import)\\s+" + _HY_RE, st[1]))' && caught "M10 mutant (H1 matches prose inside a string again)" m10
mk_sd m11; mut "$SL" "$MD/m11/scripts/ovn_verify_shape_lint.py" '("ast.FunctionDef" not in clause and not _FD_NAME.search(clause))' '("ast.FunctionDef" not in clause)' && caught "M11 mutant (A1 ignores the by-name FunctionDef spelling)" m11
# R mutant: rc 4/5 reclassification not wired -> R2 must fail
mut "$S/lib_stage_guards.sh" "$MD/lsg.sh" '[ "${_LAST_VERIFY_RC:-}" = 4 ] || [ "${_LAST_VERIFY_RC:-}" = 5 ]' '[ "${_LAST_VERIFY_RC:-}" = 99 ]' && {
  ( . "$MD/lsg.sh" 2>/dev/null; mkstub python3 "no tests ran" 5
    export PATH="$W/bin:$PATH" OVN_STAGE_REPO=r OVN_STAGE_REPO_DIR="$W/none" OVN_STAGE_IV_SHADOW_LOG="$W/iv2.log"; : > "$W/iv2.log"; stage_item_verify_run "$W/wt" "$ITEM" >/dev/null )
  t "M9 mutant (rc 4/5 not recognised): shadow log has no rc45 note" bash -c '! grep -q rc45 "$1"' _ "$W/iv2.log"; }

echo "test_p8_verify_preflight: pass=$P fail=$F"
[ "$F" = 0 ]
