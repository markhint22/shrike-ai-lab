#!/usr/bin/env bash
# Regression tests for ovn_batch_scorecard.sh (daily cron wrapper) and, through it, ovn_batch_scorecard.py:
# grade boundaries (A>=90 B>=75 C>=50 D>=25 F<25), min-age / hours / --worst flags, malformed-row tolerance,
# the machine-parseable "#SUMMARY" trailer, and the wrapper's alert-only-when-D/F behaviour.
# Hermetic: HOME is a temp dir with a fake state/outcomes.jsonl; curl is a stub with the script's PATH patched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_HOME="$HOME"
SH="$HERE/../ovn_batch_scorecard.sh"; [ -f "$SH" ] || SH="$REAL_HOME/overnight-queue/scripts/ovn_batch_scorecard.sh"
PY="$HERE/../ovn_batch_scorecard.py"; [ -f "$PY" ] || PY="$REAL_HOME/overnight-queue/scripts/ovn_batch_scorecard.py"
[ -f "$SH" ] && [ -f "$PY" ] || { echo "  SKIP: scripts not found"; exit 0; }
unset NTFY_TOPIC

pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
STUB="$T/stub"; mkdir -p "$STUB"; CURLLOG="$T/curl.log"
cat > "$STUB/curl" <<EOF
#!/bin/bash
{ echo "--CALL--"; printf '%s\n' "\$@"; } >> "$CURLLOG"
exit 0
EOF
chmod +x "$STUB/curl"
W="$T/w/overnight-queue"; OUTC="$W/state/outcomes.jsonl"; LOG="$W/logs/ovn_batch_scorecard.log"
setup(){
  rm -rf "$T/w" "$CURLLOG"; mkdir -p "$W"/{scripts,state,logs}
  sed "s|^export PATH=.*|export PATH=\"$STUB:/usr/bin:/bin\"|" "$SH" > "$W/scripts/ovn_batch_scorecard.sh"
  cp "$PY" "$W/scripts/ovn_batch_scorecard.py"
}
hago(){ date -u -d "@$(( $(date +%s) - $1 * 3600 ))" +%FT%TZ; }
# row <hours_ago> <tag> <repo> <class> [sent] [recv]
row(){ printf '{"ts":"%s","feat_tag":"%s","repo":"%s","class":"%s","tokens_sent":%s,"tokens_recv":%s}\n' "$(hago "$1")" "$2" "$3" "$4" "${5:-0}" "${6:-0}" >> "$OUTC"; }
# batch <tag> <repo> <hours_ago> <landed> <reverted> <noop>
batch(){ local i; for ((i=0;i<$4;i++)); do row "$3" "$1" "$2" landed 10 5; done; for ((i=0;i<$5;i++)); do row "$3" "$1" "$2" reverted 10 5; done; for ((i=0;i<$6;i++)); do row "$3" "$1" "$2" noop 10 5; done; }
py(){ HOME="$T/w" python3 "$W/scripts/ovn_batch_scorecard.py" "$@" 2>&1; }
runsh(){ HOME="$T/w" bash "$W/scripts/ovn_batch_scorecard.sh" 2>&1; }

HOME="$T/none" bash "$SH" >/dev/null 2>&1; eqv "wrapper: no ~/overnight-queue -> exit 1" "1" "$?"

echo "== python: empty / filtered inputs =="
setup
eqv "no outcomes file -> silent" "" "$(py)"
: > "$OUTC"
eqv "empty outcomes -> silent" "" "$(py)"
printf 'not json\n{"ts":"x","feat_tag":"t"}\n{"ts":"%s","class":"landed"}\n{"feat_tag":"t","class":"landed"}\n' "$(hago 50)" > "$OUTC"
eqv "bad json / bad ts / no feat_tag / no ts -> all skipped -> silent" "" "$(py)"
: > "$OUTC"; batch young r1 2 3 0 0
eqv "batch younger than 24h -> silent" "" "$(py)"
out="$(py --min-age-hours=1)"
chk "--min-age-hours=1 includes the 2h-old batch" grep -q '1 batch(es) >=1h old' <<<"$out"
: > "$OUTC"; batch old r1 100 4 0 0
eqv "hours arg older than data cutoff -> silent" "" "$(py 10)"
chk "hours arg 200 includes it" grep -q 'scorecard: 1 batch' <<<"$(py 200)"

