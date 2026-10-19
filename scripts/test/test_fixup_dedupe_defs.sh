#!/usr/bin/env bash
# 2026-10-18: ovn_fixup_dedupe_defs (lib_fixup.sh) - after a FIX-UP aider call, byte-identical duplicate GDScript / Python definitions that the fix-up introduced are removed
# and committed (the main aider call already had this pass; the fix-up call, whose job is to "restore" code, did not: xlite reverted(build-break) x2, 0551207 defined
# get_phase_name twice). End-to-end wiring through run_aider_fix_task is in test_buildgate_fixup_dedupe_dangling_e2e.sh; this is the function's own contract.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
Q="$(cd "$HERE/../.." && pwd)"; [ -f "$Q/scripts/lib_fixup.sh" ] || Q="$HOME/overnight-queue"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
export SCRIPT_DIR="$Q"
# shellcheck disable=SC1090
. "$Q/scripts/lib_fixup.sh"
declare -F ovn_fixup_dedupe_defs >/dev/null || { echo "  FAIL: ovn_fixup_dedupe_defs missing from lib_fixup.sh"; exit 1; }
R="$T/r"
mk(){ rm -rf "$R"; mkdir -p "$R"; git -C "$R" init -q -b main; printf 'class_name T\n\n## a\nfunc a() -> int:\n\treturn 1\n\n## b\nfunc b() -> int:\n\treturn 2\n' > "$R/t.gd"; printf 'def f():\n    return 1\n' > "$R/m.py"; git -C "$R" add -A; git -C "$R" commit -q -m base; B="$(git -C "$R" rev-parse HEAD)"; }
cnt(){ grep -c "$2" "$R/$1"; }

mk; printf '\n## b\nfunc b() -> int:\n\treturn 2\n' >> "$R/t.gd"; git -C "$R" commit -qam fixup
out="$(cd "$R" && ovn_fixup_dedupe_defs "$B")"
ok "1: a byte-identical duplicate GDScript function is removed" '[ "$(cnt t.gd "^func b(")" = 1 ]'
ok "2: stdout names the file and the function" 'grep -qF "t.gd: removed duplicate(s): b" <<< "$out"'
ok "3: exactly one new commit holds the dedupe, index and tree are clean" '[ "$(git -C "$R" rev-list --count $B..HEAD)" = 2 ] && git -C "$R" diff --quiet && git -C "$R" diff --cached --quiet'
ok "4: the surviving function keeps its body" 'grep -q "return 2" "$R/t.gd"'

mk; printf '\ndef f():\n    return 1\n' >> "$R/m.py"; git -C "$R" commit -qam fixup
out="$(cd "$R" && ovn_fixup_dedupe_defs "$B")"
ok "5: a duplicated top-level Python def is removed too" '[ "$(cnt m.py "^def f(")" = 1 ]'

mk; printf '\n## b\nfunc b() -> int:\n\treturn 99\n' >> "$R/t.gd"; git -C "$R" commit -qam fixup; H="$(git -C "$R" rev-parse HEAD)"
out="$(cd "$R" && ovn_fixup_dedupe_defs "$B")"
ok "6: same name with a DIFFERENT body is left alone (never auto-resolved), nothing committed" '[ "$(cnt t.gd "^func b(")" = 2 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$H" ]'

mk; printf '\n## c\nfunc c() -> int:\n\treturn 3\n' >> "$R/t.gd"; git -C "$R" commit -qam fixup; H="$(git -C "$R" rev-parse HEAD)"
out="$(cd "$R" && ovn_fixup_dedupe_defs "$B")"
ok "7: no duplicate => no output, no commit" '[ -z "$out" ] && [ "$(git -C "$R" rev-parse HEAD)" = "$H" ]'

mk; printf '\n## b\nfunc b() -> int:\n\treturn 2\n' >> "$R/t.gd"; git -C "$R" commit -qam fixup; H="$(git -C "$R" rev-parse HEAD)"
out="$(cd "$R" && OVN_FIXUP_DEDUPE=off ovn_fixup_dedupe_defs "$B")"
ok "8: OVN_FIXUP_DEDUPE=off => untouched (the old behaviour)" '[ "$(cnt t.gd "^func b(")" = 2 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$H" ]'
out="$(cd "$R" && ovn_fixup_dedupe_defs "")"; rc=$?
ok "9: empty from-sha => rc 0 and nothing happens" '[ $rc = 0 ] && [ "$(cnt t.gd "^func b(")" = 2 ]'

mk; printf '\n## b\nfunc b() -> int:\n\treturn 2\n' >> "$R/t.gd"; git -C "$R" commit -qam fixup
printf 'def f():\n    return 1\n\ndef f():\n    return 1\n' > "$T/pre.py"
( cd "$R" && git rm -q m.py && cp "$T/pre.py" m2.py && git add m2.py && git commit -qm older )
out="$(cd "$R" && ovn_fixup_dedupe_defs "$(git -C "$R" rev-parse HEAD)")"
ok "10: only files changed in <from>..HEAD are touched (an older duplicate in an untouched range is not)" '[ "$(cnt m2.py "^def f(")" = 2 ]'

# mutant: the function as a no-op leaves the duplicate (proves test 1 depends on it)
mk; printf '\n## b\nfunc b() -> int:\n\treturn 2\n' >> "$R/t.gd"; git -C "$R" commit -qam fixup
ovn_fixup_dedupe_defs(){ return 0; }
( cd "$R" && ovn_fixup_dedupe_defs "$B" )
ok "11 MUTANT: with the pass stubbed out the duplicate survives (test 1 would fail)" '[ "$(cnt t.gd "^func b(")" = 2 ]'

echo "fixup-dedupe-defs: $P passed, $F failed"
[ "$F" -eq 0 ]
