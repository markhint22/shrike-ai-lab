#!/usr/bin/env bash
# Regression test: ovn_queue_health_sweep.sh (2026-09-11) — established after billwatch,
# iptv_apps, gitlark, test-automation-agent, and xlite each independently ended up with most
# or all active items parked at once, and the standard ovn_recover_parked.sh cadence (1 item
# per repo per 2h cron) was far too slow to dig a repo back out (xlite alone had 28 parked
# items - clearing them one per 2h would take days).
#
# Runs the REAL script (not a reimplementation), with the real ovn_recover_parked.sh stubbed
# out (it makes live LLM calls) and $HOME sandboxed to a temp dir, matching the existing
# $HOME-relative sandboxing convention used elsewhere in this suite (e.g. provision_test_envs).
set -uo pipefail
SCRIPT="${OVN_QUEUE_HEALTH_SWEEP:-$HOME/overnight-queue/ovn_queue_health_sweep.sh}"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
WD="$tmp/overnight-queue"
mkdir -p "$WD/repos" "$WD/logs" "$WD/scripts"
cp "$SCRIPT" "$WD/ovn_queue_health_sweep.sh"
cp "$(dirname "$SCRIPT")/queue_refill.py" "$WD/queue_refill.py"
# Phase 2 (2026-09-25): the script now sources scripts/lib_worktree.sh - stage it in the
# sandbox too, matching the real ~/overnight-queue layout.
cp "$(dirname "$SCRIPT")/scripts/lib_worktree.sh" "$WD/scripts/lib_worktree.sh"

TRACE="$tmp/trace.log"; : > "$TRACE"
cat > "$WD/ovn_recover_parked.sh" <<EOF
#!/usr/bin/env bash
echo "recover-called:\$1" >> "$TRACE"
EOF
chmod +x "$WD/ovn_recover_parked.sh"

new_repo(){  # $1=name $2=progress-content
  mkdir -p "$WD/repos/$1"
  printf '%s\n' "$2" > "$WD/repos/$1/OVERNIGHT_PROGRESS.md"
}

# --- A: a repo with doable items -> left alone entirely (no recovery calls) ---
new_repo healthy "## Next Steps
- [ ] [T1] some/file.py — a real doable item.
- [ ] [AUTO-SKIP after 4 cycles] [T2] other/file.py — a parked one too, but not the only option."

# --- B: doable=0 WITH parked items -> gets extra recovery passes ---
new_repo starved "## Next Steps
- [ ] [AUTO-SKIP after 4 cycles] [T1] a/file.py — parked item one.
- [ ] [AUTO-SKIP after 5 no-op cycles] [T2] b/file.py — parked item two."

# --- C: doable=0 with NOTHING parked either -> genuinely out of work, no recovery calls ---
new_repo empty "## Next Steps
(nothing here)"

HOME="$tmp" OVN_HEALTH_RECOVER_PASSES=3 bash "$WD/ovn_queue_health_sweep.sh" healthy starved empty >/dev/null 2>&1

ok "healthy repo gets zero recovery calls" "! grep -q 'recover-called:healthy' '$TRACE'"
ok "starved-with-parked repo gets exactly 3 recovery calls" "[ \$(grep -c 'recover-called:starved' '$TRACE') -eq 3 ]"
ok "genuinely-empty repo gets zero recovery calls (nothing to recover)" "! grep -q 'recover-called:empty' '$TRACE'"
ok "sweep log records the starved repo's decision" "grep -q 'starved: doable=0 with 2 parked' '$WD/logs/ovn_queue_health_sweep.log'"
ok "sweep log records the genuinely-empty repo's decision" "grep -q 'empty: doable=0 and nothing parked' '$WD/logs/ovn_queue_health_sweep.log'"

# git-backed repo (bare "origin" standing in for GitHub) so the actual commit+push path -
# the real fix, not just detection - gets exercised end to end.
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

