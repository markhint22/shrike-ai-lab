#!/usr/bin/env bash
# Regression test: ovn_item_guard.sh repeat-revert park (package S3-guards2, 2026-11-03, outcomes F6).
#
# Gap: xlite item 23b23306 (T3 wiring item + its paired T4 test item, one [feat:] tag) was reverted 3x in 14h (reverted-red, reverted(build-break), no-op(reverted-red)); the progress-aware
# day cap and the fail streak never tripped, so ~3 GPU cycles ran for zero landing. The repeat-revert counter counts REVERTS of the same item hash in a rolling 24h window; at
# OVN_REVERT_REPEAT_N (default 2) it parks the item AND its open siblings of the same [feat:] tag. OVN_REVERT_REPEAT_MODE default shadow = log only; enforce parks; off = disabled.
# Every behaviour is also run against a MUTANT of the guard (one piece of logic broken) and must FAIL there.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"
[ -f "$SC/ovn_item_guard.sh" ] || { echo "  SKIP: guard not found"; exit 77; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# the real shape: T3 wiring item + paired T4 test item share the feature tag; a third item belongs to another feature
T3='- [ ] [T3] scripts/mission/mission_data.gd — wire the validators into is_valid(). VERIFY: pass (cat:godot) [feat:xlite-20261101-wire-the-bounds-and-obstacle-validators-]'
T4='- [ ] [T4] tests/test_mission_data.gd — add test_is_valid_uses_validators. VERIFY: pass (cat:godot) [feat:xlite-20261101-wire-the-bounds-and-obstacle-validators-]'
OTHER='- [ ] [T3] scripts/other.gd — unrelated work. VERIFY: pass (cat:godot) [feat:xlite-20261101-unrelated-feature-]'
mkscripts(){ mkdir -p "$1"; for f in ovn_item_guard.sh lib_item_select.sh lib_bug_escalate.sh ovn_extract_failure.sh ovn_repeat_ids.py; do [ -f "$SC/$f" ] && cp "$SC/$f" "$1/$f"; done
  [ -n "${2:-}" ] && sed -i.bak "$2" "$1/ovn_item_guard.sh" && rm -f "$1/ovn_item_guard.sh.bak"; echo "$1/ovn_item_guard.sh"; }
new_repo(){ local r="$tmp/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf '%s\n%s\n%s\n' "$T3" "$T4" "$OTHER" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ) >/dev/null 2>&1; echo "$r"; }
attempt(){ local g="$1" r="$2" s="$3" st="$4" id="$5"; shift 5; printf 'Tokens: 1k sent, 1 received.\n' > "$tmp/l.log"
  env OVN_ITEM_DAY_CAP_MODE=off OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=99 OVN_ITEM_TOKEN_CAP=99999999 OVN_REPEAT_BREAKER=off "$@" bash "$g" "$r" "$s" "$st" "$id" "$tmp/l.log" >/dev/null 2>&1; }
H3="$(bash -c ". '$SC/lib_item_select.sh'; ovn_item_hash '$T3'")"

run_suite(){ local g="$2" t="$tmp/$1" r st
  mkdir -p "$t"
  # A shadow default: first revert silent; second revert logs one shadow row; nothing is parked
  r="$(new_repo "$1_A")"; st="$t/stA"; mkdir -p "$st"
  attempt "$g" "$r" "reverted(test-red)" "$st" id1
  [ ! -e "$st/revert_repeat_shadow.log" ] && echo "A_first_revert_silent=1" || echo "A_first_revert_silent=0"
  attempt "$g" "$r" "no-op(reverted-red)" "$st" id1
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && [ "$(wc -l < "$st/revert_repeat_shadow.log" 2>/dev/null | tr -d ' ')" = 1 ] && grep -q 'reverts24=2/2' "$st/revert_repeat_shadow.log"; then echo "A_shadow_logs_only=1"; else echo "A_shadow_logs_only=0"; fi
  # B enforce: second revert parks the item AND its paired T4 sibling (same feat tag), not the unrelated feature; commit made; ledger cleared
  r="$(new_repo "$1_B")"; st="$t/stB"; mkdir -p "$st"
  attempt "$g" "$r" "reverted(build-break)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce
  grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && echo "C_one_revert_not_parked=0" || echo "C_one_revert_not_parked=1"
  attempt "$g" "$r" "no-op(reverted-red)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce
  if [ "$(grep -c '^- \[ \] \[AUTO-SKIP reverted 2x in 24h' "$r/OVERNIGHT_PROGRESS.md")" = 2 ] && grep -q '^- \[ \] \[T3\] scripts/other.gd' "$r/OVERNIGHT_PROGRESS.md" \
     && git -C "$r" log -1 --format=%s | grep -q '^chore(queue): park 2 item(s) after 2 reverts' && [ ! -e "$st/item_fails/id1.$H3.reverts24" ]; then echo "B_enforce_parks_pair=1"; else echo "B_enforce_parks_pair=0"; fi
  # D window: two old reverts expired + one new -> not parked ; one recent + one new -> parked
  r="$(new_repo "$1_D")"; st="$t/stD"; mkdir -p "$st/item_fails"
  old=$(( $(date +%s) - 90000 )); printf '%s\n%s\n' "$old" "$((old+10))" > "$st/item_fails/id1.$H3.reverts24"
  attempt "$g" "$r" "reverted(x)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce
  grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && echo "D_old_reverts_expire=0" || echo "D_old_reverts_expire=1"
  new=$(( $(date +%s) - 3600 )); printf '%s\n' "$new" > "$st/item_fails/id1.$H3.reverts24"
  attempt "$g" "$r" "reverted(x)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce
  grep -q 'AUTO-SKIP reverted 2x' "$r/OVERNIGHT_PROGRESS.md" && echo "D_recent_reverts_count=1" || echo "D_recent_reverts_count=0"
  # E a landing of the item clears its ledger
  r="$(new_repo "$1_E")"; st="$t/stE"; mkdir -p "$st"
  attempt "$g" "$r" "reverted(a)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce
  printf -- '--- auto-credit: item-hash %s ---\n' "$H3" > "$t/land.log"
  env OVN_REVERT_REPEAT_MODE=enforce bash "$g" "$r" "pushed(tests:pass)" "$st" id1 "$t/land.log" >/dev/null 2>&1
  attempt "$g" "$r" "reverted(b)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md"; then echo "E_landing_resets=1"; else echo "E_landing_resets=0"; fi
  # F only reverts count: no-ops that are not reverts and plain failures never trip it
  r="$(new_repo "$1_F")"; st="$t/stF"; mkdir -p "$st"
  for s in "no-op(stage-unverified)" "no-op(BLOCKED)" "skip(idle)" "no-op(fixup-undid-item)"; do attempt "$g" "$r" "$s" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce; done
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && [ ! -e "$st/item_fails/id1.$H3.reverts24" ]; then echo "F_non_reverts_not_counted=1"; else echo "F_non_reverts_not_counted=0"; fi
  # G off: no ledger at all
  r="$(new_repo "$1_G")"; st="$t/stG"; mkdir -p "$st"
  for s in a b c; do attempt "$g" "$r" "reverted($s)" "$st" id1 OVN_REVERT_REPEAT_MODE=off; done
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && [ ! -e "$st/item_fails/id1.$H3.reverts24" ]; then echo "G_off_disabled=1"; else echo "G_off_disabled=0"; fi
  # H an item without a feat tag parks only itself
  r="$tmp/$1_H"; mkdir -p "$r"; st="$t/stH"; mkdir -p "$st"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf '%s\n%s\n' '- [ ] [T3] a.py — lone item. VERIFY: pass' "$OTHER" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ) >/dev/null 2>&1
  attempt "$g" "$r" "reverted(a)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce; attempt "$g" "$r" "reverted(b)" "$st" id1 OVN_REVERT_REPEAT_MODE=enforce
  if [ "$(grep -c 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md")" = 1 ] && grep -q 'AUTO-SKIP reverted 2x.*lone item' "$r/OVERNIGHT_PROGRESS.md"; then echo "H_untagged_parks_only_itself=1"; else echo "H_untagged_parks_only_itself=0"; fi
}

REAL_OUT="$(run_suite real "$(mkscripts "$tmp/real_scripts")")"
for k in A_first_revert_silent A_shadow_logs_only B_enforce_parks_pair C_one_revert_not_parked D_old_reverts_expire D_recent_reverts_count E_landing_resets F_non_reverts_not_counted G_off_disabled H_untagged_parks_only_itself; do
  ok "real guard: $k" "printf '%s\n' '$REAL_OUT' | grep -qx '$k=1'"
done
mut(){ local name="$1" key="$2" expr="$3" out
  out="$(run_suite "$name" "$(mkscripts "$tmp/${name}_scripts" "$expr")")"
  ok "MUTATION caught ($name): check $key FAILS when the logic is broken" "printf '%s\n' '$out' | grep -qx '$key=0'"
  ok "mutation $name really changed the guard" "! cmp -s '$SC/ovn_item_guard.sh' '$tmp/${name}_scripts/ovn_item_guard.sh'"; }
mut m_noprune     D_old_reverts_expire         's/\$1 > lo {print \$1}/$1 > 0 {print $1}/'
mut m_countall    F_non_reverts_not_counted    's/^    reverted\*|"no-op(reverted"\*)$/    *)/'
mut m_shadowparks A_shadow_logs_only           's/if \[ "\$_rr_mode" = enforce \]; then/if true; then/'
mut m_siblings    B_enforce_parks_pair         's/if body.strip() == cur or (feat and feat in body):/if body.strip() == cur:/'
mut m_noreset     E_landing_resets             's# "\$state/item_fails/\${id}.\${_lh}.reverts24"##'
mut m_offbyone    C_one_revert_not_parked      's/\[ "\$_rr_c" -ge "\$_rr_n" \]/[ "$_rr_c" -ge 1 ]/'
mut m_offignored  G_off_disabled               's/if \[ "\$_rr_mode" != off \]; then/if true; then/'
safe_rm_rf "$tmp"
echo "Item-guard repeat-revert: $P passed, $F failed"
[ "$F" -eq 0 ]
