#!/usr/bin/env bash
# 2026-10-10 (package qagate, analysis[2] QA-4 / analysis[3] F7 / analysis[1] F6): lib_gut_xml.sh gut_log_skips_note
#   * names EVERY ignored script (the alert used to print 3 lines cut at 200 chars: '4 script(s)' with the 4th never named)
#   * with GITDIR+BASEREF also names the scripts that are NEW vs the base ref; OVN_GUT_SKIPS_NEW=shadow (default: text only) | enforce (rc 1, NOT deduped) | off
#   * the Parse Error portion of the line keeps its previous shape
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"; LIB="$HERE/../lib_gut_xml.sh"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(__d="$(safe_mktemp_dir)" || exit 1 && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "${T:?}"' EXIT
source "$LIB"
unset OVN_GUT_SKIPS_NEW
fresh(){ rm -rf "${T:?}/state"; mkdir -p "$T/state"; }
alertf(){ cat "$T/state/alerts.log" 2>/dev/null; }

# ---- all names are printed
fresh
{ echo 'Running'; for n in test_alpha_long_name_number_one test_bravo_long_name_number_two test_charlie_long_name_number_three test_delta_long_name_number_four \
    test_echo_long_name_number_five test_foxtrot_long_name_number_six; do echo "[Warning] Ignoring script res://tests/$n.gd because it does not extend GutTest"; done; echo 'Passing 3'; } > "$T/many.log"
gut_log_skips_note "$T/many.log" xlite "$T/state"; rc=$?
ok "rc 0 and ONE alert line for 6 ignored scripts" "[ $rc = 0 ] && [ \"\$(grep -c 'gut-skips:xlite' '$T/state/alerts.log')\" = 1 ]"
ok "the line says '6 script(s)'" "alertf | grep -q 'ignored/failed to parse 6 script(s)'"
for n in alpha bravo charlie delta echo foxtrot; do ok "NEGATIVE (old cut-off): the line names test_${n}_long_name... (every script, not a prefix)" "alertf | grep -q 'tests/test_${n}_long_name_number'"; done
ok "the names are plain paths (res:// and the 'because ...' tail stripped)" "! alertf | grep -q 'res://' && ! alertf | grep -q 'because it does not extend'"

# ---- parse errors keep their previous shape
fresh
printf 'Parse Error: res://x.gd:3 - bad\nParse Error: res://y.gd:9 - worse\nIgnoring script res://tests/a.gd because it does not extend GutTest\n' > "$T/pe.log"
gut_log_skips_note "$T/pe.log" xlite "$T/state"
ok "Parse Error lines are still printed (first 3 distinct, ';'-joined)" "alertf | grep -q 'Parse Error: res://x.gd:3 - bad;Parse Error: res://y.gd:9 - worse;'"
ok "...together with the ignored script name; count covers both kinds (3)" "alertf | grep -q '3 script(s)' && alertf | grep -q 'tests/a.gd'"

