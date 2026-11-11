#!/usr/bin/env bash
# test_q_z4_advisories.sh - Z4 reviewer advisories A1-A3 (2026-11-10). (A4 poll overshoot / first_err scoping and the native-build-on-develop change are tested in test_z4_suite_cron_poll.sh P6 and test_z4_native_build_check.sh N1/N2.)
#   A1 scripts/mac_live_commit_push.sh: a deliberate refusal (rc 6) that lasts >= MAC_REFUSAL_ESCALATE_S (default 72 h) is escalated to a distinct, daily-visible WARN (own alert key + age text); a pass that gets
#      past every refusal clears the streak; MAC_REFUSAL_ESCALATE_S=0 disables the escalation; the first refusal is the plain Z4 WARN.
#   A2 scripts/mac_jobs.manifest: box-deadman's log column is the persistent ~/.box_deadman/deadman.log the script appends to on every run (the old ~/Library/Logs/shrike/box-deadman.launchd.log is never written
#      by the installed plist, so its errors were never scanned).
#   A3 ovn_hygiene_stuck_check.sh hyg_verdict: the claude-lane log is consulted ONLY for a NAMED branch; with no branch its lines would match anything (F4 bogus-recovery class). Removing `[ -n "${2:-}" ]` must fail.
# Hermetic: stub repos + sandbox HOME (lib_mac_fixture.sh), stub ssh/curl, nothing real is reached. Mutants (each must FAIL at least one check): M1 no escalation, M2 streak never cleared, M3 escalation key not distinct,
# M4 manifest back on the launchd log, M5 hyg_verdict consults the claude log with no branch.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_mac_fixture.sh" || exit 1
CP="$MF_SCRIPTS/mac_live_commit_push.sh"; MAN="$MF_SCRIPTS/mac_jobs.manifest"; HP="$MF_SCRIPTS/mac_jobs_health.py"
[ -f "$CP" ] && [ -f "$MAN" ] && [ -f "$HP" ] || { echo "  FAIL: mac job files missing"; exit 1; }
HS="$HERE/../../ovn_hygiene_stuck_check.sh"; [ -f "$HS" ] || { echo "  SKIP: ovn_hygiene_stuck_check.sh not found"; exit 77; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
mf_init
trap 'safe_rm_rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }

# ---------------------------------------------------------------------------------------------- A1
RN=0
fresh() { RN=$((RN+1)); export OVN_MAC_STATE="$T/state$RN"; INT="$T/int$RN"; mkdir -p "$OVN_MAC_STATE"; git clone -q "$ORIGIN" "$INT" 2>/dev/null; git -C "$INT" checkout -q -B claude/feature origin/develop; }
cp_() { # cp_ <repo> <script> [extra env...] -> RC
  local r="$1" s="$2"; shift 2
  env OVN_MAC_JOBS=enforce MAC_LIVE_DIR="$T/nonexistent-live" "$@" timeout 60 bash "$s" "$r" "chore(queue): test pass" CLAUDE_QUEUE.md CLAUDE_QUEUE_DONE.md > "$T/out.txt" 2>&1 < /dev/null; RC=$?
}
a1_checks() { # a1_checks <script>: prints nothing, records ok/FAIL
  local S="$1" since
  fresh; cp_ "$INT" "$S" env -u OVN_BRIDGE_COMMIT_ON_FEATURE
  chk "A1.1 first refusal: rc 6, the plain Z4 WARN (key commit-push-branch), no ESCALATED text, streak stamped" bash -c "[ $RC -eq 6 ] && grep -q '\\[warn\\] commit-push-branch: bridge not committing' '$OVN_MAC_STATE/alerts.log' && ! grep -q ESCALATED '$OVN_MAC_STATE/alerts.log' && [ -s '$OVN_MAC_STATE/refusal_since_commit-push-branch' ]"
  since=$(( $(date +%s) - 80*3600 )); echo "$since" > "$OVN_MAC_STATE/refusal_since_commit-push-branch"
  cp_ "$INT" "$S" env -u OVN_BRIDGE_COMMIT_ON_FEATURE
  chk "A1.2 refusing for 80 h (>= 72 h): rc 6 still (deliberate), ESCALATED WARN under its OWN key with the age" bash -c "[ $RC -eq 6 ] && grep -q '\\[warn\\] commit-push-branch-escalated: ESCALATED: refused for 80h' '$OVN_MAC_STATE/alerts.log'"
  fresh; echo $(( $(date +%s) - 71*3600 )) > "$OVN_MAC_STATE/refusal_since_commit-push-branch"; cp_ "$INT" "$S" env -u OVN_BRIDGE_COMMIT_ON_FEATURE
  chk "A1.3 refusing for 71 h (< 72 h): not escalated yet" bash -c "[ $RC -eq 6 ] && ! grep -q ESCALATED '$OVN_MAC_STATE/alerts.log'"
  fresh; echo $(( $(date +%s) - 400*3600 )) > "$OVN_MAC_STATE/refusal_since_commit-push-branch"; cp_ "$INT" "$S" env -u OVN_BRIDGE_COMMIT_ON_FEATURE MAC_REFUSAL_ESCALATE_S=0
  chk "A1.4 MAC_REFUSAL_ESCALATE_S=0 disables the escalation" bash -c "[ $RC -eq 6 ] && ! grep -q ESCALATED '$OVN_MAC_STATE/alerts.log'"
  fresh; echo $(( $(date +%s) - 80*3600 )) > "$OVN_MAC_STATE/refusal_since_commit-push-branch"; cp_ "$INT" "$S" env -u OVN_BRIDGE_COMMIT_ON_FEATURE MAC_REFUSAL_ESCALATE_S=3600
  chk "A1.5 MAC_REFUSAL_ESCALATE_S is honoured (1 h threshold, 80 h streak)" bash -c "grep -q ESCALATED '$OVN_MAC_STATE/alerts.log'"
  # a pass that gets past every refusal clears the streak: the interactive checkout on develop commits + pushes the queue file
  fresh; git -C "$INT" checkout -q -B develop origin/develop; printf 'tick\n' >> "$INT/CLAUDE_QUEUE.md"
  echo $(( $(date +%s) - 80*3600 )) > "$OVN_MAC_STATE/refusal_since_commit-push-branch"; echo 1 > "$OVN_MAC_STATE/refusal_since_commit-push-feature"
  cp_ "$INT" "$S"
  chk "A1.6 a pass that is not refused (develop) clears the streak files" bash -c "[ $RC -eq 0 ] && ! ls '$OVN_MAC_STATE'/refusal_since_* >/dev/null 2>&1"
  # the feature-branch mode refusals (OVN_BRIDGE_COMMIT_ON_FEATURE=on, e.g. HEAD has unmerged files) escalate with their own key too
  fresh; git -C "$INT" checkout -q -B claude/feature origin/develop; git -C "$INT" remote remove origin; echo $(( $(date +%s) - 80*3600 )) > "$OVN_MAC_STATE/refusal_since_commit-push-feature"
  cp_ "$INT" "$S" OVN_BRIDGE_COMMIT_ON_FEATURE=on
  chk "A1.7 feature-branch mode refusal (fetch impossible) escalates under commit-push-feature-escalated" bash -c "[ $RC -eq 6 ] && grep -q 'commit-push-feature-escalated: ESCALATED' '$OVN_MAC_STATE/alerts.log'"
}
echo "== A1 escalate the deliberate rc 6 refusal after ~72 h"
a1_checks "$CP"

# ---------------------------------------------------------------------------------------------- A2
a2_check() { # a2_check <manifest> : rc 0 when box-deadman's log column resolves to ~/.box_deadman/deadman.log under HOME
  HOME="$T/home" "$PY" - "$MF_SCRIPTS" "$1" <<'PYEOF'
import os, sys, importlib.util
sc, man = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("hp", os.path.join(sc, "mac_jobs_health.py")); hp = importlib.util.module_from_spec(spec); spec.loader.exec_module(hp)
j = [x for x in hp.parse_manifest(man) if x["label"] == "com.shrike.box-deadman"][0]
sys.exit(0 if j["log"] == os.path.join(os.environ["HOME"], ".box_deadman", "deadman.log") and j["hbalt"] == j["log"] else 1)
PYEOF
}
echo "== A2 box-deadman manifest log column"
chk "A2.1 real manifest: box-deadman log = the persistent ~/.box_deadman/deadman.log (same file as hbalt)" a2_check "$MAN"
sed 's#| ~/.box_deadman/deadman.log  *|#| ~/Library/Logs/shrike/box-deadman.launchd.log |#' "$MAN" > "$T/man_old"
a2_check "$T/man_old"; ok "A2.2 the old launchd-log entry fails the same check (M4)" $([ $? -ne 0 ] && echo 0 || echo 1)

# ---------------------------------------------------------------------------------------------- A3
hv_check() { # hv_check <script>: stdout "<verdict-no-branch> <verdict-named>" for a main log that is inconclusive and a claude-lane log that says 'already in develop'
  local d="$T/hv$RANDOM"; mkdir -p "$d"
  printf '[branch-hygiene 2026-11-10 08:05:57] === xlite (/x/xlite) ===\n[branch-hygiene 2026-11-10 08:05:57]   feature branch: overnight/feature\n[branch-hygiene 2026-11-10 08:05:58]   gate-infra-skip: xlite overnight/feature - host storage\n' > "$d/main.log"
  printf '[branch-hygiene 2026-11-10 08:30:05] === xlite (/x/xlite) ===\n[branch-hygiene 2026-11-10 08:30:05]   feature branch: claude/feature\n[branch-hygiene 2026-11-10 08:30:06]   claude/feature already in develop - nothing to land\n' > "$d/claude.log"
  "$PY" -I - "$1" "$d/fn.sh" <<'PYEOF'
import re, sys
s = open(sys.argv[1]).read()
a = s.index("hyg_verdict(){"); b = s.index("# --- 2026-11-04 (Y6/3)")
open(sys.argv[2], "w").write(s[a:b])
PYEOF
  ( HYGIENE_LOG="$d/main.log"; HYGIENE_LOG_CLAUDE="$d/claude.log"; . "$d/fn.sh"; echo "$(hyg_verdict xlite) $(hyg_verdict xlite claude/feature) $(hyg_verdict xlite overnight/feature)" )
}
echo "== A3 hyg_verdict named-branch guard"
out="$(hv_check "$HS")"
chk "A3.1 no branch given: the claude-lane log is NOT consulted (unknown); named claude/feature -> merged; named overnight/feature -> unknown ($out)" bash -c "[ '$out' = 'unknown merged unknown' ]"

# ---------------------------------------------------------------------------------------------- mutants
echo "== mutants"
mut_cp() { # name old new
  local M="$T/mutcp$RANDOM"; mkdir -p "$M"; cp -p "$MF_SCRIPTS/mac_lib.sh" "$M/"
  python3 -I - "$CP" "$M/mac_live_commit_push.sh" "$2" "$3" <<'PY'
import sys
s = open(sys.argv[1]).read(); a, b = sys.argv[3], sys.argv[4]
assert s.count(a) >= 1, "anchor not found: " + a
open(sys.argv[2], "w").write(s.replace(a, b, 1))
PY
  local before=$fails nb=$n; a1_checks "$M/mac_live_commit_push.sh" >"$T/mut.out" 2>&1
  local got; got="$(grep -c '^  FAIL' "$T/mut.out")"; fails=$before; n=$((nb+1))
  if [ "$got" -ge 1 ]; then echo "  ok   mutant caught: $1 ($got check(s) fail)"; else echo "  FAIL mutant NOT caught: $1"; fails=$((fails+1)); fi
}
mut_cp "M1 no escalation" 'if [ "$esc" -gt 0 ] && [ "$age" -ge "$esc" ]; then' 'if false; then'
mut_cp "M2 streak never cleared" 'refusal_clear   # got past' ': # got past'
mut_cp "M3 escalation reuses the plain key" 'REFUSAL_KEY="$1-escalated"; REFUSAL_MSG=' 'REFUSAL_KEY="$1"; REFUSAL_MSG='
mut_cp "M6 age threshold ignored (escalates at once)" '[ "$age" -ge "$esc" ]' '[ "$age" -ge 0 ]'
mut_cp "M7 default threshold 1 h not 72 h" 'esc="${MAC_REFUSAL_ESCALATE_S:-259200}"' 'esc="${MAC_REFUSAL_ESCALATE_S:-3600}"'
M5="$T/hs_mut.sh"
python3 -I - "$HS" "$M5" <<'PY'
import sys
s = open(sys.argv[1]).read(); old = '&& [ -n "${2:-}" ]; then'
assert s.count(old) == 1; open(sys.argv[2], "w").write(s.replace(old, '; then'))
PY
out5="$(hv_check "$M5")"; n=$((n+1))
if [ "$out5" != "unknown merged unknown" ]; then echo "  ok   mutant caught: M5 hyg_verdict consults the claude log with no branch ($out5)"; else echo "  FAIL mutant NOT caught: M5"; fails=$((fails+1)); fi
echo; echo "q z4 advisories: $((n-fails))/$n passed"; [ "$fails" = 0 ]
