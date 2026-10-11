#!/usr/bin/env bash
# 2026-10-11 (r11 acct, xlite X8): the roadmap-feature floor. Live: xlite sat dry (backlog 0, no [ready] roadmap feature) for 12h then again 4.9h+ on 10-10/10-11, the planner logged the SAME
# "xlite: backlog low (0) but no [ready] roadmap feature (needs Claude research?)" line every ~69 s (945x per lane in 24h) and nothing in alerts.log named the floor.
#   A  ovn_research_trigger_check.py (the starving timer): ONE alerts.log warn per lane per local day once "backlog low (0)" + no [ready] feature has persisted > 6 h
#   B  ovn_planner.sh say_rl (queue_refill.sh's log_rl for the planner log): the identical dry line is written once per PLN_LOG_REPEAT_S, a changed line / reset prints at once
#   C  the REAL ovn_planner.sh end to end on the hermetic fixture (Linux, needs flock): 4 dry passes -> ONE log line (before: 4)
#   D  MUTATION controls
# bash 3.2 ok except C (flock).
set -uo pipefail
unset OVN_FLOOR_ALERT OVN_FLOOR_ALERT_H OVN_FLOOR_ALERT_MAX_BACKLOG PLN_LOG_REPEAT_S OVN_TRIGGER_MONOTONIC OVN_TRIGGER_PULLABLE_MIN OVN_DIR   # hermetic
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"
TC="$Q/scripts/ovn_research_trigger_check.py"; PL="$Q/ovn_planner.sh"
[ -f "$TC" ] && [ -f "$PL" ] || { echo "  SKIP: scripts not found"; exit 0; }
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo "== A: the floor alert (ovn_research_trigger_check.py, throwaway HOME)"
cat > "$tmp/floor_check.py" <<'PYEOF'
import json, os, subprocess, sys, tempfile, time
TC = sys.argv[1]
def stamp(ago_h): return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - ago_h * 3600))
STARVE = "backlog low (%d) but no [ready] roadmap feature (needs Claude research?)"
def home():
    h = tempfile.mkdtemp(prefix="floor-"); os.makedirs(os.path.join(h, "overnight-queue", "logs")); os.makedirs(os.path.join(h, "overnight-queue", "state")); return h
def planner_log(h, rows):
    with open(os.path.join(h, "overnight-queue", "logs", "ovn_planner.log"), "w") as f:
        for ago_h, repo, msg in rows: f.write("%s %s: %s\n" % (stamp(ago_h), repo, msg))
def run(h, env=None, hours="2"):
    e = dict(os.environ); e["HOME"] = h; e.pop("OVN_DIR", None); e.update(env or {})
    return subprocess.run([sys.executable, TC, hours, os.path.join(h, "overnight-queue", "logs", "ovn_planner.log")], capture_output=True, text=True, env=e, timeout=60)
def alerts(h):
    p = os.path.join(h, "overnight-queue", "state", "alerts.log")
    return [l for l in open(p).read().splitlines() if "roadmap-feature floor" in l] if os.path.exists(p) else []
def marker(h):
    p = os.path.join(h, "overnight-queue", "state", "roadmap_floor_alerted.json")
    return json.load(open(p)) if os.path.exists(p) else {}
out = {}
def streak(repo, start_h, n, every_h=0.5):   # starved lines from `start_h` hours ago down to now, one per `every_h`
    rows, t = [], start_h
    while t >= 0: rows.append((t, repo, STARVE % n)); t -= every_h
    return rows

