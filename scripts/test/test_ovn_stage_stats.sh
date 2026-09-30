#!/usr/bin/env bash
# Regression: ovn_stage_stats.py headlines INDEPENDENTLY-VERIFIED completion only (verified==true AND passed==total),
# counts false-passes / legacy-unverified separately, sums tokens, step timing, re-decompositions and top fail causes.
# Driven with a temp HOME (the script chdirs to ~/overnight-queue).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../ovn_stage_stats.py"; [ -f "$S" ] || S="$HERE/../ovn_stage_stats.py"; [ -f "$S" ] || S="$HERE/ovn_stage_stats.py"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
lacks(){ printf '%s' "$1" | grep -qF -- "$2" && echo 0 || echo 1; }
run(){ HOME="$1" python3 "$S" 2>&1; }

# ---------- empty / missing ----------
H0="$T/h0"; mkdir -p "$H0/overnight-queue"
out="$(run "$H0")"
ok "no state dir: header with 0 runs" "$(has "$out" '=== multi-stage runner: 0 completed item-runs ===')"
ok "no runs: OVERALL 0/0 (0%) without ZeroDivision" "$(has "$out" 'OVERALL verified higher-tier completion: 0/0 (0%) | re-decompositions: 0')"
ok "no runs: no tokens/timing/fail/NOTE sections" "$(printf '%s' "$out" | grep -qE 'tokens:|step timing|FAIL causes|NOTE' && echo 0 || echo 1)"
rc=0; HOME="$T/nohome" python3 "$S" >/dev/null 2>&1 || rc=$?
ok "missing ~/overnight-queue -> nonzero exit (chdir fails)" "$([ "$rc" != 0 ] && echo 1 || echo 0)"

# ---------- rich data ----------
H="$T/h"; D="$H/overnight-queue/state/stage_runs"; mkdir -p "$D"
LONG="$(printf 'x%.0s' $(seq 1 200))"
cat > "$D/a.jsonl" <<J
{"run":"A","event":"decomposed","tier":3}
{"run":"A","step":0,"verdict":"pass","tokens_sent":100,"tokens_recv":50,"duration_s":10}
{"run":"A","step":1,"verdict":"fail","fail_reason":"gate-red","excerpt":"E1","tokens_sent":null,"tokens_recv":null,"duration_s":0}
{"run":"A","step":1,"verdict":"fail","fail_reason":"gate-red","excerpt":"IGNORED-second"}
{"run":"A","step":2,"verdict":"fail"}
{"run":"A","event":"summary","tier":3,"passed":2,"total":2,"verified":true}
not json at all
{"no_run_key":true,"event":"summary","passed":9,"total":9}

