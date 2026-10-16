#!/usr/bin/env bash
# 2026-10-16 (HOME-deletion incident): lint the whole scripts/overnight-queue tree for recursive deletes whose target can be empty / HOME / / (see lint_unsafe_rm.py for the rules),
# prove the lint catches re-introduced unsafe lines (mutant proof on a scratch copy), prove lib_safe_tmp.sh fails closed, and prove the four sandbox tests that caused the incident
# ABORT when mktemp fails: run with TMPDIR pointing at a nonexistent directory and a throwaway HOME holding a sentinel - they must stop and the sentinel must survive.
# Every destructive call here targets a scratch dir under this test's own safe temp dir; nothing real is ever handed to a delete.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
QROOT="$(cd "$HERE/../.." && pwd)"
LINT="$HERE/lint_unsafe_rm.py"
PY="$(command -v python3.12 || command -v python3)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
t(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l" 1; else ok "$l" 0; fi; }
SB="$(safe_mktemp_dir)" || { echo "  FAIL: cannot create a safe temp dir"; exit 1; }
trap 'safe_rm_rf "$SB"' EXIT

echo "== A: the whole tree is clean"
out="$("$PY" -I "$LINT" "$QROOT" 2>&1)"; rc=$?
[ "$rc" = 0 ] || echo "$out" | head -20
t "A1 no unsafe rm -r / find -delete / python rmtree pattern anywhere under scripts/overnight-queue" test "$rc" = 0
t "A2 the lint is registered in run_all.sh before finish (outside finish())" bash -c "awk '/bash test_no_unsafe_rm.sh/{r=NR} /^echo; finish/{f=NR} END{exit !(r && f && r<f)}' '$HERE/run_all.sh'"
t "A3 the registration is not inside the finish() function body" bash -c "awk '/^finish\\(\\)\\{/{i=1} i&&/test_no_unsafe_rm/{bad=1} /^}/{i=0} END{exit bad}' '$HERE/run_all.sh'"

echo "== B: mutant proof - each re-introduced unsafe line makes the lint FAIL on a scratch copy"
mut(){ # $1=name $2=file content line -> prints the lint exit code
  local d="$SB/m_$1"; mkdir -p "$d"; printf '%s\n' '#!/usr/bin/env bash' "$2" > "$d/mutant.sh"
  "$PY" -I "$LINT" "$d" >/dev/null 2>&1; echo $?; }
t "B0 control: a safe file passes" test "$(mut ctl 'tmp="$(safe_mktemp_dir)" || exit 1; safe_rm_rf "$tmp"; rm -rf "${tmp:?}/x"')" = 0
t "B1 mutant: rm -rf \"\$HOME\" is caught (the incident line)" test "$(mut m1 'rm -rf "$HOME"; mkdir -p "$HOME/x"')" = 1
t "B2 mutant: rm -rf \"\$tmp/x\" with no guard is caught" test "$(mut m2 'tmp="$(mktemp -d)"; rm -rf "$tmp/x"')" = 1
t "B3 mutant: rm -rf \"\$X\"/* is caught" test "$(mut m3 'rm -rf "$X"/*')" = 1
t "B4 mutant: unquoted rm -rf \$X is caught" test "$(mut m4 'rm -rf $X')" = 1
t "B5 mutant: find \"\$D/sub\" -delete is caught" test "$(mut m5 'find "$D/sub" -name x -delete')" = 1
t "B6 mutant: trap with rm -rf \"\$T/a\" is caught" test "$(mut m6 "trap 'rm -rf \"\$T/a\"' EXIT")" = 1
t "B7 mutant: rm -fr ~ is caught" test "$(mut m7 'rm -fr ~/x')" = 1
t "B8 guard forms pass: [ -n ] && rm and \${V:?}" test "$(mut m8 '[ -n "$V" ] && rm -rf "$V/x"; rm -rf "${W:?}/y"')" = 0
d="$SB/m_py"; mkdir -p "$d"; printf 'import shutil, pathlib\nshutil.rmtree(pathlib.Path.home())\n' > "$d/m.py"
"$PY" -I "$LINT" "$d" >/dev/null 2>&1; t "B9 mutant: python shutil.rmtree(Path.home()) is caught" test "$?" = 1
# the real thing: re-introduce the incident line into a scratch copy of test_pause_guard.sh
d="$SB/m_real"; mkdir -p "$d"
sed 's|safe_rm_rf "\$HOME" \|\| exit 1; mkdir -p "\$HOME";|rm -rf "$HOME"; mkdir -p "$HOME";|' "$HERE/test_pause_guard.sh" > "$d/test_pause_guard.sh"
t "B10 the scratch copy really differs from the fixed test" bash -c "! cmp -s '$d/test_pause_guard.sh' '$HERE/test_pause_guard.sh'"
"$PY" -I "$LINT" "$d" >/dev/null 2>&1; t "B11 mutant: test_pause_guard.sh with the original rm -rf \"\$HOME\" fails the lint" test "$?" = 1
d="$SB/m_real2"; mkdir -p "$d"; cp "$HERE/test_pause_guard.sh" "$d/"; "$PY" -I "$LINT" "$d" >/dev/null 2>&1; t "B12 the fixed test_pause_guard.sh passes it" test "$?" = 0

echo "== C: lib_safe_tmp.sh fails closed"
c(){ ( . "$HERE/lib_safe_tmp.sh"; "$@" ) >/dev/null 2>&1; echo $?; }
t "C1 safe_mktemp_dir fails when TMPDIR is a nonexistent dir" test "$(TMPDIR="$SB/nonexistent" c safe_mktemp_dir)" != 0
t "C2 safe_rm_rf refuses the empty string" test "$(c safe_rm_rf '')" != 0
t "C3 safe_rm_rf refuses /" test "$(c safe_rm_rf /)" != 0
t "C4 safe_rm_rf refuses /home" test "$(c safe_rm_rf /home)" != 0
t "C5 safe_rm_rf refuses the real HOME" bash -c "[ \"\$(. '$HERE/lib_safe_tmp.sh'; safe_rm_rf \"\$HOME\" >/dev/null 2>&1; echo \$?)\" != 0 ] && [ -d \"\$HOME\" ]"
t "C5b the component counter treats /usr/x as 2 components (refused below 3) and a sandbox path as >= 3" bash -c ". '$HERE/lib_safe_tmp.sh'; [ \"\$(__st_ncomp /usr/x)\" = 2 ] && [ \"\$(__st_ncomp '$SB/a')\" -ge 3 ]"
# C6/C7 use ONLY scratch dirs inside this test's sandbox: a dir outside the allowed root (TMPDIR=$SB/root) must survive, a dir inside it must go
mkdir -p "$SB/outside/a/b" "$SB/root/inside/a/b"
t "C6 safe_rm_rf refuses a path outside the allowed sandbox root (scratch dir survives)" bash -c "TMPDIR='$SB/root' bash -c '. \"$HERE/lib_safe_tmp.sh\"; safe_rm_rf \"$SB/outside/a\" >/dev/null 2>&1'; [ -d '$SB/outside/a/b' ]"
t "C7 ...and removes one inside it" bash -c "TMPDIR='$SB/root' bash -c '. \"$HERE/lib_safe_tmp.sh\"; safe_rm_rf \"$SB/root/inside\"'; [ ! -e '$SB/root/inside' ]"
t "C8 safe_rm_rf refuses a relative path and a .. path" bash -c "[ \"\$(cd '$SB' && bash -c '. \"$HERE/lib_safe_tmp.sh\"; safe_rm_rf rel >/dev/null 2>&1; echo \$?')\" != 0 ] && [ \"\$(bash -c '. \"$HERE/lib_safe_tmp.sh\"; safe_rm_rf \"$SB/../x/y/z\" >/dev/null 2>&1; echo \$?')\" != 0 ]"
mkdir -p "$SB/root/repo/.git" "$SB/root/repo/x"
t "C8b safe_rm_rf refuses a git checkout root even inside the sandbox root" bash -c "TMPDIR='$SB/root' bash -c '. \"$HERE/lib_safe_tmp.sh\"; safe_rm_rf \"$SB/root/repo\" >/dev/null 2>&1'; [ -d '$SB/root/repo/x' ]"
t "C9 safe_set_sandbox_home refuses an empty root (HOME stays unchanged)" bash -c ". '$HERE/lib_safe_tmp.sh'; H0=\"\$HOME\"; safe_set_sandbox_home '' 2>/dev/null; [ \$? -ne 0 ] && [ \"\$HOME\" = \"\$H0\" ]"
t "C10 safe_set_sandbox_home refuses a dir that is not under a temp root" bash -c "TMPDIR='$SB/root' bash -c '. \"$HERE/lib_safe_tmp.sh\"; H0=\"\$HOME\"; safe_set_sandbox_home \"$SB/outside\" 2>/dev/null; [ \$? -ne 0 ] && [ \"\$HOME\" = \"\$H0\" ]'"
t "C11 a sandbox dir + home round-trips (create, reset, remove)" bash -c ". '$HERE/lib_safe_tmp.sh'; t=\"\$(safe_mktemp_dir)\" && safe_set_sandbox_home \"\$t\" && mkdir -p \"\$HOME/a\" && safe_rm_rf \"\$HOME\" && [ ! -e \"\$t/home\" ] && safe_rm_rf \"\$t\" && [ ! -e \"\$t\" ]"

echo "== D: the four incident tests ABORT without deleting anything when mktemp fails (TMPDIR nonexistent, throwaway HOME with a sentinel)"
for tst in test_pause_guard test_fleet_autofix test_gpu_autoswap test_daily_promote; do
  FH="$SB/fakehome_$tst"; mkdir -p "$FH/overnight-queue/state"; : > "$FH/SENTINEL"; : > "$FH/overnight-queue/state/SENTINEL2"
  out="$(cd "$HERE" && env HOME="$FH" TMPDIR="$SB/does/not/exist" bash "$tst.sh" 2>&1)"; rc=$?
  t "D $tst: exits non-zero" test "$rc" != 0
  t "D $tst: says it could not create a safe temp dir" bash -c "printf '%s' \"\$1\" | grep -qE 'safe_mktemp_dir|safe temp dir'" _ "$out"
  t "D $tst: the throwaway HOME sentinels survived" test -f "$FH/SENTINEL" -a -f "$FH/overnight-queue/state/SENTINEL2"
  # the incident's exact shape: mktemp "succeeds" with an EMPTY path (a broken mktemp on PATH) - the test must still abort
  FB="$SB/fakebin_$tst"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 0\n' > "$FB/mktemp"; chmod +x "$FB/mktemp"
  FH2="$SB/fakehome2_$tst"; mkdir -p "$FH2"; : > "$FH2/SENTINEL"
  ( cd "$HERE" && env HOME="$FH2" PATH="$FB:$PATH" bash "$tst.sh" >/dev/null 2>&1 ); rc2=$?
  t "D $tst: an EMPTY mktemp result also aborts (rc $rc2) and spares the sentinel" test "$rc2" != 0 -a -f "$FH2/SENTINEL"
done

echo "== E: lib_tmp_isolation.sh removes only guarded run roots"
t "E1 no bare rm -rf of OVN_TMP_ROOT / the sweep dir in lib_tmp_isolation.sh (all root removals go through safe_rm_rf)" bash -c "! grep -nE 'rm -rf \"?\\\$(OVN_TMP_ROOT|root|d)\"?( |\$|;)' '$HERE/lib_tmp_isolation.sh' | grep -v '^[0-9]*:#'"
echo; echo "no_unsafe_rm: $P passed, $F failed"
[ "$F" -eq 0 ]
