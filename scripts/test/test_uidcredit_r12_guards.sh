#!/usr/bin/env bash
# 2026-10-12 (package uidcredit, part 2). Three guards, each proven against its kill switch (= the old behaviour):
#   X4  the DELETE: trailer must not `git rm` a file that other tracked files still import (xlite cell_ring.gd: build went red, the fix-up regenerated the file lossy and
#       silently reverted a refactor). ovn_delete_executor.py `importers` + the run_overnight.sh trailer block (REAL extracted block).  OVN_DELETE_TRAILER_IMPORTER_GUARD=off
#   X7  ovn_classify_fail.sh: a log that only holds `verdict: no-edit-unfenced` / "/dev/null is not in the subpath" deliberation text is no-edit, not test-red. OVN_CLASSIFY_NOEDIT_FIRST=off
#   K   ovn_recover_parked.sh: a repeated [CLAUDE] escalation updates the existing line's count instead of appending another line.  OVN_CLAUDE_LINE_UPDATE=off
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"; [ -f "$ROOT/ovn_delete_executor.py" ] || ROOT="$HERE"
OQ="$ROOT/.."; [ -f "$OQ/run_overnight.sh" ] || OQ="$ROOT"
EX="$ROOT/ovn_delete_executor.py"; LIB="$ROOT/lib_fixup.sh"; RO="$OQ/run_overnight.sh"; CL="$OQ/ovn_classify_fail.sh"; RP="$OQ/ovn_recover_parked.sh"
. "$HERE/ntfy_guard.sh" 2>/dev/null || true
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ================= X4: importer guard =================
mkrepo(){
  rm -rf "${T:?}/r"; mkdir -p "$T/r"; cd "$T/r" || exit 1; git init -q -b main .
  mkdir -p scripts/battle tests
  printf 'class_name CellRing\nextends RefCounted\nstatic func ring_index(c, o): return 1\n' > scripts/battle/cell_ring.gd; echo 'uid://b1cr' > scripts/battle/cell_ring.gd.uid
  printf 'extends GutTest\nconst CellRing = preload("res://scripts/battle/cell_ring.gd")\nfunc test_x(): assert_eq(CellRing.ring_index(1, 2), 1)\n' > tests/test_cell_ring.gd; echo 'uid://b2cr' > tests/test_cell_ring.gd.uid
  printf 'extends Node\n' > scripts/battle/dead_one.gd; echo 'uid://b3d' > scripts/battle/dead_one.gd.uid
  git add -A; git commit -q -m base
}
mkrepo
r="$(python3 "$EX" importers "$T/r" scripts/battle/cell_ring.gd)"
ok "X4a importers CLI: the module is referenced by its test -> SKIP referenced by tests/test_cell_ring.gd" "$([ "$r" = "$(printf 'SKIP\treferenced by: tests/test_cell_ring.gd')" ] && echo 1 || echo 0)"
r="$(python3 "$EX" importers "$T/r" scripts/battle/cell_ring.gd tests/test_cell_ring.gd)"
ok "X4b the test deleted TOGETHER with the module does not count as an importer -> OK" "$([ "$r" = OK ] && echo 1 || echo 0)"
r="$(python3 "$EX" importers "$T/r" scripts/battle/dead_one.gd)"
ok "X4c an unreferenced file -> OK" "$([ "$r" = OK ] && echo 1 || echo 0)"

