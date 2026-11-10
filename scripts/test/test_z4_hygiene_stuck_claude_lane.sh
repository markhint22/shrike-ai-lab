#!/usr/bin/env bash
# Z4 (2026-11-07): ovn_hygiene_stuck_check.sh recovery for a stuck claude/feature branch. The claude lane logs to logs/branch_hygiene_claude.log, the check only read logs/branch_hygiene.log
# (whose last section for the repo is the overnight/feature lane) -> xlite stayed "stuck" since 11-06 12:05 and logged "recovery UNCONFIRMED" every hour although claude/feature was already in develop.
# Scenarios: (A) claude/feature stuck, claude log says 'already in develop' -> recovered once, markers cleared; (B) claude log still says MERGE CONFLICT -> stays stuck;
# (C) overnight/feature stuck + claude lane 'already in develop' in the CLAUDE log -> NOT recovered (F4 class: another branch's result must not recover it); (D) repeat run after recovery logs nothing stuck.
# Mutant: the claude-log fallback removed -> (A) must fail.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
H="${OVN_HYGIENE_STUCK_CHECK:-$HERE/../../ovn_hygiene_stuck_check.sh}"
[ -f "$H" ] || { echo "  SKIP: ovn_hygiene_stuck_check.sh not found"; exit 77; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
. "$(cd "$(dirname "$0")" && pwd)/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: Z10 mac test sandbox"; exit 1; }   # Z10: real ssh/curl/ntfy delivery impossible from this test
n=0; fails=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
hdr(){ printf '[branch-hygiene 2026-11-07 %s] === %s (/x/%s) ===\n[branch-hygiene 2026-11-07 %s]   feature branch: %s\n' "$1" "$2" "$2" "$1" "$3"; }
mk() { # mk <script> -> sets WD ALERTS
  local tmp="$T/c$RANDOM$$"; WD="$tmp/overnight-queue"; mkdir -p "$WD/state" "$WD/logs" "$tmp/bin"; cp "$1" "$WD/ovn_hygiene_stuck_check.sh"; TMP="$tmp"; ALERTS="$tmp/alerts.log"; : > "$ALERTS"
  printf '#!/usr/bin/env bash\nfor a in "$@"; do echo "$a" >> "%s"; done\nexit 0\n' "$ALERTS" > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/esc.sh"; chmod +x "$tmp/esc.sh"
}
run() { ( cd "$WD" && HOME="$TMP" PATH="$TMP/bin:$PATH" OVN_ESCALATE_CMD="$TMP/esc.sh" bash ovn_hygiene_stuck_check.sh > "$TMP/run.out" 2>&1 ); }
seed() { # seed <feat>: stuck 5h, alerted, no review flag (the live xlite shape)
  local now; now=$(date +%s); st="$WD/state"
  echo $((now - 5*3600)) > "$st/hygiene_stuck_since_xlite"; echo $((now - 3600)) > "$st/hygiene_stuck_alerted_xlite"; echo "$1" > "$st/hygiene_stuck_feat_xlite"
  { hdr 08:05:57 xlite overnight/feature; echo '[branch-hygiene 2026-11-07 08:06:29]   MERGED xlite overnight/feature (+1) -> develop'; } > "$WD/logs/branch_hygiene.log"
}
scen() { local S="$1"
  mk "$S"; seed claude/feature
  { hdr 08:30:05 xlite claude/feature; echo '[branch-hygiene 2026-11-07 08:30:06]   claude/feature already in develop — nothing to land'; } > "$WD/logs/branch_hygiene_claude.log"
  run
  chk "A: stuck claude/feature + claude log 'already in develop' -> one recovery note, markers cleared" bash -c "[ \$(grep -c 'Branch hygiene recovered: xlite' '$ALERTS') -eq 1 ] && [ ! -f '$WD/state/hygiene_stuck_since_xlite' ] && ! grep -q UNCONFIRMED '$TMP/run.out'"
  : > "$ALERTS"; run
  chk "D: the next run after recovery stays silent (no stuck line, no second note)" bash -c "! grep -q 'recovered' '$ALERTS' && ! grep -q 'UNCONFIRMED' '$TMP/run.out'"
  mk "$S"; seed claude/feature
  { hdr 08:30:05 xlite claude/feature; echo '[branch-hygiene 2026-11-07 08:30:06]   MERGE CONFLICT for xlite (conflicted: a.gd) - not merging'; } > "$WD/logs/branch_hygiene_claude.log"
  run
  chk "B: claude log still MERGE CONFLICT -> NOT recovered, stuck markers kept" bash -c "! grep -q 'Branch hygiene recovered' '$ALERTS' && [ -f '$WD/state/hygiene_stuck_since_xlite' ]"
  mk "$S"; seed overnight/feature
  { hdr 08:05:57 xlite overnight/feature; echo '[branch-hygiene 2026-11-07 08:06:29]   gate-infra-skip: xlite overnight/feature - host storage'; } > "$WD/logs/branch_hygiene.log"
  { hdr 08:30:05 xlite claude/feature; echo '[branch-hygiene 2026-11-07 08:30:06]   claude/feature already in develop — nothing to land'; } > "$WD/logs/branch_hygiene_claude.log"
  run
  chk "C: stuck overnight/feature must NOT be recovered by the claude lane's 'already in develop' (F4 class)" bash -c "! grep -q 'Branch hygiene recovered' '$ALERTS' && [ -f '$WD/state/hygiene_stuck_since_xlite' ]"
}
scen "$H"
M="$T/mut.sh"
python3 - "$H" "$M" <<'PY'
import sys
s = open(sys.argv[1]).read(); old = 'v2="$(hyg_verdict_in "$HYGIENE_LOG_CLAUDE" "$@")"'
assert s.count(old) == 1; open(sys.argv[2], "w").write(s.replace(old, 'v2=""'))
PY
[ -f "$M" ] || { ok "mutant file created" 1; }
echo "== mutant: claude-log fallback removed"; mk "$M"; seed claude/feature
{ hdr 08:30:05 xlite claude/feature; echo '[branch-hygiene 2026-11-07 08:30:06]   claude/feature already in develop - nothing to land'; } > "$WD/logs/branch_hygiene_claude.log"; run
chk "M1 (no claude-log fallback) is caught: old 'recovery UNCONFIRMED' behaviour, no recovery note" bash -c "! grep -q 'Branch hygiene recovered' '$ALERTS' && grep -q UNCONFIRMED '$TMP/run.out'"
echo; echo "z4 hygiene stuck claude lane: $((n-fails))/$n passed"; [ "$fails" = 0 ]
