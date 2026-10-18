#!/usr/bin/env bash
# Regression test (package reconcile-llm-resolve-gate, 2026-10-13): an EMPTY or UNKNOWN merge_into/sync_feature result must alert like a conflict.
# On 10-13 test-automation-agent's develop->overnight/feature sync produced 7 reconcile.log lines with an EMPTY outcome (the subshell behind rc=$(sync_feature) had died on an unbound
# variable); the `*) log "$name: develop->$feat $rc"` branch only logged them, so $conflicts stayed empty, no ntfy fired, and a 2-file conflict sat 14:04 -> 16:40 until a manual merge.
# The dying subshell is simulated with an exported git FUNCTION (it runs inside merge_into's own subshell; `exit 99` kills that subshell exactly like set -u did).
# bash 5 suite (run on the box / Homebrew bash); fixtures only, curl is a stub function.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ_SRC="$HERE/../.."; [ -f "$OQ_SRC/reconcile_branches.sh" ] || OQ_SRC="$HERE/.."
[ -f "$OQ_SRC/reconcile_branches.sh" ] || { echo "  SKIP: reconcile_branches.sh not found"; exit 0; }
for t in timeout git; do type -P $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
[ "${BASH_VERSINFO[0]:-0}" -ge 4 ] || { echo "  SKIP: needs bash >= 4"; exit 0; }
# shellcheck source=./ntfy_guard.sh
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir)" || exit 1; export T
cleanup(){ rm -rf "$T" /tmp/reconcile-*urc* 2>/dev/null; }
trap cleanup EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export NTFY_TOPIC="reconcile_urc_selftest_ignore"
unset OVN_PROGRESS_MERGE OVN_PM_DEFER OVN_MERGE_SANITY DRY_RUN
safe_set_sandbox_home "$T" || exit 1; Q="$HOME/overnight-queue"
mkdir -p "$Q/scripts" "$Q/repos" "$Q/state" "$Q/logs"
cp "$OQ_SRC/reconcile_branches.sh" "$Q/"; [ -f "$OQ_SRC/scripts/lib_tree_guard.sh" ] && cp "$OQ_SRC/scripts/lib_tree_guard.sh" "$Q/scripts/"
touch "$Q/state/PAUSED"   # the GPU-using LLM path stays out of this test; the die is injected at the plain merge
curl(){ printf '%s\n' "curl $*" >> "$T/curl.log"; return 0; }; export -f curl

mk(){   # <name> <kind>: kind=feat -> develop and overnight/feature each have a unique non-conflicting commit (real merge needed); kind=main -> main is ahead of develop (back-merge)
  local n="$1" k="$2" o="$T/origin/$1.git" s="$T/seed/$1"
  rm -rf "$o" "$s" "${Q:?}/repos/$n"; mkdir -p "$T/origin" "$T/seed"; git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; echo base > f.txt; git add -A; git commit -q -m base; git branch -M main; git push -q origin main
    git branch develop; git push -q origin develop
    if [ "$k" = feat ]; then
      git branch overnight/feature; git push -q origin overnight/feature
      git checkout -q develop; echo dev > dev.txt; git add -A; git commit -q -m "dev work"; git push -q origin develop
      git checkout -q overnight/feature; echo feat > feat.txt; git add -A; git commit -q -m "feat work"; git push -q origin overnight/feature
    else
      git checkout -q main; echo hot > hot.txt; git add -A; git commit -q -m "fix: direct hotfix"; git push -q origin main
    fi )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
}
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
run(){ ( cd "$Q" && bash ./reconcile_branches.sh "$@" > "$T/out.log" 2>&1 ); echo $? > "$T/rc"; }
reset(){ : > "$T/curl.log"; }
leaks(){ ls -d /tmp/reconcile-*urc* 2>/dev/null | wc -l | tr -d ' '; }
OUT="$T/out.log"

