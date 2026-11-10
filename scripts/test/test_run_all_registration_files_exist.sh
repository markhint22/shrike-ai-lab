#!/usr/bin/env bash
# Z8a (2026-11-10): a test file NAMED in run_all.sh but absent from scripts/test made the box suite red (2026-11-09 deploy tar omitted the Mac-only test_z6_notify_guard.sh; the unguarded
# `bash test_z6_notify_guard.sh` -> rc=1 on two consecutive suite crons). Contract proven here (real run_all.sh + real lint, synthetic fixtures, mutants):
#   A. every test file registered in the REAL run_all.sh exists next to it, or is registered via run_if_present (lint_run_all_registration.py is clean on this tree)
#   B. the lint catches an unguarded registration of a missing file and accepts the run_if_present form; comment lines are ignored
#   C. run_if_present (extracted from the real run_all.sh): missing file => SKIP line + rc 0 + rc untouched; present+passing => runs; present+failing => rc=1
#   D. the deploy-tar check (--tar-list): an unguarded registered file missing from the tar is flagged; run_if_present and Darwin-block files are exempt
#   E. incident replay: the pre-Z8a line (`bash test_z6_notify_guard.sh || rc=1`) with the file absent is flagged; docs/FLEET_RUNBOOK.md documents the tar check
#   F. mutants: lint with the missing-file rule removed, run_if_present that always runs bash -> assertions FAIL
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
RA="$HERE/run_all.sh"; LINT="$HERE/lint_run_all_registration.py"
[ -f "$RA" ] && [ -f "$LINT" ] || { echo "  FAIL: run_all.sh / lint_run_all_registration.py missing"; exit 1; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir z8a)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
lint(){ "$PY" "$1" "$2" "$3" ${4:+--tar-list "$4"} 2>&1; }

echo "== A: the real tree"
out="$(lint "$LINT" "$RA" "$HERE")"; rc=$?
ok "A1 every test named in the real run_all.sh exists or is run_if_present-guarded${out:+ - $out}" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "A2 test_z6_notify_guard.sh (Mac-only) is registered through run_if_present" "$(grep -qE '^echo; .*run_if_present test_z6_notify_guard\.sh' "$RA" && echo 1 || echo 0)"
ok "A3 the safety-net loop and register_new_tests.py both recognise run_if_present registrations" "$(grep -q '(bash|run_or_notrun|run_if_present) \$_t' "$RA" && grep -q 'run_or_notrun|run_if_present' "$HERE/register_new_tests.py" && echo 1 || echo 0)"

echo "== B: lint behaviour on fixtures"
D="$T/b"; mkdir -p "$D"; : > "$D/test_have.sh"
printf '%s\n' '# bash test_commented_out.sh || rc=1' 'bash test_have.sh || rc=1' 'python3 test_have.sh' > "$D/ok.sh"
lint "$LINT" "$D/ok.sh" "$D" >/dev/null; ok "B1 existing files + a commented-out missing name => clean" "$([ $? = 0 ] && echo 1 || echo 0)"
printf '%s\n' 'bash test_gone.sh || rc=1' > "$D/bad1.sh"
o="$(lint "$LINT" "$D/bad1.sh" "$D")"; r=$?
ok "B2 an unguarded registration of a missing file is flagged (rc 1, names the file)" "$([ $r = 1 ] && case "$o" in *test_gone.sh*) echo 1;; *) echo 0;; esac || echo 0)"
printf '%s\n' 'run_or_notrun test_gone2.sh' > "$D/bad2.sh"
lint "$LINT" "$D/bad2.sh" "$D" >/dev/null; ok "B3 the run_or_notrun form is flagged too" "$([ $? = 1 ] && echo 1 || echo 0)"
printf '%s\n' 'run_if_present test_gone.sh' > "$D/good.sh"
lint "$LINT" "$D/good.sh" "$D" >/dev/null; ok "B4 run_if_present of a missing file is accepted" "$([ $? = 0 ] && echo 1 || echo 0)"

echo "== C: run_if_present (extracted from the real run_all.sh)"
FN="$(grep '^run_if_present(){' "$RA")"
ok "C0 extracted a one-line run_if_present" "$([ -n "$FN" ] && echo 1 || echo 0)"
cdrive(){ # $1 = function text; prints "rc=<rc> out=<lines>" ; scratch has test_pass.sh / test_fail.sh
  local d="$T/c.$RANDOM"; mkdir -p "$d"; printf 'echo RAN-PASS\nexit 0\n' > "$d/test_pass.sh"; printf 'echo RAN-FAIL\nexit 1\n' > "$d/test_fail.sh"
  ( cd "$d" && rc=0 && eval "$1" && run_if_present test_absent.sh && echo "after-absent rc=$rc" && run_if_present test_pass.sh && echo "after-pass rc=$rc" && run_if_present test_fail.sh; echo "final rc=$rc" ) 2>&1
}
co="$(cdrive "$FN")"
ok "C1 a missing file prints a SKIP line and leaves rc at 0" "$(echo "$co" | grep -q 'SKIP: test_absent.sh not present' && echo "$co" | grep -q 'after-absent rc=0' && echo 1 || echo 0)"
ok "C2 a present passing suite runs and rc stays 0" "$(echo "$co" | grep -q RAN-PASS && echo "$co" | grep -q 'after-pass rc=0' && echo 1 || echo 0)"
ok "C3 a present failing suite sets rc=1" "$(echo "$co" | grep -q RAN-FAIL && echo "$co" | grep -q 'final rc=1' && echo 1 || echo 0)"

