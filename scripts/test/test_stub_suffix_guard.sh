#!/usr/bin/env bash
# test_stub_suffix_guard.sh - P3(a): ovn_stub_guard.py refuses to stub 'tests/t.py' when 'backend/tests/t.py' is tracked
# (gitlark/iptv 2026-10-21: 11+2 stub-and-drop commit pairs). Directory-boundary suffix only; a bare-basename case still works.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
G="${OVN_STUB_GUARD:-$HERE/../ovn_stub_guard.py}"
P=0; F=0
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0
pick(){ printf '%s' "$2" | timeout 60 python3 "$G" pick "$1" | tr '\t' '|'; }
R="$W/repo"; mkdir -p "$R/backend/tests" "$R/backend/app" "$R/iptv-web/src/stores" "$R/pkg/mytests" && cd "$R" || exit 1
git init -q -b main .
echo x > backend/tests/t.py; echo x > backend/tests/test_utils.py; echo x > iptv-web/src/stores/recordings.test.ts; echo x > pkg/mytests/z.py
git add -A && git commit -q -m base
eq "suffix: tests/t.py with backend/tests/t.py tracked -> SKIP" "$(pick "$R" '[T3] tests/t.py - add coverage')" "SKIP|suffix-of-existing:backend/tests/t.py|tests/t.py"
eq "suffix: stores/recordings.test.ts under iptv-web/src -> SKIP" "$(pick "$R" '[T3] src/stores/recordings.test.ts - add')" "SKIP|suffix-of-existing:iptv-web/src/stores/recordings.test.ts|src/stores/recordings.test.ts"
eq "BENIGN: no directory boundary (tests/z.py vs pkg/mytests/z.py) still PICKs" "$(pick "$R" '[T3] tests/z.py - new')" "PICK|tests/z.py"
eq "BENIGN: genuinely new path PICKs" "$(pick "$R" '[T3] backend/tests/test_new.py - new')" "PICK|backend/tests/test_new.py"
eq "BENIGN: common name in a new dir path (app/test_utils.py) PICKs" "$(pick "$R" '[T3] app/test_utils.py - new')" "PICK|app/test_utils.py"
eq "bare basename still refused" "$(pick "$R" '[T3] t.py - mention')" "SKIP|bare-basename:backend/tests/t.py|t.py"
eq "env switch off disables suffix guard" "$(OVN_STUB_SUFFIX_GUARD=off pick "$R" '[T3] tests/t.py - add')" "PICK|tests/t.py"
# --- review fixes (2026-10-22): ambiguous / explicit-create must not doom a real new file ---
mkdir -p "$R/admin/src/stores" && echo x > "$R/admin/src/stores/recordings.test.ts" && git add -A && git commit -q -m amb
eq "ambiguous: two tracked suffix matches -> PICK (cannot tell which is meant)" "$(pick "$R" '[T3] src/stores/recordings.test.ts - add')" "PICK|src/stores/recordings.test.ts"
eq "explicit create verb -> PICK even with one suffix match" "$(pick "$R" '[T3] create tests/t.py - new top-level tests')" "PICK|tests/t.py"
echo "test_stub_suffix_guard: pass=$P fail=$F"
[ "$F" = 0 ]
