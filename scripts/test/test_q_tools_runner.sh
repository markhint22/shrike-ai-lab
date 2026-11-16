#!/usr/bin/env bash
# q-weekend-fixes item 2 (2026-11-15): the pipeline-owned python test runner + the verify-skipped classification and park.
# 40 of 126 xlite rows were no-op(stage-unverified): tools/tests/*.py are PYTEST-style files and xlite has no .venv/bin/pytest, so every staged verify said
# "python tests exist but no venv pytest found: CANNOT verify (fail-closed)". Now: repo venv pytest -> $OVN_TOOLS_VENV python -> system python3 with pytest -> fail closed, CLASSIFIED
# 'verify-skipped - no python test runner' (ovn_stage_fail_tag), and the item guard parks after 3 consecutive such cycles (shadow log first, OVN_VERIFY_SKIP_PARK=on enforces).
# Every behaviour is also run against a MUTANT (one piece of logic broken) and must FAIL there.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; Q="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
[ -f "$SC/lib_tools_runner.sh" ] || { echo "  SKIP: lib_tools_runner.sh not found"; exit 77; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
sedi(){ if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }
# fake python: `-c import pytest` ok unless FAKE_NOPYTEST=1; `-m pytest ...` logs and exits $FAKE_PYTEST_RC (default 0)
mkfake(){ mkdir -p "$1/bin"; cat > "$1/bin/python" <<'PY'
#!/usr/bin/env bash
a1="$1"; [ "$a1" = -I ] && a1="$2"   # the runner calls `python -I -c <probe>` and `python -I -c <import pytest; ...pytest.main(...)> pkg args` (isolated mode)
case "$*" in *pytest.main*) ;; *) if [ "$a1" = -c ]; then [ "${FAKE_NOPYTEST:-0}" = 1 ] && exit 1; exit 0; fi;; esac
echo "$PWD :: $*" >> "${FAKE_LOG:-/dev/null}"; echo "3 passed"; exit "${FAKE_PYTEST_RC:-0}"
PY
chmod +x "$1/bin/python"; }

# ---------- lib_tools_runner.sh ----------
mkfake "$W/tv"
LIBC="$W/lib_mut"; mkdir -p "$LIBC"
runlib(){ ( . "$1"; shift; "$@" ); }
r="$(OVN_TOOLS_VENV="$W/tv" OVN_TOOLS_SYSTEM_PYTEST=off runlib "$SC/lib_tools_runner.sh" ovn_tools_pytest_py)"
ok "lib: tools venv python with pytest is chosen" "$([ "$r" = "$W/tv/bin/python" ] && echo 1 || echo 0)"
r="$(FAKE_NOPYTEST=1 OVN_TOOLS_VENV="$W/tv" OVN_TOOLS_SYSTEM_PYTEST=off runlib "$SC/lib_tools_runner.sh" ovn_tools_pytest_py)"
ok "lib: a tools venv whose python cannot import pytest is NOT chosen" "$([ -z "$r" ] && echo 1 || echo 0)"
r="$(OVN_TOOLS_VENV="$W/nonexistent" OVN_TOOLS_SYSTEM_PYTEST=off runlib "$SC/lib_tools_runner.sh" ovn_tools_pytest_py)"
ok "lib: no tools venv + system link off -> nothing" "$([ -z "$r" ] && echo 1 || echo 0)"
r="$(OVN_TOOLS_RUNNER=off OVN_TOOLS_VENV="$W/tv" runlib "$SC/lib_tools_runner.sh" ovn_tools_pytest_py)"
ok "lib: OVN_TOOLS_RUNNER=off disables the runner (old fail-closed behaviour)" "$([ -z "$r" ] && echo 1 || echo 0)"
# system python3 with pytest (stub python3 first on PATH)
mkdir -p "$W/sysbin"; cp "$W/tv/bin/python" "$W/sysbin/python3"
r="$(PATH="$W/sysbin:$PATH" OVN_TOOLS_VENV="$W/nonexistent" runlib "$SC/lib_tools_runner.sh" ovn_tools_pytest_py)"
ok "lib: system python3 that already has pytest is used when there is no tools venv" "$([ "$r" = "$W/sysbin/python3" ] && echo 1 || echo 0)"
r="$(FAKE_NOPYTEST=1 PATH="$W/sysbin:$PATH" OVN_TOOLS_VENV="$W/nonexistent" runlib "$SC/lib_tools_runner.sh" ovn_tools_pytest_py)"
ok "lib: system python3 WITHOUT pytest is not used" "$([ -z "$r" ] && echo 1 || echo 0)"
mkdir -p "$W/tree/tools/tests" "$W/tree/backend/tests" "$W/tree/node_modules/x/tests" "$W/tree/.venv/lib/tests"
touch "$W/tree/tools/tests/test_a.py" "$W/tree/tools/tests/test_b.py" "$W/tree/backend/tests/test_c.py" "$W/tree/node_modules/x/tests/test_n.py" "$W/tree/.venv/lib/tests/test_v.py"
r="$(runlib "$SC/lib_tools_runner.sh" ovn_tools_test_pkgs "$W/tree" | tr '\n' ' ')"
ok "lib: test packages = parent of */tests/test_*.py, deduped, node_modules/.venv excluded" "$([ "$r" = "backend tools " ] && echo 1 || echo 0)"
mkdir -p "$W/roottree/tests"; touch "$W/roottree/tests/test_r.py"
r="$(runlib "$SC/lib_tools_runner.sh" ovn_tools_test_pkgs "$W/roottree")"
ok "lib: repo-root tests dir -> package '.'" "$([ "$r" = "." ] && echo 1 || echo 0)"
sed 's#\[ "\${OVN_TOOLS_RUNNER:-on}" = off \] \&\& return 0#:#' "$SC/lib_tools_runner.sh" > "$LIBC/m2.sh"
r="$(OVN_TOOLS_RUNNER=off OVN_TOOLS_VENV="$W/tv" runlib "$LIBC/m2.sh" ovn_tools_pytest_py)"
ok "MUTANT lib (off-switch ignored) is caught by the off-switch check" "$([ -n "$r" ] && echo 1 || echo 0)"

