#!/usr/bin/env bash
# Regression test for ovn_credit_already_satisfied.sh's 2026-09-28 under-crediting fix.
#
# The "already done" detector was an exact-phrase match with zero tolerance for ordinary
# sentence variation, so a correctly-completed item whose model response was phrased even
# slightly differently ("This item appears to already be satisfied", "No further changes
# are needed", "already fully implemented", "already contains X", "does not need any
# changes") was scored as a flail instead of credited, and got re-served every cycle
# forever. Confirmed live on billwatch: a stuck item that was ALREADY correctly fixed in
# code kept re-failing for 4+ days, burning ~450K tokens, because of exactly this gap.
#
# Every phrasing tested here is a REAL response shape found by grepping 350+ recent model
# responses in logs/*billwatch*.log on the GPU box, not a guess. Each item's VERIFY is
# `true` so the enforce-mode VERIFY gate (a separate, already-tested mechanism — see
# test_credit_already_satisfied_enforce.sh) doesn't confound this recall-specific test.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../ovn_credit_already_satisfied.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/ovn_credit_already_satisfied.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: ovn_credit_already_satisfied.sh not found"; exit 0; }
rc=0; ok(){ echo "  OK: $1"; }; fail(){ echo "  FAIL: $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp"

cat > OVERNIGHT_PROGRESS.md << 'PROG'
## Next Steps
- [ ] [T1] already_be_satisfied.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] already_contains.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] already_defined.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] already_handles.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] already_satisfies.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] already_fine.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] no_further_changes.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] no_code_changes.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] does_not_need_changes.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] already_fully_implemented.py — Add a real thing. VERIFY: `true`. (cat:python; multifile:no)
- [ ] [T1] unrelated_untouched.py — a totally unrelated item that should stay open. VERIFY: `true`. (cat:python; multifile:no)
PROG

cat > aider.log << 'LOG'
already_be_satisfied.py
This item appears to already be satisfied.

already_contains.py
STATUS_ORDER already contains "to_president" at index 4, no change needed there.

already_defined.py
This class is already correctly defined as expected, no edit needed.

already_handles.py
Looking more carefully, the code already handles this: if not rows raise.

already_satisfies.py
The existing code already satisfies the requirement by using the imported helper.

already_fine.py
Looking at the file, it's already fine.

no_further_changes.py
The current content is correct from my previous edit. No further changes are needed.

no_code_changes.py
The feature is fully implemented with tests already in place. No code changes needed.

does_not_need_changes.py
Looking at this closely, the file does not need any changes.

already_fully_implemented.py
dashboard_metrics is already fully implemented in the code provided.

unrelated_untouched.py
Working on this now, here is my plan for a real edit.
LOG

OVN_VERIFY_SHADOW_LOG="$tmp/shadow.log" bash "$SCRIPT" aider.log OVERNIGHT_PROGRESS.md > "$tmp/out.txt" 2>&1
out="$(cat "$tmp/out.txt")"

for f in already_be_satisfied already_contains already_defined already_handles already_satisfies \
         already_fine no_further_changes no_code_changes does_not_need_changes already_fully_implemented; do
  if grep -q "^- \[x\].*${f}\.py" OVERNIGHT_PROGRESS.md; then
    ok "credited: ${f}.py"
  else
    fail "NOT credited (regression): ${f}.py — real model phrasing was missed"
  fi
done

if grep -q '^- \[ \].*unrelated_untouched.py' OVERNIGHT_PROGRESS.md; then
  ok "unrelated item with no already-done language stays open (no over-broadening)"
else
  fail "unrelated item was wrongly credited — the broadened regex over-matched"
fi

if echo "$out" | grep -q 'CREDITED=10'; then
  ok "CREDITED count is exactly 10 (all real phrasings, none of the unrelated item)"
else
  fail "wrong CREDITED count: $out"
fi

echo "credit-already-satisfied recall fix: rc=$rc"
exit $rc
