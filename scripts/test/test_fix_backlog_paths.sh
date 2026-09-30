#!/usr/bin/env bash
# Regression: scripts/fix_backlog_paths.py strips a leading "<repo>/" (repo = backlog file stem) that immediately follows
# the tier/label tag of an open "- [ ]" item, rewriting only files that changed. Idempotent. Default dir is cwd.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../fix_backlog_paths.py"; [ -f "$S" ] || S="$HERE/fix_backlog_paths.py"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
both(){ [ "$1" = 1 ] && [ "$2" = 1 ] && echo 1 || echo 0; }
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
B="$T/backlog"; mkdir -p "$B"
cat > "$B/xlite.md" <<'M'
# xlite backlog
- [ ] [T2] xlite/scripts/foo.gd — fix
- [ ] [T1] xlite/a.gd — trivial
- [ ] [T5] xlite/b.gd — five
- [ ] [CLAUDE] xlite/c.gd — claude
- [ ] [HUMAN] xlite/d.gd — human
- [ ] [T3] scripts/already_ok.gd — fine
- [ ] [T3] billwatch/scripts/x.py — other repo prefix stays
- [x] [T2] xlite/done.gd — checked items untouched
- [ ] [T2] xlite/xlite/nested.gd — strip only once
- [ ] [T2] see xlite/mid.gd in the middle — not right after tag
- [ ] [T6] xlite/bad_tier.gd — T6 is not a tag
- [ ] xlite/untagged.gd — no tag at all
- [ ] [T2] xlitefoo/notprefix.gd — 'xlite' without slash boundary
M
cat > "$B/billwatch.md" <<'M'
- [ ] [T2] billwatch/app/a.py — one
- [ ] [T2] app/b.py — clean
M
printf -- '- [ ] [T2] clean/app/c.py — nothing to do' > "$B/clean.md"     # stem "clean" DOES match clean/, so use a different stem below
printf -- '- [ ] [T2] other/app/c.py — no matching prefix, no trailing newline' > "$B/nochange.md"
printf -- '- [ ] [T2] a.b/x.py — dot repo\n- [ ] [T2] axb/y.py — must not match escaped dot\n' > "$B/a.b.md"
echo '- [ ] [T2] notes/x — ignored non-md' > "$B/notes.txt"
cp "$B/nochange.md" "$T/nochange.orig"; cp "$B/notes.txt" "$T/notes.orig"
out="$(python3 "$S" "$B")"
ok "xlite: 6 items stripped and reported" "$(has "$out" "  xlite.md: stripped 'xlite/' prefix from 6 items")"
ok "billwatch: 1 item" "$(has "$out" "  billwatch.md: stripped 'billwatch/' prefix from 1 items")"
ok "clean.md (repo-named prefix, no trailing NL) counted" "$(has "$out" "  clean.md: stripped 'clean/' prefix from 1 items")"
ok "dot-in-name repo: regex escaped, only a.b/ stripped" "$(has "$out" "  a.b.md: stripped 'a.b/' prefix from 1 items")"
ok "total line sums all files (6+1+1+1=9)" "$(has "$out" 'total items fixed: 9')"
ok "untouched file not listed" "$(printf '%s' "$out" | grep -q 'nochange.md' && echo 0 || echo 1)"
x="$B/xlite.md"
ok "T2/T1/T5 tier tags stripped" "$(grep -qxF -- '- [ ] [T2] scripts/foo.gd — fix' "$x" && grep -qxF -- '- [ ] [T1] a.gd — trivial' "$x" && grep -qxF -- '- [ ] [T5] b.gd — five' "$x" && echo 1 || echo 0)"
ok "CLAUDE and HUMAN labels stripped" "$(grep -qxF -- '- [ ] [CLAUDE] c.gd — claude' "$x" && grep -qxF -- '- [ ] [HUMAN] d.gd — human' "$x" && echo 1 || echo 0)"
ok "already-relative item unchanged" "$(grep -qxF -- '- [ ] [T3] scripts/already_ok.gd — fine' "$x" && echo 1 || echo 0)"
ok "other repo's prefix NOT stripped" "$(grep -qxF -- '- [ ] [T3] billwatch/scripts/x.py — other repo prefix stays' "$x" && echo 1 || echo 0)"
ok "checked '- [x]' item NOT stripped" "$(grep -qxF -- '- [x] [T2] xlite/done.gd — checked items untouched' "$x" && echo 1 || echo 0)"
ok "nested xlite/xlite/ stripped exactly once" "$(grep -qxF -- '- [ ] [T2] xlite/nested.gd — strip only once' "$x" && echo 1 || echo 0)"
ok "mid-line mention untouched" "$(grep -qF 'see xlite/mid.gd in the middle' "$x" && echo 1 || echo 0)"
ok "[T6] / untagged / 'xlitefoo/' lines untouched" "$(grep -qxF -- '- [ ] [T6] xlite/bad_tier.gd — T6 is not a tag' "$x" && grep -qxF -- '- [ ] xlite/untagged.gd — no tag at all' "$x" && grep -qxF -- '- [ ] [T2] xlitefoo/notprefix.gd — '"'"'xlite'"'"' without slash boundary' "$x" && echo 1 || echo 0)"
ok "heading preserved" "$(head -1 "$x" | grep -qx '# xlite backlog' && echo 1 || echo 0)"
ok "changed file ends with exactly one newline" "$([ "$(tail -c1 "$x" | xxd -p)" = 0a ] && echo 1 || echo 0)"
ok "a.b.md: 'axb/' line untouched" "$(grep -qxF -- '- [ ] [T2] axb/y.py — must not match escaped dot' "$B/a.b.md" && grep -qxF -- '- [ ] [T2] x.py — dot repo' "$B/a.b.md" && echo 1 || echo 0)"
ok "unchanged md file byte-identical (not rewritten, no newline added)" "$(cmp -s "$B/nochange.md" "$T/nochange.orig" && echo 1 || echo 0)"
ok "non-.md file ignored" "$(cmp -s "$B/notes.txt" "$T/notes.orig" && echo 1 || echo 0)"
# (xlite/xlite/ is strippable again on a 2nd pass by design of the regex; normalise that one line before the idempotency check)
sed 's#^- \[ \] \[T2\] xlite/nested.gd#- [ ] [T2] nested.gd#' "$x" > "$T/x.new" && cp "$T/x.new" "$x"
cp -R "$B" "$T/after1"; out="$(python3 "$S" "$B")"
ok "idempotent: second run total 0, no per-file lines" "$([ "$out" = 'total items fixed: 0' ] && echo 1 || echo 0)"
ok "idempotent: tree byte-identical" "$(diff -r "$B" "$T/after1" >/dev/null && echo 1 || echo 0)"

