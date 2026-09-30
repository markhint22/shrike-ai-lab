#!/usr/bin/env bash
# Extra coverage for the REAL hourly_notify.sh: stub python helpers (canned output) drive every optional body section, and a
# failing stub curl drives the 3-attempt retry + failure path. Also the no-topic early exit.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S=""; for c in "$HERE/../../hourly_notify.sh" "$HERE/../hourly_notify.sh"; do [ -f "$c" ] && { S="$c"; break; }; done
[ -n "$S" ] || { echo "  SKIP: hourly_notify.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ -n "$2" ] && [ -z "${2//1/}" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
Q="$T/q"; BIN="$T/bin"; STUBD="$T/stubd"; CALLS="$T/calls"
mkdir -p "$Q/state" "$Q/scripts" "$BIN" "$STUBD" "$CALLS"; export STUBD CALLS
cp "$S" "$Q/hourly_notify.sh"
cat > "$Q/scripts/stub.py" <<'PY'
import os, sys
a = sys.argv; b = os.path.basename(a[0]); d = os.environ["STUBD"]
def out(k):
    p = os.path.join(d, k)
    if os.path.exists(p): sys.stdout.write(open(p).read())
if b == "ovn_hourly_notable.py": out("notable")
elif b == "ovn_tier_stats.py": out("one" if "--oneline" in a else "tiers")
elif b == "ovn_landed_detail.py": out("landed")
elif b == "ovn_feature_groups.py": out("feat")
PY
for n in ovn_hourly_notable ovn_tier_stats ovn_landed_detail ovn_feature_groups; do cp "$Q/scripts/stub.py" "$Q/scripts/$n.py"; done
cat > "$BIN/curl" <<'EOF2'
#!/usr/bin/env bash
echo x >> "$CALLS/n"; body=""; prev=""
for a in "$@"; do [ "$prev" = "-d" ] && body="$a"; prev="$a"; done
printf '%s' "$body" > "$CALLS/body"
[ -n "${CURL_FAIL:-}" ] && exit 22
exit 0
EOF2
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/sleep"; chmod +x "$BIN"/*
run(){ rm -f "$CALLS"/*; OUT="$(cd "$Q" && PATH="$BIN:$PATH" HOME="$T" env "$@" bash "$Q/hourly_notify.sh" 2>&1)"; RC=$?; BODY="$(cat "$CALLS/body" 2>/dev/null)"; N=0; [ -f "$CALLS/n" ] && N="$(wc -l < "$CALLS/n" | tr -d ' ')"; }
has(){ printf '%s' "$BODY" | grep -qF -- "$1" && echo 1 || echo 0; }
rm -f "$STUBD"/*

run NTFY_TOPIC=
ok "no topic -> exit 0, no curl" "$([ "$RC" = 0 ] && [ "$N" = 0 ] && echo 1 || echo 0)"
echo "tk" > "$Q/state/ntfy_topic"
run
ok "not notable (empty helper) -> silent exit 0" "$([ "$RC" = 0 ] && [ "$N" = 0 ] && echo 1 || echo 0)"

echo "NOTABLE: a fully-wasted hour" > "$STUBD/notable"
run
ok "notable only -> one push with reason (prefix stripped) and footer, no optional sections" "$([ "$N" = 1 ] && [ "$RC" = 0 ] && echo 1 || echo 0)$(has 'a fully-wasted hour')$(printf '%s' "$BODY" | grep -q 'NOTABLE:' && echo 0 || echo 1)$(has 'Fuller breakdown')"
echo "ONE-LINER" > "$STUBD/one"; echo "TIERS-T" > "$STUBD/tiers"; echo "LANDED-D" > "$STUBD/landed"; echo "FEAT-X" > "$STUBD/feat"
run
ok "all optional sections included in order" "$(printf '%s' "$BODY" | tr '\n' '~' | grep -q 'fully-wasted hour~~ONE-LINER~~TIERS-T~~LANDED-D~~FEAT-X~~(Fuller' && echo 1 || echo 0)"
run CURL_FAIL=1
ok "send failure: retried 3 times and returns nonzero (script exit 1)" "$([ "$N" = 3 ] && [ "$RC" = 1 ] && echo 1 || echo 0)"
ok "send failure message on stderr (skipped under coverage)" "$(printf '%s' "$OUT" | grep -q 'send() FAILED after 3 attempts' || [ -n "${OVN_COV_DIR:-}" ] && echo 1 || echo 0)"

echo "hourly_notify_more_paths: $P passed, $F failed"
[ "$F" = 0 ]
