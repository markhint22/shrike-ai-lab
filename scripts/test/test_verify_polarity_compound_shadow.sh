#!/usr/bin/env bash
# iptv-night F3 (2026-10-13), bash side: lib_verify_clause.sh shadow_check on a COMPOUND narration
#   VERIFY: `grep -rn "X" app/` returns nothing and `python -c "..."` succeeds.
# The polarity reader used to answer 'unknown' for it, so shadow_check (the one function every credit path goes through) credited the item on the grep's exit 0 = the symbol still present.
# Now the narration head ('returns nothing') is the verdict on the first command: PASS only when the grep finds nothing (rc 1).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIBDIR="${OVN_LIB_DIR:-$HERE/..}"
[ -f "$LIBDIR/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)" || exit 1; trap 'rm -rf "$tmp"' EXIT; tmp="$(cd "$tmp" && pwd -P)"
mkdir -p "$tmp/work/app"
printf 'class ParentalControlsService:\n    pass\n' > "$tmp/work/app/pc.py"
it(){ printf -- '- [ ] [T4] app/pc.py — Remove it. VERIFY: %s (cat:refactor; multifile:yes)' "$1"; }
run_sc(){  # $1 = lib dir, $2 = item line -> RESULT
  printf '%s\n' "$2" > "$tmp/prog.md"
  ( cd "$tmp/work" || exit 9
    PROG="$tmp/prog.md"; SHADOW_LOG="$tmp/shadow.log"; _REPO_LABEL=t; _VC_MEMO_ON=0; : > "$SHADOW_LOG"
    # shellcheck disable=SC1091
    . "$1/lib_verify_clause.sh"
    shadow_check 1
    printf '%s' "$_LAST_VERIFY_RESULT" )
}
LINE="$(it '`grep -rn "ParentalControlsService" app/` returns nothing and `python3 -c "print(1)"` succeeds.')"
r="$(run_sc "$LIBDIR" "$LINE")"
ok "class STILL present + compound 'returns nothing and ... succeeds' -> FAIL (was PASS: the live false credit)" "$([ "$r" = FAIL ] && echo 1 || echo 0)"
ok "... the shadow row is tagged polarity=neg" "$([ "$(grep -c 'result=FAIL rc=1 polarity=neg' "$tmp/shadow.log")" = 1 ] && echo 1 || echo 0)"
printf 'def other():\n    pass\n' > "$tmp/work/app/pc.py"
r="$(run_sc "$LIBDIR" "$LINE")"
ok "class gone -> PASS (grep rc 1 = absent)" "$([ "$r" = PASS ] && echo 1 || echo 0)"
printf 'class ParentalControlsService:\n    pass\n' > "$tmp/work/app/pc.py"
r="$(OVN_VERIFY_NARRATION_HEAD=off run_sc "$LIBDIR" "$LINE")"
ok "kill switch OVN_VERIFY_NARRATION_HEAD=off restores the old reading (PASS on rc 0)" "$([ "$r" = PASS ] && echo 1 || echo 0)"
r="$(OVN_VERIFY_POLARITY=off run_sc "$LIBDIR" "$LINE")"
ok "OVN_VERIFY_POLARITY=off restores the old reading too" "$([ "$r" = PASS ] && echo 1 || echo 0)"
echo; echo "$P passed, $F failed"; [ "$F" -eq 0 ]
