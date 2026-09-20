#!/usr/bin/env bash
# Tests for scripts/ovn_noop_detail.py (2026-09-20) — grouped/deduped "repeat no-op/reverted"
# lines for the ntfy digests, added after a full-day audit found the digest's raw no-op/
# reverted counts were per-CYCLE outcome records, not per-item: a handful of stale backlog
# items re-picked and re-failed every cycle inflated the apparent number of distinct problems.
# Uses TASK_STATS to point at a fixture file so it never touches production data.
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS_DIR:-$HOME/overnight-queue/scripts}"
SCRIPT="$SCRIPTS/ovn_noop_detail.py"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

if [ ! -f "$SCRIPT" ]; then
  echo "  SKIP: $SCRIPT not found on this host"
  echo "ovn_noop_detail.py: 0 passed, 0 failed"
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
TSF="$tmp/task_stats.log"
now="$(date +%s)"
run(){ TASK_STATS="$TSF" python3 "$SCRIPT" "$@"; }

# --- 1: missing file prints nothing ---
out0="$(TASK_STATS="$tmp/nope.log" run 3 2>&1)"
ok "missing task_stats.log: prints nothing" "[ -z \"\$out0\" ]"

# --- 2: below --min-repeat (default 3) prints nothing ---
: > "$TSF"
for i in 1 2; do
  echo -e "$((now-i))\tbillwatch\tnoop:flail\t{kotlin·other·T2·unverifiable}\tBillsRepositoryTest.kt" >> "$TSF"
done
out1="$(run 3 2>&1)"
ok "2 repeats (below default min-repeat 3) prints nothing" "[ -z \"\$out1\" ]"

# --- 3: a genuine repeat (still unresolved) is grouped + counted, header shown ---
: > "$TSF"
for i in 1 2 3 4 5; do
  echo -e "$((now-i))\tbillwatch\tnoop:flail\t{kotlin·other·T2·unverifiable}\tBillsRepositoryTest.kt" >> "$TSF"
done
out2="$(run 3 2>&1)"
ok "shows the header" "printf '%s' \"\$out2\" | grep -q 'Repeat no-op/reverted'"
ok "shows repo (tier): file — failed Nx" "printf '%s' \"\$out2\" | grep -q 'billwatch (T2): BillsRepositoryTest.kt — failed 5x'"
ok "still-unresolved is worded as such" "printf '%s' \"\$out2\" | grep -q 'still unresolved'"
ok "does NOT claim self-resolved when it never landed" "! printf '%s' \"\$out2\" | grep -q 'self-resolved'"

# --- 4: same key but the LAST row in the window is a pass -> self-resolved, not stuck ---
: > "$TSF"
for i in 5 4 3 2; do
  echo -e "$((now-i))\tbillwatch\trevert\t{kotlin·bugfix·T2·unverifiable}\tBillsRepositoryTest.kt" >> "$TSF"
done
echo -e "$((now-1))\tbillwatch\tpass\t{kotlin·bugfix·T2·unverifiable}\tBillsRepositoryTest.kt" >> "$TSF"
out3="$(run 3 2>&1)"
ok "eventually-landed item is labeled self-resolved" "printf '%s' \"\$out3\" | grep -q 'then landed, self-resolved'"
ok "eventually-landed item is NOT labeled still unresolved" "! printf '%s' \"\$out3\" | grep -q 'still unresolved'"
ok "the landing itself is not counted toward the failed-Nx tally" "printf '%s' \"\$out3\" | grep -q 'failed 4x'"

# --- 5: tier is part of the grouping key — same repo+file at a DIFFERENT tier is a
# separate signature, not merged into one inflated count (avoid over-grouping unrelated work)
: > "$TSF"
for i in 1 2 3; do
  echo -e "$((now-i))\tbillwatch\tnoop:flail\t{kotlin·other·T1·unverifiable}\tShared.kt" >> "$TSF"
done
for i in 4 5 6; do
  echo -e "$((now-i))\tbillwatch\tnoop:flail\t{kotlin·other·T3·unverifiable}\tShared.kt" >> "$TSF"
