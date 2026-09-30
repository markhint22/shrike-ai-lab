#!/usr/bin/env bash
# run_overnight.sh verification helpers, exercised by SOURCING THE REAL SCRIPT in a hermetic fake tree:
# run_repo_verification (repo-owned .ovn-verify.sh incl. the SKIPPED path, pytest/npm/gradle/godot walks, change scoping,
# the no-tests-ran case), run_redgreen_check, run_lint_check, run_coverage_check.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ro_tasks '[]'
ro_source
set +e

task_log="$T/verify.task.log"; : > "$task_log"
V="$T/v"
newrepo(){ rm -rf "$V"; mkdir -p "$V"; cd "$V" || exit 1; git init -q; echo base > README; git add -A; git commit -q -m base; BEFORE_SHA="$(git rev-parse HEAD)"; : > "$task_log"; }
commit_files(){ git add -A; git commit -q -m c; } # after creating files
fakebin(){ # fakebin PATH EXITCODE [echo-text]
  mkdir -p "$(dirname "$1")"; printf '#!/bin/bash\necho "%s ran in $(pwd) args: $*" >> "%s/bins.log"\n%s\nexit %s\n' "$(basename "$(dirname "$(dirname "$1")")")/$(basename "$1")" "$RO_STUB" "${3:+echo "$3"}" "$2" > "$1"; chmod +x "$1"; }
: > "$RO_STUB/bins.log"

echo "--- run_repo_verification: nothing provisioned ---"
newrepo
eq "no suites -> none" none "$(run_repo_verification)"

echo "--- repo-owned .ovn-verify.sh ---"
newrepo
printf '#!/bin/bash\necho "changed=[$OVN_CHANGED_FILES]"\nexit 0\n' > .ovn-verify.sh; chmod +x .ovn-verify.sh; echo code > a.py; commit_files
r="$(run_repo_verification)"
eq "repo-owned verify green -> pass" pass "$r"
has "log names the repo-owned override + cap" "$(cat "$task_log")" "--- verify: ./.ovn-verify.sh (repo-owned, 600s cap) ---"
has "verify sees OVN_CHANGED_FILES" "$(cat "$task_log")" "a.py"
printf '#!/bin/bash\necho "tests exploded"\nexit 1\n' > .ovn-verify.sh; commit_files
eq "repo-owned verify red -> fail" fail "$(run_repo_verification)"
printf '#!/bin/bash\necho "SKIPPED — venv lock contended, not treating as a failure"\nexit 0\n' > .ovn-verify.sh; commit_files
eq "lock-contended SKIPPED marker -> skip (never pass)" skip "$(run_repo_verification)"
# override owns verification: a pytest venv next to it is NOT run
fakebin .venv/bin/pytest 1 "pytest should not run"
printf '#!/bin/bash\nexit 0\n' > .ovn-verify.sh; commit_files
eq "override wins over the default dir walk" pass "$(run_repo_verification)"
newrepo
mkdir -p sub/dir; printf '#!/bin/bash\nexit 0\n' > sub/dir/.ovn-verify.sh; chmod +x sub/dir/.ovn-verify.sh; echo x > sub/dir/f; commit_files
eq "override found up to depth 3 and run from its own dir" pass "$(run_repo_verification)"

