#!/usr/bin/env bash
# test_suite_cron_fx.sh - package FX-P3 (2026-11-02), reviewer minors on the suite cron wrapper + run_all.sh capture:
#   G. ops/run_suite_sandboxed_cron.sh removes its $S/capture.$$ dir on every exit path (die78 used to leak one per failed setup)
#   H. --candidate mode neither rotates the cron log nor prints the run header/footer (box_autodeploy's pre-P3 behaviour); cron mode still does
#   K. run_all.sh _ovn_first_fail prefers the suite's own "  FAIL ..." check line over a stray "FAIL:" / Traceback earlier in the output; heuristic only as fallback
#   M. mutants: each re-introduced defect must make the matching check fail.
# Deterministic: TZ pinned, ntfy pointed at a dead port, temp dirs via lib_safe_tmp.sh.
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/lib_test_tz.sh"
OPS="$HERE/../../ops"
P=0; F=0
ok(){ if [ "$1" = 1 ]; then P=$((P+1)); echo "  ok   $2"; else F=$((F+1)); echo "  FAIL $2"; fi; }
export NTFY_SERVER=http://127.0.0.1:9 TZ=UTC
SB="$(safe_mktemp_dir fxp3)" || exit 1
trap 'safe_rm_rf "$SB"' EXIT

