#!/usr/bin/env bash
# Wave-3: ovn_item_guard.sh with lib_item_select.sh ABSENT (guard copied alone into a temp dir): exercises the built-in
# fallbacks for top-item selection and item hashing (feat-tag keyed with date-strip, and plain text md5).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
G="$HERE/../ovn_item_guard.sh"; [ -f "$G" ] || G="$HERE/../scripts/ovn_item_guard.sh"
[ -f "$G" ] || { echo "  SKIP: guard not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/iso"; cp "$G" "$tmp/iso/ovn_item_guard.sh"; GG="$tmp/iso/ovn_item_guard.sh"
md5(){ printf '%s' "$1" | md5sum | cut -d' ' -f1; }
new_repo(){ local r="$tmp/$1"; mkdir -p "$r"; printf '%s\n' "${@:2}" > "$r/OVERNIGHT_PROGRESS.md"; echo "$r"; }

echo "== feat-tagged top item: streak keyed on the date-stripped feat tag"
r="$(new_repo a '- [ ] [T1] x/a.py — blocked one. [AUTO-SKIP after 9 cycles]' '- [ ] [CLAUDE] [T1] x/c.py — escalated. VERIFY: t' '- [ ] [T2] x/b.py — real top. VERIFY: t [feat:repo-20260901-big-thing]')"
st="$tmp/sa"; mkdir -p "$st"
OVN_ITEM_FAIL_CAP=3 bash "$GG" "$r" "reverted(build-break)" "$st" idA "" >/dev/null 2>&1
h="$(md5 '[feat:repo-big-thing]')"
ok "counter file keyed by md5 of the date-stripped feat tag" "[ -f '$st/item_fails/idA.$h.count' ] && [ \"\$(cat '$st/item_fails/idA.$h.count')\" = 1 ]"
ok "AUTO-SKIP and [CLAUDE] lines were skipped when picking the top item (nothing tagged yet)" "! grep -q 'AUTO-SKIP after 1 ' '$r/OVERNIGHT_PROGRESS.md'"
ok "a different date on the same feat tag continues the SAME streak" "sed -i 's/20260901/20260915/' '$r/OVERNIGHT_PROGRESS.md'; OVN_ITEM_FAIL_CAP=3 bash '$GG' '$r' 'reverted(build-break)' '$st' idA '' >/dev/null 2>&1; [ \"\$(cat '$st/item_fails/idA.$h.count')\" = 2 ]"
OVN_ITEM_FAIL_CAP=3 bash "$GG" "$r" "reverted(build-break)" "$st" idA "" >/dev/null 2>&1
ok "third failure trips the cap and tags the real top line" "grep -q 'AUTO-SKIP after 3' '$r/OVERNIGHT_PROGRESS.md' && grep 'x/b.py' '$r/OVERNIGHT_PROGRESS.md' | grep -q AUTO-SKIP"

echo "== plain top item: streak keyed on md5 of the whole line text"
t='- [ ] [T2] y/p.py — plain item. VERIFY: t'
r="$(new_repo b "$t")"
st="$tmp/sb"; mkdir -p "$st"
OVN_ITEM_FAIL_CAP=3 bash "$GG" "$r" "reverted(build-break)" "$st" idB "" >/dev/null 2>&1
h="$(md5 "${t}")"
ok "counter keyed by md5 of the item text" "ls '$st/item_fails/' | grep -q '^idB\.' && [ \"\$(cat '$st/item_fails/idB.$h.count' 2>/dev/null)\" = 1 ]"

echo "== landing clears counters for hashes named in the task log"
mkdir -p "$st/item_fails"; touch "$st/item_fails/idB.0123456789abcdef0123456789abcdef.count" "$st/item_fails/idB.0123456789abcdef0123456789abcdef.lastfail"
echo "item-hash 0123456789abcdef0123456789abcdef landed" > "$tmp/landed.log"
bash "$GG" "$r" "tests:pass" "$st" idB "$tmp/landed.log" >/dev/null 2>&1
ok "named hash counters removed (incl. lastfail)" "[ ! -e '$st/item_fails/idB.0123456789abcdef0123456789abcdef.count' ] && [ ! -e '$st/item_fails/idB.0123456789abcdef0123456789abcdef.lastfail' ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
