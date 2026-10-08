#!/usr/bin/env bash
# Extra coverage for ovn_recover_parked.sh (wave 3, w3b): lineage cap, hard-banned escalation, target-file
# grounding variants, gradle guard, alembic-dropped guard, already-satisfied filter, recovery:none tagging,
# worktree-open / push failure ladders. Fake LiteLLM on 127.0.0.1 (ephemeral port); everything in a temp HOME.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SH="$ROOT/ovn_recover_parked.sh"
for l in lib_worktree.sh lib_path_normalize.sh; do [ -f "$ROOT/scripts/$l" ] || { echo "SKIP: $l missing"; exit 0; }; done
[ -f "$SH" ] || { echo "SKIP: $SH not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
SANDBOX_HOME="$tmp/home"; OQ="$SANDBOX_HOME/overnight-queue"
mkdir -p "$OQ/repos" "$OQ/state" "$OQ/logs" "$OQ/scripts"
cp "$ROOT/scripts/lib_worktree.sh" "$ROOT/scripts/lib_path_normalize.sh" "$OQ/scripts/"
cat > "$OQ/queue.sh" <<'EOF2'
#!/usr/bin/env bash
case "$1" in hold) : > "$(dirname "$0")/state/HOLD_$2";; release) rm -f "$(dirname "$0")/state/HOLD_$2";; esac
exit 0
EOF2
printf '#!/usr/bin/env bash\necho "$*" >> "$(dirname "$0")/../tok.log"\n' > "$OQ/scripts/ovn_log_tokens.sh"
# gradle guard stub: passes input through, upper-cases nothing, but prints a note on stderr
cat > "$OQ/scripts/ovn_gradle_flavor_guard.sh" <<'EOF2'
#!/usr/bin/env bash
buf="$(cat)"
if [ "${GUARD_MODE:-pass}" = empty ]; then exit 0; fi
printf '%s\n' "$buf"
[ "${GUARD_MODE:-pass}" = note ] && echo "guard: rewrote 1 gradle task" >&2
exit 0
EOF2
chmod +x "$OQ/queue.sh" "$OQ/scripts/"*.sh

PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
RESP_FILE="$tmp/resp.txt"; REQLOG="$tmp/reqlog.txt"; : > "$REQLOG"; printf 'x' > "$RESP_FILE"
PROMPTS="$tmp/prompts.txt"
cat > "$tmp/fake_litellm.py" <<'PY_EOF'
import http.server, json, sys
port = int(sys.argv[1]); resp_file = sys.argv[2]; reqlog = sys.argv[3]; prompts = sys.argv[4]
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get('Content-Length', 0)); raw = self.rfile.read(length)
        with open(reqlog, 'a', encoding='utf-8') as f: f.write('req\n')
        try:
            msg = json.loads(raw)['messages'][0]['content']
            with open(prompts, 'a', encoding='utf-8') as f: f.write(msg + '\n=====\n')
        except Exception: pass
        content = open(resp_file, encoding='utf-8').read()
        body = json.dumps({"choices": [{"message": {"content": content}}], "usage": {"prompt_tokens": 11, "completion_tokens": 7}}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.HTTPServer(('127.0.0.1', port), H).serve_forever()
PY_EOF
python3 "$tmp/fake_litellm.py" "$PORT" "$RESP_FILE" "$REQLOG" "$PROMPTS" & FAKE_PID=$!
# wait for the fake server to actually accept connections (a fixed `sleep 0.5` raced python startup under CPU load: the first LLM call was refused
# and the 'recovered' / 'empty guard' cases failed ~1 run in 3 with the box busy - h13 review)
for _w in $(seq 1 100); do python3 -c "import socket,sys; socket.create_connection(('127.0.0.1',int(sys.argv[1])),0.2).close()" "$PORT" 2>/dev/null && break; sleep 0.1; done
cleanup(){ kill "$FAKE_PID" >/dev/null 2>&1; rm -rf "$tmp" /tmp/wt-w3b* 2>/dev/null; }
trap cleanup EXIT

new_repo(){ # $1=name $2=progress content ; extra files via $3 "path=content" optional
  local n="$1" o="$tmp/origin_$1.git"
  git init -q --bare "$o"
  local w; w="$(mktemp -d)"
  ( cd "$w" && git init -q -b overnight/feature && printf '%s' "$2" > OVERNIGHT_PROGRESS.md \
      && mkdir -p src && printf 'def real():\n    return `${x}` and 1\n' > src/real.py && echo k > keep.txt \
      && git add -A && git commit -q -m init && git remote add origin "$o" && git push -q origin overnight/feature )
  git --git-dir="$o" symbolic-ref HEAD refs/heads/overnight/feature
  rm -rf "$w"
  git clone -q "$o" "$OQ/repos/$n" && ( cd "$OQ/repos/$n" && git checkout -q overnight/feature )
}
rr(){ HOME="$SANDBOX_HOME" LITELLM_BASE="http://127.0.0.1:$PORT" LITELLM_MASTER_KEY=k OVN_MODEL=m bash "$SH" "$@" >/dev/null 2>&1; }
# capture first, then print in ONE write: under `set -o pipefail` a `glog X | grep -q ...` got SIGPIPE (rc 141) whenever grep matched the first line and
# exited before git log wrote its remaining lines - a load-dependent flake (4 of 12 runs with the box CPU-starved; h13 review)
show(){ local o; o="$(git --git-dir="$tmp/origin_$1.git" show overnight/feature:OVERNIGHT_PROGRESS.md)"; printf '%s\n' "$o"; }
glog(){ local o; o="$(git --git-dir="$tmp/origin_$1.git" log --oneline overnight/feature)"; printf '%s\n' "$o"; }
LOGF="$OQ/logs/ovn_recover_parked.log"
reqcount(){ wc -l < "$REQLOG" | tr -d ' '; }
park(){ printf '# Progress\n\n- [ ] [AUTO-SKIP after 5 no-op cycles — review] [T4] %s\n' "$1"; }

# ---- 1: nonexistent target + already-satisfied filter + gradle-guard note ----
new_repo r1 "$(park 'app/new_thing.py — implement the new thing with validation. VERIFY: pytest -q')
- [x] [T1] app/done_already.py — earlier landed work. VERIFY: pytest
"
printf '%s' $'- [ ] [CLAUDE] part of this needs a human (recovery:escalated)\n- [ ] [T1] app/done_already.py — re-propose done work. VERIFY: pytest x\n- [ ] [T2] app/new_thing.py — add validation. VERIFY: pytest y\n- [ ] [T2] tidy up general docs without a path VERIFY: make docs' > "$RESP_FILE"
: > "$REQLOG"; : > "$PROMPTS"
GUARD_MODE=note rr r1
out="$(show r1)"
ok "1: one LLM call" "[ \"\$(reqcount)\" -eq 1 ]"
ok "1: prompt says target does not exist yet" "grep -q 'app/new_thing.py does not exist yet' '$PROMPTS'"
ok "1: already-checked-off target dropped" "! printf '%s' \"\$out\" | grep -q 're-propose done work'"
ok "1: drop logged" "grep -q 'dropping recovered sub-item already checked off' '$LOGF'"
ok "1: [CLAUDE] escalation kept" "printf '%s' \"\$out\" | grep -q 'part of this needs a human'"
ok "1: fresh target kept" "printf '%s' \"\$out\" | grep -q 'add validation'"
ok "1: path-less item kept" "printf '%s' \"\$out\" | grep -q 'tidy up general docs'"
ok "1: gradle guard note logged" "grep -q 'r1: guard: rewrote 1 gradle task' '$LOGF'"
ok "1: original stuck line checked off" "printf '%s' \"\$out\" | grep -q -- '- \[x\] \[AUTO-SKIP'"
ok "1: token ledger call recorded 11/7" "grep -q 'recover_parked r1 11 7' '$OQ/tok.log'"

# ---- 2: existing target file is quoted (backticks safe) ----
new_repo r2 "$(park 'src/real.py — extend the real function with a guard. VERIFY: pytest -q')"
printf '%s' $'- [ ] [T1] src/real.py — add guard. VERIFY: pytest a\n- [ ] [T2] src/real.py — add doc. VERIFY: pytest b' > "$RESP_FILE"
: > "$PROMPTS"; GUARD_MODE=pass rr r2
ok "2: prompt embeds CURRENT CONTENT incl. backtick source" "grep -q 'CURRENT CONTENT of src/real.py' '$PROMPTS' && grep -qF '\${x}' '$PROMPTS'"
ok "2: recovered 2 items" "glog r2 | grep -q 'recover parked r2 item -> 2 smaller'"

# ---- 3: absolute / traversal target refused ----
new_repo r3 "$(park '/abs/elsewhere/file.py — weird absolute target path. VERIFY: pytest -q')"
printf '%s' $'- [ ] [T1] src/real.py — add guard. VERIFY: pytest a' > "$RESP_FILE"
: > "$PROMPTS"; rr r3
ok "3: absolute target -> 'could not determine a single target file'" "grep -q 'could not determine a single target file' '$PROMPTS'"

# ---- 4: alembic guard ----
new_repo r4 "$(park 'models/x.py — add columns and run alembic revision --autogenerate -m add_cols. VERIFY: alembic upgrade head')"
printf '%s' $'- [ ] [T1] models/x.py — add columns only. VERIFY: python -c "import models.x"' > "$RESP_FILE"
rr r4
ok "4: dropped-alembic decomposition escalated" "show r4 | grep -q 'dropped the required Alembic migration step'"
ok "4: escalation logged" "grep -q 'dropped the original item.s Alembic migration step' '$LOGF'"
new_repo r4b "$(park 'models/x.py — add columns and run alembic revision --autogenerate -m add_cols. VERIFY: alembic upgrade head')"
printf '%s' $'- [ ] [T1] models/x.py — add columns. VERIFY: alembic revision --autogenerate -m a && pytest q' > "$RESP_FILE"
rr r4b
ok "4b: decomposition that keeps alembic is NOT escalated" "! show r4b | grep -q 'dropped the required Alembic'"

# ---- 5: lineage cap escalation (no LLM call) ----
new_repo r5 "$(park 'src/real.py — capped lineage item needing escalation. VERIFY: pytest -q')"
: > "$REQLOG"; OVN_RECOVER_LINEAGE_CAP=0 rr r5
ok "5: cap exceeded -> no LLM call" "[ \"\$(reqcount)\" -eq 0 ]"
ok "5: cap escalation item written" "show r5 | grep -q 'recovered/decomposed 1 times (cap 0)'"
ok "5: cap logged" "grep -q \"lineage 'r5__src_real.py' exceeded recovery cap\" '$LOGF'"
ok "5: lineage counter persisted" "[ \"\$(cat '$OQ/state/recovery_lineage/r5__src_real.py.count')\" = 1 ]"

# ---- 6: hard-banned file ----
new_repo r6 "$(park 'src/real.py — touches banned battle.gd wiring. VERIFY: pytest -q')"
printf '# banned list\n\n   \nbattle.gd\n' > "$OQ/repos/r6/.queue-hard-banned-files"
: > "$REQLOG"; rr r6
ok "6: banned file -> no LLM call" "[ \"\$(reqcount)\" -eq 0 ]"
ok "6: banned escalation written" "show r6 | grep -q 'battle.gd is hard-banned'"
ok "6: logged" "grep -q \"targets hard-banned file 'battle.gd'\" '$LOGF'"
new_repo r6b "$(park 'src/real.py — a fine item without a banned word. VERIFY: pytest -q')"
printf 'nothing-matches-here\n' > "$OQ/repos/r6b/.queue-hard-banned-files"
printf '%s' $'- [ ] [T1] src/real.py — add guard. VERIFY: pytest a' > "$RESP_FILE"
: > "$REQLOG"; rr r6b
ok "6b: ban list without a hit -> normal LLM path" "[ \"\$(reqcount)\" -eq 1 ]"

# ---- 7: model gives nothing usable / everything filtered -> recovery:none ----
new_repo r7 "$(park 'src/real.py — stubborn item that the model cannot split. VERIFY: pytest -q')"
printf '%s' 'cannot help' > "$RESP_FILE"; rr r7
ok "7: tagged recovery:none" "show r7 | grep -q 'AUTO-SKIP recovery:none'"
new_repo r7b "$(park 'src/real.py — stubborn item, model only re-proposes done work. VERIFY: pytest -q')
- [x] [T1] src/real.py — already landed. VERIFY: pytest
"
printf '%s' $'- [ ] [T1] src/real.py — redo landed work. VERIFY: pytest x' > "$RESP_FILE"; rr r7b
ok "7b: every sub-item filtered out -> recovery:none" "show r7b | grep -q 'AUTO-SKIP recovery:none'"

# ---- 8: push rejected ----
new_repo r8 "$(park 'src/real.py — none path with a rejected push. VERIFY: pytest -q')"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/origin_r8.git/hooks/pre-receive"; chmod +x "$tmp/origin_r8.git/hooks/pre-receive"
printf '%s' 'cannot help' > "$RESP_FILE"; rr r8
ok "8: none-tag push failure logged non-fatally" "grep -q 'r8: recovery:none tag push failed' '$LOGF'"
new_repo r8b "$(park 'src/real.py — decompose path with a rejected push. VERIFY: pytest -q')"
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/origin_r8b.git/hooks/pre-receive"; chmod +x "$tmp/origin_r8b.git/hooks/pre-receive"
printf '%s' $'- [ ] [T1] src/real.py — add guard. VERIFY: pytest a' > "$RESP_FILE"; rr r8b
ok "8b: decomposed push failure logged" "grep -q 'r8b: recovered sub-items built but push failed' '$LOGF'"
ok "8b: hold released after failure" "[ ! -f '$OQ/state/HOLD_r8b' ]"

# ---- 9: worktree open failures (origin/overnight/feature ref gone locally) ----
new_repo r9 "$(park 'src/real.py — none path, worktree cannot open. VERIFY: pytest -q')"
git -C "$OQ/repos/r9" update-ref -d refs/remotes/origin/overnight/feature
printf '%s' 'cannot help' > "$RESP_FILE"; rr r9
ok "9: none path worktree failure logged" "grep -q 'r9: worktree open failed — could not tag recovery:none' '$LOGF'"
new_repo r9b "$(park 'src/real.py — decompose path, worktree cannot open. VERIFY: pytest -q')"
git -C "$OQ/repos/r9b" update-ref -d refs/remotes/origin/overnight/feature
printf '%s' $'- [ ] [T1] src/real.py — add guard. VERIFY: pytest a' > "$RESP_FILE"; rr r9b
ok "9b: decompose path worktree failure logged" "grep -q 'r9b: worktree open failed — recovered sub-items NOT written' '$LOGF'"
ok "9b: hold released" "[ ! -f '$OQ/state/HOLD_r9b' ]"

# ---- 10: gradle guard present but empty output never wipes items; misc skips ----
new_repo r10 "$(park 'src/real.py — guard prints nothing item. VERIFY: pytest -q')"
printf '%s' $'- [ ] [T1] src/real.py — add guard. VERIFY: pytest a' > "$RESP_FILE"; GUARD_MODE=empty rr r10
ok "10: empty guard output keeps the original items" "glog r10 | grep -q 'recover parked r10 item -> 1 smaller'"
new_repo r11 $'# P\n\n- [ ] [AUTO-SKIP x] short\n'
: > "$REQLOG"; rr nonexistent_repo r11
ok "11: missing repo and too-short task both skipped without an LLM call" "[ \"\$(reqcount)\" -eq 0 ]"
ok "11: pass completes" "tail -1 '$LOGF' | grep -q 'recover-parked pass complete'"
new_repo r12 "$(park 'src/real.py — cap test item one. VERIFY: pytest -q')"
new_repo r13 "$(park 'src/real.py — cap test item two. VERIFY: pytest -q')"
printf '%s' $'- [ ] [T1] src/real.py — add guard. VERIFY: pytest a' > "$RESP_FILE"; : > "$REQLOG"
OVN_RECOVER_MAX=1 rr r12 r13
ok "12: OVN_RECOVER_MAX=1 stops after the first recovered repo" "[ \"\$(reqcount)\" -eq 1 ]"

echo "$P passed, $F failed"
[ "$F" -eq 0 ]
