#!/usr/bin/env bash
# N4 tmp-isolation (2026-10-14): lib_tmp_isolation.sh (single-flight, disk-backed private TMPDIR, composed EXIT/INT/TERM cleanup, tmp-leak report, stale sweep), its run_all.sh hook, and the
# tests that used to leak. Everything runs in a sandbox under its own mktemp dir (OVN_TEST_TMP_BASE / OVN_ALERTS_FILE point inside it); nothing touches $HOME/qtmp, /tmp/run.* or any real state.
# bash 3.2 + bash 5 safe. The flock-specific stale-lock case (F) is skipped when there is no flock binary (the Mac); every other case runs on both.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib_tmp_isolation.sh"
PY="$(command -v python3.12 || command -v python3)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
t(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l" 1; else ok "$l" 0; fi; }
SB="$(mktemp -d)"; BASE="$SB/base"; ALERTS="$SB/state/alerts.log"; mkdir -p "$SB/state"
BGP=""
cleanup(){ [ -z "$BGP" ] || kill $BGP 2>/dev/null; rm -rf "$SB"; }
trap cleanup EXIT
export OVN_TEST_TMP_BASE="$BASE" OVN_ALERTS_FILE="$ALERTS"
unset OVN_TEST_LEAK_WARN OVN_TEST_ISOLATE
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
# a "run": sources the lib, isolates, then runs the body ($1); stdout+stderr -> $SB/<name>.out
cat > "$SB/run.sh" <<'EOS'
#!/usr/bin/env bash
. "$LIB"
eval "$PRE"
ovn_tmp_isolate
echo "ROOT=$OVN_TMP_ROOT TMPDIR=$TMPDIR"
eval "$BODY"
EOS
runit(){ # $1=name; env PRE/BODY set by caller
  LIB="$LIB" PRE="${PRE:-:}" BODY="${BODY:-:}" bash "$SB/run.sh" > "$SB/$1.out" 2>&1; echo $? > "$SB/$1.rc"; }
rc_of(){ cat "$SB/$1.rc"; }
waitfor(){ local i=0; while [ ! -e "$1" ] && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done; [ -e "$1" ]; }
root_of(){ sed -n 's/^ROOT=\([^ ]*\) TMPDIR=.*/\1/p' "$SB/$1.out" | head -1; }

echo "== A: private disk-backed TMPDIR, removed on normal exit, exit code preserved, leak line printed"
PRE=: BODY='mkdir -p "$TMPDIR/a/b"; : > "$TMPDIR/a/f1"; : > "$TMPDIR/a/b/f2"; mktemp -d >/dev/null; exit 3' runit A
RA="$(root_of A)"
t "A1 TMPDIR is a run.<pid> root under OVN_TEST_TMP_BASE (not /tmp)" bash -c "case '$RA' in '$BASE'/run.[0-9]*) exit 0;; *) exit 1;; esac"
t "A2 the root is removed after the run" test ! -e "$RA"
t "A3 the body's exit code (3) is preserved" test "$(rc_of A)" = 3
t "A4 a tmp-leak line reports what the tests left (>=4 entries: a, a/b, f1, f2, mktemp dir)" bash -c "grep -Eq '^tmp-leak: [4-9] entries' '$SB/A.out'"
t "A5 the lock pid file is removed on exit" test ! -e "$BASE/.run_all.lock.pid"
t "A6 a clean run reports 0 leaked entries and writes no alert" bash -c "PRE=: BODY=: LIB='$LIB' bash '$SB/run.sh' > '$SB/A6.out' 2>&1; grep -q '^tmp-leak: 0 entries' '$SB/A6.out' && [ ! -s '$ALERTS' ]"

echo "== B: single-flight - a concurrent run is refused with exit 75 and does not disturb the holder"
LIB="$LIB" PRE=: BODY='sleep 30 & wait' bash "$SB/run.sh" > "$SB/H.out" 2>&1 & BGP=$!
waitfor "$BASE/.run_all.lock.pid" && sleep 0.3
PRE=: BODY='echo SECOND-RAN' runit B
t "B1 the second run exits 75" test "$(rc_of B)" = 75
t "B2 the second run's body never ran" bash -c "! grep -q SECOND-RAN '$SB/B.out'"
t "B3 the refusal says another run is in progress" bash -c "grep -q 'in progress' '$SB/B.out'"
RH="$(root_of H)"
t "B4 the holder's root is still there (the refused run did not sweep or remove it)" test -d "$RH"

echo "== C: kill -TERM mid-run still removes the root; the next run then starts"
kill -TERM "$BGP" 2>/dev/null; wait "$BGP" 2>/dev/null; HRC=$?; BGP=""
t "C1 the TERMed holder exited 143" test "$HRC" = 143
t "C2 its root is gone" test ! -e "$RH"
t "C3 its pid file is gone" test ! -e "$BASE/.run_all.lock.pid"
PRE=: BODY='echo THIRD-RAN' runit C
t "C4 the next run is not refused (exit 0, body ran)" bash -c "[ \"\$(cat '$SB/C.rc')\" = 0 ] && grep -q THIRD-RAN '$SB/C.out'"
# (a background job of a non-interactive shell starts with SIGINT ignored and cannot trap it, so the INT case signals itself from a foreground run)
PRE=: BODY='kill -INT $$; sleep 1; echo NOT-INTERRUPTED' runit C5
t "C5 INT: exit 130, the body did not continue, and the root is gone" bash -c "[ \"\$(cat '$SB/C5.rc')\" = 130 ] && ! grep -q NOT-INTERRUPTED '$SB/C5.out' && [ ! -e \"$(root_of C5)\" ]"

echo "== D: leak warning - alerts.log gets a WARN over the threshold, nothing under it"
: > "$ALERTS"
OVN_TEST_LEAK_WARN=10 PRE=: BODY='for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do : > "$TMPDIR/leak$i"; done' runit D
t "D1 15 leaked entries over a threshold of 10 -> a WARN | test-tmp-leak line in alerts.log" bash -c "grep -q 'WARN | test-tmp-leak | ' '$ALERTS'"
: > "$ALERTS"
OVN_TEST_LEAK_WARN=100 PRE=: BODY='for i in 1 2 3; do : > "$TMPDIR/leak$i"; done' runit D2
t "D2 3 leaked entries under a threshold of 100 -> no alert" test ! -s "$ALERTS"
t "D3 the leak is still removed" test ! -e "$(root_of D2)"

echo "== E: stale-root sweep removes dead runs' roots and keeps live ones"
mkdir -p "$BASE/run.99999999/x" "$BASE/not-a-run"; : > "$BASE/run.99999999/x/f"
sleep 30 & SP=$!; mkdir -p "$BASE/run.$SP"
PRE=: BODY=: runit E
t "E1 run.<dead pid> is swept" test ! -e "$BASE/run.99999999"
t "E2 run.<live pid> is kept" test -d "$BASE/run.$SP"
t "E3 a non-run directory is never touched" test -d "$BASE/not-a-run"
kill $SP 2>/dev/null; rm -rf "$BASE/run.$SP" "$BASE/not-a-run"

echo "== F: a lock held by an ORPHAN (recorded holder dead) is stale and replaced - it must not wedge every later run"
if [ -n "$(type -P flock)" ]; then
  mkdir -p "$BASE"; printf '99999999|dead\n' > "$BASE/.run_all.lock.pid"
  ( exec 9>>"$BASE/.run_all.lock"; flock -n 9; sleep 30 ) >/dev/null 2>&1 & OP=$!
  sleep 0.5
  PRE=: BODY='echo FOURTH-RAN' runit F
  t "F1 the run starts (exit 0, body ran) although an orphan still holds the old lock inode" bash -c "[ \"\$(cat '$SB/F.rc')\" = 0 ] && grep -q FOURTH-RAN '$SB/F.out'"
  t "F2 it says the stale lock was replaced" bash -c "grep -q 'replaced a stale run lock' '$SB/F.out'"
  kill $OP 2>/dev/null; rm -f "$BASE/.run_all.lock" "$BASE/.run_all.lock.pid"
else echo "  (F skipped: no flock binary on this host)"; fi

echo "== G: a recorded pid that is alive but has a different start time (pid reuse) is not a live holder"
sleep 30 & SP=$!; printf '%s|Thu Jan  1 00:00:00 1970\n' "$SP" > "$BASE/.run_all.lock.pid"
PRE=: BODY='echo FIFTH-RAN' runit G
t "G1 the run is not refused" bash -c "[ \"\$(cat '$SB/G.rc')\" = 0 ] && grep -q FIFTH-RAN '$SB/G.out'"
kill $SP 2>/dev/null

echo "== H: the caller's own traps are composed, not replaced"
PRE='trap "echo PREV_EXIT_RAN" EXIT; trap "echo PREV_TERM_RAN" TERM' BODY='echo BODY' runit H
t "H1 the pre-existing EXIT trap still ran" bash -c "grep -q PREV_EXIT_RAN '$SB/H.out'"
t "H2 and the root was still removed" test ! -e "$(root_of H)"
PRE='trap "echo PREV_TERM_RAN" TERM' LIB="$LIB" BODY='sleep 30 & wait' bash "$SB/run.sh" > "$SB/H3.out" 2>&1 & BGP=$!
waitfor "$BASE/.run_all.lock.pid" && sleep 0.3; RH3="$(root_of H3)"
kill -TERM "$BGP" 2>/dev/null; wait "$BGP" 2>/dev/null; BGP=""
t "H3 the caller's TERM handler ran on TERM and the root is gone" bash -c "grep -q PREV_TERM_RAN '$SB/H3.out' && [ ! -e '$RH3' ]"

echo "== I: OVN_TEST_ISOLATE=off disables it (no root, TMPDIR untouched, no lock)"
OVN_TEST_ISOLATE=OFF PRE=: BODY='echo "T=$TMPDIR"' runit I
t "I1 no root, TMPDIR not redirected, exit 0" bash -c "grep -q '^ROOT= ' '$SB/I.out' && ! grep -q 'T=$BASE' '$SB/I.out' && [ \"\$(cat '$SB/I.rc')\" = 0 ] && [ ! -e '$BASE/.run_all.lock.pid' ]"

echo "== J: run_all.sh is wired (hook after ntfy_guard, harmless when the lib is absent) and this test is registered"
RUNALL="$HERE/run_all.sh"
t "J1 run_all.sh sources lib_tmp_isolation.sh and calls ovn_tmp_isolate after ntfy_guard.sh" bash -c "a=\$(grep -n 'ntfy_guard.sh' '$RUNALL' | head -1 | cut -d: -f1); b=\$(grep -n 'ovn_tmp_isolate' '$RUNALL' | head -1 | cut -d: -f1); [ -n \"\$a\" ] && [ -n \"\$b\" ] && [ \"\$b\" -gt \"\$a\" ]"
HOOK="$(grep 'ovn_tmp_isolate' "$RUNALL" | head -1)"
mkdir -p "$SB/nolib"; printf '#!/usr/bin/env bash\nHERE_RA="%s"\n%s\necho HOOK-SURVIVED\n' "$SB/nolib" "$HOOK" > "$SB/nolib/x.sh"
t "J2 the hook line is a no-op when the library is missing (the run_all meta-test sandbox has none)" bash -c "bash '$SB/nolib/x.sh' 2>&1 | grep -q HOOK-SURVIVED"
t "J3 run_all.sh registers test_tmp_isolation.sh" bash -c "grep -q 'test_tmp_isolation.sh' '$RUNALL'"

echo "== K: the python tests that used to leak mkdtemp dirs now leave NOTHING (regression for tmp_track.install())"
for pt in test_ovn_doc_executor test_qa_block_watch_r10 test_ovn_supply_r10; do
  KT="$SB/k_$pt"; mkdir -p "$KT"
  ( cd "$HERE" && TMPDIR="$KT" "$PY" "$pt.py" >/dev/null 2>&1 ); krc=$?
  t "K $pt: passes (rc 0) and leaves 0 entries in TMPDIR (found $(find "$KT" -mindepth 1 2>/dev/null | wc -l | tr -d ' '))" bash -c "[ $krc = 0 ] && [ \"\$(find '$KT' -mindepth 1 | wc -l | tr -d ' ')\" = 0 ]"
done
t "K4 each of the three installs tmp_track" bash -c "for f in test_ovn_doc_executor test_qa_block_watch_r10 test_ovn_supply_r10; do grep -q 'tmp_track.install()' '$HERE'/\$f.py || exit 1; done"
KU="$SB/k_unit"; mkdir -p "$KU"
t "K5 tmp_track unit: mkdtemp after install is swept; one made before install is not touched" bash -c "cd '$HERE' && TMPDIR='$KU' '$PY' - <<'PYEOF'
import os, sys, tempfile
pre = tempfile.mkdtemp()
import tmp_track
tmp_track.install()
m = tmp_track.mark()
a = tempfile.mkdtemp(); b = tempfile.mkdtemp()
assert tmp_track.sweep(m) == 2 and not os.path.exists(a) and not os.path.exists(b)
c = tempfile.mkdtemp()
tmp_track.sweep()
assert not os.path.exists(c) and os.path.exists(pre)
os.rmdir(pre)
PYEOF"

echo "== L: the four shell tests that had neither trap nor rm now clean up (run with a private TMPDIR, nothing may remain)"
run_leak(){ # $1=test file, rest=env assignments
  local f="$1"; shift; local d="$SB/l_$f"; mkdir -p "$d"
  ( cd "$HERE" && env TMPDIR="$d" "$@" bash "$f.sh" >/dev/null 2>&1 ); echo "$? $(find "$d" -mindepth 1 | wc -l | tr -d ' ')"; }
for spec in "test_batch_scorecard OVN_SCRIPTS_DIR=$HERE/.." "test_batch_stragglers OVN_SCRIPTS_DIR=$HERE/.." "test_pipeline_audit OVN_PIPELINE_AUDIT=$HERE/../../ovn_pipeline_audit.sh" "test_retired_filter X=1"; do
  set -- $spec; f="$1"; shift
  res="$(run_leak "$f" "$@")"; left="${res#* }"
  t "L $f: nothing left in TMPDIR (rc/leftover: $res)" test "$left" = 0
  t "L $f: has an EXIT trap that removes its temp dir/file" grep -Eq "trap .*rm -[rf]+ .*EXIT" "$HERE/$f.sh"
done
echo; echo "tmp_isolation: $P passed, $F failed"
[ "$F" -eq 0 ]
