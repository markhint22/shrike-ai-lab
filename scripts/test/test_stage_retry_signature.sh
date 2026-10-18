#!/usr/bin/env bash
# N4 stage-runner-waste, Part 2 (2026-10-13): SAME-SIGNATURE STOP + STRUCTURED PRIORFAIL in ovn_stage_runner.sh.
# 48-72h of staged runs: attempt 1 verified 24/47 items, the 2nd inline attempt 2/23, the 3rd 3/20, and the failure was often IDENTICAL run to run (iptv test_content_history_returns_429_after_120_requests_per_minute x3,
# TAA the same 4 failing ids x2, shrike-notify x2, iptv ModuleNotFoundError app.core.rate_limit x2). A retry that fails exactly like the last one costs ~200k tokens for nothing.
#   Part U (unit, python only - runs anywhere): stage_fail_signature / stage_priorfail_block extracted from the REAL runner (between the n4-stage-waste markers) and fed fixture verify.log / jsonl pairs.
#   Part E (end to end, GNU sed + bash 5 = the box): the REAL runner in the hermetic fixture, two zero-landing runs in a row.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
unset OVN_BUG_FIRST OVN_BUG_ATTEMPT_CAP OVN_STAGE_ZERO_CAP OVN_STAGE_SAME_SIG_STOP OVN_STAGE_PRIORFAIL_STEP NTFY_SERVER NTFY_TOPIC
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"; osr_cleanup' EXIT
sed -n '/^# >>> n4-stage-waste helpers: retry signature/,/^# <<< n4-stage-waste helpers: retry signature/p' "$RUNNER" > "$W/helpers.sh"
[ -s "$W/helpers.sh" ] || { echo "  FAIL: the retry-signature helper block was not found in $RUNNER"; exit 1; }
# shellcheck disable=SC1091
. "$W/helpers.sh"
SIG(){ stage_fail_signature "$1" "$2"; }

echo "== U: signature identity"
cat > "$W/v1.log" <<'LOG'
2026-10-13 15:15:37 independent full-verify (combined result)
-- pytest FULL in backend --
..........F.F
=================================== FAILURES ===================================
_______________ test_content_history_returns_429_after_120_requests _______________
    def test_content_history_returns_429_after_120_requests():
