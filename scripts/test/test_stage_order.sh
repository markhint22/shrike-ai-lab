#!/usr/bin/env bash
# D3-step-ordering (2026-10-18): dependency-aware ordering of staged steps + queue items (scripts/ovn_stage_order.py, wired into ovn_stage_runner.sh).
#   Part U: python unit + REAL-DATA replay + mutants (test_stage_order.py; runs anywhere).
#   Part E: the real runner in the hermetic fixture (needs GNU sed + bash 5: the box). OVN_STAGE_ORDER=off|shadow|enforce.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
unset OVN_STAGE_ORDER OVN_STAGE_ORDER_LOG OVN_STAGE_ORDER_MERGE_MAX_FILES OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP NTFY_SERVER NTFY_TOPIC
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"; osr_cleanup' EXIT
echo "== U: unit, real-data replay, mutants"
OVN_TEST_TMP="$W" python3 -I "$HERE/test_stage_order.py" > "$W/u.out" 2>&1; urc=$?
cat "$W/u.out"
t "U: test_stage_order.py exits 0" test "$urc" -eq 0
t "U: runner sources no new lib and still parses (bash -n)" bash -n "$RUNNER"
t "U: the module compiles under python3 -I" python3 -I -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$REALQ/scripts/ovn_stage_order.py"
echo "== S: run_overnight.sh scout-slice filter (the 'Doable Next Steps' list the scout is shown); real function, real TAA group, mutants"
RO="$REALQ/run_overnight.sh"; SD="$W/s"; mkdir -p "$SD/scripts" "$SD/state"
cp "$REALQ/scripts/ovn_stage_order.py" "$SD/scripts/"; cp "$HERE/fixtures/stage_order/group_taa_get_live_role.md" "$SD/OVERNIGHT_PROGRESS.md"
sed -n '/^# >>> d3 scout-slice filter/,/^# <<< d3 scout-slice filter/p' "$RO" > "$SD/slice.sh"
t "S0 the marked function block is present in run_overnight.sh" test -s "$SD/slice.sh"
slice(){ # $1 = function file, $2 = mode, stdin = lines  (cwd = the fake repo)
  ( cd "$SD" && SCRIPT_DIR="$SD" STATE_DIR="$SD/state" OVN_STAGE_ORDER="$2" bash -c ". '$1'; _ovn_so_slice_filter" ); }
ALL="$(grep '^- \[ \] ' "$SD/OVERNIGHT_PROGRESS.md")"; TESTS="$(printf '%s\n' "$ALL" | grep -E '\[T[345]\]')"
rm -f "$SD/state/stage_order_shadow.log"
t "S1 shadow: every line passes through unchanged" test "$(printf '%s\n' "$ALL" | slice "$SD/slice.sh" shadow)" = "$ALL"
t "S1 shadow: would_skip_item journaled for the 3 test lines" bash -c "[ \"\$(grep -c would_skip_item '$SD/state/stage_order_shadow.log')\" = 3 ]"
rm -f "$SD/state/stage_order_shadow.log"
t "S2 enforce: only the two source lines (T1,T2) are offered" test "$(printf '%s\n' "$ALL" | slice "$SD/slice.sh" enforce | grep -cE '\[T[12]\]')" = 2 -a "$(printf '%s\n' "$ALL" | slice "$SD/slice.sh" enforce | wc -l | tr -d ' ')" = 2
t "S2 enforce: skipped_item journaled" grep -q skipped_item "$SD/state/stage_order_shadow.log"
t "S3 enforce: a filter that would EMPTY the slice returns the input (scout never starved)" test "$(printf '%s\n' "$TESTS" | slice "$SD/slice.sh" enforce)" = "$TESTS"
t "S4 off: unchanged, python never consulted" test "$(printf '%s\n' "$ALL" | slice "$SD/slice.sh" off)" = "$ALL"
mv "$SD/scripts/ovn_stage_order.py" "$SD/scripts/x.py"
t "S5 helper missing: unchanged (fail-open)" test "$(printf '%s\n' "$ALL" | slice "$SD/slice.sh" enforce)" = "$ALL"
mv "$SD/scripts/x.py" "$SD/scripts/ovn_stage_order.py"
t "S6 empty input: no output" test -z "$(printf '' | slice "$SD/slice.sh" enforce)"
# mutants: each broken copy of the function must FAIL the check that guards it
sed 's/ && \[ -n "\$_out" \]//' "$SD/slice.sh" > "$SD/mut_nofailopen.sh"
t "S7 mutant (no empty-result fail-open) is caught by S3" test "$(printf '%s\n' "$TESTS" | slice "$SD/mut_nofailopen.sh" enforce)" != "$TESTS"
sed 's/item-filter --mode "\$_m"/item-filter --mode shadow/' "$SD/slice.sh" > "$SD/mut_noenforce.sh"
t "S8 mutant (mode ignored: never enforces) is caught by S2" test "$(printf '%s\n' "$ALL" | slice "$SD/mut_noenforce.sh" enforce | wc -l | tr -d ' ')" != 2
t "S9 the slice filter sits between ovn_bug_first_order and ovn_progress_slice.py in run_overnight.sh" bash -c "grep -B1 -A1 '_ovn_so_slice_filter \\\\' '$RO' | tr -d '\n' | grep -q 'ovn_bug_first_order .*_ovn_so_slice_filter .*ovn_progress_slice.py'"
# --- D3 repair 2: shell default, off / missing-progress guards, --repo argument, timeout (a stub python3 on PATH records argv; empty stdout => the wrapper falls back to the input)
STUB="$W/stub"; mkdir -p "$STUB"; printf '#!/bin/sh\necho "$@" >> "%s/argv.log"\ncat >/dev/null\n' "$W" > "$STUB/python3"; chmod +x "$STUB/python3"
stubslice(){ # $1 = function file, $2 = mode ("unset" = OVN_STAGE_ORDER not set at all), extra env via remaining args; stdin = lines
  local f="$1" m="$2"; shift 2
  if [ "$m" = unset ]; then ( cd "$SD" && env -u OVN_STAGE_ORDER PATH="$STUB:$PATH" SCRIPT_DIR="$SD" STATE_DIR="$SD/state" "$@" bash -c ". '$f'; _ovn_so_slice_filter" )
  else ( cd "$SD" && env PATH="$STUB:$PATH" SCRIPT_DIR="$SD" STATE_DIR="$SD/state" OVN_STAGE_ORDER="$m" "$@" bash -c ". '$f'; _ovn_so_slice_filter" ); fi; }