# --- D: a real duplicate item is REMOVED (keeping the first occurrence) and the fix is
# actually committed + pushed, not just logged - report-only would let the fleet keep
# re-running the exact same duplicated work forever.
#
# Phase 2 (2026-09-25): the sweep now writes+commits+pushes from an ISOLATED WORKTREE, not
# the local clone at $WD/repos/<name> directly - that local clone is EXPECTED to stay
# untouched/stale after the sweep (the whole point of worktree isolation: nothing else reading
# that clone mid-sweep sees a half-written state). The real fix lands on the REMOTE
# (bare-dupey.git's overnight/feature), which is what these assertions check now, not the
# local clone. ---
new_git_repo dupey "## Next Steps
- [ ] [T1] a/file.py — do the exact same thing here. VERIFY: pytest -k foo
- [ ] [T2] a/file.py — do the exact same thing here. VERIFY: pytest -k foo
- [ ] [T3] b/file.py — a genuinely different item, must survive untouched."
before_remote="$(cd "$tmp/bare-dupey.git" && git rev-parse overnight/feature)"
HOME="$tmp" bash "$WD/ovn_queue_health_sweep.sh" dupey >/dev/null 2>&1
after_remote="$(cd "$tmp/bare-dupey.git" && git rev-parse overnight/feature)"
after_content="$(cd "$tmp/bare-dupey.git" && git show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "the duplicate is actually removed, only one copy of a/file.py remains" \
   "[ \$(echo \"\$after_content\" | grep -c 'a/file.py') -eq 1 ]"
ok "the genuinely different item is untouched" "echo \"\$after_content\" | grep -q 'b/file.py'"
ok "sweep log records the dedupe" "grep -q 'removed 1 duplicate' '$WD/logs/ovn_queue_health_sweep.log'"
ok "the fix was actually pushed to the remote (ref moved)" "[ '$before_remote' != '$after_remote' ]"
ok "the local clone is untouched by design (worktree-isolated write)" \
   "cat '$WD/repos/dupey/OVERNIGHT_PROGRESS.md' | grep -c 'a/file.py' | grep -q 2"

# --- E: an already-satisfied item (its own VERIFY already passes) is checked off and
# committed+pushed, not left active for the fleet to keep re-attempting.
#
# Phase 2 (2026-09-25): the sweep's worktree is opened from origin/overnight/feature (the
# REMOTE ref), so the seeded real files must actually be PUSHED for the isolated worktree to
# see them - a locally-committed-but-unpushed seed (the old assumption, when the sweep read
# the local clone directly) is invisible to it now. Same reasoning as scenario D: assertions
# check the remote content, not the local clone. ---
new_git_repo already "## Next Steps
- [ ] [T1] real/thing.py — needs actual work still. VERIFY: \`grep -q NEVER_TRUE_MARKER real/thing.py\`
- [ ] [T2] docs/readme.txt — already written. VERIFY: \`grep -q ALREADY_HERE docs/readme.txt\`"
mkdir -p "$WD/repos/already/docs" "$WD/repos/already/real"
echo "ALREADY_HERE - this file already has the content the item wanted" > "$WD/repos/already/docs/readme.txt"
echo "no marker here" > "$WD/repos/already/real/thing.py"
( cd "$WD/repos/already" && git add -A && git commit -q -m "seed real files" && git push -q origin overnight/feature )
HOME="$tmp" bash "$WD/ovn_queue_health_sweep.sh" already >/dev/null 2>&1
after_content2="$(cd "$tmp/bare-already.git" && git show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "the already-satisfied item is checked off" "echo \"\$after_content2\" | grep -q '\[x\].*docs/readme.txt.*pre-verified'"
ok "the still-needed item stays unchecked" "echo \"\$after_content2\" | grep -q '\[ \].*real/thing.py'"
ok "the credit was pushed to origin" \
   "cd '$tmp/bare-already.git' && git log --oneline overnight/feature | grep -q 'dedupe + credit'"

echo "queue_health_sweep: $P passed, $F failed"
[ "$F" -eq 0 ]
