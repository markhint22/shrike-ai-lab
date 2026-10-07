#!/usr/bin/env bash
# Tests for scripts/ovn_churn_guard.sh + ovn_churn_guard.py (fleet churn-loop guard, 2026-10-07).
# Real git: a bare origin per repo, a "fleet" working clone that pushes history to origin/overnight/feature, and a "live" clone (what the guard reads
# and must NEVER modify). Commit dates are relative to now so they fall inside the 3h window. No network. Every parking case has a benign control.
HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
G="$ROOT/scripts/ovn_churn_guard.sh"; PY="$ROOT/scripts/ovn_churn_guard.py"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T" /tmp/wt-churnguard-* 2>/dev/null' EXIT
PY2=1
export NTFY_SERVER="http://127.0.0.1:9/x" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=fleet GIT_AUTHOR_EMAIL=f@f GIT_COMMITTER_NAME=fleet GIT_COMMITTER_EMAIL=f@f
mkdir -p "$T/repos" "$T/state" "$T/logs"
NOW="$(date +%s)"

# ---- fixtures -------------------------------------------------------------------------------------------------------------------------------------
mkrepo(){ # name  (progress file content on stdin)  -> bare origin, fleet work clone, live clone
  local n="$1" b="$T/origin_$1.git" w="$T/work_$1"
  git init -q --bare "$b"; git -C "$b" symbolic-ref HEAD refs/heads/overnight/feature
  git clone -q "$b" "$w" 2>/dev/null; git -C "$w" checkout -q -b overnight/feature
  cat > "$w/OVERNIGHT_PROGRESS.md"
  mkdir -p "$w/scripts/battle" "$w/tests"
  printf 'v=0\n' > "$w/scripts/battle/x.gd"; printf 'v=0\n' > "$w/tests/test_x.gd"; printf 'v=0\n' > "$w/scripts/battle/y.gd"
  git -C "$w" add -A; GIT_COMMITTER_DATE="$((NOW-20000)) +0000" GIT_AUTHOR_DATE="$((NOW-20000)) +0000" git -C "$w" commit -q -m "chore: init"
  git -C "$w" push -q origin overnight/feature 2>/dev/null
  git clone -q "$b" "$T/repos/$n" 2>/dev/null; git -C "$T/repos/$n" checkout -q overnight/feature
}
cm(){ # repo mins_ago subject file=content...   (commit these files in the fleet clone, push)
  local w="$T/work_$1" m="$2" s="$3"; shift 3
  git -C "$w" pull -q --rebase origin overnight/feature 2>/dev/null   # the guard/race hook may have pushed since the last commit
  for kv in "$@"; do mkdir -p "$w/$(dirname "${kv%%=*}")"; printf '%b\n' "${kv#*=}" > "$w/${kv%%=*}"; done
  git -C "$w" add -A
  GIT_COMMITTER_DATE="$((NOW-m*60)) +0000" GIT_AUTHOR_DATE="$((NOW-m*60)) +0000" git -C "$w" commit -q -m "$s" 2>/dev/null
  git -C "$w" push -q origin overnight/feature 2>/dev/null
}
loop(){ # repo file n start_minutes_ago  : alternating content A/B with revert-style subjects (the live 2026-10-07 shape)
  local i m="$4"
  for i in $(seq 1 "$3"); do
    m=$((m-3))
    if [ $((i%2)) = 1 ]; then cm "$1" "$m" "fix: revert get_faction argument to int" "$2=v=1"; else cm "$1" "$m" "test: update default faction test to use string input" "$2=v=0"; fi
  done
}
# repo file n start : a legit staged feature = distinct forward-only steps on ONE file, one per commit
fwd(){ local i m="$4" body="v=0"; for i in $(seq 1 "$3"); do m=$((m-3)); body="$body\\ncap_$i = $((i*7))"; cm "$1" "$m" "feat(app): staged step 1.$i - add capability number $i to the module" "$2=$body"; done; }

