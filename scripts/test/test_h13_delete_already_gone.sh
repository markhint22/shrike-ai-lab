#!/usr/bin/env bash
# test_h13_delete_already_gone.sh - 2026-10-04 (h13 task 3). A "Delete X" item whose file an EARLIER commit already removed was never credited
# (the DELETE handler only acted on an existing file) and flailed 6 cycles (xlite elevation.gd). Now:
#   * ovn_delete_executor.py answers ALREADY-GONE (absent AND deleted in history, or the item's own VERIFY `test ! -f X`); run_overnight.sh
#     credits the item and reports the benign no-op(ALREADY-DONE);
#   * a model `DELETE: <path>` trailer for an already-deleted path is the same benign status (not a bare no-op);
#   * queue_refill.py's pre-verify credit and ovn_retire_vague.py's sanitizer credit `VERIFY: test ! -f X` items with X absent.
# Every behaviour has a NEGATIVE control (a path that never existed / still exists is NOT credited) and a BENIGN control (normal delete unchanged).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"
EX="$Q/scripts/ovn_delete_executor.py"

# ------------------------------------------------------------ ovn_delete_executor.py decide()
R="$W/exrepo"; mkdir -p "$R/scripts"; git init -q -b main "$R"
( cd "$R" && echo 'extends Node' > scripts/old_mod.gd && echo 'extends Node' > scripts/live_unused.gd && git add -A && git commit -q -m add \
  && git rm -q scripts/old_mod.gd && git commit -q -m "remove old_mod" ) >/dev/null 2>&1
ex(){ python3 "$EX" check "$R" "$1" | tr '\t' '|'; }
eq "executor: tracked-then-deleted file => ALREADY-GONE" "$(ex '- [ ] [T2] scripts/old_mod.gd — Delete the dead module file. (cat:refactor)')" "ALREADY-GONE|scripts/old_mod.gd"
eq "executor: own VERIFY test ! -f on an absent path => ALREADY-GONE" "$(ex '- [ ] [T2] scripts/never_was.gd — Delete the dead module file. VERIFY: `test ! -f scripts/never_was.gd` returns exit code 0.')" "ALREADY-GONE|scripts/never_was.gd"
eq "executor NEG: never existed, no history, no VERIFY => still SKIP (not credited)" "$(ex '- [ ] [T2] scripts/never_was.gd — Delete the dead module file.')" "SKIP|target not tracked (already gone or wrong path)"
eq "executor NEG: VERIFY names a DIFFERENT path => not credited" "$(ex '- [ ] [T2] scripts/never_was.gd — Delete the dead module file. VERIFY: `test ! -f scripts/other_thing.gd`')" "SKIP|target not tracked (already gone or wrong path)"
eq "executor BENIGN: an existing unreferenced file is still a normal OK delete" "$(ex '- [ ] [T2] scripts/live_unused.gd — Delete the dead module file.')" "OK|scripts/live_unused.gd"

# review hardening (adversarial pass): false-positive controls
( cd "$R" && mkdir -p scripts/battle 'scripts/[id]' && echo 'extends Node' > scripts/readded.gd && echo 'extends Node' > scripts/battle/elev_x.gd \
  && echo 'x' > 'scripts/[id]/i.gd' && git add -A && git commit -q -m add2 && git rm -q scripts/readded.gd 'scripts/[id]/i.gd' && git commit -q -m rm2 \
  && echo 'extends Node' > scripts/readded.gd && git add -A && git commit -q -m readd ) >/dev/null 2>&1
eq "executor NEG: deleted then RE-ADDED (file exists again) is never ALREADY-GONE (normal executor path decides)" "$(ex '- [ ] [T2] scripts/readded.gd — Delete the dead module file.')" "OK|scripts/readded.gd"
eq "executor NEG: VERIFY with a '&& <more>' tail is not the item's whole check - not credited" "$(ex '- [ ] [T2] scripts/never_was.gd — Delete the dead module file. VERIFY: `test ! -f scripts/never_was.gd && ! grep -r never_was scripts`')" "SKIP|target not tracked (already gone or wrong path)"
eq "executor NEG: a bare name while a tracked file of that name lives elsewhere is ambiguous - not credited" "$(ex '- [ ] [T2] elev_x.gd — Delete the dead module file. VERIFY: `test ! -f elev_x.gd`')" "SKIP|target not tracked (already gone or wrong path)"
eq "executor NEG: a [glob] path does not match a different deleted file (literal pathspec)" "$(ex '- [ ] [T2] scripts/[id]/x.gd — Delete the dead module file.')" "SKIP|target not tracked (already gone or wrong path)"
eq "executor BENIGN: a deleted file whose path contains [brackets] literally is ALREADY-GONE" "$(ex '- [ ] [T2] scripts/[id]/i.gd — Delete the dead module file.')" "ALREADY-GONE|scripts/[id]/i.gd"
eq "executor BENIGN: VERIFY followed by a [feat:] tag is still the whole check" "$(ex '- [ ] [T2] scripts/never_was.gd — Delete the dead module file. VERIFY: `test ! -f scripts/never_was.gd` exits 0. [feat:x]')" "ALREADY-GONE|scripts/never_was.gd"

