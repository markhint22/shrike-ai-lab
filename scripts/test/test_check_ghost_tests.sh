#!/usr/bin/env bash
# Tests for scripts/check_ghost_tests.py (2026-10-18) incl. mutant (a checker that never flags must fail these).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
CK="${OVN_CHECK_GHOST:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)/check_ghost_tests.py}"
[ -f "$CK" ] || { echo "  SKIP: $CK not found"; exit 0; }
P=0; F=0
T="$(safe_mktemp_dir ghost)" || exit 1
R="$T/repo"; mkdir -p "$R/backend/tests" "$R/tests"
g(){ git -C "$R" -c user.email=t@t -c user.name=t "$@"; }
chk(){ local want="$1" name="$2"; shift 2; python3 -I "$CK" "$@" >"$T/out" 2>&1; local rc=$?; if [ "$rc" = "$want" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $name (rc=$rc want=$want)"; cat "$T/out"; fi; }
g init -q -b main
: > "$R/backend/pytest.ini"; : > "$R/backend/tests/conftest.py"; echo "x=1" > "$R/README"
g add -A; g commit -qm base; B="$(g rev-parse HEAD)"
echo "def test_a(): assert 1" > "$R/backend/tests/test_a.py"; g add -A; g commit -qm ok; A1="$(g rev-parse HEAD)"
chk 0 "test under the pytest root is clean" "$R" "$B" "$A1"
echo "def test_b(): assert 1" > "$R/tests/test_b.py"; g add -A; g commit -qm ghost; A2="$(g rev-parse HEAD)"
chk 1 "root tests/ outside backend/pytest.ini is a ghost" "$R" "$A1" "$A2"
grep -q "tests/test_b.py" "$T/out" && P=$((P+1)) || { F=$((F+1)); echo "  FAIL: message names the file"; }
echo "x=2" > "$R/README"; g add -A; g commit -qm doc; A3="$(g rev-parse HEAD)"
chk 0 "non-test change is clean" "$R" "$A2" "$A3"
# repo with no pytest config anywhere: silent
R2="$T/repo2"; mkdir -p "$R2/tests"; git -C "$R2" init -q -b main; echo "def test_c(): pass" > "$R2/tests/test_c.py"
git -C "$R2" -c user.email=t@t -c user.name=t add -A; git -C "$R2" -c user.email=t@t -c user.name=t commit -qm c; C="$(git -C "$R2" rev-parse HEAD)"
chk 0 "no collection root known -> silent" "$R2" "$C" "$C"
safe_rm_rf "$T"
echo "  passed=$P failed=$F"; [ "$F" = 0 ]
