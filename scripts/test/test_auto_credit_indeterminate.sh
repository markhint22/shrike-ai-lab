#!/usr/bin/env bash
# QA harness-X follow-ups (2026-10-02), review notes X-a / X-b / X-c on the auto-credit gate.
#   X-a  the credit gate's VERIFY used shadow_check's fixed 60s cap; live VERIFYs are slow (gradlew testDebugUnitTest, xcodebuild, full pytest, vitest),
#        so a correctly landed item could never be credited, was re-faced and burned the item guard's attempt counter. Now: configurable timeouts
#        (OVN_AC_VERIFY_TIMEOUT / _HEAVY), a rc=124 / unrunnable VERIFY is a DISTINCT indeterminate result (one deduped alert per cycle), it is not a
#        failed attempt for ovn_item_guard (the green commit landed), and the other shadow_check callers keep the 60s cap.
#   X-b  a VERIFY reading stdin swallowed the remaining item lines of the caller's here-string loop.
#   X-c  the tree guard refused on ANY tracked-file difference, including generated droppings (Godot rewrites project.godot ...), and named at most
#        a blob of 10 paths; now: generated artefacts the cycle did not touch are ignored (logged), everything else refuses and names the first 5.
# Every NEW assertion here fails on the pre-follow-up code (missing functions/variables/markers); the "benign twin" lines are labelled.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
[ -f "$S/lib_auto_credit.sh" ] || { echo "  SKIP: lib_auto_credit.sh not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
ALERTS="$W/alerts.log"; : > "$ALERTS"
emit_alert(){ echo "$1 | $2 | $3" >> "$ALERTS"; }
. "$S/lib_item_select.sh"
. "$S/lib_verify_clause.sh"
. "$S/lib_auto_credit.sh"

# ---------------- X-a: shadow_check timeouts + distinct results ----------------
PROG="$W/prog.md"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
cat > "$PROG" <<'EOP'
- [ ] [T2] a.py — slow. VERIFY: `sleep 3`
- [ ] [T2] b.py — heavy-looking and slow. VERIFY: `sleep 3 && echo npm run build >/dev/null`
- [ ] [T2] c.py — no such tool. VERIFY: `definitely_not_a_command_xyz --version`
- [ ] [T2] d.py — plain failure. VERIFY: `false`
- [ ] [T2] e.py — quick pass. VERIFY: `sleep 1`
- [ ] [T2] f.py — gradlew in a repo without one. VERIFY: `cd nowhere && ./gradlew testDebugUnitTest`
EOP
( cd "$W" && VERIFY_TIMEOUT_SECS=1 shadow_check 1; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_RC|$_LAST_VERIFY_TIMEOUT|$_LAST_VERIFY_WHY" > "$W/r1" )
eq "timeout: a 3s VERIFY under a 1s cap is TIMEOUT (not FAIL), rc 124, why names the cap" "$(cat "$W/r1")" "TIMEOUT|124|1|VERIFY timed out (rc=124) after 1s"
ok "timeout: the shadow row is result=TIMEOUT rc=124" 'grep -q "line=1 result=TIMEOUT rc=124 timeout=1s" "$SHADOW_LOG"'
( cd "$W" && VERIFY_TIMEOUT_SECS=1 VERIFY_TIMEOUT_HEAVY_SECS=10 shadow_check 2; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_TIMEOUT" > "$W/r2" )
eq "heavy clause (npm run build) gets the HEAVY cap: PASS in 3s although the normal cap is 1s" "$(cat "$W/r2")" "PASS|10"
( cd "$W" && VERIFY_TIMEOUT_SECS=1 VERIFY_TIMEOUT_HEAVY_SECS=10 shadow_check 1; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_TIMEOUT" > "$W/r2b" )
eq "benign twin: a NON-heavy slow clause does not get the heavy cap" "$(cat "$W/r2b")" "TIMEOUT|1"
( cd "$W" && shadow_check 5; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_TIMEOUT" > "$W/r3" )
eq "default timeout is still 60s for callers that set nothing (credit-already-satisfied keeps its cap)" "$(cat "$W/r3")" "PASS|60"
( cd "$W" && shadow_check 3; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_RC|$_LAST_VERIFY_WHY" > "$W/r4" )
ok "unrunnable: a missing tool is UNRUNNABLE with a 'VERIFY not runnable' reason" 'grep -q "^UNRUNNABLE|127|VERIFY not runnable" "$W/r4"'
( cd "$W" && shadow_check 4; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_RC" > "$W/r5" )
eq "benign twin: an ordinary failing VERIFY stays FAIL (rc 1), never indeterminate" "$(cat "$W/r5")" "FAIL|1"
( cd "$W" && shadow_check 6; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_WHY" > "$W/r6" )
eq "unrunnable: a gradlew clause in a repo with no gradlew" "$(cat "$W/r6")" "UNRUNNABLE|VERIFY not runnable: gradlew not found in this repo"

# heavy classifier
for c in './gradlew testDebugUnitTest' 'cd iptv-android && ./gradlew testDebugUnitTest' 'xcodebuild test -scheme X' 'mvn -q test' 'npm run build' 'npm test' 'npx vitest run' 'cd addons/gut && godot4 --headless -s gut_cmdln.gd -gtest=res://tests/test_x.gd' 'npm run test -- HomeView' 'pytest' 'cd backend && .venv/bin/pytest -q' 'pytest -q tests/'; do
  ok "heavy: [$c]" '_verify_is_heavy "$c"'
done
for c in 'pytest -k test_one' 'pytest tests/test_a.py' 'pytest tests/test_a.py::test_x -q' 'grep -q foo bar.py' 'python3 -c "import x"' 'test -f src/a.py'; do
  ok "not heavy: [$c]" '! _verify_is_heavy "$c"'
done

# ---------------- X-b: a VERIFY that reads stdin must not eat the caller's loop ----------------
cat > "$PROG" <<'EOP'
- [ ] [T2] a.py — reads stdin. VERIFY: `cat >/dev/null`
EOP
n=0; seen=""
while IFS= read -r item; do [ -z "$item" ] && continue; shadow_check 1; n=$((n+1)); seen="$seen $item"; done <<< $'one\ntwo\nthree'
eq "stdin: all 3 loop iterations ran (the old VERIFY swallowed the other lines)" "$n:$seen" "3: one two three"
eq "stdin: the reading VERIFY itself still passes (EOF immediately)" "$_LAST_VERIFY_RESULT" "PASS"

# ---------------- fixture repos for the real ovn_auto_credit ----------------
mk() {  # mk <name> ; item lines come from the caller via $ITEMS
  R="$W/r/$1"; rm -rf "$R"; mkdir -p "$R/src"; cd "$R" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'def old_a():\n    return 1\n' > src/a.py
  printf 'def old_b():\n    return 1\n' > src/b.py
  printf 'other\n' > src/other.py
  printf 'config_version=5\n' > project.godot
  printf '%s\n' "## Next Steps" "$ITEMS" "" "## Completed" > OVERNIGHT_PROGRESS.md
  git add -A && git commit -q -m base; B="$(git rev-parse HEAD)"
}
cm() { git add -A && git commit -q -m "$1"; A="$(git rev-parse HEAD)"; }
call() { : > "$R/task.log"; : > "$ALERTS"; ovn_auto_credit "$B" "$A" OVERNIGHT_PROGRESS.md "$R/task.log" 2>/dev/null; CRC=$?; CLOG="$(cat "$R/task.log")"; }
prog_line() { grep -E "$1" OVERNIGHT_PROGRESS.md | head -1; }

# ---------------- X-a: indeterminate through ovn_auto_credit ----------------
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `sleep 3 && grep -q "def new_a" src/a.py`
- [ ] [T2] src/b.py — Add new_b. VERIFY: `sleep 3 && grep -q "def new_b" src/b.py`'
mk slow; printf 'def new_a():\n    return 2\n' >> src/a.py; printf 'def new_b():\n    return 2\n' >> src/b.py; cm "feat: a and b"
OVN_AC_VERIFY_TIMEOUT=1 OVN_AC_VERIFY_TIMEOUT_HEAVY=1 call
eq "indeterminate: rc 0 (not a refusal of the cycle)" "$CRC" 0
eq "indeterminate: nothing credited, 2 indeterminate" "$OVN_AC_CREDITED:$OVN_AC_INDETERMINATE" "0:2"
ok "indeterminate: both items stay open" '[ "$(grep -c "^- \[ \]" OVERNIGHT_PROGRESS.md)" = 2 ]'
eq "indeterminate: no commit made, HEAD is the cycle commit" "$(git rev-parse HEAD)" "$A"
ok "indeterminate: per-item log line says timed out (rc=124) after 1s and not-a-failed-attempt" 'printf "%s" "$CLOG" | grep -q "INDETERMINATE line 2.*VERIFY timed out (rc=124) after 1s.*not counted as a failed attempt"'
ok "indeterminate: NOT logged as 'VERIFY: clause FAILED'" '[ "$(printf "%s" "$CLOG" | grep -c "clause FAILED")" = 0 ]'  # was: ! ... | grep -q (flaky/masking under pipefail: grep -q exits early, SIGPIPE flips the negation)
eq "indeterminate: exactly ONE alert for the cycle (deduped across both items)" "$(wc -l < "$ALERTS" | tr -d ' ')" 1
ok "indeterminate: the alert carries the distinct reason" 'grep -q "VERIFY timed out (rc=124) after 1s" "$ALERTS" && grep -q "not a failed attempt" "$ALERTS"'
eq "indeterminate: one indet-hash marker per item in the task log (item-guard contract)" "$(grep -c 'auto-credit: indet-hash [0-9a-f]\{32\}' "$R/task.log")" 2
ok "indeterminate: no item-hash (credited) marker was written" '! grep -q "auto-credit: item-hash" "$R/task.log"'
ok "indeterminate: worktree clean" '[ -z "$(git status --porcelain --untracked-files=no)" ]'

# benign twin: same items, the heavy cap fits -> credited normally (and a clause with no heavy keyword is NOT given the heavy cap)
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `sleep 2 && grep -q "def new_a" src/a.py && echo npm run build >/dev/null`
- [ ] [T2] src/b.py — Add new_b. VERIFY: `sleep 2 && grep -q "def new_b" src/b.py`'
mk heavyfits; printf 'def new_a():\n    return 2\n' >> src/a.py; printf 'def new_b():\n    return 2\n' >> src/b.py; cm "feat: a and b"
OVN_AC_VERIFY_TIMEOUT=1 OVN_AC_VERIFY_TIMEOUT_HEAVY=10 call
ok "heavy cap: the heavy-runner item is credited (benign twin)" 'prog_line "src/a.py" | grep -q "^- \[x\]"'
ok "heavy cap: the plain slow item is NOT given the heavy cap, stays open as indeterminate" 'prog_line "src/b.py" | grep -q "^- \[ \]" && [ "$OVN_AC_INDETERMINATE" = 1 ]'

# benign: the default env (no OVN_AC_* set) credits a 2s VERIFY
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `sleep 2 && grep -q "def new_a" src/a.py`'
mk dflt; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
call
ok "defaults (300s) credit a 2s VERIFY" 'prog_line "src/a.py" | grep -q "^- \[x\]"'
ok "defaults: no indeterminate marker/alert" '[ "$OVN_AC_INDETERMINATE" = 0 ] && [ ! -s "$ALERTS" ]'
ok "shadow_check's own default did not leak: the 60s default applies again after the call" '[ -z "${VERIFY_TIMEOUT_SECS:-}" ]'

# unrunnable through ovn_auto_credit
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `definitely_not_a_command_xyz src/a.py`'
mk unrun; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
call
ok "unrunnable: left open" 'prog_line "src/a.py" | grep -q "^- \[ \]"'
ok "unrunnable: alert says 'VERIFY not runnable'" 'grep -q "VERIFY not runnable" "$ALERTS"'
# negative: a failing VERIFY is a refusal (FAIL), no indeterminate bookkeeping
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def never_there" src/a.py`'
mk failv; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
call
ok "fail: refused as FAILED, not indeterminate" 'printf "%s" "$CLOG" | grep -q "clause FAILED" && [ "$OVN_AC_INDETERMINATE" = 0 ] && ! grep -q "indet-hash" "$R/task.log" && [ ! -s "$ALERTS" ]'

# per-cycle budget: exhausted budget -> remaining VERIFYs are not run, reported as timed out
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py`'
mk budget; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
: > "$OVN_VERIFY_SHADOW_LOG"; OVN_AC_VERIFY_BUDGET=0 call
ok "budget exhausted: not run (no shadow row), indeterminate, left open" '[ ! -s "$OVN_VERIFY_SHADOW_LOG" ] && [ "$OVN_AC_INDETERMINATE" = 1 ] && prog_line "src/a.py" | grep -q "^- \[ \]"'

# ---------------- X-c: tree guard ----------------
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py`'
mk drop; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
printf 'config_version=5\nrendering=1\n' > project.godot      # Godot rewrote a tracked file the cycle never touched
call
eq "benign dropping (project.godot, not in the cycle diff): rc 0 and credited" "$CRC:$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)" "0:1"
ok "benign dropping: logged as ignored" 'printf "%s" "$CLOG" | grep -q "ignoring tracked generated-artefact difference.*project.godot"'
eq "benign dropping: the tick commit stages ONLY the progress file" "$(git show --name-only --format= HEAD | tr '\n' ' ')" "OVERNIGHT_PROGRESS.md "
ok "benign dropping: the dropping is left alone in the worktree, never committed" 'git diff --name-only | grep -qx project.godot'

mk touched; printf 'def new_a():\n    return 2\n' >> src/a.py; printf 'config_version=5\nchanged_by_cycle=1\n' > project.godot; cm "feat: a + project.godot"
printf 'config_version=5\n' > project.godot                # half-reverted: the incident shape on a file the cycle's diff DID touch
call
eq "same file but the cycle touched it (half-restored): refused, rc 1" "$CRC" 1
ok "touched: nothing ticked, refusal names project.godot" '[ "$(grep -c "^- \[x\]" OVERNIGHT_PROGRESS.md)" = 0 ] && printf "%s" "$CLOG" | grep -q "REFUSED - working tree/index differ.*project.godot"'
ok "touched: alert names it too" 'grep -q "project.godot" "$ALERTS"'

mk srcdirty; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
printf 'edited\n' >> src/other.py
call
eq "non-generated tracked file the cycle did not touch (src/other.py): refused" "$CRC" 1
ok "refusal names src/other.py" 'printf "%s" "$CLOG" | grep -q "differ from AFTER.*src/other.py"'
mk many; printf 'def new_a():\n    return 2\n' >> src/a.py; mkdir -p lib; for i in 1 2 3 4 5 6 7; do printf 'v1\n' > lib/m$i.txt; done; cm "feat: a + lib"
for i in 1 2 3 4 5 6 7; do printf 'dirty\n' >> lib/m$i.txt; done
call
ok "refusal lists the FIRST 5 paths and counts the rest" 'printf "%s" "$CLOG" | grep -q "lib/m1.txt lib/m2.txt lib/m3.txt lib/m4.txt lib/m5.txt (+2 more)" && ! printf "%s" "$CLOG" | grep -q "lib/m6.txt"'

mk off; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"; printf 'rendering=1\n' >> project.godot
OVN_TREE_BENIGN=off call
eq "OVN_TREE_BENIGN=off disables the allowlist (every tracked difference refuses)" "$CRC" 1

# a staged difference is never benign-skipped silently into a commit: a staged generated file refuses at the index assertion, not committed
mk staged; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"; printf 'rendering=1\n' >> project.godot; git add project.godot
call
ok "a STAGED generated file is not swept into the credit commit" '[ "$(git show --name-only --format= HEAD | grep -c project.godot)" = 0 ]'  # was: ! ... | grep -q (flaky/masking under pipefail: grep -q exits early, SIGPIPE flips the negation)

# a VERIFY that rewrites a generated tracked file does not turn a pass into a refusal (post-VERIFY tree check)
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py && printf rewritten | tee -a project.godot >/dev/null`'
mk vgen; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
call
eq "VERIFY rewrites project.godot (generated): still credited" "$CRC:$(grep -c '^- \[x\]' OVERNIGHT_PROGRESS.md)" "0:1"
ITEMS='- [ ] [T2] src/a.py — Add new_a. VERIFY: `grep -q "def new_a" src/a.py && printf rewritten | tee -a src/other.py >/dev/null`'
mk vsrc; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
call
eq "benign twin: VERIFY rewrites a SOURCE file: still refused and reset to AFTER" "$CRC:$(git rev-parse HEAD):$(git diff --name-only "$A" | wc -l | tr -d ' ')" "1:$A:0"

# the bookkeeping-guard call shape (run_overnight.sh): third arg = BEFORE sha, except = the progress file
mk bk; printf 'def new_a():\n    return 2\n' >> src/a.py; cm "feat: a"
printf 'edit\n' >> OVERNIGHT_PROGRESS.md; printf 'rendering=1\n' >> project.godot
out="$(ovn_tree_matches_sha "$A" OVERNIGHT_PROGRESS.md "$B")"; rc=$?
eq "bookkeeping guard: progress-file edit + generated dropping: ok" "$rc:$out" "0:"
printf 'edited\n' >> src/b.py
out="$(ovn_tree_matches_sha "$A" OVERNIGHT_PROGRESS.md "$B")"; rc=$?
eq "bookkeeping guard: a real source dirt refuses and names only it" "$rc:$out" "1:src/b.py"
out="$(ovn_tree_matches_sha "$A" OVERNIGHT_PROGRESS.md)"; rc=$?
eq "bookkeeping guard WITHOUT a before sha: nothing is treated as benign (old behaviour)" "$rc:$out" "1:project.godot src/b.py"

# ---------------- item guard: an indeterminate landing is a landing, not a failed attempt ----------------
G="$S/ovn_item_guard.sh"
line='- [ ] [T2] `src/a.py` — heavy item whose VERIFY timed out'
mkg() {  # mkg <name> -> repo with the one item; sets GR, ST
  GR="$W/g/$1"; ST="$W/g/$1.state"; rm -rf "$GR" "$ST"; mkdir -p "$GR" "$ST"
  ( cd "$GR" && git init -q -b main . && git config user.email t@t && git config user.name t && printf '%s\n' "$line" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m i )
  H="$(ovn_item_hash "$line")"; mkdir -p "$ST/item_fails"
}
ilog() { printf -- '--- auto-credit: indet-hash %s ---\n' "$H" > "$W/g/ind.log"; echo "$W/g/ind.log"; }
mkdir -p "$W/g"; printf 'VERDICT: PROCEED\nFILES: src/a.py\n' > "$W/g/scout.log"

mkg idle1; printf '2' > "$ST/item_fails/it.$H.count"; printf '3' > "$ST/item_fails/it.$H.noopcount"
bash "$G" "$GR" "pushed(tests:pass)" "$ST" it "$(ilog)" >/dev/null
ok "landing with indet-hash clears the item's fail + no-op streaks (it landed)" '[ ! -e "$ST/item_fails/it.$H.count" ] && [ ! -e "$ST/item_fails/it.$H.noopcount" ]'
ok "landing with indet-hash arms the indeterminate allowance" '[ -f "$ST/item_fails/it.$H.indet" ]'
ok "landing with indet-hash does not park the item" 'grep -q "^- \[ \] \[T2\]" "$GR/OVERNIGHT_PROGRESS.md" && ! grep -q AUTO-SKIP "$GR/OVERNIGHT_PROGRESS.md"'
# next cycles: ALREADY-DONE no-ops on that item, NCAP=2 -> the first 3 are free, then it counts like any no-op
for i in 1 2 3; do OVN_ITEM_NOOP_CAP=2 bash "$G" "$GR" "no-op(ALREADY-DONE)" "$ST" it "$W/g/scout.log" >/dev/null; done
ok "3 ALREADY-DONE no-ops after an indeterminate landing burn no no-op budget and do not park the item" '[ ! -e "$ST/item_fails/it.$H.noopcount" ] && ! grep -q AUTO-SKIP "$GR/OVERNIGHT_PROGRESS.md"'
OVN_ITEM_NOOP_CAP=2 bash "$G" "$GR" "no-op(ALREADY-DONE)" "$ST" it "$W/g/scout.log" >/dev/null
ok "the allowance is bounded: the 4th ALREADY-DONE counts" '[ "$(cat "$ST/item_fails/it.$H.noopcount" 2>/dev/null)" = 1 ]'
OVN_ITEM_NOOP_CAP=2 bash "$G" "$GR" "no-op(ALREADY-DONE)" "$ST" it "$W/g/scout.log" >/dev/null
ok "...and the item is parked normally after NCAP counted no-ops" 'grep -q AUTO-SKIP "$GR/OVERNIGHT_PROGRESS.md"'

# negative twins (the old behaviour must be unchanged for everything else)
mkg noind
for i in 1 2; do OVN_ITEM_NOOP_CAP=2 bash "$G" "$GR" "no-op(ALREADY-DONE)" "$ST" it "$W/g/scout.log" >/dev/null; done
ok "without an indeterminate landing, ALREADY-DONE no-ops count and park at NCAP (unchanged)" 'grep -q AUTO-SKIP "$GR/OVERNIGHT_PROGRESS.md"'
mkg failing; printf '0' > "$ST/item_fails/it.$H.indet"
for i in 1 2 3; do OVN_ITEM_FAIL_CAP=3 bash "$G" "$GR" "reverted(build-break)" "$ST" it "$W/g/scout.log" >/dev/null; done
ok "the allowance covers ONLY no-op(ALREADY-DONE): real reverts still burn the fail budget and park" 'grep -q AUTO-SKIP "$GR/OVERNIGHT_PROGRESS.md"'
mkg otherstatus; printf '0' > "$ST/item_fails/it.$H.indet"
for i in 1 2; do OVN_ITEM_NOOP_CAP=2 bash "$G" "$GR" "no-op" "$ST" it "$W/g/scout.log" >/dev/null; done
ok "a bare no-op (not ALREADY-DONE) is not exempt either" 'grep -q AUTO-SKIP "$GR/OVERNIGHT_PROGRESS.md"'
mkg notpass; bash "$G" "$GR" "reverted(build-break)" "$ST" it "$(ilog)" >/dev/null
ok "an indet-hash in a cycle that did NOT land (reverted) is ignored" '[ ! -e "$ST/item_fails/it.$H.indet" ] && [ "$(cat "$ST/item_fails/it.$H.count")" = 1 ]'

# ---------------- wiring ----------------
RO="$S/../run_overnight.sh"
ok "WIRING: bookkeeping tree guard passes the cycle's BEFORE_SHA" 'grep -F "ovn_tree_matches_sha \"\$AFTER_SHA\" OVERNIGHT_PROGRESS.md \"\$BEFORE_SHA\"" "$RO"'
ok "WIRING: credit-already-satisfied still refuses TIMEOUT/UNRUNNABLE" 'grep -q "TIMEOUT.*UNRUNNABLE" "$S/ovn_credit_already_satisfied.sh"'

echo "$P passed, $F failed"
[ "$F" -eq 0 ]
