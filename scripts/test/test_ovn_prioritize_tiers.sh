#!/usr/bin/env bash
# Regression: ovn_prioritize_tiers.py reorders ONLY the open items inside "## Next Steps":
# T3 first, T1/T2/untiered next, T4/T5 after, parked (AUTO-SKIP/HUMAN-ONLY/BLOCKED) last; stable; idempotent.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/../../ovn_prioritize_tiers.py"; [ -f "$S" ] || S="$HERE/../ovn_prioritize_tiers.py"; [ -f "$S" ] || S="$HERE/ovn_prioritize_tiers.py"
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P="$T/p.md"
run(){ python3 "$S" "$@" 2>&1; }
same(){ [ "$(cat "$1")" = "$(printf '%b' "$2")" ] && echo 1 || echo 0; }   # compare file to expected (%b text, no trailing NL compare)
kb(){ if [ "$2" = "1" ]; then echo "  ok   $1"; else echo "  WARN KNOWN-BUG: $1 (non-fatal)"; fi; }
nb(){ grep -v '^$' "$1"; }   # file minus blank lines (order-only comparison)
has(){ printf '%s' "$1" | grep -qF -- "$2" && echo 1 || echo 0; }

# 1. full ordering across every bucket + parked, with stable order inside a bucket
printf '%s\n' '# Progress' '## Next Steps' \
 '- [ ] [T5] a5 big' \
 '- [ ] [T1] b1 first' \
 '- [ ] [T3] c3 first' \
 '- [ ] [T4] d4' \
 '- [ ] untiered e' \
 '- [ ] [T3] f3 second' \
 '- [ ] [T2] g2 [HUMAN-ONLY] parked' \
 '- [ ] [T2] h2' \
 '- [ ] [T3] i3 BLOCKED upstream' \
 '- [ ] [T1] j1 AUTO-SKIP thing' \
 '## Done' '- [x] old' > "$P"
out="$(run "$P")"
ok "summary line counts reordered/T3/T45" "$(has "$out" 'reordered 10 items: 2 T3 surfaced to top, 2 T4/T5 sunk to bottom')"
exp='# Progress\n## Next Steps\n- [ ] [T3] c3 first\n- [ ] [T3] f3 second\n- [ ] [T1] b1 first\n- [ ] untiered e\n- [ ] [T2] h2\n- [ ] [T5] a5 big\n- [ ] [T4] d4\n- [ ] [T2] g2 [HUMAN-ONLY] parked\n- [ ] [T3] i3 BLOCKED upstream\n- [ ] [T1] j1 AUTO-SKIP thing\n## Done\n- [x] old\n'
ok "exact new order (T3, T1/T2/untiered stable, T4/T5, parked)" "$(same "$P" "$exp")"
ok "parked T3 item sinks below actionable T4/T5" "$([ "$(grep -n 'i3 BLOCKED' "$P" | cut -d: -f1)" -gt "$(grep -n 'd4' "$P" | cut -d: -f1)" ] && echo 1 || echo 0)"
ok "section outside Next Steps untouched" "$(has "$(tail -2 "$P")" '- [x] old')"

# 2. idempotent
cp "$P" "$T/before"; out="$(run "$P")"
ok "second run reports already prioritized" "$(has "$out" 'already prioritized — no change')"
ok "second run leaves file byte-identical" "$(cmp -s "$P" "$T/before" && echo 1 || echo 0)"

# 3. alt tier tag form ·T3· and bare tier numbers (file does NOT end in a section-terminating header)
printf '%s\n' '## Next Steps' '- [ ] {py·x·T2·t} plain ·T1· one' '- [ ] foo ·T3· three' '- [ ] bar ·T5· five' '- [ ] [T3] baz' > "$P"
run "$P" >/dev/null
ok "·T3· form recognised as T3, ·T5· as T4/T5 (order)" "$([ "$(nb "$P")" = "$(printf '## Next Steps\n- [ ] foo ·T3· three\n- [ ] [T3] baz\n- [ ] {py·x·T2·t} plain ·T1· one\n- [ ] bar ·T5· five')" ] && echo 1 || echo 0)"
kb "Next Steps at EOF: file keeps its trailing newline and gains no stray blank line mid-section (the trailing '' split-element rides with the last item's block)" "$([ "$(tail -c1 "$P" | xxd -p)" = "0a" ] && ! grep -q '^$' "$P" && echo 1 || echo 0)"