# ---- NEW vs base ref
G="$T/g"; mkdir -p "$G/tests"; git -C "$G" init -q; git -C "$G" config user.email t@t; git -C "$G" config user.name t
printf 'extends Node\n\nfunc test_old_ignored():\n\tpass\n' > "$G/tests/test_pre.gd"      # already ignored at base
printf 'extends GutTest\n\nfunc test_was_fine():\n\tassert_eq(1, 1)\n' > "$G/tests/test_was.gd"   # GUT-valid at base
git -C "$G" add -A; git -C "$G" commit -q -m base; git -C "$G" branch -q basebranch
printf '\n' > "$G/tests/test_was.gd"; printf '# Placeholder\n' > "$G/tests/test_fresh.gd"; git -C "$G" add -A; git -C "$G" commit -q -m change
printf '[W] Ignoring script res://tests/test_pre.gd because it does not extend GutTest\n[W] Ignoring script res://tests/test_was.gd because it does not extend GutTest\n[W] Ignoring script res://tests/test_fresh.gd because it does not extend GutTest\n' > "$T/new.log"
fresh; gut_log_skips_note "$T/new.log" xlite "$T/state" "$G" basebranch; rc=$?
ok "SHADOW default: rc 0 even with NEW ignored scripts" "[ $rc = 0 ]"
ok "NEW list names the script that was GUT-valid at base (test_was) and the one absent at base (test_fresh)" "alertf | grep -q 'NEW vs basebranch: tests/test_fresh.gd, tests/test_was.gd'"
ok "BENIGN: the script already non-GUT at base (test_pre) is ignored but NOT listed as NEW" "! alertf | grep -q 'NEW vs basebranch:.*test_pre'"
ok "all three are still listed as ignored" "alertf | grep 'ignored (does not extend GutTest)' | grep -q 'tests/test_fresh.gd, tests/test_pre.gd, tests/test_was.gd'"
fresh; OVN_GUT_SKIPS_NEW=enforce gut_log_skips_note "$T/new.log" xlite "$T/state" "$G" basebranch; rc=$?
ok "ENFORCE: rc 1 when a NEW ignored script exists" "[ $rc = 1 ]"
OVN_GUT_SKIPS_NEW=enforce gut_log_skips_note "$T/new.log" xlite "$T/state" "$G" basebranch; rc=$?
ok "ENFORCE: still rc 1 on the second call (the block is NOT deduped) while the alert line is" "[ $rc = 1 ] && [ \"\$(grep -c 'gut-skips:xlite' '$T/state/alerts.log')\" = 1 ]"
printf '[W] Ignoring script res://tests/test_pre.gd because it does not extend GutTest\n' > "$T/pre.log"
fresh; OVN_GUT_SKIPS_NEW=enforce gut_log_skips_note "$T/pre.log" xlite "$T/state" "$G" basebranch; rc=$?
ok "ENFORCE BENIGN: only a pre-existing ignored script => rc 0 (a ratchet, not a wall)" "[ $rc = 0 ]"
fresh; OVN_GUT_SKIPS_NEW=off gut_log_skips_note "$T/new.log" xlite "$T/state" "$G" basebranch; rc=$?
ok "OFF: rc 0 and no NEW text, ignored names still printed" "[ $rc = 0 ] && ! alertf | grep -q 'NEW vs' && alertf | grep -q 'test_fresh.gd'"
fresh; OVN_GUT_SKIPS_NEW=enforce gut_log_skips_note "$T/new.log" xlite "$T/state" "$G" no-such-ref; rc=$?
ok "an unresolvable base ref never blocks (infra problems are not a gate failure), no NEW text" "[ $rc = 0 ] && ! alertf | grep -q 'NEW vs'"
fresh; OVN_GUT_SKIPS_NEW=enforce gut_log_skips_note "$T/new.log" xlite "$T/state"; rc=$?
ok "no GITDIR/BASEREF (old 3-arg call) => nothing is NEW, rc 0 even in enforce" "[ $rc = 0 ] && alertf | grep -q 'gut-skips:xlite'"
fresh; OVN_GUT_SKIPS_NEW=enforce gut_log_skips_note "$T/clean.log" xlite "$T/state" "$G" basebranch; rc=$?
ok "a missing log is silent, rc 0" "[ $rc = 0 ] && [ ! -s '$T/state/alerts.log' ]"
printf 'Running\nPassing 3\n' > "$T/clean.log"
fresh; OVN_GUT_SKIPS_NEW=enforce gut_log_skips_note "$T/clean.log" xlite "$T/state" "$G" basebranch; rc=$?
ok "a clean log is silent, rc 0 in enforce" "[ $rc = 0 ] && [ ! -s '$T/state/alerts.log' ]"

# ---- the hygiene call site passes the worktree + merge target and honours rc 1 (source-level contract; the function itself is tested above)
HYG="$HERE/../../branch_hygiene.sh"
ok "branch_hygiene.sh passes \"\$dir\" and origin/<merge target> to gut_log_skips_note" "grep -qE 'gut_log_skips_note \"\\\$gout\" .* \"\\\$STATE_DIR\" \"\\\$dir\" \"origin/\\\$\\{mt:-develop\\}\"' '$HYG'"
ok "branch_hygiene.sh fails the gate (return 1) when gut_log_skips_note returns 1" "grep -A2 'gut_log_skips_note \"\\\$gout\"' '$HYG' | grep -q 'return 1'"

echo "gut ignored scripts r10: $P passed, $F failed"; [ "$F" = 0 ]
