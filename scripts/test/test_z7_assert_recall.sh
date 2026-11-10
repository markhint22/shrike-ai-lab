#!/usr/bin/env bash
# Z7-A (2026-11-09): assert-weaken recall extension. Runs test_z7_assert_recall.py, then re-runs it against MUTANTS of ovn_landing_gates.py (each removes one detector or one
# false-positive guard); every mutant must be KILLED (the suite must fail).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(type -P python3.12 || type -P python3)"
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
rc=0
"$PY" "$HERE/test_z7_assert_recall.py" || rc=1
echo "test_z7_assert_recall.py rc=$rc"
[ "$rc" -eq 0 ] || exit 1
echo "== Z7-A mutation proofs (each mutant must make the suite FAIL)"
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
  if Z7_MODULE_DIR="$d" "$PY" "$HERE/test_z7_assert_recall.py" >/dev/null 2>&1; then echo "  FAIL mutant SURVIVED: $label"; survived=$((survived+1)); else echo "  ok   mutant killed: $label"; fi
}
mut "polarity-flip never reported"          'hit("polarity-flip"' '(lambda *a: None)("polarity-flip"'
mut "!= not folded into the polarity key"   't = t.replace("!=", "==")' 't = t'
mut "!= is not a negative assertion"        '\bassert\b[^#\n]*?!=|' ''
mut "kill switch ignored"                   'return os.environ.get("OVN_Z7_ASSERT_RECALL", "on").strip().lower() != "off"' 'return True'
mut "status-flip-src never reported"        'hit("status-flip-src"' '(lambda *a: None)("status-flip-src"'
mut "status-flip-src ignores the code list" 'if c in (400, 401, 403, 404, 405, 409, 422)]' 'if c in ()]'
mut "literal-swap never reported"           'hit("literal-swap"' '(lambda *a: None)("literal-swap"'
mut "literal-swap without a source edit"    'if src_touched and not retired:' 'if not retired:'
mut "literal-swap: source-introduced value still flagged" 'if new_l and all(_lit_explained(' 'if False and all(_lit_explained('
mut "literal-swap: any assertion shape"     'and _lit_shape(a) == sh and' 'and True and'
mut "literal-swap on non-equality asserts"  'if not (_ASSERTISH_RE.search(t) and _CMP_RE.search(t)) or _is_comment(t):' 'if not _ASSERTISH_RE.search(t) or _is_comment(t):'
mut "tier never strong"                     '"tier": "strong" if' '"tier": "weak" if False and'
mut "assertion-deleted never reported"      'hit("assertion-deleted"' '(lambda *a: None)("assertion-deleted"'
mut "assertion-deleted counts weak checks"  'if _ASSERTISH_RE.search(t) and not _WEAK_RE.search(t) and not _is_comment(t) and' 'if _ASSERTISH_RE.search(t) and not _is_comment(t) and'
mut "assertion-deleted ignores dedup"       'keep = [x for x in del_ass if new_norm is None or _norm_line(x[1]) not in new_norm]' 'keep = list(del_ass)'
mut "assertion-deleted double-reports"      'found.pop("assertion-deleted")' 'pass'
mut "orphan never reported"                 'hit("orphan-assert-deleted"' '(lambda *a: None)("orphan-assert-deleted"'
mut "orphan ignores duplicate tests"        'deduped = bool(rem_defs) and' 'deduped = False and'
mut "orphan not Python-only"                'if retired and fd.path.endswith(".py"):' 'if retired:'
mut "orphan ignores bound names"            'if r and r not in bound and' 'if r and True and'
echo "mutants: $n, survived/unapplied: $survived"
[ "$survived" -eq 0 ] || exit 1
exit 0
