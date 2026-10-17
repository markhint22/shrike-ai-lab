#!/usr/bin/env bash
# 2026-10-17 (xlite fleet review): a cycle whose whole net diff is blank/comment lines for an item that never asked for comments is not a landing.
#
# Live defect replayed (xlite 03:00-04:00 CDT): the 27B could not "verify" that tests/test_roster_load_hardening.gd had its tests, so it appended
# `# Verified: File exists and contains required tests for roster load hardening.` (d720e965) and then a stray blank line (b1607752). Both cycles were recorded
# `landed pushed(tests:pass)` and the item was credited "already-done" afterwards: two junk commits counted as landings.
# Sections: A ovn_cycle_comment_only (real function extracted from run_overnight.sh), B the REAL guard block extracted from run_overnight.sh (reset / shadow / off),
# C status plumbing (classifier tag). Runs anywhere (no box fixture needed).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RO="${OVN_RUN_OVERNIGHT:-$HERE/../../run_overnight.sh}"; [ -f "$RO" ] || RO="$HOME/overnight-queue/run_overnight.sh"
[ -f "$RO" ] || { echo "  SKIP: run_overnight.sh not found"; exit 0; }
SD="$(cd "$(dirname "$RO")" && pwd)"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
tmp="$(safe_mktemp_dir)" || exit 1
trap 'safe_rm_rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

echo "== A: ovn_cycle_comment_only (unit)"
FN="$(sed -n '/^ovn_cycle_comment_only() {/,/^}/p' "$RO")"; [ -n "$FN" ] || { echo "  FAIL: could not extract ovn_cycle_comment_only"; exit 1; }
eval "$FN"
R="$tmp/r"; mkdir -p "$R"; cd "$R" || exit 1; git init -q -b main . 2>/dev/null || git init -q .
mkdir -p tests scripts
printf 'extends GutTest\n\nfunc test_a() -> void:\n\tassert_eq(1, 1)\n' > tests/test_x.gd
printf 'export const a = 1;\n' > scripts/a.ts
printf '# docs\n' > README.md
printf '# prog\n- [ ] [T1] tests/test_x.gd — Verify the tests exist. VERIFY: `grep -q test_a tests/test_x.gd`\n' > OVERNIGHT_PROGRESS.md
git add -A; git commit -q -m seed; B0="$(git rev-parse HEAD)"
VERIFY_ITEM='[T1] tests/test_x.gd — Verify `test_a` exists and passes. VERIFY: `gut -gdir=tests -gexit`. (cat:test; multifile:no)'
co(){ git checkout -q main; git checkout -q -B "$1" "$B0"; }

co c1; printf '\n# Verified: File exists and contains required tests.\n' >> tests/test_x.gd; git commit -q -am "chore: add verification comment"
ok "A1 appended '# Verified:' comment on a verify item (the d720e965 shape): comment-only" "ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c2; printf '\n' >> tests/test_x.gd; git commit -q -am "style: blank line"
ok "A2 a blank line only (the b1607752 shape): comment-only" "ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c3; printf '\nfunc test_b() -> void:\n\tassert_eq(2, 2)\n' >> tests/test_x.gd; git commit -q -am "real test"
ok "A3 a real code change is NOT comment-only" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c4; printf '\n# note\nfunc test_b() -> void:\n\tassert_eq(2, 2)\n' >> tests/test_x.gd; git commit -q -am "comment plus code"
ok "A4 comment PLUS code is NOT comment-only" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c5; printf '\n## Adds docs\n' >> tests/test_x.gd; git commit -q -am "doc comment"
DOC_ITEM='[T2] tests/test_x.gd — Add a `##` doc-comment above each function. (cat:godot; multifile:no)'
ok "A5 the same diff for a DOC item (item asks for comments) is NOT comment-only" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$DOC_ITEM'"
ok "A6 an unresolved item (empty text) is NOT comment-only: when in doubt it lands" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) ''"
co c7; printf '\nmore words\n' >> README.md; git commit -q -am "readme"
ok "A7 an unknown file type (.md) is NOT judged comment-only" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c8; git rm -q tests/test_x.gd; git commit -q -m "delete"
ok "A8 a deletion is NOT comment-only" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c9; printf '# a new file\n# only comments\n' > tests/new.gd; git add -A; git commit -q -m "new comment file"
ok "A9 a NEW file that is all comments: comment-only" "ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c10; sed -i.bak 's/Verify the tests/Verified the tests/' OVERNIGHT_PROGRESS.md; rm -f OVERNIGHT_PROGRESS.md.bak; git commit -q -am "credit"
ok "A10 a progress-file-only cycle: NOT comment-only (it lands as before)" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c11; printf '// verified\n' >> scripts/a.ts; git commit -q -am "ts comment"
ok "A11 // comment in a .ts file: comment-only" "ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c12; printf 'export const b = 2;\n' >> scripts/a.ts; git commit -q -am "ts code"
ok "A12 code in a .ts file is NOT comment-only" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c13; git commit -q --allow-empty -m e1
ok "A13 an empty commit: NOT comment-only (same sha tree: nothing to judge)" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"
co c14; printf '#!/bin/sh\n# only\n' > scripts/run.sh; git add -A; git commit -q -m "sh"; printf 'echo hi\n' >> scripts/run.sh; git commit -q -am "sh code"
ok "A14 new .sh file whose later commit adds code: NOT comment-only" "! ovn_cycle_comment_only $B0 \$(git rev-parse HEAD) '$VERIFY_ITEM'"

