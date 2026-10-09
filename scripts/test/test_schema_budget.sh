#!/usr/bin/env bash
# Per-category attempt budget for schema/migration/model items (2026-10-02). Evidence + rationale: scripts/lib_item_select.sh ovn_schema_budget.
# Measured on the box: 33/600 AUTO-SKIPs are schema items (16 by the 200k token cap after ~2 cycles); the live gitlark oauth item's staged VERIFY went
# 195F+292E -> 14F -> 1F across attempts, then died at best-of-N 3/3 one failing test short. Schema items now get a bigger budget; everything else keeps
# the existing defaults EXACTLY (proved here: same caps, same best-of-N, same parking cycle).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_ro_core.sh"
. "$Q/scripts/lib_item_select.sh"
unset OVN_SCHEMA_BUDGET OVN_BESTOF_N_SCHEMA OVN_ITEM_FAIL_CAP_SCHEMA OVN_ITEM_TOKEN_CAP_SCHEMA OVN_ITEM_NOOP_CAP_SCHEMA

echo "== classifier: which items count as schema =="
for t in '- [ ] [T2] backend/alembic/versions/0010_add_col.py — add column' \
         '- [ ] [T1] backend/app/models/user.py — Add `current_period_start` column' \
         '- [ ] [T3] backend/app/schemas/plan.py — add field_validator' \
         '- [ ] [T3] backend/app/db/models.py — add index' \
         '- [ ] [T2] app/foo.py — tighten (cat:schema)' \
         '- [ ] [T2] app/foo.py — write a migration for the users table'; do
  ovn_is_schema_item "$t" && ok "schema: ${t:0:60}" 1 || ok "schema: ${t:0:60}" 0
done
for t in '- [ ] [T1] backend/app/routers/plans.py — Add POST /plans endpoint (cat:endpoint)' \
         '- [ ] [T2] tests/test_models_page.py — add a test (cat:test)' \
         '- [ ] [T2] web/src/viewmodels/x.ts — fix (cat:typescript)' \
         '- [ ] [T1] app/foo.py — improve the language model prompt wording' \
         'Work the single top not-yet-done item in the overnight progress log.' ''; do
  ovn_is_schema_item "$t" && ok "NOT schema: ${t:0:60}" 0 || ok "NOT schema: ${t:0:60}" 1
done
S='- [ ] [T1] backend/app/models/user.py — add column'; N='- [ ] [T1] app/routers/x.py — endpoint'

echo "== budget math: non-schema is byte-for-byte the base =="
for k in bestn failcap tokcap noopcap; do eq "non-schema $k unchanged" 7 "$(ovn_schema_budget $k 7 "$N")"; done
eq "non-schema best-of-N=1 stays 1" 1 "$(ovn_schema_budget bestn 1 "$N")"
echo "== budget math: schema defaults =="
eq "schema bestn 3 -> 5" 5 "$(ovn_schema_budget bestn 3 "$S")"
eq "schema bestn 1 (best-of-N off) stays 1" 1 "$(ovn_schema_budget bestn 1 "$S")"
eq "schema failcap 4 -> 6" 6 "$(ovn_schema_budget failcap 4 "$S")"
eq "schema tokcap 200000 -> 400000" 400000 "$(ovn_schema_budget tokcap 200000 "$S")"
eq "schema noopcap unchanged (no convergence signal in a no-op)" 5 "$(ovn_schema_budget noopcap 5 "$S")"
echo "== overrides + kill switch =="
eq "OVN_BESTOF_N_SCHEMA wins" 9 "$(OVN_BESTOF_N_SCHEMA=9 ovn_schema_budget bestn 3 "$S")"
eq "OVN_ITEM_FAIL_CAP_SCHEMA wins" 3 "$(OVN_ITEM_FAIL_CAP_SCHEMA=3 ovn_schema_budget failcap 4 "$S")"
eq "OVN_ITEM_TOKEN_CAP_SCHEMA wins" 123 "$(OVN_ITEM_TOKEN_CAP_SCHEMA=123 ovn_schema_budget tokcap 200000 "$S")"
eq "OVN_ITEM_NOOP_CAP_SCHEMA wins" 8 "$(OVN_ITEM_NOOP_CAP_SCHEMA=8 ovn_schema_budget noopcap 5 "$S")"
eq "override never touches a non-schema item" 4 "$(OVN_ITEM_FAIL_CAP_SCHEMA=99 ovn_schema_budget failcap 4 "$N")"
eq "OVN_SCHEMA_BUDGET=off -> schema item gets the base" 4 "$(OVN_SCHEMA_BUDGET=off ovn_schema_budget failcap 4 "$S")"
eq "OVN_SCHEMA_BUDGET=off beats an explicit override" 3 "$(OVN_SCHEMA_BUDGET=off OVN_BESTOF_N_SCHEMA=9 ovn_schema_budget bestn 3 "$S")"

