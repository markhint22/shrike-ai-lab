#!/usr/bin/env bash
# 2026-11-02 (P4 / outcomes F6): the [prod-touch] guard (ovn_testonly_prod_touch in lib_fixup.sh) flagged legitimate sibling-step work. Replay of the real shapes:
#   R1 shrike-notify: [T2] cat:test + [T3] backend/app/main.py of ONE feat tag; the cycle committed main.py AND its test, [T3] ticked 'staged 1/1 DONE', the guard resolved the
#      [T2] cat:test line as 'the item' => main.py counted as production touched by a test item.
#   R2 gitlark: the feature's open sibling item names backend/app/core/error_reporting.py; the cycle edited it => flagged although the item list asks for it.
#   Controls: a test item that touches an UNRELATED production file is still flagged; OVN_PRODTOUCH_SIBLINGS=off restores the old (false-positive) behaviour (mutation proof).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"; S="$HERE/.."
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
# shellcheck disable=SC1090
source "$S/lib_item_select.sh"; source "$S/lib_path_normalize.sh"; source "$S/lib_verify_clause.sh"; source "$S/lib_fixup.sh"
unset OVN_PRODTOUCH_SIBLINGS

R=""; BEFORE=""
mkrepo(){ # $1=name $2=progress file content
  R="$tmp/$1"; rm -rf "${R:?}"; mkdir -p "$R/backend/app/core" "$R/backend/tests"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  echo "x=1" > backend/app/main.py; echo "y=1" > backend/app/core/error_reporting.py; echo "z=1" > backend/app/other.py; echo "t=1" > backend/tests/test_main.py
  printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md; git add -A; git commit -q -m before; BEFORE="$(git rev-parse HEAD)"
}
TEST_ITEM='[T2] backend/tests/test_main_startup.py — add startup test. (cat:test) [feat:notify-20261102-retention]'

