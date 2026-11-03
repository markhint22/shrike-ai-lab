#!/usr/bin/env bash
# Bash wrapper so run_all.sh executes test_k6_reliability.py (package K6-reliability, 2026-11-03: cron beats checker + manifest + heartbeat line, forecast heartbeat row; includes the mutant runner),
# then the shell-side checks: ops/cron_beat.sh, ops/qtmp_reaper.sh, ovn_log_cap.sh SUMMARY line, lib_fixup.sh ovn_qe_gate_beat. Every behaviour assertion is also run against a MUTANT and must fail there.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
PY="$(type -P python3.12 || type -P python3)"
"$PY" "$HERE/test_k6_reliability.py"; prc=$?
echo "test_k6_reliability.py rc=$prc"
Q="$(cd "$HERE/../.." && pwd)"
BEAT="$Q/ops/cron_beat.sh"; REAP="$Q/ops/qtmp_reaper.sh"; CAP="$Q/scripts/ovn_log_cap.sh"; FIXUP="$Q/scripts/lib_fixup.sh"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir k6sh)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
mut(){ # name file old new -> $T/<name> (a mutated copy); returns 1 when the pattern is missing or the copy equals the original
  python3 - "$2" "$3" "$4" "$T/$1" <<'PY' || return 1
import sys
src = open(sys.argv[1]).read()
if sys.argv[2] not in src:
    sys.exit(1)
open(sys.argv[4], "w").write(src.replace(sys.argv[2], sys.argv[3], 1))
PY
  chmod +x "$T/$1"
}

