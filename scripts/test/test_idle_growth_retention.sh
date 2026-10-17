#!/usr/bin/env bash
# 2026-10-13 (night review platform P9, "fix-the-fixer" items): the idle loop produced 863 passes/day (a run dir + a report each), the cron log cap was dry-run only and nothing pruned
# run dirs or reports, and the doc executor's shadow breadcrumb 'parked-idle' was written on every idle pass (656 identical rows).
#   A. ovn_idle_wait_seconds (lib_fixup.sh): 60 s up to an hour of all-idle passes, then doubling every 30 min, capped at 300 s; kill switches; garbage env.
#   B. ovn_parked_idle_should_log + the REAL ovn_doc_reroute_item: one parked-idle row per repo per hour, a new row when the count changes.
#   C. ovn_log_cap.sh retention: run dirs and reports older than 14 days, but the newest 200 are never candidates (box_deadman/ovn_notify heartbeat), exact-name matching only.
#   D. the runner: an all-idle pass waits the computed time and starts/continues state/idle_since; a pass with work clears it (needs util-linux flock: skipped on the Mac).
#   E. freshness invariant: the maximum idle wait stays far below the dead-man's / silent-queue thresholds.
#   M. mutation controls on a scratch copy of the tree.
# IDLE_TEST_SECTIONS="A,B" limits a (nested mutation) run to those sections.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="$(cd "$HERE/../.." && pwd)"; S="$Q/scripts"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
SECT="${IDLE_TEST_SECTIONS:-A,B,C,D,E,M}"
want(){ case ",$SECT," in *",$1,"*) return 0;; esac; return 1; }
W="$(mktemp -d)" || exit 1; W="$(cd "$W" && pwd -P)"; trap 'rm -rf "$W"' EXIT
export HOME="$W/home"; mkdir -p "$HOME"
# shellcheck disable=SC1090
. "$S/lib_item_select.sh"; . "$S/lib_fixup.sh"

if want A; then
echo "== A. growing idle wait =="
D="$W/idle"; mkdir -p "$D"; T0=1800000000
w(){ ovn_idle_wait_seconds "$D" "$1"; }
rm -f "$D/idle_since"
ok "A1 first all-idle pass: 60 s, and state/idle_since is written with 'now'" "[ \"\$(w $T0)\" = 60 ] && [ \"\$(cat '$D/idle_since')\" = $T0 ]"
ok "A2 a second call does not move idle_since (the streak start is kept)" "[ \"\$(w $((T0 + 500)))\" = 60 ] && [ \"\$(cat '$D/idle_since')\" = $T0 ]"
ok "A3 exactly one hour into the streak: still 60 s" "[ \"\$(w $((T0 + 3600)))\" = 60 ]"
ok "A4 one second over the hour: 120 s" "[ \"\$(w $((T0 + 3601)))\" = 120 ]"
ok "A5 1h29m59s: 120 s; 1h30m: 240 s" "[ \"\$(w $((T0 + 5399)))\" = 120 ] && [ \"\$(w $((T0 + 5400)))\" = 240 ]"
ok "A6 1h59m59s: 240 s; 2h: capped at 300 s; 10 h: still 300 s" "[ \"\$(w $((T0 + 7199)))\" = 240 ] && [ \"\$(w $((T0 + 7200)))\" = 300 ] && [ \"\$(w $((T0 + 36000)))\" = 300 ]"
ok "A7 ovn_idle_clear ends the streak: the file is gone and the next pass is 60 s again from a fresh idle_since" "{ ovn_idle_clear '$D'; [ ! -e '$D/idle_since' ]; } && [ \"\$(w $((T0 + 40000)))\" = 60 ] && [ \"\$(cat '$D/idle_since')\" = $((T0 + 40000)) ]"
ok "A8 OVN_IDLE_GROW=off: flat OVN_IDLE_SLEEP_S whatever the streak length" "[ \"\$(OVN_IDLE_GROW=off w $((T0 + 99999)))\" = 60 ] && [ \"\$(OVN_IDLE_GROW=off OVN_IDLE_SLEEP_S=45 w $((T0 + 99999)))\" = 45 ]"
printf '%s' "$T0" > "$D/idle_since"
ok "A9 OVN_IDLE_SLEEP_MAX_S lowers the cap; a cap below the base is lifted to the base" "[ \"\$(OVN_IDLE_SLEEP_MAX_S=100 w $((T0 + 36000)))\" = 100 ] && [ \"\$(OVN_IDLE_SLEEP_MAX_S=10 w $((T0 + 36000)))\" = 60 ]"
ok "A10 the base is OVN_IDLE_SLEEP_S (30 s base doubles to 60 after an hour)" "[ \"\$(OVN_IDLE_SLEEP_S=30 w $((T0 + 3601)))\" = 60 ]"
ok "A11 non-numeric env values fall back to the defaults (60/300/3600/1800)" "[ \"\$(OVN_IDLE_SLEEP_S=x OVN_IDLE_SLEEP_MAX_S=y OVN_IDLE_GROW_AFTER_S=z OVN_IDLE_GROW_STEP_S=0 w $((T0 + 3601)))\" = 120 ]"
ok "A12 a garbage idle_since file counts as 'streak starts now' (60 s) and is rewritten; a future idle_since never gives a negative wait" "{ printf 'junk' > '$D/idle_since'; [ \"\$(w $T0)\" = 60 ]; } && [ \"\$(cat '$D/idle_since')\" = $T0 ] && { printf '%s' $((T0 + 99999)) > '$D/idle_since'; [ \"\$(w $T0)\" = 60 ]; }"
ok "A13 the wait it prints is exactly what ovn_idle_wait takes: a short wait with a supply_kick pending wakes at once" "{ : > '$D/supply_kick'; [ \"\$(ovn_idle_wait '$D' 300 5)\" = kick ]; }"
fi

