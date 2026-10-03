#!/usr/bin/env bash
# Delete executor (2026-09-30): ovn_delete_executor.py DECIDES conservatively; the DELETE-EXECUTOR block in run_overnight.sh
# (extracted and evaluated for real here) does git rm + verify + credit + push, and falls through untouched on any doubt.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
EX="$HERE/../ovn_delete_executor.py"; [ -f "$EX" ] || EX="$HERE/ovn_delete_executor.py"
RO="$HERE/../../run_overnight.sh"; [ -f "$RO" ] || RO="$HERE/../run_overnight.sh"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkrepo(){ rm -rf "$T/r" "$T/origin.git"; git init -q --bare "$T/origin.git"; git clone -q "$T/origin.git" "$T/r" 2>/dev/null; cd "$T/r"; git config user.email t@t; git config user.name t
  mkdir -p app tests
  echo 'def dead_helper(): return 1' > app/dead_helper.py
  echo 'def live_helper(): return 2' > app/live_helper.py
  echo 'def orphan(): return 0' > app/orphan_mod.py
  echo 'from app.live_helper import live_helper' > app/uses_live.py
  printf 'from app.dead_helper import dead_helper\ndef test_dead(): assert dead_helper() == 1\n' > tests/test_dead_helper.py
  echo 'def index(): pass' > app/index.py
  echo 'x' > app/__init__.py
  git add -A; git commit -q -m base; git branch -M main; git push -q origin main; }
d(){ python3 "$EX" check "$T/r" "$1"; }
mkrepo
r="$(d '- [ ] [T1] app/orphan_mod.py — Delete the dead orphan module, it has no callers. (cat:python)')"
ok "dead file, no importers -> OK" "$(printf '%s' "$r" | grep -q '^OK' && echo 1 || echo 0)"
r="$(d '- [ ] [T1] app/live_helper.py — Delete this file. (cat:python)')"
ok "file imported elsewhere -> SKIP referenced-by" "$(printf '%s' "$r" | grep -q 'SKIP.*referenced by.*uses_live.py' && echo 1 || echo 0)"
r="$(d '- [ ] [T1] app/dead_helper.py — Remove the dead function dead_helper from this module. (cat:python)')"
ok "function removal is an edit, not a file delete -> SKIP" "$(printf '%s' "$r" | grep -q '^SKIP' && echo 1 || echo 0)"
r="$(d '- [ ] [T1] app/__init__.py — Delete this file. (cat:python)')"
ok "protected file (__init__.py) -> SKIP" "$(printf '%s' "$r" | grep -q 'SKIP.*protected' && echo 1 || echo 0)"
r="$(d '- [ ] [T1] app/index.py — Delete this file. (cat:python)')"
ok "generic/protected name -> SKIP" "$(printf '%s' "$r" | grep -q '^SKIP' && echo 1 || echo 0)"
r="$(d '- [ ] [T1] app/ghost.py — Delete this file. (cat:python)')"
ok "untracked/already gone -> SKIP" "$(printf '%s' "$r" | grep -q 'SKIP.*not tracked' && echo 1 || echo 0)"
r="$(d '- [ ] [T1] app/dead_helper.py — Delete this file. (cat:python)')"
ok "dedicated test NOT named in the item -> its reference blocks the delete (SKIP)" "$(printf '%s' "$r" | grep -q 'SKIP.*test_dead_helper' && echo 1 || echo 0)"
r="$(d '- [ ] [T1] app/dead_helper.py — Delete this file and its dedicated test tests/test_dead_helper.py. (cat:python)')"
ok "dedicated test named in the item -> deleted together" "$(printf '%s' "$r" | grep -q '^OK.*app/dead_helper.py tests/test_dead_helper.py' && echo 1 || echo 0)"
r="$(d '- [ ] [T2] Add caching to the widget — app/live_helper.py gets a cache. (cat:python)')"
ok "non-delete item -> SKIP" "$(printf '%s' "$r" | grep -q 'SKIP.*not a whole-file' && echo 1 || echo 0)"

# ---- integration: evaluate the REAL extracted block ----
blk="$(awk '/# >>> DELETE-EXECUTOR-BEGIN/{f=1} f{print} /# <<< DELETE-EXECUTOR-END/{f=0}' "$RO")"
ok "block is present in run_overnight.sh" "$([ -n "$blk" ] && echo 1 || echo 0)"
run_block(){  # $1 = verification result the stub returns; echoes the block's stdout
  mkrepo; cd "$T/r"
  printf '## Next Steps\n- [ ] [T1] app/dead_helper.py — Delete this file and its dedicated test tests/test_dead_helper.py. (cat:python)\n' > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m prog; git push -q origin main
  rm -rf "$T/sd"; mkdir -p "$T/sd/scripts" "$T/sd/state"; cp "$EX" "$T/sd/scripts/"
  cat > "$T/harness.sh" <<H
set -u
SCRIPT_DIR="$T/sd"; id="ongoing-testrepo"; branch=main; task_log="$T/task.log"; : > "\$task_log"
ovn_item_hash(){ printf '%s' "\$1" | md5sum | cut -c1-12; }
run_repo_verification(){ echo "$1"; }
ovn_bug_first_order(){ cat; }   # bug-first ordering lives in lib_item_select.sh, not loaded by this harness
f(){
BEFORE_SHA="\$(git rev-parse HEAD)"
$blk
echo FELL-THROUGH
}
f
H
  bash "$T/harness.sh" 2>&1
}
out="$(run_block pass)"
ok "green verify: emits pushed(tests:pass) delete-executor and returns (no fall-through)" "$(printf '%s' "$out" | grep -q 'pushed(tests:pass) delete-executor' && ! printf '%s' "$out" | grep -q FELL-THROUGH && echo 1 || echo 0)"
cd "$T/r"; git fetch -q origin
ok "both files are gone on origin/main" "$(! git cat-file -e origin/main:app/dead_helper.py 2>/dev/null && ! git cat-file -e origin/main:tests/test_dead_helper.py 2>/dev/null && echo 1 || echo 0)"
ok "progress item credited [x] on origin" "$(git show origin/main:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] (deleted by delete-executor, verified)' && echo 1 || echo 0)"
out="$(run_block fail)"
ok "red verify: falls through to the normal path" "$(printf '%s' "$out" | grep -q FELL-THROUGH && echo 1 || echo 0)"
cd "$T/r"
ok "red verify: working tree restored (file still there, nothing pushed)" "$([ -f app/dead_helper.py ] && git fetch -q origin && git cat-file -e origin/main:app/dead_helper.py && echo 1 || echo 0)"
ok "red verify: failure remembered so it is tried only once per item" "$([ -n "$(ls "$T/sd/state/delete_exec_failed" 2>/dev/null)" ] && echo 1 || echo 0)"
out="$(run_block skip)"
ok "skipped verify: falls through and is NOT remembered as failed" "$(printf '%s' "$out" | grep -q FELL-THROUGH && [ -z "$(ls "$T/sd/state/delete_exec_failed" 2>/dev/null)" ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
