#!/usr/bin/env bash
# Extra coverage for supervisor.sh (wave 3, w3b): redgreen/diverged/hygiene findings, drift + commit-sanity scans
# against local bare origins, Claude review path (stub `claude`), local-27B review (fake LiteLLM on 127.0.0.1),
# ntfy push (fake server on 127.0.0.1: success, failure, daily marker). Fully hermetic via OVERNIGHT_DIR.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../supervisor.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HOME/overnight-queue/supervisor.sh"
[ -f "$SCRIPT" ] || { echo "SKIP: supervisor.sh not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
DIR="$tmp/ovn"

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
LLM_RESP="$tmp/llm_resp.txt"; NTFY_LOG="$tmp/ntfy.log"; NTFY_STATUS="$tmp/ntfy_status"; echo 200 > "$NTFY_STATUS"; : > "$NTFY_LOG"
echo "no issues found" > "$LLM_RESP"
cat > "$tmp/fake.py" <<'PY_EOF'
import http.server, json, sys
port, llm_resp, ntfy_log, ntfy_status = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body=b"ok", ctype="text/plain"):
        self.send_response(code); self.send_header("Content-Type", ctype); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_GET(self):
        self._send(200)
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); raw = self.rfile.read(n)
        if self.path.startswith("/v1/chat/completions"):
            c = open(llm_resp, encoding="utf-8").read()
            self._send(200, json.dumps({"choices": [{"message": {"content": c}}], "usage": {"prompt_tokens": 5, "completion_tokens": 3}}).encode(), "application/json")
        else:
            with open(ntfy_log, "a", encoding="utf-8") as f:
                f.write("PATH=%s TITLE=%s PRIO=%s BODY=%s\n" % (self.path, self.headers.get("Title"), self.headers.get("Priority"), raw.decode("utf-8", "replace").replace("\n", "|")))
            self._send(int(open(ntfy_status).read().strip() or 200))
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
PY_EOF
python3 "$tmp/fake.py" "$PORT" "$LLM_RESP" "$NTFY_LOG" "$NTFY_STATUS" & FAKE_PID=$!
sleep 0.5
cleanup(){ kill "$FAKE_PID" >/dev/null 2>&1; rm -rf "$tmp"; }
trap cleanup EXIT

mkdir -p "$tmp/bin"
cat > "$tmp/bin/claude" <<'EOF2'
#!/usr/bin/env bash
[ "${CLAUDE_FAIL:-0}" = 1 ] && exit 1
echo "- repoX@abc1234: commit does not do what it says"
EOF2
chmod +x "$tmp/bin/claude"

reset_dir(){
  rm -rf "$DIR"; mkdir -p "$DIR/state" "$DIR/reports" "$DIR/logs" "$DIR/scripts"
  echo '[]' > "$DIR/tasks.json"
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/tok.log"\n' "$tmp" > "$DIR/scripts/ovn_log_tokens.sh"
}
RUN(){ OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log"; }
REP(){ ls -t "$DIR"/reports/supervisor-*.md 2>/dev/null | head -1; }

mkrepo(){ # $1=name ; origin bare + clone with origin/main, origin/develop, origin/overnight/feature, local clone at repos/$1
  local n="$1" o="$tmp/o_$1.git"
  rm -rf "$o" "$tmp/s_$1"
  git init -q --bare "$o"; git clone -q "$o" "$tmp/s_$1" 2>/dev/null
  ( cd "$tmp/s_$1" && echo base > f.txt && git add -A && git commit -q -m base && git branch -M main && git push -q origin main \
    && git branch develop && git push -q origin develop && git checkout -q -b overnight/feature && git push -q origin overnight/feature )
  mkdir -p "$DIR/repos"; git clone -q "$o" "$DIR/repos/$n" 2>/dev/null
}
featc(){ ( cd "$tmp/s_$1" && git checkout -q overnight/feature && shift && eval "$*" && git push -q origin overnight/feature ); }

# ---- A: state-file findings ----
reset_dir
printf 'line\nredgreen:SUSPECT a\nredgreen:SUSPECT b\n' > "$DIR/reports/2026-09-02-0000.md"
touch "$DIR/state/diverged_billwatch" "$DIR/state/branch_hygiene_review_gitlark"
OUT="$(RUN)"; R="$(REP)"
ok "A: redgreen SUSPECT counted (2)" "grep -q '2 red-green SUSPECT test' '$R'"
ok "A: diverged clone flagged" "grep -q 'DIVERGED clone: billwatch' '$R'"
ok "A: hygiene review flagged" "grep -q 'branch-hygiene flagged: gitlark' '$R'"

# ---- B: drift + commit sanity ----
reset_dir
mkrepo rb
( cd "$tmp/s_rb" && git checkout -q overnight/feature && for i in $(seq 1 44); do echo "l$i" >> filler.txt; git add -A; git commit -q -m "chore: filler $i"; done
  git commit -q --allow-empty -m "feat: add widget (claims work)"
  git commit -q --allow-empty -m "chore(sync): reconcile develop -> overnight/feature (branch guard)"
  for i in $(seq 1 10); do echo "dup$i" >> dup.txt; done; git add -A; git commit -q -m "refactor: remove duplicate helper"
  seq 1 700 > big.txt; git add -A; git commit -q -m "feat: big generated file"
  git push -q origin overnight/feature )
mkdir -p "$DIR/repos/social-media-manager/.git" "$DIR/repos/notgit"   # discontinued + non-git dirs are skipped
OUT="$(RUN)"; R="$(REP)"
ok "B: drift >=40 flagged" "grep -q 'DRIFT: rb overnight/feature is 48 commits ahead of develop' '$R'"
ok "B: empty feat commit flagged" "grep -q \"EMPTY COMMIT: rb@.*feat: add widget\" '$R'"
ok "B: chore(sync) empty commit NOT flagged" "! grep -q 'EMPTY COMMIT.*chore(sync)' '$R'"
ok "B: remove-duplicate net-add mismatch flagged" "grep -q 'MSG/DIFF MISMATCH: rb@.*remove duplicate' '$R'"
ok "B: >600 line commit flagged" "grep -q 'LARGE COMMIT: rb@.*big generated file' '$R'"
ok "B: discontinued repo skipped" "! grep -q 'social-media-manager' '$R'"

# ---- C: Claude review ----
reset_dir
OUT="$(PATH="$tmp/bin:$PATH" ANTHROPIC_API_KEY=k OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log")"; R="$(REP)"
ok "C: claude review finding surfaces" "grep -q 'Claude review flagged commit' '$R' && echo \"$OUT\" | grep -q '(+Claude review)'"
ok "C: review text in report" "grep -q 'commit does not do what it says' '$R'"
OUT="$(CLAUDE_FAIL=1 PATH="$tmp/bin:$PATH" ANTHROPIC_API_KEY=k OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log")"; R="$(REP)"
ok "C2: claude failure degrades gracefully (no finding)" "grep -q 'Claude review failed' '$R' && ! grep -q 'Claude review flagged' '$R'"

