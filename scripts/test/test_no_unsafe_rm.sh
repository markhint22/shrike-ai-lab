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

# runtime data dirs at the queue ROOT (repos/ = live fleet clones, state/) are not queue source; a nested one is still linted (a mutant must be caught there)
# 2026-10-21 (P1): A4/A5 only fail under the nightly coverage run's BASH_ENV xtrace instrumentation (scripts/cov/run_coverage.sh exports OVN_COV_RUN=1); they pass 129/0 plain.
# Under that flag they SKIP loudly (never silently) - the plain suite run still executes them. Without OVN_COV_RUN=1 nothing is skipped.
if [ "${OVN_COV_RUN:-0}" = 1 ]; then
  echo "  SKIP A4 A5 (OVN_COV_RUN=1: coverage xtrace instrumentation perturbs this section; covered by the plain run_all.sh run)"
  SKIPPED_COV="A4 A5"
else
  SKIPPED_COV=""
d="$SB/m_root"; mkdir -p "$d/repos/app" "$d/state/x" "$d/scripts/repos"
for f in "$d/repos/app/a.sh" "$d/state/x/b.sh" "$d/scripts/repos/c.sh"; do printf '#!/usr/bin/env bash\nrm -rf "$X"\n' > "$f"; done
out="$("$PY" -I "$LINT" "$d" 2>&1)"
t "A4 unsafe lines under the root-level repos/ and state/ are not linted" bash -c "! printf '%s' '$out' | grep -q -e '/repos/app/a.sh' -e '/state/x/b.sh'"
t "A5 ...but a nested scripts/repos/ is still linted (the skip is top-level only)" bash -c "printf '%s' '$out' | grep -q '/scripts/repos/c.sh'"
fi
t "A6 the A4/A5 coverage-run skip fires ONLY under OVN_COV_RUN=1 (plain run: nothing skipped; flag: exactly A4 A5)" test "$([ "${OVN_COV_RUN:-0}" = 1 ] && echo "$SKIPPED_COV" || echo "none:$SKIPPED_COV")" = "$([ "${OVN_COV_RUN:-0}" = 1 ] && echo "A4 A5" || echo "none:")"

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

echo "== F: v1 bypasses - every sample must now be FLAGGED by the tokenising lint (one scratch file each)"
fl(){ # $1=name $2=content [$3=file name]: prints the lint exit code (1 = flagged, 0 = clean)
  local d="$SB/f_$1"; mkdir -p "$d"; printf '%s\n' '#!/usr/bin/env bash' "$2" > "$d/${3:-mutant.sh}"
  "$PY" -I "$LINT" "$d" >/dev/null 2>&1; echo $?; }
