#!/usr/bin/env bash
# reconcile_branches.sh POST-MERGE SANITY GATE (2026-09-30): a textually-clean `git merge` that SYNTHESIZES a broken
# python file (two branches edited non-overlapping lines of the same file) must NOT be pushed; a healthy merge must.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REC="$HERE/../../reconcile_branches.sh"; [ -f "$REC" ] || REC="$HERE/../reconcile_branches.sh"; [ -f "$REC" ] || REC="$HERE/reconcile_branches.sh"
[ -f "$REC" ] || { echo "  ❌ reconcile_branches.sh not found"; exit 1; }
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export NTFY_TOPIC="shrike_reconcile_selftest_ignore"
git init -q --bare "$tmp/origin.git"; git clone -q "$tmp/origin.git" "$tmp/seed" 2>/dev/null
( cd "$tmp/seed"; git config user.email t@t; git config user.name t
  printf 'def f():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n' > mod.py; echo ok > notes.txt
  git add -A; git commit -q -m base; git branch -M main; git push -q origin main
  git checkout -q -b develop; git push -q origin develop
  # main: turn the def line into a plain statement (leaves the body mis-indented)
  git checkout -q main; sed -i '1s/.*/x = 0/' mod.py; git commit -qam "main: edit line 1"; git push -q origin main
  # develop: edit line 5 only (non-overlapping hunk -> git merges cleanly)
  git checkout -q develop; sed -i '5s/4/5/' mod.py; git commit -qam "develop: edit line 5"; git push -q origin develop )
export HOME="$tmp/home"; mkdir -p "$HOME/overnight-queue/repos" "$HOME/overnight-queue/logs"
cp "$REC" "$HOME/overnight-queue/reconcile_branches.sh"
git clone -q "$tmp/origin.git" "$HOME/overnight-queue/repos/testrepo" 2>/dev/null
R="$HOME/overnight-queue/repos/testrepo"
git -C "$R" fetch -q origin; before="$(git -C "$R" rev-parse origin/develop)"
git -C "$R" show origin/develop:mod.py >/dev/null
# sanity: prove the premise - a plain merge IS textually clean and IS broken
( cd "$tmp/seed" && git checkout -q develop && git merge -q --no-edit main >/dev/null 2>&1 && ! python3 -m py_compile mod.py 2>/dev/null ) && ok "premise: git merges cleanly yet the result does not compile" || fail "premise broken (test setup)"
( cd "$tmp/seed" && git reset -q --hard origin/develop )
out=$(cd "$HOME/overnight-queue" && bash ./reconcile_branches.sh repos/testrepo 2>&1)
echo "$out" | grep -q "BROKEN file" && ok "reconcile reports the synthesized-broken merge" || fail "no sanity report: $out"
git -C "$R" fetch -q origin
[ "$(git -C "$R" rev-parse origin/develop)" = "$before" ] && ok "develop was NOT advanced (broken merge not pushed)" || fail "develop moved despite broken merge"
grep -q "mod.py: python does not compile" "$HOME/overnight-queue/logs/reconcile_sanity.log" 2>/dev/null && ok "reason logged to logs/reconcile_sanity.log" || fail "no sanity log"
# kill switch
out=$(cd "$HOME/overnight-queue" && OVN_MERGE_SANITY=off bash ./reconcile_branches.sh repos/testrepo 2>&1)
git -C "$R" fetch -q origin
[ "$(git -C "$R" rev-parse origin/develop)" != "$before" ] && ok "OVN_MERGE_SANITY=off restores the old push-anyway behavior (rollback path)" || fail "kill switch did not work: $out"
[ "$rc" = 0 ] && echo "  reconcile merge sanity: ALL PASS" || echo "  reconcile merge sanity: FAILURES"; exit $rc