echo "== cron_beat.sh"
B="$T/beats"
run_beat(){ OVN_BEATS_DIR="$B" bash "${BEATUNDER:-$BEAT}" "$@"; }
run_beat j_ok true; rc=$?
ok "B1 rc 0 is passed through and the beat is one line 'ts= rc=0 start= dur= last_ok='" "$([ "$rc" = 0 ] && [ "$(wc -l < "$B/j_ok" | tr -d ' ')" = 1 ] && grep -Eq '^ts=[0-9]+ rc=0 start=[0-9]+ dur=[0-9]+ last_ok=[0-9]+$' "$B/j_ok" && echo 1 || echo 0)"
run_beat j_fail sh -c 'exit 7'; rc=$?
ok "B2 the wrapped exit code 7 is the wrapper's exit code and is recorded (rc=7, last_ok=0)" "$([ "$rc" = 7 ] && grep -q 'rc=7 ' "$B/j_fail" && grep -q 'last_ok=0$' "$B/j_fail" && echo 1 || echo 0)"
run_beat j_fail true; ok_ts="$(sed -n 's/.*last_ok=\([0-9]*\).*/\1/p' "$B/j_fail")"; run_beat j_fail sh -c 'exit 3'; rc=$?
ok "B3 a later failure keeps the last_ok of the previous success" "$([ "$rc" = 3 ] && grep -q "rc=3 " "$B/j_fail" && grep -q "last_ok=$ok_ts\$" "$B/j_fail" && [ "$ok_ts" != 0 ] && echo 1 || echo 0)"
run_beat j_nf definitely-not-a-command-k6 2>/dev/null; rc=$?
ok "B4 a command that cannot be found exits 127 and beats rc=127" "$([ "$rc" = 127 ] && grep -q 'rc=127 ' "$B/j_nf" && echo 1 || echo 0)"
out="$(printf 'hello\nworld\n' | run_beat j_in cat)"
ok "B5 stdin and stdout pass through unchanged" "$([ "$out" = "$(printf 'hello\nworld')" ] && echo 1 || echo 0)"
OVN_BEATS_DIR="/proc/k6-no-such-dir/x" bash "$BEAT" j_ro sh -c 'exit 5'; rc=$?
ok "B6 an unwritable beats dir never changes the exit code (5) and prints nothing extra" "$([ "$rc" = 5 ] && echo 1 || echo 0)"
touch "$T/ro_file"; OVN_BEATS_DIR="$T/ro_file" bash "$BEAT" j_ro2 true; rc=$?
ok "B7 a beats 'dir' that is a regular file: still rc 0" "$([ "$rc" = 0 ] && echo 1 || echo 0)"
run_beat '../escape' true; rc1=$?; run_beat 'bad name' true; rc2=$?
ok "B8 a job name with a path component / space is not recorded anywhere (no escape from the beats dir), job still runs" "$([ "$rc1" = 0 ] && [ "$rc2" = 0 ] && [ ! -e "$T/escape" ] && [ ! -e "$B/bad name" ] && echo 1 || echo 0)"
run_beat >/dev/null 2>&1; rc=$?
ok "B9 no arguments is a usage error (rc 2), not a silent success" "$([ "$rc" = 2 ] && echo 1 || echo 0)"
OVN_BEATS=off OVN_BEATS_DIR="$B" bash "$BEAT" j_off true
ok "B10 OVN_BEATS=off runs the job and writes no beat" "$([ ! -e "$B/j_off" ] && echo 1 || echo 0)"
OVN_BEATS_DIR="$B" bash "$BEAT" j_term sleep 30 & bp=$!
sleep 1; kill -TERM "$bp" 2>/dev/null; wait "$bp" 2>/dev/null; rc=$?
ok "B11 killed by SIGTERM: exit 143 and the beat records rc=143 (a killed cron still beats)" "$([ "$rc" = 143 ] && grep -q 'rc=143 ' "$B/j_term" && echo 1 || echo 0)"
S1="$(cat "$B/.since" 2>/dev/null)"; sleep 1; run_beat j_since2 true; S2="$(cat "$B/.since" 2>/dev/null)"
ok "B13 the wrapper writes the global tracking marker .since ONCE (first beat) and never moves it" "$(case "$S1" in ''|*[!0-9]*) echo 0;; *) [ "$S1" = "$S2" ] && echo 1 || echo 0;; esac)"
mut m_since "$BEAT" '[ -e "$BEATS/.since" ] || ( set -C; printf' '( printf' && { rm -f "$B/.since"; BEATUNDER="$T/m_since" run_beat ms1 true; sleep 1; BEATUNDER="$T/m_since" run_beat ms2 true; M2="$(cat "$B/.since" 2>/dev/null)"; ok "MUTANT: .since rewritten on every beat -> B13 would FAIL" "$([ -n "$M2" ] && [ "$M2" != "$(sed -n 's/^ts=\([0-9]*\).*/\1/p' "$B/ms1")" ] && echo 1 || echo 0)"; } || ok "mutant anchor m_since" 0
ls "$B" | grep -q '^\.' && ok "B12 no temp file is left behind in the beats dir" 0 || ok "B12 no temp file is left behind in the beats dir" 1
# mutants
mut m_rc "$BEAT" 'beat "$rc"
exit "$rc"' 'beat "$rc"
exit 0' && { BEATUNDER="$T/m_rc" run_beat mj sh -c 'exit 7'; mrc=$?; ok "MUTANT: wrapper swallows the exit code -> B2 would FAIL" "$([ "$mrc" = 7 ] && echo 0 || echo 1)"; } || ok "mutant anchor m_rc" 0
mut m_nobeat "$BEAT" 'beat "$rc"
exit "$rc"' 'exit "$rc"' && { rm -f "$B/mj2"; BEATUNDER="$T/m_nobeat" run_beat mj2 true; ok "MUTANT: no beat on a normal exit -> B1 would FAIL" "$([ -f "$B/mj2" ] && echo 0 || echo 1)"; } || ok "mutant anchor m_nobeat" 0
mut m_sig "$BEAT" 'beat $((128 + n)); exit $((128 + n))' 'exit $((128 + n))' && { rm -f "$B/j_term2"; OVN_BEATS_DIR="$B" bash "$T/m_sig" j_term2 sleep 30 & bp=$!; sleep 1; kill -TERM "$bp" 2>/dev/null; wait "$bp" 2>/dev/null; ok "MUTANT: no beat on SIGTERM -> B11 would FAIL" "$([ -f "$B/j_term2" ] && echo 0 || echo 1)"; } || ok "mutant anchor m_sig" 0
mut m_name "$BEAT" 'case "$job" in *[!A-Za-z0-9._-]*|.*) job_ok=0;; *) job_ok=1;; esac' 'job_ok=1' && { rm -rf "$T/escape"; mkdir -p "$B/sub"; BEATUNDER="$T/m_name" run_beat 'bad name' true; ok "MUTANT: no job-name check -> an unsafe name is recorded (B8 would FAIL)" "$([ -f "$B/bad name" ] && echo 1 || echo 0)"; } || ok "mutant anchor m_name" 0
mut m_lastok "$BEAT" 'lastok="$prev";;' 'lastok=0;;' && { BEATUNDER="$T/m_lastok" run_beat mj3 true; BEATUNDER="$T/m_lastok" run_beat mj3 sh -c 'exit 3'; ok "MUTANT: last_ok not carried over -> B3 would FAIL" "$(grep -q 'last_ok=0$' "$B/mj3" && echo 1 || echo 0)"; } || ok "mutant anchor m_lastok" 0
mut m_stdin "$BEAT" '"$@" <&0 &' '"$@" &' && { o2="$(printf 'x\n' | BEATUNDER="$T/m_stdin" run_beat mj4 cat)"; ok "MUTANT: background child loses stdin -> B5 would FAIL" "$([ "$o2" = x ] && echo 0 || echo 1)"; } || ok "mutant anchor m_stdin" 0