unsetslice(){ ( cd "$SD" && env -u OVN_STAGE_ORDER SCRIPT_DIR="$SD" STATE_DIR="$SD/state" bash -c ". '$1'; _ovn_so_slice_filter" ); }
argv_calls(){ [ -f "$W/argv.log" ] && wc -l < "$W/argv.log" | tr -d ' ' || echo 0; }
s10check(){ rm -f "$SD/state/stage_order_shadow.log"; [ "$(printf '%s\n' "$ALL" | unsetslice "$SD/slice.sh")" = "$ALL" ] && grep -q would_skip_item "$SD/state/stage_order_shadow.log"; }
t "S10 OVN_STAGE_ORDER unset: the default is SHADOW (every line passes through unchanged, would_skip journaled)" s10check
sed 's/_m="\${OVN_STAGE_ORDER:-shadow}"/_m="${OVN_STAGE_ORDER:-enforce}"/' "$SD/slice.sh" > "$SD/mut_defenforce.sh"
t "S10m mutant (shell default flipped to enforce) is caught by S10's check" test "$(printf '%s\n' "$ALL" | unsetslice "$SD/mut_defenforce.sh")" != "$ALL"
rm -f "$W/argv.log"; printf '%s\n' "$ALL" | stubslice "$SD/slice.sh" off >/dev/null
t "S11 off: python is never consulted (stub saw 0 calls)" test "$(argv_calls)" = 0
sed 's/\[ "\$_m" = off \] || //' "$SD/slice.sh" > "$SD/mut_nooff.sh"
rm -f "$W/argv.log"; printf '%s\n' "$ALL" | stubslice "$SD/mut_nooff.sh" off >/dev/null
t "S11m mutant (off guard removed) is caught: python consulted in off mode" test "$(argv_calls)" != 0
mv "$SD/OVERNIGHT_PROGRESS.md" "$SD/OVERNIGHT_PROGRESS.md.bak"
rm -f "$W/argv.log"; printf '%s\n' "$ALL" | stubslice "$SD/slice.sh" enforce >/dev/null
t "S12 progress file missing: python never consulted, input passes through" test "$(argv_calls)" = 0 -a "$(printf '%s\n' "$ALL" | stubslice "$SD/slice.sh" enforce)" = "$ALL"
sed 's/ || \[ ! -f OVERNIGHT_PROGRESS.md \]//' "$SD/slice.sh" > "$SD/mut_nopf.sh"
rm -f "$W/argv.log"; printf '%s\n' "$ALL" | stubslice "$SD/mut_nopf.sh" enforce >/dev/null
t "S12m mutant (missing-progress guard removed) is caught" test "$(argv_calls)" != 0
mv "$SD/OVERNIGHT_PROGRESS.md.bak" "$SD/OVERNIGHT_PROGRESS.md"
rm -f "$W/argv.log"; printf '%s\n' "$ALL" | stubslice "$SD/slice.sh" shadow >/dev/null
t "S13 --repo is the basename of the repo cwd, and the mode is passed (argv: item-filter --mode shadow ... --repo s)" bash -c "grep -q -- '--mode shadow' '$W/argv.log' && grep -q -- '--repo s ' '$W/argv.log' && grep -q -- '--progress OVERNIGHT_PROGRESS.md' '$W/argv.log'"
sed 's/--repo "\$(basename "\$PWD")"/--repo x/' "$SD/slice.sh" > "$SD/mut_repo.sh"
rm -f "$W/argv.log"; printf '%s\n' "$ALL" | stubslice "$SD/mut_repo.sh" shadow >/dev/null
t "S13m mutant (--repo hard-coded) is caught" bash -c "! grep -q -- '--repo s ' '$W/argv.log'"
# timeout: a hung filter must not stall the scout
printf '#!/bin/sh\nsleep 8\n' > "$STUB/python3"
SECS0=$SECONDS; OUT14="$(printf '%s\n' "$ALL" | stubslice "$SD/slice.sh" shadow OVN_STAGE_ORDER_TIMEOUT=1)"; EL=$((SECONDS-SECS0))
t "S14 a hung filter is cut by the timeout: input returned in < 6s (took ${EL}s)" test "$OUT14" = "$ALL" -a "$EL" -lt 6
sed 's/\${_to\[@\]+"\${_to\[@\]}"} //' "$SD/slice.sh" > "$SD/mut_noto.sh"
SECS0=$SECONDS; printf '%s\n' "$ALL" | stubslice "$SD/mut_noto.sh" shadow OVN_STAGE_ORDER_TIMEOUT=1 >/dev/null; EL=$((SECONDS-SECS0))
t "S14m mutant (timeout removed) is caught: took ${EL}s >= 6" test "$EL" -ge 6
if ! sed --version >/dev/null 2>&1; then echo "  (Part E skipped: needs GNU sed; run on the box)"; osr_summary; exit $?; fi

