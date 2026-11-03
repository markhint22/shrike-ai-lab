#!/usr/bin/env bash
# 2026-11-02 (P4 / outcomes F9): the per-item rolling 24h cap (ovn_item_guard.sh) is PROGRESS-AWARE and defaults to 5 (was 3).
# Replay shapes from the 26h window (shadow log item_day_cap_shadow.log): gitlark 93bade81 (webhook rate-limit test: 6 attempts, the same edit every time, never landed) must still be
# parked; shrike-monitor e657d55c (5 attempts) and gitlark f17f4949 (4-6 attempts) LATER LANDED, so a cap of 3 would have parked wanted work. Their attempts touched different files
# each time (progress), modelled here by a distinct 'Applied edit to' set per attempt. Mutation proof: the old behaviour (OVN_ITEM_DAY_CAP=3, progress off) parks the landing items,
# and a guard copy with the progress test forced to 'stagnant' parks them at the plain cap.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; SC="$(cd "$HERE/.." && pwd)"
[ -f "$SC/ovn_item_guard.sh" ] || { echo "  SKIP: guard not found"; exit 77; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$tmp"' EXIT
ITEM='- [ ] [T3] backend/app/rate_limit_dependency.py — webhook rate-limit test. VERIFY: pass'
mkscripts(){ mkdir -p "$1"; for f in ovn_item_guard.sh lib_item_select.sh lib_bug_escalate.sh ovn_extract_failure.sh ovn_repeat_ids.py; do [ -f "$SC/$f" ] && cp "$SC/$f" "$1/$f"; done
  [ -n "${2:-}" ] && sed -i.bak "$2" "$1/ovn_item_guard.sh" && rm -f "$1/ovn_item_guard.sh.bak"; echo "$1/ovn_item_guard.sh"; }
new_repo(){ local r="$tmp/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf '%s\n' "$ITEM" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ) >/dev/null 2>&1; echo "$r"; }
# attempt <guard> <repo> <status> <state> <footprint-tag> [env...]: the task log carries the attempt's footprint (edited file + commit subject)
attempt(){ local g="$1" r="$2" s="$3" st="$4" fp="$5"; shift 5
  { echo "Tokens: 2k sent, 1 received."; [ "$fp" != none ] && { echo "Applied edit to app/f_$fp.py"; echo "Commit abc$fp fix: change $fp"; }; } > "$tmp/l.log"
  env OVN_ITEM_NOOP_CAP=99 OVN_ITEM_FAIL_CAP=99 OVN_REPEAT_BREAKER=off "$@" bash "$g" "$r" "$s" "$st" id1 "$tmp/l.log" >/dev/null 2>&1; }
parked(){ grep -q 'AUTO-SKIP after' "$1/OVERNIGHT_PROGRESS.md"; }
G="$(mkscripts "$tmp/real")"
ST=(reverted\(test-red\) no-op\(stage-unverified\) reverted\(build-break\) no-op\(test-red\) reverted\(test-red\) no-op\(no-edit\) reverted\(test-red\) no-op\(timeout\))

# S1 stuck item (same footprint every attempt, mixed statuses): parked at the cap 5 (enforce), NOT at 4
r="$(new_repo s1)"; s="$tmp/st_s1"; mkdir -p "$s"
for i in 0 1 2 3; do attempt "$G" "$r" "${ST[$i]}" "$s" same OVN_ITEM_DAY_CAP_MODE=enforce; done
ok "S1 stuck item: 4 attempts are under the new default cap (5)" "! parked '$r'"
attempt "$G" "$r" "${ST[4]}" "$s" same OVN_ITEM_DAY_CAP_MODE=enforce
ok "S1 stuck item (same footprint): parked on the 5th attempt" "parked '$r' && git -C '$r' log -1 --format=%s | grep -q 'park item after 5 non-landing'"

# S2 progressing item (e657d55c shape): 5 attempts, a different footprint each time -> NOT parked, then it lands
r="$(new_repo s2)"; s="$tmp/st_s2"; mkdir -p "$s"
for i in 0 1 2 3 4; do attempt "$G" "$r" "${ST[$i]}" "$s" "p$i" OVN_ITEM_DAY_CAP_MODE=enforce; done
ok "S2 progressing item survives 5 attempts (it later landed)" "! parked '$r'"
for i in 5 6; do attempt "$G" "$r" "${ST[$i]}" "$s" "p$i" OVN_ITEM_DAY_CAP_MODE=enforce; done
ok "S2 ... and 7 attempts (f17f4949 shape: landed after 4-6)" "! parked '$r'"
attempt "$G" "$r" "${ST[7]}" "$s" "p7" OVN_ITEM_DAY_CAP_MODE=enforce
ok "S2 the hard cap (8) parks even a changing footprint" "parked '$r' && git -C '$r' log -1 --format=%s | grep -q 'park item after 8 non-landing'"

# S3 an attempt that stalls AFTER progress is caught at the next cap-crossing: p0..p3 then two identical
r="$(new_repo s3)"; s="$tmp/st_s3"; mkdir -p "$s"
for i in 0 1 2 3; do attempt "$G" "$r" "${ST[$i]}" "$s" "p$i" OVN_ITEM_DAY_CAP_MODE=enforce; done
attempt "$G" "$r" "${ST[4]}" "$s" "p3" OVN_ITEM_DAY_CAP_MODE=enforce
ok "S3 5th attempt repeats the 4th footprint => stagnant => parked" "parked '$r'"

# S4 default mode stays SHADOW: stuck item is logged with stagnant=1 and never parked
r="$(new_repo s4)"; s="$tmp/st_s4"; mkdir -p "$s"
for i in 0 1 2 3 4 5; do attempt "$G" "$r" "${ST[$i]}" "$s" same; done
ok "S4 shadow default: nothing parked" "! parked '$r'"
ok "S4 shadow log rows carry stagnant=1 and attempts24=N/5" "grep -q 'attempts24=5/5 .*stagnant=1' '$s/item_day_cap_shadow.log'"
ok "S4 exactly ONE shadow alert per crossing (not one per extra attempt)" "[ \"\$(grep -c 'SHADOW day-cap' '$s/alerts.log')\" = 1 ]"
r="$(new_repo s5)"; s="$tmp/st_s5"; mkdir -p "$s"
for i in 0 1 2 3 4; do attempt "$G" "$r" "${ST[$i]}" "$s" "p$i"; done
ok "S5 shadow: a progressing item has NO would-park row" "[ ! -s '$s/item_day_cap_shadow.log' ]"

# MUTANTS (old behaviour): the replay of the later-landing item is parked
r="$(new_repo m1)"; s="$tmp/st_m1"; mkdir -p "$s"
for i in 0 1 2; do attempt "$G" "$r" "${ST[$i]}" "$s" "p$i" OVN_ITEM_DAY_CAP_MODE=enforce OVN_ITEM_DAY_CAP=3 OVN_ITEM_DAY_CAP_PROGRESS=off; done
ok "M1 MUTANT old behaviour (cap 3, progress off) parks the progressing item after 3 attempts" "parked '$r'"
MG="$(mkscripts "$tmp/mut" 's/_dc_stag=0; fi/_dc_stag=1; fi/')"
ok "M2 mutant copy really differs" "! cmp -s '$SC/ovn_item_guard.sh' '$MG'"
r="$(new_repo m2)"; s="$tmp/st_m2"; mkdir -p "$s"
for i in 0 1 2 3 4; do attempt "$MG" "$r" "${ST[$i]}" "$s" "p$i" OVN_ITEM_DAY_CAP_MODE=enforce; done
ok "M2 MUTANT (progress test forced to stagnant) parks the progressing item at the plain cap" "parked '$r'"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
