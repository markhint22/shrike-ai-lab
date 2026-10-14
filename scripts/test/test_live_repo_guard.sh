#!/usr/bin/env bash
# 2026-10-14 (n5): a test subshell that lost its `cd` ran a bare `git add -A; git commit` in the LIVE ~/overnight-queue repo (logs/ 133 MB + state/ swept into
# 't <t@t>' commits, GitHub rejected every ovn_git_sync push for ~20 h).  Three layers, each proven by mutation here:
#   L1 the tests: every `( cd X && a; git add -A ...)` subshell is `( cd X || exit 1; ...)` (static lint: lib_subshell_cd_lint.py) and mkloop() aborts on a failed cd
#   L2 lib_live_repo_guard.sh: an exported `git` function refusing mutating subcommands in the repo that contains the suite (aborts the owner shell)
#   L3 ovn_git_sync.sh refuses to push when a tracked file is > 90 MB (see test_git_sync_size_guard.sh)
# The scenario runs the REAL mkloop() text from test_udiff_unanchored.sh + the REAL lib_ro_core.sh in a throwaway "live" repo, with repo creation failing
# (mkdir and `git clone` stubbed to fail) and asserts the throwaway live repo's HEAD never moves.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
G(){ command git -c user.name=t -c user.email=t@t "$@"; }
REALGIT="$(command -v git)"

echo "== L1 static lint (lib_subshell_cd_lint.py; this file is skipped: its fixtures contain the bad pattern as text) =="
ok "no scripts/test/*.sh has a '( cd X && first; git add/commit ...)' subshell (the cd only guards the first statement)" "$(python3 "$HERE/lib_subshell_cd_lint.py" $(ls "$HERE"/*.sh | grep -v '/test_live_repo_guard.sh$') >/dev/null 2>&1 && echo 1 || echo 0)"
printf '%s\n' '( cd "$R/x" && mkdir -p a' '  git add -A; git commit -q -m big )' > "$T/bad.sh"
ok "lint flags the exact historical pattern (multi-line subshell, second statement is a bare git add)" "$(python3 "$HERE/lib_subshell_cd_lint.py" "$T/bad.sh" >/dev/null 2>&1 && echo 0 || echo 1)"
printf '%s\n' '( cd "$R/x" && mkdir -p a; git commit -q -m big )' > "$T/bad2.sh"
ok "lint flags the single-line '; git commit' form" "$(python3 "$HERE/lib_subshell_cd_lint.py" "$T/bad2.sh" >/dev/null 2>&1 && echo 0 || echo 1)"
printf '%s\n' '( cd "$R/x" || exit 1; mkdir -p a; git add -A; git commit -q -m ok )' '( cd "$R/y" && git add -A && git commit -q -m chained )' 'git -C "$R/z" add -A; git -C "$R/z" commit -q -m c' > "$T/good.sh"
ok "lint passes '|| exit 1;', a pure && chain, and git -C" "$(python3 "$HERE/lib_subshell_cd_lint.py" "$T/good.sh" >/dev/null 2>&1 && echo 1 || echo 0)"

echo "== L2 guard + test fix, scenario: repo creation fails, victim runs in a throwaway live repo =="
mkdir -p "$T/failbin"
printf '#!/bin/bash\nexit 1\n' > "$T/failbin/mkdir"
printf '#!/bin/bash\nfor a in "$@"; do [ "$a" = clone ] && exit 1; done\nexec %s "$@"\n' "$REALGIT" > "$T/failbin/git"
chmod +x "$T/failbin/mkdir" "$T/failbin/git"