echo "== qtmp_reaper.sh"
mkfix(){ # fixture root with: old (stale), fresh, heldpid (stale but a live pid file), keepme (.keep), named (OVN_QTMP_KEEP), deep (old top, fresh file deep inside), plain file, dot dir, symlink
  safe_rm_rf "$T/qt" "$T/outside"; mkdir -p "$T/qt/old/sub" "$T/qt/fresh" "$T/qt/heldpid" "$T/qt/keepme" "$T/qt/named" "$T/qt/deep/a/b" "$T/qt/.dotdir" "$T/outside"
  echo d > "$T/qt/old/sub/f"; echo d > "$T/qt/fresh/f"; echo d > "$T/qt/heldpid/f"; echo $$ > "$T/qt/heldpid/run.pid"; echo d > "$T/qt/keepme/f"; : > "$T/qt/keepme/.keep"; echo d > "$T/qt/named/f"
  echo d > "$T/qt/deep/a/b/fresh_file"; echo log > "$T/qt/suite_cron.log"; echo d > "$T/qt/.dotdir/f"; echo precious > "$T/outside/precious"; ln -s "$T/outside" "$T/qt/linkdir"
  for p in old/sub/f old/sub old heldpid/f heldpid/run.pid heldpid keepme/f keepme/.keep keepme named/f named suite_cron.log .dotdir/f .dotdir deep/a deep; do touch -t 202001010000 "$T/qt/$p"; done
  touch -t 202001010000 "$T/qt/deep/a/b"; touch -h -t 202001010000 "$T/qt/linkdir"
}
reap(){ ( export TMPDIR="$T" OVN_QTMP_KEEP=named OVN_SAFE_LIB="${OVN_SAFE_LIB:-$HERE/lib_safe_tmp.sh}"; bash "${REAPUNDER:-$REAP}" --root "$T/qt" "$@" ) > "$T/rout" 2>&1; echo $? > "$T/rrc"; }
mkfix; reap
ok "Q1 dry run (default): exit 0, 'WOULD reap old', and NOTHING was deleted" "$([ "$(cat "$T/rrc")" = 0 ] && grep -q 'WOULD reap old ' "$T/rout" && [ -d "$T/qt/old/sub" ] && echo 1 || echo 0)"
ok "Q2 the dry-run summary is one line with 'would reclaim' and 'mode=dry-run'" "$([ "$(grep -c 'SUMMARY' "$T/rout")" = 1 ] && grep 'SUMMARY' "$T/rout" | grep -q 'mode=dry-run .*would reclaim' && echo 1 || echo 0)"
ok "Q3 only 'old' is a candidate (fresh, held, .keep, named, deep-fresh, files, dot dirs and symlinks are not)" "$([ "$(grep -c 'WOULD reap' "$T/rout")" = 1 ] && echo 1 || echo 0)"
mkfix; reap --apply
ok "Q4 --apply removes exactly 'old'" "$([ ! -e "$T/qt/old" ] && echo 1 || echo 0)"
ok "Q5 fresh / heldpid (live pid file) / keepme / named / deep (fresh file at depth) survive" "$([ -d "$T/qt/fresh" ] && [ -d "$T/qt/heldpid" ] && [ -d "$T/qt/keepme" ] && [ -d "$T/qt/named" ] && [ -f "$T/qt/deep/a/b/fresh_file" ] && echo 1 || echo 0)"
ok "Q6 the plain file, the dot dir, the symlink and its target outside the root survive" "$([ -f "$T/qt/suite_cron.log" ] && [ -d "$T/qt/.dotdir" ] && [ -L "$T/qt/linkdir" ] && [ "$(cat "$T/outside/precious")" = precious ] && echo 1 || echo 0)"
ok "Q7 NOTHING outside the fixture root was touched (the sandbox root and sibling dir are intact)" "$([ -d "$T/outside" ] && [ -d "$T" ] && [ -f "$T/beats/j_ok" ] && echo 1 || echo 0)"
mkfix; ( export OVN_QTMP_REAP=on TMPDIR="$T" OVN_QTMP_KEEP=named; bash "$REAP" --root "$T/qt" ) > "$T/rout" 2>&1
ok "Q8 OVN_QTMP_REAP=on (the cron spelling) applies" "$([ ! -e "$T/qt/old" ] && echo 1 || echo 0)"
mkfix; reap --apply --days 100000
ok "Q9 --days 100000: nothing is old enough (everything kept)" "$([ -d "$T/qt/old" ] && echo 1 || echo 0)"
mkfix; ( sleep 20 & echo $! > "$T/qt/old/live.pid"; touch -t 202001010000 "$T/qt/old/live.pid" "$T/qt/old"; reap --apply; kill "$!" 2>/dev/null )
ok "Q10 a stale dir whose pid file names a LIVE process is kept" "$([ -d "$T/qt/old" ] && echo 1 || echo 0)"
mkfix; rm -f "$T/qt/heldpid/run.pid"; echo 99999999 > "$T/qt/heldpid/run.pid"; touch -t 202001010000 "$T/qt/heldpid/run.pid" "$T/qt/heldpid"; reap --apply
ok "Q11 a pid file naming a DEAD pid does not hold the dir" "$([ ! -e "$T/qt/heldpid" ] && echo 1 || echo 0)"
if command -v lsof >/dev/null 2>&1; then
  mkfix; ( exec 8< "$T/qt/old/sub/f"; reap --apply; exec 8<&- )
  ok "Q12 a stale dir with an OPEN file (lsof) is kept" "$([ -d "$T/qt/old" ] && echo 1 || echo 0)"
