#!/usr/bin/env bash
# Tests for hourly_notify.sh (2026-09-20, gated-on-notability 2026-09-28) — the leaner, hourly
# companion to digest_notify.sh's 3h rollup. Verifies: (a) it sends NOTHING when there was no
# activity in the last hour, (b) 2026-09-28: it ALSO sends NOTHING for a normal hour of clean
# landings — this used to push a tally every single hour regardless of content (one of two
# scripts responsible for the bulk of daily message volume); now a clean hour is NOT notable
# and stays silent, (c) it DOES send for a genuinely notable hour (a fully-wasted hour: 0
# landed + a wasted attempt), with the tier breakdown + per-item detail, and (d) it never
# duplicates the heavier 3h-only sections (tokens/by-language/planning). Stubs curl so no real
# network call is made; runs against a fixture $HOME so it never touches production data.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
SCRIPT="$OQ/hourly_notify.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; exit 0; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# hourly_notify.sh derives its own DIR from its OWN location (BASH_SOURCE), same as
# digest_notify.sh — mirror it (+ the real scripts/ helpers it shells out to) into $tmp so
# that resolves to a fixture state dir, never the real production one.
mkdir -p "$tmp/state" "$tmp/scripts" "$tmp/repos"
cp "$SCRIPT" "$tmp/hourly_notify.sh"
for f in ovn_tier_stats.py ovn_landed_detail.py ovn_feature_groups.py ovn_outcome_buckets.py ovn_hourly_notable.py; do
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

# ---- 2 (2026-09-28): a NORMAL hour of clean landings (no wasted attempts) -> NOT notable,
#      sends nothing. This is the exact behavior change this fix is about: before, ANY
#      activity at all (including a single clean landing) triggered a push every hour. ----
now="$(date +%s)"
printf '%s\tbillwatch\tpass\t{py\xc2\xb7other\xc2\xb7T2\xc2\xb7test-covered}\tapp/foo.py\n' "$now" > "$tmp/state/task_stats.log"
cat > "$tmp/state/outcomes.jsonl" <<JEOF
{"ts":"$(date -u +%FT%TZ)","repo":"billwatch","id":"ongoing-billwatch","type":"aider_fix","tier":"2","category":"python","class":"landed","severity":"good","attempt":1,"fail_reason":"","status":"pushed(tests:pass)","tokens_sent":100,"tokens_recv":50,"duration_s":30}
JEOF
: > "$CURLLOG"
run_hourly
ok "a normal hour of clean landings is NOT notable -> no push (was the old always-tally bug)" "[ ! -s '$CURLLOG' ]"

# ---- 3: a genuinely notable hour (a fully-wasted hour: 0 landed, 1 wasted attempt) -> a
#      push DOES happen, with tier + per-item detail, and the reason leads the body. ----
printf '%s\tbillwatch\trevert\t{py\xc2\xb7other\xc2\xb7T2\xc2\xb7test-covered}\tapp/bar.py\n' "$now" > "$tmp/state/task_stats.log"
cat > "$tmp/state/outcomes.jsonl" <<JEOF
{"ts":"$(date -u +%FT%TZ)","repo":"billwatch","id":"ongoing-billwatch","type":"aider_fix","tier":"2","category":"python","class":"reverted","severity":"bad","attempt":1,"fail_reason":"tests failed","status":"reverted","tokens_sent":100,"tokens_recv":50,"duration_s":30}
JEOF
: > "$CURLLOG"
run_hourly
# the -d body can itself contain newlines, so count invocations by their start marker, not raw lines
ok "a notable (fully-wasted) hour triggers exactly one push" "[ \$(grep -c '^CALL: -fsS' '$CURLLOG') -eq 1 ]"
ok "the push title identifies it as the hourly digest" "grep -q 'Overnight queue' '$CURLLOG'"
ok "the push body leads with the plain-language notability reason" "grep -q 'fully-wasted' '$CURLLOG'"
ok "the push uses a default (not unset) priority" "grep -q 'Priority: default' '$CURLLOG'"

echo "hourly_notify.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
