#!/usr/bin/env bash
# Runs the REAL reconcile_branches.sh (with the real branch_hygiene.sh run_gate + libs it loads, and the real ovn_progress_merge.py) against throwaway bare
# origins (package conflict, 2026-10-12). A develop -> overnight/feature merge that conflicts ONLY on OVERNIGHT_PROGRESS.md / OVERNIGHT_DONE.md is
# auto-merged deterministically, sanity-checked, gated on the merged tree and only then committed + pushed; any other conflicted file, a red gate, the
# kill switch, or the main -> develop direction behave exactly as before (abort + alert).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ="$HERE/../.."; [ -f "$OQ/reconcile_branches.sh" ] || OQ="$HERE/.."
FIX="$HERE/fixtures/progress_merge"
[ -f "$OQ/reconcile_branches.sh" ] && [ -f "$OQ/branch_hygiene.sh" ] && [ -f "$OQ/scripts/ovn_progress_merge.py" ] || { echo "  SKIP: scripts not found"; exit 0; }
for t in flock timeout jq git python3; do command -v $t >/dev/null || { echo "  SKIP: no $t"; exit 0; }; done
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
has(){ grep -qF -- "$2" "$1" 2>/dev/null && echo 1 || echo 0; }
T="$(safe_mktemp_dir)" || exit 1; export T; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
safe_set_sandbox_home "$T" || exit 1; Q="$HOME/overnight-queue"
unset OVN_PROGRESS_MERGE OVN_PM_DEFER OVN_MERGE_SANITY
BIN="$T/bin"; mkdir -p "$BIN"
mkstub(){ printf '#!/usr/bin/env bash\n%s\n' "$2" > "$BIN/$1"; chmod +x "$BIN/$1"; }
mkstub curl 'echo "curl $*" >> "$T/curl.log"; exit 0'
# an exported FUNCTION beats any PATH lookup (reconcile_branches.sh resets PATH to /usr/bin first): no test may ever reach the real ntfy.sh
curl(){ echo "curl $*" >> "$T/curl.log"; return 0; }; export -f curl
REALFLOCK="$(type -P flock)"; export REALFLOCK
mkstub flock 'a=(); while [ $# -gt 0 ]; do if [ "$1" = -w ] && [ "${2:-}" = 0 ]; then a+=(-n); shift 2; else a+=("$1"); shift; fi; done; exec "$REALFLOCK" "${a[@]}"'
PYTEST_BODY='echo "pytest cwd=$PWD" >> "$T/pytest.log"
[ -f red.flag ] && exit 1
if [ -f OVERNIGHT_PROGRESS.md ] && grep -q RED_A OVERNIGHT_PROGRESS.md && grep -q RED_B OVERNIGHT_PROGRESS.md; then echo "1 failed"; exit 1; fi
echo ". passed"; exit 0'