if want B; then
echo "== B. parked-idle breadcrumb dedupe =="
SD="$W/pi_state"; mkdir -p "$SD"
ok "B1 first breadcrumb for a repo is written, an identical one inside the hour is not" "ovn_parked_idle_should_log '$SD' r1 7 && ! ovn_parked_idle_should_log '$SD' r1 7 && ! ovn_parked_idle_should_log '$SD' r1 7"
ok "B2 a different count writes a new row at once" "ovn_parked_idle_should_log '$SD' r1 8 && ! ovn_parked_idle_should_log '$SD' r1 8"
ok "B3 another repo has its own marker" "ovn_parked_idle_should_log '$SD' r2 8"
printf '%s 8\n' "$(( $(date +%s) - 3601 ))" > "$SD/parked_idle_r1"
ok "B4 an hour later the same count is written again; 59 minutes later it is not" "ovn_parked_idle_should_log '$SD' r1 8 && { printf '%s 8\\n' \"\$(( \$(date +%s) - 3500 ))\" > '$SD/parked_idle_r1'; ! ovn_parked_idle_should_log '$SD' r1 8; }"
ok "B5 OVN_PARKED_IDLE_DEDUPE=off writes every row; OVN_PARKED_IDLE_DEDUPE_S shortens the window" "OVN_PARKED_IDLE_DEDUPE=off ovn_parked_idle_should_log '$SD' r1 8 && { printf '%s 8\\n' \"\$(( \$(date +%s) - 20 ))\" > '$SD/parked_idle_r1'; OVN_PARKED_IDLE_DEDUPE_S=10 ovn_parked_idle_should_log '$SD' r1 8; }"
ok "B6 a missing/garbage marker never fails the caller (row is written)" "{ rm -f '$SD/parked_idle_r9'; ovn_parked_idle_should_log '$SD' r9 1; } && { printf 'junk' > '$SD/parked_idle_r9'; ovn_parked_idle_should_log '$SD' r9 1; }"
# the real ovn_doc_reroute_item in shadow mode, three idle passes
OD="$W/od"; RD="$W/repo_pi"; mkdir -p "$OD/state" "$OD/scripts" "$RD"
printf 'import sys\nprint("SKIP\\tnot doable in this test")\n' > "$OD/scripts/ovn_doc_executor.py"
PK1='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — DOCITEM first parked gap. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-aa]'
PK2='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — DOCITEM second parked gap. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-bb]'
PK3='- [ ] [AUTO-SKIP after 2 credit refusals: VERIFY failed] [T2] docs/a.md — DOCITEM third parked gap. VERIFY: `true`. (supply:gd-missing-doc) [feat:xlite-20261009-supply-gd-missing-doc-cc]'
printf '# Overnight Progress\n\n## Next Steps\n%s\n%s\n' "$PK1" "$PK2" > "$RD/OVERNIGHT_PROGRESS.md"
LOG="$W/executor_shadow.log"; : > "$LOG"
pass(){ OVN_EXECUTOR_LOG="$LOG" OVN_DOC_EXECUTOR=shadow ovn_doc_reroute_item "$OD" "$RD" ongoing-xlite >/dev/null 2>&1; }
pi_rows(){ grep -c "parked-idle" "$LOG"; }
pass; pass; pass; pass
ok "B7 REAL ovn_doc_reroute_item: 4 idle passes with 2 parked gaps => exactly ONE parked-idle row (was 4)" "[ \"\$(pi_rows)\" = 1 ] && grep -q '2 parked gd-missing-doc gap' '$LOG'"
printf '%s\n' "$PK3" >> "$RD/OVERNIGHT_PROGRESS.md"; pass; pass
ok "B8 a third parked gap appears: one more row naming '3 parked', then quiet again (2 rows total)" "[ \"\$(pi_rows)\" = 2 ] && grep -q '3 parked gd-missing-doc gap' '$LOG'"
rm -f "$OD/state/parked_idle_"*; pass
ok "B9 the shadow evidence checks (would-apply|skip rows for the parked gaps) are unaffected by the dedupe" "[ \"\$(grep -c 'skip' '$LOG')\" -ge 3 ]"
OVN_PARKED_IDLE_DEDUPE=off pass; OVN_PARKED_IDLE_DEDUPE=off pass
ok "B10 OVN_PARKED_IDLE_DEDUPE=off restores one row per pass (5 rows total now)" "[ \"\$(pi_rows)\" = 5 ]"
fi

