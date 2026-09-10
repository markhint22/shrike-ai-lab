#!/usr/bin/env bash
# Regression test: ovn_t3_report.sh must correctly bucket outcomes by time window, count
# higher-tier (T3+) land rate, summarize fail-cause distribution, and degrade gracefully with
# no/partial data — this is the ONLY visibility into whether the higher-tier changes (architect,
# best-of-N, parked-recovery) are actually moving the needle, so a silent miscount here would
# hide a real regression (2026-09-10).
set -uo pipefail
REAL="$HOME/overnight-queue"
SH="$REAL/ovn_t3_report.sh"
[ -f "$SH" ] || { echo "  SKIP: $SH not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
SANDBOX_HOME="$tmp/home"
OQ="$SANDBOX_HOME/overnight-queue"
mkdir -p "$OQ/state" "$OQ/logs"

run_report(){ HOME="$SANDBOX_HOME" bash "$SH" 2>&1; }
now_iso(){ python3 -c "import datetime,sys; print((datetime.datetime.utcnow()-datetime.timedelta(minutes=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"; }
row(){ # $1=minutes-ago $2=class $3=tier $4=fail_reason(or empty)
  python3 -c "
import json,datetime,sys
mins,cls,tier,fr = sys.argv[1:5]
ts=(datetime.datetime.utcnow()-datetime.timedelta(minutes=int(mins))).strftime('%Y-%m-%dT%H:%M:%SZ')
o={'ts':ts,'repo':'r','id':'i','type':'aider_fix','tier':tier,'category':'c','class':cls,'severity':'x','attempt':1,'tokens_sent':0,'tokens_recv':0,'duration_s':1}
if fr: o['fail_reason']=fr
print(json.dumps(o))
" "$1" "$2" "$3" "$4"
}

# === A: empty state -> every window reports "no outcomes", never crashes ===
: > "$OQ/state/outcomes.jsonl"
outA="$(run_report)"
ok "A: empty file -> all 3 windows say no outcomes, no traceback" \
   "[ \$(printf '%s' \"$outA\" | grep -c 'no outcomes') -eq 3 ] && ! printf '%s' \"$outA\" | grep -qi traceback"
ok "A: report is also written to state/t3_report.txt" "[ -s '$OQ/state/t3_report.txt' ]"

rm -f "$OQ/state/outcomes.jsonl"
outA2="$(run_report)"
ok "A2: missing file entirely -> still degrades gracefully (no traceback)" \
   "! printf '%s' \"$outA2\" | grep -qi traceback"

# === B: mixed tiers/classes inside the 1h window -> correct counts + correct T3+ land rate ===
{
  row 5  landed   1 ""
  row 10 landed   3 ""
  row 15 reverted 3 "build-break"
  row 20 noop     4 "stage-unverified"
  row 25 landed   4 ""
  row 30 skipped  2 ""
} > "$OQ/state/outcomes.jsonl"
outB="$(run_report)"
ok "B: 1h bucket totals: landed=3 reverted=1 noop=1 skipped=1" \
   "printf '%s' \"$outB\" | grep -q 'landed=3 reverted=1 noop=1 skipped=1'"
ok "B: T3+ attempts=4 (tiers 3,3,4,4), landed=2 -> 50%" \
   "printf '%s' \"$outB\" | grep -q 'T3+ attempts=4 landed=2 (50%)'"
ok "B: fail causes line lists both non-landed reasons" \
   "printf '%s' \"$outB\" | grep -q 'fail causes:' && printf '%s' \"$outB\" | grep -q 'build-break:1' && printf '%s' \"$outB\" | grep -q 'stage-unverified:1'"
ok "B: skipped rows are excluded from the fail-cause tally (severity=expected, not a failure)" \
   "! printf '%s' \"$outB\" | grep 'fail causes:' | grep -q 'skipped:'"

# === C: window boundary — a row just outside 1h must NOT appear in the 1h bucket but DOES in 6h ===
{
  row 30 landed 1 ""
  row 90 landed 1 ""
} > "$OQ/state/outcomes.jsonl"
outC="$(run_report)"
line1h="$(printf '%s' "$outC" | grep '\[last 1h\] landed=')"
line6h="$(printf '%s' "$outC" | grep '\[last 6h\] landed=')"
ok "C: the 90-min-old row is excluded from the 1h window" "printf '%s' \"$line1h\" | grep -q 'landed=1'"
ok "C: the 90-min-old row IS included in the 6h window" "printf '%s' \"$line6h\" | grep -q 'landed=2'"

# === D: malformed lines (bad json / bad timestamp) are skipped, not fatal ===
{
  row 5 landed 3 ""
  echo 'not even json'
  echo '{"ts": "not-a-timestamp", "class": "landed"}'
  echo ''
} > "$OQ/state/outcomes.jsonl"
outD="$(run_report)"
ok "D: malformed/garbage lines don't crash the report" "! printf '%s' \"$outD\" | grep -qi traceback"
ok "D: the one valid row is still counted correctly" "printf '%s' \"$outD\" | grep -q 'landed=1 reverted=0 noop=0 skipped=0'"

echo "T3 report: $P passed, $F failed"
rm -rf "$tmp"
[ "$F" -eq 0 ]