# ===== A: develop -> overnight/feature, merge_into's subshell dies -> EMPTY result =====
reset; mk urcfeat feat; f0="$(sha urcfeat overnight/feature)"
git(){ case "$*" in *"merge --no-ff"*) exit 99;; esac; command git "$@"; }; export -f git
run repos/urcfeat
unset -f git
ok "A1: the blank outcome is logged as rc=<empty> (was: 'develop->overnight/feature ' with nothing after it)" "$([ "$(has $OUT 'develop->overnight/feature rc=<empty>')" = 1 ] && echo 1 || echo 0)"
ok "A2: the log line explains the died-before-reporting condition" "$([ "$(has $OUT 'unknown/empty result')" = 1 ] && echo 1 || echo 0)"
ok "A3: it is added to \$conflicts: the high-priority CONFLICT ntfy fired" "$([ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "A4: the alert body names the lane, the empty rc and the repo" "$([ "$(has $T/curl.log 'develop→overnight/feature(rc=<empty>):urcfeat')" = 1 ] && echo 1 || echo 0)"
ok "A5: the closing summary line carries the conflict" "$([ "$(has $OUT 'reconcile complete')" = 1 ] && [ "$(has $OUT '🔴 conflicts:')" = 1 ] && echo 1 || echo 0)"
ok "A6: nothing was pushed" "$([ "$(sha urcfeat overnight/feature)" = "$f0" ] && echo 1 || echo 0)"
ok "A7: the dying subshell still cleaned its worktree (EXIT trap)" "$([ "$(leaks)" = 0 ] && echo 1 || echo 0)"

# ===== B: main -> develop back-merge, same death =====
reset; mk urcmain main; d0="$(sha urcmain develop)"
git(){ case "$*" in *"merge --no-ff"*) exit 99;; esac; command git "$@"; }; export -f git
run repos/urcmain
unset -f git
ok "B1: main->develop empty result logged as rc=<empty>" "$([ "$(has $OUT 'main->develop rc=<empty>')" = 1 ] && echo 1 || echo 0)"
ok "B2: ...and alerts as a conflict naming main→develop" "$([ "$(has $T/curl.log 'main→develop(rc=<empty>):urcmain')" = 1 ] && [ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "B3: develop untouched, no leaked worktree" "$([ "$(sha urcmain develop)" = "$d0" ] && [ "$(leaks)" = 0 ] && echo 1 || echo 0)"

# ===== C: the known results must NOT start alerting =====
reset; mk urcfeat feat; run repos/urcfeat
ok "C1: a normal merge develop->feature is logged as merged, no CONFLICT alert, no rc= line" "$([ "$(has $OUT 'merged develop->overnight/feature')" = 1 ] && [ "$(has $T/curl.log 'CONFLICT')" = 0 ] && [ "$(has $OUT 'rc=')" = 0 ] && echo 1 || echo 0)"
run repos/urcfeat
ok "C2: the next pass is in sync, still no alert" "$([ "$(has $OUT 'in sync')" = 1 ] && [ "$(has $T/curl.log 'CONFLICT')" = 0 ] && echo 1 || echo 0)"
reset; mk urcmain main; run repos/urcmain
ok "C3: a normal main->develop back-merge: logged, only the info (direct-to-main) alert, no CONFLICT" "$([ "$(has $OUT 'back-merged main->develop')" = 1 ] && [ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 0 ] && echo 1 || echo 0)"
# wterror stays a plain log line (a known, documented result - not 'unknown')
reset; mk urcfeat feat
git(){ case "$*" in *"worktree add"*) return 1;; esac; command git "$@"; }; export -f git
run repos/urcfeat; unset -f git
ok "C4: wterror (known result) is still just logged, not re-labelled unknown" "$([ "$(has $OUT 'develop->overnight/feature wterror')" = 1 ] && [ "$(has $OUT 'rc=')" = 0 ] && [ "$(has $T/curl.log 'CONFLICT')" = 0 ] && echo 1 || echo 0)"
ok "C4b: ...and the failed worktree add leaks NO /tmp/reconcile-*urc* mktemp dir (an inode per failed pass while /tmp was full)" "$([ "$(leaks)" = 0 ] && echo 1 || echo 0)"

echo "$P passed, $F failed"
[ "$F" -eq 0 ] && echo "  test_reconcile_unknown_rc_alerts: PASS" || echo "  test_reconcile_unknown_rc_alerts: FAIL"
[ "$F" -eq 0 ]