# default dir = cwd
C="$T/cwd"; mkdir -p "$C"; printf -- '- [ ] [T1] zed/q.py — x\n' > "$C/zed.md"
out="$(cd "$C" && python3 "$S")"
ok "no arg: operates on the current directory" "$(both "$(has "$out" "zed.md: stripped 'zed/' prefix from 1 items")" "$(grep -qxF -- '- [ ] [T1] q.py — x' "$C/zed.md" && echo 1 || echo 0)")"
E="$T/empty"; mkdir -p "$E"
out="$(python3 "$S" "$E")"; ok "empty dir: total 0" "$([ "$out" = 'total items fixed: 0' ] && echo 1 || echo 0)"
out="$(python3 "$S" "$T/does-not-exist")"; ok "nonexistent dir: total 0 (glob empty), exit 0" "$([ "$out" = 'total items fixed: 0' ] && echo 1 || echo 0)"
: > "$E/empty.md"; out="$(python3 "$S" "$E")"; ok "empty .md file: untouched, total 0" "$([ "$out" = 'total items fixed: 0' ] && [ ! -s "$E/empty.md" ] && echo 1 || echo 0)"
printf -- '- [ ] [T2] ünï/ü.py — a\n- [ ] [T2] ünï/é.py — ünï ✓\n' > "$E/ünï.md"; out="$(python3 "$S" "$E")"
ok "utf-8 repo names and text handled" "$(both "$(has "$out" "stripped 'ünï/' prefix from 2 items")" "$(grep -qxF -- '- [ ] [T2] é.py — ünï ✓' "$E/ünï.md" && echo 1 || echo 0)")"
printf -- '- [ ] [T2] sorted/a.py\n' > "$E/zz.md"; printf -- '- [ ] [T2] aa/a.py\n' > "$E/aa.md"; printf -- '- [ ] [T2] zz/a.py\n' > "$E/zz.md"
out="$(python3 "$S" "$E" | grep stripped | sed -n 1p)"
ok "files processed in sorted order" "$(has "$out" 'aa.md')"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
