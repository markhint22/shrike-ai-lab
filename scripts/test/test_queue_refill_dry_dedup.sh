#!/usr/bin/env bash
# Regression test: queue_refill.sh's "backlog DRY" alert must NOT re-fire every run for as long
# as a repo stays dry (2026-09-09). queue_refill.sh runs both on its own hourly cron AND at the
# end of every fleet cycle (~20-40min) — before this fix, a persistently-dry repo re-alerted on
# EVERY one of those runs with zero dedup, producing dozens of identical "out of queued items"
# pushes per day. Fixed with the same state/qr_dry_<repo> marker pattern as queue_health.sh's
# qh_bad_<name>: one alert on newly-dry, silence while still dry, one reminder per
# DRY_REMIND_HOURS, one quiet recovery note when the repo gets doable items again.
set -uo pipefail
Q="${OVN_QUEUE_REFILL:-$HOME/overnight-queue/queue_refill.sh}"
[ -f "$Q" ] || { echo "  SKIP: $Q not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
# queue_refill.sh hardcodes `cd "$HOME/overnight-queue"`, so the test's HOME must have an
# overnight-queue/ subdir for the script to find itself in.
wd="$tmp/overnight-queue"
mkdir -p "$wd/repos/foo" "$wd/backlog" "$wd/state" "$tmp/aider-venv/bin"
cp "$Q" "$wd/queue_refill.sh"
cat > "$wd/queue.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$wd/queue.sh"

ALERT_LOG="$tmp/curl.log"; : > "$ALERT_LOG"
# queue_refill.sh hardcodes PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH", so
# the stub must live in $HOME/aider-venv/bin (ahead of the real system curl) to be picked up —
# a plain PATH= prefix on the test's own invocation isn't enough, it gets overridden inside.
cat > "$tmp/aider-venv/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in Title:*) echo "\$a" >> "$ALERT_LOG" ;; esac; done
exit 0
EOF
chmod +x "$tmp/aider-venv/bin/curl"

run_refill(){
  ( cd "$wd" && HOME="$tmp" MIN_DOABLE="${1:-15}" ./queue_refill.sh foo >/dev/null 2>&1 )
}

echo "" > "$wd/backlog/foo.md"
: > "$wd/repos/foo/OVERNIGHT_PROGRESS.md"

run_refill
ok "newly-dry fires exactly one out-of-items alert" \
   "[ \$(grep -c 'A few repos are out of queued items' '$ALERT_LOG') -eq 1 ]"
ok "newly-dry creates the qr_dry marker" "[ -f '$wd/state/qr_dry_foo' ]"

: > "$ALERT_LOG"
run_refill; run_refill
ok "still-dry: no repeat alert across 2 more runs" "[ ! -s '$ALERT_LOG' ]"

echo $(( $(date +%s) - 90000 )) > "$wd/state/qr_dry_foo"   # simulate marker aged past 24h
run_refill
ok "aged-dry fires exactly one reminder alert" \
   "[ \$(grep -c 'Still out of queued items' '$ALERT_LOG') -eq 1 ]"

: > "$ALERT_LOG"
printf -- '- [ ] [T1] a\n- [ ] [T1] b\n' > "$wd/repos/foo/OVERNIGHT_PROGRESS.md"
run_refill 1
ok "recovery fires exactly one recovered note" \
   "[ \$(grep -c 'Backlog refilled' '$ALERT_LOG') -eq 1 ]"
ok "recovery clears the qr_dry marker" "[ ! -f '$wd/state/qr_dry_foo' ]"

: > "$ALERT_LOG"
run_refill 1
ok "staying healthy: no further alert of either kind" "[ ! -s '$ALERT_LOG' ]"

rm -rf "$tmp"
echo "Queue-refill dry dedup: $P passed, $F failed"
[ "$F" -eq 0 ]