echo "== python: grades and report =="
setup; : > "$OUTC"
batch gA  ra 48 9 1 0     # 90%  -> A
batch gB  rb 48 3 1 0     # 75%  -> B
batch gC  rc 48 1 1 0     # 50%  -> C
batch gD  rd 48 1 2 1     # 25%  -> D
batch gF  rf 48 0 3 1     # 0%   -> F
batch gC2 rc 48 7 3 0     # 70%  -> C
batch gD2 rd 48 2 2 1     # 40%  -> D
batch gF2 rf 48 1 4 0     # 20%  -> F
out="$(py)"
chk "header counts all 8 batches" grep -q 'Research-batch scorecard: 8 batch(es) >=24h old' <<<"$out"
chk "#SUMMARY trailer correct" grep -qx '#SUMMARY total=8 A=1 B=1 C=2 D=2 F=2 flagged=4' <<<"$out"
chk "A bucket line" grep -qE '^  A \(90-100%\) +1 batch\(es\) +12%' <<<"$out"
chk "C bucket line (2 batches = 25%)" grep -qE '^  C \(50-74%\) +2 batch\(es\) +25%' <<<"$out"
chk "bar chars rendered for non-zero buckets" grep -q '█' <<<"$out"
chk "flag header counts D/F only" grep -q '4 batch(es) graded D/F — worth a look:' <<<"$out"
chk "F detail line fully formatted (0/4, reverted, no-op, tokens, age)" grep -qE '^  F rf/gF: 0/4 landed \(0%\) · 3 reverted · 1 no-op · 60 tok · 48h old$' <<<"$out"
eqv "A/B/C batches are not in the detail list" "0" "$(printf '%s\n' "$out" | grep -cE '^  [ABC] r[abc]/')"
firstd="$(printf '%s\n' "$out" | grep -E '^  [DF] r' | head -1)"
chk "detail list is worst-first (0% before 20%)" grep -q 'rf/gF' <<<"$firstd"
eqv "all 4 flagged batches listed" "4" "$(printf '%s\n' "$out" | grep -cE '^  [DF] r')"
out="$(py --worst=2)"
eqv "--worst=2 caps the detail list" "2" "$(printf '%s\n' "$out" | grep -cE '^  [DF] r')"
chk "--worst footer says how many hidden" grep -q '...and 2 more D/F batch(es) not shown' <<<"$out"
chk "--worst doesn't change the SUMMARY flagged count" grep -q 'flagged=4' <<<"$out"

# healthy
setup; : > "$OUTC"; batch h1 ra 48 10 0 0; batch h2 rb 48 8 2 0
out="$(py)"
chk "healthy: explicit 'No D/F' line" grep -q 'No D/F batches — nothing needs a look right now.' <<<"$out"
chk "healthy: flagged=0" grep -q 'flagged=0' <<<"$out"

# age measured from the batch's EARLIEST row; tokens sum with nulls
setup; : > "$OUTC"
row 30 mix rm landed 100 50; row 1 mix rm reverted null null
printf '{"ts":"%s","feat_tag":"mix","repo":"rm","class":"reverted","tokens_sent":7}\n' "$(hago 2)" >> "$OUTC"
out="$(py)"
chk "age from earliest row (30h), batch included despite a 1h row" grep -q 'rm/mix: 1/3 landed (33%) · 2 reverted · 0 no-op · 157 tok · 30h old' <<<"$out"
setup; : > "$OUTC"
printf '{"ts":"%s","feat_tag":"norepo","class":"noop"}\n' "$(hago 40)" >> "$OUTC"
chk "missing repo shows '?'" grep -q '?/norepo' <<<"$(py)"

