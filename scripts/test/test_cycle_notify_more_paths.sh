#!/usr/bin/env bash
# Extra coverage for the REAL cycle_notify.sh: unknown-status catch-all, per-outcome classification (_oc) for ALREADY-DONE /
# BLOCKED / no-op+revert / plain no-op / unknown, and the cycle_summary.log join (class=/top_item= extraction, cursor file
# written, stale line NOT reattributed on the next cycle, fresh line IS) into task_stats.log.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S=""; for c in "$HERE/../../cycle_notify.sh" "$HERE/../cycle_notify.sh"; do [ -f "$c" ] && { S="$c"; break; }; done
[ -n "$S" ] || { echo "  SKIP: cycle_notify.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
cp "$S" "$T/cycle_notify.sh"; ST="$T/state"; mkdir -p "$ST"
run(){ ( cd "$T" && bash "$T/cycle_notify.sh" "$1" >/dev/null 2>&1 ); }
row(){ echo "| ongoing-$1 | aider_fix | $2 | overnight/feature | $T/$1.log | 5s |"; }

# cycle_summary.log: lines 1..5, one per id
cat > "$ST/cycle_summary.log" <<'EOF2'
2026-09-30 ongoing-alpha class={py.fix.s.t} top_item=a.py
2026-09-30 ongoing-beta class={py.fix.s.t} top_item=b.py
2026-09-30 ongoing-gamma class={kt.fix.m.v} top_item=c.kt
2026-09-30 ongoing-delta class={ts.fix.m.v} top_item=d.ts
2026-09-30 ongoing-eps class={sh.fix.s.t} top_item=e.sh
2026-09-30 ongoing-zeta class={sh.fix.s.t}
EOF2
{ row alpha "no-op(ALREADY-DONE)"; row beta "no-op(BLOCKED)"; row gamma "no-op(reverted-red)"; row delta "no-op(flail)"; row eps "weird-status"; row zeta "pushed(tests:pass)"; } > "$T/r1.md"
run "$T/r1.md"
ts="$ST/task_stats.log"
cls(){ awk -F'\t' -v id="$1" '$2==id{print $3}' "$ts" | tail -1; }
ok "ALREADY-DONE -> noop:done" "$([ "$(cls alpha)" = noop:done ] && echo 1 || echo 0)"
ok "BLOCKED -> noop:blocked" "$([ "$(cls beta)" = noop:blocked ] && echo 1 || echo 0)"
ok "no-op + revert -> noop:gate" "$([ "$(cls gamma)" = noop:gate ] && echo 1 || echo 0)"
ok "plain no-op -> noop:flail" "$([ "$(cls delta)" = noop:flail ] && echo 1 || echo 0)"
ok "unknown status -> skip classification" "$([ "$(cls eps)" = skip ] && echo 1 || echo 0)"
ok "tests:pass -> pass and missing top_item recorded as '?'" "$([ "$(cls zeta)" = pass ] && awk -F'\t' '$2=="zeta"{print $5}' "$ts" | grep -qx '?' && echo 1 || echo 0)"
ok "class= and top_item= extracted into task_stats.log" "$(awk -F'\t' '$2=="alpha"{print $4" "$5}' "$ts" | grep -qx '{py.fix.s.t} a.py' && echo 1 || echo 0)"
ok "cursor file written with the consumed line number" "$([ "$(cat "$ST/.cycle_notify_cursor__alpha")" = 1 ] && [ "$(cat "$ST/.cycle_notify_cursor__gamma")" = 3 ] && echo 1 || echo 0)"
ok "unknown status counted as a no-op in the digest buffer (4 no-op* + 1 catch-all = 5)" "$(tail -1 "$ST/digest_buffer.log" | awk -F'\t' '{print $5}' | grep -qx 5 && echo 1 || echo 0)"
n1="$(wc -l < "$ts" | tr -d ' ')"
# second cycle: same ids, no NEWER cycle_summary lines -> stale, not reattributed
run "$T/r1.md"
ok "stale cycle_summary lines are not reattributed (task_stats.log unchanged)" "$([ "$(wc -l < "$ts" | tr -d ' ')" = "$n1" ] && echo 1 || echo 0)"
# fresh line for alpha -> picked up again
echo "2026-09-30 ongoing-alpha class={py.new.s.t} top_item=a2.py" >> "$ST/cycle_summary.log"
row alpha "pushed(tests:pass)" > "$T/r2.md"; run "$T/r2.md"
ok "a newer cycle_summary line IS consumed" "$(awk -F'\t' '$2=="alpha"{print $4" "$5}' "$ts" | tail -1 | grep -qx '{py.new.s.t} a2.py' && echo 1 || echo 0)"
ok "cursor advanced to the new line (7)" "$([ "$(cat "$ST/.cycle_notify_cursor__alpha")" = 7 ] && echo 1 || echo 0)"

echo "cycle_notify_more_paths: $P passed, $F failed"
[ "$F" = 0 ]
