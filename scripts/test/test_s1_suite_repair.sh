#!/usr/bin/env bash
# test_s1_suite_repair.sh - package S1-suite-repair (2026-11-03), suite.json F1-F4 + notifications.json F2:
#   A. lib_fixup.sh finds test/lib_safe_tmp.sh through a symlink tree (readlink -f), via OVN_SAFE_TMP_LIB, via $OVN_DIR; with NO helper it logs a loud stderr line and ONE alerts.log warn (never a silent no-op)
#   B. lint_ntfy_tests.py lint_scripts prunes repos/ state/ logs/ prework/ worktrees/ node_modules/ .git ONLY at the top level of the root (a nested ops/repos/ is still linted)
#   C. ops/run_suite_sandboxed_cron.sh retries ONCE after a bounded wait on run_all rc 75 in cron mode (not --candidate); the empty-capture red run is recorded, not mistaken for green
#   D. ops/suite_run_log.py alerts: streak of identical-red runs: INFO once per sig, digest bullet at run 2, escalation (shadow by default) at run 3, reset on a new sig / green run; the alert path writes
#   M. mutants: each re-introduced defect must make the matching check fail.
# Deterministic: TZ pinned, no ntfy (closed port + OVN_NOTIFY_DISABLE), temp dirs via lib_safe_tmp.sh.
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/ntfy_guard.sh"
export TZ=UTC
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if [ "$1" = 1 ]; then P=$((P+1)); echo "  ok   $2"; else F=$((F+1)); echo "  FAIL $2"; fi; }
SB="$(safe_mktemp_dir s1sr)" || exit 1
trap 'safe_rm_rf "$SB"' EXIT