tblk="$(awk '/_ovn_del_already=0/{f=1} /# Working-tree residue guard/{f=0} f{print}' "$RO")"
ok "X4d trailer handler block extracted and carries the guard" "$([ -n "$tblk" ] && printf '%s' "$tblk" | grep -q 'DELETE trailer REFUSED' && echo 1 || echo 0)"
run_trailer(){  # $1 = env assignment, $2 = trailer lines
  mkrepo; cd "$T/r" || exit 1
  cat > "$T/h.sh" <<H
set -u
$1
SCRIPT_DIR="$OQ"
task_log="$T/task.log"; printf 'blah\n$2\n' > "\$task_log"
. "$LIB"
f(){
BEFORE_SHA="\$(git rev-parse HEAD)"; AFTER_SHA="\$BEFORE_SHA"
$tblk
echo "AFTER=\$AFTER_SHA BEFORE=\$BEFORE_SHA del_did=\${del_did:-} other=\${_ovn_del_other:-}"
}
f
H
  bash "$T/h.sh" 2>&1
}
out="$(run_trailer "" 'DELETE: scripts/battle/cell_ring.gd')"; cd "$T/r" || exit 1
ok "X4e REAL case: DELETE: of a module its test still preloads is REFUSED - file + .uid kept, no commit, logged" "$([ -f scripts/battle/cell_ring.gd ] && [ -f scripts/battle/cell_ring.gd.uid ] && [ "$(git rev-parse HEAD)" = "$(git rev-parse HEAD~0)" ] && [ "$(git rev-list --count HEAD)" = 1 ] && grep -q 'DELETE trailer REFUSED: scripts/battle/cell_ring.gd referenced by: tests/test_cell_ring.gd' "$T/task.log" && ! grep -q 'DELETE trailer: removed scripts/battle/cell_ring.gd' "$T/task.log" && echo 1 || echo 0)"
out="$(run_trailer "export OVN_DELETE_TRAILER_IMPORTER_GUARD=off" 'DELETE: scripts/battle/cell_ring.gd')"; cd "$T/r" || exit 1
ok "X4f (kill switch = old behaviour) the same trailer deletes the module the test still needs" "$([ ! -e scripts/battle/cell_ring.gd ] && grep -q 'DELETE trailer: removed scripts/battle/cell_ring.gd' "$T/task.log" && echo 1 || echo 0)"
out="$(run_trailer "" 'DELETE: scripts/battle/cell_ring.gd\nDELETE: tests/test_cell_ring.gd')"; cd "$T/r" || exit 1
ok "X4g module + its test in ONE trailer: both go (with their .uid), nothing refused" "$([ ! -e scripts/battle/cell_ring.gd ] && [ ! -e tests/test_cell_ring.gd ] && [ ! -e scripts/battle/cell_ring.gd.uid ] && [ ! -e tests/test_cell_ring.gd.uid ] && ! grep -q REFUSED "$T/task.log" && echo 1 || echo 0)"
out="$(run_trailer "" 'DELETE: scripts/battle/dead_one.gd')"; cd "$T/r" || exit 1
ok "X4h an unreferenced file is still deleted (guard does not over-block)" "$([ ! -e scripts/battle/dead_one.gd ] && [ ! -e scripts/battle/dead_one.gd.uid ] && echo 1 || echo 0)"

# ================= X7: classify =================
printf "aider attempt 1\nwe should assert the old behaviour, expected to equal x\n'/dev/null' is not in the subpath of /repo. Only 3 reflections allowed\n--- aider attempt 1 verdict: no-edit-unfenced ---\n" > "$T/ne.log"
ok "X7a no-edit-unfenced transcript with 'assert'/'expected to equal' text -> no-edit (not test-red)" "$([ "$(bash "$CL" "$T/ne.log" no-op)" = no-edit ] && echo 1 || echo 0)"
ok "X7b (kill switch = old behaviour) the same log is test-red" "$([ "$(OVN_CLASSIFY_NOEDIT_FIRST=off bash "$CL" "$T/ne.log" no-op)" = test-red ] && echo 1 || echo 0)"
{ echo "--- verify: GUT"; cat "$T/ne.log"; } > "$T/ve.log"
ok "X7c a log where verification really ran keeps the content scan (test-red)" "$([ "$(bash "$CL" "$T/ve.log" no-op)" = test-red ] && echo 1 || echo 0)"
printf "assert_eq failed: expected [1] to equal [2]\n3 failed\n" > "$T/tr.log"
ok "X7d an ordinary red log (no no-edit marker) is still test-red" "$([ "$(bash "$CL" "$T/tr.log" no-op)" = test-red ] && echo 1 || echo 0)"

