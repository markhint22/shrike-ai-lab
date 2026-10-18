#!/usr/bin/env bash
# 2026-10-11 (delplan X5): ovn_planner.sh's deterministic delete bypass (OVN_PLANNER_DELETE_BYPASS=off|shadow|on, default shadow) against a MOCKED LiteLLM. A roadmap feature that is a pure
# file delete gets ONE `Delete the file` item per path from `ovn_delete_executor.py plan` and no model call; every doubt falls through to the model exactly as before.
# Needs GNU sed (the planner marks the roadmap with `sed -i`), flock and a GNU userland: run it on the box (the Mac copy skips with a note).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
PL="${OVN_PLANNER:-$HERE/../../ovn_planner.sh}"; [ -f "$PL" ] || PL="$HERE/../ovn_planner.sh"
EXD="$HERE/../ovn_delete_executor.py"
[ -f "$PL" ] || { echo "  SKIP: ovn_planner.sh not found"; exit 0; }
if ! sed --version >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1; then echo "  SKIP: needs GNU sed + flock (run on the box)"; exit 0; fi
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$tmp"' EXIT
PORT=18931
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
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_GET(self):
        self.send_response(200); self.end_headers()
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PYEOF2
: > "$tmp/reqlog.txt"
cat > "$tmp/resp.txt" <<'RESP'
- [ ] [T1] scripts/model_one.gd — Add one. VERIFY: `grep -q one scripts/model_one.gd`. (cat:godot; multifile:no)
- [ ] [T1] scripts/model_two.gd — Add two. VERIFY: `grep -q two scripts/model_two.gd`. (cat:godot; multifile:no)
- [ ] [T2] scripts/model_three.gd — Add three. VERIFY: `grep -q three scripts/model_three.gd`. (cat:godot; multifile:no)
RESP
python3 "$tmp/mockserver.py" "$PORT" "$tmp/resp.txt" "$tmp/reqlog.txt" >/dev/null 2>&1 &
MOCKPID=$!
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

WD="$tmp/home/overnight-queue"
mkdir -p "$WD"/{backlog,roadmap,repos,logs,scripts}; cp "$EXD" "$WD/scripts/ovn_delete_executor.py"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
mkrepo(){  # real git repo repos/xl with an orphan, a used file and a file deleted in history
  rm -rf "${WD:?}/repos/xl"; mkdir -p "$WD/repos/xl/scripts/battle" "$WD/repos/xl/scripts/save"; cd "$WD/repos/xl" || exit 1
  git init -q . ; git config user.email t@t; git config user.name t
  printf 'extends Node\n' > scripts/battle/save_manager.gd
  printf 'extends Node\n' > scripts/save/save_manager.gd
  printf '[autoload]\nSaveManager="*res://scripts/save/save_manager.gd"\n' > project.godot
  printf 'class_name Used\nextends Node\n' > scripts/used.gd
  printf 'extends Node\nvar u = Used.new()\n' > scripts/user.gd
  printf 'extends Node\n' > scripts/gone.gd
  git add -A; git commit -q -m base; git rm -q scripts/gone.gd; git commit -q -m "rm gone"
}
run(){ ( cd "$tmp" && HOME="$tmp/home" OVN_MODEL=m LITELLM_BASE="http://127.0.0.1:$PORT" OVN_PLAN_THRESHOLD=10 OVN_PLAN_MAX_PER_RUN=4 "$@" bash "${PLANNER:-$PL}" xl >/dev/null 2>>"$tmp/run.log" ); }
setup(){  # $1 = feature text
  mkrepo; : > "$tmp/reqlog.txt"; : > "$WD/logs/ovn_planner.log"; rm -rf "${WD:?}/state"
  printf '# backlog\n' > "$WD/backlog/xl.md"
  printf '# roadmap\n- [ ] [P2] [ready] %s\n- [ ] [P3] [ready] Another feature stays untouched\n' "$1" > "$WD/roadmap/xl.md"
}
calls(){ wc -l < "$tmp/reqlog.txt" | tr -d ' '; }
FEAT_OK='Delete orphan `scripts/battle/save_manager.gd` — a stub duplicate of scripts/save/save_manager.gd that nothing loads. VERIFY: `test ! -f scripts/battle/save_manager.gd` exits 0. {cat: game; size: S; multifile: no; research: none}'

