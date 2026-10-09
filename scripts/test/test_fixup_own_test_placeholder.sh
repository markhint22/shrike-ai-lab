#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 3): Tier-2 fix-up "own test" detection by failing test ID against BEFORE_SHA.
# Live bug: `git diff --diff-filter=A` is blank when a placeholder stub ("Placeholder - the implement step fills this in.") was committed before the
# cycle, because the model's commit MODIFIES the stub. Its brand-new failing test was therefore classed source-broke-green, the fix-up was told "restore the old
# behaviour", and the item was undone (and the NEEDS-DECISION guard could park an item for failing in its OWN test file).
# Fixture (temp git repo): BEFORE = tests/test_old.py (test_old_a) + tests/test_new.py (placeholder stub only) + backend/tests/test_sub.py;
# the model's commit fills the stub (test_new_b), adds test_old_added + test_old_a_extra to test_old.py and creates tests/test_brand_new.py.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_fixup.sh"; RUN="$HERE/../../run_overnight.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# shellcheck disable=SC1090
source "$LIB"
R="$tmp/repo"; mkdir -p "$R/tests" "$R/backend/tests" "$R/src" "$R/a/tests" "$R/b/tests"
cd "$R" || exit 1
git init -q; git config user.email t@t; git config user.name t
printf 'def test_old_a():\n    assert 1 == 1\n' > tests/test_old.py
printf '"""Placeholder - the implement step fills this in."""\n' > tests/test_new.py
printf 'def test_sub_a():\n    assert True\n' > backend/tests/test_sub.py
printf 'def test_stub_x():\n    pass  # Placeholder - the implement step fills this in.\n' > tests/test_stub2.py
printf "describe('suite', () => { it('does the old thing', () => {}) })\n" > src/a.spec.ts
printf 'def test_x():\n    assert True\n' > a/tests/test_u.py; cp a/tests/test_u.py b/tests/test_u.py   # same suffix tests/test_u.py in TWO subprojects
git add -A; git commit -q -m before
BEFORE="$(git rev-parse HEAD)"
printf 'def test_new_b():\n    assert 1 == 2\n' > tests/test_new.py
printf 'def test_old_a():\n    assert 1 == 1\n\ndef test_old_added():\n    assert 0\n\ndef test_old_a_extra():\n    assert 0\n' > tests/test_old.py
printf 'def test_brand():\n    assert 0\n' > tests/test_brand_new.py
printf 'def test_stub_x():\n    assert 1 == 2\n' > tests/test_stub2.py
printf "describe('suite', () => { it('does the old thing', () => {}); it('does the new thing', () => {}) })\n" > src/a.spec.ts
git add -A; git commit -q -m model
AFTER="$(git rev-parse HEAD)"
NEWTESTS="$(git diff --name-only --diff-filter=A "$BEFORE" "$AFTER" | grep -E 'test_')"   # what the OLD rule sees: only the brand-new file, never the filled-in stub

