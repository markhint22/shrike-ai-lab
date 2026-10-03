#!/usr/bin/env bash
# test_run_integrity_lib.sh - 2026-10-03, integrity track (A5/A6/A12). Unit + fixture tests, each new behaviour with a NEGATIVE control (seeded bad
# input is caught) and a BENIGN control (clean input passes):
#   lib_run_integrity.sh   failing ids, baseline subtraction (pre-existing red test), reachability (commit lost before push), cycle-active marker
#   lib_fixup_prompt.sh    baseline ids dropped from the prompt, no "PASSED before" claim when unverified
#   lib_verify_clause.sh   -gexit appended, narrowed GUT timeout, GUT "Failing Tests" parse (GUT exits 0 on failures), identical-VERIFY dedupe
#   qa_ledger / scorecard  landed-without-commit flag, escape-rate denominator, >=3 repeats alert
#   ovn_outcome_buckets    ContextWindowExceeded = bad
#   record_outcome         every field JSON-safe; readers tolerate a malformed row
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
PY="$(command -v python3.12 || command -v python3)"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL $1 (expected [$2] got [$3])"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
export HOME="$T/home"; mkdir -p "$HOME"

. "$Q/scripts/lib_run_integrity.sh"

# ============================================================ A5: failing ids
LOG="$T/v.log"
printf 'noise\nFAILED tests/a.py::t1 - assert 1 == 2\nERROR tests/b.py::t2 - boom\nFAILED tests/a.py::t1 - dup\n== 2 failed, 3 passed in 1.20s ==\n' > "$LOG"
eq "ids: pytest FAILED/ERROR, de-duplicated, message stripped" "tests/a.py::t1|tests/b.py::t2" "$(ovn_ri_failing_ids "$LOG" | tr '\n' '|' | sed 's/|$//')"
OFF="$(wc -c < "$LOG" | tr -d ' ')"
printf 'FAILED tests/c.py::t3\n1 failed, 9 passed in 0.5s\n' >> "$LOG"
eq "ids: only the bytes after the offset (an earlier verify run cannot leak in)" "tests/c.py::t3" "$(ovn_ri_failing_ids "$LOG" "$OFF")"
printf '  FAIL  src/x.test.ts > renders\n Test Files  1 failed (1)\n' > "$T/vt.log"
eq "ids: vitest FAIL line" "src/x.test.ts > renders" "$(ovn_ri_failing_ids "$T/vt.log")"
printf 'all good\n5 passed in 0.3s\n' > "$T/g.log"
eq "ids: green log has none (benign control)" "" "$(ovn_ri_failing_ids "$T/g.log")"
ovn_ri_has_summary "$LOG" 0 && ok "summary: pytest summary line recognised" 1 || ok "summary: pytest summary line recognised" 0
printf 'FAILED tests/a.py::t1\n' > "$T/partial.log"
ovn_ri_has_summary "$T/partial.log" 0 && ok "summary: a partial log (killed by the cap) has NO summary" 0 || ok "summary: a partial log (killed by the cap) has NO summary" 1

# ---- fixture repo: c0 (BEFORE) -> c1 (AFTER, the model's commit); stub verification driven by per-sha files
R="$T/repo"; mkdir -p "$R"; ( cd "$R" && git init -q -b main && echo 0 > f && git add f && git commit -q -m c0 && echo 1 > f && git add f && git commit -q -m c1 )
C0="$(git -C "$R" rev-parse HEAD~1)"; C1="$(git -C "$R" rev-parse HEAD)"
SD="$T/state"; mkdir -p "$SD"; FIX="$T/fix"; mkdir -p "$FIX"
run_repo_verification(){   # stub: output/result for the CHECKED-OUT sha; counts calls
  local s; s="$(git rev-parse HEAD)"
  echo $(( $(cat "$FIX/calls" 2>/dev/null || echo 0) + 1 )) > "$FIX/calls"
  echo "$s" >> "$FIX/called_at"
  [ -f "$FIX/out.$s" ] && cat "$FIX/out.$s" >> "$task_log"
  cat "$FIX/res.$s" 2>/dev/null || echo fail
}
ncalls(){ local c; c="$(cat "$FIX/calls" 2>/dev/null)"; echo "${c:-0}"; }
task_log="$T/cycle.log"
red_cur(){ printf 'FAILED tests/old.py::test_old - x\nFAILED tests/new.py::test_new - y\n== 2 failed, 5 passed in 2.00s ==\n' > "$task_log"; }
base_old_only(){ rm -f "$SD"/baseline_fail_*; printf 'FAILED tests/old.py::test_old - x\n== 1 failed, 6 passed in 2.00s ==\n' > "$FIX/out.$C0"; echo fail > "$FIX/res.$C0"; : > "$FIX/calls"; : > "$FIX/called_at"; }

