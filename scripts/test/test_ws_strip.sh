#!/usr/bin/env bash
# ovn_ws_strip.py: only whitespace-ONLY lines change; python multi-line string contents, code-line trailing whitespace,
# CRLF endings, non-code files and skip dirs are untouched; result still compiles; idempotent; --check reports.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../ovn_ws_strip.py"; [ -f "$S" ] || S="$HERE/ovn_ws_strip.py"
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; cd "$T"; git init -q .; git config user.email t@t; git config user.name t
mkdir -p node_modules/x
printf 'def f():\n    x = 1   \n    \n    s = """keep\n    \n  inner"""\n\treturn x\n' | sed 's/^\treturn/    return/' > a.py
printf 'const a = 1;\n  \n\t\nconst b = 2; \n' > b.ts
printf 'line1\r\n    \r\nline3\r\n' > c.kt
printf 'notes\n    \nmore\n' > d.md
printf '  \n' > node_modules/x/e.js
printf 'x = 1\n    ' > eof.py    # ends in a whitespace-only line with NO newline
git add -A; git commit -q -m base
out="$(python3 "$S" . --check)"; rc=$?
ok "--check exits 1 and reports without changing files" "$([ $rc = 1 ] && echo "$out" | grep -q 'check only' && git diff --quiet && echo 1 || echo 0)"
python3 "$S" . >/dev/null
ok "python still compiles" "$(python3 -m py_compile a.py 2>/dev/null && echo 1 || echo 0)"
ok "python: blank code line emptied, line inside the string literal kept" "$([ "$(sed -n 3p a.py)" = "" ] && [ "$(sed -n 5p a.py)" = "    " ] && echo 1 || echo 0)"
ok "code-line trailing whitespace is NOT touched" "$([ "$(sed -n 2p a.py)" = "    x = 1   " ] && [ "$(sed -n 4p b.ts)" = "const b = 2; " ] && echo 1 || echo 0)"
ok "ts: both space-only and tab-only lines emptied" "$([ "$(sed -n 2p b.ts)" = "" ] && [ "$(sed -n 3p b.ts)" = "" ] && echo 1 || echo 0)"
ok "CRLF preserved on emptied line" "$([ "$(sed -n 2p c.kt | od -c | head -1 | grep -c '\\r')" = 1 ] && [ "$(wc -c < c.kt | tr -d ' ')" = "$(printf 'line1\r\n\r\nline3\r\n' | wc -c | tr -d ' ')" ] && echo 1 || echo 0)"
ok ".md and node_modules untouched" "$(git diff --quiet -- d.md node_modules && echo 1 || echo 0)"
ok "idempotent: second run changes nothing" "$(python3 "$S" . | grep -q 'files_changed=0' && echo 1 || echo 0)"
ok "the whole change is whitespace-only (whitespace-insensitive content identical)" "$(for f in a.py b.ts c.kt eof.py; do [ "$(git show HEAD:$f | tr -d " \t\r\n" | md5sum 2>/dev/null | cut -c1-32 || true)" = "$(tr -d " \t\r\n" < $f | md5sum 2>/dev/null | cut -c1-32)" ] || echo BAD; done | grep -q BAD && echo 0 || echo 1)"
ok "EOF whitespace-only line without newline is handled and file compiles" "$(python3 -m py_compile eof.py 2>/dev/null && [ "$(tail -c1 eof.py | od -An -c | tr -d " ")" = "\\n" ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
