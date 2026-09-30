#!/usr/bin/env bash
# Hermetic end-to-end tests of run_aider_fix_task's post-commit GATES (run_overnight.sh, second half):
# VERIFY-SKIP guard (both checkpoints), TS-RATCHET revert, migration-safety fix-up/revert, BUILD-GATE grounded fix-up
# (incl. _ovn_buildbreak_evidence extraction), Tier-2 fix-up, NO-NEW-RED guard, red-green/lint/coverage hooks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"

seed_add(){ # <path> <content> [mode]  : add a file to origin/main and pull it into the clone
  ( cd "$OTHER" && mkdir -p "$(dirname "$1")" && printf '%b' "$2" > "$1" && [ -n "${3:-}" ] && chmod "$3" "$1"
    git add -A && git commit -q -m "seed $1" && git push -q origin main ) >/dev/null 2>&1
  ( cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1
}
reset_hd(){ git -C "$REPO" rev-parse "origin/main"; }

# ---------- P: VERIFY-SKIP guard (first checkpoint) ----------
mk_case vskip1
scout_ok
aplan 2 'gc app.py "def p(): return 1" "feat: p"'
vplan 1 'echo "ovn-verify: SKIPPED — venv lock contended past 300s wait, not treating as a failure"; exit 0'
run_case
eq "P: skipped verify -> error(verify-skipped...)" "$OUT" "error(verify-skipped - lock contended, retry next cycle)"
ok "P: guard logged" 'logged "VERIFY-SKIP GUARD: verification could not run"'
ok "P: nothing pushed" '! origin_has claude/feature "feat: p"'

# ---------- Q: TS-RATCHET revert ----------
mk_case tsc
scout_ok
aplan 2 'gc app.py "def q(): return 1" "feat: q"'
echo "TSC-RATCHET-REGRESSION: 3 new errors" > "$CASE_DIR/tsc.out"
run_case
eq "Q: ts regression -> reverted(ts-regression)" "$OUT" "reverted(ts-regression)"
ok "Q: alert emitted" 'grep -q "ts-ratchet reverted" <<< "$ALERTS"'
eq "Q: clone reset to pre-commit state" "$(repo_head)" "$(reset_hd)"
mk_case tscok
scout_ok
aplan 2 'gc app.py "def q(): return 1" "feat: q"'
echo "TSC: no new errors (baseline 4)" > "$CASE_DIR/tsc.out"
run_case
ok "Q: clean tsc output is logged and commit lands" 'logged "TSC: no new errors" && [[ "$OUT" == pushed* ]]'
mk_case tscoff
scout_ok
aplan 2 'gc app.py "def q(): return 1" "feat: q"'
echo "TSC-RATCHET-REGRESSION" > "$CASE_DIR/tsc.out"
OVN_TSC_GATE=0 run_case
ok "Q: OVN_TSC_GATE=0 disables the ratchet" '[[ "$OUT" == pushed* ]]'

# ---------- R: migration-safety gate ----------
mig_commit='gc backend/alembic/versions/0002_x.py "revision = \"0002\"" "feat(db): add migration"'
mk_case mig_fixed
scout_ok
aplan 2 "$mig_commit"
printf 'rc=1\n  ✗ MIGRATION FORK: two heads\nMULTIPLE HEADS: 0001, 0002\n' > "$CASE_DIR/mig.1"
printf 'rc=0\nok\n' > "$CASE_DIR/mig.2"
aplan 3 'echo "down_revision = \"0001\"" >> backend/alembic/versions/0002_x.py; git add -A; git commit -q -m "fix(db): linearize"'
run_case
ok "R: fix-up attempt logged" 'logged "MIGRATION-SAFETY fix-up: one bounded attempt"'
ok "R: fix-up re-check ok" 'logged "MIGRATION-SAFETY fix-up re-check: ok"'
ok "R: landed after migration fix-up" '[[ "$OUT" == pushed* ]]'
ok "R: fix-up was handed the alembic file" 'grep -qx "backend/alembic/versions/0002_x.py" "$CASE_DIR/aider.args.3"'
mk_case mig_nochange
scout_ok
aplan 2 "$mig_commit"
printf 'rc=1\n  ✗ MIGRATION FORK: two heads\n' > "$CASE_DIR/mig.default"
run_case
eq "R: fix-up made no change -> reverted(migration-fork)" "$OUT" "reverted(migration-fork)"
ok "R: no-change logged" 'logged "MIGRATION-SAFETY fix-up made no change"'
ok "R: alert emitted" 'grep -q "migration-safety gate reverted" <<< "$ALERTS"'
eq "R: clone reset" "$(repo_head)" "$(reset_hd)"
mk_case mig_stillbad
scout_ok
aplan 2 "$mig_commit"
aplan 3 'echo "# tried" >> backend/alembic/versions/0002_x.py; git add -A; git commit -q -m "fix(db): attempt"'
printf 'rc=1\n  ✗ MIGRATION FORK: two heads\n' > "$CASE_DIR/mig.default"
run_case
eq "R: fix-up did not resolve -> reverted(migration-fork)" "$OUT" "reverted(migration-fork)"
ok "R: re-check fail logged" 'logged "MIGRATION-SAFETY fix-up re-check: fail"'
mk_case mig_nosummary
scout_ok
aplan 2 "$mig_commit"
printf 'rc=1\nsome unparseable failure with no marker lines\n' > "$CASE_DIR/mig.default"
run_case
eq "R: failing check without summary lines -> direct revert" "$OUT" "reverted(migration-fork)"
ok "R: no fix-up attempted" '[ "$(cat "$CASE_DIR/aider.n")" = 2 ]'

# ---------- S: BUILD-GATE grounded fix-up ----------
bigfile(){ head -c 61000 /dev/zero | tr '\0' 'x' ; }
mk_case build_fixed
seed_add big.py "$(bigfile)\n"
seed_add helper.py 'def helper():\n    return 1\n'
scout_ok
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
vplan 1 'echo "--- noise before marker ---"
echo "Traceback (most recent call last):"
echo "  File \"$(pwd)/app.py\", line 3"
echo "app.py:3: SyntaxError: invalid syntax"
echo "helper.py:9: ImportError while loading conftest"
echo "big.py:2: cannot import name Foo"
echo "ghost.py:5: No module named ghost"
echo "file://$(pwd)/Widget.kt:3:4 Unresolved reference: nope"
echo "/repo/.venv/lib/site-packages/x.py:7: Error"
echo "ModuleNotFoundError: No module named zzz"
printf "\033[31mE   SyntaxError colored\033[0m\n"
echo "    warnings.warn(\"ignored\")"
echo "> Task :compileKotlin FAILED"
exit 1'
aplan 3 'echo "def broken(): pass" > app.py; git add -A; git commit -q -m "fix: parse error"'
run_case
ok "S: evidence banner logged" 'logged "BUILD-GATE fix-up: evidence="'
ok "S: fix-up attempt logged" 'logged "BUILD-GATE fix-up: one bounded attempt at the structural break"'
ok "S: re-verify after fix-up passed" 'logged "BUILD-GATE fix-up re-verify: pass"'
ok "S: landed" '[[ "$OUT" == pushed* ]]'
ok "S: fix-up prompt has verbatim failing output + KEY lines" 'grep -q "KEY: " "$CASE_DIR/aider.args.3" && grep -q "REAL failing output" "$CASE_DIR/aider.args.3"'
ok "S: fix-up handed the touched file" 'grep -qx "app.py" "$CASE_DIR/aider.args.3"'
ok "S: fix-up handed an evidence-named untouched file" 'grep -qx "helper.py" "$CASE_DIR/aider.args.3"'
ok "S: oversize evidence file excluded" '! grep -qx "big.py" "$CASE_DIR/aider.args.3"'
ok "S: nonexistent evidence file excluded" '! grep -qx "ghost.py" "$CASE_DIR/aider.args.3"'
ok "S: ANSI stripped / warnings filtered from evidence" '! grep -q "ignored" "$CASE_DIR/aider.args.3"'
mk_case build_nofix
scout_ok
printf '#!/bin/sh\nexit 0\n' > "$HOME/godot/godot4"; chmod +x "$HOME/godot/godot4"
seed_add project.godot 'config_version=5\n'
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
vplan default 'echo "SyntaxError: invalid syntax (app.py, line 3)"; exit 1'
run_case
eq "S: fix-up makes no change -> reverted(build-break)" "$OUT" "reverted(build-break)"
ok "S: no-change logged" 'logged "BUILD-GATE fix-up made no change"'
ok "S: alert emitted" 'grep -q "build-gate reverted" <<< "$ALERTS"'
eq "S: clone reset" "$(repo_head)" "$(reset_hd)"
rm -f "$HOME/godot/godot4"
mk_case build_stillbroken
scout_ok
aplan 2 'gc app.py "def broken(:" "feat: breaks build"'
aplan 3 'gc app.py "still broken" "fix: attempt"'
vplan default 'echo "SyntaxError: invalid syntax"; exit 1'
run_case
eq "S: fix-up still red -> reverted(build-break)" "$OUT" "reverted(build-break)"
ok "S: re-verify fail logged" 'logged "BUILD-GATE fix-up re-verify: fail"'
mk_case build_testsran
scout_ok
aplan 2 'gc app.py "def t(): return 0" "feat: t"'
vplan default 'echo "5 tests completed, 1 failed"; echo "SyntaxError: invalid syntax in fixture"; echo "FAILED tests/test_app.py::test_x"; exit 1'
run_case
ok "S: 'N tests completed' means tests ran -> no BUILD-GATE, falls to NO-NEW-RED" '! logged "BUILD-GATE" && [ "$OUT" = "no-op(reverted-red)" ]'
mk_case build_negated
scout_ok
aplan 2 'gc app.py "def t(): return 0" "feat: t"'
vplan default 'echo "Parse Error: something has no resource loaders"; exit 1'
run_case
ok "S: only negated (benign godot noise) break patterns -> no BUILD-GATE" '! logged "BUILD-GATE" && [ "$OUT" = "no-op(reverted-red)" ]'

# ---------- T: Tier-2 fix-up, NO-NEW-RED guard ----------
mk_case t2_fixed
seed_add extra.py 'def extra():\n    return 1\n'
aplan 1 'scout PROCEED "fix hello" "app.py other.py README.md ghost.py extra.py"'
aplan 2 'gc app.py "def t2(): return 1" "feat: t2"'
vplan 1 'echo "FAILED tests/test_app.py::test_x - assert 1 == 2"; exit 1'
echo "tests/test_app.py::test_x - assert 1 == 2" > "$CASE_DIR/extract.out"
aplan 3 'gc tests/test_app.py "# adjust expectation" "fix(test): expectation"'
run_case
ok "T: Tier-2 fix-up logged" 'logged "Tier-2 fix-up: one bounded attempt"'
ok "T: re-verify pass logged" 'logged "Tier-2 fix-up re-verify: pass"'
ok "T: landed" '[[ "$OUT" == pushed* ]]'
ok "T: scout-named untouched files added to fix-up context" 'grep -qx "other.py" "$CASE_DIR/aider.args.3" && grep -qx "extra.py" "$CASE_DIR/aider.args.3"'
ok "T: md and missing scout files not added" '! grep -qx "README.md" "$CASE_DIR/aider.args.3" && ! grep -qx "ghost.py" "$CASE_DIR/aider.args.3"'
mk_case t2_nochange_src
scout_ok
aplan 2 'gc app.py "def t2(): return 1" "feat: t2"'
vplan default 'echo "FAILED tests/test_app.py::test_x - assert 1 == 2"; exit 1'
echo "tests/test_app.py::test_x - assert" > "$CASE_DIR/extract.out"
run_case
eq "T: fix-up no change, source diff -> no-op(reverted-red)" "$OUT" "no-op(reverted-red)"
ok "T: no-change logged" 'logged "Tier-2 fix-up made no change"'
ok "T: red kind = source broke green test" 'logged "a source change broke a previously-green test"'
ok "T: alert emitted" 'grep -q "reverted a commit that left tests red" <<< "$ALERTS"'
eq "T: clone reset" "$(repo_head)" "$(reset_hd)"
mk_case t2_tests_only
scout_ok
aplan 2 'gc tests/test_new.py "def test_new(): assert 0" "test: add failing test"'
vplan default 'echo "FAILED tests/test_new.py::test_new"; exit 1'
run_case
eq "T: test-only red commit -> no-op(reverted-red)" "$OUT" "no-op(reverted-red)"
ok "T: red kind = model added failing tests" 'logged "the model added failing tests"'
mk_case t2_noextract
scout_ok
aplan 2 'gc app.py "def t2(): return 1" "feat: t2"'
vplan default 'echo "FAILED x"; exit 1'
run_case
eq "T: empty failure extract -> no fix-up, straight revert" "$OUT" "no-op(reverted-red)"
ok "T: only scout+implement calls" '[ "$(cat "$CASE_DIR/aider.n")" = 2 ]'
mk_case t2_stillred
scout_ok
aplan 2 'gc app.py "def t2(): return 1" "feat: t2"'
aplan 3 'gc app.py "x" "fix: try"'
vplan default 'echo "FAILED tests/test_app.py::t"; exit 1'
echo "tests/test_app.py::t" > "$CASE_DIR/extract.out"
run_case
eq "T: fix-up still red -> no-op(reverted-red)" "$OUT" "no-op(reverted-red)"
ok "T: re-verify fail logged" 'logged "Tier-2 fix-up re-verify: fail"'
mk_case t2_skip_after
scout_ok
aplan 2 'gc app.py "def t2(): return 1" "feat: t2"'
aplan 3 'gc app.py "x" "fix: try"'
vplan 1 'echo "FAILED tests/test_app.py::t"; exit 1'
vplan 2 'echo "SKIPPED — venv lock contended"; exit 0'
echo "tests/test_app.py::t" > "$CASE_DIR/extract.out"
run_case
eq "T: post-fixup skip -> error(verify-skipped...)" "$OUT" "error(verify-skipped - lock contended, retry next cycle)"
ok "T: second guard logged" 'logged "VERIFY-SKIP GUARD (post-fixup)"'

# ---------- U: red-green / lint / coverage hooks through the full flow ----------
setup_pytest_repo(){ # $1 = pytest exit code
  seed_add backend/app_mod.py 'def f():\n    return 1\n'
  seed_add backend/.venv/bin/pytest "#!/bin/sh\nexit $1\n" 755
  seed_add backend/.venv/bin/ruff '#!/bin/sh\necho "app_mod.py:1:1: E501 too long"\necho "app_mod.py:2:1: F401 unused"\nexit 1\n' 755
  seed_add web/node_modules/.bin/eslint '#!/bin/sh\necho "/x/a.js:1:2: Error - bad (no-undef)"\nexit 1\n' 755
}
mk_case rg_suspect
setup_pytest_repo 0
scout_ok
aplan 2 'gc backend/app_mod.py "def g(): return 2" "fix: g"; gc backend/tests/test_mod.py "def test_g(): assert True" "test: g"; gc web/a.js "const a = 1" "feat(web): a"'
run_case
ok "U: vacuous new test -> RED-GREEN SUSPECT logged" 'logged "RED-GREEN SUSPECT"'
ok "U: suspect alert" 'grep -q "red-green: a new test passed without the fix" <<< "$ALERTS"'
ok "U: status carries redgreen + lint tags" '[[ "$OUT" == *"[redgreen:SUSPECT]"* && "$OUT" == *"[lint:"* ]]'
ok "U: red-green run logged" 'logged "red-green: running new test(s) against pre-fix source"'
ok "U: auto-test enabled when a venv pytest exists" 'logged "auto-test enabled"'
mk_case rg_ok
setup_pytest_repo 1
scout_ok
aplan 2 'gc backend/app_mod.py "def g(): return 2" "fix: g"; gc backend/tests/test_mod.py "def test_g(): assert True" "test: g"'
run_case
ok "U: new test fails w/o fix -> not suspect" '[[ "$OUT" == pushed* && "$OUT" != *SUSPECT* ]] && ! logged "RED-GREEN SUSPECT"'
mk_case rg_new_src
setup_pytest_repo 0
scout_ok
aplan 2 'gc backend/newmod.py "def n(): return 1" "feat: n"; gc backend/tests/test_new.py "def test_n(): assert True" "test: n"'
run_case
ok "U: net-new source file skipped by red-green" 'logged "red-green: skipped"'
mk_case rg_untested
scout_ok
aplan 2 'gc app.py "def brand_new(): return 3" "feat: new def without tests"'
run_case
ok "U: new def with no test change -> [untested-change]" '[[ "$OUT" == *"[untested-change]"* ]]'

# ---------- direct calls: redgreen/lint/coverage helpers ----------
mk_case direct
seed_add backend/app_mod.py 'def f():\n    return 1\n'
( cd "$REPO" || exit 1; git checkout -q -B scratch
  echo 'def g(): pass' >> backend/app_mod.py; git add -A; git commit -q -m src )
B0="$(git -C "$REPO" rev-parse HEAD~1)"; B1="$(git -C "$REPO" rev-parse HEAD)"
task_log="$TASK_LOG"
ok "direct: redgreen n/a when no tests changed" '[ "$(cd "$REPO" && run_redgreen_check "$B0" "$B1")" = n/a ]'
( cd "$REPO" && echo 'def test_h(): pass' > backend/tests_x.py && mkdir -p backend/tests && echo 'def test_h(): pass' > backend/tests/test_h.py && git add -A && git commit -q -m tests )
B2="$(git -C "$REPO" rev-parse HEAD)"
ok "direct: redgreen n/a when only tests changed (no src)" '[ "$(cd "$REPO" && run_redgreen_check "$B1" "$B2")" = n/a ]'
ok "direct: redgreen n/a when no venv pytest" '[ "$(cd "$REPO" && run_redgreen_check "$B0" "$B2")" = n/a ]'
seed_add backend/.venv/bin/pytest '#!/bin/sh\nexit 0\n' 755
( cd "$REPO" && git checkout -q scratch 2>/dev/null; git pull -q --no-rebase origin main >/dev/null 2>&1 || true )
B3="$(git -C "$REPO" rev-parse HEAD)"
ok "direct: redgreen n/a when tests live outside the venv dir" '[ "$(cd "$REPO" && run_redgreen_check "$B0" "$B3")" = n/a ]'
ok "direct: coverage check sees untested new def" '[ "$(cd "$REPO" && run_coverage_check "$B0" "$B1")" = untested ]'
ok "direct: coverage check ok when tests changed" '[ "$(cd "$REPO" && run_coverage_check "$B1" "$B2")" = ok ]'
ok "direct: coverage ok when no defs" '[ "$(cd "$REPO" && run_coverage_check "$B2" "$B2")" = ok ]'
printf '#!/bin/sh\necho "a.py:1:1: E1 x"\necho "a.py:2:1: E2 y"\n' > "$HOME/aider-venv/bin/ruff"; chmod +x "$HOME/aider-venv/bin/ruff"
ok "direct: lint via PATH ruff counts findings (2)" '[ "$(cd "$REPO" && run_lint_check "$B0" "$B1")" = 2 ]'
rm -f "$HOME/aider-venv/bin/ruff"
ok "direct: lint 0 when no python/js changed" '[ "$(cd "$REPO" && run_lint_check "$B2" "$B2")" = 0 ]'

summary
