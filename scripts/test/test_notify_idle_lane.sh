#!/usr/bin/env bash
# wrapper: runs scripts/test/test_notify_idle_lane.py against the real scripts/ovn_notify.py IN PLACE, then proves the test has teeth:
# each mutant below breaks ONE piece of the idle-lane logic in a temp copy of ovn_notify.py and the test must then FAIL (a mutation that
# does not apply exactly once, or a mutant the test still passes, is a failure of this wrapper).
HERE="$(cd "$(dirname "$0")" && pwd)"; export OVN_ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$OVN_ROOT/scripts/ovn_notify.py" ] || export OVN_ROOT="$(cd "$HERE/.." && pwd)"
SRC="$OVN_ROOT/scripts/ovn_notify.py"
rc=0
python3 "$HERE/test_notify_idle_lane.py" || rc=1
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mutate(){  # $1=label $2=old $3=new
  OLD="$2" NEW="$3" python3 - "$SRC" "$T/mutant.py" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { echo "  FAIL mutation '$1' could not be applied"; rc=1; return; }
  OVN_NOTIFY_SRC="$T/mutant.py" python3 "$HERE/test_notify_idle_lane.py" > "$T/mut.out" 2>&1; mrc=$?
  # caught = the suite exits non-zero because an ASSERTION failed (a "  FAIL " line), not because the mutant merely crashed it
  if [ "$mrc" -ne 0 ] && [ "$(grep -c '^  FAIL ' "$T/mut.out")" -gt 0 ] && [ "$(grep -c 'Traceback' "$T/mut.out")" -eq 0 ]; then echo "  ok   mutation caught: $1"
  else echo "  FAIL mutation NOT caught cleanly: $1"; rc=1; fi
}
mutate "idle threshold 30 min -> 30000 min" "IDLE_LANE_S = 30 * 60 " "IDLE_LANE_S = 30 * 60 * 1000 "
mutate "skip rows counted as real attempts" 'if d.get("class") == "skipped" or str(d.get("status", "")).startswith("skip"):' 'if False:'
mutate "12 h dedupe removed" "< STARVED_DEDUP_S" "< -1"
mutate "a lane with pullable work counted as idle" "if n == 0 and t - last.get(repo, first)" "if t - last.get(repo, first)"
mutate "starved needs only ONE idle lane" "len(idle) != len(depths)" "len(idle) == 0"
mutate "paused fleet counted as starved" "if paused or os.environ" "if os.environ"
mutate "marker written whatever the push result (capped/failed lose the emergency for 12 h)" 'if r == "sent" and title.startswith' 'if title.startswith'
mutate "dry run consumes the dedupe window" 'if r == "sent" and title.startswith' 'if r in ("sent", "dry") and title.startswith'
mutate "marker written before the push (old behaviour)" '    return [("🚨 Fleet starved' '    (not dry) and open(_p("notify_starved_last"), "w").write(str(now()))
    return [("🚨 Fleet starved'
mutate "idle line kill switch ignored" 'if os.environ.get("OVN_IDLE_LINE", "1") != "0":' "if True:"
exit $rc