run_checks(){ # $1 = ops dir, $2 = run_all.sh
  local OPSX="$1" RAX="$2" W; W="$(safe_mktemp_dir_in "$SB" chk)" || return 1
  local H="$W/home" Q="$W/home/overnight-queue"; mkdir -p "$H/qtmp" "$Q/state" "$Q/scripts/test"
  printf '#!/usr/bin/env bash\necho "stub suite output"\nexit 0\n' > "$Q/scripts/test/run_all_sandboxed.sh"
  echo "== G. capture dir removed on every exit path"
  local out rc
  out="$(env -i HOME="$H" PATH="$PATH" TZ=UTC OVN_DEPLOY_CLONE="$H/no-clone" bash "$OPSX/run_suite_sandboxed_cron.sh" --candidate abc123 2>&1)"; rc=$?
  ok "$([ "$rc" = 78 ] && echo 1 || echo 0)" "G0 setup failure (candidate not in deploy clone) exits 78"
  ok "$([ -z "$(ls "$H/qtmp/suite" 2>/dev/null | grep '^capture\.')" ] && echo 1 || echo 0)" "G1 die78 leaves no capture.* dir behind"
  echo "== H. candidate mode keeps the pre-P3 behaviour"
  local WR="$W/wr"; mkdir -p "$WR/scripts/overnight-queue/scripts/test"; cp "$Q/scripts/test/run_all_sandboxed.sh" "$WR/scripts/overnight-queue/scripts/test/"
  git -C "$WR" init -q && git -C "$WR" add -A && git -C "$WR" -c user.email=t@t -c user.name=t commit -q -m c && git clone -q --bare "$WR" "$H/deploy-clone" 2>/dev/null
  local SHA; SHA="$(git -C "$WR" rev-parse HEAD)"
  local LG="$H/qtmp/suite_cron.log"; { for i in 1 2 3 4 5; do echo "=== SUITE RUN old$i"; echo "body"; done; } > "$LG"; local L0; L0="$(cat "$LG")"
  out="$(env -i HOME="$H" PATH="$PATH" TZ=UTC OVN_SUITE_LOG="$LG" OVN_SUITE_LOG_KEEP=2 OVN_DEPLOY_CLONE="$H/deploy-clone" bash "$OPSX/run_suite_sandboxed_cron.sh" --candidate "$SHA" 2>&1)"; rc=$?
  ok "$([ "$rc" = 0 ] && [ -f "$Q/state/suite_pass_$SHA" ] && echo 1 || echo 0)" "H0 candidate run on the stub passes and records suite_pass"
  ok "$([ "$(cat "$LG")" = "$L0" ] && echo 1 || echo 0)" "H1 candidate mode does not rotate the cron log"
  ok "$(printf '%s' "$out" | grep -q '^=== SUITE' && echo 0 || echo 1)" "H2 candidate mode prints no run header/footer to the caller"
  ok "$(printf '%s' "$out" | grep -q 'stub suite output' && echo 1 || echo 0)" "H3 the suite output still reaches the caller"
  out="$(env -i HOME="$H" PATH="$PATH" TZ=UTC OVN_SUITE_LOG="$LG" OVN_SUITE_LOG_KEEP=2 bash "$OPSX/run_suite_sandboxed_cron.sh" 2>&1)"
  ok "$(printf '%s' "$out" | grep -q '^=== SUITE RUN' && printf '%s' "$out" | grep -q '^=== SUITE END rc=0' && [ "$(grep -c '^=== SUITE RUN' "$LG")" -le 2 ] && echo 1 || echo 0)" "H4 cron mode still rotates and prints header + footer"
  echo "== K. first failing line"
  local SBX="$W/ra"; mkdir -p "$SBX/cap"
  printf '#!/usr/bin/env bash\necho "setup note FAIL: expected during fixture"\necho "Traceback (most recent call last): handled"\necho "  ok   first"\necho "  FAIL Z9 the real reason"\nexit 1\n' > "$SBX/test_a.sh"
  printf '#!/usr/bin/env bash\necho "noise"\necho "boom FAIL: only heuristic line"\nexit 1\n' > "$SBX/test_b.sh"
  { sed -n '/^FAILED_SUITES=""/,/^python3(){/p' "$RAX"; echo 'cd "$SBX_DIR"; bash test_a.sh; bash test_b.sh'; } > "$SBX/driver.sh"
  SBX_DIR="$SBX" OVN_SUITE_CAPTURE_DIR="$SBX/cap" bash "$SBX/driver.sh" >/dev/null 2>&1
  ok "$([ "$(grep '^test_a.sh' "$SBX/cap/failed.tsv" | cut -f2)" = "  FAIL Z9 the real reason" ] && echo 1 || echo 0)" "K1 the suite's own '  FAIL' check line wins over an earlier stray FAIL:/Traceback"
  ok "$([ "$(grep '^test_b.sh' "$SBX/cap/failed.tsv" | cut -f2)" = "boom FAIL: only heuristic line" ] && echo 1 || echo 0)" "K2 no '  FAIL' line: falls back to the heuristic"
  safe_rm_rf "$W"
}
echo "##### FX-P3 checks #####"
run_checks "$OPS" "$HERE/run_all.sh"
echo "== M. mutants (each must make a check fail)"
mutant(){ # name, file (ops/x or run_all.sh), "anchor=>replacement"
  local name="$1" f="$2" expr="$3" M; M="$(safe_mktemp_dir_in "$SB" mut)" || return
  mkdir -p "$M/ops" "$M/scripts/test"; cp -p "$OPS"/*.sh "$OPS"/*.py "$M/ops/" 2>/dev/null; cp -p "$HERE/lib_safe_tmp.sh" "$HERE/run_all.sh" "$M/scripts/test/"
  python3 -I - "$M/$f" "$expr" <<'PY'
import sys
p,e=sys.argv[1],sys.argv[2]; a,b=e.split("=>",1)
s=open(p).read(); n=s.replace(a,b,1); assert n!=s,"mutation anchor not found: "+a; open(p,"w").write(n)
PY
  local res; res="$( (run_checks "$M/ops" "$M/scripts/test/run_all.sh") 2>&1 | grep -c '^  FAIL')"
  ok "$([ "$res" -ge 1 ] && echo 1 || echo 0)" "MUTANT $name -> $res check(s) fail"
}
mutant "no capture cleanup on exit" ops/run_suite_sandboxed_cron.sh 'if [ -n "${CAPD:-}" ] && [ -d "$CAPD" ]; then=>if false; then'
mutant "candidate rotates log" ops/run_suite_sandboxed_cron.sh '[ -n "$CAND" ] || python3 -I "$HERE_LOG/suite_run_log.py" rotate=>python3 -I "$HERE_LOG/suite_run_log.py" rotate'
mutant "candidate prints header" ops/run_suite_sandboxed_cron.sh '[ -n "$CAND" ] || echo "=== SUITE RUN=>echo "=== SUITE RUN'
mutant "candidate prints footer" ops/run_suite_sandboxed_cron.sh '[ -n "$CAND" ] || echo "=== SUITE END=>echo "=== SUITE END'
mutant "loose first-fail only" scripts/test/run_all.sh "grep -a -m1 -E '^  (FAIL|not ok)' \"\$2\"=>false"
echo
echo "test_suite_cron_fx: $P passed, $F failed"
[ "$F" = 0 ]
