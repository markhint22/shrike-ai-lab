#!/usr/bin/env bash
# Regression test: ovn_park_sweep.py must relocate AUTO-SKIP/HUMAN-ONLY items out of the
# active flow, idempotently, without disturbing real work or prose mentions (2026-09-09).
#
# Real incident: the scout+implement loop reads OVERNIGHT_PROGRESS.md top-down and treats the
# first open `- [ ] ` line as the current item — it does NOT mechanically skip parked lines
# itself. As real items above a parked one get completed, the parked line naturally drifts to
# the front and burns a full model call every cycle correctly reporting "BLOCKED" before ever
# reaching real work. Confirmed: xlite alone burned 73 such calls (~2.5M tokens) over 3 days on
# one stuck line; 5 of 7 active repos had a parked item as their literal first open line at
# time of discovery.
set -uo pipefail
PY="${OVN_PARK_SWEEP:-$HOME/overnight-queue/ovn_park_sweep.py}"
[ -f "$PY" ] || { echo "  SKIP: $PY not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
f="$tmp/OVERNIGHT_PROGRESS.md"
cat > "$f" <<'EOF'
# Overnight Progress

## Current Status
Some notes mentioning AUTO-SKIP in prose should never be swept, only real bullet lines.

- [ ] [AUTO-SKIP after 5 no-op cycles — review] [T1] foo.py — do a thing. VERIFY: pytest -q
- [x] [T1] bar.py — already done.
- [ ] [T2] baz.py — real actionable work. VERIFY: pytest -q
- [ ] [HUMAN-ONLY BLOCKED ITEM] needs a human decision about pricing.
- [ ] [T1] qux.py — more real work. VERIFY: pytest -q
EOF

out1="$(python3 "$PY" "$f")"
ok "first sweep moves exactly 2 parked items" "[ \"$out1\" = 'SWEPT=2' ]"
ok "real work (baz.py) is now the first open line" \
   "[ \"\$(grep -m1 -n '^- \[ \] ' '$f' | grep -c baz.py)\" -eq 1 ]"
ok "prose mention of AUTO-SKIP is untouched (still just one non-bullet mention)" \
   "[ \$(grep -c 'notes mentioning AUTO-SKIP' '$f') -eq 1 ]"
ok "a Parked holding-pen header was created" "grep -q '^### Parked' '$f'"
ok "both parked items now sit below the header" \
   "[ \$(sed -n '/^### Parked/,\$p' '$f' | grep -cE '^- \[ \] \[(AUTO-SKIP|HUMAN-ONLY)') -eq 2 ]"

cp "$f" "$tmp/after_run1.md"
out2="$(python3 "$PY" "$f")"
ok "immediate re-run is a no-op" "[ \"$out2\" = 'SWEPT=0' ]"
ok "immediate re-run does not modify the file" "diff -q '$tmp/after_run1.md' '$f' >/dev/null"

# simulate drift: baz.py (currently real, above the header) later gets auto-skipped too
sed -i.bak 's/- \[ \] \[T2\] baz.py — real actionable work. VERIFY: pytest -q/- [ ] [AUTO-SKIP after 4 failed-to-land cycles — review] [T2] baz.py — real actionable work. VERIFY: pytest -q/' "$f"
out3="$(python3 "$PY" "$f")"
ok "later drift (a new parked item above the header) gets swept too" "[ \"$out3\" = 'SWEPT=1' ]"
ok "previously-parked items are undisturbed by the second sweep" \
   "[ \$(sed -n '/^### Parked/,\$p' '$f' | grep -cE '^- \[ \] \[(AUTO-SKIP|HUMAN-ONLY)') -eq 3 ]"
ok "only qux.py remains as real open work above the header" \
   "[ \$(sed -n '1,/^### Parked/p' '$f' | grep -cE '^- \[ \] ') -eq 1 ]"

rm -rf "$tmp"
echo "Park sweep: $P passed, $F failed"
[ "$F" -eq 0 ]
