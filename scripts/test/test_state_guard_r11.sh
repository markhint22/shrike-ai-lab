#!/usr/bin/env bash
# 2026-10-11 (r11 acct, platform P9b): tests must not write into the LIVE state dir. Live defect: test_bash_helpers.sh left OVN_VERIFY_SHADOW_LOG unset and ran the credit script against
# $HOME/overnight-queue/scripts, so each 3-hourly run_all.sh appended `repo=tmp.XXXX line=4 ...` rows to the live state/verify_gate_shadow.log (387 rows by 10-11, inflating shadow counts).
# Sections: A the guard (state_guard.sh) unit, B the mechanism replayed in a sandbox HOME (the credit script's default log IS the live path), C test_bash_helpers.sh is clean under the
# guard and its pre-fix shape is caught, D MUTATION controls. Everything runs in a throwaway HOME; the real ~/overnight-queue is never read or written.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
G="$HERE/state_guard.sh"
unset OVN_STATE_GUARD OVN_GUARD_LIVE_REPOS OVN_GUARD_LIVE_DIR   # hermetic: a caller that turned the guard off (or pointed it elsewhere) must not change what this test asserts
[ -f "$G" ] || { echo "  FAIL: state_guard.sh missing"; exit 1; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo "== A: state_guard.sh"
LIVE="$tmp/live"; mkdir -p "$LIVE/state" "$LIVE/repos/iptv_apps" "$LIVE/repos/xlite"
LOG="$LIVE/state/verify_gate_shadow.log"
printf '2026-10-10T01:00:00Z repo=iptv_apps line=3 result=PASS cmd=pytest\n' > "$LOG"
export OVN_GUARD_LIVE_DIR="$LIVE"
# shellcheck disable=SC1090
. "$G"
guard(){ ( . "$G"; ovn_state_guard_begin; eval "$1"; ovn_state_guard_end ) 2>&1; }   # prints guard output; rc = guard rc
ok "A1 nothing written => rc 0" "guard ':'"
ok "A2 a REAL fleet repo row (the cron/runner writing legitimately) is ignored => rc 0" "guard \"echo '2026-10-11T01:00:00Z repo=xlite line=9 result=FAIL' >> '$LOG'\""
ok "A3 a foreign row (repo=tmp.XXXX, the mktemp label) => rc 1" "! guard \"echo '2026-10-11T11:00:01Z repo=tmp.VdAbPPHC3q line=4 result=NO_VERIFY_CLAUSE' >> '$LOG'\""
OUT="$(guard "echo '2026-10-11T11:00:02Z repo=tmp.Zzz line=4 path_gate=OK target=app/foo.py' >> '$LOG'" )"
ok "A4 the failure names the live log, the fix, and shows the row" "case \"\$OUT\" in *'STATE-GUARD FAIL'*'verify_gate_shadow.log'*'OVN_VERIFY_SHADOW_LOG'*'repo=tmp.Zzz'*) true;; *) false;; esac"
ok "A5 a row with NO repo= field is foreign too" "! guard \"echo 'garbage row' >> '$LOG'\""
ok "A6 mixed: one real + one foreign row => rc 1, and only the foreign one is shown" "OUT2=\"\$(guard \"printf '%s\\n' 'x repo=iptv_apps line=1' 'y repo=tmp.Q line=2' >> '$LOG'\")\"; case \"\$OUT2\" in *repo=tmp.Q*) case \"\$OUT2\" in *repo=iptv_apps*) false;; *) true;; esac;; *) false;; esac"
rm -f "$LOG"
ok "A7 the log did not exist and a foreign row creates it => rc 1" "! guard \"echo 'z repo=tmp.NEW line=1' >> '$LOG'\""
rm -f "$LOG"
ok "A8 OVN_STATE_GUARD=off => rc 0 even for a foreign row" "OVN_STATE_GUARD=off guard \"echo 'z repo=tmp.NEW line=1' >> '$LOG'\""
ok "A9 end without begin => rc 0 (never started)" "( . '$G'; ovn_state_guard_end )"
ok "A10 the guard consumes what it reported: a second end() after a failure is clean" "( . '$G'; ovn_state_guard_begin; echo 'z repo=tmp.AGAIN line=1' >> '$LOG'; ovn_state_guard_end 2>/dev/null; ovn_state_guard_end )"
ok "A11 ovn_state_guard_run: a polluting test fails (rc 1) even though the test itself returned 0, and is named" "( . '$G'; ovn_state_guard_run bash -c \"echo 'z repo=tmp.RUN line=1' >> '$LOG'\" ) 2>&1 | grep -q 'offender: bash -c'; ! ( . '$G'; ovn_state_guard_run bash -c \"echo 'z repo=tmp.RUN2 line=1' >> '$LOG'\" ) 2>/dev/null"
ok "A12 ovn_state_guard_run: a clean test passes its own rc through (3 stays 3)" "( . '$G'; ovn_state_guard_run bash -c 'exit 3'; [ \$? = 3 ] )"
ok "A13 OVN_GUARD_LIVE_REPOS overrides the repo list" "( export OVN_GUARD_LIVE_REPOS='tmp.OK'; . '$G'; ovn_state_guard_begin; echo 'z repo=tmp.OK line=1' >> '$LOG'; ovn_state_guard_end )"

echo "== B: the mechanism (replayed in a sandbox HOME)"
SB="$tmp/home"; mkdir -p "$SB/overnight-queue/state" "$SB/overnight-queue/repos/iptv_apps"
ln -s "$Q/scripts" "$SB/overnight-queue/scripts"
SLOG="$SB/overnight-queue/state/verify_gate_shadow.log"
W="$tmp/w"; mkdir -p "$W/app"; touch "$W/app/foo.py"
reset_w(){   # rewrite the fixture from scratch: the credit script TICKS the item in place, so a second run on the same file would credit nothing (and write no row) - which is also host-dependent (GNU sed -i ticks it, BSD sed -i fails silently)
  printf '# P\n\n## Next Steps\n- [ ] [HIGH] `app/foo.py` - add Query bounds. One file.\n' > "$W/OVERNIGHT_PROGRESS.md"
  printf 'app/foo.py\nQuery is already imported. This item is already done.\n' > "$W/tlog"
}
reset_w
credit(){ ( cd "$W" && HOME="$SB" "$@" bash "$Q/scripts/ovn_credit_already_satisfied.sh" tlog OVERNIGHT_PROGRESS.md >/dev/null 2>&1 ); }
export OVN_GUARD_LIVE_DIR="$SB/overnight-queue"
( . "$G"; ovn_state_guard_begin; credit env -u OVN_VERIFY_SHADOW_LOG; ovn_state_guard_end ) >"$tmp/b1.out" 2>&1; B1=$?
ok "B1 the credit script WITHOUT OVN_VERIFY_SHADOW_LOG writes its rows to \$HOME/overnight-queue/state/verify_gate_shadow.log (the live path) and the guard catches it" "[ $B1 = 1 ] && grep -q 'repo=w ' '$SLOG'"
: > "$SLOG"
reset_w   # B2 must not depend on what B1 did to the shared fixture
( . "$G"; ovn_state_guard_begin; credit env OVN_VERIFY_SHADOW_LOG="$tmp/private.log"; ovn_state_guard_end ) >"$tmp/b2.out" 2>&1; B2=$?
ok "B2 the same run WITH OVN_VERIFY_SHADOW_LOG=<temp> leaves the live log untouched and the guard passes" "[ $B2 = 0 ] && [ ! -s '$SLOG' ] && [ -s '$tmp/private.log' ]"

echo "== C: test_bash_helpers.sh (the offender)"
# the fixed test, run with HOME = the sandbox: it must not touch the sandbox's live log
: > "$SLOG"
( . "$G"; ovn_state_guard_begin; HOME="$SB" OVN_SCRIPTS="$Q/scripts" timeout 200 bash "$HERE/test_bash_helpers.sh" >/dev/null 2>&1; ovn_state_guard_end ) >"$tmp/c1.out" 2>&1; C1=$?
ok "C1 the fixed test_bash_helpers.sh leaves the live shadow log untouched (guard rc 0)" "[ $C1 = 0 ] && [ ! -s '$SLOG' ]"
ok "C2 ... also WITHOUT OVN_SCRIPTS (it defaults to the repo copy beside the test, not \$HOME/overnight-queue/scripts)" "( . '$G'; ovn_state_guard_begin; HOME='$SB' timeout 200 bash '$HERE/test_bash_helpers.sh' >/dev/null 2>&1; ovn_state_guard_end )"
# the pre-fix shape: same test with the OVN_VERIFY_SHADOW_LOG export removed
grep -v '^export OVN_VERIFY_SHADOW_LOG=' "$HERE/test_bash_helpers.sh" > "$tmp/helpers_prefix.sh"
: > "$SLOG"
( . "$G"; ovn_state_guard_begin; HOME="$SB" OVN_SCRIPTS="$Q/scripts" timeout 200 bash "$tmp/helpers_prefix.sh" >/dev/null 2>&1; ovn_state_guard_end ) >"$tmp/c3.out" 2>&1; C3=$?
ok "C3 MUTATION: the test without the OVN_VERIFY_SHADOW_LOG export (the pre-fix shape) IS caught: guard rc 1 with repo=tmp. rows" "[ $C3 = 1 ] && grep -q 'repo=tmp\\.' '$tmp/c3.out'"
_l_exp="$(grep -n '^export OVN_VERIFY_SHADOW_LOG=' "$HERE/test_bash_helpers.sh" | head -1 | cut -d: -f1)"; _l_use="$(grep -n 'bash "\$SCRIPTS/ovn_credit_already_satisfied.sh"' "$HERE/test_bash_helpers.sh" | head -1 | cut -d: -f1)"
ok "C4 the fixed test exports OVN_VERIFY_SHADOW_LOG to a temp path BEFORE its first use of the credit script" "[ -n '$_l_exp' ] && [ -n '$_l_use' ] && [ '$_l_exp' -lt '$_l_use' ] && grep -q 'OVN_VERIFY_SHADOW_LOG=\"\$_SHADOW_DIR/' '$HERE/test_bash_helpers.sh'"

echo "== D: MUTATION controls on the guard"
export OVN_GUARD_LIVE_DIR="$LIVE"; : > "$LOG"   # (section B pointed the guard at the sandbox)
python3 - "$G" "$tmp" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = 'index(live, " " r " ") == 0'; assert s.count(a) == 1
open(sys.argv[2] + "/g_nolive.sh", "w").write(s.replace(a, "1"))
b = '  _OVN_SG_BASE="$(_ovn_sg_size)"'; assert s.count(b) == 1
open(sys.argv[2] + "/g_nosize.sh", "w").write(s.replace(b, '  _OVN_SG_BASE=0'))
PY
ok "D1 MUTATION: a guard that flags every row (no live-repo allowance) false-fails on a real fleet row (A2 would fail)" "! ( . '$tmp/g_nolive.sh'; ovn_state_guard_begin; echo 'x repo=xlite line=1' >> '$LOG'; ovn_state_guard_end ) 2>/dev/null"
ok "D2 MUTATION: a guard whose begin() does not record the current size re-reports old rows on a clean pass" "! ( . '$tmp/g_nosize.sh'; echo 'x repo=tmp.OLD line=1' >> '$LOG'; ovn_state_guard_begin; ovn_state_guard_end ) 2>/dev/null"
ok "D3 MUTATION sanity: the real guard passes both of those" "( . '$G'; ovn_state_guard_begin; echo 'x repo=xlite line=1' >> '$LOG'; ovn_state_guard_end ) && ( . '$G'; echo 'x repo=tmp.OLD line=1' >> '$LOG'; ovn_state_guard_begin; ovn_state_guard_end )"

echo "state guard r11: $P passed, $F failed"; [ "$F" -eq 0 ]
