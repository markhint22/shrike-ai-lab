#!/usr/bin/env bash
# Runs the REAL scripts/ovn_autotest.sh (aider --test-cmd, scoped) against throwaway git repos with stub gdparse/gdlint/godot,
# npx/npm (vitest, tsc) and .venv/bin/pytest. Covers: no-change exit, GDScript syntax/API/lint layers, web scoped vitest
# (specs vs related sources, nearest package.json, unprovisioned packages), scoped type-check (vue-tsc / npm type-check /
# tsc, own-file vs pre-existing errors, OVN_TSC_MIDCYCLE=0), and the pytest backend path with the OVN_GATE_STRICT
# "test must exercise the change" gate, sibling-test discovery, nested venv, full-suite fallback, exit-code propagation.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AT=""
for c in "$HERE/../ovn_autotest.sh" "$HERE/../../scripts/ovn_autotest.sh" "$HERE/ovn_autotest.sh"; do [ -f "$c" ] && { AT="$c"; break; }; done
[ -n "$AT" ] || { echo "  SKIP: ovn_autotest.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
has(){ printf '%s' "$OUT" | grep -qF -- "$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; BIN="$T/bin"; mkdir -p "$H/aider-venv/bin" "$H/godot" "$BIN"
export NPX_LOG="$T/npx.log"
# ---- stubs ----
cat > "$BIN/npx" <<'EOF'
#!/usr/bin/env bash
echo "npx $*" >> "$NPX_LOG"
if [ "$1" = "--no-install" ]; then printf '%s\n' "${TSC_OUT:-}"; exit 0; fi
echo "vitest-stub $*"; exit "${NPX_RC:-0}"
EOF
cat > "$BIN/npm" <<'EOF'
#!/usr/bin/env bash
echo "npm $*" >> "$NPX_LOG"; printf '%s\n' "${TSC_OUT:-}"; exit 0
EOF
chmod +x "$BIN/npx" "$BIN/npm"
gdtools(){ # $1 gdparse(pass|fail|none) $2 godot(clean|err|none) $3 gdlint(quiet|warn|none)
  rm -f "$H/aider-venv/bin/gdparse" "$H/aider-venv/bin/gdlint" "$H/godot/godot4"
  case "$1" in pass) printf '#!/usr/bin/env bash\nexit 0\n' > "$H/aider-venv/bin/gdparse";; fail) printf '#!/usr/bin/env bash\necho "Unexpected token export var" >&2\nexit 1\n' > "$H/aider-venv/bin/gdparse";; esac
  case "$2" in clean) printf '#!/usr/bin/env bash\necho fine\nexit 0\n' > "$H/godot/godot4";; err) printf '#!/usr/bin/env bash\necho "SCRIPT ERROR: Parse Error: bad thing"\nexit 0\n' > "$H/godot/godot4";; esac
  case "$3" in quiet) printf '#!/usr/bin/env bash\nexit 0\n' > "$H/aider-venv/bin/gdlint";; warn) printf '#!/usr/bin/env bash\necho "player.gd:3: Warning: naming"\nexit 0\n' > "$H/aider-venv/bin/gdlint";; esac
  chmod +x "$H/aider-venv/bin/"* "$H/godot/"* 2>/dev/null; return 0
}
newrepo(){ # $1=name ; empty committed repo
  rm -rf "$T/$1"; mkdir -p "$T/$1"; ( cd "$T/$1" && git init -q && git config user.email t@t && git config user.name t && echo base > README.md && git add -A && git commit -q -m base ); R="$T/$1"
}
at(){ OUT="$(cd "$T" && HOME="$H" PATH="$BIN:$PATH" env "$@" bash "$AT" "$R" 2>&1)"; RC=$?; }
atc(){ OUT="$(cd "$R" && HOME="$H" PATH="$BIN:$PATH" bash "$AT" 2>&1)"; RC=$?; }  # default root "."
pystub(){ mkdir -p "$1/.venv/bin"; printf '#!/usr/bin/env bash\necho "pytest-stub $*"\nexit "${PYTEST_RC:-0}"\n' > "$1/.venv/bin/pytest"; chmod +x "$1/.venv/bin/pytest"; }

# ---- root handling / no change ----
OUT="$(HOME="$H" bash "$AT" "$T/does-not-exist" 2>&1)"; RC=$?
ok "unreachable root -> exit 0 silently" "$([ "$RC" = 0 ] && [ -z "$OUT" ] && echo 1 || echo 0)"
newrepo clean; atc
ok "no changed files -> exit 0 (default root '.')" "$([ "$RC" = 0 ] && [ -z "$OUT" ] && echo 1 || echo 0)"

