#!/usr/bin/env bash
# Runs the REAL branch_hygiene.sh against throwaway bare origins + clones with an OVERNIGHT_PROGRESS.md conflict between develop (merge target) and
# overnight/feature (package conflict, 2026-10-12): the real conflict shape (distilled fixtures from iptv_apps fb07d121d1 / c2204cc7d9 / c7be7d3c)
# must be auto-resolved UNDER THE GATE (resolve -> gate on the merged tree -> commit), any other conflicted file / red gate / kill switch must
# abort exactly as before, and 2 consecutive conflicting passes must write exactly ONE alerts.log warn per streak.
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
export OVN_QA_SHADOW=off
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
BH="$HERE/../../branch_hygiene.sh"; [ -f "$BH" ] || BH="$HERE/../branch_hygiene.sh"
FIX="$HERE/fixtures/progress_merge"
[ -f "$BH" ] || { echo "  SKIP: branch_hygiene.sh not found"; exit 0; }
for t in flock timeout jq git python3; do command -v $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir)" || exit 1; export T; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
safe_set_sandbox_home "$T" || exit 1; export STATE_DIR="$T/state"; export REPORT_FILE="$T/report.md"; OUT="$T/out.log"
unset OVN_PROGRESS_MERGE OVN_PM_DEFER OVN_HYG_MERGE_STREAK_WARN OVN_HYG_STREAK_ALERT
BIN="$T/bin"; mkdir -p "$BIN"
mkstub(){ printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
mkstub curl 'echo "curl $*" >> "$T/curl.log"; exit 0'
# an exported FUNCTION beats any PATH lookup (reconcile_branches.sh resets PATH to /usr/bin first): no test may ever reach the real ntfy.sh
curl(){ echo "curl $*" >> "$T/curl.log"; return 0; }; export -f curl
# the Homebrew flock on a dev Mac rejects `flock -w 0` ("timeout must be greater than 0"; util-linux on the box accepts it): translate it to -n so the REAL lock code runs here too
REALFLOCK="$(type -P flock)"; export REALFLOCK
mkstub flock 'a=(); while [ $# -gt 0 ]; do if [ "$1" = -w ] && [ "${2:-}" = 0 ]; then a+=(-n); shift 2; else a+=("$1"); shift; fi; done; exec "$REALFLOCK" "${a[@]}"'
# pytest stub: logs each call + cwd; red when the progress file in the cwd carries BOTH RED_A and RED_B (a merged-tree-only failure), or red.flag exists
PYTEST_BODY='echo "pytest cwd=$PWD" >> "$T/pytest.log"
[ -f red.flag ] && exit 1
if [ -f OVERNIGHT_PROGRESS.md ] && grep -q RED_A OVERNIGHT_PROGRESS.md && grep -q RED_B OVERNIGHT_PROGRESS.md; then echo "1 failed"; exit 1; fi
echo ". passed"; exit 0'

setup(){
  rm -rf "${T:?}/home" "${T:?}/origin" "${T:?}/seed" "${T:?}/repos" "${T:?}/state" "${T:?}/report.md" "${T:?}"/*.log
  mkdir -p "$HOME/overnight-queue/scripts" "$T/origin" "$T/seed" "$T/repos" "$STATE_DIR"
  unset HYGIENE_MERGE_TARGET HYGIENE_FEATURE_BRANCH AUTO_MERGE_DEFAULT DRY_RUN OVN_PROGRESS_MERGE OVN_HYG_MERGE_STREAK_WARN OVN_HYG_STREAK_ALERT
  export OVN_XDIST_REPOS=none
}
# mk <name>: python-kind repo; main has the BASE progress file; develop == main; overnight/feature == main + 1 commit
mk(){
  local n="$1" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; mkdir -p pkg; echo "def t(): pass" > pkg/test_x.py; echo base > f.txt; cp "$FIX/real_base.md" OVERNIGHT_PROGRESS.md
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main; git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature; echo feat1 > feat1.txt; git add -A; git commit -q -m "feat: 1"; git push -q origin overnight/feature
    git checkout -q develop )
  git clone -q "$o" "$T/repos/$n" 2>/dev/null
  git -C "$T/repos/$n" config user.email t@t; git -C "$T/repos/$n" config user.name t
  mkdir -p "$T/repos/$n/.venv/bin"; printf '#!/usr/bin/env bash\n%s\n' "$PYTEST_BODY" > "$T/repos/$n/.venv/bin/pytest"; chmod +x "$T/repos/$n/.venv/bin/pytest"
}
# commit on a branch of the seed clone: pc <name> <branch> <msg> then it runs the body from stdin-less args: pc name branch "msg" file=content-source ...
pc(){ local n="$1" br="$2" msg="$3"; shift 3; ( cd "$T/seed/$n"; git fetch -q origin; git checkout -q -B "$br" "origin/$br"
    for kv in "$@"; do local f="${kv%%=*}" src="${kv#*=}"; case "$src" in @*) cp "${src#@}" "$f";; *) printf '%s\n' "$src" > "$f";; esac; done
    git add -A; git commit -q -m "$msg"; git push -q origin "$br" ); }
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
run(){ ( cd "$T" && PATH="$BIN:$PATH" bash "$BH" "$@" > "$OUT" 2>&1 ); echo $? > "$T/rc"; }
flag(){ echo "$STATE_DIR/branch_hygiene_review_$1"; }
show(){ git -C "$T/origin/$1.git" show "$2:$3" 2>/dev/null; }
parents(){ git -C "$T/origin/$1.git" rev-list --parents -n1 "$2" | wc -w | tr -d ' '; }
warns(){ local n; n="$(grep -c 'hygiene-merge-conflict-streak:' "$STATE_DIR/alerts.log" 2>/dev/null)"; echo "${n:-0}"; }

# ===== H1: the real conflict shape, gate green -> auto-resolved, gated on the merged tree, merged =====
setup; mk app
pc app develop "claude: tick items" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"
pc app overnight/feature "fleet: new items" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"
d0="$(sha app develop)"; : > "$T/pytest.log"; run "$T/repos/app"
ok "H1: rc 0" "$([ "$(cat "$T/rc")" = 0 ] && echo 1 || echo 0)"
ok "H1: develop advanced with a real merge commit (2 parents)" "$([ "$(sha app develop)" != "$d0" ] && [ "$(parents app develop)" = 3 ] && echo 1 || echo 0)"
ok "H1: merged OVERNIGHT_PROGRESS.md == the hand resolution (c7be7d3c)" "$(show app develop OVERNIGHT_PROGRESS.md | cmp -s - "$FIX/real_hand.md" && echo 1 || echo 0)"
ok "H1: the fleet's other file landed too" "$([ "$(show app develop feat1.txt)" = feat1 ] && echo 1 || echo 0)"
ok "H1: log says PROGRESS-MERGE auto-resolved and no MERGE CONFLICT" "$([ "$(has $OUT 'PROGRESS-MERGE: resolved: OVERNIGHT_PROGRESS.md')" = 1 ] && [ "$(has $OUT 'MERGE CONFLICT')" = 0 ] && echo 1 || echo 0)"
ok "H1: the gate ran on the MERGED tree (pytest ran in the main worktree, not only the feature one)" "$([ "$(has $T/pytest.log 'cwd=/tmp/hygiene-main-app.')" = 1 ] && [ "$(has $T/pytest.log 'cwd=/tmp/hygiene-app.')" = 1 ] && echo 1 || echo 0)"
ok "H1: report line says merged" "$(has $REPORT_FILE 'merged +')"
ok "H1: no review flag left" "$([ ! -f "$(flag app)" ] && echo 1 || echo 0)"
ok "H1: every resolution is logged to state/progress_merge.log" "$([ "$(has $STATE_DIR/progress_merge.log 'mode=resolve-index')" = 1 ] && [ "$(has $STATE_DIR/progress_merge.log 'merge committed after gate green')" = 1 ] && echo 1 || echo 0)"
ok "H1: clone wired per clone (info/attributes + local driver config)" "$([ "$(has $T/repos/app/.git/info/attributes 'OVERNIGHT_PROGRESS.md merge=ovn-progress')" = 1 ] && git -C "$T/repos/app" config --local --get merge.ovn-progress.driver | grep -q ovn_progress_merge && echo 1 || echo 0)"
ok "H1: no conflict streak recorded" "$([ ! -e "$STATE_DIR/hygiene_merge_streak/app__overnight_feature" ] && echo 1 || echo 0)"
ok "H1: worktrees cleaned up" "$([ "$(git -C $T/repos/app worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"

# ===== H2: a code file conflicts too -> abort exactly as before =====
setup; mk app
pc app develop "dev edits" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md" "f.txt=develop-side"
pc app overnight/feature "fleet edits" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md" "f.txt=feature-side"
d0="$(sha app develop)"; run "$T/repos/app"
ok "H2: develop untouched" "$([ "$(sha app develop)" = "$d0" ] && echo 1 || echo 0)"
ok "H2: MERGE CONFLICT flagged + reported as before" "$([ "$(has "$(flag app)" 'MERGE CONFLICT')" = 1 ] && [ "$(has $REPORT_FILE 'merge CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "H2: the log names both conflicted files and why auto-merge declined" "$([ "$(has $OUT 'conflicted: OVERNIGHT_PROGRESS.md f.txt')" = 1 ] || [ "$(has $OUT 'conflicted: f.txt OVERNIGHT_PROGRESS.md')" = 1 ] && [ "$(has $OUT 'progress auto-merge: declined')" = 1 ] && echo 1 || echo 0)"
ok "H2: the decline is logged to progress_merge.log" "$(has $STATE_DIR/progress_merge.log 'declined: f.txt is conflicted too')"
ok "H2: no worktree/merge state left behind" "$([ "$(git -C $T/repos/app worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"

# ===== H3: kill switch =====
setup; mk app
pc app develop "claude: tick items" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"
pc app overnight/feature "fleet: new items" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"
d0="$(sha app develop)"; export OVN_PROGRESS_MERGE=off; run "$T/repos/app"; unset OVN_PROGRESS_MERGE
ok "H3: OVN_PROGRESS_MERGE=off -> the progress conflict aborts as before (develop untouched)" "$([ "$(sha app develop)" = "$d0" ] && [ "$(has "$(flag app)" 'MERGE CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "H3: kill switch leaves the clone unwired" "$([ "$(has $T/repos/app/.git/info/attributes 'ovn-progress')" = 0 ] && echo 1 || echo 0)"

# ===== H4: resolved, but the gate on the MERGED tree is red -> nothing committed =====
setup; mk app
pc app develop "dev adds A" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"; ( cd "$T/seed/app"; echo "- [ ] [T1] src/red_a.py - RED_A item with enough words to be an item" >> OVERNIGHT_PROGRESS.md; git commit -qam "RED_A"; git push -q origin develop )
pc app overnight/feature "fleet adds B" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"; ( cd "$T/seed/app"; echo "- [ ] [T1] src/red_b.py - RED_B item with enough words to be an item" >> OVERNIGHT_PROGRESS.md; git commit -qam "RED_B"; git push -q origin overnight/feature )
d0="$(sha app develop)"; run "$T/repos/app"
ok "H4: the feature branch alone was green (it was gated) but the merged tree was red -> develop untouched" "$([ "$(sha app develop)" = "$d0" ] && [ "$(has $OUT 'gate on the merged tree FAILED')" = 1 ] && echo 1 || echo 0)"
ok "H4: treated as a conflict (flag + report), nothing committed" "$([ "$(has "$(flag app)" 'MERGE CONFLICT')" = 1 ] && [ "$(has $OUT 'resolved but the gate on the merged tree was not green')" = 1 ] && echo 1 || echo 0)"
ok "H4: the red-gate outcome is logged in progress_merge.log" "$(has $STATE_DIR/progress_merge.log 'gate on the auto-merged tree FAILED')"

# ===== H5: conflict streak alert: ONE warn on the 2nd consecutive conflicting pass =====
setup; mk app
pc app develop "dev edits" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md" "f.txt=develop-side"
pc app overnight/feature "fleet edits" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md" "f.txt=feature-side"
run "$T/repos/app"
ok "H5: pass 1 conflicted -> no streak alert yet" "$([ "$(warns)" = 0 ] && [ -f "$STATE_DIR/hygiene_merge_streak/app__overnight_feature" ] && echo 1 || echo 0)"
run "$T/repos/app"
ok "H5: pass 2 conflicted -> exactly one warn in alerts.log" "$([ "$(warns)" = 1 ] && echo 1 || echo 0)"
ok "H5: the warn names lane, count and the conflicted files" "$([ "$(has $STATE_DIR/alerts.log '] warn | hygiene-merge-conflict-streak:app |')" = 1 ] && [ "$(has $STATE_DIR/alerts.log 'CONFLICTED 2 consecutive passes for app')" = 1 ] && [ "$(has $STATE_DIR/alerts.log 'f.txt')" = 1 ] && echo 1 || echo 0)"
run "$T/repos/app"; run "$T/repos/app"
ok "H5: passes 3 and 4 do NOT alert again (one warn per streak)" "$([ "$(warns)" = 1 ] && echo 1 || echo 0)"
# resolve the code conflict on develop only (develop takes the feature's f.txt) -> next pass merges (progress auto-resolved) -> streak resets
pc app develop "dev takes feature f.txt" "f.txt=feature-side"
run "$T/repos/app"
ok "H5: a successful merge resets the streak (state file gone)" "$([ ! -e "$STATE_DIR/hygiene_merge_streak/app__overnight_feature" ] && [ "$(parents app develop)" = 3 ] && echo 1 || echo 0)"
# a NEW streak alerts again
pc app develop "dev conflicts again" "g.txt=dev-g"; pc app overnight/feature "fleet conflicts again" "g.txt=fleet-g"
run "$T/repos/app"; run "$T/repos/app"
ok "H5: a new streak alerts once more (2 warns total)" "$([ "$(warns)" = 2 ] && echo 1 || echo 0)"
# in-sync resets too
git -C "$T/origin/app.git" update-ref refs/heads/develop "$(sha app overnight/feature)"
run "$T/repos/app"
ok "H5: lane in sync -> streak file cleared" "$([ ! -e "$STATE_DIR/hygiene_merge_streak/app__overnight_feature" ] && echo 1 || echo 0)"

# ===== H6: streak alert kill switch / DRY_RUN / threshold =====
setup; mk app
pc app develop "dev edits" "f.txt=develop-side"; pc app overnight/feature "fleet edits" "f.txt=feature-side"
export OVN_HYG_STREAK_ALERT=off; run "$T/repos/app"; run "$T/repos/app"; run "$T/repos/app"; unset OVN_HYG_STREAK_ALERT
ok "H6: OVN_HYG_STREAK_ALERT=off -> no warn, no state" "$([ "$(warns)" = 0 ] && [ ! -d "$STATE_DIR/hygiene_merge_streak" ] && echo 1 || echo 0)"
export OVN_HYG_MERGE_STREAK_WARN=3; run "$T/repos/app"; run "$T/repos/app"
ok "H6: OVN_HYG_MERGE_STREAK_WARN=3: nothing after 2 passes" "$([ "$(warns)" = 0 ] && echo 1 || echo 0)"
run "$T/repos/app"
ok "H6: ... one warn on the 3rd" "$([ "$(warns)" = 1 ] && echo 1 || echo 0)"
unset OVN_HYG_MERGE_STREAK_WARN
# a pass that never reaches the merge (gate red) neither counts nor resets
setup; mk app
pc app develop "dev edits" "f.txt=develop-side"; pc app overnight/feature "fleet edits" "f.txt=feature-side"
run "$T/repos/app"; pc app overnight/feature "red" "red.flag=1"; run "$T/repos/app"
ok "H6: a gate-red pass between conflicts is neutral (still 1 on the streak, no warn)" "$([ "$(warns)" = 0 ] && [ "$(awk '{print $1}' "$STATE_DIR/hygiene_merge_streak/app__overnight_feature")" = 1 ] && echo 1 || echo 0)"
setup; mk app; pc app develop "d" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md" "f.txt=develop-side"; pc app overnight/feature "f" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md" "f.txt=feature-side"
DRY_RUN=1 run "$T/repos/app"
ok "H6: DRY_RUN=1 wires nothing and writes no streak" "$([ ! -d "$STATE_DIR/hygiene_merge_streak" ] && [ "$(has $T/repos/app/.git/info/attributes 'ovn-progress')" = 0 ] && echo 1 || echo 0)"

# ===== H7: unrelated flows unchanged: a plain clean merge still works and does not touch the streak =====
setup; mk app
pc app overnight/feature "more" "feat2.txt=2"
run "$T/repos/app"
ok "H7: clean merge still lands (no conflict path involved)" "$([ "$(has $OUT 'MERGED app overnight/feature')" = 1 ] && [ "$(has $OUT 'PROGRESS-MERGE')" = 0 ] && echo 1 || echo 0)"

# ===== H8 (r12): no ungated path - every merge / pull --rebase that runs in a driver-wired clone sets OVN_PM_DEFER=1 (static) =====
RB="$(dirname "$BH")/reconcile_branches.sh"
unmarked_bh="$(grep -nE 'git .* (merge --no-ff|pull (-q |--quiet )?--rebase)' "$BH" | grep -vE '^[0-9]+:\s*#' | grep -v 'OVN_PM_DEFER=1' | grep -v 'merge-base' || true)"
unmarked_rb="$(grep -nE 'git .* (merge --no-ff|pull (-q |--quiet )?--rebase)' "$RB" | grep -vE '^[0-9]+:\s*#' | grep -vE 'OVN_PM_DEFER=1|^[0-9]+:\s*[a-z_]+\(\)' | grep -v '\-\-message' || true)"
ok "H8: every git merge --no-ff / pull --rebase in branch_hygiene.sh sets OVN_PM_DEFER=1 (QA-clean-prefix re-merge + push-retry included)${unmarked_bh:+ -- unmarked: $unmarked_bh}" "$([ -z "$unmarked_bh" ] && echo 1 || echo 0)"
ok "H8: every one in reconcile_branches.sh sets it too (merge + the push-retry pulls)${unmarked_rb:+ -- unmarked: $unmarked_rb}" "$([ -z "$unmarked_rb" ] && echo 1 || echo 0)"
ok "H8: the script header documents the ungated hazard" "$(grep -q 'UNGATED RESOLUTIONS' "$(dirname "$BH")/scripts/ovn_progress_merge.py" && echo 1 || echo 0)"

echo "  test_progress_merge_hygiene.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
