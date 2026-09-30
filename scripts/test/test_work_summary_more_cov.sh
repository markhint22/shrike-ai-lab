#!/usr/bin/env bash
# Extra branch coverage for work_summary.py (real file executed in place, fixture cwd/HOME): malformed/old outcome rows, reverts,
# the staged-higher-tier summary block (verified / false-pass / legacy / dedupe / bad json), and detail-script failure modes.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$HERE/../../work_summary.py"; [ -f "$WS" ] || WS="$HERE/../work_summary.py"
[ -f "$WS" ] || { echo "work_summary.py not found"; exit 2; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ printf '%s' "$1" | grep -qE -- "$2" && echo 1 || echo 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" PYTHONDONTWRITEBYTECODE=1; mkdir -p "$HOME"
cd "$tmp"; mkdir -p state/stage_runs
now="$(python3 -c 'import datetime;print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))')"
old="2001-01-01T00:00:00Z"
cat > state/outcomes.jsonl <<J
this is not json
{"ts":"garbage","class":"landed"}
{"class":"landed"}
{"ts":"$old","repo":"ancient","class":"landed","tier":"1"}
{"ts":"$now","repo":"r1","class":"landed","tier":"4"}
{"ts":"$now","repo":"r1","class":"landed","tier":"5"}
{"ts":"$now","repo":"r2","class":"landed","tier":"1"}
{"ts":"$now","repo":"r2","class":"landed"}
{"ts":"$now","repo":"r3","class":"reverted"}
{"ts":"$now","repo":"r3","class":"reverted"}
{"ts":"$now","repo":"r4","class":"reverted"}
{"ts":"$now","class":"skipped"}
{"ts":"$now","class":"noop"}
J
export OVN_LANDED_DETAIL_SCRIPT="$tmp/none.py"
o="$(python3 "$WS" 24 2>&1)"
ok "aggregate counts skip malformed/old rows (4 reverted-less: 4 landed, 3 reverted, 1 noop, 1 skipped)" "$(has "$o" 'Last 24h: 4 landed . 3 reverted . 1 no-op . 1 skipped')"
ok "tier line in order incl '?'" "$(has "$o" 'landed by tier: T1:1 T4:1 T5:1 T\?:1')"
ok "higher-tier count T3+ = 2" "$(has "$o" 'higher-tier \(T3\+\) landed: 2')"
ok "by repo shows r1 2 first" "$(has "$o" 'by repo: r1 2')"
ok "ancient row excluded" "$([ "$(has "$o" ancient)" = 0 ] && echo 1 || echo 0)"
ok "reverts line lists r3 2, r4 1" "$(has "$o" 'reverts: r3 2, r4 1')"
ok "no staged line when no stage_runs" "$([ "$(has "$o" 'staged higher-tier')" = 0 ] && echo 1 || echo 0)"
ok "default hours 24 when no arg" "$(has "$(python3 "$WS" 2>&1)" 'Last 24h')"

# staged runs block
cat > state/stage_runs/a.jsonl <<J
not json
{"event":"other","run":"x"}
{"event":"summary","run":"r1","verified":true,"passed":3,"total":3}
{"event":"summary","run":"r1","verified":true,"passed":3,"total":3}
{"event":"summary","run":"r2","verified":false,"passed":1,"total":3}
{"event":"summary","run":"r3","verified":null,"passed":1,"total":3}
{"event":"summary","run":"r4","verified":true,"passed":1,"total":3}
J
o="$(python3 "$WS" 24 2>&1)"
ok "staged: 1 complete, false-pass + legacy suffixes" "$(has "$o" 'staged higher-tier \(independently verified\): 1 complete, 1 false-pass caught, 1 legacy-unverified')"
cat > state/stage_runs/a.jsonl <<J
{"event":"summary","run":"q1","verified":true,"passed":2,"total":2}
J
o="$(python3 "$WS" 24 2>&1)"
ok "staged: only complete -> no suffixes" "$(has "$o" 'verified\): 1 complete$')"
echo '{"event":"summary","run":"z","verified":true,"passed":0,"total":0}' > state/stage_runs/a.jsonl
o="$(python3 "$WS" 24 2>&1)"
ok "staged: total 0 counted nowhere -> no staged line" "$([ "$(has "$o" 'staged higher-tier')" = 0 ] && echo 1 || echo 0)"
# unreadable (directory named *.jsonl) -> outer except swallows
rm -f state/stage_runs/a.jsonl; mkdir state/stage_runs/dir.jsonl
o="$(python3 "$WS" 24 2>&1)"
ok "staged: unreadable run file swallowed, summary still printed" "$(has "$o" 'Last 24h: 4 landed')"
rmdir state/stage_runs/dir.jsonl

# detail script: prints output / prints nothing / crashes (timeout exception)
cat > "$tmp/det.py" <<'P'
import sys
print("DETAIL " + " ".join(sys.argv[1:]))
P
o="$(OVN_LANDED_DETAIL_SCRIPT="$tmp/det.py" python3 "$WS" 6 2>&1)"
ok "detail output appended after blank line with args" "$(has "$o" 'DETAIL 6 --max-per-repo 4 --max-total 16')"
: > "$tmp/empty.py"
o="$(OVN_LANDED_DETAIL_SCRIPT="$tmp/empty.py" python3 "$WS" 6 2>&1)"
ok "empty detail output adds nothing" "$([ "$(has "$o" 'DETAIL')" = 0 ] && echo 1 || echo 0)"
# subprocess failure: make sys.executable-run raise via a detail path that exists but subprocess.run is patched to raise
o="$(OVN_LANDED_DETAIL_SCRIPT="$tmp/det.py" python3 - "$WS" <<'P'
import sys, runpy, subprocess
def boom(*a, **k): raise subprocess.TimeoutExpired("x", 1)
subprocess.run = boom
sys.argv = [sys.argv[1], "24"]
runpy.run_path(sys.argv[0], run_name="__main__")
P
)"
ok "detail timeout swallowed, aggregates printed" "$(has "$o" 'Last 24h: 4 landed')"
echo "work_summary more: $P passed, $F failed"; [ "$F" -eq 0 ]
