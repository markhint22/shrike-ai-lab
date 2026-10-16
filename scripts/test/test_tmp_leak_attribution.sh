#!/usr/bin/env bash
# 2026-10-15 regression: the 2026-10-14 night reported "test suite left 413022 entries in its private TMPDIR" with no hint which test leaked them.
# lib_tmp_isolation.sh's cleanup now also names the top-level entries holding the most files (tmp-leak-top lines). Drives the real cleanup
# function against a synthetic run root; a mutant without the attribution block fails the assertions below.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/lib_tmp_isolation.sh"
[ -f "$LIB" ] || { echo "  FAIL: $LIB missing"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
. "$LIB"
ROOT="$T/base/run.4242"; mkdir -p "$ROOT"
mkdir -p "$ROOT/bigleak.AbCdEf"; for i in $(seq 1 50); do : > "$ROOT/bigleak.AbCdEf/f$i"; done
mkdir -p "$ROOT/small.XyZwQr"; : > "$ROOT/small.XyZwQr/a"; : > "$ROOT/small.XyZwQr/b"

OUT="$(OVN_TMP_ROOT="$ROOT" OVN_ALERTS_FILE="$T/nostate/alerts.log" __ovn_tmp_cleanup 2>&1)"
echo "=== leak total and attribution ==="
ok "reports the total" "$(printf '%s' "$OUT" | grep -q 'tmp-leak: ' && echo 1 || echo 0)"
ok "names the biggest leaker first (bigleak.AbCdEf, 51 entries incl. its dir)" "$(printf '%s' "$OUT" | grep -n 'tmp-leak-top' | head -1 | grep -q "51 entries under 'bigleak.AbCdEf'" && echo 1 || echo 0)"
ok "names the smaller entry second" "$(printf '%s' "$OUT" | grep 'tmp-leak-top' | sed -n 2p | grep -q "3 entries under 'small.XyZwQr'" && echo 1 || echo 0)"
ok "root removed after the report" "$([ ! -d "$ROOT" ] && echo 1 || echo 0)"

echo "=== an empty root reports no attribution lines ==="
ROOT2="$T/base/run.4243"; mkdir -p "$ROOT2"
OUT2="$(OVN_TMP_ROOT="$ROOT2" OVN_ALERTS_FILE="$T/nostate/alerts.log" __ovn_tmp_cleanup 2>&1)"
ok "empty root has no tmp-leak-top line" "$(printf '%s' "$OUT2" | grep -q 'tmp-leak-top' && echo 0 || echo 1)"

echo "=== a leaker sorted past the 300th top-level entry is still named (no cap) ==="
# 2026-10-15: the attribution used to scan only the first 300 top-level entries in glob order, so a leaker sorted after them was never named.
ROOT3="$T/base/run.4244"; mkdir -p "$ROOT3"
for i in $(seq 1 350); do mkdir -p "$ROOT3/aaa_$(printf '%03d' "$i")"; : > "$ROOT3/aaa_$(printf '%03d' "$i")/x"; done
mkdir -p "$ROOT3/zz_leaker"; for i in $(seq 1 60); do : > "$ROOT3/zz_leaker/f$i"; done
OUT3="$(OVN_TMP_ROOT="$ROOT3" OVN_ALERTS_FILE="$T/nostate/alerts.log" __ovn_tmp_cleanup 2>&1)"
ok "names zz_leaker (sorted after 350 small dirs) with its full count" "$(printf '%s' "$OUT3" | grep -q "tmp-leak-top: 61 entries under 'zz_leaker'" && echo 1 || echo 0)"
ok "still bounded: at most 5 attribution lines" "$([ "$(printf '%s' "$OUT3" | grep -c 'tmp-leak-top')" -le 5 ] && echo 1 || echo 0)"

echo; echo "$P passed, $F failed"; [ "$F" -eq 0 ]