# ---------- ops/make_tools_venv.sh ----------
mkdir -p "$W/mhome/qtmp"
out="$(HOME="$W/mhome" OVN_TOOLS_VENV="$W/mhome/qtmp/mkv_venv" OVN_TOOLS_DRY=1 bash "$Q/ops/make_tools_venv.sh" 2>&1)"; rc=$?
ok "make_tools_venv: dry run prints the plan, creates nothing" "$([ $rc = 0 ] && echo "$out" | grep -q 'python3 -m venv' && [ ! -e "$W/mhome/qtmp/mkv_venv" ] && echo 1 || echo 0)"
out="$(HOME="$W/mhome" OVN_TOOLS_VENV="$W/mhome/qtmp/mkv_venv" PIP_INDEX_URL=http://127.0.0.1:9/simple/ bash "$Q/ops/make_tools_venv.sh" 2>&1)"; rc=$?
ok "make_tools_venv: unreachable pip index -> exit 3, nothing created" "$([ $rc = 3 ] && [ ! -e "$W/mhome/qtmp/mkv_venv" ] && echo 1 || echo 0)"
mkdir -p "$W/mhome/qtmp"; cp -R "$W/tv" "$W/mhome/qtmp/tools_venv"
out="$(HOME="$W/mhome" OVN_TOOLS_VENV="$W/mhome/qtmp/tools_venv" bash "$Q/ops/make_tools_venv.sh" 2>&1)"; rc=$?
ok "make_tools_venv: an already-working tools venv is left alone (exit 0)" "$([ $rc = 0 ] && echo "$out" | grep -q 'already OK' && echo 1 || echo 0)"

