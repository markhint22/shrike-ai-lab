#!/usr/bin/env bash
# Extra branch coverage for scripts/lib_worktree.sh (sourced for real): wt_open failure modes + dependency symlinks,
# wt_push direct / rebase-retry / genuine-conflict (aborted, never left mid-rebase) / unreachable origin, wt_close idempotence.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB=""
for c in "$HERE/../lib_worktree.sh" "$HERE/lib_worktree.sh" "$HERE/../../scripts/lib_worktree.sh"; do [ -f "$c" ] && { LIB="$c"; break; }; done
[ -n "$LIB" ] || { echo "  SKIP: lib_worktree.sh not found"; exit 0; }
# shellcheck source=/dev/null
source "$LIB"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
git init -q --bare "$T/origin.git"
git clone -q "$T/origin.git" "$T/main" 2>/dev/null
( cd "$T/main" && git checkout -q -b claude/feature && echo one > a.txt && echo two > b.txt && git add -A && git commit -q -m init && git push -q origin claude/feature )
other(){ rm -rf "$T/other"; git clone -q -b claude/feature "$T/origin.git" "$T/other" 2>/dev/null; }
# unique repo basename so we can assert no leftover /tmp/wt-<name>.* dirs
REPO="$T/wtlibrepo_$$"; mv "$T/main" "$REPO"; RB="$(basename "$REPO")"

# ---- wt_open failure modes ----
mkdir -p "$T/plain"
out="$(wt_open "$T/plain" claude/feature)"; rc=$?
ok "wt_open on a non-git dir: rc 1, prints nothing" "$([ "$rc" = 1 ] && [ -z "$out" ] && echo 1 || echo 0)"
out="$(wt_open "$REPO" no/such-branch)"; rc=$?
ok "wt_open on a branch missing from origin: rc 1, prints nothing" "$([ "$rc" = 1 ] && [ -z "$out" ] && echo 1 || echo 0)"
ok "wt_open failure cleans up its mktemp dir" "$([ -z "$(ls -d /tmp/wt-"$RB".* 2>/dev/null)" ] && echo 1 || echo 0)"

# ---- wt_open success + dependency symlinks ----
mkdir -p "$REPO/.venv/bin" "$REPO/node_modules/pkg"
wt="$(wt_open "$REPO" claude/feature --link-venv --link-node-modules)"; rc=$?
ok "wt_open success returns the path, rc 0" "$([ "$rc" = 0 ] && [ -f "$wt/a.txt" ] && echo 1 || echo 0)"
ok "--link-venv symlinks repo/.venv" "$([ -L "$wt/.venv" ] && [ "$(readlink "$wt/.venv")" = "$REPO/.venv" ] && echo 1 || echo 0)"
ok "--link-node-modules symlinks repo/node_modules" "$([ -L "$wt/node_modules" ] && echo 1 || echo 0)"
wt_close "$REPO" "$wt"
ok "wt_close removes the worktree" "$([ ! -d "$wt" ] && echo 1 || echo 0)"
wt_close "$REPO" "$wt"; ok "wt_close twice / on a gone path is a harmless no-op" "$([ "$?" = 0 ] && echo 1 || echo 0)"
wt_close "$REPO" "$T/never-existed"; ok "wt_close on a never-existing path is a no-op" "$([ "$?" = 0 ] && echo 1 || echo 0)"
# flags given but the repo has neither dir; and flags absent even though dirs exist
rm -rf "$REPO/.venv" "$REPO/node_modules"
wt="$(wt_open "$REPO" claude/feature --link-venv --link-node-modules)"
ok "link flags with no .venv/node_modules in the repo: nothing linked, still opens" "$([ -d "$wt" ] && [ ! -e "$wt/.venv" ] && [ ! -e "$wt/node_modules" ] && echo 1 || echo 0)"
wt_close "$REPO" "$wt"
mkdir -p "$REPO/.venv" "$REPO/node_modules"
wt="$(wt_open "$REPO" claude/feature)"
ok "no link flags: no symlinks created even though dirs exist" "$([ ! -e "$wt/.venv" ] && [ ! -e "$wt/node_modules" ] && echo 1 || echo 0)"
wt_close "$REPO" "$wt"
# tracked .venv already present in the worktree -> not replaced by a symlink
( cd "$REPO" && mkdir -p .venv && echo tracked > .venv/marker && git add -f .venv/marker && git commit -q -m "track venv" && git push -q origin claude/feature )
wt="$(wt_open "$REPO" claude/feature --link-venv)"
ok "existing (tracked) .venv in the worktree is left alone" "$([ ! -L "$wt/.venv" ] && [ -f "$wt/.venv/marker" ] && echo 1 || echo 0)"
wt_close "$REPO" "$wt"