echo "--- pytest walk (no override) ---"
newrepo
fakebin .venv/bin/pytest 0 "5 passed"; echo x > f; commit_files
eq "root .venv pytest green -> pass" pass "$(run_repo_verification)"
has "pytest invoked with -q --no-cov" "$(cat "$task_log")" "--- verify: pytest in . (240s cap) ---"
fakebin .venv/bin/pytest 1 "1 failed"; commit_files
eq "root pytest red -> fail" fail "$(run_repo_verification)"
newrepo
fakebin backend/.venv/bin/pytest 0 "ok"; fakebin web/.venv/bin/pytest 1 "web red"; commit_files
BEFORE_SHA="$(git rev-parse HEAD)"; echo y > backend/x.py; commit_files
r="$(run_repo_verification)"
eq "commit touched only backend/: web (red) pytest is scoped out -> pass" pass "$r"
has "untouched dir skipped with a log line" "$(cat "$task_log")" "--- skip pytest in ./web: commit did not touch it ---"
echo z > web/y.py; commit_files
BEFORE_SHA="$(git rev-parse HEAD~1)"; : > "$task_log"
eq "commit touching web/ runs the red web suite -> fail" fail "$(run_repo_verification)"
BEFORE_SHA="$(git rev-parse HEAD)"; : > "$task_log"
r="$(run_repo_verification)"
has "unknown change set runs every suite (safe default)" "$(cat "$task_log")" "verify: pytest in ./backend"
BEFORE_SHA="$(git rev-parse HEAD~1)"
# per-dir .ovn-verify.sh override: only reachable via a non-regular file (symlink), since the repo-root find is -type f
newrepo
fakebin backend/.venv/bin/pytest 1 "full suite would fail"
printf '#!/bin/bash\necho "targeted verify, changed=[$OVN_CHANGED_FILES]"\nexit 0\n' > "$T/targeted-verify.sh"; chmod +x "$T/targeted-verify.sh"
ln -s "$T/targeted-verify.sh" backend/.ovn-verify.sh; echo y > backend/x.py; commit_files
r="$(run_repo_verification)"
eq "per-dir executable .ovn-verify.sh (symlink) replaces pytest" pass "$r"
has "per-dir override logged" "$(cat "$task_log")" "--- verify: .ovn-verify.sh override in ./backend (600s cap) ---"
printf '#!/bin/bash\nexit 1\n' > "$T/targeted-verify.sh"
eq "per-dir override red -> fail" fail "$(run_repo_verification)"

echo "--- npm walk ---"
newrepo
mkdir -p web/node_modules; echo '{"scripts":{"test":"vitest"}}' > web/package.json
mkdir -p nomods; echo '{"scripts":{"test":"vitest"}}' > nomods/package.json
mkdir -p notest/node_modules; echo '{"scripts":{"build":"vite build"}}' > notest/package.json
mkdir -p web/node_modules/dep; echo '{"scripts":{"test":"x"}}' > web/node_modules/dep/package.json
commit_files 2>/dev/null; echo c >> web/package.json; commit_files; BEFORE_SHA="$(git rev-parse HEAD~1)"
rm -f "$RO_STUB/npm.log" "$RO_STUB/npm_fails"
r="$(run_repo_verification)"
eq "npm test run for the provisioned, touched project -> pass" pass "$r"
has "npm runs with CI=true" "$(cat "$RO_STUB/npm.log")" "test --silent CI=true"
eq "exactly one npm run (no node_modules / no test script / vendored pkg ignored)" 1 "$(wc -l < "$RO_STUB/npm.log" | tr -d ' ')"
touch "$RO_STUB/npm_fails"
eq "npm test red -> fail" fail "$(run_repo_verification)"
rm -f "$RO_STUB/npm_fails"
echo d > nomods/x; commit_files; BEFORE_SHA="$(git rev-parse HEAD~1)"; : > "$task_log"
r="$(run_repo_verification)"
has "untouched npm project skipped with a log line" "$(cat "$task_log")" "--- skip npm test in ./web: commit did not touch it ---"
eq "nothing ran (web untouched, nomods has no node_modules) -> none" none "$r"

echo "--- gradle walk ---"
newrepo
mkdir -p android; touch android/settings.gradle.kts; printf '#!/bin/bash\necho "gradlew $* ANDROID_HOME=$ANDROID_HOME" >> "%s/bins.log"\nexit 0\n' "$RO_STUB" > android/gradlew; chmod +x android/gradlew
mkdir -p nosettings; printf '#!/bin/bash\nexit 1\n' > nosettings/gradlew; chmod +x nosettings/gradlew
mkdir -p oldstyle; touch oldstyle/settings.gradle; printf '#!/bin/bash\nexit 0\n' > oldstyle/gradlew; chmod +x oldstyle/gradlew
commit_files; echo c >> android/x; echo c >> nosettings/x; echo c >> oldstyle/x; commit_files; BEFORE_SHA="$(git rev-parse HEAD~1)"
: > "$RO_STUB/bins.log"
r="$(run_repo_verification)"
eq "gradle suites green (dir without settings.gradle ignored) -> pass" pass "$r"
has "gradlew test run with console=plain + ANDROID_HOME" "$(cat "$RO_STUB/bins.log")" "gradlew test --console=plain ANDROID_HOME=$HOME/android-sdk"
eq "local.properties written with the sdk dir" "sdk.dir=$HOME/android-sdk" "$(cat android/local.properties)"
printf '#!/bin/bash\nexit 1\n' > android/gradlew
eq "gradle red -> fail" fail "$(run_repo_verification)"
commit_files; BEFORE_SHA="$(git rev-parse HEAD)"; echo u > README; commit_files; : > "$task_log"
r="$(run_repo_verification)"
has "untouched gradle dir skipped with a log line" "$(cat "$task_log")" "--- skip gradle test in ./android: commit did not touch it ---"
eq "nothing ran -> none" none "$r"