if want C; then
echo "== C. log cap retention (run dirs + reports) =="
TOOL="$S/ovn_log_cap.sh"
mkq(){ # fresh fixture
  rm -rf "${W:?}/q"; mkdir -p "$W/q/logs/archive" "$W/q/logs/hygiene_gate" "$W/q/logs/notes" "$W/q/reports" "$W/q/state" "$W/q/repos/r"
  echo keep > "$W/q/state/x"; echo keep > "$W/q/repos/r/x"
}
mkrun(){ local d="$W/q/logs/$1"; mkdir -p "$d"; echo log > "$d/ongoing-x.log"; touch -t "$2" "$d"; }
mkrep(){ local f="$W/q/reports/$1"; echo r > "$f"; touch -t "$2" "$f"; }
cap(){ ( export OVN_Q="$W/q"; "$@" bash "$TOOL" ) > "$W/out" 2>&1; echo $? > "$W/rc"; }
# 230 OLD run dirs (2026-01-01 + i minutes), 5 recent ones, an old ISO dir, an old archive dir, an old non-run dir, an old symlink named like a run dir; 260 OLD reports
mkq
python3 - "$W/q" <<'PY'
import os, sys, time, calendar
q = sys.argv[1]
base = calendar.timegm((2026, 1, 1, 0, 0, 0))
for i in range(230):
    d = "%s/logs/20260101-%06d" % (q, i)
    os.makedirs(d); open(d + "/ongoing-x.log", "w").write("log\n"); os.utime(d, (base + i * 60, base + i * 60))