# NEGATIVE: a NEW failing id on top of a pre-existing one is reported as new red (revert stays correct)
red_cur; base_old_only
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD" ); rc=$?
eq "subtract: new failing id => rc 1 (the commit IS red)" 1 "$rc"
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD" >/dev/null; echo "$OVN_RI_STATUS|$OVN_RI_NEW|$OVN_RI_BASE_N" ) > "$T/o1"
eq "subtract: status=subtracted, NEW = only the id the baseline lacked" "subtracted|tests/new.py::test_new|1" "$(cat "$T/o1")"
eq "subtract: tree restored to the model's commit after the baseline run" "$C1" "$(git -C "$R" rev-parse HEAD)"
eq "subtract: still on the branch (not detached)" main "$(git -C "$R" symbolic-ref --short HEAD)"
eq "subtract: baseline verified at BEFORE_SHA, not AFTER" "$C0" "$(sort -u "$FIX/called_at" | head -1)"
ok "subtract: baseline ids cached in state/baseline_fail_<repo>_<sha>.txt" "$([ -s "$SD/baseline_fail_repo_$C0.txt" ] && head -1 "$SD/baseline_fail_repo_$C0.txt" | grep -q '^#result=fail' && grep -qx 'tests/old.py::test_old' "$SD/baseline_fail_repo_$C0.txt" && echo 1 || echo 0)"
eq "subtract: second call reuses the cache (baseline verified once for two calls)" 1 "$(ncalls)"

# BENIGN: the red run's failures are exactly the pre-existing ones => no NEW red
printf 'FAILED tests/old.py::test_old - x\n== 1 failed, 6 passed in 2.00s ==\n' > "$task_log"; base_old_only
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS n=$OVN_RI_BASE_N new=[$OVN_RI_NEW]" ) > "$T/o2"
eq "subtract: identical failures => rc 0, all-baseline, nothing new" "rc=0 all-baseline n=1 new=[]" "$(cat "$T/o2")"

# ---- reviewer blocker: MULTI-SUITE red. pytest red == baseline, but a second suite (gradle/GUT/tsc/npm) also failed WITHOUT ids.
multi_log(){ printf 'FAILED tests/old.py::test_old - x\n== 1 failed, 20 passed in 3.21s ==\n%s\n' "$1" > "$task_log"; }
base_old_only
multi_log '--- verify: ./gradlew test in app (240s cap) ---
> Task :app:testDebugUnitTest FAILED
FAILURE: Build failed with an exception.'
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract NEGATIVE: pytest==baseline + gradle build failed (no ids) => NOT all-baseline (reverts)" "rc=1 other-suite-red" "$(cat "$T/o3")"
base_old_only
multi_log '--- GUT RED: failures=2'
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract NEGATIVE: pytest==baseline + GUT red => other-suite-red" "rc=1 other-suite-red" "$(cat "$T/o3")"
base_old_only
multi_log "src/a.ts(3,1): error TS2322: bad"
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract NEGATIVE: pytest==baseline + tsc error (an .ovn-verify.sh later step) => other-suite-red" "rc=1 other-suite-red" "$(cat "$T/o3")"
# per-suite record written by run_repo_verification: two red suites, or a non-pytest red suite, vetoes subtraction even with NO textual marker
base_old_only
multi_log '--- verify-suite-red: pytest in ./backend rc=1 ---
--- verify-suite-red: npm in ./web rc=124 ---'
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract NEGATIVE: two red suites recorded (second timed out, no ids) => other-suite-red" "rc=1 other-suite-red" "$(cat "$T/o3")"
base_old_only
multi_log '--- verify-suite-red: gradle in ./app rc=1 ---'
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract NEGATIVE: the only recorded red suite is gradle => other-suite-red" "rc=1 other-suite-red" "$(cat "$T/o3")"
# BENIGN: exactly one red suite, pytest, ids == baseline => still all-baseline
base_old_only
multi_log '--- verify-suite-red: pytest in ./backend rc=1 ---'
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract BENIGN: single red pytest suite, ids == baseline => all-baseline" "rc=0 all-baseline" "$(cat "$T/o3")"
base_old_only
multi_log '--- verify: ./gradlew test in app (240s cap) ---
BUILD SUCCESSFUL in 4s'
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract BENIGN: a green gradle section next to the baseline pytest red => all-baseline" "rc=0 all-baseline" "$(cat "$T/o3")"
# vitest trailing duration is stripped so the id matches the baseline
printf '  ×  src/x.test.ts > renders 3ms\n Test Files  1 failed (1)\n' > "$T/vt2.log"
eq "ids: trailing duration stripped (vitest 'name 3ms')" "src/x.test.ts > renders" "$(ovn_ri_failing_ids "$T/vt2.log")"
# jest is unsupported on purpose (documented): status incomplete => old revert
printf ' FAIL  src/a.test.ts\nTests:       2 failed, 3 passed, 5 total\n' > "$T/jest.log"
ovn_ri_has_summary "$T/jest.log" 0 && ok "jest: NOT treated as a parseable summary (falls back to revert)" 0 || ok "jest: NOT treated as a parseable summary (falls back to revert)" 1

