#!/usr/bin/env bash
# 2026-10-18 (iptv overnight audit): `PROBE && echo "FAIL" || echo "PASS"` always exits 0 - the echo decides the exit status, not the probe.
# iptv `Remove the definitions of check_session_limit/... from streams.py` carried exactly that clause: PASS before AND after (item_verify refuse:already GREEN), a staged repair round
# re-added the deleted functions, the item was ticked [x] with nothing deleted. lib_verify_clause.sh now re-reads such a clause by the PROBE's exit status
# (OVN_VERIFY_ECHO_VERDICT: shadow (default, log only) | on | off). Real shadow_check, real grep/test, no mocks; mutation control proves the test bites.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
LIBDIR="${OVN_LIB_DIR:-$HERE/..}"
[ -f "$LIBDIR/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/work/app"
printf 'def check_session_limit():\n    pass\n' > "$tmp/work/app/streams.py"
printf 'x = 1\n' > "$tmp/work/app/clean.py"

run_sc(){  # $1 = lib dir, $2 = item line, $3 = OVN_VERIFY_ECHO_VERDICT value -> RESULT
  printf '%s\n' "$2" > "$tmp/prog.md"
  ( cd "$tmp/work" || exit 9
    safe_set_sandbox_home "$tmp" || exit 1
    export OVN_VERIFY_ECHO_VERDICT="$3"
    PROG="$tmp/prog.md"; SHADOW_LOG="$tmp/shadow.log"; _REPO_LABEL=t; _VC_MEMO_ON=0; : > "$SHADOW_LOG"
    # shellcheck disable=SC1091
    . "$1/lib_verify_clause.sh"
    shadow_check 1
    printf '%s' "$_LAST_VERIFY_RESULT" )
}
it(){ printf -- '- [ ] [T3] app/streams.py — Remove check_session_limit. VERIFY: `%s`. (cat:python; multifile:no)' "$1"; }
NEG_PRESENT='grep -E "def check_session_limit|def other" app/streams.py && echo "FAIL" || echo "PASS"'
NEG_ABSENT='grep -E "def zz_missing|def other" app/streams.py && echo "FAIL" || echo "PASS"'
POS_PRESENT='grep -q "def check_session_limit" app/streams.py && echo PASS || echo FAIL'
POS_ABSENT='grep -q "def zz_missing" app/streams.py && echo PASS || echo FAIL'

echo "== helper: _verify_echo_verdict"
h(){ ( . "$LIBDIR/lib_verify_clause.sh"; _verify_echo_verdict "$1" ); }
ok "echo FAIL on success / echo PASS otherwise => neg + the bare probe" "[ \"\$(h '$NEG_PRESENT')\" = 'neg|grep -E \"def check_session_limit|def other\" app/streams.py' ]"
ok "echo PASS on success / echo FAIL otherwise => pos" "[ \"\$(h '$POS_PRESENT')\" = 'pos|grep -q \"def check_session_limit\" app/streams.py' ]"
ok "'test -f x || echo FAIL' => pos (the echo exits 0 on a failing probe)" "[ \"\$(h 'test -f x || echo FAIL')\" = 'pos|test -f x' ]"
ok "a plain pytest clause is untouched" "[ -z \"\$(h 'python -m pytest tests/t.py -q')\" ]"
ok "'test ! -f x && echo PASS' (rc follows the probe) is untouched" "[ -z \"\$(h 'test ! -f x && echo PASS')\" ]"
ok "a probe with ; or && inside is not re-read" "[ -z \"\$(h 'true; ls && echo FAIL || echo PASS')\" ]"

echo "== shadow (default): verdicts unchanged, would-be reading logged"
r="$(run_sc "$LIBDIR" "$(it "$NEG_PRESENT")" shadow)"
ok "shadow: symbol STILL present => PASS (old behaviour, the live false credit)" "[ '$r' = PASS ]"
ok "shadow: the would-be neg reading is logged" "grep -c 'note=echo-verdict mode=shadow would=neg' '$tmp/shadow.log' | grep -qx 1"
r="$(run_sc "$LIBDIR" "$(it "$NEG_PRESENT")" off)"
ok "off: no note logged, PASS as before" "[ '$r' = PASS ] && ! grep -q 'echo-verdict' '$tmp/shadow.log'"

echo "== on: the probe decides"
r="$(run_sc "$LIBDIR" "$(it "$NEG_PRESENT")" on)"
ok "on: echo-FAIL clause, symbol STILL present => FAIL" "[ '$r' = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it "$NEG_ABSENT")" on)"
ok "on: echo-FAIL clause, symbol absent => PASS" "[ '$r' = PASS ]"
r="$(run_sc "$LIBDIR" "$(it "$POS_PRESENT")" on)"
ok "on: echo-PASS clause, symbol present => PASS" "[ '$r' = PASS ]"
r="$(run_sc "$LIBDIR" "$(it "$POS_ABSENT")" on)"
ok "on: echo-PASS clause, symbol absent => FAIL (old code: PASS)" "[ '$r' = FAIL ]"
r="$(run_sc "$LIBDIR" "$(it 'grep -E "def x" app/missing_file.py && echo "FAIL" || echo "PASS"')" on)"
ok "on: grep error rc 2 (file missing) is not an absence => FAIL" "[ '$r' = FAIL ]"

echo "== MUTATION: without the normalisation the present-symbol clause reads PASS in 'on' mode"
mkdir -p "$tmp/mut"; cp "$LIBDIR/lib_verify_clause.sh" "$tmp/mut/lib_verify_clause.sh"
python3 - "$tmp/mut/lib_verify_clause.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '      if [ "$_evmode" = on ]; then\n        vcmd="$_evp"'
assert s.count(a) == 1
open(p, "w").write(s.replace(a, '      if [ "$_evmode" = never ]; then\n        vcmd="$_evp"'))
PY
for f in "$LIBDIR"/*.py "$LIBDIR"/ovn_verify_safe.py; do [ -f "$f" ] && cp "$f" "$tmp/mut/" 2>/dev/null; done
r="$(run_sc "$tmp/mut" "$(it "$NEG_PRESENT")" on)"
ok "MUTANT: normalisation disabled => PASS (the false credit returns), so the 'on' FAIL assertion above bites" "[ '$r' = PASS ]"

echo "$P passed, $F failed"; [ "$F" -eq 0 ]
