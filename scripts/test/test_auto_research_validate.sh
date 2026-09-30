#!/usr/bin/env bash
# Regression test for ovn_auto_research_validate.py: the gate between an LLM research pass's
# proposed roadmap lines and the fleet planner. Bad/duplicate/ungrounded lines must be dropped,
# status forced to [ready], an empty proposal is valid, and the cap holds.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
V="$HERE/../../ovn_auto_research_validate.py"; [ -f "$V" ] || V="$HERE/../ovn_auto_research_validate.py"; [ -f "$V" ] || V="$HERE/ovn_auto_research_validate.py"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
M='{cat: backend; size: S; multifile: no; research: none}'
cat > "$T/roadmap.md" <<EOR
- [ ] [P2] [decomposed] Existing feature alpha — already built in app/alpha.py $M
- [x] [P3] [done] Done thing — see app/done.py $M
EOR
cat > "$T/p.md" <<EOR
- [ ] [P1] [needs-decompose] Fix beta crash — app/beta.py line 10 subscripts a User object $M
- [ ] [P2] [ready] Existing Feature Alpha — app/alpha.py again $M
- [ ] [P2] [ready] Done thing — app/done.py $M
- [ ] [P2] [ready] Ungrounded idea — make it better somehow $M
- [ ] [P2] [ready] Fix beta crash — app/beta.py duplicate within batch $M
- [ ] [P9] [ready] Bad priority — app/x.py $M
- [ ] [P3] [ready] Good gamma — web/src/gamma.ts has an unused export $M
- [ ] [P1] [ready] A very long descriptive title that real research agents produce, naming the bug and the trigger and the symptom in one breath so it runs well past the old one hundred twenty character limit — app/long.py has the defect $M
not a feature line
EOR
out="$(python3 "$V" "$T/p.md" "$T/roadmap.md" 12 2>"$T/err")"
ok "accepts the 3 valid lines (incl. a >120-char title)" "$([ "$(printf '%s\n' "$out" | grep -c '^- \[ \]')" = 3 ] && echo 1 || echo 0)"
ok "forces status to [ready]" "$(printf '%s' "$out" | grep -q 'Fix beta crash' && printf '%s' "$out" | grep 'Fix beta crash' | grep -q '\[ready\]' && echo 1 || echo 0)"
ok "drops duplicate of existing (case-insensitive)" "$(grep -q 'duplicate title: Existing Feature Alpha' "$T/err" && echo 1 || echo 0)"
ok "drops duplicate of a done item" "$(grep -q 'duplicate title: Done thing' "$T/err" && echo 1 || echo 0)"
ok "drops ungrounded (no file path)" "$(grep -q 'cites no file path: Ungrounded' "$T/err" && echo 1 || echo 0)"
ok "drops in-batch duplicate" "$(grep -q 'duplicate title: Fix beta crash' "$T/err" && echo 1 || echo 0)"
ok "drops bad priority P9" "$(grep -q 'bad format: - \[ \] \[P9\]' "$T/err" && echo 1 || echo 0)"
: > "$T/empty.md"
out2="$(python3 "$V" "$T/empty.md" "$T/roadmap.md" 12 2>"$T/err2")"; rc=$?
ok "empty proposal is valid (rc 0, no output)" "$([ $rc = 0 ] && [ -z "$out2" ] && echo 1 || echo 0)"
for i in 1 2 3 4 5; do echo "- [ ] [P2] [ready] Item number $i — app/m$i.py $M"; done > "$T/many.md"
out3="$(python3 "$V" "$T/many.md" "$T/roadmap.md" 3 2>/dev/null)"
ok "cap of 3 holds" "$([ "$(printf '%s\n' "$out3" | grep -c '^- \[ \]')" = 3 ] && echo 1 || echo 0)"
ok "output matches the planner's pickup regex" "$(printf '%s\n' "$out" | grep -qE '^- \[ \] \[P[1-4]\] \[ready\]' && echo 1 || echo 0)"
echo "  $pass passed, $fail failed"; [ "$fail" = 0 ]
