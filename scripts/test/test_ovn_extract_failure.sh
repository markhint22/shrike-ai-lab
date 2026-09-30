#!/usr/bin/env bash
# Regression tests for ovn_extract_failure.sh: grounded, verbatim one-line summary of the most recent real
# test failure in a task log (pytest FAILED/E lines, vitest/jest lines, generic error fallback), capped at 500 chars.
# Hermetic: synthetic logs in a temp dir.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SH="$HERE/../ovn_extract_failure.sh"; [ -f "$SH" ] || SH="$HOME/overnight-queue/scripts/ovn_extract_failure.sh"
[ -f "$SH" ] || { echo "  SKIP: script not found"; exit 0; }
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ex(){ bash "$SH" "$@"; }

echo "== no-input paths =="
eqv "no argument -> empty" "" "$(ex)"
ex >/dev/null 2>&1; eqv "no argument -> exit 0" "0" "$?"
eqv "missing file -> empty" "" "$(ex "$T/nope.log")"
ex "$T/nope.log" >/dev/null 2>&1; eqv "missing file -> exit 0" "0" "$?"
: > "$T/empty.log"
eqv "empty log -> empty" "" "$(ex "$T/empty.log")"
printf 'all good\n12 passed in 0.3s\n' > "$T/clean.log"
eqv "log with nothing failure-like -> empty" "" "$(ex "$T/clean.log")"

echo "== pytest =="
cat > "$T/py1.log" <<'L'
collecting ...
tests/test_a.py .F
    def test_x():
>       assert add(1, 1) == 3
E       assert 2 == 3
FAILED tests/test_a.py::test_x - assert 2 == 3
1 failed, 1 passed in 0.12s
L
out="$(ex "$T/py1.log")"
eqv "assert line + E line + FAILED line, single line, squeezed" "> assert add(1, 1) == 3 E assert 2 == 3 FAILED tests/test_a.py::test_x - assert 2 == 3" "$out"
chk "output is a single line (no embedded newline)" bash -c '[ "$(printf "%s" "$1" | wc -l)" = 0 ]' _ "$out"
chk "includes the verbatim FAILED test id" grep -q 'FAILED tests/test_a.py::test_x - assert 2 == 3' <<<"$out"

# only two lines of context above FAILED are considered
cat > "$T/py2.log" <<'L'
E       far-away assertion detail (3 lines above, must be excluded)
noise 1
noise 2
FAILED tests/test_b.py::test_y - boom
L
out="$(ex "$T/py2.log")"
eqv "context window is -B2: the 3-lines-up E line is excluded" "FAILED tests/test_b.py::test_y - boom" "$out"
cat > "$T/py3.log" <<'L'
E       near detail
noise
FAILED tests/test_b.py::test_y - boom
L
eqv "E line within 2 lines above is included" "E near detail FAILED tests/test_b.py::test_y - boom" "$(ex "$T/py3.log")"

# cap at 6 lines
{ for i in 1 2 3 4 5 6 7 8; do echo "FAILED tests/t.py::test_$i - e$i"; done; } > "$T/py4.log"
out="$(ex "$T/py4.log")"
eqv "at most 6 pytest lines" "6" "$(printf '%s' "$out" | grep -o 'FAILED' | wc -l)"
chk "first six kept (test_1..test_6)" grep -q 'test_6' <<<"$out"
chk "seventh dropped" bash -c '! grep -q test_7 <<<"$1"' _ "$out"

# indented FAILED is not a pytest summary line -> falls through to the generic fallback
printf '  FAILED indented line\n' > "$T/py5.log"
eqv "indented FAILED doesn't match the pytest pattern but the fallback still surfaces it" "FAILED indented line" "$(ex "$T/py5.log" | sed 's/^ *//')"

echo "== vitest / jest =="
cat > "$T/js1.log" <<'L'
 ❯ src/foo.test.ts (2 tests | 1 failed)
   × bar
AssertionError: expected 1 to be 2
L
out="$(ex "$T/js1.log")"
chk "vitest: file line kept" grep -q '❯ src/foo.test.ts' <<<"$out"
chk "vitest: AssertionError line kept" grep -q 'AssertionError: expected 1 to be 2' <<<"$out"
cat > "$T/js2.log" <<'L'
  expected { a: 1 } to deep equal { a: 2 }
L
eqv "jest 'expected X to deep equal' line matched" "expected { a: 1 } to deep equal { a: 2 }" "$(ex "$T/js2.log" | sed 's/^ *//')"
printf 'expected foo to equal bar\n' > "$T/js3.log"
eqv "'expected .. to equal' matched" "expected foo to equal bar" "$(ex "$T/js3.log")"
printf 'src/a.spec.tsx\n ❯ src/a.spec.tsx > renders\n' > "$T/js4.log"
chk "❯ .spec.tsx variant matched" grep -q '❯ src/a.spec.tsx' <<<"$(ex "$T/js4.log")"
{ for i in 1 2 3 4 5 6 7 8; do echo " ❯ src/f$i.test.ts"; done; } > "$T/js5.log"
eqv "at most 6 js lines" "6" "$(ex "$T/js5.log" | grep -o '❯' | wc -l)"

# pytest wins over js when both are present
cat > "$T/both.log" <<'L'
FAILED tests/test_p.py::test_z - boom
AssertionError: js-ish thing
L
out="$(ex "$T/both.log")"
chk "pytest summary preferred over js evidence" grep -q 'FAILED tests/test_p.py' <<<"$out"
chk "js line not mixed into the pytest summary" bash -c '! grep -q "js-ish" <<<"$1"' _ "$out"

echo "== generic fallback =="
cat > "$T/gen.log" <<'L'
starting build
Error: cannot find module 'x'
done step
BUILD FAILED with 2 errors
L
out="$(ex "$T/gen.log")"
eqv "fallback = error/failed lines (case-insensitive), verbatim" "Error: cannot find module 'x' BUILD FAILED with 2 errors" "$out"
{ for i in 1 2 3 4 5 6 7 8 9; do echo "error number $i"; done; } > "$T/gen2.log"
out="$(ex "$T/gen2.log")"
eqv "fallback keeps the LAST 6 lines" "error number 4 error number 5 error number 6 error number 7 error number 8 error number 9" "$out"

echo "== truncation / whitespace =="
python3 -c "print('FAILED tests/t.py::test_long - ' + 'x'*1200)" > "$T/long.log"
out="$(ex "$T/long.log")"
eqv "output capped at 500 chars" "500" "${#out}"
printf 'FAILED   tests/t.py::t  -    spaced     out\n' > "$T/sp.log"
eqv "runs of spaces squeezed to one" "FAILED tests/t.py::t - spaced out" "$(ex "$T/sp.log")"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
