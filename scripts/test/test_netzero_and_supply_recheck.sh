#!/usr/bin/env bash
# 2026-10-10 (harness R10, IPTV-3): a cycle whose commits cancel out is not a landing, and a supply item that a later commit already satisfied is credited instead of worked.
#
# Live defect replayed (iptv_apps 04:13-04:39 CDT): supply item `unused-import|device_auth.py` was red at 01:37 (staged step e493f065 had added `import os` ahead of its use), a later staged
# step used `os` (02:44), and the item was STILL pulled four times: each cycle removed the import, saw F821 undefined name 'os', and re-added it. Net diff zero, 8 noise commits pushed, each cycle
# recorded `landed pushed(tests:pass)`; the churn guard parked the item only after the 4th.
# Sections: A ovn_cycle_net_zero unit, B the REAL run_aider_fix_task end to end (net-zero), C the supply re-check hook end to end, D outcome class/bucket mapping of the new status.
# A and D run anywhere; B and C drive the hermetic Linux fixture (box-only, like test_run_overnight_aider2_*).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RO="${OVN_RUN_OVERNIGHT:-$HERE/../../run_overnight.sh}"; [ -f "$RO" ] || RO="$HOME/overnight-queue/run_overnight.sh"
[ -f "$RO" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }
SD="$(cd "$(dirname "$RO")" && pwd)"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

echo "== A: ovn_cycle_net_zero (unit, real function extracted from run_overnight.sh)"
FN="$(sed -n '/^ovn_cycle_net_zero() {/,/^}/p' "$RO")"; [ -n "$FN" ] || { echo "  FAIL: could not extract ovn_cycle_net_zero"; exit 1; }
eval "$FN"
tmp="$(mktemp -d)" || exit 1; export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
R="$tmp/r"; mkdir -p "$R"; cd "$R" || exit 1; git init -q -b main . 2>/dev/null || git init -q .
printf 'import os\nx = os.getenv("A")\n' > svc.py; printf '# prog\n- [ ] [T1] svc.py — do it\n' > OVERNIGHT_PROGRESS.md
git add -A; git commit -q -m seed; B0="$(git rev-parse HEAD)"
git checkout -q -b t1 2>/dev/null
printf 'x = 1\n' > svc.py; git commit -q -am "remove the import"; printf 'import os\nx = os.getenv("A")\n' > svc.py; git commit -q -am "re-add the import"
ok "A1 remove-then-re-add (the device_auth.py shape): net-zero" "ovn_cycle_net_zero $B0 \$(git rev-parse HEAD)"
git checkout -q main; git checkout -q -b t2; printf 'import os\nx = os.getenv("B")\n' > svc.py; git commit -q -am real
ok "A2 a real net change is NOT net-zero" "! ovn_cycle_net_zero $B0 \$(git rev-parse HEAD)"
git checkout -q main; git checkout -q -b t3; sed -i.bak 's/do it/done it/' OVERNIGHT_PROGRESS.md 2>/dev/null; rm -f OVERNIGHT_PROGRESS.md.bak; git commit -q -am "credit"
ok "A3 a progress-file-only (bookkeeping/credit) cycle is NOT net-zero (it lands as before)" "! ovn_cycle_net_zero $B0 \$(git rev-parse HEAD)"
git checkout -q main; git checkout -q -b t4; git commit -q --allow-empty -m e1; git commit -q --allow-empty -m e2
ok "A4 empty commits only: NOT net-zero (nothing touched a code file)" "! ovn_cycle_net_zero $B0 \$(git rev-parse HEAD)"
git checkout -q main; git checkout -q -b t5; printf 'x = 1\n' > svc.py; git commit -q -am rm; printf 'import os\nx = os.getenv("A")\n' > svc.py; git commit -q -am readd; sed -i.bak 's/do it/done it/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak; git commit -q -am credit2
ok "A5 churn PLUS a progress-file change: NOT net-zero (the credit must not be lost)" "! ovn_cycle_net_zero $B0 \$(git rev-parse HEAD)"
ok "A6 same sha / empty args: NOT net-zero" "! ovn_cycle_net_zero $B0 $B0 && ! ovn_cycle_net_zero '' ''"
git checkout -q main; git checkout -q -b t7; printf 'x = 1\n' > new_file.py; git add -A; git commit -q -m add; git rm -q new_file.py; git commit -q -m del
ok "A7 add-then-delete of a new file: net-zero" "ovn_cycle_net_zero $B0 \$(git rev-parse HEAD)"
cd "$HERE" || exit 1

