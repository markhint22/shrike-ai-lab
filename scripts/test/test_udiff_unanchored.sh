#!/usr/bin/env bash
# 2026-10-13 (night review xlite F6 / iptv F9): unanchored udiff hunks on large files + dirty tracked lockfiles in the push-retry path.
#
# F6: aider's udiff coder APPENDS a hunk with no context line and no removed line to the END of the file.  xlite 20261013-011116: `@@ -1,0 +1,2 @@` with two '+' lines
# (meant for display_name()) landed after _draw() at the bottom of the ~1150-line scripts/units/unit.gd; the build-gate fix-up removed them again; NET-ZERO GUARD reset the cycle;
# the same thing happened three cycles in a row.  Fixture real_unit_gd_unanchored_eof_append.txt is that log, cut read-only from the box (lines 1-116).
# Part 1 = scripts/ovn_udiff_anchor.py (the detector) + lib_fixup.sh decision/nudge helpers.  Part 2 = the REAL run_overnight.sh implement loop in a hermetic fake tree
# (lib_ro_core.sh) with a stub aider that emits unanchored/anchored hunks.  Part 3 = lib_tree_guard.sh lockfile reset (iptv F9) incl. the real push-retry path.
# Part 4 = MUTATION controls (each fix reverted in a scratch copy of the tree; the suite's key assertions must then fail).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
FX="$HERE/fixtures/aider_attempt"
ANCHOR="$RO_Q/scripts/ovn_udiff_anchor.py"
ro_link scripts/ovn_udiff_anchor.py scripts/lib_tree_guard.sh update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py \
        scripts/ovn_classify.py scripts/ovn_progress_slice.py scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh
# shellcheck disable=SC1091
. "$RO_Q/scripts/lib_fixup.sh"
. "$RO_Q/scripts/lib_tree_guard.sh"