echo "--- godot walk ---"
mkdir -p "$HOME/godot"
cat > "$HOME/godot/godot4" <<'EOF'
#!/bin/bash
# fake godot: GODOT_OUT_TEXT is printed; GUT runs write GODOT_XML to the -gjunit_xml_file path
echo "godot4 $*" >> "$RO_STUB/bins.log"
[ -n "${GODOT_OUT_TEXT:-}" ] && echo "$GODOT_OUT_TEXT"
for a in "$@"; do
  case "$a" in -gjunit_xml_file=*) [ -n "${GODOT_XML:-}" ] && printf '%s\n' "$GODOT_XML" > "${a#-gjunit_xml_file=}";; esac
done
exit "${GODOT_RC:-0}"
EOF
chmod +x "$HOME/godot/godot4"
newrepo; touch project.godot; commit_files
export GODOT_OUT_TEXT="" GODOT_XML=""
r="$(run_repo_verification)"
eq "godot project without GUT, clean parse -> pass" pass "$r"
has "no-GUT path logged" "$(cat "$task_log")" "godot4 --headless in . (90s cap, no GUT yet)"
GODOT_OUT_TEXT="SCRIPT ERROR: Parse Error: bad thing"
eq "no GUT: SCRIPT ERROR in output -> fail" fail "$(run_repo_verification)"
GODOT_OUT_TEXT="SCRIPT ERROR: Cannot call method 'x' on a null value."
eq "no GUT: known-benign runtime noise is ignored -> pass" pass "$(run_repo_verification)"
# with GUT
mkdir -p addons/gut tests; echo x > addons/gut/gut_cmdln.gd; commit_files
GODOT_OUT_TEXT=""; GODOT_XML='<testsuites failures="0" tests="3"></testsuites>'
r="$(run_repo_verification)"
eq "GUT green (failures=0) -> pass" pass "$r"
has "GUT path logged" "$(cat "$task_log")" "--- verify: GUT tests in . (90s cap) ---"
GODOT_XML='<testsuites failures="2" tests="3"></testsuites>'
eq "GUT failures>0 -> fail" fail "$(run_repo_verification)"
GODOT_XML=""
eq "GUT produced no junit xml -> fail" fail "$(run_repo_verification)"
GODOT_XML='<testsuites failures="0"><testcase status="no asserts"/></testsuites>'
eq "GUT 'no asserts' (Risky) testcase is a failure" fail "$(run_repo_verification)"
GODOT_XML='<testsuites failures="0" tests="1"></testsuites>'; GODOT_OUT_TEXT="ERROR: Failed to load script res://x.gd"
eq "GUT green but a project-wide load error in the import output -> fail" fail "$(run_repo_verification)"
GODOT_OUT_TEXT="Attempted to free a RefCounted object"
eq "GUT green + benign engine noise -> pass" pass "$(run_repo_verification)"
unset GODOT_OUT_TEXT GODOT_XML
mv "$HOME/godot/godot4" "$HOME/godot/godot4.off"
newrepo; touch project.godot; commit_files
eq "no godot binary installed -> godot project not run -> none" none "$(run_repo_verification)"
mv "$HOME/godot/godot4.off" "$HOME/godot/godot4"

echo "--- mixed results: any failure wins ---"
newrepo
fakebin a/.venv/bin/pytest 0 ok; mkdir -p b/node_modules; echo '{"scripts":{"test":"x"}}' > b/package.json; commit_files
touch "$RO_STUB/npm_fails"; BEFORE_SHA=""
eq "pytest green + npm red -> fail" fail "$(run_repo_verification)"
rm -f "$RO_STUB/npm_fails"
eq "pytest green + npm green -> pass" pass "$(run_repo_verification)"