# ------------------------------------------------------------ queue_refill.py pre-verify credit
QR="$W/qr"; mkdir -p "$QR/scripts"; : > "$QR/scripts/present.gd"
cat > "$W/qr_probe.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("qr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
root = sys.argv[2]
for line in sys.stdin.read().split("\n"):
    if line: print(1 if m.already_satisfied(line, root) else 0)
PY
qr(){ printf '%s\n' "$1" | python3 "$W/qr_probe.py" "$Q/queue_refill.py" "$QR"; }
eq "queue_refill: VERIFY test ! -f <absent> => already satisfied (credited)" "$(qr '- [ ] [T2] scripts/gone.gd — Delete it. VERIFY: `test ! -f scripts/gone.gd` returns exit code 0. (cat:refactor)')" "1"
eq "queue_refill NEG: VERIFY test ! -f <STILL PRESENT> => not credited" "$(qr '- [ ] [T2] scripts/present.gd — Delete it. VERIFY: `test ! -f scripts/present.gd` returns exit code 0.')" "0"
eq "queue_refill NEG: compound/always-true shape is still refused" "$(qr '- [ ] [T2] x — d. VERIFY: `test ! -f scripts/gone.gd && echo ok`')" "0"
eq "queue_refill NEG: path escaping the repo is refused" "$(qr '- [ ] [T2] x — d. VERIFY: `test ! -f ../outside.gd`')" "0"
eq "queue_refill BENIGN: grep VERIFY shape still works" "$(qr '- [ ] [T1] a.py — x. VERIFY: `grep -q zzz_not_there a.py`')" "0"

