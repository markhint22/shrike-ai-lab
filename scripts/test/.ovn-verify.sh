#!/bin/bash
# fake repo-owned verification: mode from $RO_STUB/verify.<repo-dir-name> or RO_VERIFY = skip|assertfail|ok(default)
m="$(cat "${RO_STUB:-/nonexistent}/verify.$(basename "$PWD")" 2>/dev/null || echo "${RO_VERIFY:-ok}")"
case "$m" in
  skip) echo "SKIPPED — venv lock contended, not treating as a failure"; exit 0;;
  assertfail) echo "FAILED tests/test_x.py::test_x - AssertionError: assert 1 == 2"; echo "1 failed, 4 passed"; exit 1;;
esac
rc=0
for f in $(git ls-files '*.py'); do
  python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$f" 2>/dev/null || { echo "SyntaxError: invalid syntax in $f"; rc=1; }
done
[ "$rc" = 0 ] && echo "verify ok"
exit $rc
