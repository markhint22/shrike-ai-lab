#!/usr/bin/env bash
# q-verify-web-gap (2026-11-17): a red vitest on a changed web file can never pass the staged verify, even while OVN_STAGE_WEB_VERIFY=shadow.
# Incident: billwatch overnight/feature red 33 h; fleet commit 7dfcf84a (WeeklyDigestView.vue, staged step 1, 11-16 04:50) broke WeeklyDigestView.test.ts. The step's own VERIFY ran only the new
# preview test, full_verify has no vitest FULL (OVN_STAGE_VITEST_FULL opt-in off), and the shadow web-verify logged `vitest related rc=1` but never blocked.
# Each behaviour is also run against a MUTANT of lib_stage_guards.sh and must FAIL there.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"; LIB0="$SC/lib_stage_guards.sh"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
[ -f "$LIB0" ] || { echo "  SKIP: lib_stage_guards.sh not found"; exit 77; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
WT="$W/wt"; mkdir -p "$WT/web/src" "$WT/web/node_modules"
( cd "$WT" && git init -q -b main && echo 'export const a = 1' > web/src/a.ts && printf '{"devDependencies":{"vue-tsc":"1","vitest":"1"}}' > web/package.json && git add -A && git commit -qm base && echo 'export const a = 2' > web/src/a.ts && git commit -qam change )
BASE="$(git -C "$WT" rev-parse HEAD~1)"
SCN="$W/scn"; mkdir -p "$SCN" "$W/bin"
cat > "$W/bin/npx" <<'NPX'
#!/usr/bin/env bash
case "$1" in vue-tsc) f=tsc;; vitest) f=vitest;; *) exit 0;; esac
[ -f "$SCN/$f.out" ] && cat "$SCN/$f.out"; exit "$(cat "$SCN/$f.rc" 2>/dev/null || echo 0)"
NPX
chmod +x "$W/bin/npx"; export SCN
FAILLINE=' FAIL  src/views/__tests__/WeeklyDigestView.test.ts > WeeklyDigestView > renders a section per stage with correct counts'
vit(){ echo "$1" > "$SCN/vitest.rc"; if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$SCN/vitest.out"; else rm -f "$SCN/vitest.out"; fi; }
tsc_rc(){ echo "$1" > "$SCN/tsc.rc"; if [ -n "${2:-}" ]; then printf '%s\n' "$2" > "$SCN/tsc.out"; else rm -f "$SCN/tsc.out"; fi; }
run(){ # <lib> <repo|-> <mode> [env...]
  local lib="$1" repo="$2" mode="$3"; shift 3; : > "$W/vlog"; local rn="$repo"; [ "$repo" = - ] && rn=""
  OUT="$( cd "$W" && env PATH="$W/bin:$PATH" OVN_WEB_VERIFY_STATE="$SD" OVN_STAGE_WEB_VERIFY="$mode" OVN_STAGE_REPO="$rn" repo="" "$@" bash -c '. "$0"; stage_web_verify "$1" "$2" "$3"' "$lib" "$WT" "$BASE" "$W/vlog" 2>&1 )"; RC=$?
}
suite(){ local L="$1" lib="$2"; SD="$W/sd_$L"; rm -rf "$SD"; mkdir -p "$SD/web_verify_baseline"
  tsc_rc 0; vit 1 "$FAILLINE"
  run "$lib" billwatch shadow
  [ $RC = 1 ] && grep -q 'QUALITY FAIL: vitest failed' "$W/vlog" && grep -q 'V:src/views/__tests__/WeeklyDigestView.test.ts' "$W/vlog" && echo "A_shadow_new_vitest_red_blocks=1" || echo "A_shadow_new_vitest_red_blocks=0"
  # B: shadow + a NEW red vitest while vue-tsc has only inherited debt (the billwatch case after the baseline seed)
  tsc_rc 2 'src/x.test.ts(1,1): error TS6133: unused'; printf 'src/x.test.ts|TS6133\n' > "$SD/web_verify_baseline/billwatch.sigs"
  run "$lib" billwatch shadow
  [ $RC = 1 ] && echo "B_shadow_new_vitest_red_blocks_beside_inherited_tsc_debt=1" || echo "B_shadow_new_vitest_red_blocks_beside_inherited_tsc_debt=0"
  # C: vue-tsc-only red stays shadow (whole-project debt is not this gate's job)
  vit 0; tsc_rc 2 'src/new.ts(1,1): error TS2322: bad'; run "$lib" billwatch shadow
  [ $RC = 0 ] && [ ! -s "$W/vlog" ] && echo "C_shadow_tsc_only_red_never_blocks=1" || echo "C_shadow_tsc_only_red_never_blocks=0"
  # D: a failing test already in the baseline is inherited, not blocking
  tsc_rc 0; printf '%s\n' "$FAILLINE" > "$W/d1.log"; ( . "$lib"; _sg_web_sigs "$W/d1.log" ) > "$SD/web_verify_baseline/billwatch.sigs"; vit 1 "$FAILLINE"; run "$lib" billwatch shadow
  [ $RC = 0 ] && echo "D_inherited_vitest_failure_does_not_block=1" || echo "D_inherited_vitest_failure_does_not_block=0"
  # E: vitest crash with no FAIL line blocks
  rm -f "$SD/web_verify_baseline/billwatch.sigs"; vit 1 'Error: failed to load config'; run "$lib" billwatch shadow
  [ $RC = 1 ] && echo "E_vitest_crash_without_fail_line_blocks=1" || echo "E_vitest_crash_without_fail_line_blocks=0"
  # F: vitest timeout = no verdict
  vit 124; tsc_rc 2 'src/new.ts(1,1): error TS2322: bad'; run "$lib" billwatch shadow; tsc_rc 0
  [ $RC = 0 ] && echo "F_vitest_timeout_is_no_verdict=1" || echo "F_vitest_timeout_is_no_verdict=0"
  # G: off switch restores shadow
  vit 1 "$FAILLINE"; run "$lib" billwatch shadow OVN_STAGE_WEB_VITEST_ENFORCE=off
  [ $RC = 0 ] && echo "G_off_switch_restores_shadow=1" || echo "G_off_switch_restores_shadow=0"
  # H: mode off stays silent and non-blocking
  run "$lib" billwatch off; [ $RC = 0 ] && [ -z "$OUT" ] && echo "H_mode_off_is_silent=1" || echo "H_mode_off_is_silent=0"
  # I: baseline off (or no repo name) = any vitest red blocks
  run "$lib" - shadow; [ $RC = 1 ] && echo "I_no_repo_name_any_vitest_red_blocks=1" || echo "I_no_repo_name_any_vitest_red_blocks=0"
  # J: green stays green
  vit 0; tsc_rc 0; run "$lib" billwatch shadow; [ $RC = 0 ] && echo "$OUT" | grep -q '^WEB ok' && echo "J_green_is_green=1" || echo "J_green_is_green=0"
  # K: the reporter's duration (12ms vs 15ms) must not make an inherited red look new
  tsc_rc 0; printf 'V:renders the thing\n' > "$SD/web_verify_baseline/billwatch.sigs"; vit 1 " × renders the thing 15ms"; run "$lib" billwatch shadow
  [ $RC = 0 ] && echo "K_vitest_duration_does_not_change_signature=1" || echo "K_vitest_duration_does_not_change_signature=0"
  # L: two long test names sharing their first 120 chars stay distinct (baseline has A, current run fails B => new => blocks)
  local LONG n1 n2; LONG="$(printf 'x%.0s' $(seq 1 130))"; n1="${LONG}A"; n2="${LONG}B"
  printf ' FAIL  %s\n' "$n1" > "$W/l1.log"; ( . "$lib"; _sg_web_sigs "$W/l1.log" ) > "$SD/web_verify_baseline/billwatch.sigs"
  vit 1 " FAIL  $n2"; run "$lib" billwatch shadow
  [ $RC = 1 ] && echo "L_long_names_sharing_prefix_stay_distinct=1" || echo "L_long_names_sharing_prefix_stay_distinct=0"
}
getv(){ printf '%s\n' "$1" | grep "^$2=" | cut -d= -f2; }
real="$(suite real "$LIB0")"
for n in $(printf '%s\n' "$real" | cut -d= -f1); do ok "gate: $n" "$([ "$(getv "$real" "$n")" = 1 ] && echo 1 || echo 0)"; done
[ "$(printf '%s\n' "$real" | grep -c .)" -ge 10 ] || ok "gate: all checks produced" 0
mutl(){ local m="$W/mut_$1.sh"; python3 -c 'import sys;s=open(sys.argv[1]).read();o=sys.argv[3];assert s.count(o)==1,"anchor count %d"%s.count(o);open(sys.argv[2],"w").write(s.replace(o,sys.argv[4]))' "$LIB0" "$m" "$2" "$3" || { ok "MUTANT $1: applies" 0; return; }
  local r; r="$(suite "m$1" "$m")"; ok "MUTANT $1 is caught by $4" "$([ "$(getv "$r" "$4")" = 1 ] && echo 0 || echo 1)"; }
mutl remove-step 'if [ "$vblock" = 1 ]; then' 'if false; then' A_shadow_new_vitest_red_blocks
mutl default-off 'OVN_STAGE_WEB_VITEST_ENFORCE:-on' 'OVN_STAGE_WEB_VITEST_ENFORCE:-off' A_shadow_new_vitest_red_blocks
mutl inherited-blocks '[ -n "$_vnew" ] && vblock=1' 'vblock=1' D_inherited_vitest_failure_does_not_block
mutl crash-ignored 'if [ -z "$_vs" ]; then vblock=1; elif' 'if [ -z "$_vs" ]; then :; elif' E_vitest_crash_without_fail_line_blocks
mutl timeout-blocks '[ "$to_v" = 0 ] && [ "$eff_v" -ne 0 ]; then
    if [ -n "$bf" ]' '[ "$rc_v" -ne 0 ]; then
    if [ -n "$bf" ]' F_vitest_timeout_is_no_verdict
mutl tsc-blocks 'if [ "$vblock" = 1 ]; then' 'if [ "$vblock" = 1 ] || [ "$rc_t" -ne 0 ]; then' C_shadow_tsc_only_red_never_blocks
mutl off-ignored '[ "${OVN_STAGE_WEB_VITEST_ENFORCE:-on}" != off ] && ' '' G_off_switch_restores_shadow
mutl duration-kept 's/[[:space:]]+[0-9]+(\.[0-9]+)? ?ms[[:space:]]*$//; ' '' K_vitest_duration_does_not_change_signature
mutl truncate-120 '_sg_web_shorten | sort -u; }' 'cut -c1-120 | sort -u; }' L_long_names_sharing_prefix_stay_distinct
echo "  $P passed, $F failed"; [ "$F" -eq 0 ]
