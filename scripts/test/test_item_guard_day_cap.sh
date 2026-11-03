#!/usr/bin/env bash
# Regression test: ovn_item_guard.sh rolling 24h non-landing cap (package K3 item 2, 2026-11-01).
#
# Gap: every per-item cap counts CONSECUTIVE results of ONE kind (fail streak, no-op streak, same failing-id signature), so an item that alternates
# revert / no-op / fixup-undid-item all day never reaches any of them (gitlark's status-code item). The day cap counts ANY non-landing attempt of the item in a
# rolling 24h window (default cap 3, default mode SHADOW = log only; OVN_ITEM_DAY_CAP_MODE=enforce parks it).
# Every behaviour is also run against a MUTANT of the guard (one piece of logic broken) and must FAIL there.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"
G0="$SC/ovn_item_guard.sh"
[ -f "$G0" ] || { echo "  SKIP: $G0 not found"; exit 77; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
ITEM='- [ ] [T3] backend/app/routers/workspaces.py — conversation route status. VERIFY: pass'
mkscripts(){ # $1 dir ; $2 optional sed expression applied to the guard copy (a mutant) -> prints the guard path
  mkdir -p "$1"; for f in ovn_item_guard.sh lib_item_select.sh lib_bug_escalate.sh ovn_extract_failure.sh ovn_repeat_ids.py; do [ -f "$SC/$f" ] && cp "$SC/$f" "$1/$f"; done
  [ -n "${2:-}" ] && sed -i.bak "$2" "$1/ovn_item_guard.sh" && rm -f "$1/ovn_item_guard.sh.bak"
  echo "$1/ovn_item_guard.sh"; }
new_repo(){ local r="$tmp/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf '%s\n' "$ITEM" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ) >/dev/null 2>&1; echo "$r"; }
attempt(){ # guard repo status state id [env...]
  local g="$1" r="$2" s="$3" st="$4" id="$5"; shift 5; printf 'Tokens: 1k sent, 1 received.\n' > "$tmp/l.log"
  env OVN_ITEM_DAY_CAP=3 OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=99 OVN_REPEAT_BREAKER=off "$@" bash "$g" "$r" "$s" "$st" "$id" "$tmp/l.log" >/dev/null 2>&1; }
ledger(){ ls "$1"/item_fails/*.attempts24 2>/dev/null | head -1; }

# the real guard + one mutant per behaviour
run_suite(){ # $1 = label, $2 = guard path ; prints one line per check "NAME=0|1"
  local g="$2" t="$tmp/$1" r st
  mkdir -p "$t"
  # A shadow default: three mixed attempts, nothing parked, shadow log + one alert; 4th adds a shadow line, no 2nd alert
  r="$(new_repo "$1_A")"; st="$t/stA"; mkdir -p "$st"
  attempt "$g" "$r" "reverted(build-break)" "$st" id1; attempt "$g" "$r" "no-op(stage-unverified)" "$st" id1
  [ ! -e "$st/item_day_cap_shadow.log" ] && echo "A_under_cap_silent=1" || echo "A_under_cap_silent=0"
  attempt "$g" "$r" "reverted(test-red)" "$st" id1
  attempt "$g" "$r" "reverted(test-red)" "$st" id1
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && [ "$(wc -l < "$st/item_day_cap_shadow.log" 2>/dev/null | tr -d ' ')" = 2 ] && grep -q 'attempts24=3/3' "$st/item_day_cap_shadow.log" \
     && [ "$(grep -c 'SHADOW day-cap' "$st/alerts.log" 2>/dev/null)" = 1 ] && grep -q ' info | item-guard | ' "$st/alerts.log"; then echo "A_shadow_logs_only=1"; else echo "A_shadow_logs_only=0"; fi
  # B enforce: third mixed attempt parks, with a commit, and clears the ledger
  r="$(new_repo "$1_B")"; st="$t/stB"; mkdir -p "$st"
  attempt "$g" "$r" "reverted(build-break)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce; attempt "$g" "$r" "no-op(stage-unverified)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce
  grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && echo "C_two_attempts_not_parked=0" || echo "C_two_attempts_not_parked=1"
  attempt "$g" "$r" "reverted(build-break)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce
  if grep -q '^- \[ \] \[AUTO-SKIP after 3 non-landing attempts in 24h (1x no-op(stage-unverified), 2x reverted' "$r/OVERNIGHT_PROGRESS.md" \
     && git -C "$r" log -1 --format=%s | grep -q '^chore(queue): park item after 3 non-landing attempts in 24h' && [ -z "$(ledger "$st")" ]; then echo "B_enforce_parks=1"; else echo "B_enforce_parks=0"; fi
  # D window: two attempts older than 24h + one new -> NOT parked ; two recent + one new -> parked
  r="$(new_repo "$1_D")"; st="$t/stD"; mkdir -p "$st/item_fails"
  h="$(bash -c ". '$SC/lib_item_select.sh'; ovn_item_hash '$ITEM'")"
  old=$(( $(date +%s) - 90000 )); printf '%s reverted(x)\n%s reverted(x)\n' "$old" "$((old+10))" > "$st/item_fails/id1.$h.attempts24"
  attempt "$g" "$r" "reverted(build-break)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce
  grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && echo "D_old_attempts_expire=0" || echo "D_old_attempts_expire=1"
  new=$(( $(date +%s) - 3600 )); printf '%s reverted(x)\n%s reverted(x)\n' "$new" "$((new+10))" > "$st/item_fails/id1.$h.attempts24"
  attempt "$g" "$r" "reverted(build-break)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce
  grep -q 'AUTO-SKIP after 3 non-landing' "$r/OVERNIGHT_PROGRESS.md" && echo "D_recent_attempts_count=1" || echo "D_recent_attempts_count=0"
  # E a landing of the item clears its ledger
  r="$(new_repo "$1_E")"; st="$t/stE"; mkdir -p "$st"
  attempt "$g" "$r" "reverted(a)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce; attempt "$g" "$r" "reverted(b)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce
  printf -- '--- auto-credit: item-hash %s ---\n' "$h" > "$t/land.log"
  env OVN_ITEM_DAY_CAP_MODE=enforce bash "$g" "$r" "pushed(tests:pass)" "$st" id1 "$t/land.log" >/dev/null 2>&1
  attempt "$g" "$r" "reverted(c)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md"; then echo "E_landing_resets=1"; else echo "E_landing_resets=0"; fi
  # F benign terminal no-ops / skips are not counted
  r="$(new_repo "$1_F")"; st="$t/stF"; mkdir -p "$st"
  for s in "no-op(BLOCKED)" "no-op(ALREADY-DONE)" "no-op(NEEDS-DECISION)" "skip(idle)" "held(pause)"; do attempt "$g" "$r" "$s" "$st" id1 OVN_ITEM_DAY_CAP_MODE=enforce; done
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && [ -z "$(ledger "$st")" ]; then echo "F_benign_not_counted=1"; else echo "F_benign_not_counted=0"; fi
  # G off: no ledger at all
  r="$(new_repo "$1_G")"; st="$t/stG"; mkdir -p "$st"
  for s in a b c d; do attempt "$g" "$r" "reverted($s)" "$st" id1 OVN_ITEM_DAY_CAP_MODE=off; done
  if ! grep -q 'AUTO-SKIP' "$r/OVERNIGHT_PROGRESS.md" && [ -z "$(ledger "$st")" ]; then echo "G_off_disabled=1"; else echo "G_off_disabled=0"; fi
}

# H (K3 review fix) a schema/migration item's day cap grows with its schema fail budget (base 3 -> 5 here): 3 mixed attempts must NOT park it, the 5th must.
SITEM='- [ ] [T3] backend/alembic/versions — add migration for last_event_ms column. VERIFY: pass'
_sg="$(mkscripts "$tmp/schema_scripts")"; _sr="$tmp/schema_repo"; mkdir -p "$_sr"
( cd "$_sr" && git init -q && git config user.email t@t.com && git config user.name t && printf '%s\n' "$SITEM" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ) >/dev/null 2>&1
_sst="$tmp/schema_state"; mkdir -p "$_sst"
for s in a b c; do printf 'Tokens: 1k sent, 1 received.\n' > "$tmp/l.log"; env OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=3 OVN_REPEAT_BREAKER=off OVN_ITEM_DAY_CAP_MODE=enforce bash "$_sg" "$_sr" "reverted($s)" "$_sst" id1 "$tmp/l.log" >/dev/null 2>&1; done
ok "schema item NOT day-capped at 3 attempts (its fail budget is 5)" "! grep -q 'AUTO-SKIP' '$_sr/OVERNIGHT_PROGRESS.md'"
REAL_OUT="$(run_suite real "$(mkscripts "$tmp/real_scripts")")"
for k in A_under_cap_silent A_shadow_logs_only B_enforce_parks C_two_attempts_not_parked D_old_attempts_expire D_recent_attempts_count E_landing_resets F_benign_not_counted G_off_disabled; do
  ok "real guard: $k" "printf '%s\n' '$REAL_OUT' | grep -qx '$k=1'"
done
# mutants: (check that must flip to 0) | sed expression
mut(){ local name="$1" key="$2" expr="$3" out
  out="$(run_suite "$name" "$(mkscripts "$tmp/${name}_scripts" "$expr")")"
  ok "MUTATION caught ($name): check $key FAILS when the logic is broken" "printf '%s\n' '$out' | grep -qx '$key=0'"
  # the mutation must actually have changed the guard
  ok "mutation $name really changed the guard" "! cmp -s '$SC/ovn_item_guard.sh' '$tmp/${name}_scripts/ovn_item_guard.sh'"; }
mut m_noprune        D_old_attempts_expire 's/\$1 > lo/$1 > 0/'
mut m_countbenign    F_benign_not_counted  's/skip\*|held\*|no-op\\(BLOCKED\\)|no-op\\(ALREADY-DONE\\)|no-op\\(NEEDS-DECISION\\)) : ;;/skip*|held*) : ;;/'
mut m_shadowenforces A_shadow_logs_only    's/if \[ "\$_dc_mode" = enforce \]; then/if true; then/'
mut m_noreset        E_landing_resets      's#"\$state/item_fails/\${id}.\${_lh}.attempts24" ##'
mut m_offbyone       B_enforce_parks       's/\[ "\$_dc_n" -ge "\$_dc_cap" \]/[ "$_dc_n" -gt "$_dc_cap" ]/'
mut m_off_ignored    G_off_disabled        's/if \[ "\$_dc_mode" != off \]; then/if true; then/'
safe_rm_rf "$tmp"
echo "Item-guard day cap: $P passed, $F failed"
[ "$F" -eq 0 ]