for i in range(260):
    f = "%s/reports/20260101-%06d.md" % (q, i)
    open(f, "w").write("r\n"); os.utime(f, (base + i * 60, base + i * 60))
PY
ln -s "$W/q/state" "$W/q/logs/20260102-000000"; touch -h -t 202501010000 "$W/q/logs/20260102-000000"
mkrun 2026-01-05 202601050000; touch -t 202601050000 "$W/q/logs/archive" "$W/q/logs/hygiene_gate" "$W/q/logs/notes"
RECENT="$(date +%Y%m%d-%H%M%S)"; mkrun "$RECENT" "$(date +%Y%m%d%H%M)"
mkrep zimage-final.out 202601010000; mkrep grooming-xlite-20260101.md 202601010001; mkrep grooming-iptv_apps-2026-09-02.md 202601010001; mkrep 2026-08-02.md 202601010001; mkrep "$RECENT.md" "$(date +%Y%m%d%H%M)"
ls -lR "$W/q" > "$W/before.ls" 2>/dev/null
cap env
ok "C1 dry run (the default) exits 0, changes nothing anywhere, and says it WOULD remove run dirs and reports" "[ \"\$(cat '$W/rc')\" = 0 ] && grep -q 'WOULD remove 32 run dir' '$W/out' && grep -q 'WOULD remove 61 report' '$W/out' && [ \"\$(ls -lR '$W/q' 2>/dev/null | diff - '$W/before.ls' | wc -l | tr -d ' ')\" = 0 ]"
ok "C2 the dry run leaves no temp file behind in logs/ or reports/" "[ -z \"\$(ls -A '$W/q/logs' '$W/q/reports' | grep 'log_cap')\" ]"
cap env OVN_LOG_CAP=on
ok "C3 apply: 232 run dirs (230 old + the old ISO one + a fresh one): the newest 200 are KEPT, 32 removed (the line says so)" "grep -q 'removed 32 run dir' '$W/out' && [ \"\$(find '$W/q/logs' -mindepth 1 -maxdepth 1 -type d | sed 's#.*/##' | grep -cE '^(20[0-9]{6}-[0-9]{6}|20[0-9]{2}-[0-9]{2}-[0-9]{2})\$')\" = 200 ]"
ok "C4 apply: 261 RUN reports (260 old + a fresh one): the oldest 61 go, exactly the newest 200 run reports remain" "grep -q 'removed 61 report' '$W/out' && [ \"\$(ls '$W/q/reports' | grep -cE '^20[0-9]{6}-[0-9]{6}\\.md\$')\" = 200 ]"
ok "C4b the old groom.sh proposals and the dated one-off *.md in reports/ are NOT run reports and survive the live apply (review finding: 500 of them on the box)" "[ -f '$W/q/reports/grooming-xlite-20260101.md' ] && [ -f '$W/q/reports/grooming-iptv_apps-2026-09-02.md' ] && [ -f '$W/q/reports/2026-08-02.md' ]"
ok "C5 the freshest report and the freshest run dir are untouched (heartbeat for box_deadman: ls -t reports | head -1)" "[ \"\$(ls -t '$W/q/reports' | head -1)\" = '$RECENT.md' ] && [ -d '$W/q/logs/$RECENT' ]"
ok "C6 never touched: archive/, hygiene_gate/, a non-run-named dir, the symlink named like a run dir (and its target), state/, repos/, non-.md reports" "[ -d '$W/q/logs/archive' ] && [ -d '$W/q/logs/hygiene_gate' ] && [ -d '$W/q/logs/notes' ] && [ -L '$W/q/logs/20260102-000000' ] && [ \"\$(cat '$W/q/state/x')\" = keep ] && [ \"\$(cat '$W/q/repos/r/x')\" = keep ] && [ -e '$W/q/reports/zimage-final.out' ]"
ok "C7 a second apply is a no-op for retention (nothing older beyond the kept 200)" "{ cap env OVN_LOG_CAP=on; ! grep -q 'removed [0-9]* run dir' '$W/out' && ! grep -q 'removed [0-9]* report' '$W/out'; }"
# kept-newest set is by mtime: an OLD name with a NEW mtime is kept; knobs
mkq; i=0; while [ "$i" -lt 30 ]; do mkrun "$(printf '20260101-%06d' "$i")" 202601010000; mkrep "$(printf '20260101-%06d.md' "$i")" 202601010000; i=$((i+1)); done
cap env OVN_LOG_CAP=on OVN_LOG_RUN_KEEP_NEWEST=5 OVN_REPORT_KEEP_NEWEST=7
ok "C8 OVN_LOG_RUN_KEEP_NEWEST / OVN_REPORT_KEEP_NEWEST set the floor (5 run dirs, 7 reports remain)" "[ \"\$(ls '$W/q/logs' | grep -cE '^20[0-9]{6}-[0-9]{6}\$')\" = 5 ] && [ \"\$(ls '$W/q/reports' | grep -c '\\.md\$')\" = 7 ]"
mkq; mkrun 20260101-000001 202601010000; mkrep 20260101-000001.md 202601010000
cap env OVN_LOG_CAP=on OVN_LOG_RETENTION=off OVN_LOG_RUN_KEEP_NEWEST=0 OVN_REPORT_KEEP_NEWEST=0
ok "C9 OVN_LOG_RETENTION=off: nothing is pruned even with a zero floor" "[ -d '$W/q/logs/20260101-000001' ] && [ -f '$W/q/reports/20260101-000001.md' ]"
mkq; mkrun 20260101-000001 202601010000; mkrep 20260101-000001.md 202601010000
cap env OVN_LOG_CAP=on OVN_LOG_RUN_KEEP_NEWEST=0 OVN_REPORT_KEEP_NEWEST=0 OVN_LOG_RUN_KEEP_DAYS=14 OVN_REPORT_KEEP_DAYS=14
ok "C10 with the floor at 0, old ones go by the days rule alone" "[ ! -d '$W/q/logs/20260101-000001' ] && [ ! -f '$W/q/reports/20260101-000001.md' ]"
mkq; mkrun "$RECENT" "$(date +%Y%m%d%H%M)"; mkrep "$RECENT.md" "$(date +%Y%m%d%H%M)"
cap env OVN_LOG_CAP=on OVN_LOG_RUN_KEEP_NEWEST=0 OVN_REPORT_KEEP_NEWEST=0
ok "C11 a RECENT run dir / report is never removed by age, even with a zero floor" "[ -d '$W/q/logs/$RECENT' ] && [ -f '$W/q/reports/$RECENT.md' ]"
mkq; rm -rf "${W:?}/q/reports"; cap env OVN_LOG_CAP=on
ok "C12 no reports/ dir: clean run, exit 0" "[ \"\$(cat '$W/rc')\" = 0 ]"
fi

