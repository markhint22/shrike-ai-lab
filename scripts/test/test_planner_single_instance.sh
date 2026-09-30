#!/usr/bin/env bash
# Regression: ovn_planner.sh must be single-instance. 2026-09-30 a manual run overlapping the :40 cron run made 2-3
# passes each pick the SAME [ready] feature before any marked it [decomposed] -> duplicate, differently-worded
# decompositions in the live queues. The second concurrent pass must skip immediately and log why.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
P="$HERE/../../ovn_planner.sh"; [ -f "$P" ] || P="$HERE/../ovn_planner.sh"; [ -f "$P" ] || P="$HERE/ovn_planner.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"; kill %1 2>/dev/null' EXIT
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
ok "planner takes an exclusive flock on state/ovn_planner.lock" "$(grep -q 'flock -n 228' "$P" && grep -q 'ovn_planner.lock' "$P" && echo 1 || echo 0)"
ok "the lock is taken BEFORE the per-repo loop" "$([ "$(grep -n 'flock -n 228' "$P" | head -1 | cut -d: -f1)" -lt "$(grep -n '^for r in \$REPOS' "$P" | head -1 | cut -d: -f1)" ] && echo 1 || echo 0)"
if command -v flock >/dev/null 2>&1; then
  # isolated HOME: the planner does `cd "$HOME/overnight-queue"`, so never run it against a real tree
  H="$T/home"; W="$H/overnight-queue"; mkdir -p "$W/state" "$W/logs" "$W/roadmap" "$W/backlog" "$W/repos"; cp "$P" "$W/ovn_planner.sh"
  ( exec 9>"$W/state/ovn_planner.lock"; flock -n 9 && sleep 8 ) & sleep 1
  ( cd "$W" && HOME="$H" timeout 6 bash ./ovn_planner.sh ) >"$T/out" 2>&1; rc=$?
  ok "second pass exits 0 immediately while the lock is held" "$([ $rc = 0 ] && echo 1 || echo 0)"
  ok "second pass logs that it skipped" "$(grep -q 'already running' "$W/logs/ovn_planner.log" 2>/dev/null && echo 1 || echo 0)"
else
  echo "  skip dynamic check (no flock on this host)"
fi
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
