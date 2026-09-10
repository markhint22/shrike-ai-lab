#!/usr/bin/env bash
# Regression test: groom.sh — the daily backlog-grooming pass that compares each repo's Next Steps
# against real repo state and writes a review PROPOSAL (never auto-applies — proposal-mode by
# design). Bugs here could either silently skip repos that need grooming, or (worse) groom a
# disabled/nonexistent repo and burn a model call for nothing.
#
# Verifies against a MOCKED LiteLLM (a tiny local HTTP server), never a live model call:
#  A. LiteLLM unreachable -> the whole pass exits cleanly with NO reports written and NO
#     state/grooming_pending written (safe no-op, doesn't crash the cron job).
#  B. healthy path: an enabled aider_fix repo with a "## Next Steps" section gets a report written
#     containing both the deterministic-stale section and the LLM proposal, and
#     state/grooming_pending reflects the count.
#  C. the actual guard this script exists for — deterministic stale-item detection: a "delete/remove
#     <file>" Next Steps item whose target file is ALREADY GONE from the repo must be surfaced in
#     the report's "Deterministically stale" section regardless of what the LLM says (objective,
#     not a matter of LLM judgment).
#  D. repos that must NEVER be groomed: disabled tasks, repos with no OVERNIGHT_PROGRESS.md, and
#     repos whose progress doc has no "## Next Steps" section at all.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="${OVN_GROOM:-$HERE/../../groom.sh}"
[ -f "$G" ] || G="$HERE/../groom.sh"
[ -f "$G" ] || { echo "  SKIP: groom.sh not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$tmp"' EXIT

PORT=18915
cat > "$tmp/mockserver.py" <<'PYEOF2'
import http.server, json, sys
PORT = int(sys.argv[1]); RESP_FILE = sys.argv[2]; REQLOG = sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        if self.path.startswith('/health'):
            self.send_response(200); self.end_headers(); return
        self.send_response(200); self.end_headers()
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
srv = http.server.HTTPServer(('127.0.0.1', PORT), H)
srv.serve_forever()
PYEOF2

mk_git_repo(){  # $1=path
  mkdir -p "$1"
  ( cd "$1" && git init -q && git config user.email t@t.com && git config user.name t )
}

# ============ A: LiteLLM unreachable -> safe no-op, nothing written ============
DIR="$tmp/ovnA"; mkdir -p "$DIR/state" "$DIR/reports"
mk_git_repo "$tmp/repoA"
echo "kept.py" > /dev/null; echo "print(1)" > "$tmp/repoA/kept.py"
cat > "$tmp/repoA/OVERNIGHT_PROGRESS.md" <<'DOC'
## Next Steps
1. Add validation to kept.py
DOC
cat > "$DIR/tasks.json" <<JSON
[{"id":"a","type":"aider_fix","enabled":true,"repo":"$tmp/repoA"}]
JSON
rc=0
OVERNIGHT_DIR="$DIR" LITELLM_BASE="http://127.0.0.1:19999" bash "$G" >/dev/null 2>&1 || rc=$?
ok "A: unreachable LiteLLM -> exits 0 (doesn't crash the cron job)" "[ '$rc' -eq 0 ]"
ok "A: unreachable LiteLLM -> no report written" "[ -z \"\$(ls -A '$DIR/reports' 2>/dev/null)\" ]"
ok "A: unreachable LiteLLM -> grooming_pending never written" "[ ! -f '$DIR/state/grooming_pending' ]"

# ============ start mock server for the remaining scenarios ============
: > "$tmp/reqlog.txt"
python3 "$tmp/mockserver.py" "$PORT" "$tmp/resp.txt" "$tmp/reqlog.txt" >/dev/null 2>&1 &
MOCKPID=$!
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/health/liveliness" && break; sleep 0.1; done
printf '1. Add validation to kept.py (quick win, unchanged)\n2. New item: add a test for kept.py\n' > "$tmp/resp.txt"

# ============ B: healthy path + C: deterministic stale detection (combined repo, both checked) ============
DIR2="$tmp/ovnB"; mkdir -p "$DIR2/state" "$DIR2/reports"
mk_git_repo "$tmp/repoB"
echo "print(1)" > "$tmp/repoB/kept.py"
cat > "$tmp/repoB/OVERNIGHT_PROGRESS.md" <<'DOC'
## Next Steps
1. Delete legacy_helper.py (unused since the rewrite)
2. Add validation to kept.py
## Notes
irrelevant
DOC
cat > "$DIR2/tasks.json" <<JSON
[{"id":"b","type":"aider_fix","enabled":true,"repo":"$tmp/repoB"}]
JSON
DATE="$(date +%Y%m%d)"
OVERNIGHT_DIR="$DIR2" LITELLM_BASE="http://127.0.0.1:$PORT" bash "$G" >/dev/null 2>&1
rpt="$DIR2/reports/grooming-repoB-${DATE}.md"
ok "B: a report file is written for the enabled repo" "[ -f '$rpt' ]"
ok "B: report contains the LLM proposal section" "grep -q 'Proposed' '$rpt'"
ok "B: report contains the proposal content from the (mocked) model" "grep -q 'New item: add a test for kept.py' '$rpt'"
ok "B: report echoes the current Next Steps verbatim" "grep -q 'Add validation to kept.py' '$rpt'"
ok "B: grooming_pending reflects exactly 1 report" "[ \"\$(cat '$DIR2/state/grooming_pending')\" = '1' ]"
ok "C: deterministically-stale section present" "grep -q 'Deterministically stale' '$rpt'"
ok "C: the stale item (target file already gone) is surfaced" "grep -q 'legacy_helper.py' '$rpt'"
ok "C: the stale flag is objective (in the stale section), regardless of the LLM proposal" \
   "sed -n '/Deterministically stale/,/Current Next Steps/p' '$rpt' | grep -q 'Delete legacy_helper.py'"

# ============ D: repos that must never be groomed ============
DIR3="$tmp/ovnD"; mkdir -p "$DIR3/state" "$DIR3/reports"
mk_git_repo "$tmp/repoDisabled"
cat > "$tmp/repoDisabled/OVERNIGHT_PROGRESS.md" <<'DOC'
## Next Steps
1. Some item
DOC
mk_git_repo "$tmp/repoNoDoc"   # no OVERNIGHT_PROGRESS.md at all
mk_git_repo "$tmp/repoNoNextSteps"
cat > "$tmp/repoNoNextSteps/OVERNIGHT_PROGRESS.md" <<'DOC'
## Status
Nothing to see here, no Next Steps section.
DOC
cat > "$DIR3/tasks.json" <<JSON
[
  {"id":"d1","type":"aider_fix","enabled":false,"repo":"$tmp/repoDisabled"},
  {"id":"d2","type":"aider_fix","enabled":true,"repo":"$tmp/repoNoDoc"},
  {"id":"d3","type":"aider_fix","enabled":true,"repo":"$tmp/repoNoNextSteps"}
]
JSON
OVERNIGHT_DIR="$DIR3" LITELLM_BASE="http://127.0.0.1:$PORT" bash "$G" >/dev/null 2>&1
ok "D: disabled task -> no report" "[ ! -f '$DIR3/reports/grooming-repoDisabled-${DATE}.md' ]"
ok "D: repo missing OVERNIGHT_PROGRESS.md -> no report" "[ ! -f '$DIR3/reports/grooming-repoNoDoc-${DATE}.md' ]"
ok "D: repo with no '## Next Steps' section -> no report" "[ ! -f '$DIR3/reports/grooming-repoNoNextSteps-${DATE}.md' ]"
ok "D: grooming_pending is 0 when nothing was groomed" "[ \"\$(cat '$DIR3/state/grooming_pending')\" = '0' ]"

echo "groom: $P passed, $F failed"
[ "$F" -eq 0 ]