# baseline GREEN: every failing id is new red
red_cur; rm -f "$SD"/baseline_fail_*; echo pass > "$FIX/res.$C0"; rm -f "$FIX/out.$C0"
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o3"
eq "subtract: green baseline => baseline-green, rc 1 (old revert behaviour)" "rc=1 baseline-green" "$(cat "$T/o3")"

# no summary line => never subtract (a killed run's partial list)
printf 'FAILED tests/old.py::test_old\n' > "$task_log"; base_old_only
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o4"
eq "subtract: partial output (no runner summary) => incomplete, rc 1" "rc=1 incomplete" "$(cat "$T/o4")"
eq "subtract: ... and no baseline run was spent on it" 0 "$(ncalls)"

# nothing parseable => old behaviour, no baseline run
printf 'npm ERR! build failed\n' > "$task_log"; base_old_only
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o5"
eq "subtract: no failing ids => no-ids, rc 1" "rc=1 no-ids" "$(cat "$T/o5")"
eq "subtract: ... baseline only runs when the red run has failures" 0 "$(ncalls)"

# baseline run could not happen (skip) => unknown, never cached, never subtracted
printf 'FAILED tests/old.py::test_old\n== 1 failed in 1.0s ==\n' > "$task_log"; base_old_only; echo skip > "$FIX/res.$C0"
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o6"
eq "subtract: baseline verify skipped => baseline-unknown, rc 1" "rc=1 baseline-unknown" "$(cat "$T/o6")"
ok "subtract: a skipped baseline is NOT cached" "$([ ! -e "$SD/baseline_fail_repo_$C0.txt" ] && echo 1 || echo 0)"

