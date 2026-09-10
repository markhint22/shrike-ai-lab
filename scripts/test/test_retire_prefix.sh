#!/usr/bin/env bash
# Regression for the 2026-09-04 bug: ovn_retire_vague.classify() retired every backlog item
# whose path carried a leading "<repo>/" prefix as dead-path (282 valid items silently deleted).
# classify() must now tolerate the prefix (strip one leading component when checking existence),
# while still retiring genuinely-missing paths.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RV="$HERE/../ovn_retire_vague.py"; [ -f "$RV" ] || RV="$HERE/ovn_retire_vague.py"
[ -f "$RV" ] || { echo "  ❌ ovn_retire_vague.py not found"; exit 1; }
rc=0; fail(){ echo "  ❌ $1"; rc=1; }; ok(){ echo "  ✅ $1"; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/pkgdir"; echo "y = 1" > "$tmp/pkgdir/mod.py"
RVDIR="$(cd "$(dirname "$RV")" && pwd)"
cd "$tmp"
out=$(RVDIR="$RVDIR" python3 - <<'PY'
import os, sys
sys.path.insert(0, os.environ["RVDIR"])
from ovn_retire_vague import classify
print("A", classify("- [ ] [T2] myrepo/pkgdir/mod.py — do X. One file."))   # prefixed, exists -> keep
print("B", classify("- [ ] [T2] pkgdir/mod.py — do X. One file."))          # clean, exists -> keep
print("C", classify("- [ ] [T2] ghost/none.py — do X. One file."))          # missing -> dead-path
PY
)
echo "$out" | grep -q "^A None"      && ok "<repo>/-prefixed existing file KEPT (the bug)" || fail "A: $out"
echo "$out" | grep -q "^B None"      && ok "clean existing file KEPT"                        || fail "B: $out"
echo "$out" | grep -q "^C dead-path" && ok "genuinely-missing file still retired"           || fail "C: $out"
[ $rc -eq 0 ] && echo "  test_retire_prefix: PASS" || echo "  test_retire_prefix: FAIL"
exit $rc