# ---- GDScript ----
newrepo gd1; echo 'extends Node' > "$R/player.gd"; mkdir -p "$R/addons/x"; echo 'x' > "$R/addons/x/lib.gd"; gdtools fail clean warn
at
ok "gdparse failure -> exit 1 with [SYNTAX] report" "$([ "$RC" = 1 ] && [ "$(has '[SYNTAX] player.gd is not valid Godot 4 GDScript')" = 1 ] && [ "$(has 'GODOT 4 VALIDATION FAILED')" = 1 ] && echo 1 || echo 0)"
# (under the coverage harness the stub's stderr is discarded by cov_env.sh's `exec ... 2>/dev/null`, so only assert outside it)
ok "gdparse error text echoed" "$({ [ "$(has 'Unexpected token export var')" = 1 ] || [ -n "${OVN_COV_DIR:-}" ]; } && echo 1 || echo 0)"
ok "addons/ .gd files are never validated" "$(printf '%s' "$OUT" | grep -q 'addons' && echo 0 || echo 1)"
touch "$R/project.godot"; gdtools pass err warn
at
ok "project.godot present + engine Parse Error -> [API] failure" "$([ "$RC" = 1 ] && [ "$(has '[API] player.gd has Godot-4 semantic errors')" = 1 ] && echo 1 || echo 0)"
gdtools pass clean warn
at
ok "clean gd + lint warning -> exit 0, advisory printed" "$([ "$RC" = 0 ] && [ "$(has '[lint-advisory] player.gd:')" = 1 ] && echo 1 || echo 0)"
gdtools pass clean quiet
at
ok "clean gd, quiet lint -> exit 0, no output" "$([ "$RC" = 0 ] && [ -z "$OUT" ] && echo 1 || echo 0)"
gdtools none none none
at
ok "no gd tooling installed -> exit 0 (layers skipped)" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
# .gd listed but deleted on disk
newrepo gd2; echo 'extends Node' > "$R/gone.gd"; ( cd "$R" && git add -A && git commit -q -m g && rm gone.gd ); gdtools pass clean quiet
at
ok "deleted .gd (in diff, not on disk) is skipped" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
# gd + ts in one change: gd validated, then falls through to web section
newrepo gd3; mkdir -p "$R/web/src"; echo '{"devDependencies":{"vitest":"1"}}' > "$R/web/package.json"; echo 'x' > "$R/web/src/a.ts"; echo 'extends Node' > "$R/m.gd"; gdtools pass clean warn
at OVN_TSC_MIDCYCLE=0
ok "gd + ts change: gd passes then vitest related runs" "$([ "$(has 'vitest-stub vitest related src/a.ts --run')" = 1 ] && echo 1 || echo 0)"

# ---- WEB (vitest) ----
newrepo w1; gdtools none none none
mkdir -p "$R/web/src" "$R/web/node_modules/vitest" "$R/other/src"
echo '{"name":"web"}' > "$R/web/package.json"; echo 'x' > "$R/web/src/util.ts"; echo 't' > "$R/web/src/util.test.ts"
echo 'x' > "$R/other/src/orphan.ts"            # no package.json anywhere above
: > "$NPX_LOG"; at OVN_TSC_MIDCYCLE=0
ok "web: changed spec -> 'vitest run <spec>' (specs take precedence over sources)" "$([ "$(has 'vitest-stub vitest run src/util.test.ts')" = 1 ] && echo 1 || echo 0)"
ok "web: source without package.json ignored; vitest detected via node_modules/vitest" "$(grep -q orphan "$NPX_LOG" && echo 0 || echo 1)"
rm "$R/web/src/util.test.ts"; ( cd "$R" && git add -A && git commit -q -m x && echo y >> web/src/util.ts ) >/dev/null
: > "$NPX_LOG"; at OVN_TSC_MIDCYCLE=0
ok "web: source only -> 'vitest related'" "$([ "$(has 'vitest-stub vitest related src/util.ts --run')" = 1 ] && echo 1 || echo 0)"
NPX_RC=1 at OVN_TSC_MIDCYCLE=0 NPX_RC=1
ok "web: vitest failure exit code propagates through the pipe" "$([ "$RC" = 1 ] && echo 1 || echo 0)"
NPX_RC=0

