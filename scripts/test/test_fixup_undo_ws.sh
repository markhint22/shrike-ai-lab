#!/usr/bin/env bash
# 2026-10-18 (xlite overnight audit): the fix-up undid the item but left one blank line, so the exact net-zero test (a) in ovn_fixup_integrity_gate missed it.
# Live: xlite 55824bee removed AchievementRegistry.on_faction_codex_update, build-gate fix-up 80c33bb3 restored it + a blank line; recorded landed-uncredited.
# Covers ovn_fixup_undid_item_ws + gate step (a2): SHADOW by default (kept, '[fixup-undo-ws]' logged + info alert + 'WOULD RESET' line), enforce resets, off is silent,
# a whitespace-only MAIN commit (a format item) and a real surviving change are never flagged. Mutation controls at the end (disable the helper -> shadow/enforce checks go red).
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"; S="$HERE/.."
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT
export OVN_VERIFY_SHADOW_LOG="$tmp/shadow.log"
ALERTS="$tmp/alerts.log"; : > "$ALERTS"
emit_alert(){ printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$ALERTS"; }
# shellcheck disable=SC1090
source "$S/lib_item_select.sh"; source "$S/lib_path_normalize.sh"; source "$S/lib_verify_clause.sh"; source "$S/lib_fixup.sh"
unset OVN_FIXUP_REVERIFY OVN_FIXUP_UNDO_GUARD OVN_FIXUP_UNDO_WS OVN_TESTONLY_GUARD OVN_RI_NEW

BEFORE=""; MAIN=""; R=""; TL=""
ITEMLINE='- [ ] [T1] app/reg.gd — Remove the `orphan` method definition. VERIFY: `! grep -q "func orphan" app/reg.gd`'
mkrepo(){
  R="$tmp/$1"; rm -rf "${R:?}"; mkdir -p "$R/app"; cd "$R" || exit 1
  git init -q; git config user.email t@t; git config user.name t
  printf 'func keep():\n\treturn 1\n\nfunc orphan():\n\treturn 2\n\nfunc tail():\n\treturn 3\n' > app/reg.gd
  printf '## Next Steps\n%s\n' "${2:-$ITEMLINE}" > OVERNIGHT_PROGRESS.md
  git add -A; git commit -q -m before; BEFORE="$(git rev-parse HEAD)"; TL="$tmp/$1.log"; : > "$TL"
}
maincommit(){ printf 'func keep():\n\treturn 1\n\nfunc tail():\n\treturn 3\n' > app/reg.gd; git add -A; git commit -q -m main; MAIN="$(git rev-parse HEAD)"; }
fixup(){ git add -A; git commit -q -m fixup; }
head_(){ git rev-parse HEAD; }
restore_plus_blank(){ printf 'func keep():\n\treturn 1\n\nfunc orphan():\n\treturn 2\n\n\nfunc tail():\n\treturn 3\n' > app/reg.gd; fixup; }

# ---- helper: pure function ----
mkrepo h1; maincommit; restore_plus_blank
ok "helper: restore + extra blank line => undone (rc 0)" "cd '$R' && ovn_fixup_undid_item_ws '$BEFORE' '$MAIN' app/reg.gd"
ok "helper: exact (a) test does NOT see it (the gap this closes)" "cd '$R' && ! ovn_fixup_undid_item '$BEFORE' '$MAIN' app/reg.gd"
mkrepo h2; maincommit; printf 'func keep():\n\treturn 1\n\nfunc tail():\n\treturn 4\n' > app/reg.gd; fixup
ok "helper: real change survives the fix-up => not undone (rc 1)" "cd '$R' && ! ovn_fixup_undid_item_ws '$BEFORE' '$MAIN' app/reg.gd"
mkrepo h3; printf 'func keep():\n\treturn 1\n\n\nfunc orphan():\n\treturn 2\n\nfunc tail():\n\treturn 3\n' > app/reg.gd; git add -A; git commit -q -m main; MAIN="$(head_)"; printf 'func keep():\n\treturn 1\n\nfunc orphan():\n\treturn 2\n\nfunc tail():\n\treturn 3\n' > app/reg.gd; fixup
ok "helper: a whitespace-only MAIN commit (format item) is never flagged" "cd '$R' && ! ovn_fixup_undid_item_ws '$BEFORE' '$MAIN' app/reg.gd"
ok "helper: empty target => rc 1" "cd '$R' && ! ovn_fixup_undid_item_ws '$BEFORE' '$MAIN' ''"
ok "helper: git error (bogus sha) => rc 1, never 0" "cd '$R' && ! ovn_fixup_undid_item_ws deadbeefdeadbeefdeadbeefdeadbeefdeadbeef '$MAIN' app/reg.gd"

# ---- gate: default SHADOW ----
mkrepo g1; maincommit; restore_plus_blank; H="$(head_)"; : > "$ALERTS"
ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemW; RC=$?
ok "shadow (default): gate keeps the commit (rc 0, HEAD untouched, no status)" "[ $RC = 0 ] && [ \"\$(head_)\" = '$H' ] && [ -z \"\$OVN_FXI_STATUS\" ]"
ok "shadow: task log carries [fixup-undo-ws] and the WOULD RESET line" "grep -q '\[fixup-undo-ws\] (buildgate, mode=shadow)' '$TL' && grep -q 'shadow: WOULD RESET to' '$TL'"
ok "shadow: exactly one info alert" "[ \"\$(grep -c '^info|itemW|\[fixup-undo-ws\]' '$ALERTS')\" = 1 ]"

# ---- gate: ENFORCE ----
mkrepo g2; maincommit; restore_plus_blank; : > "$ALERTS"
OVN_FIXUP_UNDO_WS=enforce ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemW; RC=$?
ok "enforce: rc 1, hard reset to BEFORE_SHA, status no-op(fixup-undid-item)" "[ $RC = 1 ] && [ \"\$(head_)\" = '$BEFORE' ] && [ \"\$OVN_FXI_STATUS\" = 'no-op(fixup-undid-item)' ]"
ok "enforce: marker line the item guard reads is logged" "grep -q '^--- fixup-integrity: the buildgate fix-up left only whitespace' '$TL'"

# ---- gate: OFF and unaffected paths ----
mkrepo g3; maincommit; restore_plus_blank; : > "$ALERTS"
OVN_FIXUP_UNDO_WS=off ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemW; RC=$?
ok "off: silent keep (no [fixup-undo-ws] log line, no such alert)" "[ $RC = 0 ] && ! grep -q 'fixup-undo-ws' '$TL' && ! grep -q 'fixup-undo-ws' '$ALERTS'"
mkrepo g4; maincommit; printf 'func keep():\n\treturn 1\n\nfunc tail():\n\treturn 4\n' > app/reg.gd; fixup; : > "$ALERTS"
OVN_FIXUP_UNDO_WS=enforce ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemW; RC=$?
ok "control: enforce with a genuine surviving change keeps the commit" "[ $RC = 0 ] && [ -z \"\$OVN_FXI_STATUS\" ] && ! grep -q 'fixup-undo-ws' '$TL'"

# ---- mutation controls: neutralise the helper, the same assertions must go red ----
mutant="$tmp/lib_fixup_mut.sh"
python3 - "$S/lib_fixup.sh" "$mutant" <<'PY'
import sys
s=open(sys.argv[1],encoding="utf-8").read()
a='ovn_fixup_undid_item_ws() {\n'
assert a in s
open(sys.argv[2],"w",encoding="utf-8").write(s.replace(a,a+'  return 1\n',1))
PY
mkrepo m1; maincommit; restore_plus_blank
( source "$mutant"; cd "$R" && OVN_FIXUP_UNDO_WS=enforce ovn_fixup_integrity_gate buildgate "$BEFORE" "$MAIN" "$TL" itemW ); MRC=$?
ok "MUTANT (helper always 1): enforce no longer resets - proves the enforce test above detects a broken helper" "[ $MRC = 0 ]"
mkrepo m2; maincommit; restore_plus_blank
( source "$mutant"; cd "$R" && ovn_fixup_undid_item_ws "$BEFORE" "$MAIN" app/reg.gd ); MRC=$?
ok "MUTANT: helper rc flips to 1 - proves the helper test above detects it" "[ $MRC = 1 ]"

echo; echo "$P passed, $F failed"; [ "$F" -eq 0 ]
