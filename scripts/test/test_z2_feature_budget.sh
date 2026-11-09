#!/usr/bin/env bash
# Z2 (2026-11-07, bugfix): ovn_item_guard.sh feature-level token budget. An item parked for 'tokens with no landing' used to reset its tally (rm toksf) and its recovery-decomposition CHILDREN
# (new text = new hash) each started a fresh 200k budget: nov7 iptv discover rate-limit test, parent AUTO-SKIPped at 206k, 3 children burned 737k more with no landing. The parked spend now goes into a
# per-LINEAGE ledger (same [feat:] tag, or a recovery child named by its '# --- recovered from a parked item' header; + the file, NOT the bare file) that later items of the lineage inherit. OVN_FEATURE_TOKEN_INHERIT: off = old behaviour, shadow (DEFAULT) = log would_park_inherited only, on = enforce. Mutants: the same suite run against edited copies of the guard.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
G0="$HERE/../ovn_item_guard.sh"; [ -f "$G0" ] || G0="$HERE/../../ovn_item_guard.sh"
[ -f "$G0" ] || { echo "  SKIP: ovn_item_guard.sh not found"; exit 0; }
command -v md5sum >/dev/null 2>&1 || { echo "  SKIP: needs md5sum"; exit 0; }
tmp="$(safe_mktemp_dir)" || exit 1
trap 'rm -rf "${tmp:?}"' EXIT
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
mklog(){ printf 'Tokens: %sk sent, 100 received.\n' "$1" > "$tmp/log_$2_$3.log"; echo "$tmp/log_$2_$3.log"; }
new_repo(){ local r="$tmp/$1"; mkdir -p "$r"; ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t && printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ); echo "$r"; }
. "$HERE/../lib_item_select.sh" 2>/dev/null
PARENT='- [ ] [T3] app/routers/discover.py — rate limit the discover endpoint with a test. VERIFY: pytest tests/test_discover_rl.py'
# the header exactly as ovn_recover_parked.sh writes it: '[date ph:<md5 of the FULL parent text>]: <first 70 chars> (review) ---' (the hash function is extracted from the tool itself)
eval "$(sed -n '/^# >>> z2 parent-hash/,/^# <<< z2 parent-hash/p' "$HERE/../../ovn_recover_parked.sh")"
mkhdr(){ local t="${1#- \[ \] }"; printf '# --- recovered from a parked item [2026-11-07 ph:%s]: %s (review) ---' "$(_ovn_parent_hash "$t")" "${t:0:70}"; }
HDR="$(mkhdr "$PARENT")"
CHILD_A='- [ ] [T3] app/routers/discover.py — decomposed: add the limiter dependency. VERIFY: pytest tests/test_discover_rl.py::a (cat:python; recovery:decomposed)'
CHILD_OTHER='- [ ] [T3] app/routers/other.py — unrelated item. VERIFY: pytest tests/test_other.py'
UNREL='- [ ] [T3] app/routers/discover.py — add an unrelated sort param. VERIFY: pytest tests/test_sort.py'
OTHERPARENT_HDR="$(mkhdr '[T3] app/routers/discover.py — a completely different parent item')"
CHILD_B='- [ ] [T3] app/routers/discover.py — decomposed: child of a DIFFERENT parent. VERIFY: pytest tests/test_x.py (cat:python; recovery:decomposed)'
FEAT1='- [ ] [T3] app/routers/streams.py — feature one step. VERIFY: pytest tests/test_s1.py [feat:iptv-20261101-aaaa1111]'
FEAT2='- [ ] [T3] app/routers/streams.py — other feature. VERIFY: pytest tests/test_s2.py [feat:iptv-20261101-bbbb2222]'
FEAT1B='- [ ] [T3] app/routers/streams.py — feature one second step. VERIFY: pytest tests/test_s1b.py [feat:iptv-20261107-aaaa1111]'
RUN(){ OVN_ITEM_FAIL_CAP=3 OVN_ITEM_NOOP_CAP=4 OVN_ITEM_TOKEN_CAP=200000 bash "$@" >/dev/null 2>&1; }
setchild(){ printf '%s\n\n%s\n%s\n' "$(head -1 "$1")" "$2" "$3" > "$1"; }   # $1 progress file, $2 header, $3 child line
park_parent(){ local i l; for i in 1 2; do l="$(mklog 110 "$4" "p$i")"; RUN "$1" "$2" "reverted(build-break)" "$3" ongoing-x "$l"; done; }   # guard repo state label
led1(){ ls "$1"/item_fails/ongoing-x.lineage.*.toks 2>/dev/null | head -1; }
# Z5-D: `touch -t` reads the stamp as LOCAL time, so the stamp must be local too (the old `date -u` made the ledger 17h old on the CST box and G2 failed every run there)
old_ts(){ date -d '23 hours ago' +%Y%m%d%H%M 2>/dev/null || date -v-23H +%Y%m%d%H%M; }

