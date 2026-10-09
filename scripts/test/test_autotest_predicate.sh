#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 9): ovn_repo_has_autotest <dir> - does aider's in-loop --auto-test have something to run here?
# run_overnight.sh only enabled `--auto-test --test-cmd ovn_autotest.sh` for a pytest venv or a package.json; xlite has neither, so the Godot gate that
# ovn_autotest.sh implements (gdparse + godot --check-only) never ran in the loop and Godot-3-isms / parse errors were committed blind. The predicate now also
# accepts a Godot project (project.godot); OVN_GODOT_INLOOP_GATE=off restores the old two clauses.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; RUN="$S/../run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
# shellcheck disable=SC1090
. "$S/lib_autotest_base.sh"
set -o pipefail   # the runner's mode: the predicate must not use `find | grep -q`
mk(){ rm -rf "$W/$1"; mkdir -p "$W/$1"; }
mk godot; : > "$W/godot/project.godot"
mk empty
mk pkg; : > "$W/pkg/package.json"
mk venv; mkdir -p "$W/venv/backend/.venv/bin"; : > "$W/venv/backend/.venv/bin/pytest"
mk nm; mkdir -p "$W/nm/node_modules/foo"; : > "$W/nm/node_modules/foo/package.json"
mk addons; mkdir -p "$W/addons/addons/gut"; : > "$W/addons/addons/gut/project.godot"
mk deep; mkdir -p "$W/deep/a/b/c/d"; : > "$W/deep/a/b/c/d/project.godot"
mk sub; mkdir -p "$W/sub/game"; : > "$W/sub/game/project.godot"
mk godot_pkg; : > "$W/godot_pkg/project.godot"; : > "$W/godot_pkg/package.json"
ok "project.godot only => true (xlite shape)" "ovn_repo_has_autotest '$W/godot'"
ok "empty dir => false" "! ovn_repo_has_autotest '$W/empty'"
ok "package.json => true" "ovn_repo_has_autotest '$W/pkg'"
ok ".venv/bin/pytest (nested backend/) => true" "ovn_repo_has_autotest '$W/venv'"
ok "package.json only under node_modules => false" "! ovn_repo_has_autotest '$W/nm'"
ok "project.godot only under addons/ (a vendored plugin) => false" "! ovn_repo_has_autotest '$W/addons'"
ok "project.godot 5 levels deep => false (maxdepth 3)" "! ovn_repo_has_autotest '$W/deep'"
ok "project.godot in a subdirectory (game/project.godot) => true" "ovn_repo_has_autotest '$W/sub'"
ok "default dir argument is the current directory" "( cd '$W/godot' && ovn_repo_has_autotest )"
ok "a nonexistent directory => false, no error output" "[ -z \"\$(ovn_repo_has_autotest '$W/nope' 2>&1)\" ] && ! ovn_repo_has_autotest '$W/nope'"
# kill switch
ok "OVN_GODOT_INLOOP_GATE=off: project.godot only => false (the old predicate)" "! OVN_GODOT_INLOOP_GATE=off ovn_repo_has_autotest '$W/godot'"
ok "OVN_GODOT_INLOOP_GATE=off leaves the other clauses alone (package.json, pytest venv still true)" "OVN_GODOT_INLOOP_GATE=off ovn_repo_has_autotest '$W/pkg' && OVN_GODOT_INLOOP_GATE=off ovn_repo_has_autotest '$W/venv'"
ok "godot + package.json => true with the gate on or off" "ovn_repo_has_autotest '$W/godot_pkg' && OVN_GODOT_INLOOP_GATE=off ovn_repo_has_autotest '$W/godot_pkg'"
# stable under pipefail on repeated calls (no SIGPIPE race)
STABLE=1; for i in 1 2 3 4 5 6 7 8 9 10; do ovn_repo_has_autotest "$W/godot" || STABLE=0; done
ok "result is stable across 10 consecutive calls under pipefail" "[ $STABLE = 1 ]"
# wiring
ok "run_overnight.sh enables TEST_ARGS through ovn_repo_has_autotest (code line)" "[ \"\$(grep -c '^    if \\[ -f \"\$SCRIPT_DIR/scripts/ovn_autotest.sh\" \\] && ovn_repo_has_autotest \".\"; then' '$RUN')\" = 1 ]"
ok "the old inline find|grep -q predicate is gone from that if" "[ \"\$(grep -c 'ovn_autotest.sh\" \\] && { find' '$RUN')\" = 0 ]"
# MUTATION: without the Godot clause the xlite shape is false again
python3 - "$S/lib_autotest_base.sh" "$W/m_lib.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = '''  if [ "${OVN_GODOT_INLOOP_GATE:-on}" != off ]; then'''
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, '  if false; then'))
PY
ok "MUTATION: with the project.godot clause disabled the xlite shape is false (so the 'project.godot only => true' test would fail)" "( . '$W/m_lib.sh'; ! ovn_repo_has_autotest '$W/godot' )"
ok "MUTATION sanity: the unmutated lib says true for the same dir" "ovn_repo_has_autotest '$W/godot'"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
