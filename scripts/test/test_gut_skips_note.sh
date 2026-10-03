#!/usr/bin/env bash
# gut_log_skips_note (lib_gut_xml.sh): shadow warning when GUT silently skips/ fails to parse test scripts but exits green. Never blocks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; LIB="$HERE/../lib_gut_xml.sh"
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; mkdir -p "$T/state"
source "$LIB"
printf 'Running\nIgnoring script res://tests/a.gd because it does not extend GutTest\nPassing 3\n' > "$T/bad.log"
printf 'Running\nPassing 3\n' > "$T/clean.log"
gut_log_skips_note "$T/clean.log" xlite "$T/state"; rc=$?
ok "BENIGN: a clean log writes no alert and returns 0" "$([ $rc = 0 ] && [ ! -s "$T/state/alerts.log" ] && echo 1 || echo 0)"
gut_log_skips_note "$T/bad.log" xlite "$T/state"; rc=$?
ok "NEGATIVE: 'Ignoring script' -> one gut-skips warn line naming the script, rc 0 (never blocks)" "$([ $rc = 0 ] && grep -c 'gut-skips:xlite' "$T/state/alerts.log" | grep -qx 1 && grep -q 'a.gd' "$T/state/alerts.log" && echo 1 || echo 0)"
gut_log_skips_note "$T/bad.log" xlite "$T/state"
ok "dedup: the same skip set does not alert twice" "$([ "$(grep -c 'gut-skips:xlite' "$T/state/alerts.log")" = 1 ] && echo 1 || echo 0)"
printf 'Parse Error: res://x.gd:3\n' > "$T/bad2.log"; gut_log_skips_note "$T/bad2.log" xlite "$T/state"
ok "a different skip set alerts again" "$([ "$(grep -c 'gut-skips:xlite' "$T/state/alerts.log")" = 2 ] && echo 1 || echo 0)"
gut_log_skips_note "$T/missing.log" xlite "$T/state"; r1=$?; gut_log_skips_note "$T/bad.log" xlite "$T/nodir"; r2=$?
ok "missing log / missing state dir: silent, rc 0" "$([ $r1 = 0 ] && [ $r2 = 0 ] && echo 1 || echo 0)"
echo "gut skips note: $P passed, $F failed"; [ "$F" = 0 ]