echo "== D: the new status maps to the right class / bucket (pass-rate math stays honest)"
LIB="$SD/scripts/lib_item_select.sh"
FN_SRC="$(sed -n '/^record_outcome(/,/^}/p' "$RO")"; eval "$FN_SRC"
# shellcheck source=/dev/null
source "$LIB"; SCRIPT_DIR="$SD"; STATE_DIR="$tmp/state"; mkdir -p "$STATE_DIR"
rd="$tmp/rd"; mkdir -p "$rd"; printf '# p\n- [ ] [T2] a.py — x\n' > "$rd/OVERNIGHT_PROGRESS.md"
printf -- '--- NET-ZERO GUARD: touched code files but the net code diff is EMPTY ---\n' > "$tmp/nz.log"
: > "$STATE_DIR/outcomes.jsonl"; record_outcome id1 repo "no-op(net-zero)" "" aider_fix 1 "$tmp/nz.log" 5 "$rd" "" 2>/dev/null
ROW="$(tail -1 "$STATE_DIR/outcomes.jsonl")"
ok "D1 record_outcome: class noop, severity bad" "printf '%s' '$ROW' | jq -e '.class==\"noop\" and .severity==\"bad\"'"
ok "D2 fail_reason is the bounded tag 'net-zero' (ovn_classify_fail.sh)" "printf '%s' '$ROW' | jq -e '.fail_reason==\"net-zero\"'"
printf '%s' "$ROW" > "$tmp/row.json"
ok "D3 ovn_outcome_buckets: the row is BAD (counts in the denominator, never GOOD)" "python3 -c \"import sys,json;sys.path.insert(0,'$SD/scripts');import ovn_outcome_buckets as b;r=json.load(open('$tmp/row.json'));assert b.bucket_from_outcome_row(r)=='bad'\""
ok "D4 ... also when the severity field is missing (older-row fallback by class+status)" "python3 -c \"import sys;sys.path.insert(0,'$SD/scripts');import ovn_outcome_buckets as b;assert b.bucket_from_outcome_row({'class':'noop','status':'no-op(net-zero)'})=='bad'\""
ok "D5 the cycle_notify status->oc map files it under noop:flail (BAD), not skip" "grep -q 'no-op\\*) _oc=noop:flail' '$SD/cycle_notify.sh'"
ok "D6 the item guard counts any no-op(...) toward the item's no-op cap (net-zero included)" "grep -q 'status\" == no-op\\*' '$SD/scripts/ovn_item_guard.sh'"

if [ "$(uname)" != Linux ]; then
  echo "  SKIP B/C: box-only (the hermetic run_overnight.sh fixture needs the Linux runtime); run on the box"
  rm -rf "$tmp"; echo "net-zero + supply re-check: $P passed, $F failed"; [ "$F" -eq 0 ]; exit $?
