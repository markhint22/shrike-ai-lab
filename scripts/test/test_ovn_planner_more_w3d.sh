#!/usr/bin/env bash
# Wave-3 extra coverage for ovn_planner.sh: the state/PAUSED early exit and the gradle-flavor guard integration
# (guard present in $HOME/overnight-queue/scripts -> VERIFY task rewritten, the guard's stderr note logged).
# Hermetic: fake HOME, mocked LiteLLM (local http server), no real state touched.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PL="$HERE/../../ovn_planner.sh"; [ -f "$PL" ] || PL="$HERE/../ovn_planner.sh"
GUARD="$HERE/../ovn_gradle_flavor_guard.sh"; [ -f "$GUARD" ] || GUARD="$HERE/../scripts/ovn_gradle_flavor_guard.sh"
[ -f "$PL" ] || { echo "  SKIP: ovn_planner.sh not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$tmp"' EXIT
PORT=$(( 20000 + RANDOM % 20000 ))
cat > "$tmp/mock.py" <<'PY'
import http.server, json, sys
PORT=int(sys.argv[1]); RESP=sys.argv[2]; LOG=sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self,*a): pass
    def do_POST(self):
        self.rfile.read(int(self.headers.get('Content-Length',0) or 0))
        open(LOG,'a').write("1\n")
        p=json.dumps({"choices":[{"message":{"content":open(RESP).read()}}],"usage":{"prompt_tokens":5,"completion_tokens":3}}).encode()
        self.send_response(200); self.send_header('Content-Type','application/json'); self.send_header('Content-Length',str(len(p))); self.end_headers(); self.wfile.write(p)
    def do_GET(self): self.send_response(200); self.end_headers()
http.server.HTTPServer(('127.0.0.1',PORT),H).serve_forever()
PY
: > "$tmp/reqlog.txt"; : > "$tmp/resp.txt"
python3 "$tmp/mock.py" "$PORT" "$tmp/resp.txt" "$tmp/reqlog.txt" >/dev/null 2>&1 &
MOCKPID=$!
for i in $(seq 1 100); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done
WD="$tmp/home/overnight-queue"
mkdir -p "$WD"/{backlog,roadmap,repos,logs,state,scripts}
run(){ ( HOME="$tmp/home" OVN_MODEL=m LITELLM_BASE="http://127.0.0.1:$PORT" OVN_PLAN_THRESHOLD=10 bash "$PL" "$@" >/dev/null 2>>"$tmp/run.log" ); }

echo "== paused: exits before any model call"
mkdir -p "$WD/repos/rp/scripts"; echo "def f(): pass" > "$WD/repos/rp/scripts/e.py"
printf '# b\n' > "$WD/backlog/rp.md"; printf '# r\n- [ ] [P2] [ready] Paused feature\n' > "$WD/roadmap/rp.md"
touch "$WD/state/PAUSED"
run rp; rc=$?
ok "paused run exits 0" "[ $rc = 0 ]"
ok "paused run logs the skip" "grep -q 'queue is paused' '$WD/logs/ovn_planner.log'"
ok "paused run never calls the model" "[ ! -s '$tmp/reqlog.txt' ]"
ok "paused run leaves the roadmap [ready]" "grep -q '\[ready\] Paused feature' '$WD/roadmap/rp.md'"
rm -f "$WD/state/PAUSED"

echo "== gradle guard present: flavored repo gets the umbrella task"
cp "$GUARD" "$WD/scripts/ovn_gradle_flavor_guard.sh"
mkdir -p "$WD/repos/rg/app" "$WD/repos/rg/scripts"; echo "def f(): pass" > "$WD/repos/rg/scripts/e.py"
echo 'android { productFlavors { googleTv {} } }' > "$WD/repos/rg/app/build.gradle"
printf '# b\n' > "$WD/backlog/rg.md"; printf '# r\n- [ ] [P2] [ready] Flavored feature\n' > "$WD/roadmap/rg.md"
cat > "$tmp/resp.txt" <<'RESP'
- [ ] [T2] app/A.kt — add a. VERIFY: ./gradlew :app:testDebugUnitTest. (cat:kotlin; multifile:no)
- [ ] [T1] app/B.kt — add b. VERIFY: ./gradlew :app:testReleaseUnitTest. (cat:kotlin; multifile:no)
- [ ] [T3] app/C.kt — add c. VERIFY: ./gradlew :app:test. (cat:kotlin; multifile:no)
RESP
run rg
ok "model called once" "[ \$(wc -l < '$tmp/reqlog.txt') -eq 1 ]"
ok "single-variant debug task rewritten to :app:test" "grep -q 'gradlew :app:test\. ' '$WD/backlog/rg.md' && ! grep -q testDebugUnitTest '$WD/backlog/rg.md'"
ok "single-variant release task rewritten too" "! grep -q testReleaseUnitTest '$WD/backlog/rg.md'"
ok "guard's stderr summary is logged by the planner" "grep -qE 'rg: .+' '$WD/logs/ovn_planner.log' && grep -c 'rg:' '$WD/logs/ovn_planner.log' | grep -qv '^1$' || grep -qE 'rg: .*(rewr|gradle|umbrella|:test)' '$WD/logs/ovn_planner.log'"
ok "feature marked decomposed" "grep -q '\[decomposed\] Flavored feature' '$WD/roadmap/rg.md'"

echo "== gradle guard present, repo without flavors: passes items unchanged"
mkdir -p "$WD/repos/rn/app" "$WD/repos/rn/scripts"; echo "def f(): pass" > "$WD/repos/rn/scripts/e.py"
echo 'android { }' > "$WD/repos/rn/app/build.gradle"
printf '# b\n' > "$WD/backlog/rn.md"; printf '# r\n- [ ] [P2] [ready] Plain feature\n' > "$WD/roadmap/rn.md"
run rn
ok "unflavored repo keeps testDebugUnitTest" "grep -q testDebugUnitTest '$WD/backlog/rn.md'"

echo "$P passed, $F failed"; [ "$F" -eq 0 ]
