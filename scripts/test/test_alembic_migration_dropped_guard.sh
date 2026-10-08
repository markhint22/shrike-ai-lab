#!/usr/bin/env bash
# Regression test for ovn_recover_parked.sh's ALEMBIC-MIGRATION-DROPPED GUARD (2026-09-29).
#
# A decomposed schema-change sub-item that drops the original item's Alembic migration
# step is unlandable no matter how well the 27B implements it -
# backend/tests/test_migration_drift.py::test_alembic_head_matches_models fails the
# instant a model gains a column with no matching migration, and the decomposer only
# ever sees ONE tiny "add columns to X + assert hasattr" step at a time - it has no
# visibility into the fact that dropping the original `alembic revision --autogenerate
# ...` VERIFY guarantees every sub-item reverts forever on the same gate. Confirmed live
# on test-automation-agent: item_hash e10cebb4 (ScheduledRun.plan_source/plan_upload_id)
# reverted 3x the same day (2026-09-29 08:11/08:58/09:11 CDT), same NO-NEW-RED GUARD
# failure on the same test every time, after recovery decomposed the original item
# (VERIFY: `alembic revision --autogenerate -m "add plan source fields" && alembic
# upgrade head`) into a bare `hasattr(...)` check that never touches Alembic at all.
#
# Extracts the real guard block out of ovn_recover_parked.sh (not a reimplementation) so
# this can't silently drift from what's deployed.
set -uo pipefail
RP="${OVN_RECOVER_PARKED:-$HOME/overnight-queue/ovn_recover_parked.sh}"
[ -f "$RP" ] || { echo "  SKIP: $RP not found on this host"; exit 0; }

BLOCK="$(sed -n '/^  # ALEMBIC-MIGRATION-DROPPED GUARD/,/^  # ALREADY-SATISFIED FILTER/p' "$RP")"
[ -n "$BLOCK" ] || { echo "  FAIL: could not extract the alembic-migration-dropped guard block from $RP"; exit 1; }
case "$BLOCK" in
  *'ALEMBIC-MIGRATION-DROPPED GUARD'*'alembic (revision|upgrade)'*) : ;;
  *) echo "  FAIL: extracted block doesn't look like the expected guard:"; printf '%s\n' "$BLOCK"; exit 1 ;;
esac

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

say(){ :; }  # the real script's logger - a no-op here, we only assert on $items

run_guard(){ # $1=task $2=items(newline-separated) -> prints resulting $items
  local task="$1" items="$2" r=test
  eval "$BLOCK" >/dev/null 2>&1
  printf '%s' "$items"
}

# --- A: original item names an Alembic command, decomposed sub-items never mention
#     Alembic at all -> decomposition dropped required work, must be escalated ---
task_a='backend/app/models/ci.py — Add `plan_source` and `plan_upload_id` columns to `ScheduledRun`. VERIFY: `alembic revision --autogenerate -m "add plan source fields" && alembic upgrade head`.'
items_a="- [ ] [T1] backend/app/models/ci.py — Add \`plan_source\` column to \`ScheduledRun\`. VERIFY: \`python -c \"from app.models.ci import ScheduledRun; assert hasattr(ScheduledRun, 'plan_source')\"\`. (cat:schema)"
result_a="$(run_guard "$task_a" "$items_a")"
ok "decomposition that drops the Alembic step is replaced with a [CLAUDE] escalation" \
   "printf '%s' \"\$result_a\" | grep -q '\[CLAUDE\]'"
ok "escalation note explains the dropped-migration reason" \
   "printf '%s' \"\$result_a\" | grep -qi 'alembic'"
ok "the unlandable hasattr-only sub-item is NOT kept alongside the escalation" \
   "! printf '%s' \"\$result_a\" | grep -q 'hasattr'"

# --- B: original item names an Alembic command, and at least one decomposed sub-item
#     DOES preserve it -> decomposition kept the required work, must pass through as-is ---
task_b='backend/app/models/ci.py — Add `plan_source` column to `ScheduledRun`. VERIFY: `alembic revision --autogenerate -m "add plan source" && alembic upgrade head`.'
items_b="- [ ] [T2] backend/app/models/ci.py — Add \`plan_source\` column AND a matching migration. VERIFY: \`alembic revision --autogenerate -m \"add plan source\" && alembic upgrade head\`. (cat:schema)"
result_b="$(run_guard "$task_b" "$items_b")"
ok "decomposition that keeps the Alembic step passes through untouched" \
   "[ \"\$result_b\" = \"\$items_b\" ]"

# --- C: original item never mentions Alembic at all -> guard must never fire
#     (no false positive on ordinary, non-schema decompositions) ---
task_c='backend/app/services/ci_service.py — Implement resolve_test_plan(db, integration). VERIFY: pytest backend/tests/test_ci_service.py -v.'
items_c="- [ ] [T2] backend/app/services/ci_service.py — Implement resolve_test_plan. VERIFY: \`pytest backend/tests/test_ci_service.py -v\`. (cat:python)"
result_c="$(run_guard "$task_c" "$items_c")"
ok "no Alembic mention in the original item: guard never fires, items pass through untouched" \
   "[ \"\$result_c\" = \"\$items_c\" ]"

echo "recover-parked alembic-migration-dropped guard: $P passed, $F failed"
[ "$F" -eq 0 ]