echo "== wrapper =="
setup
out="$(runsh)"; rc=$?
eqv "no outcomes -> exit 0" "0" "$rc"
chk "clean run message logged" grep -q 'clean run — no feat-tagged batches >=24h old to report on' "$LOG"
chk "no alert on clean run" bash -c "! test -s '$CURLLOG'"

: > "$OUTC"; batch ok1 ra 48 10 0 0
NTFY_TOPIC=tt runsh >/dev/null
chk "healthy batches: report logged" grep -q 'Research-batch scorecard: 1 batch' "$LOG"
chk "healthy batches: '#SUMMARY' line in log" grep -q '#SUMMARY total=1' "$LOG"
chk "healthy batches: 'no D/F batches — no alert' logged" grep -q 'no D/F batches — no alert' "$LOG"
chk "healthy batches: curl not invoked" bash -c "! test -s '$CURLLOG'"

: > "$OUTC"; batch ok1 ra 48 10 0 0; batch badA rb 48 0 3 0; batch badB rc 48 1 3 0
: > "$CURLLOG"
NTFY_TOPIC=tt runsh >/dev/null
chk "flagged: one alert" test "$(grep -c -- '--CALL--' "$CURLLOG")" = 1
chk "flagged: title carries the D/F count (2)" grep -q 'Title: Research-batch scorecard: 2 batch(es) graded D/F' "$CURLLOG"
chk "flagged: tag warning" grep -q 'Tags: warning' "$CURLLOG"
chk "flagged: url" grep -q 'https://ntfy.sh/tt$' "$CURLLOG"
chk "flagged: body has detail lines" grep -q 'rb/badA' "$CURLLOG"
chk "flagged: body excludes the #SUMMARY line" bash -c "! grep -q '#SUMMARY' '$CURLLOG'"
chk "flagged: #SUMMARY kept in the log" grep -q '#SUMMARY total=3 A=1 B=0 C=0 D=1 F=1 flagged=2' "$LOG"

# no truncation: many flagged batches -> full body (> 800 chars)
setup; : > "$OUTC"
for i in $(seq 1 30); do batch "long-tag-number-$i" "repo$i" 48 0 2 0; done
NTFY_TOPIC=tt runsh >/dev/null
chk "30 flagged batches: title says 30" grep -q 'graded D/F' "$CURLLOG"
chk "30 flagged batches: last batch present (body not head -c truncated)" grep -q 'long-tag-number-9\b' "$CURLLOG"
eqv "30 flagged batches: all 30 detail lines delivered" "30" "$(grep -c 'repo[0-9]*/long-tag-number' "$CURLLOG")"

# topics
setup; : > "$OUTC"; batch bad rb 48 0 3 0
runsh >/dev/null
chk "flagged, no topic: no curl" bash -c "! test -s '$CURLLOG'"
chk "flagged, no topic: still logged" grep -q 'graded D/F\|rb/bad' "$LOG"
echo ftopic > "$W/state/ntfy_topic"
runsh >/dev/null
chk "topic from state/ntfy_topic" grep -q 'https://ntfy.sh/ftopic$' "$CURLLOG"
: > "$CURLLOG"; NTFY_TOPIC=etopic runsh >/dev/null
chk "env topic wins" grep -q 'https://ntfy.sh/etopic$' "$CURLLOG"

# missing/garbled #SUMMARY -> FLAGGED defaults to 0 -> no alert (stubbed python)
setup
cat > "$W/scripts/ovn_batch_scorecard.py" <<'EOF'
print("some report without a summary trailer")
EOF
NTFY_TOPIC=tt runsh >/dev/null
chk "no #SUMMARY -> treated as flagged=0, no alert" bash -c "! test -s '$CURLLOG'"
chk "no #SUMMARY -> 'no D/F' logged" grep -q 'no D/F batches — no alert' "$LOG"
cat > "$W/scripts/ovn_batch_scorecard.py" <<'EOF'
import sys
sys.stderr.write("boom from python\n")
EOF
runsh >/dev/null; rc=$?
eqv "python produced nothing (stderr only) -> exit 0" "0" "$rc"
chk "python stderr captured in log, then clean-run message" grep -q 'boom from python' "$LOG"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
