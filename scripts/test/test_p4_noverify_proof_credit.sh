#!/usr/bin/env bash
# 2026-11-02 (P4 / outcomes F10): ROOT CAUSE of xlite's landed-uncredited rows (15 in 26h) and the ~50 ALREADY-DONE no-ops/day.
#   An item with NO runnable VERIFY (xlite: 103 with none + 383 whose "VERIFY:" is prose / a GDScript expression such as `assert_eq(UpkeepCost.squad_upkeep(3, -10), 0)`, ~29% of the roster; the
#   bare-verify fallback correctly refuses them) is REFUSED by ovn_auto_credit RULE 4 ('item has no VERIFY: clause') => the green push is class landed-uncredited and the item stays open;
#   the NEXT cycle's scout ALREADY-DONE credit (ovn_credit_verify_gate lets NO_VERIFY_CLAUSE through) ticks it after one wasted no-op cycle.
#   Fix (evidence-based, OVN_AC_NOVERIFY_PROOF=shadow|on|off, default SHADOW): credit when the item NAMES an identifier and this commit's diff on the item's own file ADDS its definition.
# Replay fixture: the xlite item shapes (`static func deficit`, `amount_payable`) and the prose-VERIFY form. Mutation: with the proof helper broken the `on` checks go red.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_aider2_fixture.sh"
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_VERIFY_SHADOW_LOG="$W/shadow.log"
[ -f "$Q/scripts/lib_auto_credit.sh" ] && . "$Q/scripts/lib_auto_credit.sh"
declare -F ovn_auto_credit >/dev/null || { echo "  FAIL: ovn_auto_credit missing"; exit 1; }

mk(){ # $1 name ; $2 progress item line ; creates scripts/roster/upkeep_cost.gd with an existing func
  R1="$W/p4/$1"; rm -rf "${R1:?}"; mkdir -p "$R1/scripts/roster"; cd "$R1" || exit 1
  git init -q -b main . && git config user.email t@t && git config user.name t
  printf 'class_name UpkeepCost\n\nstatic func squad_upkeep(n: int, per_unit: int) -> int:\n\treturn n * per_unit\n' > scripts/roster/upkeep_cost.gd
  printf '## Next Steps\n%s\n\n## Completed\n' "$2" > OVERNIGHT_PROGRESS.md
  git add -A && git commit -q -m base; B1="$(git rev-parse HEAD)"
}
commit1(){ git add -A && git commit -q -m "$1"; A1="$(git rev-parse HEAD)"; }
call(){ : > "$R1/task.log"; env "$@" bash -c '. "'"$Q"'/scripts/lib_auto_credit.sh" 2>/dev/null; cd "'"$R1"'"; ovn_auto_credit "'"$B1"'" "'"$A1"'" OVERNIGHT_PROGRESS.md "'"$R1"'/task.log"' >/dev/null 2>&1; CLOG="$(cat "$R1/task.log")"; }
ticked(){ grep -q '^- \[x\] \[T1\]' "$R1/OVERNIGHT_PROGRESS.md"; }
ITEM_PROSE='- [ ] [T1] scripts/roster/upkeep_cost.gd — Add `static func deficit(funds: int, upkeep: int) -> int` returning maxi(0, upkeep - funds). VERIFY: assert_eq(UpkeepCost.deficit(3, 10), 7). (cat:godot)'
ITEM_NONE='- [ ] [T1] scripts/roster/upkeep_cost.gd — Add `static func deficit(funds: int, upkeep: int) -> int`. (cat:godot)'
ITEM_OTHER='- [ ] [T1] scripts/roster/upkeep_cost.gd — Add `static func amount_payable(funds: int, upkeep: int) -> int`. (cat:godot)'
add_deficit(){ printf '\nstatic func deficit(funds: int, upkeep: int) -> int:\n\treturn maxi(0, upkeep - funds)\n' >> scripts/roster/upkeep_cost.gd; commit1 "feat: deficit"; }

