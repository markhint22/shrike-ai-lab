#!/usr/bin/env bash
# Bugs-first policy (2026-10-02, branch qa/h8-bug-first) - the run_overnight.sh WIRING, end to end through the REAL script in the hermetic fake tree
# (lib_ro_core.sh): what the scout is shown, the delete-hint peek, the best-of-N cap, the attempt count handed to the guard, and a full
# main-loop escalation with the REAL ovn_item_guard.sh. The selector/guard/stage-picker unit proofs are in test_bug_first_select.sh.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed (the guard uses sed -i); run on the box"; exit 0; fi
unset OVN_BUG_FIRST OVN_BUG_FOCUS OVN_BUG_ATTEMPT_CAP OVN_GUARD_ATTEMPTS NTFY_SERVER NTFY_TOPIC
ro_init
ro_hook_stubs
ro_link update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py \
        scripts/ovn_classify.py scripts/ovn_delete_executor.py scripts/ovn_progress_slice.py scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh
ST="$T/tree/state"; R="$T/repos"; mkdir -p "$ST"
row(){ printf '%s\n' "$REP" | grep -F "| $1 |" | head -1; }
oc(){ jq -r --arg id "$1" --arg f "$2" 'select(.id==$id) | .[$f]' "$ST/outcomes.jsonl" | tail -1; }

BUG='- [ ] [T3] `app/foo.py` — Manual-test bug (reported by Mark, flow f1, 2026-10-02): the add button does nothing. First write a failing test that reproduces this, then fix it. VERIFY: `true`. (cat:bugfix; multifile:no; src:manual) [feat:r-20261002-manual-aaaa1111]'
BUG2="${BUG/\[T3\]/[T2]}"      # T2 variant: the scout+implement flow (a T3 bug goes to the staged runner first, see section D)
RA='- [ ] [T1] `app/old.py` — roadmap item ALPHA tidy the old helper (cat:python)'
RB='- [ ] [T1] `app/foo.py` — roadmap item BETA add a bar function (cat:python)'
DELI='- [ ] [T1] Remove the dead file app/old.py — nothing imports it. (cat:python)'
mkp(){ printf '# Overnight Progress\n\n## Next Steps\n'; printf '%s\n' "$@"; }