# ================= K: [CLAUDE] escalation line update =================
if [ -f "$ROOT/lib_worktree.sh" ] && [ -f "$ROOT/lib_path_normalize.sh" ] && [ -f "$RP" ] && sed --version >/dev/null 2>&1; then
  H="$T/home"; Q="$H/overnight-queue"; mkdir -p "$Q/repos" "$Q/state/recovery_lineage" "$Q/logs" "$Q/scripts"
  cp "$ROOT/lib_worktree.sh" "$ROOT/lib_path_normalize.sh" "$Q/scripts/"
  printf '#!/usr/bin/env bash\ncase "$1" in hold) : > "$(dirname "$0")/state/HOLD_$2";; release) rm -f "$(dirname "$0")/state/HOLD_$2";; esac\nexit 0\n' > "$Q/queue.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$Q/scripts/ovn_log_tokens.sh"; chmod +x "$Q/queue.sh" "$Q/scripts/"*.sh
  mkk(){  # $1 name
    local o="$T/origin_$1.git" w; git init -q --bare "$o"; w="$(mktemp -d)" || exit 1
    ( cd "$w" || exit 1; git init -q -b overnight/feature && mkdir -p src && printf 'def real():\n    return 1\n' > src/real.py && printf '# Progress\n\n- [ ] [CLAUDE] src/real.py has been recovered/decomposed 4 times (cap 0) without ever landing - the fleet keeps re-guessing at this same file with no real diagnosis; needs a human/Claude session to understand the actual blast radius (recovery:escalated)\n- [ ] [AUTO-SKIP after 5 no-op cycles — review] [T4] src/real.py — a stuck item needing escalation. VERIFY: pytest -q\n' > OVERNIGHT_PROGRESS.md \
        && git add -A && git commit -q -m init && git remote add origin "$o" && git push -q origin overnight/feature )
    git --git-dir="$o" symbolic-ref HEAD refs/heads/overnight/feature; rm -rf "$w"
    rm -rf "${Q:?}/repos/$1"; git clone -q "$o" "$Q/repos/$1" && ( cd "$Q/repos/$1" && git checkout -q overnight/feature )
    printf '4' > "$Q/state/recovery_lineage/$1__src_real.py.count"
  }
  runrp(){ RN="$1"; shift; ( cd "$Q" && HOME="$H" LITELLM_BASE="http://127.0.0.1:9" LITELLM_MASTER_KEY=k OVN_MODEL=m OVN_RECOVER_LINEAGE_CAP=0 env "$@" timeout 120 bash "$RP" "$RN" >/dev/null 2>&1 ); }
  mkk r1; runrp r1 OVN_CLAUDE_LINE_UPDATE=on
  p="$(git --git-dir="$T/origin_r1.git" show overnight/feature:OVERNIGHT_PROGRESS.md)"
  ok "K1 a repeated [CLAUDE] escalation UPDATES the existing line (4 -> 5 times): exactly one [CLAUDE] line" "$([ "$(printf '%s\n' "$p" | grep -c '^- \[ \] \[CLAUDE\]')" = 1 ] && printf '%s\n' "$p" | grep -q 'recovered/decomposed 5 times (cap 0)' && ! printf '%s\n' "$p" | grep -q 'decomposed 4 times' && echo 1 || echo 0)"
  mkk r2; runrp r2 OVN_CLAUDE_LINE_UPDATE=off
  p="$(git --git-dir="$T/origin_r2.git" show overnight/feature:OVERNIGHT_PROGRESS.md)"
  ok "K2 (kill switch = old behaviour) a second [CLAUDE] line is appended" "$([ "$(printf '%s\n' "$p" | grep -c '^- \[ \] \[CLAUDE\]')" = 2 ] && echo 1 || echo 0)"
else
  echo "  SKIP K1-K2: needs lib_worktree/lib_path_normalize + GNU sed (run on the box)"
fi

