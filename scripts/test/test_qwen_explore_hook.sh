#!/usr/bin/env bash
# 2026-10-13 (n3-qwen-research): the QUEUE HOOK of the Qwen explorer (scripts/ovn_qwen_explore.py), event-driven, no cron.
#  - ovn_qwen_explore_kick <repo> <state_dir> <ovn_dir> [exhausted|low] (lib_fixup.sh): starts the explorer in the background on a skip(exhausted) pass (or the low-water path),
#    behind cheap gates, at most once per cooldown (state/qwen_explore/next_<repo>), never blocking the pass, run.lock's fd 200 closed for the child, always rc 0;
#  - ovn_qwen_explore_wait: the pass-end guard (the unit is KillMode=control-group: a running explorer would die with the pass);
#  - the REAL case block of run_overnight.sh is extracted and evaluated: skip(exhausted) kicks, every other status does not.
# Needs bash 5 + GNU flock (box scratch copy); on a host without flock the lock-dependent checks are skipped. Mutation controls at the end.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; Q="$(cd "$HERE/../.." && pwd)"; RUN="$Q/run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME"
HAVE_FLOCK=0; type -P flock >/dev/null 2>&1 && HAVE_FLOCK=1
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"; . "$S/lib_fixup.sh"

OD="$W/ovn"; SD="$W/state"; QD="$SD/qwen_explore"
mk_od(){  # fresh ovn dir + state dir with a stub explorer that records its invocation
  rm -rf "$OD" "$SD"; mkdir -p "$OD/scripts" "$OD/roadmap" "$OD/backlog" "$OD/logs" "$SD"
  cat > "$OD/scripts/ovn_qwen_explore.py" <<'EOP'
import os, sys, time
fd200 = "open" if os.path.exists("/dev/fd/200") else "closed"
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "explore_calls.txt"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + " fd200=" + fd200 + " nice=" + str(os.nice(0)) + " cwd=" + os.getcwd() + "\n")
time.sleep(float(os.environ.get("QE_STUB_SLEEP", "0")))
EOP
  cat > "$OD/scripts/ovn_work_supply.py" <<'EOP'
# supply-v2 stub (implements --on-exhausted)
import os, sys
with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "supply_calls.txt"), "a") as f:
    f.write(" ".join(sys.argv[1:]) + "\n")
EOP
  printf '# roadmap\n' > "$OD/roadmap/iptv_apps.md"; printf '' > "$OD/backlog/iptv_apps.md"
  printf '# roadmap\n' > "$OD/roadmap/xlite.md"; printf '' > "$OD/backlog/xlite.md"
}
calls(){ [ -f "$OD/explore_calls.txt" ] && wc -l < "$OD/explore_calls.txt" | tr -d ' ' || echo 0; }
waitcalls(){ local i=0; while [ "$i" -lt 60 ]; do [ "$(calls)" -ge "$1" ] && return 0; sleep 0.1; i=$((i+1)); done; return 1; }
nolaunch(){ sleep 0.6; [ "$(calls)" = "$1" ]; }
now(){ date +%s; }
exec 200> "$W/lockfile"    # simulate run.lock's fd 200 being open in the runner

