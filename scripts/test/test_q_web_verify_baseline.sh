#!/usr/bin/env bash
# q-weekend-fixes item 5 (2026-11-15): the staged web-verify gate (vue-tsc --noEmit + vitest related) is baseline-aware.
# Measured from the box: 138 shadow reds, 120 of them carried only error signatures already present at the previous run of the same repo (billwatch/gitlark whole-project vue-tsc debt that their
# real gate, vite build, never checks; iptv_apps: the one en.ts break repeating 7x). So the gate stays SHADOW (precision ~5% as an any-red blocking rule); a red is now `red-inherited` unless it
# adds NEW signatures (file|TScode COUNTED per occurrence, failing vitest names) against state/web_verify_baseline/<repo>.sigs, and only a NEW red can block when OVN_STAGE_WEB_VERIFY=enforce.
# Review round 2 (advisories d): the baseline is written ONLY on green (reset) or by ops/web_verify_baseline_seed.sh (never on a red, shadow or enforce); errors the parser cannot attribute count as new;
# a vue-tsc/vitest timeout does not hide the other tool's red.
# Each behaviour is also run against a MUTANT of lib_stage_guards.sh and must FAIL there.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; LIB0="$SC/lib_stage_guards.sh"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
[ -f "$LIB0" ] || { echo "  SKIP: lib_stage_guards.sh not found"; exit 77; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
sedi(){ if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi; }
# a worktree whose HEAD changes one web file over `base`; node_modules present; npx stub driven by $SCN files
WT="$W/wt"; mkdir -p "$WT/web/src" "$WT/web/node_modules"; ( cd "$WT" && git init -q -b main && echo 'export const a = 1' > web/src/a.ts && printf '{"devDependencies":{"vue-tsc":"1","vitest":"1"}}' > web/package.json && git add -A && git commit -qm base && echo 'export const a = 2' > web/src/a.ts && git add -A && git commit -qm change )
BASE="$(git -C "$WT" rev-parse HEAD~1)"
SCN="$W/scn"; mkdir -p "$SCN" "$W/bin"
cat > "$W/bin/npx" <<'NPX'
#!/usr/bin/env bash
k="$1"; case "$k" in vue-tsc) f=tsc;; vitest) f=vitest;; *) exit 0;; esac
[ -f "$SCN/$f.out" ] && cat "$SCN/$f.out"; exit "$(cat "$SCN/$f.rc" 2>/dev/null || echo 0)"
NPX
chmod +x "$W/bin/npx"; export SCN
tsc(){ printf '%s\n' "$@" > "$SCN/tsc.out"; echo 2 > "$SCN/tsc.rc"; }   # error lines
tsc_green(){ rm -f "$SCN/tsc.out"; echo 0 > "$SCN/tsc.rc"; }
echo 0 > "$SCN/vitest.rc"
E_A="src/t/A.test.ts(10,5): error TS2339: Property x does not exist"; E_B="src/b.vue(3,4): error TS6133: unused"; E_C="src/c.ts(9,9): error TS2322: bad"
run(){ # <lib> <repo|-> <mode> [env...] -> sets OUT RC ; state dir per call group in $SD
  local lib="$1" repo="$2" mode="$3"; shift 3
  : > "$W/vlog"
  local rn="$repo"; [ "$repo" = - ] && rn=""
  OUT="$( cd "$W" && env PATH="$W/bin:$PATH" OVN_WEB_VERIFY_STATE="$SD" OVN_STAGE_WEB_VERIFY="$mode" OVN_STAGE_REPO="$rn" repo="" "$@" bash -c '. "$0"; stage_web_verify "$1" "$2" "$3"' "$lib" "$WT" "$BASE" "$W/vlog" 2>&1 )"; RC=$?
}
seedb(){ # <lib> <repo> : what ops/web_verify_baseline_seed.sh does, with the library under test (the real script is tested separately)
  mkdir -p "$SD/web_verify_baseline"; ( . "$1"; _sg_web_sigs "$W/vlog.web.log" ) > "$SD/web_verify_baseline/$2.sigs"
}
suite(){ # <label> <lib> -> prints "NAME=1|0"
  local L="$1" lib="$2"; SD="$W/sd_$L"; rm -rf "$SD"; mkdir -p "$SD"; local r bfile="$SD/web_verify_baseline/billwatch.sigs"
  tsc "$E_A" "$E_B"
  run "$lib" billwatch shadow
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red vue-tsc rc=2 (2 new / 0 inherited' && [ ! -e "$bfile" ] && echo "A_first_red_is_new_and_writes_no_baseline=1" || echo "A_first_red_is_new_and_writes_no_baseline=0"
  seedb "$lib" billwatch   # the explicit seed command accepts the current debt
  tsc "$E_A" "$E_B"; run "$lib" billwatch enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red-inherited' && [ ! -s "$W/vlog" ] && echo "B_enforce_inherited_never_blocks=1" || echo "B_enforce_inherited_never_blocks=0"
  tsc "src/t/A.test.ts(99,1): error TS2339: moved line" "$E_B"; run "$lib" billwatch enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red-inherited' && echo "C_line_number_drift_is_still_inherited=1" || echo "C_line_number_drift_is_still_inherited=0"
  tsc "$E_A" "$E_B" "$E_C"; run "$lib" billwatch enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '(1 new / 2 inherited' && grep -q 'QUALITY FAIL: web verification failed' "$W/vlog" && grep -q 'src/c.ts|TS2322' "$W/vlog" && echo "D_enforce_new_signature_blocks=1" || echo "D_enforce_new_signature_blocks=0"
  grep -q 'src/c.ts' "$bfile" && echo "E_blocked_run_does_not_update_baseline=0" || echo "E_blocked_run_does_not_update_baseline=1"
  tsc "$E_A" "$E_B" "$E_C"; run "$lib" billwatch shadow
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red vue-tsc rc=2 (1 new' && ! grep -q 'src/c.ts' "$bfile" && echo "F_shadow_never_blocks_and_a_red_never_writes_the_baseline=1" || echo "F_shadow_never_blocks_and_a_red_never_writes_the_baseline=0"
  run "$lib" billwatch shadow
  echo "$OUT" | grep -q '^WEB red vue-tsc rc=2 (1 new' && echo "F2_the_same_red_is_still_new_next_run=1" || echo "F2_the_same_red_is_still_new_next_run=0"
  tsc_green; run "$lib" billwatch enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB ok' && [ ! -s "$bfile" ] && echo "G_green_clears_the_baseline=1" || echo "G_green_clears_the_baseline=0"
  tsc "$E_A"; run "$lib" billwatch enforce
  [ $RC = 1 ] && echo "H_after_green_the_same_error_is_new_again=1" || echo "H_after_green_the_same_error_is_new_again=0"
  tsc "$E_A"; run "$lib" gitlark enforce
  [ $RC = 1 ] && echo "I_baselines_are_per_repo=1" || echo "I_baselines_are_per_repo=0"
  tsc_green; run "$lib" billwatch shadow; tsc "$E_B"; run "$lib" billwatch shadow
  echo 124 > "$SCN/tsc.rc"; run "$lib" billwatch enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB timeout' && [ ! -s "$W/vlog" ] && echo "J_timeout_is_no_verdict_and_never_blocks=1" || echo "J_timeout_is_no_verdict_and_never_blocks=0"
  tsc "$E_B"; run "$lib" billwatch enforce OVN_WEB_VERIFY_BASELINE=off
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red vue-tsc rc=2 (see' && echo "K_baseline_off_restores_any_red_blocking=1" || echo "K_baseline_off_restores_any_red_blocking=0"
  run "$lib" - enforce
  [ $RC = 1 ] && echo "L_no_repo_name_keeps_old_behaviour=1" || echo "L_no_repo_name_keeps_old_behaviour=0"
  tsc_green; echo 1 > "$SCN/vitest.rc"; printf ' FAIL  src/x.test.ts > does a thing\n' > "$SCN/vitest.out"
  run "$lib" tas enforce
  [ $RC = 1 ] && grep -q 'V:src/x.test.ts > does a thing' "$W/vlog" && echo "M_vitest_failures_are_signatures_too=1" || echo "M_vitest_failures_are_signatures_too=0"
  seedb "$lib" tas
  run "$lib" tas enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red-inherited' && echo "N_same_vitest_failure_is_inherited=1" || echo "N_same_vitest_failure_is_inherited=0"
  echo 0 > "$SCN/vitest.rc"; rm -f "$SCN/vitest.out"; tsc_green
  run "$lib" billwatch off
  [ $RC = 0 ] && [ -z "$OUT" ] && echo "O_mode_off_is_silent=1" || echo "O_mode_off_is_silent=0"
  # ---- review round 2 ----
  # P: per-signature counts: a SECOND error with the same code in an already-baselined file is NEW
  tsc "$E_A" "$E_B"; run "$lib" cnt shadow; seedb "$lib" cnt
  tsc "$E_A" "$E_B" "src/t/A.test.ts(55,5): error TS2339: another property"; run "$lib" cnt enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red .*(1 new / 2 inherited' && echo "P_second_same_code_error_in_a_baselined_file_is_new=1" || echo "P_second_same_code_error_in_a_baselined_file_is_new=0"
  tsc "$E_A" "$E_B"; run "$lib" cnt enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red-inherited' && echo "P2_same_counts_stay_inherited=1" || echo "P2_same_counts_stay_inherited=0"
  tsc "$E_A"; run "$lib" cnt enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red-inherited' && echo "P3_fewer_errors_than_baseline_stay_inherited=1" || echo "P3_fewer_errors_than_baseline_stay_inherited=0"
  # Q: unparseable errors (path with spaces, no file prefix) make an otherwise-inherited red NEW
  tsc "$E_A" "$E_B" "src/my dir/z.ts(1,1): error TS2304: Cannot find name"; run "$lib" cnt enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red .*1 unparseable' && grep -q 'QUALITY FAIL' "$W/vlog" && echo "Q_path_with_spaces_is_an_unparseable_new_red=1" || echo "Q_path_with_spaces_is_an_unparseable_new_red=0"
  tsc "$E_A" "$E_B" "error TS18003: No inputs were found in config file"; run "$lib" cnt enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red .*1 unparseable' && echo "Q2_error_without_a_file_prefix_is_an_unparseable_new_red=1" || echo "Q2_error_without_a_file_prefix_is_an_unparseable_new_red=0"
  printf 'sh: vue-tsc: command not found\n' > "$SCN/tsc.out"; echo 127 > "$SCN/tsc.rc"; echo 1 > "$SCN/vitest.rc"; printf ' FAIL  src/x.test.ts > does a thing\n' > "$SCN/vitest.out"; run "$lib" tas enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red ' && echo "Q3_tsc_crash_with_no_error_line_is_red_even_if_vitest_failures_are_inherited=1" || echo "Q3_tsc_crash_with_no_error_line_is_red_even_if_vitest_failures_are_inherited=0"
  echo 0 > "$SCN/vitest.rc"; rm -f "$SCN/vitest.out"; tsc "$E_A" "$E_B"; echo 1 > "$SCN/vitest.rc"; printf 'Error: failed to load config\n' > "$SCN/vitest.out"; run "$lib" cnt enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red ' && echo "Q4_vitest_crash_with_no_FAIL_line_is_red_even_if_tsc_errors_are_inherited=1" || echo "Q4_vitest_crash_with_no_FAIL_line_is_red_even_if_tsc_errors_are_inherited=0"
  echo 0 > "$SCN/vitest.rc"; rm -f "$SCN/vitest.out"; echo 0 > "$SCN/tsc.rc"; rm -f "$SCN/tsc.out"
  # R: a vue-tsc timeout must not hide a vitest red (and the reverse)
  tsc_green; echo 124 > "$SCN/tsc.rc"; echo 1 > "$SCN/vitest.rc"; printf ' FAIL  src/y.test.ts > broke\n' > "$SCN/vitest.out"; run "$lib" tmo enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red vitest related rc=1, vue-tsc timeout (no verdict)' && grep -q 'V:src/y.test.ts > broke' "$W/vlog" && echo "R_tsc_timeout_does_not_hide_a_vitest_red=1" || echo "R_tsc_timeout_does_not_hide_a_vitest_red=0"
  run "$lib" tmo shadow; [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB red vitest related rc=1, vue-tsc timeout' && echo "R2_shadow_reports_both=1" || echo "R2_shadow_reports_both=0"
  echo 0 > "$SCN/vitest.rc"; rm -f "$SCN/vitest.out"; tsc "$E_A"; echo 124 > "$SCN/vitest.rc"; run "$lib" tmo2 enforce
  [ $RC = 1 ] && echo "$OUT" | grep -q '^WEB red vue-tsc rc=2, vitest timeout (no verdict)' && echo "S_vitest_timeout_does_not_hide_a_tsc_red=1" || echo "S_vitest_timeout_does_not_hide_a_tsc_red=0"
  tsc_green; echo 124 > "$SCN/tsc.rc"; echo 0 > "$SCN/vitest.rc"; run "$lib" tmo3 enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB timeout vue-tsc timeout' && echo "T_timeout_plus_green_is_still_no_verdict=1" || echo "T_timeout_plus_green_is_still_no_verdict=0"
  echo 124 > "$SCN/tsc.rc"; echo 124 > "$SCN/vitest.rc"; run "$lib" tmo4 enforce
  [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB timeout' && echo "T2_both_timed_out_is_no_verdict=1" || echo "T2_both_timed_out_is_no_verdict=0"
  echo 0 > "$SCN/vitest.rc"; tsc_green
}
getv(){ printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2; }
real="$(suite real "$LIB0")"
NAMES="$(printf '%s\n' "$real" | cut -d= -f1 | tr '\n' ' ')"
[ "$(printf '%s\n' "$real" | grep -c .)" -ge 28 ] || ok "gate: the suite produced all its checks ($(printf '%s\n' "$real" | grep -c .))" 0
for n in $NAMES; do ok "gate: $n" "$([ "$(getv "$real" "$n")" = 1 ] && echo 1 || echo 0)"; done
mutl(){ # <label> <literal old> <literal new> <expected-failing check name>
  local m="$W/mut_$1.sh"; python3 -c 'import sys;s=open(sys.argv[1]).read();o=sys.argv[3];assert s.count(o)==1,"mutant anchor count %d"%s.count(o);open(sys.argv[2],"w").write(s.replace(o,sys.argv[4]))' "$LIB0" "$m" "$2" "$3" || { ok "MUTANT $1: the mutation applied" 0; return; }
  local r; r="$(suite "m$1" "$m")"; ok "MUTANT $1 is caught by $4" "$([ "$(getv "$r" "$4")" = 1 ] && echo 0 || echo 1)"
}
mutl compare 'awk -v bf="$1" '"'"'BEGIN{while((getline l < bf)>0) b[l]++} NF{c[$0]++; if(c[$0]>b[$0]) print}'"'"' <<< "$2"' 'printf '"'"'%s\n'"'"' "$2"' B_enforce_inherited_never_blocks
mutl counts-lost 'if(c[$0]>b[$0]) print' 'if(!($0 in b)) print' P_second_same_code_error_in_a_baselined_file_is_new
mutl inherit-blocks 'if [ "$nnew" -eq 0 ] && [ "$nunparsed" -eq 0 ]; then verdict="red-inherited"; fi' ':' B_enforce_inherited_never_blocks
mutl unparsed-ignored 'if [ "$nnew" -eq 0 ] && [ "$nunparsed" -eq 0 ]; then' 'if [ "$nnew" -eq 0 ]; then' Q_path_with_spaces_is_an_unparseable_new_red
mutl noprefix-ignored 'if [ "$ntot" -gt "$nparsed" ]; then nunparsed=$((ntot - nparsed)); elif' 'if false; then :; elif' Q2_error_without_a_file_prefix_is_an_unparseable_new_red
mutl crash-ignored '[ "$eff_t" -ne 0 ] && [ "$ntot" -eq 0 ]; then nunparsed=1; fi' 'false; then :; fi' Q3_tsc_crash_with_no_error_line_is_red_even_if_vitest_failures_are_inherited
mutl vitest-crash-ignored 'if [ "$to_v" = 0 ] && [ "$eff_v" -ne 0 ] && [ "$nv" -eq 0 ]; then nunparsed=$((nunparsed + 1)); fi' ':' Q4_vitest_crash_with_no_FAIL_line_is_red_even_if_tsc_errors_are_inherited
mutl red-writes 'return "$blocked"' '[ -n "$bf" ] && { mkdir -p "$bdir"; printf "%s\n" "$cur" > "$bf"; }; return "$blocked"' F_shadow_never_blocks_and_a_red_never_writes_the_baseline
mutl red-writes-A 'return "$blocked"' '[ -n "$bf" ] && { mkdir -p "$bdir"; printf "%s\n" "$cur" > "$bf"; }; return "$blocked"' A_first_red_is_new_and_writes_no_baseline
mutl timeout-hides-vitest 'if [ "$eff_t" -eq 0 ] && [ "$eff_v" -eq 0 ]; then echo "WEB timeout' 'if [ "$rc_t" -eq 124 ] || [ "$rc_v" -eq 124 ]; then echo "WEB timeout' R_tsc_timeout_does_not_hide_a_vitest_red
mutl timeout-hides-tsc 'if [ "$eff_t" -eq 0 ] && [ "$eff_v" -eq 0 ]; then echo "WEB timeout' 'if [ "$rc_t" -eq 124 ] || [ "$rc_v" -eq 124 ]; then echo "WEB timeout' S_vitest_timeout_does_not_hide_a_tsc_red
mutl timeout-is-green 'if [ "$eff_t" -eq 0 ] && [ "$eff_v" -eq 0 ]; then echo "WEB timeout' 'if false; then echo "WEB timeout' J_timeout_is_no_verdict_and_never_blocks
mutl green-keeps '[ -n "$bf" ] && { mkdir -p "$bdir" 2>/dev/null; : > "$bf" 2>/dev/null; }   # GREEN' ':   # GREEN' G_green_clears_the_baseline
mutl baseline-switch '"${OVN_WEB_VERIFY_BASELINE:-on}" != off ] && [ -n "$bname" ]' '-n "$bname" ]' K_baseline_off_restores_any_red_blocking
mutl shadow-blocks 'if [ "$mode" = enforce ] && [ "$verdict" = red ]; then' 'if [ "$verdict" = red ]; then' F_shadow_never_blocks_and_a_red_never_writes_the_baseline
# ---------- ops/web_verify_baseline_seed.sh (the explicit manual command) ----------
SQ="$W/seedq"; mkdir -p "$SQ/ops" "$SQ/scripts" "$SQ/state/stage_runs"; cp "$SC/lib_stage_guards.sh" "$SC/ovn_stage_guards.py" "$SQ/scripts/" 2>/dev/null; cp "$HERE/../../ops/web_verify_baseline_seed.sh" "$SQ/ops/"
printf '%s\n' "-- vue-tsc --noEmit in web --" "$E_A" "$E_A" "$E_B" ' FAIL  src/x.test.ts > a thing' > "$SQ/state/stage_runs/billwatch-1.verify.log.web.log"
out="$(bash "$SQ/ops/web_verify_baseline_seed.sh" billwatch 2>&1)"; rc=$?
ok "seed: seeds the baseline from the newest web log (counts kept: 2 x A, 1 x B, 1 vitest)" "$([ $rc = 0 ] && [ "$(grep -c 'src/t/A.test.ts|TS2339' "$SQ/state/web_verify_baseline/billwatch.sigs")" = 2 ] && grep -q '^V:src/x.test.ts > a thing$' "$SQ/state/web_verify_baseline/billwatch.sigs" && echo 1 || echo 0)"
out="$(bash "$SQ/ops/web_verify_baseline_seed.sh" billwatch --show 2>&1)"; ok "seed: --show prints and changes nothing" "$(echo "$out" | grep -q 'src/b.vue|TS6133' && echo 1 || echo 0)"
printf '%s\n' "$E_A" "src/my dir/z.ts(1,1): error TS2304: x" > "$SQ/state/stage_runs/gitlark-1.web.log"
out="$(bash "$SQ/ops/web_verify_baseline_seed.sh" gitlark 2>&1)"; rc=$?
ok "seed: a log with unattributable errors is refused (exit 3), nothing written" "$([ $rc = 3 ] && [ ! -e "$SQ/state/web_verify_baseline/gitlark.sigs" ] && echo 1 || echo 0)"
bash "$SQ/ops/web_verify_baseline_seed.sh" gitlark --force >/dev/null 2>&1; ok "seed: --force overrides" "$([ -s "$SQ/state/web_verify_baseline/gitlark.sigs" ] && echo 1 || echo 0)"
bash "$SQ/ops/web_verify_baseline_seed.sh" nolog >/dev/null 2>&1; ok "seed: no log for the repo -> exit 2" "$([ $? = 2 ] && echo 1 || echo 0)"
# the gate really uses what the seed script wrote
SD="$SQ/state"; tsc "$E_A" "$E_A" "$E_B"; : > "$W/vlog"
out="$( cd "$W" && env PATH="$W/bin:$PATH" OVN_WEB_VERIFY_STATE="$SQ/state" OVN_STAGE_WEB_VERIFY=enforce OVN_STAGE_REPO=billwatch repo="" bash -c '. "$0"; stage_web_verify "$1" "$2" "$3"' "$SC/lib_stage_guards.sh" "$WT" "$BASE" "$W/vlog" 2>&1 )"; rc=$?
ok "seed -> gate: the seeded debt is inherited (red-inherited, rc 0, not blocked)" "$([ $rc = 0 ] && echo "$out" | grep -q '^WEB red-inherited' && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" -eq 0 ]
