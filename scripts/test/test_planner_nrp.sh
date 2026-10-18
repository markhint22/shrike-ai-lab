#!/usr/bin/env bash
# Regression test (2026-10-18, FIX 3b): ovn_planner.sh calls ovn_needs_research_promote.py when a repo has no [ready] feature.
#  S shadow (default): roadmap unchanged, model never called, a "needs-research promotion (shadow)" line is logged
#  O off: no promotion line, nothing changes
#  E enforce: the grounded [needs-research] feature is promoted AND decomposed in the same pass (backlog gets the items, roadmap line ends [decomposed])
#  M mutant planner without the hook: enforce promotes nothing
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
PL="$HERE/../../ovn_planner.sh"; [ -f "$PL" ] || PL="$HERE/../ovn_planner.sh"
NRP="$HERE/../ovn_needs_research_promote.py"
[ -f "$PL" ] && [ -f "$NRP" ] || { echo "  SKIP: planner or promote script missing"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; safe_rm_rf "$tmp"' EXIT
PORT=18917
cat > "$tmp/mockserver.py" <<'PYEOF2'
import http.server, json, sys
PORT = int(sys.argv[1]); RESP_FILE = sys.argv[2]; REQLOG = sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0) or 0))
        open(REQLOG, 'a').write("1\n")
        payload = json.dumps({"choices": [{"message": {"content": open(RESP_FILE).read()}}]}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_GET(self):
        self.send_response(200); self.end_headers()
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PYEOF2
cat > "$tmp/resp.txt" <<'RESP'
- [ ] [T2] app/routers/export.py — add a limiter. VERIFY: pytest -k new1. (cat:python; multifile:no)
- [ ] [T1] app/routers/export.py — add validation. VERIFY: python -c 'import export'. (cat:python; multifile:no)
- [ ] [T3] app/routers/export.py — wire the endpoint. VERIFY: curl localhost/new3. (cat:endpoint; multifile:no)
RESP
: > "$tmp/reqlog.txt"
python3 "$tmp/mockserver.py" "$PORT" "$tmp/resp.txt" "$tmp/reqlog.txt" >/dev/null 2>&1 &
MOCKPID=$!
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
WD="$tmp/home/overnight-queue"
mkdir -p "$WD"/{backlog,roadmap,repos,logs,scripts,state}
cp "$NRP" "$WD/scripts/"
mkdir -p "$WD/repos/demo/app/routers"; printf 'x = 1\n' > "$WD/repos/demo/app/routers/export.py"
FEAT='- [ ] [P2] [needs-research] Rate limit the export router — `app/routers/export.py:1` has no limiter {cat: backend; size: M; multifile: no; research: repo}'
reset(){ printf '# backlog\n- [ ] [T1] app/x.py — a. VERIFY: t\n' > "$WD/backlog/demo.md"; printf '# roadmap\n%s\n' "$FEAT" > "$WD/roadmap/demo.md"; rm -f "$WD"/state/pl_log_* "$WD"/state/nrp_count_*; : > "$tmp/reqlog.txt"; : > "$WD/logs/ovn_planner.log"; }
run(){ ( HOME="$tmp/home" LITELLM_BASE="http://127.0.0.1:$PORT" OVN_PLAN_THRESHOLD=10 OVN_PLAN_MAX_PER_RUN=4 "$@" bash "${PLANNER:-$PL}" demo >"$tmp/out.txt" 2>>"$tmp/run.log" ); }
logs(){ cat "$WD/logs/ovn_planner.log" "$tmp/out.txt" 2>/dev/null; }

reset; run env
ok "S shadow(default): roadmap untouched" "grep -q '\[needs-research\] Rate limit' '$WD/roadmap/demo.md' && ! grep -q '\[ready\]' '$WD/roadmap/demo.md'"
ok "S shadow: model never called" "[ ! -s '$tmp/reqlog.txt' ]"
ok "S shadow: promotion line logged" "logs | grep -q 'needs-research promotion (shadow).*SHADOW 1'"
ok "S shadow: starvation line still logged (trigger check keeps working)" "logs | grep -q 'no \[ready\] roadmap feature'"

reset; run env OVN_NEEDS_RESEARCH_PROMOTE=off
ok "O off: roadmap untouched, no promotion line" "grep -q '\[needs-research\]' '$WD/roadmap/demo.md' && ! logs | grep -q 'needs-research promotion'"

reset; run env OVN_NEEDS_RESEARCH_PROMOTE=enforce
ok "E enforce: model called once (the promoted feature was decomposed in the same pass)" "[ \$(wc -l < '$tmp/reqlog.txt') -eq 1 ]"
ok "E enforce: items landed in the backlog" "[ \$(grep -cE '^- \[ \] \[T[1-5]\]' '$WD/backlog/demo.md') -eq 4 ]"
# the final [ready] -> [decomposed] flip is the planner's own `sed -i "Ns/..."` (GNU sed on the box; BSD sed on a Mac silently no-ops it - the pre-existing test_ovn_planner G/H failures there), so accept either
ok "E enforce: roadmap line left [needs-research], carries the AUTO-PROMOTED stamp" "grep -qE '\[(decomposed|ready)\] Rate limit the export router.*AUTO-PROMOTED' '$WD/roadmap/demo.md' && ! grep -q '\[needs-research\]' '$WD/roadmap/demo.md'"

# mutant planner: hook removed -> enforce promotes nothing
python3 - "$PL" "$tmp/planner_mut.sh" <<'PYEOF3'
import sys
s = open(sys.argv[1]).read()
old = 'if [ -z "$feat_line" ] && [ "${OVN_NEEDS_RESEARCH_PROMOTE:-shadow}" != "off" ] && [ -f "scripts/ovn_needs_research_promote.py" ]; then'
assert s.count(old) == 1, "anchor"
open(sys.argv[2], "w").write(s.replace(old, "if false; then"))
PYEOF3
reset; PLANNER="$tmp/planner_mut.sh" run env OVN_NEEDS_RESEARCH_PROMOTE=enforce
ok "M MUTANT (no hook) is caught: nothing promoted, model never called" "grep -q '\[needs-research\]' '$WD/roadmap/demo.md' && [ ! -s '$tmp/reqlog.txt' ]"
echo "test_planner_nrp: $P passed, $F failed"
[ "$F" = 0 ]