suite(){   # $1=guard path  $2=label ; asserts the NEW behaviour in ENFORCING mode (OVN_FEATURE_TOKEN_INHERIT=on)
  local G="$1" L="$2" r r2 st l led ll ph ch
  export OVN_FEATURE_TOKEN_INHERIT=on
  # A: parent parked by tokens (2 x 110k) -> its recovery children inherit
  r="$(new_repo "${L}A" "$PARENT")"; st="$tmp/st${L}A"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}A"
  ok "$L A1 the parent is parked for tokens" "grep -q 'AUTO-SKIP after 220000 tokens with no landing' '$r/OVERNIGHT_PROGRESS.md'"
  ok "$L A2 a lineage ledger with the spent tokens exists (line 1)" "[ \"\$(sed -n 1p \$(ls '$st'/item_fails/ongoing-x.lineage.*.toks | head -1))\" = 220000 ]"
  setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
  l="$(mklog 60 "${L}A" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L A3 the recovery child (60k of its own) is parked after its FIRST failed cycle (inherited budget, capped at 200k)" "grep -q 'AUTO-SKIP after 260000 tokens with no landing (feature budget: 200000 inherited' '$r/OVERNIGHT_PROGRESS.md'"
  ok "$L A4 ... on the feature budget, not a cycle count" "! grep -q 'failed-to-land cycles' '$r/OVERNIGHT_PROGRESS.md'"
  # B: unrelated items must NOT inherit
  r="$(new_repo "${L}B" "$CHILD_OTHER")"
  l="$(mklog 60 "${L}B" 1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L B1 an unrelated FILE's item is not charged the other lineage's spend" "! grep -q 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md'"
  r="$(new_repo "${L}B2" "$UNREL")"
  l="$(mklog 1 "${L}B2" 1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L B2 an UNRELATED item on the SAME file (no shared feat, no recovery header) is NOT parked" "! grep -q 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md'"
  r="$(new_repo "${L}B3" "$CHILD_A")"; setchild "$r/OVERNIGHT_PROGRESS.md" "$OTHERPARENT_HDR" "$CHILD_B"
  l="$(mklog 1 "${L}B3" 1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L B3 a recovery child of a DIFFERENT parent on the same file is NOT parked" "! grep -q 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md'"
  # F: feat lineage: same feat tag (date stripped) shares; a different feat tag on the same file does not
  r="$(new_repo "${L}F" "$FEAT1")"; st="$tmp/st${L}F"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}F"
  ok "$L F0 the feat item is parked for tokens" "grep -q 'AUTO-SKIP after 220000 tokens' '$r/OVERNIGHT_PROGRESS.md'"
  r2="$(new_repo "${L}F1" "$FEAT2")"
  l="$(mklog 1 "${L}F" d1)"; RUN "$G" "$r2" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L F1 same file, DIFFERENT feat lineage: NOT parked" "! grep -q 'AUTO-SKIP' '$r2/OVERNIGHT_PROGRESS.md'"
  # C: no-op path inherits too
  r="$(new_repo "${L}C" "$PARENT")"; st="$tmp/st${L}C"; mkdir -p "$st"
  for i in 1 2; do l="$(mklog 110 "${L}C" "$i")"; RUN "$G" "$r" "no-op(stage-unverified)" "$st" ongoing-x "$l"; done
  setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
  l="$(mklog 20 "${L}C" c1)"; RUN "$G" "$r" "no-op(stage-unverified)" "$st" ongoing-x "$l"
  ok "$L C1 the no-op streak of a recovery child inherits the parked parent's spend as well" "grep -q 'AUTO-SKIP after 220000 tokens with no landing (feature budget' '$r/OVERNIGHT_PROGRESS.md'"
  # D: a cycle-count park (cheap) leaves NO ledger
  r="$(new_repo "${L}D" "$PARENT")"; st="$tmp/st${L}D"; mkdir -p "$st"
  for i in 1 2 3; do l="$(mklog 5 "${L}D" "$i")"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"; done
  ok "$L D1 parked by cycles -> no inherited ledger" "! ls '$st'/item_fails/ongoing-x.lineage.*.toks"
  # E: expiry (TTL) and landing clears
  r="$(new_repo "${L}E" "$PARENT")"; st="$tmp/st${L}E"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}E"
  led="$(led1 "$st")"
  setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
  touch -t 202001010000 "$led"
  l="$(mklog 60 "${L}E" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L E1 an expired (>24h) ledger is ignored: the child is NOT parked after one 60k cycle" "! grep -q 'feature budget' '$r/OVERNIGHT_PROGRESS.md' && ! grep -q 'AUTO-SKIP after 260000' '$r/OVERNIGHT_PROGRESS.md'"
  ok "$L E2 ... and the expired ledger file is removed" "[ ! -f '$led' ]"
  printf '220000\n' > "$led"
  ll="$tmp/land_${L}.log"; { printf 'stage-item-line %s\n' "${CHILD_A#- \[ \] }"; } > "$ll"
  RUN "$G" "$r" "pushed(tests:pass) stage(higher-tier)" "$st" ongoing-x "$ll"
  ok "$L E3 a staged landing of an item of the lineage clears the ledger" "[ ! -f '$led' ]"
  r="$(new_repo "${L}E4" "$PARENT")"; st="$tmp/st${L}E4"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}E4"
  ph="$(ovn_item_hash "$PARENT")"; echo "--- auto-credit: item-hash $ph ---" > "$tmp/aland_${L}.log"
  RUN "$G" "$r" "pushed(tests:pass)" "$st" ongoing-x "$tmp/aland_${L}.log"
  ok "$L E4 an aider-path landing (item-hash marker only) of an item of the lineage clears the ledger" "! ls '$st'/item_fails/ongoing-x.lineage.*.toks"
  r="$(new_repo "${L}E5" "$PARENT")"; st="$tmp/st${L}E5"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}E5"
  setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
  l="$(mklog 1 "${L}E5" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"   # registers the child hash as a member of the ledger
  ch="$(ovn_item_hash "$CHILD_A")"; echo "--- auto-credit: item-hash $ch ---" > "$tmp/aland5_${L}.log"
  RUN "$G" "$r" "pushed(tests:pass)" "$st" ongoing-x "$tmp/aland5_${L}.log"
  ok "$L E5 an aider-path landing of a recorded CHILD clears the lineage ledgers too" "! ls '$st'/item_fails/ongoing-x.lineage.*.toks"
  # R2-1: two UNRELATED parents on one file whose first 40 chars are identical ("[T3] app/routers/discover.py — " + ...): the 2nd parent's recovery child must NOT inherit the 1st's spend
  r="$(new_repo "${L}K" "$PARENT")"; st="$tmp/st${L}K"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}K"
  P2='- [ ] [T3] app/routers/discover.py — rate limit the DOWNLOADS endpoint with a different test. VERIFY: pytest tests/test_dl.py'
  ok "$L K0 the two parents share their first 40 chars (test premise)" "[ \"\$(printf '%s' '${PARENT#- \[ \] }' | cut -c1-40)\" = \"\$(printf '%s' '${P2#- \[ \] }' | cut -c1-40)\" ]"
  setchild "$r/OVERNIGHT_PROGRESS.md" "$(mkhdr "$P2")" "$CHILD_B"
  l="$(mklog 1 "${L}K" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L K1 a recovery child of the unrelated 2nd parent does NOT inherit the 1st parent's spend (not parked)" "! grep -q 'feature budget' '$r/OVERNIGHT_PROGRESS.md' && ! grep -q 'AUTO-SKIP after 2[0-9]*000 tokens with no landing (feature' '$r/OVERNIGHT_PROGRESS.md'"
  setchild "$r/OVERNIGHT_PROGRESS.md" "$(mkhdr "$PARENT")" "$CHILD_B"
  l="$(mklog 1 "${L}K" c2)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L K2 ... while a child carrying the FIRST parent's header still inherits (the lineage link is kept)" "grep -q 'feature budget: 200000 inherited' '$r/OVERNIGHT_PROGRESS.md'"
  r2="$(new_repo "${L}K3" "$P2")"; st="$tmp/st${L}K3"; mkdir -p "$st"
  park_parent "$G" "$r2" "$st" "${L}K3"
  ok "$L K3 two parents' ledgers are distinct files: the 1st parent's ledger still holds its own 220000 and the 2nd parent has its own" "[ \"\$(sed -n 1p '$tmp/st${L}K'/item_fails/ongoing-x.lineage.txt-\$(_ovn_parent_hash '${PARENT#- \[ \] }').app_routers_discover.py.toks)\" = 220000 ] && [ -f '$st'/item_fails/ongoing-x.lineage.txt-\$(_ovn_parent_hash '${P2#- \[ \] }').app_routers_discover.py.toks ]"
  r2="$(new_repo "${L}K4" "$CHILD_A")"; setchild "$r2/OVERNIGHT_PROGRESS.md" "$(printf '# --- recovered from a parked item [2026-11-07]: %s (review) ---' "${PARENT#- \[ \] }")" "$CHILD_A"
  l="$(mklog 1 "${L}K4" 1)"; RUN "$G" "$r2" "reverted(build-break)" "$tmp/st${L}K" ongoing-x "$l"
  ok "$L K4 a child with a LEGACY header (no ph:) has no lineage: not parked (safe direction)" "! grep -q 'AUTO-SKIP' '$r2/OVERNIGHT_PROGRESS.md'"
  ok "$L K5 the parent-hash pipeline in ovn_recover_parked.sh equals the guard's key (same text, any whitespace/checkbox form)" "[ \"\$(_ovn_parent_hash '- [ ] [T3]  a   b ')\" = \"\$(_ovn_parent_hash '[T3] a b')\" ]"
  # R2-2: a sibling child that lands FIRST TRY (never failed => in no member list) must clear the lineage; a later sibling then inherits nothing
  r="$(new_repo "${L}M" "$PARENT")"; st="$tmp/st${L}M"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}M"
  CHILD_A2='- [ ] [T3] app/routers/discover.py — decomposed: add 429 handler. VERIFY: pytest tests/test_discover_rl.py::b (cat:python; recovery:decomposed)'
  printf '%s\n\n%s\n%s\n%s\n' "- [x] x" "$HDR" "$CHILD_A" "$CHILD_A2" > "$r/OVERNIGHT_PROGRESS.md"
  ch="$(ovn_item_hash "$CHILD_A")"; echo "--- auto-credit: item-hash $ch ---" > "$tmp/m1_${L}.log"
  printf '%s\n\n%s\n%s\n%s\n' "- [x] x" "$HDR" "${CHILD_A/- \[ \]/- [x]}" "$CHILD_A2" > "$r/OVERNIGHT_PROGRESS.md"
  RUN "$G" "$r" "pushed(tests:pass)" "$st" ongoing-x "$tmp/m1_${L}.log"
  ok "$L M1 child A landed first try (aider item-hash marker, never recorded as a member): the lineage ledger is cleared" "! ls '$st'/item_fails/ongoing-x.lineage.*.toks"
  l="$(mklog 1 "${L}M" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L M2 ... so sibling B failing once is NOT parked on the parent's spend" "! grep -q 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md'"
  # R2-2b: [feat:] siblings: the inherited spend comes only from siblings that FAILED; a landing of ANY member of the feat lineage clears it
  r="$(new_repo "${L}N" "$FEAT1")"; st="$tmp/st${L}N"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}N"
  ok "$L N0 the failing feat sibling left a feat ledger" "ls '$st'/item_fails/ongoing-x.lineage.feat-*.toks"
  printf '%s\n%s\n' "- [x] [T3] app/routers/streams.py — landed sibling. VERIFY: pytest tests/t.py [feat:iptv-20261101-aaaa1111]" "$FEAT1B" > "$r/OVERNIGHT_PROGRESS.md"
  ch="$(ovn_item_hash "$FEAT1B")"; echo "--- auto-credit: item-hash $ch ---" > "$tmp/n1_${L}.log"
  RUN "$G" "$r" "pushed(tests:pass)" "$st" ongoing-x "$tmp/n1_${L}.log"
  ok "$L N1 a landing of ANY member of the feat lineage clears the feat ledger" "! ls '$st'/item_fails/ongoing-x.lineage.feat-*.toks"
  l="$(mklog 1 "${L}N" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L N2 ... so a later sibling failing once is NOT parked on the earlier sibling's spend" "! grep -q 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md'"
  r="$(new_repo "${L}N3" "$FEAT1")"; st="$tmp/st${L}N3"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}N3"
  printf '%s\n' "$FEAT1B" > "$r/OVERNIGHT_PROGRESS.md"
  l="$(mklog 1 "${L}N3" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L N3 control: with NO landing in between, a failing sibling of the same feat DOES inherit the failed sibling's spend" "grep -q 'feature budget: 200000 inherited' '$r/OVERNIGHT_PROGRESS.md'"
  # G: the expiry is FIXED from the first write: an inherited-only park never refreshes it (nor creates a fresher copy)
  r="$(new_repo "${L}G" "$PARENT")"; st="$tmp/st${L}G"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}G"
  for led in "$st"/item_fails/ongoing-x.lineage.*.toks; do touch -t "$(old_ts)" "$led"; done
  setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
  l="$(mklog 60 "${L}G" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L G1 the child was parked by the inherited budget only" "grep -q 'feature budget' '$r/OVERNIGHT_PROGRESS.md'"
  ok "$L G2 every ledger is still ~23h old (none refreshed, none newly created with a fresh mtime)" "[ -z \"\$(find '$st'/item_fails -name 'ongoing-x.lineage.*.toks' -mmin -1300)\" ] && [ -n \"\$(ls '$st'/item_fails/ongoing-x.lineage.*.toks)\" ]"
  # H: a child inherits at most the feature cap
  r="$(new_repo "${L}H" "$PARENT")"; st="$tmp/st${L}H"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}H"
  for led in "$st"/item_fails/ongoing-x.lineage.*.toks; do printf '900000\n' > "$led"; done
  setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
  l="$(mklog 60 "${L}H" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L H1 inherited spend is capped at the feature budget (200000, not 900000)" "grep -q 'feature budget: 200000 inherited' '$r/OVERNIGHT_PROGRESS.md'"
  unset OVN_FEATURE_TOKEN_INHERIT
}
shadow_suite(){   # $1=guard path $2=label ; the DEFAULT (variable unset) must only log
  local G="$1" L="$2" r st l
  unset OVN_FEATURE_TOKEN_INHERIT
  r="$(new_repo "${L}S" "$PARENT")"; st="$tmp/st${L}S"; mkdir -p "$st"
  park_parent "$G" "$r" "$st" "${L}S"
  setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
  l="$(mklog 60 "${L}S" c1)"; RUN "$G" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
  ok "$L S1 default (shadow): the recovery child is NOT parked on the inherited budget" "! grep -q 'feature budget' '$r/OVERNIGHT_PROGRESS.md' && ! grep -q 'AUTO-SKIP after 260000' '$r/OVERNIGHT_PROGRESS.md'"
  ok "$L S2 ... the would-be park is logged as would_park_inherited" "grep -q 'would_park_inherited' '$st/feature_budget_shadow.log'"
  ok "$L S3 ... and the ledger is still recorded (corpus measure)" "ls '$st'/item_fails/ongoing-x.lineage.*.toks"
}
suite "$G0" real
shadow_suite "$G0" real
echo "== kill switch = the old behaviour (child restarts the budget)"
r="$(new_repo killsw "$PARENT")"; st="$tmp/stkillsw"; mkdir -p "$st"
export OVN_FEATURE_TOKEN_INHERIT=off
park_parent "$G0" "$r" "$st" ks
setchild "$r/OVERNIGHT_PROGRESS.md" "$HDR" "$CHILD_A"
l="$(mklog 60 ks c1)"; RUN "$G0" "$r" "reverted(build-break)" "$st" ongoing-x "$l"
ok "K1 OVN_FEATURE_TOKEN_INHERIT=off: no ledger, no shadow log, the child is not parked" "! ls '$st'/item_fails/ongoing-x.lineage.*.toks && ! grep -q 'AUTO-SKIP after 260000' '$r/OVERNIGHT_PROGRESS.md' && [ ! -f '$st/feature_budget_shadow.log' ]"
unset OVN_FEATURE_TOKEN_INHERIT

