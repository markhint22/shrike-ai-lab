#!/usr/bin/env bash
# q-contract (2026-11-25): POST-CYCLE CONTRACT HOOK (scripts/lib_postcycle_contract.sh, wired in run_overnight.sh) + read-only gate-red report (ovn_gate_red_report.py).
# Runs the REAL lib against throwaway git repos with a FAKE venv python (a bash script that emulates `-m pytest <files>` and `scripts/export_openapi.py` over plain-text "routes/tags"),
# so the logic (trigger, baseline compare, regen, pathspec commit, shadow no-op, enforce revert, repo scoping) is tested without pytest/fastapi on the host (Mac and box alike).
# Every behavioural case has a mutant at the end that must fail it. Nothing touches the real repos, the live state dir, ssh or ntfy.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; TMP0="${TMPDIR:-}"
cleanup(){ if [ -n "$TMP0" ]; then TMPDIR="$TMP0" safe_rm_rf "$T"; else ( unset TMPDIR; safe_rm_rf "$T" ); fi; }; trap cleanup EXIT
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: mac test sandbox"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 TZ=UTC
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 SCRIPT_DIR="$Q" OVN_STATE_DIR="$T/state" TMPDIR="$T/tmp"
mkdir -p "$T/state" "$T/tmp"
LIB="$Q/scripts/lib_postcycle_contract.sh"
. "$LIB"
ROWS="$T/state/contract_regen_shadow.log"

