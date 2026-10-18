#!/usr/bin/env bash
# test_stub_leak_alert_n2.sh - package qa (2026-10-13, platform-night P11). The stub-leak FLAG is shadow and lived only in branch_hygiene.log: the same 2 placeholder-only
# files were flagged on every pass 02:00-11:00 and nothing alerted. Now ONE alerts.log warn when the SAME file set is flagged on 3 consecutive passes (a different set
# restarts the count, a clean pass resets, OVN_STUB_LEAK_ALERT=off / DRY_RUN=1 write nothing, OVN_STUB_LEAK_ALERT_PASSES tunes). Nothing blocks (enforce stays a separate switch).
# The deployed block is extracted from branch_hygiene.sh and run for real (like test_stub_leak_hygiene.sh).
# The counter is keyed by repo AND feature branch (reviewer fix: hygiene runs twice per repo - overnight/feature and claude/feature - and a repo-only key let one lane's clean
# pass reset the other lane's count); the interleaved-lane cases are at the end.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
BH="${OVN_BRANCH_HYGIENE:-$HERE/../../branch_hygiene.sh}"
[ -f "$BH" ] || { echo "  SKIP: $BH not found"; exit 0; }
SD="$(cd "$(dirname "$BH")" && pwd)"
P=0; F=0
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1 (got [$2] want [$3])"; fi; }
BLOCK="$(sed -n '/# stub-leak FLAG (r11, package stub; SHADOW)/,/^  # web build+test/p' "$BH" | sed '$d')"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the stub-leak block from $BH"; exit 1; }
W="$(__d="$(safe_mktemp_dir)" || exit 1 && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "${W:?}"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
LOGF="$W/hygiene.log"; : > "$LOGF"
log(){ echo "[branch-hygiene] $*" >> "$LOGF"; }
STATE_DIR="$W/state"; mkdir -p "$STATE_DIR"; ALERTS="$STATE_DIR/alerts.log"
FEAT="overnight/feature"
gate_fn(){ local repo="$1" dir="$2"; eval "$BLOCK"; return 0; }
pass(){ SCRIPT_DIR="$SD" STATE_DIR="$STATE_DIR" gate_fn "$1" "$1" >/dev/null; }
sf(){ echo "$STATE_DIR/stub_leak_streak/$1__overnight_feature"; }   # the overnight/feature lane's streak file for repo $1
nal(){ local n; n="$(grep -c "stub-leak:$1" "$ALERTS" 2>/dev/null || true)"; echo "${n:-0}"; }
M='Placeholder - the implement step fills this in.'
mk(){ rm -rf "${W:?}/$1"; mkdir -p "$W/$1/app"; ( cd "$W/$1" && git init -q -b main . && printf 'x=1\n' > app/real.py && git add -A && git commit -q -m init ); }
leak(){ local r="$1"; shift; for f in "$@"; do printf '// %s\n' "$M" > "$W/$r/$f"; done; ( cd "$W/$r" && git add -A && git commit -q -m "leak $*" ); }

mk app; leak app app/A.kt app/B.kt
pass "$W/app"; pass "$W/app"
eq "pass 1-2 with the same leak: NO alert yet" "$(nal app)" "0"
pass "$W/app"
eq "pass 3: exactly ONE warn" "$(nal app)" "1"
eq "the alert line has the standard format and names the files" "$(grep -cE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] warn \| stub-leak:app \| .*3 consecutive passes.*app/A.kt app/B.kt' "$ALERTS")" "1"
pass "$W/app"; pass "$W/app"; pass "$W/app"
eq "pass 4-6: still exactly one alert (no spam)" "$(nal app)" "1"
eq "the shadow flag still logs every pass (unchanged)" "$(grep -c 'STUB-LEAK FLAG (shadow)' "$LOGF")" "6"
eq "nothing blocks (rc 0 in shadow)" "$(SCRIPT_DIR="$SD" STATE_DIR="$STATE_DIR" gate_fn "$W/app" "$W/app"; echo $?)" "0"

# a CHANGED file set restarts the count
leak app app/C.kt
pass "$W/app"; pass "$W/app"
eq "a different file set restarts the count: 2 passes -> no second alert" "$(nal app)" "1"
pass "$W/app"
eq "... and the 3rd pass of the new set alerts once more" "$(nal app)" "2"

# a clean pass resets
( cd "$W/app" && git rm -q app/A.kt app/B.kt app/C.kt && git commit -q -m clean )
pass "$W/app"
eq "a clean pass removes the streak file" "$([ -e "$(sf app)" ] && echo present || echo gone)" "gone"
leak app app/A.kt; pass "$W/app"; pass "$W/app"
eq "after the reset a new streak needs 3 passes again (2 -> no new alert)" "$(nal app)" "2"

