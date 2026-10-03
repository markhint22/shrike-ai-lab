#!/usr/bin/env bash
# QA harness-X follow-up 3 (2026-10-02), from the independent re-review of dafc7a2:
#   M1  watch-mode VERIFYs (vitest/jest via `npm run test -- X`) pass in ~1s and then wait for file changes until the timeout: 48 of the 50 rc=124 rows
#       in the shadow log. The VERIFY now runs with CI=true so runners exit; a heavy 900s cap must not be spent on a hang.
#   M2  a glob list left unquoted was pathname-expanded against the repo root: '*.log' became the literal a.log b.log, so real droppings were refused.
#   M3  an indeterminate landing cleared the item's streaks and re-armed the allowance forever: now bounded across cycles (OVN_INDET_LAND_MAX) + one alert.
#   M4  the UNRUNNABLE reason carried 120 chars of the clause's output into alerts.log (a wider channel than the shadow log): fixed reason only.
# Every NEW assertion fails on dafc7a2; labelled "benign twin" lines check that normal behaviour is unchanged.
set -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
[ -f "$S/lib_auto_credit.sh" ] || { echo "  SKIP: lib_auto_credit.sh not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t.com GIT_CONFIG_NOSYSTEM=1
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
emit_alert(){ :; }
. "$S/lib_item_select.sh"
. "$S/lib_verify_clause.sh"
. "$S/lib_auto_credit.sh"

# ---- M1: CI mode ----
PROG="$W/prog.md"
cat > "$PROG" <<'EOP'
- [ ] [T2] a.ts — watch-mode runner. VERIFY: `if [ "$CI" = "true" ]; then exit 0; else sleep 4; fi`
- [ ] [T2] b.ts — a check that really fails in CI mode. VERIFY: `[ "$CI" = "true" ] && exit 3`
EOP
( cd "$W" && VERIFY_TIMEOUT_SECS=2 shadow_check 1; echo "$_LAST_VERIFY_RESULT" > "$W/m1" )
eq "M1: a clause that only exits when CI=true passes (it would sit in 'watch mode' and TIME OUT without it)" "$(cat "$W/m1")" "PASS"
( cd "$W" && VERIFY_TIMEOUT_SECS=2 shadow_check 2; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_RC" > "$W/m1b" )
eq "M1 benign twin: a clause that genuinely fails under CI is still FAIL (rc preserved), not hidden" "$(cat "$W/m1b")" "FAIL|3"

# ---- M4: no output tail in the UNRUNNABLE reason ----
cat > "$PROG" <<'EOP'
- [ ] [T2] c.py — unrunnable and noisy. VERIFY: `echo TOKEN_sk_live_abcdef123456; definitely_not_a_command_xyz`
EOP
( cd "$W" && shadow_check 1; echo "$_LAST_VERIFY_RESULT|$_LAST_VERIFY_RC|$_LAST_VERIFY_WHY" > "$W/m4" )
eq "M4: UNRUNNABLE reason is the fixed text only (no clause output)" "$(cat "$W/m4")" "UNRUNNABLE|127|VERIFY not runnable: rc=127"
ok "M4 benign twin: the SHADOW log row still keeps the tail for debugging" 'grep -q "result=UNRUNNABLE rc=127" "$SHADOW_LOG"'

# ---- M2: noglob benign matcher ----
mkdir -p "$W/repo" && ( cd "$W/repo" && touch a.log b.log && mkdir -p app/build/x .godot/editor )
( cd "$W/repo" && for p in sub/c.log app/build/x/other .godot/editor/new debug.log; do _ovn_tree_is_benign_path "$p" && echo "$p=benign" || echo "$p=refused"; done > "$W/m2" )
eq "M2: patterns are not pathname-expanded against cwd (a.log/b.log/app/build/x/.godot/editor present)" "$(tr '\n' ' ' < "$W/m2")" "sub/c.log=benign app/build/x/other=benign .godot/editor/new=benign debug.log=benign "
( cd "$W/repo" && for p in src/main.py package-lock.json; do _ovn_tree_is_benign_path "$p" && echo "$p=benign" || echo "$p=refused"; done > "$W/m2b" )
eq "M2 benign twin: real source and lockfiles are still NOT benign" "$(tr '\n' ' ' < "$W/m2b")" "src/main.py=refused package-lock.json=refused "
( set -f; cd "$W/repo"; _ovn_tree_is_benign_path x.log; case "$-" in *f*) echo keep > "$W/m2c";; *) echo lost > "$W/m2c";; esac )
eq "M2: the caller's noglob setting is preserved" "$(cat "$W/m2c")" "keep"

# ---- M3: bounded indeterminate landings ----
G="$S/ovn_item_guard.sh"
line='- [ ] [T2] `src/a.py` — heavy item whose VERIFY never concludes'
GR="$W/g/r"; ST="$W/g/s"; mkdir -p "$GR" "$ST/item_fails"
( cd "$GR" && git init -q -b main . && git config user.email t@t && git config user.name t && printf '%s\n' "$line" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m i )
H="$(ovn_item_hash "$line")"; : > "$ST/alerts.log"
printf -- '--- auto-credit: indet-hash %s ---\n' "$H" > "$W/g/ind.log"
cycle(){ printf '2' > "$ST/item_fails/it.$H.count"; OVN_INDET_LAND_MAX=3 bash "$G" "$GR" "pushed(tests:pass)" "$ST" it "$W/g/ind.log" >/dev/null; }
cycle; cycle; cycle
ok "M3: the first 3 indeterminate landings still clear the streak (unchanged behaviour)" '[ ! -e "$ST/item_fails/it.$H.count" ]'
cycle
ok "M3: the 4th indeterminate landing of the same item does NOT clear the streak any more (accounting resumes)" '[ "$(cat "$ST/item_fails/it.$H.count" 2>/dev/null)" = 2 ]'
eq "M3: exactly one alert asks for a human" "$(grep -c 'never concluded' "$ST/alerts.log")" "1"
cycle
eq "M3: no repeated alert on the 5th" "$(grep -c 'never concluded' "$ST/alerts.log")" "1"
printf -- '--- item-hash %s ---\n' "$H" > "$W/g/ok.log"; bash "$G" "$GR" "pushed(tests:pass)" "$ST" it "$W/g/ok.log" >/dev/null
ok "M3 benign twin: a CREDITED landing resets the counter" '[ ! -e "$ST/item_fails/it.$H.indetlands" ]'

echo "auto-credit h9x3: $P passed, $F failed"
[ "$F" -eq 0 ]