else echo "  skip Q12 (no lsof on this host)"; fi
mkfix; mkdir -p "$T/emptybin"; for t in bash find du awk date dirname basename head tr kill cat sed ls mkdir rm getconf id; do ln -sf "$(command -v $t)" "$T/emptybin/$t" 2>/dev/null; done
( OVN_QTMP_NO_LSOF_OK=0; export PATH="$T/emptybin"; reap --apply )
ok "Q13 without lsof/fuser and without a pid file the entry is KEPT (fail closed)" "$([ -d "$T/qt/old" ] && echo 1 || echo 0)"
mkdir -p "$T/noroot"; ( reap --root "$T/does-not-exist" ); ok "Q14 a missing root is a clean no-op, exit 0" "$([ "$(cat "$T/rrc")" = 0 ] && echo 1 || echo 0)"
mkfix; ( export OVN_SAFE_LIB="$T/no-such-lib.sh"; reap --apply )
ok "Q15 lib_safe_tmp.sh not loadable -> --apply is REFUSED (dry run only), nothing deleted" "$([ -d "$T/qt/old" ] && grep -q 'refusing --apply' "$T/rout" && echo 1 || echo 0)"
# root = HOME (a mis-set OVN_QTMP): refuse the whole run
rhome(){ ( mkdir -p "$T/hm"; safe_set_sandbox_home "$T/hm" || exit 1; mkdir -p "$HOME/proj"; echo keep > "$HOME/proj/f"; touch -t 202001010000 "$HOME/proj/f" "$HOME/proj"; export HOME TMPDIR="$T"; OVN_SAFE_LIB="$HERE/lib_safe_tmp.sh" bash "${REAPUNDER:-$REAP}" --root "$HOME" --apply ) > "$T/rout" 2>&1; }
rhome
ok "Q16 root = HOME is refused ('refusing root'): nothing under it is touched" "$([ -d "$T/hm/home/proj" ] && grep -q 'refusing root' "$T/rout" && echo 1 || echo 0)"
( mkdir -p "$T/hm2"; safe_set_sandbox_home "$T/hm2" || exit 1; export HOME TMPDIR="$T"; OVN_SAFE_LIB="$HERE/lib_safe_tmp.sh" bash "$REAP" --root "$T" --apply ) > "$T/rout" 2>&1
ok "Q17 a root that CONTAINS HOME is refused too" "$(grep -q 'refusing root' "$T/rout" && echo 1 || echo 0)"
# mutants
mut r_dry "$REAP" '  else say "WOULD reap $n' '  else safe_rm_rf "$e"; say "WOULD reap $n' && { mkfix; REAPUNDER="$T/r_dry" reap; ok "MUTANT: the dry run deletes -> Q1 would FAIL" "$([ -d "$T/qt/old" ] && echo 0 || echo 1)"; } || ok "mutant anchor r_dry" 0
mut r_fresh "$REAP" 'if [ -n "$(find "$e" -mmin "-$MIN" -print -quit 2>/dev/null)" ]; then' 'if [ -n "$(find "$e" -maxdepth 0 -mmin "-$MIN" -print -quit 2>/dev/null)" ]; then' && { mkfix; REAPUNDER="$T/r_fresh" reap --apply; ok "MUTANT: freshness judged on the top dir only -> Q5 would FAIL (a dir with a fresh file at depth is reaped)" "$([ -d "$T/qt/deep" ] && echo 0 || echo 1)"; } || ok "mutant anchor r_fresh" 0
mut r_pid "$REAP" '    [ -n "$p" ] && kill -0 "$p" 2>/dev/null && return 0' '    :' && { mkfix; ( OVN_QTMP_NO_LSOF_OK=1 REAPUNDER="$T/r_pid"; export REAPUNDER OVN_QTMP_NO_LSOF_OK; reap --apply ); ok "MUTANT: pid files ignored -> Q5 would FAIL (heldpid reaped)" "$([ -d "$T/qt/heldpid" ] && echo 0 || echo 1)"; } || ok "mutant anchor r_pid" 0
mut r_keep "$REAP" '  [ -e "$2/.keep" ] && return 0' '  :' && { mkfix; REAPUNDER="$T/r_keep" reap --apply; ok "MUTANT: .keep ignored -> Q5 would FAIL" "$([ -d "$T/qt/keepme" ] && echo 0 || echo 1)"; } || ok "mutant anchor r_keep" 0
mut r_sym "$REAP" '  [ -d "$e" ] && [ ! -L "$e" ] || continue' '  [ -d "$e" ] || continue' && { mkfix; REAPUNDER="$T/r_sym" reap --apply; ok "MUTANT: symlinked entries followed -> Q6 would FAIL (the stale symlink is removed / followed)" "$([ -L "$T/qt/linkdir" ] && echo 0 || echo 1)"; } || ok "mutant anchor r_sym" 0
mut r_failopen "$REAP" '  return 0                                            # no tool to prove it is free: keep' '  return 1' && { mkfix; ( export PATH="$T/emptybin"; REAPUNDER="$T/r_failopen"; export REAPUNDER; reap --apply ); ok "MUTANT: fail-open without lsof -> Q13 would FAIL" "$([ -d "$T/qt/old" ] && echo 0 || echo 1)"; } || ok "mutant anchor r_failopen" 0
mut r_root "$REAP" 'if [ -n "$RH" ]; then case "$RH/" in' 'if false; then case "$RH/" in' && { safe_rm_rf "$T/hm"; REAPUNDER="$T/r_root" rhome; ok "MUTANT: no HOME-root guard -> Q16 would FAIL (a stale subdir of HOME is reaped)" "$([ -d "$T/hm/home/proj" ] && echo 0 || echo 1)"; } || ok "mutant anchor r_root" 0
mut r_lib "$REAP" 'if [ "$APPLY" = 1 ] && [ "$HAVELIB" = 0 ]; then' 'if false; then' && { mkfix; ( export OVN_SAFE_LIB="$T/no-such-lib.sh" REAPUNDER="$T/r_lib"; reap --apply ); ok "MUTANT: apply without the safe lib -> Q15 would FAIL (no explicit refusal; the script runs on without safe_rm_rf)" "$(grep -q 'refusing --apply' "$T/rout" && echo 0 || echo 1)"; } || ok "mutant anchor r_lib" 0