>       assert resp.status_code == 429
E       assert 200 == 429
tests/test_history.py:44: AssertionError
=========================== short test summary info ============================
FAILED tests/test_history.py::test_content_history_returns_429_after_120_requests - assert 200 == 429
FAILED tests/test_other.py::test_b - AssertionError: nope
2 failed, 1400 passed in 61.02s (0:01:01)
LOG
# same failure, different timing / timestamp / pass count
sed -e 's/15:15:37/18:02:11/' -e 's/61.02s/58.77s/' -e 's/1400 passed/1401 passed/' "$W/v1.log" > "$W/v1b.log"
# one failing id differs
sed -e 's/test_other.py::test_b/test_other.py::test_c/' "$W/v1.log" > "$W/v2.log"
# one id fewer
grep -v 'test_other.py::test_b' "$W/v1.log" > "$W/v3.log"
: > "$W/none.jsonl"
s1="$(SIG "$W/v1.log" "$W/none.jsonl")"; s1b="$(SIG "$W/v1b.log" "$W/none.jsonl")"; s2="$(SIG "$W/v2.log" "$W/none.jsonl")"; s3="$(SIG "$W/v3.log" "$W/none.jsonl")"
t "U1 a signature is produced (16 hex)" bash -c "[[ '$s1' =~ ^[0-9a-f]{16}$ ]]"
t "U2 the SAME failure with different timestamps/timings/pass counts has the SAME signature" test "$s1" = "$s1b"
t "U3 a different failing test id => a different signature" test "$s1" != "$s2"
t "U4 one failing id fewer => a different signature" test "$s1" != "$s3"
# order of the failing ids must not matter
{ grep -v '^FAILED' "$W/v1.log"; grep '^FAILED' "$W/v1.log" | sort -r; } > "$W/v1r.log"
t "U5 the order of the FAILED lines does not change the signature" test "$s1" = "$(SIG "$W/v1r.log" "$W/none.jsonl")"
printf -- '-- QUALITY FAIL: backend/tests/test_auth_register_audit.py is a 0-byte file - not a real implementation or test --\n-- SEMANTIC FAIL: x.py only defines (or never uses) y --\n' > "$W/q1.log"
printf -- '-- QUALITY FAIL: backend/tests/test_auth_register_audit.py is a 0-byte file - not a real implementation or test --\n-- SEMANTIC FAIL: x.py only defines (or never uses) y --\n' > "$W/q1b.log"
printf -- '-- QUALITY FAIL: backend/tests/test_other.py is a 0-byte file - not a real implementation or test --\n' > "$W/q2.log"
t "U6 identical QUALITY+SEMANTIC lines => same signature, a different file => different" bash -c "[ -n '$(SIG "$W/q1.log" "$W/none.jsonl")' ] && [ '$(SIG "$W/q1.log" "$W/none.jsonl")' = '$(SIG "$W/q1b.log" "$W/none.jsonl")' ] && [ '$(SIG "$W/q1.log" "$W/none.jsonl")' != '$(SIG "$W/q2.log" "$W/none.jsonl")' ]"
printf 'E   ModuleNotFoundError: No module named '"'"'app.core.rate_limit'"'"'\n' > "$W/m1.log"
printf '12:00 something else\nE   ModuleNotFoundError: No module named '"'"'app.core.rate_limit'"'"'\n' > "$W/m1b.log"
printf 'E   ModuleNotFoundError: No module named '"'"'app.core.other'"'"'\n' > "$W/m2.log"
t "U7 ModuleNotFoundError text is part of the signature (same module = same, other module = different)" bash -c "[ -n '$(SIG "$W/m1.log" "$W/none.jsonl")' ] && [ '$(SIG "$W/m1.log" "$W/none.jsonl")' = '$(SIG "$W/m1b.log" "$W/none.jsonl")' ] && [ '$(SIG "$W/m1.log" "$W/none.jsonl")' != '$(SIG "$W/m2.log" "$W/none.jsonl")' ]"
t "U8 no recognisable evidence => EMPTY signature (an empty signature never stops a retry)" bash -c "[ -z '$(SIG "$W/none.jsonl" "$W/none.jsonl")' ] && [ -z '$(SIG "$W/missing.log" "$W/missing.jsonl")' ]"
printf 'random aider chatter\nTokens: 2k sent\n' > "$W/noise.log"
t "U9 a verify log with no failing ids / checks => EMPTY signature" bash -c "[ -z '$(SIG "$W/noise.log" "$W/none.jsonl")' ]"

echo "== U: step-blocked runs (no verify evidence): fail_reason + files + undeclared set"
mkrows(){  # $1=out $2=reason $3=files $4=excerpt
  { printf '{"run":"r","step":0,"files":"%s","attempt":1,"verdict":"fail","fail_reason":"%s","excerpt":"%s"}\n' "$3" "$2" "$4"
    printf '{"run":"r","step":0,"files":"%s","attempt":2,"verdict":"fail","fail_reason":"%s","excerpt":"%s"}\n' "$3" "$2" "$4"
    printf '{"run":"r","step":0,"verdict":"blocked"}\n'; } > "$1"; }