# ---------- run_overnight.sh: run_repo_verification (per-cycle verify) ----------
( . "$HERE/lib_ro_core.sh"; ro_init; ro_tasks '[]'; ro_source; set +e
  . "$SC/lib_tools_runner.sh"
  task_log="$T/v.log"; : > "$task_log"; V="$T/v"
  newrepo(){ rm -rf "${V:?}"; mkdir -p "$V"; cd "$V" || exit 1; git init -q; echo base > README; git add -A; git commit -q -m base; BEFORE_SHA="$(git rev-parse HEAD)"; }
  newrepo; mkdir -p tools/tests; printf 'def test_a():\n    assert True\n' > tools/tests/test_a.py; git add -A; git commit -q -m t
  export OVN_TOOLS_SYSTEM_PYTEST=off
  r="$(OVN_TOOLS_VENV="$W/nonexistent" run_repo_verification)"; echo "R1=$r"
  r="$(OVN_TOOLS_VENV="$W/tv" FAKE_LOG="$T/fake.log" run_repo_verification)"; echo "R2=$r"; grep -q 'tools runner' "$task_log" && echo "LOG2=yes"
  r="$(OVN_TOOLS_VENV="$W/tv" FAKE_PYTEST_RC=1 run_repo_verification)"; echo "R3=$r"
  r="$(OVN_TOOLS_VENV="$W/tv" FAKE_PYTEST_RC=5 run_repo_verification)"; echo "R4=$r"
  r="$(OVN_TOOLS_RUNNER=off OVN_TOOLS_VENV="$W/tv" run_repo_verification)"; echo "R5=$r"
  # a unittest-style file keeps going through unittest (not the tools runner)
  newrepo; mkdir -p tools/tests; printf 'import unittest\nclass T(unittest.TestCase):\n    def test_a(self):\n        self.assertTrue(True)\n' > tools/tests/test_u.py; git add -A; git commit -q -m u
  r="$(OVN_TOOLS_VENV="$W/tv" FAKE_LOG="$T/fake2.log" run_repo_verification)"; echo "R6=$r"; [ ! -s "$T/fake2.log" ] && echo "UT6=yes"
) > "$W/ro.out" 2>&1
get(){ grep "^$1=" "$W/ro.out" | head -1 | cut -d= -f2; }
ok "per-cycle: pytest-style file + NO runner anywhere -> skip (fail-closed, as before)" "$([ "$(get R1)" = skip ] && echo 1 || echo 0)"
ok "per-cycle: pytest-style file + tools runner (green) -> pass" "$([ "$(get R2)" = pass ] && echo 1 || echo 0)"
ok "per-cycle: the log names the tools runner" "$(grep -q LOG2=yes "$W/ro.out" && echo 1 || echo 0)"
ok "per-cycle: tools runner red -> fail" "$([ "$(get R3)" = fail ] && echo 1 || echo 0)"
ok "per-cycle: tools runner rc 5 (no tests collected) -> skip, never pass" "$([ "$(get R4)" = skip ] && echo 1 || echo 0)"
ok "per-cycle: OVN_TOOLS_RUNNER=off restores skip" "$([ "$(get R5)" = skip ] && echo 1 || echo 0)"
ok "per-cycle: a unittest-style file still runs via unittest, not the tools runner" "$([ "$(get R6)" = pass ] && grep -q UT6=yes "$W/ro.out" && echo 1 || echo 0)"
if [ "$(get R2)" != pass ]; then sed 's/^/    | /' "$W/ro.out" | tail -12; fi

