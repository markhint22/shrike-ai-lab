#!/usr/bin/env bash
# Z7 review fix 1: OVN_Z7_ASSERT_RECALL=off must restore the pre-Z7 assert-weaken output exactly. Runs test_z7_off_exact.py, then re-runs it against MUTANTS of
# ovn_landing_gates.py (each un-guards one Z7 behaviour in off mode); every mutant must be KILLED (the suite must fail).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
rc=0
"$PY" "$HERE/test_z7_off_exact.py" || rc=1
echo "test_z7_off_exact.py rc=$rc"
[ "$rc" -eq 0 ] || exit 1
echo "== Z7 off-exact mutation proofs (each mutant must make the suite FAIL)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
MD="$(safe_mktemp_dir)" || exit 1
trap 'safe_rm_rf "$MD"' EXIT
SRC="$HERE/.."
survived=0; n=0
mut() {  # mut <label> <old> <new>
  local label="$1" old="$2" new="$3" d="$MD/$((n+1))"
  n=$((n+1)); mkdir -p "$d"; cp "$SRC/ovn_landing_gates.py" "$d/"
  if ! OLD="$old" NEW="$new" "$PY" - "$d/ovn_landing_gates.py" <<'PYEOF'
import os, sys
p = sys.argv[1]; s = open(p).read(); old = os.environ["OLD"]; new = os.environ["NEW"]
if old not in s:
    sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PYEOF
  then echo "  FAIL mutant '$label' could not be applied (source changed?)"; survived=$((survived+1)); return; fi
  if Z7_MODULE_DIR="$d" "$PY" "$HERE/test_z7_off_exact.py" >/dev/null 2>&1; then echo "  FAIL mutant SURVIVED: $label"; survived=$((survived+1)); else echo "  ok   mutant killed: $label"; fi
}
mut "regex alternative not-equal unconditional"  'return (_NEG_ASSERT_RE_Z7 if _z7_on() else _NEG_ASSERT_RE_PRE).search(t)' 'return _NEG_ASSERT_RE_Z7.search(t)'
mut "polarity fold not-equal unconditional"      '    if _z7_on():
        t = t.replace("!=", "==")' '    t = t.replace("!=", "==")'
mut "src_changed/tier keys unconditional"   'if not _z7_on() else
                       {"rule"' 'if False else
                       {"rule"'
mut "polarity-flip hit unconditional"       'if _z7_on():
                                hit("polarity-flip"' 'if True:
                                hit("polarity-flip"'
echo "mutants: $n, survived/unapplied: $survived"
[ "$survived" -eq 0 ] || exit 1
exit 0
