#!/usr/bin/env bash
# ovn_auto_research.sh daily-cap ESCALATION (package supply-ledger, 2026-10-13): xlite starved 15h while the log said "daily cap reached (2/2)" for ~22h.
# ovn_supply_ledger.py leaves state/supply_escalate_<repo> (JSON {repo, day, ...}) on the box; when the cap is reached the Mac job reads those markers over ssh:
#   shadow (DEFAULT) = log what it would allow, change nothing   on = up to OVN_AR_ESCALATE_MAX (2) extra passes above MAX_PER_DAY, for the marked repos only,
#   only while they have been starving >= 3h, never past cap+2   off = no extra ssh read.
# Hermetic (lib_ar_fixture.sh): temp HOME/state, stub ssh/scp/claude, the "box" is a temp dir. Assertions read run output, the stub's call log and the stub ssh log.
# No `x | grep -q`, no kill -0. Mutation checks at the bottom run on a scratch copy of the script.
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../ovn_auto_research.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/../ovn_auto_research.sh"
VALIDATOR="$HERE/../../ovn_auto_research_validate.py"; [ -f "$VALIDATOR" ] || VALIDATOR="$HERE/../ovn_auto_research_validate.py"
. "$HERE/lib_ar_fixture.sh"
# HERMETIC CAPS (2026-10-15): every scenario below assumes the caps in ESC_PIN (2/day, 2/run, allowlist iptv_apps + xlite, +2 escalation, 3h floor).
# The script's own defaults are NOT part of this test and they move: the claude/feature build runs 8/day and 3/run, so the unpinned "cap reached (2/2)" fixture
# was an open cap there and every scenario saw real passes (box deploy6 run: FAIL A-I, "calls: xlite iptv_apps", count 4). The assertions are unchanged.
ESC_PIN=(OVN_AR_MAX_PER_DAY=2 OVN_AR_MAX_PER_RUN=2 'OVN_AR_REPOS=iptv_apps xlite' OVN_AR_PULLABLE_MAX=10 OVN_AR_MIN_STARVE_H=0.5 OVN_AR_ESCALATE_MAX=2 OVN_AR_ESCALATE_MIN_H=3 OVN_AR_COOLDOWN_EMPTY_H=18 OVN_AR_COOLDOWN_PRODUCTIVE_H=2)
esc_run(){ ar_run "${ESC_PIN[@]}" "$@"; }   # the pins come before the scenario's own VAR=val args, and env applies the later assignment, so a scenario can still override a pin
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
MT="$(cd "$(mktemp -d)" && pwd -P)"; trap 'rm -rf "$MT"; [ -n "${T:-}" ] && rm -rf "$T"' EXIT
META='{cat: backend; size: S; multifile: no; research: repo}'
TODAY="$(date +%F)"; YESTERDAY="$(python3 -c 'import time;print(time.strftime("%Y-%m-%d", time.localtime(time.time()-86400)))')"

mutate(){   # <src> <dest> <anchor> <replacement>
  python3 - "$1" "$2" "$3" "$4" 2>/dev/null <<'PY' || { F=$((F+1)); echo "  FAIL mutation anchor missing - the test is stale: $3"; }
import sys
src, dest, a, b = sys.argv[1:5]
s = open(src).read()
assert a in s, "mutation anchor missing: %r" % a
open(dest, "w").write(s.replace(a, b, 1))
PY
}
fresh(){ rm -rf "$STATE" "$CAP"; mkdir -p "$STATE" "$CAP"; : > "$BOX/ssh.log"; rm -f "$BOX/markers.txt"; }
used_is(){ echo "$1" > "$STATE/count_$TODAY"; }
marker(){ printf '{"repo": "%s", "day": "%s", "ts": 1, "mode": "shadow"}\n' "$1" "${2:-$TODAY}" >> "$BOX/markers.txt"; }
calls(){ [ -s "$CAP/calls.log" ] && tr '\n' ' ' < "$CAP/calls.log" || echo -n ""; }
seed(){ for r in iptv_apps xlite billwatch; do ar_roadmap "$r" "- [x] [P1] [done] Old feature of $r — app/old.py $META"; done; }
# the stub ssh learns the one extra command this feature uses: the escalation markers (cat of the state/supply_escalate_* files)
add_marker_stub(){
  python3 - "$FAKEBIN/ssh" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('  "grep -cE"*)', '  "cat ~/overnight-queue/state/supply_escalate_*"*) [ -f "$FAKEBOX/markers.txt" ] && cat "$FAKEBOX/markers.txt" ;;\n  "grep -cE"*)', 1)
open(p, "w").write(s)
PY
}

