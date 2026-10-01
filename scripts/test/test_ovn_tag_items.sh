#!/usr/bin/env bash
# Regression: scripts/ovn_tag_items.py prefixes each unchecked, non-human, not-yet-tagged item with its ovn_classify tag
# {lang·type·complexity·verif}; idempotent; prints GENERATED_TAGS=<n>. Runs against COPIES in a temp dir (no __pycache__ in the tree).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/.."; [ -f "$D/ovn_tag_items.py" ] || D="$HERE"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then echo "  ok   $1"; else echo "  WARN KNOWN-BUG: $1 (non-fatal)"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/s"; cp "$D/ovn_tag_items.py" "$D/ovn_classify.py" "$T/s/"
S="$T/s/ovn_tag_items.py"; C="$T/s/ovn_classify.py"
tagof(){ python3 "$C" --tag "$1"; }
P="$T/p.md"
L1='app/foo.py — replace the bare except with except Exception. One line.'
L2='web/src/A.vue — add type="button" to the close button'
L3='ios/V.swift — rename helper'
printf '%s\n' '## Next Steps' "- [ ] $L1" "- [ ] [CLAUDE] $L2" "- [x] $L3" "- [ ] $L3 HUMAN-ONLY" "- [ ] human/ review the design" \
  '- [ ] [T1] (retired-vague) thing' '- [ ] blocked item: BLOCKED ITEM waiting' '- [ ] {py·x·T1·y} already tagged' '- [ ] [CLAUDE] {py·x·T1·y} already tagged w/ label' \
  'prose line - [ ] not an item' '- [ ]' '- [ ]x glued' > "$P"
out="$(python3 "$S" "$P")"
ok "prints GENERATED_TAGS=2 (only the two eligible items)" "$([ "$out" = "GENERATED_TAGS=2" ] && echo 1 || echo 0)"
t1="$(tagof "$L1")"; t2="$(tagof "$L2")"
ok "classifier sanity: tag has 4 dot-separated parts" "$(printf '%s' "$t1" | grep -qE '^\{[a-z]+·[a-z0-9]+·T[1-5]·[a-z-]+\}$' && echo 1 || echo 0)"
ok "plain item prefixed with its tag right after checkbox" "$(grep -qxF -- "- [ ] $t1 $L1" "$P" && echo 1 || echo 0)"
ok "known-good tag for bare-except item" "$([ "$t1" = '{py·syntax·T1·test-covered}' ] && echo 1 || echo 0)"
ok "[CLAUDE]-labelled item: tag goes AFTER the label" "$(grep -qxF -- "- [ ] [CLAUDE] $t2 $L2" "$P" && echo 1 || echo 0)"
ok "checked item untouched" "$(grep -qxF -- "- [x] $L3" "$P" && echo 1 || echo 0)"
ok "HUMAN-ONLY item untouched" "$(grep -qxF -- "- [ ] $L3 HUMAN-ONLY" "$P" && echo 1 || echo 0)"
ok "human/ item untouched" "$(grep -qxF -- '- [ ] human/ review the design' "$P" && echo 1 || echo 0)"
ok "retired- item untouched" "$(grep -qxF -- '- [ ] [T1] (retired-vague) thing' "$P" && echo 1 || echo 0)"
ok "BLOCKED ITEM (case-insensitive SKIP regex) untouched" "$(grep -qxF -- '- [ ] blocked item: BLOCKED ITEM waiting' "$P" && echo 1 || echo 0)"
ok "already-tagged items (with and without [LABEL]) untouched" "$(grep -qxF -- '- [ ] {py·x·T1·y} already tagged' "$P" && grep -qxF -- '- [ ] [CLAUDE] {py·x·T1·y} already tagged w/ label' "$P" && echo 1 || echo 0)"
ok "prose / bare '- [ ]' / glued '- [ ]x' lines preserved verbatim" "$(grep -qxF -- 'prose line - [ ] not an item' "$P" && grep -qxF -- '- [ ]' "$P" && grep -qxF -- '- [ ]x glued' "$P" && echo 1 || echo 0)"
ok "header preserved, line count unchanged" "$([ "$(grep -c '' "$P")" = 13 ] && head -1 "$P" | grep -qx '## Next Steps' && echo 1 || echo 0)"
cp "$P" "$T/b"; out="$(python3 "$S" "$P")"
ok "idempotent: second run GENERATED_TAGS=0" "$([ "$out" = "GENERATED_TAGS=0" ] && echo 1 || echo 0)"
ok "idempotent: file unchanged" "$(cmp -s "$P" "$T/b" && echo 1 || echo 0)"

