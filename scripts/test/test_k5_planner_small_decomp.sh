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
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
sed --version >/dev/null 2>&1 || { echo "  NOT RUN: GNU sed required (ovn_planner.sh uses sed -i; box-only, like test_ovn_planner.sh)"; exit 77; }
PL="${OVN_PLANNER:-$HERE/../../ovn_planner.sh}"
[ -f "$PL" ] || PL="$HERE/../ovn_planner.sh"
[ -f "$PL" ] || { echo "  SKIP: ovn_planner.sh not found"; exit 0; }
P=0; F=0
if [ -n "${K5_MUTANT:-}" ]; then :; fi
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(safe_mktemp_dir)" || exit 1
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$tmp"' EXIT

# --- mock LiteLLM: serves POST /v1/chat/completions with content from $tmp/resp.txt; logs one
#     line per request to $tmp/reqlog.txt so we can assert the model was (or wasn't) called ---
PORT="${K5_PORT:-18947}"
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


# ============ K5 (2026-11-01): a feature accepted as a SMALL decomposition (1-2 valid items on the 2nd miss) is marked on its roadmap line ============
mk_repo_files repoH
printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n' > "$WD/backlog/repoH.md"
printf '# roadmap\n- [ ] [P3] [ready] Tiny one-line cleanup of the console output in the status page — remove it {cat: web; size: S}\n- [ ] [P3] [ready] Unrelated second feature\n' > "$WD/roadmap/repoH.md"
cat > "$tmp/resp.txt" <<'RESP'
- [ ] [T1] scripts/tiny.py — remove the stray print. VERIFY: python -c 'import tiny'. (cat:python; multifile:no)
- [ ] [T1] scripts/tiny2.py — drop the second print. VERIFY: python -c 'import tiny2'. (cat:python; multifile:no)
RESP
run repoH
ok "H1: 1st miss (2 valid items) leaves the feature [ready] and unmarked" "grep -q '\[ready\] Tiny one-line cleanup' '$WD/roadmap/repoH.md' && ! grep -q 'small-decomposition' '$WD/roadmap/repoH.md'"
run repoH
ok "H2: 2nd miss accepts the 2 items and marks the feature [decomposed]" "grep -q '\[decomposed\] Tiny one-line cleanup' '$WD/roadmap/repoH.md' && grep -q 'scripts/tiny2.py' '$WD/backlog/repoH.md'"
ok "H3: the roadmap line records ' [small-decomposition n=2]' at its END" "grep -qE 'Tiny one-line cleanup.*\{cat: web; size: S\} \[small-decomposition n=2\]\$' '$WD/roadmap/repoH.md'"
ok "H4: the other [ready] line is untouched" "grep -q '^- \[ \] \[P3\] \[ready\] Unrelated second feature\$' '$WD/roadmap/repoH.md'"
ok "H5: the planner log says so" "grep -q 'repoH: recorded small-decomposition (n=2)' '$WD/logs/ovn_planner.log'"
ok "H6: the [feat:] tag on the items is the slug of the unmarked feature text" "grep -q '\[feat:repoH-[0-9]*-tiny-one-line-cleanup-of-the-console-out\]' '$WD/backlog/repoH.md'"

# a healthy 3-item decomposition is NOT marked
mk_repo_files repoI
printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n' > "$WD/backlog/repoI.md"
printf '# roadmap\n- [ ] [P2] [ready] A normal sized feature\n' > "$WD/roadmap/repoI.md"
cat > "$tmp/resp.txt" <<'RESP'
- [ ] [T2] scripts/n1.py — add a pure function. VERIFY: pytest -k n1. (cat:python; multifile:no)
- [ ] [T1] scripts/n2.py — add validation. VERIFY: python -c 'import n2'. (cat:python; multifile:no)
- [ ] [T3] scripts/n3.py — wire the endpoint. VERIFY: curl localhost/n3. (cat:endpoint; multifile:no)
RESP
run repoI
ok "I1: a 3-item decomposition is decomposed without any small-decomposition marker" "grep -q '\[decomposed\] A normal sized feature\$' '$WD/roadmap/repoI.md' && ! grep -q 'small-decomposition' '$WD/roadmap/repoI.md'"

# the marker can be switched off
mk_repo_files repoJ
printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n' > "$WD/backlog/repoJ.md"
printf '# roadmap\n- [ ] [P3] [ready] Another tiny feature\n' > "$WD/roadmap/repoJ.md"
cat > "$tmp/resp.txt" <<'RESP'
- [ ] [T1] scripts/j1.py — one change. VERIFY: python -c 'import j1'. (cat:python; multifile:no)
RESP
OVN_PLANNER_SMALL_MARK=off run repoJ
OVN_PLANNER_SMALL_MARK=off run repoJ
ok "J1: OVN_PLANNER_SMALL_MARK=off accepts the small decomposition but writes no marker" "grep -q '\[decomposed\] Another tiny feature\$' '$WD/roadmap/repoJ.md' && grep -q 'scripts/j1.py' '$WD/backlog/repoJ.md'"

echo "  K5 planner: $P passed, $F failed"
[ "$F" = 0 ] || exit 1
# ---- mutant proof: each planner mutant must make this suite FAIL (children run with K5_PL_MUTANT=1 and skip this block)
[ -n "${K5_PL_MUTANT:-}" ] && exit 0
bad=0
mut(){ # $1=name $2=python-literal old $3=python-literal new
  local mp="$tmp/planner_mut.sh"
  python3 - "$PL" "$mp" "$2" "$3" <<'PYM' || { echo "  MUTANT SETUP FAIL: $1"; bad=$((bad+1)); return; }
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3], sys.argv[4]
if old not in src:
    sys.exit(1)
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PYM
  if K5_PL_MUTANT=1 K5_PORT=$((18950 + RANDOM % 300)) OVN_PLANNER="$mp" bash "$0" >/dev/null 2>&1; then echo "  SURVIVED MUTANT $1"; bad=$((bad+1)); else echo "  killed   MUTANT $1"; fi
}
mut "planner never records the marker" '[ "$_small_decomp" = 1 ] &&' '[ "$_small_decomp" = 99 ] &&'
mut "planner marks every decomposition as small" '_small_decomp=0
' '_small_decomp=1
'
mut "planner ignores OVN_PLANNER_SMALL_MARK=off" '"${OVN_PLANNER_SMALL_MARK:-on}" != off' '"${OVN_PLANNER_SMALL_MARK:-on}" != nevermatch'
mut "planner puts the marker before the title (breaks the [P#] [status] prefix)" 'sed -i "${fln}s/\$/ [small-decomposition n=${n}]/" "$rm"' 'sed -i "${fln}s/\] \[decomposed\] /] [decomposed] [small-decomposition n=${n}] /" "$rm"'
echo "  planner mutants survived: $bad"
[ "$bad" = 0 ]