echo "== ovn_log_cap.sh SUMMARY line"
safe_rm_rf "$T/lq"; mkdir -p "$T/lq/logs"; seq 1 80000 | sed 's/^/gate output line number /' > "$T/lq/logs/big.log"
lc(){ ( export OVN_Q="$T/lq" OVN_LOG_CAP_MB=1 OVN_LOG_KEEP_LINES=1000; bash "${CAPUNDER:-$CAP}" "$@" ) > "$T/lout" 2>&1; }
lc
ok "L1 dry run ends with ONE 'log_cap: SUMMARY mode=dry-run would reclaim ~N MB' line (N >= 2 for the 2.4 MB fixture) and still changes nothing" "$([ "$(grep -c 'log_cap: SUMMARY' "$T/lout")" = 1 ] && grep 'log_cap: SUMMARY' "$T/lout" | grep -Eq 'mode=dry-run would reclaim ~[2-9] MB' && [ "$(wc -l < "$T/lq/logs/big.log" | tr -d ' ')" = 80000 ] && echo 1 || echo 0)"
ok "L2 the SUMMARY line is the LAST line and names the apply command" "$(tail -1 "$T/lout" | grep -q 'log_cap: SUMMARY.*apply: OVN_LOG_CAP=on' && echo 1 || echo 0)"
lc --apply
ok "L3 apply: 'SUMMARY mode=apply reclaimed ~N MB'" "$(grep 'log_cap: SUMMARY' "$T/lout" | grep -Eq 'mode=apply reclaimed ~[2-9] MB' && echo 1 || echo 0)"
ok "L4 the header documents the exact apply procedure (OVN_LOG_CAP=on, rollback)" "$(grep -q 'APPLY PROCEDURE' "$CAP" && grep -q 'rollback:' "$CAP" && grep -q 'grep .log_cap: SUMMARY' "$CAP" && echo 1 || echo 0)"
mut c_sum "$CAP" 'est_logs=$(( est_logs + size * drop / total ))' 'est_logs=$est_logs' && { safe_rm_rf "$T/lq"; mkdir -p "$T/lq/logs"; seq 1 80000 | sed 's/^/gate output line number /' > "$T/lq/logs/big.log"; CAPUNDER="$T/c_sum" lc; ok "MUTANT: dry-run estimate not accumulated -> L1 would FAIL (reports ~0 MB)" "$(grep 'log_cap: SUMMARY' "$T/lout" | grep -Eq 'would reclaim ~[2-9] MB' && echo 0 || echo 1)"; } || ok "mutant anchor c_sum" 0

