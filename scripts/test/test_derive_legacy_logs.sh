#!/usr/bin/env bash
# Regression test for ovn_derive_legacy_logs.py — Phase 5 Step 1 of the pipeline-
# hardening plan (strangler-fig derivation of task_stats.log/cycle_summary.log FROM
# outcomes.jsonl, run alongside the existing writers, not replacing them).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="${OVN_DERIVE_LOGS:-$HERE/../ovn_derive_legacy_logs.py}"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/ovn_derive_legacy_logs.py"
[ -f "$SCRIPT" ] || { echo "  SKIP: ovn_derive_legacy_logs.py not found"; exit 0; }

rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state"

write_outcome(){ # $1=ts $2=repo $3=id $4=tier $5=category $6=status
  python3 -c "
import json
print(json.dumps({'ts':'$1','repo':'$2','id':'$3','tier':'$4','category':'$5','status':'$6'}))
" >> "$tmp/state/outcomes.jsonl"
}

# ---- 1: each real outcome-code vocabulary value maps correctly (ported from cycle_notify.sh) ----
declare -A cases=(
  ["pushed(tests:pass)"]="pass"
  ["reverted(build-break)"]="revert"
  ["build-gate reverted a commit"]="revert"
  ["error(model/API error - see log)"]="error"
  ["(already-satisfied in code, implement-verified) ALREADY-DONE"]="noop:done"
  ["no-op(BLOCKED)"]="noop:blocked"
  ["no-op(NEEDS-DECISION)"]="noop:blocked"
  ["no-op(reverted-red)"]="noop:gate"
  ["no-op(ALREADY-DONE)"]="noop:done"
  ["no-op"]="noop:flail"
  ["disabled — skipping"]="skip"
)
i=0
for status in "${!cases[@]}"; do
  i=$((i+1))
  expected="${cases[$status]}"
  write_outcome "2026-09-27T10:0${i}:00Z" "testrepo" "ongoing-testrepo" "2" "py" "$status"
done
python3 "$SCRIPT" "$tmp/state" >/dev/null
for status in "${!cases[@]}"; do
  expected="${cases[$status]}"
  ok "status '${status:0:30}...' maps to outcome code '$expected'" \
     "grep -qP '\t${expected}\t' '$tmp/state/task_stats.derived.log'"
done

# ---- 2: fields are correctly derived (epoch, repo, tier, category tag) ----
line="$(grep 'testrepo' "$tmp/state/task_stats.derived.log" | head -1)"
ok "task_stats line has 5 tab-separated fields" "[ \"\$(echo \"\$line\" | awk -F'\t' '{print NF}')\" -eq 5 ]"
ok "derived tag includes the category and tier" "echo \"\$line\" | grep -qE '\{py·py·T2·\?\}'"

cs_line="$(grep 'ongoing-testrepo' "$tmp/state/cycle_summary.derived.log" | head -1)"
ok "cycle_summary line has verdict=PROCEED" "echo \"\$cs_line\" | grep -q 'verdict=PROCEED'"
ok "cycle_summary line includes the derived class tag" "echo \"\$cs_line\" | grep -qE 'class=\{py·py·T2·\?\}'"

# ---- 3: incremental cursor — a second run with no new records adds nothing ----
n1=$(wc -l < "$tmp/state/task_stats.derived.log")
python3 "$SCRIPT" "$tmp/state" >/dev/null
n2=$(wc -l < "$tmp/state/task_stats.derived.log")
[ "$n1" -eq "$n2" ] && ok "re-running with no new outcomes.jsonl records adds nothing (cursor works)" || fail "re-run duplicated records ($n1 -> $n2)"

# ---- 4: a genuinely NEW record after the cursor gets picked up on the next run ----
write_outcome "2026-09-27T11:00:00Z" "newrepo" "ongoing-newrepo" "3" "vue" "pushed(tests:pass)"
python3 "$SCRIPT" "$tmp/state" >/dev/null
grep -q "newrepo" "$tmp/state/task_stats.derived.log" && ok "a new record appended after the cursor is picked up on the next run" || fail "new record was not derived"

# ---- 5: cursor resets safely if outcomes.jsonl is truncated/rotated (cursor > file size) ----
: > "$tmp/state/outcomes.jsonl"
write_outcome "2026-09-27T12:00:00Z" "rotatedrepo" "ongoing-rotatedrepo" "1" "docs" "pushed(tests:pass)"
python3 "$SCRIPT" "$tmp/state" >/dev/null
grep -q "rotatedrepo" "$tmp/state/task_stats.derived.log" && ok "a truncated/rotated outcomes.jsonl is handled without crashing (cursor resets)" || fail "did not recover from file truncation"

# ---- 6: missing outcomes.jsonl entirely -> exits cleanly, no crash ----
rm -rf "$tmp/empty_state"; mkdir -p "$tmp/empty_state"
python3 "$SCRIPT" "$tmp/empty_state" >/dev/null 2>&1
empty_rc=$?
ok "missing outcomes.jsonl exits cleanly (no crash)" "[ $empty_rc -eq 0 ]"

[ $rc -eq 0 ] && echo "  legacy-log derivation (Phase 5 step 1): ALL PASS" || echo "  legacy-log derivation (Phase 5 step 1): FAILURES"
exit $rc