fi
cd "$HERE" || exit 1
PRE_P=$P; PRE_F=$F
. "$HERE/lib_ro_aider2_fixture.sh"   # defines its own P/F/ok/eq (same call shape as ok above): carry the A/D counts over
P=$PRE_P; F=$PRE_F
churn='printf "def hello():\n    return 1\n# x\n" > app.py; git add -A; git commit -q -m "feat: remove import"; git revert --no-edit HEAD >/dev/null 2>&1'
run_id(){  # like run_case but with a chosen task id (the ongoing-* lanes get the supply re-check)
  local id="$1" prompt="${2:-$PROMPT_DEFAULT}"
  : > "$TREE/state/alerts.log"
  OUT="$(run_aider_fix_task "$id" "$REPO" "$prompt" claude/feature false "$TASK_LOG" "" false 2 "" 60 2>/dev/null | tail -1)"
  LOGTXT="$(cat "$TASK_LOG" 2>/dev/null)"
}

echo "== B: net-zero guard, end to end"
mk_case nz_on; scout_ok; aplan 2 "$churn"
BEFORE="$(git -C "$REPO" rev-parse HEAD)"
run_case
eq "B1 status no-op(net-zero)" "$OUT" "no-op(net-zero)"
ok "B2 the log explains the guard" 'logged "NET-ZERO GUARD:" && logged "net code diff is EMPTY"'
eq "B3 the tree is back at BEFORE_SHA (the noise commits are gone)" "$(git -C "$REPO" rev-parse HEAD)" "$BEFORE"
ok "B4 nothing was pushed to origin" '[ "$(git -C "$ORIGIN" rev-parse claude/feature)" = "$(git -C "$ORIGIN" rev-parse main)" ]'
ok "B5 an alert names the net-zero cycle" 'grep -q "net-zero cycle" "$TREE/state/alerts.log"'
mk_case nz_real; scout_ok
aplan 2 'gc app.py "def hello2(): return 2" "feat(app): return 2

