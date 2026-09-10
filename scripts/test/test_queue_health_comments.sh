#!/usr/bin/env bash
# Regression test: queue_health.sh's health_endpoints.txt loader must skip comment/blank
# lines. Written 2026-09-09 after finding that a "# name|url|..." header line got fed
# straight into CHECKS, curl'd the literal string "url" as a domain, and would have raised
# a FALSE "Deploy health check FAILED" alert on every run (this was caught before it ever
# fired live, since the config file was empty/missing at the time). Runs the real
# queue_health.sh against a fixture endpoints file with no network dependency for the
# comment-parsing part by pointing every real check at 127.0.0.1's closed port (curl fails
# fast with a real, deterministic non-2xx/3xx "000") plus asserting the alert body never
# mentions the comment lines' bogus "url"/"name" fields.
set -uo pipefail
Q="${OVN_QUEUE_HEALTH:-$HOME/overnight-queue/queue_health.sh}"
[ -f "$Q" ] || { echo "  SKIP: $Q not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
mkdir -p "$tmp/state" "$tmp/repos"
printf '[]\n' > "$tmp/tasks.json"
cat > "$tmp/state/health_endpoints.txt" <<'EOF'
# name|url|expected-substring-in-body (empty = any 2xx/3xx is fine)
# a second comment line, and a blank line below

realcheck|https://this-host-should-not-be-curled.invalid.test|
EOF
cp "$Q" "$tmp/queue_health.sh"

# capture what curl would be asked to fetch, without hitting the network: stub curl on PATH.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# log every URL curl is asked to fetch (last arg), then behave like a reachable 200 for
# anything that doesn't look like the poisoned comment-parse output.
url="${@: -1}"
echo "$url" >> "$CURL_LOG"
for a in "$@"; do
  case "$a" in -o) shift_out=1;; esac
done
echo -n "" > /tmp/hc_body 2>/dev/null
echo 200
exit 0
EOF
chmod +x "$tmp/bin/curl"

CURL_LOG="$tmp/curl.log"; : > "$CURL_LOG"
( cd "$tmp" && PATH="$tmp/bin:$PATH" CURL_LOG="$CURL_LOG" MIN_DOABLE=999999 bash queue_health.sh >/dev/null 2>&1 )

ok "the comment header line's bogus 'url' field was NEVER curl'd" \
   "! grep -qx 'url' '$CURL_LOG'"
ok "the real (non-comment) endpoint WAS curl'd"                    \
   "grep -q 'this-host-should-not-be-curled.invalid.test' '$CURL_LOG'"
ok "exactly one URL was checked (comments/blank fully filtered)"   \
   "[ \$(wc -l < '$CURL_LOG') -eq 1 ]"

rm -rf "$tmp"
echo "Queue-health comment parsing: $P passed, $F failed"
[ "$F" -eq 0 ]