PROGRESS_DEFAULT='# Progress
- [ ] [T5] scripts/battle/x.gd — Ensure get_faction handles the `_` default case. VERIFY: `grep -q default scripts/battle/x.gd`.
- [ ] [T2] scripts/battle/y.gd — Unrelated item about something else entirely.
- [ ] [CLAUDE] [T3] tests/test_x.gd — already escalated to Claude.
- [ ] [AUTO-SKIP parked earlier] [T3] scripts/battle/x.gd — already parked.
- [x] [T1] scripts/battle/x.gd — a finished item naming the file.'
run(){ # extra env...  -> runs the wrapper, log in $T/logs/churn_guard.log ; echoes rc
  : > "$T/logs/churn_guard.log"
  env OVN_DIR="$T" OVN_REPOS_DIR="$T/repos" OVN_STATE_DIR="$T/state" OVN_CHURN_LOG="$T/logs/churn_guard.log" OVN_CHURN_LOCK_WAIT=2 "$@" bash "$G" </dev/null >/dev/null 2>&1; echo $?
}
tip(){ git -C "$T/origin_$1.git" log -1 --format=%s overnight/feature; }
prog(){ git -C "$T/origin_$1.git" show overnight/feature:OVERNIGHT_PROGRESS.md; }
ncommits(){ git -C "$T/origin_$1.git" rev-list --count overnight/feature; }
alerts(){ grep -c "churn-guard:$1" "$T/state/alerts.log" 2>/dev/null || true; }
reset(){ : > "$T/state/alerts.log"; rm -f "$T/state/churn_guard_seen.txt"; }
live_sig(){ echo "$(git -C "$T/repos/$1" rev-parse HEAD) $(git -C "$T/repos/$1" symbolic-ref -q HEAD) $(git -C "$T/repos/$1" status --porcelain | wc -l | tr -d ' ')"; }

