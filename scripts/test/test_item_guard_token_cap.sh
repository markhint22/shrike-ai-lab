#!/usr/bin/env bash
# Regression test: ovn_item_guard.sh must trip on cumulative TOKEN spend, not just cycle count
# (2026-09-10).
#
# Real gap this closes: the existing per-item fail/no-op cycle caps (CAP=3, NCAP=4) assume every
# cycle costs about the same. A T4/T5 item's decomposed multi-step attempt can burn 5-10x what a
# T1 one-shot does, so a genuinely stuck expensive item could thrash through several times the
# token spend of a cheap one before either cycle cap ever trips. This tracks cumulative tokens
# per item streak (same hash-based reset semantics as the existing cycle counters) and trips on
# whichever limit — cycles or tokens — is hit first.
set -uo pipefail
G="${OVN_ITEM_GUARD:-$HOME/overnight-queue/scripts/ovn_item_guard.sh}"
[ -f "$G" ] || { echo "  SKIP: $G not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
mklog(){ printf 'Tokens: %sk sent, 100 received.\n' "$1" > "$tmp/log_$2_$3.log"; echo "$tmp/log_$2_$3.log"; }

new_repo(){  # $1=name $2=item-line
  local r="$tmp/$1"; mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t \
    && printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
  echo "$r"
}

# --- A: normal low-token no-ops still trip on cycle count (NCAP), unaffected by this change ---
r="$(new_repo repoA '- [ ] [T4] scripts/foo.gd — thing. VERIFY: pass')"
st="$tmp/stateA"; mkdir -p "$st"
for i in 1 2 3 4; do
  l="$(mklog 5 A "$i")"
  OVN_ITEM_NOOP_CAP=4 OVN_ITEM_TOKEN_CAP=200000 bash "$G" "$r" "no-op(BLOCKED)" "$st" itemA "$l" >/dev/null
done
ok "low-token item still trips on cycle count (unaffected by token cap)" \
   "grep -q 'AUTO-SKIP after 4 no-op cycles' '$r/OVERNIGHT_PROGRESS.md'"

# --- B: an expensive item (80k/cycle) trips on TOKENS before reaching NCAP=4 ---
r="$(new_repo repoB '- [ ] [T4] scripts/foo.gd — thing. VERIFY: pass')"
st="$tmp/stateB"; mkdir -p "$st"
for i in 1 2 3; do
  l="$(mklog 80 B "$i")"
  OVN_ITEM_NOOP_CAP=4 OVN_ITEM_TOKEN_CAP=200000 bash "$G" "$r" "no-op(stage-unverified)" "$st" itemB "$l" >/dev/null
done
ok "expensive item trips on token spend before the cycle cap" \
   "grep -q 'AUTO-SKIP after 240000 tokens with no landing' '$r/OVERNIGHT_PROGRESS.md'"
ok "token-triggered message reports the actual (lower) cycle count too" \
   "grep -q 'only 3/4 cycles' '$r/OVERNIGHT_PROGRESS.md'"

# --- C: the fail streak (reverted) path also respects the token cap ---
r="$(new_repo repoC '- [ ] [T5] scripts/hard.gd — thing. VERIFY: pass')"
st="$tmp/stateC"; mkdir -p "$st"
for i in 1 2; do
  l="$(mklog 110 C "$i")"
  OVN_ITEM_FAIL_CAP=3 OVN_ITEM_TOKEN_CAP=200000 bash "$G" "$r" "reverted(build-break)" "$st" itemC "$l" >/dev/null
done
ok "fail streak trips on token spend before the cycle cap" \
   "grep -q 'AUTO-SKIP after 220000 tokens with no landing' '$r/OVERNIGHT_PROGRESS.md'"

# --- D: a landing clears the new token counter files, not just the old hash/count ones ---
r="$(new_repo repoD '- [ ] [T3] scripts/x.gd — thing. VERIFY: pass')"
st="$tmp/stateD"; mkdir -p "$st"
l="$(mklog 50 D 1)"
bash "$G" "$r" "no-op" "$st" itemD "$l" >/dev/null
ok "a no-op writes a nooptoks counter file" "[ -f '$st/item_fails/itemD.nooptoks' ]"
bash "$G" "$r" "pushed(tests:pass)" "$st" itemD "$l" >/dev/null
ok "landing clears the nooptoks counter file too" "[ ! -f '$st/item_fails/itemD.nooptoks' ]"

rm -rf "$tmp"
echo "Item-guard token cap: $P passed, $F failed"
[ "$F" -eq 0 ]
