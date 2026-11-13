#!/usr/bin/env bash
# test_q_suite_fix.sh - package q-suite-fix (2026-11-13): the 08:36 CST suite-cron red rows.
#   A. test_run_all_skip77.sh leaked its fixture suites (bad.sh ...) into a real OVN_SUITE_CAPTURE_DIR/failed.tsv -> five bogus "suite FAILED bad.sh" alerts.log INFO rows
#   B. lint: no test that extracts/executes run_all.sh pieces may run without neutralising OVN_SUITE_CAPTURE_DIR; ops/suite_run_log.py also drops these fixture names
#   C. test_stage_new_tests.sh `pushed()` was `git log | grep -q` under pipefail = SIGPIPE flake ("FAIL kill switch: pushed" only under load)
#   D. the fail-fast red verify log carries a "-- pytest FAIL-FAST in <pkg> --" section so qa/baseline_verify.py (shadow hook) still sees the red ids; a green early run gets none
# Mutants: M1 skip77 without the unset, M2 lint-bad test copy, M3 pipe form of pushed(), M4 parser regex without FAIL-FAST, M5 runner without the header insertion.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
[ -f "$HERE/ntfy_guard.sh" ] && . "$HERE/ntfy_guard.sh"
export TZ=UTC OVN_NOTIFY_DISABLE=1 NTFY_SERVER=http://127.0.0.1:9 OVN_QA_SHADOW=off OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0
unset OVN_SUITE_CAPTURE_DIR OVN_VERIFY_FAILFAST_HEADER OVN_VERIFY_FAILFAST_OWN_TESTS OVN_RUN_NEW_TESTS 2>/dev/null || true
SRC="$(cd "$HERE/../.." && pwd)"
SB="$(safe_mktemp_dir qsf)" || exit 1; trap 'safe_rm_rf "$SB"; osr_cleanup' EXIT
PY="$(command -v python3.12 || command -v python3)"; export PY
mutate(){ # <src> <dst> <python-old> <python-new> : exact-once replace
  OLD="$3" NEW="$4" S="$1" D="$2" "$PY" -I - <<'PYEOF'
import os,sys
s=open(os.environ['S']).read(); o=os.environ['OLD']
if s.count(o)!=1: sys.exit(1)
open(os.environ['D'],'w').write(s.replace(o,os.environ['NEW'],1))
PYEOF
}

