#!/usr/bin/env bash
# lib_tree_guard.sh + its two call sites (branch_hygiene.sh, reconcile_branches.sh): a branch that tracks an ABSOLUTE symlink
# (committed .venv/node_modules link) must be detected, and a merge that would bring it in must be refused. 2026-09-30 incident.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
L="$HERE/../lib_tree_guard.sh"; [ -f "$L" ] || L="$HERE/lib_tree_guard.sh"
R="$HERE/../../reconcile_branches.sh"; [ -f "$R" ] || R="$HERE/../reconcile_branches.sh"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
. "$L"
git init -q --bare "$T/origin.git"; git clone -q "$T/origin.git" "$T/seed" 2>/dev/null
( cd "$T/seed"; git config user.email t@t; git config user.name t
  echo a > a.txt; mkdir -p backend; echo x > backend/code.py; git add -A; git commit -q -m base; git branch -M main; git push -q origin main
  git checkout -q -b develop; git push -q origin develop
  git checkout -q -b feat; ln -s /home/someone/repo/backend/.venv backend/.venv; ln -s ../a.txt backend/rel_link; echo y >> backend/code.py
  git add -A; git commit -q -m "feat: adds an absolute symlink and a relative one"; git push -q origin feat )
git clone -q "$T/origin.git" "$T/c" 2>/dev/null; git -C "$T/c" fetch -q origin
out="$(ovn_abs_symlinks "$T/c" origin/develop origin/feat)"
ok "absolute symlink reported" "$([ "$out" = "backend/.venv" ] && echo 1 || echo 0)"
ok "relative symlink is NOT reported" "$(printf '%s' "$out" | grep -q rel_link && echo 0 || echo 1)"
ok "no findings when head == base" "$([ -z "$(ovn_abs_symlinks "$T/c" origin/develop origin/develop)" ] && echo 1 || echo 0)"
ok "a clean branch has no findings" "$([ -z "$(ovn_abs_symlinks "$T/c" origin/develop origin/main)" ] && echo 1 || echo 0)"
# reconcile: main is ahead of develop with the bad branch merged -> back-merge main->develop must be refused
( cd "$T/seed"; git checkout -q main; git merge -q --no-ff -m "promote feat" feat; git push -q origin main )
export NTFY_TOPIC="shrike_reconcile_selftest_ignore" HOME="$T/home"; mkdir -p "$HOME/overnight-queue/repos" "$HOME/overnight-queue/logs" "$HOME/overnight-queue/scripts"
cp "$R" "$HOME/overnight-queue/reconcile_branches.sh"; cp "$L" "$HOME/overnight-queue/scripts/"
git clone -q "$T/origin.git" "$HOME/overnight-queue/repos/testrepo" 2>/dev/null
before="$(git -C "$HOME/overnight-queue/repos/testrepo" rev-parse origin/develop)"
out="$(cd "$HOME/overnight-queue" && bash ./reconcile_branches.sh repos/testrepo 2>&1)"
git -C "$HOME/overnight-queue/repos/testrepo" fetch -q origin
ok "reconcile refuses to push a merge that brings in an absolute symlink" "$([ "$(git -C "$HOME/overnight-queue/repos/testrepo" rev-parse origin/develop)" = "$before" ] && echo 1 || echo 0)"
ok "reconcile reports it as a sanity failure" "$(printf '%s' "$out" | grep -q 'BROKEN file' && echo 1 || echo 0)"
grep -q "absolute symlink" "$HOME/overnight-queue/logs/reconcile_sanity.log" 2>/dev/null && ok "reason logged" 1 || ok "reason logged" 0
# ---- ovn_unstage_abs_symlinks: a scripted `git add -A` must not stage a live-env symlink ----
W="$T/wt"; git init -q "$W"; ( cd "$W" && git config user.email t@t && git config user.name t && echo k > keep.py && mkdir -p web && echo n > web/real.txt
  ln -s /home/someone/repo/web/node_modules node_modules; ln -s ../keep.py rel_link; git add -A )
ok "premise: git add -A stages the absolute symlink" "$(git -C "$W" diff --cached --name-only | grep -qx node_modules && echo 1 || echo 0)"
ovn_unstage_abs_symlinks "$W"
ok "absolute symlink is unstaged" "$(git -C "$W" diff --cached --name-only | grep -qx node_modules && echo 0 || echo 1)"
ok "the link itself stays on disk" "$([ -L "$W/node_modules" ] && echo 1 || echo 0)"
ok "relative symlink and normal files stay staged" "$(git -C "$W" diff --cached --name-only | grep -q rel_link && git -C "$W" diff --cached --name-only | grep -q keep.py && echo 1 || echo 0)"
ok "helper on a repo with nothing staged is a no-op that returns 0" "$( (cd "$T" && git init -q e && ovn_unstage_abs_symlinks "$T/e"; echo $?) | tail -1 | grep -qx 0 && echo 1 || echo 0)"
ok "stage runner and residue salvage call the helper after add -A" "$(grep -q 'ovn_unstage_abs_symlinks' "$HERE/../../ovn_stage_runner.sh" 2>/dev/null && grep -q 'ovn_unstage_abs_symlinks' "$HERE/../../run_overnight.sh" 2>/dev/null && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
