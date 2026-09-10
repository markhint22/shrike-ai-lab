#!/usr/bin/env bash
# Tests for the bash helpers: ovn_credit_already_satisfied.sh, ovn_item_guard.sh
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS:-$HOME/overnight-queue/scripts}"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# ---- ovn_credit_already_satisfied.sh ----
d=$(mktemp -d); ( cd "$d"
  printf '# P\n\n## Next Steps\n- [ ] [HIGH] `app/foo.py` — add Query bounds. One file.\n- [ ] [MED] `app/bar.py` — add aria-label. One file.\n' > OVERNIGHT_PROGRESS.md
  printf 'app/foo.py\nLooking at it, Query is already imported and both params already use Query. This item is already done.\n' > tlog
  bash "$SCRIPTS/ovn_credit_already_satisfied.sh" tlog OVERNIGHT_PROGRESS.md >/dev/null 2>&1
)
ok "credit: checks off already-done foo.py" "grep -qE '^- \[x\].*app/foo.py' $d/OVERNIGHT_PROGRESS.md"
ok "credit: leaves bar.py unchecked"       "grep -qE '^- \[ \].*app/bar.py' $d/OVERNIGHT_PROGRESS.md"
( cd "$d"
  printf '## Next Steps\n- [ ] [HIGH] `app/foo.py` — add Query bounds. One file.\n' > OVERNIGHT_PROGRESS.md
  printf 'app/foo.py\nThis needs changing, it is not done yet.\n' > tlog2
  bash "$SCRIPTS/ovn_credit_already_satisfied.sh" tlog2 OVERNIGHT_PROGRESS.md >/dev/null 2>&1
)
ok "credit: does NOT check off a not-done item" "grep -qE '^- \[ \].*app/foo.py' $d/OVERNIGHT_PROGRESS.md"
rm -rf "$d"

# ---- ovn_item_guard.sh ----
d=$(mktemp -d); ( cd "$d"; git init -q; git config user.email t@t; git config user.name t
  mkdir -p state/failures
  printf '## Next Steps\n- [ ] [HIGH] `app/x.py` — do a thing. One file.\n' > OVERNIGHT_PROGRESS.md
  git add -A; git commit -qm init
  echo 2 > state/failures/ongoing-test.count   # task-valve at 2 (near disable)
  for i in 1 2 3; do bash "$SCRIPTS/ovn_item_guard.sh" "$d" "reverted" "$d/state" "ongoing-test" >/dev/null 2>&1; done
)
ok "item-guard: parks the item after 3 fails"        "grep -q 'AUTO-SKIP' $d/OVERNIGHT_PROGRESS.md"
ok "item-guard: resets task-valve counter on park"   "[ ! -f $d/state/failures/ongoing-test.count ]"
( cd "$d"
  printf '## Next Steps\n- [ ] [HIGH] `app/y.py` — do a thing. One file.\n' > OVERNIGHT_PROGRESS.md
  bash "$SCRIPTS/ovn_item_guard.sh" "$d" "pushed(tests:pass)" "$d/state" "ongoing-test" >/dev/null 2>&1
)
ok "item-guard: no-op/pass does not park"             "! grep -q 'HUMAN-ONLY' $d/OVERNIGHT_PROGRESS.md"
rm -rf "$d"

# ---- ovn_item_guard.sh: no-op streak (2026-08-31 regression) ----
# The guard used to `exit 0` on every no-op, so an already-done / mis-targeted /
# too-hard item that cleanly no-ops every cycle sat at the top of the list
# forever, blocking everything below it. It must now park such an item.
d=$(mktemp -d); ( cd "$d"; git init -q; git config user.email t@t; git config user.name t
  mkdir -p state/failures
  printf '## Next Steps\n- [ ] [HIGH] `app/z.py` — already done / mis-targeted. One file.\n' > OVERNIGHT_PROGRESS.md
  git add -A; git commit -qm init
  for i in 1 2 3; do bash "$SCRIPTS/ovn_item_guard.sh" "$d" "no-op(ALREADY-DONE)" "$d/state" "ongoing-noop" >/dev/null 2>&1; done
)
ok "item-guard: 3 no-ops do NOT park (cap 4)"          "! grep -q 'AUTO-SKIP' $d/OVERNIGHT_PROGRESS.md"
bash "$SCRIPTS/ovn_item_guard.sh" "$d" "no-op(ALREADY-DONE)" "$d/state" "ongoing-noop" >/dev/null 2>&1
ok "item-guard: 4th consecutive no-op parks AUTO-SKIP" "grep -q 'AUTO-SKIP after 4 no-op' $d/OVERNIGHT_PROGRESS.md"
ok "item-guard: no-op park is NOT tagged HUMAN-ONLY"   "! grep -q 'HUMAN-ONLY' $d/OVERNIGHT_PROGRESS.md"
rm -rf "$d"

# A real landing between no-ops resets the streak, so a merely-flaky item is not parked.
d=$(mktemp -d); ( cd "$d"; git init -q; git config user.email t@t; git config user.name t
  mkdir -p state/failures
  printf '## Next Steps\n- [ ] [HIGH] `app/w.py` — occasionally no-ops. One file.\n' > OVERNIGHT_PROGRESS.md
  git add -A; git commit -qm init
  for i in 1 2 3; do bash "$SCRIPTS/ovn_item_guard.sh" "$d" "no-op(BLOCKED)" "$d/state" "ongoing-reset" >/dev/null 2>&1; done
  bash "$SCRIPTS/ovn_item_guard.sh" "$d" "pushed(tests:pass)" "$d/state" "ongoing-reset" >/dev/null 2>&1  # landing clears the streak
  bash "$SCRIPTS/ovn_item_guard.sh" "$d" "no-op(BLOCKED)" "$d/state" "ongoing-reset" >/dev/null 2>&1      # back to 1, not 4
)
ok "item-guard: a landing resets the no-op streak"     "! grep -q 'AUTO-SKIP' $d/OVERNIGHT_PROGRESS.md"
rm -rf "$d"

echo "Bash helpers: $P passed, $F failed"
[ "$F" -eq 0 ]