so_new(){ osr_new; cp "$REALQ/scripts/ovn_stage_order.py" "$Q/scripts/"; local f; for f in lib_stage_guards.sh lib_verify_clause.sh ovn_stage_guards.py ovn_backlog_eligibility.py ovn_credit_items.py ovn_spec_rules.py ovn_verify_safe.py ovn_gut_clause.py lib_item_select.sh; do
    [ -f "$REALQ/scripts/$f" ] && cp "$REALQ/scripts/$f" "$Q/scripts/"; done; osr_venv backend; }
# a test-first plan (the defect): the test step that needs foo comes BEFORE the step that creates it
PLAN_TF='[{"desc":"Add test test_foo_helper for the `foo_helper` helper","files":["backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"},{"desc":"Add `foo_helper` function returning 1","files":["backend/app/foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
ITEM_TF='[T3] backend/app/foo.py — Add `foo` helper with its test. VERIFY: `pytest backend/tests/test_foo.py` (cat:python; multifile:no)'
SNIP_TF='mkdir -p backend/app backend/tests
printf "def foo_helper():\n    return 1\n" > backend/app/foo.py
printf "from app.foo import foo_helper\n\ndef test_foo_helper():\n    assert foo_helper() == 1\n" > backend/tests/test_foo.py
echo "Applied edit to backend/app/foo.py"'
run_tf(){ rm -f "$T/llm/n" "$T/scn/aider.n"; osr_plan default "$PLAN_TF"; osr_aider default "$SNIP_TF"; OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO" "$ITEM_TF"; }
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }

echo "== E1: shadow (the default) journals the would-have decision and changes nothing"
so_new; run_tf
t "E1 plan has the model's 2 steps (unchanged)" J '"event":"decomposed","steps":2'
t "E1 step_order event journaled, mode shadow" J '"event":"step_order","mode":"shadow"'
t "E1 would_park_dep journaled for the test-first step" J '"event":"would_park_dep"'
t "E1 shadow never parks (no step_parked_dep)" bash -c "! grep -qF step_parked_dep '$Q'/state/stage_runs/$OSR_REPO-*.jsonl"
t "E1 shadow log row in state/stage_order_shadow.log" grep -q '"would_reorder"' "$Q/state/stage_order_shadow.log"
osr_cleanup

