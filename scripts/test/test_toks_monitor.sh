#!/usr/bin/env bash
# Regression test: ovn_toks_monitor.sh's whole reason for existing is to tell a REAL GPU/config
# regression apart from ordinary fleet contention. It must (a) alert only on a genuinely SOLO
# (uncontended) slow sample, (b) NEVER alert when the fleet was busy during the probe — that's
# just load, not a regression, (c) dedupe so it only alerts once per calendar day, and (d) still
# record every sample to state/toks.jsonl regardless of whether it alerts (2026-09-10).
set -uo pipefail
REAL="$HOME/overnight-queue"
SH="$REAL/ovn_toks_monitor.sh"
[ -f "$SH" ] || { echo "  SKIP: $SH not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
SANDBOX_HOME="$tmp/home"
OQ="$SANDBOX_HOME/overnight-queue"
mkdir -p "$OQ/state"
FAKEBIN="$tmp/fakebin"; mkdir -p "$FAKEBIN"
NTFYLOG="$tmp/ntfy_calls.log"; : > "$NTFYLOG"

# ovn_toks_monitor.sh never resets PATH itself, so a fakebin dir prepended in front of the real
# system dirs really does shadow curl/pgrep/nvidia-smi for the duration of the run.
cat > "$FAKEBIN/curl" <<'CURL_EOF'
#!/usr/bin/env bash
joined="$*"
if [[ "$joined" == *"/v1/chat/completions"* ]]; then
  sleep "${FAKE_CURL_SLEEP:-0}"
  printf '{"usage":{"completion_tokens": %s}}' "${FAKE_TOKENS:-150}"
  exit 0
elif [[ "$joined" == *"ntfy.sh"* ]]; then
  echo "NTFY: $joined" >> "$NTFYLOG_PATH"
  exit 0
fi
exit 1
CURL_EOF
cat > "$FAKEBIN/pgrep" <<'PGREP_EOF'
#!/usr/bin/env bash
echo "${FAKE_AIDERS:-0}"
exit 0
PGREP_EOF
cat > "$FAKEBIN/nvidia-smi" <<'NV_EOF'
#!/usr/bin/env bash
echo "0, 1234"
NV_EOF
chmod +x "$FAKEBIN/curl" "$FAKEBIN/pgrep" "$FAKEBIN/nvidia-smi"

run_monitor(){ # env FAKE_* set by caller
  NTFYLOG_PATH="$NTFYLOG" PATH="$FAKEBIN:$PATH" HOME="$SANDBOX_HOME" \
    LITELLM_BASE="http://unused" LITELLM_MASTER_KEY=x \
    FAKE_AIDERS="${FAKE_AIDERS:-0}" FAKE_TOKENS="${FAKE_TOKENS:-150}" FAKE_CURL_SLEEP="${FAKE_CURL_SLEEP:-0}" \
    NTFYLOG_PATH="$NTFYLOG" \
    bash "$SH" 2>&1
}
ntfy_count(){ wc -l < "$NTFYLOG" | tr -d ' '; }

# === A: healthy SOLO sample (fast, no contention) -> no alert, sample recorded ===
: > "$OQ/state/toks.jsonl"; rm -f "$OQ/state/toks_alerted"; : > "$NTFYLOG"
FAKE_AIDERS=0 FAKE_TOKENS=150 FAKE_CURL_SLEEP=0.05 OVN_TOKS_FLOOR=38 run_monitor >/dev/null
ok "A: sample recorded to toks.jsonl" "[ -s '$OQ/state/toks.jsonl' ]"
ok "A: sample correctly labeled NOT contended (it was a true solo probe)" \
   "grep -q '\"contended\":false' '$OQ/state/toks.jsonl'"
ok "A: no alert fired for a healthy fast solo sample" "[ \"\$(ntfy_count)\" -eq 0 ]"
ok "A: no toks_alerted marker written" "[ ! -f '$OQ/state/toks_alerted' ]"

# === B: contended sample (fleet aider running) that is ALSO slow -> must NOT alert (load, not a bug) ===
: > "$OQ/state/toks.jsonl"; rm -f "$OQ/state/toks_alerted"; : > "$NTFYLOG"
FAKE_AIDERS=1 FAKE_TOKENS=20 FAKE_CURL_SLEEP=1 OVN_TOKS_FLOOR=100 run_monitor >/dev/null
ok "B: sample correctly labeled contended" "grep -q '\"contended\":true' '$OQ/state/toks.jsonl'"
ok "B: NO alert on a slow but contended sample (this is the core guard this script exists for)" \
   "[ \"\$(ntfy_count)\" -eq 0 ]"
ok "B: no toks_alerted marker written on a contended sample" "[ ! -f '$OQ/state/toks_alerted' ]"

# === C: a genuine SOLO regression (slow AND uncontended) -> DOES alert, exactly once ===
: > "$OQ/state/toks.jsonl"; rm -f "$OQ/state/toks_alerted"; : > "$NTFYLOG"
FAKE_AIDERS=0 FAKE_TOKENS=20 FAKE_CURL_SLEEP=1 OVN_TOKS_FLOOR=100 run_monitor >/dev/null
ok "C: alert fired for a real solo regression" "[ \"\$(ntfy_count)\" -eq 1 ]"
ok "C: alert title mentions the SOLO framing (not a generic slowdown claim)" \
   "grep -q 'SOLO' '$NTFYLOG'"
ok "C: toks_alerted marker written with today's date" \
   "[ \"\$(cat '$OQ/state/toks_alerted')\" = \"\$(date +%F)\" ]"

# === D: a second regression sample on the SAME day must NOT alert again (dedup) ===
: > "$NTFYLOG"
FAKE_AIDERS=0 FAKE_TOKENS=20 FAKE_CURL_SLEEP=1 OVN_TOKS_FLOOR=100 run_monitor >/dev/null
ok "D: no second alert the same day (dedup by date)" "[ \"\$(ntfy_count)\" -eq 0 ]"
ok "D: the sample is still recorded even though it doesn't re-alert" \
   "[ \"\$(wc -l < "$OQ/state/toks.jsonl" | tr -d ' ')\" -eq 2 ]"

# === E: a regression on a NEW day (marker is stale) DOES alert again ===
echo "2020-01-01" > "$OQ/state/toks_alerted"
: > "$NTFYLOG"
FAKE_AIDERS=0 FAKE_TOKENS=20 FAKE_CURL_SLEEP=1 OVN_TOKS_FLOOR=100 run_monitor >/dev/null
ok "E: stale (yesterday's) marker does not suppress today's real regression" "[ \"\$(ntfy_count)\" -eq 1 ]"

echo "Toks monitor: $P passed, $F failed"
rm -rf "$tmp"
[ "$F" -eq 0 ]
