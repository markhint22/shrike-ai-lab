#!/usr/bin/env bash
# Regression test for queue_refill.py (the dumb, $0 backlog->queue puller).
# Verifies the refill contract the auto-refill loop relies on:
#   - exactly N eligible items move from backlog to the live queue (no loss, no dup)
#   - pulled items are REMOVED from the backlog (can't be pulled twice)
#   - [CLAUDE] and parked (AUTO-SKIP/HUMAN-ONLY/BLOCKED) items are NEVER pulled
#   - asking for more than available pulls only what's there
#   - an empty/missing backlog is a safe no-op (REFILL=0)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RF="$HERE/../../queue_refill.py"; [ -f "$RF" ] || RF="$HERE/../queue_refill.py"; [ -f "$RF" ] || RF="$HERE/queue_refill.py"
[ -f "$RF" ] || { echo "  ❌ queue_refill.py not found"; exit 1; }
rc=0; fail(){ echo "  ❌ $1"; rc=1; }; ok(){ echo "  ✅ $1"; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

prog="$tmp/prog.md"; bl="$tmp/bl.md"
printf '# progress\n- [ ] [T1] pre-existing item\n' > "$prog"
cat > "$bl" <<'EOF'
# backlog
- [ ] [T2] repo/a.py — spec A. VERIFY: x. (polish:validation)
- [ ] [T1] repo/b.py — spec B. VERIFY: y. (polish:docstrings)
- [ ] [CLAUDE] repo/big — a type-heavy refactor (must NOT be pulled)
- [ ] [T3] repo/c.py — spec C. VERIFY: z. (polish:tests)
- [ ] [T2] repo/d.vue — AUTO-SKIP parked item (must NOT be pulled)
- [ ] [T2] repo/e.py — spec E. VERIFY: e. (polish:error-handling)
EOF
# eligible = a,b,c,e = 4 (CLAUDE + AUTO-SKIP excluded)

OUT="$(python3 "$RF" "$prog" "$bl" 2)"
echo "$OUT" | grep -q "REFILL=2" && ok "pull 2 -> REFILL=2" || fail "expected REFILL=2: $OUT"
echo "$OUT" | grep -q "BACKLOG_REMAINING=2" && ok "2 eligible remain" || fail "expected REMAINING=2: $OUT"
[ "$(grep -cE '^- \[ \] \[T[1-5]\]' "$prog")" -eq 3 ] && ok "queue now has 3 (1 pre + 2 pulled)" || fail "queue count wrong"
grep -q "CLAUDE" "$bl" && ok "[CLAUDE] item retained in backlog" || fail "[CLAUDE] should stay"
grep -q "AUTO-SKIP" "$bl" && ok "parked item retained in backlog" || fail "parked should stay"
# no dup: the 2 pulled items (first two eligible: spec A, spec B) must be gone from backlog
if ! grep -q "spec A" "$bl" && ! grep -q "spec B" "$bl" && grep -q "spec C" "$bl" && grep -q "spec E" "$bl"; then
  ok "pulled items removed from backlog, un-pulled retained (no dup, no loss)"
else fail "backlog not correctly decremented"; fi

# pull more than available: only 2 eligible left -> pulls 2
OUT="$(python3 "$RF" "$prog" "$bl" 99)"
echo "$OUT" | grep -q "REFILL=2" && ok "over-ask pulls only remaining 2" || fail "expected REFILL=2 on over-ask: $OUT"
echo "$OUT" | grep -q "BACKLOG_REMAINING=0" && ok "backlog now dry (0 eligible)" || fail "expected REMAINING=0: $OUT"

# empty backlog -> safe no-op
OUT="$(python3 "$RF" "$prog" "$bl" 5)"
echo "$OUT" | grep -q "REFILL=0" && ok "dry backlog -> REFILL=0 (no-op)" || fail "expected REFILL=0: $OUT"

# missing backlog file -> safe no-op
OUT="$(python3 "$RF" "$prog" "$tmp/nonexistent.md" 5)"
echo "$OUT" | grep -q "REFILL=0" && ok "missing backlog -> REFILL=0 (safe)" || fail "expected REFILL=0 for missing: $OUT"

# dedup: an item already present in the live queue is NOT pulled again (no duplicates)
prog2="$tmp/prog2.md"; bl2="$tmp/bl2.md"
printf '# progress\n- [ ] [T2] app/x.py — do the X thing. VERIFY: t.\n' > "$prog2"
printf '# backlog\n- [ ] [T2] app/x.py — do the X thing. VERIFY: t.\n- [ ] [T1] app/y.py — do Y. VERIFY: u.\n' > "$bl2"
OUT="$(python3 "$RF" "$prog2" "$bl2" 5)"
echo "$OUT" | grep -q "REFILL=1" && ok "dedup: only the non-duplicate item pulled (REFILL=1)" || fail "expected REFILL=1 (dedup): $OUT"
xc=$(grep -c "app/x.py" "$prog2")
if [ "$xc" -eq 1 ] && grep -q "app/y.py" "$prog2"; then ok "dedup: existing item not duplicated, new item added"; else fail "dedup wrong (x count=$xc)"; fi

[ $rc -eq 0 ] && echo "  test_queue_refill: PASS" || echo "  test_queue_refill: FAIL"
exit $rc
