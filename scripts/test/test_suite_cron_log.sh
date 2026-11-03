#!/usr/bin/env bash
# test_suite_cron_log.sh - package P3-suite-cron (2026-11-02): the six-hourly suite cron's log hygiene + failure alerts, and the two date bugs that made the suite fail only under cron.
#   A. ops/suite_run_log.py rotate: keeps the last N runs, IN PLACE (same inode, a held O_APPEND fd keeps appending), drops the pre-header legacy text, no-op on a missing log
#   B. ops/suite_run_log.py alerts: one INFO line per failing suite, once per run signature (digits normalised), cleared by a green run
#   C. run_all.sh capture (OVN_SUITE_CAPTURE_DIR): failing suite + first failing check recorded; default off = no tsv, same output
#   D. ops/run_suite_sandboxed_cron.sh end to end (stub run_all_sandboxed.sh): header per run, rotation to OVN_SUITE_LOG_KEEP, alert once, green run clears the signature
#   E. lib_ar_fixture.sh ar_run passes TZ through (the 18:17 CST = 00:17 UTC failure of test_auto_research_lock), F. test_k5_supply_engine pins the clock Y16 reads
#   M. mutants: every re-introduced defect must make the matching check fail.
# Deterministic: TZ pinned, no wall-clock comparisons (dates are injected / only counted).
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/lib_test_tz.sh"
OPS="$HERE/../../ops"
P=0; F=0
nl_(){ wc -l < "$1" | tr -d " "; }
ok(){ if [ "$1" = 1 ]; then P=$((P+1)); echo "  ok   $2"; else F=$((F+1)); echo "  FAIL $2"; fi; }
export NTFY_SERVER=http://127.0.0.1:9
SB="$(safe_mktemp_dir p3suite)" || exit 1
trap 'safe_rm_rf "$SB"' EXIT
LOGT="$OPS/suite_run_log.py"

