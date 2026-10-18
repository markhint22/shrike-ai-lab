#!/usr/bin/env bash
# 2026-10-18 shrike-monitor landing audit: `python -m pytest ...` run by a python WITHOUT pytest exits 1 ("No module named pytest").
# shadow_check read that as FAIL, so the stage item-VERIFY gate called correct python items "RED after the change" (5/5 rows on the box).
# It is INDETERMINATE (UNRUNNABLE), like `pytest: command not found`. Each "new logic" assertion FAILS with OVN_VERIFY_MISSING_PYTEST=off (the old behaviour; see M4).
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
[ -f "$S/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-17: fail-closed sandbox helpers (see lint_unsafe_rm.py)
W="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME" "$W/bin" "$W/repo"
export PYTHONDONTWRITEBYTECODE=1
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
# stub interpreters: nopytest mimics an interpreter with no pytest; failpytest mimics a real red test run
printf '#!/bin/sh\necho "/x/bin/python: No module named pytest" >&2\nexit 1\n' > "$W/bin/python";  chmod +x "$W/bin/python"
printf '#!/bin/sh\necho "FAILED tests/test_a.py::test_a - assert 1 == 2"\necho "No module named pytest_asyncio_plugin_not_the_issue"\nexit 1\n' > "$W/bin/python3"; chmod +x "$W/bin/python3"
export PATH="$W/bin:$PATH"
. "$S/lib_verify_clause.sh"
PROG="$W/prog.md"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
cat > "$PROG" <<'EOP'
- [ ] [T2] a.py - interpreter without pytest. VERIFY: `python -m pytest tests/test_a.py -v`
- [ ] [T2] a.py - a genuine red test run (other module named pytest_*). VERIFY: `python3 -m pytest tests/test_a.py -v`
- [ ] [T2] a.py - not pytest at all. VERIFY: `python3 -c "assert 1 == 2"`
EOP
cd "$W/repo" || exit 1
chk(){ shadow_check "$1"; printf '%s' "$_LAST_VERIFY_RESULT"; }
eq "M1 python -m pytest with an interpreter lacking pytest is UNRUNNABLE, not FAIL" "$(chk 1)" UNRUNNABLE
shadow_check 1; eq "M2 the raw rc is kept for the record" "$_LAST_VERIFY_RC" 1
eq "M3 benign twin: a genuine red run whose output merely mentions another module stays FAIL" "$(chk 2)" FAIL
eq "M4 kill switch OVN_VERIFY_MISSING_PYTEST=off restores FAIL" "$(OVN_VERIFY_MISSING_PYTEST=off chk 1)" FAIL
eq "M5 benign twin: a non-pytest clause is untouched" "$(chk 3)" FAIL
[ -f "$S/lib_stage_guards.sh" ] && . "$S/lib_stage_guards.sh" 2>/dev/null
if declare -F stage_item_verify_decision >/dev/null; then
  eq "M6 the stage decision no longer refuses on UNRUNNABLE (no evidence -> credit path decides)" "$(stage_item_verify_decision 'FAIL|' 'UNRUNNABLE|x')" OK
  eq "M7 ... while a real FAIL after the change is still refused" "$(stage_item_verify_decision 'FAIL|' 'FAIL|x' | cut -d: -f1)" refuse
fi
echo "test_verify_missing_pytest_unrunnable: pass=$P fail=$F"
[ "$F" = 0 ]