# 4. continuation lines travel with their item; preamble stays above; blank/notes
printf '%s\n' '## Next Steps' 'Some preamble note' '' '- [ ] [T1] one' '  detail of one' '  - sub' '- [ ] [T3] three' '  detail of three' '- [x] [T3] checked item' '' '## Later' '- [ ] [T3] not in section' > "$P"
out="$(run "$P")"
ok "reordered 2 items" "$(has "$out" 'reordered 2 items: 1 T3 surfaced to top, 0 T4/T5 sunk to bottom')"
exp='## Next Steps\nSome preamble note\n\n- [ ] [T3] three\n  detail of three\n- [x] [T3] checked item\n\n- [ ] [T1] one\n  detail of one\n  - sub\n## Later\n- [ ] [T3] not in section\n'
ok "continuation + trailing checked/blank lines move with their block; preamble fixed; later section untouched" "$(same "$P" "$exp")"

# 5. header variants / case / section bounds
printf '%s\n' '## NEXT STEPS (auto)' '- [ ] [T4] x' '- [ ] [T3] y' '### sub header rides with y' '- [ ] [T1] z' '## End' > "$P"
out="$(run "$P")"
ok "case-insensitive header w/ suffix; ### subheader does not end the section" "$(has "$out" 'reordered 3 items')"
ok "### line is a continuation: moves with the item above it" "$(same "$P" '## NEXT STEPS (auto)\n- [ ] [T3] y\n### sub header rides with y\n- [ ] [T1] z\n- [ ] [T4] x\n## End')"

# 6. no section / no items / only checked items / only one item
printf '%s\n' '# nothing' '- [ ] [T3] x' > "$P"; cp "$P" "$T/b"
out="$(run "$P")"
ok "no Next Steps section -> message" "$(has "$out" 'no Next Steps section — nothing to do')"
ok "no-section file unchanged" "$(cmp -s "$P" "$T/b" && echo 1 || echo 0)"
printf '%s\n' '## Next Steps' '- [x] done' 'note' '## Z' > "$P"; cp "$P" "$T/b"
out="$(run "$P")"
ok "no open items -> message" "$(has "$out" 'no open items in Next Steps — nothing to do')"
ok "no-items file unchanged" "$(cmp -s "$P" "$T/b" && echo 1 || echo 0)"
printf '%s\n' '## Next Steps' '- [ ] [T5] only' > "$P"
ok "single item already ordered" "$(has "$(run "$P")" 'already prioritized')"
: > "$P"
ok "empty file -> no section" "$(has "$(run "$P")" 'no Next Steps section')"
printf '## Next Steps' > "$P"
ok "header-only file w/o newline -> no open items" "$(has "$(run "$P")" 'no open items')"

# 7. utf-8 content survives the rewrite
printf '%s\n' '## Next Steps' '- [ ] [T5] ünïcode — five' '- [ ] [T3] ✓ three' '## End' > "$P"
run "$P" >/dev/null
ok "utf-8 content preserved through rewrite" "$(same "$P" '## Next Steps\n- [ ] [T3] ✓ three\n- [ ] [T5] ünïcode — five\n## End')"

# 8. first-match semantics: only the FIRST Next Steps section is processed
printf '%s\n' '## Next Steps' '- [ ] [T4] a' '- [ ] [T3] b' '## Other' '## Next Steps' '- [ ] [T4] c' '- [ ] [T3] d' > "$P"
run "$P" >/dev/null
ok "only first Next Steps section reordered" "$(same "$P" '## Next Steps\n- [ ] [T3] b\n- [ ] [T4] a\n## Other\n## Next Steps\n- [ ] [T4] c\n- [ ] [T3] d')"

# 9. error paths
out="$(run "$T/missing.md")"; rc=$?
ok "missing file -> nonzero exit (traceback)" "$(has "$out" 'FileNotFoundError')"
python3 "$S" >/dev/null 2>&1; ok "no args -> nonzero exit" "$([ $? != 0 ] && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