# the whole check set as a function so the mutant runner can re-run it against a mutated copy of ops/ + lib
run_checks(){
  local OPSX="$1" FIXX="$2" LOGX="$1/suite_run_log.py" W; W="$(safe_mktemp_dir_in "$SB" chk)" || return 1
  echo "== A. rotate"
  local L="$W/log"; { echo "legacy line 1"; echo "legacy line 2"; for i in 1 2 3 4 5 6; do echo "=== SUITE RUN run$i"; echo "body $i"; echo "FAILED SUITES: x$i"; done; } > "$L"
  local ino0; ino0="$(ls -i "$L" | awk '{print $1}')"
  exec 7>>"$L"
  python3 -I "$LOGX" rotate "$L" 3
  echo "=== SUITE RUN run7" >&7; exec 7>&-
  ok "$([ "$(grep -c '^=== SUITE RUN' "$L")" = 4 ] && grep -q 'run4' "$L" && ! grep -q 'run3' "$L" && ! grep -q legacy "$L" && echo 1 || echo 0)" "A1 keep=3 leaves the last 3 runs (+ the run appended after), drops older runs and the legacy text"
  ok "$([ "$(ls -i "$L" | awk '{print $1}')" = "$ino0" ] && [ "$(tail -1 "$L")" = "=== SUITE RUN run7" ] && echo 1 || echo 0)" "A2 rotation is in place: same inode and a held O_APPEND fd still lands at the end"
  local before; before="$(cat "$L")"; python3 -I "$LOGX" rotate "$L" 10; ok "$([ "$(cat "$L")" = "$before" ] && echo 1 || echo 0)" "A3 fewer runs than keep: untouched"
  python3 -I "$LOGX" rotate "$W/nonexistent" 3; ok "$([ $? = 0 ] && [ ! -e "$W/nonexistent" ] && echo 1 || echo 0)" "A4 missing log: no-op, not created"
  seq 1 5000 > "$W/plain"; python3 -I "$LOGX" rotate "$W/plain" 3; ok "$([ "$(nl_ "$W/plain")" -le 2001 ] && [ "$(tail -1 "$W/plain")" = 5000 ] && echo 1 || echo 0)" "A5 a headerless legacy log is cut to its last ~2000 lines"
  echo "== B. alerts"
  local ST="$W/state"; mkdir -p "$ST"; printf 'test_a.sh\t  FAIL A1 broke at 12:01\ntest_b.sh\t  FAIL B2 other\n' > "$W/f.tsv"
  local s1; s1="$(python3 -I "$LOGX" alerts "$W/f.tsv" "$ST" "2026-11-02 00:17:00")"
  ok "$([ "$(grep -c 'INFO | qtests | suite FAILED' "$ST/alerts.log")" = 2 ] && grep -q 'suite FAILED test_a.sh:   FAIL A1 broke at 12:01\|suite FAILED test_a.sh: FAIL A1 broke at 12:01' "$ST/alerts.log" && echo 1 || echo 0)" "B1 first failing run: one INFO line per failing suite with its first failing check"
  printf 'test_a.sh\t  FAIL A1 broke at 18:44\ntest_b.sh\t  FAIL B2 other\n' > "$W/f2.tsv"; local s2; s2="$(python3 -I "$LOGX" alerts "$W/f2.tsv" "$ST" "2026-11-02 06:17:00")"
  ok "$([ "$s1" = "$s2" ] && [ "$(nl_ "$ST/alerts.log")" = 2 ] && echo 1 || echo 0)" "B2 same failing set (only digits differ) -> same signature, nothing re-alerted"
  printf 'test_a.sh\t  FAIL A1 broke at 18:44\ntest_c.sh\t  FAIL C different\n' > "$W/f3.tsv"; python3 -I "$LOGX" alerts "$W/f3.tsv" "$ST" "x" >/dev/null
  ok "$([ "$(nl_ "$ST/alerts.log")" = 4 ] && echo 1 || echo 0)" "B3 a different failing set alerts again"
  : > "$W/none.tsv"; local s4; s4="$(python3 -I "$LOGX" alerts "$W/none.tsv" "$ST")"
  ok "$([ "$s4" = none ] && [ ! -e "$ST/suite_alert_sig" ] && echo 1 || echo 0)" "B4 a green run clears the signature"
  python3 -I "$LOGX" alerts "$W/f.tsv" "$ST" "y" >/dev/null; ok "$([ "$(nl_ "$ST/alerts.log")" = 6 ] && echo 1 || echo 0)" "B5 ...so the same failure recurring after a green run alerts again"
  echo "== C. run_all.sh capture"
  local SBX="$W/ra"; mkdir -p "$SBX/cap"
  printf '#!/usr/bin/env bash\necho "  ok   fine"\nexit 0\n' > "$SBX/test_pass.sh"
  printf '#!/usr/bin/env bash\necho "  ok   first"\necho "  FAIL Z9 the real reason"\necho "  FAIL Z10 later"\nexit 1\n' > "$SBX/test_fail.sh"
  printf '#!/usr/bin/env bash\nexit 77\n' > "$SBX/test_notrun.sh"
  { sed -n '/^FAILED_SUITES=""/,/^python3(){/p' "$HERE/run_all.sh"; echo 'cd "$SBX_DIR"; bash test_pass.sh; bash test_fail.sh; python3 -c pass; bash test_notrun.sh; echo "FS=[$FAILED_SUITES]"'; } > "$SBX/driver.sh"
  local out; out="$(SBX_DIR="$SBX" OVN_SUITE_CAPTURE_DIR="$SBX/cap" bash "$SBX/driver.sh" 2>&1)"
  ok "$(printf '%s' "$out" | grep -q 'FS=\[ test_fail.sh\]' && [ "$(cat "$SBX/cap/failed.tsv" 2>/dev/null)" = "$(printf 'test_fail.sh\t  FAIL Z9 the real reason')" ] && echo 1 || echo 0)" "C1 failing suite recorded with its FIRST failing check; passing and NOT RUN (77) suites are not"
  ok "$(printf '%s' "$out" | grep -q 'FAIL Z10 later' && echo 1 || echo 0)" "C2 the suite output still reaches stdout"
  local out2; out2="$(SBX_DIR="$SBX" bash "$SBX/driver.sh" 2>&1)"; rm -f "$SBX/cap/failed.tsv"; out2b="$(SBX_DIR="$SBX" bash "$SBX/driver.sh" 2>&1)"
  ok "$([ ! -e "$SBX/cap/failed.tsv" ] && [ "$out2" = "$out" ] && echo 1 || echo 0)" "C3 default (no capture dir): nothing recorded, output identical"
  echo "== D. cron wrapper end to end"
  local H="$W/home" Q="$W/home/overnight-queue"; mkdir -p "$H/qtmp" "$Q/state" "$Q/scripts/test"
  cat > "$Q/scripts/test/run_all_sandboxed.sh" <<'EOS'
#!/usr/bin/env bash
echo "stub suite output"
if [ -f "$HOME/green" ]; then exit 0; fi
printf 'test_x.sh\t  FAIL Q1 boom %s\n' "$RANDOM" >> "$OVN_SUITE_CAPTURE_DIR/failed.tsv"
echo "FAILED SUITES: test_x.sh"; exit 1
EOS
  local LG="$H/qtmp/suite_cron.log" i rc
  for i in 1 2 3; do env -i HOME="$H" PATH="$PATH" TZ=UTC OVN_SUITE_LOG="$LG" OVN_SUITE_LOG_KEEP=2 bash "$OPSX/run_suite_sandboxed_cron.sh" >> "$LG" 2>&1; rc=$?; done
  ok "$([ "$rc" = 1 ] && [ "$(grep -c '^=== SUITE RUN' "$LG")" = 2 ] && [ "$(grep -c '^=== SUITE END rc=1' "$LG")" -ge 1 ] && grep -q 'mode=cron' "$LG" && echo 1 || echo 0)" "D1 three runs, keep=2: two run headers left, rc propagated, mode shown"
  ok "$([ "$(grep -c 'suite FAILED test_x.sh' "$Q/state/alerts.log")" = 1 ] && echo 1 || echo 0)" "D2 three identical failing runs -> ONE INFO alert line (random digits normalised)"
  ok "$([ -z "$(ls "$H/qtmp/suite" | grep '^capture\.')" ] && echo 1 || echo 0)" "D3 the per-run capture dir is removed"
  touch "$H/green"; env -i HOME="$H" PATH="$PATH" TZ=UTC OVN_SUITE_LOG="$LG" bash "$OPSX/run_suite_sandboxed_cron.sh" >> "$LG" 2>&1
  ok "$([ ! -e "$Q/state/suite_alert_sig" ] && echo 1 || echo 0)" "D4 a green run clears the alert signature"
  echo "== E. fixture TZ"
  local T2="$W/fx"; mkdir -p "$T2"
  ( T="$T2"; FAKEBIN="$T2"; PYDIR=/usr/bin; SHARED_T="$T2"; STATE="$T2"; CLONES="$T2"; BOX="$T2"; CAP="$T2"; mkdir -p "$T2/home" "$T2/tmp"
    printf '#!/usr/bin/env bash\necho "TZ=[${TZ-unset}]"\n' > "$T2/s.sh"; AR_SCRIPT="$T2/s.sh"
    eval "$(sed -n '/^ar_run(){/,/^}/p' "$FIXX")"; ar_run; cat "$T2/out.txt" ) > "$W/e.out" 2>&1
  ok "$(grep -q 'TZ=\[UTC\]' "$W/e.out" && echo 1 || echo 0)" "E1 ar_run hands the suite's TZ to the script under test (env -i used to drop it)"
  echo "== F. K5 Y16 clock"
  ok "$(grep -q '^qz.now_ts = lambda: NOW' "$HERE/test_k5_supply_engine.py" && grep -q '^time.tzset()' "$HERE/test_k5_supply_engine.py" && echo 1 || echo 0)" "F1 Y16 pins the clock _ledger_pass reads (and the process TZ)"
  safe_rm_rf "$W"
}

