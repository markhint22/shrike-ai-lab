#!/usr/bin/env bash
# D2-prestate-credit (2026-10-18): pre-edit already-satisfied credit + duplicate-spend guard for staged items (ovn_precredit.py + stage_precredit_run in ovn_stage_runner.sh).
# OVN_STAGE_PRECREDIT=off|shadow|enforce (default shadow). Part U: the deterministic decision module (python, runs anywhere) incl. MUTANTS that prove the assertions bite.
# Part E: the real runner in the fixture (GNU sed + bash 5: the box) - shadow journals only, enforce credits with ZERO model calls, a vacuous VERIFY never credits.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_VERIFYONLY_PREFLIGHT OVN_STAGE_ITEM_VERIFY OVN_STAGE_IV_SHADOW_LOG OVN_STAGE_VERIFYONLY_LOG OVN_STAGE_PRECREDIT OVN_STAGE_PRECREDIT_LOG NTFY_SERVER NTFY_TOPIC
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"; osr_cleanup' EXIT
PC="$REALQ/scripts/ovn_precredit.py"
dec(){ python3 -I "$PC" decide --item "$1" --pre "$2" --progress "${3:-}" --wt "${4:-}" --verify-only "${5:-0}"; }
jf(){ python3 -I -c 'import json,sys; print(json.loads(sys.stdin.read())[sys.argv[1]])' "$1"; }
IV='[T3] backend/app/svc.py — Verify run_job still exists. VERIFY: `grep -q "def run_job" backend/app/svc.py` (cat:python)'
echo "== U: vacuity rules (a vacuous VERIFY must NOT credit)"
vac(){ python3 -I "$PC" vacuity --verify "$1" --wt "$W" | jf vacuous; }
for c in 'true' 'echo ok' 'grep -r foo app | wc -l' 'pytest tests/x.py || true' 'pytest tests/x.py | tail -3' 'pytest --collect-only tests/x.py' 'cat app/x.py' 'ls app' 'test -f a.py && echo FAIL || echo PASS' 'python -c "print(1)"' '! grep -q foo app/missing_file.py' 'grep -c foo app/x.py | wc -l' 'pytest x.py; echo done' 'exit 0'; do
  t "U-vac  vacuous: $c" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify '$c' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
done
for c in 'pytest backend/tests/test_svc.py -q' 'grep -q "def run_job" backend/app/svc.py' 'cd web && npx vitest run src/a.test.ts' '[ "$(grep -c x a.py)" -ge 1 ]' 'python3 -m pytest t.py' 'grep -q a x.py || grep -q a y.py'; do
  t "U-vac  honest: $c" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify '$c' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
done
echo "== U: decisions"
P="$W/prog.md"
printf '# P\n## Next Steps\n- [x] [T3] svc.py — Add test_run_job. VERIFY: `pytest backend/tests/test_svc.py::test_run_job` (cat:python)\n- [ ] [T3] svc.py — Add test_run_job again. VERIFY: `pytest backend/tests/test_svc.py::test_run_job` (cat:python)\n- [ ] %s\n' "$IV" > "$P"
ITEM_DUP='[T3] svc.py — Add test_run_job again. VERIFY: `pytest backend/tests/test_svc.py::test_run_job` (cat:python)'
ITEM_ADD='[T3] svc.py — Add retry handling to run_job. VERIFY: `pytest backend/tests/test_svc.py` (cat:python)'
t "U1 verify-only + PASS + honest VERIFY -> credit" bash -c "[ \"\$(python3 -I '$PC' decide --item '$IV' --pre PASS --progress '$P' --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
t "U2 same item but pristine FAIL -> none" bash -c "[ \"\$(python3 -I '$PC' decide --item '$IV' --pre FAIL --progress '$P' --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
for v in TIMEOUT UNRUNNABLE NO_VERIFY_CLAUSE SKIPPED_DENYLIST 'PASS_BUT_NOT'; do
  t "U3 indeterminate pristine verdict $v -> none" bash -c "[ \"\$(python3 -I '$PC' decide --item '$IV' --pre '$v' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
