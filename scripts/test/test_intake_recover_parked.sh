#!/usr/bin/env bash
# Regression test: ovn_recover_parked.sh, intake package (2026-10-13).
#  F2  the hard-ban short-circuit matched the WHOLE item text as a substring, so the GUT runner named in a VERIFY (addons/gut/gut_cmdln.gd) matched the vendored-code ban `addons/` and a 'Create test X'
#      item was escalated as hard-banned with no LLM call. Now only the text before VERIFY: is checked (a real banned TARGET still escalates). OVN_PARK_VERIFY_SCOPE=off restores the old scan.
#  F5  the decomposition copies the parent's VERIFY, so `cd /path/to/xlite && ...` / `cd tests && godot -s test_x.gd` survived into every child. Now repaired (ovn_spec_gate.py recover-lint);
#      OVN_RECOVER_VERIFY_LINT=off|repair|enforce.
# Runs the REAL script of this tree against a sandbox HOME (fake LiteLLM, bare origin repos), like test_recover_parked.sh.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
QD="$(cd "$HERE/../.." && pwd)"
SH="$QD/ovn_recover_parked.sh"
[ -f "$SH" ] || { echo "  SKIP: $SH not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
SANDBOX_HOME="$tmp/home"; OQ="$SANDBOX_HOME/overnight-queue"
mkdir -p "$OQ/repos" "$OQ/state" "$OQ/logs" "$OQ/scripts"
cp "$QD/queue.sh" "$OQ/queue.sh"; chmod +x "$OQ/queue.sh"
cp "$QD/ovn_park_unworkable.py" "$OQ/ovn_park_unworkable.py"
for f in lib_worktree.sh lib_path_normalize.sh ovn_log_tokens.sh ovn_gradle_flavor_guard.sh ovn_spec_gate.py ovn_spec_rules.py ovn_backlog_eligibility.py ovn_gut_clause.py ovn_spec_classify.py; do
  [ -f "$QD/scripts/$f" ] && cp "$QD/scripts/$f" "$OQ/scripts/$f"
done
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
RESP_FILE="$tmp/resp.txt"; REQLOG="$tmp/reqlog.txt"; : > "$REQLOG"; printf 'placeholder' > "$RESP_FILE"
cat > "$tmp/fake_litellm.py" <<'PY_EOF'
import http.server, json, sys
port = int(sys.argv[1]); resp_file = sys.argv[2]; reqlog = sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0)); self.rfile.read(length)
        with open(reqlog, 'a', encoding='utf-8') as f: f.write('req\n')
        content = open(resp_file, encoding='utf-8').read()
        body = json.dumps({"choices": [{"message": {"content": content}}]}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PY_EOF
python3 "$tmp/fake_litellm.py" "$PORT" "$RESP_FILE" "$REQLOG" & FAKE_PID=$!
sleep 0.5
trap 'kill "$FAKE_PID" >/dev/null 2>&1; rm -rf "$tmp"' EXIT
new_origin(){ # $1=name $2=progress content ; the repo carries the vendored-code ban + a GUT project
  local o="$tmp/origin_$1.git"; git init -q --bare "$o"; local w; w="$(safe_mktemp_dir)" || exit 1
  ( cd "$w" && git init -q -b overnight/feature && git config user.email t@t.com && git config user.name t \
      && printf '%s' "$2" > OVERNIGHT_PROGRESS.md && printf '# vendored\naddons/\n' > .queue-hard-banned-files \
      && mkdir -p addons/gut tests && printf 'x' > addons/gut/gut_cmdln.gd && printf 'x' > addons/gut/gut.gd \
      && printf 'extends GutTest\nfunc test_a():\n\tpass\n' > tests/test_a.gd \
      && git add -A && git commit -q -m init && git remote add origin "$o" && git push -q origin overnight/feature )
  git --git-dir="$o" symbolic-ref HEAD refs/heads/overnight/feature; rm -rf "$w"; echo "$o"
}
clone_into_repos(){ git clone -q "$2" "$OQ/repos/$1"; ( cd "$OQ/repos/$1" && git checkout -q overnight/feature && git config user.email t@t.com && git config user.name t ); }
run_recover(){ HOME="$SANDBOX_HOME" LITELLM_BASE="http://127.0.0.1:$PORT" LITELLM_MASTER_KEY=test-key OVN_MODEL=test-model OVN_RECOVER_MAX=4 bash "$SH" "$@" >/dev/null 2>&1; }
reqcount(){ wc -l < "$REQLOG" | tr -d ' '; }
progress(){ git --git-dir="$1" show overnight/feature:OVERNIGHT_PROGRESS.md; }

RUN='godot --headless -s addons/gut/gut_cmdln.gd'
CREATE=$'# Progress\n\n- [ ] [AUTO-SKIP after 5 no-op cycles — review] [T4] tests/test_new.gd — Create a GUT test that checks the helper. VERIFY: `'"$RUN"$' -gtest=res://tests/test_new.gd -gexit`. (cat:test; multifile:no)\n'
CHILDREN=$'- [ ] [T2] tests/test_new.gd — step one: create the test file with one case. VERIFY: `cd /path/to/xlite && '"$RUN"$' -gtest=res://tests/test_new.gd -gexit`. (cat:test; recovery:decomposed)\n- [ ] [T2] tests/test_new.gd — step two: add the second case. VERIFY: `cd tests && godot --headless -s test_a.gd`. (cat:test; recovery:decomposed)'

echo "== F2: hard-ban check scans only the text before VERIFY:"
oG="$(new_origin G "$CREATE")"; clone_into_repos repoG "$oG"
printf '%s' "$CHILDREN" > "$RESP_FILE"; : > "$REQLOG"
run_recover repoG
ok "[F2] a 'Create test X' item whose VERIFY names addons/gut/gut_cmdln.gd is DECOMPOSED (an LLM call was made), not escalated as hard-banned" "[ \"\$(reqcount)\" -eq 1 ]"
ok "[F2] no 'hard-banned' escalation line was written" "[ \"\$(progress '$oG' | grep -c 'hard-banned from automated edits')\" -eq 0 ]"
oG2="$(new_origin G2 "$CREATE")"; clone_into_repos repoG2 "$oG2"; : > "$REQLOG"
OVN_PARK_VERIFY_SCOPE=off run_recover repoG2
ok "[mut] OVN_PARK_VERIFY_SCOPE=off restores the old whole-text scan: escalated as hard-banned, no LLM call" "[ \"\$(reqcount)\" -eq 0 ] && [ \"\$(progress '$oG2' | grep -c 'hard-banned from automated edits')\" -ge 1 ]"
BANNED_T=$'# Progress\n\n- [ ] [AUTO-SKIP after 5 no-op cycles — review] [T3] addons/gut/gut.gd — change the vendored runner. VERIFY: `grep -c x addons/gut/gut.gd`. (cat:test)\n'
oH="$(new_origin H "$BANNED_T")"; clone_into_repos repoH "$oH"; : > "$REQLOG"
run_recover repoH
ok "a REAL banned target (before the VERIFY) is still escalated without an LLM call" "[ \"\$(reqcount)\" -eq 0 ] && [ \"\$(progress '$oH' | grep -c 'hard-banned from automated edits')\" -ge 1 ]"

echo "== F5: a decomposed child never inherits a VERIFY that can never run"
after="$(progress "$oG")"
ok "[F5] the placeholder cd is gone from the written child" "[ \"\$(printf '%s' \"\$after\" | grep -c '/path/to/')\" -eq 0 ]"
ok "[F5] the written children run through the GUT runner with a res:// target" "[ \"\$(printf '%s' \"\$after\" | grep -cE '^- \\[ \\] \\[T2\\] tests/test_new.gd.*gut_cmdln.gd .*-gtest=res://tests/test_new.gd')\" -eq 1 ] && [ \"\$(printf '%s' \"\$after\" | grep -cE '^- \\[ \\] \\[T2\\] tests/test_new.gd.*-gtest=res://tests/test_a.gd')\" -eq 1 ]"
ok "[F5] no child still runs a test file as a script (godot -s test_a.gd)" "[ \"\$(printf '%s' \"\$after\" | grep -cE 'godot --headless -s test_a.gd')\" -eq 0 ]"
oI="$(new_origin I "$CREATE")"; clone_into_repos repoI "$oI"; : > "$REQLOG"
OVN_RECOVER_VERIFY_LINT=off run_recover repoI
afterI="$(progress "$oI")"
ok "[mut] OVN_RECOVER_VERIFY_LINT=off: the children keep the broken clauses (old behaviour)" "[ \"\$(printf '%s' \"\$afterI\" | grep -c '/path/to/xlite')\" -ge 1 ]"
UNFIX='- [ ] [T2] tests/test_new.gd — step one. VERIFY: `grep -q x /path/to/xlite/tests/test_new.gd`. (cat:test; recovery:decomposed)'
printf '%s' "$UNFIX" > "$RESP_FILE"
oJ="$(new_origin J "$CREATE")"; clone_into_repos repoJ "$oJ"; : > "$REQLOG"
run_recover repoJ
ok "repair mode (default) keeps a child that still cannot run (shadow) and logs it" "[ \"\$(progress '$oJ' | grep -c 'grep -q x /path/to/xlite')\" -ge 1 ] && grep -q 'kept (shadow)' '$OQ/logs/ovn_recover_parked.log'"
oK="$(new_origin K "$CREATE")"; clone_into_repos repoK "$oK"; : > "$REQLOG"
OVN_RECOVER_VERIFY_LINT=enforce run_recover repoK
afterK="$(progress "$oK")"
ok "enforce mode: nothing runnable left -> one [CLAUDE] escalation line instead of the unrunnable child" "[ \"\$(printf '%s' \"\$afterK\" | grep -c 'grep -q x /path/to/xlite')\" -eq 0 ] && [ \"\$(printf '%s' \"\$afterK\" | grep -c 'VERIFY can never run')\" -ge 1 ]"

echo "Intake recover parked: $P passed, $F failed"
[ "$F" -eq 0 ]