EX1='multifile:no step touched undeclared file(s): iptv-web/src/stores/recordings.ts iptv-web/src/__tests__/recordings.test.ts (declared: iptv-web/src/views/RecordingsView.vue)'
EX2='multifile:no step touched undeclared file(s): iptv-web/src/stores/other.ts (declared: iptv-web/src/views/RecordingsView.vue)'
mkrows "$W/b1.jsonl" scope-violation "iptv-web/src/views/RecordingsView.vue" "$EX1"
mkrows "$W/b1b.jsonl" scope-violation "iptv-web/src/views/RecordingsView.vue" "$EX1"
mkrows "$W/b2.jsonl" scope-violation "iptv-web/src/views/RecordingsView.vue" "$EX2"
mkrows "$W/b3.jsonl" no-edit "iptv-web/src/views/RecordingsView.vue" "x"
mkrows "$W/b4.jsonl" scope-violation "iptv-web/src/views/OtherView.vue" "$EX1"
t "U10 same blocked-step reasons + same undeclared set => same signature" bash -c "[ -n '$(SIG "$W/none.jsonl" "$W/b1.jsonl")' ] && [ '$(SIG "$W/none.jsonl" "$W/b1.jsonl")' = '$(SIG "$W/none.jsonl" "$W/b1b.jsonl")' ]"
t "U11 a different undeclared set => different signature" bash -c "[ '$(SIG "$W/none.jsonl" "$W/b1.jsonl")' != '$(SIG "$W/none.jsonl" "$W/b2.jsonl")' ]"
t "U12 a different fail_reason => different signature" bash -c "[ '$(SIG "$W/none.jsonl" "$W/b1.jsonl")' != '$(SIG "$W/none.jsonl" "$W/b3.jsonl")' ]"
t "U13 a different step target (the plan changed) => different signature" bash -c "[ '$(SIG "$W/none.jsonl" "$W/b1.jsonl")' != '$(SIG "$W/none.jsonl" "$W/b4.jsonl")' ]"
# a step that failed once but then PASSED (no blocked row) is not evidence of a stuck item
{ printf '{"run":"r","step":0,"files":"a.py","attempt":1,"verdict":"fail","fail_reason":"no-edit","excerpt":""}\n'; printf '{"run":"r","step":0,"files":"a.py","attempt":2,"verdict":"pass","fail_reason":""}\n'; } > "$W/ok.jsonl"
t "U14 a step that failed once and then passed (no blocked row) contributes no evidence" bash -c "[ -z '$(SIG "$W/none.jsonl" "$W/ok.jsonl")' ]"
t "U15 verify-log evidence wins over step evidence (the verify identity is what matters)" bash -c "[ '$(SIG "$W/v1.log" "$W/b1.jsonl")' = '$(SIG "$W/v1.log" "$W/b3.jsonl")' ]"

echo "== U: structured priorfail block"
blk="$(stage_priorfail_block "$W/v1.log" "$W/none.jsonl")"
t "U16 names the failing test ids" bash -c "grep -q 'test_content_history_returns_429_after_120_requests' <<< '$blk' && grep -q 'test_other.py::test_b' <<< '$blk'"
t "U17 carries the first assertion line of each" bash -c "grep -q 'assert 200 == 429' <<< '$blk' && grep -q 'AssertionError: nope' <<< '$blk'"
{ echo '-- pytest FULL --'; for i in 1 2 3 4 5 6 7 8 9; do echo "FAILED tests/test_many.py::test_n$i - assert $i == 0"; done; } > "$W/many.log"
mb="$(stage_priorfail_block "$W/many.log" "$W/none.jsonl")"
t "U18 at most 6 failing ids are listed (and the total is stated)" bash -c "[ \"\$(grep -c '^- tests/test_many.py' <<< '$mb')\" = 6 ] && grep -q '(9, showing up to 6)' <<< '$mb'"
printf -- '-- QUALITY FAIL: a.py is a 0-byte file --\n-- SEMANTIC FAIL: b.py never uses c --\n' > "$W/qs.log"
qb="$(stage_priorfail_block "$W/qs.log" "$W/none.jsonl")"
t "U19 carries the QUALITY and SEMANTIC lines" bash -c "grep -q 'QUALITY FAIL: a.py is a 0-byte file' <<< '$qb' && grep -q 'SEMANTIC FAIL: b.py never uses c' <<< '$qb'"
sb="$(stage_priorfail_block "$W/none.jsonl" "$W/b1.jsonl")"
t "U20 a step-blocked run lists the blocked reason and the undeclared files" bash -c "grep -q 'blocked step: scope-violation' <<< '$sb' && grep -q 'iptv-web/src/stores/recordings.ts' <<< '$sb' && grep -q 'iptv-web/src/__tests__/recordings.test.ts' <<< '$sb'"
printf 'FAILED tests/test_db.py::test_c - OperationalError: could not connect to postgresql://appuser:s3cr3tPassw0rd@db.internal:5432/prod token=abcd1234efgh5678 Bearer eyAbCdEf0123456789xyz\n' > "$W/sec.log"
eb="$(stage_priorfail_block "$W/sec.log" "$W/none.jsonl")"
t "U21 credentials are scrubbed from the block (it is stored and fed to a prompt)" bash -c "! grep -qE 's3cr3tPassw0rd|abcd1234efgh5678|eyAbCdEf0123456789xyz' <<< '$eb' && grep -q 'test_db.py::test_c' <<< '$eb'"
t "U22 no evidence => no block" bash -c "[ -z '$(stage_priorfail_block "$W/noise.log" "$W/none.jsonl")' ]"
{ echo '=================================== FAILURES ==================================='; echo '_______________ test_x _______________'; echo 'E       assert 3 == 4'; echo '=== short test summary info ==='; echo 'FAILED tests/test_z.py::test_x'; } > "$W/long.log"
t "U23 a FAILED line without ' - msg' takes the first E-line of its traceback section" bash -c "grep -q 'assert 3 == 4' <<< '$(stage_priorfail_block "$W/long.log" "$W/none.jsonl")'"