# mkvariant <name> <fix 1|0> <guard 1|0> : a throwaway live repo holding the real lib + the real test file (variant = mutations of exactly those two layers)
mkvariant(){
  local d="$T/$1/scripts/test"; mkdir -p "$d"
  cp "$HERE/lib_ro_core.sh" "$HERE/lib_live_repo_guard.sh" "$HERE/test_udiff_unanchored.sh" "$d/"
  python3 - "$d" "$2" "$3" <<'PY'
import sys, re
d, fix, guard = sys.argv[1], sys.argv[2], sys.argv[3]
if fix == "0":   # mutation L1: put the original unprotected subshell back (cd only guards the python3 statement)
    p = d + "/test_udiff_unanchored.sh"; s = open(p).read()
    new, n = re.subn(r'\( cd "\$R/\$1" \|\| \{[^}]*\}; python3', '( cd "$R/$1" && python3', s)
    assert n == 1, "mkloop fix not found"
    open(p, "w").write(new)
if guard == "0": # mutation L2: the guard removed
    open(d + "/lib_live_repo_guard.sh", "w").write("# guard removed (mutation)\n")
PY
  G -C "$T/$1" init -q . && G -C "$T/$1" add . && G -C "$T/$1" commit -q -m live-base
  echo "runtime junk (stands for logs/branch_hygiene.log)" > "$d/junk_runtime.log"   # untracked, in the cwd the victim starts from
}
# victim: source the real lib, extract the real mkloop() from the test file, call it with repo creation failing (cwd = the throwaway live repo's scripts/test)
cat > "$T/victim.sh" <<'V'
set -uo pipefail
cd "$1/scripts/test" || exit 2
. ./lib_ro_core.sh
ro_init
R="$T/repos"
eval "$(sed -n '/^mkloop(){/,/^}/p' ./test_udiff_unanchored.sh)"
mkloop r1 10
echo "victim-reached-end"
V
runvariant(){ # runvariant <name>: prints "<head-moved 0|1> <guard-line-seen 0|1> <victim-finished 0|1>"
  local n="$1" before after out
  before="$(command git -C "$T/$n" rev-parse HEAD)"
  out="$(cd "$T/$n/scripts/test" && PATH="$T/failbin:$PATH" OVN_LIVE_GUARD_LOG="$T/$n.guard.log" timeout 60 bash "$T/victim.sh" "$T/$n" </dev/null 2>&1)"
  after="$(command git -C "$T/$n" rev-parse HEAD)"
  echo "$([ "$before" != "$after" ] && echo 1 || echo 0) $(printf '%s' "$out" | grep -q 'LIVE-REPO-GUARD\|FATAL mkloop' && echo 1 || echo 0) $(printf '%s' "$out" | grep -q victim-reached-end && echo 1 || echo 0)"
}
mkvariant full 1 1; r="$(runvariant full)"
ok "fixed test + guard: live repo HEAD unchanged when repo creation fails (got: moved/msg/finished = $r)" "$([ "${r%% *}" = 0 ] && echo 1 || echo 0)"
ok "fixed test + guard: the victim is aborted (never reaches the end) with a FATAL/GUARD line" "$([ "$r" = "0 1 0" ] && echo 1 || echo 0)"
mkvariant onlyguard 0 1; r="$(runvariant onlyguard)"
ok "MUTATION (test fix reverted, guard kept): the guard alone keeps live HEAD unchanged and aborts ($r)" "$([ "$r" = "0 1 0" ] && echo 1 || echo 0)"
mkvariant onlyfix 1 0; r="$(runvariant onlyfix)"
ok "MUTATION (guard removed, test fix kept): the test fix alone keeps live HEAD unchanged ($r)" "$([ "${r%% *}" = 0 ] && echo 1 || echo 0)"
mkvariant none 0 0; r="$(runvariant none)"
ok "MUTATION (both removed = the 2026-10-14 incident): the live repo HEAD MOVES (the scenario really reproduces the hazard; $r)" "$([ "${r%% *}" = 1 ] && echo 1 || echo 0)"
ok "... and the junk commit is the bare 'big file' commit" "$([ "$(command git -C "$T/none" log -1 --format=%s)" = "big file" ] && echo 1 || echo 0)"

echo "== L2 guard unit: it only blocks mutations IN the protected repo =="
mkdir -p "$T/u/live" "$T/u/scratch"; G -C "$T/u/live" init -q .; G -C "$T/u/live" commit -q --allow-empty -m base; G -C "$T/u/scratch" init -q .
cat > "$T/u/run.sh" <<'V'
. "$1/lib_live_repo_guard.sh"
cd "$2/live" || exit 2
git -C "$2/scratch" commit -q --allow-empty -m scratch-ok && echo scratch-commit-ok
git -C "$2/live" log -1 --format=%s >/dev/null && echo live-read-ok
git status >/dev/null 2>&1 && echo live-status-ok
git branch >/dev/null 2>&1 && echo live-branch-list-ok
git commit -q --allow-empty -m junk; echo "after-junk-commit rc=$?"
V
out="$(OVN_LIVE_GUARD_TOP="$T/u/live" OVN_LIVE_GUARD_LOG="$T/u/g.log" bash "$T/u/run.sh" "$HERE" "$T/u" 2>&1)"
ok "a scratch repo can still be committed to" "$(printf '%s' "$out" | grep -q scratch-commit-ok && echo 1 || echo 0)"
ok "read-only git in the protected repo (log/status/branch list) still works" "$(printf '%s' "$out" | grep -q live-read-ok && printf '%s' "$out" | grep -q live-status-ok && printf '%s' "$out" | grep -q live-branch-list-ok && echo 1 || echo 0)"
ok "git commit in the protected repo is refused and aborts the owner shell" "$(printf '%s' "$out" | grep -q 'LIVE-REPO-GUARD: refused .git commit' && ! printf '%s' "$out" | grep -q after-junk-commit && echo 1 || echo 0)"
ok "the protected repo has no junk commit" "$([ "$(command git -C "$T/u/live" log -1 --format=%s)" = base ] && echo 1 || echo 0)"
ok "the refusal is logged to OVN_LIVE_GUARD_LOG" "$(grep -q 'refused .git commit' "$T/u/g.log" && echo 1 || echo 0)"

echo "== wiring =="
ok "run_all.sh sources the guard" "$(grep -q 'lib_live_repo_guard.sh' "$HERE/run_all.sh" && echo 1 || echo 0)"
ok "lib_ro_core.sh sources the guard (every ro_init test is covered when run alone)" "$(grep -q 'lib_live_repo_guard.sh' "$HERE/lib_ro_core.sh" && echo 1 || echo 0)"
echo; echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
