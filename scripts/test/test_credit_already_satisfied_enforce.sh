#!/usr/bin/env bash
# Regression test for ovn_credit_already_satisfied.sh's 2026-09-28 shadow->enforce
# promotion: a credit whose own VERIFY clause genuinely fails must be REFUSED (left
# open) in enforce mode, and must still credit as before in shadow mode (instant
# rollback path) or when the VERIFY clause passes / doesn't exist.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../ovn_credit_already_satisfied.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/ovn_credit_already_satisfied.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: ovn_credit_already_satisfied.sh not found"; exit 0; }
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

cat > OVERNIGHT_PROGRESS.md << 'PROG'
## Next Steps
- [ ] [T1] pass_file.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] fail_file.py — Add a real thing. VERIFY: `false`. (cat:python; multifile:no)
- [ ] [T1] noverify_file.py — Add a real thing with no verify clause at all. (cat:python; multifile:no)
PROG

cat > aider.log << 'LOG'
pass_file.py
This is already done, no changes needed.
fail_file.py
This is already done, no changes needed.
noverify_file.py
This is already done, no changes needed.
LOG

# --- enforce mode (new default): pass credits, fail is REFUSED, no-verify credits ---
rm -f state/verify_gate_shadow.log 2>/dev/null
cp OVERNIGHT_PROGRESS.md /tmp/prog_enforce.md
( cd "$tmp" && cp /tmp/prog_enforce.md OVERNIGHT_PROGRESS.md && OVN_VERIFY_SHADOW_LOG="$tmp/shadow_enforce.log" bash "$SCRIPT" aider.log OVERNIGHT_PROGRESS.md > /tmp/out_enforce.txt 2>&1 )
out_enforce="$(cat /tmp/out_enforce.txt)"
grep -q '^- \[x\].*pass_file.py' OVERNIGHT_PROGRESS.md && ok "enforce: PASSing VERIFY credits normally" || fail "enforce: pass_file.py was not credited"
grep -q '^- \[ \].*fail_file.py' OVERNIGHT_PROGRESS.md && ok "enforce: FAILing VERIFY is REFUSED (left open)" || fail "enforce: fail_file.py was wrongly credited despite a failing VERIFY"
grep -q '^- \[x\].*noverify_file.py' OVERNIGHT_PROGRESS.md && ok "enforce: no-VERIFY-clause item still credits (unaffected)" || fail "enforce: noverify_file.py was not credited"
echo "$out_enforce" | grep -q 'REFUSED credit.*fail_file.py' && ok "enforce: refusal is logged with the file name" || fail "enforce: no REFUSED log line for fail_file.py"
echo "$out_enforce" | grep -q 'CREDITED=2' && ok "enforce: CREDITED count excludes the refused item (2 of 3)" || fail "enforce: wrong CREDITED count: $out_enforce"

# --- shadow mode (instant rollback): ALL three credit, old behavior preserved ---
cp /tmp/prog_enforce.md OVERNIGHT_PROGRESS.md
OVN_VERIFY_SHADOW_LOG="$tmp/shadow_rollback.log" OVN_VERIFY_GATE_MODE=shadow bash "$SCRIPT" aider.log OVERNIGHT_PROGRESS.md > /tmp/out_shadow.txt 2>&1
grep -q '^- \[x\].*fail_file.py' OVERNIGHT_PROGRESS.md && ok "shadow mode (rollback): FAILing VERIFY still credits (pre-promotion behavior)" || fail "shadow mode: fail_file.py was wrongly refused"
grep -q 'CREDITED=3' /tmp/out_shadow.txt && ok "shadow mode (rollback): all 3 credited, matching pre-promotion behavior" || fail "shadow mode: wrong CREDITED count: $(cat /tmp/out_shadow.txt)"

# --- the shadow log itself is still written in both modes (observability preserved) ---
grep -q 'result=PASS' "$tmp/shadow_enforce.log" && ok "shadow log still records PASS in enforce mode" || fail "shadow log missing PASS record in enforce mode"
grep -q 'result=FAIL' "$tmp/shadow_enforce.log" && ok "shadow log still records FAIL in enforce mode" || fail "shadow log missing FAIL record in enforce mode"

[ $rc -eq 0 ] && echo "  credit-already-satisfied enforce promotion: ALL PASS" || echo "  credit-already-satisfied enforce promotion: FAILURES"
exit $rc
