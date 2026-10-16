#!/usr/bin/env bash
# Regression test: queue_refill.py's _norm() dedup must collapse a [feat:...]-tagged item
# regenerated under a new date onto the SAME identity as its already-queued/already-done
# sibling (2026-09-29 PREVENTIVE port — no confirmed live miss for this exact path yet).
#
# Mirrors scripts/test/test_item_guard_feattag_churn.sh's scenario A on the bash side
# (ovn_item_hash()'s date-strip): a roadmap regeneration mints a fresh YYYYMMDD/MMDDYY date
# stamp on the SAME feat-tag slug when it re-decomposes a stuck feature. Before this port,
# queue_refill.py's _norm() had no equivalent date-strip, so a backlog line that's byte-for-byte
# identical except for that one date would NOT dedup against its already-live/already-done
# twin — it would look like brand-new work and get pulled again.
#
# Also verifies the negative case: two DIFFERENT feat-tag slugs (not just a date bump) must
# NOT collapse into one identity — this port only normalizes the date inside a matched tag, it
# does not hash-the-tag-alone the way ovn_item_hash() does on the bash side (see queue_refill.py's
# 2026-09-29 comment for why: two sibling lines sharing one live feat-tag are still genuinely
# different content for this dedup's purposes).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RF="$HERE/../../queue_refill.py"; [ -f "$RF" ] || RF="$HERE/../queue_refill.py"; [ -f "$RF" ] || RF="$HERE/queue_refill.py"
[ -f "$RF" ] || { echo "  SKIP: queue_refill.py not found"; exit 0; }
rc=0; fail(){ echo "  FAIL: $1"; rc=1; }; ok(){ echo "  ok: $1"; }
tmp="$(mktemp -d)" || exit 1; trap 'rm -rf "$tmp"' EXIT

# --- A: SAME feat-tag slug, NEW date — must dedup (not re-pulled) ---
prog="$tmp/progA.md"; bl="$tmp/blA.md"
printf '# progress\n- [ ] [T2] `backend/app/models.py` — fix the thing [feat:shrike-notify-20260921-wire-check-message-field-duplicates]. VERIFY: `true`.\n' > "$prog"
printf '# backlog\n- [ ] [T2] `backend/app/models.py` — fix the thing [feat:shrike-notify-20260925-wire-check-message-field-duplicates]. VERIFY: `true`.\n' > "$bl"

OUT="$(python3 "$RF" "$prog" "$bl" 5)"
echo "$OUT" | grep -q "REFILL=0" && ok "regenerated feat-tag (new date, same slug) is NOT pulled as new work (REFILL=0)" \
  || fail "expected REFILL=0 (dedup should collapse date-only regeneration): $OUT"
echo "$OUT" | grep -q "PRUNED=1" && ok "regenerated feat-tag line is pruned from backlog as a duplicate (PRUNED=1)" \
  || fail "expected PRUNED=1: $OUT"
if [ -s "$bl" ] && grep -q "20260925" "$bl"; then
  fail "regenerated-date backlog line should have been removed as a duplicate, but is still present"
else
  ok "regenerated-date backlog line removed from backlog (deduped, not left to re-surface)"
fi

# --- B: a GENUINELY different feat-tag slug (not just a date bump) must NOT collapse ---
prog2="$tmp/progB.md"; bl2="$tmp/blB.md"
printf '# progress\n- [ ] [T2] `backend/app/models.py` — fix the thing [feat:shrike-notify-20260921-wire-check-message-field-duplicates]. VERIFY: `true`.\n' > "$prog2"
printf '# backlog\n- [ ] [T2] `backend/app/models.py` — fix the thing [feat:shrike-notify-20260921-completely-different-feature]. VERIFY: `true`.\n' > "$bl2"

OUT="$(python3 "$RF" "$prog2" "$bl2" 5)"
echo "$OUT" | grep -q "REFILL=1" && ok "a genuinely different feat-tag slug (not just a date bump) IS pulled as new work (REFILL=1)" \
  || fail "expected REFILL=1 (different slug must not be treated as a dup): $OUT"

