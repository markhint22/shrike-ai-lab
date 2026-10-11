#!/usr/bin/env bash
# docs/patches/overnight-queue.service.d-wait-litellm.conf (PROPOSED systemd drop-in, not installed; review F5): the unit waits (bounded) for LiteLLM instead of burning 10 restarts after a boot.
# Static properties + the real ExecStartPre command run against a stub curl (bounded wait, immediate when LiteLLM is up, never fatal) + systemd-analyze verify when available.
# Mutation section: each rule is broken in a temp copy of the file and check_conf must then fail.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OQ="$(cd "$HERE/../.." && pwd)"
CONF=""
for c in "${WAIT_CONF:-/nonexistent}" "$OQ/../../docs/patches/overnight-queue.service.d-wait-litellm.conf" "$OQ/docs/patches/overnight-queue.service.d-wait-litellm.conf"; do [ -f "$c" ] && { CONF="$c"; break; }; done
[ -n "$CONF" ] || { echo "  SKIP: overnight-queue.service.d-wait-litellm.conf not installed here"; exit 0; }
TO="$(command -v timeout || command -v gtimeout || true)"
P=0; F=0; QUIET=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); [ "$QUIET" = 1 ] || echo "  FAIL: $1"; fi; }
T="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$T"' EXIT

# check_conf FILE LABEL : every property of the drop-in
check_conf(){
  local f="$1" l="${2:-}" pre secs tmo
  pre="$(grep '^ExecStartPre=' "$f" | head -1)"; printf '%s' "$pre" > "$T/pre"       # asserted from a FILE: the command itself contains single quotes
  ok "${l}has exactly one ExecStartPre" "[ \"\$(grep -c '^ExecStartPre=' '$f')\" = 1 ]"
  ok "${l}ExecStartPre is NON-fatal (leading '-': a LiteLLM still down after the wait must not keep the unit down; run_overnight aborts itself as today)" "grep -q '^ExecStartPre=-/' '$T/pre'"
  ok "${l}waits for the SAME endpoint run_overnight.sh probes (localhost:4000/health/liveliness)" "grep -q 'localhost:4000/health/liveliness' '$T/pre'"
  ok "${l}each probe has its own --max-time (a hung curl cannot stall the loop)" "grep -q -- '--max-time' '$T/pre'"
  ok "${l}the whole wait is bounded by timeout(1)" "grep -qE 'timeout [0-9]+ ' '$T/pre'"
  tmo="$(printf '%s' "$pre" | sed -n 's/.*timeout \([0-9][0-9]*\) .*/\1/p')"
  secs="$(sed -n 's/^TimeoutStartSec=\([0-9][0-9]*\)$/\1/p' "$f" | head -1)"
  ok "${l}TimeoutStartSec is set and exceeds the wait (default 90 s would kill a 300 s wait)" "[ -n '$secs' ] && [ -n '$tmo' ] && [ '${secs:-0}' -gt '${tmo:-9999}' ]"
  ok "${l}a drop-in must not replace ExecStart / Restart / RestartSec" "! grep -qE '^(ExecStart=|Restart=|RestartSec=)' '$f'"
  ok "${l}orders after docker.service" "grep -q '^After=.*docker.service' '$f'"
  ok "${l}file says it is NOT installed and how to roll back" "grep -q 'NOT INSTALLED' '$f' && grep -q 'Roll back' '$f'"
}
check_conf "$CONF"
if [ -f "$OQ/run_overnight.sh" ]; then
  ok "run_overnight.sh really probes /health/liveliness on localhost:4000 (the drop-in waits for what the script checks)" "grep -q 'LITELLM_BASE=\"http://localhost:4000\"' '$OQ/run_overnight.sh' && grep -q 'LITELLM_BASE}/health/liveliness' '$OQ/run_overnight.sh'"
fi

# ---- run the REAL ExecStartPre command (paths swapped for the test host: timeout binary, a short sleep, a stub curl)
if [ -z "$TO" ]; then echo "  SKIP (functional part): no timeout/gtimeout on this host"; else
  CMD="$(grep '^ExecStartPre=' "$CONF" | head -1 | sed 's/^ExecStartPre=-//')"
  mkdir -p "$T/bin"
  cat > "$T/bin/curl" <<STUB
