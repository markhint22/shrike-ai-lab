#!/usr/bin/env bash
# Regression tests for ovn_progress_slice.py: UTF-8-boundary-safe byte-budget head/tail slicing of
# OVERNIGHT_PROGRESS.md (a raw head -c/tail -c can split a multibyte char and crash the downstream JSON encode).
# Hermetic: temp files only, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$HERE/../ovn_progress_slice.py"; [ -f "$PY" ] || PY="$HOME/overnight-queue/scripts/ovn_progress_slice.py"
[ -f "$PY" ] || { echo "  SKIP: script not found"; exit 0; }
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
hex(){ od -An -tx1 -v | tr -d ' \n'; }
# em-dash = e2 80 94 (3 bytes); "ab—cd" = 61 62 e2 80 94 63 64 (7 bytes)
EM='ab—cd'
head_(){ printf '%s' "$2" | python3 "$PY" head "$1" | hex; }

echo "== head =="
eqv "head 5 ends exactly after the em-dash -> complete char kept" "6162e28094" "$(head_ 5 "$EM")"
eqv "head 7 (covers all) incl. trailing chars" "6162e280946364" "$(head_ 7 "$EM")"
eqv "head 100 (budget > input) = input unchanged" "6162e280946364" "$(head_ 100 "$EM")"
eqv "head cuts after 1st byte of em-dash -> partial bytes dropped" "6162" "$(head_ 3 "$EM")"
eqv "head cuts after 2nd byte of em-dash -> partial bytes dropped" "6162" "$(head_ 4 "$EM")"
eqv "head 2 = clean ascii boundary" "6162" "$(head_ 2 "$EM")"
eqv "head 0 -> empty" "" "$(head_ 0 "$EM")"
eqv "head on empty stdin -> empty" "" "$(head_ 10 "")"
eqv "pure-ascii input: exactly N bytes" "hello" "$(printf 'hello world' | python3 "$PY" head 5)"
chk "output is ALWAYS strictly-valid UTF-8 at every cut point" bash -c '
  s="x—y—z—é—日本語—"
  for n in $(seq 0 40); do printf "%s" "$s" | python3 "'"$PY"'" head $n | python3 -c "import sys; sys.stdin.buffer.read().decode(\"utf-8\")" || exit 1; done'
eqv "invalid stray byte (0xff) is dropped, rest preserved" "6162" "$(printf 'a\xffb' | python3 "$PY" head 10 | hex)"
eqv "4-byte emoji cut mid-sequence is dropped" "61" "$(printf 'a\xf0\x9f\x98\x80' | python3 "$PY" head 3 | hex)"
eqv "4-byte emoji intact when budget covers it" "61f09f9880" "$(printf 'a\xf0\x9f\x98\x80' | python3 "$PY" head 5 | hex)"
eqv "newlines preserved (no text-mode translation)" "610a62" "$(printf 'a\nb' | python3 "$PY" head 9 | hex)"

echo "== tail =="
printf 'ab—cd' > "$T/f.md"     # 7 bytes
tail_(){ python3 "$PY" tail "$1" "$2" | hex; }
eqv "tail 2 = last two ascii bytes" "6364" "$(tail_ 2 "$T/f.md")"
eqv "tail 4 starts on em-dash's last 2 bytes -> dropped" "6364" "$(tail_ 4 "$T/f.md")"
eqv "tail 3 starts on em-dash's final byte -> dropped" "6364" "$(tail_ 3 "$T/f.md")"
eqv "tail 5 starts exactly on em-dash -> kept" "e280946364" "$(tail_ 5 "$T/f.md")"
eqv "tail 100 (> size) = whole file" "6162e280946364" "$(tail_ 100 "$T/f.md")"
eqv "tail 0 -> empty" "" "$(tail_ 0 "$T/f.md")"
: > "$T/empty.md"
eqv "tail of empty file -> empty" "" "$(tail_ 10 "$T/empty.md")"
printf 'line1\nline2\nline3\n' > "$T/a.md"
eqv "tail returns newline-intact trailing slice" "line3" "$(python3 "$PY" tail 6 "$T/a.md")"
chk "tail output strictly valid UTF-8 at every cut point" bash -c '
  printf "x—y—z—é—日本語—" > "'"$T"'/u.md"
  for n in $(seq 0 40); do python3 "'"$PY"'" tail $n "'"$T"'/u.md" | python3 -c "import sys; sys.stdin.buffer.read().decode(\"utf-8\")" || exit 1; done'

echo "== usage / error paths =="
err="$(python3 "$PY" 2>&1 >/dev/null)"; rc=$?
eqv "no args -> exit 2" "2" "$rc"
chk "no args -> usage on stderr" grep -q 'usage: ovn_progress_slice.py head N | tail N FILE' <<<"$err"
python3 "$PY" head >/dev/null 2>&1; eqv "mode without N -> exit 2" "2" "$?"
err="$(python3 "$PY" tail 5 2>&1 >/dev/null)"; rc=$?
eqv "tail without FILE -> exit 2" "2" "$rc"
chk "tail without FILE -> tail-specific usage" grep -q 'usage: ovn_progress_slice.py tail N FILE' <<<"$err"
err="$(echo x | python3 "$PY" bogus 5 2>&1 >/dev/null)"; rc=$?
eqv "unknown mode -> exit 2" "2" "$rc"
chk "unknown mode named on stderr" grep -q 'unknown mode: bogus' <<<"$err"
echo x | python3 "$PY" head notanumber >/dev/null 2>&1; chk "non-integer N -> nonzero exit" test "$?" -ne 0
python3 "$PY" tail 5 "$T/nope.md" >/dev/null 2>&1; chk "tail on missing file -> nonzero exit" test "$?" -ne 0
eqv "stdout stays clean on usage error" "" "$(python3 "$PY" 2>/dev/null)"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