if want E; then
echo "== E. freshness invariant =="
MAXW="$(grep -o 'OVN_IDLE_SLEEP_MAX_S:-[0-9]*' "$S/lib_fixup.sh" | head -1 | grep -o '[0-9]*$')"
STALE="$(grep -o 'env_f("DEADMAN_STALE_S", [0-9]*' "$Q/ops/fleet_review/box_deadman.py" | grep -o '[0-9]*$')"
SILENT="$(grep -o 'OVN_SILENT_S", "[0-9]*"' "$S/ovn_notify.py" | grep -o '[0-9]*' | head -1)"
ok "E1 default max idle wait ($MAXW s) + a generous 120 s pass is under HALF of the dead-man's stale threshold ($STALE s) and of the silent-queue threshold ($SILENT s)" "[ -n '$MAXW' ] && [ -n '$STALE' ] && [ -n '$SILENT' ] && [ $((MAXW + 120)) -lt $((STALE / 2)) ] && [ $((MAXW + 120)) -lt $((SILENT / 2)) ]"
ok "E2 retention keeps at least the newest 200 reports by default (a 5-minute idle cadence = 16 h of heartbeat; the dead-man needs only the newest one)" "grep -q 'OVN_REPORT_KEEP_NEWEST:-200' '$S/ovn_log_cap.sh' && grep -q 'OVN_LOG_RUN_KEEP_NEWEST:-200' '$S/ovn_log_cap.sh'"
fi

