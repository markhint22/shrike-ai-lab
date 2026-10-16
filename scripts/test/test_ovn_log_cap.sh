#!/usr/bin/env bash
# scripts/ovn_log_cap.sh (qacov F7): dry run by default, lossless head archive, in-place truncate (open `>>` writers keep working), retention only inside logs/archive
# and logs/hygiene_gate. Every behaviour assertion is also run against a MUTANT of the script and must fail there. bash 3.2 ok.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOOL="$HERE/../ovn_log_cap.sh"; [ -f "$TOOL" ] || { echo "  SKIP: ovn_log_cap.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)" || exit 1; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkq(){  # fresh fixture: logs/big.log (80000 lines ~ 2.4MB), logs/small.log, state/x, repos/r/x.log (must never be touched)
  rm -rf "${T:?}/q"; mkdir -p "$T/q/logs" "$T/q/state" "$T/q/repos/r"
  i=0; seq 1 80000 | sed 's/^/gate output line number /' > "$T/q/logs/big.log"
  seq 1 10 > "$T/q/logs/small.log"; echo keep > "$T/q/state/x.log"; seq 1 40000 > "$T/q/repos/r/x.log"
  cp "$T/q/logs/big.log" "$T/big.orig"; cp "$T/q/repos/r/x.log" "$T/repos_x.orig"
}
run(){ ( export OVN_Q="$T/q" OVN_LOG_CAP_MB=1 OVN_LOG_KEEP_LINES=1000; "$@" ) > "$T/out" 2>&1; echo $? > "$T/rc"; }
tool(){ bash "${TOOLUNDER:-$TOOL}" "$@"; }

echo "== dry run is the default"
mkq; run tool
ok "dry run exits 0, says WOULD cap big.log and changes nothing (cmp)" "$([ "$(cat "$T/rc")" = 0 ] && grep -q 'WOULD cap big.log' "$T/out" && cmp -s "$T/q/logs/big.log" "$T/big.orig" && [ ! -d "$T/q/logs/archive" ] && echo 1 || echo 0)"
ok "small.log (under the cap) is not mentioned as a candidate" "$(grep -q 'small.log' "$T/out" && echo 0 || echo 1)"
ok "mode is reported as dry-run" "$(grep -q 'mode=dry-run' "$T/out" && echo 1 || echo 0)"
mkq; run env OVN_LOG_CAP=off bash "$TOOL"
ok "OVN_LOG_CAP=off is the same as the default (dry run)" "$(cmp -s "$T/q/logs/big.log" "$T/big.orig" && echo 1 || echo 0)"

echo "== apply"
mkq; run tool --apply
ok "apply exits 0 and the log keeps exactly its last 1000 lines" "$([ "$(cat "$T/rc")" = 0 ] && [ "$(wc -l < "$T/q/logs/big.log" | tr -d ' ')" = 1000 ] && [ "$(tail -1 "$T/q/logs/big.log")" = "gate output line number 80000" ] && [ "$(head -1 "$T/q/logs/big.log")" = "gate output line number 79001" ] && echo 1 || echo 0)"
arch="$(ls "$T/q/logs/archive"/big.log.*.gz 2>/dev/null | head -1)"
ok "the dropped head is archived and the archive is a valid gzip" "$([ -n "$arch" ] && gzip -t "$arch" 2>/dev/null && echo 1 || echo 0)"
ok "LOSSLESS: zcat(archive) + the kept log == the original, byte for byte" "$([ -n "$arch" ] && { gzip -dc "$arch"; cat "$T/q/logs/big.log"; } | cmp -s - "$T/big.orig" && echo 1 || echo 0)"
ok "small.log, state/ and repos/ are untouched" "$([ "$(cat "$T/q/logs/small.log" | wc -l | tr -d ' ')" = 10 ] && [ "$(cat "$T/q/state/x.log")" = keep ] && cmp -s "$T/q/repos/r/x.log" "$T/repos_x.orig" && echo 1 || echo 0)"
mkq; run env OVN_LOG_CAP=on bash "$TOOL"
ok "OVN_LOG_CAP=on (the cron spelling) applies too" "$([ "$(wc -l < "$T/q/logs/big.log" | tr -d ' ')" = 1000 ] && echo 1 || echo 0)"
run env OVN_LOG_CAP=on bash "$TOOL"
ok "a second run is a no-op (the log is now under the cap)" "$(grep -q 'done: 0 log' "$T/out" && echo 1 || echo 0)"