# ---- 1. the live loop: ping-pong on the TEST file, queue item names the SOURCE file ---------------------------------------------------------------
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo a
loop a tests/test_x.gd 12 170
cm a 5 "feat: unrelated landing" "scripts/battle/y.gd=v=9"
before_live="$(live_sig a)"; before_n="$(ncommits a)"
reset; rc="$(run OVN_CHURN_REPOS="a")"
ok "loop: exits 0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
ok "loop NEGATIVE: exactly the matching open item is parked (source named by the item, churn in the test file)" "$(prog a | grep -c 'AUTO-SKIP churn-loop: tests/test_x.gd touched by 12 fleet commits in 3h - needs Claude; recovery:none]' | grep -qx 1 && prog a | grep '^- \[ \] \[AUTO-SKIP churn-loop' | grep -q '\[T5\] scripts/battle/x.gd' && echo 1 || echo 0)"
ok "loop BENIGN: unrelated open item untouched" "$(prog a | grep -qF -- '- [ ] [T2] scripts/battle/y.gd — Unrelated item' && echo 1 || echo 0)"
ok "loop BENIGN: [CLAUDE]-tagged, already AUTO-SKIPped and checked lines untouched" "$(prog a | grep -qF -- '- [ ] [CLAUDE] [T3] tests/test_x.gd — already escalated' && prog a | grep -qF -- '- [ ] [AUTO-SKIP parked earlier] [T3] scripts/battle/x.gd' && prog a | grep -qF -- '- [x] [T1] scripts/battle/x.gd — a finished item' && echo 1 || echo 0)"
ok "loop: diff on origin is exactly one line changed in OVERNIGHT_PROGRESS.md" "$(git -C "$T/origin_a.git" diff --numstat overnight/feature~1 overnight/feature | tr '\t' ' ' | grep -qx '1 1 OVERNIGHT_PROGRESS.md' && echo 1 || echo 0)"
ok "loop: pushed as a chore(queue) commit with the fleet identity" "$(tip a | grep -q '^chore(queue): park 1 item(s) in a churn loop on tests/test_x.gd' && [ "$(git -C "$T/origin_a.git" log -1 --format=%an overnight/feature)" = shrike-fleet ] && echo 1 || echo 0)"
ok "loop: exactly one alerts.log line in the standard format" "$([ "$(alerts a)" = 1 ] && grep -qE '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8}\] warn \| churn-guard:a \| tests/test_x.gd had 12 fleet commits in 3h - parked 1 queue item\(s\)$' "$T/state/alerts.log" && echo 1 || echo 0)"
ok "loop: live fleet clone untouched (HEAD, branch, working tree)" "$([ "$(live_sig a)" = "$before_live" ] && echo 1 || echo 0)"
ok "loop: no temp worktree left in the live clone" "$([ "$(git -C "$T/repos/a" worktree list | wc -l | tr -d ' ')" = 1 ] && [ -z "$(ls -d /tmp/wt-churnguard-a.* 2>/dev/null)" ] && echo 1 || echo 0)"
ok "loop: tagged line is invisible to ovn_recover_parked.sh's own selector (it must not decompose + re-queue the loop)" "$([ -z "$(prog a | grep -nE '^- \[ \] \[(AUTO-SKIP|HUMAN-ONLY BLOCKED ITEM)' | grep -vE '\[(AUTO-SKIP|HUMAN-ONLY BLOCKED ITEM)[^]]*recovery:' | grep -viE 'route to claude' | grep -vE '\[CLAUDE\]' | grep 'churn-loop')" ] && echo 1 || echo 0)"
# ---- 2. dedupe + re-run -------------------------------------------------------------------------------------------------------------------------
n1="$(ncommits a)"; rc="$(run OVN_CHURN_REPOS="a")"
ok "dedupe: re-run adds no commit (nothing left to park) and no second alert" "$([ "$(ncommits a)" = "$n1" ] && [ "$(alerts a)" = 1 ] && echo 1 || echo 0)"
cm a 1 "feat: bridge adds another open item" "OVERNIGHT_PROGRESS.md=$(prog a)\\n- [ ] [T4] tests/test_x.gd — a NEW item naming the churning test file."
rc="$(run OVN_CHURN_REPOS="a")"
ok "dedupe: a NEW matching open item is parked on the next tick, but the alert stays deduped (one line per file per day)" "$(prog a | grep -q '^- \[ \] \[AUTO-SKIP churn-loop: tests/test_x.gd touched by 12 fleet commits in 3h - needs Claude; recovery:none\] \[T4\]' && [ "$(alerts a)" = 1 ] && echo 1 || echo 0)"
# ---- 3. DRY_RUN / kill switch ---------------------------------------------------------------------------------------------------------------------
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo d; loop d tests/test_x.gd 12 170; reset; n0="$(ncommits d)"
rc="$(run OVN_CHURN_REPOS="d" DRY_RUN=1)"
ok "DRY_RUN: exits 0, prints what it would park, changes nothing (no commit, no alert, no seen state)" "$([ "$rc" = 0 ] && grep -q 'DRY_RUN would park line: - \[ \] \[T5\] scripts/battle/x.gd' "$T/logs/churn_guard.log" && [ "$(ncommits d)" = "$n0" ] && [ "$(alerts d)" = 0 ] && [ ! -s "$T/state/churn_guard_seen.txt" ] && echo 1 || echo 0)"
rc="$(run OVN_CHURN_REPOS="d" OVN_CHURN_GUARD=off)"
ok "kill switch OVN_CHURN_GUARD=off: nothing changes, log says disabled" "$([ "$rc" = 0 ] && [ "$(ncommits d)" = "$n0" ] && [ "$(alerts d)" = 0 ] && grep -q 'disabled' "$T/logs/churn_guard.log" && echo 1 || echo 0)"
# ---- 4. legit staged feature + sub-threshold + bookkeeping (benign controls) ---------------------------------------------------------------------
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo s; fwd s scripts/battle/x.gd 10 170; reset; n0="$(ncommits s)"
rc="$(run OVN_CHURN_REPOS="s")"
ok "BENIGN: a legit staged feature (10 distinct forward steps on ONE file, n>=8) is NOT parked and raises no alert" "$([ "$rc" = 0 ] && [ "$(ncommits s)" = "$n0" ] && [ "$(alerts s)" = 0 ] && ! prog s | grep -q churn-loop && echo 1 || echo 0)"
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo u; loop u tests/test_x.gd 7 170; reset; n0="$(ncommits u)"
rc="$(run OVN_CHURN_REPOS="u")"
ok "BENIGN: an oscillating file with only 7 commits (< OVN_CHURN_MIN=8) is NOT parked" "$([ "$(ncommits u)" = "$n0" ] && [ "$(alerts u)" = 0 ] && echo 1 || echo 0)"
rc="$(run OVN_CHURN_REPOS="u" OVN_CHURN_MIN=6)"
ok "OVN_CHURN_MIN is tunable (6 => the same 7-commit oscillation IS parked)" "$(prog u | grep -q 'AUTO-SKIP churn-loop' && echo 1 || echo 0)"
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo k
for i in $(seq 1 14); do cm k $((170-i*3)) "chore(queue): automated bridge pass $i" "scripts/battle/x.gd=v=$((i%2))"; done
for i in $(seq 1 14); do cm k $((120-i*3)) "docs(queue): note $i" "scripts/battle/y.gd=v=$((i%2))"; done
reset; n0="$(ncommits k)"; rc="$(run OVN_CHURN_REPOS="k")"
ok "BENIGN: chore(/docs(queue commits are bookkeeping and never counted (28 oscillating chore/docs commits => no park)" "$([ "$(ncommits k)" = "$n0" ] && [ "$(alerts k)" = 0 ] && echo 1 || echo 0)"
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo o; loop o tests/test_x.gd 12 400   # loop is OLDER than the 3h window
reset; n0="$(ncommits o)"; rc="$(run OVN_CHURN_REPOS="o")"
ok "BENIGN: a loop entirely outside the 3h window is not parked" "$([ "$(ncommits o)" = "$n0" ] && [ "$(alerts o)" = 0 ] && echo 1 || echo 0)"
# ---- 5. no open item matches: still alert once, push nothing ---------------------------------------------------------------------------------------
printf '%s\n' '# Progress
- [ ] [T2] scripts/battle/y.gd — only an unrelated item is open.' | mkrepo m
loop m tests/test_x.gd 12 170; reset; n0="$(ncommits m)"; rc="$(run OVN_CHURN_REPOS="m")"
ok "no matching open item: nothing pushed, ONE alert that names the backlog/roadmap possibility" "$([ "$(ncommits m)" = "$n0" ] && [ "$(alerts m)" = 1 ] && grep -q 'parked 0 queue item(s) (no open queue item names it' "$T/state/alerts.log" && echo 1 || echo 0)"
# ---- 6. cap ------------------------------------------------------------------------------------------------------------------------------------
{ echo '# Progress'; for i in 1 2 3 4; do echo "- [ ] [T$i] tests/test_x.gd — item number $i names the churning file."; done; } | mkrepo c
loop c tests/test_x.gd 12 170; reset; rc="$(run OVN_CHURN_REPOS="c" OVN_CHURN_MAX_PARK=2)"
ok "cap: OVN_CHURN_MAX_PARK=2 parks exactly 2 of 4 matching lines" "$([ "$(prog c | grep -c 'AUTO-SKIP churn-loop')" = 2 ] && echo 1 || echo 0)"
rc="$(run OVN_CHURN_REPOS="c")"
ok "cap: default cap (10) parks the remaining 2 on the next tick" "$([ "$(prog c | grep -c 'AUTO-SKIP churn-loop')" = 4 ] && echo 1 || echo 0)"
# ---- 7. push race: a commit lands between our fetch and push -----------------------------------------------------------------------------------
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo r; loop r tests/test_x.gd 12 170; reset
cat > "$T/racehook.sh" <<EOS
#!/usr/bin/env bash
set -e
d="\$(mktemp -d)"; git clone -q "$T/origin_r.git" "\$d/c"; cd "\$d/c"; git checkout -q overnight/feature
printf -- '- [ ] [T9] scripts/battle/y.gd — landed by the fleet during the race.\n' >> OVERNIGHT_PROGRESS.md
git add -A; git commit -q -m "chore(queue): auto-refill 1 item (race)"; git push -q origin overnight/feature; rm -rf "\$d"
EOS
chmod +x "$T/racehook.sh"
rc="$(run OVN_CHURN_REPOS="r" OVN_CHURN_BEFORE_PUSH_HOOK="bash $T/racehook.sh")"
ok "push race: first push rejected, retry on the new tip succeeds; park AND the racing commit both on origin" "$([ "$rc" = 0 ] && grep -q 'push attempt 1/5 rejected' "$T/logs/churn_guard.log" && prog r | grep -q 'AUTO-SKIP churn-loop: tests/test_x.gd' && prog r | grep -q 'landed by the fleet during the race' && echo 1 || echo 0)"
ok "push race: history is linear (non-force push, nothing rewritten)" "$([ -z "$(git -C "$T/origin_r.git" log --merges --format=%h overnight/feature)" ] && [ "$(alerts r)" = 1 ] && echo 1 || echo 0)"
# ---- 8. infrastructure failures => exit 0, no change -------------------------------------------------------------------------------------------
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo i; loop i tests/test_x.gd 12 170; reset; n0="$(ncommits i)"
printf '#!/bin/sh\necho no >&2\nexit 1\n' > "$T/origin_i.git/hooks/pre-receive"; chmod +x "$T/origin_i.git/hooks/pre-receive"
rc="$(run OVN_CHURN_REPOS="i" OVN_CHURN_PUSH_TRIES=2)"
ok "INFRA push rejected persistently: exit 0, origin unchanged, one PUSHFAIL alert, no leaked worktree" "$([ "$rc" = 0 ] && [ "$(ncommits i)" = "$n0" ] && [ "$(alerts i)" = 1 ] && grep -q 'could not push' "$T/state/alerts.log" && [ "$(git -C "$T/repos/i" worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
rc="$(run OVN_CHURN_REPOS="i" OVN_CHURN_PUSH_TRIES=2)"
ok "INFRA push failure alert is deduped per day" "$([ "$(alerts i)" = 1 ] && echo 1 || echo 0)"
rm -f "$T/origin_i.git/hooks/pre-receive"
mkdir -p "$T/repos/bad"; git init -q "$T/repos/bad"; git -C "$T/repos/bad" remote add origin "$T/nonexistent.git"
reset; rc="$(run OVN_CHURN_REPOS="bad")"
ok "INFRA fetch failure: exit 0, log says infra, no alert" "$([ "$rc" = 0 ] && grep -q 'infra (fetch failed' "$T/logs/churn_guard.log" && [ "$(alerts bad)" = 0 ] && echo 1 || echo 0)"
reset; rc="$(run OVN_CHURN_REPOS="nosuchrepo")"
ok "INFRA missing clone: exit 0, skipped" "$([ "$rc" = 0 ] && grep -q 'infra (no clone' "$T/logs/churn_guard.log" && echo 1 || echo 0)"
reset; rc="$(run OVN_CHURN_REPOS="bad i")"
ok "INFRA in one repo does not stop the next repo (bad then i: i is parked once the hook is gone)" "$([ "$rc" = 0 ] && prog i | grep -q 'AUTO-SKIP churn-loop' && echo 1 || echo 0)"
# lock contention: another pass holds the lock => skip, exit 0, no change
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo l; loop l tests/test_x.gd 12 170; reset; n0="$(ncommits l)"
if command -v flock >/dev/null 2>&1; then
  ( exec 8>"$T/state/churn_guard.lock"; flock 8; sleep 6 ) & lp=$!; sleep 1
  rc="$(run OVN_CHURN_REPOS="l")"; wait "$lp" 2>/dev/null
  ok "lock held by another pass: waits briefly, skips, exit 0, no change" "$([ "$rc" = 0 ] && [ "$(ncommits l)" = "$n0" ] && grep -q 'already running' "$T/logs/churn_guard.log" && echo 1 || echo 0)"
else echo "  skip lock contention (no flock on this host)"; fi
# ---- 9. other repos untouched ---------------------------------------------------------------------------------------------------------------
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo p1; printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo p2
loop p1 tests/test_x.gd 12 170; fwd p2 scripts/battle/x.gd 10 170; reset; n2="$(ncommits p2)"
rc="$(run OVN_CHURN_REPOS="p1 p2")"
ok "two repos: only the churning repo is edited; the other (legit staged feature) gets no commit and no alert" "$(prog p1 | grep -q 'AUTO-SKIP churn-loop' && [ "$(ncommits p2)" = "$n2" ] && [ "$(alerts p2)" = 0 ] && [ "$(alerts p1)" = 1 ] && echo 1 || echo 0)"
# ---- 10. test<->source PAIR rule -------------------------------------------------------------------------------------------------------------
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo q
m=170; for i in 1 2 3 4 5 6; do m=$((m-3)); cm q $m "fix: revert x to int" "scripts/battle/x.gd=v=$((i%2))"; m=$((m-3)); cm q $m "test: update x test to string" "tests/test_x.gd=v=$((i%2))"; done
reset; rc="$(run OVN_CHURN_REPOS="q")"
ok "PAIR NEGATIVE: source+test each touched 6x in strict alternation with revisits/revert wording (each < MIN=8) => both flagged, matching item parked" "$([ "$(alerts q)" = 2 ] && prog q | grep '^- \[ \] \[AUTO-SKIP churn-loop' | grep -q 'scripts/battle/x.gd' && echo 1 || echo 0)"
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo q2
m=170; sb="v=0"; tb="v=0"; for i in 1 2 3 4 5 6 7; do m=$((m-3)); sb="$sb\\ns$i=1"; cm q2 $m "feat(app): add capability $i" "scripts/battle/x.gd=$sb"; m=$((m-3)); tb="$tb\\nt$i=1"; cm q2 $m "test: cover capability $i" "tests/test_x.gd=$tb"; done
reset; n0="$(ncommits q2)"; rc="$(run OVN_CHURN_REPOS="q2")"
ok "PAIR BENIGN: legit TDD alternation (test/source 7x each, distinct subjects, content only moves forward) => NOT parked" "$([ "$(ncommits q2)" = "$n0" ] && [ "$(alerts q2)" = 0 ] && echo 1 || echo 0)"
# ---- 11. replay mode is read-only --------------------------------------------------------------------------------------------------------------
n0="$(ncommits p1)"; out="$(env OVN_DIR="$T" OVN_REPOS_DIR="$T/repos" OVN_STATE_DIR="$T/state" OVN_CHURN_REPOS="p1" python3 "$PY" --replay 4 2>&1)"
ok "replay: lists the churning file and changes nothing" "$(echo "$out" | grep -q 'tests/test_x.gd' && [ "$(ncommits p1)" = "$n0" ] && echo 1 || echo 0)"
# ---- 13. review fixes: byte safety, match scope, protected lines, authorship, chore:, WATCH, PARK=off, sweep, SIGTERM -------------------------------
CRLF_PROGRESS="$(printf '# Progress\r\n- [ ] [T5] scripts/battle/x.gd — Ensure h\xc3\xa9llo w\xc3\xb6rld  \r\n- [ ] [T2] scripts/battle/y.gd — Unrelated   \r\n- [ ] [T6] scripts/battle/x.gd — dup line\r\n- [ ] [T6] scripts/battle/x.gd — dup line\r\n- [ ] [T7] scripts/battle/y.gd — long %s\r\nraw \xff\xfe bytes line\r\n' "$(head -c 6000 /dev/zero | tr '\0' 'q')")"
printf '%s' "$CRLF_PROGRESS" | mkrepo w; loop w tests/test_x.gd 12 170; reset
rc="$(run OVN_CHURN_REPOS="w")"
ok "BYTES: CRLF + trailing spaces + unicode + 6KB line + invalid utf-8: exactly the 3 matching lines change (1 + the 2 identical duplicates), numstat 3/3" "$(git -C "$T/origin_w.git" diff --numstat overnight/feature~1 overnight/feature | tr '\t' ' ' | grep -qx '3 3 OVERNIGHT_PROGRESS.md' && echo 1 || echo 0)"
ok "BYTES: every line still ends in CRLF, the invalid bytes and trailing spaces survive, unrelated lines byte-identical" "$(git -C "$T/origin_w.git" show overnight/feature:OVERNIGHT_PROGRESS.md > "$T/w_new.md"; git -C "$T/origin_w.git" show overnight/feature~1:OVERNIGHT_PROGRESS.md > "$T/w_old.md"; [ "$(grep -c $'\r$' "$T/w_new.md")" = "$(grep -c $'\r$' "$T/w_old.md")" ] && grep -qa $'Unrelated   \r$' "$T/w_new.md" && grep -qa $'\xff\xfe bytes line' "$T/w_new.md" && python3 - "$T/w_old.md" "$T/w_new.md" <<'EOS'
import sys
a=open(sys.argv[1],'rb').read().split(b"\n"); b=open(sys.argv[2],'rb').read().split(b"\n")
d=[(x,y) for x,y in zip(a,b) if x!=y]
sys.exit(0 if len(a)==len(b) and len(d)==3 and all(y.endswith(x[len(b"- [ ] "):]) for x,y in d) else 1)
EOS
[ $? = 0 ] && echo 1 || echo 0)"
# match scope
printf '%s\n' '# Progress
- [ ] [T1] scripts/battle/y.gd — an item that only RUNS the churning test. VERIFY: `gut -gtest=res://tests/test_x.gd`.
- [ ] [T2] scripts/battle/y.gd — an item whose description only READS scripts/battle/x.gd for context.
- [ ] [T3] other/main.py — shares a basename with another tracked file and names it bare: main.py edit.
- [ ] [T4] tests/test_x.gd — the real driver, named first.
- [ ] [T5] tests/test_x.gd — manual bug [feat:app-20261007-fix-x-manual-0a1b2c3d]
- [ ] [T6] EMERGENCY tests/test_x.gd failing in test-watch' | mkrepo v
mkdir -p "$T/work_v/other" "$T/work_v/a"; echo 1 > "$T/work_v/other/main.py"; echo 1 > "$T/work_v/a/main.py"; git -C "$T/work_v" add -A; git -C "$T/work_v" commit -q -m "init2"; git -C "$T/work_v" push -q origin overnight/feature
loop v tests/test_x.gd 12 170; reset
rc="$(run OVN_CHURN_REPOS="v")"
ok "SCOPE: only the item whose HEAD names the file is parked (VERIFY-only, description-only, bare ambiguous basename, manual bug, EMERGENCY all left active)" "$([ "$(prog v | grep -c 'AUTO-SKIP churn-loop')" = 1 ] && prog v | grep -q '^- \[ \] \[AUTO-SKIP churn-loop: tests/test_x.gd touched by 12 fleet commits in 3h - needs Claude; recovery:none\] \[T4\]' && echo 1 || echo 0)"
ok "SCOPE: the alert names the protected (bug/EMERGENCY) items left active" "$(grep -q '2 manual-bug/EMERGENCY item(s) name it and were left active' "$T/state/alerts.log" && echo 1 || echo 0)"
# interactive Claude commits are not fleet churn
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo cl
for i in $(seq 1 12); do w="$T/work_cl"; git -C "$w" pull -q --rebase origin overnight/feature 2>/dev/null; printf 'v=%s\n' $((i%2)) > "$w/tests/test_x.gd"; git -C "$w" add -A
  GIT_COMMITTER_DATE="$((NOW-(170-i*3)*60)) +0000" GIT_AUTHOR_DATE="$((NOW-(170-i*3)*60)) +0000" git -C "$w" commit -q -m "fix: revert x to int" -m "Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"; git -C "$w" push -q origin overnight/feature 2>/dev/null; done
