#!/usr/bin/env bash
# Regression test: lib_verify_clause.sh shadow_check (spec-compiler-v2 part B, 2026-10-09).
#  B1  GUT with a missing -gtest target prints "[ERROR]: Could not find script", then runs the WHOLE suite (391 scripts, 2987 tests) and exits 0. shadow_check
#      returned PASS, so every xlite 'create test file X' item looked already satisfied. Now FAIL / WHY "GUT target missing". OVN_GUT_MISSING_TARGET=ignore restores it.
#  B2  pytest `file::name` that exits rc=4 (a class-based test is only addressable as file::Class::name) is retried once as `file -k name`;
#      rc 5 / "no tests ran" is a FAIL with WHY "no tests collected". OVN_VERIFY_NODEID_FALLBACK=off disables the retry.
# A fake `godot` (installed where the lib resolves it: $HOME/godot/godot4) stands in for the engine.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIBDIR="${OVN_LIB_DIR:-$HERE/..}"
[ -f "$LIBDIR/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
# assertions are evaluated with pipefail OFF (under pipefail `A | grep -q X` is flaky: grep -q exits at its first hit and A may take SIGPIPE)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"   # /private/var vs /var on macOS
mkdir -p "$tmp/home/godot" "$tmp/work"

# --- the fake engine: behaviour picked by SHIM_MODE, argv logged so the -gexit append can be asserted
cat > "$tmp/home/godot/godot4" <<'EOT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SHIM_ARGS:-/dev/null}"
case "${SHIM_MODE:-clean}" in
  missing) echo "[ERROR]: Could not find script res://tests/test_missing.gd"; echo "Totals"; echo "  Scripts        391"; echo "  Passing Tests  2987"; exit 0 ;;
  fail)    echo "Totals"; printf '  Failing         1\n'; exit 0 ;;
  *)       echo "Totals"; echo "  Scripts        1"; echo "  Passing Tests  3"; exit 0 ;;
esac
EOT
chmod +x "$tmp/home/godot/godot4"

# run shadow_check on one item line in a clean subshell; prints RESULT|WHY|RC
run_sc(){  # $1 = lib dir, $2 = item line
  printf '%s\n' "$2" > "$tmp/prog.md"
  ( cd "$tmp/work" || exit 9
    export HOME="${RUN_HOME:-$tmp/home}"   # B2 runs with the real HOME (asdf-style pytest shims resolve through it); GUT runs need the shim home
    PROG="$tmp/prog.md"; SHADOW_LOG="$tmp/shadow.log"; _REPO_LABEL=t; _VC_MEMO_ON=0; : > "$SHADOW_LOG"
    # shellcheck disable=SC1091
    . "$1/lib_verify_clause.sh"
    shadow_check 1
    printf '%s|%s|%s\n' "$_LAST_VERIFY_RESULT" "${_LAST_VERIFY_WHY:-}" "${_LAST_VERIFY_RC:-}" )
}
GUT_ITEM='- [ ] [T2] tests/test_missing.gd — create the test. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_missing.gd`. (cat:test)'

