#!/usr/bin/env bash
# Z8b-C (2026-11-10): PARTIAL fix-up undo guard (a3) in ovn_fixup_integrity_gate: the fix-up removed >= 80% of the item's added lines on its target (kept <= 20%), net-zero (a) misses it.
# SHADOW by default ('[fixup-undo-frac] shadow: WOULD REJECT'), enforce resets + no-op(fixup-undid-item), off silent. Helper unit tests + gate tests + mutation controls.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/.."
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
export OVN_VERIFY_SHADOW_LOG="$tmp/shadow.log"
ALERTS="$tmp/alerts.log"; : > "$ALERTS"
emit_alert(){ printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$ALERTS"; }
source "$S/lib_item_select.sh"; source "$S/lib_path_normalize.sh"; source "$S/lib_verify_clause.sh"; source "$S/lib_fixup.sh"
unset OVN_FIXUP_REVERIFY OVN_FIXUP_UNDO_GUARD OVN_FIXUP_UNDO_WS OVN_FIXUP_UNDO_FRAC OVN_FIXUP_UNDO_FRAC_PCT OVN_FIXUP_UNDO_FRAC_MIN OVN_TESTONLY_GUARD OVN_RI_NEW
BEFORE=""; MAIN=""; R=""; TL=""
ITEMLINE='- [ ] [T1] app/reg.py — Add the `helper_one` helpers. VERIFY: `true`'
mkrepo(){
  R="$tmp/$1"; rm -rf "${R:?}"; mkdir -p "$R/app"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  printf 'def keep():\n    return 1\n' > app/reg.py
  printf '## Next Steps\n%s\n' "$ITEMLINE" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m before; BEFORE="$(git rev-parse HEAD)"; TL="$tmp/$1.log"; : > "$TL"
}
main10(){ { printf 'def keep():\n    return 1\n'; for i in 1 2 3 4 5 6 7 8 9 10; do printf 'def helper_%s():\n    return %s\n' "$i" "$i"; done; } > app/reg.py; git add -A; git commit -q -m main; MAIN="$(git rev-parse HEAD)"; }
fixup_keep(){ # $1 = how many helper defs survive
  { printf 'def keep():\n    return 1\n'; i=1; while [ "$i" -le "$1" ]; do printf 'def helper_%s():\n    return %s\n' "$i" "$i"; i=$((i+1)); done; } > app/reg.py; git add -A; git commit -q -m fixup >/dev/null 2>&1; }
head_(){ git rev-parse HEAD; }

echo "== helper ovn_fixup_undo_frac"
mkrepo h1; main10; fixup_keep 1
ok "H1 kept 2 of 20 added lines (90% removed) => rc 0 and prints '2 20'" "cd '$R' && [ \"\$(ovn_fixup_undo_frac '$BEFORE' '$MAIN' app/reg.py)\" = '2 20' ]"
mkrepo h2; main10; fixup_keep 5
ok "H2 kept 10 of 20 (50% removed) => rc 1 (below the 80% bar)" "cd '$R' && ! ovn_fixup_undo_frac '$BEFORE' '$MAIN' app/reg.py"
mkrepo h3; main10; fixup_keep 2
ok "H3 kept 4 of 20 (exactly 80% removed) => rc 0 (the bar is >=)" "cd '$R' && ovn_fixup_undo_frac '$BEFORE' '$MAIN' app/reg.py"
mkrepo h4; printf 'def keep():\n    return 1\ndef h_a():\n    return 1\n' > app/reg.py; git add -A; git commit -q -m main; MAIN="$(head_)"; git checkout -q "$BEFORE" -- app/reg.py; git commit -q -m fixup
ok "H4 the item added only 2 lines (< MIN 5): never flagged even though fully undone" "cd '$R' && ! ovn_fixup_undo_frac '$BEFORE' '$MAIN' app/reg.py"
mkrepo h5; main10; fixup_keep 10
ok "H5 everything kept => rc 1 and prints '20 20'" "cd '$R' && out=\$(ovn_fixup_undo_frac '$BEFORE' '$MAIN' app/reg.py); [ \"\$out\" = '20 20' ]"
ok "H6 empty target => rc 1" "cd '$R' && ! ovn_fixup_undo_frac '$BEFORE' '$MAIN' ''"
ok "H7 bogus sha => rc 1" "cd '$R' && ! ovn_fixup_undo_frac deadbeefdeadbeefdeadbeefdeadbeefdeadbeef '$MAIN' app/reg.py"
mkrepo h8; main10; fixup_keep 1
ok "H8 OVN_FIXUP_UNDO_FRAC_PCT=95 raises the bar (90% removed no longer trips)" "cd '$R' && ! OVN_FIXUP_UNDO_FRAC_PCT=95 ovn_fixup_undo_frac '$BEFORE' '$MAIN' app/reg.py"
ok "H9 OVN_FIXUP_UNDO_FRAC_MIN=30 raises the minimum (20 added lines no longer count)" "cd '$R' && ! OVN_FIXUP_UNDO_FRAC_MIN=30 ovn_fixup_undo_frac '$BEFORE' '$MAIN' app/reg.py"

echo "== gate (a3)"
mkrepo g1; main10; fixup_keep 1; H="$(head_)"; : > "$ALERTS"
ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemF; RC=$?
ok "G1 shadow (default): the repair round is KEPT (rc 0, HEAD untouched, no status)" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && [ -z \"\$OVN_FXI_STATUS\" ]"
ok "G2 shadow: task log has [fixup-undo-frac] and 'WOULD REJECT'" "grep -q '\[fixup-undo-frac\] (tier2, mode=shadow)' '$TL' && grep -q 'shadow: WOULD REJECT the repair round' '$TL'"
ok "G3 shadow: one info alert" "[ \"\$(grep -c '^info|itemF|\[fixup-undo-frac\]' '$ALERTS')\" = 1 ]"
mkrepo g2; main10; fixup_keep 1; : > "$ALERTS"
OVN_FIXUP_UNDO_FRAC=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemF; RC=$?
ok "G4 enforce: rc 1, tree reset to BEFORE, status no-op(fixup-undid-item)" "[ $RC = 1 ] && [ \"\$(head_)\" = '$BEFORE' ] && [ \"\$OVN_FXI_STATUS\" = 'no-op(fixup-undid-item)' ]"
mkrepo g3; main10; fixup_keep 1; H="$(head_)"; : > "$ALERTS"
OVN_FIXUP_UNDO_FRAC=off ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemF; RC=$?
ok "G5 off: silent (no log line, no alert), commit kept" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && ! grep -q 'fixup-undo-frac' '$TL' && [ ! -s '$ALERTS' ]"
mkrepo g4; main10; fixup_keep 6; H="$(head_)"; : > "$ALERTS"
OVN_FIXUP_UNDO_FRAC=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemF; RC=$?
ok "G6 enforce but only 40% removed: nothing happens" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ]"
mkrepo g5; main10; git checkout -q "$BEFORE" -- app/reg.py; git commit -q -m fixup; : > "$ALERTS"
OVN_FIXUP_UNDO_FRAC=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" itemF; RC=$?
ok "G7 a FULL undo is still the net-zero guard (a): no [fixup-undo-frac] line" "[ $RC = 1 ] && ! grep -q 'fixup-undo-frac' '$TL' && grep -q 'FIXUP-INTEGRITY (tier2)' '$TL'"

echo "== mutation controls (each broken copy of lib_fixup.sh must make a check fail)"
n=0; surv=0
mutlib(){ # label old new check-description (the check re-runs G4/G1 logic against the mutated lib)
  local label="$1" old="$2" new="$3" want="$4" d="$tmp/mut$((n+1))"; n=$((n+1)); mkdir -p "$d"
  for f in lib_item_select.sh lib_path_normalize.sh lib_verify_clause.sh lib_fixup.sh; do cp "$S/$f" "$d/"; done
  [ -f "$S/lib_safe_tmp.sh" ] && cp "$S/lib_safe_tmp.sh" "$d/"; cp "$HERE/lib_safe_tmp.sh" "$d/" 2>/dev/null
  OLD="$old" NEW="$new" python3 - "$d/lib_fixup.sh" <<'PYEOF' || { echo "  FAIL mutant '$label' not applicable"; surv=$((surv+1)); return; }
import os, sys
p = sys.argv[1]; s = open(p).read(); o = os.environ["OLD"]
if o not in s: sys.exit(3)
open(p, "w").write(s.replace(o, os.environ["NEW"], 1))
PYEOF
  local res
  res="$( ( source "$d/lib_item_select.sh"; source "$d/lib_path_normalize.sh"; source "$d/lib_verify_clause.sh"; source "$d/lib_fixup.sh"
    emit_alert(){ :; }
    mkrepo mm$n; main10; fixup_keep 1; H="$(head_)"
    case "$want" in
      enforce-resets) OVN_FIXUP_UNDO_FRAC=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" it >/dev/null 2>&1; [ "$(head_)" = "$BEFORE" ] && echo PASS || echo FAIL ;;
      shadow-keeps)  ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" it >/dev/null 2>&1; [ "$(head_)" = "$H" ] && grep -q 'WOULD REJECT' "$TL" && echo PASS || echo FAIL ;;
      off-silent)    OVN_FIXUP_UNDO_FRAC=off ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" it >/dev/null 2>&1; ! grep -q 'fixup-undo-frac' "$TL" && echo PASS || echo FAIL ;;
      min-lines)     cd "$R"; git reset -q --hard "$BEFORE"; printf 'def keep():\n    return 1\ndef a():\n    return 11\ndef b():\n    return 12\n' > app/reg.py; git add -A; git commit -q -m m2; M2="$(head_)"; git checkout -q "$BEFORE" -- app/reg.py; printf 'def keep():\n    return 1\ndef z():\n    return 9\n' > app/reg.py; git add -A; git commit -q -m f2
                     OVN_FIXUP_UNDO_FRAC=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$M2" "$TL" it >/dev/null 2>&1; [ "$(head_)" != "$BEFORE" ] && echo PASS || echo FAIL ;;
      half-not)      cd "$R"; git reset -q --hard "$MAIN"; fixup_keep 5; H="$(head_)"; OVN_FIXUP_UNDO_FRAC=enforce ovn_fixup_integrity_gate tier2 "$BEFORE" "$MAIN" "$TL" it >/dev/null 2>&1; [ "$(head_)" = "$H" ] && echo PASS || echo FAIL ;;
    esac ) 2>/dev/null | tail -1)"
  if [ "$res" = PASS ]; then echo "  FAIL mutant SURVIVED: $label"; surv=$((surv+1)); else echo "  ok   mutant killed: $label"; fi
}
mutlib "enforce does not reset"             '_ovn_fxi_reset "$before"; OVN_FXI_STATUS="no-op(fixup-undid-item)"; return 1
    fi
    _ovn_fxi_log "$tl" "[fixup-undo-frac] shadow' ':; return 1
    fi
    _ovn_fxi_log "$tl" "[fixup-undo-frac] shadow' enforce-resets
mutlib "shadow stops being shadow (default enforce)" 'local fmode="${OVN_FIXUP_UNDO_FRAC:-shadow}"' 'local fmode="${OVN_FIXUP_UNDO_FRAC:-enforce}"' shadow-keeps
mutlib "off switch ignored"                  'if [ "$fmode" != off ] && frac=' 'if frac=' off-silent
mutlib "minimum added lines ignored"         '[ "$added" -ge "$min" ] 2>/dev/null || return 1' ':' min-lines
mutlib "percent bar ignored (any removal trips)" '[ $(( (added - kept) * 100 )) -ge $(( pct * added )) ]' '[ "$kept" -lt "$added" ]' half-not
echo "mutants: $n, survived/unapplied: $surv"
echo "z8b fixup frac: $P passed, $F failed"
[ "$F" = 0 ] && [ "$surv" = 0 ]
