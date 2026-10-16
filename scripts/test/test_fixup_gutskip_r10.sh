#!/usr/bin/env bash
# 2026-10-10 (package qagate, analysis[6] BX-04): lib_fixup.sh
#   * ovn_fixup_gut_unrunnable: a GDScript test file the cycle ADDED/MODIFIED that GUT would silently ignore (emptied, no extends GutTest) is reported;
#   * ovn_fixup_integrity_gate (c2): that finding is logged '[fixup-gut-skip]' + alerted in SHADOW (default, tree kept, says what enforce WOULD reset),
#     resets only with OVN_FIXUP_GUTSKIP=enforce, silent with =off;
#   * (c) fixup-tests-lost stays shadow but now logs 'WOULD RESET' (and does not in enforce).
# Fix-ups are simulated by stub commits in temp repos (no model, no network).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(__d="$(mktemp -d)" && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "$tmp"' EXIT
export OVN_VERIFY_SHADOW_LOG="$tmp/shadow.log"
ALERTS="$tmp/alerts.log"; : > "$ALERTS"
emit_alert(){ printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$ALERTS"; }
# shellcheck disable=SC1090
source "$S/lib_item_select.sh"; source "$S/lib_path_normalize.sh"; source "$S/lib_verify_clause.sh"; source "$S/lib_fixup.sh"
unset OVN_FIXUP_REVERIFY OVN_FIXUP_UNDO_GUARD OVN_TESTONLY_GUARD OVN_RI_NEW OVN_FIXUP_GUTSKIP

GOOD=$'extends GutTest\n\nfunc test_a():\n\tassert_eq(1, 1)\n'
BEFORE=""; MAIN=""; R=""; TL=""
mkrepo(){  # $1=name
  R="$tmp/$1"; rm -rf "$R"; mkdir -p "$R/app" "$R/tests/helpers" "$R/addons/gut"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  printf 'def old_name():\n    return 1\n' > app/foo.py
  printf '%s' "$GOOD" > tests/test_a.gd
  printf '%s' "$GOOD" > tests/test_b.gd
  printf 'extends RefCounted\n\nfunc build():\n\tpass\n' > tests/helpers/builder.gd
  printf 'extends Node\n\nfunc test_vendored():\n\tpass\n' > addons/gut/vendored_test.gd
  printf '## Next Steps\n%s\n' "- [ ] [T2] app/foo.py — Rename \`old_name\` to \`new_name\`. VERIFY: \`grep -q new_name app/foo.py\`" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m before; BEFORE="$(git rev-parse HEAD)"
  TL="$tmp/$1.log"; : > "$TL"
}
maincommit(){ printf 'def new_name():\n    return 1\n' > app/foo.py; git add -A; git commit -q -m main; MAIN="$(git rev-parse HEAD)"; }
fixup(){ git add -A; git commit -q -m fixup; }
head_(){ git rev-parse HEAD; }
unrun(){ ovn_fixup_gut_unrunnable "$BEFORE"; }

# ---------------------------------------------------------------- ovn_fixup_gut_unrunnable
mkrepo u1; printf '\n\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "NEGATIVE: a test file emptied to 2 bytes is reported (df1de23 shape)" "unrun | grep -q 'tests/test_a.gd (no test function left'"
mkrepo u2; printf '# The Scatter class was removed.\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "NEGATIVE: comment-only test file is reported (091a8df shape)" "unrun | grep -q 'tests/test_a.gd'"
mkrepo u3; printf '# Placeholder - the implement step fills this in.\n' > tests/test_new.gd; git add -A; git commit -q -m m
ok "NEGATIVE: a NEW test_*.gd that is only a placeholder comment is reported (harness stub shape)" "unrun | grep -q 'tests/test_new.gd'"
mkrepo u4; printf 'func test_a():\n\tassert_eq(1, 1)\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "NEGATIVE: func test_ but no extends at all is reported" "unrun | grep -q 'tests/test_a.gd (no extends GutTest'"
mkrepo u5; printf 'extends Node\n\nfunc test_a():\n\tassert_eq(1, 1)\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "NEGATIVE: extends Node (not GutTest) is reported" "unrun | grep -q 'extends Node, not GutTest'"
mkrepo u6; printf 'extends GUTTest\n\nfunc test_a():\n\tassert_eq(1, 1)\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "NEGATIVE: the 'extends GUTTest' typo is reported" "unrun | grep -q 'extends GUTTest, not GutTest'"
mkrepo u7; printf 'extends GutTest  # base\n\nfunc test_a():\n\tassert_eq(2, 2)\n\nfunc test_c():\n\tassert_eq(3, 3)\n' > tests/test_a.gd; printf 'extends "res://addons/gut/test.gd"\n\nfunc test_b():\n\tassert_eq(1, 1)\n' > tests/test_b.gd; git add -A; git commit -q -m m
ok "BENIGN: valid GutTest files (with a trailing comment, and the res:// base path) are not reported" "[ -z \"\$(unrun)\" ]"
mkrepo u8; printf 'extends "res://tests/base_case.gd"\n\nfunc test_a():\n\tassert_eq(2, 2)\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "BENIGN: a custom base class (cannot be resolved in shell) is not judged" "[ -z \"\$(unrun)\" ]"
mkrepo u9; printf 'extends RefCounted\n\nfunc build2():\n\tpass\n' > tests/helpers/builder.gd; git add -A; git commit -q -m m
ok "BENIGN: editing a non-test helper under tests/ is not reported" "[ -z \"\$(unrun)\" ]"
mkrepo u10; git rm -q tests/test_a.gd; git commit -q -m m
ok "BENIGN: a deleted test file is not 'unrunnable' (diff-filter AM)" "[ -z \"\$(unrun)\" ]"
mkrepo u11; printf 'extends Node\n\nfunc test_vendored():\n\tpass\n# edit\n' > addons/gut/vendored_test.gd; git add -A; git commit -q -m m
ok "BENIGN: vendored addons/ are never judged" "[ -z \"\$(unrun)\" ]"
mkrepo u12; printf '\n' > tests/test_a.gd; git add -A; git commit -q -m pre; PRE="$(head_)"; printf 'x\n' > app/other.txt; git add -A; git commit -q -m later
ok "BENIGN: a file already empty BEFORE this cycle's BEFORE_SHA (emptied in an earlier cycle) and untouched since is not reported" "[ -z \"\$(ovn_fixup_gut_unrunnable '$PRE')\" ]"
ok "... while the same file IS reported from the earlier BEFORE_SHA (the cycle that emptied it)" "ovn_fixup_gut_unrunnable '$BEFORE' | grep -q 'tests/test_a.gd'"
# reviewer r2 minor 2: only files that were GUT-valid BEFORE the cycle (or are new) are this cycle's doing
mkrepo u14; printf 'extends GutTest\n\nfunc helper_only():\n\tpass\n' > tests/test_helpers.gd; git add -A; git commit -q -m pre; BEFORE="$(head_)"; printf 'extends GutTest\n\nfunc helper_only():\n\tpass\n\nfunc helper_two():\n\tpass\n' > tests/test_helpers.gd; git add -A; git commit -q -m m
ok "BENIGN (r2): an existing test_helpers.gd (extends GutTest, never had a func test_) that the cycle merely edited is NOT reported" "[ -z \"\$(unrun)\" ]"
mkrepo u15; printf '# emptied earlier\n' > tests/test_a.gd; git add -A; git commit -q -m pre; BEFORE="$(head_)"; printf '# emptied earlier, comment edited\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "BENIGN (r2): a file already ignored by GUT at BEFORE_SHA and merely re-touched by the cycle is NOT reported" "[ -z \"\$(unrun)\" ]"
mkrepo u16; printf 'extends GutTest\n\nfunc helper_only():\n\tpass\n' > tests/test_new_helpers.gd; git add -A; git commit -q -m m
ok "NEGATIVE (r2): a NEW extends-GutTest file with no test function is still reported, with accurate wording (nothing runs, not 'GUT ignores it')" "unrun | grep -q 'tests/test_new_helpers.gd (extends GutTest but no test function left: nothing runs)'"
mkrepo u17; printf '# emptied\n' > tests/test_a.gd; git add -A; git commit -q -m m
ok "NEGATIVE (r2): a file that WAS valid at BEFORE_SHA and is emptied by the cycle is still reported" "unrun | grep -q 'tests/test_a.gd (no test function left: GUT ignores it)'"
mkrepo u13; ok "BENIGN: no change at all -> empty" "[ -z \"\$(unrun)\" ]"
ok "fail-safe: an unresolvable before-sha gives empty output and rc 0" "[ -z \"\$(ovn_fixup_gut_unrunnable deadbeef)\" ]"
ok "fail-safe: an empty argument gives empty output and rc 0" "ovn_fixup_gut_unrunnable ''"

# ---------------------------------------------------------------- the gate (c2): shadow default / enforce / off
mkrepo g1; maincommit; printf '\n' > tests/test_a.gd; fixup; H="$(head_)"
: > "$ALERTS"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemG; RC=$?
ok "(c2) SHADOW (default): rc 0, tree untouched" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && [ -z \"\$OVN_FXI_STATUS\" ]"
ok "(c2) SHADOW: '[fixup-gut-skip] (tier2, mode=shadow)' names the file in the task log" "grep -q '\\[fixup-gut-skip\\] (tier2, mode=shadow).*tests/test_a.gd' '$TL'"
ok "(c2) SHADOW: says what enforce WOULD reset" "grep -q 'fixup-gut-skip\\] shadow: WOULD RESET to ${BEFORE:0:12}' '$TL'"
ok "(c2) SHADOW: exactly one info alert" "[ \"\$(grep -c '^info|itemG|\\[fixup-gut-skip\\]' '$ALERTS')\" = 1 ]"

mkrepo g2; maincommit; printf '\n' > tests/test_a.gd; fixup
OVN_FIXUP_GUTSKIP=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemG; RC=$?
ok "(c2) ENFORCE: rc 1, tree reset to BEFORE_SHA, status no-op(fixup-undid-item)" "[ $RC = 1 ] && [ \"\$(head_)\" = '$BEFORE' ] && [ \"\$OVN_FXI_STATUS\" = 'no-op(fixup-undid-item)' ]"
ok "(c2) ENFORCE: lastfail text tells the model what to do" "case \"\$OVN_FXI_TEXT\" in *'extends GutTest'*'tests/test_a.gd'*|*'tests/test_a.gd'*'extends GutTest'*) true;; *) false;; esac"
ok "(c2) ENFORCE: the task log carries the '--- fixup-integrity: ...' marker" "grep -q '^--- fixup-integrity: the cycle left GDScript test file' '$TL'"

mkrepo g3; maincommit; printf '\n' > tests/test_a.gd; fixup; H="$(head_)"
OVN_FIXUP_GUTSKIP=off ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemG; RC=$?
ok "(c2) OFF: rc 0, nothing logged" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && ! grep -q 'fixup-gut-skip' '$TL'"

mkrepo g4; maincommit; printf 'extends GutTest\n\nfunc test_a():\n\tassert_eq(2, 2)\n' > tests/test_a.gd; fixup; H="$(head_)"
OVN_FIXUP_GUTSKIP=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemG; RC=$?
ok "(c2) BENIGN control: a fix-up that keeps valid GUT tests => rc 0 even in enforce, nothing logged" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && ! grep -q 'fixup-gut-skip' '$TL'"

# ---------------------------------------------------------------- (c) tests-lost: shadow logs WOULD RESET, enforce does not
mkrepo t1; maincommit; printf 'func test_hello2():\n\tassert_eq(1, 1)\n' >> tests/test_a.gd; git add -A; git commit -q -m main2; MAIN="$(head_)"
printf '%s' "$GOOD" > tests/test_a.gd; fixup; H="$(head_)"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemT; RC=$?
ok "(c) shadow: lost test logged as before, tree kept" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && grep -q 'fixup-tests-lost\\] (tier2, mode=shadow).*test_hello2' '$TL'"
ok "(c) shadow: NEW 'WOULD RESET to <sha>' line" "grep -q 'fixup-tests-lost\\] shadow: WOULD RESET to ${BEFORE:0:12}' '$TL'"
ok "(c) shadow: the WOULD RESET line does not repeat the test name (existing per-test counts stay 1)" "[ \"\$(grep -c 'fixup-tests-lost.*test_hello2' '$TL')\" = 1 ]"
mkrepo t2; maincommit; printf 'func test_hello2():\n\tassert_eq(1, 1)\n' >> tests/test_a.gd; git add -A; git commit -q -m main2; MAIN="$(head_)"
printf '%s' "$GOOD" > tests/test_a.gd; fixup
OVN_FIXUP_REVERIFY=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemT; RC=$?
ok "(c) enforce: still resets (unchanged) and does NOT print WOULD RESET" "[ $RC = 1 ] && [ \"\$(head_)\" = '$BEFORE' ] && ! grep -q 'WOULD RESET' '$TL'"

echo "fixup gut-skip r10: $P passed, $F failed"; [ "$F" = 0 ]
