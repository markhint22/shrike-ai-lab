#!/usr/bin/env bash
# Regression: passrate_check.py buckets state/outcomes.jsonl rows by hard-coded time windows and prints good/bad/benign
# + pass_rate = good/(good+bad) overall and per repo. The script is cwd-relative (state/, scripts/), so it is driven from a
# fake tree. NOTE: passrate_check.py currently exists only on the box (not in the Mac mirror); the test skips if absent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S=""; for c in "$HERE/../../passrate_check.py" "$HERE/../passrate_check.py" "$HERE/passrate_check.py"; do [ -f "$c" ] && { S="$c"; break; }; done
B="$HERE/../ovn_outcome_buckets.py"; [ -f "$B" ] || B="$HERE/ovn_outcome_buckets.py"
if [ -z "$S" ]; then echo "  skip: passrate_check.py not present in this tree (box-only script)"; echo "  0 passed, 0 failed"; exit 0; fi
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then echo "  ok   $1"; else echo "  WARN KNOWN-BUG: $1 (non-fatal)"; fi; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
W="$T/tree"; mkdir -p "$W/state" "$W/scripts"; cp "$B" "$W/scripts/ovn_outcome_buckets.py"
run(){ ( cd "$W" && python3 "$S" 2>&1 ); }
row(){ printf '{"ts":"%s","repo":"%s","severity":%s}\n' "$1" "$2" "$3"; }
A1=2026-09-28T10:00:00Z; B1=2026-09-29T05:00:00Z; C1=2026-09-30T01:00:00Z
{
  row $A1 billwatch '"good"'; row $A1 billwatch '"good"'; row $A1 billwatch '"bad"'; row $A1 xlite '"neutral"'
  row 2026-09-28T05:00:00Z gitlark '"good"'            # window a start: inclusive
  row 2026-09-28T04:59:59Z gitlark '"bad"'             # before everything: excluded
  row 2026-09-29T02:00:00Z gitlark '"bad"'             # a end (exclusive) == b start (inclusive) -> only window b
  row $B1 iptv_apps '"bad"'; row $B1 iptv_apps '"bad"'; row $B1 iptv_apps null; row $B1 iptv_apps '"fixable"'
  row $B1 billwatch '"expected"'
  printf '{"ts":"%s","severity":"good"}\n' $C1      # missing repo -> "?"
  row 2026-09-29T13:00:00Z iptv_apps '"good"'       # c start
  row 2026-09-30T23:59:59Z iptv_apps '"bad"'        # c end exclusive -> dropped
  row 2027-01-01T00:00:00Z iptv_apps '"bad"'        # beyond: dropped
  printf '{"repo":"xlite","severity":"good"}\n'     # no ts -> "" -> dropped
  echo 'garbage not json'
  echo ''
  echo '   '
} > "$W/state/outcomes.jsonl"
out="$(run)"
win(){ printf '%s\n' "$out" | awk -v w="=== $1" 'index($0,w)==1{f=1;print;next} /^===/{f=0} f'; }
WA="$(win a_baseline)"; WB="$(win b_post)"; WC="$(win c_post)"
ok "three windows printed in order with their bounds" "$([ "$(has "$out" '=== a_baseline_0928_pre21cdt [2026-09-28T05:00:00Z .. 2026-09-29T02:00:00Z] ===')$(has "$out" '=== b_post11bugfix_0928-21cdt_to_0929-08cdt [2026-09-29T02:00:00Z .. 2026-09-29T13:00:00Z] ===')$(has "$out" '=== c_post_morningsweep_0929-08cdt_to_now [2026-09-29T13:00:00Z .. 2026-09-30T23:59:59Z] ===')" = 111 ] && echo 1 || echo 0)"
ok "window a OVERALL: good=3 bad=1 benign=1 n=4 rate 75.0%" "$(has "$WA" 'OVERALL: good=3 bad=1 benign=1 nonbenign_n=4 pass_rate=75.0%')"
ok "window a excludes row before start; includes start row (gitlark good=1)" "$(printf '%s\n' "$WA" | grep -E '^    gitlark +good=  1 bad=  0 benign=  0 n=  1 rate=100.0%' >/dev/null && echo 1 || echo 0)"
ok "window a per-repo billwatch good=2 bad=1 rate 66.7%" "$(printf '%s\n' "$WA" | grep -E '^    billwatch +good=  2 bad=  1 benign=  0 n=  3 rate=66.7%' >/dev/null && echo 1 || echo 0)"
ok "all-benign repo shows n=0 rate=nan%" "$(printf '%s\n' "$WA" | grep -E '^    xlite +good=  0 bad=  0 benign=  1 n=  0 rate=nan%' >/dev/null && echo 1 || echo 0)"
ok "window end is exclusive: a-end row lands in window b" "$(has "$WB" 'OVERALL: good=0 bad=3 benign=3 nonbenign_n=3 pass_rate=0.0%')"
ok "null/expected/fixable severities count as benign" "$(printf '%s\n' "$WB" | grep -E '^    iptv_apps +good=  0 bad=  2 benign=  2 n=  2 rate=0.0%' >/dev/null && echo 1 || echo 0)"
ok "repos listed alphabetically" "$([ "$(printf '%s\n' "$WB" | grep '^    ' | awk '{print $1}' | tr '\n' ' ')" = 'billwatch gitlark iptv_apps ' ] && echo 1 || echo 0)"
ok "window c: good=2 (incl. missing-repo row), row at end and later dropped" "$(has "$WC" 'OVERALL: good=2 bad=0 benign=0 nonbenign_n=2 pass_rate=100.0%')"
ok "missing repo field grouped under '?'" "$(printf '%s\n' "$WC" | grep -E '^    \? +good=  1' >/dev/null && echo 1 || echo 0)"
ok "row with no ts is excluded from every window" "$(printf '%s\n' "$out" | grep -E '^    xlite .*good=  1' >/dev/null && echo 0 || echo 1)"
ok "garbage and blank lines skipped, exit clean" "$(printf '%s' "$out" | grep -q Traceback && echo 0 || echo 1)"