k(){ ovn_fixup_kind "FAILED $1" "$NEWTESTS" "$BEFORE" "$1"; }
ok "fixture: the old added-file rule sees only test_brand_new.py (the stub fill-in is invisible to it)" "[ \"\$NEWTESTS\" = tests/test_brand_new.py ]"
ok "placeholder stub filled by the model: failing id from that file => own-test" "[ \"\$(k 'tests/test_new.py::test_new_b')\" = own-test ]"
ok "CONTROL: the OLD basename rule (OVN_OWN_TEST_IDS=off) wrongly says source-broke-green for the same failure" "[ \"\$(OVN_OWN_TEST_IDS=off ovn_fixup_kind 'FAILED tests/test_new.py::test_new_b - assert 1 == 2' \"\$NEWTESTS\" '$BEFORE' 'tests/test_new.py::test_new_b')\" = source-broke-green ]"
ok "control: failing id from an OLDER file with an UNCHANGED function => source-broke-green" "[ \"\$(k 'tests/test_old.py::test_old_a')\" = source-broke-green ]"
ok "placeholder stub that ALREADY declares the function name (test_stub_x): the file is only a stub at BEFORE => own-test" "[ \"\$(k 'tests/test_stub2.py::test_stub_x')\" = own-test ]"
ok "existing test file gains a NEW failing function => own-test" "[ \"\$(k 'tests/test_old.py::test_old_added')\" = own-test ]"
ok "new function whose name merely CONTAINS an old one (test_old_a_extra vs test_old_a) => own-test (whole-word match)" "[ \"\$(k 'tests/test_old.py::test_old_a_extra')\" = own-test ]"
ok "parametrised id of an unchanged function (test_old_a[1-2]) => source-broke-green" "[ \"\$(k 'tests/test_old.py::test_old_a[1-2]')\" = source-broke-green ]"
ok "class-qualified id of an unchanged function => source-broke-green" "[ \"\$(k 'tests/test_old.py::TestX::test_old_a')\" = source-broke-green ]"
ok "file absent at BEFORE (brand-new test file) => own-test" "[ \"\$(k 'tests/test_brand_new.py::test_brand')\" = own-test ]"
ok "id relative to a subproject dir resolves by suffix (tests/test_sub.py -> backend/tests/test_sub.py) => source-broke-green" "[ \"\$(k 'tests/test_sub.py::test_sub_a')\" = source-broke-green ]"
ok "vitest style id: unchanged title => source-broke-green" "[ \"\$(k 'src/a.spec.ts > suite > does the old thing')\" = source-broke-green ]"
ok "vitest style id: new title => own-test" "[ \"\$(k 'src/a.spec.ts > suite > does the new thing')\" = own-test ]"
ok "mixed ids (one old, one own) => own-test" "[ \"\$(ovn_fixup_kind 'x' '' '$BEFORE' \"\$(printf 'tests/test_old.py::test_old_a\ntests/test_new.py::test_new_b')\")\" = own-test ]"
ok "no ids => the old basename rule still applies (own-test when the summary names an added file)" "[ \"\$(ovn_fixup_kind 'FAILED tests/test_brand_new.py::test_brand' \"\$NEWTESTS\" '$BEFORE' '')\" = own-test ]"
ok "no ids and no match => source-broke-green" "[ \"\$(ovn_fixup_kind 'FAILED tests/test_old.py::test_old_a' \"\$NEWTESTS\" '$BEFORE' '')\" = source-broke-green ]"
# UNKNOWN (harness-credit-integrity fix): an id whose file cannot be resolved must NOT be claimed as own (that flipped the fix-up direction for tests that
# already passed and skipped the NEEDS-DECISION park) - it falls back to the old added-file-basename rule.
ok "ambiguous subproject-relative id (a/tests/test_u.py AND b/tests/test_u.py both present at BEFORE) => rc 2 (unknown), not own" "ovn_test_id_is_own '$BEFORE' 'tests/test_u.py::test_x'; [ \$? = 2 ]"
ok "ambiguous id => kind source-broke-green (the test passed before; the old rule has no added file to match)" "[ \"\$(k 'tests/test_u.py::test_x')\" = source-broke-green ]"
ok "unresolvable id (absent at BEFORE and at the after-commit) => rc 2 (unknown)" "ovn_test_id_is_own '$BEFORE' 'ghost/tests/test_ghost.py::test_g'; [ \$? = 2 ]"
ok "unresolvable id => kind source-broke-green via the old rule (no added file matches)" "[ \"\$(k 'ghost/tests/test_ghost.py::test_g')\" = source-broke-green ]"
ok "unresolvable id whose basename IS an added file => the old rule still says own-test" "[ \"\$(ovn_fixup_kind 'FAILED sub/tests/test_brand_new.py::test_brand' \"\$NEWTESTS\" '$BEFORE' 'sub/tests/test_brand_new.py::test_brand')\" = own-test ]"
ok "nd precondition: an unresolvable id with no added-file match => rc 0 (old rule: a pre-existing test broke)" "ovn_fixup_nd_precondition '$BEFORE' '$AFTER' 'ghost/tests/test_ghost.py::test_g'"
ok "nd precondition: an unresolvable id whose basename is an added file => rc 1" "! ovn_fixup_nd_precondition '$BEFORE' '$AFTER' 'sub/tests/test_brand_new.py::test_brand'"
ok "nd precondition: ambiguous id => rc 0 (old rule), not blocked as 'own'" "ovn_fixup_nd_precondition '$BEFORE' '$AFTER' 'tests/test_u.py::test_x'"
ok "non-file-shaped id (no extension) is never claimed as own" "! ovn_test_id_is_own '$BEFORE' 'some_random_id'"

# own-test failures must tell the fix-up the test is NEW and never to restore old behaviour
D="$(ovn_fixup_direction own-test)"
ok "own-test direction says the failing test is NEW" "case \"\$D\" in *'is NEW'*) true;; *) false;; esac"
ok "own-test direction says never restore old behaviour / never undo the task" "case \"\$D\" in *'Never restore old behaviour'*'undo the committed change'*) true;; *) false;; esac"
ok "own-test direction still says prefer fixing the TEST (existing contract)" "case \"\$D\" in *'prefer fixing the TEST'*) true;; *) false;; esac"
ok "source-broke-green direction unchanged (fix the SOURCE change)" "case \"\$(ovn_fixup_direction source-broke-green)\" in *'Fix the SOURCE change'*) true;; *) false;; esac"

