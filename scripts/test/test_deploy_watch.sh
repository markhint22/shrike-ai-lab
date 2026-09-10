#!/usr/bin/env bash
# Regression test for the deploy self-heal enqueuer (ovn_enqueue_emergency.py).
# Verifies the injection contract deploy_watch.sh relies on:
#   - an emergency item is prepended ABOVE existing open items (scout picks it first)
#   - it lands after a leading H1, inside the 🚨 Emergency section
#   - re-running for the SAME service is a no-op (cron can't stack duplicates)
#   - a DIFFERENT service DOES get its own item
#   - a missing file is handled (created with the item)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ENQ="$HERE/../ovn_enqueue_emergency.py"
[ -f "$ENQ" ] || ENQ="$HERE/ovn_enqueue_emergency.py"   # fallback if colocated
rc=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail(){ echo "  ❌ $1"; rc=1; }
ok(){ echo "  ✅ $1"; }

f="$tmp/OVERNIGHT_PROGRESS.md"
cat > "$f" <<'EOF'
# Overnight Progress — billwatch

## Open
- [ ] [T1] add a helper
- [ ] [T2] add another helper
- [x] [T1] done thing
EOF

ITEM="- [ ] [T4] billwatch — 🚨 EMERGENCY DEPLOY FIX (auto-added 2026-09-03): the Railway PRODUCTION deploy for 'billwatch' FAILED. ERROR EXCERPT: multiple head revisions are present"

# 1. inject
python3 "$ENQ" "$f" billwatch "$ITEM" >/dev/null || fail "enqueue exited non-zero"
grep -q "🚨 EMERGENCY DEPLOY FIX" "$f" && ok "emergency item present" || fail "emergency item missing"

# 2. H1 preserved as first line
[ "$(head -1 "$f")" = "# Overnight Progress — billwatch" ] && ok "H1 preserved" || fail "H1 clobbered"

# 3. emergency OPEN item appears before the pre-existing open items (scout order)
em_ln=$(grep -nF "🚨 EMERGENCY DEPLOY FIX" "$f" | head -1 | cut -d: -f1)
first_old_ln=$(grep -nF "add a helper" "$f" | head -1 | cut -d: -f1)
[ "$em_ln" -lt "$first_old_ln" ] && ok "emergency ranks above existing open items" || fail "emergency not above existing items ($em_ln !< $first_old_ln)"

# 4. dedup — same service again is a no-op (still exactly one emergency item)
python3 "$ENQ" "$f" billwatch "$ITEM" >/dev/null || fail "dedup run exited non-zero"
n=$(grep -cF "🚨 EMERGENCY DEPLOY FIX" "$f")
[ "$n" -eq 1 ] && ok "dedup: still exactly 1 item for billwatch" || fail "dedup failed (found $n)"

# 5. a different service DOES get added
ITEM2="- [ ] [T4] gitlark — 🚨 EMERGENCY DEPLOY FIX (auto-added 2026-09-03): the Railway PRODUCTION deploy for 'gitlark' FAILED. ERROR EXCERPT: boom"
python3 "$ENQ" "$f" gitlark "$ITEM2" >/dev/null || fail "second-service run exited non-zero"
n=$(grep -cF "🚨 EMERGENCY DEPLOY FIX" "$f")
[ "$n" -eq 2 ] && ok "distinct service adds its own item (2 total)" || fail "second service not added (found $n)"

# 6. missing file is created
mf="$tmp/new.md"
python3 "$ENQ" "$mf" billwatch "$ITEM" >/dev/null || fail "missing-file run exited non-zero"
[ -f "$mf" ] && grep -q "🚨 EMERGENCY DEPLOY FIX" "$mf" && ok "missing file created with item" || fail "missing file not handled"

[ $rc -eq 0 ] && echo "  deploy_watch enqueuer: ALL PASS" || echo "  deploy_watch enqueuer: FAILURES"
exit $rc