# tier-tag interplay (downstream ovn_filesize_retag matches ^- [ ] [T1|T2] at line start)
printf '%s\n' '- [ ] [T2] app/big.py — rework the module' > "$P"; python3 "$S" "$P" >/dev/null
kb "leading [T1]/[T2] tier tag stays first on the line after tagging (regex (\\[[A-Z]+\\] ) does not match [T2] because of the digit)" "$(grep -q '^- \[ \] \[T[1-5]\] ' "$P" && echo 1 || echo 0)"
ok "[T2] item still gets exactly one {tag} and keeps its text" "$([ "$(grep -o '{[^}]*}' "$P" | wc -l | tr -d ' ')" = 1 ] && grep -qF 'app/big.py — rework the module' "$P" && grep -qE '^- \[ \] \[T2\] \{' "$P" && echo 1 || echo 0)"   # tag goes right after the tier label (regex fixed 2026-09-30)"

# multiple files, missing file, counts
printf '%s\n' '- [ ] app/a.py — one' > "$T/f1.md"; printf '%s\n' '- [ ] app/b.py — two' '- [ ] app/c.py — three' > "$T/f2.md"
out="$(python3 "$S" "$T/f1.md" "$T/missing.md" "$T/f2.md")"
ok "multiple files: counts summed, missing path skipped" "$([ "$out" = "GENERATED_TAGS=3" ] && echo 1 || echo 0)"
ok "each file rewritten" "$([ "$(cat "$T/f1.md" "$T/f2.md" | grep -c '^- \[ \] {')" = 3 ] && echo 1 || echo 0)"
out="$(python3 "$S")"; ok "no args: GENERATED_TAGS=0" "$([ "$out" = "GENERATED_TAGS=0" ] && echo 1 || echo 0)"
out="$(python3 "$S" "$T/missing.md")"; ok "only missing file: GENERATED_TAGS=0, no file created" "$([ "$out" = "GENERATED_TAGS=0" ] && [ ! -e "$T/missing.md" ] && echo 1 || echo 0)"

# newline handling
printf -- '- [ ] app/a.py — no trailing newline' > "$P"; python3 "$S" "$P" >/dev/null
ok "file without trailing newline gets exactly one" "$([ "$(tail -c1 "$P" | xxd -p)" = 0a ] && [ "$(grep -c '' "$P")" = 1 ] && echo 1 || echo 0)"
printf -- '- [ ] app/a.py — crlf\r\n- [ ] app/b.py — crlf2\r\n' > "$P"; python3 "$S" "$P" >/dev/null
ok "CRLF input normalised to LF" "$(grep -q $'\r' "$P" && echo 0 || echo 1)"
: > "$P"; out="$(python3 "$S" "$P")"
ok "empty file: 0 tags" "$([ "$out" = "GENERATED_TAGS=0" ] && echo 1 || echo 0)"
printf -- '- [ ] ünï — ✓ text.py\n' > "$P"; python3 "$S" "$P" >/dev/null
ok "utf-8 item text survives" "$(grep -qF 'ünï — ✓ text.py' "$P" && echo 1 || echo 0)"
printf -- '- [ ] no file path at all, just words\n' > "$P"; python3 "$S" "$P" >/dev/null
ok "item with no file path -> lang 'other' + build-verified tag" "$(grep -q '^- \[ \] {other·[a-z0-9]*·T[1-5]·build-verified} ' "$P" && echo 1 || echo 0)"
printf -- '- [ ] see `ios/X.swift` please\n' > "$P"; python3 "$S" "$P" >/dev/null
ok "backticked path classified (swift -> unverifiable)" "$(grep -q '{swift·[a-z0-9]*·T[1-5]·unverifiable}' "$P" && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
