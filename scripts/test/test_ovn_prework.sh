#!/usr/bin/env bash
# Regression test: ovn_prework.sh — the 27B does the legwork on a Claude-bound task (relevant files,
# current state, approach, draft) so Claude spends minimal tokens picking it up. Bugs here mean
# Claude either gets a garbage briefing or a task silently vanishes from the shared prework queue.
# Exercises real behavior against a MOCKED LiteLLM (a tiny local HTTP server), never a live call.
#
# Verifies:
#  A. single-shot healthy path: writes prework/<repo>-<slug>.md with all 5 required sections, and
#     the slug is a sane lowercased/hyphenated/length-capped filename component.
#  B. the actual guard this script exists for: a too-short model response (<200 chars, i.e. a
#     degenerate/garbage briefing) must NOT be written to disk at all.
#  C. queue mode respects OVN_PREWORK_MAX per run and correctly requeues leftover lines (not lost,
#     not duplicated) for the next run.
#  D. queue mode: a task whose model call fails (too-short response) is put BACK in the queue for
#     retry rather than silently dropped.
#  E. FIXED BUG (2026-09-10): a task for a repo with no clone yet is also requeued, not dropped —
#     do_one's "no clone" branch used to `return` bare (inheriting `say`'s exit 0), making it look
#     like a success and silently vanish from queue.tsv. Fixed with an explicit `return 1`.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PW="${OVN_PREWORK:-$HERE/../../ovn_prework.sh}"
[ -f "$PW" ] || PW="$HERE/../ovn_prework.sh"
[ -f "$PW" ] || { echo "  SKIP: ovn_prework.sh not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$tmp"' EXIT

PORT=18914
cat > "$tmp/mockserver.py" <<'PYEOF2'
import http.server, json, sys
PORT = int(sys.argv[1]); RESP_FILE = sys.argv[2]; REQLOG = sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        ln = int(self.headers.get('Content-Length', 0) or 0)
        self.rfile.read(ln)
        with open(REQLOG, 'a') as lf: lf.write("1\n")
        with open(RESP_FILE) as f: content = f.read()
        payload = json.dumps({"choices": [{"message": {"content": content}}]}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)
    def do_GET(self):
        self.send_response(200); self.end_headers()
srv = http.server.HTTPServer(('127.0.0.1', PORT), H)
srv.serve_forever()
PYEOF2
: > "$tmp/reqlog.txt"
python3 "$tmp/mockserver.py" "$PORT" "$tmp/resp.txt" "$tmp/reqlog.txt" >/dev/null 2>&1 &
MOCKPID=$!
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

mkdir -p "$tmp/home/overnight-queue"/{prework,logs,repos/demo-repo}
WD="$tmp/home/overnight-queue"
echo "def handler(): return 200" > "$WD/repos/demo-repo/routes.py"
run(){ ( HOME="$tmp/home" OVN_MODEL=qwen-dflash-27B LITELLM_BASE="http://127.0.0.1:$PORT" \
          bash "$PW" "$@" >"$tmp/stdout.txt" 2>>"$tmp/run.log" ); }

longresp(){
  python3 -c "print('## Relevant files\n- routes.py: handles the endpoint\n## Current state\n- no validation exists\n## Approach\n1. add a check\n2. add a test\n## Draft\n\`\`\`python\ndef check(): pass\n\`\`\`\n## Risks / unknowns\n- none' + ('x'*250))"
}

# ============ A: single-shot healthy path ============
longresp > "$tmp/resp.txt"
run demo-repo "Add input validation to the /submit endpoint in routes.py"
out="$(cat "$tmp/stdout.txt")"
ok "A: prints the briefing path to stdout" "[ -n '$out' ]"
ok "A: the briefing file actually exists" "[ -f '$WD/$out' ]"
ok "A: briefing filename is under prework/" "[[ '$out' == prework/demo-repo-* ]]"
ok "A: slug is lowercased/hyphenated (no raw spaces or slashes)" "[[ '$out' != *' '* ]] && [[ '$out' != */submit* ]]"
ok "A: slug length is capped (filename component <= ~60 chars incl prefix)" "[ \${#out} -le 75 ]"
ok "A: briefing has the Relevant files section" "grep -q '## Relevant files' '$WD/$out'"
ok "A: briefing has the Current state section" "grep -q '## Current state' '$WD/$out'"
ok "A: briefing has the Approach section" "grep -q '## Approach' '$WD/$out'"
ok "A: briefing has the Draft section" "grep -q '## Draft' '$WD/$out'"
ok "A: briefing has the Risks / unknowns section" "grep -q '## Risks / unknowns' '$WD/$out'"
ok "A: briefing header names the source repo" "grep -q 'Repo: demo-repo' '$WD/$out'"
ok "A: briefing header flags itself as 27B-generated / needs review" "grep -qi 'REVIEW' '$WD/$out'"

# ============ B: the guard — a too-short (garbage) model response must NOT be written ============
rm -rf "$WD/prework"/*
printf 'nope' > "$tmp/resp.txt"   # 4 chars, well under the 200-char floor
: > "$tmp/reqlog.txt"
rc=0
run demo-repo "Some other task that gets a garbage response" || rc=$?
ok "B: too-short response -> do_one returns failure (rc != 0)" "[ '$rc' -ne 0 ]"
ok "B: too-short response -> no briefing file written" "[ -z \"\$(ls -A '$WD/prework' 2>/dev/null)\" ]"
ok "B: too-short response -> logged as skipped" "grep -q 'model returned too little' '$WD/logs/ovn_prework.log'"

# ============ C: queue mode respects OVN_PREWORK_MAX and requeues leftovers ============
rm -rf "$WD/prework"/*
longresp > "$tmp/resp.txt"
printf 'demo-repo\tTask one for the queue\ndemo-repo\tTask two for the queue\ndemo-repo\tTask three for the queue\n' > "$WD/prework/queue.tsv"
: > "$tmp/reqlog.txt"
OVN_PREWORK_MAX=2 run
ok "C: exactly 2 briefings generated (MAX=2)" "[ \$(ls '$WD/prework'/demo-repo-task-* 2>/dev/null | wc -l) -eq 2 ]"
ok "C: exactly 1 task line left in the queue for next run" "[ \$(grep -c . '$WD/prework/queue.tsv') -eq 1 ]"
ok "C: the leftover queue line is 'Task three' (untouched order)" "grep -q 'Task three' '$WD/prework/queue.tsv'"
ok "C: 'Task one' and 'Task two' are NOT still queued (consumed)" "! grep -q 'Task one' '$WD/prework/queue.tsv' && ! grep -q 'Task two' '$WD/prework/queue.tsv'"

# ============ D: queue mode — a model-call failure re-queues the task instead of dropping it ============
rm -rf "$WD/prework"/*
printf 'nope' > "$tmp/resp.txt"   # every call in this run fails (too short)
printf 'demo-repo\tA task whose model call will fail\n' > "$WD/prework/queue.tsv"
OVN_PREWORK_MAX=2 run
ok "D: failed task is requeued, not dropped" "grep -q 'A task whose model call will fail' '$WD/prework/queue.tsv'"
ok "D: no briefing was produced for the failed task" "[ -z \"\$(ls -A '$WD/prework' | grep -v queue.tsv)\" ]"

# ============ E: FIXED BUG regression guard (2026-09-10) — a task for a repo with no clone yet
#     must be requeued for retry, not silently dropped. `do_one`'s "no clone" branch used to do a
#     bare `return` (no explicit code), which inherits the preceding `say` call's exit status (0),
#     making do_one look like a SUCCESS in queue mode — the task vanished from queue.tsv instead of
#     waiting for the clone to exist. Fixed with an explicit `return 1`. ============
rm -rf "$WD/prework"/*
longresp > "$tmp/resp.txt"
printf 'no-such-repo\tA task for a repo that has not been cloned yet\n' > "$WD/prework/queue.tsv"
OVN_PREWORK_MAX=2 run
ok "E: no-clone task is requeued, not dropped (was silently lost before the fix)" \
   "grep -q 'A task for a repo that has not been cloned yet' '$WD/prework/queue.tsv'"
ok "E: no briefing was produced for the no-clone task" "[ -z \"\$(ls -A '$WD/prework' | grep -v queue.tsv)\" ]"
ok "E: logged as no-clone" "grep -q 'no-such-repo: no clone' '$WD/logs/ovn_prework.log'"

echo "ovn_prework: $P passed, $F failed"
[ "$F" -eq 0 ]
