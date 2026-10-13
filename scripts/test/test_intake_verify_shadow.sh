#!/usr/bin/env bash
# Regression test: lib_verify_clause.sh shadow_check, intake package (2026-10-13).
#  B3  a GUT checkout without the godot import cache prints "Some GUT class_names have not been imported" and exits 0 having run NOTHING. The spec gate (a clean worktree) read that as PASS, so every
#      GUT item looked already satisfied. Now UNRUNNABLE (rc 127, indeterminate), marker GUT-not-imported in the log row. OVN_GUT_CLAUSE_NORMALIZE=off restores the old reading.
#  F4  the normaliser also runs for shapes that cannot run AT ALL: `cd /path/to/<repo> && godot ... gut_cmdln` (the cd never succeeds) and `cd tests && godot -s <GutTest>.gd` (not a SceneTree script).
# A fake `godot` (installed where the lib resolves it: $HOME/godot/godot4) stands in for the engine and logs its argv.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIBDIR="${OVN_LIB_DIR:-$HERE/..}"
[ -f "$LIBDIR/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
tmp="$(cd "$tmp" && pwd -P)"
mkdir -p "$tmp/home/godot" "$tmp/work/addons/gut" "$tmp/work/tests"
printf 'x' > "$tmp/work/addons/gut/gut_cmdln.gd"
printf 'extends GutTest\nfunc test_a():\n\tpass\n' > "$tmp/work/tests/test_a.gd"
cat > "$tmp/home/godot/godot4" <<'EOT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SHIM_ARGS:-/dev/null}"
case "${SHIM_MODE:-clean}" in
  notimported) echo "ERROR: Some GUT class_names have not been imported.  Please restart the Editor or run godot --headless --import"; echo 'Missing class_names:  ["GutTest"]'; exit 0 ;;
  *)           echo "Totals"; echo "  Scripts        1"; echo "  Tests          3"; echo "  Passing        3"; exit 0 ;;
esac
EOT
chmod +x "$tmp/home/godot/godot4"
run_sc(){  # $1 = item line -> RESULT|WHY|RC
  printf '%s\n' "$1" > "$tmp/prog.md"
  ( cd "$tmp/work" || exit 9
    export HOME="$tmp/home"
    PROG="$tmp/prog.md"; SHADOW_LOG="$tmp/shadow.log"; _REPO_LABEL=t; _VC_MEMO_ON=0; : > "$SHADOW_LOG"
    # shellcheck disable=SC1091
    . "$LIBDIR/lib_verify_clause.sh"
    shadow_check 1
    printf '%s|%s|%s\n' "$_LAST_VERIFY_RESULT" "${_LAST_VERIFY_WHY:-}" "${_LAST_VERIFY_RC:-}" )
}
item(){ printf '%s' "- [ ] [T2] tests/test_a.gd — add a test. VERIFY: \`$1\`. (cat:test)"; }
GUT='godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd'

echo "== B3: GUT that cannot import its class_names ran nothing"
r="$(SHIM_MODE=notimported run_sc "$(item "$GUT")")"
ok "not-imported -> UNRUNNABLE (was PASS)" "[ \"\${r%%|*}\" = UNRUNNABLE ]"
ok "the RAW rc recorded for the caller is 127 (spec_check prints it; 0 would read as passes-before)" "[ \"\${r##*|}\" = 127 ]"
ok "the log row carries the GUT-not-imported marker (the classifier reads it)" "grep -c 'GUT-not-imported' '$tmp/shadow.log' | grep -qx 1"
r="$(OVN_GUT_CLAUSE_NORMALIZE=off SHIM_MODE=notimported run_sc "$(item "$GUT")")"
ok "OVN_GUT_CLAUSE_NORMALIZE=off restores the old PASS" "[ \"\${r%%|*}\" = PASS ]"
r="$(SHIM_MODE=clean run_sc "$(item "$GUT")")"
ok "CONTROL: a clean GUT run still PASSes" "[ \"\${r%%|*}\" = PASS ]"
r="$(SHIM_MODE=notimported run_sc "$(item 'echo "Some GUT class_names have not been imported"')")"
ok "NEGATIVE: a non-GUT command printing the phrase is unaffected" "[ \"\${r%%|*}\" = PASS ]"

echo "== F4: shapes that cannot run at all are normalised before they run"
: > "$tmp/args.log"
r="$(SHIM_ARGS="$tmp/args.log" run_sc "$(item "cd /path/to/xlite && $GUT")")"
ok "placeholder cd + GUT runner -> PASS (the cd is dropped; was FAIL 'cd: No such file or directory')" "[ \"\${r%%|*}\" = PASS ]"
ok "... godot really ran with the res:// target" "grep -c -- '-gtest=res://tests/test_a.gd' '$tmp/args.log' | grep -qx 1"
r="$(OVN_GUT_CLAUSE_NORMALIZE=off run_sc "$(item "cd /path/to/xlite && $GUT")")"
ok "OVN_GUT_CLAUSE_NORMALIZE=off: the placeholder clause fails again (cd error)" "[ \"\${r%%|*}\" = FAIL ]"
: > "$tmp/args.log"
r="$(SHIM_ARGS="$tmp/args.log" run_sc "$(item 'cd tests && godot --headless -s test_a.gd')")"
ok "[mut] cd tests && godot -s test_a.gd runs through the GUT runner (argv has gut_cmdln and -gtest=res://tests/test_a.gd)" "grep -c 'gut_cmdln.gd' '$tmp/args.log' | grep -qx 1 && grep -c -- '-gtest=res://tests/test_a.gd' '$tmp/args.log' | grep -qx 1"
: > "$tmp/args.log"
OVN_GUT_CLAUSE_NORMALIZE=off SHIM_ARGS="$tmp/args.log" run_sc "$(item 'cd tests && godot --headless -s test_a.gd')" >/dev/null
ok "off: the clause is run as written (no gut_cmdln)" "[ \"\$(grep -c gut_cmdln '$tmp/args.log')\" = 0 ]"
: > "$tmp/args.log"
r="$(run_sc "$(item 'cd /path/to/xlite && echo placeholder-ok')")"
ok "a placeholder cd in a NON-GUT, non-godot clause is dropped too (PASS; the cd could never succeed)" "[ \"\${r%%|*}\" = PASS ]"
r="$(SHIM_ARGS="$tmp/args.log" run_sc "$(item 'cd /tmp && echo hi')")"
ok "NEGATIVE: an unrelated clause with a real cd is untouched" "[ \"\${r%%|*}\" = PASS ]"

echo "Intake verify shadow: $P passed, $F failed"
[ "$F" -eq 0 ]
