#!/usr/bin/env bash
# K4 (2026-11-01): the nightly coverage run at 04:27 CST on the America/Chicago fall-back night failed 10 lines in four suites (test_ovn_research_trigger_check, test_auto_research_lock,
# test_research_trigger_monotonic, test_box_recover): they build "N hours ago" as LOCAL wall-clock strings and the code under test parses them back, and 01:00-02:00 happens twice that night.
# This asserts (1) the root cause is real (an ambiguous local hour does not round-trip; UTC does), (2) lib_test_tz.sh pins UTC whatever the caller's TZ, (3) every one of the four suites sources it,
# (4) mutant: a suite copy with the pin line removed is caught by (3). Nothing here depends on the host's current date or zone.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir k4tz)" || exit 1; trap 'safe_rm_rf "$W"' EXIT
ROUNDTRIP='import os,sys,time
os.environ["TZ"]=sys.argv[1]; time.tzset()
e=1793518020   # 2026-11-01 07:27:00 UTC = 01:27 CST, the SECOND 01:27 of the America/Chicago fall-back night (3h before a 04:27 CST run)
s=time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(e))
print(int(time.mktime(time.strptime(s, "%Y-%m-%d %H:%M:%S")))-e)'
ok "T1 root cause: in America/Chicago the wall-clock string of that instant parses back an hour off (what the suites' ago()/touch -t/mktime did)" '[ "$(python3 -c "$ROUNDTRIP" America/Chicago)" != 0 ]'
ok "T2 in UTC the same instant round-trips exactly" '[ "$(python3 -c "$ROUNDTRIP" UTC)" = 0 ]'
ok "T3 lib_test_tz.sh pins UTC even when the caller runs in America/Chicago" '[ "$(TZ=America/Chicago bash -c ". \"$HERE/lib_test_tz.sh\"; echo \$TZ")" = UTC ]'
SUITES="test_ovn_research_trigger_check.sh test_auto_research_lock.sh test_research_trigger_monotonic.sh test_box_recover.sh"
pinned(){ grep -q 'lib_test_tz.sh' "$1"; }
for s in $SUITES; do ok "T4 $s sources the UTC pin" 'pinned "$HERE/$s"'; done
# the pin must come BEFORE the suite builds any timestamp: it sits in the header, ahead of the first date/touch/strftime use
for s in $SUITES; do ok "T5 $s: pin line precedes the first time-relative command" '[ "$(grep -n "lib_test_tz.sh" "$HERE/$s" | head -1 | cut -d: -f1)" -lt "$(grep -nE "date |touch -t|strftime|time\\.time" "$HERE/$s" | head -1 | cut -d: -f1)" ] || [ -z "$(grep -nE "date |touch -t|strftime|time\\.time" "$HERE/$s" | head -1)" ]'; done
# the monotonic suite's python half inherits TZ from its wrapper
ok "T6 the pinned wrapper really runs the monotonic python in UTC (TZ inherited)" '[ "$(TZ=America/Chicago bash -c ". \"$HERE/lib_test_tz.sh\"; python3 -c \"import time; print(time.tzname[0])\"")" = UTC ]'
# MUTANT: the pin line removed from a copy must be caught by the T4 check
for s in $SUITES; do grep -v 'lib_test_tz.sh' "$HERE/$s" > "$W/mut_$s"; done
ok "M1 MUTANT (pin removed from all four suites): every T4 check would fail" 'for s in $SUITES; do ! pinned "$W/mut_$s" || exit 1; done'
echo "  $P passed, $F failed"; [ "$F" = 0 ]