echo "##### P3 suite-cron checks #####"
run_checks "$OPS" "$HERE/lib_ar_fixture.sh"
echo "== M. mutants (each must make a check fail)"
mutant(){ # name, file-relative-sed on a copy
  local name="$1" f="$2" expr="$3" M; M="$(safe_mktemp_dir_in "$SB" mut)" || return
  mkdir -p "$M/ops"; cp -p "$OPS"/*.sh "$OPS"/suite_run_log.py "$M/ops/" 2>/dev/null; mkdir -p "$M/scripts/test"; cp -p "$HERE/lib_safe_tmp.sh" "$HERE/lib_ar_fixture.sh" "$M/scripts/test/"
  cp -p "$HERE"/lib_ar_fixture.sh "$M/lib_ar_fixture.sh"
  python3 -I - "$M/$f" "$expr" <<'PY'
import re,sys
p,e=sys.argv[1],sys.argv[2]; a,b=e.split("=>",1)
s=open(p).read(); n=s.replace(a,b,1); assert n!=s,"mutation anchor not found: "+a; open(p,"w").write(n)
PY
  local res; res="$( (P=0; F=0; run_checks "$M/ops" "$M/lib_ar_fixture.sh") 2>&1 | grep -c '^  FAIL')"
  ok "$([ "$res" -ge 1 ] && echo 1 || echo 0)" "MUTANT $name -> $res check(s) fail"
}
# run_checks re-sources nothing: mutants only touch copies. The nested run's own counters live in a subshell.
mutant "rotation via rewrite-and-mv" ops/suite_run_log.py 'f.seek(0)
        f.write(b"\n".join(new))
        f.truncate()=>open(path+".n","wb").write(b"\n".join(new)); os.replace(path+".n", path)'
mutant "no signature dedupe" ops/suite_run_log.py 'if old != sig:=>if True:'
mutant "green run keeps the signature" ops/suite_run_log.py '        try:
            os.remove(sigf)
        except OSError:
            pass
        return "none"=>        return "none"'
mutant "keep ignored" ops/suite_run_log.py 'if keep < 1 or not os.path.isfile(path):=>if True:'
mutant "ar_run drops TZ again" lib_ar_fixture.sh '${TZ:+TZ="$TZ"} =>'
mutant "cron wrapper never alerts" ops/run_suite_sandboxed_cron.sh 'suite_run_log.py" alerts=>suite_run_log.py" noop'
mutant "cron wrapper never rotates" ops/run_suite_sandboxed_cron.sh 'suite_run_log.py" rotate=>suite_run_log.py" noop'
echo
echo "test_suite_cron_log: $P passed, $F failed"
[ "$F" = 0 ]