# root-level package.json (rel == f, pd == ".")
newrepo w2; echo '{"devDependencies":{"vitest":"1"}}' > "$R/package.json"; echo a > "$R/index.ts"; echo b > "$R/index.spec.ts"
at OVN_TSC_MIDCYCLE=0
ok "web: root package.json handled (pd='.')" "$([ "$(has 'vitest-stub vitest run index.spec.ts')" = 1 ] && echo 1 || echo 0)"
# package.json without vitest and no node_modules -> not a web target, falls to backend (none) -> exit 0
newrepo w3; mkdir -p "$R/web"; echo '{"name":"x"}' > "$R/web/package.json"; echo a > "$R/web/a.ts"
: > "$NPX_LOG"; at OVN_TSC_MIDCYCLE=0
ok "web: package without vitest is skipped -> exit 0, vitest never run" "$([ "$RC" = 0 ] && ! grep -q vitest "$NPX_LOG" && echo 1 || echo 0)"

# ---- scoped type check ----
newrepo tc1; mkdir -p "$R/web/src" "$R/web/node_modules/.bin"; echo '{"devDependencies":{"vitest":"1"}}' > "$R/web/package.json"; echo a > "$R/web/src/mine.ts"; echo b > "$R/web/src/other.ts"
printf '#!/usr/bin/env bash\n' > "$R/web/node_modules/.bin/vue-tsc"; chmod +x "$R/web/node_modules/.bin/vue-tsc"
( cd "$R" && git add -A && git commit -q -m base ); echo c >> "$R/web/src/mine.ts"
at TSC_OUT="src/mine.ts(3,1): error TS2322: bad type
src/other.ts(9,9): error TS2304: pre-existing"
ok "tsc: error in a file I edited -> exit 1 with TYPE ERRORS" "$([ "$RC" = 1 ] && [ "$(has 'TYPE ERRORS in files you just edited')" = 1 ] && [ "$(has 'src/mine.ts(3,1)')" = 1 ] && echo 1 || echo 0)"
ok "tsc: pre-existing error in an untouched file is NOT reported" "$(printf '%s' "$OUT" | grep -q 'other.ts' && echo 0 || echo 1)"
: > "$NPX_LOG"; at TSC_OUT="src/other.ts(9,9): error TS2304: pre-existing"
ok "tsc: only foreign errors -> proceeds to vitest (vue-tsc preferred)" "$([ "$(has 'vitest-stub vitest related src/mine.ts --run')" = 1 ] && grep -q 'npx --no-install vue-tsc --noEmit' "$NPX_LOG" && echo 1 || echo 0)"
at OVN_TSC_MIDCYCLE=0 TSC_OUT="src/mine.ts(1,1): error TS1: x"
ok "OVN_TSC_MIDCYCLE=0 disables the scoped type check" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
# tsc with a type-check script
rm "$R/web/node_modules/.bin/vue-tsc"; printf '#!/usr/bin/env bash\n' > "$R/web/node_modules/.bin/tsc"; chmod +x "$R/web/node_modules/.bin/tsc"
echo '{"scripts":{"type-check":"tsc"},"devDependencies":{"vitest":"1"}}' > "$R/web/package.json"
: > "$NPX_LOG"; at TSC_OUT="src/mine.ts(3,1): error TS2322: bad"
ok "tsc with a package.json type-check script uses 'npm run --silent type-check'" "$([ "$RC" = 1 ] && grep -q 'npm run --silent type-check' "$NPX_LOG" && echo 1 || echo 0)"
# plain tsc
echo '{"devDependencies":{"vitest":"1"}}' > "$R/web/package.json"
: > "$NPX_LOG"; at TSC_OUT=""
ok "tsc without type-check script uses 'npx --no-install tsc --noEmit'" "$(grep -q 'npx --no-install tsc --noEmit' "$NPX_LOG" && echo 1 || echo 0)"