mk shadow "$ITEM_PROSE"; add_deficit; call OVN_AC_NOVERIFY_PROOF=shadow
ok "N1 shadow (default): the prose-VERIFY item is still refused (stays open)" '! ticked'
ok "N1 shadow logs the would-credit with the identifier" 'printf "%s" "$CLOG" | grep -q "NO-VERIFY PROOF SHADOW line 2.*definition of .deficit."'
ok "N1 shadow still logs the REFUSED marker (class stays landed-uncredited today)" 'printf "%s" "$CLOG" | grep -q "REFUSED line 2.*no VERIFY"'
mk on1 "$ITEM_PROSE"; add_deficit; call OVN_AC_NOVERIFY_PROOF=on
ok "N2 on: the prose-VERIFY item whose named func was added is credited" 'ticked'
ok "N2 on: the log names the proof and there is no REFUSED line" 'printf "%s" "$CLOG" | grep -q "NO-VERIFY PROOF line 2" && ! printf "%s" "$CLOG" | grep -q "REFUSED line 2"'
ok "N2 on: the tick commit stages only the progress file" '[ "$(git show --name-only --format= HEAD | tr "\n" " ")" = "OVERNIGHT_PROGRESS.md " ]'
mk on2 "$ITEM_NONE"; add_deficit; call OVN_AC_NOVERIFY_PROOF=on
ok "N3 on: an item with no VERIFY at all is credited the same way" 'ticked'
mk off1 "$ITEM_PROSE"; add_deficit; call OVN_AC_NOVERIFY_PROOF=off
ok "N4 off: old behaviour (refused, no proof line)" '! ticked && ! printf "%s" "$CLOG" | grep -q "NO-VERIFY PROOF"'
# negatives: the commit does not add what the item names
mk neg1 "$ITEM_OTHER"; add_deficit; call OVN_AC_NOVERIFY_PROOF=on
ok "N5 on: a commit that adds a DIFFERENT func does not credit the item" '! ticked'
mk neg2 "$ITEM_PROSE"; printf '\n# deficit helper TODO\n' >> scripts/roster/upkeep_cost.gd; commit1 "chore: comment"; call OVN_AC_NOVERIFY_PROOF=on
ok "N6 on: a comment that merely mentions the name does not credit it" '! ticked'
mk neg3 "$ITEM_PROSE"; printf 'class_name UpkeepCost\n\nstatic func deficit(funds: int, upkeep: int) -> int:\n\treturn 0\n\nstatic func squad_upkeep(n: int, per_unit: int) -> int:\n\treturn n * per_unit\n' > scripts/roster/upkeep_cost.gd; git add -A; git commit -q -m x; B1="$(git rev-parse HEAD)"
printf 'class_name UpkeepCost\n\nstatic func deficit(funds: int, upkeep: int) -> int:\n\treturn maxi(0, upkeep - funds)\n\nstatic func squad_upkeep(n: int, per_unit: int) -> int:\n\treturn n * per_unit\n' > scripts/roster/upkeep_cost.gd; commit1 "fix: body"; call OVN_AC_NOVERIFY_PROOF=on
ok "N7 on: editing the body of an ALREADY-defined func (definition on a removed line too) is no proof" '! ticked'
mk neg4 '- [ ] [T1] scripts/roster/other.gd — Add `static func deficit(a: int) -> int`. VERIFY: assert_eq(1, 1). (cat:godot)'; add_deficit; call OVN_AC_NOVERIFY_PROOF=on
ok "N8 on: the commit touched a different file than the item names (path rule still first)" '! ticked'
# a real VERIFY keeps deciding: a failing runnable VERIFY is still a refusal even when the func was added
mk fail1 '- [ ] [T1] scripts/roster/upkeep_cost.gd — Add `static func deficit(a: int) -> int`. VERIFY: `grep -q "maxi(1," scripts/roster/upkeep_cost.gd`. (cat:godot)'; add_deficit; call OVN_AC_NOVERIFY_PROOF=on
ok "N9 on: a runnable VERIFY that FAILS still refuses (the proof only replaces a MISSING verify)" '! ticked && printf "%s" "$CLOG" | grep -q "VERIFY: clause FAILED"'
# mutation: a broken proof helper must flip N2
MUT="$W/lib_auto_credit_mut.sh"; sed 's/^_ovn_ac_noverify_proof() {/_ovn_ac_noverify_proof() { return 1/' "$Q/scripts/lib_auto_credit.sh" > "$MUT"
ok "N10 mutant differs" '! cmp -s "$Q/scripts/lib_auto_credit.sh" "$MUT"'
mk mut1 "$ITEM_PROSE"; add_deficit; : > "$R1/task.log"
env OVN_AC_NOVERIFY_PROOF=on bash -c '. "'"$MUT"'" 2>/dev/null; cd "'"$R1"'"; ovn_auto_credit "'"$B1"'" "'"$A1"'" OVERNIGHT_PROGRESS.md "'"$R1"'/task.log"' >/dev/null 2>&1
ok "N10 MUTANT (proof disabled): N2 goes red - the item is NOT credited" '! ticked'
# FX-P4: the definition proof must be a real definition, not a dict key / kwarg / local assignment line
mk weak1 "$ITEM_PROSE"; printf '\nvar _cfg = {\n\t"a": 1,\n  deficit: 5,\n}\n' >> scripts/roster/upkeep_cost.gd; commit1 "chore: dict key"; call OVN_AC_NOVERIFY_PROOF=on
ok "N11 on: an indented 'deficit: value' dict-key line is no proof" '! ticked'
mk weak2 "$ITEM_PROSE"; printf '\nstatic func other() -> int:\n\treturn foo(deficit = 3)\n' >> scripts/roster/upkeep_cost.gd; commit1 "chore: local assign"; call OVN_AC_NOVERIFY_PROOF=on
ok "N12 on: an indented local assignment / kwarg 'deficit = 3' is no proof" '! ticked'
mk weak3 '- [ ] [T1] scripts/roster/upkeep_cost.gd — Add `deficit` constant. VERIFY: assert_eq(1, 1). (cat:godot)'; printf 'deficit = 7\n' >> scripts/roster/upkeep_cost.gd; commit1 "feat: module-level assign"; call OVN_AC_NOVERIFY_PROOF=on
ok "N13 on: an unindented statement-level assignment IS a definition proof" 'ticked'
mk weak4 '- [ ] [T1] scripts/roster/upkeep_cost.gd — Add `deficit` const. VERIFY: assert_eq(1, 1). (cat:godot)'; printf '\nconst deficit = 7\n' >> scripts/roster/upkeep_cost.gd; commit1 "feat: const"; call OVN_AC_NOVERIFY_PROOF=on
ok "N14 on: 'const NAME' is still a definition proof" 'ticked'
# mutant: the old weak regex credits the dict-key case
MUT2="$W/lib_auto_credit_mut2.sh"; python3 - "$Q/scripts/lib_auto_credit.sh" "$MUT2" "$Q/scripts" <<'PYM'
import sys
s=open(sys.argv[1]).read()
new='^\\+${n}([[:space:]]*:[[:space:]]*[A-Za-z_][^=]*)?[[:space:]]*=[^=]'
assert new in s
s=s.replace(new,'^\\+[[:space:]]*${n}[[:space:]]*(=|:)[^=]')
a='_AC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"'
assert a in s
open(sys.argv[2],'w').write(s.replace(a,'_AC_DIR="'+sys.argv[3]+'"'))
PYM
ok "N15 mutant2 differs" '! cmp -s "$Q/scripts/lib_auto_credit.sh" "$MUT2"'
mk mut2 "$ITEM_PROSE"; printf '\nvar _cfg = {\n  deficit: 5,\n}\n' >> scripts/roster/upkeep_cost.gd; commit1 "chore: dict key"; : > "$R1/task.log"
env OVN_AC_NOVERIFY_PROOF=on bash -c '. "'"$MUT2"'" 2>/dev/null; cd "'"$R1"'"; ovn_auto_credit "'"$B1"'" "'"$A1"'" OVERNIGHT_PROGRESS.md "'"$R1"'/task.log"' >/dev/null 2>&1
ok "N15 MUTANT (old weak regex): the dict-key line wrongly credits the item" 'ticked'
echo "  $P passed, $F failed"; [ "$F" = 0 ]