flag(){ local lbl="$1"; shift; t "F $lbl is flagged" test "$(fl "$@")" = 1; }
okay(){ local lbl="$1"; shift; t "G $lbl passes" test "$(fl "$@")" = 0; }
flag "1 absolute /bin/rm" f1 '/bin/rm -rf "$tmp/x"'
flag "2 backslash-escaped quotes on the line (v1 skipped the whole line)" f2 'trap "rm -rf \"$T/a\"" EXIT'
flag "3 line-continued rm, target on the next line" f3 $'rm -rf \\\n  "$tmp/x"'
flag "4 \"\$RM\" -rf" f4 '"$RM" -rf "$tmp/x"'
flag "5 adjacent quoted strings" f5 'rm -rf '"''"'"$tmp"/x'
flag "6 two adjacent variables joined by a slash" f6 'rm -rf "$A"/"$B"'
flag "7 command substitution leads the target" f7 'rm -rf "$(dirname "$x")/y"'
flag "8 \${tmp:-}/x" f8 'rm -rf "${tmp:-}/x"'
flag "9 \${tmp:-/}/x" f9 'rm -rf "${tmp:-/}/x"'
flag "10 \"/\$tmp\"" f10 'rm -rf "/$tmp"'
flag "11 \"\$A\$B\"" f11 'rm -rf "$A$B"'
flag "12 alias of HOME (h=\"\$HOME\"; rm -rf \"\$h\")" f12 'h="$HOME"; rm -rf "$h"'
flag "13 alias of HOME through a second alias" f13 $'h="$HOME"\ng="$h"\nrm -rf "$g"'
flag "14 find \"\$tmp\" -delete" f14 'find "$tmp" -delete'
flag "15 find \"\$tmp/x\" -exec rm -rf {} +" f15 'find "$tmp/x" -exec rm -rf {} +'
flag "16 backslash-rm (\\rm)" f16 '\rm -rf "$tmp/x"'
flag "17 command rm" f17 'command rm -rf "$tmp/x"'
flag "18 env rm" f18 'env rm -rf "$tmp/x"'
flag "19 bash -c string" f19 "bash -c 'rm -rf \"\$T/x\"'"
flag "20 eval string" f20 'eval "rm -rf \"$T/x\""'
flag "21 xargs rm -rf" f21 'printf "%s\n" a b | xargs rm -rf'
flag "22 rm inside a command substitution" f22 'x="$(rm -rf "$tmp/x")"'
flag "23 rm inside backticks" f23 'x=`rm -rf "$tmp/x"`'
flag "24 rm in a heredoc body fed to bash" f24 $'bash <<EOT\nrm -rf "$tmp/x"\nEOT'
flag "25 rm -r (not -rf) of an unproven alias" f25 'd="$tmp/x"; rm -r "$d"'
flag "26 rm -fr / rm -Rf / rm --recursive spellings" f26 'rm -Rf "$a/x"; rm --recursive "$b/y"'
flag "27 rm of a quoted HOME with a trailing glob" f27 'rm -rf "$HOME"/*'
flag "28 rm of \${HOME} (braces)" f28 'rm -rf "${HOME}"'
flag "29 tilde" f29 'rm -rf ~/x'
flag "30 rm -rf of an unquoted variable" f30 'rm -rf $X'
flag "31 rm -rf \"\$V\" with only an unrelated test on the same line" f31 '[ -n "$OTHER" ] && rm -rf "$V/x"'
flag "32 find -exec sh -c rm" f32 'find "$tmp/x" -type d -exec sh -c "rm -rf {}" \;'
flag "33 rm after a trap string with a variable" f33 "trap 'rm -rf \"\$W\"' EXIT"
flag "34 python shutil.rmtree(os.environ[HOME])" f34 $'import os, shutil\nshutil.rmtree(os.environ["HOME"])' m.py
flag "35 python shutil.rmtree(Path.home())" f35 $'import shutil, pathlib\nshutil.rmtree(pathlib.Path.home())' m.py
flag "36 python rmtree of an alias of expanduser" f36 $'import os, shutil\nh = os.path.expanduser("~")\nshutil.rmtree(h)' m.py
flag "37 python rmtree of an f-string with an unanchored variable" f37 $'import shutil\nshutil.rmtree(f"{base}/x")' m.py
flag "38 python -c rmtree of HOME inside a shell script" f38 "python3 -c 'import os,shutil; shutil.rmtree(os.environ[\"HOME\"])'"
flag "39 export HOME=\$tmp/home (the incident assignment)" f39 'export HOME="$tmp/home"'
flag "40 plain HOME=\$tmp/home" f40 'HOME="$tmp/home"'
flag "41 raw mktemp -d in a test, abort but no non-empty check (R8): rc 0 with empty output would go unnoticed" f41 $'T="$(mktemp -d)" || exit 1\nmkdir -p "$T/x"' test_x.sh
okay "11b raw mktemp -d in a test WITH the abort + non-empty/dir check (the sandbox-specific /tmp probes)" g11b $'T="$(mktemp -d /tmp/x.XXXXXX)" || exit 1\n[ -n "$T" ] && [ -d "$T" ] || exit 1\nmkdir -p "$T/x"' test_x.sh
flag "42 raw mktemp -d in a production script, no abort/check (R7)" f42 'WORK="$(mktemp -d)"; echo "$WORK/x"'
flag "43 mktemp -d result used inline" f43 'cd "$(mktemp -d)" && touch x'
flag "44 mktemp -d via local (masks the exit status)" f44 'f(){ local d="$(mktemp -d)" || return 1; echo "$d"; }'
flag "45 find root is an unproven variable with -exec rm -f" f45 'find "$LOGS/x" -maxdepth 1 -type f -mtime +3 -exec rm -f {} +'
flag "46 a [ -n ] guard on a DIFFERENT variable does not guard" f46 'if [ -n "$A" ]; then rm -rf "$B/x"; fi'
flag "47 a loop variable" f47 'for d in "$R"/*; do rm -rf "$d"; done'
flag "48 positional parameter" f48 'f(){ rm -rf "$1/x"; }'
echo "== G: the guarded forms the migration relies on still pass (no false positives from the new rules)"
okay "1 safe_mktemp_dir + derived rm in a test" g1 $'T="$(safe_mktemp_dir)" || exit 1\nrm -rf "$T/x" "$T"/y\ntrap \'rm -rf "$T"\' EXIT\nR="$T/r"; rm -rf "$R"' test_x.sh
okay "2 \${V:?} on every target" g2 'rm -rf "${A:?}/x" "${B:?}"'
okay "3 enclosing if [ -n ] / [ -d ]" g3 $'if [ -d "$Q" ]; then\n  rm -rf "$Q/a"\nfi'
okay "4 [ -n ] && rm chain and early-exit guard" g4 $'[ -n "$V" ] && rm -rf "$V/z"\n[ -n "$W" ] || exit 1\nrm -rf "$W/y"'
okay "5 literal anchored paths and plain names" g5 'rm -rf build dist /tmp/foo.$$ ./node_modules'
okay "6 mktemp -d || V=\"\" then guarded rm" g6 $'wt="$(mktemp -d /tmp/x.XXXX 2>/dev/null)" || wt=""\n[ -n "$wt" ] && rm -rf "$wt"'
okay "7 mktemp -d || exit plus a non-empty/dir check" g7 $'W="$(mktemp -d)" || exit 1\n[ -n "$W" ] && [ -d "$W" ] || exit 1\nrm -rf "$W/x"'
okay "8 safe_set_sandbox_home and safe_rm_rf" g8 $'T="$(safe_mktemp_dir)" || exit 1\nsafe_set_sandbox_home "$T" || exit 1\nsafe_rm_rf "$HOME"' test_x.sh
okay "9 an unsafe-looking rm only inside a single-quoted DATA string / comment" g9 $'echo \'rm -rf "$x/y"\'\n# rm -rf "$HOME"'
okay "10 python rmtree of a mkdtemp-derived path" g10 $'import shutil, tempfile, os\nd = tempfile.mkdtemp()\nshutil.rmtree(os.path.join(d, "x"))' m.py
okay "11 find with a \${V:?} root" g11 'find "${D:?}/x" -maxdepth 1 -type f -mtime +3 -exec rm -f {} +'
okay "12 safe_mktemp_dir_in" g12 $'T="$(safe_mktemp_dir)" || exit 1\nS="$(safe_mktemp_dir_in "$T" sub)" || exit 1\nrm -rf "$S/x"' test_x.sh
okay "13 restoring the real HOME" g13 'export HOME="$OVN_SAFE_REAL_HOME"'
echo "== F2: the lint does not skip a file just because it is an odd shape"
d="$SB/f_misc"; mkdir -p "$d"; printf 'rm -rf "$tmp/x"\n' > "$d/noshebang_script"
t "F49 an extension-less file with no shebang is not shell: not linted (documented), but a shebang one is" test "$(printf '#!/bin/sh\nrm -rf "$tmp/x"\n' > "$d/withshebang"; "$PY" -I "$LINT" "$d/withshebang" >/dev/null 2>&1; echo $?)" = 1

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

