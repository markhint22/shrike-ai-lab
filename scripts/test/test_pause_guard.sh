#!/usr/bin/env bash
# Regression test for pause_guard.sh — the fleet-pause self-heal guard.
#
# Real gap this closes: pause_guard.sh runs unmocked against $HOME/overnight-queue/state
# and calls queue.sh resume + ntfy on a live host. This sandboxes it entirely via a fake
# HOME (so STATE/queue.sh/logs are all throwaway) and a fake `curl` on PATH (so no real
# ntfy traffic and so alerts are inspectable), and exercises the three pause kinds the
# script must tell apart: stale DEPLOY pause (auto-clear+resume), stale STAGE pause
# (auto-clear, no resume call), and MANUAL pause (alert-only, never auto-cleared).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${OVN_PAUSE_GUARD:-}" ]; then
  G="$OVN_PAUSE_GUARD"
else
  G="$HERE/../../pause_guard.sh"; [ -f "$G" ] || G="$HERE/../pause_guard.sh"; [ -f "$G" ] || G="$HERE/pause_guard.sh"
fi
[ -f "$G" ] || { echo "  SKIP: pause_guard.sh not found"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# fake bin dir: curl (records alerts, never hits the network) + queue.sh (records resume calls)
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "CURL_CALL $*" >> "$FAKE_CURL_LOG"
exit 0
EOF
chmod +x "$tmp/bin/curl"

run_guard(){  # sets up a fresh sandbox HOME each call
  export HOME="$tmp/home"
  rm -rf "$HOME"; mkdir -p "$HOME/overnight-queue/state"
  cat > "$HOME/overnight-queue/queue.sh" <<'EOF'
#!/usr/bin/env bash
# mirrors the real queue.sh resume: removes state/PAUSED itself (pause_guard.sh's
# deploy-pause branch relies on THIS to clear PAUSED — it only rm's deploy_pause itself)
if [ "$1" = "resume" ]; then
  echo "RESUME_CALLED" >> "$FAKE_QUEUE_LOG"
  rm -f "$HOME/overnight-queue/state/PAUSED"
fi
exit 0
EOF
  chmod +x "$HOME/overnight-queue/queue.sh"
}

export FAKE_CURL_LOG="$tmp/curl.log"; export FAKE_QUEUE_LOG="$tmp/queue.log"
export PATH="$tmp/bin:$PATH"
export NTFY_TOPIC="shrike_pauseguard_selftest_ignore"

# --- A: healthy path — no PAUSED file at all -> exits clean, touches nothing ---
run_guard
: > "$FAKE_CURL_LOG"; : > "$FAKE_QUEUE_LOG"
bash "$G"
rc=$?
ok "no PAUSED file: exits 0" "[ $rc -eq 0 ]"
ok "no PAUSED file: no alert fired" "[ ! -s '$FAKE_CURL_LOG' ]"
ok "no PAUSED file: no resume called" "[ ! -s '$FAKE_QUEUE_LOG' ]"

# --- B: stale DEPLOY pause (>20min) -> auto-clear + resume + alert ---
run_guard
: > "$FAKE_CURL_LOG"; : > "$FAKE_QUEUE_LOG"
touch "$HOME/overnight-queue/state/PAUSED"
touch "$HOME/overnight-queue/state/deploy_pause"
# back-date both past the 20min threshold
touch -d "-30 minutes" "$HOME/overnight-queue/state/PAUSED" "$HOME/overnight-queue/state/deploy_pause"
bash "$G"
ok "stale deploy-pause: PAUSED cleared" "[ ! -f '$HOME/overnight-queue/state/PAUSED' ]"
ok "stale deploy-pause: deploy_pause marker cleared" "[ ! -f '$HOME/overnight-queue/state/deploy_pause' ]"
ok "stale deploy-pause: queue.sh resume was called" "grep -q RESUME_CALLED '$FAKE_QUEUE_LOG'"
ok "stale deploy-pause: alert fired" "grep -q 'auto-resumed' '$FAKE_CURL_LOG'"

# --- C: FRESH deploy pause (<20min) -> left alone, no resume, no alert ---
run_guard
: > "$FAKE_CURL_LOG"; : > "$FAKE_QUEUE_LOG"
touch "$HOME/overnight-queue/state/PAUSED"
touch "$HOME/overnight-queue/state/deploy_pause"
bash "$G"
ok "fresh deploy-pause: PAUSED left in place" "[ -f '$HOME/overnight-queue/state/PAUSED' ]"
ok "fresh deploy-pause: no resume called" "[ ! -s '$FAKE_QUEUE_LOG' ]"
ok "fresh deploy-pause: no alert fired" "[ ! -s '$FAKE_CURL_LOG' ]"

# --- D: stale STAGE pause (>45min) -> auto-clear directly, must NOT call queue.sh resume ---
run_guard
: > "$FAKE_CURL_LOG"; : > "$FAKE_QUEUE_LOG"
touch "$HOME/overnight-queue/state/PAUSED"
echo "$(( $(date +%s) - 2800 ))" > "$HOME/overnight-queue/state/stage_pause_since"
bash "$G"
ok "stale stage-pause: PAUSED cleared" "[ ! -f '$HOME/overnight-queue/state/PAUSED' ]"
ok "stale stage-pause: stage_pause_since cleared" "[ ! -f '$HOME/overnight-queue/state/stage_pause_since' ]"
ok "stale stage-pause: alert fired" "grep -q 'auto-resumed' '$FAKE_CURL_LOG'"
ok "stale stage-pause: does NOT call queue.sh resume (self-clears directly)" "[ ! -s '$FAKE_QUEUE_LOG' ]"

# --- E: FRESH stage pause (<45min) -> left alone entirely ---
run_guard
: > "$FAKE_CURL_LOG"; : > "$FAKE_QUEUE_LOG"
touch "$HOME/overnight-queue/state/PAUSED"
echo "$(date +%s)" > "$HOME/overnight-queue/state/stage_pause_since"
bash "$G"
ok "fresh stage-pause: PAUSED left in place" "[ -f '$HOME/overnight-queue/state/PAUSED' ]"
ok "fresh stage-pause: no alert fired" "[ ! -s '$FAKE_CURL_LOG' ]"

# --- F: MANUAL pause (no deploy/stage marker) >90min -> alert ONCE, never auto-clear ---
run_guard
: > "$FAKE_CURL_LOG"; : > "$FAKE_QUEUE_LOG"
touch "$HOME/overnight-queue/state/PAUSED"
touch -d "-100 minutes" "$HOME/overnight-queue/state/PAUSED"
bash "$G"
ok "stale manual pause: PAUSED is NOT cleared (manual pauses are never auto-resumed)" "[ -f '$HOME/overnight-queue/state/PAUSED' ]"
ok "stale manual pause: no resume ever called" "[ ! -s '$FAKE_QUEUE_LOG' ]"
ok "stale manual pause: alert fired once" "grep -q 'Queue paused' '$FAKE_CURL_LOG'"
n1=$(grep -c 'Queue paused' "$FAKE_CURL_LOG")
: > "$FAKE_CURL_LOG"
bash "$G"   # second tick, still paused -> must NOT re-alert (dedup via pause_alerted flag)
n2=$(grep -c 'Queue paused' "$FAKE_CURL_LOG" || true)
ok "stale manual pause: second tick does not re-alert (deduped)" "[ '$n1' -eq 1 ] && [ '${n2:-0}' -eq 0 ]"

# --- G: FIXED BUG regression guard (2026-09-10) — pause_alerted must be cleaned up once the
# pause resolves, so a LATER, separate manual-pause episode that also crosses 90 min still
# re-alerts. Was dead code before the fix: `[ -f "$P" ] || exit 0` always exited before the
# bottom-of-script cleanup line could ever run, so the dedupe flag was never reset and a
# second stuck-pause incident would silently never alert. ---
rm -f "$HOME/overnight-queue/state/PAUSED"
bash "$G"
ok "pause resolved: pause_alerted flag IS cleaned up (was dead code before the fix)" \
   "[ ! -f '$HOME/overnight-queue/state/pause_alerted' ]"

# a SECOND, separate manual-pause episode past 90min must re-alert now that the flag reset
: > "$FAKE_CURL_LOG"
touch "$HOME/overnight-queue/state/PAUSED"
touch -d "-100 minutes" "$HOME/overnight-queue/state/PAUSED"
bash "$G"
ok "a second stale-manual-pause episode re-alerts (was silently swallowed before the fix)" \
   "grep -q 'Queue paused' '$FAKE_CURL_LOG'"

echo "pause_guard.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
