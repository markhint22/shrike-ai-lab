#!/usr/bin/env bash
# q-contract (2026-11-25), advisory 2: the POST-CYCLE CONTRACT HOOK is wired into the REAL ovn_stage_runner.sh (after a staged step's commit, before the push / credit). Hermetic fixture
# (lib_osr_fixture.sh): a gitlark-shaped repo (backend/tests/test_openapi*.py, a frozen docs/openapi.json, scripts/export_openapi.py, a FAKE venv python that emulates pytest over "# route:" /
# "# tag:" comment lines). The step adds a router; shadow (default) must journal would-regen and change nothing, only OVN_POSTCYCLE_CONTRACT=enforce + a listed repo may act.
# Needs GNU sed + bash 5 (run on the box); SKIPs elsewhere like the other runner fixtures.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed; run on the box"; exit 0; fi
unset OVN_POSTCYCLE_CONTRACT OVN_POSTCYCLE_ENFORCE_REPOS OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_EMPTY_FILE NTFY_SERVER NTFY_TOPIC OVN_Z3_TONE
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
trap osr_cleanup EXIT
G(){ grep -qF -- "$1" "$T/out.txt"; }
NG(){ ! grep -qF -- "$1" "$T/out.txt"; }
LOG(){ cat "$Q/state/contract_regen_shadow.log" 2>/dev/null; }
PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
FAKEPY='#!/usr/bin/env bash
if [ "$1" = -m ] && [ "$2" = pytest ]; then
  shift 2; rc=0
  live="$(grep -h "^# route: " app/routers/*.py 2>/dev/null | sed "s/^# route: //" | sort)"; frozen="$(cat ../docs/openapi.json)"
  for f in "$@"; do case "$f" in
    tests/test_openapi_contract.py) [ "$live" = "$frozen" ] || { echo "FAILED tests/test_openapi_contract.py::test_frozen_contract_matches_the_live_app - Assert..."; rc=1; };;
    tests/test_openapi_meta.py) for t in $(grep -h "^# tag: " app/routers/*.py 2>/dev/null | sed "s/^# tag: //" | sort -u); do grep -q "^# desc: $t\$" app/core/openapi_meta.py || { echo "FAILED tests/test_openapi_meta.py::test_every_route_tag_is_described - Assert..."; rc=1; break; }; done;;
  esac; done
  echo "done"; exit $rc
fi
if [ "$1" = -c ]; then exit 1; fi
if [ "$1" = scripts/export_openapi.py ]; then grep -h "^# route: " app/routers/*.py | sed "s/^# route: //" | sort > ../docs/openapi.json; exit 0; fi
exit 9'
SNIP_ROUTE='mkdir -p backend/app/routers backend/tests
printf "# route: /b\n# tag: auth\n" > backend/app/routers/b.py
printf "def foo():\n    return 1\n" > backend/app/foo.py
printf "from app.foo import foo\n\ndef test_foo():\n    assert foo() == 1\n" > backend/tests/test_foo.py
echo "Applied edit to backend/app/foo.py"'
SNIP_TAG='mkdir -p backend/app/routers backend/tests
printf "# route: /b\n# tag: undescribed\n" > backend/app/routers/b.py
printf "def foo():\n    return 1\n" > backend/app/foo.py
printf "from app.foo import foo\n\ndef test_foo():\n    assert foo() == 1\n" > backend/tests/test_foo.py
echo "Applied edit to backend/app/foo.py"'
setup(){ osr_new; osr_venv backend; cp "$REALQ/scripts/lib_postcycle_contract.sh" "$Q/scripts/"
  printf '%s\n' "$FAKEPY" > "$RD/backend/.venv/bin/python3"; chmod +x "$RD/backend/.venv/bin/python3"
  mkdir -p "$RD/docs" "$RD/backend/app/routers" "$RD/backend/app/core"
  printf '# route: /a\n# tag: auth\n' > "$RD/backend/app/routers/a.py"; printf '# desc: auth\n' > "$RD/backend/app/core/openapi_meta.py"; printf '/a\n' > "$RD/docs/openapi.json"
  printf '# c\n' > "$RD/backend/tests/test_openapi_contract.py"; printf '# m\n' > "$RD/backend/tests/test_openapi_meta.py"; printf '# e\n' > "$RD/backend/scripts/export_openapi.py"
  git -C "$RD" add -A; git -C "$RD" commit -q -m "gitlark-shaped"; git -C "$RD" push -q origin HEAD:overnight/feature
  osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN"; }

echo "== A: DEFAULT (shadow): the router step lands untouched, the hook journals would-regen"
setup; osr_aider default "$SNIP_ROUTE"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "A1 the step PASSes and lands 1/1" bash -c "grep -qF 'step 0 PASS (att 1' '$T/out.txt' && grep -qF 'DONE: 1/1 steps landed' '$T/out.txt'"
t "A2 the shadow log has a would-regen row for the repo, mode shadow, naming the frozen-contract id" bash -c "grep -q 'osrrepo	shadow	would-regen	' '$Q/state/contract_regen_shadow.log' && grep -q 'test_frozen_contract_matches_the_live_app' '$Q/state/contract_regen_shadow.log'"
t "A3 the runner says so (and does not claim an action)" G "postcycle contract: would-regen (mode shadow)"
t "A4 origin has the step commit only: docs/openapi.json is unchanged (no regen commit)" bash -c "[ \"\$(git -C '$O' show overnight/feature:docs/openapi.json)\" = '/a' ] && ! git -C '$O' log --format=%s overnight/feature | grep -q 'regenerate artifacts after'"
osr_cleanup

echo "== B: OVN_POSTCYCLE_CONTRACT=off: no row, same landing"
setup; osr_aider default "$SNIP_ROUTE"
OVN_POSTCYCLE_CONTRACT=off OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "B1 lands 1/1, no contract rows, no hook line" bash -c "grep -qF 'DONE: 1/1 steps landed' '$T/out.txt' && [ ! -s '$Q/state/contract_regen_shadow.log' ] && ! grep -qF 'postcycle contract:' '$T/out.txt'"
osr_cleanup

echo "== C: enforce but the repo is not listed (default list = gitlark): still shadow, nothing acts"
setup; osr_aider default "$SNIP_TAG"
OVN_POSTCYCLE_CONTRACT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "C1 an undescribed tag would revert, but the unlisted repo only journals would-revert and the step lands" bash -c "grep -qF 'DONE: 1/1 steps landed' '$T/out.txt' && grep -q 'osrrepo	shadow	would-revert	' '$Q/state/contract_regen_shadow.log'"
osr_cleanup

echo "== D: enforce + listed repo: the regen is committed WITH the step (pushed together)"
setup; osr_aider default "$SNIP_ROUTE"
OVN_POSTCYCLE_CONTRACT=enforce OVN_POSTCYCLE_ENFORCE_REPOS=osrrepo OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "D1 lands 1/1 and a regen row is journalled in enforce mode" bash -c "grep -qF 'DONE: 1/1 steps landed' '$T/out.txt' && grep -q 'osrrepo	enforce	regen	' '$Q/state/contract_regen_shadow.log'"
t "D2 origin carries the regenerated contract and the regen commit" bash -c "[ \"\$(git -C '$O' show overnight/feature:docs/openapi.json | tr '\\n' ' ')\" = '/a /b ' ] && git -C '$O' log --format=%s overnight/feature | grep -q 'regenerate artifacts after'"
osr_cleanup

echo "== E: enforce + listed repo: a new red no regen can fix (undescribed tag) refuses the step"
setup; osr_aider default "$SNIP_TAG"
OVN_POSTCYCLE_CONTRACT=enforce OVN_POSTCYCLE_ENFORCE_REPOS=osrrepo OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1 the step is REJECTED (postcycle contract) and 0/1 land" bash -c "grep -qF 'REJECTED (postcycle contract)' '$T/out.txt' && grep -qF 'DONE: 0/1 steps landed' '$T/out.txt'"
t "E2 the router is not on origin" bash -c "! git -C '$O' show overnight/feature:backend/app/routers/b.py >/dev/null 2>&1"
osr_cleanup

echo "== F: the lib missing = fail-open (the old behaviour)"
setup; rm -f "$Q/scripts/lib_postcycle_contract.sh"; osr_aider default "$SNIP_ROUTE"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "F1 lands 1/1 with no row" bash -c "grep -qF 'DONE: 1/1 steps landed' '$T/out.txt' && [ ! -s '$Q/state/contract_regen_shadow.log' ]"
osr_cleanup

echo "== G: static wiring"
t "G1 the hook call sits right after the staged-step commit and before the step's return 0" bash -c "n1=\$(grep -n 'staged step \$idx — ' '$RUNNER' | head -1 | cut -d: -f1); n2=\$(grep -n 'if stage_postcycle_contract \"\$base\"; then return 0; fi' '$RUNNER' | cut -d: -f1); [ -n \"\$n1\" ] && [ -n \"\$n2\" ] && [ \"\$n2\" -gt \"\$n1\" ] && [ \$((n2-n1)) -le 3 ]"
t "G2 the runner sources the lib with a fail-open stub and bounds the hook in a subshell" bash -c "grep -q 'source scripts/lib_postcycle_contract.sh 2>/dev/null || true' '$RUNNER' && grep -q 'declare -F ovn_postcycle_contract' '$RUNNER' && grep -q '_pres=\"\$( ( cd \"\$wt\"' '$RUNNER'"
t "G3 syntax" bash -n "$RUNNER"
osr_summary
