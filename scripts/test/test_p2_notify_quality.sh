#!/usr/bin/env bash
# wrapper: runs test_p2_notify_quality.py against the real ovn_notify.py, then proves it has teeth: each mutant breaks ONE piece in a temp copy and the test must then FAIL on an
# assertion (not merely crash). A mutation that does not apply exactly once is a failure of this wrapper.
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; export OVN_ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$OVN_ROOT/scripts/ovn_notify.py" ] || export OVN_ROOT="$(cd "$HERE/.." && pwd)"
NSRC="$OVN_ROOT/scripts/ovn_notify.py"
export TZ=UTC
rc=0
python3 "$HERE/test_p2_notify_quality.py" || rc=1
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
mutate(){  # $1=label $2=old $3=new
  local out="$T/mutant.py"
  OLD="$2" NEW="$3" python3 - "$NSRC" "$out" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { echo "  FAIL mutation '$1' could not be applied"; rc=1; return; }
  OVN_NOTIFY_SRC="$out" python3 "$HERE/test_p2_notify_quality.py" > "$T/mut.out" 2>&1; mrc=$?
  if [ "$mrc" -ne 0 ] && [ "$(grep -c '^  FAIL ' "$T/mut.out")" -gt 0 ] && [ "$(grep -c 'Traceback' "$T/mut.out")" -eq 0 ]; then echo "  ok   mutation caught: $1 ($(grep -c '^  FAIL ' "$T/mut.out") assertion(s) fail)"
  else echo "  FAIL mutation NOT caught cleanly: $1"; rc=1; fi
}
mutate "forward ignores OVN_NOTIFY_DISABLE (N4)" '        return "disabled"' '        pass'
mutate "digest and emergency share no budget (N10)" 'budget = {"digest": DIGEST_CAP, "emergency": EMERGENCY_CAP}.get(kind)' 'budget = None'
mutate "heartbeat subject to the caps (N8)" '    if kind != "heartbeat":
        # N10' '    if True:
        # N10'
mutate "heartbeat sent as kind=emergency (title-deduped, counted against the emergency budget) (N8)" '    return "%s: %s -> %s" % (title, body, forward(title, body, "default", "white_check_mark", kind="heartbeat"))' '    return "%s: %s -> %s" % (title, body, forward(title, body, "default", "white_check_mark", kind="emergency"))'
mutate "'[suppressed N]' never reported (N10)" '    if suppressed:
        body +=' '    if False:
        body +='
mutate "all-good digest sent even when the heartbeat is alive (N6)" '        if heartbeat_alive():' '        if False:'
mutate "escalate not once per day (N7)" '    if seen.get(sig) == day:' '    if False:'
mutate "escalate shadow mode falls through to a real push (N7)" '    if mode == "shadow":
        if seen.get("shadow:" + sig) != day and not dry:' '    if mode == "off":
        if seen.get("shadow:" + sig) != day and not dry:'
mutate "a capped escalation consumes the day (N7)" '    if res in ("sent", "deduped") and not dry:' '    if res in ("sent", "deduped", "capped") and not dry:'
mutate "dropped messages not counted (N8)" '            _event("dropped", "drop", clean_title(title), body)' '            pass'
[ "$rc" = 0 ] && echo "  p2 notify quality wrapper: all green"
exit $rc