echo "== B1: GUT missing target"
r="$(SHIM_MODE=missing run_sc "$LIBDIR" "$GUT_ITEM")"
ok "missing target -> FAIL (was PASS)" "[ \"\${r%%|*}\" = FAIL ]"
ok "WHY says 'GUT target missing'" "printf '%s' '$r' | grep -c 'GUT target missing' | grep -qx 1"
ok "the shadow log row carries the GUT-target-missing marker (the classifier reads it)" "grep -c 'GUT-target-missing' '$tmp/shadow.log' | grep -qx 1"
r="$(OVN_GUT_MISSING_TARGET=ignore SHIM_MODE=missing run_sc "$LIBDIR" "$GUT_ITEM")"
ok "OVN_GUT_MISSING_TARGET=ignore restores the old PASS" "[ \"\${r%%|*}\" = PASS ]"
r="$(OVN_GUT_MISSING_TARGET=fail SHIM_MODE=missing run_sc "$LIBDIR" "$GUT_ITEM")"
ok "OVN_GUT_MISSING_TARGET=fail (explicit) FAIL" "[ \"\${r%%|*}\" = FAIL ]"
r="$(SHIM_MODE=clean run_sc "$LIBDIR" "$GUT_ITEM")"
ok "CONTROL: a clean GUT run still PASSes" "[ \"\${r%%|*}\" = PASS ]"
r="$(SHIM_MODE=fail run_sc "$LIBDIR" "$GUT_ITEM")"
ok "CONTROL: GUT-reported failures (exit 0 + 'Failing 1') still FAIL" "[ \"\${r%%|*}\" = FAIL ]"
: > "$tmp/args.log"
SHIM_ARGS="$tmp/args.log" SHIM_MODE=missing run_sc "$LIBDIR" "$GUT_ITEM" >/dev/null
ok "-gexit is still appended to the gut_cmdln clause" "grep -c -- '-gexit' '$tmp/args.log' | grep -qx 1"
r="$(run_sc "$LIBDIR" '- [ ] [T2] x.py — echo. VERIFY: `echo "Could not find script"`. (cat:test)')"
ok "NEGATIVE: a non-GUT command that merely prints the phrase is unaffected (PASS)" "[ \"\${r%%|*}\" = PASS ]"
# B1b (review defect): a -gdir that names a directory/file that does not exist is the same vacuous-pass class (GUT exits 0)
mkdir -p "$tmp/work/test/battle"
GDIR_ITEM='- [ ] [T2] test/battle/test_overwatch.gd — create the test. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle/test_overwatch.gd`. (cat:test)'
r="$(SHIM_MODE=clean run_sc "$LIBDIR" "$GDIR_ITEM")"
ok "-gdir naming a nonexistent file -> FAIL even though godot exits 0 (was PASS)" "[ \"\${r%%|*}\" = FAIL ]"
ok "... WHY 'GUT target missing'" "printf '%s' '$r' | grep -c 'GUT target missing' | grep -qx 1"
r="$(OVN_GUT_MISSING_TARGET=ignore SHIM_MODE=clean run_sc "$LIBDIR" "$GDIR_ITEM")"
ok "OVN_GUT_MISSING_TARGET=ignore restores the old PASS for -gdir too" "[ \"\${r%%|*}\" = PASS ]"
r="$(SHIM_MODE=clean run_sc "$LIBDIR" '- [ ] [T2] x — t. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle`. (cat:test)')"
ok "CONTROL: -gdir naming an existing directory PASSes" "[ \"\${r%%|*}\" = PASS ]"
r="$(SHIM_MODE=clean run_sc "$LIBDIR" '- [ ] [T2] x — t. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle,res://test/nope_test.gd`. (cat:test)')"
ok "a comma list with one missing .gd entry -> FAIL" "[ \"\${r%%|*}\" = FAIL ]"
r="$(SHIM_MODE=clean run_sc "$LIBDIR" '- [ ] [T2] x — t. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests_not_created_yet`. (cat:test)')"
ok "NEGATIVE (documented limit): a plain nonexistent DIRECTORY is not flagged (test_run_integrity_lib fixtures rely on it)" "[ \"\${r%%|*}\" = PASS ]"
: > "$tmp/work/test/battle/test_exists.gd"
r="$(SHIM_MODE=clean run_sc "$LIBDIR" '- [ ] [T2] x — t. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://test/battle/test_exists.gd`. (cat:test)')"
ok "NEGATIVE: a -gdir .gd path that exists is not flagged" "[ \"\${r%%|*}\" = PASS ]"
# mutation: break the detection in a copy of the library; the missing-target scenario must flip back to PASS (i.e. this test would catch the regression)
mkdir -p "$tmp/mut"; cp "$LIBDIR"/lib_*.sh "$tmp/mut/"
sed -i.bak "s/Could not find script' <<</Could not find scriptXX' <<</" "$tmp/mut/lib_verify_clause.sh"
r="$(SHIM_MODE=missing run_sc "$tmp/mut" "$GUT_ITEM")"
ok "MUTATION (detection phrase broken): the shim fixture reads PASS again, so the FAIL assertion above is load-bearing" "[ \"\${r%%|*}\" = PASS ]"