if want D; then
echo "== D. the runner (real run_overnight.sh, hermetic tree) =="
. "$HERE/lib_ro_core.sh"
# lib_ro_core.sh defines its own ok() (value-based); restore this file's command-based one
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
if ! ( _p="$(mktemp)"; trap 'rm -f "$_p"' EXIT; exec 9>"$_p"; flock -w 0 9 ) 2>/dev/null || ! sed --version >/dev/null 2>&1; then
  echo "  SKIP: needs util-linux flock and GNU sed (run on the box)"
else
  ro_init
  # 2026-10-16: ro_init installs its own `trap 'rm -rf "$T"' EXIT`, which REPLACED line 18's trap, so $W (the scratch copy of the whole tree for section M, 168,912 entries on the box where repos/ is populated) was never removed. Remove both.
  trap 'rm -rf "${T:?}" "${W:?}"' EXIT
  ro_hook_stubs
  ro_link update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py scripts/ovn_classify.py scripts/ovn_progress_slice.py \
          scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh scripts/lib_verify_clause.sh scripts/lib_auto_credit.sh scripts/lib_parked_pattern.sh \
          scripts/lib_path_normalize.sh scripts/lib_run_integrity.sh scripts/lib_worktree.sh scripts/lib_tree_guard.sh
  ST="$T/tree/state"; R="$T/repos"; mkdir -p "$ST"
  ro_mkrepo idle1 "# Overnight Progress