# ------------------------------------------------------------ ovn_retire_vague.py sanitizer
RV="$W/rv"; mkdir -p "$RV/scripts" "$RV/addons/gut"; : > "$RV/scripts/present.gd"; : > "$RV/addons/gut/gut_cmdln.gd"
cat > "$RV/OVERNIGHT_PROGRESS.md" <<'EOP'
## Next Steps
- [ ] [T2] scripts/gone.gd — Delete the inert class file. VERIFY: `test ! -f scripts/gone.gd` returns exit code 0. (cat:refactor) [feat:x-a]
- [ ] [T2] scripts/present.gd — Delete the live class file. VERIFY: `test ! -f scripts/present.gd` returns exit code 0. (cat:refactor) [feat:x-a]
- [ ] [T4] . — Execute full test suite to ensure no runtime errors. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests` exits with code 0. (cat:test) [feat:x-a]
- [ ] [T4] tests — Run everything again. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests` exits 0.
- [ ] [T3] scripts/present.gd — add a clamp helper. VERIFY: `grep -q clamp scripts/present.gd`
EOP
RVOUT="$( cd "$RV" && python3 "$Q/scripts/ovn_retire_vague.py" OVERNIGHT_PROGRESS.md )"
RVP="$(cat "$RV/OVERNIGHT_PROGRESS.md")"
ok "retire_vague: already-absent delete item is CREDITED [x] (already-done)" 'grep -q "^- \[x\] (already-done, target already absent) \[T2\] scripts/gone.gd" <<< "$RVP"'
ok "retire_vague NEG: delete item whose file still exists stays OPEN" 'grep -q "^- \[ \] \[T2\] scripts/present.gd — Delete the live" <<< "$RVP"'
ok "retire_vague: path '.' item whose only file token is VERIFY tooling is retired (vague)" 'grep -q "^- \[x\] (retired-vague) \[T4\] \. — Execute full test suite" <<< "$RVP"'
ok "retire_vague: path 'tests' item with no concrete file is retired (vague)" 'grep -q "^- \[x\] (retired-vague) \[T4\] tests — Run everything" <<< "$RVP"'
ok "retire_vague BENIGN: a normal item naming a real file is untouched" 'grep -q "^- \[ \] \[T3\] scripts/present.gd — add a clamp helper" <<< "$RVP"'
ok "retire_vague: summary line counts them and keeps the 'retired N' grep contract" 'grep -qE "total retired: 3 \(vague=2 dead-path=0 already-done=1\)" <<< "$RVOUT"'
RV3="$W/rv3"; mkdir -p "$RV3/scripts/deep"; : > "$RV3/scripts/deep/there.gd"
cat > "$RV3/OVERNIGHT_PROGRESS.md" <<'EOP'
## Next Steps
- [ ] [T2] scripts/g1.gd — Delete it. VERIFY: `test ! -f scripts/g1.gd && ! grep -rq g1 scripts` (cat:refactor)
- [ ] [T2] xlite/scripts/deep/there.gd — Delete it. VERIFY: `test ! -f xlite/scripts/deep/there.gd`
- [ ] [T2] there.gd — Delete it. VERIFY: `test ! -f there.gd`
- [ ] [T2] scripts/g4.gd — Delete it. VERIFY: `test ! -f scripts/g4.gd`. [feat:x-b]
EOP
( cd "$RV3" && python3 "$Q/scripts/ovn_retire_vague.py" OVERNIGHT_PROGRESS.md >/dev/null ); RV3P="$(cat "$RV3/OVERNIGHT_PROGRESS.md")"
ok "retire_vague NEG: VERIFY with an '&&' tail is not credited as already-done (legacy dead-path handling applies)" '! grep -q "already-done.*scripts/g1.gd" <<< "$RV3P"'
ok "retire_vague NEG: a repo-prefixed (mis-pathed) VERIFY that passes trivially is not credited while the real file exists" 'grep -q "^- \[ \] \[T2\] xlite/scripts/deep/there.gd" <<< "$RV3P"'
ok "retire_vague NEG: a bare file name that exists elsewhere in the tree is not credited" 'grep -q "^- \[ \] \[T2\] there.gd" <<< "$RV3P"'
ok "retire_vague BENIGN: a clean absent-path VERIFY followed by a [feat:] tag is credited" 'grep -q "^- \[x\] (already-done, target already absent) \[T2\] scripts/g4.gd" <<< "$RV3P"'
RV2="$W/rv2"; mkdir -p "$RV2"; printf '## Next Steps\n- [ ] [T3] scripts/zzz.py — add a clamp helper. [feat:x]\n' > "$RV2/OVERNIGHT_PROGRESS.md"
ok "retire_vague BENIGN: clean queue keeps the legacy summary format exactly" '[ "$(cd "$RV2" && python3 "$Q/scripts/ovn_retire_vague.py" OVERNIGHT_PROGRESS.md)" = "  total retired: 1 (vague=0 dead-path=1)" ] || [ "$(cd "$RV2" && python3 "$Q/scripts/ovn_retire_vague.py" OVERNIGHT_PROGRESS.md)" = "  total retired: 0 (vague=0 dead-path=0)" ]'

# ------------------------------------------------------------ run_overnight.sh end-to-end
setup_progress(){   # $1 = item text; history: scripts/old_mod.gd added then deleted
  ( cd "$REPO" && mkdir -p scripts && echo 'extends Node' > scripts/old_mod.gd && git add -A && git commit -q -m "add old_mod" \
    && git rm -q scripts/old_mod.gd && git commit -q -m "remove old_mod" \
    && printf '# Progress\n\n## Next Steps\n%s\n- [ ] Tidy dead code in old.py\n\n## Completed\n' "$1" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m "queue" && git push -q origin HEAD:claude/feature ) >/dev/null 2>&1
}
ITEM='- [ ] [T2] scripts/old_mod.gd — Delete the dead module file. VERIFY: `test ! -f scripts/old_mod.gd` returns exit code 0.'
runid(){ OUT="$(run_aider_fix_task "ongoing-t" "$REPO" "$PROMPT_DEFAULT" claude/feature true "$TASK_LOG" "" false 2 "" 60 2>/dev/null | tail -1)"; ALERTS="$(cat "$TREE/state/alerts.log" 2>/dev/null)"; }