# 1. xlite: backlog 0, starved 7h -> exactly one warn, in the alerts.log format, naming the lane and the fix
h = home(); planner_log(h, streak("xlite", 7, 0)); r = run(h); a = alerts(h)
out["one_alert"] = len(a) == 1
out["format"] = bool(a) and "] warn | ongoing-xlite | roadmap-feature floor: xlite has had backlog 0 and no [ready] roadmap feature for 7." in a[0] and "roadmap/xlite.md" in a[0]
out["marker"] = marker(h).get("xlite") == time.strftime("%Y-%m-%d", time.localtime())
# 2. the very same state on every later run the same day: still ONE line
for _ in range(3): run(h)
out["dedup_same_day"] = len(alerts(h)) == 1
# 3. the next local day (marker is yesterday) -> a second line
mp = os.path.join(h, "overnight-queue", "state", "roadmap_floor_alerted.json"); json.dump({"xlite": "2000-01-01"}, open(mp, "w")); run(h)
out["next_day"] = len(alerts(h)) == 2 and marker(h)["xlite"] == time.strftime("%Y-%m-%d", time.localtime())
# 4. the starving state file is unchanged in shape (no internal fields leak to the session-side poller)
st = json.load(open(os.path.join(h, "overnight-queue", "state", "research_trigger_starving.json")))
out["state_clean"] = st["starving"] and all(set(x) <= {"repo", "starving_since", "hours", "pullable"} for x in st["starving"])
# 5. only 5h -> below the 6h floor: starving (the timer sees it) but no alert
h = home(); planner_log(h, streak("xlite", 5, 0)); run(h)
out["below_floor"] = alerts(h) == [] and marker(h) == {}
# 6. backlog low (3) for 8h is thin, not the floor -> no alert
h = home(); planner_log(h, streak("gitlark", 8, 3)); run(h)
out["not_zero_backlog"] = alerts(h) == []
# 7. two lanes at the floor -> one line each
h = home(); planner_log(h, streak("xlite", 7, 0) + streak("iptv_apps", 9, 0)); run(h); a = alerts(h)
out["per_lane"] = len(a) == 2 and any("ongoing-xlite" in x for x in a) and any("ongoing-iptv_apps" in x for x in a)
# 8. a decomposition event clears the streak -> no alert
h = home(); rows = streak("xlite", 8, 0, 0.5)[:8] + [(3.5, "xlite", "appended 8 27B-decomposed items to backlog; marked feature [decomposed]")] + streak("xlite", 3, 0, 0.5)
planner_log(h, rows); run(h)
out["decomp_clears"] = alerts(h) == []   # only 3h of streak since the decomposition
# 9. kill switch and threshold override
h = home(); planner_log(h, streak("xlite", 7, 0)); run(h, {"OVN_FLOOR_ALERT": "off"})
out["kill_switch"] = alerts(h) == []
h = home(); planner_log(h, streak("xlite", 2.5, 0)); run(h, {"OVN_FLOOR_ALERT_H": "1"})
out["threshold_env"] = len(alerts(h)) == 1
h = home(); planner_log(h, streak("gitlark", 8, 2)); run(h, {"OVN_FLOOR_ALERT_MAX_BACKLOG": "2"})
out["max_backlog_env"] = len(alerts(h)) == 1
# 10. an unwritable alerts.log (a directory) never crashes the timer, writes no marker (the next run retries) and the starving file is still written
h = home(); planner_log(h, streak("xlite", 7, 0)); os.makedirs(os.path.join(h, "overnight-queue", "state", "alerts.log")); r = run(h)
out["unwritable_safe"] = r.returncode == 0 and marker(h) == {} and os.path.exists(os.path.join(h, "overnight-queue", "state", "research_trigger_starving.json"))
# 11. OVN_TRIGGER_MONOTONIC=off (the legacy walk-back rule) alerts too
h = home(); planner_log(h, streak("xlite", 7, 0)); run(h, {"OVN_TRIGGER_MONOTONIC": "off"})
out["legacy_mode"] = len(alerts(h)) == 1
# 12. a log with no starved lines: nothing, no markers
h = home(); planner_log(h, [(1, "xlite", "xlite: backlog=40 >= 10 - no planning needed")]); run(h)
out["healthy_quiet"] = alerts(h) == [] and marker(h) == {}
print(json.dumps(out))
PYEOF
FR="$("$PY" "$tmp/floor_check.py" "$TC" 2>/dev/null | tail -1)"
for k in one_alert:"A1 xlite starved 7h at backlog 0 => exactly ONE warn line" format:"A2 the line is '[ts] warn | ongoing-xlite | roadmap-feature floor: ... for 7.xh ... roadmap/xlite.md' (alerts.log format)" marker:"A3 the dedup marker holds today's date" dedup_same_day:"A4 three more runs the same day => still ONE line" next_day:"A5 a marker from an earlier day => the next day alerts again (one per lane per DAY)" state_clean:"A6 research_trigger_starving.json keeps its shape (no internal _h leaked)" below_floor:"A7 5h < 6h floor => starving but NO alert, no marker" not_zero_backlog:"A8 'backlog low (3)' for 8h is thin, not the floor => no alert" per_lane:"A9 two lanes at the floor => one line EACH" decomp_clears:"A10 a decomposition event clears the streak => no alert" kill_switch:"A11 OVN_FLOOR_ALERT=off => no alert" threshold_env:"A12 OVN_FLOOR_ALERT_H=1 lowers the floor (2.5h alerts)" max_backlog_env:"A13 OVN_FLOOR_ALERT_MAX_BACKLOG=2 widens what counts as the floor" unwritable_safe:"A14 an unwritable alerts.log never crashes the timer, writes no marker, the starving file is still written" legacy_mode:"A15 OVN_TRIGGER_MONOTONIC=off (legacy walk-back streak) alerts too" healthy_quiet:"A16 a healthy planner log => no alert, no marker"; do
  ok "${k#*:}" "printf '%s' '$FR' | jq -e '.${k%%:*}'"