echo "== B: the REAL guard block from run_overnight.sh"
BLK="$(awk '/# COMMENT-ONLY GUARD \(2026-10-17\)/{f=1} /# Auto-regenerate a frozen OpenAPI contract/{f=0} f{print}' "$RO")"
if [ -n "$BLK" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: B0 guard block extracted"; fi
run_block(){  # $1 = env assignment
  co "b$RANDOM"; printf '\n# Verified: File exists.\n' >> tests/test_x.gd; git commit -q -am "chore: verification comment"
  cat > "$tmp/h.sh" <<H
set -u
$1
cd "$R"
task_log="$tmp/task.log"; : > "\$task_log"; id=ongoing-xlite
emit_alert(){ echo "ALERT \$*" >> "\$task_log"; }
ovn_fixup_item_line(){ printf '1:%s' '$VERIFY_ITEM'; }
$FN
f(){
BEFORE_SHA="$B0"; AFTER_SHA="\$(git rev-parse HEAD)"
$BLK
echo FELL-THROUGH
}
f
H
  bash "$tmp/h.sh" 2>&1
}
out="$(run_block "")"
ok "B1 default: status no-op(comment-only), no fall-through" "printf '%s' \"\$out\" | grep -qx 'no-op(comment-only)' && ! printf '%s' \"\$out\" | grep -q FELL-THROUGH"
ok "B2 default: the tree is reset to BEFORE_SHA (the junk commit is gone)" "[ \"\$(git -C '$R' rev-parse HEAD)\" = '$B0' ]"
ok "B3 default: the log explains the guard and an alert names it" "grep -q 'COMMENT-ONLY GUARD:' '$tmp/task.log' && grep -q 'comment-only cycle' '$tmp/task.log'"
out="$(run_block "export OVN_COMMENTONLY_GUARD=off")"
ok "B4 kill switch OVN_COMMENTONLY_GUARD=off: falls through, commit kept (the old behaviour)" "printf '%s' \"\$out\" | grep -q FELL-THROUGH && [ \"\$(git -C '$R' rev-parse HEAD)\" != '$B0' ]"
out="$(run_block "export OVN_COMMENTONLY_GUARD=shadow")"
ok "B5 shadow: falls through, commit kept, but the log says what would have happened" "printf '%s' \"\$out\" | grep -q FELL-THROUGH && grep -q 'COMMENT-ONLY GUARD (shadow)' '$tmp/task.log' && [ \"\$(git -C '$R' rev-parse HEAD)\" != '$B0' ]"

echo "== C: wiring"
ok "C1 the call site sits AFTER the net-zero guard and BEFORE the OpenAPI auto-regen" "awk '/NET-ZERO GUARD \\(2026-10-10/{a=NR} /COMMENT-ONLY GUARD \\(2026-10-17\\)/{b=NR} /Auto-regenerate a frozen OpenAPI/{c=NR} END{exit !(a && b>a && c>b)}' '$RO'"
ok "C2 ovn_classify_fail.sh maps no-op(comment-only) to the bounded tag 'comment-only'" "[ \"\$(bash '$SD/ovn_classify_fail.sh' '$tmp/task.log' 'no-op(comment-only)')\" = comment-only ]"

echo "comment-only guard: $P passed, $F failed"
[ "$F" -eq 0 ]
