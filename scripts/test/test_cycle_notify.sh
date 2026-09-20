#!/usr/bin/env bash
# Regression test: cycle_notify.sh must correctly bucket per-repo cycle outcomes
# (pass/fail/revert/error/no-op) out of a run_overnight.sh report's "| ongoing-*"
# table rows, write one compact digest_buffer.log line per cycle, extract failing
# test names/counts into failing_tests.log, and skip writing anything when a
# report has no ongoing rows at all (paused/aborted run - "record nothing").
#
# Real script under test lives at ../../cycle_notify.sh (this file: scripts/test/).
set -uo pipefail
SCRIPT="$(cd "$(dirname "$0")/../.." && pwd)/cycle_notify.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
DIR="$tmp/ovn"
mkdir -p "$DIR/logs"
# cycle_notify.sh derives STATE_DIR from its own location ($SCRIPT's dirname),
# so we can't relocate STATE_DIR via env - instead we run the REAL script but
# point $REPORT/$logp fixtures at our sandbox, and use a throwaway copy of the
# script's own directory concept by just letting it write into the real
# overnight-queue/state dir... which we must NOT do (never touch prod state).
# Instead: copy the script itself into our sandbox so its own dirname-derived
# STATE_DIR resolves inside the sandbox.
cp "$SCRIPT" "$tmp/cycle_notify.sh"
STATE="$tmp/state"

# --- fixture: one log with a real pytest-style failure summary -------------
FAILLOG="$DIR/logs/ongoing-gitlark.log"
cat > "$FAILLOG" <<'LOG'
Tokens: 12k sent, 100 received.
collected 10 items
FAILED tests/test_api.py::test_widget_create
FAILED tests/test_api.py::test_widget_delete
2 failed, 8 passed in 3.21s
LOG

REPORT="$DIR/report.md"
cat > "$REPORT" <<EOF2
# Report
| ongoing-billwatch | aider_fix | pushed(tests:pass) | overnight/feature | $DIR/logs/ongoing-billwatch.log | 90s |
| ongoing-gitlark | aider_fix | pushed(tests:FAIL) | overnight/feature | $FAILLOG | 120s |
| ongoing-iptv-apps | aider_fix | reverted(build-gate) | overnight/feature | $DIR/logs/x.log | 30s |
| ongoing-xlite | aider_fix | error(exit=124) | overnight/feature | $DIR/logs/y.log | 600s |
| ongoing-shrike-notify | aider_fix | no-op | overnight/feature | $DIR/logs/z.log | 5s |
EOF2

# --- A: healthy multi-outcome cycle ------------------------------------------
bash "$tmp/cycle_notify.sh" "$REPORT" >/dev/null 2>&1
ok "digest_buffer.log created" "[ -s '$STATE/digest_buffer.log' ]"
LINE="$(tail -1 "$STATE/digest_buffer.log" 2>/dev/null)"
ok "counts np=1 nf=1 nr=1 nn=1 ne=1" "echo \"$LINE\" | grep -qE $'\\t1\\t1\\t1\\t1\\t1\\t'"
ok "PASS bucket has billwatch (ongoing- prefix stripped)" "echo \"$LINE\" | grep -q 'PASS=billwatch'"
ok "FAIL bucket has gitlark" "echo \"$LINE\" | grep -q 'FAIL=gitlark'"
ok "REV bucket has iptv-apps" "echo \"$LINE\" | grep -q 'REV=iptv-apps'"
ok "ERR bucket has xlite" "echo \"$LINE\" | grep -q 'ERR=xlite'"
ok "failing_tests.log records the FAIL cycle" "grep -q 'gitlark' '$STATE/failing_tests.log'"
ok "failing_tests.log captured the '2 failed' count" "grep -q '2 failed' '$STATE/failing_tests.log'"
ok "failing_tests.log captured a test name from the log" "grep -q 'test_widget_create' '$STATE/failing_tests.log'"

# --- B: missing/absent report file -> exit 0, no state dir side effects ------
rm -rf "$STATE"
bash "$tmp/cycle_notify.sh" "$tmp/does-not-exist.md" >/dev/null 2>&1
rc=$?
ok "missing report file: exits 0" "[ $rc -eq 0 ]"
ok "missing report file: no state dir created" "[ ! -d '$STATE' ]"

# --- C: report present but with NO ongoing rows (paused/aborted run) --------
# Documented behaviour (script header comment + line: 'nothing ran (paused /
# abort) -> record nothing'): digest_buffer.log must NOT gain an entry.
EMPTY_REPORT="$DIR/empty.md"
printf '# Report\nQueue paused this cycle.\n' > "$EMPTY_REPORT"
rm -rf "$STATE"; mkdir -p "$STATE"  # simulate STATE dir already existing from prior cycles
: > "$STATE/digest_buffer.log"
bash "$tmp/cycle_notify.sh" "$EMPTY_REPORT" >/dev/null 2>&1
ok "no-ongoing-rows report: digest_buffer.log stays empty" "[ ! -s '$STATE/digest_buffer.log' ]"

