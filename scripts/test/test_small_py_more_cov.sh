#!/usr/bin/env bash
# Branch coverage for three small one-shot python scripts run IN PLACE against fixtures: ovn_park_sweep.py (usage / missing file /
# header present), archive_done.py, passrate_check.py (cwd-relative state/outcomes.jsonl, scripts/ via PYTHONPATH).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
export PYTHONDONTWRITEBYTECODE=1
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
b(){ [ "$1" = "$2" ] && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME"

# ---------- ovn_park_sweep.py ----------
PS="$ROOT/ovn_park_sweep.py"
python3 "$PS" >"$T/o" 2>"$T/e"; rc=$?
ok "park_sweep: no args -> usage rc2" "$([ $rc = 2 ] && grep -q usage "$T/e" && echo 1 || echo 0)"
python3 "$PS" a b >"$T/o" 2>"$T/e"; rc=$?
ok "park_sweep: 2 args -> usage rc2" "$(b $rc 2)"
out="$(python3 "$PS" "$T/missing.md")"
ok "park_sweep: missing file -> SWEPT=0" "$(b "$out" SWEPT=0)"
HDR="### Parked (AUTO-SKIP/HUMAN-ONLY sweep — needs Claude/human review, not attempted by the 27B)"
cat > "$T/p.md" <<P
# P
- [ ] [AUTO-SKIP x] drifted one
- [ ] [T1] real.py — real
$HDR — last swept 2020-01-01
- [ ] [HUMAN-ONLY old] already parked
P
out="$(python3 "$PS" "$T/p.md")"
ok "park_sweep: header present -> 1 moved" "$(b "$out" SWEPT=1)"
ok "park_sweep: header restamped, moved line at end" "$(python3 - "$T/p.md" <<'Q'
import sys,datetime
L=open(sys.argv[1]).read().splitlines()
h=[i for i,l in enumerate(L) if l.startswith("### Parked")]
print(1 if len(h)==1 and datetime.date.today().isoformat() in L[h[0]] and L[-1].endswith("drifted one") and L[1].startswith("- [ ] [T1]") else 0)
Q
)"
printf '# P\n- [ ] [T1] only real\n' > "$T/q.md"
out="$(python3 "$PS" "$T/q.md")"
ok "park_sweep: nothing to move -> SWEPT=0" "$(b "$out" SWEPT=0)"

# ---------- archive_done.py ----------
AD="$ROOT/archive_done.py"
printf '# H\n- [ ] open a\n- [x] done a\n  - [X] done nested\n- [ ] open b\nprose\n' > "$T/prog.md"
out="$(python3 "$AD" "$T/prog.md" "$T/arch.md")"
ok "archive_done: moved 2, open 2" "$(b "$out" "MOVED=2 KEPT_OPEN=2")"
ok "archive_done: progress lost [x] lines, archive gained them + stamp" "$(grep -q 'done a' "$T/prog.md" && echo 0 || { grep -q 'done nested' "$T/arch.md" && grep -q '<!-- archived' "$T/arch.md" && grep -q 'open a' "$T/prog.md" && echo 1 || echo 0; })"
out="$(python3 "$AD" "$T/prog.md" "$T/arch.md")"
ok "archive_done: nothing left to move -> MOVED=0 KEPT=2" "$(b "$out" "MOVED=0 KEPT=2")"
ok "archive_done: archive appended not truncated on 2nd run" "$([ "$(grep -c '<!-- archived' "$T/arch.md")" = 1 ] && echo 1 || echo 0)"

# ---------- passrate_check.py ----------
PC="$ROOT/passrate_check.py"
mkdir -p "$T/w/state"; cd "$T/w"
cat > state/outcomes.jsonl <<'J'

not json
[1,2]
"str"
{"ts":"2026-09-28T06:00:00Z","repo":"billwatch","severity":"good"}
{"ts":"2026-09-28T07:00:00Z","repo":"billwatch","severity":"bad"}
{"ts":"2026-09-28T08:00:00Z","repo":"gitlark","severity":"neutral"}
{"ts":"2026-09-29T03:00:00Z","repo":"gitlark","severity":"good"}
{"ts":"2026-09-29T05:00:00Z","severity":"bad"}
{"ts":123,"repo":"x","severity":"good"}
{"repo":"nots","severity":"good"}
J
PYTHONPATH="$ROOT/scripts" python3 "$PC" > "$T/pc.out" 2>"$T/pc.err"; rc=$?
ok "passrate_check: exits 0" "$(b $rc 0)"
ok "passrate_check: window a 1 good 1 bad 1 benign rate 50.0%" "$(grep -q 'OVERALL: good=1 bad=1 benign=1 nonbenign_n=2 pass_rate=50.0%' "$T/pc.out" && echo 1 || echo 0)"
ok "passrate_check: per-repo line billwatch" "$(grep -q 'billwatch .*good=  1 bad=  1 benign=  0 n=  2 rate=50.0%' "$T/pc.out" && echo 1 || echo 0)"
ok "passrate_check: per-repo benign-only repo has rate nan" "$(grep -q 'gitlark .*benign=  1 n=  0 rate=nan%' "$T/pc.out" && echo 1 || echo 0)"
ok "passrate_check: empty window c prints nan overall" "$(grep -q 'nonbenign_n=0 pass_rate=nan%' "$T/pc.out" && echo 1 || echo 0)"
ok "passrate_check: missing-repo row bucketed under '?'" "$(grep -qE '^ +\? +good=' "$T/pc.out" && echo 1 || echo 0)"
cd "$T"
echo "small py more: $P passed, $F failed"; [ "$F" -eq 0 ]