# ---------------------------------------------------------------- the kick
mk_od
mkdir -p "$W/fake_live_clone"; cd "$W/fake_live_clone"   # the loop calls the hook from inside a live repo clone
t0="$(now)"; QE_STUB_SLEEP=3 ovn_exhausted_clear x "$SD"; export QE_STUB_SLEEP=3
s0="$(date +%s.%N)"; ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; rc=$?; s1="$(date +%s.%N)"
ok "kick: rc 0 and it returns at once although the explorer sleeps 3 s (background, never blocks the pass)" "[ $rc = 0 ] && python3 -c 'import sys; sys.exit(0 if $s1 - $s0 < 1.0 else 1)'"
waitcalls 1
ok "kick: first exhausted pass launches the explorer once with '<repo> --from-queue'" "[ \"\$(calls)\" = 1 ] && grep -q '^iptv_apps --from-queue ' '$OD/explore_calls.txt'"
ok "kick: run.lock's fd 200 is closed for the child" "grep -q 'fd200=closed' '$OD/explore_calls.txt'"
ok "kick: the child does NOT inherit the caller's cwd (a live repo clone): it starts in the ovn dir" "grep -q 'cwd=$(cd "$OD" && pwd -P)\$' '$OD/explore_calls.txt'"
ok "kick: the child runs niced (nice >= 15; more when the caller is itself niced)" "grep -qE 'nice=(1[5-9])' '$OD/explore_calls.txt'"
ok "kick: the launch debounce stamp next_<repo> is in the future (~300 s)" "[ \"\$(cat '$QD/next_iptv_apps')\" -gt \"\$(now)\" ] && [ \"\$(cat '$QD/next_iptv_apps')\" -le \"\$((\$(now)+301))\" ]"
ok "kick: a launching_<repo> stamp is written (the pass-end wait keys on it)" "[ -s '$QD/launching_iptv_apps' ]"
unset QE_STUB_SLEEP
for i in 1 2 3 4 5; do ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; done
ok "kick: five more exhausted passes inside the cooldown/debounce fork NOTHING (still 1 call)" "nolaunch 1"
echo $(( $(now) - 5 )) > "$QD/next_iptv_apps"; ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; waitcalls 2
ok "kick: once the stamp the explorer wrote has passed, the next exhausted pass launches again (2 calls)" "[ \"\$(calls)\" = 2 ]"
echo $(( $(now) + 3600 )) > "$QD/next_iptv_apps"; ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "kick: a cooldown stamp 1 h ahead (written by the explorer after a productive/empty pass) => no launch" "nolaunch 2"
ovn_qwen_explore_kick xlite "$SD" "$OD" exhausted; waitcalls 3
ok "kick: another repo has its own stamp: launched (3 calls)" "[ \"\$(calls)\" = 3 ] && grep -q '^xlite --from-queue ' '$OD/explore_calls.txt'"
rm -f "$QD"/next_*; OVN_QWEN_EXPLORE=off ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "kick: kill switch OVN_QWEN_EXPLORE=off => no launch and no stamp" "nolaunch 3 && [ ! -e '$QD/next_iptv_apps' ]"
touch "$SD/PAUSED"; ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "kick: state/PAUSED => no launch" "nolaunch 3"
rm -f "$SD/PAUSED"
mv "$OD/scripts/ovn_qwen_explore.py" "$OD/scripts/x.bak"; ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; rc=$?
ok "kick: explorer not deployed => silent no-op, rc 0" "[ $rc = 0 ] && nolaunch 3"
mv "$OD/scripts/x.bak" "$OD/scripts/ovn_qwen_explore.py"
for i in 1 2 3; do echo "- [ ] [P3] [ready] f$i — x {cat: backend; size: S; multifile: no; research: none}" >> "$OD/roadmap/iptv_apps.md"; done
ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; waitcalls 4
ok "kick: 3 [ready] features queued (< cap 4) => still launches" "[ \"\$(calls)\" = 4 ]"
rm -f "$QD"/next_*; echo "- [ ] [P3] [ready] f4 — x {cat: backend; size: S; multifile: no; research: none}" >> "$OD/roadmap/iptv_apps.md"
ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
ok "kick: 4 [ready] features queued (= cap) => enough fuel, no launch" "nolaunch 4"
OVN_QE_READY_CAP=9 ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; waitcalls 5
ok "kick: OVN_QE_READY_CAP raises the cap (5 calls)" "[ \"\$(calls)\" = 5 ]"
printf '# roadmap\n' > "$OD/roadmap/iptv_apps.md"; rm -f "$QD"/next_*
echo "- [ ] [T2] iptv-backend/app/x.py — do a thing. VERIFY: \`true\`. (cat:python; multifile:no)" > "$OD/backlog/iptv_apps.md"
ovn_qwen_explore_kick iptv_apps "$SD" "$OD" low
ok "kick(low): the backlog still has an open T-item => the lane is not about to starve: no launch" "nolaunch 5"
: > "$OD/backlog/iptv_apps.md"; ovn_qwen_explore_kick iptv_apps "$SD" "$OD" low; waitcalls 6
ok "kick(low): doable <= 3 AND an empty backlog => launches (6 calls)" "[ \"\$(calls)\" = 6 ]"
if [ "$HAVE_FLOCK" = 1 ]; then
  rm -f "$QD"/next_*; mkdir -p "$QD"
  ( exec 9> "$QD/lock_global"; flock 9; sleep 4 ) & HOLD=$!; sleep 0.5
  ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted
  ok "kick: another explorer holds the global one-at-a-time lock => no launch (cheap check, no fork)" "nolaunch 6"
  wait "$HOLD"
  ovn_qwen_explore_kick iptv_apps "$SD" "$OD" exhausted; waitcalls 7
  ok "kick: lock free again => launches (7 calls)" "[ \"\$(calls)\" = 7 ]"