DONE: Fix \`hello\` in app.py to return 2"; echo "Tests  2 passed (2)"'
run_case
ok "B6 CONTROL: a real change still lands and pushes (not net-zero)" '[[ "$OUT" == pushed* ]] && origin_has claude/feature "feat(app): return 2"'
mk_case nz_prog; scout_ok; aplan 2 'gc OVERNIGHT_PROGRESS.md "- [ ] [T2] extra.py — note" "docs: note"'
run_case
ok "B7 CONTROL: a progress-file-only cycle is not net-zero" '! logged "NET-ZERO GUARD:" && [ "$OUT" != "no-op(net-zero)" ]'
mk_case nz_shadow; scout_ok; aplan 2 "$churn"
OVN_NETZERO_GUARD=shadow run_case
ok "B8 shadow mode: only logs 'would reset', the cycle continues and (old behaviour) pushes the churn" 'logged "NET-ZERO GUARD (shadow)" && [[ "$OUT" == pushed* ]]'
mk_case nz_off; scout_ok; aplan 2 "$churn"
OVN_NETZERO_GUARD=off run_case
ok "B9 MUTATION / kill switch off: the cancelled-out cycle is pushed as a landing (the live defect)" '! logged "NET-ZERO GUARD" && [[ "$OUT" == pushed* ]]'

echo "== C: supply re-check, end to end (ongoing-* lane)"
SUP_OK='- [ ] [T1] app.py — Remove the unused os import VERIFY: `grep -q hello app.py`. (cat:python; multifile:no; supply:unused-import) [feat:demo-20261010-supply-unused-import-app]'
SUP_RED='- [ ] [T1] app.py — Remove the unused os import VERIFY: `grep -q zzz_not_there app.py`. (cat:python; multifile:no; supply:unused-import) [feat:demo-20261010-supply-unused-import-app]'
NON_SUP='- [ ] [T1] app.py — Remove the unused os import VERIFY: `grep -q hello app.py`. (cat:python; multifile:no) [feat:demo-20261010-plain-app]'
set_prog(){   # the item list lives on origin's default branch (a non-persistent task starts from it): commit it in the seed clone, push both branches, pull it into the working clone
  ( cd "$OTHER" && printf '# Progress\n\n## Next Steps\n%s\n- [ ] [T2] other.py — second item\n\n## Completed\n' "$1" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m "prog" && git push -q origin main && git push -q -f origin main:claude/feature \
    && cd "$REPO" && git pull -q origin main ) >/dev/null 2>&1; }
aider_calls(){ cat "$CASE_DIR/aider.n" 2>/dev/null || echo 0; }
mk_case sup_ok; set_prog "$SUP_OK"; scout_ok
OVN_SUPPLY_RECHECK=on run_id ongoing-app
eq "C1 a supply item whose own VERIFY already passes -> no-op(ALREADY-DONE)" "$OUT" "no-op(ALREADY-DONE)"
eq "C2 ... and no model call was spent (aider never ran)" "$(aider_calls)" "0"
ok "C3a ... the credit is recorded in state/supply_recheck.log (mode=on)" 'grep -q "mode=on verify=PASS" "$TREE/state/supply_recheck.log"'
ok "C3 ... the item is ticked as already-satisfied and the credit commit exists" 'git -C "$REPO" show HEAD:OVERNIGHT_PROGRESS.md | grep -q "^- \[x\] (already-satisfied: supply VERIFY green at pull)" && git -C "$REPO" log --format=%s | grep -q "credit supply item already satisfied at pull"'
ok "C4 ... pushed to origin" 'origin_has claude/feature "credit supply item already satisfied at pull"'
mk_case sup_red; set_prog "$SUP_RED"; scout_ok
OVN_SUPPLY_RECHECK=on run_id ongoing-app
ok "C5 CONTROL: a supply item whose VERIFY still FAILS is NOT credited (the cycle runs)" '[ "$(aider_calls)" -ge 1 ] && ! git -C "$REPO" log --format=%s | grep -q "credit supply item already satisfied"'
mk_case sup_plain; set_prog "$NON_SUP"; scout_ok
OVN_SUPPLY_RECHECK=on run_id ongoing-app
ok "C6 CONTROL: a NON-supply item with a passing VERIFY is not touched by the re-check" '[ "$(aider_calls)" -ge 1 ] && ! logged "SUPPLY-RECHECK"'
mk_case sup_shadow; set_prog "$SUP_OK"; scout_ok
OVN_SUPPLY_RECHECK=shadow run_id ongoing-app
ok "C7 shadow: records 'mode=shadow verify=PASS' in state/supply_recheck.log, credits nothing, the cycle runs" 'grep -q "mode=shadow verify=PASS" "$TREE/state/supply_recheck.log" && [ "$(aider_calls)" -ge 1 ] && ! git -C "$REPO" log --format=%s | grep -q "credit supply item already satisfied"'
mk_case sup_off; set_prog "$SUP_OK"; scout_ok
OVN_SUPPLY_RECHECK=off run_id ongoing-app
ok "C8 MUTATION / kill switch off: the already-green supply item is WORKED (the live defect)" '[ "$(aider_calls)" -ge 1 ] && ! logged "SUPPLY-RECHECK"'
mk_case sup_nonongoing; set_prog "$SUP_OK"; scout_ok
OVN_SUPPLY_RECHECK=on run_id t-app
ok "C9 a non-ongoing task id never runs the re-check" '! logged "SUPPLY-RECHECK" && [ "$(aider_calls)" -ge 1 ]'

mk_case sup_default; set_prog "$SUP_OK"; scout_ok
run_id ongoing-app
ok "C10 DEFAULT (OVN_SUPPLY_RECHECK unset) is SHADOW: logs 'mode=shadow verify=PASS', credits and pushes nothing, the cycle runs" '[ -z "${OVN_SUPPLY_RECHECK:-}" ] && grep -q "mode=shadow verify=PASS" "$TREE/state/supply_recheck.log" && [ "$(aider_calls)" -ge 1 ] && ! git -C "$REPO" log --format=%s | grep -q "credit supply item already satisfied" && ! origin_has claude/feature "credit supply item already satisfied at pull"'

echo "net-zero + supply re-check: $P passed, $F failed"
[ "$F" -eq 0 ]