echo "== lib_fixup.sh ovn_qe_gate_beat (explorer gated => one heartbeat row per repo per window)"
OD="$T/od"; SD="$T/sd"; QD="$SD/qwen_explore"
mkod(){ safe_rm_rf "$OD" "$SD"; mkdir -p "$OD/scripts" "$OD/roadmap" "$OD/backlog" "$OD/logs" "$SD"; : > "$OD/scripts/ovn_qwen_explore.py"; : > "$OD/roadmap/iptv_apps.md"; : > "$OD/backlog/iptv_apps.md"; }
gb(){ ( . "${FIXUPUNDER:-$FIXUP}" >/dev/null 2>&1; "$@" ); }
mkod; touch "$SD/PAUSED"
gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "G1 gated by PAUSED: ONE 'gate-skip: queue paused' row in logs/qwen_explore.log (throttled: the second call writes none)" "$([ "$(grep -c 'iptv_apps gate-skip: queue paused' "$OD/logs/qwen_explore.log")" = 1 ] && echo 1 || echo 0)"
ok "G2 the row has no lens=/result= fields (the supply-report parser ignores it)" "$(grep -q 'lens=\|result=' "$OD/logs/qwen_explore.log" && echo 0 || echo 1)"
OVN_QE_BEAT_S=0 gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "G3 OVN_QE_BEAT_S=0 writes a row every call" "$([ "$(grep -c 'gate-skip' "$OD/logs/qwen_explore.log")" = 2 ] && echo 1 || echo 0)"
mkod; mkdir -p "$QD"; echo $(( $(date +%s) + 600 )) > "$QD/next_iptv_apps"
gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "G4 gated by the next-pass stamp: row says 'next pass in <N>s'" "$(grep -Eq 'iptv_apps gate-skip: next pass in [0-9]+s' "$OD/logs/qwen_explore.log" && echo 1 || echo 0)"
mkod; for i in 1 2 3 4; do echo '- [ ] [P3] [ready] f — x' >> "$OD/roadmap/iptv_apps.md"; done
gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "G5 gated by the fuel cap: row says '4 [ready] features already queued'" "$(grep -q 'gate-skip: 4 \[ready\] features already queued' "$OD/logs/qwen_explore.log" && echo 1 || echo 0)"
mkod; touch "$SD/PAUSED"; OVN_QE_GATE_BEAT=off gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "G6 OVN_QE_GATE_BEAT=off writes nothing" "$([ ! -s "$OD/logs/qwen_explore.log" ] && echo 1 || echo 0)"
mkod; touch "$SD/PAUSED"; mkdir -p "$OD/logs"; chmod 500 "$OD/logs"; gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; grc=$?; chmod 700 "$OD/logs"
ok "G7 an unwritable logs dir never fails the kick (rc 0)" "$([ "$grc" = 0 ] && echo 1 || echo 0)"
mut g_off "$FIXUP" '  [ -e "$sd/PAUSED" ] && { ovn_qe_gate_beat "$od" "$qd" "$repo" "queue paused"; return 0; }' '  [ -e "$sd/PAUSED" ] && return 0' && { mkod; touch "$SD/PAUSED"; FIXUPUNDER="$T/g_off" gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; ok "MUTANT: the PAUSED gate does not beat -> G1 would FAIL" "$([ -s "$OD/logs/qwen_explore.log" ] && echo 0 || echo 1)"; } || ok "mutant anchor g_off" 0
mut g_thr "$FIXUP" '  [ $((now - last)) -lt "${OVN_QE_BEAT_S:-1800}" ] && return 0' '  :' && { mkod; touch "$SD/PAUSED"; FIXUPUNDER="$T/g_thr" gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; FIXUPUNDER="$T/g_thr" gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; ok "MUTANT: no throttle -> G1 would FAIL (a row per call)" "$([ "$(grep -c gate-skip "$OD/logs/qwen_explore.log")" = 2 ] && echo 1 || echo 0)"; } || ok "mutant anchor g_thr" 0
mut g_fmt "$FIXUP" '"$(date '"'"'+%F %T'"'"' 2>/dev/null)" "$3" "$4"' '"$(date '"'"'+%F %T'"'"' 2>/dev/null)" "$3 lens=x result=skip" "$4"' && { mkod; touch "$SD/PAUSED"; FIXUPUNDER="$T/g_fmt" gb ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; ok "MUTANT: row carries result= fields -> G2 would FAIL" "$(grep -q 'result=' "$OD/logs/qwen_explore.log" && echo 1 || echo 0)"; } || ok "mutant anchor g_fmt" 0

echo "  shell side: $P passed, $F failed"
[ "$prc" = 0 ] && [ "$F" = 0 ]
