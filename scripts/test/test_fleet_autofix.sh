#!/usr/bin/env bash
# Regression test for fleet_autofix.sh — the */20 self-healing watchdog with two halves:
#   A) detect+alert on PERSISTENT issues (a diverged clone still flagged >30min, or a
#      feature->develop gate red >3h), deduped by content so it never spams
#   B) fix: reconcile branches + refill queues, gated behind run_overnight's lock
#
# Sandboxed via a fake HOME (throwaway state/logs) and fake reconcile_branches.sh /
# queue_refill.sh dropped into the sandbox overnight-queue dir (fleet_autofix.sh cd's
# there and calls them by relative path — this test must NEVER let it invoke the real
# ones against real repos/).
#
# NOTE on ntfy: fleet_autofix.sh hardcodes `export PATH=/usr/local/bin:/usr/bin:/bin:...`
# near the top, which puts the REAL system curl ahead of any test-injected PATH curl —
# unlike pause_guard.sh/gpu_autoswap.sh, a fake `curl` on PATH does NOT get picked up
# here. So, following the existing convention in test_reconcile_branches.sh, alerts are
# allowed to hit the real ntfy.sh but routed to an unwatched selftest topic (NTFY_TOPIC),
# and verified via the script's own log file + state (dedupe sig), not by intercepting curl.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${OVN_FLEET_AUTOFIX:-}" ]; then
  G="$OVN_FLEET_AUTOFIX"
else
  G="$HERE/../../fleet_autofix.sh"; [ -f "$G" ] || G="$HERE/../fleet_autofix.sh"; [ -f "$G" ] || G="$HERE/fleet_autofix.sh"