done
out4="$(run 3 2>&1)"
n4="$(printf '%s' "$out4" | grep -c 'Shared.kt')"
ok "two different tiers on the same file produce TWO separate grouped lines" "[ \"$n4\" -eq 2 ]"
ok "T1 line shows its own count (3x), not the combined 6x" "printf '%s' \"\$out4\" | grep -q 'billwatch (T1): Shared.kt — failed 3x'"
ok "T3 line shows its own count (3x), not the combined 6x" "printf '%s' \"\$out4\" | grep -q 'billwatch (T3): Shared.kt — failed 3x'"

# --- 6: 'pass', 'error' and 'skip' outcomes never count toward the repeat tally ---
: > "$TSF"
for i in 1 2 3; do
  echo -e "$((now-i))\tbillwatch\tpass\t{py·other·T2·test-covered}\tclean.py" >> "$TSF"
done
for i in 4 5 6; do
  echo -e "$((now-i))\tbillwatch\terror\t{py·other·T2·test-covered}\tflaky-net.py" >> "$TSF"
done
for i in 7 8 9; do
  echo -e "$((now-i))\tbillwatch\tskip\t{py·other·T2·test-covered}\tidle.py" >> "$TSF"
done
out5="$(run 3 2>&1)"
ok "an item that only ever passed is never shown as a repeat" "! printf '%s' \"\$out5\" | grep -q 'clean.py'"
ok "repeated errors (network/timeout) are excluded from this section" "! printf '%s' \"\$out5\" | grep -q 'flaky-net.py'"
ok "repeated idle/skip rows are excluded from this section" "! printf '%s' \"\$out5\" | grep -q 'idle.py'"

# --- 7: rows outside the window are excluded ---
: > "$TSF"
old_ts=$(( now - 30 * 3600 ))
for i in 0 1 2 3; do
  echo -e "$((old_ts-i))\tbillwatch\trevert\t{kotlin·other·T2·unverifiable}\told-item.kt" >> "$TSF"
done
out6="$(run 3 2>&1)"
ok "rows older than the window are excluded" "[ -z \"\$out6\" ]"
out6b="$(run 48 2>&1)"
ok "the same rows appear once the window widens past them" "printf '%s' \"\$out6b\" | grep -q 'old-item.kt'"

# --- 8: --min-repeat and --max-total are respected ---
: > "$TSF"
for i in 1 2; do
  echo -e "$((now-i))\tbillwatch\trevert\t{kotlin·other·T2·unverifiable}\tlow-repeat.kt" >> "$TSF"
done
out7="$(run 3 --min-repeat 2 2>&1)"
ok "--min-repeat 2 surfaces a 2x repeat the default (3) would hide" "printf '%s' \"\$out7\" | grep -q 'low-repeat.kt'"

: > "$TSF"
for r in repo-a repo-b repo-c; do
  for i in 1 2 3; do
    echo -e "$((now-i))\t$r\trevert\t{kotlin·other·T2·unverifiable}\tf.kt" >> "$TSF"
  done
done
out8="$(run 3 --max-total 2 2>&1)"
n8="$(printf '%s' "$out8" | grep -c 'f.kt')"
ok "--max-total caps the overall grouped-line count" "[ \"$n8\" -eq 2 ]"

# --- 9: sorted worst-first (highest repeat count first) ---
: > "$TSF"
for i in 1 2 3; do
  echo -e "$((now-i))\tbillwatch\trevert\t{kotlin·other·T2·unverifiable}\tsmall.kt" >> "$TSF"
done
for i in 1 2 3 4 5 6 7; do
  echo -e "$((now-i))\tbillwatch\trevert\t{kotlin·other·T2·unverifiable}\tbig.kt" >> "$TSF"
done
out9="$(run 3 2>&1)"
first_line="$(printf '%s' "$out9" | sed -n '2p')"
ok "the biggest repeat offender is listed first" "printf '%s' \"\$first_line\" | grep -q 'big.kt'"

# --- 10: a malformed/missing tag falls back to '?' tier instead of crashing ---
: > "$TSF"
for i in 1 2 3; do
  echo -e "$((now-i))\tbillwatch\trevert\tnotatag\tuntagged.kt" >> "$TSF"
done
out10="$(run 3 2>&1)"
ok "malformed tag doesn't crash, falls back to '?' tier" "printf '%s' \"\$out10\" | grep -q 'billwatch (?): untagged.kt'"

echo "ovn_noop_detail.py: $P passed, $F failed"
[ "$F" -eq 0 ]