# ================= review r15 fixes =================
# --- 1. [CLAUDE] line identity: only the counters are masked (the REAL python block of ovn_recover_parked.sh, run on fixture files; no git/flock needed)
awk '/OVN_F="\$wf" OVN_LN=/{f=1;next} f&&/^PY$/{exit} f{print}' "$RP" > "$T/rp_block.py"
ok "R1a recover_parked python block extracted" "$([ -s "$T/rp_block.py" ] && grep -q '_ck' "$T/rp_block.py" && echo 1 || echo 0)"
cl_run(){  # $1 = existing [CLAUDE] line(s) file content, $2 = new item, rest env -> prints the resulting [CLAUDE] lines
  local ex="$1" it="$2"; shift 2
  printf '# Progress\n%s\n- [ ] [AUTO-SKIP] [T4] src/x.py - stuck. VERIFY: pytest -q\n' "$ex" > "$T/pp.md"
  printf '%s\n' "$it" > "$T/pi.txt"; printf '# hdr\n' > "$T/ph.txt"
  env "$@" OVN_F="$T/pp.md" OVN_LN=3 OVN_ITEMS="$T/pi.txt" OVN_HDR="$T/ph.txt" python3 "$T/rp_block.py" || return 1
  grep '^- \[ \] \[CLAUDE\]' "$T/pp.md"
}
mk_esc(){ printf -- '- [ ] [CLAUDE] %s has been recovered/decomposed %s times (cap %s) without ever landing - the fleet keeps re-guessing (recovery:escalated)' "$1" "$2" "$3"; }
out="$(cl_run "$(mk_esc scenes/level1.gd 3 0)" "$(mk_esc scenes/level2.gd 3 0)" X=1)"
ok "R1b two escalations differing ONLY by a digit in the file name are distinct: both lines kept (old _ck masked every digit -> level1 line overwritten)" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && printf '%s\n' "$out" | grep -q level1.gd && printf '%s\n' "$out" | grep -q level2.gd && echo 1 || echo 0)"
out="$(cl_run "$(mk_esc scenes/level1.gd 3 0)" "$(mk_esc scenes/level1.gd 5 0)" X=1)"
ok "R1c two escalations differing ONLY by the counter are the same: ONE line, updated to 5" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && printf '%s\n' "$out" | grep -q 'decomposed 5 times' && echo 1 || echo 0)"
bn(){ printf -- '- [ ] [CLAUDE] %s is hard-banned from automated edits (.queue-hard-banned-files) - no decomposition can route around a file-level ban, needs a human/Claude session (recovery:escalated)' "$1"; }
out="$(cl_run "$(bn a1.gd)" "$(bn a2.gd)" X=1)"
ok "R1d hard-banned-file lines for a1.gd / a2.gd are distinct (compared verbatim)" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && echo 1 || echo 0)"
out="$(cl_run "$(bn a1.gd)" "$(bn a1.gd)" X=1)"
ok "R1e the identical hard-banned line is not duplicated" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
out="$(cl_run "$(mk_esc scenes/level1.gd 3 0)" "$(mk_esc scenes/level1.gd 5 0)" OVN_CLAUDE_LINE_UPDATE=off)"
ok "R1f (kill switch) OVN_CLAUDE_LINE_UPDATE=off appends a second line" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 2 ] && echo 1 || echo 0)"
out="$(cl_run "$(mk_esc scenes/level1.gd 3 0)" "$(mk_esc scenes/level1.gd 5 0)" -u OVN_CLAUDE_LINE_UPDATE)"
ok "R5a (default pin) OVN_CLAUDE_LINE_UPDATE UNSET = update in place (one line)" "$([ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = 1 ] && grep -q 'OVN_CLAUDE_LINE_UPDATE", "on")' "$RP" && echo 1 || echo 0)"

# --- 2. strict-verify default stays shadow (the old `on` was silently coerced to shadow: a no-op that looked like enabling strict mode)
CR="$ROOT/ovn_credit_already_satisfied.sh"
eff="$(unset OVN_IMPL_CREDIT_REQUIRE_VERIFY; eval "$(sed -n '/^STRICT_MODE=/,/^case "\$STRICT_MODE"/p' "$CR")"; echo "$STRICT_MODE")"
ok "R2a effective OVN_IMPL_CREDIT_REQUIRE_VERIFY default is shadow" "$([ "$eff" = shadow ] && echo 1 || echo 0)"
ok "R2b the literal default is 'shadow' (not an unaccepted 'on' that is coerced)" "$(grep -q '^STRICT_MODE="${OVN_IMPL_CREDIT_REQUIRE_VERIFY:-shadow}"' "$CR" && echo 1 || echo 0)"
eff="$(OVN_IMPL_CREDIT_REQUIRE_VERIFY=enforce; eval "$(sed -n '/^STRICT_MODE=/,/^case "\$STRICT_MODE"/p' "$CR")"; echo "$STRICT_MODE")"
ok "R2c enforce is still accepted" "$([ "$eff" = enforce ] && echo 1 || echo 0)"