FAKEPY='#!/usr/bin/env bash
if [ "$1" = -m ] && [ "$2" = pytest ]; then
  shift 2; rc=0
  { [ -n "${FAKE_PY_CRASH:-}" ] || grep -q CRASH app/routers/a.py 2>/dev/null; } && { echo "ImportError: boom"; exit 2; }
  live="$(grep -h "^route: " app/routers/*.py 2>/dev/null | sed "s/^route: //" | sort)"; frozen="$(cat ../docs/openapi.json)"
  for f in "$@"; do case "$f" in
    tests/test_openapi_contract.py) [ "$live" = "$frozen" ] || { echo "FAILED tests/test_openapi_contract.py::test_frozen_contract_matches_the_live_app - Assert..."; rc=1; };;
    tests/test_openapi_meta.py) for t in $(grep -h "^tag: " app/routers/*.py 2>/dev/null | sed "s/^tag: //" | sort -u); do grep -q "^desc: $t\$" app/core/openapi_meta.py || { echo "FAILED tests/test_openapi_meta.py::test_every_route_tag_is_described - Assert..."; rc=1; break; }; done;;
  esac; done
  echo "done"; exit $rc
fi
if [ "$1" = -c ]; then pk="$(printf "%s" "$2" | sed -n "s/.*version(.\([a-z]*\).).*/\1/p")"; v="$(eval echo \"\${FAKE_VER_$pk:-}\")"; [ -n "$v" ] && { echo "$v"; exit 0; }; exit 1; fi
if [ "$1" = scripts/export_openapi.py ]; then grep -h "^route: " app/routers/*.py | sed "s/^route: //" | sort > ../docs/openapi.json; [ -n "${FAKE_EXPORT_EXTRA:-}" ] && echo extra > ../docs/extra_generated.json; exit 0; fi
exit 9'

# mk NAME : a gitlark-shaped repo, green at HEAD. Sets R (dir) and B (the base sha).
mk(){ R="$T/$1"; rm -rf "$R"; mkdir -p "$R/backend/app/routers" "$R/backend/app/core" "$R/backend/tests" "$R/backend/scripts" "$R/backend/venv/bin" "$R/docs"
  printf 'route: /a\ntag: auth\n' > "$R/backend/app/routers/a.py"; printf 'desc: auth\n' > "$R/backend/app/core/openapi_meta.py"; printf '/a\n' > "$R/docs/openapi.json"
  for f in test_openapi_contract test_openapi_meta test_api_tags_doc; do printf '# %s\n' "$f" > "$R/backend/tests/$f.py"; done
  printf '# export\n' > "$R/backend/scripts/export_openapi.py"; printf '%s\n' "$FAKEPY" > "$R/backend/venv/bin/python3"; chmod +x "$R/backend/venv/bin/python3"
  printf 'pydantic==2.8.2\nfastapi==0.115.0\npydantic-settings==2.2.1\n' > "$R/backend/requirements.txt"
  printf 'backend/venv/\n' > "$R/.gitignore"; printf 'x\n' > "$R/README.md"
  git -C "$R" init -q -b main; git -C "$R" add -A; git -C "$R" commit -q -m base; B="$(git -C "$R" rev-parse HEAD)"; cd "$R" || exit 1; }
cyc(){ git -C "$R" add -A; git -C "$R" commit -q -m "cycle: $1"; A="$(git -C "$R" rev-parse HEAD)"; }   # commit whatever the case staged
# hook MODE : run the hook in R; sets RC, ST (status), AF (after sha)
hook(){ : > "$T/tl"; OVN_POSTCYCLE_CONTRACT="$1" ovn_postcycle_contract "$B" "$A" "$T/tl" item1; RC=$?; ST="$OVN_PCC_STATUS"; AF="$OVN_PCC_AFTER"; }
lastrow(){ tail -1 "$ROWS" 2>/dev/null; }
rows(){ : > "$ROWS"; }
tree_clean(){ [ -z "$(git -C "$R" status --porcelain)" ]; }

echo "== trigger"
mk gitlark
printf 'x2\n' >> "$R/README.md"; cyc readme
ok "1: a README-only cycle does not trigger" '! ovn_pcc_trigger "$B" "$A"'
mk gitlark; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc router
ok "2: a changed file under app/routers/ triggers" 'ovn_pcc_trigger "$B" "$A" | grep -q "^path:backend/app/routers/a.py"'
mk gitlark; mkdir -p "$R/backend/app/schemas"; printf 'x\n' > "$R/backend/app/schemas/p.py"; cyc schema
ok "3: a changed file under app/schemas/ triggers" 'ovn_pcc_trigger "$B" "$A" | grep -q "^path:backend/app/schemas/p.py"'
mk gitlark; printf 'app.include_router(x)\n' > "$R/backend/app/main.py"; cyc inc
ok "4: an added include_router line triggers (app/main.py)" 'ovn_pcc_trigger "$B" "$A" | grep -q "^added:+app.include_router"'
mk gitlark; printf 'router = APIRouter(prefix="/z", tags=["zz"])\n' > "$R/backend/app/zz.py"; cyc tags
ok "5: an added APIRouter(...tags=...) line triggers outside routers/" 'ovn_pcc_trigger "$B" "$A" | grep -q "^added:"'
mk gitlark; printf 'unrelated = 1\n' > "$R/backend/app/zz.py"; cyc other
ok "6: an unrelated python change does not trigger" '! ovn_pcc_trigger "$B" "$A"'

echo "== config"
mk gitlark
ovn_pcc_config
ok "7: autodetect finds backend, the artifact tests, the export script and the venv python" '[ "$PCC_DIR" = backend ] && [ "$PCC_TESTS" = "tests/test_api_tags_doc.py tests/test_openapi_contract.py tests/test_openapi_meta.py " ] && [ "$PCC_REGEN" = scripts/export_openapi.py ] && [ "$PCC_PY" = "$R/backend/venv/bin/python3" ]'
mk other; rm -rf "$R/backend"; ovn_pcc_config; RCC=$?
ok "8: a repo with no test_openapi* tests is not applicable" '[ "$RCC" = 1 ]'
mk gitlark; printf 'dir=backend\ntests=tests/test_openapi_meta.py\nregen=\nrm -rf /=1\n' > "$R/.ovn-postcycle.conf"; ovn_pcc_config
ok "9: .ovn-postcycle.conf is PARSED (tests override), never sourced; junk lines are ignored" '[ "$PCC_TESTS" = "tests/test_openapi_meta.py" ]'

echo "== shadow (default) measures and changes nothing"
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc route-no-regen; H="$(git -C "$R" rev-parse HEAD)"
unset OVN_POSTCYCLE_CONTRACT; : > "$T/tl"; ovn_postcycle_contract "$B" "$A" "$T/tl" i; RCD=$?
ok "10: the DEFAULT mode is shadow: would-regen row, rc 0, HEAD and tree untouched" '[ "$RCD" = 0 ] && [ "$OVN_PCC_STATUS" = would-regen ] && [ "$(git -C "$R" rev-parse HEAD)" = "$H" ] && tree_clean && [ "$(cat docs/openapi.json)" = "/a" ]'
ok "11: the shadow row names the failing id, the mode, the trigger and a count" 'lastrow | grep -q "gitlark	shadow	would-regen	" && lastrow | grep -q "test_frozen_contract_matches_the_live_app" && lastrow | grep -q "trigger=path:backend/app/routers/a.py" && lastrow | grep -q "n=1$"'
ok "12: the task log carries a would-regen line" 'grep -q "POSTCYCLE CONTRACT (shadow): would regenerate docs/openapi.json" "$T/tl"'
hook shadow
ok "13: a second run counts n=2" 'lastrow | grep -q "n=2$"'

echo "== enforce: regen commit"
mk gitlark; rows; mkdir -p "$R/backend/app/extra"; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc route; printf 'stray\n' > "$R/stray.txt"; git -C "$R" add stray.txt
hook enforce
ok "14: enforce commits the regenerated contract with the cycle (rc 0, status regen, AFTER advanced)" '[ "$RC" = 0 ] && [ "$ST" = regen ] && [ "$AF" != "$A" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$AF" ] && [ "$(git -C "$R" show HEAD:docs/openapi.json | tr "\n" " ")" = "/a /b " ]'
ok "15: the regen commit holds ONLY the regenerated file (the staged stray file is not swept in)" '[ "$(git -C "$R" show --name-only --format= HEAD)" = "docs/openapi.json" ] && git -C "$R" diff --cached --name-only | grep -qx stray.txt'
ok "16: the regen row is logged" 'lastrow | grep -q "	enforce	regen	"'
git -C "$R" reset -q stray.txt; rm -f "$R/stray.txt"
A="$AF"; hook enforce
ok "17: the same cycle re-checked after the regen is green (pass, no second commit)" '[ "$ST" = pass ] && [ "$AF" = "$A" ]'

echo "== enforce: a new red no regen can fix reverts"
mk gitlark; rows; printf 'route: /b\ntag: stage-runs\n' >> "$R/backend/app/routers/a.py"; cyc newtag
hook enforce
ok "18: an undescribed new tag -> rc 1, status revert" '[ "$RC" = 1 ] && [ "$ST" = revert ]'
ok "19: the tree is left as the cycle left it (the regen is undone; the CALLER resets)" 'tree_clean && [ "$(git -C "$R" rev-parse HEAD)" = "$A" ]'
ok "20: the revert row names ONLY the new id (the contract id the regen fixed is not listed)" 'lastrow | grep -q "	revert	" && lastrow | grep -q "test_every_route_tag_is_described" && ! lastrow | cut -f7 | grep -q frozen'
mk gitlark; rows; printf 'route: /b\ntag: stage-runs\n' >> "$R/backend/app/routers/a.py"; cyc newtag; hook shadow
ok "21: shadow: would-revert row, rc 0, nothing changed" '[ "$RC" = 0 ] && [ "$ST" = would-revert ] && tree_clean && lastrow | grep -q "	would-revert	"'
ok "22: the shadow would-revert task-log line" 'grep -q "would REVERT" "$T/tl"'

echo "== inherited red never reverts a later cycle (no cascade)"
mk gitlark; printf 'route: /i\ntag: old-undescribed\n' >> "$R/backend/app/routers/a.py"; printf '/a\n/i\n' > "$R/docs/openapi.json"; git -C "$R" add -A; git -C "$R" commit -q -m "red lane"; B="$(git -C "$R" rev-parse HEAD)"
rows; printf 'x\n' >> "$R/backend/app/routers/a.py"; cyc touch-router; hook enforce
ok "23: a cycle that adds nothing new on an already tag-red lane: inherited-red, rc 0" '[ "$RC" = 0 ] && [ "$ST" = inherited-red ] && lastrow | grep -q "old-undescribed\|test_every_route_tag_is_described"'
mk gitlark; printf 'route: /i\ntag: old-undescribed\n' >> "$R/backend/app/routers/a.py"; printf '/a\n/i\n' > "$R/docs/openapi.json"; git -C "$R" add -A; git -C "$R" commit -q -m "red lane"; B="$(git -C "$R" rev-parse HEAD)"
rows; printf 'route: /n\n' >> "$R/backend/app/routers/a.py"; cyc drift; hook enforce
ok "24: on a tag-red lane a contract drift cycle is still HEALED by the regen (the inherited tag red neither blocks nor is blamed)" '[ "$RC" = 0 ] && [ "$ST" = regen ] && [ "$(git -C "$R" show HEAD:docs/openapi.json | wc -l | tr -d " ")" = 3 ]'

echo "== scoping and safety"
mk gitlark; rows; printf 'route: /b\ntag: zz\n' >> "$R/backend/app/routers/a.py"; cyc newtag; mv "$R" "$T/xrepo"; R="$T/xrepo"; cd "$R" || exit 1
hook enforce
ok "25: enforce is limited to OVN_POSTCYCLE_ENFORCE_REPOS (default gitlark): another repo stays shadow" '[ "$RC" = 0 ] && [ "$ST" = would-revert ] && lastrow | grep -q "xrepo	shadow	would-revert"'
OVN_POSTCYCLE_ENFORCE_REPOS="xrepo gitlark" hook enforce
ok "26: the list is the switch (xrepo listed -> revert)" '[ "$RC" = 1 ] && [ "$ST" = revert ]'
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc route; hook off
ok "27: off = no row, rc 0, status off" '[ "$RC" = 0 ] && [ "$ST" = off ] && [ ! -s "$ROWS" ]'
mk gitlark; rows; printf 'x3\n' >> "$R/README.md"; cyc readme; hook enforce
ok "28: no trigger = no row, no test run" '[ "$ST" = no-trigger ] && [ ! -s "$ROWS" ]'
mk gitlark; rows; printf 'x\n' >> "$R/backend/app/routers/a.py"; cyc ok; hook enforce
ok "29: green artifact tests -> pass row" '[ "$ST" = pass ] && lastrow | grep -q "	pass	"'
mk gitlark; rows; printf 'route: /b\nCRASH\n' >> "$R/backend/app/routers/a.py"; cyc route; hook enforce
ok "30: tests that cannot run (no failing id, rc 2) -> unrunnable, rc 0, never a revert" '[ "$RC" = 0 ] && [ "$ST" = unrunnable ] && lastrow | grep -q "	unrunnable	"'
mk gitlark; rows; rm -f "$R/backend/venv/bin/python3"; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc route; hook enforce
ok "31: no venv python -> unrunnable, rc 0" '[ "$RC" = 0 ] && [ "$ST" = unrunnable ] && lastrow | grep -q "no venv python"'

echo "== regen guards (q-contract fix): venv-mismatch, regen-removes-paths, predirty, untracked undo, bounded log"
# 1. a venv whose pydantic differs from the repo pin never commits a regen
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; H="$(git -C "$R" rev-parse HEAD)"
FAKE_VER_pydantic=2.10.6 FAKE_VER_fastapi=0.115.0 hook enforce
ok "61: enforce + pydantic 2.10.6 installed vs the 2.8.2 pin -> venv-mismatch, rc 0, NO commit, tree clean" '[ "$RC" = 0 ] && [ "$ST" = venv-mismatch ] && [ "$(git -C "$R" rev-parse HEAD)" = "$H" ] && tree_clean && [ "$(cat docs/openapi.json)" = "/a" ]'
ok "62: the venv-mismatch row names the package, both versions, and the task log says skipped" 'lastrow | grep -q "	venv-mismatch	" && lastrow | grep -q "pydantic installed 2.10.6 != pin 2.8.2" && grep -q "regen skipped (venv-mismatch" "$T/tl"'
FAKE_VER_pydantic=2.10.6 hook shadow
ok "63: shadow + mismatch: the same skip, nothing run, tree clean" '[ "$ST" = venv-mismatch ] && tree_clean'
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift
FAKE_VER_pydantic=2.8.2 FAKE_VER_fastapi=0.115.0 hook enforce
ok "64: venv == pins (and pydantic-settings is not mistaken for pydantic) -> the valid regen is still committed" '[ "$RC" = 0 ] && [ "$ST" = regen ] && [ "$AF" != "$A" ] && [ "$(git -C "$R" show HEAD:docs/openapi.json | tr "\n" " ")" = "/a /b " ]'
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; hook enforce
ok "65: a package that is not installed (langsmith/none reported) is not a mismatch -> regen" '[ "$ST" = regen ]'
mk gitlark; rm -f "$R/backend/requirements.txt"; git -C "$R" add -A; git -C "$R" commit -q -m norequirements; B="$(git -C "$R" rev-parse HEAD)"; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift
FAKE_VER_pydantic=2.10.6 hook enforce
ok "66: a repo that documents no pins (no requirements) is not blocked by the venv guard" '[ "$ST" = regen ]'
# 2. a regen that removes an API path is rejected (inherited drift: the stale entry /old is not in the live app)
mk gitlark; printf '/a\n/old\n' > "$R/docs/openapi.json"; git -C "$R" add -A; git -C "$R" commit -q -m "stale entry"; B="$(git -C "$R" rev-parse HEAD)"
rows; printf '# touched\n' >> "$R/backend/app/routers/a.py"; cyc touch; H="$(git -C "$R" rev-parse HEAD)"; hook enforce
ok "67: a regen that would remove path /old -> regen-removes-paths, rc 0, nothing committed, artifact restored" '[ "$RC" = 0 ] && [ "$ST" = regen-removes-paths ] && [ "$(git -C "$R" rev-parse HEAD)" = "$H" ] && tree_clean && [ "$(wc -l < docs/openapi.json | tr -d " ")" = 2 ]'
ok "68: the row names the removed path" 'lastrow | grep -q "	regen-removes-paths	" && lastrow | grep -q "removed: /old"'
hook shadow
ok "69: shadow: the same row, tree clean" '[ "$ST" = regen-removes-paths ] && tree_clean'
J="$T/jrepo"; rm -rf "$J"; mkdir -p "$J"; git -C "$J" init -q -b main
printf '{\n  "paths": {\n    "/api/x": {\n      "get": {}\n    },\n    "/api/y": {\n      "get": {}\n    }\n  },\n  "components": {\n    "P": {\n      "allOf": [\n        {"$ref": "#/Q"}\n      ]\n    }\n  }\n}\n' > "$J/o.json"; git -C "$J" add -A; git -C "$J" commit -q -m j
( cd "$J" && sed -i.bak '/"\/api\/y": {/,+2d' o.json && rm -f o.json.bak; ovn_pcc_removed_paths o.json > "$T/rm1"; echo $? > "$T/rm1.rc" )
ok "70: on a real JSON artifact, deleting a paths key is detected (/api/y)" '[ "$(cat "$T/rm1.rc")" = 0 ] && grep -q "\"/api/y\"" "$T/rm1"'
( cd "$J" && git checkout -q -- o.json && python3 - <<'PYEOF'
import json,collections
d=json.load(open("o.json"),object_pairs_hook=collections.OrderedDict)
d["paths"]=collections.OrderedDict(reversed(list(d["paths"].items())))
d["components"]["P"]={"$ref":"#/Q"}
json.dump(d,open("o.json","w"),indent=2)
PYEOF
ovn_pcc_removed_paths o.json > "$T/rm2"; echo $? > "$T/rm2.rc" )
ok "71: a pure reorder of paths plus an allOf->bare-ref flip removes no path key (the flip is the venv guard's job)" '[ "$(cat "$T/rm2.rc")" = 1 ] && [ ! -s "$T/rm2" ]'
# 3. pre-dirty artifact and untracked outputs
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; H="$(git -C "$R" rev-parse HEAD)"; printf 'hand edit\n' > "$R/docs/openapi.json"
hook enforce
ok "72: an artifact already dirty before the hook -> predirty skip: rc 0, no commit, the hand edit untouched" '[ "$RC" = 0 ] && [ "$ST" = predirty ] && [ "$(git -C "$R" rev-parse HEAD)" = "$H" ] && [ "$(cat docs/openapi.json)" = "hand edit" ] && lastrow | grep -q "	predirty	"'
hook shadow
ok "73: shadow + predirty: same, the hand edit is never checked out" '[ "$ST" = predirty ] && [ "$(cat docs/openapi.json)" = "hand edit" ]'
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; FAKE_EXPORT_EXTRA=1 hook shadow
ok "74: shadow undo also removes an UNTRACKED regen output (and restores the tracked one): tree clean" '[ "$ST" = would-regen ] && tree_clean && [ ! -e docs/extra_generated.json ] && [ "$(cat docs/openapi.json)" = "/a" ]'
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; FAKE_EXPORT_EXTRA=1 hook enforce
ok "75: enforce commits the untracked output together with the artifact" '[ "$ST" = regen ] && git -C "$R" show --name-only --format= HEAD | grep -qx docs/extra_generated.json && tree_clean'
mk gitlark; rows; printf 'route: /b\ntag: nodesc\n' >> "$R/backend/app/routers/a.py"; cyc newtag; FAKE_EXPORT_EXTRA=1 hook enforce
ok "76: the revert path also cleans the untracked regen output" '[ "$ST" = revert ] && tree_clean && [ ! -e docs/extra_generated.json ]'
# 4. bounded log
mk gitlark; rows; i=0; : > "$ROWS"; yes "2026-01-01 00:00:00	gitlark	shadow	pass	b	a			x	n=1" | head -n 6500 >> "$ROWS"
printf 'x\n' >> "$R/backend/app/routers/a.py"; cyc ok; hook shadow
ok "77: a log over 6000 lines is trimmed to ~5000 on the next row, the new row is last" '[ "$(wc -l < "$ROWS" | tr -d " ")" -le 5001 ] && [ "$(wc -l < "$ROWS" | tr -d " ")" -ge 4900 ] && lastrow | grep -q "	pass	"'
ok "78: no tmp file is left behind by the trim" '[ -z "$(ls "$T/state" | grep "contract_regen_shadow.log.tmp")" ]'
mk gitlark; rows; yes "2026-01-01 00:00:00	gitlark	shadow	pass	b	a			x	n=1" | head -n 5990 >> "$ROWS"; printf 'x\n' >> "$R/backend/app/routers/a.py"; cyc ok; hook shadow
ok "79: a log under the threshold is not trimmed" '[ "$(wc -l < "$ROWS" | tr -d " ")" = 5991 ]'

echo "== wiring in run_overnight.sh"
RO="$Q/run_overnight.sh"
ok "32: run_overnight.sh sources the lib with a fail-open stub" 'grep -q "source \"\$SCRIPT_DIR/scripts/lib_postcycle_contract.sh\" 2>/dev/null || ovn_postcycle_contract()" "$RO"'
ok "33: the call sits AFTER the NO-NEW-RED revert and BEFORE the TEST-ONLY GUARD" '[ "$(grep -n "POST-CYCLE CONTRACT HOOK (q-contract" "$RO" | cut -d: -f1)" -gt "$(grep -n "^      # NO-NEW-RED GUARD (2026-08-29)" "$RO" | cut -d: -f1)" ] && [ "$(grep -n "POST-CYCLE CONTRACT HOOK (q-contract" "$RO" | cut -d: -f1)" -lt "$(grep -n "^      # TEST-ONLY GUARD (2026-10-09" "$RO" | cut -d: -f1)" ]'
ok "34: the OLD pre-verify auto-regen is still there (the hook adds, it does not replace)" 'grep -q "chore(contract): auto-regenerate openapi.json" "$RO"'
ok "35: syntax" 'bash -n "$RO" && bash -n "$LIB"'
n1="$(grep -n "POST-CYCLE CONTRACT HOOK (q-contract" "$RO" | cut -d: -f1)"; n2="$(grep -n "^      # TEST-ONLY GUARD (2026-10-09" "$RO" | cut -d: -f1)"
{ echo 'blk(){'; sed -n "$((n1+3)),$((n2-1))p" "$RO"; echo '}'; } > "$T/block.sh"
ok "36: call-site block extracted" 'bash -n "$T/block.sh" && grep -q ovn_postcycle_contract "$T/block.sh"'
mk gitlark; printf 'route: /b\ntag: zz\n' >> "$R/backend/app/routers/a.py"; cyc bad
emit_alert(){ echo "$*" >> "$T/alerts"; }
runblock(){ ( . "$T/block.sh"; BEFORE_SHA="$B"; AFTER_SHA="$A"; VERIFY_RESULT="${1:-pass}"; id=i; task_log="$T/tl"; branch=main; blk ) ; }
OVN_POSTCYCLE_CONTRACT=enforce; export OVN_POSTCYCLE_CONTRACT
out="$(runblock)"
ok "37: the real block on a hook revert resets to BEFORE_SHA and reports no-op(reverted-red)" '[ "$out" = "no-op(reverted-red)" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$B" ] && grep -q "postcycle contract hook" "$T/alerts"'
mk gitlark; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift
cat > "$T/blk_tail.sh" <<'EOF'
tailchk(){ echo "AFTER=$AFTER_SHA LAND=${_ovn_land_sha:-}"; }
EOF
runblock2(){ ( . "$T/block.sh"; . "$T/blk_tail.sh"; BEFORE_SHA="$B"; AFTER_SHA="$A"; VERIFY_RESULT=pass; id=i; task_log="$T/tl"; branch=main; blk; tailchk ); }
out="$(runblock2)"
ok "38: the real block on a regen follows the new sha (AFTER_SHA and the landing-check sha)" 'h="$(git -C "$R" rev-parse HEAD)"; [ "$h" != "$A" ] && [ "$out" = "AFTER=$h LAND=$h" ]'
OVN_POSTCYCLE_CONTRACT=shadow
out="$(runblock fail)"
ok "39: the block does not run when the cycle is already red (VERIFY_RESULT=fail)" '[ -z "$out" ]'
unset OVN_POSTCYCLE_CONTRACT

echo "== gate-red report (read only)"
RPT="$Q/ovn_gate_red_report.py"
cat > "$T/hyg.log" <<'EOF'
[branch-hygiene 2026-11-25 09:00:01] === gitlark (repos/gitlark) ===
[branch-hygiene 2026-11-25 09:03:00]   MERGED gitlark overnight/feature (+3) -> develop (r
[branch-hygiene 2026-11-25 10:00:01] === gitlark (repos/gitlark) ===
FAILED tests/test_openapi_meta.py::test_every_route_tag_is_described - Assert...
FAILED tests/test_x.py::test_y
[branch-hygiene 2026-11-25 10:02:49]   gate FAILED (build/tests red) for gitlark — NOT merging, flagged for review
[branch-hygiene 2026-11-25 10:02:49] === shrike-notify (repos/shrike-notify) ===
[branch-hygiene 2026-11-25 10:03:00]   MERGED shrike-notify overnight/feature (+1) -> develop (r
[branch-hygiene 2026-11-25 11:00:01] === gitlark (repos/gitlark) ===
FAILED tests/test_openapi_meta.py::test_every_route_tag_is_described - Assert...
FAILED tests/test_openapi_contract.py::test_frozen_contract_matches_the_live_app
[branch-hygiene 2026-11-25 11:02:49]   gate FAILED (build/tests red) for gitlark — NOT merging, flagged for review
EOF
out="$(python3 "$RPT" --log "$T/hyg.log" --repo gitlark)"
ok "40: one red streak, still red, 2 red passes, first-failure ids, per-id pass counts" 'grep -q "STILL RED), 2 red pass" <<< "$out" && grep -q "first-failure ids (cause): tests/test_openapi_meta.py::test_every_route_tag_is_described, tests/test_x.py::test_y" <<< "$out" && grep -q "test_every_route_tag_is_described .* 2 pass" <<< "$out"'
ok "41: an id that first appears in a later pass is flagged [appeared later]" 'grep -q "test_frozen_contract_matches_the_live_app.*1 pass.*appeared later" <<< "$out"'
ok "42: the streak starts at the first red pass (10:00:01), not the last green merge" 'grep -q "RED 2026-11-25 10:00:01 -> 2026-11-25 11:00:01" <<< "$out"'
ok "43: another repo (shrike-notify) is not in a gitlark report" '! grep -q shrike-notify <<< "$out"'
ok "44: --json is valid json with the streak" 'python3 "$RPT" --log "$T/hyg.log" --json | python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"streaks\"][0][\"n\"]==2 and d[\"current\"][\"gitlark\"]==\"red\""'
python3 "$RPT" --log "$T/hyg.log" --repo gitlark --git "$R" > "$T/o2" 2>&1
ok "45: --git on a clone lists commits (or n/a) without failing" 'grep -q "commits landed" "$T/o2"'
ok "46: py_compile" 'python3 -m py_compile "$RPT"'

echo "== MUTANTS (each must break the cases it guards)"
mut(){ cp "$LIB" "$T/mut.sh"; sed "$1" "$LIB" > "$T/mut.sh"; ! cmp -s "$T/mut.sh" "$LIB"; }
# M1: no baseline compare (every failing id is blamed on the cycle)
mut 's/new2="$(_pcc_ids_minus "$f2" "$f0")"/new2="$(_pcc_ids_minus "$f2" "")"/'; ok "47: mutant M1 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; printf 'route: /i\ntag: old-undescribed\n' >> "$R/backend/app/routers/a.py"; printf '/a\n/i\n' > "$R/docs/openapi.json"; git -C "$R" add -A; git -C "$R" commit -q -m "red lane"; B="$(git -C "$R" rev-parse HEAD)"
rows; printf 'x\n' >> "$R/backend/app/routers/a.py"; cyc touch; hook enforce
ok "48: M1 reverts a cycle for an INHERITED red (the cascade) - case 23 catches it" '[ "$RC" = 1 ]'
. "$LIB"
# M2: bare commit (sweeps staged files)
mut "s/(postcycle contract hook)\" -- \\\$changed/(postcycle contract hook)\"/"; ok "49: mutant M2 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc route; printf 'stray\n' > "$R/stray.txt"; git -C "$R" add stray.txt; hook enforce
ok "50: M2 sweeps the staged stray file into the regen commit - case 15 catches it" 'git -C "$R" show --name-only --format= HEAD | grep -qx stray.txt'
. "$LIB"
# M3: shadow acts
mut 's/^  eff="\$mode"$/  eff=enforce/'; ok "51: mutant M3 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc route; H="$(git -C "$R" rev-parse HEAD)"; hook shadow
ok "52: M3 shadow mode commits a regen - case 10 catches it" '[ "$(git -C "$R" rev-parse HEAD)" != "$H" ]'
. "$LIB"
# M4: trigger ignores app/routers
mut 's#app/(routers|schemas)/#app/(zzz)/#'; ok "53: mutant M4 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc route; hook enforce
ok "54: M4 never triggers on a router change - cases 2/14 catch it" '[ "$ST" = no-trigger ]'
. "$LIB"
# M5: enforce not scoped to the repo list
mut 's/\*" \$repo "\*) ;; \*) eff=shadow;;/*" $repo "*) ;; *) :;;/'; ok "55: mutant M5 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; printf 'route: /b\ntag: zz\n' >> "$R/backend/app/routers/a.py"; cyc newtag; mv "$R" "$T/yrepo"; R="$T/yrepo"; cd "$R" || exit 1; hook enforce
ok "56: M5 enforces on an unlisted repo - case 25 catches it" '[ "$RC" = 1 ]'
. "$LIB"
# M6: a crashed run counts as red
mut 's/if \[ -z "\$f1" \]; then OVN_PCC_STATUS="unrunnable"/if false; then OVN_PCC_STATUS="unrunnable"/'; ok "57: mutant M6 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; rows; printf 'route: /b\nCRASH\n' >> "$R/backend/app/routers/a.py"; cyc route; hook enforce
ok "58: M6 does not stop at an unrunnable test run - case 30 catches it" '[ "$ST" != unrunnable ]'
. "$LIB"
# M7: the report regex that read "for review" as the repo (greedy .*)
sed 's/\^gate FAILED \\(\[^)\]\*\\) for/^gate FAILED .* for/' "$RPT" > "$T/rpt_old.py"
ok "59: mutant M7 differs" '! cmp -s "$T/rpt_old.py" "$RPT"'
out="$(python3 "$T/rpt_old.py" --log "$T/hyg.log" --repo gitlark)"
ok "60: M7 (greedy regex: the repo is parsed as 'review') finds NO red streak - cases 40-42 catch it" 'grep -q "no red streaks" <<< "$out"'

# M8: no venv guard
mut 's/if vm="$(ovn_pcc_venv_mismatch)"; then/if true; then/'; ok "61m: mutant M8 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; rows; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; FAKE_VER_pydantic=2.10.6 hook enforce
ok "62m: M8 commits a regen from a mismatched venv - cases 61/62 catch it" '[ "$ST" = regen ]'
. "$LIB"
# M9: no removal guard
mut 's/if rm_paths="$(ovn_pcc_removed_paths $changed)"; then/if false; then/'; ok "63m: mutant M9 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; printf '/a\n/old\n' > "$R/docs/openapi.json"; git -C "$R" add -A; git -C "$R" commit -q -m "stale entry"; B="$(git -C "$R" rev-parse HEAD)"
printf '# touched\n' >> "$R/backend/app/routers/a.py"; cyc touch; hook enforce
ok "64m: M9 commits the regen that dropped /old - case 67 catches it" '[ "$ST" = regen ] && [ "$(git -C "$R" show HEAD:docs/openapi.json | tr "\n" " ")" = "/a " ]'
. "$LIB"
# M10: no predirty guard
mut 's/grep -qE "$OVN_PCC_PATH_ERE"; then/grep -qE "NOMATCHXX"; then/'
. "$T/mut.sh"
mk gitlark; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; printf 'hand edit\n' > "$R/docs/openapi.json"; hook shadow
ok "66m: M10 runs over the hand edit and checks it out (the dirty work is lost) - case 73 catches it" '[ "$(cat docs/openapi.json)" != "hand edit" ]'
. "$LIB"
# M11: the old undo (git checkout of every changed path, untracked ones included)
mut 's/^      _pcc_undo "$changed"$/      git checkout -q -- $changed 2>\/dev\/null/'; ok "67m: mutant M11 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; printf 'route: /b\n' >> "$R/backend/app/routers/a.py"; cyc drift; FAKE_EXPORT_EXTRA=1 hook shadow
ok "68m: M11 leaves the tree dirty (checkout aborts on the untracked path) - case 74 catches it" '! tree_clean'
. "$LIB"
# M12: no trim
mut 's/-gt "${OVN_PCC_LOG_MAX:-6000}"/-gt 99999999/'; ok "69m: mutant M12 differs" '! cmp -s "$T/mut.sh" "$LIB"'
. "$T/mut.sh"
mk gitlark; rows; yes "x	gitlark	shadow	pass	b	a			x	n=1" | head -n 6500 >> "$ROWS"; printf 'x\n' >> "$R/backend/app/routers/a.py"; cyc ok; hook shadow
ok "70m: M12 never trims - case 77 catches it" '[ "$(wc -l < "$ROWS" | tr -d " ")" -gt 6000 ]'
. "$LIB"

echo "q-contract: $P passed, $F failed"; [ "$F" = 0 ]
