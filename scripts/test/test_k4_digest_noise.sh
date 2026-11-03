#!/usr/bin/env bash
# wrapper: runs test_k4_digest_noise.py against the real ovn_notify.py / ovn_research_trigger_check.py, then proves it has teeth: each mutant breaks ONE enforcing piece in a temp copy
# and the test must then FAIL on an assertion (not merely crash). A mutation that does not apply exactly once is a failure of this wrapper.
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; export OVN_ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$OVN_ROOT/scripts/ovn_notify.py" ] || export OVN_ROOT="$(cd "$HERE/.." && pwd)"
NSRC="$OVN_ROOT/scripts/ovn_notify.py"; TSRC="$OVN_ROOT/scripts/ovn_research_trigger_check.py"
rc=0
python3 "$HERE/test_k4_digest_noise.py" || rc=1
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
cp "$OVN_ROOT/scripts/ovn_supply_filter.py" "$T/" 2>/dev/null   # FX-P5: ovn_notify._doable imports the shared filter from its own directory; the mutant copy lives in $T
mutate(){  # $1=label $2=notify|trigger $3=old $4=new
  local src="$NSRC" var=OVN_NOTIFY_SRC out="$T/mutant.py"
  [ "$2" = trigger ] && { src="$TSRC"; var=OVN_TRIGGER_SRC; out="$T/ovn_research_trigger_check.py"; cp "$OVN_ROOT/scripts/ovn_chronic_alert.py" "$T/" 2>/dev/null; }
  OLD="$3" NEW="$4" python3 - "$src" "$out" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { echo "  FAIL mutation '$1' could not be applied"; rc=1; return; }
  env "$var=$out" python3 "$HERE/test_k4_digest_noise.py" > "$T/mut.out" 2>&1; mrc=$?
  if [ "$mrc" -ne 0 ] && [ "$(grep -c '^  FAIL ' "$T/mut.out")" -gt 0 ] && [ "$(grep -c 'Traceback' "$T/mut.out")" -eq 0 ]; then echo "  ok   mutation caught: $1 ($(grep -c '^  FAIL ' "$T/mut.out") assertion(s) fail)"
  else echo "  FAIL mutation NOT caught cleanly: $1"; rc=1; fi
}
mutate "digest dedupe removed" notify 'if kind == "digest" and _mode("OVN_DIGEST_DEDUPE") != "off":' 'if False:'
mutate "'Queue empty' always emitted (old behaviour)" notify '    return (not same), sig' '    return True, sig'
mutate "pass-rate minimum sample removed (old behaviour)" notify 'if gd + bd < min_n and _mode("OVN_PASSRATE_MIN") != "off":' 'if False:'
mutate "OVN_EMPTY_ONCE / OVN_PASSRATE_MIN default back to shadow (the 2026-11-02 flip undone)" notify '_DEFAULT_ON = ("OVN_EMPTY_ONCE", "OVN_PASSRATE_MIN", "OVN_DIGEST_QUIET", "OVN_ESC_HYGIENE", "OVN_HB_DROP_CLASSES")' '_DEFAULT_ON = ()'
mutate "[ready] floor never fires" trigger '        if n > max_ready:' '        if n > 10**9 or True:'
mutate "[ready] floor ignores its per-day dedupe" trigger 'if repo in skip or seen.get(repo) == today:' 'if repo in skip:'
exit $rc
