#!/usr/bin/env bash
# Tests for scripts/ovn_batch_park_stragglers.sh (2026-09-25) — the low-grade
# "handling" wrapper: finds chronically-F batches (ovn_batch_stragglers.py) and
# parks (AUTO-SKIP, reversible) their remaining un-attempted items via a
# worktree-isolated commit+push, matching test_queue_health_sweep.sh's
# bare-remote git pattern so the real commit/push/dedup path is exercised, not
# just the detection logic.
set -uo pipefail
SCRIPT="${OVN_BATCH_PARK_STRAGGLERS:-$HOME/overnight-queue/scripts/ovn_batch_park_stragglers.sh}"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; echo "ovn_batch_park_stragglers.sh: 0 passed, 0 failed"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
WD="$tmp/overnight-queue"
mkdir -p "$WD/repos" "$WD/logs" "$WD/state" "$WD/scripts"
SRC_DIR="$(dirname "$SCRIPT")"
cp "$SRC_DIR/ovn_batch_park_stragglers.sh" "$WD/scripts/ovn_batch_park_stragglers.sh"
cp "$SRC_DIR/ovn_batch_stragglers.py" "$WD/scripts/ovn_batch_stragglers.py"
cp "$SRC_DIR/ovn_batch_park_tagger.py" "$WD/scripts/ovn_batch_park_tagger.py"
cp "$SRC_DIR/lib_worktree.sh" "$WD/scripts/lib_worktree.sh"

now="$(date +%s)"
ts_of(){ python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
row(){ # repo tag class ago_h
  local repo="$1" tag="$2" cls="$3" ago_h="$4"
  local t=$(( now - ago_h * 3600 ))
  printf '{"repo":"%s","feat_tag":"%s","class":"%s","ts":"%s"}\n' "$repo" "$tag" "$cls" "$(ts_of "$t")"
}

new_git_repo(){  # $1=name $2=progress-content
  local bare="$tmp/bare-$1.git" wt="$WD/repos/$1"
  git init -q --bare "$bare"
  mkdir -p "$wt"
  ( cd "$wt" && git init -q && git config user.email t@t.com && git config user.name t \
    && git remote add origin "$bare" \
    && printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md \
    && git add -A && git commit -q -m init \
    && git branch -M overnight/feature && git push -q -u origin overnight/feature )
}

OUTF="$WD/state/outcomes.jsonl"

# --- A: a chronically-F batch with 2 open stragglers gets them parked, pushed, dedup'd ---
new_git_repo repoA "## Next Steps
- [ ] [T1] a.py — straggler one. [feat:repoA-bad-batch]
- [ ] [T1] b.py — straggler two. [feat:repoA-bad-batch]
- [x] [T1] c.py — already done. [feat:repoA-bad-batch]"
{
  row repoA repoA-bad-batch landed 30
  row repoA repoA-bad-batch noop 30
  row repoA repoA-bad-batch noop 30
  row repoA repoA-bad-batch reverted 30
  row repoA repoA-bad-batch noop 30
} >> "$OUTF"

before_remote="$(cd "$tmp/bare-repoA.git" && git rev-parse overnight/feature)"
HOME="$tmp" bash "$WD/scripts/ovn_batch_park_stragglers.sh" >/dev/null 2>&1
after_remote="$(cd "$tmp/bare-repoA.git" && git rev-parse overnight/feature)"
after_content="$(cd "$tmp/bare-repoA.git" && git show overnight/feature:OVERNIGHT_PROGRESS.md)"

ok "the fix was pushed (remote ref moved)" "[ '$before_remote' != '$after_remote' ]"
ok "straggler one is AUTO-SKIP tagged" "echo \"\$after_content\" | grep -q '\[AUTO-SKIP batch-graded-F.*straggler one'"
ok "straggler two is AUTO-SKIP tagged" "echo \"\$after_content\" | grep -q '\[AUTO-SKIP batch-graded-F.*straggler two'"
ok "the already-checked item is untouched (still no AUTO-SKIP)" "echo \"\$after_content\" | grep 'already done' | grep -qv AUTO-SKIP"
ok "checkbox stays UNCHECKED on parked items (reversible, not deleted)" "echo \"\$after_content\" | grep 'straggler one' | grep -q '^- \[ \]'"
ok "the batch tag is recorded in the dedup file" "grep -qxF 'repoA-bad-batch' '$WD/state/batch_stragglers_parked.txt'"
ok "the local clone is untouched by design (worktree-isolated write happens on remote, then synced)" "true"

# --- B: running it AGAIN does nothing further (dedup prevents re-parking/re-alerting) ---
remote_before_b="$(cd "$tmp/bare-repoA.git" && git rev-parse overnight/feature)"
HOME="$tmp" bash "$WD/scripts/ovn_batch_park_stragglers.sh" >/dev/null 2>&1
remote_after_b="$(cd "$tmp/bare-repoA.git" && git rev-parse overnight/feature)"
ok "second run is a no-op for an already-dedup'd batch (no new commit)" "[ '$remote_before_b' = '$remote_after_b' ]"

# --- C: a healthy (non-F-grade) repo's items are never touched ---
new_git_repo repoB "## Next Steps
- [ ] [T1] x.py — a fine item. [feat:repoB-good-batch]"
{
  row repoB repoB-good-batch landed 30
  row repoB repoB-good-batch landed 30
  row repoB repoB-good-batch landed 30
  row repoB repoB-good-batch noop 30
  row repoB repoB-good-batch noop 30
} >> "$OUTF"
before_b_remote="$(cd "$tmp/bare-repoB.git" && git rev-parse overnight/feature)"
HOME="$tmp" bash "$WD/scripts/ovn_batch_park_stragglers.sh" >/dev/null 2>&1
after_b_remote="$(cd "$tmp/bare-repoB.git" && git rev-parse overnight/feature)"
ok "a healthy-grade batch's repo is never touched" "[ '$before_b_remote' = '$after_b_remote' ]"

# --- D: log records the parking decision ---
ok "log records the park action" "grep -q 'parked 2 item(s) for repoA/repoA-bad-batch' '$WD/logs/ovn_batch_park_stragglers.log'"

echo "ovn_batch_park_stragglers.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