# ---------- ovn_stage_runner.sh: full_verify ----------
( . "$HERE/lib_osr_fixture.sh"
  # `producer | grep -q` under pipefail: grep -q exits at the FIRST match, the producer (cat of a >64 KB runner log, git log) then dies of SIGPIPE and pipefail turns a TRUE match into a failed
  # condition: a load-dependent flake (observed 1-3% under 12 parallel runs + 10 CPU burners, in S1 'PUSHED', S2 'verify FAILED', 'shows the tools runner'). This block never needs pipefail.
  set +o pipefail
  pass=0; fail=0
  export OVN_STAGE_DEDICATE=0 OVN_VERIFY_REPAIR_ROUNDS=0 OVN_VERIFY_REGEN=0 OVN_TOOLS_SYSTEM_PYTEST=off
  trap osr_cleanup EXIT
  osr_new; cp "$SC/lib_tools_runner.sh" "$Q/scripts/"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
  OVN_TOOLS_VENV="$W/tv" FAKE_LOG="$T/fake.log" osr_run "$OSR_REPO" "$ITEM_PY"
  echo "S1_pushed=$(osr_origin_log | grep -q 'staged step' && echo 1 || echo 0)"
  echo "S1_vlog_tools=$(osr_vlog | grep -q 'pipeline tools runner' && echo 1 || echo 0)"
  echo "S1_vlog_noCannot=$(osr_vlog | grep -q 'CANNOT verify' && echo 0 || echo 1)"
  echo "S1_ran_in_pkg=$(grep -q 'backend :: -I -c' "$T/fake.log" 2>/dev/null && echo 1 || echo 0)"
  osr_cleanup
  osr_new; cp "$SC/lib_tools_runner.sh" "$Q/scripts/"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
  OVN_TOOLS_VENV="$W/tv" FAKE_PYTEST_RC=1 osr_run "$OSR_REPO" "$ITEM_PY"
  echo "S2_red_not_pushed=$(osr_origin_log | grep -q 'staged step' && echo 0 || echo 1)"
  echo "S2_verify_failed=$(osr_out | grep -q 'independent full-verify: FAILED' && echo 1 || echo 0)"
  { osr_origin_log | grep -q 'staged step'; } && { echo "S2_DIAG pushed rc=$RC"; osr_out | tail -30 | sed 's/^/S2_DIAG out| /'; osr_vlog | tail -15 | sed 's/^/S2_DIAG vlog| /'; }
  osr_out | grep -q 'independent full-verify: FAILED' || { echo "S2_DIAG not-failed rc=$RC"; osr_out | tail -30 | sed 's/^/S2_DIAG out| /'; osr_vlog | tail -15 | sed 's/^/S2_DIAG vlog| /'; }
  osr_cleanup
  osr_new; cp "$SC/lib_tools_runner.sh" "$Q/scripts/"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
  OVN_TOOLS_VENV="$W/nonexistent" osr_run "$OSR_REPO" "$ITEM_PY"
  echo "S3_not_pushed=$(osr_origin_log | grep -q 'staged step' && echo 0 || echo 1)"
  echo "S3_classified=$(osr_vlog | grep -q 'verify-skipped - no python test runner' && echo 1 || echo 0)"
  echo "S3_still_cannot=$(osr_vlog | grep -q 'CANNOT verify (fail-closed)' && echo 1 || echo 0)"
  osr_cleanup
  osr_new; cp "$SC/lib_tools_runner.sh" "$Q/scripts/"; osr_plan default "$PLAN_FOO"; osr_aider 1 "$SNIP_FOO"
  OVN_TOOLS_RUNNER=off OVN_TOOLS_VENV="$W/tv" osr_run "$OSR_REPO" "$ITEM_PY"
  echo "S4_off_failclosed=$(osr_vlog | grep -q 'CANNOT verify (fail-closed) --' && ! osr_vlog | grep -q 'verify-skipped' && echo 1 || echo 0)"
) > "$W/osr.out" 2>&1
g2(){ grep "^$1=" "$W/osr.out" | head -1 | cut -d= -f2; }
ok "stage: no repo venv + tools runner green -> verified and PUSHED (was fail-closed)" "$([ "$(g2 S1_pushed)" = 1 ] && echo 1 || echo 0)"
ok "stage: the verify log shows the tools runner and no longer says CANNOT verify" "$([ "$(g2 S1_vlog_tools)" = 1 ] && [ "$(g2 S1_vlog_noCannot)" = 1 ] && echo 1 || echo 0)"
ok "stage: pytest ran inside the package dir (backend) isolated (python -I)" "$([ "$(g2 S1_ran_in_pkg)" = 1 ] && echo 1 || echo 0)"
ok "stage: tools runner RED -> verify FAILED, nothing pushed" "$([ "$(g2 S2_red_not_pushed)" = 1 ] && [ "$(g2 S2_verify_failed)" = 1 ] && echo 1 || echo 0)"
ok "stage: no runner anywhere -> still fail-closed (not pushed) and classified verify-skipped" "$([ "$(g2 S3_not_pushed)" = 1 ] && [ "$(g2 S3_classified)" = 1 ] && [ "$(g2 S3_still_cannot)" = 1 ] && echo 1 || echo 0)"
ok "stage: OVN_TOOLS_RUNNER=off -> the old single fail-closed message, no classification" "$([ "$(g2 S4_off_failclosed)" = 1 ] && echo 1 || echo 0)"
if [ "$F" -gt 0 ]; then echo "    | stage-check values and diagnostics follow (F=$F):"; grep -E '^S[0-9]' "$W/osr.out" | cut -c1-300 | sed 's/^/    | /'; fi
if [ -z "$(g2 S1_pushed)" ]; then sed 's/^/    | /' "$W/osr.out" | tail -15; fi

# ---------- ovn_stage_fail_tag ----------
printf -- '-- python tests exist but no venv pytest found: CANNOT verify (fail-closed): verify-skipped - no python test runner (x) --\n' > "$W/vs.log"
printf -- '-- pytest FULL in backend --\nFAILED tests/test_x.py::t - assert 1 == 2\n' > "$W/vr.log"
t1="$( . "$SC/lib_p4_outcomes.sh"; OVN_STAGE_FAILTAG=on ovn_stage_fail_tag "" "$W/vs.log" )"
ok "fail tag: verify log with the no-runner line -> 'verify-skipped'" "$([ "$t1" = verify-skipped ] && echo 1 || echo 0)"
t1="$( . "$SC/lib_p4_outcomes.sh"; OVN_STAGE_FAILTAG=on ovn_stage_fail_tag "" "$W/vr.log" )"
ok "fail tag: an ordinary red verify log is NOT verify-skipped" "$([ "$t1" != verify-skipped ] && [ -n "$t1" ] && echo 1 || echo 0)"
t1="$( . "$SC/lib_p4_outcomes.sh"; OVN_VERIFY_SKIP_TAG=off OVN_STAGE_FAILTAG=on ovn_stage_fail_tag "" "$W/vs.log" )"
ok "fail tag: OVN_VERIFY_SKIP_TAG=off restores the old classification" "$([ "$t1" != verify-skipped ] && echo 1 || echo 0)"