echo "== mutants (each must make the suite fail)"
CUTK="cut -d' ' -f1"
mutant(){  # $1=label then (old new) pairs
  local lab="$1"; shift
  cp "$G0" "$tmp/mut_guard.sh"; cp "$(dirname "$G0")/lib_item_select.sh" "$(dirname "$G0")/lib_path_normalize.sh" "$tmp/" 2>/dev/null
  python3 - "$tmp/mut_guard.sh" "$@" <<'PY'
import sys
p = sys.argv[1]; a = sys.argv[2:]
s = open(p).read()
for old, new in zip(a[0::2], a[1::2]):
    assert old in s, "anchor missing: " + old
    s = s.replace(old, new, 1)
open(p, "w").write(s)
PY
  local before=$F; P0=$P
  suite "$tmp/mut_guard.sh" "mut" >/dev/null 2>&1; shadow_suite "$tmp/mut_guard.sh" "mut" >/dev/null 2>&1
  if [ "$F" -gt "$before" ]; then echo "  ok   mutant '$lab' is killed"; F=$before; P=$P0; else echo "  FAIL: mutant '$lab' SURVIVED"; F=$((F+1)); fi
}
mutant "ledger never recorded"               '_lin_record "$text" "$lineno" $((toks + _inh)) "$h" 1' ':'
mutant "inherited spend ignored"             '_inh="$_INH_V"; _inh_src' '_inh=0; _inh_src'
mutant "no-op path ignores the ledger"       '[ "$_inh" -gt 0 ] && [ $((ntoks + _inh)) -ge "$FEATCAP" ] &&' 'false &&'
mutant "ledger never expires"                'ttl="${OVN_FEATURE_TOKEN_TTL_H:-24}"' 'ttl=99999'
mutant "staged landing does not clear"       '_lin_clear_text "$_sl_line"' ':'
mutant "aider landing does not clear"        '_lin_clear_hash "$_zh"' ':'
mutant "bare-file lineage (old key)"         'if [ "$2" = rec ]; then' 'if true; then' 'k="$(_lin_pfx "$t" | md5sum | cut -d'"' '"' -f1)"' 'k=x'
mutant "inherited-only park refreshes mtime" '_lin_write "$f" "$3" "$4" "$ref"' '_lin_write "$f" "$3" "$4"'
mutant "child inherits uncapped"             '[ "$best" -gt "$cap" ] && best="$cap"' ':'
mutant "inheritance enforced by default"     '${OVN_FEATURE_TOKEN_INHERIT:-shadow}' '${OVN_FEATURE_TOKEN_INHERIT:-on}'
mutant "key = first 40 chars again"            '_lin_phash(){ printf '"'%s'"' "$(_lin_norm "$1")" | md5sum' '_lin_phash(){ printf '"'%s'"' "$(_lin_norm "$1" | LC_ALL=C tr -cd '"'\\040-\\176'"' | cut -c1-40)" | md5sum'
mutant "landed child text never resolved"      '_lin_clear_landed_texts "$_zhs"' ':'
mutant "header ph hash ignored (txt prefix)"   "s/^# --- recovered from a parked item" "s/^# --- recovered from a parked itemX"
mutant "child hash never registered"         '[ "$_inh" -gt 0 ] && _lin_member "$_inh_src" "$h"' ':'

# Z5-D regression: old_ts + touch -t must land ~23h in the past under ANY zone (the CST box failed G2 5x because the stamp was UTC and touch read it as local time)
for _tz in UTC America/Chicago Asia/Tokyo Pacific/Kiritimati; do
  _f="$tmp/tzprobe"; : > "$_f"
  ( export TZ="$_tz"; touch -t "$(old_ts)" "$_f" )
  ok "Z5-D old_ts is ~23h old under TZ=$_tz (between 1320 and 1440 minutes)" "[ -n \"\$(find '$_f' -mmin +1320 -mmin -1440)\" ]"
done
echo "Z2 feature token budget: $P passed, $F failed"
[ "$F" -eq 0 ]