# dirty tracked tree must never be disturbed
base_old_only; echo dirty >> "$R/f"
( cd "$R" && ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o7"
eq "subtract: dirty tracked tree => baseline-unknown (tree untouched)" "rc=1 baseline-unknown" "$(cat "$T/o7")"
eq "subtract: dirty file content survived" "$(printf '1\ndirty')" "$(cat "$R/f")"
git -C "$R" checkout -q -- f
base_old_only
( cd "$R" && OVN_BASELINE_SUBTRACT=off ovn_ri_subtract "$task_log" 0 repo "$C0" "$SD"; echo "rc=$? $OVN_RI_STATUS" ) > "$T/o8"
eq "subtract: OVN_BASELINE_SUBTRACT=off disables it" "rc=1 disabled" "$(cat "$T/o8")"

# same item reverted twice for the same new ids
eq "repeat: first revert counts 1" 1 "$(ovn_ri_revert_repeat "$SD" repo h1 $'b\na')"
eq "repeat: same item + same ids (any order) counts 2" 2 "$(ovn_ri_revert_repeat "$SD" repo h1 $'a\nb')"
eq "repeat: same item, DIFFERENT ids restarts at 1 (benign control)" 1 "$(ovn_ri_revert_repeat "$SD" repo h1 $'a\nc')"
eq "repeat: a different item is independent" 1 "$(ovn_ri_revert_repeat "$SD" repo h2 $'a\nb')"
# counters expire and reset on a landed outcome
ovn_ri_revert_repeat "$SD" repo h9 'z' >/dev/null; ovn_ri_revert_repeat "$SD" repo h9 'z' >/dev/null
touch -d '10 days ago' "$SD"/nr_reverts/repo.h9.* 2>/dev/null || touch -t 202001010000 "$SD"/nr_reverts/repo.h9.*
eq "repeat: a counter older than the TTL (7d) restarts at 1" 1 "$(ovn_ri_revert_repeat "$SD" repo h9 'z')"
eq "repeat: ... and counts normally again afterwards (benign control)" 2 "$(ovn_ri_revert_repeat "$SD" repo h9 'z')"
ovn_ri_revert_reset "$SD" repo h9
eq "repeat: reset after a landed outcome restarts at 1" 1 "$(ovn_ri_revert_repeat "$SD" repo h9 'z')"
eq "repeat: reset of one item leaves another item's counter (control)" 2 "$(ovn_ri_revert_repeat "$SD" repo h7 $'a\nb' >/dev/null; ovn_ri_revert_repeat "$SD" repo h7 $'a\nb')"
eq "repeat: empty hash/ids never repeats" 1 "$(ovn_ri_revert_repeat "$SD" repo '' 'a')"

# ============================================================ A6: reachability
OR="$T/origin.git"; git init -q --bare -b main "$OR"; W="$T/clone"; git clone -q "$OR" "$W" 2>/dev/null
( cd "$W" && git checkout -q -b feat && echo a > a && git add a && git commit -q -m base && git push -q origin feat )
( cd "$W" && echo b > b && git add b && git commit -q -m model && git push -q origin feat )
PUSHED="$(git -C "$W" rev-parse HEAD)"
( cd "$W" && ovn_ri_commit_reachable "$PUSHED" feat ) && ok "reachable: a pushed commit is an ancestor of origin/feat" 1 || ok "reachable: a pushed commit is an ancestor of origin/feat" 0
( cd "$W" && echo c > c && git add c && git commit -q -m local-only )
LOCAL="$(git -C "$W" rev-parse HEAD)"
( cd "$W" && ovn_ri_commit_reachable "$LOCAL" feat ) && ok "reachable NEGATIVE: an unpushed commit is NOT reachable" 0 || ok "reachable NEGATIVE: an unpushed commit is NOT reachable" 1
# the real incident: commit made, tree reset to BEFORE, push says "up to date" (exit 0), AFTER is gone from the branch but still in the object db
( cd "$W" && git reset -q --hard "$PUSHED" && git push -q origin feat; echo "push_rc=$?" ) > "$T/p1"
eq "incident fixture: push of a reset tree exits 0" "push_rc=0" "$(cat "$T/p1")"
( cd "$W" && ovn_ri_commit_reachable "$LOCAL" feat ) && ok "incident: the lost commit is detected although push exited 0" 0 || ok "incident: the lost commit is detected although push exited 0" 1
( cd "$W" && git remote set-url origin "$T/nonexistent.git" && ovn_ri_commit_reachable "$LOCAL" feat ) && ok "reachable: fetch failure is UNKNOWN => 0 (a real push is not reclassified on infra errors)" 1 || ok "reachable: fetch failure is UNKNOWN => 0 (a real push is not reclassified on infra errors)" 0
( cd "$W" && git remote set-url origin "$OR" )

# ============================================================ A6: cycle marker / stage runner
export OVN_CYCLE_MARK_MAX_MIN=240
( sleep 60 & echo $! > "$T/sleep.pid"; wait ) >/dev/null 2>&1 &
sleep 0.3; LIVE="$(cat "$T/sleep.pid")"
printf '%s\n' "$LIVE" > "$SD/cycle_active_r1"
ovn_ri_cycle_active "$SD" r1 && ok "cycle-active: live pid marker => active" 1 || ok "cycle-active: live pid marker => active" 0
ovn_ri_cycle_active "$SD" r2 && ok "cycle-active: other repo is not blocked (benign control)" 0 || ok "cycle-active: other repo is not blocked (benign control)" 1
kill "$LIVE" 2>/dev/null; wait 2>/dev/null; for _i in $(seq 1 50); do kill -0 "$LIVE" 2>/dev/null || break; sleep 0.1; done   # poll: a loaded box can take >0.2s to reap
ovn_ri_cycle_active "$SD" r1 && ok "cycle-active: dead pid (stale marker after kill -9) => NOT active" 0 || ok "cycle-active: dead pid (stale marker after kill -9) => NOT active" 1
printf '%s\n' "$$" > "$SD/cycle_active_r3"; touch -t 202001010000 "$SD/cycle_active_r3"
ovn_ri_cycle_active "$SD" r3 && ok "cycle-active: marker older than the max age is ignored" 0 || ok "cycle-active: marker older than the max age is ignored" 1
( ovn_ri_cycle_mark "$SD" r4; echo "$BASHPID" > "$T/markpid" );
ok "cycle-mark: writes the marker" "$([ -f "$SD/cycle_active_r4" ] && echo 1 || echo 0)"
ovn_ri_cycle_unmark "$SD" r4; ok "cycle-unmark: removes it" "$([ ! -f "$SD/cycle_active_r4" ] && echo 1 || echo 0)"
mkdir -p "$T/sr"; printf '#!/bin/bash\nsleep 30\n' > "$T/sr/ovn_stage_runner.sh"; chmod +x "$T/sr/ovn_stage_runner.sh"
( bash "$T/sr/ovn_stage_runner.sh" iptv_apps >/dev/null 2>&1 & echo $! > "$T/sr.pid"; wait ) >/dev/null 2>&1 &
sleep 0.5
ovn_ri_cycle_active "$SD" iptv_apps && ok "cycle-active: a stage runner for the repo is active" 1 || ok "cycle-active: a stage runner for the repo is active" 0
ovn_ri_cycle_active "$SD" billwatch && ok "cycle-active: a stage runner for ANOTHER repo does not block this one" 0 || ok "cycle-active: a stage runner for ANOTHER repo does not block this one" 1
pkill -P "$(cat "$T/sr.pid" 2>/dev/null)" 2>/dev/null; kill "$(cat "$T/sr.pid" 2>/dev/null)" 2>/dev/null; wait 2>/dev/null

# ============================================================ A5: fix-up prompt
. "$Q/scripts/lib_fixup_prompt.sh"; . "$Q/scripts/lib_fixup.sh"
FL="$T/fix.log"; printf 'FAILED tests/old.py::test_old - assert a\nFAILED tests/new.py::test_new - assert b\nE   assert 1 == 2\n' > "$FL"
unset OVN_FIXUP_BASELINE_FILE OVN_FIXUP_BASELINE_VERIFIED
EV0="$(ovn_fixup_failure_facts "$FL" "sum")"
ok "prompt: no baseline => both failing ids listed (old behaviour, byte for byte)" "$(printf '%s' "$EV0" | grep -q 'test_old' && printf '%s' "$EV0" | grep -q 'test_new' && ! printf '%s' "$EV0" | grep -q 'ALREADY failing' && echo 1 || echo 0)"
printf '#result=fail\n#n=1\ntests/old.py::test_old\n' > "$T/base.txt"
export OVN_FIXUP_BASELINE_FILE="$T/base.txt"
EV1="$(ovn_fixup_failure_facts "$FL" "sum")"
ok "prompt NEGATIVE: the pre-existing failing id is NOT in the evidence" "$(printf '%s' "$EV1" | grep -q 'test_old' && echo 0 || echo 1)"
ok "prompt: the NEW failing id is still there" "$(printf '%s' "$EV1" | grep -q 'tests/new.py::test_new' && echo 1 || echo 0)"
ok "prompt: the model is told 1 other test was already failing and to ignore it" "$(printf '%s' "$EV1" | grep -q '1 other test(s) were ALREADY failing' && echo 1 || echo 0)"
cd "$R"
DIRSRC="$(ovn_fixup_direction source-broke-green)"
export OVN_FIXUP_BASELINE_VERIFIED=0
P0="$(ovn_fixup_prompt "H" "$C0" "$C1" "$EV1" "$DIRSRC")"
ok "prompt NEGATIVE: baseline NOT verified => no 'PASSED before' claim" "$(printf '%s' "$P0" | grep -q 'PASSED before' && echo 0 || echo 1)"
ok "prompt: ... it says the failure may be pre-existing" "$(printf '%s' "$P0" | grep -q 'may ALREADY have been failing' && echo 1 || echo 0)"
export OVN_FIXUP_BASELINE_VERIFIED=1
P1="$(ovn_fixup_prompt "H" "$C0" "$C1" "$EV1" "$DIRSRC")"
ok "prompt BENIGN: baseline verified => the original 'PASSED before' direction is kept" "$(printf '%s' "$P1" | grep -q 'PASSED before the committed change' && echo 1 || echo 0)"
unset OVN_FIXUP_BASELINE_VERIFIED OVN_FIXUP_BASELINE_FILE
P2="$(ovn_fixup_prompt "H" "$C0" "$C1" "$EV0" "$DIRSRC")"
ok "prompt: vars unset => unchanged text (fail-safe default)" "$(printf '%s' "$P2" | grep -q 'PASSED before the committed change' && echo 1 || echo 0)"
cd "$T"

# ============================================================ A6: verify clause (GUT)
mkdir -p "$HOME/godot" "$T/w"; cd "$T/w"
cat > "$HOME/godot/godot4" <<'EOF'
#!/bin/bash
echo $(( $(cat "$GLOG.n" 2>/dev/null || echo 0) + 1 )) > "$GLOG.n"
echo "$*" >> "$GLOG"
for a in "$@"; do case "$a" in -gjunit_xml_file=*) f="${a#-gjunit_xml_file=}"; f="${f#res://}"; printf '%s\n' "${FAKE_GUT_XML:-<testsuites failures=\"0\" errors=\"0\"></testsuites>}" > "$f";; esac; done
printf '%b\n' "${FAKE_GUT_OUT:-Failing Tests  0}"
exit "${FAKE_GUT_RC:-0}"
EOF
chmod +x "$HOME/godot/godot4"
export GLOG="$T/godot.log"
. "$Q/scripts/lib_verify_clause.sh"
PROG="$T/prog.md"; SHADOW_LOG="$T/shadow.log"; _REPO_LABEL=fix
vline(){ printf '%s\n' "- [ ] item $2 VERIFY: \`$1\`" > "$PROG"; }
vrun(){ vline "$1" x; shadow_check 1; }
reset_g(){ : > "$GLOG"; rm -f "$GLOG.n"; }
GC='godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests'
reset_g; vrun "$GC -gtest=res://tests/t.gd"
ok "-gexit: appended to a gut_cmdln clause that lacks it" "$(grep -q -- '-gexit' "$GLOG" && echo 1 || echo 0)"
eq "-gexit: verdict PASS on a clean run" PASS "$_LAST_VERIFY_RESULT"
reset_g; vrun "$GC -gtest=res://tests/t.gd -gexit"
eq "-gexit: not duplicated when already present" 1 "$(grep -o -- '-gexit' "$GLOG" | wc -l | tr -d ' ')"
reset_g; vrun "echo hello"
eq "-gexit: a non-GUT clause is untouched (benign control)" PASS "$_LAST_VERIFY_RESULT"
ok "-gexit: ... and never ran godot" "$([ ! -s "$GLOG" ] && echo 1 || echo 0)"
VERIFY_TIMEOUT_SECS=60; VERIFY_TIMEOUT_HEAVY_SECS=900
reset_g; vrun "$GC -gtest=res://tests/t.gd"
eq "timeout: narrowed (-gtest) GUT clause gets ~120s" 120 "$_LAST_VERIFY_TIMEOUT"
reset_g; vrun "$GC"
eq "timeout: the un-narrowed GUT suite keeps the heavy cap (control)" 900 "$_LAST_VERIFY_TIMEOUT"
OVN_VERIFY_GUT_NARROW_SECS=45 vrun "$GC -gtest=res://tests/t.gd"
eq "timeout: narrowed cap is overridable" 45 "$_LAST_VERIFY_TIMEOUT"
# GUT exits 0 on failing tests
FAKE_GUT_OUT='Totals\\nPassing Tests     3\\nFailing Tests     2' vrun "$GC -gtest=res://tests/t.gd"
eq "GUT NEGATIVE: exit 0 but 'Failing Tests 2' => FAIL" FAIL "$_LAST_VERIFY_RESULT"
FAKE_GUT_OUT='  [Failed]:  test_x\\n    expected 1' vrun "$GC -gtest=res://tests/t.gd"
eq "GUT NEGATIVE: exit 0 with a [Failed] line => FAIL" FAIL "$_LAST_VERIFY_RESULT"
# REAL GUT 9.4.0 output captured on the box: ANSI-coloured detail line, summary "  Failing         1" (no word "Tests")
FAKE_GUT_OUT='\033[31m    [Failed]:  expected 1 got 2\n\033[0m  Failing         1' vrun "$GC -gtest=res://tests/t.gd"
eq "GUT NEGATIVE (real 9.4.0 output): ANSI [Failed]: + 'Failing 1', exit 0 => FAIL" FAIL "$_LAST_VERIFY_RESULT"
FAKE_GUT_OUT='  Passing         4\n  Failing         0' vrun "$GC -gtest=res://tests/t.gd"
eq "GUT BENIGN (real format): 'Failing 0' => PASS" PASS "$_LAST_VERIFY_RESULT"
FAKE_GUT_OUT='Totals\\nPassing Tests     5\\nFailing Tests     0' vrun "$GC -gtest=res://tests/t.gd"
eq "GUT BENIGN: 'Failing Tests 0' => PASS" PASS "$_LAST_VERIFY_RESULT"
FAKE_GUT_XML='<testsuites failures="3" errors="0"><testsuite failures="0"></testsuite></testsuites>' vrun "$GC -gjunit_xml_file=res://out.xml"
eq "GUT NEGATIVE: red junit xml (root failures=3) with exit 0 => FAIL" FAIL "$_LAST_VERIFY_RESULT"
FAKE_GUT_XML='<testsuites failures="0" errors="0"><testsuite failures="0"></testsuite></testsuites>' vrun "$GC -gjunit_xml_file=res://out.xml"
eq "GUT BENIGN: green junit xml => PASS" PASS "$_LAST_VERIFY_RESULT"
FAKE_GUT_RC=1 vrun "$GC -gtest=res://tests/t.gd"
eq "GUT: a non-zero exit is still FAIL (unchanged)" FAIL "$_LAST_VERIFY_RESULT"
# dedupe within one call
reset_g; _VC_MEMO=""; _VC_MEMO_ON=1
vline "$GC -gtest=res://tests/t.gd" a; shadow_check 1; r1="$_LAST_VERIFY_RESULT"
vline "$GC -gtest=res://tests/t.gd" b; shadow_check 1; r2="$_LAST_VERIFY_RESULT"
eq "dedupe: identical VERIFY command inside one call runs ONCE" 1 "$(cat "$GLOG.n")"
eq "dedupe: ... and the second item gets the same verdict" "$r1" "$r2"
vline "$GC -gtest=res://tests/other.gd" c; shadow_check 1
eq "dedupe BENIGN control: a DIFFERENT command still runs" 2 "$(cat "$GLOG.n")"
_VC_MEMO_ON=0; _VC_MEMO=""; reset_g
vline "$GC -gtest=res://tests/t.gd" a; shadow_check 1; vline "$GC -gtest=res://tests/t.gd" b; shadow_check 1
eq "dedupe: memo off (every other caller) => both run, as before" 2 "$(cat "$GLOG.n")"
cd "$T"