# ---------- ovn_item_guard.sh: verify-skip park ----------
. "$SC/lib_item_select.sh"
B='- [ ] [T3] [feat:xlite-20261115-vs] tools/thing.py — item whose verify cannot run. VERIFY: `true`'
HB="$(ovn_item_hash "$B")"; BTXT="${B#- \[ \] }"
mkg(){ local d="$W/g_$1"; mkdir -p "$d"; for f in ovn_item_guard.sh lib_item_select.sh lib_bug_escalate.sh ovn_extract_failure.sh ovn_repeat_ids.py; do [ -f "$SC/$f" ] && cp "$SC/$f" "$d/$f"; done
  [ -n "${2:-}" ] && { sedi "$2" "$d/ovn_item_guard.sh"; }; echo "$d/ovn_item_guard.sh"; }
mkrepo(){ local r="$W/r_$1"; rm -rf "${r:?}"; mkdir -p "$r"; ( cd "$r" && git init -q -b main && git config user.email t@t && git config user.name t && printf '## Next Steps\n%s\n' "$B" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ); printf '%s' "$r"; }
STG='no-op(stage-unverified) stage(higher-tier)'
cyc(){ # guard repo state tag [env...] : one stage cycle with the given fail tag
  local g="$1" r="$2" st="$3" tag="$4"; shift 4
  { echo 'Tokens: 1k sent, 1 received.'; echo "stage-item-hash $HB"; echo "stage-item-line $BTXT"; } > "$W/cyc.log"; [ -n "$tag" ] && printf '%s\n' "$tag" > "$W/cyc.log.stagefr" || rm -f "$W/cyc.log.stagefr"
  env OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=99 OVN_ITEM_DAY_CAP=99 OVN_REPEAT_BREAKER=off "$@" bash "$g" "$r" "$STG" "$st" idV "$W/cyc.log" >/dev/null 2>&1; }