mk_case gone_exec
setup_progress "$ITEM"
runid
eq "e2e: already-deleted item => no-op(ALREADY-DONE) with ZERO model calls" "$OUT" "no-op(ALREADY-DONE)"
ok "e2e: no aider call was made" '[ ! -f "$CASE_DIR/aider.n" ]'
ok "e2e: the item is credited [x] on origin (leaves rotation)" 'git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "^- \[x\] (already-done, target already deleted) \[T2\] scripts/old_mod.gd"'
ok "e2e: the next item is untouched" 'git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "^- \[ \] Tidy dead code in old.py"'

mk_case gone_neg
setup_progress '- [ ] [T2] scripts/never_was.gd — Delete the dead module file.'
scout_ok
runid
ok "e2e NEG: a path that NEVER existed is not credited as already-done by the executor (normal flow continues)" '! git -C "$ORIGIN" show claude/feature:OVERNIGHT_PROGRESS.md | grep -q "already-done, target already deleted"'

ok "e2e NEG: a delete item's missing target is NOT re-created as a stub placeholder (that made it look doable again)" '! git -C "$REPO" log --format=%s | grep -q "stub new source file"'
mk_case stub_create
setup_progress '- [ ] [T2] scripts/new_mod.gd — Create the new helper module with a clamp function.'
scout_ok
runid
ok "e2e BENIGN: a CREATE item's missing target is still stubbed as before" 'git -C "$REPO" log --format=%s | grep "stub new source file" >/dev/null'   # no -q: grep -q + pipefail = SIGPIPE flake on a multi-line log
mk_case stub_verify_delete
setup_progress '- [ ] [T2] Clean up. VERIFY: `test ! -f scripts/other_dead.gd` returns exit code 0.'
scout_ok
runid
ok "e2e NEG: an item whose own VERIFY is test ! -f <file> never gets that file stubbed" '! git -C "$REPO" log --format=%s | grep -q "stub new source file"'

# DELETE: trailer for an already-deleted path (the model, not the executor, names it): benign already-done instead of a bare no-op
mk_case trailer_gone
setup_progress '- [ ] [T2] Tidy up the dead helper module (cat:refactor)'
scout_ok
aplan 2 'echo "DELETE: scripts/old_mod.gd"'
runid
eq "e2e: DELETE trailer for an already-deleted (in history) path => no-op(ALREADY-DONE)" "$OUT" "no-op(ALREADY-DONE)"
ok "e2e: logged as already deleted" 'logged "scripts/old_mod.gd is already deleted (git history)"'
mk_case trailer_never
setup_progress '- [ ] [T2] Tidy up the dead helper module (cat:refactor)'
scout_ok
aplan 2 'echo "DELETE: scripts/never_was.gd"'
runid
eq "e2e NEG: DELETE trailer for a path that never existed stays a plain no-op (not credited)" "$OUT" "no-op"
mk_case trailer_real
setup_progress '- [ ] [T2] Tidy up the dead helper module (cat:refactor)'
scout_ok
aplan 2 'echo "DELETE: old.py"'
vplan default 'exit 0'
runid
ok "e2e BENIGN: DELETE trailer for an EXISTING file still deletes it (unchanged)" '[[ "$OUT" == pushed* ]] && logged "DELETE trailer: removed old.py"'
# review hardening: '.' / a directory / traversal in a DELETE trailer is never "already deleted"
mk_case trailer_dot
setup_progress '- [ ] [T2] Tidy up the dead helper module (cat:refactor)'
scout_ok
aplan 2 'echo "DELETE: ."'
runid
eq "e2e NEG: DELETE trailer naming '.' (history of '.' always holds a deletion) stays a plain no-op" "$OUT" "no-op"
mk_case trailer_dir
setup_progress '- [ ] [T2] Tidy up the dead helper module (cat:refactor)'
( cd "$REPO" && mkdir -p scripts/keep && echo a > scripts/keep/a.txt && echo b > scripts/keep/b.gd && git add -A && git commit -q -m addkeep && git rm -q scripts/keep/b.gd && git commit -q -m rmkeep && git push -q origin HEAD:claude/feature ) >/dev/null 2>&1
scout_ok
aplan 2 'echo "DELETE: scripts/keep"'
runid
eq "e2e NEG: DELETE trailer naming an EXISTING directory (a file inside was deleted once) stays a plain no-op" "$OUT" "no-op"
summary