# ---- on: pure delete, safe -> no model call, one item ----
setup "$FEAT_OK"; run env OVN_PLANNER_DELETE_BYPASS=on
ok "on: the model is never called" "[ \"\$(calls)\" = 0 ]"
ok "on: exactly one item appended: the verbatim delete item with the [feat:] tag" "[ \"\$(grep -c '^- \\[ \\] \\[T1\\] scripts/battle/save_manager.gd — Delete the file. VERIFY: \`test ! -f scripts/battle/save_manager.gd\`. (cat:refactor; multifile:no) \\[feat:xl-[0-9]*-delete-orphan-scripts-battle-[a-z0-9-]*\\]\$' '$WD/backlog/xl.md')\" = 1 ] && [ \"\$(grep -c '^- \\[ \\]' '$WD/backlog/xl.md')\" = 1 ]"
ok "on: a '# --- 27B-decomposed from roadmap' header precedes it (same shape as a model decomposition)" "grep -q '^# --- 27B-decomposed from roadmap \\[' '$WD/backlog/xl.md'"
ok "on: ONLY the matched roadmap line is marked [decomposed]" "grep -q '^- \\[ \\] \\[P2\\] \\[decomposed\\] Delete orphan' '$WD/roadmap/xl.md' && grep -q '^- \\[ \\] \\[P3\\] \\[ready\\] Another feature stays untouched' '$WD/roadmap/xl.md'"
ITEMLINE="$(grep '^- \[ \] \[T1\] scripts/battle/save_manager.gd' "$WD/backlog/xl.md")"
ok "on: the appended item is accepted by the delete executor's own check (the DELETE-EXECUTOR block will act on it)" "[ \"\$(python3 '$EXD' check '$WD/repos/xl' '$ITEMLINE')\" = \$'OK\\tscripts/battle/save_manager.gd' ]"
ok "on: the planner log says so" "grep -q 'delete-plan (on): 1 deterministic delete item' '$WD/logs/ovn_planner.log' && grep -q 'appended 1 27B-decomposed items' '$WD/logs/ovn_planner.log'"

# ---- shadow (default): the model still decomposes, the log shows what would have happened ----
setup "$FEAT_OK"; run env -u OVN_PLANNER_DELETE_BYPASS
ok "default (shadow): the model IS called and its 3 items are appended, the delete item is not" "[ \"\$(calls)\" = 1 ] && [ \"\$(grep -c '^- \\[ \\]' '$WD/backlog/xl.md')\" = 3 ] && ! grep -q 'Delete the file' '$WD/backlog/xl.md'"
ok "default (shadow): the log records 'delete-plan (shadow): 1 deterministic delete item'" "grep -q 'delete-plan (shadow): 1 deterministic delete item' '$WD/logs/ovn_planner.log'"
setup "$FEAT_OK"; run env OVN_PLANNER_DELETE_BYPASS=off
ok "off: no delete-plan line at all, model decomposes" "[ \"\$(calls)\" = 1 ] && ! grep -q 'delete-plan' '$WD/logs/ovn_planner.log'"

# ---- on, but the safety checks decline: the model path, unchanged ----
setup 'Delete `scripts/used.gd` — dead. VERIFY: `test ! -f scripts/used.gd`.'; run env OVN_PLANNER_DELETE_BYPASS=on
ok "a path referenced elsewhere (Used.new() in user.gd): declined, the model decomposes, nothing was deleted by the planner" "[ \"\$(calls)\" = 1 ] && grep -q 'delete-plan declined (scripts/used.gd: referenced by: scripts/user.gd)' '$WD/logs/ovn_planner.log' && [ -f '$WD/repos/xl/scripts/used.gd' ]"
setup 'Refactor the save system. {cat: dead-code; size: S}'; run env OVN_PLANNER_DELETE_BYPASS=on
ok "a non-delete feature: declined, the model decomposes (regression: the normal path is untouched)" "[ \"\$(calls)\" = 1 ] && [ \"\$(grep -c '^- \\[ \\]' '$WD/backlog/xl.md')\" = 3 ] && grep -q 'delete-plan declined' '$WD/logs/ovn_planner.log'"
setup 'Delete scripts/gone.gd — already removed. VERIFY: `test ! -f scripts/gone.gd`.'; run env OVN_PLANNER_DELETE_BYPASS=on
ok "every path already gone (deleted in history): no model call, no items, the feature is marked [decomposed]" "[ \"\$(calls)\" = 0 ] && [ \"\$(grep -c '^- \\[ \\]' '$WD/backlog/xl.md')\" = 0 ] && grep -q '^- \\[ \\] \\[P2\\] \\[decomposed\\] Delete scripts/gone.gd' '$WD/roadmap/xl.md' && grep -q 'already satisfied' '$WD/logs/ovn_planner.log'"

# ---- wiring: a missing executor script never costs the planner its decomposition ----
setup "$FEAT_OK"; mv "$WD/scripts/ovn_delete_executor.py" "$WD/scripts/ovn_delete_executor.py.off"; run env OVN_PLANNER_DELETE_BYPASS=on
ok "executor script absent: silently the model path" "[ \"\$(calls)\" = 1 ] && [ \"\$(grep -c '^- \\[ \\]' '$WD/backlog/xl.md')\" = 3 ]"
mv "$WD/scripts/ovn_delete_executor.py.off" "$WD/scripts/ovn_delete_executor.py"
ok "the prompt region is still byte-for-byte what it was (the golden prompt test covers it)" "bash '$HERE/test_planner_prompt_golden.sh' >/dev/null 2>&1"

# ---- MUTATION: without the `on` assignment the bypass never produces items ----
sed 's/\[ "\$_dp_mode" = on \] && _det_items=/false \&\& _det_items=/' "$PL" > "$tmp/mut_planner.sh"
setup "$FEAT_OK"; PLANNER="$tmp/mut_planner.sh" run env OVN_PLANNER_DELETE_BYPASS=on
ok "MUTATION: with the on-branch neutralised the model IS called (the 'never called' assertion above would fail)" "[ \"\$(calls)\" = 1 ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
