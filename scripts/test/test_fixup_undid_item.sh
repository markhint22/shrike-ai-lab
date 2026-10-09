#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 5): the Tier-2 / BUILD-GATE fix-up must not UNDO the item it is fixing.
# Live: xlite remove/restore ping-pong (12 + 9 landed cycles, 21 pairs), iptv fix-ups that deleted the model's own tests, a test item that rewrote
# app/core/rate_limiting.py and reached prod. Covers lib_fixup.sh ovn_fixup_integrity_gate (a: net-zero, ENFORCED; b: VERIFY re-run and c: test-name
# retention, SHADOW unless OVN_FIXUP_REVERIFY=enforce), ovn_testonly_guard (d, SHADOW unless OVN_TESTONLY_GUARD=enforce), the ovn_item_guard.sh fail-cap billing and
# the run_overnight.sh wiring. Fix-ups are simulated by stub commits in temp repos (no model, no network). Mutation controls at the end.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; RUN="$S/../run_overnight.sh"; GUARD="$S/ovn_item_guard.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export OVN_VERIFY_SHADOW_LOG="$tmp/shadow.log"
ALERTS="$tmp/alerts.log"; : > "$ALERTS"
emit_alert(){ printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$ALERTS"; }
# shellcheck disable=SC1090
source "$S/lib_item_select.sh"; source "$S/lib_path_normalize.sh"; source "$S/lib_verify_clause.sh"; source "$S/lib_fixup.sh"
unset OVN_FIXUP_REVERIFY OVN_FIXUP_UNDO_GUARD OVN_TESTONLY_GUARD OVN_RI_NEW

BEFORE=""; MAIN=""; R=""; TL=""
mkrepo(){  # $1=name  [$2=item line]
  R="$tmp/$1"; rm -rf "$R"; mkdir -p "$R/app" "$R/tests"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  printf 'def old_name():\n    return 1\n' > app/foo.py
  printf 'from app.foo import old_name\n\ndef test_old():\n    assert old_name() == 1\n' > tests/test_foo.py
  printf '## Next Steps\n%s\n' "${2:-"- [ ] [T2] app/foo.py — Rename \`old_name\` to \`new_name\`. VERIFY: \`grep -q new_name app/foo.py\`"}" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m before; BEFORE="$(git rev-parse HEAD)"
  TL="$tmp/$1.log"; : > "$TL"
}
maincommit(){  # the model's commit: rename + a brand-new test
  printf 'def new_name():\n    return 1\n' > app/foo.py
  printf 'from app.foo import new_name\n\ndef test_new_feature():\n    assert new_name() == 1\n' > tests/test_new.py
  git add -A; git commit -q -m main; MAIN="$(git rev-parse HEAD)"
}
fixup(){ git add -A; git commit -q -m fixup; }
head_(){ git rev-parse HEAD; }

# ---- (a) net-zero: ENFORCED by default ----
mkrepo a1; maincommit
git checkout -q "$BEFORE" -- app/foo.py; fixup           # the "fix-up" restores old behaviour => no net change on app/foo.py
OVN_RI_NEW='tests/test_foo.py::test_old'
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemA; RC=$?
ok "(a) net-zero fix-up: gate returns 1" "[ $RC = 1 ]"
ok "(a) tree is hard-reset to BEFORE_SHA" "[ \"\$(head_)\" = '$BEFORE' ]"
ok "(a) status is no-op(fixup-undid-item)" "[ \"\$OVN_FXI_STATUS\" = 'no-op(fixup-undid-item)' ]"
ok "(a) the new test file the main commit added is gone too (clean reset, nothing stranded)" "[ ! -e tests/test_new.py ] && [ -z \"\$(git status --porcelain)\" ]"
ok "(a) lastfail text names the tests and the symbol and says to edit them in the same step" "case \"\$OVN_FXI_TEXT\" in *'fix-up reverted the item; tests tests/test_foo.py::test_old still reference old_name; edit them in the same step'*) true;; *) false;; esac"
ok "(a) the task log carries the '--- fixup-integrity: ...' marker the item guard reads" "[ \"\$(grep -c '^--- fixup-integrity: fix-up reverted the item' '$TL')\" = 1 ]"
ok "(a) alerts.log has a warn line" "[ \"\$(grep -c '^warn|itemA|tier2 fix-up undid the item' '$ALERTS')\" = 1 ]"
unset OVN_RI_NEW

# real net diff => kept
mkrepo a2; maincommit
printf 'from app.foo import new_name\n\ndef test_old():\n    assert new_name() == 1\n' > tests/test_foo.py; fixup   # the fix-up edits the OLD test to match the item
H="$(head_)"; ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemA; RC=$?
ok "(a) control: fix-up that edits the tests and keeps the item => rc 0, HEAD untouched" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && [ -z \"\$OVN_FXI_STATUS\" ]"

# the main commit never touched the target: nothing to undo
mkrepo a3; printf 'def test_x():\n    assert True\n' > tests/test_x.py; git add -A; git commit -q -m main; MAIN="$(head_)"
printf '# touch\n' >> tests/test_x.py; fixup; H="$(head_)"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemA; RC=$?
ok "(a) control: main commit never changed the item target (app/foo.py) => no net-zero verdict" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ]"

# kill switch
mkrepo a4; maincommit; git checkout -q "$BEFORE" -- app/foo.py; fixup; H="$(head_)"
OVN_FIXUP_UNDO_GUARD=off OVN_FIXUP_REVERIFY=off ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemA; RC=$?
ok "(a) kill switch OVN_FIXUP_UNDO_GUARD=off => net-zero fix-up is kept (rc 0)" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ]"

# an item that names no file has no target => no opinion
mkrepo a5 '- [ ] [T2] Tighten some wording in the docs. VERIFY: `true`'; maincommit; git checkout -q "$BEFORE" -- app/foo.py; fixup; H="$(head_)"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemA; RC=$?
ok "(a) item without a leading file path => rc 0" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ]"

# ---- (b) VERIFY re-run: SHADOW by default ----
mkrepo b1; maincommit
printf 'def other():\n    return 2\n' > app/foo.py; fixup; H="$(head_)"   # net diff on foo.py is non-empty but the item's VERIFY (grep new_name) now FAILS
: > "$ALERTS"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemB; RC=$?
ok "(b) default (OVN_FIXUP_REVERIFY unset) is SHADOW: VERIFY fails but nothing is reset (rc 0, HEAD unchanged)" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && [ -z \"\$OVN_FXI_STATUS\" ]"
ok "(b) shadow logs '[fixup-verify-fail]' to the task log" "[ \"\$(grep -c '\\[fixup-verify-fail\\] (tier2, mode=shadow)' '$TL')\" = 1 ]"
ok "(b) shadow writes an info alert" "[ \"\$(grep -c '^info|itemB|\\[fixup-verify-fail\\]' '$ALERTS')\" = 1 ]"
ok "(b) the VERIFY itself ran through shadow_check (a FAIL row is in the shadow log)" "[ \"\$(grep -c 'result=FAIL' '$OVN_VERIFY_SHADOW_LOG')\" -ge 1 ]"
OVN_FIXUP_REVERIFY=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemB; RC=$?
ok "(b) enforce: rc 1, reset to BEFORE_SHA, status no-op(fixup-undid-item)" "[ $RC = 1 ] && [ \"\$(head_)\" = '$BEFORE' ] && [ \"\$OVN_FXI_STATUS\" = 'no-op(fixup-undid-item)' ]"
mkrepo b2; maincommit; printf 'def new_name():\n    return 11\n' > app/foo.py; fixup; H="$(head_)"
: > "$TL"; ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemB; RC=$?
ok "(b) control: the fix-up keeps the VERIFY green => rc 0 and no verify-fail log" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && [ \"\$(grep -c 'fixup-verify-fail' '$TL')\" = 0 ]"
mkrepo b3; maincommit; printf 'def other():\n    return 2\n' > app/foo.py; fixup; : > "$TL"
OVN_FIXUP_REVERIFY=off ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemB; RC=$?
ok "(b) OVN_FIXUP_REVERIFY=off skips the VERIFY and the test check (rc 0, nothing logged)" "[ $RC = 0 ] && [ ! -s '$TL' ]"
mkrepo b4 '- [ ] [T2] app/foo.py — Rename `old_name` to `new_name`. VERIFY: `sleep 5`'; maincommit; printf 'def new_name():\n    return 12\n' > app/foo.py; fixup; : > "$TL"
OVN_FIXUP_VERIFY_TIMEOUT=1 OVN_FIXUP_REVERIFY=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemB; RC=$?
ok "(b) an INDETERMINATE VERIFY (timeout) is not a failure, even in enforce (rc 0)" "[ $RC = 0 ] && [ \"\$(grep -c 'fixup-verify-fail' '$TL')\" = 0 ]"

# ---- (c) test-name retention ----
mkrepo c1; maincommit
git rm -q tests/test_new.py; fixup; H="$(head_)"; : > "$TL"; : > "$ALERTS"
ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemC; RC=$?
ok "(c) shadow: fix-up deleted the new test file => rc 0, logged '[fixup-tests-lost]' naming test_new_feature" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && [ \"\$(grep -c 'fixup-tests-lost.*test_new_feature' '$TL')\" = 1 ] && [ \"\$(grep -c '^info|itemC|\\[fixup-tests-lost\\]' '$ALERTS')\" = 1 ]"
OVN_FIXUP_REVERIFY=enforce ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemC; RC=$?
ok "(c) enforce: reset + status, text says to edit them instead of deleting" "[ $RC = 1 ] && [ \"\$(head_)\" = '$BEFORE' ] && case \"\$OVN_FXI_TEXT\" in *'edit them in the same step instead of deleting them'*) true;; *) false;; esac"
mkrepo c2; maincommit
printf 'from app.foo import new_name\n\ndef test_new_feature():\n    assert new_name() == 1\n    assert True\n' > tests/test_new.py; fixup; : > "$TL"
ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemC; RC=$?
ok "(c) control: a fix-up that EDITS the new test (name kept) is fine" "[ $RC = 0 ] && [ \"\$(grep -c 'fixup-tests-lost' '$TL')\" = 0 ]"
mkrepo c3; maincommit
printf 'from app.foo import new_name\n\ndef test_new_feature_renamed():\n    assert new_name() == 1\n' > tests/test_new.py; fixup; : > "$TL"
ok "(c) names are matched whole-word: renaming test_new_feature -> test_new_feature_renamed counts as lost" "[ \"\$(ovn_fixup_lost_tests '$BEFORE' '$MAIN')\" = 'tests/test_new.py::test_new_feature' ]"
ok "(c) ovn_fixup_added_test_names finds python def, gd func and JS it() titles" "[ \"\$(printf 'x' >/dev/null; cd '$R' && git checkout -q '$BEFORE' && printf 'func test_gd_one():\n\tpass\n' > tests/test_g.gd && printf \"it('does a thing', () => {})\n\" > tests/a.test.ts && git add -A && git commit -q -m js && ovn_fixup_added_test_names '$BEFORE' HEAD | sort | tr '\n' '|' )\" = \$'tests/a.test.ts\tdoes a thing|tests/test_g.gd\ttest_gd_one|' ]"

# ---- (d) test-only guard ----
TITEM='- [ ] [T2] tests/test_rate.py — Add a 429 test for notifications. VERIFY: `true`'
mkrepo d1 "$TITEM"; mkdir -p app/core; printf 'x\n' > tests/test_rate.py; printf 'LIMIT = 1\n' > app/core/rate_limiting.py; git add -A; git commit -q -m cycle; H="$(head_)"; : > "$ALERTS"; : > "$TL"
ovn_testonly_guard "$BEFORE" "$TL" itemD; RC=$?
ok "(d) default is SHADOW: a test item touching app/core/rate_limiting.py => rc 0, tag '[prod-touch]', no reset" "[ $RC = 0 ] && [ \"\$OVN_TOGUARD_TAG\" = '[prod-touch]' ] && [ \"\$(head_)\" = '$H' ]"
ok "(d) shadow logs [prod-touch] to the task log and warns in alerts.log naming the file" "[ \"\$(grep -c '\\[prod-touch\\].*app/core/rate_limiting.py' '$TL')\" = 1 ] && [ \"\$(grep -c '^warn|itemD|\\[prod-touch\\]' '$ALERTS')\" = 1 ]"
OVN_TESTONLY_GUARD=enforce ovn_testonly_guard "$BEFORE" "$TL" itemD; RC=$?
ok "(d) enforce: rc 1, reset to BEFORE_SHA, status reverted(test-item-touched-prod)" "[ $RC = 1 ] && [ \"\$(head_)\" = '$BEFORE' ] && [ \"\$OVN_FXI_STATUS\" = 'reverted(test-item-touched-prod)' ] && [ ! -e app/core/rate_limiting.py ]"
mkrepo d2 "$TITEM"; printf 'x\n' > tests/test_rate.py; printf 'x\n' > tests/conftest.py; git add -A; git commit -q -m cycle
ovn_testonly_guard "$BEFORE" "$TL" itemD; RC=$?
ok "(d) control: a test item that only touches tests/ (and its target) => no tag" "[ $RC = 0 ] && [ -z \"\$OVN_TOGUARD_TAG\" ]"
mkrepo d3 '- [ ] [T2] app/foo.py — Rename `old_name`. VERIFY: `true`'; mkdir -p app/core; printf 'LIMIT = 1\n' > app/core/rate_limiting.py; git add -A; git commit -q -m cycle
ovn_testonly_guard "$BEFORE" "$TL" itemD; RC=$?
ok "(d) control: a NON-test item touching production files is not this guard's business" "[ $RC = 0 ] && [ -z \"\$OVN_TOGUARD_TAG\" ]"
mkrepo d4 '- [ ] [T2] app/foo.py — add coverage {cat:test}. VERIFY: `true`'; mkdir -p app/core; printf 'LIMIT = 1\n' > app/core/rate_limiting.py; git add -A; git commit -q -m cycle
ovn_testonly_guard "$BEFORE" "$TL" itemD; RC=$?
ok "(d) a cat:test item counts as a test item (touches app/core/rate_limiting.py => tag)" "[ \"\$OVN_TOGUARD_TAG\" = '[prod-touch]' ]"
mkrepo d5 "$TITEM"; mkdir -p app/core; printf 'LIMIT = 1\n' > app/core/rate_limiting.py; git add -A; git commit -q -m cycle
OVN_TESTONLY_GUARD=off ovn_testonly_guard "$BEFORE" "$TL" itemD; RC=$?
ok "(d) OVN_TESTONLY_GUARD=off => no tag, no reset" "[ $RC = 0 ] && [ -z \"\$OVN_TOGUARD_TAG\" ]"
mkrepo d6 "$TITEM"; printf 'OVERNIGHT bookkeeping\n' > OVERNIGHT_PROGRESS.md; printf 'x\n' > tests/test_rate.py; git add -A; git commit -q -m cycle
ovn_testonly_guard "$BEFORE" "$TL" itemD; RC=$?
ok "(d) bookkeeping (OVERNIGHT_PROGRESS.md) is not a production touch" "[ $RC = 0 ] && [ -z \"\$OVN_TOGUARD_TAG\" ]"

# ---- wrong-item guard (harness-credit-integrity review): when the scout named files that no open item mentions, ovn_resolve_top_item falls back to the TOP item,
# which the cycle did probably NOT work - the gates (which reset in enforce mode) must then have no opinion instead of acting on it ----
wi_repo(){ # <name> : two open items, top = app/foo.py, second = app/bar.py
  R="$tmp/$1"; rm -rf "$R"; mkdir -p "$R/app" "$R/tests"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  printf 'def old_name():\n    return 1\n' > app/foo.py; printf 'def b():\n    return 1\n' > app/bar.py
  printf '## Next Steps\n- [ ] [T2] app/foo.py — Rename `old_name` to `new_name`. VERIFY: `grep -q new_name app/foo.py`\n- [ ] [T2] app/bar.py — Tidy b. VERIFY: `true`\n' > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m before; BEFORE="$(git rev-parse HEAD)"; TL="$tmp/$1.log"; : > "$TL"
}
wi_repo wi1; printf 'VERDICT: PROCEED\nPLAN: x\nFILES: app/bar.py\n' > "$TL"
ok "wrong-item guard: the scout names app/bar.py => that item (line 3) is the worked item" "case \"\$(ovn_fixup_item_line '$BEFORE' '$TL')\" in 3:*'app/bar.py'*) true;; *) false;; esac"
wi_repo wi2; printf 'VERDICT: PROCEED\nPLAN: x\nFILES: app/zzz.py\n' > "$TL"
ok "wrong-item guard: the scout names a file NO open item mentions => unresolvable (empty), not the top item" "[ -z \"\$(ovn_fixup_item_line '$BEFORE' '$TL')\" ]"
ok "wrong-item guard CONTROL (OVN_FIXUP_ITEM_STRICT=off = the old behaviour): the top item (line 2) comes back" "case \"\$(OVN_FIXUP_ITEM_STRICT=off ovn_fixup_item_line '$BEFORE' '$TL')\" in 2:*'app/foo.py'*) true;; *) false;; esac"
wi_repo wi3; printf 'Tokens: 1k sent\n' > "$TL"
ok "wrong-item guard: no scout tokens in the log => the top item is the best answer (line 2)" "case \"\$(ovn_fixup_item_line '$BEFORE' '$TL')\" in 2:*'app/foo.py'*) true;; *) false;; esac"
# end to end through the enforced net-zero gate: the cycle worked app/bar.py (scout names app/zzz.py, so nothing resolves); the top item's file is net-zero => NO reset
wi_repo wi4; printf 'VERDICT: PROCEED\nFILES: app/zzz.py\n' > "$TL"
printf 'def new_name():\n    return 1\n' > app/foo.py; git add -A; git commit -q -m main; MAIN="$(git rev-parse HEAD)"
git checkout -q "$BEFORE" -- app/foo.py; git add -A; git commit -q -m fixup; H="$(git rev-parse HEAD)"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemW; RC=$?
ok "wrong-item guard: an unresolvable worked item => the enforced net-zero gate has no opinion (rc 0, HEAD untouched)" "[ $RC = 0 ] && [ \"\$(git rev-parse HEAD)\" = '$H' ]"
printf 'VERDICT: PROCEED\nFILES: app/foo.py\n' > "$TL"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemW; RC=$?
ok "wrong-item guard CONTROL: the scout names app/foo.py => the same net-zero IS reset (rc 1)" "[ $RC = 1 ] && [ \"\$(git rev-parse HEAD)\" = '$BEFORE' ]"

# ---- ovn_item_guard.sh: the undone-item status is billed to the FAIL cap (3), not the no-op cap (4), and keeps the lesson as lastfail ----
guard_repo(){ # $1=name
  local r="$tmp/g_$1"; rm -rf "$r"; mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t && printf '%s\n' '- [ ] [T2] app/foo.py — Rename `old_name` to `new_name`. VERIFY: `true`' > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
  printf '%s' "$r"
}
GL="$tmp/guard.log"; printf '%s\n' 'Tokens: 5k sent, 100 received.' '--- fixup-integrity: fix-up reverted the item; tests tests/test_foo.py::test_old still reference old_name; edit them in the same step ---' > "$GL"
gr="$(guard_repo m)"; gst="$tmp/gstate_m"; mkdir -p "$gst"
for i in 1 2 3; do bash "$GUARD" "$gr" 'no-op(fixup-undid-item)' "$gst" itemG "$GL" >/dev/null 2>&1; done
ok "guard: 3 x no-op(fixup-undid-item) parks the item on the FAIL cap ('3 failed-to-land cycles')" "[ \"\$(grep -c 'AUTO-SKIP after 3 failed-to-land cycles' '$gr/OVERNIGHT_PROGRESS.md')\" = 1 ]"
gr2="$(guard_repo m2)"; gst2="$tmp/gstate_m2"; mkdir -p "$gst2"
for i in 1; do bash "$GUARD" "$gr2" 'no-op(fixup-undid-item)' "$gst2" itemG "$GL" >/dev/null 2>&1; done
LF="$(cat "$gst2"/item_fails/itemG.*.lastfail 2>/dev/null)"
ok "guard: lastfail keeps the integrity text (not the generic failure extract)" "case \"\$LF\" in *'fix-up reverted the item; tests tests/test_foo.py::test_old still reference old_name; edit them in the same step'*) true;; *) false;; esac"
gr3="$(guard_repo m3)"; gst3="$tmp/gstate_m3"; mkdir -p "$gst3"
for i in 1 2 3; do bash "$GUARD" "$gr3" 'no-op(stage-unverified)' "$gst3" itemG "$GL" >/dev/null 2>&1; done
ok "guard control: 3 x an ordinary no-op does NOT park (the no-op cap is 4)" "[ \"\$(grep -c 'AUTO-SKIP' '$gr3/OVERNIGHT_PROGRESS.md')\" = 0 ]"
gr4="$(guard_repo m4)"; gst4="$tmp/gstate_m4"; mkdir -p "$gst4"
for i in 1 2 3; do bash "$GUARD" "$gr4" 'reverted(test-item-touched-prod)' "$gst4" itemG "$GL" >/dev/null 2>&1; done
ok "guard: reverted(test-item-touched-prod) is a plain revert on the fail cap (parks at 3)" "[ \"\$(grep -c 'AUTO-SKIP after 3 failed-to-land cycles' '$gr4/OVERNIGHT_PROGRESS.md')\" = 1 ]"

# ---- run_overnight.sh wiring (anchored code lines) ----
ok "the MAIN commit sha is captured before any fix-up (_ovn_main_sha)" "[ \"\$(grep -c '^      _ovn_main_sha=\"\$AFTER_SHA\"' '$RUN')\" = 1 ]"
ok "the gate runs after the Tier-2 fix-up re-verify and after the BUILD-GATE fix-up re-verify" "[ \"\$(grep -c 'ovn_fixup_integrity_gate tier2 \"\$BEFORE_SHA\"' '$RUN')\" = 1 ] && [ \"\$(grep -c 'ovn_fixup_integrity_gate buildgate \"\$BEFORE_SHA\"' '$RUN')\" = 1 ]"
ok "a gate reset returns the gate's status to the caller" "[ \"\$(grep -c '^              echo \"\$OVN_FXI_STATUS\"; return' '$RUN')\" = 2 ]"
ok "the test-only guard runs before the push and tags the status" "[ \"\$(grep -c '^      if \\[ \"\$VERIFY_RESULT\" != \"fail\" \\] && declare -F ovn_testonly_guard' '$RUN')\" = 1 ] && [ \"\$(grep -c 'PUSH_STATUS=\"\${PUSH_STATUS} \${_ovn_prod_touch}\"' '$RUN')\" = 1 ]"

# ---- MUTATION controls ----
python3 - "$S/lib_fixup.sh" "$tmp" <<'PY'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, name):
    assert s.count(a) == 1, a
    open(sys.argv[2] + "/" + name, "w").write(s.replace(a, b))
mut('  git --literal-pathspecs diff --quiet "$before" HEAD -- "$tgt" 2>/dev/null\n}', '  return 1\n}', "m_undid.sh")
mut('  git --literal-pathspecs diff --quiet "$before" "$main" -- "$tgt" 2>/dev/null && return 1', '  true', "m_pre.sh")
mut('      *) grep -qwF -- "$n" "$tmp" || printf', '      *) true || printf', "m_lost.sh")
mut('    _ovn_fx_is_testpath "$f" && continue\n', '', "m_testpath.sh")
PY
mut_gate(){ # $1=mutant lib $2=scenario builder
  ( source "$1"; unset OVN_RI_NEW; "$2"; ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemM; echo $? )
}
sc_undo(){ mkrepo mu1; maincommit; git checkout -q "$BEFORE" -- app/foo.py; fixup; }
sc_pre(){ mkrepo mu2; printf 'def test_x():\n    assert True\n' > tests/test_x.py; git add -A; git commit -q -m main; MAIN="$(head_)"; printf '# t\n' >> tests/test_x.py; fixup; }
sc_lost(){ mkrepo mu3; maincommit; printf 'from app.foo import new_name\n\ndef test_new_feature_renamed():\n    assert new_name() == 1\n' > tests/test_new.py; fixup; }
ok "MUTATION: if the net-diff check is disabled the net-zero scenario is no longer reset (gate rc 0, so the (a) test would fail)" "[ \"\$(mut_gate '$tmp/m_undid.sh' sc_undo | tail -1)\" = 0 ]"
ok "MUTATION: if the 'main commit touched it' precondition is removed the untouched-target control is wrongly reset (rc 1)" "[ \"\$(mut_gate '$tmp/m_pre.sh' sc_pre | tail -1)\" = 1 ]"
ok "MUTATION sanity: the unmutated gate resets sc_undo (rc 1) and keeps sc_pre (rc 0)" "[ \"\$(mut_gate '$S/lib_fixup.sh' sc_undo | tail -1)\" = 1 ] && [ \"\$(mut_gate '$S/lib_fixup.sh' sc_pre | tail -1)\" = 0 ]"
ok "MUTATION: whole-word test-name matching removed => a renamed test is no longer reported lost" "[ -z \"\$( ( source '$tmp/m_lost.sh'; sc_lost; ovn_fixup_lost_tests \"\$BEFORE\" \"\$MAIN\" ) )\" ] && [ -n \"\$( ( source '$S/lib_fixup.sh'; sc_lost; ovn_fixup_lost_tests \"\$BEFORE\" \"\$MAIN\" ) )\" ]"
ok "MUTATION: without the test-path exclusion the test-only guard flags a pure-test cycle (false positive)" "( source '$tmp/m_testpath.sh'; mkrepo mu5 '$TITEM'; printf 'x\n' > tests/test_rate.py; printf 'y\n' > tests/conftest.py; git add -A; git commit -q -m c; ovn_testonly_prod_touch \"\$BEFORE\" HEAD '$TITEM' tests/test_rate.py >/dev/null )"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