# NEEDS-DECISION precondition: only PRE-EXISTING failing tests, and never the item's own target file
OLDIDS='tests/test_old.py::test_old_a'; OWNIDS="$(printf 'tests/test_old.py::test_old_a\ntests/test_new.py::test_new_b')"
ok "nd precondition: only old ids => rc 0" "ovn_fixup_nd_precondition '$BEFORE' '$AFTER' '$OLDIDS'"
ok "nd precondition: an id from the filled-in placeholder file => rc 1 (not an older test)" "! ovn_fixup_nd_precondition '$BEFORE' '$AFTER' \"\$OWNIDS\""
ok "CONTROL: the old added-file rule would let the placeholder case through (rc 0) - the bug" "OVN_OWN_TEST_IDS=off ovn_fixup_nd_precondition '$BEFORE' '$AFTER' \"\$OWNIDS\""
ok "nd precondition: empty ids => rc 1" "! ovn_fixup_nd_precondition '$BEFORE' '$AFTER' ''"
ITEM='- [ ] [T2] tests/test_old.py — Add tests for the old thing. VERIFY: pytest tests/test_old.py'
ok "failing file is the item's OWN target (tests/test_old.py) => hit_target rc 0" "ovn_fixup_ids_hit_target '$ITEM' '$OLDIDS'"
ok "failing file is a different file than the item's target => hit_target rc 1" "! ovn_fixup_ids_hit_target '- [ ] [T2] app/svc.py — Fix it' '$OLDIDS'"
ok "hit_target handles a subdir-relative target and tags/backticks (\`backend/tests/test_sub.py\`)" "ovn_fixup_ids_hit_target '- [ ] [T3] (bug) \`backend/tests/test_sub.py\`: — x' 'tests/test_sub.py::test_sub_a'"
ok "ids_old_only with the item line: old id + own target => rc 1 (tag must not apply)" "! ovn_fixup_ids_old_only '$BEFORE' '$OLDIDS' '$ITEM'"
ok "ids_old_only with the item line: old id + different target => rc 0" "ovn_fixup_ids_old_only '$BEFORE' '$OLDIDS' '- [ ] [T2] app/svc.py — Fix it'"
ok "ovn_item_leading_path strips checkbox, tags, backticks and :line" "[ \"\$(ovn_item_leading_path '- [ ] (x) [T2] \`app/a.py:12\` — d')\" = app/a.py ]"

# wiring in run_overnight.sh (anchored to executed code, not comments)
ok "run_overnight.sh passes BEFORE_SHA and the failing ids to ovn_fixup_kind" "[ \"\$(grep -c '^          _fixup_kind=\"\$(ovn_fixup_kind \"\$_fixup_summary\" \"\$_fixup_newtests\" \"\$BEFORE_SHA\" \"\$_fixup_ids\")\"' '$RUN')\" = 1 ]"
ok "run_overnight.sh NEEDS-DECISION guard calls ovn_fixup_nd_precondition" "[ \"\$(grep -c '&& declare -F ovn_fixup_nd_precondition >/dev/null 2>&1 && ovn_fixup_nd_precondition ' '$RUN')\" = 1 ]"
ok "run_overnight.sh no longer decides NEEDS-DECISION from added-file basenames inline" "[ \"\$(grep -c 'grep -F -f <(printf' '$RUN')\" = 0 ]"

# MUTATION controls (copies of the lib with one rule removed must fail the matching case)
python3 - "$LIB" "$tmp/m_placeholder.sh" "$tmp/m_name.sh" "$tmp/m_absent.sh" "$tmp/m_unknown.sh" "$tmp/m_ambig.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, out):
    assert s.count(a) == 1, a
    open(out, "w").write(s.replace(a, b))
mut('if grep -qF -- "$OVN_FIXUP_PLACEHOLDER_TEXT" "$tmp"; then own=0', 'if false; then own=0', sys.argv[2])
mut('*) grep -qwF -- "$_FX_NAME" "$tmp" || own=0 ;;', '*) true ;;', sys.argv[3])
mut('[ -n "$f" ] && [ "$f" != AMBIGUOUS ] && return 0', 'false', sys.argv[4])
mut('    return 2\n  fi\n  tmp=', '    return 0\n  fi\n  tmp=', sys.argv[5])      # old behaviour: an unresolvable file is claimed as own
mut('[ "$f" = AMBIGUOUS ] && return 2', '[ "$f" = AMBIGUOUS ] && return 0', sys.argv[6])   # old behaviour: ambiguous => empty => own
PY
mutcase(){ ( source "$1"; cd "$R" && ovn_test_id_is_own "$BEFORE" "$2" ); }
ok "MUTATION: without the placeholder rule the filled-in stub id is no longer own (test would fail)" "! mutcase '$tmp/m_placeholder.sh' 'tests/test_stub2.py::test_stub_x'"
ok "MUTATION: without the name-absent rule a new function in an old file is no longer own" "! mutcase '$tmp/m_name.sh' 'tests/test_old.py::test_old_added'"
ok "MUTATION: without the file-absent rule a brand-new file is no longer own" "! mutcase '$tmp/m_absent.sh' 'tests/test_brand_new.py::test_brand'"
ok "MUTATION: the old claim-own-when-unresolvable behaviour flips the unknown id to own (rc 0 instead of 2)" "mutcase '$tmp/m_unknown.sh' 'ghost/tests/test_ghost.py::test_g'"
ok "MUTATION: the old ambiguous behaviour claims own (rc 0 instead of 2)" "mutcase '$tmp/m_ambig.sh' 'tests/test_u.py::test_x'"
ok "MUTATION sanity: the unmutated lib says own for all three" "ovn_test_id_is_own '$BEFORE' 'tests/test_stub2.py::test_stub_x' && ovn_test_id_is_own '$BEFORE' 'tests/test_old.py::test_old_added' && ovn_test_id_is_own '$BEFORE' 'tests/test_brand_new.py::test_brand'"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