echo "== D: deploy-tar check"
D2="$T/d"; mkdir -p "$D2"; : > "$D2/test_a.sh"; : > "$D2/test_b.sh"; : > "$D2/test_mac.sh"; : > "$D2/test_opt.sh"
cat > "$D2/ra.sh" <<'RA'
bash test_a.sh || rc=1
bash test_b.sh || rc=1
run_if_present test_opt.sh
if [[ "$(uname)" == "Darwin" ]]; then
  bash test_mac.sh || rc=1
else
  echo skipped
fi
RA
printf '%s\n' './test_a.sh' './test_b.sh' > "$D2/tar_full.txt"; printf '%s\n' './test_a.sh' > "$D2/tar_missing_b.txt"
lint "$LINT" "$D2/ra.sh" "$D2" "$D2/tar_full.txt" >/dev/null; ok "D1 tar has every unguarded non-Darwin test => clean (run_if_present + Darwin-block files exempt)" "$([ $? = 0 ] && echo 1 || echo 0)"
o="$(lint "$LINT" "$D2/ra.sh" "$D2" "$D2/tar_missing_b.txt")"; r=$?
ok "D2 an unguarded registered test missing from the tar is flagged" "$([ $r = 1 ] && case "$o" in *test_b.sh*NOT\ in\ the\ deploy\ tar*) echo 1;; *) echo 0;; esac || echo 0)"
ok "D3 only the missing one is flagged (test_a.sh, the guarded and the Darwin ones are not)" "$(echo "$o" | grep -c 'deploy tar' | grep -qx 1 && echo 1 || echo 0)"

echo "== E: incident replay + runbook"
E="$T/e"; mkdir -p "$E"; : > "$E/test_other.sh"
printf '%s\n' 'bash test_other.sh || rc=1' 'echo; echo "===== Z6 ====="; bash test_z6_notify_guard.sh || rc=1' > "$E/ra.sh"
o="$(lint "$LINT" "$E/ra.sh" "$E")"; r=$?
ok "E1 the pre-Z8a registration with the Mac-only file absent is flagged" "$([ $r = 1 ] && case "$o" in *test_z6_notify_guard.sh*) echo 1;; *) echo 0;; esac || echo 0)"
RB="$HERE/../../../../docs/FLEET_RUNBOOK.md"
if [ -f "$RB" ]; then ok "E2 docs/FLEET_RUNBOOK.md documents the deploy-tar registration check" "$(grep -q 'lint_run_all_registration.py' "$RB" && grep -q 'run_if_present' "$RB" && echo 1 || echo 0)"; else echo "  (E2 skipped: runbook not on this host)"; fi

echo "== F: mutants"
if [ "${UDIFF_TEST_NO_MUTATION:-0}" = 1 ]; then echo "  (mutation controls skipped: nested run)"; else
  sed 's/if interp != "run_if_present" and not exists/if False/; s/if not exists and interp != "run_if_present":/if False:/' "$LINT" > "$T/mut_lint.py"
  cmp -s "$LINT" "$T/mut_lint.py" && ok "F0 mutant lint differs from the real one" 0
  lint "$T/mut_lint.py" "$E/ra.sh" "$E" >/dev/null
  ok "F1 MUTANT lint without the missing-file rule passes the incident shape (so B2/E1 genuinely depend on the rule)" "$([ $? = 0 ] && echo 1 || echo 0)"
  MF="$(printf '%s' "$FN" | sed 's/if \[ -f "\$1" \]; then bash "\$1" || rc=1; else/if true; then bash "$1" || rc=1; else/')"
  [ "$MF" != "$FN" ] || ok "F0b mutant run_if_present differs" 0
  mo="$(cdrive "$MF")"
  ok "F2 MUTANT run_if_present that always runs bash => the missing file turns rc to 1 (C1 would FAIL)" "$(echo "$mo" | grep -q 'after-absent rc=0' && echo 0 || echo 1)"
fi
echo "run_all registration: $P passed, $F failed"; [ "$F" = 0 ]
