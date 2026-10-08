#!/usr/bin/env bash
# Tests for the bash helpers: ovn_credit_already_satisfied.sh, ovn_item_guard.sh
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS:-$HOME/overnight-queue/scripts}"
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
# shellcheck source=scripts/lib_item_select.sh
[ -f "$SCRIPTS/lib_item_select.sh" ] && . "$SCRIPTS/lib_item_select.sh"

# ---- ovn_credit_already_satisfied.sh ----
d=$(mktemp -d); ( cd "$d"
  mkdir -p app; touch app/foo.py app/bar.py   # 2026-09-30 target-path gate: an 'already satisfied' credit needs its target to exist
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
# 2026-09-29: a landing is identified via an "item-hash <md5>" marker in $task_log (written
# by run_overnight.sh at the moment it checks an item off — see that file's 2026-09-29
# comment at the marker-emission site), not a blind clear-everything-for-this-id, because by
# the time this guard runs on a real landing, OVERNIGHT_PROGRESS.md's checkbox for the landed
# item is already flipped and a fresh re-read can no longer identify it (see
# ovn_item_guard.sh's own header comment). Build that marker for THIS item explicitly so the
# "landing" call below actually lands the SAME item the no-ops were accumulating against.
w_line='- [ ] [HIGH] `app/w.py` — occasionally no-ops. One file.'
d=$(mktemp -d); ( cd "$d"; git init -q; git config user.email t@t; git config user.name t
  mkdir -p state/failures
  printf '## Next Steps\n%s\n' "$w_line" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -qm init
  for i in 1 2 3; do bash "$SCRIPTS/ovn_item_guard.sh" "$d" "no-op(BLOCKED)" "$d/state" "ongoing-reset" >/dev/null 2>&1; done
  if command -v ovn_item_hash >/dev/null 2>&1; then
    printf -- '--- auto-credit: item-hash %s ---\n' "$(ovn_item_hash "$w_line")" > landed.log
  else
    : > landed.log
  fi
  bash "$SCRIPTS/ovn_item_guard.sh" "$d" "pushed(tests:pass)" "$d/state" "ongoing-reset" landed.log >/dev/null 2>&1  # landing clears the streak
  bash "$SCRIPTS/ovn_item_guard.sh" "$d" "no-op(BLOCKED)" "$d/state" "ongoing-reset" >/dev/null 2>&1      # back to 1, not 4
)
ok "item-guard: a landing resets the no-op streak"     "! grep -q 'AUTO-SKIP' $d/OVERNIGHT_PROGRESS.md"
rm -rf "$d"

echo "Bash helpers: $P passed, $F failed"
[ "$F" -eq 0 ]
