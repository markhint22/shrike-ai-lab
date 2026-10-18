#!/bin/bash
# Hermetic test + MUTANTS for the explorer's VERIFY normaliser (scripts/ovn_qwen_explore.py normalize_verify / dialect_only_empty).
# Each mutant is a scratch copy of the script with the behaviour removed; the test run against it must FAIL.
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh"
tmp="$(safe_mktemp_dir qvn)" || exit 1
PY="$(command -v python3.12 || command -v python3)"
SCRIPT="$HERE/../ovn_qwen_explore.py"
rc=0
mkdir -p "$tmp/led"
QV_TMP="$tmp/led" "$PY" "$HERE/test_qwen_verify_normalize.py" "$SCRIPT" || rc=1
mut(){ # name old new
  "$PY" - "$SCRIPT" "$tmp/mut_$1.py" "$2" "$3" <<'PYX' || { echo "mutant $1: pattern not found"; rc=1; return; }
import sys
s=open(sys.argv[1]).read()
if sys.argv[3] not in s: sys.exit(1)
open(sys.argv[2],"w").write(s.replace(sys.argv[3], sys.argv[4], 1))
PYX
  mkdir -p "$tmp/led_$1"
  if QV_TMP="$tmp/led_$1" "$PY" "$HERE/test_qwen_verify_normalize.py" "$tmp/mut_$1.py" >/dev/null 2>&1; then echo "MUTANT SURVIVED: $1"; rc=1; else echo "mutant killed: $1"; fi
}
mut no_normalize 'if not VERIFY_NORMALIZE or not isinstance(v, str)' 'if True or not isinstance(v, str)'
mut no_venv_rewrite 'if _VENV_PYTEST_HEAD.match(head):' 'if False:'
mut no_root_prefix_rewrite 'elif not cd and len(firsts) == 1' 'elif False and len(firsts) == 1'
mut no_nocov_flag '|--no-cov|' '|'
mut dialect_stamps_ttl 'DIALECT_RETRY = os.environ.get("OVN_QE_DIALECT_RETRY", "on").strip().lower() not in ("off", "0", "no", "false")' 'DIALECT_RETRY = False'
mut widened_pytest_paths '_PYTEST_PATH = re.compile(r"^(?!/)(?!.*\.\.)' '_PYTEST_PATH = re.compile(r"^'
safe_rm_rf "$tmp"
echo "test_qwen_verify_normalize.sh rc=$rc"
exit $rc