echo "== A. test_run_all_skip77.sh does not write fixture suites into a real capture dir"
mkdir -p "$SB/cap"
( cd "$SB" && OVN_SUITE_CAPTURE_DIR="$SB/cap" RA_NO_MUTANTS=1 bash "$HERE/test_run_all_skip77.sh" >/dev/null 2>&1 )
t "A1 failed.tsv stays empty with a real OVN_SUITE_CAPTURE_DIR exported" bash -c "[ ! -s '$SB/cap/failed.tsv' ]"
mkdir -p "$SB/m1" "$SB/cap2"; cp "$HERE"/*.sh "$HERE"/*.py "$SB/m1/" 2>/dev/null; mkdir -p "$SB/m1/../../ops" 2>/dev/null
# the mutant copy needs the same relative layout (HERE/../.. = SRC); run it with RA_SRC pointing at the real tree
mutate "$HERE/test_run_all_skip77.sh" "$SB/m1/test_run_all_skip77.sh" $'\nunset OVN_SUITE_CAPTURE_DIR\n' $'\n:\n'
( cd "$SB" && OVN_SUITE_CAPTURE_DIR="$SB/cap2" RA_SRC="$SRC" RA_NO_MUTANTS=1 bash "$SB/m1/test_run_all_skip77.sh" >/dev/null 2>&1 )
t "M1 mutant (unset removed): the fixtures DO pollute failed.tsv (A1 would fail)" bash -c "grep -q fx77_bad.sh '$SB/cap2/failed.tsv'"

echo "== B. lint: tests touching run_all pieces neutralise OVN_SUITE_CAPTURE_DIR"
lint_leaks(){ # <dir> : print test files that extract/run run_all.sh pieces without handling the capture dir
  local f
  for f in "$1"/test_*.sh; do
    [ "$(basename "$f")" = "test_q_suite_fix.sh" ] && continue
    grep -qE "_ovn_note_fail|_ovn_run_suite|\^finish\(\)|(^|[ ;(\"'])bash +run_all\.sh" "$f" 2>/dev/null || continue
    grep -qE "unset OVN_SUITE_CAPTURE_DIR|-u OVN_SUITE_CAPTURE_DIR|OVN_SUITE_CAPTURE_DIR=|env -i" "$f" || echo "$(basename "$f")"
  done
}
LK="$(lint_leaks "$HERE")"
t "B1 no test file extracts/runs run_all.sh without handling OVN_SUITE_CAPTURE_DIR (offenders: ${LK:-none})" test -z "$LK"
mkdir -p "$SB/lint"; cp "$HERE/test_run_all_skip77.sh" "$SB/lint/"; sed -i.bak '/^unset OVN_SUITE_CAPTURE_DIR$/d' "$SB/lint/test_run_all_skip77.sh"
# strip the other mentions too so the mutant is a genuinely unhandled file
sed -i.bak 's/OVN_SUITE_CAPTURE_DIR=//g; s/env -i//g' "$SB/lint/test_run_all_skip77.sh"
t "M2 mutant (unset removed): the lint flags it" bash -c "[ \"\$($(declare -f lint_leaks); lint_leaks '$SB/lint')\" = test_run_all_skip77.sh ]"
t "B2 ops/suite_run_log.py FIXTURE_SUITES also names the skip77 fixtures" bash -c "grep -q '\"fx77_bad.sh\"' '$SRC/ops/suite_run_log.py' && grep -q '\"fx77_skip.sh\"' '$SRC/ops/suite_run_log.py'"

echo "== C. pushed() in test_stage_new_tests.sh survives SIGPIPE (pipefail)"
TS="$HERE/test_stage_new_tests.sh"
t "C1 no 'git ... log | grep' pipeline left in test_stage_new_tests.sh" bash -c "! grep -E 'git .*log[^|#]*\\| *grep' '$TS' | grep -v '^#' | grep -q ."
pushed_pass(){ # <test file>: source its pushed() with a git stub whose output is slow (grep -q would have exited) ; rc of pushed
  ( set -uo pipefail; O=/nonexistent
    eval "$(sed -n '/^origin_subjects(){/p;/^pushed(){/p' "$1")"
    git(){ echo "feat(osrrepo): staged step 0 - add foo helper"; sleep 0.4; echo seed; }
    pushed ) 2>/dev/null
}
t "C2 the real pushed() finds the commit even when git log keeps writing after the match" pushed_pass "$TS"
mutate "$TS" "$SB/ts_mut.sh" "pushed(){ local l; l=\"\$(origin_subjects)\"; grep -q 'staged step 0' <<<\"\$l\"; }" "pushed(){ git -C \"\$O\" log --format=%s overnight/feature | grep -q 'staged step 0'; }"
t "M3 mutant (pipe form): pushed() reads as not-pushed under pipefail (C2 would fail)" bash -c "$(declare -f pushed_pass); ! pushed_pass '$SB/ts_mut.sh'"

echo "== D. fail-fast red verify log is parseable by the baseline tool"
FF="$SB/ff.verify.log"
printf '%s\n' "-- fail-fast: cycle's own new/changed test files first (timeout 120s) --" "-- pytest FAIL-FAST in backend (the cycle's own test files only; the full suite was skipped) --" \
  "-- new/changed python tests (explicit run): tests/test_old.py --" "=========================== short test summary info ===========================" \
  "FAILED tests/test_old.py::test_old_red - AssertionError: boom" "1 failed, 4 passed in 0.50s" "-- NEW-TESTS RED: explicit run of new/changed python test file(s) failed (pytest rc=1) --" \
  "-- FAIL-FAST: the cycle's own test file(s) are red; skipping the full suite (OVN_VERIFY_FAILFAST_OWN_TESTS=off restores the full run) --" > "$FF"
parse_ids(){ "$PY" -I - "$1" "$2" <<'PYEOF'
import sys; sys.path.insert(0, sys.argv[2])
import baseline_verify as b
r = b.parse_verify_log(open(sys.argv[1]).read())
print(",".join(sorted(r["ids"])), "|", ",".join(r.get("kinds", [])))
PYEOF
}
t "D1 parse_verify_log returns the red id with its [pkg] prefix and a pytest stage" bash -c "[ \"\$($(declare -f parse_ids); parse_ids '$FF' '$SRC/qa')\" = '[backend] tests/test_old.py::test_old_red | pytest' ]"
t "D2 detect_format picks verify-log for it" "$PY" -I -c "import sys; sys.path.insert(0,'$SRC/qa'); import baseline_verify as b; sys.exit(0 if b.detect_format(open('$FF').read())=='verify-log' else 1)"
mkdir -p "$SB/qa_mut"; cp "$SRC/qa/baseline_verify.py" "$SB/qa_mut/"
mutate "$SRC/qa/baseline_verify.py" "$SB/qa_mut/baseline_verify.py" 'r"^-- (pytest (?:FULL|FAIL-FAST) in (\S+)|' 'r"^-- (pytest FULL in (\S+)|'
t "M4 mutant (parser without FAIL-FAST): the red id is lost (D1 would fail)" bash -c "[ \"\$($(declare -f parse_ids); parse_ids '$FF' '$SB/qa_mut')\" != '[backend] tests/test_old.py::test_old_red | pytest' ]"

echo "== D3. the real runner: header on a fail-fast RED only"
base(){ osr_new; osr_venv backend; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"; }
vlg(){ osr_vlog; }
base; echo "failfile:tests/test_foo.py" > "$T/scn/pytest.mode"; osr_run "$OSR_REPO" "$ITEM_PY"
t "D3a red own test: verify log has the FAIL-FAST pytest section naming the package" bash -c "$(declare -f vlg osr_vlog); Q='$Q'; OSR_REPO='$OSR_REPO'; vlg | grep -q '^-- pytest FAIL-FAST in backend'"
t "D3b ...and it sits between the fail-fast start line and the explicit-run output" bash -c "$(declare -f vlg osr_vlog); Q='$Q'; OSR_REPO='$OSR_REPO'; vlg | grep -v '^\$' | awk '/^-- fail-fast: /{a=NR} /^-- pytest FAIL-FAST in /{b=NR} /new\\/changed python tests \\(explicit run\\)/{c=NR} END{exit !(a&&b&&c&&a<b&&b<c)}'"
osr_cleanup
base; osr_run "$OSR_REPO" "$ITEM_PY"
t "D3c green own test: no FAIL-FAST section (the real FULL section follows)" bash -c "$(declare -f vlg osr_vlog); Q='$Q'; OSR_REPO='$OSR_REPO'; ! vlg | grep -q 'pytest FAIL-FAST'"
osr_cleanup
base; echo "failfile:tests/test_foo.py" > "$T/scn/pytest.mode"; OVN_VERIFY_FAILFAST_HEADER=off osr_run "$OSR_REPO" "$ITEM_PY"
t "D3d OVN_VERIFY_FAILFAST_HEADER=off restores the unlabeled log" bash -c "$(declare -f vlg osr_vlog); Q='$Q'; OSR_REPO='$OSR_REPO'; ! vlg | grep -q 'pytest FAIL-FAST'"
osr_cleanup
mutate "$SRC/ovn_stage_runner.sh" "$SB/runner_mut.sh" 'NR==n{print h}' 'NR==n{}'
base; echo "failfile:tests/test_foo.py" > "$T/scn/pytest.mode"
RUNNER="$SB/runner_mut.sh"; chmod +x "$RUNNER"   # libs resolve from $HOME/overnight-queue (the fixture tree), so the mutant runs fine from SB
osr_run "$OSR_REPO" "$ITEM_PY"
t "M5 mutant (header insertion dropped): no section (D3a would fail)" bash -c "$(declare -f vlg osr_vlog); Q='$Q'; OSR_REPO='$OSR_REPO'; ! vlg | grep -q '^-- pytest FAIL-FAST'"
osr_cleanup

echo "== F. fail-fast-only verify log is partial evidence (baseline shadow hook)"
cmp_verdict(){ # <verify-log> <baseline-failing,comma> <qa dir> : verdict|n_new|would_have_rescued-equivalent
  "$PY" -I - "$1" "$2" "$3" <<'PYEOF2'
import sys, time; sys.path.insert(0, sys.argv[3])
import baseline_verify as b
p = b.parse_verify_log(open(sys.argv[1]).read())
bl = {"ts": time.time(), "commit": "c", "iso": "x", "failing": [x for x in sys.argv[2].split(",") if x], "history": []}
v, summ, d = b.compare_sets(p, bl)
print(v, len(d.get("new_failures") or []), p["complete"])
PYEOF2
}
printf '%s\n' "-- pytest FAIL-FAST in backend (the cycle's own test files only; the full suite was skipped) --" "FAILED tests/test_old.py::test_old_red - boom" "1 failed, 4 passed in 0.5s" > "$SB/ff_only.log"
printf '%s\n' "-- pytest FAIL-FAST in backend (the cycle's own test files only; the full suite was skipped) --" "FAILED tests/test_old.py::test_old_red - boom" "1 failed in 0.5s" "-- pytest FULL in backend --" "FAILED tests/test_old.py::test_old_red - boom" "1 failed, 9 passed in 2s" > "$SB/ff_full.log"
t "F1 FAIL-FAST-only log whose reds are all pre-existing is UNVERIFIED (not PASS), marked incomplete" bash -c "[ \"\$($(declare -f cmp_verdict); PY='$PY'; cmp_verdict '$SB/ff_only.log' '[backend] tests/test_old.py::test_old_red' '$SRC/qa')\" = 'UNVERIFIED 0 False' ]"
t "F2 a NEW red id in a fail-fast-only log still FAILs" bash -c "[ \"\$($(declare -f cmp_verdict); PY='$PY'; cmp_verdict '$SB/ff_only.log' '[backend] tests/other.py::t' '$SRC/qa')\" = 'FAIL 1 False' ]"
t "F3 benign: FAIL-FAST plus a FULL section is complete (judged by the normal rules, no fail-fast downgrade)" bash -c "[ \"\$($(declare -f cmp_verdict); PY='$PY'; cmp_verdict '$SB/ff_full.log' '[backend] tests/test_old.py::test_old_red' '$SRC/qa')\" = 'UNVERIFIED 0 True' ]"
mutate "$SRC/qa/baseline_verify.py" "$SB/qa_mut/baseline_verify.py" '        failfast_only = True
        complete = False' '        failfast_only = True'
t "M6 mutant (fail-fast-only not marked incomplete): pre-existing reds return PASS on partial evidence (F1 would fail)" bash -c "[ \"\$($(declare -f cmp_verdict); PY='$PY'; cmp_verdict '$SB/ff_only.log' '[backend] tests/test_old.py::test_old_red' '$SB/qa_mut')\" != 'UNVERIFIED 0 False' ]"

echo "== G. FIXTURE_SUITES filter hides only fixture-specific names"
printf 'ok.sh\t  FAIL real one\nbad.sh\t  FAIL real two\nfx77_bad.sh\t  FAIL fixture\n' > "$SB/f.tsv"
t "G1 real suites named ok.sh/bad.sh are reported, the fx77_ fixture is dropped" bash -c "[ \"\$('$PY' -I -c \"import sys; sys.path.insert(0,'$SRC/ops'); import suite_run_log as s; print(','.join(n for n,_ in s.read_failed('$SB/f.tsv')))\")\" = 'ok.sh,bad.sh' ]"

t "E1 run_all.sh registers this test" bash -c "grep -qE '(bash|run_if_present|run_or_notrun) test_q_suite_fix\\.sh' '$SRC/scripts/test/run_all.sh'"
osr_summary
