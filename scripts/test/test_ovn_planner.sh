#!/usr/bin/env bash
# Regression test: ovn_planner.sh — the auto-planning layer that decomposes a [ready] roadmap
# feature into backlog items when a repo's backlog runs low. Bugs here silently misdirect the fleet
# (wrong repo planned, malformed LLM output corrupting the human-curated backlog, wrong roadmap line
# marked [decomposed]), so this exercises real file-state behavior end-to-end against a MOCKED
# LiteLLM (a tiny local HTTP server), never a live model call.
#
# Verifies:
#  A. backlog already >= PLAN_THRESHOLD -> skipped WITHOUT ever calling the model (no network hit).
#  B. below threshold but no [ready] roadmap feature -> skipped, no model call, no changes.
#  C. neediest-repo-first ordering + MAX_PER_RUN cap: of two eligible repos, only the one with the
#     LOWER backlog count is processed when the cap is 1 — regardless of arg order.
#  D. healthy path: a well-formed LLM decomposition (>=3 valid item lines) gets appended to the
#     backlog and marks ONLY the matched roadmap line [decomposed] (a second [ready] line for a
#     different feature is left untouched).
#  E. the actual failure mode this script exists to guard against: a malformed/too-short LLM
#     response (fewer than 3 well-formed item lines) must NOT be appended to the backlog, and the
#     roadmap feature must remain [ready] (not falsely marked [decomposed]).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PL="${OVN_PLANNER:-$HERE/../../ovn_planner.sh}"
[ -f "$PL" ] || PL="$HERE/../ovn_planner.sh"
[ -f "$PL" ] || { echo "  SKIP: ovn_planner.sh not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$tmp"' EXIT

# --- mock LiteLLM: serves POST /v1/chat/completions with content from $tmp/resp.txt; logs one
#     line per request to $tmp/reqlog.txt so we can assert the model was (or wasn't) called ---
PORT=18913
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

# --- sandbox: ovn_planner.sh hardcodes `cd "$HOME/overnight-queue"`, so point HOME at our sandbox ---
mkdir -p "$tmp/home/overnight-queue"/{backlog,roadmap,repos,logs}
WD="$tmp/home/overnight-queue"
run(){ ( HOME="$tmp/home" OVN_MODEL=qwen-dflash-27B LITELLM_BASE="http://127.0.0.1:$PORT" \
          OVN_PLAN_THRESHOLD="${OVN_PLAN_THRESHOLD:-10}" OVN_PLAN_MAX_PER_RUN="${OVN_PLAN_MAX_PER_RUN:-4}" \
          bash "$PL" "$@" >/dev/null 2>>"$tmp/run.log" ); }

mk_repo_files(){  # $1=repo name — a minimal source layout so `layout` isn't empty
  mkdir -p "$WD/repos/$1/scripts"
  echo "def f(): pass" > "$WD/repos/$1/scripts/existing.py"
}

# ============ A: backlog already >= threshold -> no model call, no changes ============
mk_repo_files repoA
printf '# backlog\n%s\n' "$(for i in $(seq 1 10); do echo "- [ ] [T1] scripts/x$i.py — thing $i. VERIFY: t"; done)" > "$WD/backlog/repoA.md"
cp "$WD/backlog/repoA.md" "$tmp/repoA.before"
printf '# roadmap\n- [ ] [P2] [ready] Some big feature\n' > "$WD/roadmap/repoA.md"
: > "$tmp/reqlog.txt"
run repoA
ok "A: over-threshold backlog is never touched" "diff -q '$WD/backlog/repoA.md' '$tmp/repoA.before'"
ok "A: over-threshold backlog never calls the model" "[ ! -s '$tmp/reqlog.txt' ]"
ok "A: roadmap feature stays [ready] (not decomposed)" "grep -q '\[ready\] Some big feature' '$WD/roadmap/repoA.md'"

# ============ B: below threshold, but no [ready] feature -> no model call, no changes ============
mk_repo_files repoB
printf '# backlog\n- [ ] [T1] scripts/x.py — thing. VERIFY: t\n' > "$WD/backlog/repoB.md"
cp "$WD/backlog/repoB.md" "$tmp/repoB.before"
printf '# roadmap\n- [ ] [P2] [decomposed] Already handled feature\n' > "$WD/roadmap/repoB.md"
: > "$tmp/reqlog.txt"
run repoB
ok "B: no [ready] feature -> backlog untouched" "diff -q '$WD/backlog/repoB.md' '$tmp/repoB.before'"
ok "B: no [ready] feature -> model never called" "[ ! -s '$tmp/reqlog.txt' ]"

# ============ C: neediest-first ordering + MAX_PER_RUN=1 cap ============
mk_repo_files repoNeedy; mk_repo_files repoFull
printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n- [ ] [T1] scripts/y.py — b. VERIFY: t\n' > "$WD/backlog/repoNeedy.md"   # 2 items (neediest)
printf '# backlog\n%s\n' "$(for i in 1 2 3 4 5; do echo "- [ ] [T1] scripts/z$i.py — thing $i. VERIFY: t"; done)" > "$WD/backlog/repoFull.md"  # 5 items
printf '# roadmap\n- [ ] [P2] [ready] Needy feature\n' > "$WD/roadmap/repoNeedy.md"
printf '# roadmap\n- [ ] [P2] [ready] Full feature\n' > "$WD/roadmap/repoFull.md"
cat > "$tmp/resp.txt" <<'RESP'
- [ ] [T2] scripts/new1.py — add a pure function. VERIFY: pytest -k new1. (cat:python; multifile:no)
- [ ] [T1] scripts/new2.py — add validation. VERIFY: python -c 'import new2'. (cat:python; multifile:no)
- [ ] [T3] scripts/new3.py — wire the endpoint. VERIFY: curl localhost/new3. (cat:endpoint; multifile:no)
RESP
: > "$tmp/reqlog.txt"
run repoFull repoNeedy   # intentionally passed in "wrong" (non-needy-first) order
ok "C: MAX_PER_RUN=4 (default) processed both eligible repos" "[ \$(wc -l < '$tmp/reqlog.txt') -eq 2 ]"

# re-run fresh with cap=1 to prove ordering: only the neediest (repoNeedy) gets processed
printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n- [ ] [T1] scripts/y.py — b. VERIFY: t\n' > "$WD/backlog/repoNeedy.md"
printf '# backlog\n%s\n' "$(for i in 1 2 3 4 5; do echo "- [ ] [T1] scripts/z$i.py — thing $i. VERIFY: t"; done)" > "$WD/backlog/repoFull.md"
printf '# roadmap\n- [ ] [P2] [ready] Needy feature\n' > "$WD/roadmap/repoNeedy.md"
printf '# roadmap\n- [ ] [P2] [ready] Full feature\n' > "$WD/roadmap/repoFull.md"
: > "$tmp/reqlog.txt"
OVN_PLAN_MAX_PER_RUN=1 run repoFull repoNeedy
ok "C: cap=1 calls the model exactly once (only the neediest repo)" "[ \$(wc -l < '$tmp/reqlog.txt') -eq 1 ]"
ok "C: the NEEDIEST repo (fewer backlog items) is the one processed" "grep -q 'new1.py' '$WD/backlog/repoNeedy.md'"
ok "C: the fuller repo is left untouched despite being listed first in args" "! grep -q 'new1.py' '$WD/backlog/repoFull.md'"
ok "C: fuller repo's roadmap feature remains [ready]" "grep -q '\[ready\] Full feature' '$WD/roadmap/repoFull.md'"

# ============ D: healthy decomposition — appended to backlog, ONLY the matched roadmap line marked [decomposed] ============
mk_repo_files repoD
printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n' > "$WD/backlog/repoD.md"
printf '# roadmap\n- [ ] [P2] [ready] Target feature to decompose\n- [ ] [P3] [ready] A different unrelated feature\n' > "$WD/roadmap/repoD.md"
: > "$tmp/reqlog.txt"
run repoD
ok "D: model called exactly once for repoD" "[ \$(wc -l < '$tmp/reqlog.txt') -eq 1 ]"
ok "D: all 3 well-formed items appended to the backlog" "[ \$(grep -cE '^- \[ \] \[T[1-5]\]' '$WD/backlog/repoD.md') -eq 4 ]"
ok "D: appended header attributes the decomposition to the source feature" "grep -q '27B-decomposed from roadmap' '$WD/backlog/repoD.md'"
ok "D: the matched roadmap line is marked [decomposed]" "grep -q '\[decomposed\] Target feature to decompose' '$WD/roadmap/repoD.md'"
ok "D: the UNRELATED roadmap line is left [ready] (only the matched line changes)" "grep -q '\[ready\] A different unrelated feature' '$WD/roadmap/repoD.md'"

# ============ E: the guard this script exists for — malformed/too-short LLM output must NOT land ============
mk_repo_files repoE
printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n' > "$WD/backlog/repoE.md"
cp "$WD/backlog/repoE.md" "$tmp/repoE.before"
printf '# roadmap\n- [ ] [P2] [ready] A feature that gets a bad decomposition\n' > "$WD/roadmap/repoE.md"
cat > "$tmp/resp.txt" <<'RESP'
Sure! Here's a rough plan for that feature:
- [ ] [T2] scripts/ok1.py — the only well-formed line. VERIFY: pytest -k ok1
1. refactor the whole auth module (no VERIFY, not a real item line)
Some closing remarks about the approach.
RESP
: > "$tmp/reqlog.txt"
run repoE
ok "E: model was still called" "[ -s '$tmp/reqlog.txt' ]"
ok "E: too-few-valid-items response is NOT appended to backlog" "diff -q '$WD/backlog/repoE.md' '$tmp/repoE.before'"
ok "E: roadmap feature stays [ready] (NOT falsely marked [decomposed])" "grep -q '\[ready\] A feature that gets a bad decomposition' '$WD/roadmap/repoE.md'"
ok "E: log records why it was rejected" "grep -q 'NOT appending' '$WD/logs/ovn_planner.log'"

echo "ovn_planner: $P passed, $F failed"
[ "$F" -eq 0 ]