checks(){
  ar_setup "$1" "$VALIDATOR"; add_marker_stub; seed

  # A. cap reached, no marker: exactly the old behaviour
  fresh; used_is 2; ar_starving xlite:9
  esc_run DRY_RUN=1
  grep -aq "daily cap reached (2/2) - skip" "$T/out.txt" && [ -z "$(calls)" ] && echo "1|A: cap reached + no marker -> 'daily cap reached' and no pass" || echo "0|A: cap reached + no marker -> 'daily cap reached' and no pass"

  # B. shadow (default): the marker is seen and logged, nothing is researched
  fresh; used_is 2; ar_starving xlite:9; marker xlite
  esc_run
  grep -aq "ESCALATE (shadow" "$T/out.txt" && grep -aq "supply-floor marker today for: xlite" "$T/out.txt" && grep -aq "daily cap reached (2/2) - skip" "$T/out.txt" && [ -z "$(calls)" ] && echo "1|B: shadow (default) logs the would-be escalation and researches nothing" || echo "0|B: shadow (default) logs the would-be escalation and researches nothing"

  # C. on: one extra pass for the marked repo only (iptv_apps is starving too but has no marker)
  fresh; used_is 2; ar_starving xlite:9 iptv_apps:8; marker xlite
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on
  [ "$(calls)" = "xlite " ] && grep -aq "supply-floor escalation allows up to 2 extra pass(es) for: xlite" "$T/out.txt" && echo "1|C: on -> the marked repo gets a pass above the cap, the unmarked starving repo does not" || echo "0|C: on -> the marked repo gets a pass above the cap, the unmarked starving repo does not [calls: $(calls)]"
  [ "$(cat "$STATE/count_$TODAY")" = 3 ] && echo "1|C2: the extra pass is counted (3 today)" || echo "0|C2: the extra pass is counted (3 today) [got $(cat "$STATE/count_$TODAY" 2>/dev/null)]"

  # D. on, but the marked repo has only been starving 1h (< 3h)
  fresh; used_is 2; ar_starving xlite:1; marker xlite
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on
  [ -z "$(calls)" ] && echo "1|D: starving < 3h -> no extra pass" || echo "0|D: starving < 3h -> no extra pass [calls: $(calls)]"

  # E. on, a marker from YESTERDAY is ignored
  fresh; used_is 2; ar_starving xlite:9; marker xlite "$YESTERDAY"
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on
  [ -z "$(calls)" ] && grep -aq "daily cap reached (2/2) - skip" "$T/out.txt" && echo "1|E: yesterday's marker is ignored" || echo "0|E: yesterday's marker is ignored [calls: $(calls)]"

  # F. on, two marked repos, ONE extra slot left (used=3, cap 2 + 2): exactly one pass
  fresh; used_is 3; ar_starving xlite:9 iptv_apps:8; marker xlite; marker iptv_apps
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on
  [ "$(grep -c . "$CAP/calls.log" 2>/dev/null || echo 0)" = 1 ] && [ "$(cat "$STATE/count_$TODAY")" = 4 ] && echo "1|F: capped at MAX_PER_DAY + 2 (used 3 -> exactly one more pass, then 4)" || echo "0|F: capped at MAX_PER_DAY + 2 [calls: $(calls) count: $(cat "$STATE/count_$TODAY" 2>/dev/null)]"

  # G. on, already at cap + 2: nothing, and the box is not even asked
  fresh; used_is 4; ar_starving xlite:9; marker xlite
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on
  [ -z "$(calls)" ] && grep -aq "daily cap reached (4/2) - skip" "$T/out.txt" && [ "$(grep -c supply_escalate "$BOX/ssh.log")" = 0 ] && echo "1|G: at cap+2 no further pass and no marker read" || echo "0|G: at cap+2 no further pass and no marker read [calls: $(calls)]"

  # H. a marker for a repo outside the research allowlist (billwatch) is ignored
  fresh; used_is 2; ar_starving billwatch:9; marker billwatch
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on
  [ -z "$(calls)" ] && echo "1|H: a marker for a non-allowlisted repo does not buy a pass" || echo "0|H: a marker for a non-allowlisted repo does not buy a pass [calls: $(calls)]"

  # I. off: the markers are not even read
  fresh; used_is 2; ar_starving xlite:9; marker xlite
  esc_run OVN_AUTO_RESEARCH_ESCALATE=off
  [ -z "$(calls)" ] && [ "$(grep -c supply_escalate "$BOX/ssh.log")" = 0 ] && echo "1|I: OVN_AUTO_RESEARCH_ESCALATE=off reads no markers" || echo "0|I: OVN_AUTO_RESEARCH_ESCALATE=off reads no markers"

  # J. under the cap nothing changes and the markers are not read
  fresh; used_is 0; ar_starving xlite:9; marker xlite
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on DRY_RUN=1
  [ "$(calls)" = "xlite " ] && [ "$(grep -c supply_escalate "$BOX/ssh.log")" = 0 ] && echo "1|J: under the cap the normal path runs and no marker is read" || echo "0|J: under the cap the normal path runs and no marker is read [calls: $(calls)]"

  # K. garbage in the marker output (a truncated file, a non-JSON line) never crashes the cap check
  fresh; used_is 2; ar_starving xlite:9; printf 'not json\n{"repo": \n' > "$BOX/markers.txt"; marker xlite
  esc_run OVN_AUTO_RESEARCH_ESCALATE=on
  [ "$(calls)" = "xlite " ] && [ "$(grep -a -c Traceback "$T/out.txt")" = 0 ] && echo "1|K: garbage lines in the marker output are skipped, the valid marker still counts" || echo "0|K: garbage lines in the marker output are skipped [calls: $(calls)]"
  ar_cleanup; T=""
}