# $1 = queue root to test (real tree or a mutated copy)
run_checks(){
  local QX="$1" W; W="$(safe_mktemp_dir_in "$SB" chk)" || return 1
  echo "== A. lib_fixup.sh helper lookup"
  # A1: symlink tree without test/ (the fixture shape that broke 11-02)
  mkdir -p "$W/a1/scripts"; ln -s "$QX/scripts/lib_fixup.sh" "$W/a1/scripts/lib_fixup.sh"; ln -s "$QX/scripts/lib_item_select.sh" "$W/a1/scripts/lib_item_select.sh"
  local o; o="$(env -i PATH="$PATH" HOME="$W" bash -c ". '$W/a1/scripts/lib_item_select.sh'; . '$W/a1/scripts/lib_fixup.sh'; declare -F safe_mktemp_dir >/dev/null && echo DEFINED || echo MISSING" 2>&1)"
  ok "$(printf '%s' "$o" | grep -q DEFINED && echo 1 || echo 0)" "A1 a symlinked lib_fixup.sh (no test/ beside the link) still finds lib_safe_tmp.sh through the link target"
  # A2: a COPY with nothing around it: loud, once, in alerts.log
  mkdir -p "$W/a2/scripts" "$W/a2/state"; cp "$QX/scripts/lib_fixup.sh" "$QX/scripts/lib_item_select.sh" "$W/a2/scripts/"
  o="$(env -i PATH="$PATH" HOME="$W" OVN_DIR="$W/a2" bash -c ". '$W/a2/scripts/lib_item_select.sh'; . '$W/a2/scripts/lib_fixup.sh'; ovn_fixup_item_line abc123 /dev/null; ovn_fixup_item_line abc123 /dev/null; echo END" 2>&1)"
  ok "$(printf '%s' "$o" | grep -q 'WARNING test/lib_safe_tmp.sh not found' && echo 1 || echo 0)" "A2 no helper anywhere: a loud stderr line names the disabled gates"
  ok "$([ "$(grep -c 'cannot find test/lib_safe_tmp.sh' "$W/a2/state/alerts.log" 2>/dev/null)" = 1 ] && echo 1 || echo 0)" "A3 ...and exactly ONE alerts.log warn per run, even after two calls"
  # A4: OVN_SAFE_TMP_LIB override works for a copy
  o="$(env -i PATH="$PATH" HOME="$W" OVN_SAFE_TMP_LIB="$QX/scripts/test/lib_safe_tmp.sh" bash -c ". '$W/a2/scripts/lib_item_select.sh'; . '$W/a2/scripts/lib_fixup.sh'; declare -F safe_mktemp_dir >/dev/null && echo DEFINED" 2>&1)"
  ok "$(printf '%s' "$o" | grep -q DEFINED && ! printf '%s' "$o" | grep -q WARNING && echo 1 || echo 0)" "A4 OVN_SAFE_TMP_LIB override locates the helper for a bare copy"
  # A5: fallback to $OVN_DIR/scripts/test
  mkdir -p "$W/a5/scripts/test"; cp "$QX/scripts/test/lib_safe_tmp.sh" "$W/a5/scripts/test/"; mkdir -p "$W/a5b"; cp "$QX/scripts/lib_fixup.sh" "$QX/scripts/lib_item_select.sh" "$W/a5b/"
  o="$(env -i PATH="$PATH" HOME="$W" OVN_DIR="$W/a5" bash -c ". '$W/a5b/lib_item_select.sh'; . '$W/a5b/lib_fixup.sh'; declare -F safe_mktemp_dir >/dev/null && echo DEFINED" 2>&1)"
  ok "$(printf '%s' "$o" | grep -q DEFINED && echo 1 || echo 0)" "A5 a copy elsewhere falls back to \$OVN_DIR/scripts/test/lib_safe_tmp.sh"
  echo "== B. lint prune"
  local R="$W/qroot"; mkdir -p "$R/repos/iptv_apps/scripts" "$R/state/qwen_explore/work/x" "$R/logs" "$R/scripts" "$R/ops/repos"
  local bad='curl -d x "${NTFY_SERVER:-https://ntfy.s''h}/t"'
  printf '%s\n' "$bad" > "$R/repos/iptv_apps/scripts/daily-verify.sh"; printf '%s\n' "$bad" > "$R/state/qwen_explore/work/x/daily-verify.sh"; printf '%s\n' "$bad" > "$R/logs/x.sh"
  o="$(python3 "$QX/scripts/test/lint_ntfy_tests.py" --scripts "$R" 2>&1)"; local rc=$?
  ok "$([ "$rc" = 0 ] && [ -z "$o" ] && echo 1 || echo 0)" "B1 seeded repos/ state/ logs/ copies of the product line are not reported${o:+: $o}"
  printf '%s\n' "$bad" > "$R/ops/repos/real.sh"; printf '%s\n' "$bad" > "$R/scripts/real2.sh"
  o="$(python3 "$QX/scripts/test/lint_ntfy_tests.py" --scripts "$R" 2>&1)"; rc=$?
  ok "$([ "$rc" = 1 ] && printf '%s' "$o" | grep -q 'ops/repos/real.sh' && printf '%s' "$o" | grep -q 'scripts/real2.sh' && echo 1 || echo 0)" "B2 only the TOP-level dirs are pruned: a nested ops/repos/ and scripts/ are still linted"
  echo "== C. suite cron lock retry"
  local H="$W/home" QQ="$W/home/overnight-queue"; mkdir -p "$H/qtmp" "$QQ/state" "$QQ/scripts/test"
  cat > "$QQ/scripts/test/run_all_sandboxed.sh" <<'STUB'
#!/usr/bin/env bash
n=0; [ -f "$STUB_CNT" ] && n="$(cat "$STUB_CNT")"; n=$((n+1)); echo "$n" > "$STUB_CNT"
echo "stub attempt $n"
[ "$n" -le "${STUB_75_TIMES:-1}" ] && exit 75
[ -n "${STUB_FAIL_RC:-}" ] && exit "$STUB_FAIL_RC"
exit 0
STUB
  local LG="$H/qtmp/suite_cron.log" CNT="$W/cnt"
  rm -f "$CNT"; o="$(env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" STUB_75_TIMES=1 OVN_SUITE_LOG="$LG" OVN_SUITE_LOCK_RETRY_SEC=1 bash "$QX/ops/run_suite_sandboxed_cron.sh" 2>&1)"; rc=$?
  ok "$([ "$rc" = 0 ] && [ "$(cat "$CNT")" = 2 ] && printf '%s' "$o" | grep -q 'waiting 1s and retrying once' && echo 1 || echo 0)" "C1 cron mode: rc 75 then a retry that passes -> rc 0, run twice, the wait is logged"
  rm -f "$CNT"; o="$(env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" STUB_75_TIMES=9 OVN_SUITE_LOG="$LG" OVN_SUITE_LOCK_RETRY_SEC=1 bash "$QX/ops/run_suite_sandboxed_cron.sh" 2>&1)"; rc=$?
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 2 ] && echo 1 || echo 0)" "C2 still locked after the retry -> benign rc 75, exactly ONE retry (no loop)"
  rm -f "$CNT"; o="$(env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" STUB_75_TIMES=1 OVN_SUITE_LOG="$LG" OVN_SUITE_LOCK_RETRY_SEC=0 bash "$QX/ops/run_suite_sandboxed_cron.sh" 2>&1)"; rc=$?
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 1 ] && echo 1 || echo 0)" "C3 retry wait 0 disables the retry (old behaviour)"
  # C4: candidate mode never retries
  local WR="$W/wr"; mkdir -p "$WR/scripts/overnight-queue/scripts/test"; cp "$QQ/scripts/test/run_all_sandboxed.sh" "$WR/scripts/overnight-queue/scripts/test/"
  git -C "$WR" init -q && git -C "$WR" add -A && git -C "$WR" -c user.email=t@t -c user.name=t commit -q -m c && git clone -q --bare "$WR" "$H/deploy-clone" 2>/dev/null
  local SHA; SHA="$(git -C "$WR" rev-parse HEAD)"
  rm -f "$CNT"; env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" STUB_75_TIMES=1 OVN_DEPLOY_CLONE="$H/deploy-clone" OVN_SUITE_LOCK_RETRY_SEC=1 bash "$QX/ops/run_suite_sandboxed_cron.sh" --candidate "$SHA" >/dev/null 2>&1; rc=$?
  ok "$([ "$rc" = 75 ] && [ "$(cat "$CNT")" = 1 ] && echo 1 || echo 0)" "C4 --candidate mode does not retry (its caller retries hourly)"
  # C5: red run with nothing captured is recorded as red (stub exits 3 without writing failed.tsv)
  rm -f "$CNT" "$QQ/state/suite_alert_sig" "$QQ/state/suite_red_streak"; env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" STUB_75_TIMES=0 STUB_FAIL_RC=3 OVN_SUITE_LOG="$LG" bash "$QX/ops/run_suite_sandboxed_cron.sh" >/dev/null 2>&1
  ok "$(grep -q 'suite FAILED (run_all rc=3)' "$QQ/state/alerts.log" && [ -f "$QQ/state/suite_alert_sig" ] && echo 1 || echo 0)" "C5 rc!=0 with an empty capture writes a synthetic red row + alerts.log INFO (end to end through the wrapper)"
  # C6: candidate-mode runs never touch the cron red-streak / signature state
  rm -f "$QQ/state/suite_alert_sig" "$QQ/state/suite_red_streak" "$QQ/state/alerts.log" "$QQ/state/notify_notes.jsonl"
  for _i in 1 2 3; do rm -f "$CNT"; env -i HOME="$H" PATH="$PATH" TZ=UTC OVN_NOTIFY_DISABLE=1 NTFY_SERVER=http://127.0.0.1:9 STUB_CNT="$CNT" STUB_75_TIMES=0 STUB_FAIL_RC=3 OVN_DEPLOY_CLONE="$H/deploy-clone" bash "$QX/ops/run_suite_sandboxed_cron.sh" --candidate "$SHA" >/dev/null 2>&1; done
  ok "$([ ! -e "$QQ/state/suite_red_streak" ] && [ ! -e "$QQ/state/suite_alert_sig" ] && ! grep -q 'suite FAILED' "$QQ/state/alerts.log" && [ ! -s "$QQ/state/notify_notes.jsonl" ] && [ -f "$QQ/state/suite_fail_$SHA" ] && echo 1 || echo 0)" "C6 three red CANDIDATE runs: no streak/signature, no INFO/digest bullet (suite_fail verdict still recorded)"
  printf 'sigX 2\n' > "$QQ/state/suite_red_streak"; printf 'sigX\n' > "$QQ/state/suite_alert_sig"
  rm -f "$CNT"; env -i HOME="$H" PATH="$PATH" TZ=UTC STUB_CNT="$CNT" STUB_75_TIMES=0 OVN_DEPLOY_CLONE="$H/deploy-clone" bash "$QX/ops/run_suite_sandboxed_cron.sh" --candidate "$SHA" >/dev/null 2>&1
  ok "$([ "$(cat "$QQ/state/suite_red_streak" 2>/dev/null)" = "sigX 2" ] && [ -f "$QQ/state/suite_alert_sig" ] && echo 1 || echo 0)" "C7 a GREEN candidate run does not reset the cron run's streak"
  rm -f "$QQ/state/suite_alert_sig" "$QQ/state/suite_red_streak"
  echo "== D. red streak escalation"
  local ST="$W/st"; mkdir -p "$ST"; printf 'test_a.sh\t  FAIL A1 at 12:01\n' > "$W/f.tsv"
  local LOGX="$QX/ops/suite_run_log.py" E="OVN_NOTIFY_DISABLE=1 NTFY_SERVER=http://127.0.0.1:9 TZ=UTC"
  env $E python3 -I "$LOGX" alerts "$W/f.tsv" "$ST" "2026-11-03 06:00:00" >/dev/null
  ok "$([ "$(grep -c 'INFO | qtests | suite FAILED' "$ST/alerts.log")" = 1 ] && ! grep -q 'Suite red' "$ST/alerts.log" && [ ! -s "$ST/notify_notes.jsonl" ] && echo 1 || echo 0)" "D1 run 1: one INFO line, no digest bullet, no escalation"
  printf 'test_a.sh\t  FAIL A1 at 18:44\n' > "$W/f2.tsv"
  env $E python3 -I "$LOGX" alerts "$W/f2.tsv" "$ST" "2026-11-03 12:00:00" >/dev/null
  ok "$([ "$(grep -c 'INFO | qtests | suite FAILED' "$ST/alerts.log")" = 1 ] && grep -q '"title": "Suite red x2: test_a.sh"' "$ST/notify_notes.jsonl" && grep -q 'Suite red x2.*digest bullet queued' "$ST/alerts.log" && [ ! -e "$ST/notify_shadow.log" ] && echo 1 || echo 0)" "D2 run 2 (same sig, digits normalised): no second INFO, a digest bullet is buffered and logged, NOT an emergency"
  env $E python3 -I "$LOGX" alerts "$W/f2.tsv" "$ST" "2026-11-03 18:00:00" >/dev/null
  ok "$(grep -q 'escalate.*suite_red:' "$ST/notify_shadow.log" 2>/dev/null && grep -q 'escalation shadow' "$ST/alerts.log" && echo 1 || echo 0)" "D3 run 3: escalation recorded in SHADOW (notify_shadow.log + alerts.log); no push (flag default shadow)"
  ok "$([ ! -s "$ST/notify_sent.jsonl" ] && echo 1 || echo 0)" "D4 nothing was sent upstream"
  printf 'test_z.sh\t  FAIL Z new\n' > "$W/f3.tsv"
  env $E python3 -I "$LOGX" alerts "$W/f3.tsv" "$ST" "2026-11-04 00:00:00" >/dev/null
  ok "$([ "$(cut -d' ' -f2 "$ST/suite_red_streak")" = 1 ] && echo 1 || echo 0)" "D5 a different signature restarts the streak at 1"
  : > "$W/none.tsv"; env $E python3 -I "$LOGX" alerts "$W/none.tsv" "$ST" >/dev/null
  ok "$([ ! -e "$ST/suite_red_streak" ] && [ ! -e "$ST/suite_alert_sig" ] && echo 1 || echo 0)" "D6 a green run clears streak + signature"
  local nb0; nb0="$(grep -c 'Suite red x' "$ST/notify_notes.jsonl")"
  env $E OVN_ESC_SUITE=off OVN_SUITE_RED_DIGEST=off python3 -I "$LOGX" alerts "$W/f.tsv" "$ST" >/dev/null; env $E OVN_ESC_SUITE=off OVN_SUITE_RED_DIGEST=off python3 -I "$LOGX" alerts "$W/f.tsv" "$ST" >/dev/null; env $E OVN_ESC_SUITE=off OVN_SUITE_RED_DIGEST=off python3 -I "$LOGX" alerts "$W/f.tsv" "$ST" >/dev/null
  ok "$([ "$(grep -c 'Suite red x' "$ST/notify_notes.jsonl")" = "$nb0" ] && echo 1 || echo 0)" "D7 OVN_SUITE_RED_DIGEST=off: three more identical red runs add no digest bullet"
  safe_rm_rf "$W"
}
echo "##### S1 checks #####"
run_checks "$Q"
echo "== M. mutants (each must make a check fail)"
mutant(){ # name, file (relative to queue root), "anchor=>replacement"
  local name="$1" f="$2" expr="$3" M; M="$(safe_mktemp_dir_in "$SB" mut)" || return
  mkdir -p "$M/scripts/test" "$M/ops"; cp -p "$Q"/scripts/lib_fixup.sh "$Q"/scripts/lib_item_select.sh "$Q"/scripts/ovn_notify.py "$M/scripts/"; cp -p "$Q"/scripts/test/lib_safe_tmp.sh "$Q"/scripts/test/lint_ntfy_tests.py "$M/scripts/test/"; cp -p "$Q"/ops/run_suite_sandboxed_cron.sh "$Q"/ops/suite_run_log.py "$M/ops/"
  python3 -I - "$M/$f" "$expr" <<'PY'
import sys
p,e=sys.argv[1],sys.argv[2]; a,b=e.split("=>",1)
s=open(p).read(); n=s.replace(a,b,1); assert n!=s,"mutation anchor not found: "+a; open(p,"w").write(n)
PY
  local res; res="$( (run_checks "$M") 2>&1 | grep -c '^  FAIL')"
  ok "$([ "$res" -ge 1 ] && echo 1 || echo 0)" "MUTANT $name -> $res check(s) fail"
}
mutant "lib_fixup: readlink/OVN_DIR fallbacks removed" scripts/lib_fixup.sh '  for d in "$(cd "$(dirname "$here")" 2>/dev/null && pwd)" "$( [ -n "$real" ] && cd "$(dirname "$real")" 2>/dev/null && pwd)" "${OVN_DIR:+$OVN_DIR/scripts}" "${OVN_QUEUE_DIR:+$OVN_QUEUE_DIR/scripts}"; do=>  for d in "$(cd "$(dirname "$here")" 2>/dev/null && pwd)"; do'
mutant "lib_fixup: warning silenced" scripts/lib_fixup.sh '  [ -z "${_OVN_FX_NOHELPER_WARNED:-}" ] || return 0=>  return 0'
mutant "lib_fixup: warns on every call" scripts/lib_fixup.sh '  _OVN_FX_NOHELPER_WARNED=1=>  :'
mutant "lint: no top-level prune" scripts/test/lint_ntfy_tests.py 'and not (top and d in TOP_PRUNE)]=>]'
mutant "lint: prune at every depth" scripts/test/lint_ntfy_tests.py 'not (top and d in TOP_PRUNE)=>d not in TOP_PRUNE'
mutant "cron: no retry" ops/run_suite_sandboxed_cron.sh 'if [ $rc -eq 75 ] && [ -z "$CAND" ]; then=>if false; then'
mutant "cron: retry also in candidate mode" ops/run_suite_sandboxed_cron.sh 'if [ $rc -eq 75 ] && [ -z "$CAND" ]; then=>if [ $rc -eq 75 ]; then'
mutant "cron: alerts also in candidate mode" ops/run_suite_sandboxed_cron.sh 'if [ -z "$CAND" ] && [ -n "${OVN_SUITE_CAPTURE_DIR:-}" ] && [ -d "$Q/state" ]=>if [ -n "${OVN_SUITE_CAPTURE_DIR:-}" ] && [ -d "$Q/state" ]'
mutant "cron: empty capture not recorded" ops/run_suite_sandboxed_cron.sh '[ ! -s "$CAPD/failed.tsv" ]; then=>[ -s "$CAPD/failed.tsv" ] && false; then'
mutant "alerts: no streak notify" ops/suite_run_log.py '    if n >= 2:=>    if n >= 99:'
mutant "alerts: escalate already at 2" ops/suite_run_log.py '        if n >= 3:=>        if n >= 2:'
mutant "alerts: streak never resets on a new sig" ops/suite_run_log.py 'n = int(n) if old_sig == sig else 0=>n = int(n)'
mutant "alerts: green run keeps the streak" ops/suite_run_log.py 'for f in (sigf, os.path.join(state, "suite_red_streak")):=>for f in (sigf,):'
echo "  $P passed, $F failed"; [ "$F" = 0 ]