echo "--- run_redgreen_check ---"
rg_repo(){ # rg_repo SUBDIR  (venv + tests + src live under SUBDIR, '.' for root)
  local d="$1"; rm -rf "$V"; mkdir -p "$V"; cd "$V" || exit 1; git init -q
  mkdir -p "$d"; [ "$d" = "." ] || true
  echo 'def f(): return "broken"' > "$d/mod.py"; : > "$d/__init__.py"
  fakebin "$d/.venv/bin/pytest" 0
  # fake pytest passes only when mod.py contains FIXED (i.e. the fix is present)
  printf '#!/bin/bash\necho "pytest $*" >> "%s/bins.log"\ngrep -q FIXED mod.py\n' "$RO_STUB" > "$d/.venv/bin/pytest"; chmod +x "$d/.venv/bin/pytest"
  git add -A; git commit -q -m base; RG_BEFORE="$(git rev-parse HEAD)"
}
rg_apply_fix(){ # writes fix + a test
  local d="$1"; echo 'def f(): return "FIXED"' > "$d/mod.py"; mkdir -p "$d/tests"; echo 'def test_f(): pass' > "$d/tests/test_mod.py"
  git add -A; git commit -q -m fix; RG_AFTER="$(git rev-parse HEAD)"
}
: > "$task_log"
rg_repo backend; rg_apply_fix backend
eq "bugfix with a real regression test (fails w/o fix) -> ok" ok "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
eq "source restored to the fixed version afterwards" 1 "$(grep -q FIXED backend/mod.py && echo 1 || echo 0)"
has "log says new tests run against pre-fix source" "$(cat "$task_log")" "--- red-green: running new test(s) against pre-fix source ---"
has "changed test path made relative to the venv dir" "$(tail -3 "$RO_STUB/bins.log")" "pytest -q --no-cov tests/test_mod.py"
rg_repo .; rg_apply_fix .
eq "venv at repo root (dir '.') works too" ok "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
rg_repo backend; printf '#!/bin/bash\nexit 0\n' > backend/.venv/bin/pytest; git add -A; git commit -q -m x; RG_BEFORE="$(git rev-parse HEAD)"; rg_apply_fix backend
eq "vacuous test (passes without the fix) -> suspect" suspect "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
# n/a cases
rg_repo backend; echo 'def test_only(): pass' > backend/test_only.py; git add -A; git commit -q -m t; RG_AFTER="$(git rev-parse HEAD)"
eq "tests-only change (coverage add) -> n/a" n/a "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
rg_repo backend; echo 'def g(): pass' >> backend/mod.py; git add -A; git commit -q -m s; RG_AFTER="$(git rev-parse HEAD)"
eq "source-only change (no test) -> n/a" n/a "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
rg_repo backend; rm -rf backend/.venv; git add -A; git commit -q -m nv; RG_BEFORE="$(git rev-parse HEAD)"; rg_apply_fix backend
eq "no pytest venv -> n/a" n/a "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
rg_repo backend; mkdir -p other/tests; echo 'def test_o(): pass' > other/tests/test_o.py; echo 'x=1' > other/o.py; git add -A; git commit -q -m o; RG_AFTER="$(git rev-parse HEAD)"
eq "changed tests live outside the venv's dir -> n/a" n/a "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
rg_repo backend; echo 'def h(): pass' > backend/brandnew.py; mkdir -p backend/tests; echo 'def test_h(): pass' > backend/tests/test_h.py; git add -A; git commit -q -m nn; RG_AFTER="$(git rev-parse HEAD)"; : > "$task_log"
eq "net-new source file (nothing to revert) -> n/a" n/a "$(run_redgreen_check "$RG_BEFORE" "$RG_AFTER")"
has "net-new skip is logged" "$(cat "$task_log")" "did not exist at"