# 2026-10-16: explicit template (BSD mktemp ignores TMPDIR when given no template) - the TMPDIR containment check must hold on BSD and GNU alike
mkdir -p "$SB/root" "$SB/mkpath"
lib(){ ( . "$HERE/lib_safe_tmp.sh" && "$@" ); }          # run one lib function in a subshell (TMPDIR=... lib safe_mktemp_dir x)
physroot="$(cd "$SB/root" && pwd -P)"
c12(){ local d; d="$(TMPDIR="$SB/root" lib safe_mktemp_dir lbl)" || return 1; [ -d "$d" ] || return 1; case "$d" in "$physroot"/lbl.??????) rmdir "$d";; *) return 1;; esac; }
t "C12 safe_mktemp_dir with TMPDIR set returns a dir strictly under TMPDIR (physical form, <label>.XXXXXX)" c12
c13(){ local d; d="$(TMPDIR="$SB/root/" lib safe_mktemp_dir)" || return 1; [ -d "$d" ] && rmdir "$d"; }
t "C13 ...also with a trailing slash on TMPDIR" c13
c14(){ local d; d="$(env -u TMPDIR bash -c '. "$1"; safe_mktemp_dir' _ "$HERE/lib_safe_tmp.sh")" || return 1; [ -d "$d" ] && rmdir "$d"; }
t "C14 ...and with TMPDIR unset (the OS per-user temp dir)" c14
# a mktemp that ignores the template and creates elsewhere (what BSD mktemp did with no template) must be REFUSED when TMPDIR points elsewhere
printf '#!/bin/sh\nexec env -i %s -d\n' "$(command -v mktemp)" > "$SB/mkpath/mktemp"; chmod +x "$SB/mkpath/mktemp"
c15(){ local out rc; out="$(TMPDIR="$SB/root" PATH="$SB/mkpath:$PATH" lib safe_mktemp_dir 2>/dev/null)"; rc=$?; [ "$rc" != 0 ] && [ -z "$out" ]; }
t "C15 a mktemp that ignores the template and creates elsewhere is refused (not under TMPDIR) and prints nothing" c15
c16(){ [ -x /usr/bin/mktemp ] || return 0; local d; d="$(PATH=/usr/bin:/bin TMPDIR="$SB/root" lib safe_mktemp_dir)" || return 1; rmdir "$d"; }
t "C16 BSD mktemp (/usr/bin, macOS) first on PATH works with TMPDIR set" c16
GNUB=/opt/homebrew/opt/coreutils/libexec/gnubin
c17(){ [ -x "$GNUB/mktemp" ] || { echo "    (no GNU coreutils here: C17 trivially skipped)" >&2; return 0; }
  local d; d="$(PATH="$GNUB:/usr/bin:/bin" TMPDIR="$SB/root" lib safe_mktemp_dir)" || return 1; rmdir "$d" || return 1
  d="$(PATH="$GNUB:/usr/bin:/bin" env -u TMPDIR bash -c '. "$1"; safe_mktemp_dir' _ "$HERE/lib_safe_tmp.sh")" || return 1; rmdir "$d"; }
