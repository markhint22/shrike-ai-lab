#!/usr/bin/env bash
# Runs the REAL ovn_toks_monitor.sh with a DETERMINISTIC clock: an exported `date` function feeds the script's two
# `date +%s.%N` reads per probe a controlled elapsed time, so tok/s = 150 / DT is exact and no real sleeping is needed
# (sleep is stubbed). Covers PAUSED, failed probe, thin-history FLOOR fallback, computed median baseline (incl. malformed /
# old / ts-less history rows), window-not-full, alert + same-day dedupe + recovery, zero baseline, pgrep/nvidia-smi variants.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
M=""
for c in "$HERE/../../ovn_toks_monitor.sh" "$HERE/../ovn_toks_monitor.sh" "$HERE/ovn_toks_monitor.sh"; do [ -f "$c" ] && { M="$c"; break; }; done
[ -n "$M" ] || { echo "  SKIP: ovn_toks_monitor.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
H="$T/home"; Q="$H/overnight-queue"; BIN="$T/bin"; NTFY="$T/ntfy.log"; CNT="$T/date.cnt"; DTF="$T/date.dt"
mkdir -p "$Q/state" "$BIN"; cp "$M" "$Q/ovn_toks_monitor.sh"; : > "$NTFY"; export NTFY CNT DTF

date(){
  if [ "${1:-}" = "+%s.%N" ]; then
    local n; n=$(( $(command cat "$CNT" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CNT"
    if [ $((n % 2)) = 1 ]; then echo "1000.0"; else echo "1000 + $(command cat "$DTF")" | bc; fi
  else command date "$@"; fi
}
export -f date
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
url="${@: -1}"
case "$url" in
  *ntfy.sh*) title=""; prev=""; for a in "$@"; do [ "$prev" = "-H" ] && case "$a" in Title:*) title="$a";; esac; prev="$a"; done; echo "$title" >> "$NTFY"; exit 0;;
  *) [ -n "${FAKE_FAIL:-}" ] && exit 22
     printf '{"usage":{"completion_tokens":%s}}' "${FAKE_TOKENS:-150}";;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/sleep"
cat > "$BIN/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_NOGPU:-}" ] && exit 9
echo "50, 20000"
EOF
cat > "$BIN/pgrep" <<'EOF'
#!/usr/bin/env bash
n="${FAKE_AIDERS:-0}"; echo "$n"; [ "$n" = 0 ] && exit 1; exit 0
EOF
chmod +x "$BIN"/*

# probe <speed tok/s> [env...] : runs one monitor pass where every one of the 4 probes measures <speed> tok/s
probe(){
  local speed="$1"; shift
  echo "scale=6; 150/$speed" | bc > "$DTF"; rm -f "$CNT"
  OUT="$(cd "$Q" && HOME="$H" PATH="$BIN:$PATH" LITELLM_BASE=http://fake.invalid NTFY_TOPIC=tk env "$@" bash ovn_toks_monitor.sh 2>&1)"; RC=$?
}
alerts(){ local c; c="$(grep -c 'speed regression' "$NTFY" 2>/dev/null)"; echo "${c:-0}"; }
seed(){ # $1=value $2=count : recent valid samples (2h apart)
  python3 - "$1" "$2" "$Q/state/toks.jsonl" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone
v, n, path = float(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
now = datetime.now(timezone.utc)
with open(path, "a") as f:
    for i in range(1, n + 1):
        f.write(json.dumps({"ts": (now - timedelta(hours=i)).strftime("%Y-%m-%dT%H:%M:%SZ"), "tok_s_best": v}) + "\n")
PY
}
fresh(){ rm -f "$Q"/state/toks.jsonl "$Q"/state/toks_rolling.txt "$Q"/state/toks_alerted "$Q"/state/PAUSED; : > "$NTFY"; }

# ---- 1. PAUSED: no probe, no record ----
fresh; touch "$Q/state/PAUSED"
probe 40
# NOTE: the coverage harness's BASH_ENV hook (cov_env.sh: `exec 97>>f 2>/dev/null`) permanently discards stderr of every
# instrumented bash process, so the stderr message can only be asserted outside coverage runs.
ok "PAUSED: exit 0, says paused" "$([ "$RC" = 0 ] && { printf '%s' "$OUT" | grep -q 'queue is paused' || [ -n "${OVN_COV_DIR:-}" ]; } && echo 1 || echo 0)"
ok "PAUSED: no toks.jsonl written" "$([ ! -f "$Q/state/toks.jsonl" ] && echo 1 || echo 0)"
rm -f "$Q/state/PAUSED"

# ---- 2. probe failure: best=0, recorded, rolling untouched ----
fresh
probe 40 FAKE_FAIL=1
ok "failed probe: logs best=0" "$(printf '%s' "$OUT" | grep -q 'best=0 ' && echo 1 || echo 0)"
ok "failed probe: a zero record is still appended to toks.jsonl" "$(grep -q '"tok_s_best":0,' "$Q/state/toks.jsonl" && echo 1 || echo 0)"
ok "failed probe: rolling window untouched" "$([ ! -f "$Q/state/toks_rolling.txt" ] && echo 1 || echo 0)"
probe 40 FAKE_TOKENS=0
ok "zero completion_tokens treated as failed probe" "$([ ! -f "$Q/state/toks_rolling.txt" ] && echo 1 || echo 0)"

# ---- 3. healthy probe records exact tok/s, aiders + gpu columns ----
fresh
probe 40 FAKE_AIDERS=3
ok "healthy probe: best=40.0 logged" "$(printf '%s' "$OUT" | grep -q 'best=40.0 aiders=3 gpu=50,20000' && echo 1 || echo 0)"
ok "healthy probe: toks.jsonl row has tok_s_best/aiders/gpu" "$(tail -1 "$Q/state/toks.jsonl" | jq -e '.tok_s_best==40 and .aiders==3 and .gpu=="50,20000"' >/dev/null && echo 1 || echo 0)"
ok "healthy probe: rolling window has 1 reading" "$([ "$(wc -l < "$Q/state/toks_rolling.txt" | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
probe 40
ok "pgrep exiting 1 with '0' output -> aiders=0 (no doubled value)" "$(printf '%s' "$OUT" | grep -q 'aiders=0 ' && echo 1 || echo 0)"
probe 40 FAKE_NOGPU=1
ok "nvidia-smi failing -> empty gpu field, script continues" "$(printf '%s' "$OUT" | grep -q 'gpu=$' && echo 1 || echo 0)"

# ---- 4. window not full -> never alerts even when low ----
fresh
probe 5
ok "window not full (1 of 6 readings): no alert even at 5 tok/s" "$([ "$(alerts)" = 0 ] && echo 1 || echo 0)"

# ---- 5. thin history -> FLOOR fallback (20 -> threshold 10); sustained low alerts once per day; recovery re-arms ----
fresh; printf '5\n5\n5\n5\n5\n' > "$Q/state/toks_rolling.txt"
probe 5
ok "sustained low vs FLOOR baseline -> one alert" "$([ "$(alerts)" = 1 ] && echo 1 || echo 0)"
ok "alert title carries best + baseline" "$(grep -q 'Title: 27B speed regression: 5.0 tok/s (baseline 20)' "$NTFY" && echo 1 || echo 0)"
ok "toks_alerted set to today" "$([ "$(cat "$Q/state/toks_alerted")" = "$(command date +%F)" ] && echo 1 || echo 0)"
probe 5
ok "same-day repeat: deduped" "$([ "$(alerts)" = 1 ] && echo 1 || echo 0)"
probe 40
ok "one healthy reading breaks the all-below condition" "$([ "$(alerts)" = 1 ] && echo 1 || echo 0)"
ok "recovery removes the dedupe marker" "$([ ! -f "$Q/state/toks_alerted" ] && echo 1 || echo 0)"
printf '5\n5\n5\n5\n5\n' > "$Q/state/toks_rolling.txt"; probe 5
ok "after recovery a new regression can alert again the same day" "$([ "$(alerts)" = 2 ] && echo 1 || echo 0)"
ok "rolling file trimmed to the window size" "$([ "$(wc -l < "$Q/state/toks_rolling.txt" | tr -d ' ')" = 6 ] && echo 1 || echo 0)"

# ---- 6. computed median baseline (>=20 valid recent samples), junk rows ignored ----
fresh
{ echo 'not json'; echo ''; echo '{"tok_s_best":99}'; echo '{"ts":"garbage","tok_s_best":99}'
  echo '{"ts":"2020-01-01T00:00:00Z","tok_s_best":99}'; echo '{"ts":"'"$(command date -u +%FT%TZ)"'","tok_s_best":0}'; } > "$Q/state/toks.jsonl"
seed 40 24
printf '15\n15\n15\n15\n15\n' > "$Q/state/toks_rolling.txt"
probe 15
ok "computed baseline (median 40, ratio .5 -> 20): 6 readings at 15 alert" "$([ "$(alerts)" = 1 ] && grep -q 'baseline 40' "$NTFY" && echo 1 || echo 0)"
rm -f "$Q/state/toks_alerted"; : > "$NTFY"
printf '15\n15\n15\n15\n15\n' > "$Q/state/toks_rolling.txt"
probe 30
ok "reading above threshold (30 > 20) does not alert" "$([ "$(alerts)" = 0 ] && echo 1 || echo 0)"
ok "python baseline ignored junk/old/ts-less/zero rows (median stays 40)" "$(! grep -q 'baseline 99' "$NTFY" && echo 1 || echo 0)"

# ---- 7. env-tunable thresholds; zero baseline skips the comparison ----
fresh; printf '5\n5\n5\n5\n5\n' > "$Q/state/toks_rolling.txt"
probe 5 OVN_TOKS_FLOOR=0
ok "FLOOR=0 and thin history -> baseline 0 -> comparison skipped" "$([ "$(alerts)" = 0 ] && echo 1 || echo 0)"
fresh; printf '5\n5\n' > "$Q/state/toks_rolling.txt"
probe 5 OVN_TOKS_ROLLING_WINDOW=3
ok "custom ROLLING_WINDOW=3 fires with 3 low readings" "$([ "$(alerts)" = 1 ] && echo 1 || echo 0)"

# ---- 8. missing install dir ----
OUT="$(HOME="$T/none" bash "$M" 2>&1)"; RC=$?
ok "missing \$HOME/overnight-queue exits 1" "$([ "$RC" = 1 ] && echo 1 || echo 0)"

echo "ovn_toks_monitor_run: $P passed, $F failed"
[ "$F" = 0 ]