# ============================================================ A6: qa ledger (landed without commit)
OVN="$T/ovn"; mkdir -p "$OVN/state" "$OVN/repos"; QR="$OVN/repos/fixrepo"; mkdir -p "$QR"
"$PY" - "$QR" "$OVN/state/outcomes.jsonl" <<'PYEOF' || { echo "  FAIL qa fixture"; F=$((F+1)); }
import json, subprocess, sys, time, os
rd, outp = sys.argv[1], sys.argv[2]
def git(*a, when=None):
    env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@t")
    if when: env["GIT_AUTHOR_DATE"] = env["GIT_COMMITTER_DATE"] = "%d +0000" % when
    return subprocess.run(["git", "-C", rd] + list(a), env=env, capture_output=True, text=True, check=True).stdout.strip()
now = int(time.time()); D = 86400
git("init", "-q", "-b", "main")
open(os.path.join(rd, "svc.py"), "w").write("x=1\n"); git("add", "svc.py"); git("commit", "-q", "-m", "feat: real work", when=now - 3 * D)
git("update-ref", "refs/remotes/origin/develop", "HEAD")
iso = lambda e: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(e))
def row(e, ident, h, dur=60):
    return json.dumps({"ts": iso(e), "repo": "fixrepo", "id": ident, "type": "aider_fix", "tier": "2", "category": "endpoint", "class": "landed", "severity": "good",
                       "attempt": 1, "status": "pushed(tests:pass)", "duration_s": dur, "item_hash": h, "feat_tag": ""})
