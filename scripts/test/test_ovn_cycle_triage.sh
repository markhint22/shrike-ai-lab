#!/usr/bin/env bash
# Regression test: scripts/ovn_cycle_triage.sh — the per-cycle "why did this cycle end the way it
# did" line-writer that feeds state/cycle_triage.log for data-driven tuning.
#
# Real behavior this locks down:
#  - the healthy path: item selection, tries counting, flag detection, verdict/plan/tests parsing,
#    and the id/status fields all land correctly in the one appended line.
#  - flag detection (TIMEOUT/CTX-OVERFLOW) combines correctly from a single tasklog.
#  - FIXED BUG (2026-09-10): the item-selection pipeline used to do
#    `grep -m1 '^- \[ \]' | grep -v 'HUMAN-ONLY|AUTO-SKIP'` (line 13), taking the FIRST bullet
#    BEFORE applying the exclusion filter, so when the very first Next Steps bullet was a parked
#    item, the whole pipeline yielded nothing (item=<none>) instead of falling through to the real
#    actionable item beneath it. Fixed by filtering first, then taking -m1. Test D locks in the
#    correct behavior so this can't silently regress.
#  - it must be a safe no-op (no log line, no crash) when required args are missing.
#  - it must still write a (mostly empty) line rather than crash when repo/tasklog files don't exist.
#
# Note: captured log lines are written to files and grepped from there (not interpolated directly
# into an eval'd pattern string) because the log format itself contains embedded double-quotes
# (item="...", plan="...") which would break eval's re-parsing if substituted inline.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="${OVN_CYCLE_TRIAGE:-$HERE/../ovn_cycle_triage.sh}"
[ -f "$T" ] || T="$HERE/../../scripts/ovn_cycle_triage.sh"
[ -f "$T" ] || { echo "  SKIP: ovn_cycle_triage.sh not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- A: normal/healthy path — first bullet is real+actionable; tries/flags/verdict/plan/tests/id/status all captured ---
repo="$tmp/repoA"; mkdir -p "$repo"
cat > "$repo/OVERNIGHT_PROGRESS.md" <<'PROG'
## Next Steps
- [ ] [T2] `scripts/foo.py` — add a *pure* validation helper. VERIFY: pytest -k foo
- [ ] HUMAN-ONLY rotate the Stripe live key
- [ ] AUTO-SKIP after 4 no-op cycles: scripts/dead.py — old parked item
PROG
tasklog="$tmp/taskA.log"
cat > "$tasklog" <<'LOG'
2026-09-10 01:00:00 implement attempt 1
2026-09-10 01:02:00 implement attempt 2
VERDICT: PROCEED
PLAN: add validation helper FILES: scripts/foo.py
Tests 3 passed, 0 failed
LOG
state="$tmp/stateA"; mkdir -p "$state"
bash "$T" "$repo" "pushed(tests:pass)" "$tasklog" "$state" itemA
cp "$state/cycle_triage.log" "$tmp/lineA.txt" 2>/dev/null || : > "$tmp/lineA.txt"
ok "writes exactly one line" "[ \$(wc -l < '$state/cycle_triage.log') -eq 1 ]"
ok "item= picks the real actionable first bullet" "grep -qF 'item=\"[T2] scripts/foo.py' '$tmp/lineA.txt'"
ok "item= does NOT contain the HUMAN-ONLY bullet" "! grep -qi 'Stripe' '$tmp/lineA.txt'"
ok "item= does NOT contain the AUTO-SKIP bullet" "! grep -qF 'scripts/dead.py' '$tmp/lineA.txt'"
ok "tries= counts the two implement-attempt lines" "grep -qF 'tries=2' '$tmp/lineA.txt'"
ok "flags default to clean when no failure markers present" "grep -qF 'clean' '$tmp/lineA.txt'"
ok "verdict= picked up from the tasklog" "grep -qF 'verdict=PROCEED' '$tmp/lineA.txt'"
ok "id field is the passed-in id" "grep -qF '| itemA ' '$tmp/lineA.txt'"
ok "status field is the passed-in status" "grep -qF 'pushed(tests:pass)' '$tmp/lineA.txt'"

# --- B: flag detection combines multiple signals from one tasklog ---
tasklog2="$tmp/taskB.log"
cat > "$tasklog2" <<'LOG'
implement attempt 1
run exit=124 (timed out)
ContextWindowExceeded: too much context
LOG
state2="$tmp/stateB"; mkdir -p "$state2"
bash "$T" "$repo" "no-op(timeout)" "$tasklog2" "$state2" itemB
cp "$state2/cycle_triage.log" "$tmp/lineB.txt"
ok "TIMEOUT flag set on exit=124" "grep -qF 'TIMEOUT' '$tmp/lineB.txt'"
ok "CTX-OVERFLOW flag set on ContextWindowExceeded" "grep -qF 'CTX-OVERFLOW' '$tmp/lineB.txt'"
ok "PARSE-ERR flag NOT set (no such marker present)" "! grep -qF 'PARSE-ERR' '$tmp/lineB.txt'"

# --- C: missing required args (state or tasklog empty) is a safe no-op, no log written, no crash ---
rc=0
bash "$T" "$repo" "pushed" "" "$tmp/stateC" itemC || rc=$?
ok "missing tasklog arg: exits 0" "[ '$rc' -eq 0 ]"
ok "missing tasklog arg: no log file created" "[ ! -f '$tmp/stateC/cycle_triage.log' ]"

rc=0
bash "$T" "$repo" "pushed" "$tasklog" "" itemD || rc=$?
ok "missing state-dir arg: exits 0" "[ '$rc' -eq 0 ]"

# --- D: FIXED BUG regression guard — a parked item AS THE FIRST bullet must NOT make item
#     selection go empty; it must fall through to the real actionable item beneath it ---
repoD="$tmp/repoD"; mkdir -p "$repoD"
cat > "$repoD/OVERNIGHT_PROGRESS.md" <<'PROG'
## Next Steps
- [ ] HUMAN-ONLY rotate the Stripe live key
- [ ] [T2] scripts/real.py — a real actionable item that exists further down. VERIFY: pytest
PROG
tasklog4="$tmp/taskD.log"; echo "implement attempt 1" > "$tasklog4"
state4b="$tmp/stateD2"; mkdir -p "$state4b"
bash "$T" "$repoD" "pushed" "$tasklog4" "$state4b" itemDbug
cp "$state4b/cycle_triage.log" "$tmp/lineD.txt"
ok "parked-first-bullet falls through to the real item beneath it (was item=<none> before the fix)" \
   "grep -qF 'item=\"[T2] scripts/real.py' '$tmp/lineD.txt'"
ok "parked-first-bullet's own text never leaks into item=" \
   "! grep -qi 'Stripe' '$tmp/lineD.txt'"

# --- E: missing tasklog FILE (state+tasklog args non-empty strings, but file doesn't exist) and
#     missing OVERNIGHT_PROGRESS.md — must still write a (mostly-empty) line, never crash ---
state5="$tmp/stateE"; mkdir -p "$state5"
norepo="$tmp/no-such-repo"
rc=0
bash "$T" "$norepo" "pushed" "$tmp/no-such-tasklog.log" "$state5" itemE || rc=$?
ok "nonexistent tasklog file + repo: still exits 0" "[ '$rc' -eq 0 ]"
ok "nonexistent tasklog file + repo: still writes a line" "[ -f '$state5/cycle_triage.log' ]"
cp "$state5/cycle_triage.log" "$tmp/lineE.txt" 2>/dev/null || : > "$tmp/lineE.txt"
ok "no verdict found -> verdict=? placeholder" "grep -qF 'verdict=?' '$tmp/lineE.txt'"
ok "no item found -> item=<none> placeholder" "grep -qF 'item=\"<none>\"' '$tmp/lineE.txt'"
ok "no tries counted -> tries=0" "grep -qF 'tries=0' '$tmp/lineE.txt'"

echo "ovn_cycle_triage: $P passed, $F failed"
[ "$F" -eq 0 ]