# ---- BACKEND (pytest) ----
newrepo b1; pystub "$R"; mkdir -p "$R/app" "$R/tests"; echo 'def f(): pass' > "$R/app/widget.py"; echo 'from app.widget import f' > "$R/tests/test_widget.py"; echo 'def other(): pass' > "$R/app/gadget.py"
( cd "$R" && git add -A && git commit -q -m base )
echo 'def f(): return 1' > "$R/app/widget.py"
at
ok "backend: source change -> sibling test_<module>.py is discovered and run with -x --no-cov" "$([ "$RC" = 0 ] && [ "$(has 'pytest-stub -q --no-cov -x tests/test_widget.py')" = 1 ] && echo 1 || echo 0)"
( cd "$R" && git checkout -q -- . ); echo 'def g(): return 1' > "$R/app/gadget.py"
at
ok "backend: source with no test file -> full suite fallback" "$([ "$(has 'pytest-stub -q --no-cov -x')" = 1 ] && [ "$(has 'tests/')" = 0 ] && echo 1 || echo 0)"
( cd "$R" && git checkout -q -- . )
# strict gate: new test that doesn't exercise the change
echo 'def f(): return 2' > "$R/app/widget.py"; echo 'def test_nothing(): assert True' > "$R/tests/test_new.py"
at
ok "strict gate: test that never touches the changed module -> exit 1 + guidance" "$([ "$RC" = 1 ] && [ "$(has 'TEST DOES NOT EXERCISE YOUR CHANGE')" = 1 ] && [ "$(has 'widget')" = 1 ] && echo 1 || echo 0)"
at OVN_GATE_STRICT=0
ok "OVN_GATE_STRICT=0 disables the exercise gate and the sibling-test expansion" "$([ "$RC" = 0 ] && [ "$(has 'pytest-stub -q --no-cov -x tests/test_new.py')" = 1 ] && echo 1 || echo 0)"
echo 'from app.widget import f
def test_it(): assert f() == 2' > "$R/tests/test_new.py"
at
ok "strict gate passes when the test names the changed module (and sibling test added)" "$([ "$RC" = 0 ] && [ "$(has 'tests/test_new.py tests/test_widget.py')" = 1 ] && echo 1 || echo 0)"
echo 'def test_api(client): assert client.get("/x").status_code == 200' > "$R/tests/test_new.py"
at
ok "strict gate passes for endpoint tests driven via client.get(...)" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
PYTEST_RC=1 at PYTEST_RC=1
ok "pytest failure exit code propagates through the tail pipe" "$([ "$RC" = 1 ] && echo 1 || echo 0)"
PYTEST_RC=0
# only a test file changed (no src mods) -> just the test
( cd "$R" && git checkout -q -- . && git clean -qfd ); echo '# tweak' >> "$R/tests/test_widget.py"
at
ok "only a test file changed: runs just that test" "$([ "$(has 'pytest-stub -q --no-cov -x tests/test_widget.py')" = 1 ] && echo 1 || echo 0)"
# non-python change with a pytest venv present -> empty runset -> full suite
( cd "$R" && git checkout -q -- . ); echo x >> "$R/README.md"
at
ok "non-python change + pytest venv: empty runset -> full -x suite" "$([ "$(has 'pytest-stub -q --no-cov -x')" = 1 ] && echo 1 || echo 0)"
# nested venv: paths relative to the pytest dir
newrepo b2; pystub "$R/backend"; mkdir -p "$R/backend/app" "$R/backend/tests"; echo 'def f(): pass' > "$R/backend/app/svc.py"; echo 'from app.svc import f' > "$R/backend/tests/test_svc.py"
( cd "$R" && git add -A && git commit -q -m base ); echo '# c' >> "$R/backend/app/svc.py"; echo '# c' >> "$R/backend/tests/test_svc.py"
at
ok "nested backend/.venv: changed paths made relative to it, test+module exercised" "$([ "$RC" = 0 ] && [ "$(has 'pytest-stub -q --no-cov -x tests/test_svc.py')" = 1 ] && echo 1 || echo 0)"
# python change deleted on disk + untracked non-.py
newrepo b3; pystub "$R"; echo 'x=1' > "$R/mod.py"; ( cd "$R" && git add -A && git commit -q -m b && rm mod.py ); echo data > "$R/notes.txt"
at
ok "deleted .py skipped; non-.py ignored -> full suite" "$([ "$(has 'pytest-stub -q --no-cov -x')" = 1 ] && echo 1 || echo 0)"
# no pytest venv and no web -> exit 0
newrepo b4; echo 'x=1' > "$R/m.py"
at
ok "nothing runnable (no venv, no web, no gd) -> exit 0" "$([ "$RC" = 0 ] && [ -z "$OUT" ] && echo 1 || echo 0)"

echo "ovn_autotest_run: $P passed, $F failed"
[ "$F" = 0 ]