rows = [row(now - 3 * D + 30, "real", "HREAL")]                                       # a commit exists in its window
rows += [row(now - 20 * D + i * 3600, "ghost%d" % i, "HGHOST") for i in range(3)]       # 3 landings of ONE item, no commit anywhere near
rows += [row(now - 12 * D + i * 3600, "two%d" % i, "HTWO") for i in range(2)]           # only 2 repeats: below the alert threshold
open(outp, "w").write("\n".join(rows) + "\n")
PYEOF
qrun(){ env -i PATH="/usr/bin:/bin:$(dirname "$PY")" HOME="$T" NTFY_SERVER=http://127.0.0.1:9 OVN_DIR="$OVN" OVN_REPOS_DIR="$OVN/repos" "$PY" "$@"; }
qrun "$Q/qa/qa_ledger.py" derive --no-record --no-events > "$T/derive.out" 2>&1
LED="$OVN/state/qa_ledger.jsonl"
lq(){ "$PY" - "$LED" "$1" <<'PYEOF'
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1])]
recs = [r for r in recs if r.get("kind") == "landed"]
print(eval(sys.argv[2]))
PYEOF
}
eq "ledger: 6 landed rows became records" 6 "$(lq 'len(recs)')"
eq "ledger BENIGN: the landing with a commit in its window is NOT flagged" "False" "$(lq '"no-commit" in [r for r in recs if r["id"]=="real"][0]["flags"]')"
eq "ledger NEGATIVE: landings with no commit are flagged no-commit" 5 "$(lq 'len([r for r in recs if "no-commit" in r["flags"]])')"
ok "ledger: derive summary reports the no-commit count" "$(grep -q 'NO commit' "$T/derive.out" && echo 1 || echo 0)"
AL="$OVN/state/alerts.log"
eq "alert: exactly ONE line, for the item landed 3x with no commit" 1 "$(grep -c 'qa-ledger:fixrepo' "$AL" 2>/dev/null || echo 0)"
ok "alert: names the 3-times item hash, not the 2-times one (benign control)" "$(grep -q "$("$PY" -c 'print("HGHOST"[:12])')" "$AL" && ! grep -q 'HTWO' "$AL" && echo 1 || echo 0)"
qrun "$Q/qa/qa_ledger.py" derive --no-record --no-events >/dev/null 2>&1
eq "alert: not repeated on the next derive pass (deduped)" 1 "$(grep -c 'qa-ledger:fixrepo' "$AL" 2>/dev/null || echo 0)"
qrun "$Q/qa/qa_scorecard.py" report --days 60 > "$T/report.out" 2>&1
ok "escape report: separate landed-without-commit line (5)" "$(grep -q 'landed-without-commit.*: 5 record' "$T/report.out" && echo 1 || echo 0)"
ok "escape report: no-commit rows are OUT of the feature denominator (1 feature, not 4)" "$(grep -q 'landed records: 1 ' "$T/report.out" && echo 1 || echo 0)"