if ! sed --version >/dev/null 2>&1; then echo "  (Part E skipped: needs GNU sed; run on the box)"; osr_summary; _s=$?; [ "$_s" -ne 0 ] && exit "$_s"; echo "  NOT RUN: Part E needs GNU sed (run on the box)"; exit 77; fi

echo "== E: the real runner, two zero-landing runs in a row"
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
PLAN='[{"desc":"add foo helper","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
PLAN_B='[{"desc":"add foo helper differently","files":["backend/app/foo.py","backend/tests/test_foo_b.py"],"verify":"pytest backend/tests/test_foo_b.py"}]'
prog(){ git -C "$O" show overnight/feature:OVERNIGHT_PROGRESS.md; }
pyfail(){ # $1 = text the stub pytest prints (and exits 1 with) on the full run
  printf '%s\n' "$1" > "$OSR_SCN/pytest.out"
  printf '#!/usr/bin/env bash\ncat "$OSR_SCN/pytest.out"\nexit 1\n' > "$RD/backend/.venv/bin/pytest"; chmod +x "$RD/backend/.venv/bin/pytest"; }
nextrun(){ rm -f "$T/llm/n" "$T/scn/aider.n" "$T"/llm/body.* "$T"/scn/aider.args.*; }
setup(){ osr_new; osr_venv backend; cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/" 2>/dev/null; osr_progress "- [ ] $ITEM_PY"; osr_plan default "$PLAN"; osr_aider default "$SNIP_FOO"; }
FAIL_A='FAILED backend/tests/test_foo.py::test_a - assert 1 == 2
FAILED backend/tests/test_foo.py::test_b - AssertionError: nope'
FAIL_B='FAILED backend/tests/test_foo.py::test_zzz - assert 5 == 6'

echo "-- E1: OVN_STAGE_SAME_SIG_STOP=on: run 1 fails, run 2 fails IDENTICALLY -> escalated at once (no attempt 3 of 3)"
setup; pyfail "$FAIL_A"
OVN_STAGE_SAME_SIG_STOP=on OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1a run 1: item stays open (attempt 1/3), a signature is recorded" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE' && ls '$Q'/state/item_fails/stage-$OSR_REPO.*.lastsig >/dev/null 2>&1"
t "E1b run 1: priorfail is STRUCTURED (header + the failing test ids + the assertion text)" bash -c "f=\$(ls '$Q'/state/item_fails/stage-$OSR_REPO.*.priorfail); grep -q 'attempt 1 of 3' \$f && grep -q 'test_foo.py::test_a' \$f && grep -q 'test_foo.py::test_b' \$f && grep -q 'assert 1 == 2' \$f"
nextrun
OVN_STAGE_SAME_SIG_STOP=on OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1c run 2's decomposition prompt carries the failing test ids" bash -c "grep -l 'PREVIOUS ATTEMPT' '$T'/llm/body.* | head -1 | xargs grep -q 'test_foo.py::test_a'"
t "E1d run 2's STEP prompt (aider --message) carries the previous failure too" bash -c "grep -q 'PREVIOUS STAGED RUN AT THIS TASK FAILED' '$T/scn/aider.args.1' && grep -q 'test_foo.py::test_a' '$T/scn/aider.args.1'"
t "E1e run 2: same signature => ESCALATED to Claude although only 2 of 3 attempts were used" bash -c "prog_out=\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md); echo \"\$prog_out\" | grep -q 'AUTO-SKIP staged: 27B could not land this'"
t "E1f the same_signature_stop event is journaled and the run says why" bash -c "grep -q 'same failure signature as the previous staged run' '$T/out.txt' && grep -q '\"event\":\"same_signature_stop\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
t "E1g counters (zerocount/priorfail/lastsig) cleared after the routing" bash -c "! ls '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount '$Q'/state/item_fails/stage-$OSR_REPO.*.priorfail '$Q'/state/item_fails/stage-$OSR_REPO.*.lastsig >/dev/null 2>&1"
osr_cleanup

echo "-- E2: run 2 fails DIFFERENTLY -> the retry budget still applies (control)"
setup; pyfail "$FAIL_A"
OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
nextrun; pyfail "$FAIL_B"
OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E2a a changed failing id keeps the item OPEN (attempt 2/3), not routed" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE' && grep -q 'attempt 2/3: item stays OPEN' '$T/out.txt'"
t "E2b zerocount is 2 and no same_signature_stop was journaled" bash -c "[ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount)\" = 2 ] && ! grep -q same_signature_stop '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup

echo "-- E3: OVN_STAGE_SAME_SIG_STOP=off = the old budget (identical failure still gets attempt 2/3)"
setup; pyfail "$FAIL_A"
OVN_STAGE_SAME_SIG_STOP=off OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
nextrun
OVN_STAGE_SAME_SIG_STOP=off OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E3a identical failure + stop OFF: still OPEN at attempt 2/3" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE' && grep -q 'attempt 2/3: item stays OPEN' '$T/out.txt'"
osr_cleanup

echo "-- E3b: OVN_STAGE_SAME_SIG_STOP=shadow logs the would-stop event but still retries"
setup; pyfail "$FAIL_A"
OVN_STAGE_SAME_SIG_STOP=shadow OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
nextrun
OVN_STAGE_SAME_SIG_STOP=shadow OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E3b shadow: identical failure -> SHADOW line + mode:shadow event, the item stays OPEN at attempt 2/3" bash -c "grep -q 'SHADOW: would escalate now' '$T/out.txt' && grep -q '\"event\":\"same_signature_stop\",\"mode\":\"shadow\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE' && grep -q 'attempt 2/3: item stays OPEN' '$T/out.txt'"
osr_cleanup

echo "-- E4: step-blocked runs (no-edit twice, identical plan) are stopped; a changed plan is not"
setup; osr_aider default 'echo "I looked at it, nothing to change"'
OVN_STAGE_SAME_SIG_STOP=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E4a run 1 (no-edit): open, a step-based signature is recorded" bash -c "ls '$Q'/state/item_fails/stage-$OSR_REPO.*.lastsig >/dev/null 2>&1 && grep -q 'attempt 1/3: item stays OPEN' '$T/out.txt'"
nextrun
OVN_STAGE_SAME_SIG_STOP=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E4b run 2 (same no-edit on the same files) => escalated, not a 3rd attempt" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged: 27B could not land this' && grep -q same_signature_stop '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
setup; osr_aider default 'echo "I looked at it, nothing to change"'
OVN_STAGE_SAME_SIG_STOP=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
nextrun; osr_plan default "$PLAN_B"
OVN_STAGE_SAME_SIG_STOP=on OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E4c run 2 with a DIFFERENT plan (other target files) keeps the item open" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE' && grep -q 'attempt 2/3: item stays OPEN' '$T/out.txt'"
osr_cleanup

echo "-- E1h: DEFAULT (var unset) is SHADOW: an identical failure is only logged, the item stays open (7 of 67 historical same-signature repeats landed next run)"
setup; pyfail "$FAIL_A"
OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
nextrun
OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E1h default: SHADOW line + mode:shadow event, NOT mode:on, item OPEN at attempt 2/3 and not routed to Claude" bash -c "grep -q 'SHADOW: would escalate now' '$T/out.txt' && grep -q '\"event\":\"same_signature_stop\",\"mode\":\"shadow\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && ! grep -q '\"mode\":\"on\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && grep -q 'attempt 2/3: item stays OPEN' '$T/out.txt' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE'"
osr_cleanup

echo "-- E1i: the kill switch is case-insensitive and accepts 0/false/no (before: OFF / 0 / false fell through to ENFORCING mode)"
for _kv in OFF 0; do
  setup; pyfail "$FAIL_A"
  OVN_STAGE_SAME_SIG_STOP=$_kv OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
  nextrun
  OVN_STAGE_SAME_SIG_STOP=$_kv OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
  t "E1i OVN_STAGE_SAME_SIG_STOP=$_kv: no same_signature_stop event of any mode, item OPEN at attempt 2/3, not routed to Claude" bash -c "! grep -q same_signature_stop '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl && ! grep -q 'would escalate now' '$T/out.txt' && grep -q 'attempt 2/3: item stays OPEN' '$T/out.txt' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE'"
  osr_cleanup
done

echo "-- E6: a zero-landing run with NO recognisable evidence clears the recorded signature (no stale match against a later, non-adjacent run)"
setup; pyfail "$FAIL_A"
OVN_STAGE_SAME_SIG_STOP=on OVN_STAGE_ZERO_CAP=6 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E6a run 1 recorded a signature" bash -c "ls '$Q'/state/item_fails/stage-$OSR_REPO.*.lastsig >/dev/null 2>&1"
nextrun; pyfail "random aider chatter, no failing ids"
OVN_STAGE_SAME_SIG_STOP=on OVN_STAGE_ZERO_CAP=6 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E6b run 2 (no evidence) leaves the item open and CLEARS lastsig" bash -c "grep -q 'attempt 2/6: item stays OPEN' '$T/out.txt' && ! ls '$Q'/state/item_fails/stage-$OSR_REPO.*.lastsig >/dev/null 2>&1"
nextrun; pyfail "$FAIL_A"
OVN_STAGE_SAME_SIG_STOP=on OVN_STAGE_ZERO_CAP=6 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E6c run 3 fails like run 1 but run 1 is not ADJACENT: no same-signature stop, item still open at 3/6" bash -c "! grep -q 'same failure signature' '$T/out.txt' && grep -q 'attempt 3/6: item stays OPEN' '$T/out.txt' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qE 'AUTO-SKIP|CLAUDE'"
osr_cleanup

echo "-- E5: a run that LANDS clears the signature"
setup; pyfail "$FAIL_A"
OVN_VERIFY_REPAIR_ROUNDS=0 OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
nextrun; osr_venv backend
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "E5a a landing run removes lastsig/priorfail/zerocount" bash -c "grep -q 'DONE: 1/1 steps landed' '$T/out.txt' && ! ls '$Q'/state/item_fails/stage-$OSR_REPO.*.lastsig '$Q'/state/item_fails/stage-$OSR_REPO.*.priorfail '$Q'/state/item_fails/stage-$OSR_REPO.*.zerocount >/dev/null 2>&1"
osr_cleanup
osr_summary