# --- C: two DIFFERENT lines sharing one LIVE (non-churning) feat-tag are still treated as
#     different content by this dedup (unlike ovn_item_hash()'s hash-the-tag-alone behavior on
#     the bash side) — confirms the port only strips the embedded date, not the whole line ---
prog3="$tmp/progC.md"; bl3="$tmp/blC.md"
printf '# progress\n- [ ] [T2] `backend/app/models.py` — impl [feat:shrike-notify-20260921-shared-feature]. VERIFY: `true`.\n' > "$prog3"
printf '# backlog\n- [ ] [T2] `backend/tests/test_models.py` — test [feat:shrike-notify-20260921-shared-feature]. VERIFY: `true`.\n' > "$bl3"

OUT="$(python3 "$RF" "$prog3" "$bl3" 5)"
echo "$OUT" | grep -q "REFILL=1" && ok "a sibling sub-item sharing one live feat-tag is still pulled (not mistaken for a duplicate of its sibling)" \
  || fail "expected REFILL=1 (sibling sub-items must not collapse into one dedup key): $OUT"

# --- D (2026-10-11, harness R10 review): R01 rewrites a pulled bare VERIFY to the backticked form before it is stored, so a bare backlog copy that re-enters the backlog must still dedup
#     against the ticked backticked copy (else finished work is re-queued - the 2026-10-07 churn-loop shape) ---
prog4="$tmp/progD.md"; bl4="$tmp/blD.md"
printf '# progress\n- [x] [T1] app.py — add the helper. VERIFY: `grep -q "def helper" app.py` (cat:python; multifile:no) [feat:demo-20261011-bare-verify]\n' > "$prog4"
printf '# backlog\n- [ ] [T1] app.py — add the helper. VERIFY: grep -q "def helper" app.py (cat:python; multifile:no) [feat:demo-20261011-bare-verify]\n' > "$bl4"
OUT="$(OVN_SPEC_GATE_ENFORCE_RULES= python3 "$RF" "$prog4" "$bl4" 5)"
echo "$OUT" | grep -q "REFILL=0" && echo "$OUT" | grep -q "PRUNED=1" && ok "D a bare-VERIFY backlog copy of a finished item whose stored copy is backticked is a duplicate (REFILL=0 PRUNED=1)" \
  || fail "D expected REFILL=0 PRUNED=1 (backtick asymmetry re-queued finished work): $OUT"
OUT="$(python3 "$RF" "$prog4" "$bl4" 5)"
echo "$OUT" | grep -q "REFILL=0" && ok "D2 ... also with the default repair rules (R01) active" || fail "D2 expected REFILL=0 with default rules: $OUT"

# --- E: same class for R11 (gut_cli.gd -> gut_cmdln.gd rewritten at ingest) ---
prog5="$tmp/progE.md"; bl5="$tmp/blE.md"
printf '# progress\n- [x] [T2] test_x.gd — add a GUT test. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://test/test_x.gd` (cat:gdscript; multifile:no) [feat:demo-20261011-gut]\n' > "$prog5"
printf '# backlog\n- [ ] [T2] test_x.gd — add a GUT test. VERIFY: `godot --headless -s addons/gut/cli/gut_cli.gd -gtest=res://test/test_x.gd` (cat:gdscript; multifile:no) [feat:demo-20261011-gut]\n' > "$bl5"
OUT="$(OVN_SPEC_GATE_ENFORCE_RULES= python3 "$RF" "$prog5" "$bl5" 5)"
echo "$OUT" | grep -q "REFILL=0" && echo "$OUT" | grep -q "PRUNED=1" && ok "E an old gut_cli.gd backlog copy of a finished (gut_cmdln.gd-rewritten) item is a duplicate" \
  || fail "E expected REFILL=0 PRUNED=1: $OUT"

# --- F: CONTROL - a genuinely different VERIFY command must still NOT collapse ---
prog6="$tmp/progF.md"; bl6="$tmp/blF.md"
printf '# progress\n- [x] [T1] app.py — add the helper. VERIFY: `grep -q "def helper" app.py` (cat:python; multifile:no) [feat:demo-20261011-ctl]\n' > "$prog6"
printf '# backlog\n- [ ] [T1] app.py — add the helper. VERIFY: `grep -q "def other_helper" app.py` (cat:python; multifile:no) [feat:demo-20261011-ctl]\n' > "$bl6"
OUT="$(python3 "$RF" "$prog6" "$bl6" 5)"
echo "$OUT" | grep -q "REFILL=1" && ok "F CONTROL: an item with a different VERIFY command is still pulled" || fail "F expected REFILL=1: $OUT"

[ $rc -eq 0 ] && echo "test_queue_refill_feattag_norm: PASS" || echo "test_queue_refill_feattag_norm: FAIL"
exit $rc
