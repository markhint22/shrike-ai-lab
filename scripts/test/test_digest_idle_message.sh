#!/usr/bin/env bash
# Regression test: digest_notify.sh's empty-buffer branch must report the REAL queue state
# (paused / running / not-running), never the old ambiguous "queue idle or paused" hedge
# (2026-09-09).
#
# Real incident: two manual digest_notify.sh runs a few minutes apart — the first drained the
# buffer normally, the second found it empty (correctly, almost no time had passed) and sent
# "No cycles ran in the last 3h (queue idle or paused)". The queue was never paused; it had been
# cycling the whole time. The wording itself was the bug — an empty buffer only ever means
# "nothing since the last digest," not "idle for 3h," and guessing "idle or paused" instead of
# checking is what read as alarming. Fixed to check state/PAUSED and `systemctl is-active`
# directly instead of hedging.
set -uo pipefail
D="${OVN_DIGEST_NOTIFY:-$HOME/overnight-queue/digest_notify.sh}"
[ -f "$D" ] || { echo "  SKIP: $D not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
mkdir -p "$tmp/state" "$tmp/bin"
: > "$tmp/state/digest_buffer.log"   # empty buffer -> exercises the branch under test
# digest_notify.sh derives STATE_DIR from its OWN location (BASH_SOURCE), not an env var —
# copy it into $tmp so that resolves to our fixture state dir, not the real production one.
cp "$D" "$tmp/digest_notify.sh"

ALERT_LOG="$tmp/alerts.log"; : > "$ALERT_LOG"
cat > "$tmp/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do echo "\$a" >> "$ALERT_LOG"; done
exit 0
EOF
chmod +x "$tmp/bin/curl"

run_digest(){  # $1=systemctl-mode (active|inactive)
  cat > "$tmp/bin/systemctl" <<EOF
#!/usr/bin/env bash
[ "\$1" = "is-active" ] && [ "\$2" = "--quiet" -o "\$3" = "overnight-queue" ] || true
[ "$1" = "active" ] && exit 0 || exit 3
EOF
  chmod +x "$tmp/bin/systemctl"
  ( cd "$tmp" && PATH="$tmp/bin:$PATH" NTFY_TOPIC=test-topic bash "$tmp/digest_notify.sh" >/dev/null 2>&1 )
}

# --- case 1: no PAUSED file, systemd active -> "quiet, NOT paused" ---
: > "$ALERT_LOG"
run_digest active
ok "running+empty-buffer: fires the quiet heartbeat"          "grep -q 'Title: Overnight queue — quiet' '$ALERT_LOG'"
ok "running+empty-buffer: explicitly says NOT paused"          "grep -qi 'not paused' '$ALERT_LOG'"
ok "running+empty-buffer: never uses the old ambiguous hedge"  "! grep -qi 'idle or paused' '$ALERT_LOG'"

# --- case 2: state/PAUSED exists -> must say PAUSED, unambiguously ---
: > "$ALERT_LOG"
touch "$tmp/state/PAUSED"
run_digest active
ok "paused+empty-buffer: fires a PAUSED-titled alert"  "grep -q 'Title: Overnight queue — PAUSED' '$ALERT_LOG'"
rm -f "$tmp/state/PAUSED"

# --- case 3: no PAUSED file, systemd NOT active -> must say NOT RUNNING, not a vague guess ---
: > "$ALERT_LOG"
run_digest inactive
ok "not-running+empty-buffer: fires a NOT RUNNING alert"  "grep -q 'Title: Overnight queue — NOT RUNNING' '$ALERT_LOG'"
ok "not-running+empty-buffer: never uses the old ambiguous hedge" "! grep -qi 'idle or paused' '$ALERT_LOG'"

rm -rf "$tmp"
echo "Digest idle-message accuracy: $P passed, $F failed"
[ "$F" -eq 0 ]