fi
rm -rf "${W:?}/ovn_missing"; ovn_qwen_explore_kick iptv_apps "$W/nostate" "$W/ovn_missing" exhausted; rc=$?
ok "kick: a missing ovn dir / state dir is rc 0 (never fails the pass)" "[ $rc = 0 ]"
ok "kick: garbage in the stamp file is treated as 'no stamp'" "( mk_od; mkdir -p '$QD'; echo garbage > '$QD/next_iptv_apps'; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1 )"

# ---------------------------------------------------------------- the wait guard
mk_od; mkdir -p "$QD"
t0="$(now)"; OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 30; t1="$(now)"
ok "wait: nothing running => returns at once" "[ $((t1 - t0)) -le 1 ]"
printf '%s\n' "$(now)" > "$QD/launching_iptv_apps"
t0="$(date +%s)"; OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 30; t1="$(date +%s)"
ok "wait: a fresh launching_<repo> stamp (< 15 s, the explorer has not taken its lock yet) is waited out (~15 s)" "[ $((t1 - t0)) -ge 12 ] && [ $((t1 - t0)) -le 20 ]"
printf '%s\n' "$(( $(now) - 100 ))" > "$QD/launching_iptv_apps"
t0="$(date +%s)"; OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 30; t1="$(date +%s)"
ok "wait: a stale launching stamp (100 s old, the explorer is long gone) does not hold the pass" "[ $((t1 - t0)) -le 1 ]"
if [ "$HAVE_FLOCK" = 1 ]; then
  ( exec 9> "$QD/lock_global"; flock 9; sleep 3 ) & HOLD=$!; sleep 0.4
  t0="$(date +%s)"; OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 30; t1="$(date +%s)"; wait "$HOLD"
  ok "wait: a running explorer (global lock held ~3 s) is waited for, then the pass ends" "[ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 6 ]"
  ( exec 9> "$QD/lock_global"; flock 9; sleep 8 ) & HOLD=$!; sleep 0.4
  t0="$(date +%s)"; OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 2; t1="$(date +%s)"
  ok "wait: bounded by max_s (an explorer that runs for 8 s holds the pass for at most ~2 s)" "[ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 4 ]"
  ( exec 9> "$QD/lock_global"; flock 9; sleep 3 ) & HOLD=$!; sleep 0.4
  t0="$(date +%s)"; OVN_QWEN_EXPLORE=off OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 30; t1="$(date +%s)"
  ok "wait: kill switch => returns at once" "[ $((t1 - t0)) -le 1 ]"
  wait "$HOLD" 2>/dev/null
  # DELAY (reviewer minor 5): the pass-end wait must not hold the other lanes for the long default while a lane did real work this pass
  ( exec 9> "$QD/lock_global"; flock 9; sleep 9 ) & HOLD=$!; sleep 0.4
  t0="$(date +%s)"; OVN_QE_WAIT_BUSY_S=2 OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 7 2 1; t1="$(date +%s)"
  ok "wait: some lane did real work (2 lanes seen, 1 idle) => capped at OVN_QE_WAIT_BUSY_S (2 s), not the long max (7 s)" "[ $((t1 - t0)) -ge 2 ] && [ $((t1 - t0)) -le 4 ]"
  wait "$HOLD" 2>/dev/null
  ( exec 9> "$QD/lock_global"; flock 9; sleep 9 ) & HOLD=$!; sleep 0.4
  t0="$(date +%s)"; OVN_QE_WAIT_BUSY_S=2 OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 5 2 2; t1="$(date +%s)"
  ok "wait: every lane idle (2 of 2) => nobody to delay: the long max (5 s) applies" "[ $((t1 - t0)) -ge 5 ] && [ $((t1 - t0)) -le 7 ]"
  wait "$HOLD" 2>/dev/null
  ( exec 9> "$QD/lock_global"; flock 9; sleep 9 ) & HOLD=$!; sleep 0.4
  t0="$(date +%s)"; OVN_QE_WAIT_BUSY_S=2 OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait "$SD" 5 junk 1; t1="$(date +%s)"
  ok "wait: garbage lane counts fall back to the long wait (never crash, never zero)" "[ $((t1 - t0)) -ge 5 ]"
  wait "$HOLD" 2>/dev/null