fi
[ -f "$G" ] || { echo "  SKIP: fleet_autofix.sh not found"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export NTFY_TOPIC="shrike_fleetautofix_selftest_ignore"   # any alert goes to an unwatched junk topic

reset_env(){
  export HOME="$tmp/home"
  rm -rf "$HOME"; mkdir -p "$HOME/overnight-queue/state" "$HOME/overnight-queue/logs"
  LOG="$HOME/overnight-queue/logs/fleet_autofix.log"
  export FAKE_RECONCILE_LOG="$tmp/reconcile.log"; export FAKE_REFILL_LOG="$tmp/refill.log"
  : > "$FAKE_RECONCILE_LOG"; : > "$FAKE_REFILL_LOG"
  cat > "$HOME/overnight-queue/reconcile_branches.sh" <<EOF
#!/usr/bin/env bash
echo "RECONCILE_CALLED" >> "$FAKE_RECONCILE_LOG"
exit \${FAKE_RECONCILE_RC:-0}
EOF
  cat > "$HOME/overnight-queue/queue_refill.sh" <<EOF
#!/usr/bin/env bash
echo "REFILL_CALLED MIN_DOABLE=\$MIN_DOABLE" >> "$FAKE_REFILL_LOG"
exit \${FAKE_REFILL_RC:-0}
EOF
  chmod +x "$HOME/overnight-queue/reconcile_branches.sh" "$HOME/overnight-queue/queue_refill.sh"
}

# --- A: healthy path — no diverged/gate-red markers at all ---
reset_env
FAKE_RECONCILE_RC=0 FAKE_REFILL_RC=0 bash "$G"
ok "healthy: logs 'no persistent issues' (no alert-worthy condition)" "grep -q 'no persistent issues' '$LOG'"
ok "healthy: no dedupe sig file left behind" "[ ! -f '$HOME/overnight-queue/state/autofix_last_sig' ]"
ok "healthy: fix stage still runs reconcile_branches.sh every tick" "grep -q RECONCILE_CALLED '$FAKE_RECONCILE_LOG'"
ok "healthy: fix stage still runs queue_refill.sh with MIN_DOABLE=15" "grep -q 'REFILL_CALLED MIN_DOABLE=15' '$FAKE_REFILL_LOG'"

# --- B: the actual guard case — a diverged clone still flagged >30min after the self-heal
#     window should have cleared it -> must be treated as persistent, and dedupe on the
#     next identical tick (same content -> same sig -> no repeat) ---
reset_env
touch "$HOME/overnight-queue/state/diverged_billwatch"
touch -d "-40 minutes" "$HOME/overnight-queue/state/diverged_billwatch"
bash "$G"
ok "stale diverged clone (>30min): flagged as persistent, names the repo" "grep -q 'persistent issues:.*diverged:billwatch' '$LOG'"
sig1="$(cat "$HOME/overnight-queue/state/autofix_last_sig" 2>/dev/null)"
ok "stale diverged clone: dedupe sig file recorded" "[ -n '$sig1' ]"
bash "$G"   # same persistent issue, second tick -> sig must be UNCHANGED (this is what dedup relies on)
sig2="$(cat "$HOME/overnight-queue/state/autofix_last_sig" 2>/dev/null)"
ok "stale diverged clone: identical issue set on 2nd tick keeps the same dedupe sig" "[ '$sig1' = '$sig2' ] && [ -n '$sig2' ]"

# --- C: a FRESH diverged marker (<30min, still inside the self-heal window) must NOT
#     be treated as a persistent issue at all ---
reset_env
touch "$HOME/overnight-queue/state/diverged_gitlark"
bash "$G"
ok "fresh diverged clone (<30min): logs 'no persistent issues' (self-heal window still open)" "grep -q 'no persistent issues' '$LOG'"
ok "fresh diverged clone: no dedupe sig created" "[ ! -f '$HOME/overnight-queue/state/autofix_last_sig' ]"

# --- D: a feature->develop gate red for >3h -> must be flagged, labeled gate-red not diverged ---
reset_env
touch "$HOME/overnight-queue/state/branch_hygiene_review_iptv_apps"
touch -d "-200 minutes" "$HOME/overnight-queue/state/branch_hygiene_review_iptv_apps"
bash "$G"
ok "stale gate-red (>3h): flagged, labeled gate-red not diverged" "grep -q 'persistent issues:.*gate-red:iptv_apps' '$LOG'"

# --- E: a FRESH gate-red (<3h) must NOT be flagged yet (a normal red build cycle) ---
reset_env
touch "$HOME/overnight-queue/state/branch_hygiene_review_xlite"
bash "$G"
ok "fresh gate-red (<3h): logs 'no persistent issues'" "grep -q 'no persistent issues' '$LOG'"

# --- F: once the issue clears entirely, the dedupe sig is dropped so a FUTURE recurrence
#     of the same issue (e.g. same repo diverges again later) will be treated as new/alert-worthy ---
reset_env
touch "$HOME/overnight-queue/state/diverged_billwatch"
touch -d "-40 minutes" "$HOME/overnight-queue/state/diverged_billwatch"
bash "$G"
ok "issue present: sig file exists" "[ -s '$HOME/overnight-queue/state/autofix_last_sig' ]"
rm -f "$HOME/overnight-queue/state/diverged_billwatch"
bash "$G"
ok "issue cleared: sig file is removed (dedupe state resets)" "[ ! -f '$HOME/overnight-queue/state/autofix_last_sig' ]"
touch "$HOME/overnight-queue/state/diverged_billwatch"
touch -d "-40 minutes" "$HOME/overnight-queue/state/diverged_billwatch"
bash "$G"
ok "issue recurs after clearing: flagged again (not permanently suppressed)" "grep -q 'persistent issues:.*diverged:billwatch' '$LOG'"

# --- G: the fix stage's exit status is logged correctly whether reconcile/refill succeed or fail ---
reset_env
FAKE_RECONCILE_RC=1 bash "$G"
ok "reconcile failure is logged as nonzero, not silently swallowed as ok" "grep -q 'reconcile nonzero' '$LOG'"
reset_env
FAKE_REFILL_RC=1 bash "$G"
ok "refill failure is logged as nonzero, not silently swallowed as ok" "grep -q 'refill nonzero' '$LOG'"

echo "fleet_autofix.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
