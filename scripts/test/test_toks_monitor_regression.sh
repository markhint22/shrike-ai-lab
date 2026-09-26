#!/usr/bin/env bash
# Regression test for ovn_toks_monitor.sh's rolling-baseline regression detector (the
# 2026-09-26 redesign — the old "solo sample" gate never once fired in 3 weeks of real
# production history, so its alert path had never actually been exercised).
#
# Sandboxed: fake `curl` (controllable completion-token count + a small real delay so the
# tok/s division is meaningful, and it distinguishes the litellm completion call from the
# ntfy alert POST by URL) and a fake HOME (state/logs are throwaway). Real `sleep`/`bc`/
# `jq`/`python3`/`nvidia-smi`(faked, trivial) are used since this script's core logic IS
# real-time-based division — faking sleep away would make every reading's denominator ~0.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${OVN_TOKS_MONITOR:-}" ]; then
  M="$OVN_TOKS_MONITOR"
else
  M="$HERE/../../ovn_toks_monitor.sh"; [ -f "$M" ] || M="$HERE/../ovn_toks_monitor.sh"; [ -f "$M" ] || M="$HERE/ovn_toks_monitor.sh"
fi
[ -f "$M" ] || { echo "  SKIP: ovn_toks_monitor.sh not found"; exit 0; }

rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/overnight-queue/state"
cp "$M" "$tmp/home/overnight-queue/ovn_toks_monitor.sh"

# fake curl: completion calls return FAKE_TOKENS after a short real delay (FAKE_DELAY);
# ntfy calls are just logged. Distinguishes by URL (last arg).
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
url="${@: -1}"
case "$url" in
  *ntfy.sh*) echo "ALERT_CALL $*" >> "$FAKE_NTFY_LOG"; exit 0 ;;
  *)
    sleep "${FAKE_DELAY:-0.1}"
    printf '{"usage":{"completion_tokens":%s}}' "${FAKE_TOKENS:-100}"
    ;;
esac
EOF
chmod +x "$tmp/bin/curl"

cat > "$tmp/bin/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
echo "50, 20000"
EOF
chmod +x "$tmp/bin/nvidia-smi"

cat > "$tmp/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
echo 0
EOF
chmod +x "$tmp/bin/pgrep"

export PATH="$tmp/bin:$PATH"
export HOME="$tmp/home"
export FAKE_NTFY_LOG="$tmp/ntfy.log"
cd "$HOME/overnight-queue"

run_probe(){ # $1=fake_tokens $2=fake_delay
  FAKE_TOKENS="$1" FAKE_DELAY="$2" bash ovn_toks_monitor.sh >/tmp/toks_probe_out.txt 2>&1
}

seed_history(){ # $1=tok_s value to repeat, $2=count, all within the baseline window
  python3 -c "
import json
from datetime import datetime, timedelta, timezone
now = datetime.now(timezone.utc)
with open('state/toks.jsonl', 'a') as f:
    for i in range($2):
        t = now - timedelta(hours=i*2)
        f.write(json.dumps({'ts': t.strftime('%Y-%m-%dT%H:%M:%SZ'), 'tok_s_best': $1, 'aiders': 0, 'gpu': '0,20000'}) + '\n')
"
}

# ---- Test 1: insufficient history falls back to FLOOR, doesn't crash ----
run_probe 100 0.1   # ~1000 tok/s (100 tokens / ~0.1-0.3s incl. 4 attempts) - clearly healthy either way
[ -f state/toks.jsonl ] && ok "probe runs and writes a toks.jsonl record with thin/no history" || fail "no toks.jsonl written"
[ -f "$FAKE_NTFY_LOG" ] && fail "alerted on a healthy reading with insufficient history (should never alert)" || ok "no alert fired on a healthy reading with insufficient history"
rm -f state/toks.jsonl state/toks_rolling.txt

# ---- Test 2: sustained regression fires exactly once ----
seed_history 40 25          # 25 historical readings at 40 tok/s -> median baseline = 40
printf '15\n15\n15\n15\n15\n' > state/toks_rolling.txt   # 5 already-low readings pre-seeded
run_probe 3 1.0              # 3 tokens / ~4-5s (4 attempts * (1s delay + 1s sleep)) ≈ well under 40*0.5=20
grep -q "ALERT_CALL" "$FAKE_NTFY_LOG" 2>/dev/null && ok "sustained regression (6/6 low readings) fires an alert" || fail "sustained regression did NOT alert"
[ "$(cat state/toks_alerted 2>/dev/null)" = "$(date +%F)" ] && ok "toks_alerted dedup marker set to today" || fail "toks_alerted marker not set"
n1=$(wc -l < "$FAKE_NTFY_LOG")
run_probe 3 1.0               # same still-low reading again — dedup should suppress a second alert same day
n2=$(wc -l < "$FAKE_NTFY_LOG")
[ "$n1" -eq "$n2" ] && ok "repeat sustained-low reading does not re-alert same day (dedup)" || fail "re-alerted same day despite dedup"

# ---- Test 3: recovery clears the dedup marker ----
run_probe 100 0.05           # a fast/healthy reading breaks "all 6 below threshold"
[ -f state/toks_alerted ] && fail "toks_alerted marker not cleared after recovery" || ok "recovery clears the dedup marker"

# ---- Test 4: a single blip among otherwise-healthy readings does NOT alert ----
rm -f state/toks.jsonl state/toks_rolling.txt "$FAKE_NTFY_LOG"
seed_history 40 25
printf '38\n42\n39\n41\n40\n' > state/toks_rolling.txt   # 5 healthy readings
run_probe 3 1.0               # one bad reading — window is now [38,42,39,41,40,~low] — NOT all-below
[ -f "$FAKE_NTFY_LOG" ] && fail "alerted on a single blip (5 healthy + 1 bad) — should require ALL 6 low" || ok "a single blip among healthy readings does not alert"

# ---- Test 5: PAUSED is respected — no probe call at all ----
rm -f state/toks.jsonl state/toks_rolling.txt "$FAKE_NTFY_LOG" /tmp/curl_calls.log
touch state/PAUSED
FAKE_TOKENS=100 FAKE_DELAY=0.05 bash ovn_toks_monitor.sh > /tmp/toks_paused_out.txt 2>&1
grep -q "paused" /tmp/toks_paused_out.txt && ok "PAUSED short-circuits before any probe" || fail "did not respect state/PAUSED"
[ -f state/toks.jsonl ] && fail "wrote a toks.jsonl record while paused" || ok "no toks.jsonl record written while paused"
rm -f state/PAUSED

[ $rc -eq 0 ] && echo "  toks-monitor rolling baseline: ALL PASS" || echo "  toks-monitor rolling baseline: FAILURES"
exit $rc