setup(){
  rm -rf "${T:?}/home" "${T:?}/origin" "${T:?}/seed" "${T:?}"/*.log
  mkdir -p "$Q/scripts" "$Q/repos" "$Q/state" "$Q/logs" "$T/origin" "$T/seed"
  cp "$OQ/reconcile_branches.sh" "$OQ/branch_hygiene.sh" "$Q/"
  for f in lib_lock.sh lib_pytest_parallel.sh lib_gut_xml.sh lib_tree_guard.sh ovn_progress_merge.py; do cp "$OQ/scripts/$f" "$Q/scripts/"; done
  touch "$Q/state/PAUSED"   # the LLM-assisted resolver (a separate, GPU-using path) must stay out of these tests
  unset OVN_PROGRESS_MERGE OVN_MERGE_SANITY DRY_RUN
  export NTFY_TOPIC="reconcile_progress_selftest_ignore"
}
mk(){   # <name>: main has the BASE progress file; develop == main; overnight/feature == main + 1 commit; clone at repos/<name> with a stub pytest
  local n="$1" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s"; mkdir -p pkg; echo "def t(): pass" > pkg/test_x.py; echo base > f.txt; cp "$FIX/real_base.md" OVERNIGHT_PROGRESS.md
    git add -A; git commit -q -m base; git branch -M main; git push -q origin main; git branch develop; git push -q origin develop
    git checkout -q -b overnight/feature; echo feat1 > feat1.txt; git add -A; git commit -q -m "feat: 1"; git push -q origin overnight/feature
    git checkout -q develop )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
  git -C "$Q/repos/$n" config user.email t@t; git -C "$Q/repos/$n" config user.name t
  mkdir -p "$Q/repos/$n/.venv/bin"; printf '#!/usr/bin/env bash\n%s\n' "$PYTEST_BODY" > "$Q/repos/$n/.venv/bin/pytest"; chmod +x "$Q/repos/$n/.venv/bin/pytest"
}
pc(){ local n="$1" br="$2" msg="$3"; shift 3; ( cd "$T/seed/$n"; git fetch -q origin; git checkout -q -B "$br" "origin/$br"
    for kv in "$@"; do local f="${kv%%=*}" src="${kv#*=}"; case "$src" in @*) cp "${src#@}" "$f";; *) printf '%s\n' "$src" > "$f";; esac; done
    git add -A; git commit -q -m "$msg"; git push -q origin "$br" ); }
sha(){ git -C "$T/origin/$1.git" rev-parse --verify -q "$2" 2>/dev/null; true; }
run(){ ( cd "$Q" && PATH="$BIN:$PATH" bash ./reconcile_branches.sh "$@" > "$T/out.log" 2>&1 ); echo $? > "$T/rc"; }
show(){ git -C "$T/origin/$1.git" show "$2:$3" 2>/dev/null; }
parents(){ git -C "$T/origin/$1.git" rev-list --parents -n1 "$2" | wc -w | tr -d ' '; }
OUT="$T/out.log"; PML="$Q/state/progress_merge.log"

# ===== R1: the real shape on develop -> overnight/feature: reconcile must NOT gate or land it (r12) - flag + log + leave it for hygiene =====
setup; mk app
pc app develop "claude: tick items" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"
pc app overnight/feature "fleet: new items" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"
f0="$(sha app overnight/feature)"; d0="$(sha app develop)"; : > "$T/pytest.log"; run repos/app
ok "R1: rc 0" "$([ "$(cat "$T/rc")" = 0 ] && echo 1 || echo 0)"
ok "R1: overnight/feature NOT touched by reconcile (landing is hygiene's gated job)" "$([ "$(sha app overnight/feature)" = "$f0" ] && echo 1 || echo 0)"
ok "R1: develop untouched" "$([ "$(sha app develop)" = "$d0" ] && echo 1 || echo 0)"
ok "R1: NO build/test gate was run in reconcile (the 300s fleet_autofix budget / run.lock hazard)" "$([ ! -s "$T/pytest.log" ] && echo 1 || echo 0)"
ok "R1: logged as DEFERRED to hygiene, not as a CONFLICT" "$([ "$(has $OUT 'deferred to the hourly hygiene pass')" = 1 ] && [ "$(has $OUT 'CONFLICT')" = 0 ] && echo 1 || echo 0)"
ok "R1: no conflict notification sent (hygiene's merge-streak alert covers persistence)" "$([ ! -s "$T/curl.log" ] || [ "$(has $T/curl.log 'CONFLICT')" = 0 ] && echo 1 || echo 0)"
[ -n "${DBG:-}" ] && { ls "$Q/state"; cat "$PML"; }
ok "R1: deferral logged in state/progress_merge.log + a per-lane flag file written" "$([ "$(has $PML 'DEFERRED to hygiene')" = 1 ] && ls "$Q"/state/reconcile_progress_deferred_app__overnight_feature >/dev/null 2>&1 && echo 1 || echo 0)"
ok "R1: the check was read-only (check-index, never resolve-index/committed lines)" "$([ "$(has $PML 'mode=check-index')" = 1 ] && [ "$(has $PML 'committed after gate green')" = 0 ] && [ "$(has $PML 'mode=resolve-index')" = 0 ] && echo 1 || echo 0)"
ok "R1: no stray /tmp/reconcile-app.* worktree left behind" "$([ -z "$(ls -d /tmp/reconcile-app.* 2>/dev/null)" ] && echo 1 || echo 0)"
ok "R1: the clone was wired per clone" "$([ "$(has $Q/repos/app/.git/info/attributes 'OVERNIGHT_PROGRESS.md merge=ovn-progress')" = 1 ] && echo 1 || echo 0)"
: > "$T/pytest.log"; run repos/app; run repos/app
ok "R1: repeated 20-min passes never run the gate either (no per-pass re-gating while the conflict persists)" "$([ ! -s "$T/pytest.log" ] && [ "$(sha app overnight/feature)" = "$f0" ] && echo 1 || echo 0)"

# ===== R2: a code file conflicts too -> unchanged behaviour (abort + alert) =====
setup; mk app
pc app develop "dev edits" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md" "f.txt=develop-side"
pc app overnight/feature "fleet edits" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md" "f.txt=feature-side"
f0="$(sha app overnight/feature)"; run repos/app
ok "R2: overnight/feature untouched" "$([ "$(sha app overnight/feature)" = "$f0" ] && echo 1 || echo 0)"
ok "R2: reported as a CONFLICT and the alert went out" "$([ "$(has $OUT 'CONFLICT develop->overnight/feature')" = 1 ] && [ "$(has $T/curl.log 'Branch reconcile CONFLICT')" = 1 ] && echo 1 || echo 0)"
ok "R2: the decline is logged" "$(has $PML 'declined: f.txt is conflicted too')"

# ===== R3: even a would-be-red merged tree is never gated here (hygiene owns that decision) =====
setup; mk app
pc app develop "dev adds A" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"; ( cd "$T/seed/app"; echo "- [ ] [T1] src/red_a.py - RED_A item with enough words to be an item" >> OVERNIGHT_PROGRESS.md; git commit -qam "RED_A"; git push -q origin develop )
pc app overnight/feature "fleet adds B" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"; ( cd "$T/seed/app"; echo "- [ ] [T1] src/red_b.py - RED_B item with enough words to be an item" >> OVERNIGHT_PROGRESS.md; git commit -qam "RED_B"; git push -q origin overnight/feature )
f0="$(sha app overnight/feature)"; : > "$T/pytest.log"; run repos/app
ok "R3: nothing pushed, no gate run, deferred" "$([ "$(sha app overnight/feature)" = "$f0" ] && [ ! -s "$T/pytest.log" ] && [ "$(has $OUT 'deferred to the hourly hygiene pass')" = 1 ] && echo 1 || echo 0)"

# ===== R4: kill switch =====
setup; mk app
pc app develop "claude: tick items" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"
pc app overnight/feature "fleet: new items" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"
f0="$(sha app overnight/feature)"; OVN_PROGRESS_MERGE=off run repos/app
ok "R4: OVN_PROGRESS_MERGE=off -> conflict as before, nothing pushed" "$([ "$(sha app overnight/feature)" = "$f0" ] && [ "$(has $OUT 'CONFLICT develop->overnight/feature')" = 1 ] && echo 1 || echo 0)"
ok "R4: kill switch leaves the clone unwired" "$([ "$(has $Q/repos/app/.git/info/attributes 'ovn-progress')" = 0 ] && echo 1 || echo 0)"

# ===== R5: main -> develop is production-adjacent: never auto-resolved =====
setup; mk app
pc app develop "dev ticks" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"
pc app main "direct to main" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"
d0="$(sha app develop)"; run repos/app
ok "R5: main->develop progress conflict still goes to a human (develop untouched, CONFLICT main->develop)" "$([ "$(sha app develop)" = "$d0" ] && [ "$(has $OUT 'CONFLICT main->develop')" = 1 ] && echo 1 || echo 0)"

# ===== R6: DRY_RUN wires nothing; plain flows unchanged =====
setup; mk app; pc app develop "more" "dev2.txt=2"
DRY_RUN=1 run repos/app
ok "R6: DRY_RUN=1 wires nothing and changes nothing" "$([ "$(has $Q/repos/app/.git/info/attributes 'ovn-progress')" = 0 ] && echo 1 || echo 0)"
run repos/app
ok "R6: plain non-conflicting develop->feature merge still works (no progress path)" "$([ "$(has $OUT 'merged develop->overnight/feature')" = 1 ] && [ "$(has $OUT 'progress-file')" = 0 ] && echo 1 || echo 0)"
# ===== R7 (review M1): the deferral flag keeps its first-seen epoch, escalates ONCE to the normal CONFLICT alert after OVN_PM_DEFER_ALERT_H (default 6h), and is
# deleted when the conflict is gone (hygiene landed it). Fake clock via OVN_PM_NOW. =====
setup; mk app
pc app develop "claude: tick items" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"
pc app overnight/feature "fleet: new items" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"
FLAG="$Q/state/reconcile_progress_deferred_app__overnight_feature"; f0="$(sha app overnight/feature)"
conf(){ local n; n="$(grep -c 'Branch reconcile CONFLICT' "$T/curl.log" 2>/dev/null)"; echo "${n:-0}"; }
OVN_PM_NOW=1000000 run repos/app
ok "R7: first pass creates the flag with the first-seen epoch" "$([ "$(head -n1 "$FLAG" 2>/dev/null)" = 1000000 ] && echo 1 || echo 0)"
OVN_PM_NOW=1003600 run repos/app
ok "R7: +1h: flag NOT overwritten (epoch kept), still silent" "$([ "$(head -n1 "$FLAG")" = 1000000 ] && [ "$(conf)" = 0 ] && [ "$(has $OUT 'CONFLICT')" = 0 ] && echo 1 || echo 0)"
OVN_PM_NOW=$((1000000+5*3600+3599)) run repos/app
ok "R7: just under 6h: still silent" "$([ "$(conf)" = 0 ] && [ "$(has $OUT 'CONFLICT')" = 0 ] && echo 1 || echo 0)"
OVN_PM_NOW=$((1000000+6*3600)) run repos/app
ok "R7: at 6h the deferral escalates to the normal reconcile CONFLICT alert" "$([ "$(conf)" = 1 ] && [ "$(has $OUT 'CONFLICT develop->overnight/feature')" = 1 ] && echo 1 || echo 0)"
ok "R7: the alert names the repo + lane" "$([ "$(has $T/curl.log 'develop→overnight/feature')" = 1 ] && [ "$(has $T/curl.log 'app')" = 1 ] && echo 1 || echo 0)"
ok "R7: still nothing pushed (reconcile never lands it)" "$([ "$(sha app overnight/feature)" = "$f0" ] && echo 1 || echo 0)"
OVN_PM_NOW=$((1000000+7*3600)) run repos/app; OVN_PM_NOW=$((1000000+30*3600)) run repos/app
ok "R7: one alert per flag - later passes stay quiet (dedupe)" "$([ "$(conf)" = 1 ] && [ "$(head -n1 "$FLAG")" = 1000000 ] && echo 1 || echo 0)"
# hygiene lands it (simulated: feature absorbs develop) -> the next pass deletes the flag
( cd "$T/seed/app"; git fetch -q origin; git checkout -q -B overnight/feature origin/overnight/feature; git merge -q -X ours --no-edit origin/develop >/dev/null 2>&1; git push -q origin overnight/feature )
OVN_PM_NOW=$((1000000+31*3600)) run repos/app
ok "R7: conflict gone -> flag deleted" "$([ ! -e "$FLAG" ] && echo 1 || echo 0)"
# a NEW later conflict starts a fresh clock and can alert again
pc app develop "claude: tick more" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md" "dev3.txt=3"
( cd "$T/seed/app"; git fetch -q origin; git checkout -q -B develop origin/develop; echo "- [ ] [T1] src/zz1.py - dev side new item with enough words to be an item" >> OVERNIGHT_PROGRESS.md; git commit -qam dz; git push -q origin develop )
( cd "$T/seed/app"; git checkout -q -B overnight/feature origin/overnight/feature; echo "- [ ] [T1] src/zz2.py - feature side new item with enough words to be an item" >> OVERNIGHT_PROGRESS.md; sed -i.bak 's/^## /## /' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak; git commit -qam fz; git push -q origin overnight/feature )
OVN_PM_NOW=$((1000000+40*3600)) run repos/app
ok "R7: a later progress-only conflict (if any) restarts the clock from its own first-seen time (no instant alert)" "$([ ! -e "$FLAG" ] || [ "$(head -n1 "$FLAG")" = $((1000000+40*3600)) ] && [ "$(conf)" = 1 ] && echo 1 || echo 0)"
# OVN_PM_DEFER_ALERT_H is honoured
setup; mk app
pc app develop "claude: tick items" "OVERNIGHT_PROGRESS.md=@$FIX/real_ours.md"
pc app overnight/feature "fleet: new items" "OVERNIGHT_PROGRESS.md=@$FIX/real_theirs.md"
OVN_PM_NOW=1000000 OVN_PM_DEFER_ALERT_H=1 run repos/app
OVN_PM_NOW=$((1000000+3600)) OVN_PM_DEFER_ALERT_H=1 run repos/app
ok "R7: OVN_PM_DEFER_ALERT_H=1 escalates after 1h" "$([ "$(conf)" = 1 ] && echo 1 || echo 0)"

echo "  test_progress_merge_reconcile.sh: $pass passed, $fail failed"
[ "$fail" = 0 ]