# ============================================================ A6: ContextWindowExceeded = bad
PYTHONPATH="$Q/scripts" "$PY" - <<'PYEOF' > "$T/bk.out" 2>&1
import ovn_outcome_buckets as b
r_ctx = {"class": "error", "severity": "neutral", "status": "error(model/API error - see log)", "fail_reason": "context-exceeded"}
r_err = {"class": "error", "severity": "neutral", "status": "error(model/API error - see log)", "fail_reason": "api-mismatch"}
r_ok = {"class": "landed", "severity": "good", "status": "pushed(tests:pass)", "fail_reason": "context-exceeded"}
print(b.bucket_from_outcome_row(r_ctx), b.bucket_from_outcome_row(r_err), b.bucket_from_outcome_row(r_ok))
PYEOF
eq "buckets: context-exceeded error = bad; other error = benign (control); a landed row is never re-bucketed" "bad benign good" "$(cat "$T/bk.out")"

# ============================================================ A12: outcomes writer is JSON-safe
OW="$T/ow"; mkdir -p "$OW/tree/state" "$OW/tree/scripts" "$OW/tree/logs" "$OW/tree/reports"
cp "$Q"/scripts/*.sh "$Q"/scripts/*.py "$OW/tree/scripts/" 2>/dev/null; cp "$Q"/*.sh "$Q"/*.py "$OW/tree/" 2>/dev/null; echo '[]' > "$OW/tree/tasks.json"
mkdir -p "$OW/home/aider-venv/bin"; printf '#!/bin/bash\nexit 0\n' > "$OW/home/aider-venv/bin/aider"; printf '#!/bin/bash\necho "{\\"data\\":[{\\"id\\":\\"qwen-dflash-27B\\"}]}"\nexit 0\n' > "$OW/home/aider-venv/bin/curl"; chmod +x "$OW/home/aider-venv/bin/"*
(
  export HOME="$OW/home" OVN_SCRIPT_DIR="$OW/tree" OVN_SOURCE_ONLY=1
  . "$Q/run_overnight.sh" >/dev/null 2>&1
  set +u
  declare -F record_outcome >/dev/null || { echo NOFUNC > "$T/ow.err"; exit 0; }
  STATE_DIR="$OW/tree/state"
  record_outcome "ongoing-x" "repo" 'no-op(rev"erted\red) back\slash {"a":1}' "p" aider_fix 2 "" 33 "" "a\\b"
  record_outcome "ongoing-x" "repo" "$(printf 'line1\nline2\ttab\001ctl')" "p" aider_fix 1 "" 5 ""
  record_outcome "ongoing-x" "repo" 'pushed(tests:pass)' "p" aider_fix notanumber "" abc ""
  record_outcome "id\"quoted" "re\\po" 'pushed' "p" aider_fix 1 "" 1 ""
) 2>/dev/null
OUTF="$OW/tree/state/outcomes.jsonl"
if [ -f "$T/ow.err" ]; then ok "outcomes: record_outcome sourced" 0; else
  eq "outcomes: 4 rows written" 4 "$(wc -l < "$OUTF" | tr -d ' ')"
  "$PY" - "$OUTF" <<'PYEOF' > "$T/ow.res" 2>&1
import json, sys
bad = 0; keys = None; n = 0
for l in open(sys.argv[1]):
    n += 1
    try:
        d = json.loads(l)
    except ValueError:
        bad += 1; continue
    k = list(d)
    keys = keys or k
    if k != keys: bad += 1
print("bad=%d keys=%s attempt_types=%s" % (bad, "ok" if keys and keys[:3] == ["ts", "repo", "id"] and "feat_tag" in keys else keys, sorted(set(type(json.loads(l)["attempt"]).__name__ for l in open(sys.argv[1])))))
PYEOF
  eq "outcomes: every row is valid JSON with the same key order, numeric fields numeric (quotes, backslashes, newline, tab, control byte in the fields)" "bad=0 keys=ok attempt_types=['int']" "$(cat "$T/ow.res")"
fi
# NEGATIVE control: the OLD printf writer really did produce invalid JSON for such a status (proves the fixture catches the bug)
OLDROW="$(printf '{"status":"%s"}' 'a\q')"
"$PY" -c 'import json,sys; json.loads(sys.argv[1])' "$OLDROW" 2>/dev/null && ok "outcomes NEGATIVE control: old printf output with a backslash is invalid JSON" 0 || ok "outcomes NEGATIVE control: old printf output with a backslash is invalid JSON" 1
# readers tolerate the malformed row
printf 'this is {not json\n' >> "$OUTF"
"$PY" "$Q/scripts/ovn_tier_stats.py" --help >/dev/null 2>&1 || true
env -i PATH="/usr/bin:/bin:$(dirname "$PY")" HOME="$T" OVN_DIR="$OW/tree" OVN_REPOS_DIR="$OW/tree/repos" QA_STATE_DIR="$OW/tree/state" "$PY" "$Q/qa/qa_ledger.py" derive --no-record --no-events > "$T/rd.out" 2>&1; rrc=$?
ok "readers: qa_ledger derive survives the malformed row (rc 0, counts it, verdict FLAG not a crash)" "$([ $rrc -eq 0 ] && grep -qE '"bad_json": ?1' "$T/rd.out" && echo 1 || echo 0)"

echo "  $P passed, $F failed"; [ "$F" = 0 ]
