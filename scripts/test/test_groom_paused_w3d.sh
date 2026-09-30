#!/usr/bin/env bash
# Wave-3: groom.sh must skip the ENTIRE run (before touching the LLM) when state/PAUSED exists.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/../../groom.sh"; [ -f "$G" ] || G="$HERE/../groom.sh"
[ -f "$G" ] || { echo "  SKIP: groom.sh not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/q/state" "$tmp/bin"
touch "$tmp/q/state/PAUSED"
printf '#!/bin/sh\necho curl-was-called >> "%s/curl.calls"\nexit 1\n' "$tmp" > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
out="$(PATH="$tmp/bin:$PATH" OVERNIGHT_DIR="$tmp/q" bash "$G" 2>&1)"; rc=$?
ok "paused run exits 0" "[ $rc = 0 ]"
ok "paused run says so and names the PAUSED file" "echo \"$out\" | grep -q 'Queue is paused'"
ok "paused run never probes LiteLLM" "[ ! -f '$tmp/curl.calls' ]"
ok "paused run writes no grooming_pending" "[ ! -f '$tmp/q/state/grooming_pending' ]"
ok "paused run creates no report" "[ -z \"\$(ls '$tmp/q/reports')\" ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