# ---- D: local 27B review ----
reset_dir; mkrepo rd
echo "rd@abc: diff contradicts message" > "$LLM_RESP"; rm -f "$tmp/tok.log"
OUT="$(SUPERVISOR_USE_LOCAL=1 LITELLM_BASE="http://127.0.0.1:$PORT" OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log")"; R="$(REP)"
ok "D1: local review flagged a problem -> finding" "grep -q 'Local-27B review flagged commit' '$R' && echo \"$OUT\" | grep -q 'local-27B review'"
ok "D1: token usage recorded 5/3" "grep -q 'supervisor-review - 5 3' '$tmp/tok.log'"
: > "$LLM_RESP"
OUT="$(SUPERVISOR_USE_LOCAL=1 LITELLM_BASE="http://127.0.0.1:$PORT" OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log")"; R="$(REP)"
ok "D2: empty model reply -> 'returned nothing' note, no finding" "grep -q 'local review returned nothing' '$R' && ! grep -q 'flagged commit' '$R'"
OUT="$(SUPERVISOR_USE_LOCAL=1 LITELLM_BASE="http://127.0.0.1:1" OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log")"; R="$(REP)"
ok "D3: litellm unreachable -> skipped note, no finding" "grep -q 'litellm unreachable' '$R' && ! grep -q 'flagged commit' '$R'"
touch "$DIR/state/PAUSED"
OUT="$(SUPERVISOR_USE_LOCAL=1 LITELLM_BASE="http://127.0.0.1:$PORT" OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log")"; R="$(REP)"
ok "D4: PAUSED skips the local review entirely" "! grep -q 'Local-27B' '$R'"
rm -f "$DIR/state/PAUSED"
reset_dir   # no repos at all -> CTX empty -> no review text
OUT="$(SUPERVISOR_USE_LOCAL=1 LITELLM_BASE="http://127.0.0.1:$PORT" OVERNIGHT_DIR="$DIR" bash "$SCRIPT" 2>>"$DIR/logs/supervisor.log")"; R="$(REP)"
ok "D5: nothing to review -> no review section" "! grep -q 'Local-27B review$' '$R'"

