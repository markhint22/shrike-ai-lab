#!/usr/bin/env bash
# 2026-10-22 PKG-B: a pytest clause `pytest sub/tests/t.py::test_m` run from the repo root, where sub/pytest.ini makes pytest print ids ROOTDIR-RELATIVE (`tests/t.py::TestX::test_m`),
# used to rc=4 and FAIL even though the class-method test exists and passes (29-41 FAIL rows in 7d on test-automation-agent + gitlark; TAA items looped 9 and 11 cycles).
# _verify_nodeid_fallback_cmd now accepts a collected file part that is a path-component suffix of the clause path and rebuilds the retry id from the ORIGINAL path.
# Part A uses a deterministic stub `pytest` (runs on the Mac and on the box mirror without pytest installed); part B uses a REAL pytest when one is found (skipped loudly otherwise).
# Mutation proof: with the old matching (OVN_VERIFY_NODEID_ROOTDIR=off) A1/B1 FAIL.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/.."
[ -f "$S/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
W="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME" "$W/bin" "$W/repo"
export PYTHONDONTWRITEBYTECODE=1 OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
# ---- stub pytest: ids are rootdir-relative (sub/ is the rootdir); the unqualified method id is rc 4, the qualified one passes ----
cat > "$W/bin/pytest" <<'EOS'
#!/bin/sh
for a in "$@"; do
  case "$a" in
    --collect-only) printf 'tests/t.py::TestX::test_m\ntests/t.py::TestX::test_other[a-1]\ntests/other.py::test_m2\n\n3 tests collected in 0.01s\n'; exit 0 ;;
  esac
done
for a in "$@"; do
  case "$a" in
    sub/tests/t.py::TestX::test_m) echo "1 passed in 0.01s"; exit 0 ;;
    sub/tests/t.py::test_m|sub/tests/t.py::test_zzz) echo "ERROR: not found: $a"; exit 4 ;;
    sub/tests/t.py::TestX::test_m\ sub/tests/t.py::TestX::test_m) echo "1 passed"; exit 0 ;;
  esac
done
echo "1 passed in 0.01s"; exit 0
EOS
chmod +x "$W/bin/pytest"
export PATH="$W/bin:$PATH"
. "$S/lib_verify_clause.sh"
PROG="$W/prog.md"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
cat > "$PROG" <<'EOP'
- [ ] [T2] sub/tests/t.py - class method addressed by bare name. VERIFY: `pytest sub/tests/t.py::test_m -v`
- [ ] [T2] sub/tests/t.py - a name that exists nowhere. VERIFY: `pytest sub/tests/t.py::test_zzz -v`
EOP
cd "$W/repo" || exit 1
chk(){ shadow_check "$1"; printf '%s' "$_LAST_VERIFY_RESULT"; }
eq "A1 rootdir-relative collected id: bare-name clause PASSES via the fallback" "$(chk 1)" PASS
eq "A2 mutation: OVN_VERIFY_NODEID_ROOTDIR=off (old exact-path matching) FAILs" "$(OVN_VERIFY_NODEID_ROOTDIR=off chk 1)" FAIL
eq "A3 kill switch OVN_VERIFY_NODEID_FALLBACK=off FAILs" "$(OVN_VERIFY_NODEID_FALLBACK=off chk 1)" FAIL
eq "A4 benign twin: a name that is not collected stays FAIL" "$(chk 2)" FAIL
eq "A5 the retry id is the ORIGINAL path + :: + rest" "$(_verify_nodeid_fallback_cmd 'pytest sub/tests/t.py::test_m -v' 30)" 'pytest sub/tests/t.py::TestX::test_m -v'
eq "A6 a suffix that is not a path COMPONENT (xtests/t.py vs sub/tests/t.py) is not accepted" "$(printf '#!/bin/sh\nprintf "stests/t.py::TestX::test_m\\n"\n' > "$W/bin/pytest2"; chmod +x "$W/bin/pytest2"; _verify_nodeid_fallback_cmd 'pytest2 sub/tests/t.py::test_m' 30)" ""
eq "A7 an exact-path collected id still works (no rootdir offset)" "$(printf '#!/bin/sh\nprintf "sub/tests/t.py::TestX::test_m\\n"\n' > "$W/bin/pytest3"; chmod +x "$W/bin/pytest3"; _verify_nodeid_fallback_cmd 'pytest3 sub/tests/t.py::test_m' 30)" 'pytest3 sub/tests/t.py::TestX::test_m'
# ---- part B: real pytest ----
RP=""
for c in "$(command -v python3)" "$OVN_TEST_PYTHON" /Users/*/LocalProjects/*/.venv/bin/python /home/*/overnight-queue/repos/*/.venv/bin/python /home/*/overnight-queue/repos/*/backend/.venv/bin/python; do
  [ -n "$c" ] && [ -x "$c" ] && "$c" -m pytest --version >/dev/null 2>&1 && { RP="$c"; break; }
done
if [ -z "$RP" ]; then
  echo "  SKIP (loud): part B needs a python with pytest; none found. Part A (stub) ran."
else
  mkdir -p "$W/real/sub/tests" && cd "$W/real" || exit 1
  printf '[pytest]\ntestpaths = tests\n' > sub/pytest.ini
  printf 'class TestLogin:\n    def test_login_invalid(self):\n        assert True\n' > sub/tests/t.py
  rm -f "$W/bin/pytest"; printf '#!/bin/sh\nexec "%s" -m pytest -p no:cacheprovider "$@"\n' "$RP" > "$W/bin/pytest"; chmod +x "$W/bin/pytest"
  printf -- '- [ ] [T2] sub/tests/t.py - real. VERIFY: `pytest sub/tests/t.py::test_login_invalid -q`\n' > "$PROG"
  eq "B1 REAL pytest (sub/pytest.ini rootdir): bare method name PASSES" "$(chk 1)" PASS
  eq "B2 mutation: old matching FAILs on real pytest too" "$(OVN_VERIFY_NODEID_ROOTDIR=off chk 1)" FAIL
fi
echo "test_verify_nodeid_rootdir: pass=$P fail=$F"
[ "$F" = 0 ]