echo "== B2: pytest node ids"
PYT="${OVN_TEST_PYTEST:-$(command -v pytest 2>/dev/null || true)}"   # a pytest executable; OVN_TEST_PYTEST overrides (the box has none on PATH)
if [ -z "$PYT" ] || ! "$PYT" --version >/dev/null 2>&1; then
  echo "  SKIP B2: no runnable pytest executable (set OVN_TEST_PYTEST)"
else
  RUN_HOME="$HOME"
  mkdir -p "$tmp/work/tests"
  cat > "$tmp/work/tests/test_cls.py" <<'EOT'
class TestThing:
    def test_alpha(self):
        assert 1

    def test_beta(self):
        assert 1
EOT
  printf 'def test_gamma():\n    assert 1\n' > "$tmp/work/tests/test_fn.py"
  item(){ printf '%s' "- [ ] [T2] tests/x.py — a thing. VERIFY: \`$1\`. (cat:test)"; }   # $1 may reference $PYT (expanded by the caller's double quotes)
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_cls.py::test_alpha -q")")"
  ok "class-based test addressed as file::name (rc 4) is retried with -k and PASSes" "[ \"\${r%%|*}\" = PASS ]"
  r="$(OVN_VERIFY_NODEID_FALLBACK=off run_sc "$LIBDIR" "$(item "$PYT tests/test_cls.py::test_alpha -q")")"
  ok "OVN_VERIFY_NODEID_FALLBACK=off: no retry, FAIL with rc 4" "[ \"\${r%%|*}\" = FAIL ] && [ \"\${r##*|}\" = 4 ]"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_cls.py::test_nope -q")")"
  ok "NEGATIVE: nonexistent name -> retry collects nothing -> FAIL" "[ \"\${r%%|*}\" = FAIL ]"
  ok "... with WHY 'no tests collected'" "printf '%s' '$r' | grep -c 'no tests collected' | grep -qx 1"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_cls.py::TestThing::test_beta -q")")"
  ok "full Class::name node id resolves directly (PASS, no retry needed)" "[ \"\${r%%|*}\" = PASS ]"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_cls.py::Missing::test_beta -q")")"
  ok "NEGATIVE: wrong class in Class::name -> FAIL" "[ \"\${r%%|*}\" = FAIL ]"
  # review defect (spec-compiler-v2 fixer): the retry must be an EXACT-name match, never a -k substring match
  printf 'def test_foo_bar():\n    assert 1\n' > "$tmp/work/tests/test_sub.py"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_sub.py::test_foo -q")")"
  ok "SUBSTRING: file has only test_foo_bar, VERIFY names test_foo -> FAIL (was a false PASS via -k test_foo)" "[ \"\${r%%|*}\" = FAIL ] && [ \"\${r##*|}\" = 4 ]"
  ok "... with WHY 'no tests collected'" "printf '%s' '$r' | grep -c 'no tests collected' | grep -qx 1"
  r="$(OVN_VERIFY_NODEID_FALLBACK=off run_sc "$LIBDIR" "$(item "$PYT tests/test_sub.py::test_foo -q")")"
  ok "SUBSTRING control: fallback off also FAILs rc 4 (same verdict as the fixed fallback)" "[ \"\${r%%|*}\" = FAIL ] && [ \"\${r##*|}\" = 4 ]"
  printf 'class TestSub:\n    def test_foo_bar(self):\n        assert 1\n    def test_foo(self):\n        assert 1\n' > "$tmp/work/tests/test_sub2.py"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_sub2.py::test_foo -q")")"
  ok "EXACT name present next to a longer sibling (class based) -> PASS" "[ \"\${r%%|*}\" = PASS ]"
  printf 'class TestSub:\n    def test_foo_bar(self):\n        assert 0\n    def test_foo(self):\n        assert 1\n' > "$tmp/work/tests/test_sub3.py"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_sub3.py::test_foo -q")")"
  ok "the retry runs ONLY the exactly named test (a failing longer sibling does not leak in)" "[ \"\${r%%|*}\" = PASS ]"
  printf 'import pytest\nclass TestP:\n    @pytest.mark.parametrize("x", [1, 2])\n    def test_par(self, x):\n        assert x\n' > "$tmp/work/tests/test_par.py"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_par.py::test_par -q")")"
  ok "parametrized class test resolves by its base name -> PASS" "[ \"\${r%%|*}\" = PASS ]"
  # bash 3.2 portability of the id rewrite (review defect: ${c/\"$tok\"/...} left literal quotes on macOS /bin/bash)
  fb="$(cd "$tmp/work" && bash -c ". '$LIBDIR/lib_verify_clause.sh'; _verify_nodeid_fallback_cmd '$PYT tests/test_cls.py::test_alpha -q' 60" 2>/dev/null)"
  ok "fallback command text has the qualified id and no stray quote characters" "[ \"\$fb\" = \"$PYT tests/test_cls.py::TestThing::test_alpha -q\" ]"
  if [ -x /bin/bash ] && /bin/bash -c '[ "${BASH_VERSINFO[0]}" -le 3 ]' 2>/dev/null; then
    fb32="$(cd "$tmp/work" && /bin/bash -c ". '$LIBDIR/lib_verify_clause.sh'; _verify_nodeid_fallback_cmd '$PYT tests/test_cls.py::test_alpha -q' 60" 2>/dev/null)"
    ok "same under the system bash 3.2" "[ \"\$fb32\" = \"$PYT tests/test_cls.py::TestThing::test_alpha -q\" ]"
  fi
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_fn.py::test_gamma -q")")"
  ok "CONTROL: a plain function node id PASSes" "[ \"\${r%%|*}\" = PASS ]"
  r="$(run_sc "$LIBDIR" "$(item "$PYT tests/test_fn.py -k nothing_matches -q")")"
  ok "rc 5 (-k selects nothing) is FAIL with WHY 'no tests collected'" "[ \"\${r%%|*}\" = FAIL ] && printf '%s' '$r' | grep -c 'no tests collected' | grep -qx 1"
  r="$(OVN_VERIFY_NODEID_FALLBACK=off run_sc "$LIBDIR" "$(item "$PYT tests/test_fn.py -k gamma -q")")"
  ok "CONTROL: -k that selects a test PASSes" "[ \"\${r%%|*}\" = PASS ]"
  # mutation: without the retry the class-based id cannot pass; breaking the retry in a library copy flips the first assertion
  cp "$LIBDIR/lib_verify_clause.sh" "$tmp/mut/lib_verify_clause.sh"
  sed -i.bak 's/-eq 4 \]/-eq 44 ]/' "$tmp/mut/lib_verify_clause.sh"
  r="$(run_sc "$tmp/mut" "$(item "$PYT tests/test_cls.py::test_alpha -q")")"
  ok "MUTATION (retry condition broken): the class-based id FAILs, so the PASS assertion above is load-bearing" "[ \"\${r%%|*}\" = FAIL ]"
  # mutation: the old -k substring fallback restored in a library copy must false-PASS the SUBSTRING fixture (so the fix is load-bearing)
  cp "$LIBDIR/lib_verify_clause.sh" "$tmp/mut/lib_verify_clause.sh"
  python3 - "$tmp/mut/lib_verify_clause.sh" <<'PYEOF'