suite(){ # label guard
  local L="$1" g="$2" r st; local p=""
  r="$(mkrepo "${L}A")"; st="$W/s_${L}A"; mkdir -p "$st"
  cyc "$g" "$r" "$st" verify-skipped; cyc "$g" "$r" "$st" verify-skipped
  [ ! -e "$st/verify_skip_shadow.log" ] && ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && p="${p}A_under_n_silent "
  cyc "$g" "$r" "$st" verify-skipped
  if ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && grep -q 'vskip=3/3 would park' "$st/verify_skip_shadow.log" 2>/dev/null; then p="${p}B_shadow_logs_only "; fi
  r="$(mkrepo "${L}C")"; st="$W/s_${L}C"; mkdir -p "$st"
  for i in 1 2 3; do cyc "$g" "$r" "$st" verify-skipped OVN_VERIFY_SKIP_PARK=on; done
  subj="$(git -C "$r" log --format=%s 2>/dev/null)"   # captured first: `git log | grep -q` under pipefail is a SIGPIPE flake under load
  grep -q 'AUTO-SKIP after 3 verify-skipped cycles' "$r/OVERNIGHT_PROGRESS.md" && case "$subj" in *verify-skipped*) true;; *) false;; esac && [ ! -e "$st/item_fails/idV.$HB.vskip" ] && p="${p}C_on_parks_and_resets "
  r="$(mkrepo "${L}D")"; st="$W/s_${L}D"; mkdir -p "$st"
  cyc "$g" "$r" "$st" verify-skipped OVN_VERIFY_SKIP_PARK=on; cyc "$g" "$r" "$st" verify-skipped OVN_VERIFY_SKIP_PARK=on
  cyc "$g" "$r" "$st" test-red OVN_VERIFY_SKIP_PARK=on; cyc "$g" "$r" "$st" verify-skipped OVN_VERIFY_SKIP_PARK=on
  ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && p="${p}D_other_outcome_resets_streak "
  r="$(mkrepo "${L}E")"; st="$W/s_${L}E"; mkdir -p "$st"
  for i in 1 2 3 4; do cyc "$g" "$r" "$st" verify-skipped OVN_VERIFY_SKIP_PARK=off; done
  [ ! -e "$st/item_fails/idV.$HB.vskip" ] && [ ! -e "$st/verify_skip_shadow.log" ] && p="${p}E_off_inert "
  r="$(mkrepo "${L}F")"; st="$W/s_${L}F"; mkdir -p "$st"
  for i in 1 2 3; do cyc "$g" "$r" "$st" verify-skipped OVN_VERIFY_SKIP_PARK=on OVN_VERIFY_SKIP_PARK_N=5; done
  ! grep -q AUTO-SKIP "$r/OVERNIGHT_PROGRESS.md" && p="${p}F_custom_N "
  echo "$p"
}
real="$(suite real "$(mkg real)")"
for c in A_under_n_silent B_shadow_logs_only C_on_parks_and_resets D_other_outcome_resets_streak E_off_inert F_custom_N; do ok "guard: $c" "$(echo "$real" | grep -qw "$c" && echo 1 || echo 0)"; done
m1="$(suite m1 "$(mkg m1 's/_vs_n" -ge "${OVN_VERIFY_SKIP_PARK_N:-3}"/_vs_n" -ge 99/')")"
ok "MUTANT guard (threshold never reached) is caught" "$(echo "$m1" | grep -qw C_on_parks_and_resets && echo 0 || echo 1)"
m2="$(suite m2 "$(mkg m2 's/else rm -f "\$vskipf" 2>\/dev\/null; fi ;;/else :; fi ;;/')")"
ok "MUTANT guard (other outcome does not reset the streak) is caught" "$(echo "$m2" | grep -qw D_other_outcome_resets_streak && echo 0 || echo 1)"
m3="$(suite m3 "$(mkg m3 's/OVN_VERIFY_SKIP_PARK:-shadow}" = on \]/OVN_VERIFY_SKIP_PARK:-shadow}" != off ]/')")"
ok "MUTANT guard (shadow enforces) is caught" "$(echo "$m3" | grep -qw B_shadow_logs_only && echo 0 || echo 1)"
m4="$(suite m4 "$(mkg m4 's/\[ "\${OVN_VERIFY_SKIP_PARK:-shadow}" != off \]/true/')")"
ok "MUTANT guard (off-switch ignored) is caught" "$(echo "$m4" | grep -qw E_off_inert && echo 0 || echo 1)"
# ---------- review advisory (a): isolated pytest, neutral-cwd probe, no package cap, venv path guard ----------
mut(){ python3 -c 'import sys;s=open(sys.argv[1]).read();o=sys.argv[3];assert o in s,"mutant anchor missing";open(sys.argv[2],"w").write(s.replace(o,sys.argv[4],1))' "$@" || { echo "  FAIL mutant anchor missing: $3"; F=$((F+1)); }; }
# a probe from the repo cwd must not be fooled: this fake python "has pytest" only when a pytest.py sits in its cwd (what a hostile repo would plant)
mkdir -p "$W/hv/bin" "$W/hostile"; cat > "$W/hv/bin/python" <<'PY'
#!/usr/bin/env bash
[ -f "$PWD/pytest.py" ] && exit 0
exit 1
PY
chmod +x "$W/hv/bin/python"; : > "$W/hostile/pytest.py"
r="$( cd "$W/hostile" && OVN_TOOLS_VENV="$W/hv" OVN_TOOLS_SYSTEM_PYTEST=off runlib "$SC/lib_tools_runner.sh" ovn_tools_pytest_py )"
ok "probe: a pytest.py planted in the caller's cwd does not make a python 'have pytest' (probe runs from a neutral cwd)" "$([ -z "$r" ] && echo 1 || echo 0)"
mut "$SC/lib_tools_runner.sh" "$LIBC/m3.sh" '( cd / && "$p" -I -c' '( "$p" -I -c'
r="$( cd "$W/hostile" && OVN_TOOLS_VENV="$W/hv" OVN_TOOLS_SYSTEM_PYTEST=off runlib "$LIBC/m3.sh" ovn_tools_pytest_py )"
ok "MUTANT (probe from the repo cwd) is caught" "$([ -n "$r" ] && echo 1 || echo 0)"
mut "$SC/lib_tools_runner.sh" "$LIBC/m4.sh" '[ -n "$p" ] && [ -x "$p" ] && ( cd / && "$p" -I -c '"'"'import pytest'"'"' ) >/dev/null 2>&1 && { printf '"'"'%s'"'"' "$p"; return 0; }' ':'
r="$(OVN_TOOLS_VENV="$W/tv" OVN_TOOLS_SYSTEM_PYTEST=off runlib "$LIBC/m4.sh" ovn_tools_pytest_py)"
ok "MUTANT lib (selection removed) is caught by the first check" "$([ "$r" != "$W/tv/bin/python" ] && echo 1 || echo 0)"
# 7 packages: all returned (the old head -6 cap silently skipped the 7th)
mkdir -p "$W/seven"; for i in 1 2 3 4 5 6 7; do mkdir -p "$W/seven/p$i/tests"; touch "$W/seven/p$i/tests/test_a.py"; done
r="$(runlib "$SC/lib_tools_runner.sh" ovn_tools_test_pkgs "$W/seven" | wc -l | tr -d ' ')"
ok "lib: 7 test packages -> all 7 returned (no silent cap)" "$([ "$r" = 7 ] && echo 1 || echo 0)"
mut "$SC/lib_tools_runner.sh" "$LIBC/m5.sh" "done | awk '!s[\$0]++'" "done | awk '!s[\$0]++' | head -6"
r="$(runlib "$LIBC/m5.sh" ovn_tools_test_pkgs "$W/seven" | wc -l | tr -d ' ')"
ok "MUTANT (head -6 cap restored) is caught" "$([ "$r" != 7 ] && echo 1 || echo 0)"
# real pytest repros (need a python that really has pytest: any repo venv on this host; otherwise SKIPPED, never faked)
RP=""; for c in "${OVN_TEST_PYTEST_PY:-}" $HOME/overnight-queue/repos/*/*/.venv/bin/python $HOME/overnight-queue/repos/*/.venv/bin/python $HOME/LocalProjects/*/.venv/bin/python $HOME/LocalProjects/*/*/.venv/bin/python; do
  [ -n "$c" ] && [ -x "$c" ] && ( cd / && "$c" -I -c 'import pytest; assert pytest.version_tuple >= (7,)' ) >/dev/null 2>&1 && { RP="$c"; break; }; done
