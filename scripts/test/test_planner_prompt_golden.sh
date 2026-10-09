#!/usr/bin/env bash
# Regression test: ovn_planner.sh prompt + spec-gate lint hook (spec-compiler-v2 C5, 2026-10-09).
#  1. GOLDEN prompt: the text the planner sends the model equals the pre-change prompt (embedded below, captured from the planner at f50ea04 for this fixture) EXCEPT for exactly
#     two new hard rules: "An item that only Verifies/Ensures/Checks is forbidden" and "For a Delete feature the FIRST items remove every reference ...; the LAST item deletes the
#     definition". No other prompt change. Mutation: drop one new rule from a copy of the planner and the golden comparison fails.
#  2. After the ground guard and before feat tagging the items go through `ovn_spec_gate.py lint` (static repairs R01-R03, only for rules in OVN_SPEC_GATE_ENFORCE_RULES).
#     Fail-safe: a crashing, silent or missing lint can never lose or alter a decomposition.
# A stub LiteLLM (python http.server) returns a fixed completion and records the request. (On macOS the planner's own `sed -i` marking step is BSD-incompatible; nothing here
# depends on it.)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$(cd "$HERE/.." && pwd)"
PL="${OVN_PLANNER:-$HERE/../../ovn_planner.sh}"
[ -f "$PL" ] || { echo "  SKIP: ovn_planner.sh not found"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "  SKIP: jq not installed"; exit 0; }
command -v flock >/dev/null 2>&1 || { echo "  SKIP: flock not installed"; exit 0; }
P=0; F=0
# assertions are evaluated with pipefail OFF (under pipefail `A | grep -q X` is flaky: grep -q exits at its first hit and A may take SIGPIPE)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; tmp="$(cd "$tmp" && pwd -P)"
trap '[ -n "${MOCKPID:-}" ] && kill "$MOCKPID" 2>/dev/null; rm -rf "$tmp"' EXIT

cat > "$tmp/golden_old.txt" <<'GOLDEN_EOT'
You decompose a product FEATURE into small, self-verifying backlog items for an autonomous coding fleet (a 27B model driving aider). Output ONLY the item lines — no preamble, no prose.

REPO: demo
Source layout (real paths you must reuse):
scripts/existing.py

FEATURE to decompose:
Golden feature

Output 6 to 10 items, each EXACTLY one line in this format:
- [ ] [T<1-5>] <real/path.ext> — <one precise change> VERIFY: <an exact test or command that proves it>. (cat:<category>; multifile:<yes|no>)

Hard rules:
- Each item is SMALL, independently landable, and self-verifying (a unit test, a type-check, or a grep).
- Prefer NEW pure functions + a colocated test (T1-T2). Use T3 for a wired change; reserve T4-T5 for a genuine multi-file refactor and set multifile:yes.
- Use ONLY real paths consistent with the layout above; put new files in the right directory.
- NEVER write "Create"/"Implement"/"Define" for a function, class or test file the FEATURE text says already exists
  (or that a path in the layout shows exists): modify it instead. Tests go where the repo's runner collects them
  (iptv_apps: iptv-backend/tests/ only; xlite: tests/ only, never test/).
- Do NOT invent a new generic helper function (coercion, casting, formatting) in an unrelated file. Put the change
  INLINE in the function the FEATURE names, and write at most ONE test file per behaviour (no near-duplicate tests).
- Do not add a step that only casts values already typed as int/str; every step must change observable behaviour.
- category is one of: python, typescript, vue, godot, endpoint, schema, test, docs, refactor.
- No secrets, no deploy/DNS/keys (those are human tasks — skip them).
GOLDEN_EOT
NEW1='- An item that only Verifies/Ensures/Checks is forbidden: every item must change code or tests.'
NEW2='- For a Delete feature the FIRST items remove every reference to the symbol outside its definition (tests included); the LAST item deletes the definition.'

