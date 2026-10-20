#!/usr/bin/env bash
# wrapper: runs test_notify_autodeploy.py against the real scripts/ovn_notify.py, then proves it has teeth with mutants of autodeploy_report() (each must make the test FAIL by assertion).
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; export OVN_ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$OVN_ROOT/scripts/ovn_notify.py" ] || export OVN_ROOT="$(cd "$HERE/.." && pwd)"
SRC="$OVN_ROOT/scripts/ovn_notify.py"
rc=0
python3 "$HERE/test_notify_autodeploy.py" || rc=1
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
mutate(){  # $1=label $2=old $3=new
  OLD="$2" NEW="$3" python3 - "$SRC" "$T/mutant.py" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { echo "  FAIL mutation '$1' could not be applied"; rc=1; return; }
  OVN_NOTIFY_SRC="$T/mutant.py" python3 "$HERE/test_notify_autodeploy.py" > "$T/mut.out" 2>&1; mrc=$?
  if [ "$mrc" -ne 0 ] && [ "$(grep -c '^  FAIL ' "$T/mut.out")" -gt 0 ] && [ "$(grep -c 'Traceback' "$T/mut.out")" -eq 0 ]; then echo "  ok   mutation caught: $1"
  else echo "  FAIL mutation NOT caught cleanly: $1"; rc=1; fi
}
mutate "stale-report (cron stopped) detection removed" "if age > 3 * 3600:" "if age > 3000 * 3600:"
mutate "kill switch ignored" 'if os.environ.get("OVN_AUTODEPLOY_LINE", "1") == "0":' "if False:"
mutate "stale-box bullet never raised" "elif ahead > 0 and oldest >= thr and rep.get(\"decision\") != \"deployed\":" "elif False:"
mutate "off-mode report treated as stale" '        if rep.get("mode") == "off":' '        if False:'
mutate "shadow stale bullet is high priority" '"prio": "high" if enforcing else "default"}' '"prio": "high"}'
mutate "rollback_failed not urgent" '"prio": "urgent"}' '"prio": "default"}'
mutate "stale threshold hard-coded (report value ignored)" 'thr = float(rep.get("stale_threshold_h") or 12)' "thr = 12.0"
mutate "line not added to the hourly update" "    if _ad_line:
        lines.append(_ad_line)" "    if False:
        lines.append(_ad_line)"
mutate "bullet not added to the hourly update" "    if _ad_need:
        needs.insert(0," "    if False:
        needs.insert(0,"
exit $rc