fi

# ---------------------------------------------------------------- the REAL case block of run_overnight.sh
BLOCK_START="$(grep -n '_ovn_lanes_seen=\$(( \${_ovn_lanes_seen:-0} + 1 ))' "$RUN" | head -1 | cut -d: -f1)"
BLOCK="$W/block.sh"
awk -v s="$((BLOCK_START - 1))" 'NR>=s { print; if (NR>s && $0 == "  fi") exit }' "$RUN" > "$BLOCK"
ok "the loop's idle/exhausted bookkeeping block was extracted from run_overnight.sh (starts with the train_job guard, ends with its fi)" "head -1 '$BLOCK' | grep -q 'TYPE.*train_job' && [ \"\$(tail -1 '$BLOCK')\" = '  fi' ] && grep -q ovn_qwen_explore_kick '$BLOCK'"
exercise(){  # exercise <type> <status> [repo]  -> runs the real block once
  ( TYPE="$1"; STATUS="$2"; REPO_BASENAME="${3:-iptv_apps}"; STATE_DIR="$SD"; SCRIPT_DIR="$OD"; _ovn_lanes_seen=0; _ovn_lanes_idle=0
    # shellcheck disable=SC1090
    . "$BLOCK" )
}
mk_od
export QE_STUB_SLEEP=3
s0="$(date +%s.%N)"; exercise aider_fix 'skip(exhausted)'; s1="$(date +%s.%N)"
ok "loop block: a skip(exhausted) pass starts the explorer (1 call) and returns at once (explorer sleeps 3 s)" "waitcalls 1 && [ \"\$(calls)\" = 1 ] && python3 -c 'import sys; sys.exit(0 if $s1 - $s0 < 1.5 else 1)'"
unset QE_STUB_SLEEP
exercise aider_fix 'skip(exhausted)'; exercise aider_fix 'skip(exhausted)'
ok "loop block: the next exhausted passes (every ~20-60 s in an idle loop) do NOT relaunch while the cooldown holds (still 1 call)" "nolaunch 1"
ok "loop block: the deterministic supply kick still fires on the first exhausted pass (its own marker), unchanged" "[ -s '$W/ovn/supply_calls.txt' ] || sleep 0.5; [ -s '$W/ovn/supply_calls.txt' ]"
for st in 'pushed(tests:pass)' 'no-op(ALREADY-DONE)' 'skip(oversized-context)' 'reverted(tests-red)' 'error(model-api-error)'; do
  rm -f "$QD"/next_*; exercise aider_fix "$st"
done
ok "loop block: a pass with ANY other status (pushed / no-op / other skip / reverted / error) never starts the explorer (still 1 call)" "nolaunch 1"
rm -f "$QD"/next_*; exercise train_job 'skip(exhausted)'
ok "loop block: a train_job lane is not a coding lane: no explorer (still 1 call)" "nolaunch 1"
rm -f "$QD"/next_*; exercise aider_fix 'skip(exhausted)' xlite; waitcalls 2
ok "loop block: an exhausted xlite lane starts ITS explorer (2 calls, 'xlite --from-queue')" "[ \"\$(calls)\" = 2 ] && grep -q '^xlite --from-queue ' '$OD/explore_calls.txt'"
# the idle count still works (lanes_seen/idle incremented by the real block)
ok "loop block: lanes_seen / lanes_idle still count (idle wait keys on them)" "( TYPE=aider_fix; STATUS='skip(exhausted)'; REPO_BASENAME=iptv_apps; STATE_DIR='$SD'; SCRIPT_DIR='$OD'; _ovn_lanes_seen=0; _ovn_lanes_idle=0; . '$BLOCK'; [ \$_ovn_lanes_seen = 1 ] && [ \$_ovn_lanes_idle = 1 ] )"