# --- 3. trailer importer guard for non-.gd files: only import-style references count; tests/ exempt
rm -rf "${T:?}/r3"; mkdir -p "$T/r3/src" "$T/r3/tests" "$T/r3/web" "$T/r3/notes" "$T/r3/pkg"; cd "$T/r3" || exit 1; git init -q -b main .
printf 'def f():\n    return 1\n' > src/utils.py
printf 'from src import utils\nprint(utils.f())\n' > src/app.py
printf 'x = "see utils for details"\nprint(x)\n' > notes/readme_helper.py
printf 'from src.utils import f\n' > tests/test_utils.py
printf 'module.exports = {}\n' > web/config.js
printf "const c = require('./config')\n" > web/main.js
printf 'def g():\n    return 2\n' > pkg/helpers.py
printf 'from lib import (\n    helpers,\n    other,\n)\n' > pkg/multi.py
printf 'def h():\n    return 3\n' > pkg/lonely.py
printf 'the lonely function is lonely, utils is not lonely\nlonely = 1\n' > pkg/bare.py
git add -A; git commit -q -m base
r="$(python3 "$EX" importers "$T/r3" src/utils.py)"
ok "R3a a real import (from src import utils) refuses" "$([ "$r" = "$(printf 'SKIP\treferenced by: src/app.py')" ] && echo 1 || echo 0)"
git rm -q src/app.py; git commit -q -m x
r="$(python3 "$EX" importers "$T/r3" src/utils.py)"
ok "R3b a BARE-WORD mention (notes/readme_helper.py) and an import from tests/ do NOT refuse -> OK (old: SKIP every cycle)" "$([ "$r" = OK ] && echo 1 || echo 0)"
r="$(python3 "$EX" importers "$T/r3" web/config.js)"
ok "R3c a JS require('./config') refuses" "$([ "$r" = "$(printf 'SKIP\treferenced by: web/main.js')" ] && echo 1 || echo 0)"
r="$(python3 "$EX" importers "$T/r3" pkg/helpers.py)"
ok "R3d a bare name inside a multi-line import list refuses" "$([ "$r" = "$(printf 'SKIP\treferenced by: pkg/multi.py')" ] && echo 1 || echo 0)"
r="$(python3 "$EX" importers "$T/r3" pkg/lonely.py)"
ok "R3e a bare-word prose/identifier line in a code file does not refuse" "$([ "$r" = OK ] && echo 1 || echo 0)"
r="$(python3 "$EX" check "$T/r3" '- [ ] [T1] pkg/lonely.py — Delete this dead file. (cat:py)')"
ok "R3f (scope) the deterministic executor keeps the broad word scan: its check still refuses on the bare-word mention" "$(printf '%s' "$r" | grep -q 'referenced by: pkg/bare.py' && echo 1 || echo 0)"

# --- 4 (canon case) is covered in test_twin_credit_dedupe.sh Q6/Q7

# --- 5. sidecar filters / kill switches of the importer scan and companions
rm -rf "${T:?}/r5"; mkdir -p "$T/r5/art" "$T/r5/lib"; cd "$T/r5" || exit 1; git init -q -b main .
printf 'png' > art/tile.png; printf '[remap]\nsource_file="res://art/tile.png"\nimport tile.png\n' > art/tile.png.import
printf 'x=1\n' > lib/helper.py; printf 'import helper\n' > lib/other.gd.uid
git add -A; git commit -q -m base
r="$(python3 "$EX" importers "$T/r5" art/tile.png)"
ok "R5b a tracked .import sidecar of the deleted file is not an importer of it" "$([ "$r" = OK ] && echo 1 || echo 0)"
r="$(OVN_DELETE_SIDECARS=off python3 "$EX" importers "$T/r5" art/tile.png)"
ok "R5c (kill switch OVN_DELETE_SIDECARS=off drops the companion exemption) the same call now sees the sidecar as an importer" "$(printf '%s' "$r" | grep -q '^SKIP' && echo 1 || echo 0)"
r="$(python3 "$EX" importers "$T/r5" lib/helper.py)"
ok "R5d a .uid file is never an importer (IGNORE_REF), even if its text looks like one" "$([ "$r" = OK ] && echo 1 || echo 0)"
cmp_py='import sys; sys.path.insert(0, sys.argv[1]); import ovn_delete_executor as e; print(e.companions(sys.argv[2], sys.argv[3]))'
mkdir -p "$T/r6"; cd "$T/r6" || exit 1; git init -q -b main .; printf 'x' > a.gd; echo u > a.gd.uid; git add -A; git commit -q -m b
ok "R5e companions(): default returns the tracked .uid" "$([ "$(python3 -c "$cmp_py" "$ROOT" "$T/r6" a.gd)" = "['a.gd.uid']" ] && echo 1 || echo 0)"
ok "R5f companions(): OVN_DELETE_SIDECARS=off returns []" "$([ "$(OVN_DELETE_SIDECARS=off python3 -c "$cmp_py" "$ROOT" "$T/r6" a.gd)" = "[]" ] && echo 1 || echo 0)"

echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
