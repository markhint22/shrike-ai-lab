#!/usr/bin/env bash
# Regression test for ovn_credit_already_satisfied.sh's SHADOW-MODE verify gate
# (2026-09-24). Verifies:
#   - crediting behavior is UNCHANGED (shadow mode never blocks/demotes)
#   - a passing VERIFY: clause logs result=PASS
#   - a failing VERIFY: clause logs result=FAIL (this is the false-credit case
#     confirmed live in billwatch - a credited item whose own VERIFY fails)
#   - a line with no VERIFY: clause logs result=NO_VERIFY_CLAUSE, doesn't crash
#   - a denylisted (destructive-looking) VERIFY: clause is skipped, not executed
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../ovn_credit_already_satisfied.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/../../scripts/ovn_credit_already_satisfied.sh"
[ -f "$SCRIPT" ] || { echo "  ❌ ovn_credit_already_satisfied.sh not found"; exit 1; }
rc=0; fail(){ echo "  ❌ $1"; rc=1; }; ok(){ echo "  ✅ $1"; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1

# --- fixture: a repo dir with one file that genuinely exists, one that doesn't ---
mkdir -p app/utils
echo "def real(): pass" > app/utils/real_thing.py

prog="OVERNIGHT_PROGRESS.md"
cat > "$prog" <<'EOF'
# progress
- [ ] [T1] app/utils/real_thing.py — Do a thing. VERIFY: `test -f app/utils/real_thing.py`. (cat:python)
- [ ] [T1] app/utils/fake_thing.py — Do a thing that never landed. VERIFY: `test -f app/utils/fake_thing.py`. (cat:python)
- [ ] [T1] app/utils/no_clause.py — An item with no backtick VERIFY clause at all
- [ ] [T1] app/utils/danger.py — A denylist-triggering clause. VERIFY: `rm -rf /tmp/whatever`. (cat:python)
EOF

task_log="task.log"
cat > "$task_log" <<'EOF'
Looking at the item, real_thing.py already handles this correctly - no changes needed.
Checking fake_thing.py — this already exists and already implements the logic, already done.
Checking no_clause.py — already present, no changes needed.
Checking danger.py — already handled, already correct.
EOF

shadow_log="$tmp/state/verify_gate_shadow.log"
OVN_VERIFY_SHADOW_LOG="$shadow_log" bash "$SCRIPT" "$task_log" "$prog" > /tmp/credit_out.$$ 2>&1
out="$(cat /tmp/credit_out.$$)"; rm -f /tmp/credit_out.$$

# --- crediting behavior unchanged: all 4 items should still get credited ---
credited_count="$(grep -cE '^\- \[x\] \(already-satisfied' "$prog")"
[ "$credited_count" -eq 4 ] && ok "crediting behavior unchanged (4/4 still credited despite shadow gate)" || fail "expected 4 credited, got $credited_count"

[ -f "$shadow_log" ] || { fail "shadow log was never written"; echo "$out"; exit 1; }

grep -qE "result=PASS.*real_thing\.py" "$shadow_log" && ok "real, existing file -> shadow result=PASS" || fail "expected PASS for real_thing.py"
grep -qE "result=FAIL.*fake_thing\.py" "$shadow_log" && ok "never-landed file -> shadow result=FAIL (the false-credit case)" || fail "expected FAIL for fake_thing.py"
grep -q "result=NO_VERIFY_CLAUSE" "$shadow_log" && ok "line with no VERIFY: clause -> NO_VERIFY_CLAUSE, no crash" || fail "expected NO_VERIFY_CLAUSE"
grep -q "result=SKIPPED_DENYLIST" "$shadow_log" && ok "destructive-looking clause -> SKIPPED_DENYLIST, not executed" || fail "expected SKIPPED_DENYLIST"
[ ! -e /tmp/whatever ] && ok "denylisted rm -rf was never actually executed" || fail "DANGER: denylisted command executed"

echo "$out" | grep -q "CREDITED=4" && ok "script still reports CREDITED=4" || fail "expected CREDITED=4 in output: $out"

if [ "$rc" -eq 0 ]; then echo "credit_verify_shadow: all checks passed"; else echo "credit_verify_shadow: FAILURES ABOVE"; fi
exit $rc
