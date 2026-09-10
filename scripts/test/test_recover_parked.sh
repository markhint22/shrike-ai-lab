#!/usr/bin/env bash
# Regression test: ovn_recover_parked.sh must (a) actually decompose a genuinely stuck AUTO-SKIP
# item into landable sub-items and push them, (b) tag (not silently drop) an item the model can't
# usefully recover so it isn't retried forever, (c) never re-pick an item already tagged
# `recovery:*` (no duplicate LLM spend), and (d) respect OVN_RECOVER_MAX as a real cost-control
# cap across repos in one pass (2026-09-10).
set -uo pipefail
REAL="$HOME/overnight-queue"
SH="$REAL/ovn_recover_parked.sh"
[ -f "$SH" ] || { echo "  SKIP: $SH not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
SANDBOX_HOME="$tmp/home"
OQ="$SANDBOX_HOME/overnight-queue"
mkdir -p "$OQ/repos" "$OQ/state" "$OQ/logs"
cp "$REAL/queue.sh" "$OQ/queue.sh"; chmod +x "$OQ/queue.sh"

# --- fake LiteLLM: serves whatever's currently in $RESP_FILE, logs one line per request ---
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
RESP_FILE="$tmp/resp.txt"; REQLOG="$tmp/reqlog.txt"; : > "$REQLOG"
printf 'placeholder' > "$RESP_FILE"
FAKE_PID=""
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
sleep 0.4
cleanup(){ kill "$FAKE_PID" >/dev/null 2>&1; rm -rf "$tmp"; }
trap cleanup EXIT

new_origin(){ # $1=name $2=progress-file-content
  local o="$tmp/origin_$1.git"
  git init -q --bare "$o"
  local w; w="$(mktemp -d)"
  ( cd "$w" && git init -q -b overnight/feature \
      && git config user.email t@t.com && git config user.name t \
      && printf '%s' "$2" > OVERNIGHT_PROGRESS.md \
      && git add -A && git commit -q -m init \
      && git remote add origin "$o" && git push -q origin overnight/feature )
  git --git-dir="$o" symbolic-ref HEAD refs/heads/overnight/feature
  rm -rf "$w"
  echo "$o"
}
clone_into_repos(){ # $1=repo-name $2=origin-path
  git clone -q "$2" "$OQ/repos/$1"
  ( cd "$OQ/repos/$1" && git checkout -q overnight/feature && git config user.email t@t.com && git config user.name t )
}

run_recover(){ # env RESP + OVN_RECOVER_MAX should be set by caller; $@=repo list
  HOME="$SANDBOX_HOME" LITELLM_BASE="http://127.0.0.1:$PORT" LITELLM_MASTER_KEY=test-key \
    OVN_MODEL=test-model OVN_RECOVER_MAX="${OVN_RECOVER_MAX:-4}" \
    bash "$SH" "$@" >/dev/null 2>&1
}
reqcount(){ wc -l < "$REQLOG" | tr -d ' '; }

STUCK=$'# Progress\n\n- [ ] [AUTO-SKIP after 5 no-op cycles — review] [T4] scripts/hard_thing.gd — this genuinely needs real decomposition work. VERIFY: run tests\n- [ ] [T1] other.py — unrelated real work. VERIFY: pytest -q\n'
ALREADY_TAGGED=$'# Progress\n\n- [ ] [AUTO-SKIP after 5 no-op cycles — review recovery:decomposed] [T4] scripts/x.gd — thing. VERIFY: x\n'

# === A: healthy decompose path ===
oA="$(new_origin A "$STUCK")"
clone_into_repos repoA "$oA"
printf '%s' $'- [ ] [T1] scripts/hard_thing.gd — step one small change. VERIFY: godot --headless test1\n- [ ] [T2] scripts/hard_thing.gd — step two small change. VERIFY: godot --headless test2\n- [ ] [T1] scripts/hard_thing_test.gd — add unit test for step one. VERIFY: godot --headless test1' > "$RESP_FILE"
: > "$REQLOG"
OVN_RECOVER_MAX=4 run_recover repoA
after="$(git --git-dir="$oA" show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "A: made exactly one LLM call for the one eligible item" "[ \"\$(reqcount)\" -eq 1 ]"
ok "A: origin gained the recovery commit" \
   "git --git-dir='$oA' log --oneline overnight/feature | grep -q 'recover parked repoA item -> 3 smaller sub-item'"
ok "A: the original stuck line is checked off, not deleted" \
   "printf '%s' \"$after\" | grep -q -- '- \[x\] \[AUTO-SKIP after 5 no-op cycles'"
ok "A: all 3 recovered sub-items are present as new open items" \
   "[ \$(printf '%s' \"$after\" | grep -cE '^- \[ \] \[T[12]\] scripts/hard_thing') -eq 3 ]"
ok "A: unrelated real work line untouched" "printf '%s' \"$after\" | grep -q 'other.py — unrelated real work'"
ok "A: hold released" "[ ! -f '$OQ/state/HOLD_repoA' ]"

# === B: model gives no usable recovery -> tag recovery:none, don't drop the item silently ===
oB="$(new_origin B "$STUCK")"
clone_into_repos repoB "$oB"
printf '%s' 'I cannot decide what to do with this, sorry.' > "$RESP_FILE"
: > "$REQLOG"
OVN_RECOVER_MAX=4 run_recover repoB
afterB="$(git --git-dir="$oB" show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "B: still made the one LLM call" "[ \"\$(reqcount)\" -eq 1 ]"
ok "B: parked line is tagged recovery:none (not silently dropped)" \
   "printf '%s' \"$afterB\" | grep -q -- '\[AUTO-SKIP recovery:none after 5 no-op cycles'"
ok "B: line is still open (not checked off — nothing was actually recovered)" \
   "printf '%s' \"$afterB\" | grep -q -- '- \[ \] \[AUTO-SKIP.*recovery:none'"
ok "B: origin got the recovery-attempted commit" \
   "git --git-dir='$oB' log --oneline overnight/feature | grep -q 'recovery-attempted (no decomposition)'"
ok "B: hold released" "[ ! -f '$OQ/state/HOLD_repoB' ]"
ok "B: a no-op recovery does not count toward the run's recovered total" \
   "grep -q 'recover-parked pass complete (recovered 0 this run)' '$OQ/logs/ovn_recover_parked.log'"

# === C: an item already tagged recovery:* must NEVER be re-picked (no duplicate LLM spend) ===
oC="$(new_origin C "$ALREADY_TAGGED")"
clone_into_repos repoC "$oC"
: > "$REQLOG"
OVN_RECOVER_MAX=4 run_recover repoC
ok "C: zero LLM calls made for an already-tagged item" "[ \"\$(reqcount)\" -eq 0 ]"
ok "C: origin has no new commit (repo was never even touched)" \
   "[ \"\$(git --git-dir='$oC' log --oneline overnight/feature | wc -l)\" -eq 1 ]"
ok "C: hold was never even acquired for a repo with nothing eligible" "[ ! -f '$OQ/state/HOLD_repoC' ]"

# === D: OVN_RECOVER_MAX is a real cross-repo cost cap, not per-repo ===
oD1="$(new_origin D1 "$STUCK")"; clone_into_repos repoD1 "$oD1"
oD2="$(new_origin D2 "$STUCK")"; clone_into_repos repoD2 "$oD2"
printf '%s' $'- [ ] [T1] scripts/hard_thing.gd — step one. VERIFY: t1\n- [ ] [T2] scripts/hard_thing.gd — step two. VERIFY: t2' > "$RESP_FILE"
: > "$REQLOG"
OVN_RECOVER_MAX=1 run_recover repoD1 repoD2
ok "D: exactly one LLM call across the whole pass (cap=1 honored)" "[ \"\$(reqcount)\" -eq 1 ]"
ok "D: repoD1 got recovered" "git --git-dir='$oD1' log --oneline overnight/feature | grep -q 'recover parked'"
ok "D: repoD2 was never even touched once the cap was hit" \
   "[ \"\$(git --git-dir='$oD2' log --oneline overnight/feature | wc -l)\" -eq 1 ]"

echo "Recover parked: $P passed, $F failed"
[ "$F" -eq 0 ]