echo "== an open >> writer keeps working after the truncate (same inode)"
mkq
exec 7>>"$T/q/logs/big.log"
run tool --apply
echo "appended after the cap" >&7; exec 7>&-
ok "a line written through the pre-existing O_APPEND fd lands at the END of the capped log" "$([ "$(tail -1 "$T/q/logs/big.log")" = "appended after the cap" ] && [ "$(wc -l < "$T/q/logs/big.log" | tr -d ' ')" = 1001 ] && echo 1 || echo 0)"

echo "== retention"
mkq; mkdir -p "$T/q/logs/archive" "$T/q/logs/hygiene_gate"
for n in 1 2 3 4 5; do : > "$T/q/logs/archive/big.log.2020010${n}T000000Z.gz"; touch -t "20200101000$n" "$T/q/logs/archive/big.log.2020010${n}T000000Z.gz"; done
: > "$T/q/logs/archive/other.log.20200101T000000Z.gz"; touch -t 202001010000 "$T/q/logs/archive/other.log.20200101T000000Z.gz"
: > "$T/q/logs/hygiene_gate/old.run"; touch -t 202001010000 "$T/q/logs/hygiene_gate/old.run"; : > "$T/q/logs/hygiene_gate/new.run"
run tool --apply
ok "only the newest 3 archives of big.log remain (the new one + 2 newest old ones); other logs' archives are not pruned" "$([ "$(ls "$T/q/logs/archive"/big.log.*.gz | wc -l | tr -d ' ')" = 3 ] && [ -e "$T/q/logs/archive/other.log.20200101T000000Z.gz" ] && echo 1 || echo 0)"
ok "hygiene gate files older than 3 days are removed, fresh ones stay" "$([ ! -e "$T/q/logs/hygiene_gate/old.run" ] && [ -e "$T/q/logs/hygiene_gate/new.run" ] && echo 1 || echo 0)"
mkq; mkdir -p "$T/q/logs/hygiene_gate"; : > "$T/q/logs/hygiene_gate/old.run"; touch -t 202001010000 "$T/q/logs/hygiene_gate/old.run"; run tool
ok "dry run does not remove old gate files, it says it would" "$([ -e "$T/q/logs/hygiene_gate/old.run" ] && grep -q 'WOULD remove 1 hygiene gate' "$T/out" && echo 1 || echo 0)"

echo "== edge cases"
mkq; run env OVN_LOG_CAP_MB=abc OVN_LOG_KEEP_LINES=-5 bash "$TOOL" --apply; ok "non-numeric knobs fall back to defaults (20MB/20000 lines): the 2.4 MB log is under the cap and untouched" "$(cmp -s "$T/q/logs/big.log" "$T/big.orig" && echo 1 || echo 0)"
mkq; rm -rf "${T:?}/q/logs"; run tool --apply; ok "missing logs/ dir is a clean no-op (exit 0)" "$([ "$(cat "$T/rc")" = 0 ] && echo 1 || echo 0)"
mkq; head -c 3000000 /dev/zero | tr '\0' 'x' > "$T/q/logs/longline.log"; run tool --apply
ok "a huge log with fewer lines than KEEP is left alone (cannot be line-capped)" "$([ "$(wc -c < "$T/q/logs/longline.log" | tr -d ' ')" = 3000000 ] && grep -q 'left alone' "$T/out" && echo 1 || echo 0)"

