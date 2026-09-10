#!/usr/bin/env bash
# Regression test: queue_refill.py must pre-check an item's own VERIFY command and credit it
# WITHOUT ever queueing it for the 27B, when the check already passes against current code
# (2026-09-10).
#
# Real incident this closes: shrike-monitor alone had 19 backlog items that were already fully
# implemented (a stale decomposition snapshot) — every one of them cost N wasted no-op cycles
# before the existing AUTO-SKIP-after-N-cycles safety net finally parked it. Most items' VERIFY
# is a cheap, side-effect-free existence/import check; running it ONCE before ever pulling the
# item catches this class at zero fleet cost instead of N wasted cycles.
set -uo pipefail
PY="${OVN_QUEUE_REFILL_PY:-$HOME/overnight-queue/queue_refill.py}"
[ -f "$PY" ] || { echo "  SKIP: $PY not found on this host"; exit 0; }
# already_satisfied()'s VERIFY commands (extracted from real backlog text) say plain "python",
# not "python3" — that only resolves via queue_refill.sh's own PATH export
# ($HOME/aider-venv/bin first), which the real invocation always has but a bare `python3
# queue_refill.py` test call does not. Match production PATH here too, or every python-shaped
# VERIFY spuriously "fails" (python: not found) and gets pulled instead of credited.
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
mkdir -p "$tmp/repo"
cat > "$tmp/repo/existing_module.py" <<'EOF'
def already_here():
    return "yes"
EOF
: > "$tmp/repo/OVERNIGHT_PROGRESS.md"
: > "$tmp/repo/OVERNIGHT_DONE.md"
cat > "$tmp/backlog.md" <<EOF
- [ ] [T1] existing_module.py — Add already_here(). VERIFY: \`python -c "from existing_module import already_here; assert already_here()=='yes'"\`
- [ ] [T1] missing_module.py — Add not_here(). VERIFY: \`python -c "from missing_module import not_here; assert not_here()"\`
- [ ] [T2] existing_module.py — grep check for a real def. VERIFY: \`grep -q "def already_here" existing_module.py\`
- [ ] [T3] backend/foo.py — needs full pytest, unsupported shape. VERIFY: pytest tests/test_foo.py -v
EOF

out="$(python3 "$PY" "$tmp/repo/OVERNIGHT_PROGRESS.md" "$tmp/backlog.md" 4)"
ok "reports 2 pulled and 2 credited" "printf '%s' \"\$out\" | grep -qE 'REFILL=2.*CREDITED=2'"
ok "a python-import item that already passes is credited, not queued" \
   "! grep -q 'missing.*existing_module.py — Add already_here' '$tmp/repo/OVERNIGHT_PROGRESS.md'"
ok "the already-satisfied item is NOT in the active progress file" \
   "! grep -q 'Add already_here' '$tmp/repo/OVERNIGHT_PROGRESS.md'"
ok "the already-satisfied item IS marked done in OVERNIGHT_DONE.md" \
   "grep -q '\[x\].*pre-verified.*Add already_here' '$tmp/repo/OVERNIGHT_DONE.md'"
ok "a grep-shaped VERIFY that already matches is also credited" \
   "grep -q '\[x\].*pre-verified.*grep check for a real def' '$tmp/repo/OVERNIGHT_DONE.md'"
ok "a genuinely-missing item (import fails) still gets pulled normally" \
   "grep -q 'Add not_here' '$tmp/repo/OVERNIGHT_PROGRESS.md'"
ok "an unsupported VERIFY shape (pytest) is never pre-checked, always pulled" \
   "grep -q 'needs full pytest' '$tmp/repo/OVERNIGHT_PROGRESS.md'"
ok "backlog is fully drained (all 4 items accounted for)" "[ ! -s '$tmp/backlog.md' ] || [ \$(grep -c '^- \[' '$tmp/backlog.md') -eq 0 ]"

rm -rf "$tmp"
echo "Queue-refill pre-check: $P passed, $F failed"
[ "$F" -eq 0 ]
