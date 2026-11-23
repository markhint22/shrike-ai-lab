#!/usr/bin/env bash
# q-mon-fixes (2026-11-23): billwatch 858e1492 "fix: auto-remove duplicate Python class/function definition(s)" added a 0-byte tests/test_notification_preview.py.
# The dedupe commit was a bare `git commit` (it swept whatever was already staged) and staged on `!= "unchanged"` (an empty answer counted as a change).
# This runs the REAL block text from run_overnight.sh and the REAL lib_fixup.sh helpers in throwaway repos; each case fails on the old behaviour (mutation section at the end).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
Q="$(cd "$HERE/../.." && pwd)"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 SCRIPT_DIR="$Q"
. "$Q/scripts/lib_fixup.sh"
R="$T/r"
mk(){ rm -rf "$R"; mkdir -p "$R/tests"; git -C "$R" init -q -b main; printf 'def f():\n    return 1\n' > "$R/tests/test_a.py"; git -C "$R" add -A; git -C "$R" commit -q -m base; B="$(git -C "$R" rev-parse HEAD)"
  printf '\ndef f():\n    return 1\n' >> "$R/tests/test_a.py"; git -C "$R" commit -qam cycle; }

echo "== helpers"
printf 'x\n' > "$T/full"; : > "$T/empty"
ok "1: empty dedupe answer is not a change" '! ovn_dedupe_is_change "" "$T/full"'
ok "2: 'unchanged' is not a change" '! ovn_dedupe_is_change unchanged "$T/full"'
ok "3: 'removed duplicate(s)' on an EMPTY file is not a change" '! ovn_dedupe_is_change "removed duplicate(s): f" "$T/empty"'
ok "4: 'removed duplicate(s)' on a real file is a change" 'ovn_dedupe_is_change "removed duplicate(s): f" "$T/full"'
mk; : > "$R/tests/test_new.py"; : > "$R/tests/__init__.py"; printf 'def t():\n    pass\n' > "$R/tests/test_full.py"; : > "$R/tests/conftest.py"; git -C "$R" add -A; git -C "$R" commit -qm c2
out="$(cd "$R" && ovn_empty_test_files_added "$B" HEAD)"
ok "5: lists the 0-byte added test file" 'grep -qx "tests/test_new.py" <<< "$out"'
ok "6: does not list an empty __init__.py / conftest.py / a non-empty test" '! grep -qE "__init__|conftest|test_full" <<< "$out"'

echo "== ovn_fixup_dedupe_defs with an empty test file already staged"
mk; : > "$R/tests/test_stage.py"; git -C "$R" add tests/test_stage.py
out="$(cd "$R" && ovn_fixup_dedupe_defs "$B")"
ok "7: the dedupe commit removed the duplicate" '[ "$(grep -c "^def f(" "$R/tests/test_a.py")" = 1 ]'
ok "8: the dedupe commit does NOT contain the pre-staged 0-byte file" '! git -C "$R" show --stat --format= HEAD | grep -q test_stage'
ok "9: HEAD never gains a 0-byte test file" '[ -z "$(cd "$R" && ovn_empty_test_files_added "$B" HEAD)" ]'

echo "== the real run_overnight.sh python dedupe block"
RO="$Q/run_overnight.sh"
n="$(grep -n 'CHANGED_PY_FILES="\$(git diff' "$RO" | head -1 | cut -d: -f1)"
sed -n "$((n-1)),\$p" "$RO" | awk 'NR==1{print;next}{print} /^    fi$/{exit}' > "$T/block.sh"
ok "10: block extracted" '[ -s "$T/block.sh" ] && bash -n "$T/block.sh" && grep -q _dd_files "$T/block.sh"'
runblock(){ ( cd "$R" || exit 1; ovn_hto(){ shift 2; "$@"; }; task_log="$T/task.log"; : > "$task_log"; BEFORE_SHA="$B"; AFTER_SHA="$(git rev-parse HEAD)"; . "$T/block.sh"; echo "$AFTER_SHA" > "$T/after" ); }
mk; : > "$R/tests/test_notification_preview.py"; git -C "$R" add tests/test_notification_preview.py
runblock
ok "11: block removed the duplicate in a new commit" '[ "$(grep -c "^def f(" "$R/tests/test_a.py")" = 1 ] && [ "$(git -C "$R" log -1 --format=%s)" = "fix: auto-remove duplicate Python class/function definition(s)" ]'
ok "12: block commit holds ONLY the deduped file (the staged empty test file is not swept in)" '[ "$(git -C "$R" show --name-only --format= HEAD)" = "tests/test_a.py" ]'
mk; ( cd "$R" && ovn_hto(){ shift 2; echo; }; task_log="$T/task.log"; : > "$task_log"; BEFORE_SHA="$B"; AFTER_SHA="$(git rev-parse HEAD)"; H0="$AFTER_SHA"; . "$T/block.sh"; [ "$(git rev-parse HEAD)" = "$H0" ] ); R13=$?
ok "13: an EMPTY dedupe answer (timeout/crash) stages and commits nothing" '[ "$R13" = 0 ] && git -C "$R" diff --cached --quiet'

echo "== gate wiring (shadow default)"
ok "14: run_overnight.sh carries the shadow EMPTY-TEST-FILE GUARD" 'grep -q "OVN_EMPTYTEST_GUARD:-shadow" "$RO"'
ok "15: syntax" 'bash -n "$RO" && bash -n "$Q/scripts/lib_fixup.sh"'

echo "== MUTATION: old bare-commit behaviour must fail cases 8/12"
sed 's/ -- "\${files\[@\]}" >\/dev\/null 2>&1 ||/ >\/dev\/null 2>\&1 ||/' "$Q/scripts/lib_fixup.sh" > "$T/lib_old.sh"
ok "16: mutant lib differs from real" '! cmp -s "$T/lib_old.sh" "$Q/scripts/lib_fixup.sh"'
mk; : > "$R/tests/test_stage.py"; git -C "$R" add tests/test_stage.py
( . "$T/lib_old.sh"; cd "$R" && ovn_fixup_dedupe_defs "$B" >/dev/null )
ok "17: MUTANT sweeps the staged 0-byte file (the 858e1492 shape reproduces)" 'git -C "$R" show --stat --format= HEAD | grep -q test_stage'
sed 's/git commit -m "fix: auto-remove duplicate Python class\/function definition(s)" --quiet -- "\${_dd_files\[@\]}"/git commit -m "fix: auto-remove duplicate Python class\/function definition(s)" --quiet/' "$RO" > "$T/ro_old.sh"
ok "18: block mutant differs" '! cmp -s "$T/ro_old.sh" "$RO"'
n2="$(grep -n 'CHANGED_PY_FILES="\$(git diff' "$T/ro_old.sh" | head -1 | cut -d: -f1)"
sed -n "$((n2-1)),\$p" "$T/ro_old.sh" | awk 'NR==1{print;next}{print} /^    fi$/{exit}' > "$T/block_old.sh"
mk; : > "$R/tests/test_notification_preview.py"; git -C "$R" add tests/test_notification_preview.py
( cd "$R" && ovn_hto(){ shift 2; "$@"; }; task_log="$T/task.log"; BEFORE_SHA="$B"; AFTER_SHA="$(git rev-parse HEAD)"; . "$T/block_old.sh" )
ok "19: MUTANT block commits the 0-byte file (reproduces billwatch 858e1492)" 'git -C "$R" show --name-only --format= HEAD | grep -q test_notification_preview'

echo "q-mon-fixes empty-dedupe: $P passed, $F failed"; [ "$F" = 0 ]
