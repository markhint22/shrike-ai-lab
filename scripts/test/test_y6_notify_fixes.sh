#!/usr/bin/env bash
# wrapper: runs test_y6_notify_fixes.py against the real ovn_notify.py / vercel_state_check.py, then proves it has teeth: each mutant breaks ONE piece in a temp copy and the test must then
# FAIL on an assertion (not merely crash). A mutation that does not apply exactly once is a failure of this wrapper.
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; export OVN_ROOT="$(cd "$HERE/../.." && pwd)"; [ -f "$OVN_ROOT/scripts/ovn_notify.py" ] || export OVN_ROOT="$(cd "$HERE/.." && pwd)"
NSRC="$OVN_ROOT/scripts/ovn_notify.py"; VSRC="$OVN_ROOT/vercel_state_check.py"
export TZ=UTC
rc=0
python3 "$HERE/test_y6_notify_fixes.py" || rc=1
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: Z10 mac test sandbox"; exit 1; }   # Z10: real ssh/curl/ntfy delivery impossible from this test
cp "$OVN_ROOT/scripts/ovn_supply_filter.py" "$T/" 2>/dev/null          # ovn_notify._doable imports the shared filter from its own directory; the mutant copy lives in $T
cp "$OVN_ROOT/scripts/ovn_relay.py" "$T/" 2>/dev/null; mkdir -p "$T/up"; cp "$OVN_ROOT/scripts/ovn_relay.py" "$T/up/" 2>/dev/null   # vercel_state_check imports ovn_relay from its parent dir
mutate(){  # $1=label $2=notify|vsc $3=old $4=new
  local src="$NSRC" var=OVN_NOTIFY_SRC out="$T/mutant.py"
  [ "$2" = vsc ] && { src="$VSRC"; var=OVN_VSC_SRC; out="$T/up/vsc_mutant.py"; }
  OLD="$3" NEW="$4" python3 - "$src" "$out" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { echo "  FAIL mutation '$1' could not be applied"; rc=1; return; }
  env "$var=$out" python3 "$HERE/test_y6_notify_fixes.py" > "$T/mut.out" 2>&1; mrc=$?
  if [ "$mrc" -ne 0 ] && [ "$(grep -c '^  FAIL ' "$T/mut.out")" -gt 0 ] && [ "$(grep -c 'Traceback' "$T/mut.out")" -eq 0 ]; then echo "  ok   mutation caught: $1 ($(grep -c '^  FAIL ' "$T/mut.out") assertion(s) failed)"
  else echo "  FAIL mutation NOT caught cleanly: $1"; rc=1; fi
}
mutate "promote summary not folded (falls through to a plain note)" notify '    if cls == "note" and PROMOTE_RE.search(title or ""):' '    if False:'
mutate "promote summary dropped again (DROP_RE)" notify 'lock-orphan|hourly|feature complete"' 'lock-orphan|hourly|feature complete|daily prod promote"'
mutate "a capped/deduped digest consumes the promote summary" notify '    if res == "sent":
        commit_digest_state(now())' '    if res in ("sent", "capped", "deduped"):
        commit_digest_state(now())'
mutate "promote bullet can fall into the '+N more' tail" notify '        shown[-1] = promo      # a promote summary' '        pass      # a promote summary'
mutate "scorecard line shown every digest" notify '    if sc["ts"] <= float(shown.get("entry_ts", 0) or 0) or t - float(shown.get("at", 0) or 0) < every:' '    if False:'
mutate "mac supervisor back to shadow by default" notify '"OVN_ESC_MAC_SUPERVISOR", "OVN_BULLET_ONCE")' '"OVN_BULLET_ONCE")'
mutate "rolling window ignored (calendar-day key only)" notify '        if _recent(sig):' '        if False:'
mutate "reconcile bullet loses repo+branch" notify '    return "; ".join(seen)' '    return ""'
mutate "bullet cooldown ignored" notify '            if mode != "off" and same:' '            if False:'
mutate "bullet cooldown never recorded" notify '        _save_json(BULLET_STATE, st)' '        pass'
mutate "features-ready signature uses the changing text" notify '("features_ready", re.compile(r"^Features ready to test", re.I), "title")' '("features_ready", re.compile(r"^Features ready to test", re.I), "text")'
mutate "features-ready signature ignores the body feature names" notify '(_digest_key(n["title"]) + "|" + "|".join(_feature_names(n.get("text"))))' '_digest_key(n["title"])'
mutate "weekly scorecard does not force the quiet digest out" notify ' and not force and not _LAST.get("scorecard_ts"):' ' and not force:'
mutate "suite-red note keeps fixture names" notify '        if name and not fixture(name):' '        if name:'
mutate "suite-red escalation unfiltered" notify '    f = suite_red_filter(title, body)      # Y6/6' '    f = (title, body)      # Y6/6'
mutate "vercel recovery without a prior alert" vsc ' and (state.get("prod_" + name) or state.get("esc_" + name)) and prod[0]["uid"] != state.get("prod_" + name):' ' and prod[0]["uid"] != state.get("prod_" + name):'
mutate "vercel recovery not low priority" vsc 'rbody[:200], "low", dry)' 'rbody[:200], False, dry)'
mutate "vercel recovery repeats (alert state kept)" vsc '                    state.pop(kk, None)' '                    pass'
[ "$rc" = 0 ] && echo "  y6 notify fixes wrapper: all green"
exit $rc