echo "== E2: enforce merges the red-by-design test step into the fix step (ONE commit)"
so_new; OVN_STAGE_ORDER=enforce run_tf
t "E2 plan collapsed to 1 merged step" J '"event":"decomposed","steps":1'
t "E2 step_order event, mode enforce, action merge" bash -c "grep -F '\"event\":\"step_order\",\"mode\":\"enforce\"' '$Q'/state/stage_runs/$OSR_REPO-*.jsonl | grep -qF '\"action\":\"merge\"'"
t "E2 the merged run landed 1/1" J '"passed":1,"total":1'
t "E2 origin has the fix AND its test (same commit)" bash -c "git -C '$O' show overnight/feature:backend/app/foo.py >/dev/null && git -C '$O' show overnight/feature:backend/tests/test_foo.py >/dev/null"
osr_cleanup

echo "== E3: enforce parks a step whose prerequisite did not land (and the item is never credited as whole)"
so_new
PLAN_DEP='[{"desc":"Add `bar_value` function in bar.py","files":["backend/app/bar.py"],"verify":"pytest backend/tests/test_bar.py"},{"desc":"Wire `bar_value` into the handler","files":["backend/app/svc.py"],"verify":"pytest backend/tests/test_svc.py","depends_on":[0]}]'
osr_progress "- [ ] [T3] backend/app/bar.py — Add \`bar_value\` and wire it. VERIFY: \`pytest backend/tests/test_svc.py\` (cat:python; multifile:no)"
rm -f "$T/llm/n" "$T/scn/aider.n"; osr_plan default "$PLAN_DEP"; echo "exit 0" > "$T/scn/aider.default"   # aider edits nothing: step 0 cannot land
OVN_STAGE_ORDER=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E3 step 1 parked on its unlanded prerequisite (step_parked_dep)" J '"event":"step_parked_dep"'
t "E3 aider ran only for step 0 (the parked step never invoked it)" bash -c "[ \"\$(ls '$T'/scn/aider.args.* 2>/dev/null | wc -l | tr -d ' ')\" -le 2 ] && ! grep -qF 'wire' '$T'/scn/aider.args.* 2>/dev/null"
t "E3 the item is not checked off (still '- [ ]' in origin)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] .*bar_value' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] .*bar_value'"
osr_cleanup

echo "== E4: OVN_STAGE_ORDER=off is byte-for-byte the old behaviour"
so_new; OVN_STAGE_ORDER=off run_tf
t "E4 no step_order event, no shadow log" bash -c "! grep -qF step_order '$Q'/state/stage_runs/$OSR_REPO-*.jsonl && [ ! -e '$Q/state/stage_order_shadow.log' ]"
t "E4 plan kept (2 steps)" J '"event":"decomposed","steps":2'
osr_cleanup

echo "== E5: the picker - enforce skips a queue item whose feature-group prerequisite is open; shadow still takes it"
IT_TEST='[T3] backend/tests/test_foo.py — Add test `test_foo_value` for the `foo_value` helper. VERIFY: `pytest backend/tests/test_foo.py` (cat:test; multifile:no) [feat:g1]'
IT_SRC='[T3] backend/app/foo.py — Add `foo_value` function returning 1. VERIFY: `pytest backend/tests/test_foo.py` (cat:python; multifile:no) [feat:g1]'
so_new; osr_progress "- [ ] $IT_TEST" "- [ ] $IT_SRC"; rm -f "$T/llm/n"; osr_plan default '[{"desc":"add foo","files":["backend/app/foo.py"],"verify":"pytest"}]'; osr_run "$OSR_REPO"
t "E5 shadow: picks the test-first item (file order, unchanged)" grep -qF 'ITEM (T3): [T3] backend/tests/test_foo.py' "$T/out.txt"
t "E5 shadow: would_skip_item journaled" grep -q '"would_skip_item"' "$Q/state/stage_order_shadow.log"
osr_cleanup
so_new; osr_progress "- [ ] $IT_TEST" "- [ ] $IT_SRC"; rm -f "$T/llm/n"; osr_plan default '[{"desc":"add foo","files":["backend/app/foo.py"],"verify":"pytest"}]'; OVN_STAGE_ORDER=enforce osr_run "$OSR_REPO"
t "E5 enforce: picks the SOURCE item first" grep -qF 'ITEM (T3): [T3] backend/app/foo.py' "$T/out.txt"
t "E5 enforce: skipped_item journaled" grep -q '"skipped_item"' "$Q/state/stage_order_shadow.log"
osr_cleanup
osr_summary