t "C17 GNU coreutils mktemp first on PATH works with TMPDIR set and unset" c17
c18(){ local p s bad
  p="$(TMPDIR="$SB/root" lib safe_mktemp_dir)" || return 1
  s="$(TMPDIR="$SB/root" lib safe_mktemp_dir_in "$p" sub)" || return 1
  [ -d "$s" ] || return 1
  case "$s" in "$p"/sub.??????) :;; *) return 1;; esac
  for bad in "" /tmp "$HOME" "$p/nonexistent"; do TMPDIR="$SB/root" lib safe_mktemp_dir_in "$bad" x >/dev/null 2>&1 && return 1; done
  rmdir "$s" "$p"; return 0; }
t "C18 safe_mktemp_dir_in makes a subdir of a sandbox and refuses empty, /tmp, HOME and a non-directory" c18
: > "$SB/afile"
c19(){ local out; out="$(TMPDIR="$SB/afile" lib safe_mktemp_dir 2>/dev/null)"; [ -z "$out" ] && ! TMPDIR="$SB/afile" lib safe_mktemp_dir >/dev/null 2>&1; }
t "C19 safe_mktemp_dir fails closed and prints nothing when TMPDIR is a FILE" c19

c20(){ # a test that narrows TMPDIR below its sandbox (export TMPDIR="$T/tmpd") keeps working when it names $T in OVN_SAFE_RM_ROOTS; without it the helpers refuse (fail closed)
  local base t sub rc1 rc2
  base="$(TMPDIR="$SB/root" lib safe_mktemp_dir narrow)" || return 1; mkdir -p "$base/tmpd"
  rc1="$(TMPDIR="$base/tmpd" lib safe_mktemp_dir_in "$base" sub >/dev/null 2>&1; echo $?)"
  sub="$(TMPDIR="$base/tmpd" OVN_SAFE_RM_ROOTS="$base" lib safe_mktemp_dir_in "$base" sub)" || return 1
  [ "$rc1" != 0 ] && [ -d "$sub" ] || return 1
  TMPDIR="$base/tmpd" OVN_SAFE_RM_ROOTS="$base" lib safe_rm_rf "$sub" || return 1          # strictly under the named root: removable
  [ ! -e "$sub" ] || return 1
  [ "$(TMPDIR="$base/tmpd" OVN_SAFE_RM_ROOTS="$base" lib safe_rm_rf "$base" >/dev/null 2>&1; echo $?)" != 0 ] && [ -d "$base" ] || return 1   # the named root ITSELF is never removable
  TMPDIR="$SB/root" lib safe_rm_rf "$base"; [ ! -e "$base" ]; }
