#!/usr/bin/env bash
# Tests for the two new ntfy-digest stats scripts (2026-09-09): ovn_tier_stats.py (pass/fail/
# no-op/timeout by tier + token spend) and ovn_planning_stats.py (planner/refill activity +
# stuck-dry detection). Both read real state files (outcomes.jsonl, ovn_planner.log,
# queue_refill.log) against a fixture $HOME so they never touch production data.
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS_DIR:-$HOME/overnight-queue/scripts}"
TS="$SCRIPTS/ovn_tier_stats.py"
PS="$SCRIPTS/ovn_planning_stats.py"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# ---- ovn_tier_stats.py ----
if [ -f "$TS" ]; then
  tmp="$(mktemp -d)"; export HOME="$tmp"; mkdir -p "$HOME/overnight-queue/state"
  OUT="$HOME/overnight-queue/state/outcomes.jsonl"
  now="$(date -u +%FT%TZ 2>/dev/null || python3 -c 'import datetime;print(datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"))')"
  cat > "$OUT" <<EOF
{"ts":"$now","repo":"r","id":"a","type":"aider_fix","tier":"3","category":"python","class":"landed","severity":"good","attempt":1,"fail_reason":"","status":"pushed(tests:pass)","tokens_sent":1000,"tokens_recv":200}
{"ts":"$now","repo":"r","id":"b","type":"aider_fix","tier":"3","category":"python","class":"noop","severity":"bad","attempt":1,"fail_reason":"timeout","status":"no-op","tokens_sent":500,"tokens_recv":50}
{"ts":"$now","repo":"r","id":"c","type":"aider_fix","tier":"3","category":"python","class":"skipped","severity":"expected","attempt":1,"fail_reason":"","status":"skip(exhausted)","tokens_sent":0,"tokens_recv":0}
{"ts":"$now","repo":"r","id":"d","type":"aider_fix","tier":"1","category":"python","class":"landed","severity":"good","attempt":1,"fail_reason":"","status":"pushed(tests:pass)","tokens_sent":300,"tokens_recv":40}
EOF
  out="$(python3 "$TS" 6 2>&1)"
  ok "tier stats: T3 rate excludes the skipped row from the denominator (1/2, not 1/3)" \
     "printf '%s' \"\$out\" | grep -qE 'T3: 1/2 \(50%\)'"
  ok "tier stats: T3's timeout is surfaced"                    "printf '%s' \"\$out\" | grep -q '1 timeout'"
  ok "tier stats: T1 shows 100%"                                "printf '%s' \"\$out\" | grep -qE 'T1: 1/1 \(100%\)'"
  ok "tier stats: total timeout line present"                  "printf '%s' \"\$out\" | grep -q '1 timeout(s) total'"
  ok "tier stats: token totals sum correctly (1800 sent, 290 recv)" \
     "printf '%s' \"\$out\" | grep -q '1.8k sent / 290 received'"

  : > "$OUT"
  out2="$(python3 "$TS" 6 2>&1)"
  ok "tier stats: empty window prints nothing (caller skips the section)" "[ -z \"\$out2\" ]"

  # --tokens-only (2026-09-09): a compact rolling-window token total for the digest, so a daily
  # spend figure doesn't require duplicating the whole tier table at a 24h window too.
  cat > "$OUT" <<EOF
{"ts":"$now","repo":"r","id":"a","type":"aider_fix","tier":"3","category":"python","class":"landed","severity":"good","attempt":1,"fail_reason":"","status":"pushed(tests:pass)","tokens_sent":1000,"tokens_recv":200}
{"ts":"$now","repo":"r","id":"b","type":"aider_fix","tier":"3","category":"python","class":"noop","severity":"bad","attempt":1,"fail_reason":"timeout","status":"no-op","tokens_sent":500,"tokens_recv":50}
EOF
  outtok="$(python3 "$TS" 6 --tokens-only 2>&1)"
  ok "tokens-only: sums across the window (1.5k sent / 250 recv)" \
     "printf '%s' \"\$outtok\" | grep -q '1.5k sent / 250 received'"
  ok "tokens-only: reports the task count"          "printf '%s' \"\$outtok\" | grep -q '(2 tasks)'"
  ok "tokens-only: does NOT print the tier table"    "! printf '%s' \"\$outtok\" | grep -q 'By tier'"

  : > "$OUT"
  outtok2="$(python3 "$TS" 6 --tokens-only 2>&1)"
  ok "tokens-only: empty window prints nothing" "[ -z \"\$outtok2\" ]"

  rm -rf "$tmp"
else
  echo "  SKIP: $TS not found on this host"
fi

# ---- ovn_planning_stats.py ----
if [ -f "$PS" ]; then
  tmp="$(mktemp -d)"; export HOME="$tmp"; mkdir -p "$HOME/overnight-queue/logs"
  now_local="$(date '+%Y-%m-%d %H:%M:%S')"
  cat > "$HOME/overnight-queue/logs/ovn_planner.log" <<EOF
$now_local gitlark: appended 8 27B-decomposed items to backlog; marked feature [decomposed]
$now_local billwatch: backlog low (0) but no [ready] roadmap feature (needs Claude research?)
EOF
  cat > "$HOME/overnight-queue/logs/queue_refill.log" <<EOF
$now_local gitlark: refilled +8 (was 5, backlog now 0)
$now_local billwatch: 0 doable — backlog DRY
EOF
  out="$(python3 "$PS" 6 2>&1)"
  ok "planning stats: reports decomposed count"        "printf '%s' \"\$out\" | grep -q 'gitlark +8'"
  ok "planning stats: reports refilled count"           "printf '%s' \"\$out\" | grep -q 'refilled gitlark +8'"
  ok "planning stats: flags a genuinely stuck repo (both dry AND no ready feature)" \
     "printf '%s' \"\$out\" | grep -q 'Stuck dry.*billwatch'"
  ok "planning stats: does NOT flag gitlark (it has activity, not stuck)" \
     "! printf '%s' \"\$out\" | grep -E 'Stuck dry' | grep -q gitlark"

  # a repo with NO ready feature but backlog still healthy must NOT be flagged stuck
  # (only refill AND planner both reporting dry counts as genuinely stuck)
  cat > "$HOME/overnight-queue/logs/ovn_planner.log" <<EOF
$now_local shrike-monitor: backlog low (3) but no [ready] roadmap feature (needs Claude research?)
EOF
  cat > "$HOME/overnight-queue/logs/queue_refill.log" <<EOF
$now_local shrike-monitor: 12 doable (ok, no refill)
EOF
  out2="$(python3 "$PS" 6 2>&1)"
  ok "planning stats: no-ready-feature ALONE (backlog still healthy) is not flagged stuck" \
     "! printf '%s' \"\$out2\" | grep -q 'Stuck dry'"

  : > "$HOME/overnight-queue/logs/ovn_planner.log"; : > "$HOME/overnight-queue/logs/queue_refill.log"
  out3="$(python3 "$PS" 6 2>&1)"
  ok "planning stats: no activity in either log prints nothing" "[ -z \"\$out3\" ]"
  rm -rf "$tmp"
else
  echo "  SKIP: $PS not found on this host"
fi

echo "Ntfy digest stats: $P passed, $F failed"
[ "$F" -eq 0 ]