# ---- R1: sibling staged step ticked this cycle
mkrepo r1 "## Next Steps
- [ ] $TEST_ITEM VERIFY: \`pytest backend/tests/test_main.py -q\`
- [ ] [T3] backend/app/main.py — propagate topic_history_sizes to broker. (cat:python) [feat:notify-20261102-retention] VERIFY: \`grep -q x backend/app/main.py\`"
echo "x=2" > backend/app/main.py; echo "t=2" > backend/tests/test_main.py
sed -i.bak 's/^- \[ \] \[T3\]\(.*\)$/- [x] [T3]\1  <!-- staged 1\/1 DONE -->/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak
git add -A; git commit -q -m "feat: propagate"
TXT="${TEST_ITEM}"
ok "R1 default: staged production sibling ticked this cycle => no prod-touch (rc 1)" "cd '$R' && ! ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT' ''"
ok "R1 MUTANT (OVN_PRODTOUCH_SIBLINGS=off): the old false positive returns main.py" "cd '$R' && [ \"\$(OVN_PRODTOUCH_SIBLINGS=off ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT' '')\" = backend/app/main.py ]"

# ---- R1b: sibling NOT ticked yet (open) but names the file
mkrepo r1b "## Next Steps
- [ ] $TEST_ITEM VERIFY: \`true\`
- [ ] [T3] backend/app/main.py — propagate. (cat:python) [feat:notify-20261102-retention] VERIFY: \`true\`"
echo "x=2" > backend/app/main.py; git add -A; git commit -q -m "feat: x"
ok "R1b open sibling of the same feat naming the file => excluded" "cd '$R' && ! ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT' ''"

# ---- R2: gitlark sibling names error_reporting.py (no ticking at all)
mkrepo r2 "## Next Steps
- [ ] [T2] backend/tests/test_error_reporting.py — tests for the hook. (cat:test) [feat:gitlark-20261102-errrep] VERIFY: \`true\`
- [ ] [T2] backend/app/core/error_reporting.py — add an env-gated hook. (cat:python) [feat:gitlark-20261102-errrep] VERIFY: \`true\`"
echo "y=2" > backend/app/core/error_reporting.py; git add -A; git commit -q -m "feat: hook"
TXT2='[T2] backend/tests/test_error_reporting.py — tests for the hook. (cat:test) [feat:gitlark-20261102-errrep]'
ok "R2 sibling in the same feature names error_reporting.py => excluded" "cd '$R' && ! ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT2' backend/tests/test_error_reporting.py"
ok "R2 MUTANT: old behaviour flags error_reporting.py" "cd '$R' && [ \"\$(OVN_PRODTOUCH_SIBLINGS=off ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT2' backend/tests/test_error_reporting.py)\" = backend/app/core/error_reporting.py ]"

# ---- controls: a genuine test item that touches an unrelated prod file is still flagged; another feature's files are not excluded
mkrepo c1 "## Next Steps
- [ ] $TEST_ITEM VERIFY: \`true\`
- [ ] [T3] backend/app/main.py — propagate. (cat:python) [feat:notify-20261102-retention] VERIFY: \`true\`
- [ ] [T3] backend/app/other.py — other feature. (cat:python) [feat:other-20261102-zzz] VERIFY: \`true\`"
echo "z=2" > backend/app/other.py; git add -A; git commit -q -m "oops prod"
ok "C1 test item touching another feature's production file is STILL flagged" "cd '$R' && [ \"\$(ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT' '')\" = backend/app/other.py ]"
mkrepo c2 "## Next Steps
- [ ] [T2] backend/tests/test_main.py — add test. (cat:test) VERIFY: \`true\`"
echo "x=9" > backend/app/main.py; git add -A; git commit -q -m "oops"
ok "C2 no feat tag, no siblings: flagged as before" "cd '$R' && [ \"\$(ovn_testonly_prod_touch '$BEFORE' HEAD '[T2] backend/tests/test_main.py — add test. (cat:test)' backend/tests/test_main.py)\" = backend/app/main.py ]"
ok "C3 non-test item: never prod-touch" "cd '$R' && ! ovn_testonly_prod_touch '$BEFORE' HEAD '[T3] backend/app/main.py — change. (cat:python)' backend/app/main.py"
# ---- FX-P4 (1) lib_fixup.sh uses the fail-closed temp helpers (no raw mktemp -d / rm -rf); lint must pass
ok "F1 lib_fixup.sh has no raw 'mktemp -d' / 'rm -rf'" "! grep -nE 'mktemp -d|rm -rf' '$S/lib_fixup.sh'"
ok "F1 test_no_unsafe_rm lint passes on lib_fixup.sh" "python3 '$HERE/lint_unsafe_rm.py' '$S/lib_fixup.sh'"
# ---- FX-P4 (2) PRODSTEP + UNRELATED production file: still no alert, but a shadow row names the unrelated file
PSL="$tmp/prodstep.log"
mkrepo ps1 "## Next Steps
- [ ] $TEST_ITEM VERIFY: \`true\`
- [ ] [T3] backend/app/main.py — propagate. (cat:python) [feat:notify-20261102-retention] VERIFY: \`true\`"
echo "x=2" > backend/app/main.py; echo "z=2" > backend/app/other.py
sed -i.bak 's/^- \[ \] \[T3\]\(.*\)$/- [x] [T3]\1  <!-- staged 1\/1 DONE -->/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak
git add -A; git commit -q -m "feat: propagate + unrelated"
rm -f "$PSL"
ok "S1 PRODSTEP + unrelated prod file: still no-alert (rc 1)" "cd '$R' && ! OVN_PRODSTEP_SHADOW_LOG='$PSL' ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT' ''"
ok "S1 shadow row lists the unrelated file, not the staged sibling's" "[ \$(wc -l < '$PSL') = 1 ] && grep -q 'backend/app/other.py' '$PSL' && ! grep -q 'backend/app/main.py' '$PSL'"
ok "S1 shadow row is TSV with repo name" "awk -F'\\t' 'NF==4 && \$2==\"ps1\"' '$PSL' | grep -q ."
# pure sibling cycle (R1 shape) writes NO row
mkrepo ps2 "## Next Steps
- [ ] $TEST_ITEM VERIFY: \`true\`
- [ ] [T3] backend/app/main.py — propagate. (cat:python) [feat:notify-20261102-retention] VERIFY: \`true\`"
echo "x=2" > backend/app/main.py
sed -i.bak 's/^- \[ \] \[T3\]\(.*\)$/- [x] [T3]\1  <!-- staged 1\/1 DONE -->/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak
git add -A; git commit -q -m "feat: propagate only"
rm -f "$PSL"
ok "S2 PRODSTEP with only sibling files: no alert and no shadow row" "cd '$R' && ! OVN_PRODSTEP_SHADOW_LOG='$PSL' ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT' '' && [ ! -s '$PSL' ]"
# mutant: old early-return on PRODSTEP => no shadow row for S1
MUTL="$tmp/lib_fixup_mut.sh"; sed 's/\*PRODSTEP\*) prodstep=1 ;;/*PRODSTEP*) return 1 ;;/' "$S/lib_fixup.sh" > "$MUTL"
ok "S3 mutant differs" "! cmp -s '$S/lib_fixup.sh' '$MUTL'"
mkrepo ps3 "## Next Steps
- [ ] $TEST_ITEM VERIFY: \`true\`
- [ ] [T3] backend/app/main.py — propagate. (cat:python) [feat:notify-20261102-retention] VERIFY: \`true\`"
echo "x=2" > backend/app/main.py; echo "z=2" > backend/app/other.py
sed -i.bak 's/^- \[ \] \[T3\]\(.*\)$/- [x] [T3]\1  <!-- staged 1\/1 DONE -->/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak
git add -A; git commit -q -m "feat: x"; rm -f "$PSL"
ok "S3 MUTANT (early return): no shadow row => blind spot unmeasured (row absent)" "cd '$R' && ( source '$MUTL'; OVN_PRODSTEP_SHADOW_LOG='$PSL' ovn_testonly_prod_touch '$BEFORE' HEAD '$TXT' ''; [ ! -s '$PSL' ] )"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
