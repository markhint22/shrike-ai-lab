#!/usr/bin/env bash
# Regression test: queue_health.sh's deploy-health check must NOT re-alert every run for as
# long as an endpoint stays down (2026-09-09). Before this fix it had zero dedup at all - every
# hourly run would re-fire "Deploy health check FAILED" for the same ongoing outage, unlike
# deploy_watch.sh's proper state-change-only alerting. This got MORE exposed today: populating
# state/health_endpoints.txt with all 6 production backends (previously just one hardcoded
# default) would have multiplied the repeat-alert volume for any single real outage.
#
# Verifies the full sequence with a stubbed curl (controlled via a file so its response can
# change between separate invocations of queue_health.sh): first failure -> ONE alert; still
# failing -> NO alert; recovers -> ONE recovery alert; stays healthy -> no further alert.
set -uo pipefail
Q="${OVN_QUEUE_HEALTH:-$HOME/overnight-queue/queue_health.sh}"
[ -f "$Q" ] || { echo "  SKIP: $Q not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
mkdir -p "$tmp/state" "$tmp/bin"
printf '[]\n' > "$tmp/tasks.json"
cat > "$tmp/state/health_endpoints.txt" <<'EOF'
depcheck|https://this-host-should-not-be-curled.invalid.test|
EOF
cp "$Q" "$tmp/queue_health.sh"

CODE_FILE="$tmp/stub_code"
ALERT_LOG="$tmp/alerts.log"; : > "$ALERT_LOG"
run_qh(){
  ( cd "$tmp" && PATH="$tmp/bin:$PATH" CODE_FILE="$CODE_FILE" MIN_DOABLE=999999 \
      NTFY_TOPIC=x bash queue_health.sh >/dev/null 2>&1 )
}
# One curl stub handles BOTH roles it's asked to play: the health-check GET (returns the
# controllable stub code) and alert()'s POST (recorded here by grepping its -H "Title: ..."
# argument) - queue_health.sh doesn't distinguish them by anything else we can intercept on.
cat > "$tmp/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in Title:*) echo "\$a" >> "$ALERT_LOG" ;; esac
done
echo -n "" > /tmp/hc_body 2>/dev/null
cat "$CODE_FILE" 2>/dev/null || echo 200
exit 0
EOF
chmod +x "$tmp/bin/curl"

echo 500 > "$CODE_FILE"
run_qh
ok "first failure fires exactly one FAILED alert" \
   "[ \$(grep -c 'Deploy health check FAILED' '$ALERT_LOG') -eq 1 ]"
ok "first failure creates the bad-state marker" "[ -f '$tmp/state/qh_bad_depcheck' ]"

: > "$ALERT_LOG"
run_qh
run_qh
ok "still-down: no repeat FAILED alert across 2 more runs" \
   "[ \$(grep -c 'Deploy health check FAILED' '$ALERT_LOG') -eq 0 ]"

echo 200 > "$CODE_FILE"
run_qh
ok "recovery fires exactly one recovery alert" \
   "[ \$(grep -c 'Deploy health check recovered' '$ALERT_LOG') -eq 1 ]"
ok "recovery clears the bad-state marker" "[ ! -f '$tmp/state/qh_bad_depcheck' ]"

: > "$ALERT_LOG"
run_qh
ok "staying healthy: no further alert of either kind" "[ ! -s '$ALERT_LOG' ]"

rm -rf "$tmp"
echo "Queue-health dedup: $P passed, $F failed"
[ "$F" -eq 0 ]