echo "--- run_lint_check ---"
lint_repo(){ rm -rf "$V"; mkdir -p "$V"; cd "$V" || exit 1; git init -q; echo base > README; git add -A; git commit -q -m base; LB="$(git rev-parse HEAD)"; }
rm -f "$T/home/aider-venv/bin/ruff"
lint_repo; echo 'x=1' > a.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "python change, no ruff anywhere -> 0 issues" 0 "$(run_lint_check "$LB" "$LA")"
lint_repo; echo hi > notes.txt; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "no py/js files changed -> 0" 0 "$(run_lint_check "$LB" "$LA")"
printf '#!/bin/bash\necho "a.py:1:1: E1 thing"\necho "  detail line"\necho "a.py:2:1: E2 thing"\n' > "$T/home/aider-venv/bin/ruff"; chmod +x "$T/home/aider-venv/bin/ruff"
lint_repo; echo 'x=1' > a.py; mkdir -p migrations; echo 'y=1' > migrations/0001.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "ruff on PATH: counts top-level issue lines (indented detail ignored)" 2 "$(run_lint_check "$LB" "$LA")"
lint_repo; mkdir -p app/migrations; echo 'y=1' > app/migrations/0001.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "nested app/migrations/ python files are excluded" 0 "$(run_lint_check "$LB" "$LA")"
lint_repo; mkdir -p migrations; echo 'y=1' > migrations/0001.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
known_bug "a repo-ROOT migrations/ dir (Flask-Migrate default) is not excluded from lint because the pattern needs a leading slash: '/(migrations|\\.venv)/' (run_overnight.sh:721); patch: grep -vE '(^|/)(migrations|\\.venv)/'" "$([ "$(run_lint_check "$LB" "$LA")" = 0 ] && echo 1 || echo 0)"
rm -f "$T/home/aider-venv/bin/ruff"
lint_repo; mkdir -p be/.venv/bin; printf '#!/bin/bash\necho "a.py:1:1 bad"\n' > be/.venv/bin/ruff; chmod +x be/.venv/bin/ruff; git add -A; git commit -q -m v; LB="$(git rev-parse HEAD)"; echo 'x=1' > a.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "repo-local .venv ruff is preferred/found" 1 "$(run_lint_check "$LB" "$LA")"
lint_repo; echo 'x' > a.js; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "js change with no eslint installed -> 0" 0 "$(run_lint_check "$LB" "$LA")"
lint_repo; mkdir -p node_modules/.bin; printf '#!/bin/bash\necho "a.js:1:1: error x"\necho "a.js:3:2: error y"\necho "summary"\n' > node_modules/.bin/eslint; chmod +x node_modules/.bin/eslint; git add -A; git commit -q -m e; LB="$(git rev-parse HEAD)"; echo 'x' > a.js; echo 'y' > b.ts; mkdir -p node_modules/pkg; echo z > node_modules/pkg/i.js; git add -A -f; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "eslint --format unix lines counted (node_modules excluded)" 2 "$(run_lint_check "$LB" "$LA")"

echo "--- run_coverage_check ---"
cov_repo(){ lint_repo; }
cov_repo; echo 'def f(): pass' > a.py; echo 'def test_f(): pass' > test_a.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "new def WITH a test file -> ok" ok "$(run_coverage_check "$LB" "$LA")"
cov_repo; echo 'def f(): pass' > a.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "new def, no test -> untested" untested "$(run_coverage_check "$LB" "$LA")"
cov_repo; echo 'class K: pass' > a.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "new class, no test -> untested" untested "$(run_coverage_check "$LB" "$LA")"
cov_repo; echo 'func f():' > a.gd; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "new gdscript func, no test -> untested" untested "$(run_coverage_check "$LB" "$LA")"
cov_repo; echo 'export async function f() {}' > a.ts; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "new exported ts function -> untested" untested "$(run_coverage_check "$LB" "$LA")"
cov_repo; echo 'x = 1' > a.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "no new definitions -> ok" ok "$(run_coverage_check "$LB" "$LA")"
cov_repo; echo 'def f(): pass' > a.py; echo t > a.test.ts; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "a *.test.ts file counts as a test change -> ok" ok "$(run_coverage_check "$LB" "$LA")"
cov_repo; mkdir tests; echo 'def f(): pass' > a.py; echo 'x' > tests/helper.py; git add -A; git commit -q -m a; LA="$(git rev-parse HEAD)"
eq "a file under tests/ counts as a test change -> ok" ok "$(run_coverage_check "$LB" "$LA")"

ro_summary
