#!/usr/bin/env bash
# test_supply_cron_installer.sh - FIX 3a (2026-10-18): ops/install_supply_cron.sh + ops/cron.supply.proposed.txt. Hermetic: sandbox HOME, crontab is a stub file on PATH.
# Mutants (an edited copy of the installer) must each make the scenario that guards that behaviour FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OVN_REAL="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || exit 1
INST="$OVN_REAL/ops/install_supply_cron.sh"; PROP="$OVN_REAL/ops/cron.supply.proposed.txt"
[ -f "$INST" ] && [ -f "$PROP" ] || { echo "  FAIL: installer or proposal missing"; exit 1; }
ROOT="$(safe_mktemp_dir supply_itc)" || exit 1
trap 'safe_rm_rf "$ROOT"' EXIT
fails=0; n=0
ok(){ n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk(){ local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
new_sb(){ SB="$(safe_mktemp_dir_in "$ROOT" sc)" || exit 1; safe_set_sandbox_home "$SB" || exit 1; mkdir -p "$SB/bin" "$SB/ovn/scripts/test" "$SB/ovn/ops"
  cp "$HERE/lib_safe_tmp.sh" "$SB/ovn/scripts/test/"; cp "$PROP" "$SB/ovn/ops/"; for s in ovn_work_supply.py ovn_local_research.py; do : > "$SB/ovn/scripts/$s"; done
  cp "${1:-$INST}" "$SB/ovn/ops/install_supply_cron.sh"
  printf '%s\n' '#!/bin/sh' 'F="$HOME/crontab.stub"' 'case "$1" in -l) [ -n "${STUB_LIST_FAIL:-}" ] && { echo "crontab: boom" >&2; exit 1; }; [ -f "$F" ] || { echo "no crontab for u" >&2; exit 1; }; cat "$F";; *) echo write >> "$HOME/crontab.writes"; cp "$1" "$F";; esac' > "$SB/bin/crontab"
  chmod 755 "$SB/bin/crontab"; }
inst(){ ( cd "$SB/ovn" && PATH="$SB/bin:$PATH" bash ops/install_supply_cron.sh "$@" ); }
HAND='7,37 * * * * cd /h/overnight-queue && python3 scripts/ovn_work_supply.py iptv_apps --max 12 >> logs/work_supply.log 2>&1; python3 scripts/ovn_work_supply.py xlite --max 12 >> logs/work_supply.log 2>&1'

new_sb; printf '%s\n' "$HAND" > "$HOME/crontab.stub"; cp "$HOME/crontab.stub" "$SB/before"
inst > "$SB/out" 2>&1
chk "dry-run is the default: crontab unchanged, never written" cmp -s "$HOME/crontab.stub" "$SB/before"
chk "dry-run: no write call and no backup dir" bash -c "[ ! -e '$HOME/crontab.writes' ] && [ ! -d '$HOME/crontab-backups' ]"
chk "dry-run lists all ten lines ON" bash -c "[ \$(grep -c '^  ON ' '$SB/out') -eq 10 ]"
inst --apply > "$SB/out2" 2>&1
chk "apply: hand-installed line preserved byte-for-byte" grep -qxF "$HAND" "$HOME/crontab.stub"
chk "apply: block markers + 5 supply lines for exactly the five new repos (none for iptv_apps/xlite)" bash -c "[ \$(grep -c 'ovn_work_supply.py' '$HOME/crontab.stub') -eq 6 ] && grep -q 'SUPPLY-LINES BEGIN' '$HOME/crontab.stub' && ! grep -E '^[0-9].*ovn_work_supply.py (iptv_apps|xlite)' '$HOME/crontab.stub' | grep -v '^7,37'"
chk "apply: old crontab saved byte-for-byte first" bash -c "cmp -s '$SB/before' \$(ls '$HOME'/crontab-backups/crontab.*.txt | head -1)"
chk "apply: local-research lines present for all five" bash -c "[ \$(grep -c '^[0-9].*ovn_local_research.py' '$HOME/crontab.stub') -eq 5 ]"
inst --apply > "$SB/out3" 2>&1; chk "re-apply is idempotent (no change)" grep -q "no change" "$SB/out3"
inst --apply --remove >/dev/null 2>&1; chk "remove restores the original crontab byte-for-byte" cmp -s "$HOME/crontab.stub" "$SB/before"

new_sb; printf '%s\n' "$HAND" > "$HOME/crontab.stub"; STUB_LIST_FAIL=1 inst --apply > "$SB/out" 2>&1; rc=$?
chk "REFUSES (rc 2) when crontab -l fails, writes nothing" bash -c "[ $rc -eq 2 ] && [ ! -e '$HOME/crontab.writes' ]"

# a hand-installed line for the SAME script+repo is not duplicated
new_sb; printf '%s\n' "$HAND" '1,31 * * * * cd /h/overnight-queue && python3 scripts/ovn_work_supply.py gitlark --max 12 >> x 2>&1' > "$HOME/crontab.stub"
inst > "$SB/out" 2>&1
chk "same script+repo already hand-installed -> that one id is SKIPped, the other nine stay" bash -c "grep -q 'SKIP supply_gitlark' '$SB/out' && [ \$(grep -c '^  ON ' '$SB/out') -eq 9 ]"

# mutants
mut(){ python3 - "$INST" "$1" "$2" "$3" <<'PYEOF'
import sys
s = open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4]
assert s.count(old) == 1, "anchor %r found %d" % (old, s.count(old))
open(sys.argv[2], "w").write(s.replace(old, new))
PYEOF
}
mut "$ROOT/m1.sh" 'dup = [l for l in live_outside if kk and kk in re.sub(r"\s+", " ", l)]' 'dup = [l for l in live_outside if sc and sc in l]' || ok "mutant1 anchor" 1
new_sb "$ROOT/m1.sh"; printf '%s\n' "$HAND" > "$HOME/crontab.stub"; inst > "$SB/out" 2>&1
chk "MUTANT script-only dup check is caught (it skips the new repos because iptv_apps runs the same script)" bash -c "! [ \$(grep -c '^  ON ' '$SB/out') -eq 10 ]"
mut "$ROOT/m2.sh" 'if [ $lrc -ne 0 ]; then' 'if false; then' || ok "mutant2 anchor" 1
new_sb "$ROOT/m2.sh"; STUB_LIST_FAIL=1 inst --apply > "$SB/out" 2>&1
chk "MUTANT no crontab -l refusal is caught" bash -c "[ -e '$HOME/crontab.writes' ]"
echo "test_supply_cron_installer: $((n-fails)) passed, $fails failed"
[ "$fails" = 0 ]