## Next Steps" >/dev/null
  ro_mkrepo busy1 >/dev/null
  idlepass(){ # idlepass <repo> [ENV=..]: one ongoing-<repo> pass
    local nm="$1"; shift
    ro_tasks "$(jq -nc --arg R "$R" --arg n "$nm" '[{id:("ongoing-"+$n),repo:($R+"/"+$n),prompt:"Work the single top not-yet-done item in the overnight progress log."}]')"
    rm -rf "${T:?}/tree/reports"/* "${RO_STUB:?}/aider_n" "${RO_STUB:?}/aider_kinds" "${RO_STUB:?}/sleep.log"; printf 'IMPL_SEQ=none\n' > "$RO_STUB/scn"
    ro_run_main "$@"
  }
  # the REAL wait: ovn_idle_wait sleeps in 5 s steps and the sleep stub logs every call, so the number of 'sleep 5' lines is wait/5 (the log line alone only proves what was PRINTED)
  steps(){ local n; n="$(grep -c '^sleep 5$' "$RO_STUB/sleep.log" 2>/dev/null)"; echo "${n:-0}"; }
  rm -f "$ST/idle_since"
  idlepass idle1
  [ -n "${IDLE_TEST_DEBUG:-}" ] && { echo "---- RO_OUT (rc=$RO_RC)"; printf '%s\n' "$RO_OUT" | tail -25; ls -la "$ST" | head -20; }
  ok "D1 first all-idle pass: waits the base 60 s and starts the streak (state/idle_since)" "printf '%s' \"\$RO_OUT\" | grep -q 'all 1 lane(s) idle (skip(exhausted)) - waiting up to 60s' && [ -f '$ST/idle_since' ]"
  ok "D1b ... and it really sleeps 60 s: 12 steps of 5 s" "[ \"\$(steps)\" = 12 ]"
  since="$(cat "$ST/idle_since")"; idlepass idle1
  ok "D2 the next idle pass keeps the streak start" "[ \"\$(cat '$ST/idle_since')\" = '$since' ]"
  printf '%s' "$(( $(date +%s) - 3700 ))" > "$ST/idle_since"; idlepass idle1
  ok "D3 idle for 1h02m: waits 120 s" "printf '%s' \"\$RO_OUT\" | grep -q 'waiting up to 120s'"
  ok "D3b ... and it really sleeps 120 s (24 steps), not the flat 60 s that the log line would hide" "[ \"\$(steps)\" = 24 ]"
  printf '%s' "$(( $(date +%s) - 8000 ))" > "$ST/idle_since"; idlepass idle1
  ok "D4 idle for 2h13m: waits 300 s (the cap)" "printf '%s' \"\$RO_OUT\" | grep -q 'waiting up to 300s'"
  ok "D4b ... and it really sleeps 300 s (60 steps)" "[ \"\$(steps)\" = 60 ]"
  printf '%s' "$(( $(date +%s) - 8000 ))" > "$ST/idle_since"; idlepass idle1 OVN_IDLE_GROW=off
  ok "D5 OVN_IDLE_GROW=off: back to the flat 60 s" "printf '%s' \"\$RO_OUT\" | grep -q 'waiting up to 60s' && [ \"\$(steps)\" = 12 ]"
  printf '%s' "$(( $(date +%s) - 8000 ))" > "$ST/idle_since"; idlepass busy1
  ok "D6 a pass that had work (the lane was not skip(exhausted)) ends the streak: idle_since is removed, no idle wait" "[ ! -e '$ST/idle_since' ] && ! printf '%s' \"\$RO_OUT\" | grep -q 'waiting up to'"
  idlepass idle1
  ok "D7 and the next idle pass starts again at 60 s" "printf '%s' \"\$RO_OUT\" | grep -q 'waiting up to 60s'"
  printf '%s' "$(( $(date +%s) - 8000 ))" > "$ST/idle_since"; idlepass idle1 OVN_IDLE_SLEEP_S=0
  ok "D8 OVN_IDLE_SLEEP_S=0 (the existing off switch) still disables the wait entirely" "! printf '%s' \"\$RO_OUT\" | grep -q 'waiting up to' && [ \"\$(steps)\" = 0 ]"
  ok "D9 the pass still writes its run report on every idle pass (heartbeat for the dead-man)" "[ \"\$(ls '$T/tree/reports' | grep -c '\\.md\$')\" -ge 1 ]"
fi
fi

if want M; then
echo "== M. MUTATION controls (scratch copy of the tree) =="
if [ "${IDLE_TEST_NESTED:-0}" = 1 ]; then echo "  (skipped: nested run)"; else
MQ="$W/mut"; rm -rf "$MQ"; mkdir -p "$MQ"; ( cd "$Q" && tar cf - --exclude=./logs --exclude=./state . ) | ( cd "$MQ" && tar xf - )
mutate(){ python3 - "$MQ/$1" "$2" "$3" <<'PY'
import sys
p, a, b = sys.argv[1:4]
s = open(p).read()
assert s.count(a) == 1, (p, a, s.count(a))
open(p, "w").write(s.replace(a, b))
PY
}
restore(){ ( cd "$Q" && cp "$1" "$MQ/$1" ); }
nest(){ ( cd "$MQ/scripts/test" && IDLE_TEST_NESTED=1 IDLE_TEST_SECTIONS="$1" timeout 900 bash test_idle_growth_retention.sh ) > "$W/mut.out" 2>&1; true; }
mutate scripts/lib_fixup.sh '  d=$(( now - since )); [ "$d" -lt 0 ] && d=0' '  d=0'
nest A,D; restore scripts/lib_fixup.sh
ok "M1 MUTATION: an idle wait that never grows fails the growth table (A4..A6) and the runner scenarios (D3, D4)" "grep -q 'FAIL A4' '$W/mut.out' && grep -q 'FAIL A6' '$W/mut.out' && { ! grep -q 'SKIP: needs util-linux' '$W/mut.out' && grep -q 'FAIL D3' '$W/mut.out' || grep -q 'SKIP: needs util-linux' '$W/mut.out'; }"
mutate scripts/lib_fixup.sh '  [ "$w" -gt "$max" ] && w="$max"
  echo "$w"' '  echo "$w"'
nest A; restore scripts/lib_fixup.sh
ok "M2 MUTATION: without the cap the wait exceeds 300 s (A6 fails)" "grep -q 'FAIL A6' '$W/mut.out'"
mutate scripts/lib_fixup.sh '  if [ "$lastn" != "$n" ] || [ $((now - last)) -ge "$win" ]; then' '  if true; then'
nest B; restore scripts/lib_fixup.sh
ok "M3 MUTATION: a breadcrumb written on every pass fails the dedupe assertions (B1, B7)" "grep -q 'FAIL B1' '$W/mut.out' && grep -q 'FAIL B7' '$W/mut.out'"
mutate scripts/ovn_log_cap.sh '| head -n "$PNEW" > "$tk" || true' '| head -n 0 > "$tk" || true'
nest C; restore scripts/ovn_log_cap.sh
ok "M4 MUTATION: retention without the newest-N exemption for reports fails (C4, C8)" "grep -q 'FAIL C4' '$W/mut.out' && grep -q 'FAIL C8' '$W/mut.out'"
mutate scripts/ovn_log_cap.sh "find \"\$RPT\" -maxdepth 1 -type f -name '*.md' -mtime +\"\$PDAYS\"" "find \"\$RPT\" -maxdepth 1 -type f -name '*.md'"
nest C; restore scripts/ovn_log_cap.sh
ok "M5 MUTATION: retention that ignores the age rule deletes recent reports (C11 fails)" "grep -q 'FAIL C11' '$W/mut.out'"
mutate scripts/ovn_log_cap.sh "grep -E \"\$RUNDIR_ERE\" | grep -vxFf" "grep -vxFf"
nest C; restore scripts/ovn_log_cap.sh
ok "M6 MUTATION: matching run dirs by age only (no exact-name rule) removes archive/, hygiene_gate/ and notes/ (C6 fails)" "grep -q 'FAIL C6' '$W/mut.out'"
mutate scripts/ovn_log_cap.sh '| grep -E "$REPORT_ERE" | grep -vxFf "$tk" > "$tc"' '| grep -vxFf "$tk" > "$tc"'
nest C; restore scripts/ovn_log_cap.sh
ok "M9 MUTATION: a name-blind *.md report rule (the first shipped behaviour) deletes the groom.sh proposals (C4b and C1 fail)" "grep -q 'FAIL C4b' '$W/mut.out' && grep -q 'FAIL C1 ' '$W/mut.out'"
if ( _p="$(mktemp)"; trap 'rm -f "$_p"' EXIT; exec 9>"$_p"; flock -w 0 9 ) 2>/dev/null && sed --version >/dev/null 2>&1; then
  mutate run_overnight.sh '  ovn_idle_clear "$STATE_DIR"   # a pass with work ends the all-idle streak: the next idle pass starts at the base wait again' '  :'
  nest D; restore run_overnight.sh
  ok "M7 MUTATION: not clearing the streak after a pass with work fails D6/D7" "grep -q 'FAIL D6' '$W/mut.out' && grep -q 'FAIL D7' '$W/mut.out'"
  mutate run_overnight.sh '_ovn_idle_res="$(ovn_idle_wait "$STATE_DIR" "$_ovn_idle_s")"' '_ovn_idle_res="$(ovn_idle_wait "$STATE_DIR")"'
  nest D; restore run_overnight.sh
  ok "M8 MUTATION: the runner dropping the computed wait (a flat 60 s while the log still says 300 s) fails the real-sleep checks D3b/D4b" "grep -q 'FAIL D3b' '$W/mut.out' && grep -q 'FAIL D4b' '$W/mut.out' && ! grep -q 'FAIL D3 ' '$W/mut.out'"
else echo "  (M7/M8 need util-linux flock: skipped on this host)"; fi
fi
fi
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
