#!/usr/bin/env bash
# D1 repair (2026-10-18): the ovn_planner.sh VERIFY-shape-lint hook block, end to end against a MOCKED LiteLLM: the item recount (n), the [decomposed] marking when every item is
# dropped, quarantine, shadow = byte-identical, and the fail-open fall-through when the lint python fails or exceeds OVN_VERIFY_LINT_TIMEOUT. Mutants: each reverts one hunk of a COPY of
# the planner and the same cases must go red. Never touches the box: HOME is a private sandbox (lib_safe_tmp.sh).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
PL="${OVN_PLANNER:-$HERE/../../ovn_planner.sh}"
[ -f "$PL" ] || PL="$HERE/../ovn_planner.sh"
[ -f "$PL" ] || { echo "  SKIP: ovn_planner.sh not found"; exit 0; }
VSL="$HERE/../ovn_verify_shape_lint.py"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(safe_mktemp_dir)" || exit 1
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; safe_rm_rf "$tmp"' EXIT
PORT="${VLP_PORT:-18927}"
cat > "$tmp/mockserver.py" <<'PYEOF2'
import http.server, json, sys
PORT = int(sys.argv[1]); RESP_FILE = sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        ln = int(self.headers.get('Content-Length', 0) or 0)
        self.rfile.read(ln)
        content = open(RESP_FILE).read()
        payload = json.dumps({"choices": [{"message": {"content": content}}]}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_GET(self):
        self.send_response(200); self.end_headers()
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PYEOF2
python3 "$tmp/mockserver.py" "$PORT" "$tmp/resp.txt" >/dev/null 2>&1 &
MOCKPID=$!
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

mkdir -p "$tmp/home/overnight-queue"/{backlog,roadmap,repos,logs,scripts}
WD="$tmp/home/overnight-queue"
cp "$VSL" "$WD/scripts/ovn_verify_shape_lint.py"
# the planner uses GNU `sed -i`; on a BSD sed (macOS) put a tiny shim first on PATH that supplies the empty backup suffix
mkdir -p "$tmp/shim"
if ! sed --version >/dev/null 2>&1; then
  # the planner also prepends /usr/bin to PATH (box layout), which would hide the shim: run a copy with that one line neutralised
  PLX="$tmp/planner_bsdsed.sh"; sed 's|^export PATH=/usr/local/bin:/usr/bin:/bin:\${PATH:-}$|export PATH="${PATH:-}"|' "$PL" > "$PLX" && PL="$PLX"
  printf '#!/bin/bash\nif [ "${1:-}" = "-i" ]; then shift; exec /usr/bin/sed -i "" "$@"; fi\nexec /usr/bin/sed "$@"\n' > "$tmp/shim/sed"; chmod +x "$tmp/shim/sed"
fi
run(){ ( PATH="$tmp/shim:$PATH" HOME="$tmp/home" OVN_MODEL=qwen-dflash-27B LITELLM_BASE="http://127.0.0.1:$PORT" OVN_PLAN_THRESHOLD=10 OVN_PLAN_MAX_PER_RUN=4 \
         OVN_VERIFY_SHAPE_LOG="$WD/state_vsl.log" OVN_VERIFY_ALERTS_LOG="$WD/state_vsl.alerts" bash "$PL" "$@" >/dev/null 2>>"$tmp/run.log" ); }
mk_repo(){ mkdir -p "$WD/repos/$1/scripts"; echo "def f(): pass" > "$WD/repos/$1/scripts/existing.py"
  printf '# backlog\n- [ ] [T1] scripts/x.py — a. VERIFY: t\n' > "$WD/backlog/$1.md"
  printf '# roadmap\n- [ ] [P2] [ready] Feature for %s\n' "$1" > "$WD/roadmap/$1.md"; }
U1='- [ ] [T1] scripts/q1.py — wrap it. VERIFY: `grep -n "_zz.call" scripts/q1.py | grep -q handle_everything`. (cat:python; multifile:no)'
U2='- [ ] [T1] scripts/q2.py — wrap it too. VERIFY: `grep -n "_yy.call" scripts/q2.py | grep -q handle_all_things`. (cat:python; multifile:no)'
U3='- [ ] [T1] scripts/q3.py — and this. VERIFY: `grep -n "_xx.call" scripts/q3.py | grep -q handle_every_thing`. (cat:python; multifile:no)'
W1='- [ ] [T1] scripts/w1.py — add foo. VERIFY: `grep -n "foo" scripts/w1.py | wc -l`. (cat:python; multifile:no)'
C1='- [ ] [T1] scripts/c1.py — add bar. VERIFY: `grep -q "bar" scripts/c1.py`. (cat:python; multifile:no)'

cases(){
  # H: enforce, 1 dropped + 1 rewritten + 1 clean -> 2 appended, the unfixable quarantined, n recounted to 2, roadmap [decomposed]
  mk_repo repoH; printf '%s\n%s\n%s\n' "$U1" "$W1" "$C1" > "$tmp/resp.txt"; : > "$WD/logs/ovn_planner.log"
  OVN_VERIFY_LINT=enforce run repoH
  ok "H: the unfixable item is NOT in the backlog" "! grep -q handle_everything '$WD/backlog/repoH.md'"
  ok "H: the wc item was rewritten to a real assertion and appended" "grep -q -- '-ge 1' '$WD/backlog/repoH.md'"
  ok "H: the clean item is appended untouched" "grep -q 'c1.py' '$WD/backlog/repoH.md'"
  ok "H: n is recounted: log says appended 2" "grep -q 'appended 2 27B-decomposed items' '$WD/logs/ovn_planner.log'"
  ok "H: the log says verify-lint kept 2 of 3" "grep -q 'verify-lint (mode enforce) kept 2 of 3' '$WD/logs/ovn_planner.log'"
  ok "H: the unfixable item is quarantined with a verify-lint tag" "grep -q 'handle_everything.*verify-lint:S1' '$WD/backlog/quarantine/repoH.md'"
  ok "H: the roadmap feature is marked [decomposed]" "grep -q '\[decomposed\] Feature for repoH' '$WD/roadmap/repoH.md'"
  # I: enforce, EVERY item dropped -> nothing appended, quarantined, feature still marked [decomposed]
  mk_repo repoI; printf '%s\n%s\n%s\n' "$U1" "$U2" "$U3" > "$tmp/resp.txt"; : > "$WD/logs/ovn_planner.log"; cp "$WD/backlog/repoI.md" "$tmp/repoI.before"
  OVN_VERIFY_LINT=enforce run repoI
  ok "I: all items dropped -> backlog byte-identical (nothing appended)" "diff -q '$WD/backlog/repoI.md' '$tmp/repoI.before'"
  ok "I: all items dropped -> the feature is marked [decomposed] (not retried forever)" "grep -q '\[decomposed\] Feature for repoI' '$WD/roadmap/repoI.md'"
  ok "I: all three quarantined" "[ \$(grep -c 'verify-lint:S1' '$WD/backlog/quarantine/repoI.md') -eq 3 ]"
  ok "I: the log says every decomposed item was dropped" "grep -q 'verify-lint dropped every decomposed item' '$WD/logs/ovn_planner.log'"
  # J: shadow -> all three appended byte-identical, nothing quarantined
  mk_repo repoJ; printf '%s\n%s\n%s\n' "$U1" "$W1" "$C1" > "$tmp/resp.txt"
  OVN_VERIFY_LINT=shadow run repoJ
  ok "J: shadow appends every item unchanged (wc item NOT rewritten)" "grep -q handle_everything '$WD/backlog/repoJ.md' && grep -q 'wc -l' '$WD/backlog/repoJ.md' && ! grep -q -- '-ge 1' '$WD/backlog/repoJ.md'"
  ok "J: shadow quarantines nothing" "[ ! -s '$WD/backlog/quarantine/repoJ.md' ]"
  ok "J: shadow wrote its findings to the log" "grep -q 'S1' '$WD/state_vsl.log'"
  # K: the lint python FAILS -> fall through, items appended unchanged (fail-open)
  mk_repo repoK; printf '%s\n%s\n%s\n' "$U1" "$W1" "$C1" > "$tmp/resp.txt"
  cp "$WD/scripts/ovn_verify_shape_lint.py" "$tmp/real_vsl.py"
  printf 'import sys\nsys.stdin.read()\nsys.exit(3)\n' > "$WD/scripts/ovn_verify_shape_lint.py"
  OVN_VERIFY_LINT=enforce run repoK
  ok "K: a failing lint python never loses the decomposition (all 3 appended unchanged)" "grep -q handle_everything '$WD/backlog/repoK.md' && grep -q 'c1.py' '$WD/backlog/repoK.md' && ! grep -q -- '-ge 1' '$WD/backlog/repoK.md'"
  ok "K: the feature is marked [decomposed] after the fall-through append" "grep -q '\[decomposed\] Feature for repoK' '$WD/roadmap/repoK.md'"
  # L: the lint python HANGS -> timeout (OVN_VERIFY_LINT_TIMEOUT) cuts it, fall through, bounded
  mk_repo repoL; printf '%s\n%s\n%s\n' "$U1" "$W1" "$C1" > "$tmp/resp.txt"
  printf 'import sys, time\nsys.stdin.read()\ntime.sleep(8)\nprint("- [ ] [T1] never")\n' > "$WD/scripts/ovn_verify_shape_lint.py"
  _t0=$(date +%s); OVN_VERIFY_LINT=enforce OVN_VERIFY_LINT_TIMEOUT=1 run repoL; _dt=$(( $(date +%s) - _t0 ))
  ok "L: a hanging lint is cut at OVN_VERIFY_LINT_TIMEOUT and the items are appended unchanged" "grep -q handle_everything '$WD/backlog/repoL.md' && ! grep -q 'never' '$WD/backlog/repoL.md' && [ $_dt -lt 7 ]"
  cp "$tmp/real_vsl.py" "$WD/scripts/ovn_verify_shape_lint.py"
  # M: off -> hook skipped entirely
  mk_repo repoM; printf '%s\n%s\n%s\n' "$U1" "$W1" "$C1" > "$tmp/resp.txt"; : > "$WD/state_vsl.log"
  rm -f "$tmp/vsl_invoked"
  printf 'import sys\nopen(%s, "w").write("1")\nsys.stdout.write(sys.stdin.read())\n' "\"$tmp/vsl_invoked\"" > "$WD/scripts/ovn_verify_shape_lint.py"
  OVN_VERIFY_LINT=off run repoM
  ok "M: off appends unchanged, logs nothing and never even starts the lint python" "grep -q handle_everything '$WD/backlog/repoM.md' && [ ! -s '$WD/state_vsl.log' ] && [ ! -e '$tmp/vsl_invoked' ]"
  mk_repo repoM
  OVN_VERIFY_LINT=shadow run repoM
  ok "M: control - the same stub IS started in shadow mode" "[ -e '$tmp/vsl_invoked' ]"
}

if [ -n "${VLP_MUTANT:-}" ]; then cases; echo "mutant-run P=$P F=$F"; [ "$F" -eq 0 ]; exit $?; fi
cases
# ---- mutants: revert ONE hunk of a copy of the planner; the same cases must go red
mut(){ # name old new
  local mf="$tmp/planner_mut_$RANDOM.sh"
  python3 - "$PL" "$mf" "$2" "$3" <<'PYEOF3' || { F=$((F+1)); echo "  FAIL: [mut] $1: hunk missing"; return; }
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3], sys.argv[4]
if old not in src:
    sys.exit(1)
open(sys.argv[2], "w").write(src.replace(old, new, 1))
PYEOF3
  ( VLP_MUTANT=1 OVN_PLANNER="$mf" VLP_PORT=$((PORT+1)) bash "$0" >/dev/null 2>&1 )
  if [ $? -ne 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: [mut] $1: cases stayed green"; fi
}
mut "n not recounted after the lint" 'items="$_vsl_out"; n="$_vsl_n"' 'items="$_vsl_out"'
mut "all-dropped feature not marked [decomposed]" '      if [ "${n:-0}" -le 0 ]; then
        sed -i "${fln}s/\[ready\]/[decomposed]/" "$rm"
        say "$r: verify-lint dropped' '      if [ "${n:-0}" -le 0 ]; then
        say "$r: verify-lint dropped'
mut "lint timeout removed" 'timeout "${OVN_VERIFY_LINT_TIMEOUT:-30}" python3' 'python3'
mut "failing lint python no longer falls through" '2>/dev/null)"; then
      _vsl_n=' '2>/dev/null; true)"; then
      _vsl_n='
mut "hook runs even when OVN_VERIFY_LINT=off" 'if [ "${OVN_VERIFY_LINT:-shadow}" != off ] && [ -f "$_vsl_py" ]; then' 'if [ -f "$_vsl_py" ]; then'
echo "test_verify_lint_planner_hook: $P passed, $F failed"
[ "$F" -eq 0 ]