if [ -z "$RP" ]; then echo "  SKIP real-pytest repros: no python with pytest>=7 found on this host (set OVN_TEST_PYTEST_PY)"
else
  mkpkg(){ rm -rf "${W:?}/$1"; mkdir -p "$W/$1/tests"; printf 'def test_bad():\n    assert 1 == 2\n' > "$W/$1/tests/test_bad.py"; }
  runit(){ ( . "$1"; ovn_tools_pytest_run "$RP" "$W/$2" 60 tests ) >"$W/run.out" 2>&1; echo $?; }
  # R1: pytest.py stub that exits 0
  mkpkg p_stub; printf 'import sys\nsys.exit(0)\n' > "$W/p_stub/pytest.py"
  ctl="$( cd "$W/p_stub" && PYTHONPATH="$W/p_stub" "$RP" -m pytest -q -o addopts="" -p no:cacheprovider tests >/dev/null 2>&1; echo $? )"
  ok "CONTROL: the OLD invocation (cwd + PYTHONPATH=package) is fooled by a pytest.py stub (rc 0 on a failing test)" "$([ "$ctl" = 0 ] && echo 1 || echo 0)"
  rc="$(runit "$SC/lib_tools_runner.sh" p_stub)"
  ok "failing test + pytest.py stub -> rc NON-zero (stub never imported)" "$([ "$rc" != 0 ] && grep -q 'failed' "$W/run.out" && echo 1 || echo 0)"
  # R2: sitecustomize.py that hard-exits 0
  mkpkg p_site; printf 'import os\nos._exit(0)\n' > "$W/p_site/sitecustomize.py"
  ctl="$( cd "$W/p_site" && PYTHONPATH="$W/p_site" "$RP" -m pytest -q -o addopts="" -p no:cacheprovider tests >/dev/null 2>&1; echo $? )"
  ok "CONTROL: the OLD invocation is fooled by a sitecustomize.py os._exit(0)" "$([ "$ctl" = 0 ] && echo 1 || echo 0)"
  rc="$(runit "$SC/lib_tools_runner.sh" p_site)"
  ok "failing test + sitecustomize os._exit(0) -> rc NON-zero" "$([ "$rc" != 0 ] && echo 1 || echo 0)"
  # R3: honest packages still work: package module importable, green rc 0, no .pytest_cache written
  rm -rf "${W:?}/p_ok"; mkdir -p "$W/p_ok/tests"; printf 'def f():\n    return 41 + 1\n' > "$W/p_ok/mymod.py"; printf 'import mymod\ndef test_ok():\n    assert mymod.f() == 42\n' > "$W/p_ok/tests/test_ok.py"
  rc="$(runit "$SC/lib_tools_runner.sh" p_ok)"
  ok "an honest package: its own module is importable (pythonpath ini), rc 0, 1 passed" "$([ "$rc" = 0 ] && grep -q '1 passed' "$W/run.out" && [ ! -e "$W/p_ok/.pytest_cache" ] && echo 1 || echo 0)"
  mkpkg p_red; rc="$(runit "$SC/lib_tools_runner.sh" p_red)"
  ok "an honest failing package -> rc non-zero" "$([ "$rc" != 0 ] && echo 1 || echo 0)"
  # mutants: drop -I ; PYTHONPATH-first again
  mut "$SC/lib_tools_runner.sh" "$LIBC/m6.sh" '"$py" -I -c' '"$py" -c'
  rc="$(runit "$LIBC/m6.sh" p_stub)"; ok "MUTANT (no -I) is caught by the pytest.py stub repro" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
  mut "$SC/lib_tools_runner.sh" "$LIBC/m9.sh" '"$py" -I -c '"'"'import sys, pytest; sys.path.append(sys.argv[1]); sys.exit(pytest.main(sys.argv[2:]))'"'"' "$pkg"' 'env PYTHONPATH="$pkg" "$py" -m pytest'
  rc="$(runit "$LIBC/m9.sh" p_site)"; ok "MUTANT (package on PYTHONPATH, no -I) is caught by the sitecustomize repro" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
  mut "$SC/lib_tools_runner.sh" "$LIBC/m7.sh" '"$py" -I -c '"'"'import sys, pytest; sys.path.append(sys.argv[1]); sys.exit(pytest.main(sys.argv[2:]))'"'"' "$pkg"' 'env PYTHONPATH="$pkg" "$py" -m pytest'
  rc="$(runit "$LIBC/m7.sh" p_stub)"; ok "MUTANT (package first on PYTHONPATH, cwd on path) is caught" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
  mut "$SC/lib_tools_runner.sh" "$LIBC/m8.sh" 'sys.path.append(sys.argv[1]); ' ''
  rc="$(runit "$LIBC/m8.sh" p_ok)"; ok "MUTANT (package not on the path) is caught by the honest-package check" "$([ "$rc" != 0 ] && echo 1 || echo 0)"