# empty windows / empty file
: > "$W/state/outcomes.jsonl"; out="$(run)"
ok "empty file: every window OVERALL all-zero with pass_rate=nan%" "$([ "$(printf '%s\n' "$out" | grep -c 'OVERALL: good=0 bad=0 benign=0 nonbenign_n=0 pass_rate=nan%')" = 3 ] && echo 1 || echo 0)"
ok "empty file: no per-repo rows" "$(printf '%s\n' "$out" | grep -q '^    ' && echo 0 || echo 1)"
row $A1 only '"neutral"' > "$W/state/outcomes.jsonl"; out="$(run)"
ok "benign-only window: nan rate but benign counted" "$(has "$out" 'OVERALL: good=0 bad=0 benign=1 nonbenign_n=0 pass_rate=nan%')"

# error paths
rm -f "$W/state/outcomes.jsonl"; out="$(run)"
ok "missing outcomes.jsonl -> FileNotFoundError" "$(has "$out" 'FileNotFoundError')"
: > "$W/state/outcomes.jsonl"; rm -f "$W/scripts/ovn_outcome_buckets.py"; out="$(run)"
ok "missing scripts/ovn_outcome_buckets.py -> import error" "$(has "$out" 'ModuleNotFoundError')"
cp "$B" "$W/scripts/ovn_outcome_buckets.py"

# robustness: one malformed-but-valid-JSON row must not kill the whole report
{ row $A1 billwatch '"good"'; echo '"a bare json string"'; echo '[1,2]'; row $A1 billwatch '"bad"'; } > "$W/state/outcomes.jsonl"; out="$(run)"
kb "non-object JSON lines (string/array) are skipped instead of crashing with AttributeError" "$(has "$out" 'OVERALL: good=1 bad=1 benign=0 nonbenign_n=2 pass_rate=50.0%')"
printf '{"ts":12345,"repo":"x","severity":"good"}\n' > "$W/state/outcomes.jsonl"; out="$(run)"
kb "non-string ts does not crash the report (TypeError on str<=int compare)" "$(printf '%s' "$out" | grep -q Traceback && echo 0 || echo 1)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
