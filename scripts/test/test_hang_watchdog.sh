#!/usr/bin/env bash
# hotfix-scout-hang (2026-11-08): ops/hang_watchdog.sh - detects a run loop stuck on one of OUR helper scripts (>= 15 min CPU or >= 30 min old, no aider/pytest/llama descendant),
# SHADOW by default (alerts.log HANG row, 'would kill'), OVN_HANG_WATCHDOG=on kills TERM then KILL; never touches aider/pytest/llama/orchestrators.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
Q="$HERE/../.."; [ -f "$Q/ops/hang_watchdog.sh" ] || Q="$HERE/.."
W="$Q/ops/hang_watchdog.sh"; [ -f "$W" ] || { echo "  FAIL: $W missing"; exit 1; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
T="$(safe_mktemp_dir hangwd)" || exit 1
PIDS=""; cleanup(){ for p in $PIDS; do kill -KILL "$p" 2>/dev/null; done; safe_rm_rf "$T"; }; trap cleanup EXIT
rc=0; ok(){ echo "  ok   $1"; }; bad(){ echo "  FAIL: $1"; rc=1; }
wd(){ OVN_HW_STATE="$T/st" OVN_HW_PS_FILE="$T/ps.txt" "$@" bash "$W"; }   # usage: wd env A=b ...
run(){ rm -rf "$T/st"; mkdir -p "$T/st"; env OVN_HW_STATE="$T/st" OVN_HW_PS_FILE="$T/ps.txt" "$@" bash "$W"; }
loopl='  100     1 Ss    05:00:00 00:10:00 bash /home/u/overnight-queue/run_overnight.sh'

echo "== snapshot decisions"
printf '%s\n' "$loopl" \
 '  101   100 S     04:52:00 00:00:00 timeout -k 5 60 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b 120000' \
 '  102   101 R     04:52:00 04:51:00 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b 120000' > "$T/ps.txt"
out="$(run)"; a="$T/st/alerts.log"
printf '%s' "$out" | grep -q 'HANG pid=102 loop=100' && ok "the 4h52m scout spin is flagged (innermost helper pid 102, loop 100)" || bad "no HANG: $out"
grep -q 'WARN | hang-watchdog | HANG: run_overnight pid 100 .*helper pid 102.*shadow: would kill' "$a" && ok "alerts.log row says 'would kill' in shadow" || bad "alerts row: $(cat "$a" 2>/dev/null)"
[ "$(grep -c HANG "$a")" = 1 ] && ok "one row (the timeout wrapper pid 101 is not double-reported)" || bad "rows: $(cat "$a")"
OVN_HW_STATE="$T/st" OVN_HW_PS_FILE="$T/ps.txt" bash "$W" >/dev/null; [ "$(grep -c HANG "$a")" = 1 ] && ok "a second pass does not re-log the same pid" || bad "duplicate rows"
printf '%s\n' "$loopl" '  102   100 R     00:20:00 00:16:00 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b' > "$T/ps.txt"
run | grep -q 'HANG pid=102' && ok ">= 15 min CPU while only 20 min old is a hang" || bad "cpu rule"
printf '%s\n' "$loopl" '  102   100 S     00:31:00 00:00:02 python3 /home/u/overnight-queue/ovn_classify.py --tag x' > "$T/ps.txt"
run | grep -q 'HANG pid=102' && ok ">= 30 min old and idle is a hang" || bad "age rule"
printf '%s\n' "$loopl" '  102   100 R     00:14:00 00:14:00 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b' > "$T/ps.txt"
[ -z "$(run)" ] && ok "below both thresholds: silent" || bad "false positive under thresholds"
printf '%s\n' "$loopl" '  102   100 R     05:00:00 04:00:00 /home/u/.venv/bin/aider --model x' \
 '  103   100 R     05:00:00 04:00:00 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b' > "$T/ps.txt"
[ -z "$(run)" ] && ok "a loop with an aider descendant is working: never flagged" || bad "flagged a loop that runs aider"
printf '%s\n' "$loopl" '  102   100 S     05:00:00 00:50:00 /usr/bin/python3 -m pytest tests/' > "$T/ps.txt"
[ -z "$(run)" ] && ok "pytest is never a hang target" || bad "pytest flagged"
printf '%s\n' "$loopl" '  102   100 S     05:00:00 00:00:10 bash /home/u/overnight-queue/ovn_stage_runner.sh x' > "$T/ps.txt"
[ -z "$(run)" ] && ok "orchestrators (ovn_stage_runner.sh) are excluded" || bad "stage runner flagged"
printf '%s\n' '  102     1 R     05:00:00 04:00:00 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b' > "$T/ps.txt"
[ -z "$(run)" ] && ok "a helper NOT under a run_overnight.sh loop is not ours to judge" || bad "orphan helper flagged"
printf '%s\n' "$loopl" '  102   100 R     05:00:00 04:00:00 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b' > "$T/ps.txt"
[ -z "$(run OVN_HANG_WATCHDOG=off)" ] && ok "OVN_HANG_WATCHDOG=off does nothing" || bad "off ignored"
printf '%s\n' '  100     1 Ss    2-05:00:00 1-00:10:00.50 bash /x/run_overnight.sh' '  102   100 R     2-04:00:00 1-00:00:00.25 python3 /x/ovn_scout_ground.py a' > "$T/ps.txt"
run | grep -q 'age 187200s' && ok "d-hh:mm:ss etime and mm:ss.cc cputime parse" || bad "time parse"

echo "== live processes"
mkdir -p "$T/live/overnight-queue"
cat > "$T/live/overnight-queue/run_overnight.sh" <<'LOOP'
#!/bin/bash
# stand-in run loop: one hung helper child, then it proceeds
python3 "$(dirname "$0")/ovn_spin_test.py" &
H=$!
wait $H
echo "loop-continued" > "$(dirname "$0")/proceeded.txt"
LOOP
printf 'while True:\n    pass\n' > "$T/live/overnight-queue/ovn_spin_test.py"
(bash "$T/live/overnight-queue/run_overnight.sh" >/dev/null 2>&1 &) ; sleep 5
HP="$(pgrep -f "$T/live/overnight-queue/ovn_spin_test.py" | head -1)"; PIDS="$PIDS $HP"
[ -n "$HP" ] && ok "stand-in helper spinning (pid $HP)" || bad "stand-in did not start"
rm -rf "$T/st"; mkdir -p "$T/st"
out="$(OVN_HW_STATE="$T/st" OVN_HW_CPU_S=2 OVN_HW_AGE_S=99999 bash "$W")"
printf '%s' "$out" | grep -q "HANG pid=$HP" && ok "real ps: busy helper under a real run_overnight.sh is detected" || bad "live detection failed: $out"
kill -0 "$HP" 2>/dev/null && ok "SHADOW default leaves the process alone" || bad "shadow killed the process"
out="$(OVN_HANG_WATCHDOG=on OVN_HW_STATE="$T/st" OVN_HW_CPU_S=2 OVN_HW_AGE_S=99999 OVN_HW_GRACE_S=2 bash "$W")"
sleep 1
kill -0 "$HP" 2>/dev/null && bad "enforce mode did not kill the helper ($out)" || ok "OVN_HANG_WATCHDOG=on killed the hung helper"
sleep 1; [ "$(cat "$T/live/overnight-queue/proceeded.txt" 2>/dev/null)" = loop-continued ] && ok "the loop stayed alive and proceeded" || bad "loop did not proceed (loop was killed?)"
pgrep -f "$T/live/overnight-queue/run_overnight.sh" >/dev/null 2>&1 && bad "loop still running" || true

echo "== a TERM-ignoring helper is KILLed after the grace; a protected sibling survives"
cat > "$T/live/overnight-queue/run_overnight.sh" <<'LOOP'
#!/bin/bash
python3 "$(dirname "$0")/ovn_spin_test.py" &
H=$!
wait $H
echo "loop-continued" > "$(dirname "$0")/proceeded2.txt"
LOOP
printf 'import signal\nsignal.signal(signal.SIGTERM, signal.SIG_IGN)\nwhile True:\n    pass\n' > "$T/live/overnight-queue/ovn_spin_test.py"
(bash "$T/live/overnight-queue/run_overnight.sh" >/dev/null 2>&1 &) ; sleep 4
HP="$(pgrep -f "$T/live/overnight-queue/ovn_spin_test.py" | head -1)"; PIDS="$PIDS $HP"
rm -rf "$T/st"; mkdir -p "$T/st"
OVN_HANG_WATCHDOG=on OVN_HW_STATE="$T/st" OVN_HW_CPU_S=2 OVN_HW_AGE_S=99999 OVN_HW_GRACE_S=2 bash "$W" >/dev/null
sleep 1; kill -0 "$HP" 2>/dev/null && bad "TERM-ignoring helper survived" || ok "TERM ignored -> KILLed after the grace"
mkdir -p "$T/live2/bin"; printf '#!/bin/bash\nsleep 40\n' > "$T/live2/bin/aider"
cat > "$T/live2/run_overnight.sh" <<LOOP
#!/bin/bash
python3 "$T/live/overnight-queue/ovn_spin_test.py" &
bash "$T/live2/bin/aider" &
wait
LOOP
printf 'while True:\n    pass\n' > "$T/live/overnight-queue/ovn_spin_test.py"
(bash "$T/live2/run_overnight.sh" >/dev/null 2>&1 &) ; sleep 4
SP="$(pgrep -f "$T/live/overnight-queue/ovn_spin_test.py" | head -1)"; PIDS="$PIDS $SP"
AP="$(pgrep -f "$T/live2/bin/aider" | head -1)"; [ -n "$AP" ] && PIDS="$PIDS $AP"
OVN_HANG_WATCHDOG=on OVN_HW_STATE="$T/st" OVN_HW_CPU_S=2 OVN_HW_AGE_S=99999 OVN_HW_GRACE_S=1 bash "$W" >/dev/null
sleep 1
if [ -n "$AP" ] && [ -n "$SP" ]; then kill -0 "$SP" 2>/dev/null && ok "loop with a live aider child: helper NOT killed even in enforce mode" || bad "killed a helper while aider was running"; else bad "could not start the aider stand-in (SP=$SP AP=$AP)"; fi
pkill -f "$T/live" 2>/dev/null; pkill -f "$T/live2" 2>/dev/null; true

echo "== mutant: protection removed -> the aider case is wrongly flagged (test can fail)"
printf '%s\n' "$loopl" '  102   100 R     05:00:00 04:00:00 /home/u/.venv/bin/aider --model x' '  103   100 R     05:00:00 04:00:00 python3 /home/u/overnight-queue/ovn_scout_ground.py /r a b' > "$T/ps.txt"
run OVN_HW_PROTECT_RE='^$' | grep -q 'HANG pid=103' && ok "with PROTECT_RE emptied the protected case flips to a HANG row" || bad "protection not what stops the row"
exit $rc