# --- D: comma-joined id lists for multiple ids in the same bucket -----------
rm -rf "$STATE"
REPORT2="$DIR/report2.md"
cat > "$REPORT2" <<EOF3
# Report
| ongoing-billwatch | aider_fix | pushed(tests:pass) | overnight/feature | $DIR/logs/a.log | 10s |
| ongoing-gitlark | aider_fix | pushed(tests:pass) | overnight/feature | $DIR/logs/b.log | 10s |
EOF3
bash "$tmp/cycle_notify.sh" "$REPORT2" >/dev/null 2>&1
LINE2="$(tail -1 "$STATE/digest_buffer.log" 2>/dev/null)"
ok "two passes in one cycle are comma-joined in PASS=" "echo \"$LINE2\" | grep -q 'PASS=billwatch,gitlark'"

# --- E: FIXED BUG regression guard (2026-09-10, updated 2026-09-20) — a cycle whose rows
# are ONLY qualified no-op forms (no-op(BLOCKED) etc) or unrelated real outcome strings
# (disabled, skip(exhausted)) must still reach digest_buffer.log, not be silently dropped.
# The original case statement matched only the bare literal `no-op)`, so real outcome
# strings seen live in reports/*.md (no-op(BLOCKED), no-op(stage-unverified),
# no-op(reverted-red), disabled, skip(exhausted)) fell through every bucket uncounted -
# if a WHOLE cycle consisted only of these, the sum stayed 0 and line 55's early-exit
# dropped the entire cycle even though real activity happened.
#
# 2026-09-20 UPDATE: disabled/skip(exhausted) no longer land in the SAME bucket as a real
# no-op attempt (nn) - they mean no attempt happened at all, so they're now their own IDLE
# bucket (see cycle_notify.sh's 2026-09-20 fix comment: lumping them into nn was the main
# cause of a real digest showing "$NN no-op" far higher than what the fleet actually
# attempted). This test now asserts the split, not the old lumped nn=3. ---
rm -rf "$STATE"
REPORT3="$DIR/report3.md"
cat > "$REPORT3" <<EOF4
# Report
| ongoing-task-automation-agent | aider_fix | disabled | overnight/feature | $DIR/logs/c.log | 5s |
| ongoing-shrike-notify | aider_fix | skip(exhausted) | overnight/feature | $DIR/logs/d.log | 3s |
| ongoing-shrike-monitor | aider_fix | no-op(BLOCKED) | overnight/feature | $DIR/logs/e.log | 4s |
EOF4
bash "$tmp/cycle_notify.sh" "$REPORT3" >/dev/null 2>&1
ok "an all-disabled/skip/qualified-no-op cycle still writes a digest line (was silently dropped before the fix)" \
   "[ -s '$STATE/digest_buffer.log' ]"
LINE3="$(tail -1 "$STATE/digest_buffer.log" 2>/dev/null)"
ok "disabled + skip(exhausted) are counted as IDLE, not real no-op work (2026-09-20 fix)" \
   "echo \"\$LINE3\" | grep -qE 'IDLE=2\$'"
ok "no-op(BLOCKED) is still counted as a real no-op (nn=1, not 3)" \
   "echo \"\$LINE3\" | grep -qE \$'\\t0\\t0\\t0\\t1\\t0\\t'"

# --- F: 2026-09-20 FIX regression guard — a bare "pushed"/"pushed(after-rebase)" status
# (VERIFY_RESULT was neither pass nor fail, or a push-rejected-then-rebased retry) is a
# REAL landed commit and must count as a pass, not fall through to the no-op catch-all.
# "held(<repo>)" (human hold) and "skipped(paused)" (mid-run pause) are, like
# disabled/skip(exhausted) above, idle - no attempt happened - not a no-op attempt.
rm -rf "$STATE"
REPORT4="$DIR/report4.md"
cat > "$REPORT4" <<EOF5
# Report
| ongoing-billwatch | aider_fix | pushed | overnight/feature | $DIR/logs/f.log | 5s |
| ongoing-gitlark | aider_fix | pushed(after-rebase) | overnight/feature | $DIR/logs/g.log | 5s |
| ongoing-iptv-apps | aider_fix | held(iptv-apps) | overnight/feature | $DIR/logs/h.log | 1s |
| ongoing-xlite | aider_fix | skipped(paused) | overnight/feature | $DIR/logs/i.log | 1s |
EOF5
bash "$tmp/cycle_notify.sh" "$REPORT4" >/dev/null 2>&1
LINE4="$(tail -1 "$STATE/digest_buffer.log" 2>/dev/null)"
ok "bare 'pushed' and 'pushed(after-rebase)' both count as landed (np=2), not no-op" \
   "echo \"\$LINE4\" | grep -qE \$'\\t2\\t0\\t0\\t0\\t0\\t'"
ok "'pushed' landed items are still recorded in the PASS= bucket" \
   "echo \"\$LINE4\" | grep -q 'PASS=billwatch,gitlark'"
ok "held(<repo>) + skipped(paused) are counted as IDLE (2 more), not no-op" \
   "echo \"\$LINE4\" | grep -qE 'IDLE=2\$'"

rm -rf "$tmp"
echo "cycle_notify: $P passed, $F failed"
[ "$F" -eq 0 ]
