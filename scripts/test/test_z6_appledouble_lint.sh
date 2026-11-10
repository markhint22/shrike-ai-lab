#!/usr/bin/env bash
# test_z6_appledouble_lint.sh - Z6 (2026-11-09): macOS AppleDouble sidecars (`._name.py`, binary junk written when a tar/cp crosses a non-HFS volume) made test_no_unsafe_rm red for 15 h
# ("._test_y2_fixes.py python file does not parse"). Every lint that walks the queue root / scripts/test and parses .py/.sh must skip `._*` files. Mutants (skip removed) must FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
PY="$(command -v python3.12 || command -v python3)"
T="$(safe_mktemp_dir z6ad)" || exit 1
trap 'safe_rm_rf "$T"' EXIT
P=0; F=0
ok() { if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
junk() { printf '\x00\x05\x16\x07\x00\x02\x00\x00Mac OS X        \x00\x02\x00\x00\x00\x09\x00\x00\x00\x32\xff\xfe\x80rm -rf "$HOME"\n(' > "$1"; }
mkdir -p "$T/clean/sub" "$T/clean/scripts/test"
printf '#!/usr/bin/env bash\necho hi\n' > "$T/clean/ok.sh"; printf 'x = 1\n' > "$T/clean/sub/ok.py"
for f in "$T/clean/._x.py" "$T/clean/._x.sh" "$T/clean/sub/._test_y2_fixes.py" "$T/clean/scripts/test/._test_q.py" "$T/clean/scripts/test/._test_q.sh"; do junk "$f"; done

echo "== lint_unsafe_rm.py"
"$PY" -I "$HERE/lint_unsafe_rm.py" "$T/clean" > "$T/o1.txt" 2>&1; rc=$?
ok "tree with ._*.py / ._*.sh AppleDouble junk lints clean (rc 0, 0 findings): $(tail -1 "$T/o1.txt")" "$([ $rc = 0 ] && echo 0 || echo 1)"
"$PY" -I "$HERE/lint_unsafe_rm.py" "$T/clean/sub/._test_y2_fixes.py" > "$T/o1b.txt" 2>&1
ok "an AppleDouble file passed explicitly is skipped too" "$([ $? = 0 ] && echo 0 || echo 1)"
mkdir -p "$T/real"; printf '#!/usr/bin/env bash\nrm -rf "$HOME"\n' > "$T/real/bad.sh"; junk "$T/real/._bad.sh"
"$PY" -I "$HERE/lint_unsafe_rm.py" "$T/real" > "$T/o1c.txt" 2>&1
ok "control: a REAL unsafe rm next to an AppleDouble file is still caught (rc 1)" "$([ $? = 1 ] && grep -q 'bad.sh' "$T/o1c.txt" && ! grep -q '\._bad' "$T/o1c.txt" && echo 0 || echo 1)"
sed -e 's/if f.startswith("._") or f.endswith(TEXT_SKIP_EXT)/if f.endswith(TEXT_SKIP_EXT)/' -e 's/^    if os.path.basename(p).startswith("._"):/    if False:/' "$HERE/lint_unsafe_rm.py" > "$T/lint_mut.py"
cmp -s "$T/lint_mut.py" "$HERE/lint_unsafe_rm.py" && ok "mutant built (anchors present)" 1
"$PY" -I "$T/lint_mut.py" "$T/clean" > "$T/o1d.txt" 2>&1
ok "MUTANT without the ._ skip FAILS on the AppleDouble tree (old behaviour: rc 1, 'does not parse')" "$([ $? = 1 ] && grep -q 'does not parse\|\._' "$T/o1d.txt" && echo 0 || echo 1)"

echo "== lint_ntfy_tests.py (scripts audit walk)"
"$PY" -I "$HERE/lint_ntfy_tests.py" "$T/clean" > "$T/o2.txt" 2>&1
ok "ntfy lint over the AppleDouble tree: no finding on ._ files" "$(grep -q '\._' "$T/o2.txt" && echo 1 || echo 0)"
mkdir -p "$T/nt"; bad_url="https://ntf""y.sh"; printf 'export NTFY_SERVER="${NTFY_SERVER:-%s}"\n' "$bad_url" > "$T/nt/._junk.sh"   # assembled at run time so this test file itself is not a lint finding
"$PY" -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import lint_ntfy_tests as L; sys.exit(0 if not L.lint_scripts(sys.argv[2]) else 1)' "$HERE" "$T/nt" 2>/dev/null
ok "lint_scripts skips an AppleDouble file even if its junk looks like a violation" "$([ $? = 0 ] && echo 0 || echo 1)"
sed 's/if fn.startswith("._") or not fn.endswith/if not fn.endswith/' "$HERE/lint_ntfy_tests.py" > "$T/nt_mut.py"
"$PY" -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import nt_mut as L; sys.exit(0 if not L.lint_scripts(sys.argv[2]) else 1)' "$T" "$T/nt" 2>/dev/null
ok "MUTANT without the ._ skip in lint_ntfy_tests FAILS (finding on the junk file)" "$([ $? = 1 ] && echo 0 || echo 1)"

echo "== ops/box_deploy.sh extraction drops AppleDouble entries"
BD="$HERE/../../ops/box_deploy.sh"
mkdir -p "$T/tarsrc" "$T/tarout"; echo real > "$T/tarsrc/real.sh"; junk "$T/tarsrc/._real.sh"
( cd "$T/tarsrc" && tar -cf "$T/d.tar" real.sh ._real.sh )
ln=$(grep -n 'tar -xf "\$TAR" -C "\$STAGE"' "$BD" | head -1 | cut -d: -f2-)
ok "box_deploy.sh --tar extraction carries --exclude='._*' (line: $(printf '%s' "$ln" | cut -c1-70))" "$(printf '%s' "$ln" | grep -q -- "--exclude='._\*'" && echo 0 || echo 1)"
tar -xf "$T/d.tar" -C "$T/tarout" --exclude='._*'
ok "that tar invocation extracts real.sh and NOT ._real.sh" "$([ -f "$T/tarout/real.sh" ] && [ ! -e "$T/tarout/._real.sh" ] && echo 0 || echo 1)"
sed "s|tar -xf \"\$TAR\" -C \"\$STAGE\" --exclude='._\*'|tar -xf \"\$TAR\" -C \"\$STAGE\"|" "$BD" > "$T/bd_mut.sh"
ln2=$(grep -n 'tar -xf "\$TAR" -C "\$STAGE"' "$T/bd_mut.sh" | head -1)
ok "MUTANT box_deploy without the exclude FAILS the anchor check (old behaviour)" "$(printf '%s' "$ln2" | grep -q -- "--exclude" && echo 1 || echo 0)"

echo; echo "z6_appledouble_lint: $P passed, $F failed"
[ "$F" -eq 0 ]