fi
# make_tools_venv.sh refuses an unsafe OVN_TOOLS_VENV (it rm -rf's it)
MH="$W/mkhome"; mkdir -p "$MH/qtmp" "$MH/overnight-queue/state" "$W/victim"; echo keep > "$W/victim/precious"; mkdir -p "$MH/qtmp/notv"; echo keep > "$MH/qtmp/notv/precious"
mkrun(){ HOME="$MH" OVN_TOOLS_VENV="$1" PIP_INDEX_URL=http://127.0.0.1:9/simple/ bash "${2:-$Q/ops/make_tools_venv.sh}" >"$W/mk.out" 2>&1; echo $?; }
ok "make_tools_venv: a venv path outside HOME/overnight-queue/state and HOME/qtmp is refused (exit 2), nothing touched" "$([ "$(mkrun "$W/victim")" = 2 ] && [ -f "$W/victim/precious" ] && echo 1 || echo 0)"
ok "make_tools_venv: a path under qtmp that is not named *venv* is refused" "$([ "$(mkrun "$MH/qtmp/notv")" = 2 ] && [ -f "$MH/qtmp/notv/precious" ] && echo 1 || echo 0)"
ok "make_tools_venv: HOME itself, / and a relative path are refused" "$([ "$(mkrun "$MH")" = 2 ] && [ "$(mkrun /)" = 2 ] && [ "$(mkrun venv)" = 2 ] && echo 1 || echo 0)"
ok "make_tools_venv: a .. traversal out of the allowed root is refused" "$([ "$(mkrun "$MH/qtmp/../../victim_venv")" = 2 ] && [ -f "$W/victim/precious" ] && echo 1 || echo 0)"
ln -s "$W/victim" "$MH/qtmp/linkvenv"
ok "make_tools_venv: a symlinked venv path is refused" "$([ "$(mkrun "$MH/qtmp/linkvenv")" = 2 ] && [ -f "$W/victim/precious" ] && echo 1 || echo 0)"
mkdir -p "$W/outside"; ln -s "$W/outside" "$MH/qtmp/linkdir"
ok "make_tools_venv: a venv under a symlinked parent that points outside is refused" "$([ "$(mkrun "$MH/qtmp/linkdir/x_venv")" = 2 ] && echo 1 || echo 0)"
ok "make_tools_venv: valid paths (qtmp/x_venv, state/tools_venv) pass the guard (exit 3 = index unreachable, not 2)" "$([ "$(mkrun "$MH/qtmp/x_venv")" = 3 ] && [ "$(mkrun "$MH/overnight-queue/state/tools_venv")" = 3 ] && echo 1 || echo 0)"
mut "$Q/ops/make_tools_venv.sh" "$W/mk_m1.sh" 'if ! tools_venv_path_ok "$V"; then' 'if false; then'
ok "MUTANT make_tools_venv (guard removed) is caught" "$([ "$(mkrun "$W/victim" "$W/mk_m1.sh")" != 2 ] && echo 1 || echo 0)"
mut "$Q/ops/make_tools_venv.sh" "$W/mk_m2.sh" 'case "$base" in *venv*) ;; *) return 1;; esac' ':'
ok "MUTANT make_tools_venv (name check removed) is caught" "$([ "$(mkrun "$MH/qtmp/notv" "$W/mk_m2.sh")" != 2 ] && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" -eq 0 ]