echo "== ovn_item_guard.sh: parking cycle, schema vs non-schema =="
G="$Q/scripts/ovn_item_guard.sh"; tmp="$(mktemp -d)"
new_repo(){ local r="$tmp/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t && git config user.name t && printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m i ); echo "$r"; }
# cycles_until_park <name> <item> <status> <ksent> <max> [ENV...] -> number of guard calls until the item is AUTO-SKIPped (0 = never within max)
cycles_until_park(){
  local name="$1" item="$2" st="$3" k="$4" max="$5"; shift 5
  local r; r="$(new_repo "$name" "$item")"; local state="$tmp/state_$name"; mkdir -p "$state"
  local i
  for i in $(seq 1 "$max"); do
    printf 'Tokens: %sk sent, 100 received.\n' "$k" > "$tmp/l_${name}_$i.log"
    env "$@" bash "$G" "$r" "$st" "$state" "id_$name" "$tmp/l_${name}_$i.log" >/dev/null 2>&1
    grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && { echo "$i"; return; }
  done
  echo 0
}
E="OVN_ITEM_FAIL_CAP=4 OVN_ITEM_NOOP_CAP=5 OVN_ITEM_TOKEN_CAP=200000"
SI='- [ ] [T1] backend/app/models/user.py — add column. VERIFY: pass'; NI='- [ ] [T1] backend/app/routers/users.py — add endpoint. VERIFY: pass'
eq "non-schema: reverts park at the 4th cycle (unchanged)" 4 "$(cycles_until_park n1 "$NI" 'reverted(build-break)' 10 12 $E)"
eq "schema: reverts park at the 6th cycle" 6 "$(cycles_until_park s1 "$SI" 'reverted(build-break)' 10 12 $E)"
eq "non-schema: 80k/cycle parks by TOKENS at cycle 3 (unchanged)" 3 "$(cycles_until_park n2 "$NI" 'no-op(stage-unverified)' 80 12 $E)"
eq "schema: 80k/cycle parks by TOKENS at cycle 5 (400k cap)" 5 "$(cycles_until_park s2 "$SI" 'no-op(stage-unverified)' 80 12 $E)"
eq "schema: no-op cap unchanged (5th cycle, same as non-schema)" 5 "$(cycles_until_park s3 "$SI" 'no-op(BLOCKED)' 5 12 $E)"
eq "non-schema: no-op cap 5th cycle" 5 "$(cycles_until_park n3 "$NI" 'no-op(BLOCKED)' 5 12 $E)"
eq "OVN_SCHEMA_BUDGET=off: schema item parks like any other (4th)" 4 "$(cycles_until_park s4 "$SI" 'reverted(build-break)' 10 12 $E OVN_SCHEMA_BUDGET=off)"
eq "OVN_ITEM_FAIL_CAP_SCHEMA=2 override honoured" 2 "$(cycles_until_park s5 "$SI" 'reverted(build-break)' 10 12 $E OVN_ITEM_FAIL_CAP_SCHEMA=2)"
eq "schema item still parks eventually even with big budget (cap, not infinity)" 6 "$(cycles_until_park s6 "$SI" 'reverted(reverted-red)' 1 20 $E)"
ok "parked schema item message names its real trigger" "$(grep -q 'AUTO-SKIP after 6 failed-to-land cycles' "$tmp/s6/OVERNIGHT_PROGRESS.md" && echo 1 || echo 0)"
rm -rf "$tmp"

echo "== best-of-N through the real main loop =="
ro_init
ro_hook_stubs
ro_link update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py \
        scripts/ovn_classify.py scripts/ovn_progress_slice.py scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh
ST="$T/tree/state"; R="$T/repos"; mkdir -p "$ST"
row(){ printf '%s\n' "$REP" | grep -F "| $1 |" | head -1; }
oc(){ jq -r --arg id "$1" --arg f "$2" 'select(.id==$id) | .[$f]' "$ST/outcomes.jsonl" | tail -1; }
SCHEMA_PROG='# Overnight Progress

## Next Steps
- [ ] [T1] `backend/app/models/user.py` — add a nullable column to the User model (cat:python)'
PLAIN_PROG='# Overnight Progress

## Next Steps
- [ ] [T1] `app/foo.py` — add a bar function (cat:python)'
bon_run(){  # <name> <progress> [ENV...]  -> runs one never-landing task, sets the outcome attempt
  local name="$1" prog="$2"; shift 2
  ro_mkrepo "r-$name" "$prog" >/dev/null
  echo 'OVN_BESTOF_N=3' > "$ST/pilot_flags.env"
  printf 'IMPL_SEQ=none; SCOUT_EXTRA="a multi-file change"\n' > "$RO_STUB/scn"
  : > "$RO_STUB/aider_n"; rm -f "$RO_STUB/impl_n" "$RO_STUB/aider_kinds" "$ST/outcomes.jsonl" "$T/tree/reports"/*
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$name" '[{id:("t-"+$n),repo:($R+"/r-"+$n),prompt:"x"}]')"
  ro_run_main "$@"; REP="$(ro_report)"
}
bon_run schema "$SCHEMA_PROG"
eq "schema item: best-of-N 3 -> 5 attempts (outcome attempt=5)" 5 "$(oc t-schema attempt)"
has "log shows the larger denominator" "$RO_OUT" "attempt 5/5 (prev: no-op"
bon_run plain "$PLAIN_PROG"
eq "non-schema item: best-of-N still 3 (outcome attempt=3)" 3 "$(oc t-plain attempt)"
has "non-schema log keeps the old denominator" "$RO_OUT" "attempt 3/3 (prev: no-op"
bon_run schema "$SCHEMA_PROG" OVN_SCHEMA_BUDGET=off
eq "OVN_SCHEMA_BUDGET=off: schema item back to 3 attempts" 3 "$(oc t-schema attempt)"
bon_run schema "$SCHEMA_PROG" OVN_BESTOF_N_SCHEMA=4
eq "OVN_BESTOF_N_SCHEMA=4 honoured" 4 "$(oc t-schema attempt)"

echo; echo "Schema budget: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