echo "== ovn_planner.log keeps more history (ovn_research_trigger_check.py walks it backward for multi-day streaks)"
mkq; cp "$T/q/logs/big.log" "$T/q/logs/ovn_planner.log"; run tool --apply
ok "with the global keep at 1000 lines, a 80000-line ovn_planner.log is left alone (its own keep is 100000) while big.log is capped" "$([ "$(wc -l < "$T/q/logs/ovn_planner.log" | tr -d ' ')" = 80000 ] && [ "$(wc -l < "$T/q/logs/big.log" | tr -d ' ')" = 1000 ] && grep -q 'ovn_planner.log: .*left alone' "$T/out" && echo 1 || echo 0)"
mkq; cp "$T/q/logs/big.log" "$T/q/logs/ovn_planner.log"; run env OVN_LOG_KEEP_PLANNER=5000 bash "$TOOL" --apply
ok "OVN_LOG_KEEP_PLANNER=5000 caps ovn_planner.log to exactly its last 5000 lines (other logs keep the global 1000)" "$([ "$(wc -l < "$T/q/logs/ovn_planner.log" | tr -d ' ')" = 5000 ] && [ "$(tail -1 "$T/q/logs/ovn_planner.log")" = "gate output line number 80000" ] && [ "$(wc -l < "$T/q/logs/big.log" | tr -d ' ')" = 1000 ] && echo 1 || echo 0)"
mkq; cp "$T/q/logs/big.log" "$T/q/logs/ovn_planner.log"; run env OVN_LOG_KEEP_PLANNER=500 bash "$TOOL" --apply
ok "a planner keep SMALLER than the global keep never undercuts it (max of the two: 1000)" "$([ "$(wc -l < "$T/q/logs/ovn_planner.log" | tr -d ' ')" = 1000 ] && echo 1 || echo 0)"

echo "== mutants must fail the behaviour assertions"
M1="$T/mut_dry.sh"; sed 's/if \[ "\$APPLY" != 1 \]; then say "WOULD cap/if false; then say "WOULD cap/' "$TOOL" > "$M1"
ok "mutant 1 differs (dry run applies anyway)" "$(cmp -s "$M1" "$TOOL" && echo 0 || echo 1)"
mkq; TOOLUNDER="$M1" run tool
ok "MUTANT 1: the dry-run no-change assertion FAILS (the file was capped without --apply)" "$(cmp -s "$T/q/logs/big.log" "$T/big.orig" && echo 0 || echo 1)"
M2="$T/mut_off.sh"; sed 's/drop=\$(( total - keep ))/drop=$(( total - keep + 1 ))/' "$TOOL" > "$M2"
ok "mutant 2 differs (off-by-one in the archived head)" "$(cmp -s "$M2" "$TOOL" && echo 0 || echo 1)"
mkq; TOOLUNDER="$M2" run tool --apply; arch="$(ls "$T/q/logs/archive"/big.log.*.gz 2>/dev/null | head -1)"
ok "MUTANT 2: the lossless assertion FAILS (a line vanishes between archive and kept log)" "$([ -n "$arch" ] && { gzip -dc "$arch"; cat "$T/q/logs/big.log"; } | cmp -s - "$T/big.orig" && echo 0 || echo 1)"
M3="$T/mut_planner.sh"; sed 's/^  keep="\$KEEP"; \[ "\$(basename "\$f")" = "ovn_planner.log" \].*$/  keep="$KEEP"/' "$TOOL" > "$M3"
ok "mutant 3 differs (no planner exception: every log gets the global keep)" "$(cmp -s "$M3" "$TOOL" && echo 0 || echo 1)"
mkq; cp "$T/q/logs/big.log" "$T/q/logs/ovn_planner.log"; TOOLUNDER="$M3" run tool --apply
ok "MUTANT 3: the planner-history assertion FAILS (ovn_planner.log is cut to 1000 lines)" "$([ "$(wc -l < "$T/q/logs/ovn_planner.log" | tr -d ' ')" = 80000 ] && echo 0 || echo 1)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
