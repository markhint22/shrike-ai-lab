#!/usr/bin/env bash
# ovn_git_sync.sh size guard (2026-10-14): a 133 MB logs/branch_hygiene.log got into overnight-live history (junk test commits) and GitHub rejected every push for ~20 h.
# The script now refuses to commit/push when a blob that is staged, or in a local commit origin does not have, exceeds OVN_GIT_SYNC_MAX_MB (default 90): it writes an alert,
# unstages (index only), exits 1 and leaves the marker alone.  Real script, throwaway repo + bare origin, fake HOME; OVN_GIT_SYNC_MAX_MB=1 + a 2 MB file stand in for 90/133 MB.
# A mutant (guard condition disabled) must be caught by the same assertions.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
G=""; for c in "$HERE/../../ovn_git_sync.sh" "$HERE/../ovn_git_sync.sh"; do [ -f "$c" ] && { G="$c"; break; }; done
[ -n "$G" ] || { echo "  NOT RUN: ovn_git_sync.sh not found"; exit 77; }   # 77 = cannot run here; run_all.sh reports it (never a silent green)
G="$(cd "$(dirname "$G")" && pwd)/$(basename "$G")"
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
build(){ # $1=script
  W="$T/w.$RANDOM"; HOME_="$W/home"; R="$HOME_/overnight-queue"; BARE="$W/origin.git"
  mkdir -p "$R/scripts" "$R/state"; cp "$1" "$R/ovn_git_sync.sh"; git init -q --bare "$BARE"
  ( cd "$R" || exit 1; git init -q; git remote add origin "$BARE"; echo v1 > scripts/a.sh; git add scripts/a.sh ovn_git_sync.sh; git commit -q -m init; git checkout -q -b overnight-live; git push -q -u origin overnight-live ) >/dev/null 2>&1
}
run_sync(){ ( cd "$HOME_" && env -i HOME="$HOME_" PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" TMPDIR="$W" OVN_GIT_SYNC_RETRY_SLEEP=0 OVN_GIT_SYNC_MAX_MB=1 \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null bash "$R/ovn_git_sync.sh" >"$W/out.log" 2>&1 ); RC=$?; }
head_(){ git -C "$R" rev-parse HEAD; }; remote_(){ git -C "$BARE" rev-parse overnight-live; }
alerts(){ if [ -f "$R/state/alerts.log" ]; then grep -c -F -- "$1" "$R/state/alerts.log" || true; else echo 0; fi; }
bigfile(){ head -c 2097152 /dev/zero > "$1"; }

suite(){ # $1=label $2=script ; sets SCEN_* results via ok()
  local L="$1" S="$2" h0
  build "$S"; bigfile "$R/scripts/big.bin"; echo v2 > "$R/scripts/a.sh"; h0="$(head_)"; run_sync
  ok "$L A: a newly staged 2 MB file (limit 1 MB) is refused: exit 1, HEAD unmoved, origin unmoved" "$([ "$RC" = 1 ] && [ "$(head_)" = "$h0" ] && [ "$(remote_)" = "$h0" ] && echo 1 || echo 0)"
  ok "$L A: alert line names the file and the size guard; marker NOT written; index left clean; file still on disk" "$([ "$(alerts 'REFUSING to commit/push')" = 1 ] && grep -q 'scripts/big.bin' "$R/state/alerts.log" && [ ! -f "$R/state/git_sync_last_ok" ] && [ -z "$(git -C "$R" diff --cached --name-only)" ] && [ -f "$R/scripts/big.bin" ] && echo 1 || echo 0)"
  build "$S"; bigfile "$R/scripts/big.bin"; git -C "$R" add scripts/big.bin; git -C "$R" commit -q -m "junk: big blob already committed locally"; h0="$(remote_)"; run_sync
  ok "$L B: a big blob already in an UNPUSHED local commit blocks the push (the 2026-10-14 case): exit 1, origin unmoved" "$([ "$RC" = 1 ] && [ "$(remote_)" = "$h0" ] && [ "$(alerts 'REFUSING to commit/push')" = 1 ] && echo 1 || echo 0)"
  build "$S"; echo v2 > "$R/scripts/a.sh"; run_sync
  ok "$L C control: a normal change is committed and pushed, marker written, no alert" "$([ "$RC" = 0 ] && [ "$(head_)" = "$(remote_)" ] && [ -f "$R/state/git_sync_last_ok" ] && [ "$(alerts 'REFUSING')" = 0 ] && echo 1 || echo 0)"
}
SUITE_RES="$T/res"
suite REAL "$G"
# mutant: guard disabled -> assertions A/B must flip (the same suite is run again and its FAIL count is inverted)
python3 - "$G" "$T/mut.sh" <<'PY'
import sys
s = open(sys.argv[1]).read(); a = 'if [ -n "$big" ]; then'
assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, 'if false; then'))
PY
P0=$P; F0=$F; suite MUTANT "$T/mut.sh" >/dev/null   # its expected FAIL lines are the proof, not output
mp=$((P-P0)); mf=$((F-F0))
# restate: in the mutant run A+B (3 assertions) must FAIL and C (1) pass
ok "MUTATION (size guard disabled): the A/B assertions fail (3 expected FAILs seen: $mf) and the control still passes" "$([ "$mf" = 3 ] && [ "$mp" = 1 ] && echo 1 || echo 0)"
F=$((F-mf)); P=$((P-mp))   # the mutant's own FAIL lines were the proof, they are not suite failures
ok "the default limit is 90 MB" "$(grep -q 'OVN_GIT_SYNC_MAX_MB:-90' "$G" && echo 1 || echo 0)"
echo; echo "$P passed, $F failed"; [ "$F" -eq 0 ]