{"run":"B","event":"summary","tier":3,"passed":1,"total":2,"verified":false}
{"run":"B","step":0,"verdict":"pass","tokens_sent":1000,"tokens_recv":500,"duration_s":30}
{"run":"C","event":"summary","tier":4,"passed":2,"total":2}
{"run":"E","event":"summary","tier":4,"passed":1,"total":2,"verified":true}
{"run":"F","step":0,"verdict":"fail","fail_reason":"timeout","excerpt":"$LONG","tokens_sent":9999,"tokens_recv":9999,"duration_s":300}
{"run":"G","event":"redecomposed"}
{"run":"G","event":"redecomposed"}
J
cat > "$D/b.jsonl" <<J
{"run":"D","event":"summary","tier":4,"passed":2,"total":2}
{"run":"D","event":"verify","verified":true}
J
out="$(run "$H")"; echo "$out" | sed 's/^/      | /' > "$T/dump"
ok "header counts only runs with total>0 (A,B,C,D,E = 5)" "$(has "$out" '=== multi-stage runner: 5 completed item-runs ===')"
ok "T3 line: 2 items, 1 verified, 1 false-pass caught" "$(has "$out" '  T3: 2 items | VERIFIED-complete 1  (1 false-pass CAUGHT)')"
ok "T4 line: 3 items, verified only D (E not full, C legacy)" "$(has "$out" '  T4: 3 items | VERIFIED-complete 1  (1 legacy-unverified)')"
ok "verify event after summary upgrades D to verified" "$(has "$out" 'VERIFIED-complete 1  (1 legacy')"
ok "tokens sums only finished runs (F's 9999 excluded), null tokens -> 0" "$(has "$out" 'tokens: 1,100 sent + 550 generated across 5 runs; ~825/verified-item')"
ok "OVERALL 2/5 = 40%, 2 re-decompositions" "$(has "$out" 'OVERALL verified higher-tier completion: 2/5 (40%) | re-decompositions: 2')"
ok "NOTE counts legacy run(s) predating the verify layer" "$(has "$out" 'NOTE: 1 run(s) predate the verify layer')"
ok "step timing median/max across ALL runs, zero duration skipped" "$(has "$out" 'step timing: median 30s, max 300s')"
ok "FAIL causes header" "$(has "$out" 'FAIL causes (attack these):')"
ok "most common cause first with count + first excerpt only" "$(has "$out" '    gate-red: 2  e.g. «E1»')"
ok "excerpt truncated to 140 chars" "$(printf '%s' "$out" | grep -F 'timeout: 1' | grep -qF "«$(printf 'x%.0s' $(seq 1 140))»" && ! printf '%s' "$out" | grep -qF "$(printf 'x%.0s' $(seq 1 141))" && echo 1 || echo 0)"
ok "fail verdict without fail_reason not counted as a cause" "$([ "$(printf '%s\n' "$out" | grep -c '^    [a-z-]*: [0-9]')" = 2 ] && echo 1 || echo 0)"
ok "junk line / run-less line / blank line ignored (no crash)" "$(has "$out" 'item-runs')"
ok "run-less summary (9/9) not counted" "$(lacks "$out" '9/9')"

# ---------- token line variants ----------
H2="$T/h2"; D2="$H2/overnight-queue/state/stage_runs"; mkdir -p "$D2"
cat > "$D2/x.jsonl" <<J
{"run":"P","event":"summary","tier":5,"passed":0,"total":3,"verified":null}
{"run":"P","step":0,"verdict":"fail","fail_reason":"oops","tokens_sent":7,"tokens_recv":3}
J
out="$(run "$H2")"
ok "tokens with 0 verified -> '(0 verified yet)'" "$(has "$out" 'tokens: 7 sent + 3 generated across 1 runs (0 verified yet)')"
ok "tier 5 legacy row" "$(has "$out" '  T5: 1 items | VERIFIED-complete 0  (1 legacy-unverified)')"
ok "overall 0/1 (0%)" "$(has "$out" '0/1 (0%)')"
ok "no step timing line when no durations" "$(lacks "$out" 'step timing')"
ok "fail cause w/o excerpt prints no e.g. clause" "$(printf '%s\n' "$out" | grep -qx '    oops: 1  e.g. «»' && echo 0 || echo 1)"

# ---------- untiered run and verified-false-with-no-summary-tier ----------
H3="$T/h3"; D3="$H3/overnight-queue/state/stage_runs"; mkdir -p "$D3"
cat > "$D3/x.jsonl" <<J
{"run":"Q","event":"summary","passed":1,"total":1,"verified":true}
{"run":"R","event":"summary","tier":3,"passed":1,"total":1,"verified":true}
{"run":"R","event":"verify","verified":false}
J
out="$(run "$H3")"
ok "missing tier bucketed as 'TNone'" "$(has "$out" '  TNone: 1 items | VERIFIED-complete 1')"
ok "later verify=false downgrades a previously verified run to false-pass" "$(has "$out" '  T3: 1 items | VERIFIED-complete 0  (1 false-pass CAUGHT)')"
ok "percent uses integer floor (1/2 -> 50%)" "$(has "$out" '1/2 (50%)')"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