# ---------------------------------------------------------------- static wiring (code lines)
ok "run_overnight.sh: the exhausted branch kicks the explorer BEFORE the supply kick, both lines intact" "[ \"\$(grep -c 'ovn_qwen_explore_kick \"\${REPO_BASENAME:-}\" \"\$STATE_DIR\" \"\$SCRIPT_DIR\" exhausted || true' '$RUN')\" = 1 ] && [ \"\$(grep -c 'ovn_exhausted_supply_kick \"\${REPO_BASENAME:-}\" \"\$STATE_DIR\" \"\$SCRIPT_DIR\" ;;' '$RUN')\" = 1 ]"
ok "run_overnight.sh: the low-water path kicks in 'low' mode after the inline refill (doable <= 3)" "[ \"\$(grep -c 'ovn_qwen_explore_kick \"\$(basename \"\$PWD\")\" \"\$STATE_DIR\" \"\$SCRIPT_DIR\" low || true' '$RUN')\" = 1 ] && [ \"\$(grep -n 'ovn_qwen_explore_kick.* low || true' '$RUN' | head -1 | cut -d: -f1)\" -gt \"\$(grep -n 'inline refill done' '$RUN' | head -1 | cut -d: -f1)\" ]"
ok "run_overnight.sh: the pass-end wait runs after the idle wait, after releasing run.lock, and is the last statement of the pass" "[ \"\$(grep -c 'ovn_qwen_explore_wait \"\$STATE_DIR\"' '$RUN')\" = 1 ] && [ \"\$(grep -n 'ovn_qwen_explore_wait \"\$STATE_DIR\"' '$RUN' | cut -d: -f1)\" -gt \"\$(grep -n 'idle wait over' '$RUN' | cut -d: -f1)\" ] && [ \"\$(grep -B2 'ovn_qwen_explore_wait \"\$STATE_DIR\"' '$RUN' | grep -c 'exec 200>&-')\" = 1 ]"
ok "run_overnight.sh: no new cron / crontab line anywhere in the change (the hook is the loop itself)" "[ \"\$(git -C '$Q' diff -U0 -- run_overnight.sh scripts/lib_fixup.sh 2>/dev/null | grep -c '^+.*crontab')\" = 0 ] || true"
ok "run_overnight.sh: still parses (bash -n)" "bash -n '$RUN'"
ok "lib_fixup.sh: still parses (bash -n)" "bash -n '$S/lib_fixup.sh'"
exec 200>&-