done

echo "== B: say_rl (the planner's log rate limit, REAL function)"
FN="$(sed -n '/^say_rl(){/,/^}/p' "$PL")"; FN2="$(sed -n '/^say_rl_reset(){/p' "$PL")"
[ -n "$FN" ] && [ -n "$FN2" ] || { echo "  FAIL: say_rl()/say_rl_reset() not defined in ovn_planner.sh (the defect: every dry pass logged the line)"; exit 1; }
BL="$tmp/b"; mkdir -p "$BL/state"; PLOG="$BL/planner.log"
run_b(){ ( cd "$BL" && STATE_DIR=state LOG="$PLOG" PLN_LOG_REPEAT_S="${PLN_LOG_REPEAT_S:-1800}" bash -c "say(){ echo \"\$(date '+%F %T') \$*\" >> \"\$LOG\"; }; $FN
$FN2
$1" ); }
DRY='xlite: backlog low (0) but no [ready] roadmap feature (needs Claude research?)'
fresh(){ : > "$PLOG"; rm -f "$BL"/state/pl_log_*; }   # an empty log AND no remembered signature
fresh; run_b "for i in 1 2 3 4 5 6 7 8; do say_rl xlite '$DRY'; done"
ok "B1 8 identical dry passes => ONE line (was 8)" "[ \"\$(grep -c 'backlog low (0)' '$PLOG')\" = 1 ]"
fresh; run_b "say_rl xlite '$DRY'; say_rl iptv_apps 'iptv_apps: backlog low (0) but no [ready] roadmap feature (needs Claude research?)'; say_rl xlite '$DRY'"
ok "B2 the key is per lane: a second lane prints its own first line" "[ \"\$(grep -c 'backlog low (0)' '$PLOG')\" = 2 ] && grep -q 'iptv_apps: backlog low' '$PLOG'"
fresh; run_b "say_rl xlite '$DRY'; say_rl xlite 'xlite: backlog low (2) but no [ready] roadmap feature (needs Claude research?)'; say_rl xlite '$DRY'"
ok "B3 a CHANGED message (backlog 0 -> 2 -> 0) prints every time" "[ \"\$(grep -c 'backlog low' '$PLOG')\" = 3 ]"
fresh; run_b "say_rl xlite '$DRY'; say_rl_reset xlite; say_rl xlite '$DRY'"
ok "B4 say_rl_reset (a [ready] feature appeared and was decomposed) lets the identical next dry line print" "[ \"\$(grep -c 'backlog low (0)' '$PLOG')\" = 2 ]"
fresh; PLN_LOG_REPEAT_S=0 run_b "for i in 1 2 3; do say_rl xlite '$DRY'; done"
ok "B5 PLN_LOG_REPEAT_S=0 = the old behaviour (every pass logs)" "[ \"\$(grep -c 'backlog low (0)' '$PLOG')\" = 3 ]"
fresh; run_b "say_rl xlite '$DRY'"; old=$(( $(date +%s) - 1900 )); sed -i.bak "1s/.*/$old/" "$BL/state/pl_log_xlite" 2>/dev/null; rm -f "$BL/state/pl_log_xlite.bak"; run_b "say_rl xlite '$DRY'"
ok "B6 after the repeat window (1900s > 1800s) the identical line prints once more (liveness)" "[ \"\$(grep -c 'backlog low (0)' '$PLOG')\" = 2 ]"
ok "B7 a garbled stamp file is treated as 'never printed' (prints, never crashes)" "printf 'garbage\n' > '$BL/state/pl_log_xlite'; : > '$PLOG'; run_b \"say_rl xlite '$DRY'\"; [ \"\$(grep -c 'backlog low (0)' '$PLOG')\" = 1 ]"
ok "B8 the planner uses say_rl (not say) for the dry line, and resets the key when a [ready] feature exists" "grep -q '^    say_rl \"\$r\" \"\$r: backlog low (\$bcount) but no \[ready\] roadmap feature (needs Claude research?)\"' '$PL' && grep -q '^  say_rl_reset \"\$r\"' '$PL' && ! grep -q '^    say \"\$r: backlog low' '$PL'"

echo "== C: the REAL ovn_planner.sh, hermetic (Linux + flock)"
if command -v flock >/dev/null 2>&1 && [ "$(uname)" = Linux ]; then
  H="$tmp/home"; O="$H/overnight-queue"; mkdir -p "$O/state" "$O/logs" "$O/roadmap" "$O/backlog" "$O/repos/xlite"
  printf '# xlite roadmap\n- [x] [P1] [decomposed] old feature\n- [ ] [P2] [needs-research] a future feature\n' > "$O/roadmap/xlite.md"; : > "$O/backlog/xlite.md"
  planner(){ ( cd "$O" && HOME="$H" bash "$PL" xlite >/dev/null 2>&1 ); }
  for i in 1 2 3 4; do planner; done
  ok "C1 four dry passes of the real planner => ONE 'backlog low (0) but no [ready] roadmap feature' line (before: 4)" "[ \"\$(grep -c 'backlog low (0) but no \[ready\] roadmap feature' '$O/logs/ovn_planner.log')\" = 1 ]"
  ok "C2 the needs-research marker bookkeeping still ran (state/ovn_needs_research_xlite)" "[ -f '$O/state/ovn_needs_research_xlite' ]"
  rm -f "$O/logs/ovn_planner.log" "$O/state/pl_log_xlite"; for i in 1 2 3; do ( cd "$O" && HOME="$H" PLN_LOG_REPEAT_S=0 bash "$PL" xlite >/dev/null 2>&1 ); done
  ok "C3 PLN_LOG_REPEAT_S=0 => the old behaviour on the real script (3 passes, 3 lines)" "[ \"\$(grep -c 'backlog low (0) but no \[ready\] roadmap feature' '$O/logs/ovn_planner.log')\" = 3 ]"
else
  echo "  SKIP C: needs Linux + flock (the planner takes flock -n 228); run on the box"
fi

echo "== D: MUTATION controls"
mkdir -p "$tmp/mut"; cp "$Q"/scripts/*.py "$tmp/mut/" 2>/dev/null
"$PY" - "$TC" "$PL" "$tmp" <<'PYEOF'
import sys
tc = open(sys.argv[1]).read(); pl = open(sys.argv[2]).read()
def mut(s, a, b, path):
    assert s.count(a) == 1, a
    open(path, "w").write(s.replace(a, b))
t = sys.argv[3]
mut(tc, '        if r.get("_h", 0.0) <= floor_h or seen.get(repo) == today:', '        if r.get("_h", 0.0) <= floor_h:', t + "/mut/m_nodedup.py")
mut(tc, '        if n is None or n > max_b:\n            continue\n', '', t + "/mut/m_nobacklog.py")
mut(tc, '        if r.get("_h", 0.0) <= floor_h or seen.get(repo) == today:', '        if seen.get(repo) == today:', t + "/mut/m_nofloor.py")
mut(pl, '  if [ "$PLN_LOG_REPEAT_S" -gt 0 ]; then', '  if false; then', t + "/m_planner_norl.sh")
PYEOF
mfloor(){ "$PY" - "$1" "$2" <<'PYEOF'
import json, os, subprocess, sys, tempfile, time
tc, case = sys.argv[1], sys.argv[2]
h = tempfile.mkdtemp(); os.makedirs(h + "/overnight-queue/logs"); os.makedirs(h + "/overnight-queue/state")
def st(ago): return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(time.time() - ago * 3600))
n = {"nodedup": 0, "nobacklog": 3, "nofloor": 0}[case]; span = 5 if case == "nofloor" else 7
with open(h + "/overnight-queue/logs/ovn_planner.log", "w") as f:
    t = span
    while t >= 0: f.write("%s xlite: backlog low (%d) but no [ready] roadmap feature (needs Claude research?)\n" % (st(t), n)); t -= 0.5
e = dict(os.environ); e["HOME"] = h
for _ in range(3): subprocess.run([sys.executable, tc, "2", h + "/overnight-queue/logs/ovn_planner.log"], capture_output=True, env=e, timeout=60)
p = h + "/overnight-queue/state/alerts.log"
print(len([l for l in open(p) if "roadmap-feature floor" in l]) if os.path.exists(p) else 0)
PYEOF
}
ok "D1 MUTATION: without the per-day dedup the same-day reruns write 3 lines (A4 would fail)" "[ \"\$(mfloor '$tmp/mut/m_nodedup.py' nodedup)\" = 3 ]"
ok "D2 MUTATION: without the backlog==0 condition a thin-but-not-empty lane alerts (A8 would fail)" "[ \"\$(mfloor '$tmp/mut/m_nobacklog.py' nobacklog)\" = 1 ]"
ok "D3 MUTATION: without the 6h floor a 5h streak alerts (A7 would fail)" "[ \"\$(mfloor '$tmp/mut/m_nofloor.py' nofloor)\" = 1 ]"
ok "D4 control: the unmutated script gives 1 (dry 7h), 0 (backlog 3), 0 (5h)" "[ \"\$(mfloor '$TC' nodedup)\" = 1 ] && [ \"\$(mfloor '$TC' nobacklog)\" = 0 ] && [ \"\$(mfloor '$TC' nofloor)\" = 0 ]"
FNM="$(sed -n '/^say_rl(){/,/^}/p' "$tmp/m_planner_norl.sh")"
: > "$PLOG"; rm -f "$BL/state/pl_log_xlite"; ( cd "$BL" && STATE_DIR=state LOG="$PLOG" PLN_LOG_REPEAT_S=1800 bash -c "say(){ echo \"\$(date '+%F %T') \$*\" >> \"\$LOG\"; }; $FNM
for i in 1 2 3; do say_rl xlite '$DRY'; done" )
ok "D5 MUTATION: a say_rl that never suppresses logs every pass (B1 would fail)" "[ \"\$(grep -c 'backlog low (0)' '$PLOG')\" = 3 ]"

echo "roadmap floor: $P passed, $F failed"; [ "$F" -eq 0 ]
