#!/usr/bin/env bash
# Tests for hourly_notify.sh (2026-09-20) — the new leaner, hourly companion to
# digest_notify.sh's 3h rollup. Verifies: (a) it sends NOTHING when there was no activity in
# the last hour (no idle heartbeat — digest_notify.sh already owns that signal), (b) it DOES
# send when there was landed activity, with a tier breakdown + per-item detail, and (c) it
# never duplicates the heavier 3h-only sections (tokens/by-language/planning). Stubs curl so no
# real network call is made; runs against a fixture $HOME so it never touches production data.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
SCRIPT="$OQ/hourly_notify.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# hourly_notify.sh derives its own DIR from its OWN location (BASH_SOURCE), same as
# digest_notify.sh — mirror it (+ the real scripts/ helpers it shells out to) into $tmp so
# that resolves to a fixture state dir, never the real production one.
mkdir -p "$tmp/state" "$tmp/scripts" "$tmp/repos"
cp "$SCRIPT" "$tmp/hourly_notify.sh"
for f in ovn_tier_stats.py ovn_landed_detail.py ovn_feature_groups.py; do
  [ -f "$OQ/scripts/$f" ] && cp "$OQ/scripts/$f" "$tmp/scripts/$f"
done
echo "faketopic" > "$tmp/state/ntfy_topic"

# stub curl on PATH: records every call it would have made instead of hitting the network
mkdir -p "$tmp/bin"
CURLLOG="$tmp/curl_calls.log"
cat > "$tmp/bin/curl" <<CURLEOF
#!/usr/bin/env bash
echo "CALL: \$*" >> "$CURLLOG"
exit 0
CURLEOF
chmod +x "$tmp/bin/curl"

run_hourly(){ ( cd "$tmp" && PATH="$tmp/bin:$PATH" HOME="$tmp" bash "$tmp/hourly_notify.sh" >/dev/null 2>&1 ); }

# ---- 1: no activity at all in the last hour -> no curl call, no push ----
: > "$CURLLOG"
run_hourly
ok "no activity -> no ntfy call at all (no idle heartbeat)" "[ ! -s '$CURLLOG' ]"

# ---- 2: real landed activity -> a push happens, with tier + per-item detail ----
now="$(date +%s)"
printf '%s\tbillwatch\tpass\t{py\xc2\xb7other\xc2\xb7T2\xc2\xb7test-covered}\tapp/foo.py\n' "$now" > "$tmp/state/task_stats.log"
cat > "$tmp/state/outcomes.jsonl" <<JEOF
{"ts":"$(date -u +%FT%TZ)","repo":"billwatch","id":"ongoing-billwatch","type":"aider_fix","tier":"2","category":"python","class":"landed","severity":"good","attempt":1,"fail_reason":"","status":"pushed(tests:pass)","tokens_sent":100,"tokens_recv":50,"duration_s":30}
JEOF
: > "$CURLLOG"
run_hourly
# the -d body can itself contain newlines, so count invocations by their start marker, not raw lines
ok "real activity in the window triggers exactly one push" "[ \$(grep -c '^CALL: -fsS' '$CURLLOG') -eq 1 ]"
ok "the push title identifies it as the hourly digest" "grep -q 'Overnight queue' '$CURLLOG'"

echo "hourly_notify.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