import re, sys
p = sys.argv[1]
s = open(p).read()
a = s.index("_verify_nodeid_fallback_cmd(){")
b = s.index("# 0 (true) when GUT output reports failures.")
old = '_verify_nodeid_fallback_cmd(){\n  local c="$1" tok path name\n  _verify_is_pytest "$c" || return 0\n  tok="$(printf \'%s\' "$c" | grep -oE \'[A-Za-z0-9_./-]+\\.py::[A-Za-z0-9_:.-]+\' | head -1)"\n  [ -n "$tok" ] || return 0\n  path="${tok%%::*}"; name="${tok#*::}"\n  printf \'%s\' "$path -k $name"\n}\n'
open(p, "w").write(s[:a] + old.replace("$path -k $name", "$(printf '%s' \"$c\" | sed -E \"s#$tok#$path -k $name#\")") + s[b:])
PYEOF
  r="$(run_sc "$tmp/mut" "$(item "$PYT tests/test_sub.py::test_foo -q")")"
  ok "MUTATION (old -k substring retry restored): test_foo vs test_foo_bar false-PASSes, so the SUBSTRING assertion above is load-bearing" "[ \"\${r%%|*}\" = PASS ]"
fi

echo; echo "gut missing target / node ids: $P passed, $F failed"
[ "$F" = 0 ]