reset; n0="$(ncommits cl)"; rc="$(run OVN_CHURN_REPOS="cl")"
ok "AUTHORSHIP: 12 oscillating commits that are Co-Authored-By: Claude (interactive session) are not counted => no park, no alert" "$([ "$(ncommits cl)" = "$n0" ] && [ "$(alerts cl)" = 0 ] && echo 1 || echo 0)"
# plain 'chore:' subjects (aider's real code commits) DO count
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo ch; m=170
for i in $(seq 1 6); do m=$((m-3)); cm ch $m "fix: restore x.gd to resolve missing module error" "scripts/battle/x.gd=v=1"; m=$((m-3)); cm ch $m "chore: remove file(s) per DELETE trailer" "scripts/battle/x.gd=v=0"; done
reset; rc="$(run OVN_CHURN_REPOS="ch")"
ok "CHORE: restore/'chore: remove file(s)' ping-pong (half the commits are plain 'chore:') is detected and parked" "$(prog ch | grep -q 'AUTO-SKIP churn-loop: scripts/battle/x.gd' && echo 1 || echo 0)"
# 3-file rotation
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo r3; m=170
for i in $(seq 1 9); do for f in x y z; do m=$((m-1)); cm r3 $m "fix: revert $f module to the previous behaviour" "scripts/battle/$f.gd=v=$((i%2))"; done; done
reset; rc="$(run OVN_CHURN_REPOS="r3")"
ok "FALSE-NEGATIVE: a 3-file rotation (each file 9 commits A/B/A) is flagged for all three files" "$([ "$(alerts r3)" = 3 ] && echo 1 || echo 0)"
# slow loop: 1 commit / 40 min on one file, 14 commits over ~9h: not parked, but WATCH alert
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo sl; m=560
for i in $(seq 1 14); do m=$((m-38)); cm sl $m "fix: revert x to previous value" "scripts/battle/x.gd=v=$((i%2))"; done
reset; n0="$(ncommits sl)"; rc="$(run OVN_CHURN_REPOS="sl")"
ok "FALSE-NEGATIVE: a slow loop (14 commits/9h, outside the 3h detector) raises ONE WATCH alert and parks nothing" "$([ "$(ncommits sl)" = "$n0" ] && [ "$(alerts sl)" = 1 ] && grep -q 'WATCH scripts/battle/x.gd' "$T/state/alerts.log" && echo 1 || echo 0)"
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo sf; m=560
for i in $(seq 1 14); do m=$((m-38)); cm sf $m "feat(app): staged step $i adds capability $i" "scripts/battle/x.gd=$(for j in $(seq 1 $i); do printf 'c%s=1\\n' $j; done)"; done
reset; rc="$(run OVN_CHURN_REPOS="sf")"
ok "WATCH BENIGN: a slow legit staged feature (14 forward steps/9h) raises no alert" "$([ "$(alerts sf)" = 0 ] && echo 1 || echo 0)"
# PARK=off
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo po; loop po tests/test_x.gd 12 170; reset; n0="$(ncommits po)"
rc="$(run OVN_CHURN_REPOS="po" OVN_CHURN_PARK=off)"
ok "OVN_CHURN_PARK=off: alert only, branch untouched, alert says how many would be parked" "$([ "$(ncommits po)" = "$n0" ] && [ "$(alerts po)" = 1 ] && grep -q 'ALERT ONLY (OVN_CHURN_PARK=off): 1 open queue item(s) would be parked' "$T/state/alerts.log" && echo 1 || echo 0)"
# stale worktree sweep + SIGTERM mid-push
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo st; loop st tests/test_x.gd 12 170; reset
git -C "$T/repos/st" worktree add -q --detach /tmp/wt-churnguard-st.stale1 HEAD; touch -t 202001010000 /tmp/wt-churnguard-st.stale1
rc="$(run OVN_CHURN_REPOS="st")"
ok "SWEEP: a stale (SIGKILL-leftover) worktree is removed on the next pass" "$([ ! -d /tmp/wt-churnguard-st.stale1 ] && [ "$(git -C "$T/repos/st" worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo sg; loop sg tests/test_x.gd 12 170; reset; n0="$(ncommits sg)"
( env OVN_DIR="$T" OVN_REPOS_DIR="$T/repos" OVN_STATE_DIR="$T/state" OVN_CHURN_REPOS="sg" OVN_CHURN_BEFORE_PUSH_HOOK="sleep 8" python3 "$PY" >"$T/sg.out" 2>&1 & echo $! > "$T/sg.pid"; wait ) &
for _ in $(seq 1 40); do ls -d /tmp/wt-churnguard-sg.* >/dev/null 2>&1 && break; sleep 0.25; done; sleep 1
kill -TERM "$(cat "$T/sg.pid")" 2>/dev/null; sleep 2
ok "SIGTERM mid-pass (committed locally, not pushed): temp worktree removed, origin unchanged, live clone has no worktree entry" "$([ -z "$(ls -d /tmp/wt-churnguard-sg.* 2>/dev/null)" ] && [ "$(ncommits sg)" = "$n0" ] && [ "$(git -C "$T/repos/sg" worktree list | wc -l | tr -d ' ')" = 1 ] && echo 1 || echo 0)"
# queue_refill must not re-pull the ORIGINAL text of a parked item
mkdir -p "$T/rf"; printf '%s\n' '- [ ] [AUTO-SKIP churn-loop: tests/test_x.gd touched by 12 fleet commits in 3h - needs Claude; recovery:none] [T5] scripts/battle/x.gd — Ensure h. VERIFY: `true`. [feat:xlite-20261007-add-h]' > "$T/rf/p.md"
printf '%s\n' '- [ ] [T5] scripts/battle/x.gd — Ensure h. VERIFY: `true`. [feat:xlite-20261009-add-h]' '- [ ] [T2] scripts/battle/y.gd — fresh item.' > "$T/rf/b.md"
out="$(python3 "$ROOT/queue_refill.py" "$T/rf/p.md" "$T/rf/b.md" 5)"
ok "REFILL: the roadmap's re-decomposed copy of a parked item is deduped (pruned), a genuinely new item is still pulled" "$(echo "$out" | grep -q 'REFILL=1' && ! grep -c 'scripts/battle/x.gd' "$T/rf/p.md" | grep -qv '^1$' && echo 1 || echo 0)"
# fleet-clone interaction: the live clone (behind) can fast-forward; one with an unpushed commit on ANOTHER line rebases cleanly
printf '%s\n' "$PROGRESS_DEFAULT" | mkrepo fc; loop fc tests/test_x.gd 12 170; reset
L="$T/repos/fc"; git -C "$L" fetch -q origin overnight/feature; git -C "$L" reset -q --hard origin/overnight/feature
printf -- '- [ ] [T9] scripts/battle/y.gd — fleet local line\n' >> "$L/OVERNIGHT_PROGRESS.md"; git -C "$L" add -A; git -C "$L" -c user.name=f -c user.email=f@f commit -q -m "fleet local cycle"
rc="$(run OVN_CHURN_REPOS="fc")"
ok "FLEET CLONE: with an unpushed cycle commit on another line, the runner's 'pull --rebase + push' succeeds after the guard pushed" "$(git -C "$L" -c user.name=f -c user.email=f@f pull -q --rebase origin overnight/feature 2>/dev/null && git -C "$L" push -q origin HEAD:overnight/feature 2>/dev/null && prog fc | grep -q 'AUTO-SKIP churn-loop' && prog fc | grep -q 'fleet local line' && echo 1 || echo 0)"

# ---- 12. pure-function checks -------------------------------------------------------------------------------------------------------------------
out="$(python3 - "$ROOT/scripts" <<'EOS'
import sys; sys.path.insert(0, sys.argv[1]); import ovn_churn_guard as g
assert g.names_file("- [ ] [T1] scripts/battle/x.gd — z", "scripts/battle/x.gd")
assert g.names_file("- [ ] edit x.gd please", "scripts/battle/x.gd", set())          # bare basename OK only when unambiguous
assert not g.names_file("- [ ] edit x.gd please", "scripts/battle/x.gd", {"x.gd"}) and not g.names_file("- [ ] edit x.gd please", "scripts/battle/x.gd")
assert g.names_file("- [ ] [T2] battle/x.gd - z", "scripts/battle/x.gd", {"x.gd"})   # '/'-bounded path suffix is never ambiguous
assert not g.names_file("- [ ] edit damage_x.gd please", "scripts/battle/x.gd", set())  # whole-token match
assert not g.names_file("- [ ] edit x.gdscript", "scripts/battle/x.gd", set())
assert not g.names_file("- [ ] [T2] scripts/other.gd - add a case. VERIFY: gut -gtest=scripts/battle/x.gd", "scripts/battle/x.gd", set())   # VERIFY only RUNS it
assert not g.names_file("- [ ] [T2] scripts/other.gd - this reads scripts/battle/x.gd for context", "scripts/battle/x.gd", set())   # description only READS it
assert g.names_file("- [ ] [T2] Fix the bug - in scripts/battle/x.gd", "scripts/battle/x.gd", set())  # no path before the separator => whole text
assert g.tag_text("a]b.gd", 3, 3).count("]") == 1
assert g.is_test_path("tests/test_a.gd") and g.is_test_path("src/a.test.ts") and not g.is_test_path("scripts/a.gd")
assert g.stem("tests/test_enemy_faction_map.gd") == g.stem("scripts/battle/enemy_faction_map.gd") == "enemy_faction_map"
assert not g.oscillates(2, 5, 9, 9) and g.oscillates(3, 2, 0, 9) and g.oscillates(3, 0, 3, 9) and not g.oscillates(3, 1, 2, 9)
t = "- [ ] [AUTO-SKIP x] a.gd\n- [ ] [CLAUDE] a.gd\n- [ ] BLOCKED a.gd\n- [ ] (retired-dead-path) a.gd\n- [ ] HUMAN-ONLY a.gd\n- [ ] ok a.gd\n- [x] a.gd"
assert [l for _, l in g.open_lines(t)] == ["- [ ] ok a.gd"]
print("PURE-OK")
EOS
)"
ok "pure helpers: boundary matching, test/source stems, oscillation predicate, ineligible-line set mirrors the pickers" "$([ "$out" = PURE-OK ] && echo 1 || echo 0)"

echo; echo "ovn_churn_guard: $pass passed, $fail failed"; [ "$fail" = 0 ]