t "C20 TMPDIR narrowed below the sandbox: refused by default, allowed once the sandbox root is named in OVN_SAFE_RM_ROOTS" c20

# 2026-10-17 (round-2 review of e5caef2): a TMPDIR that is not an allowed sandbox root must fail UP FRONT (the old behaviour: rc 0 + a dir that safe_set_sandbox_home / safe_rm_rf then refused = a leaked dir)
mkdir -p "$SB/mkshim"
printf '#!/bin/sh\nd="$(%s "$@")" || exit $?\necho "$d" >> "%s/mkshim/mk.log"\necho "$d"\n' "$(command -v mktemp)" "$SB" > "$SB/mkshim/mktemp"; chmod +x "$SB/mkshim/mktemp"
c21(){ # $1=TMPDIR value [$2=HOME]: safe_mktemp_dir fails closed, prints nothing, and leaves NO directory behind
  : > "$SB/mkshim/mk.log"
  local out rc dd
  out="$(env TMPDIR="$1" HOME="${2:-$HOME}" PATH="$SB/mkshim:$PATH" bash -c '. "$1"; safe_mktemp_dir x' _ "$HERE/lib_safe_tmp.sh" 2>/dev/null)"; rc=$?
  [ "$rc" != 0 ] && [ -z "$out" ] || return 1
  while IFS= read -r dd; do [ -n "$dd" ] && [ -e "$dd" ] && return 1; done < "$SB/mkshim/mk.log"
  return 0; }
t "C21 TMPDIR=/tmp: safe_mktemp_dir fails up front and leaks nothing" c21 /tmp
t "C21b TMPDIR=/tmp/ (trailing slash): same" c21 /tmp/
ln -s /tmp "$SB/tmplink"
t "C21c TMPDIR is a symlink to /tmp: same" c21 "$SB/tmplink"
mkdir -p "$SB/hh"
t "C21d TMPDIR == HOME: same" c21 "$SB/hh" "$SB/hh"
c21e(){ local d; d="$(TMPDIR="$SB/root" lib safe_mktemp_dir ok)" || return 1; [ -d "$d" ] && rmdir "$d"; }
t "C21e ...and a normal TMPDIR still works" c21e
c22(){ # safe_use_short_tmp: a long TMPDIR is replaced by a short private one; a short TMPDIR is left alone; sandboxes then live under it and are removable
  local long="$SB/root/$(printf 'x%.0s' $(seq 1 60))" r
  mkdir -p "$long"
  r="$(TMPDIR="$long" bash -c '. "$1"; safe_use_short_tmp || exit 1; printf "%s" "$TMPDIR"; d="$(safe_mktemp_dir t)" || exit 2; [ -d "$d" ] || exit 3; safe_rm_rf "$d" || exit 4; [ ! -e "$d" ] || exit 5' _ "$HERE/lib_safe_tmp.sh")" || return 1
  [ "${#r}" -le 48 ] && [ "${r#/tmp/ovn-s}" != "$r" ] || return 1
  [ "$(TMPDIR="$SB/root" bash -c '. "$1"; safe_use_short_tmp 4000; printf "%s" "$TMPDIR"' _ "$HERE/lib_safe_tmp.sh")" = "$SB/root" ]; }   # the threshold argument: a TMPDIR shorter than it is left alone
t "C22 safe_use_short_tmp shortens a deep TMPDIR (and only then); sandboxes under it are creatable and removable" c22

echo "== H: round-2 review bypasses (lint_bypass_cases.py: one scratch file per sample, linted by a separate process; FLAG samples must be reported, PASS samples clean)"
mkdir -p "$SB/hcases"
hout="$("$PY" -I "$HERE/lint_bypass_check.py" "$LINT" "$SB/hcases" 2>&1)"; hrc=$?
[ "$hrc" = 0 ] || echo "$hout" | head -20
t "H1 every bypass sample is flagged and every guarded sample passes: $(printf '%s' "$hout" | tail -1)" test "$hrc" = 0
t "H2 the case file really holds >= 100 FLAG and >= 10 PASS samples (it cannot be emptied silently)" "$PY" -I -c "import sys; sys.path.insert(0, '$HERE'); import lint_bypass_cases as c; sys.exit(0 if len(c.FLAG) >= 100 and len(c.PASS) >= 10 else 1)"
t "H3 the lint tree itself is still clean after the stricter rules (same run as A1)" test "$rc" = 0

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
