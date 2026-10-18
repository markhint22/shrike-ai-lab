#!/usr/bin/env bash
# 2026-10-16 (overnight review, xlite): (A) a bare `gut ...` VERIFY command word is rewritten to the GUT entry point (no `gut` binary on the box: rc 127 on every run);
# (B) an UNRUNNABLE VERIFY is not a crediting verdict for the scout ALREADY-DONE credit: shadow (default) logs 'would be REFUSED' and credits as before, enforce refuses.
# Every NEW assertion fails on the pre-fix code (no _verify_gut_alias, no UNRUNNABLE branch). The benign twins are labelled.
set -o pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
[ -f "$S/lib_auto_credit.sh" ] || { echo "  SKIP: lib_auto_credit.sh not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME"
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
ALERTS="$W/alerts.log"; : > "$ALERTS"
emit_alert(){ echo "$1 | $2 | $3" >> "$ALERTS"; }
. "$S/lib_item_select.sh"
. "$S/lib_verify_clause.sh"
. "$S/lib_auto_credit.sh"

echo "== A: bare gut alias"
eq "A1 bare gut with -gdir/-gselect/-gexit becomes the GUT entry point" "$(_verify_gut_alias 'gut -gdir=tests -gselect=test_roster_load_hardening.gd -gexit -gquiet')" "godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gselect=test_roster_load_hardening.gd -gexit -gquiet"
eq "A2 gut after a cd && keeps the cd" "$(_verify_gut_alias 'cd /x && gut -gdir=tests -gexit')" "cd /x && godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gexit"
eq "A3 gut after ; is rewritten (benign twin: a second command in a chain)" "$(_verify_gut_alias 'pytest -q; gut -gexit')" "pytest -q; godot --headless -s addons/gut/gut_cmdln.gd -gexit"
eq "A4 gut_cmdln already present is untouched (benign twin)" "$(_verify_gut_alias 'godot --headless -s addons/gut/gut_cmdln.gd -gexit')" "godot --headless -s addons/gut/gut_cmdln.gd -gexit"
eq "A5 cd gut is untouched (benign twin: a directory named gut)" "$(_verify_gut_alias 'cd gut && ls')" "cd gut && ls"
eq "A6 grep gut is untouched (benign twin)" "$(_verify_gut_alias 'grep gut file.md')" "grep gut file.md"
eq "A7 OVN_GUT_ALIAS=off disables the rewrite" "$(OVN_GUT_ALIAS=off _verify_gut_alias 'gut -gexit')" "gut -gexit"

echo "== B: UNRUNNABLE verdict and the scout ALREADY-DONE credit"
# stub shadow_check: the verdict is whatever STUB_RESULT says
shadow_check(){ _LAST_VERIFY_RESULT="$STUB_RESULT"; _LAST_VERIFY_WHY="rc=127 gut: command not found"; return 0; }
PROG="$W/prog.md"; printf -- '- [ ] [T1] tests/x.gd — thing VERIFY: gut -gexit. (cat:test)\n' > "$PROG"
TL="$W/task.log"; : > "$TL"
STUB_RESULT=UNRUNNABLE
OVN_UNRUNNABLE_CREDIT_GATE=shadow ovn_credit_verify_gate "$PROG" 1 "$TL" "scout ALREADY-DONE credit"; rc_sh=$?
eq "B1 shadow (default): UNRUNNABLE scout credit is still credited (rc 0)" "$rc_sh" "0"
ok "B1 shadow logs 'would be REFUSED'" "grep -q 'would be REFUSED (VERIFY UNRUNNABLE' '$TL'"
: > "$TL"
OVN_UNRUNNABLE_CREDIT_GATE=enforce ovn_credit_verify_gate "$PROG" 1 "$TL" "scout ALREADY-DONE credit"; rc_en=$?
eq "B2 enforce: UNRUNNABLE scout credit is REFUSED (rc 1)" "$rc_en" "1"
ok "B2 enforce logs REFUSED" "grep -q 'REFUSED at line 1 - VERIFY UNRUNNABLE' '$TL'"
: > "$TL"
OVN_UNRUNNABLE_CREDIT_GATE=enforce ovn_credit_verify_gate "$PROG" 1 "$TL" "DONE-trailer credit"; rc_dt=$?
eq "B3 benign twin: the DONE-trailer credit on UNRUNNABLE is unchanged (rc 0)" "$rc_dt" "0"
OVN_UNRUNNABLE_CREDIT_GATE=off ovn_credit_verify_gate "$PROG" 1 "$TL" "scout ALREADY-DONE credit"; rc_off=$?
eq "B4 off: the old behaviour (rc 0)" "$rc_off" "0"
STUB_RESULT=TIMEOUT
OVN_UNRUNNABLE_CREDIT_GATE=enforce ovn_credit_verify_gate "$PROG" 1 "$TL" "scout ALREADY-DONE credit"; rc_to=$?
eq "B5 benign twin: TIMEOUT is never refused by this gate (rc 0)" "$rc_to" "0"
STUB_RESULT=PASS
OVN_UNRUNNABLE_CREDIT_GATE=enforce ovn_credit_verify_gate "$PROG" 1 "$TL" "scout ALREADY-DONE credit"; rc_ps=$?
eq "B6 benign twin: PASS is credited (rc 0)" "$rc_ps" "0"

echo "== C: the gut alias is SHADOW by default (verdict unchanged unless OVN_GUT_ALIAS=on, 2026-10-16 review)"
# runs the REAL shadow_check (a subshell re-sources the lib, replacing the section-B stub); a fake godot on PATH records whether the aliased form ran
CB="$W/cbin"; mkdir -p "$CB"; CCALLS="$W/godot.calls"
printf '#!/bin/sh\necho ran >> "%s"\nexit 0\n' "$CCALLS" > "$CB/godot"; chmod +x "$CB/godot"
CPROG="$W/cprog.md"; printf -- '- [ ] [T1] tests/x.gd — thing VERIFY: `gut -gexit`. (cat:test; multifile:no)\n' > "$CPROG"
CLOG="$W/cshadow.log"
crun(){  # $1 = OVN_GUT_ALIAS value or "unset"; prints "RESULT|CALLS"
  : > "$CLOG"; rm -f "$CCALLS"
  (
    cd "$W"; PATH="$CB:$PATH"
    . "$S/lib_verify_clause.sh"
    PROG="$CPROG"; SHADOW_LOG="$CLOG"; _REPO_LABEL=t; VERIFY_TIMEOUT_SECS=20
    _VC_MEMO=""; _VC_MEMO_ON=0
    if [ "$1" = unset ]; then unset OVN_GUT_ALIAS; else export OVN_GUT_ALIAS="$1"; fi
    shadow_check 1 >/dev/null 2>&1
    printf '%s|%s' "$_LAST_VERIFY_RESULT" "$( [ -f "$CCALLS" ] && echo ran || echo none )"
  )
}
RES_DEF="$(crun unset)"
eq "C1 default (OVN_GUT_ALIAS unset): the verdict is unchanged (UNRUNNABLE for the bare gut, the aliased godot is not the verdict)" "${RES_DEF%%|*}" "UNRUNNABLE"
ok "C2 default: the aliased form is run and logged to the shadow log as a would=PASS note" "grep -q 'note=gut-alias mode=shadow would=PASS' '$CLOG'"
ok "C3 default: the shadow note carries no result= token (readers count result= rows)" "! grep -q 'note=gut-alias.*result=' '$CLOG'"
RES_ON="$(crun on)"
eq "C4 OVN_GUT_ALIAS=on: the rewrite decides the verdict (PASS)" "${RES_ON%%|*}" "PASS"
RES_OFF="$(crun off)"
eq "C5 OVN_GUT_ALIAS=off: the verdict is unchanged and nothing is aliased" "${RES_OFF%%|*}" "UNRUNNABLE"
ok "C6 OVN_GUT_ALIAS=off: no gut-alias note row" "! grep -q 'gut-alias' '$CLOG'"

echo "== RESULT: $P passed, $F failed"
[ "$F" = 0 ]