# ---- wt_push: direct ----
wt="$(wt_open "$REPO" claude/feature)"
( cd "$wt" && echo three > c.txt && git add c.txt && git commit -q -m c )
res="$(wt_push "$wt" claude/feature)"; rc=$?
ok "wt_push direct: echoes ok, rc 0" "$([ "$res" = ok ] && [ "$rc" = 0 ] && echo 1 || echo 0)"
ok "wt_push direct: origin has the commit" "$(git -C "$T/origin.git" show claude/feature:c.txt 2>/dev/null | grep -q three && echo 1 || echo 0)"
wt_close "$REPO" "$wt"

# ---- wt_push: non-fast-forward -> pull --rebase -> push ok ----
wt="$(wt_open "$REPO" claude/feature)"
other; ( cd "$T/other" && echo remote > r.txt && git add r.txt && git commit -q -m remote && git push -q origin claude/feature )
( cd "$wt" && echo local > l.txt && git add l.txt && git commit -q -m local )
res="$(wt_push "$wt" claude/feature)"; rc=$?
ok "wt_push non-ff: rebase retry succeeds (ok)" "$([ "$res" = ok ] && [ "$rc" = 0 ] && echo 1 || echo 0)"
ok "wt_push non-ff: origin has BOTH the remote and the local commit" "$(git -C "$T/origin.git" show claude/feature:r.txt >/dev/null 2>&1 && git -C "$T/origin.git" show claude/feature:l.txt >/dev/null 2>&1 && echo 1 || echo 0)"
wt_close "$REPO" "$wt"

# ---- wt_push: genuine conflict -> pushfail, rebase aborted ----
wt="$(wt_open "$REPO" claude/feature)"
other; ( cd "$T/other" && echo remote-version > a.txt && git commit -qam remote-a && git push -q origin claude/feature )
( cd "$wt" && echo local-version > a.txt && git commit -qam local-a )
res="$(wt_push "$wt" claude/feature)"; rc=$?
ok "wt_push conflict: echoes pushfail, rc 1" "$([ "$res" = pushfail ] && [ "$rc" = 1 ] && echo 1 || echo 0)"
ok "wt_push conflict: worktree not left mid-rebase" "$(git -C "$wt" status 2>&1 | grep -qi 'rebase in progress' && echo 0 || echo 1)"
ok "wt_push conflict: origin still has the remote version (nothing clobbered)" "$(git -C "$T/origin.git" show claude/feature:a.txt | grep -q remote-version && echo 1 || echo 0)"
wt_close "$REPO" "$wt"

# ---- wt_push: unreachable origin ----
wt="$(wt_open "$REPO" claude/feature)"
( cd "$wt" && echo z > z.txt && git add z.txt && git commit -q -m z && git remote set-url origin "$T/nonexistent.git" )
res="$(wt_push "$wt" claude/feature)"; rc=$?
ok "wt_push with an unreachable origin: pushfail, rc 1" "$([ "$res" = pushfail ] && [ "$rc" = 1 ] && echo 1 || echo 0)"
wt_close "$REPO" "$wt"

ok "no leaked /tmp/wt-$RB.* dirs at the end" "$([ -z "$(ls -d /tmp/wt-"$RB".* 2>/dev/null)" ] && echo 1 || echo 0)"
echo "lib_worktree_paths: $P passed, $F failed"
[ "$F" = 0 ]
