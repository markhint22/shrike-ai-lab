#!/usr/bin/env bash
# 2026-10-22 PKG-B: a lint/type tool the interpreter lacks (`python -m mypy` -> "No module named mypy"; `npx tsc` -> npm's "To get access to the TypeScript compiler" banner) exits 1.
# That is no verdict about the item: UNRUNNABLE rc 127 (tagged), never FAIL, and an UNRUNNABLE/TIMEOUT verdict never counts toward 'AUTO-SKIP after N credit refusals'.
# Mutation proof: OVN_VERIFY_MISSING_TOOL=off gives FAIL (the old behaviour); the gate refuses a tool-not-installed clause (it must not credit an unrun VERIFY).
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/.."
[ -f "$S/lib_verify_clause.sh" ] && [ -f "$S/lib_auto_credit.sh" ] || { echo "  SKIP: libs not found"; exit 0; }
P=0; F=0
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
W="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME" "$W/bin" "$W/repo/state"
export PYTHONDONTWRITEBYTECODE=1 OVN_VERIFY_SHADOW_LOG="$W/shadow.log" OVN_STATE_DIR="$W/repo/state"
printf '#!/bin/sh\necho "/x/bin/python: No module named mypy" >&2\nexit 1\n' > "$W/bin/python3"; chmod +x "$W/bin/python3"
printf '#!/bin/sh\necho "FAILED tests/test_a.py::test_a - ImportError"\necho "No module named mypy_plugins_helper"\nexit 1\n' > "$W/bin/python4"; chmod +x "$W/bin/python4"
printf '#!/bin/sh\necho "npm WARN exec"\necho "                 This is not the tsc command you are looking for"\necho "To get access to the TypeScript compiler, tsc, from the command line either:"\nexit 1\n' > "$W/bin/npx"; chmod +x "$W/bin/npx"
printf '#!/bin/sh\necho "No module named ruff" >&2\nexit 1\n' > "$W/bin/python5"; chmod +x "$W/bin/python5"
export PATH="$W/bin:$PATH"
. "$S/lib_verify_clause.sh"; . "$S/lib_auto_credit.sh"
PROG="$W/repo/OVERNIGHT_PROGRESS.md"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
cat > "$PROG" <<'EOP'
- [ ] [T2] a.py - typed. VERIFY: `python3 -m mypy app/billing.py`
- [ ] [T2] a.py - a test run that mentions another missing module. VERIFY: `python4 -m pytest tests/test_a.py`
- [ ] [T2] web.ts - typed web. VERIFY: `cd web && npx tsc --noEmit`
- [ ] [T2] a.py - a linter that is present in name only. VERIFY: `python5 -m ruff check app/`
- [ ] [T2] a.py - real failure of a non-tool clause. VERIFY: `python3 -c "assert 1 == 2"`
EOP
cd "$W/repo" || exit 1
chk(){ shadow_check "$1"; printf '%s' "$_LAST_VERIFY_RESULT"; }
eq "T1 python -m mypy without mypy is UNRUNNABLE" "$(chk 1)" UNRUNNABLE
: > "$OVN_VERIFY_SHADOW_LOG"; shadow_check 1; eq "T2 raw rc is kept (1), the shadow row is UNRUNNABLE rc=127 and tagged" "$_LAST_VERIFY_RC/$(grep -c 'result=UNRUNNABLE rc=127 .*tool-not-installed:mypy' "$OVN_VERIFY_SHADOW_LOG")" "1/1"
eq "T3 mutation: OVN_VERIFY_MISSING_TOOL=off restores FAIL" "$(OVN_VERIFY_MISSING_TOOL=off chk 1)" FAIL
mkdir -p web
eq "T4 npx tsc banner (typescript not installed) is UNRUNNABLE" "$(chk 3)" UNRUNNABLE
eq "T5 mutation: kill switch restores FAIL for the npx banner" "$(OVN_VERIFY_MISSING_TOOL=off chk 3)" FAIL
eq "T6 benign twin: output mentions mypy_plugins_helper, clause names no mypy: stays FAIL" "$(chk 2)" FAIL
eq "T7 ruff missing is UNRUNNABLE too" "$(chk 4)" UNRUNNABLE
eq "T8 benign twin: a plain failing clause stays FAIL" "$(chk 5)" FAIL
# ---- the gate (real call path): a missing tool is REFUSED (item left open) for EVERY caller label, never credited, never counted toward the park ----
_cnt(){ local n=0 f; for f in "$OVN_STATE_DIR"/credit_refused/*; do [ -f "$f" ] && n=$(sed -n 1p "$f"); done; printf '%s' "${n:-0}"; }
git init -q . 2>/dev/null
for lab in "scout ALREADY-DONE credit" "DONE-trailer credit" "bookkeeping"; do
  rm -rf "$OVN_STATE_DIR/credit_refused"
  OVN_VERIFY_GATE_MODE=enforce ovn_credit_verify_gate "$PROG" 1 "$W/tl.log" "$lab" >/dev/null; rc=$?
  eq "G1 [$lab] mypy-less clause: gate REFUSES (rc 1), item stays open" "$rc" 1
  eq "G2 [$lab] ... and the refusal is not counted toward the park" "$(_cnt)" 0
done
OVN_MISSING_TOOL_CREDIT=credit OVN_UNRUNNABLE_CREDIT_GATE=off OVN_VERIFY_GATE_MODE=enforce ovn_credit_verify_gate "$PROG" 1 "$W/tl.log" "DONE-trailer credit" >/dev/null; eq "G3 mutation: OVN_MISSING_TOOL_CREDIT=credit gives the old-after-PKG-B credit (rc 0)" "$?" 0
OVN_VERIFY_MISSING_TOOL=off OVN_VERIFY_GATE_MODE=enforce ovn_credit_verify_gate "$PROG" 1 "$W/tl.log" "DONE-trailer credit" >/dev/null; eq "G4 mutation: tool mapping off = pre-PKG-B FAIL, refused too (rc 1)" "$?" 1
rm -rf "$OVN_STATE_DIR/credit_refused"
OVN_VERIFY_GATE_MODE=enforce ovn_credit_verify_gate "$PROG" 5 "$W/tl.log" "scout ALREADY-DONE credit" >/dev/null; eq "G5 benign twin: genuine FAIL refused" "$?" 1
eq "G6 benign twin: genuine FAIL still counted toward the park" "$(_cnt)" 1
# ---- item 4: stage item-VERIFY decision for "already GREEN before any step" ----
if [ -f "$S/lib_stage_guards.sh" ]; then
  . "$S/lib_stage_guards.sh" 2>/dev/null
  eq "D1 already GREEN before and after: default is the old refusal (credit is opt-in: it loosens credit)" "$(stage_item_verify_decision 'PASS|' 'PASS|' | cut -d: -f1)" refuse
  eq "D2 OVN_STAGE_ITEM_VERIFY_ALREADY_GREEN=credit credits it as already-satisfied" "$(OVN_STAGE_ITEM_VERIFY_ALREADY_GREEN=credit stage_item_verify_decision 'PASS|' 'PASS|' | cut -d: -f1-2)" "OK:already-satisfied"
  eq "D3 benign twin: RED after the change is still refused" "$(stage_item_verify_decision 'FAIL|' 'FAIL|' | cut -d: -f1)" refuse
  eq "D4 benign twin: RED before, GREEN after is plain OK" "$(stage_item_verify_decision 'FAIL|' 'PASS|')" OK
fi
echo "test_verify_missing_tool_unrunnable: pass=$P fail=$F"
[ "$F" = 0 ]
