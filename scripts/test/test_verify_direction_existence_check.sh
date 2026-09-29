#!/usr/bin/env bash
# Regression test for ovn_verify_direction_check.sh's check 3 (existence-only VERIFY on
# cat:schema/cat:endpoint items, added 2026-09-29). Root cause this closes: two of the
# costliest bugs found this week were both schema/API changes with existence-only VERIFY
# clauses that never tested real behavior - a "referral" model got marked done and credited
# despite the file never being created (VERIFY was just an import check), and an Alembic
# migration item's VERIFY was a bare hasattr() that could never catch a broken migration.
#
# Verifies: (a) a cat:schema item with a bare hasattr(...) VERIFY IS flagged, (b) a cat:schema
# item with a real pytest-delegated VERIFY is NOT flagged (correctness lives in the test file),
# (c) a non-schema/endpoint-tagged item with an equally shallow VERIFY is NOT flagged (scope is
# deliberately narrow - schema/endpoint work only, not every VERIFY in the fleet), and (d) an
# already-flagged item does not re-alert on a second run (dedup via state/verify_direction_seen.txt).
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
# The live box keeps this script under scripts/; the shared-repo mirror keeps it at top level.
SCRIPT="$OQ/scripts/ovn_verify_direction_check.sh"
[ -f "$SCRIPT" ] || SCRIPT="$OQ/ovn_verify_direction_check.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: ovn_verify_direction_check.sh not found under $OQ (checked scripts/ and top level)"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# The script does `cd "$HOME/overnight-queue"` itself, so give it a fixture HOME with the
# real script mirrored in, plus empty backlog/state/logs dirs — never touches production data.
mkdir -p "$tmp/overnight-queue/backlog" "$tmp/overnight-queue/state" "$tmp/overnight-queue/logs"
cp "$SCRIPT" "$tmp/overnight-queue/ovn_verify_direction_check.sh"

run_check(){ # $1=repo
  ( HOME="$tmp" bash "$tmp/overnight-queue/ovn_verify_direction_check.sh" "$1" >/dev/null 2>&1 )
}
seen_file(){ echo "$tmp/overnight-queue/state/verify_direction_seen.txt"; }
log_file(){ echo "$tmp/overnight-queue/logs/ovn_verify_direction_check.log"; }

cat > "$tmp/overnight-queue/backlog/testrepo.md" <<'EOF'
# Backlog

- [ ] [T2] app/models/referral.py - Add Referral model with a `status` field. VERIFY: `python -c "from app.models.referral import Referral; assert hasattr(Referral, 'status')"`. (cat:schema)
- [ ] [T2] app/models/order.py - Add Order model with a `total` field, covered by a real test. VERIFY: `pytest tests/test_order_model.py -q`. (cat:schema)
- [ ] [T2] app/utils/formatter.py - Refactor date formatting helper for readability. VERIFY: `python -c "from app.utils.formatter import format_date"`. (multifile:no)
- [ ] [T2] app/api/webhooks.py - Add /webhooks/stripe endpoint. VERIFY: `python -c "from app.api.webhooks import router; assert router is not None"`. (cat:endpoint)
EOF

# ---- run 1: schema item w/ bare hasattr flags, real-pytest schema item does not, non-schema
#      item with an equally shallow VERIFY does not (scope stays narrow), endpoint item w/ bare
#      "is not None" also flags ----
run_check testrepo
LOG="$(cat "$(log_file)" 2>/dev/null)"

ok "bare-hasattr cat:schema item IS flagged as existence-only" \
   "printf '%s' \"\$LOG\" | grep -q 'existence-only.*referral.py'"
ok "real pytest-delegated cat:schema item is NOT flagged" \
   "! printf '%s' \"\$LOG\" | grep -q 'existence-only.*order.py'"
ok "non-schema/endpoint-tagged item with a shallow VERIFY is NOT flagged (narrow scope)" \
   "! printf '%s' \"\$LOG\" | grep -q 'existence-only.*formatter.py'"
ok "bare 'is not None' cat:endpoint item IS flagged as existence-only" \
   "printf '%s' \"\$LOG\" | grep -q 'existence-only.*webhooks.py'"

ok "seen-file records exactly 2 existence-only (e:) entries after run 1" \
   "[ \"\$(grep -c '^e:' \"\$(seen_file)\")\" = 2 ]"

# ---- run 2 (dedup): same backlog, unchanged -> no NEW existence-only findings this time ----
: > "$(log_file)"
run_check testrepo
LOG2="$(cat "$(log_file)" 2>/dev/null)"
ok "second run on the same still-open items does not re-alert (dedup holds)" \
   "! printf '%s' \"\$LOG2\" | grep -q 'NEW existence-only'"
ok "second run still logs a clean-run line (no new findings, not an error)" \
   "printf '%s' \"\$LOG2\" | grep -qE 'clean run|existence-only item.s. this run'"

echo "Verify-direction existence-only check: $P passed, $F failed"
[ "$F" -eq 0 ]
