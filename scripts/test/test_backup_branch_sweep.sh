#!/usr/bin/env bash
# Regression test for ovn_backup_branch_sweep.sh — the backup-diverged-* branch safety net.
# Builds a throwaway bare origin, creates 3 backup-diverged-* branches (already-landed,
# unresolved-but-old, unresolved-but-fresh), and asserts: landed gets deleted, old-unresolved
# gets one alert with a real diff summary, fresh-unresolved is left alone (grace period), a
# repeat run doesn't re-alert (dedup), and forcing the seen-marker stale re-escalates.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SWEEP="$HERE/../ovn_backup_branch_sweep.sh"; [ -f "$SWEEP" ] || SWEEP="$HERE/ovn_backup_branch_sweep.sh"
[ -f "$SWEEP" ] || { echo "  ❌ ovn_backup_branch_sweep.sh not found"; exit 1; }
rc=0; ok(){ echo "  ✅ $1"; }; fail(){ echo "  ❌ $1"; rc=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

git init -q --bare "$tmp/origin.git"
git clone -q "$tmp/origin.git" "$tmp/seed" 2>/dev/null
( cd "$tmp/seed"; git config user.email t@t; git config user.name t
  echo base > f.txt; git add -A; git commit -q -m base
  git branch -M overnight/feature; git push -q origin overnight/feature
  git checkout -q -b develop; git push -q origin develop )

# fake overnight-queue root with a clone at repos/testrepo + this script under scripts/
root="$tmp/ovnq"; mkdir -p "$root/scripts" "$root/repos"
cp "$SWEEP" "$root/scripts/ovn_backup_branch_sweep.sh"
git clone -q "$tmp/origin.git" "$root/repos/testrepo" 2>/dev/null

( cd "$root/repos/testrepo"; git config user.email t@t; git config user.name t; git checkout -q overnight/feature
  # A: content that WILL be landed on origin/overnight/feature
  echo landed >> f.txt; git commit -q -am "a landed change"
  git branch backup-diverged-testA-20260901-100000
  git push -q origin overnight/feature
  # B: unresolved, old timestamp (outside grace window)
  git checkout -q -b tmpB overnight/feature
  echo unresolved-old >> f.txt; git commit -q -am "chore(queue): stale unresolved item"
  git branch -f backup-diverged-testB-20260901-100000 tmpB
  git checkout -q overnight/feature; git branch -D tmpB
  # C: unresolved, fresh timestamp (inside grace window)
  git checkout -q -b tmpC overnight/feature
  echo unresolved-fresh >> f.txt; git commit -q -am "chore(queue): fresh unresolved item"
  git branch -f "backup-diverged-testC-$(date +%Y%m%d-%H%M%S)" tmpC
  git checkout -q overnight/feature; git branch -D tmpC )

out=$(cd "$root" && bash scripts/ovn_backup_branch_sweep.sh state 2>&1)
echo "$out" | grep -q "cleaned up 1 already-landed" && ok "cleans up the landed branch" || fail "didn't report cleanup: $out"
echo "$out" | grep -q "flagged 1 unresolved" && ok "flags exactly the old unresolved branch" || fail "didn't report a flag: $out"

branches="$(git -C "$root/repos/testrepo" branch)"
echo "$branches" | grep -q "backup-diverged-testA" && fail "landed branch A still exists" || ok "landed branch A was deleted"
echo "$branches" | grep -q "backup-diverged-testB" && ok "old unresolved branch B survives (needs human/Claude review)" || fail "branch B was wrongly deleted"
echo "$branches" | grep -q "backup-diverged-testC" && ok "fresh unresolved branch C survives (grace period)" || fail "branch C was wrongly deleted"

grep -q "backup-diverged-testC" "$root/state/alerts.log" 2>/dev/null && fail "fresh branch C was wrongly alerted (grace period bypassed)" || ok "fresh branch C did NOT get alerted (grace period respected)"
grep -q "chore(queue): stale unresolved item" "$root/state/alerts.log" 2>/dev/null && ok "alert body includes the real commit subject" || fail "alert missing commit subject"
grep -q "f.txt" "$root/state/alerts.log" 2>/dev/null && ok "alert body includes the real diffstat" || fail "alert missing diffstat"

n1=$(wc -l < "$root/state/alerts.log")
bash "$root/scripts/ovn_backup_branch_sweep.sh" >/dev/null 2>&1
( cd "$root" && bash scripts/ovn_backup_branch_sweep.sh state >/dev/null 2>&1 )
n2=$(wc -l < "$root/state/alerts.log")
[ "$n1" -eq "$n2" ] && ok "repeat run does not re-alert within the dedup window" || fail "repeat run re-alerted ($n1 -> $n2 lines)"

echo 0 > "$root/state/backup_branch_seen/testrepo__backup-diverged-testB-20260901-100000"
( cd "$root" && bash scripts/ovn_backup_branch_sweep.sh state >/dev/null 2>&1 )
n3=$(wc -l < "$root/state/alerts.log")
[ "$n3" -gt "$n2" ] && ok "forcing the seen-marker stale re-escalates the still-unresolved branch" || fail "did not re-escalate after the marker went stale"

[ $rc -eq 0 ] && echo "  backup-branch sweep: ALL PASS" || echo "  backup-branch sweep: FAILURES"
exit $rc