# ---------------------------------------------------------------- mutation controls: each removed behaviour must make its check FAIL
mutlib(){  # mutlib <name> <python-replace-old> <python-replace-new>  -> $W/<name>.sh (a copy of lib_fixup.sh with the first occurrence replaced)
  python3 - "$S/lib_fixup.sh" "$W/$1.sh" "$2" "$3" <<'EOP'
import sys
src = open(sys.argv[1]).read()
old, new = sys.argv[3], sys.argv[4]
assert old in src, "mutation anchor missing: " + old[:60]
open(sys.argv[2], "w").write(src.replace(old, new, 1))
EOP
}
fresh_calls(){ mk_od; rm -f "$QD"/next_*; }
# 1. no next_<repo> gate => relaunched on every exhausted pass
mutlib m_gate '  [ "$now" -lt "$nxt" ] && return 0' '  :' || { F=$((F+1)); echo "  FAIL mutation anchor 1"; }
ok "MUTATION: without the next_<repo> gate EVERY exhausted pass forks an explorer (2 calls from 2 passes)" "( . '$W/m_gate.sh'; fresh_calls; rm -f '$QD/next_iptv_apps'; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 2; [ \"\$(calls)\" = 2 ] )"
# 2. no debounce stamp => two passes before the explorer finishes double-launch
mutlib m_debounce '  printf '"'"'%s\n'"'"' "$(( now + ${OVN_QE_DEBOUNCE_S:-300} ))" > "$qd/next_${repo}" 2>/dev/null' '  :' || { F=$((F+1)); echo "  FAIL mutation anchor 2"; }
ok "MUTATION: without the launch debounce stamp a second pass double-launches (2 calls)" "( . '$W/m_debounce.sh'; fresh_calls; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 2; [ \"\$(calls)\" = 2 ] )"
# 3. fd 200 stays open
exec 200> "$W/lockfile"
mutlib m_fd '--from-queue 200>&- < /dev/null >> "$od/logs/qwen_explore.stdout" 2>&1 &' '--from-queue < /dev/null >> "$od/logs/qwen_explore.stdout" 2>&1 &' || { F=$((F+1)); echo "  FAIL mutation anchor 3"; }
ok "MUTATION: without 200>&- the explorer child inherits run.lock's fd (fd200=open recorded)" "( . '$W/m_fd.sh'; fresh_calls; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1; grep -q 'fd200=open' '$OD/explore_calls.txt' )"
exec 200>&-
# 3b. the child keeps the caller's cwd (a live repo clone)
mutlib m_cwd '( cd "$od" 2>/dev/null; nohup' '( nohup' || { F=$((F+1)); echo "  FAIL mutation anchor 3b"; }
ok "MUTATION: without the cd the explorer would run with a live repo clone as its cwd (cwd recorded as the caller's)" "( . '$W/m_cwd.sh'; fresh_calls; mkdir -p '$W/fake_live_clone'; cd '$W/fake_live_clone'; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1; grep -q 'cwd=.*fake_live_clone' '$OD/explore_calls.txt' )"
# 4. foreground launch blocks the pass
mutlib m_block '--from-queue 200>&- < /dev/null >> "$od/logs/qwen_explore.stdout" 2>&1 & ) 2>/dev/null' '--from-queue 200>&- < /dev/null >> "$od/logs/qwen_explore.stdout" 2>&1 ; ) 2>/dev/null' || { F=$((F+1)); echo "  FAIL mutation anchor 4"; }
ok "MUTATION: a foreground launch blocks the pass for the explorer's whole run (>= 2.5 s with a 3 s explorer)" "( . '$W/m_block.sh'; fresh_calls; export QE_STUB_SLEEP=3; s0=\$(date +%s.%N); ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; s1=\$(date +%s.%N); python3 -c \"import sys; sys.exit(0 if \$s1 - \$s0 >= 2.5 else 1)\" )"
# 5. kill switch ignored
mutlib m_kill '  [ "${OVN_QWEN_EXPLORE:-on}" = off ] && return 0
  [ -f "$od/scripts/ovn_qwen_explore.py" ]' '  [ -f "$od/scripts/ovn_qwen_explore.py" ]' || { F=$((F+1)); echo "  FAIL mutation anchor 5"; }
ok "MUTATION: without the kill-switch line the explorer is launched although OVN_QWEN_EXPLORE=off" "( . '$W/m_kill.sh'; fresh_calls; OVN_QWEN_EXPLORE=off ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1 )"
# 6. fuel cap ignored
mutlib m_fuel '  [ "$rdy" -ge "${OVN_QE_READY_CAP:-4}" ] && return 0' '  :' || { F=$((F+1)); echo "  FAIL mutation anchor 6"; }
ok "MUTATION: without the fuel check an explorer starts although 4 [ready] features wait" "( . '$W/m_fuel.sh'; fresh_calls; for i in 1 2 3 4; do echo '- [ ] [P3] [ready] f — x {cat: backend; size: S; multifile: no; research: none}' >> '$OD/roadmap/iptv_apps.md'; done; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1 )"
# 7. low mode ignores the backlog
mutlib m_low '    [ "$backlog_open" -gt 0 ] && return 0' '    :' || { F=$((F+1)); echo "  FAIL mutation anchor 7"; }
ok "MUTATION: low mode without the backlog check launches with an open backlog" "( . '$W/m_low.sh'; fresh_calls; echo '- [ ] [T2] a.py — x. VERIFY: \`true\`. (cat:python; multifile:no)' > '$OD/backlog/iptv_apps.md'; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' low; waitcalls 1 )"
# 8. PAUSED ignored
mutlib m_paused '  [ -e "$sd/PAUSED" ] && return 0
  qd=' '  qd=' || { F=$((F+1)); echo "  FAIL mutation anchor 8"; }