#!/bin/sh
n=\$(cat "$T/n" 2>/dev/null || echo 0); n=\$((n+1)); echo \$n > "$T/n"
echo "\$*" >> "$T/curl_args"
[ "\$n" -gt "\$(cat "$T/fail_first" 2>/dev/null || echo 0)" ]
STUB
  chmod +x "$T/bin/curl"
  runcmd(){ # \$1 = timeout seconds
    local c="$CMD"; c="${c/\/usr\/bin\/timeout 300/$TO $1}"; c="${c//sleep 3/sleep 0.05}"
    ( PATH="$T/bin:$PATH" bash -c "$c" )
  }
  rm -f "$T/n" "$T/fail_first" "$T/curl_args"; echo 0 > "$T/fail_first"
  s=$(date +%s); runcmd 20; rc=$?; e=$(( $(date +%s) - s ))
  ok "LiteLLM already up: the wait returns 0 at once after ONE probe" "[ '$rc' = 0 ] && [ \"\$(cat '$T/n')\" = 1 ] && [ '$e' -le 2 ]"
  ok "the probe URL and --max-time reach curl" "grep -q 'localhost:4000/health/liveliness' '$T/curl_args' && grep -q -- '--max-time 5' '$T/curl_args'"
  rm -f "$T/n" "$T/curl_args"; echo 4 > "$T/fail_first"
  runcmd 20; rc=$?
  ok "LiteLLM comes up after 4 failed probes: returns 0 after exactly 5 probes (a poll loop, not 10 unit restarts)" "[ '$rc' = 0 ] && [ \"\$(cat '$T/n')\" = 5 ]"
  rm -f "$T/n" "$T/curl_args"; echo 1000000 > "$T/fail_first"
  s=$(date +%s); runcmd 2; rc=$?; e=$(( $(date +%s) - s ))
  ok "LiteLLM NEVER up: the wait is bounded by timeout (non-zero exit, within seconds) - with the '-' prefix the unit then starts anyway" "[ '$rc' -ne 0 ] && [ '$e' -le 6 ]"
fi

# ---- systemd-analyze verify of the drop-in merged into a scratch unit (Linux hosts with systemd only)
if command -v systemd-analyze >/dev/null 2>&1 && [ -x /usr/bin/timeout ] && [ -x /bin/bash ]; then
  { echo "[Unit]"; echo "Description=scratch"; echo "[Service]"; echo "Type=simple"; echo "ExecStart=/bin/true"; grep -vE '^(#|\[Unit\]|\[Service\]|$)' "$CONF" | grep -E '^(ExecStartPre|TimeoutStartSec)'; echo "[Install]"; echo "WantedBy=multi-user.target"; } > "$T/scratch.service"
  ok "systemd-analyze verify accepts the drop-in's directives in a scratch unit" "systemd-analyze verify '$T/scratch.service'"
fi

# ---- mutation proofs: break each rule in a temp copy; check_conf must report failures
if [ -z "${WAITCONF_SKIP_MUTATION:-}" ]; then
  mut(){ # label  sed-expr
    local m="$T/mut.conf"; sed -e "$2" "$CONF" > "$m"
    if cmp -s "$m" "$CONF"; then P=$((P)); F=$((F+1)); echo "  FAIL: mutation anchor not found: $1"; return; fi
    local p0=$P f0=$F; QUIET=1; check_conf "$m" "[mut] "; QUIET=0
    local caught=$(( F > f0 )); P=$p0; F=$f0
    ok "mutation CAUGHT: $1" "[ '$caught' = 1 ]"
  }
  mut "ExecStartPre made fatal (dash removed)" 's#^ExecStartPre=-/#ExecStartPre=/#'
  mut "TimeoutStartSec removed" '/^TimeoutStartSec=/d'
  mut "TimeoutStartSec shorter than the wait" 's#^TimeoutStartSec=.*#TimeoutStartSec=60#'
  mut "wrong endpoint" 's#health/liveliness#health/liveness#'
  mut "no per-probe --max-time" 's# --max-time 5##'
  mut "unbounded wait (timeout removed)" 's#/usr/bin/timeout 300 ##'
  mut "drop-in overrides RestartSec" 's#^TimeoutStartSec=330#TimeoutStartSec=330\nRestartSec=20#'
  mut "ordering after docker.service dropped" 's#^After=docker.service #After=#'
fi
echo "test_wait_litellm_dropin: $P passed, $F failed"
[ "$F" -eq 0 ]