done
t "U4 an item that ADDS code with a file-wide VERIFY is NOT credited though it passes (model still runs)" bash -c "[ \"\$(python3 -I '$PC' decide --item '$ITEM_ADD' --pre PASS --wt '$W' --verify-only 0 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U5 a specific test node already green (no sibling) -> credit" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] x — Add test_zz. VERIFY: \`pytest backend/tests/test_svc.py::test_zz\`' --pre PASS --progress /nonexistent --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
t "U6 same VERIFY test node as a done sibling -> duplicate (retire)" bash -c "[ \"\$(python3 -I '$PC' decide --item '$ITEM_DUP' --pre PASS --progress '$P' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = duplicate ]"
t "U7 the duplicate names its sibling" bash -c "python3 -I '$PC' decide --item '$ITEM_DUP' --pre PASS --progress '$P' --wt '$W' | grep -q 'test_run_job'"
t "U8 a vacuous VERIFY that matches a sibling is still not credited or retired" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] x — Verify. VERIFY: \`pytest backend/tests/test_svc.py::test_run_job || true\`' --pre PASS --progress '$P' --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U9 a different test node is not a duplicate" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] x — Add test_other. VERIFY: \`pytest backend/tests/test_svc.py::test_other\`' --pre PASS --progress '$P' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
t "U10 a bad invocation never raises (JSON none)" bash -c "python3 -I '$PC' decide --item x --pre PASS --progress /nonexistent --wt /nonexistent | grep -q '\"decision\"'"
echo "== U: mark"
cp "$P" "$W/mk.md"
t "U11 mark rewrites ONLY the open line of the item" bash -c "python3 -I '$PC' mark --progress '$W/mk.md' --item '$ITEM_DUP' --decision duplicate --note 'duplicate: sibling owns it' | grep -q true && grep -c '^- \[x\] (duplicate: sibling owns it) \[T3\] svc.py — Add test_run_job again' '$W/mk.md' | grep -q '^1$' && grep -c '^- \[ \] ' '$W/mk.md' | grep -q '^1$'"
t "U12 mark of an absent item changes nothing and says false" bash -c "python3 -I '$PC' mark --progress '$W/mk.md' --item 'nope nope' --decision credit --note n | grep -q false"

echo "== U: repair D2 review defects (edit items, inverted/self-compare VERIFYs, loose verify-only, rule coverage)"
dd(){ python3 -I "$PC" decide --item "$1" --pre "${2:-PASS}" --progress "${4:-}" --wt "$W" --verify-only "${3:-0}" | jf decision; }
vv(){ python3 -I "$PC" vacuity --verify "$1" --wt "$W" | jf vacuous; }
teq(){ local n="$1" got="$2" want="$3"; t "$n" bash -c "[ '$got' = '$want' ]"; }
# defect 1: a node-named EDIT item is never credited (a regression test passes before a behaviour-preserving edit)
for it in '[T3] backend/app/ws.py — Refactor WebSocketManager to store WebSocket objects directly in self.connections. VERIFY: `pytest tests/test_ws.py::test_send_json_delivers_to_peers -v` (cat:python)' \
          '[T3] backend/app/parental.py — Fix check_time_restrictions logic. VERIFY: `pytest tests/test_parental.py::test_check_time -q` (cat:python)' \
          '[T3] backend/app/parental.py — Modify _today_utc to accept offset_minutes. VERIFY: `pytest tests/test_parental.py::test_today -q` (cat:python)' \
          '[T3] backend/app/routers/parental.py — Update POST /api/parental/check handler. VERIFY: `pytest tests/test_parental.py -k check_handler` (cat:python)' \
          '[T3] backend/tests/test_ws.py — Fix the flaky assertion in test_send. VERIFY: `pytest tests/test_ws.py::test_send` (cat:python)'; do
  t "U13 node-named EDIT item is NOT credited (pristine PASS): ${it:0:60}" bash -c "[ \"\$(python3 -I '$PC' decide --item '$it' --pre PASS --wt '$W' --verify-only 0 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
done
t "U13b an EDIT item is not retired as a duplicate of a done sibling's node either" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] backend/app/svc.py — Refactor run_job. VERIFY: \`pytest backend/tests/test_svc.py::test_run_job\`' --pre PASS --progress '$P' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U13c add-a-test item with the node in a test-file target is still credited" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] backend/tests/test_svc.py — Cover retries. VERIFY: \`pytest backend/tests/test_svc.py::test_retry\`' --pre PASS --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
# defect 2: trailing `grep -v` is an inverted verdict
for c in 'grep -rn "stream_import_guard" app --include="*.py" | grep -v "stream_import_guard.py"' 'grep -rn foo app | egrep -v bar' 'grep -rn foo app | grep -vq bar' 'grep -rn foo app | grep --invert-match bar'; do
  t "U14 vacuous (inverted grep -v tail): ${c:0:60}" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify '$c' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
done
t "U14b the real historical 'Ensure no other code references stream_import_guard' item is NOT credited" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] iptv-backend/app/services/stream_import_guard.py — Ensure no other code in app/ imports or references stream_import_guard or is_source_licensed. VERIFY: \`grep -rn \"stream_import_guard\" app --include=\"*.py\" | grep -v \"stream_import_guard.py\"\`.' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U14c a mid-pipeline grep -v followed by a real grep is still honest" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify 'grep -rn foo app | grep -v bar | grep -q baz' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
# defect 3: verify-only classified items that ask for a change / negative polarity / loose grep
ALERT='[T3] iptv-ios/TVGuideView.swift — Ensure the `.alert` modifier is attached to the root view hierarchy element to ensure proper presentation. VERIFY: `grep -A 2 "fetchError" V.swift | grep -q "alert"`'
t "U15 'Ensure the .alert modifier is attached' verify-only + loose grep -> none" bash -c "[ \"\$(python3 -I '$PC' decide --item '$ALERT' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U15b 'Ensure X' with only a grep VERIFY (no change verb) -> none" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] a.py — Ensure the retry helper is exercised. VERIFY: \`grep -q retry a.py\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U15c negative-polarity description + positive grep -> none" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] a.py — Verify nothing else references legacy_x. VERIFY: \`grep -rq legacy_x app\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U15d a genuine 'Verify X still exists' item keeps crediting (not over-blocked)" bash -c "[ \"\$(python3 -I '$PC' decide --item '$IV' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
# defect 4: HEAD-vs-worktree self-compare and a whole-suite pytest for a Verify X item
for c in 'diff <(git show HEAD:t.py | grep "^def test_") <(grep "^def test_" t.py)' 'git diff --quiet' 'git diff --exit-code HEAD -- t.py' 'cmp <(git show HEAD:t.py) t.py'; do
  t "U16 vacuous (pristine self-compare): ${c:0:60}" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify '$c' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
done
t "U16b git diff --exit-code against a real ref is a real check" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify 'git diff --exit-code origin/develop -- t.py' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
t "U16c 'Verify X' with a whole-file pytest and no suite/tests wording -> none" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] svc.py — Verify run_job is importable. VERIFY: \`pytest backend/tests/test_svc.py -q\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U16d 'Verify the test suite passes' with a whole-file pytest -> credit" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] svc.py — Verify the existing test suite passes. VERIFY: \`pytest backend/tests/test_svc.py -q\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
# defect 7: previously unpinned rules
t "U17 pytest -k '' (empty expression) is vacuous" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify 'pytest tests/x.py -k \"\"' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
t "U17b unbalanced quotes are vacuous" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify 'grep -q \"abc app/x.py' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
t "U17c \`a || true-ish\` rescue (|| echo ok) is vacuous even in the middle" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify 'grep -q a x.py || echo ok && grep -q b y.py' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
t "U17d bare wc -l with no comparison is vacuous" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify 'x=\$(grep -c a b.py); wc -l a.py' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
t "U17e wc -l WITH a comparison is honest" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify '[ \$(wc -l < a.py) -ge 3 ]' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
for c in 'npm --version' 'go version' 'cargo --version' 'npx --yes cowsay hi'; do
  t "U17f constant sub-command is vacuous: $c" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify '$c' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"
done
for c in 'npm test' 'go test ./...' 'cargo test -q' 'python -m pytest t.py' 'python3 -m pytest -q'; do
  t "U17g real runner is honest: $c" bash -c "[ \"\$(python3 -I '$PC' vacuity --verify '$c' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
done
# find_sibling branches: an UNDONE sibling above the item owns it; an UNDONE sibling BELOW does not; an item absent from the file (own is None) still defers to a done/undone sibling
PS="$W/sib.md"
printf '# P\n## Next Steps\n- [ ] [T3] t.py — Add test_up. VERIFY: `pytest backend/tests/test_s.py::test_k`\n- [ ] [T3] t.py — Add test_up again. VERIFY: `pytest backend/tests/test_s.py::test_k`\n- [ ] [T3] t.py — Add test_down. VERIFY: `pytest backend/tests/test_s.py::test_k2`\n- [ ] [T3] t.py — Add test_down again. VERIFY: `pytest backend/tests/test_s.py::test_k2`\n' > "$PS"
UP='[T3] t.py — Add test_up again. VERIFY: `pytest backend/tests/test_s.py::test_k`'
DOWN='[T3] t.py — Add test_down. VERIFY: `pytest backend/tests/test_s.py::test_k2`'
t "U18 an UNDONE sibling ABOVE owns the node -> duplicate" bash -c "[ \"\$(python3 -I '$PC' decide --item '$UP' --pre PASS --progress '$PS' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = duplicate ]"
t "U18b an UNDONE sibling BELOW does not own it (the earlier item keeps the work) -> credit not duplicate" bash -c "[ \"\$(python3 -I '$PC' decide --item '$DOWN' --pre PASS --progress '$PS' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
t "U18c item not present in the progress file (own is None) + a sibling carrying the node -> duplicate" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T3] t.py — Add test_ghost. VERIFY: \`pytest backend/tests/test_s.py::test_k\`' --pre PASS --progress '$PS' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = duplicate ]"
# mark(): the 55-char prefix fallback (a progress line whose tail was edited since the runner picked it up)
cat > "$W/mk2.md" <<'MD'
# P
## Next Steps
- [ ] [T3] backend/app/svc.py — Add retry handling to run_job with exponential backoff and jitter. VERIFY: `pytest x` (cat:python; edited-tail)
MD
t "U19 mark() falls back to the 55-char prefix when the exact line changed" bash -c "python3 -I '$PC' mark --progress '$W/mk2.md' --item '[T3] backend/app/svc.py — Add retry handling to run_job with exponential backoff and jitter. VERIFY: \`pytest x\` (cat:python)' --decision credit --note n | grep -q true && grep -q '^- \[x\] (n) ' '$W/mk2.md'"
# real historical progress lines through decide(): none of these may credit (they were the false positives the review found)
cat > "$W/hist.md" <<'MD'
# P
## Next Steps
- [ ] [T3] backend/app/ws.py — Refactor WebSocketManager to store WebSocket objects directly in self.connections. VERIFY: `pytest tests/test_ws.py::test_send_json_delivers_to_peers -v` (cat:python)
- [ ] [T3] backend/app/parental.py — Replace hardcoded state123 with the real state code. VERIFY: `pytest tests/test_parental.py::test_state -q` (cat:python)
- [ ] [T3] iptv-ios/TVHistoryView.swift — Ensure the `.alert` modifier is attached to the root view hierarchy element to ensure proper presentation. VERIFY: `grep -A 2 "fetchError" V.swift | grep -q "alert"` (cat:swift)
- [ ] [T3] t.py — Confirm no other test functions in t.py were accidentally modified. VERIFY: `diff <(git show HEAD:t.py | grep "^def test_") <(grep "^def test_" t.py)` (cat:python)
MD
t "U20 historical false-positive lines never credit, with verify-only 0 or 1" bash -c "python3 -I - '$PC' '$W/hist.md' <<'PY'
import subprocess, sys, json, re
pc, f = sys.argv[1], sys.argv[2]
for ln in open(f):
    m = re.match(r'- \[ \] (.*)', ln.rstrip())
    if not m: continue
    for vo in ('0', '1'):
        out = json.loads(subprocess.run(['python3','-I',pc,'decide','--item',m.group(1),'--pre','PASS','--progress',f,'--verify-only',vo],capture_output=True,text=True).stdout)
        if out['decision'] != 'none': print('CREDITED', vo, m.group(1)[:80]); sys.exit(1)
PY"
# the runner's own classifier carries the placement verbs (bash side of defect 3)
t "U21 stage_item_is_verify_only rejects 'attached/applied/placed/wrapped' descriptions" bash -c "
$(awk '/^stage_item_is_verify_only\(\)/,/^}/' "$REALQ/ovn_stage_runner.sh")
for d in 'Ensure the .alert modifier is attached to the root view' 'Verify the lock is applied before the write' 'Confirm the banner is placed above the list' 'Check the call is wrapped in try'; do
  stage_item_is_verify_only \"[T3] V.swift — \$d. VERIFY: \\\`grep -q x V.swift\\\`\" && { echo \"verify-only: \$d\"; exit 1; }
done; stage_item_is_verify_only '[T3] V.swift — Verify run_job still exists. VERIFY: \`grep -q x V.swift\`'"
t "U22 no bash-4-only \${var^^} expansion in stage_precredit_run (bash 3.2 on the Mac)" bash -c "! awk '/^stage_precredit_run\(\)/,/^}/' '$REALQ/ovn_stage_runner.sh' | grep -v '^ *#' | grep -qE '\\\$\{[A-Za-z_]+\^\^?\}'"
t "U22b stage_precredit_run parses under /bin/bash 3.2 (extracted)" bash -c "awk '/^stage_precredit_run\(\)/,/^}/' '$REALQ/ovn_stage_runner.sh' > '$W/fn.sh' && /bin/bash -n '$W/fn.sh'"
echo "== U: MUTANTS (each weakening must make an assertion above go red)"
mut(){ # $1 name  $2 python snippet transforming the source text s
  local m="$W/mut_$1"; mkdir -p "$m"; cp "$REALQ/scripts/ovn_backlog_eligibility.py" "$m/"
  python3 -I - "$PC" "$m/ovn_precredit.py" "$2" <<'PY'
import sys
src=open(sys.argv[1]).read(); s=src; exec(sys.argv[3]); assert s!=src, "mutation did not apply"; open(sys.argv[2],"w").write(s)
PY
  t "MUT-applies $1: the mutation changed the source (an unapplied mutant proves nothing)" test -s "$m/ovn_precredit.py"
}
mdec(){ python3 -I "$W/mut_$1/ovn_precredit.py" decide --item "$2" --pre "$3" --progress "${4:-}" --wt "$W" --verify-only "${5:-0}" | jf decision; }
mut novac 's=s.replace("    vac, why = vacuity(v, wt)\n","    vac, why = False, \"x\"\n")'
VAC_ITEM='[T3] x — Verify the tests pass. VERIFY: `pytest backend/tests/test_svc.py || true`'
t "M1 mutant: vacuity check disabled -> a vacuous VERIFY WOULD credit (real module: none)" bash -c "[ \"\$(python3 -I '$W/mut_novac/ovn_precredit.py' decide --item '$VAC_ITEM' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ] && [ \"\$(python3 -I '$PC' decide --item '$VAC_ITEM' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
mut nopass 's=s.replace("    if verdict != \"PASS\":","    if False:")'
t "M2 mutant: pristine-PASS requirement removed -> a FAILING pristine VERIFY WOULD credit" bash -c "[ \"\$(python3 -I '$W/mut_nopass/ovn_precredit.py' decide --item '$IV' --pre FAIL --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
mut nokeys 's=s.replace("    if keys and add_test:\n        res.update(decision=\"credit\"","    if True:\n        res.update(decision=\"credit\"")'
t "M3 mutant: test-node requirement dropped -> an ADD item with a file-wide VERIFY WOULD credit" bash -c "[ \"\$(python3 -I '$W/mut_nokeys/ovn_precredit.py' decide --item '$ITEM_ADD' --pre PASS --wt '$W' --verify-only 0 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
mut nodup 's=s.replace("    if keys and add_test and progress_text:","    if False:")'
t "M4 mutant: duplicate guard removed -> the duplicate is no longer retired (real module: duplicate)" bash -c "[ \"\$(python3 -I '$W/mut_nodup/ovn_precredit.py' decide --item '$ITEM_DUP' --pre PASS --progress '$P' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ] && [ \"\$(python3 -I '$PC' decide --item '$ITEM_DUP' --pre PASS --progress '$P' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = duplicate ]"
mut nowc 's=s.replace("if nxt != \"|\" and _first_word(cl) in _STATUS_HIDING_TAIL:","if False:")'
t "M5 mutant: status-hiding pipeline rule removed -> \`pytest | tail\` WOULD be honest (real module: vacuous)" bash -c "[ \"\$(python3 -I '$W/mut_nowc/ovn_precredit.py' vacuity --verify 'pytest tests/x.py | tail -3' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ] && [ \"\$(python3 -I '$PC' vacuity --verify 'pytest tests/x.py | tail -3' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = True ]"

# mutants for the repair (each must flip a repair assertion)
mut noedit 's=s.replace("    if keys and add_test:\n        res.update(decision=\"credit\"","    if keys:\n        res.update(decision=\"credit\"")'
EDIT1='[T3] backend/app/ws.py — Refactor WebSocketManager. VERIFY: `pytest tests/test_ws.py::test_send -v` (cat:python)'
t "M6 mutant: add-a-test requirement dropped -> a node-named EDIT item WOULD credit (real: none)" bash -c "[ \"\$(python3 -I '$W/mut_noedit/ovn_precredit.py' decide --item '$EDIT1' --pre PASS --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ] && [ \"\$(python3 -I '$PC' decide --item '$EDIT1' --pre PASS --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
mut nogrepv 's=s.replace("if nxt != \"|\" and _is_inverted_grep(cl):","if False:")'
t "M7 mutant: inverted-grep rule removed -> the grep -v pipeline WOULD be honest" bash -c "[ \"\$(python3 -I '$W/mut_nogrepv/ovn_precredit.py' vacuity --verify 'grep -rn foo app | grep -v bar' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
mut nochg 's=s.replace("        bad = asks_change(item, v)\n","        bad = \"\"\n")'
t "M8 mutant: verify-only asks_change guard removed -> the '.alert attached' item WOULD credit" bash -c "[ \"\$(python3 -I '$W/mut_nochg/ovn_precredit.py' decide --item '$ALERT' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
mut nogit 's=s.replace("    if re.search(r\"\\bgit\\s+(?:show|cat-file","    if False and re.search(r\"\\bgit\\s+(?:show|cat-file")'
t "M9 mutant: HEAD self-compare rule removed -> the diff <(git show HEAD:..) VERIFY WOULD be honest" bash -c "[ \"\$(python3 -I '$W/mut_nogit/ovn_precredit.py' vacuity --verify 'diff <(git show HEAD:t.py) t.py' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
mut sib 's=s.replace("(done or own is None or n < own)","(done)")'
t "M10 mutant: find_sibling above/own-None branch reduced to (done) -> the undone-above duplicate is lost" bash -c "[ \"\$(python3 -I '$W/mut_sib/ovn_precredit.py' decide --item '$UP' --pre PASS --progress '$PS' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
mut nosub 's=s.replace("        return not need or bool(need & set(_clause_words(cl)[1:]))","        return True")'
t "M11 mutant: sub-command requirement removed -> \`npm --version\` WOULD be honest" bash -c "[ \"\$(python3 -I '$W/mut_nosub/ovn_precredit.py' vacuity --verify 'npm --version' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"vacuous\"])')\" = False ]"
mut nosuite 's=s.replace("    if runs_tests and not test_keys(v) and not _SUITE_WORDS.search(desc):","    if False:")'
t "M12 mutant: whole-suite guard removed -> 'Verify X' + whole-file pytest WOULD credit" bash -c "[ \"\$(python3 -I '$W/mut_nosuite/ovn_precredit.py' decide --item '[T3] svc.py — Verify run_job is importable. VERIFY: \`pytest backend/tests/test_svc.py -q -k run_job\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
echo "== U: repair D2 round 2 (class-level/-k nodes, loose verify-only, mutation gaps)"
dj(){ python3 -I "$PC" decide --item "$1" --pre PASS --progress "${3:-}" --wt "$W" --verify-only "${2:-0}"; }
# defect 1: a class id or a -k substring is not a specific test; only a LEAF test function is
for it in '[T1] tests/test_x.py — Add test_follow_404 and test_unfollow_404 to class TestFollow. VERIFY: `python -m pytest tests/test_x.py::TestFollow -q`' \
          '[T1] tests/test_d.py — Add test_utcnow_type. VERIFY: `python -m pytest tests/test_d.py -k test_utcnow -q`' \
          '[T1] tests/test_d.py — Add test_utcnow_type. VERIFY: `python -m pytest tests/test_d.py -k "test_utcnow" -q`'; do
  t "U23 class-level / -k VERIFY never credits an add-a-test item: ${it:0:70}" bash -c "[ \"\$(python3 -I '$PC' decide --item '$it' --pre PASS --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
done
t "U23b a leaf node under a class (file::Class::test_x) is still a specific test -> credit" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T1] tests/test_x.py — Add test_follow_404. VERIFY: \`python -m pytest tests/test_x.py::TestFollow::test_follow_404 -q\`' --pre PASS --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
printf '# P\n## Next Steps\n- [ ] [T1] t.py — Add test_a to class TestFollow. VERIFY: `pytest tests/test_x.py::TestFollow`\n- [ ] [T1] t.py — Add test_b to class TestFollow. VERIFY: `pytest tests/test_x.py::TestFollow`\n' > "$W/cls.md"
t "U23c two add-test items sharing a class node are NOT retired as duplicates of each other" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T1] t.py — Add test_b to class TestFollow. VERIFY: \`pytest tests/test_x.py::TestFollow\`' --pre PASS --progress '$W/cls.md' --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U23d test_keys unit: class id and -k give no key, leaf ids do" bash -c "python3 -I - '$REALQ/scripts' <<'PY'
import sys; sys.path.insert(0, sys.argv[1]); import ovn_precredit as m
assert m.test_keys('pytest tests/test_x.py::TestFollow') == [], m.test_keys('pytest tests/test_x.py::TestFollow')
assert m.test_keys('pytest tests/test_x.py -k test_utcnow') == []
assert m.test_keys('pytest tests/test_x.py::test_a') == ['tests/test_x.py::test_a']
assert m.test_keys('pytest tests/test_x.py::TestFollow::test_a[p1]') == ['tests/test_x.py::TestFollow::test_a[p1]']
PY"
# defect 2: verify-only credit must tie the VERIFY to the claim
vo(){ python3 -I "$PC" decide --item "[T1] app/foo.py — $1" --pre PASS --wt "$W" --verify-only 1 | jf decision; }
for it in 'Verify that foo handles None gracefully. VERIFY: `grep -q "def foo" app/foo.py`' \
          'Verify the retry logic backs off exponentially. VERIFY: `grep -q retry app/foo.py`' \
          'Confirm no secrets are logged. VERIFY: `grep -q "def foo" app/foo.py`' \
          'Check that the timeout is 30s. VERIFY: `grep -n timeout app/foo.py`' \
          'Validate input sanitisation. VERIFY: `pytest tests/test_foo.py::test_sanitize`' \
          'Verify run_job returns early. VERIFY: `grep -q "def other_fn" app/foo.py`'; do
  t "U24 loose/polarity-blind verify-only is NOT credited: ${it:0:62}" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T1] app/foo.py — $it' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
done
t "U24b a verify-only item whose VERIFY names the described identifier still credits" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T1] app/foo.py — Verify run_job still exists. VERIFY: \`grep -q \"def run_job\" app/foo.py\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ]"
# defect 3: rules that survived mutation get their own assertions
t "U25 'Verify the \`run_lock\` is applied' + a grep that names it: only the change-verb guard rejects" bash -c "[ \"\$(python3 -I '$PC' decide --item '[T1] app/foo.py — Verify the \`run_lock\` is applied in svc. VERIFY: \`grep -q run_lock app/foo.py\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
t "U26 bare wc -l after a real command has its own reason" bash -c "python3 -I '$PC' vacuity --verify 'grep -c foo a.py; wc -l a.py' --wt '$W' | grep -q 'bare .wc -l. count'"
t "U26b all-trivial command rule has its own reason" bash -c "python3 -I '$PC' vacuity --verify 'echo a; ls; pwd' --wt '$W' | grep -q 'only trivial commands'"
mut nochgv 's=s.replace("    if _CHANGE_VERBS_VERIFY.search(desc):","    if False:")'
CHGV='[T1] app/foo.py — Verify the `run_lock` is applied in svc. VERIFY: `grep -q run_lock app/foo.py`'
t "M13 mutant: change-verb guard removed -> the 'is applied' item WOULD credit (real: none)" bash -c "[ \"\$(python3 -I '$W/mut_nochgv/ovn_precredit.py' decide --item '$CHGV' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ] && [ \"\$(python3 -I '$PC' decide --item '$CHGV' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
mut noleaf 's=s.replace("        if _is_leaf_test(m.group(2)):","        if True:")'
CLS='[T1] tests/test_x.py — Add test_follow_404 to class TestFollow. VERIFY: `python -m pytest tests/test_x.py::TestFollow -q`'
t "M14 mutant: leaf-test requirement removed -> the class-level VERIFY WOULD credit (real: none)" bash -c "[ \"\$(python3 -I '$W/mut_noleaf/ovn_precredit.py' decide --item '$CLS' --pre PASS --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ] && [ \"\$(python3 -I '$PC' decide --item '$CLS' --pre PASS --wt '$W' | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
mut noident 's=s.replace("    if not idents:","    if False:")'
t "M15 mutant: identifier requirement removed -> 'retry logic' + grep retry WOULD credit (real: none)" bash -c "[ \"\$(python3 -I '$W/mut_noident/ovn_precredit.py' decide --item '[T1] app/foo.py — Verify the retry logic is solid. VERIFY: \`grep -q retry app/foo.py\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ] && [ \"\$(python3 -I '$PC' decide --item '[T1] app/foo.py — Verify the retry logic is solid. VERIFY: \`grep -q retry app/foo.py\`' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
mut nonegany 's=s.replace("neg = _NEGATIVE_POLARITY.search(desc) or _NEG_ANY.search(desc)","neg = _NEGATIVE_POLARITY.search(desc)")'
NEGI='[T1] app/foo.py — Confirm no secrets are logged by `run_job`. VERIFY: `grep -q run_job app/foo.py`'
t "M16 mutant: generic negation rule removed -> 'no secrets are logged' + positive grep WOULD credit (real: none)" bash -c "[ \"\$(python3 -I '$W/mut_nonegany/ovn_precredit.py' decide --item '$NEGI' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = credit ] && [ \"\$(python3 -I '$PC' decide --item '$NEGI' --pre PASS --wt '$W' --verify-only 1 | python3 -I -c 'import json,sys;print(json.load(sys.stdin)[\"decision\"])')\" = none ]"
if ! sed --version >/dev/null 2>&1; then echo "  (Part E skipped: needs GNU sed; run on the box)"; osr_summary; exit $?; fi

echo "== E: the real runner"
n2_new(){ osr_new; local f; for f in lib_stage_guards.sh lib_verify_clause.sh ovn_stage_guards.py ovn_backlog_eligibility.py ovn_credit_items.py ovn_spec_rules.py ovn_verify_safe.py ovn_gut_clause.py lib_item_select.sh ovn_precredit.py; do
    [ -f "$REALQ/scripts/$f" ] && cp "$REALQ/scripts/$f" "$Q/scripts/"; done; }
export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
PLAN='[{"desc":"Verify run_job exists and add a second test","files":["backend/app/svc.py","backend/tests/test_svc.py"],"verify":"pytest backend/tests/test_svc.py"}]'
SNIP='printf "\n\ndef test_run_job_twice():\n    assert run_job() == run_job()\n" >> backend/tests/test_svc.py; echo "Applied edit"'
ITEM_VO='[T3] backend/app/svc.py — Verify run_job still exists without modification. VERIFY: `grep -q "def run_job" backend/app/svc.py` (cat:python; multifile:no)'
run1(){ # $1 = item  rest env assignments via caller
  n2_new; osr_venv backend; osr_progress "- [ ] $1"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
  OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"; }
G(){ grep -qF -- "$1" "$T/out.txt"; }
prog_origin(){ git -C "$O" show overnight/feature:OVERNIGHT_PROGRESS.md; }
aider_n(){ cat "$T/scn/aider.n" 2>/dev/null || echo 0; }
llm_n(){ cat "$T/llm/n" 2>/dev/null || echo 0; }
# default (shadow)
run1 "$ITEM_VO"
t "E1 shadow (default): the would-credit decision is journalled (say + event + shadow log)" bash -c "grep -q 'pre-edit credit: WOULD CREDIT' '$T/out.txt' && grep -q '\"event\":\"precredit_decision\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'would=credit' '$Q/state/stage_precredit_shadow.log'"
t "E2 shadow changes NOTHING: the model still ran (aider called, plan fetched) and the item landed as before" bash -c "[ \"$(aider_n)\" -ge 1 ] && [ \"$(llm_n)\" -ge 1 ] && grep -q 'DONE: 1/1 steps landed' '$T/out.txt'"
osr_cleanup
# enforce: credit with zero model calls
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_PRECREDIT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E3 enforce: ZERO model calls (no aider call, no planner/LLM call)" bash -c "[ \"\$(cat '$T/scn/aider.n' 2>/dev/null || echo 0)\" = 0 ] && [ \"\$(cat '$T/llm/n' 2>/dev/null || echo 0)\" = 0 ]"
t "E4 enforce: the item is checked off on origin/overnight/feature with the already-satisfied note" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] (already-satisfied: pre-edit VERIFY green, non-vacuous) '"
t "E5 enforce: precredit_applied journalled with model_calls 0, queue held then released, runner exit message" bash -c "grep -q '\"event\":\"precredit_applied\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'model_calls\":0' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q '^hold $OSR_REPO' '$Q/state/queue.calls' && grep -q '^release $OSR_REPO' '$Q/state/queue.calls' && grep -q 'pre-edit credit APPLIED' '$T/out.txt'"
osr_cleanup
# mutant of the RUNNER wiring: vacuous VERIFY in enforce must not credit
ITEM_VAC='[T3] backend/app/svc.py — Verify run_job still exists without modification. VERIFY: `grep -q "def run_job" backend/app/svc.py || true` (cat:python; multifile:no)'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VAC"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_PRECREDIT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E6 MUTANT-GUARD enforce: a vacuous (|| true) VERIFY is NOT credited - the model still runs" bash -c "[ \"\$(cat '$T/scn/aider.n' 2>/dev/null || echo 0)\" -ge 1 ] && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'already-satisfied: pre-edit' && ! grep -q 'precredit_applied' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
# an ADD item whose file-wide VERIFY passes pristine is not credited
ITEM_ADD2='[T3] backend/app/svc.py — Add a second helper to the service. VERIFY: `grep -q "def run_job" backend/app/svc.py` (cat:python)'
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_ADD2"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_PRECREDIT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E7 enforce: an item that ADDS code is not credited even though its VERIFY passes pristine" bash -c "[ \"\$(cat '$T/scn/aider.n' 2>/dev/null || echo 0)\" -ge 1 ] && ! grep -q 'precredit_applied' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
# duplicate: sibling done with the same node
SIB='[T3] backend/tests/test_svc.py — Add test_run_job. VERIFY: `pytest backend/tests/test_svc.py::test_run_job` (cat:python; multifile:no)'
DUP='[T3] backend/tests/test_svc.py — Add the run_job test again. VERIFY: `pytest backend/tests/test_svc.py::test_run_job` (cat:python; multifile:no)'
n2_new; osr_venv backend; osr_progress "- [x] $SIB" "- [ ] $DUP"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_PRECREDIT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E8 enforce: a duplicate of a done sibling's VERIFY test is retired with a duplicate note, zero model calls" bash -c "[ \"\$(cat '$T/scn/aider.n' 2>/dev/null || echo 0)\" = 0 ] && git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] (duplicate: sibling owns the VERIFY test backend/tests/test_svc.py::test_run_job) '"
osr_cleanup
# off
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_PRECREDIT=off OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E9 OVN_STAGE_PRECREDIT=off: nothing journalled, no shadow log, the run is the old one" bash -c "! grep -q 'pre-edit credit' '$T/out.txt' && [ ! -f '$Q/state/stage_precredit_shadow.log' ] && grep -q 'DONE: 1/1 steps landed' '$T/out.txt'"
osr_cleanup
# explicit item argument is never credited in enforce
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_PRECREDIT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO" "$ITEM_VO"
t "E10 enforce with an explicit item argument: not credited (only queue-picked items), the run proceeds" bash -c "grep -q 'explicit item argument' '$T/out.txt' && ! grep -q 'precredit_applied' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
# D2 repair: shadow is behaviour-neutral (no probe where the old code did not probe)
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_ITEM_VERIFY=off OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E11 OVN_STAGE_ITEM_VERIFY=off disables the precredit probe too (no pre-edit credit line, no shadow log, run unchanged)" bash -c "! grep -q 'pre-edit credit' '$T/out.txt' && [ ! -f '$Q/state/stage_precredit_shadow.log' ] && grep -q 'DONE: 1/1 steps landed' '$T/out.txt'"
osr_cleanup
# D2 repair: enforce guard for manual-bug items (decision would be credit, the runner must still refuse)
BUGI='[T3] `backend/tests/test_svc.py` — Manual-test bug (reported by Mark, flow f1, 2026-10-02): the run button shows nothing. Add test_run_job. VERIFY: `pytest backend/tests/test_svc.py::test_run_job` (cat:bugfix; multifile:no; src:manual) [feat:r-20261002-manual-aaaa1111]'
n2_new; mkdir -p "$Q/qa"; cp "$REALQ/qa/bug_ground.py" "$Q/qa/"; cp "$REALQ/scripts/lib_bug_escalate.sh" "$Q/scripts/"; osr_venv backend; osr_progress "- [ ] $BUGI"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"
OVN_STAGE_PRECREDIT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E12 enforce: a manual-bug item that WOULD credit is not credited (bug guard), the run proceeds" bash -c "grep -q 'manual bug item' '$T/out.txt' && ! grep -q 'precredit_applied' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
# D2 repair: push rejected -> item left OPEN, queue released, tree reset, the normal run continues
n2_new; osr_venv backend; osr_progress "- [ ] $ITEM_VO"; osr_plan default "$PLAN"; osr_aider 1 "$SNIP"; touch "$T/reject_always"
OVN_STAGE_PRECREDIT=enforce OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E13 enforce + push rejected: 'push failed' said, item stays open on origin, queue released, no precredit_applied" bash -c "grep -q 'pre-edit credit: push failed' '$T/out.txt' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'already-satisfied: pre-edit' && grep -q '^release $OSR_REPO' '$Q/state/queue.calls' && ! grep -q 'precredit_applied' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
osr_summary