echo "== escalation above the daily cap (real script) =="
res="$(checks "$SCRIPT")"
while IFS='|' read -r v name; do [ -n "$name" ] && ok "$name" "[ $v = 1 ]"; done <<EOT
$res
EOT

echo "== mutation checks (scratch copies; each mutant must break at least one scenario) =="
n_mut=0
run_mutant(){   # <label> <anchor> <replacement>
  mutate "$SCRIPT" "$MT/mut.sh" "$2" "$3" || return
  r="$(checks "$MT/mut.sh")"
  if printf '%s\n' "$r" | grep -aq '^0|'; then ok "mutant killed: $1" "true"; else ok "mutant killed: $1" "false"; fi
}
run_mutant "shadow applies the escalation" 'if [ "$ESC_MODE" = on ]; then' 'if [ "$ESC_MODE" != off ]; then'
run_mutant "daily cap check skipped" 'if [ "$used" -ge "$MAX_PER_DAY" ]; then' 'if false; then'
run_mutant "no cap+2 bound" '[ "$used" -lt $(( MAX_PER_DAY + ESC_MAX )) ]' 'true'
run_mutant "escalation not limited to the marked repos" 'OVN_AR_REPOS="$esc_repos"' ':'
run_mutant "starving floor not raised" '&& MIN_STARVE_H="$ESC_MIN_H";;' '&& true;;'
run_mutant "marker day not checked" 'd.get("day") == today and ' ''

echo; echo "auto_research_escalate: $P passed, $F failed"
[ "$F" = 0 ]
