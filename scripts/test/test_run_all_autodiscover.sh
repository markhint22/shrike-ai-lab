#!/usr/bin/env bash
# 2026-10-18: run_all.sh must RUN (loudly) any scripts/test/test_*.sh that has no registration line, so a dropped/forgotten registration
# (concurrent agents all append at the same spot; merge "keep both" drops lines) can never silently mean "never runs in the gate".
# Extracts the real safety-net block from run_all.sh and drives it in a scratch dir with stub tests; mutant = the block with its loop broken.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
SB="$(safe_mktemp_dir)" || { echo "  FAIL: cannot create a safe temp dir"; exit 1; }
trap 'safe_rm_rf "$SB"' EXIT
BLK="$SB/block.sh"
awk '/SAFETY NET: a test file that never got a line/{p=1} /^echo; finish/{p=0} p' "$HERE/run_all.sh" > "$BLK"
ok "A0 the safety-net block exists in run_all.sh and is outside finish()" "$([ "$(grep -c 'for _t in test_' "$BLK")" = 1 ] && echo 1 || echo 0)"
drive(){ # $1=block file -> prints the names the stub run_or_notrun ran
  local d="$SB/drive.$RANDOM"; mkdir -p "$d"
  printf 'x\n' > "$d/test_reg_a.sh"; printf 'x\n' > "$d/test_reg_b.sh"; printf 'x\n' > "$d/test_orphan_c.sh"; printf 'x\n' > "$d/test_orphan_prefix.sh"
  printf 'bash test_reg_a.sh || rc=1\nrun_or_notrun test_reg_b.sh\nbash test_orphan_prefix.sh.bak || rc=1\n' > "$d/run_all.sh"
  ( cd "$d" && HERE_RA="$d" && run_or_notrun(){ echo "RAN $1"; } && . "$1" ) 2>&1 | grep '^RAN ' | tr '\n' ' '
}
out="$(drive "$BLK")"
ok "A1 an unregistered test is auto-run" "$(case "$out" in *"RAN test_orphan_c.sh"*) echo 1;; *) echo 0;; esac)"
ok "A2 registered tests (bash form and run_or_notrun form) are NOT run twice" "$(case "$out" in *test_reg_a*|*test_reg_b*) echo 0;; *) echo 1;; esac)"
ok "A3 a name that is only a prefix of a registered one is still treated as unregistered" "$(case "$out" in *"RAN test_orphan_prefix.sh"*) echo 1;; *) echo 0;; esac)"
sed 's/^for _t in test_\*\.sh; do/for _t in; do/' "$BLK" > "$SB/mut.sh"
out="$(drive "$SB/mut.sh")"
ok "B1 MUTANT: with the loop disabled the orphan is NOT run (so A1 detects the defect)" "$(case "$out" in *test_orphan_c*) echo 0;; *) echo 1;; esac)"
un="$(python3 "$HERE/register_new_tests.py" --check 2>/dev/null)"
ok "C1 the real tree has no unregistered test ($un)" "$([ "$un" = "unregistered: none" ] && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