# ---- E: ntfy push ----
export NTFY_SERVER="http://127.0.0.1:$PORT"
reset_dir; : > "$NTFY_LOG"; echo 200 > "$NTFY_STATUS"
printf '#!/usr/bin/env python3\nprint("landed 3 items (T1:2 T2:1)")\n' > "$DIR/work_summary.py"
touch "$DIR/state/diverged_acme"
OUT="$(NTFY_TOPIC=tst RUN)"
ok "E1: findings push sent with default priority + work summary" "grep -q 'TITLE=Overnight queue: 1 item(s) need attention PRIO=default' '$NTFY_LOG' && grep -q 'what landed.*landed 3 items' '$NTFY_LOG'"
ok "E1: pushed message + daily marker written" "echo \"$OUT\" | grep -q 'pushed to ntfy topic' && [ \"\$(cat '$DIR/state/last_daily_digest')\" = \"\$(date +%F)\" ]"
ok "E1: work summary appears in the report" "grep -q 'Work (last 24h)' \"\$(ls -t '$DIR'/reports/supervisor-*.md | head -1)\""
reset_dir; : > "$NTFY_LOG"
OUT="$(NTFY_TOPIC=tst RUN)"
ok "E2: all-clear daily heartbeat is low priority, no-outcomes text" "grep -q 'PRIO=low' '$NTFY_LOG' && grep -q 'All clear, no issues' '$NTFY_LOG' && grep -q 'no outcomes recorded' '$NTFY_LOG'"
: > "$NTFY_LOG"
OUT="$(NTFY_TOPIC=tst RUN)"
ok "E3: second all-clear run same day sends nothing" "[ ! -s '$NTFY_LOG' ]"
rm -f "$DIR/state/last_daily_digest"; echo 500 > "$NTFY_STATUS"
OUT="$(NTFY_TOPIC=tst RUN)"
ok "E4: server error -> 'ntfy push failed', marker NOT written" "echo \"$OUT\" | grep -q 'ntfy push failed' && [ ! -f '$DIR/state/last_daily_digest' ]"
echo 200 > "$NTFY_STATUS"

# ---- F: auto-disabled, alerts archive, noop streaks, timeout auto-recovery, grooming ----
reset_dir
cat > "$DIR/tasks.json" <<'JSON'
[ {"id":"dead-task","enabled":false,"timeout_secs":600}, {"id":"slow-task","enabled":false,"timeout_secs":1200}, {"id":"manual-off","enabled":false}, {"id":"healed","enabled":true}, {"id":"slow2","enabled":false,"timeout_secs":1500} ]
JSON
mkdir -p "$DIR/state/failures" "$DIR/state/noops"
echo 4 > "$DIR/state/failures/dead-task.count"
echo 3 > "$DIR/state/failures/slow-task.count"
echo 3 > "$DIR/state/failures/slow2.count"
echo 1 > "$DIR/state/failures/notimeouts.count"
touch "$DIR/state/autorecovered_healed" "$DIR/state/autorecovered_slow2"
printf '| slow-task | x | error(exit=124) | f | l | 1s |\n| slow-task | x | error(exit=124) | f | l | 1s |\n' > "$DIR/reports/2026-09-05-0000.md"
printf '| dead-task | x | error(exit=1) | f | l | 1s |\n' > "$DIR/reports/2026-09-06-0000.md"
printf '| slow2 | x | error(exit=124) | f | l | 1s |\n| slow2 | x | error(exit=124) | f | l | 1s |\n' > "$DIR/reports/2026-09-07-0000.md"
printf '[t] warn | a | build-gate reverted x\n[t] error | b | real problem one\n[t] error | c | real problem two\n' > "$DIR/state/alerts.log"
echo 31 > "$DIR/state/noops/ongoing-stuck.count"; echo 2 > "$DIR/state/noops/ongoing-fine.count"; : > "$DIR/state/noops/notcount.txt"
touch "$DIR/reports/grooming-gitlark-$(date +%Y%m%d).md"
OUT="$(RUN)"; R="$(REP)"
ok "F: auto-disabled with count flagged" "grep -q 'AUTO-DISABLED: dead-task (failed 4x)' '$R'"
ok "F: manual disable (no count) not flagged" "! grep -q 'AUTO-DISABLED: manual-off' '$R'"
ok "F: two real alerts counted with newest" "grep -q '2 alert(s) need a look — newest: c | real problem two' '$R'"
ok "F: alerts archived and cleared" "[ ! -s '$DIR/state/alerts.log' ] && grep -q 'real problem one' '$DIR/state/alerts.archive.log'"
ok "F: noop streak flagged, low streak not" "grep -q 'STUCK: ongoing-stuck no-op.d 31 cycles' '$R' && ! grep -q 'ongoing-fine' '$R'"
ok "F: timeout task auto-recovered with doubled timeout" "grep -q 'AUTO-RECOVERED slow-task.*timeout_secs=1800s' '$R'"
ok "F: already-recovered slow2 not recovered again" "! grep -q 'AUTO-RECOVERED slow2' '$R'"
ok "F: healthy task's stale recovery flag cleared" "[ ! -e '$DIR/state/autorecovered_healed' ]"
ok "F: dead-task (non-timeout failures) not recovered" "! grep -q 'AUTO-RECOVERED dead-task' '$R'"
ok "F: grooming proposal surfaced" "grep -q 'backlog grooming proposal' '$R'"
reset_dir
echo '[{"id":"huge","enabled":false,"timeout_secs":1700}]' > "$DIR/tasks.json"; mkdir -p "$DIR/state/failures"; echo 2 > "$DIR/state/failures/huge.count"
printf '| huge | x | error(exit=124) | f | l | 1s |\n| huge | x | error(exit=124) | f | l | 1s |\n' > "$DIR/reports/2026-09-08-0000.md"
OUT="$(RUN)"
ok "F2: doubled timeout capped at 1800" "[ \"\$(jq -r '.[0].timeout_secs' '$DIR/tasks.json')\" = 1800 ]"

echo "$P passed, $F failed"
[ "$F" -eq 0 ]