# lanes independent
mk other; leak other app/Z.kt
pass "$W/other"; pass "$W/other"; pass "$W/other"
eq "another repo has its own counter and alerts under its own tag" "$(nal other)" "1"

# switches
mk off1; leak off1 app/A.kt
for i in 1 2 3 4; do OVN_STUB_LEAK_ALERT=off pass "$W/off1"; done
eq "OVN_STUB_LEAK_ALERT=off: no alert, no state" "$(nal off1)$([ -e "$(sf off1)" ] && echo S)" "0"
for i in 1 2 3 4; do DRY_RUN=1 pass "$W/off1"; done
eq "DRY_RUN=1 never writes an alert or state" "$(nal off1)$([ -e "$(sf off1)" ] && echo S)" "0"
mk tun; leak tun app/A.kt
for i in 1 2; do OVN_STUB_LEAK_ALERT_PASSES=2 pass "$W/tun"; done
eq "OVN_STUB_LEAK_ALERT_PASSES=2 alerts on the 2nd pass" "$(nal tun)" "1"
mk bad; leak bad app/A.kt
for i in 1 2 3; do OVN_STUB_LEAK_ALERT_PASSES=abc pass "$W/bad"; done
eq "a garbage threshold falls back to 3" "$(nal bad)" "1"
mk offleak; leak offleak app/A.kt
for i in 1 2 3; do OVN_STUB_LEAK=off pass "$W/offleak"; done
eq "OVN_STUB_LEAK=off (the flag itself off): no alert" "$(nal offleak)" "0"
mk tst; mkdir -p "$W/tst/tests"; printf '# %s\n' "$M" > "$W/tst/tests/test_x.gd"; ( cd "$W/tst" && git add -A && git commit -q -m t )
for i in 1 2 3 4; do pass "$W/tst"; done
eq "BENIGN: a test-file placeholder is informational only: no alert" "$(nal tst)" "0"
mk corrupt; leak corrupt app/A.kt; mkdir -p "$STATE_DIR/stub_leak_streak"; echo "garbage line here" > "$(sf corrupt)"
for i in 1 2 3; do pass "$W/corrupt"; done
eq "a corrupt streak file is treated as 0 (restarts, alerts at pass 3)" "$(nal corrupt)" "1"
# the two hygiene lanes of ONE repo (same basename, different $FEAT) have independent counters
mkdir -p "$W/lanes/a" "$W/lanes/b"; mk lanesrc; rm -rf "${W:?}/lanes/a/lnx" "${W:?}/lanes/b/lnx"
cp -R "$W/lanesrc" "$W/lanes/a/lnx"; cp -R "$W/lanesrc" "$W/lanes/b/lnx"; leak "lanes/a/lnx" app/A.kt
lane(){ ( FEAT="$1"; SCRIPT_DIR="$SD" STATE_DIR="$STATE_DIR" gate_fn "$2" "$2" >/dev/null ); }
rm -rf "${STATE_DIR:?}/stub_leak_streak"
lane overnight/feature "$W/lanes/a/lnx"
lane claude/feature    "$W/lanes/b/lnx"      # clean lane between the leaky lane's passes
lane overnight/feature "$W/lanes/a/lnx"
lane claude/feature    "$W/lanes/b/lnx"
eq "interleaved: 2 leaky + 2 clean passes -> no alert yet" "$(nal lnx)" "0"
lane overnight/feature "$W/lanes/a/lnx"
eq "interleaved: the leaky lane's 3rd pass alerts although the other lane ran clean passes in between" "$(nal lnx)" "1"
eq "each lane has its own streak file (only the leaky lane has one)" "$(ls "$STATE_DIR/stub_leak_streak" | tr '\n' ' ')" "lnx__overnight_feature "
# a DIFFERENT leak on the other lane does not restart this lane's count
( cd "$W/lanes/b/lnx" && printf '// %s\n' "$M" > app/B.kt && git add -A && git commit -q -m leakb )
lane claude/feature "$W/lanes/b/lnx"; lane overnight/feature "$W/lanes/a/lnx"
eq "the other lane's different file set neither alerts under the first lane's count nor resets it (still 1 alert, 2 streak files)" "$(nal lnx) $(ls "$STATE_DIR/stub_leak_streak" | wc -l | tr -d ' ')" "1 2"
echo "stub leak alert n2: $P passed, $F failed"; [ "$F" = 0 ]
