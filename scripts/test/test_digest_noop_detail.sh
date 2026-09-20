#!/usr/bin/env bash
# Regression test: digest_notify.sh's 3h digest surfaces a grouped/deduped "repeat no-op/
# reverted" section (2026-09-20, full-day audit finding) — the raw ➖/↩️ counts are per-CYCLE
# outcome tallies, so a single stuck item re-picked and re-failed every cycle looked like many
# distinct problems. Mirrors digest_notify.sh + its real script dependencies into a fixture
# dir so it never touches production data or the real network.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
D="$OQ/digest_notify.sh"
[ -f "$D" ] || { echo "  SKIP: $D not found on this host"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/state" "$tmp/scripts" "$tmp/bin"
cp "$D" "$tmp/digest_notify.sh"
for f in ovn_landed_detail.py ovn_noop_detail.py ovn_tier_stats.py ovn_stats.py ovn_planning_stats.py ovn_feature_groups.py; do
  [ -f "$OQ/scripts/$f" ] && cp "$OQ/scripts/$f" "$tmp/scripts/$f"
done
echo "faketopic" > "$tmp/state/ntfy_topic"
echo '{}' > "$tmp/tasks.json"

now="$(date +%s)"
{
  for i in 1 2 3 4 5; do
    printf '%s\tbillwatch\tnoop:flail\t{kotlin.other.T2.unverifiable}\tStuck.kt\n' "$((now-i))"
  done
} > "$tmp/state/task_stats.log"
printf '%s\t0\t0\t0\t5\t0\tPASS=\tFAIL=\tREV=\tERR=\tIDLE=0\n' "$now" > "$tmp/state/digest_buffer.log"

BODYLOG="$tmp/body.log"
cat > "$tmp/bin/curl" <<CURLEOF
#!/usr/bin/env bash
prev=""
for a in "\$@"; do
  if [ "\$prev" = "-d" ]; then printf '%s' "\$a" > "$BODYLOG"; fi
  prev="\$a"
done
exit 0
CURLEOF
chmod +x "$tmp/bin/curl"

( cd "$tmp" && PATH="$tmp/bin:$PATH" HOME="$tmp" bash "$tmp/digest_notify.sh" >/dev/null 2>&1 )

ok "digest body includes the repeat no-op/reverted section" "grep -q 'Repeat no-op/reverted' '$BODYLOG'"
ok "digest body groups the 5 repeat rows into ONE counted line" "grep -q 'billwatch (T2): Stuck.kt — failed 5x' '$BODYLOG'"
ok "digest body does NOT show 5 separate raw lines for the same item" "[ \"\$(grep -c 'Stuck.kt' '$BODYLOG')\" -eq 1 ]"

# a single/double no-op (below default min-repeat) does not spam the section
: > "$tmp/state/task_stats.log"
for i in 1 2; do
  printf '%s\tbillwatch\tnoop:flail\t{kotlin.other.T2.unverifiable}\tMinor.kt\n' "$((now-i))" >> "$tmp/state/task_stats.log"
done
printf '%s\t0\t0\t0\t2\t0\tPASS=\tFAIL=\tREV=\tERR=\tIDLE=0\n' "$now" > "$tmp/state/digest_buffer.log"
( cd "$tmp" && PATH="$tmp/bin:$PATH" HOME="$tmp" bash "$tmp/digest_notify.sh" >/dev/null 2>&1 )
ok "a below-threshold repeat (2x) does not trigger the repeat section" "! grep -q 'Repeat no-op/reverted' '$BODYLOG'"

echo "Digest no-op-detail section: $P passed, $F failed"
[ "$F" -eq 0 ]