W="$T/w"; mkdir -p "$W"
mkbig(){ # mkbig <dir> <nlines>: a git repo with scripts/units/unit.gd (n lines) at HEAD
  rm -rf "$1"; mkdir -p "$1/scripts/units"; git init -q "$1" 2>/dev/null
  python3 - "$1/scripts/units/unit.gd" "$2" <<'PY'
import sys
n = int(sys.argv[2])
open(sys.argv[1], "w").write("".join("func f_%d(): return %d\n" % (i, i) for i in range(n)))
PY
  git -C "$1" add -A; git -C "$1" commit -q -m base
}
scan(){ python3 "$ANCHOR" "$@"; }
mkbig "$W/big" 1150; BIGSHA="$(git -C "$W/big" rev-parse HEAD)"; BIGN="$(wc -l < "$W/big/scripts/units/unit.gd" | tr -d ' ')"
echo "== detector (scripts/ovn_udiff_anchor.py) =="
OUT="$(scan "$FX/real_unit_gd_unanchored_eof_append.txt" "$W/big" --rev "$BIGSHA")"
ok "REAL xlite log + a 1150-line unit.gd: the '@@ -1,0 +1,2 @@' pure-addition hunk is flagged" "$([ "$(printf '%s\n' "$OUT" | grep -c "^scripts/units/unit.gd	${BIGN}	@@ -1,0 +1,2 @@")" = 1 ] && echo 1 || echo 0)"
ok "the anchored scout hunk (-/+ the same ELITE line) is not flagged: exactly one finding" "$([ "$(printf '%s\n' "$OUT" | grep -c .)" = 1 ] && echo 1 || echo 0)"
ok "the cycle's own fix-up hunk (@@ -1,2 +0,0 @@, only removed lines) is not flagged" "$([ "$(printf '%s\n' "$OUT" | grep -c '0,0')" = 0 ] && echo 1 || echo 0)"
mkbig "$W/small" 120
ok "the same log against a 120-line file (<= 300) => nothing flagged (EOF append on a small file stays as before)" "$([ -z "$(scan "$FX/real_unit_gd_unanchored_eof_append.txt" "$W/small" --rev HEAD)" ] && echo 1 || echo 0)"
ok "--min-lines can be lowered: 120 lines flagged with --min-lines 50" "$([ -n "$(scan "$FX/real_unit_gd_unanchored_eof_append.txt" "$W/small" --rev HEAD --min-lines 50)" ] && echo 1 || echo 0)"
ok "OVN_UDIFF_UNANCHORED_MIN_LINES env is honoured" "$([ -n "$(OVN_UDIFF_UNANCHORED_MIN_LINES=50 scan "$FX/real_unit_gd_unanchored_eof_append.txt" "$W/small" --rev HEAD)" ] && echo 1 || echo 0)"
ok "the real zero-context additions hunk on a missing/new path (real_dot_damage_applied) => nothing (file not at rev)" "$([ -z "$(scan "$FX/real_dot_damage_applied.txt" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ ... @@' ' func f_2():' ' 	return 2' '+	# note' > "$W/anch.log"
ok "a hunk with context lines is anchored => not flagged" "$([ -z "$(scan "$W/anch.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ ... @@' '-	return 2' '+	return 3' > "$W/del.log"
ok "a hunk with a removed line (replace) is anchored => not flagged" "$([ -z "$(scan "$W/del.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ ... @@' ' ' '+	# note' ' ' > "$W/blankctx.log"
ok "blank context lines do not anchor (they match anywhere) => flagged" "$([ -n "$(scan "$W/blankctx.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ ... @@' '+func g():' '+	pass' > "$W/bare.log"
ok "bare '@@ ... @@' header + only '+' lines on a big file => flagged" "$([ -n "$(scan "$W/bare.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' "@@ -${BIGN},0 +$((BIGN+1)),2 @@" '+func g():' '+	pass' > "$W/endapp.log"
ok "a numbered header placing the insertion at the very end of the file is an intended append => not flagged" "$([ -z "$(scan "$W/endapp.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ -600,0 +601,2 @@' '+func g():' '+	pass' > "$W/midnum.log"
ok "a numbered header pointing into the middle with no context => flagged (aider ignores the numbers and appends at EOF)" "$([ -n "$(scan "$W/midnum.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
mkdir -p "$W/big/tests"; for tp in tests/test_tech_manager.gd web/src/a.test.ts app/foo_test.py; do mkdir -p "$W/big/$(dirname "$tp")"; python3 -c 'print("\n".join("x%d" % i for i in range(400)))' > "$W/big/$tp"; done; git -C "$W/big" add -A; git -C "$W/big" commit -q -m tests
for tp in tests/test_tech_manager.gd web/src/a.test.ts app/foo_test.py; do printf '%s\n' "--- $tp" "+++ $tp" '@@ -1,0 +1,2 @@' '+func test_x() -> void:' '+	pass' > "$W/testpath.log"
ok "a pure-addition hunk on a TEST file ($tp, 400 lines) is a normal append of a new test => not flagged" "$([ -z "$(scan "$W/testpath.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"; done
ok "the REAL xlite test_tech_manager.gd hunk shape (20261013-021646, @@ -1,0 +1,8 @@) is not flagged either" "$(printf '%s\n' '--- tests/test_tech_manager.gd' '+++ tests/test_tech_manager.gd' '@@ -1,0 +1,8 @@' '+func test_improved_ammo_material_cost() -> void:' '+	var techs := TechManager.get_techs()' > "$W/real_test.log"; [ -z "$(scan "$W/real_test.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- /dev/null' '+++ scripts/units/unit.gd' '@@ -0,0 +1,2 @@' '+func g():' '+	pass' > "$W/newfile.log"
ok "a new-file hunk (--- /dev/null) is never flagged" "$([ -z "$(scan "$W/newfile.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/missing.gd' '+++ scripts/units/missing.gd' '@@ ... @@' '+func g():' > "$W/missing.log"
ok "a path that does not exist at the rev is skipped (no crash)" "$([ -z "$(scan "$W/missing.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
ok "garbage/empty/missing inputs never fail: rc 0, no output" "$(python3 "$ANCHOR" /nonexistent "$W/big" >/dev/null 2>&1; r1=$?; : > "$W/empty.log"; python3 "$ANCHOR" "$W/empty.log" "$W/nonrepo" --rev HEAD >/dev/null 2>&1; r2=$?; python3 "$ANCHOR" >/dev/null 2>&1; r3=$?; [ "$r1$r2$r3" = 000 ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ ... @@' '+func g():' '+	var long_line_wrapped_by_the_terminal = 1' 'continuation of a wrapped line' '-	return 2' > "$W/wrap.log"
ok "a terminal-wrapped continuation line inside a hunk does not hide a later removed line (anchored)" "$([ -z "$(scan "$W/wrap.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ ... @@' '+func a():' '@@ ... @@' ' func f_2():' '+	# x' > "$W/twohunks.log"
ok "two hunks: the unanchored one is found even when a later hunk is anchored" "$([ "$(scan "$W/twohunks.log" "$W/big" --rev HEAD | grep -c .)" = 1 ] && echo 1 || echo 0)"

# --- python EOF-tolerant additions (reviewer finding: 4 of 18 flagged cycles landed on the box) ---
mkdir -p "$W/big/app"; python3 -c 'print("\n".join("def f_%d(): return %d" % (i, i) for i in range(1, 801)))' > "$W/big/app/svc.py"; git -C "$W/big" add -A; git -C "$W/big" commit -q -m py
pyh(){ # pyh <label> <hunk header> <added lines...>: writes $W/py.log for app/svc.py
  local h="$1"; shift; { printf '%s\n' '--- app/svc.py' '+++ app/svc.py' "$h"; for l in "$@"; do printf '+%s\n' "$l"; done; } > "$W/py.log"; }
pyhit(){ scan "$W/py.log" "$W/big" --rev HEAD | grep -c .; }
pyh '@@ -1,0 +1,23 @@' 'def helper(x):' '    return x + 1' '' 'def other(y):' '    return y'
ok "PY1 (real iptv playlist.py shape) top-level defs appended at EOF => NOT flagged" "$([ "$(pyhit)" = 0 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +2 @@' 'import logging'
ok "PY2 (2nd review) an import-only hunk is NOT exempt any more: the edit that uses the import was lost => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +2 @@' 'import logging' 'from app.core.limiter import limiter'
ok "PY2b several imports and nothing else => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +2,3 @@' 'import logging' '' 'LOG = logging.getLogger(__name__)'
ok "PY2c an import PLUS the module-level statement that uses it => still NOT flagged" "$([ "$(pyhit)" = 0 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +1,5 @@' 'ALLOWED_METRIC_FIELDS = {' '    "a",' '    "b",' '}' 'TIMEOUT: int = 30'
ok "PY3 (real main.py shape) a multi-line module constant + an annotated assignment => NOT flagged" "$([ "$(pyhit)" = 0 ] && echo 1 || echo 0)"
pyh '@@ ... @@' '@router.get("/x")' 'async def x():' '    return 1' '' 'class Foo:' '    pass' 'from a.b import c'
ok "PY4 a decorator + async def + class + from-import => NOT flagged" "$([ "$(pyhit)" = 0 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +1,2 @@' '    elif kind == "x":' '        return 1'
ok "PY5 an INDENTED first line (a branch body meant for the middle of a function) is still flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +1,2 @@' 'if kind == "x":' '    return 1'
ok "PY6 a module-level control-flow statement (if) is still flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +1,2 @@' 'def helper(x):' '    return x' 'return 5'
ok "PY7 one non-tolerant line (a stray return) among top-level defs => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +1,2 @@' '# just a comment' '# another'
ok "PY8 comments only (no module-level statement at all) => flagged (nothing proves it is an EOF-safe addition)" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -1,0 +1,2 @@' 'def helper(x):' '    return x'
ok "PY9 OVN_UDIFF_PY_EOF_OK=off flags the tolerant shape again" "$([ "$(OVN_UDIFF_PY_EOF_OK=off scan "$W/py.log" "$W/big" --rev HEAD | grep -c .)" = 1 ] && echo 1 || echo 0)"
printf '%s\n' '--- scripts/units/unit.gd' '+++ scripts/units/unit.gd' '@@ -1,0 +1,2 @@' '+def helper(x):' '+    return x' > "$W/gdpy.log"
ok "PY10 the exemption is .py only: the same python-looking text on a .gd file is flagged" "$([ -n "$(scan "$W/gdpy.log" "$W/big" --rev HEAD)" ] && echo 1 || echo 0)"

# 2nd review (MAJOR): a decorator-only / import-only hunk appended at EOF is NOT harmless (iptv downloads.py '+@limiter.limit("5/minute")' loop: SyntaxError 491:1 -> fix-up -> revert)
pyh '@@ -69,0 +71 @@' '@limiter.limit("5/minute")'
ok "PY11 a lone decorator line (dangling at EOF = SyntaxError) => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -69,0 +71 @@' '@limiter.limit("5/minute")' '@other.deco'
ok "PY12 only decorators (no def/class after them) => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -69,0 +71,3 @@' '@limiter.limit("5/minute")' '# note' 'x = 1'
ok "PY13 a decorator followed by an assignment (not a def/class) => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -69,0 +71,5 @@' '@limiter.limit("5/minute")' '@router.get(' '    "/x",' ')' 'async def x():' '    return 1'
ok "PY14 a (multi-line) decorator stack followed by a def with a body => NOT flagged" "$([ "$(pyhit)" = 0 ] && echo 1 || echo 0)"
pyh '@@ -17,0 +18 @@' 'def helper(x):'
ok "PY15 a def header with no body (does not parse alone) => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
pyh '@@ -17,0 +18 @@' 'def helper(x): return x'
ok "PY15b a one-line def is complete => NOT flagged" "$([ "$(pyhit)" = 0 ] && echo 1 || echo 0)"
# the REAL box log (iptv 20261008-010537, cut read-only): single-line '+from app.core.limiter import limiter' and '+@limiter.limit("5/minute")' hunks on downloads.py
mkdir -p "$W/big/iptv-backend/app/routers"; python3 -c 'print("\n".join("def f_%d(): return %d" % (i, i) for i in range(1, 490)))' > "$W/big/iptv-backend/app/routers/downloads.py"; git -C "$W/big" add -A; git -C "$W/big" commit -q -m dl
OUT="$(scan "$FX/real_iptv_downloads_limiter_decorator_import.txt" "$W/big" --rev HEAD)"
ok "REAL iptv downloads.py attempt (import + dangling @limiter.limit hunks) => both hunks flagged" "$([ "$(printf '%s\n' "$OUT" | grep -c '^iptv-backend/app/routers/downloads.py	489	@@ -')" = 2 ] && echo 1 || echo 0)"
ok "the same REAL log with OVN_UDIFF_PY_EOF_OK=off is flagged identically (2 hunks)" "$([ "$(OVN_UDIFF_PY_EOF_OK=off scan "$FX/real_iptv_downloads_limiter_decorator_import.txt" "$W/big" --rev HEAD | grep -c .)" = 2 ] && echo 1 || echo 0)"
# 2nd review (MINOR): keyword headers must not pass as module-level assignments
for kw in 'else: x = 1' 'try: x = 1' 'finally: y = 2' 'except: x = 1' 'class: x = 1' 'elif: x = 1' 'if: x = 1' 'for: x = 1' 'while: x = 1' 'with: x = 1' 'def: x = 1' 'return = 1'; do
  pyh '@@ -17,0 +18 @@' "$kw"
  ok "PY16 keyword header '$kw' is not a module-level assignment => flagged" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
  pyh '@@ -17,0 +18,2 @@' 'ok_one = 1' "$kw"
  ok "PY16b '$kw' next to a valid assignment still flags the hunk" "$([ "$(pyhit)" = 1 ] && echo 1 || echo 0)"
  ok "PY16c classifier (without the parse safety net): '$kw' is not an assignment/def line" "$(python3 - "$ANCHOR" "$kw" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("a", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(1 if m._py_top_kind(sys.argv[2]) is None else 0)
PY
)"
done
ok "PY17 keyword-PREFIXED names are still plain assignments (else_x = 1, tryit: int = 2, classes = []) => NOT flagged" "$(pyh '@@ -17,0 +18,3 @@' 'else_x = 1' 'tryit: int = 2' 'classes = []'; [ "$(pyhit)" = 0 ] && echo 1 || echo 0)"

echo "== decision / nudge helpers (lib_fixup.sh) =="
d(){ ovn_udiff_unanchored_decision "$@"; }
ok "decision: found, first time => reset-retry" "$([ "$(d 1 0 on)" = reset-retry ] && echo 1 || echo 0)"
ok "decision: found again after the retry => refuse" "$([ "$(d 1 1 on)" = refuse ] && echo 1 || echo 0)"
ok "decision: nothing found => none" "$([ "$(d 0 0 on)" = none ] && [ "$(d 0 1 on)" = none ] && echo 1 || echo 0)"
ok "decision: mode shadow => shadow (log only), mode off => none" "$([ "$(d 1 0 shadow)" = shadow ] && [ "$(d 1 0 off)" = none ] && echo 1 || echo 0)"
ok "decision: default mode comes from OVN_UDIFF_UNANCHORED (unset => on)" "$([ "$(unset OVN_UDIFF_UNANCHORED; d 1 0)" = reset-retry ] && [ "$(OVN_UDIFF_UNANCHORED=off d 1 0)" = none ] && echo 1 || echo 0)"
NT="$(ovn_udiff_unanchored_nudge_text "$(printf 'scripts/units/unit.gd\t1150\t@@ -1,0 +1,2 @@')")"
ok "nudge text names the file, the hunk, the file length and the 3-lines-of-context rule" "$(printf '%s' "$NT" | grep -q 'scripts/units/unit.gd' && printf '%s' "$NT" | grep -q '@@ -1,0 +1,2 @@' && printf '%s' "$NT" | grep -q '1150 lines' && printf '%s' "$NT" | grep -q 'at least 3 unchanged lines' && echo 1 || echo 0)"
ok "scan wrapper prints the finding for the real slice and nothing for a clean slice" "$([ -n "$(ovn_udiff_unanchored_scan "$FX/real_unit_gd_unanchored_eof_append.txt" "$W/big" "$BIGSHA")" ] && [ -z "$(ovn_udiff_unanchored_scan "$FX/real_dot_damage_applied.txt" "$W/big" "$BIGSHA")" ] && echo 1 || echo 0)"

echo "== the real implement loop (run_overnight.sh, stub aider) =="
# aider stub: scout -> PROCEED on app/big.py; implement attempt k does the k-th word of state/un_seq (last word repeats):
#   unanchored  prints a '@@ -1,0 +1,2 @@' pure-addition hunk whose first line is module-level CONTROL FLOW (`if True:` + an indented block; valid python, so the build gate stays quiet), APPENDS it at EOF of app/big.py, commits   (what aider's udiff coder does with it)
#   toplevel    the same hunk shape but MODULE-LEVEL python (a def + a constant): appended at EOF it still works, so it must NOT be flagged
#   anchored    prints a hunk with 3 context lines, inserts the lines after line 500, commits
#   endappend   prints '@@ -1000,0 +1001,1 @@' (an intended append at the end), appends, commits
ro_stub aider <<'EOF'
S="${RO_STUB:?}"
n=$(( $(cat "$S/aider_n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$S/aider_n"
msg=""; prev=""; for a in "$@"; do [ "$prev" = "--message" ] && msg="$a"; prev="$a"; done
case " $* " in
  *" --no-auto-commits "*)
    printf 'VERDICT: PROCEED\nPLAN: add a function to app/big.py\nFILES: app/big.py\nTokens: 1.2k sent, 300 received.\n'; exit 0;;
esac
k=$(( $(cat "$S/impl_n" 2>/dev/null || echo 0) + 1 )); echo "$k" > "$S/impl_n"
printf '%s' "$msg" > "$S/impl_msg.$k"
act=none; i=0; for w in $(cat "$S/un_seq"); do i=$((i+1)); act="$w"; [ "$i" -ge "$k" ] && break; done
case "$act" in
  unanchored)
    printf '\n--- app/big.py\n+++ app/big.py\n@@ -1,0 +1,3 @@\n+if True:\n+    def added_%s(): return 1\n+    def added_%s_b(): return 2\n\nTokens: 29k sent, 46 received.\nApplied edit to app/big.py\n' "$k" "$k"
    printf 'if True:\n    def added_%s(): return 1\n    def added_%s_b(): return 2\n' "$k" "$k" >> app/big.py
    git add -A; git commit -q -m "feat: add function $k"; echo "Commit abc123$k feat: add function $k";;
  toplevel)
    printf '\n--- app/big.py\n+++ app/big.py\n@@ -1,0 +1,3 @@\n+def added_%s(x):\n+    return x + 1\n+LIMIT_%s = 5\n\nTokens: 29k sent, 46 received.\nApplied edit to app/big.py\n' "$k" "$k"
    printf 'def added_%s(x):\n    return x + 1\nLIMIT_%s = 5\n' "$k" "$k" >> app/big.py
    git add -A; git commit -q -m "feat: add function $k"; echo "Commit 0a1b2c$k feat: add function $k";;
  anchored)
    printf '\n--- app/big.py\n+++ app/big.py\n@@ -498,3 +498,4 @@\n def f_498(): return 498\n def f_499(): return 499\n def f_500(): return 500\n+def added_%s(): return 1\n\nTokens: 29k sent, 46 received.\nApplied edit to app/big.py\n' "$k"
    python3 -c 'import sys; L=open("app/big.py").read().split("\n"); L.insert(500, "def added_%s(): return 1" % sys.argv[1]); open("app/big.py","w").write("\n".join(L))' "$k"
    git add -A; git commit -q -m "feat: add function $k"; echo "Commit def456$k feat: add function $k";;
  endappend)
    printf '\n--- app/big.py\n+++ app/big.py\n@@ -1000,0 +1001,1 @@\n+def added_%s(): return 1\n\nTokens: 29k sent, 46 received.\nApplied edit to app/big.py\n' "$k"
    printf 'def added_%s(): return 1\n' "$k" >> app/big.py
    git add -A; git commit -q -m "feat: add function $k"; echo "Commit 789abc$k feat: add function $k";;
  *) echo "I considered the request but produced no edits.";;
esac
exit 0
EOF
ro_hook_stubs
ST="$T/tree/state"; R="$T/repos"; mkdir -p "$ST"
mkloop(){ # mkloop <name> <nlines>
  ro_mkrepo "$1" '# Overnight Progress

## Next Steps
- [ ] [T1] `app/big.py` — add a function (cat:python)' >/dev/null
  ( cd "$R/$1" || { echo "FATAL mkloop: cd $R/$1 failed - refusing to run git in $PWD" >&2; kill -TERM $$; exit 1; }; python3 - "$2" <<'PY'
import sys
open("app/big.py", "w").write("".join("def f_%d(): return %d\n" % (i, i) for i in range(1, int(sys.argv[1]) + 1)))
PY
    git add -A; git commit -q -m "big file"; git push -q origin main 2>/dev/null )
}
runloop(){ # runloop <name> "<un_seq>" [ENV=VAL...]
  local nm="$1" seq="$2"; shift 2
  rm -f "$RO_STUB/aider_n" "$RO_STUB/impl_n" "$RO_STUB"/impl_msg.* "$T/tree/reports"/*; echo "$seq" > "$RO_STUB/un_seq"; : > "$ST/outcomes.jsonl"
  ro_tasks "$(jq -nc --arg R "$R" --arg n "$nm" '[{id:("t-"+$n),repo:($R+"/"+$n),prompt:"x"}]')"
  ro_run_main "$@"
  REP="$(ro_report)"
  ROW="$(printf '%s\n' "$REP" | grep -F "| t-$nm |" | head -1)"
  IMPLS="$(cat "$RO_STUB/impl_n" 2>/dev/null || echo 0)"
}
tlog(){ cat "$T/tree/logs"/*/ongoing-"$1".log 2>/dev/null; cat "$T/tree/logs"/*/*"$1"*.log 2>/dev/null; }

mkloop r-heal 1000
runloop r-heal "unanchored anchored"
LOG="$RO_OUT"
echo "-- heal: unanchored first, anchored second --"
has "first attempt's unanchored hunk is detected and the edit discarded + retried" "$RO_OUT$(tlog r-heal)" "UDIFF-UNANCHORED: app/big.py"
eq "exactly two implement attempts" 2 "$IMPLS"
has "the retry prompt carries the anchor nudge (names the file and the rule)" "$(cat "$RO_STUB/impl_msg.2" 2>/dev/null)" "had a hunk (@@ -1,0 +1,3 @@) with NO context lines"
hasnt "the first attempt's prompt has no nudge" "$(cat "$RO_STUB/impl_msg.1" 2>/dev/null)" "NO context lines"
has "the cycle then lands normally" "$ROW" "pushed"
eq "the EOF-appended function is gone, the anchored one landed mid-file" "1" "$([ "$(grep -c 'def added_1' "$R/r-heal/app/big.py")" = 0 ] && [ "$(grep -c 'def added_2()' "$R/r-heal/app/big.py")" = 1 ] && [ "$(sed -n 501p "$R/r-heal/app/big.py")" = 'def added_2(): return 1' ] && echo 1 || echo 0)"

mkloop r-refuse 1000
runloop r-refuse "unanchored unanchored unanchored"
echo "-- refuse: the hunk comes back unanchored again --"
eq "exactly two implement attempts (one retry, then refuse early)" 2 "$IMPLS"
has "second occurrence is refused early" "$RO_OUT$(tlog r-refuse)" "refusing early (no net-zero cycle)"
has "the cycle reports no-op(unanchored-hunk)" "$ROW" "no-op(unanchored-hunk)"
hasnt "no net-zero cycle (nothing was committed, so the guard never fired)" "$RO_OUT$(tlog r-refuse)" "NET-ZERO GUARD:"
eq "repo is back at the pre-cycle commit and clean" "0" "$(git -C "$R/r-refuse" status --porcelain | grep -c .)"
eq "no 'added_' function remains in the file" "0" "$(grep -c 'def added_' "$R/r-refuse/app/big.py")"
eq "nothing reached origin" "$(git -C "$R/r-refuse" rev-parse HEAD)" "$(git -C "$T/origin/r-refuse.git" rev-parse main)"
has "outcomes row is classed as a bad no-op (discarded model work)" "$(cat "$ST/outcomes.jsonl")" '"status":"no-op(unanchored-hunk)"'

mkloop r-off 1000
runloop r-off "unanchored" OVN_UDIFF_UNANCHORED=off
echo "-- kill switch OVN_UDIFF_UNANCHORED=off --"
eq "one implement attempt, old behaviour (the EOF append lands)" 1 "$IMPLS"
hasnt "no detector line in the log" "$RO_OUT$(tlog r-off)" "UDIFF-UNANCHORED"
has "the cycle pushes the appended edit as before" "$ROW" "pushed"

mkloop r-shadow 1000
runloop r-shadow "unanchored" OVN_UDIFF_UNANCHORED=shadow
echo "-- shadow mode --"
eq "one implement attempt (shadow never resets)" 1 "$IMPLS"
has "shadow logs what it would have done" "$RO_OUT$(tlog r-shadow)" "UDIFF-UNANCHORED (shadow)"
has "and the cycle behaves as before" "$ROW" "pushed"

mkloop r-small 100
runloop r-small "unanchored"
echo "-- small file (100 lines <= 300) --"
eq "one implement attempt" 1 "$IMPLS"
hasnt "not flagged" "$RO_OUT$(tlog r-small)" "UDIFF-UNANCHORED"
has "lands as before" "$ROW" "pushed"

mkloop r-endapp 1000
runloop r-endapp "endappend"
echo "-- intended append at the end of a big file --"
eq "one implement attempt" 1 "$IMPLS"
hasnt "not flagged" "$RO_OUT$(tlog r-endapp)" "UDIFF-UNANCHORED"
has "lands" "$ROW" "pushed"

mkloop r-anch 1000
runloop r-anch "anchored"
echo "-- a well-anchored hunk on a big file --"
eq "one implement attempt" 1 "$IMPLS"
hasnt "not flagged" "$RO_OUT$(tlog r-anch)" "UDIFF-UNANCHORED"
has "lands" "$ROW" "pushed"

mkloop r-pytop 1000
runloop r-pytop "toplevel"
echo "-- python module-level addition appended at EOF of a big .py (reviewer finding) --"
eq "one implement attempt (no reset, no nudge)" 1 "$IMPLS"
hasnt "not flagged" "$RO_OUT$(tlog r-pytop)" "UDIFF-UNANCHORED"
has "lands as before" "$ROW" "pushed"
mkloop r-pytop-off 1000
runloop r-pytop-off "toplevel unanchored" OVN_UDIFF_PY_EOF_OK=off
eq "OVN_UDIFF_PY_EOF_OK=off: the same hunk is flagged, reset and retried (2 attempts)" 2 "$IMPLS"
has "and the detector line is logged" "$RO_OUT$(tlog r-pytop-off)" "UDIFF-UNANCHORED: app/big.py"

echo "== dirty tracked lockfiles (lib_tree_guard.sh) =="
mklock(){ rm -rf "$1"; mkdir -p "$1/iptv-web"; git init -q "$1" 2>/dev/null; printf '{"v":1}\n' > "$1/iptv-web/package-lock.json"; printf 'a\n' > "$1/code.py"; printf 'x\n' > "$1/poetry.lock"; git -C "$1" add -A; git -C "$1" commit -q -m base; }
mklock "$W/lk"; : > "$W/lk.log"
printf '{"v":2}\n' > "$W/lk/iptv-web/package-lock.json"
ovn_tree_dirty_note "$W/lk" "$W/lk.log" "verify (.ovn-verify.sh)"
ok "dirty note names the step and the lockfile" "$(grep -q 'TREE-DIRTY after verify (.ovn-verify.sh): iptv-web/package-lock.json' "$W/lk.log" && echo 1 || echo 0)"
ovn_reset_dirty_lockfiles "$W/lk" "$W/lk.log" push-retry
ok "dirty tracked lockfile is restored to HEAD" "$([ "$(cat "$W/lk/iptv-web/package-lock.json")" = '{"v":1}' ] && [ -z "$(git -C "$W/lk" status --porcelain)" ] && echo 1 || echo 0)"
ok "the reset is logged with the path" "$(grep -q 'LOCKFILE-RESET (push-retry): restored tracked lockfile iptv-web/package-lock.json' "$W/lk.log" && echo 1 || echo 0)"
mklock "$W/lk2"; : > "$W/lk2.log"; printf '{"v":2}\n' > "$W/lk2/iptv-web/package-lock.json"; git -C "$W/lk2" add iptv-web/package-lock.json; printf 'b\n' >> "$W/lk2/poetry.lock"; printf 'edit\n' >> "$W/lk2/code.py"
ovn_reset_dirty_lockfiles "$W/lk2" "$W/lk2.log" x
ok "a STAGED lockfile change and a second lockfile are restored too" "$([ "$(cat "$W/lk2/iptv-web/package-lock.json")" = '{"v":1}' ] && [ "$(cat "$W/lk2/poetry.lock")" = 'x' ] && echo 1 || echo 0)"
ok "a real source edit is NEVER touched (and is logged as left in place)" "$([ "$(cat "$W/lk2/code.py")" = "$(printf 'a\nedit')" ] && grep -q 'non-lockfile tracked change(s) left in place: code.py' "$W/lk2.log" && echo 1 || echo 0)"
mklock "$W/lk3"; printf '{"v":2}\n' > "$W/lk3/iptv-web/package-lock.json"
OVN_LOCKFILE_RESET=off ovn_reset_dirty_lockfiles "$W/lk3" /dev/null x
ok "OVN_LOCKFILE_RESET=off leaves the lockfile alone" "$([ "$(cat "$W/lk3/iptv-web/package-lock.json")" = '{"v":2}' ] && echo 1 || echo 0)"
mklock "$W/lk4"; ovn_reset_dirty_lockfiles "$W/lk4" /dev/null x; ovn_tree_dirty_note "$W/lk4" "$W/lk4.log" s
ok "a clean tree: nothing logged, rc 0" "$([ ! -s "$W/lk4.log" ] && echo 1 || echo 0)"

echo "-- the real push-retry path: tool dirties the lockfile, origin advances --"
# stub npm-ish step: the repo's verify script rewrites a tracked lockfile (like 'npm ci' resolving differently) - then origin gets a new commit so the push is rejected.
mkloop r-lock 1000
( cd "$R/r-lock" && printf '{"v":1}\n' > package-lock.json && git add -A && git commit -q -m lock && git push -q origin main 2>/dev/null )
cat > "$R/r-lock/.ovn-verify.sh" <<'V'
#!/bin/bash
# verify that dirties a tracked lockfile and (once) advances origin so the cycle's push is rejected
printf '{"v":99}\n' > package-lock.json
if [ ! -f "${RO_STUB}/advanced" ]; then
  touch "${RO_STUB}/advanced"
  b="$(git rev-parse --abbrev-ref HEAD)"   # the cycle works on its own overnight/<ts>/<id> branch: advance THAT branch on origin so the cycle's push is non-fast-forward
  d="$(mktemp -d)" || exit 1; git clone -q "$(git remote get-url origin)" "$d" 2>/dev/null; ( cd "$d" && git checkout -q -b "$b" origin/main && echo other > other.txt && git add -A && git -c user.name=o -c user.email=o@o commit -q -m other && git push -q origin "$b" 2>/dev/null ); rm -rf "$d"
fi
echo "verify ok"; exit 0
V
chmod +x "$R/r-lock/.ovn-verify.sh"; ( cd "$R/r-lock" && git add -A && git commit -q -m verify-script && git push -q origin main 2>/dev/null )
rm -f "$RO_STUB/advanced"
runloop r-lock "anchored"
LOG="$RO_OUT$(tlog r-lock)"
has "the log names the step that left the lockfile dirty" "$LOG" "TREE-DIRTY after verify"
has "the dirty lockfile is restored after the verify" "$LOG" "LOCKFILE-RESET (after verify): restored tracked lockfile package-lock.json"
has "the rejected push is rebased and lands (not 'cannot pull with rebase: unstaged changes')" "$ROW" "pushed(after-rebase)"
hasnt "no unstaged-changes rebase failure" "$LOG" "cannot pull with rebase"
hasnt "no push-diverged transient status" "$ROW" "push-diverged"

echo "== wiring (code lines) =="
RUN="$RO_Q/run_overnight.sh"
ok "retry flags initialised once per implement loop" "$([ "$(grep -c '^    _ovn_retry_nm=0; _ovn_retry_unf=0; _ovn_retry_una=0; _ovn_una_refused=0' "$RUN")" = 1 ] && echo 1 || echo 0)"
ok "the unanchored check sits BEFORE the commit-detection (NOW_SHA) block" "$([ "$(grep -n 'ovn_udiff_unanchored_scan "\$_ovn_slice2"' "$RUN" | head -1 | cut -d: -f1)" -lt "$(grep -n '^      NOW_SHA="\$(git rev-parse HEAD)"' "$RUN" | head -1 | cut -d: -f1)" ] && echo 1 || echo 0)"
ok "the refuse status is emitted right after the implement loop" "$([ "$(grep -c 'echo "no-op(unanchored-hunk)"' "$RUN")" = 1 ] && echo 1 || echo 0)"
ok "the push-retry and credit-push paths reset dirty lockfiles before the rebase" "$([ "$(grep -c 'ovn_reset_dirty_lockfiles "\$PWD" "\$task_log" "push-retry"' "$RUN")" = 1 ] && [ "$(grep -c 'ovn_reset_dirty_lockfiles "\$PWD" "\$task_log" "credit-push-retry"' "$RUN")" = 1 ] && echo 1 || echo 0)"

echo "== MUTATION controls (scratch copy of the tree) =="
MQ="$T/mut"; rm -rf "$MQ"; mkdir -p "$MQ"
mutate(){ # mutate <file-rel> <python-expr old> <new> : replace exactly one occurrence in the scratch copy
  python3 - "$MQ/$1" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
assert s.count(a) == 1, (p, a, s.count(a))
open(p, "w").write(s.replace(a, b))
PY
}
runmut(){ # runmut <label>: run this very test file from the scratch copy and capture failing lines
  ( cd "$MQ/scripts/test" && timeout 900 bash test_udiff_unanchored.sh ) > "$T/mut.out" 2>&1
  [ -n "${UDIFF_KEEP:-}" ] && { echo "### $1"; cat "$T/mut.out"; } >> "$UDIFF_KEEP"
  true
}
if [ "${UDIFF_TEST_NO_MUTATION:-0}" = 1 ]; then
  echo "  (mutation controls skipped: nested run)"
else
  # Copy ONLY the code tree. The live box queue holds ~460k files (repos/ 6 GB, logs/ 2.7 GB, state/); copying all of it into the tmpfs /tmp
  # ran out of inodes (ENOSPC), so every mutant failed to set up and the 8 MUTATION checks failed for the wrong reason (2026-10-15 r17 box run).
  if ( cd "$RO_Q" && tar -cf - --exclude=./logs --exclude=./state --exclude=./repos --exclude=./reports --exclude=./_archive_pre_git_bak --exclude=__pycache__ . ) | tar -C "$MQ" -xf - 2>/dev/null \
     && [ -s "$MQ/run_overnight.sh" ] && [ -s "$MQ/scripts/test/test_udiff_unanchored.sh" ]; then MQ_OK=1; else MQ_OK=0; fi
  ok "MUTATION scratch copy of the code tree is complete (run_overnight.sh and scripts/test present)" "$MQ_OK"
  # M1: the detector never reports anything
  cp "$RO_Q/scripts/ovn_udiff_anchor.py" "$T/anchor.orig"
  mutate scripts/ovn_udiff_anchor.py 'return bool(adds) and not dels and not ctx' 'return False'
  UDIFF_TEST_NO_MUTATION=1 runmut M1
  ok "MUTATION: a detector that never flags makes the detector + retry + refuse assertions FAIL" "$([ "$(grep -c '^  FAIL' "$T/mut.out")" -ge 5 ] && grep -q 'FAIL exactly two implement attempts' "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/anchor.orig" "$MQ/scripts/ovn_udiff_anchor.py"
  # M2: refuse branch behaves like retry forever is impossible; instead make the decision never refuse (old net-zero behaviour: just fall through)
  cp "$RO_Q/scripts/lib_fixup.sh" "$T/fixup.orig"
  mutate scripts/lib_fixup.sh '*) if [ "$retried" = 0 ]; then echo reset-retry; else echo refuse; fi ;;' '*) echo none ;;'
  UDIFF_TEST_NO_MUTATION=1 runmut M2
  ok "MUTATION: a decision that always says none makes the heal/refuse loop assertions FAIL" "$(grep -q 'FAIL the cycle reports no-op(unanchored-hunk)' "$T/mut.out" && grep -q 'FAIL decision: found, first time => reset-retry' "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/fixup.orig" "$MQ/scripts/lib_fixup.sh"
  # M3: the small-file / end-append exemptions removed
  mutate scripts/ovn_udiff_anchor.py 'if n is None or n <= min_lines or intended_append(header, n):' 'if n is None:'
  UDIFF_TEST_NO_MUTATION=1 runmut M3
  ok "MUTATION: without the size threshold and the intended-append exemption those controls FAIL" "$(grep -q 'FAIL the same log against a 120-line file' "$T/mut.out" && grep -q 'FAIL a numbered header placing the insertion at the very end' "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/anchor.orig" "$MQ/scripts/ovn_udiff_anchor.py"
  # M5: test files are not exempt
  mutate scripts/ovn_udiff_anchor.py 'if old == "/dev/null" or is_test_path(path) or not is_unanchored(body) or py_eof_tolerant(path, body):' 'if old == "/dev/null" or not is_unanchored(body) or py_eof_tolerant(path, body):'
  UDIFF_TEST_NO_MUTATION=1 runmut M5
  ok "MUTATION: without the test-file exemption the real test_tech_manager.gd shape is wrongly flagged" "$(grep -q 'FAIL the REAL xlite test_tech_manager.gd hunk shape' "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/anchor.orig" "$MQ/scripts/ovn_udiff_anchor.py"
  # M6: the python EOF-tolerance removed (the first shipped behaviour: every pure-addition hunk on a big file is flagged)
  mutate scripts/ovn_udiff_anchor.py 'or py_eof_tolerant(path, body):' ':'
  UDIFF_TEST_NO_MUTATION=1 runmut M6
  ok "MUTATION: without the python EOF-tolerance the real iptv shapes are wrongly flagged (PY1, PY3, PY4 and the r-pytop loop FAIL)" "$(grep -q 'FAIL PY1' "$T/mut.out" && grep -q 'FAIL PY3' "$T/mut.out" && grep -q 'FAIL one implement attempt (no reset, no nudge)' "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/anchor.orig" "$MQ/scripts/ovn_udiff_anchor.py"
  # M7: the pre-2nd-review exemption (dangling decorators, import-only hunks and unparsable hunks all tolerated)
  mutate scripts/ovn_udiff_anchor.py 'if pending_deco and kind not in ("def", "deco"):' 'if False:'
  mutate scripts/ovn_udiff_anchor.py 'if pending_deco or not (seen_top and substantive):' 'if not seen_top:'
  mutate scripts/ovn_udiff_anchor.py '        ast.parse("\n".join(added) + "\n")' '        pass'
  UDIFF_TEST_NO_MUTATION=1 runmut M7
  ok "MUTATION: tolerating decorator-only / import-only / unparsable hunks makes PY2, PY11..PY13, PY15 and the REAL downloads.py assertion FAIL" "$(grep -q 'FAIL PY2 ' "$T/mut.out" && grep -q 'FAIL PY11' "$T/mut.out" && grep -q 'FAIL PY12' "$T/mut.out" && grep -q 'FAIL PY13' "$T/mut.out" && grep -q 'FAIL PY15 ' "$T/mut.out" && grep -q 'FAIL REAL iptv downloads.py attempt' "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/anchor.orig" "$MQ/scripts/ovn_udiff_anchor.py"
  # M8: python keywords allowed as assignment names again
  mutate scripts/ovn_udiff_anchor.py '_KW = "|".join(sorted(keyword.kwlist, key=len, reverse=True))' '_KW = "zzzzzzzz"'
  UDIFF_TEST_NO_MUTATION=1 runmut M8
  ok "MUTATION: without the keyword exclusion the keyword-header classifier assertions (PY16c) FAIL" "$(grep -q "FAIL PY16c classifier (without the parse safety net): 'else: x = 1'" "$T/mut.out" && grep -q "FAIL PY16c classifier (without the parse safety net): 'try: x = 1'" "$T/mut.out" && grep -q "FAIL PY16c classifier (without the parse safety net): 'class: x = 1'" "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/anchor.orig" "$MQ/scripts/ovn_udiff_anchor.py"
  # M4: no lockfile reset in the runner (the old push-retry behaviour)
  cp "$RO_Q/run_overnight.sh" "$T/run.orig"
  mutate run_overnight.sh '      declare -F ovn_reset_dirty_lockfiles >/dev/null 2>&1 && ovn_reset_dirty_lockfiles "$PWD" "$task_log" "after verify"' '      :'
  mutate run_overnight.sh 'ovn_reset_dirty_lockfiles "$PWD" "$task_log" "push-retry"; fi' ':; fi'
  UDIFF_TEST_NO_MUTATION=1 runmut M4
  ok "MUTATION: without the lockfile reset the real push-retry scenario FAILS (rebase blocked by the dirty lockfile)" "$(grep -q 'FAIL the rejected push is rebased and lands (not' "$T/mut.out" && echo 1 || echo 0)"
  cp "$T/run.orig" "$MQ/run_overnight.sh"
fi
ok "the real tree is untouched by the mutation runs (no mutant in the tracked sources)" "$(grep -q 'return bool(adds) and not dels and not ctx' "$RO_Q/scripts/ovn_udiff_anchor.py" && grep -q 'if n is None or n <= min_lines or intended_append(header, n):' "$RO_Q/scripts/ovn_udiff_anchor.py" && grep -q 'or not is_unanchored(body) or py_eof_tolerant(path, body):' "$RO_Q/scripts/ovn_udiff_anchor.py" && grep -q 'if pending_deco and kind not in ("def", "deco"):' "$RO_Q/scripts/ovn_udiff_anchor.py" && grep -q '_KW = "|".join(sorted(keyword.kwlist' "$RO_Q/scripts/ovn_udiff_anchor.py" && grep -q '\*) if \[ "\$retried" = 0 \]; then echo reset-retry; else echo refuse; fi ;;' "$RO_Q/scripts/lib_fixup.sh" && grep -q 'ovn_reset_dirty_lockfiles "\$PWD" "\$task_log" "after verify"' "$RO_Q/run_overnight.sh" && echo 1 || echo 0)"
ro_summary