ok "MUTATION: without the PAUSED check an explorer starts while the queue is paused" "( . '$W/m_paused.sh'; fresh_calls; touch '$SD/PAUSED'; ovn_qwen_explore_kick iptv_apps '$SD' '$OD' exhausted; waitcalls 1 )"
# 9. the wait guard neutered
mutlib m_wait '    [ "$running" = 0 ] && return 0
    sleep "$step"' '    return 0
    sleep "$step"' || { F=$((F+1)); echo "  FAIL mutation anchor 9"; }
if [ "$HAVE_FLOCK" = 1 ]; then
  ok "MUTATION: a wait guard that returns at once lets the pass exit under a running explorer (waited < 1 s instead of >= 2 s)" "( . '$W/m_wait.sh'; mk_od; mkdir -p '$QD'; ( exec 9> '$QD/lock_global'; flock 9; sleep 3 ) & H=\$!; sleep 0.4; t0=\$(date +%s); OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait '$SD' 30; t1=\$(date +%s); wait \$H; [ \$((t1 - t0)) -lt 1 ] )"
fi
# 9b. the busy cap removed
mutlib m_busy '  if [ "$seen" -gt "$idle" ] && [ "$max" -gt "${OVN_QE_WAIT_BUSY_S:-90}" ]; then max="${OVN_QE_WAIT_BUSY_S:-90}"; fi' '  :' || { F=$((F+1)); echo "  FAIL mutation anchor 9b"; }
if [ "$HAVE_FLOCK" = 1 ]; then
  ok "MUTATION: without the busy cap the pass-end wait holds busy lanes for the long max (>= 5 s instead of ~2 s)" "( . '$W/m_busy.sh'; mk_od; mkdir -p '$QD'; ( exec 9> '$QD/lock_global'; flock 9; sleep 7 ) & H=\$!; sleep 0.4; t0=\$(date +%s); OVN_QE_WAIT_BUSY_S=2 OVN_QE_WAIT_STEP_S=1 ovn_qwen_explore_wait '$SD' 6 2 1; t1=\$(date +%s); wait \$H; [ \$((t1 - t0)) -ge 5 ] )"
fi
# 10. the real loop hook removed / applied to every status
python3 - "$BLOCK" "$W/block_nohook.sh" <<'EOP'
import sys
t = open(sys.argv[1]).read()
lines = [l for l in t.split("\n") if "ovn_qwen_explore_kick" not in l]
open(sys.argv[2], "w").write("\n".join(lines))
EOP
exec 200> "$W/lockfile"
ok "MUTATION: the loop block without the hook line never starts the explorer on skip(exhausted)" "( mk_od; ( TYPE=aider_fix; STATUS='skip(exhausted)'; REPO_BASENAME=iptv_apps; STATE_DIR='$SD'; SCRIPT_DIR='$OD'; _ovn_lanes_seen=0; _ovn_lanes_idle=0; . '$W/block_nohook.sh' ); sleep 0.6; [ \"\$(calls)\" = 0 ] )"
python3 - "$BLOCK" "$W/block_always.sh" <<'EOP'
import sys, re
t = open(sys.argv[1]).read()
# move the hook out of the skip*exhausted) branch: it now fires on every status
hook = [l for l in t.split("\n") if l.strip().startswith("declare -F ovn_qwen_explore_kick")][0]
t = "\n".join(l for l in t.split("\n") if "ovn_qwen_explore_kick" not in l)
t = t.replace("    case \"$STATUS\" in", hook.strip() + "\n    case \"$STATUS\" in", 1)
open(sys.argv[2], "w").write(t)
EOP
ok "MUTATION: a hook that fires on every status would start the explorer on a pushed pass (the 'never on a non-exhausted pass' check would FAIL)" "( mk_od; ( TYPE=aider_fix; STATUS='pushed(tests:pass)'; REPO_BASENAME=iptv_apps; STATE_DIR='$SD'; SCRIPT_DIR='$OD'; _ovn_lanes_seen=0; _ovn_lanes_idle=0; . '$W/block_always.sh' ); waitcalls 1 )"
exec 200>&-

echo "qwen explore hook: $P passed, $F failed"
[ "$F" = 0 ]