# stub guard: records the env the loop hands it (the real guard is linked in section D)
stub_guard(){ rm -f "$T/tree/scripts/ovn_item_guard.sh"; printf '#!/bin/bash\necho "guard attempts=${OVN_GUARD_ATTEMPTS:-unset} status=$2" >> "%s/guard.log"\nexit 0\n' "$T/stub" > "$T/tree/scripts/ovn_item_guard.sh"; chmod +x "$T/tree/scripts/ovn_item_guard.sh"; }
# scn hook: copy every --read file the stub aider is handed so the test can see exactly what the scout was shown
scn_read(){ cat > "$RO_STUB/scn" <<'EOF'
n_=$(cat "$S/aider_n"); prev_=""; for a_ in "$@"; do [ "$prev_" = "--read" ] && cp "$a_" "$S/read.$n_.$(basename "$a_")" 2>/dev/null; prev_="$a_"; done
IMPL_SEQ=none
EOF
}
run1(){ # <name> <progress-text> [ENV=...]  one task, one cycle
  local name="$1" prog="$2"; shift 2
  ro_mkrepo "r-$name" "$prog" >/dev/null
  rm -f "$RO_STUB"/read.* "$RO_STUB/aider_n" "$RO_STUB/impl_n" "$RO_STUB/aider_kinds" "$RO_STUB/guard.log" "$ST/outcomes.jsonl" "$T/tree/reports"/*
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$name" '[{id:("ongoing-"+$n),repo:($R+"/r-"+$n),prompt:"Work the single top not-yet-done item in the overnight progress log."}]')"
  ro_run_main "$@"; REP="$(ro_report)"
}
slice(){ cat "$RO_STUB"/read.1.ovn_progress_tail_*.md 2>/dev/null; }
doable_section(){ slice | awk '/^## Doable Next Steps/{f=1;next} /^## Recent history/{f=0} f'; }
first_doable(){ slice | awk '/^## Doable Next Steps/{f=1;next} f&&/^- \[ \]/{print;exit}'; }

echo "=== A: what the scout is shown ==="
stub_guard; scn_read
run1 a1 "$(mkp "$RA" "$RB" "$BUG2")"
ok "bug at the BOTTOM of a small file: the scout is handed the ordered 'Doable Next Steps' slice, not the raw file" "$(ls "$RO_STUB"/read.1.ovn_progress_tail_* >/dev/null 2>&1 && echo 1 || echo 0)"
has "the first doable item in the slice is the bug" "$(first_doable)" "Manual-test bug"
hasnt "lane focus: no roadmap ALPHA in the Doable section while the bug is open" "$(doable_section)" "ALPHA"
hasnt "lane focus: no roadmap BETA in the Doable section" "$(doable_section)" "BETA"
run1 a2 "$(mkp "$RA" "$RB" "$BUG2")" OVN_BUG_FIRST=off
ok "kill switch: the raw progress file is handed over exactly as before (no slice file)" "$(ls "$RO_STUB"/read.1.OVERNIGHT_PROGRESS.md >/dev/null 2>&1 && ! ls "$RO_STUB"/read.1.ovn_progress_tail_* >/dev/null 2>&1 && echo 1 || echo 0)"
run1 a3 "$(mkp "$RA" "$RB")"
ok "no manual bug: the raw progress file as before (unchanged behaviour)" "$(ls "$RO_STUB"/read.1.OVERNIGHT_PROGRESS.md >/dev/null 2>&1 && ! ls "$RO_STUB"/read.1.ovn_progress_tail_* >/dev/null 2>&1 && echo 1 || echo 0)"
run1 a4 "$(mkp "$RA" "- [ ] [CLAUDE] [bug-escalated: 2 failed attempts] ${BUG2#- \[ \] }" "$RB")"
ok "escalated bug is not open: raw file again, lane back to normal work" "$(ls "$RO_STUB"/read.1.OVERNIGHT_PROGRESS.md >/dev/null 2>&1 && echo 1 || echo 0)"

echo "=== B: delete-hint peek follows the ordered top item ==="
run1 b1 "$(mkp "$DELI" "$BUG2")"
hasnt "top is the bug (not the 'Remove the dead file' roadmap line): no delete hint injected" "$(cat "$RO_STUB/aider.last_args" 2>/dev/null)" "this task deletes/removes a file"
run1 b2 "$(mkp "$DELI" "$BUG2")" OVN_BUG_FIRST=off
has "kill switch: the delete item is the top item again and the hint is injected (old behaviour)" "$(cat "$RO_STUB/aider.last_args" 2>/dev/null)" "this task deletes/removes a file"

echo "=== C: best-of-N is capped for a bug, and the guard is told how many tries were used ==="
bon(){ # <name> <progress> [ENV...]
  local name="$1" prog="$2"; shift 2
  ro_mkrepo "r-$name" "$prog" >/dev/null
  echo 'OVN_BESTOF_N=5' > "$ST/pilot_flags.env"
  printf 'IMPL_SEQ=none; SCOUT_EXTRA="a multi-file change"\n' > "$RO_STUB/scn"
  : > "$RO_STUB/aider_n"; rm -f "$RO_STUB/impl_n" "$RO_STUB/aider_kinds" "$RO_STUB/guard.log" "$ST/outcomes.jsonl" "$T/tree/reports"/*
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$name" '[{id:("t-"+$n),repo:($R+"/r-"+$n),prompt:"x"}]')"
  ro_run_main "$@"; REP="$(ro_report)"
}
bon c1 "$(mkp "$BUG2")"
eq "bug: OVN_BESTOF_N=5 is capped at the bug cap 2 (outcome attempt=2)" 2 "$(oc t-c1 attempt)"
has "bug: the retry line shows the capped denominator" "$RO_OUT" "attempt 2/2"
hasnt "bug: no third attempt" "$RO_OUT" "attempt 3/"
has "guard is handed OVN_GUARD_ATTEMPTS=2 (both tries were used in this cycle)" "$(cat "$RO_STUB/guard.log" 2>/dev/null)" "attempts=2"
bon c2 "$(mkp "$BUG2")" OVN_BUG_ATTEMPT_CAP=3
eq "OVN_BUG_ATTEMPT_CAP=3: 3 attempts" 3 "$(oc t-c2 attempt)"
bon c3 "$(mkp "$BUG2")" OVN_BUG_FIRST=off
eq "kill switch: best-of-N is the full 5 again" 5 "$(oc t-c3 attempt)"
bon c4 "$(mkp "$RB")"
eq "UNCHANGED: a roadmap item keeps best-of-N 5" 5 "$(oc t-c4 attempt)"
has "UNCHANGED: guard attempts=5 for it (ignored by the guard for non-bugs)" "$(cat "$RO_STUB/guard.log" 2>/dev/null)" "attempts=5"
bon c5 "$(mkp "- [ ] [T2] \`app/models/user.py\` — Manual-test bug (reported by Mark, flow x, 2026-10-02): alembic column missing. (cat:bugfix; src:manual) [feat:r-20261002-manual-cccc3333]")"
eq "schema-shaped bug does NOT get the schema N+2 (capped at 2)" 2 "$(oc t-c5 attempt)"
rm -f "$ST/pilot_flags.env"

echo "=== D: full main-loop escalation with the REAL guard ==="
rm -f "$T/tree/scripts/ovn_item_guard.sh"; ro_link scripts/ovn_item_guard.sh
# a stand-in stage runner: like the real one it journals the item it DECOMPOSED (state/stage_runs/<repo>-*.jsonl), which run_overnight.sh turns into the
# 'stage-item-hash'/'stage-item-line' markers (harness-credit-integrity item 8) the guard bills; the item it works is whatever $T/stage_item says
# (the test flips it to the roadmap line after the bug is escalated: "the lane moves on"). It fails the cycle (no summary event => no-op(stage-unverified)).
cat > "$T/tree/ovn_stage_runner.sh" <<EOSR
#!/bin/bash
mkdir -p state/stage_runs
jq -nc --arg i "\$(cat "$T/stage_item")" '{run:"r",event:"decomposed",item:\$i}' > "state/stage_runs/\$1-run.jsonl"
echo "ITEM stub"
exit 1
EOSR
stage_item(){ printf '%s' "${1#- \[ \] }" > "$T/stage_item"; }
d_run(){ # 1 cycle
  : > "$RO_STUB/aider_n"; rm -f "$RO_STUB/impl_n" "$RO_STUB/aider_kinds" "$T/tree/reports"/*
  ro_run_main "$@"; REP="$(ro_report)"
}
ro_mkrepo r-d1 "$(mkp "$RA" "$RB" "$BUG")" >/dev/null
printf 'IMPL_SEQ=none; SCOUT_EXTRA="a multi-file change"\n' > "$RO_STUB/scn"
echo "topic-d" > "$ST/ntfy_topic"
ro_tasks "$(jq -nc --arg R "$R" '[{id:"ongoing-d1",repo:($R+"/r-d1"),prompt:"Work the single top not-yet-done item in the overnight progress log."}]')"
stage_item "$BUG"
d_run
P1="$(cat "$R/r-d1/OVERNIGHT_PROGRESS.md")"
hasnt "cycle 1 (1 failed attempt): not escalated yet" "$P1" "bug-escalated"
ok "cycle 1: a bug counter exists" "$(ls "$ST"/item_fails/ongoing-d1.*.bugcount >/dev/null 2>&1 && echo 1 || echo 0)"
d_run
P2="$(cat "$R/r-d1/OVERNIGHT_PROGRESS.md")"
has "cycle 2: the bug line is now '[CLAUDE] [bug-escalated: ...]'" "$(printf '%s\n' "$P2" | grep -F 'Manual-test bug')" "[CLAUDE] [bug-escalated: 2 failed attempts (cap 2)"
hasnt "cycle 2: NOT AUTO-SKIPped" "$P2" "AUTO-SKIP"
ok "bug_escalations.jsonl written by the real loop (one line, repo r-d1)" "$([ "$(wc -l < "$ST/bug_escalations.jsonl" 2>/dev/null | tr -d ' ')" = 1 ] && grep -q '"repo":"r-d1"' "$ST/bug_escalations.jsonl" && echo 1 || echo 0)"
stage_item "$RA"      # the bug is parked/escalated: the stage runner now picks the roadmap item
d_run
d_run
P3="$(cat "$R/r-d1/OVERNIGHT_PROGRESS.md")"
eq "after escalation the loop works the roadmap again and writes no second escalation" 1 "$(wc -l < "$ST/bug_escalations.jsonl" | tr -d ' ')"
hasnt "the roadmap item the lane moved on to was not tagged as a bug escalation" "$(printf '%s\n' "$P3" | grep -F 'ALPHA')" "bug-escalated"

ro_summary