# ---- stub LiteLLM: answers with $tmp/resp.txt, stores the last request body in $tmp/req.json
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')"
cat > "$tmp/mock.py" <<'PYEOF'
import http.server, json, sys
PORT, RESP, REQ = int(sys.argv[1]), sys.argv[2], sys.argv[3]
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0) or 0)
        body = self.rfile.read(n)
        open(REQ, 'wb').write(body)
        payload = json.dumps({"choices": [{"message": {"content": open(RESP).read()}}], "usage": {"prompt_tokens": 1, "completion_tokens": 1}}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.send_header('Content-Length', str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_GET(self):
        self.send_response(200); self.end_headers()
http.server.HTTPServer(('127.0.0.1', PORT), H).serve_forever()
PYEOF
python3 "$tmp/mock.py" "$PORT" "$tmp/resp.txt" "$tmp/req.json" >/dev/null 2>&1 &
MOCKPID=$!
: > "$tmp/resp.txt"
for i in $(seq 1 50); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.1; done

# ---- sandbox live dir (the planner does `cd "$HOME/overnight-queue"`)
WD="$tmp/home/overnight-queue"
fresh(){  # <planner script> -> re-creates the sandbox
  rm -rf "$tmp/home"; mkdir -p "$WD"/{backlog,roadmap,repos/demo/scripts,logs,scripts,state}
  echo "def f(): pass" > "$WD/repos/demo/scripts/existing.py"
  printf '# roadmap\n- [ ] [P2] [ready] Golden feature\n' > "$WD/roadmap/demo.md"
  : > "$WD/backlog/demo.md"
  cp "$1" "$WD/ovn_planner_under_test.sh"
}
cat > "$tmp/resp.txt" <<'EOT'
- [ ] [T2] scripts/existing.py — Add `a()` to the module. VERIFY: grep -q "def a" scripts/existing.py. (cat:python; multifile:no)
- [ ] [T2] scripts/existing.py — Rename old_name to new_name. VERIFY: `grep -q old_name scripts/existing.py && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)
- [ ] [T2] scripts/existing.py — Add `c()` to the module. VERIFY: `grep -q "def c" scripts/existing.py`. (cat:python; multifile:no)
EOT
run(){  # <planner script> [env assignments...]
  local pl="$1"; shift
  ( cd "$tmp" && env HOME="$tmp/home" OVN_MODEL=qwen-dflash-27B LITELLM_BASE="http://127.0.0.1:$PORT" OVN_PLAN_THRESHOLD=10 OVN_PLAN_MAX_PER_RUN=1 "$@" bash "$pl" demo ) >/dev/null 2>"$tmp/run.err"
}
prompt_of(){  # the user message of the last request, stripped
  python3 -c "import json;print(json.load(open('$tmp/req.json'))['messages'][0]['content'].strip())"
}
# compare <prompt file> -> 0 iff prompt == golden with exactly NEW1+NEW2 inserted right after the 'Do not add a step' rule
compare(){
  python3 - "$tmp/golden_old.txt" "$1" "$NEW1" "$NEW2" <<'PYEOF'
import sys
old = open(sys.argv[1]).read().strip().split("\n")
new = open(sys.argv[2]).read().strip().split("\n")
n1, n2 = sys.argv[3], sys.argv[4]
anchor = next(i for i, l in enumerate(old) if l.startswith("- Do not add a step that only casts values"))
want = old[:anchor + 1] + [n1, n2] + old[anchor + 1:]
sys.exit(0 if new == want else 1)
PYEOF
}

echo "== golden prompt"
fresh "$PL"; run "$WD/ovn_planner_under_test.sh"
prompt_of > "$tmp/prompt.new"
ok "the model was called and the request recorded" "[ -s '$tmp/req.json' ]"
ok "GOLDEN: prompt == pre-change prompt + exactly the two new rules (right after the 'Do not add a step' rule)" "compare '$tmp/prompt.new'"
ok "both new rules are present verbatim" "grep -cxF -- '$NEW1' '$tmp/prompt.new' | grep -qx 1 && grep -cxF -- '$NEW2' '$tmp/prompt.new' | grep -qx 1"
ok "no old line was removed: every golden line appears in the new prompt" "python3 -c \"import sys;o=open('$tmp/golden_old.txt').read().strip().split(chr(10));n=set(open('$tmp/prompt.new').read().split(chr(10)));sys.exit(0 if all(l in n for l in o) else 1)\""
# mutation: drop one new rule from a copy of the planner; the golden comparison must fail
python3 - "$PL" "$tmp/planner_mut.sh" "$NEW2" <<'PYEOF'
import sys
src = open(sys.argv[1]).read()
needle = "\\n" + sys.argv[3]            # the rule sits inside a $'...' string as \n<rule>
assert needle in src
open(sys.argv[2], "w").write(src.replace(needle, "", 1))
PYEOF
fresh "$tmp/planner_mut.sh"; run "$WD/ovn_planner_under_test.sh"; prompt_of > "$tmp/prompt.mut"
ok "MUTATION (second rule removed from the planner): the golden comparison fails" "! compare '$tmp/prompt.mut'"
# kill switch: OVN_PLANNER_SPEC_RULES=off gives back the pre-change prompt byte for byte
fresh "$PL"; run "$WD/ovn_planner_under_test.sh" OVN_PLANNER_SPEC_RULES=off; prompt_of > "$tmp/prompt.off"
ok "KILL SWITCH OVN_PLANNER_SPEC_RULES=off: the prompt equals the pre-change golden exactly" "cmp -s '$tmp/prompt.off' '$tmp/golden_old.txt'"
# mutation: an unrelated prompt edit is caught too
sed 's/Each item is SMALL, independently landable/Each item is TINY, independently landable/' "$PL" > "$tmp/planner_mut2.sh"
fresh "$tmp/planner_mut2.sh"; run "$WD/ovn_planner_under_test.sh"; prompt_of > "$tmp/prompt.mut2"
ok "MUTATION (an unrelated wording change): the golden comparison fails" "! compare '$tmp/prompt.mut2'"

echo "== lint hook (spec gate)"
install_gate(){  # copy the real gate + modules into the sandbox scripts/
  for f in ovn_spec_gate.py ovn_spec_rules.py ovn_spec_classify.py ovn_backlog_eligibility.py; do cp "$SRC/$f" "$WD/scripts/"; done
}
items(){ grep '^- \[ \] \[T' "$WD/backlog/demo.md"; }
fresh "$PL"; install_gate; run "$WD/ovn_planner_under_test.sh"
ok "default (nothing enforced): 3 items appended exactly as the model wrote them (+ feat tag)" "[ \"\$(items | wc -l | tr -d ' ')\" = 3 ] && items | grep -c 'VERIFY: grep -q \"def a\" scripts/existing.py. (cat:python; multifile:no) \\[feat:' | grep -qx 1 && items | grep -c 'echo \"FAIL\" || echo \"PASS\"' | grep -qx 1"
ok "... and the planner log notes what the lint would repair (shadow)" "grep -c 'shadow, nothing rewritten' '$WD/logs/ovn_planner.log' | grep -qx 1"
fresh "$PL"; install_gate; run "$WD/ovn_planner_under_test.sh" OVN_SPEC_GATE_ENFORCE_RULES=R01,R02
ok "R01+R02 enforced: the bare VERIFY is backticked and the vacuous idiom repaired before the feat tag is appended" "items | grep -c 'VERIFY: .grep -q \"def a\" scripts/existing.py. (cat:python; multifile:no) \\[feat:' | grep -qx 1 && items | grep -c '! ( grep -q old_name scripts/existing.py )' | grep -qx 1 && [ \"\$(items | grep -c 'echo \"FAIL\"')\" = 0 ]"
ok "R01+R02 enforced: still exactly 3 items, all feat-tagged" "[ \"\$(items | wc -l | tr -d ' ')\" = 3 ] && [ \"\$(items | grep -c '\\[feat:demo-')\" = 3 ]"
fresh "$PL"; install_gate; run "$WD/ovn_planner_under_test.sh" OVN_SPEC_GATE=off OVN_SPEC_GATE_ENFORCE_RULES=R01,R02
ok "KILL SWITCH OVN_SPEC_GATE=off: items appended unchanged" "items | grep -c 'echo \"FAIL\" || echo \"PASS\"' | grep -qx 1"
# crash safety
fresh "$PL"; install_gate; printf 'import sys\nsys.exit(3)\n' > "$WD/scripts/ovn_spec_gate.py"
run "$WD/ovn_planner_under_test.sh" OVN_SPEC_GATE_ENFORCE_RULES=R01,R02
ok "a lint that crashes (exit 3, no output): the decomposition is appended unchanged" "[ \"\$(items | wc -l | tr -d ' ')\" = 3 ] && items | grep -c 'echo \"FAIL\" || echo \"PASS\"' | grep -qx 1"
fresh "$PL"; install_gate; printf 'import sys\nsys.stdout.write("")\n' > "$WD/scripts/ovn_spec_gate.py"
run "$WD/ovn_planner_under_test.sh" OVN_SPEC_GATE_ENFORCE_RULES=R01,R02
ok "a lint that prints nothing: items kept (an empty answer is ignored)" "[ \"\$(items | wc -l | tr -d ' ')\" = 3 ]"
fresh "$PL"; install_gate; rm -f "$WD/scripts/ovn_spec_rules.py"
run "$WD/ovn_planner_under_test.sh" OVN_SPEC_GATE_ENFORCE_RULES=R01,R02
ok "a lint whose sibling module is missing echoes its input: items unchanged" "[ \"\$(items | wc -l | tr -d ' ')\" = 3 ] && items | grep -c 'echo \"FAIL\" || echo \"PASS\"' | grep -qx 1"
fresh "$PL"; run "$WD/ovn_planner_under_test.sh" OVN_SPEC_GATE_ENFORCE_RULES=R01,R02
ok "no lint script installed at all: items appended unchanged" "[ \"\$(items | wc -l | tr -d ' ')\" = 3 ]"

echo; echo "planner prompt golden: $P passed, $F failed"
[ "$F" = 0 ]
