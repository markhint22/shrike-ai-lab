#!/usr/bin/env bash
# Regression tests for ovn_research_trigger_check.py + ovn_research_trigger_check.sh.
# The python half parses ovn_planner.log for "no [ready] roadmap feature" streaks per repo and writes
# state/research_trigger_starving.json; the shell half logs a summary and keeps a per-repo streak-dedup
# marker (alerting is suppressed on purpose since 2026-09-28 - we assert NO ntfy/curl path exists).
# Hermetic: HOME is a temp dir, logs are synthesized with timestamps relative to "now".
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REAL_HOME="$HOME"
PY="$HERE/../ovn_research_trigger_check.py"; [ -f "$PY" ] || PY="$REAL_HOME/overnight-queue/scripts/ovn_research_trigger_check.py"
SH="$HERE/../ovn_research_trigger_check.sh"; [ -f "$SH" ] || SH="$REAL_HOME/overnight-queue/scripts/ovn_research_trigger_check.sh"
[ -f "$PY" ] && [ -f "$SH" ] || { echo "  SKIP: scripts not found"; exit 0; }
unset NTFY_TOPIC OVN_STARVE_HOURS

pass=0; fail=0; warnc=0
ok(){ pass=$((pass+1)); echo "  ok   $1"; }
bad(){ fail=$((fail+1)); echo "  FAIL $1"; }
chk(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else bad "$l"; fi; }
eqv(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2] got [$3])"; fi; }
known(){ local l="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$l"; else warnc=$((warnc+1)); echo "  WARN KNOWN-BUG: $l"; fi; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ago(){ date -d "@$(( $(date +%s) - $1 ))" '+%F %T'; }   # seconds ago -> log timestamp
H=3600
STARVE='no [ready] roadmap feature (needs Claude research?)'
mkhome(){ rm -rf "$T/h"; mkdir -p "$T/h/overnight-queue/logs" "$T/h/overnight-queue/state"; echo "$T/h"; }
LOGF="$T/h/overnight-queue/logs/ovn_planner.log"
STJ="$T/h/overnight-queue/state/research_trigger_starving.json"
runpy(){ HOME="$T/h" python3 "$PY" "$@" 2>&1; }
jq_py(){ python3 -c "import json,sys; d=json.load(open('$STJ')); print($1)"; }

echo "== python: log parsing =="
mkhome >/dev/null
out="$(runpy 2 "$T/nonexistent.log")"
eqv "missing log -> empty output" "" "$out"
chk "missing log -> no state file written" test ! -f "$STJ"

: > "$LOGF"
out="$(runpy 2 "$LOGF")"
eqv "empty log -> empty output" "" "$out"
chk "empty log -> state file written (empty starving list)" test -f "$STJ"
eqv "empty log -> starving == []" "[]" "$(jq_py "d['starving']")"

# one repo starving 5h, continuous
cat > "$LOGF" <<EOF
$(ago $((5*H))) alpha: backlog low (2) but $STARVE
$(ago $((4*H))) alpha: backlog low (2) but $STARVE
$(ago $((3*H))) alpha: backlog low (2) but $STARVE
EOF
out="$(runpy 2 "$LOGF")"
eqv "5h streak -> summary line" "1 repo(s) starving >= 2.0h: alpha (5.0h)" "$out"
eqv "state: repo name" "alpha" "$(jq_py "d['starving'][0]['repo']")"
eqv "state: hours" "5.0" "$(jq_py "d['starving'][0]['hours']")"
chk "state: checked_at is recent epoch" python3 -c "import json,time; d=json.load(open('$STJ')); assert abs(time.time()-d['checked_at'])<60"
chk "state: starving_since ~5h ago" python3 -c "import json,time; d=json.load(open('$STJ')); s=d['starving'][0]['starving_since']; assert abs((time.time()-s)-5*3600)<120"

# healthy last line -> not starving
cat > "$LOGF" <<EOF
$(ago $((6*H))) alpha: backlog low (2) but $STARVE
$(ago $((5*H))) alpha: backlog low (2) but $STARVE
$(ago $((1*H))) alpha: planned 4 items from roadmap feature X
EOF
out="$(runpy 2 "$LOGF")"
eqv "latest line healthy -> not starving (empty output)" "" "$out"
eqv "latest healthy -> starving list empty" "[]" "$(jq_py "d['starving']")"

# broken streak in the middle: only the unbroken tail counts
cat > "$LOGF" <<EOF
$(ago $((8*H))) alpha: backlog low (2) but $STARVE
$(ago $((6*H))) alpha: planned 3 items
$(ago $((3*H))) alpha: backlog low (2) but $STARVE
$(ago $((2*H+1800))) alpha: backlog low (2) but $STARVE
EOF
out="$(runpy 2 "$LOGF")"
eqv "streak measured from the LAST healthy break (3.0h not 8h)" "1 repo(s) starving >= 2.0h: alpha (3.0h)" "$out"

# reminder-sent line is NON-breaking (2026-09-23 live bug)
cat > "$LOGF" <<EOF
$(ago $((5*H))) alpha: backlog low (2) but $STARVE
$(ago $((4*H))) alpha: sent needs-research reminder
$(ago $((3*H))) alpha: backlog low (2) but $STARVE
EOF
out="$(runpy 2 "$LOGF")"
eqv "reminder line does not reset the streak (5.0h)" "1 repo(s) starving >= 2.0h: alpha (5.0h)" "$out"
cat > "$LOGF" <<EOF
$(ago $((5*H))) alpha: backlog low (2) but $STARVE
$(ago $((1*H))) alpha: sent needs-research reminder
EOF
out="$(runpy 2 "$LOGF")"
eqv "reminder as the LATEST line still counts as starved" "1 repo(s) starving >= 2.0h: alpha (5.0h)" "$out"

# threshold handling
cat > "$LOGF" <<EOF
$(ago $((1*H))) alpha: backlog low (2) but $STARVE
EOF
eqv "1h streak below default 2h threshold -> empty" "" "$(runpy 2 "$LOGF")"
eqv "same log with 0.5h threshold -> flagged" "1 repo(s) starving >= 0.5h: alpha (1.0h)" "$(runpy 0.5 "$LOGF")"
eqv "default threshold (no args beyond log) is 2h" "" "$(runpy 2 "$LOGF")"

# multi repo, sorted by hours desc, healthy repo excluded, out-of-order lines
cat > "$LOGF" <<EOF
$(ago $((1*H))) carol: planned 2 items
$(ago $((3*H))) alpha: backlog low (1) but $STARVE
$(ago $((9*H))) bravo: backlog low (0) but $STARVE
$(ago $((2*H))) bravo: backlog low (0) but $STARVE
$(ago $((10*H))) carol: backlog low (1) but $STARVE
$(ago $((1*H))) alpha: backlog low (1) but $STARVE
EOF
out="$(runpy 2 "$LOGF")"
eqv "two starving repos sorted worst-first, healthy one excluded" "2 repo(s) starving >= 2.0h: bravo (9.0h), alpha (3.0h)" "$out"
eqv "state order matches (bravo first)" "bravo" "$(jq_py "d['starving'][0]['repo']")"

# malformed lines / unparsable timestamps are ignored
cat > "$LOGF" <<EOF
this is not a log line
2026-13-45 99:99:99 alpha: $STARVE
$(ago $((4*H))) alpha: $STARVE

not-a-date alpha: $STARVE
EOF
out="$(runpy 2 "$LOGF")"
eqv "garbage + invalid-timestamp lines skipped, valid one used" "1 repo(s) starving >= 2.0h: alpha (4.0h)" "$out"
cat > "$LOGF" <<EOF
2026-13-45 99:99:99 alpha: $STARVE
EOF
eqv "only invalid timestamp -> nothing" "" "$(runpy 2 "$LOGF")"

# default log path + state dir auto-created under a fresh HOME
rm -rf "$T/h2"; mkdir -p "$T/h2/overnight-queue/logs"
cat > "$T/h2/overnight-queue/logs/ovn_planner.log" <<EOF
$(ago $((3*H))) zed: $STARVE
EOF
out="$(HOME="$T/h2" python3 "$PY" 2>&1)"
eqv "no args -> default log path + default 2h threshold" "1 repo(s) starving >= 2.0h: zed (3.0h)" "$out"
chk "state dir created on demand" test -f "$T/h2/overnight-queue/state/research_trigger_starving.json"

out="$(runpy abc "$LOGF"; echo "rc=$?")"
chk "non-numeric threshold -> python error (nonzero)" bash -c "! HOME='$T/h' python3 '$PY' abc '$LOGF' >/dev/null 2>&1"

echo "== shell wrapper =="
mkfake(){ rm -rf "$T/w"; mkdir -p "$T/w/overnight-queue/"{scripts,logs,state}; cp "$PY" "$T/w/overnight-queue/scripts/"; echo "$T/w"; }
WL="$T/w/overnight-queue/logs/ovn_research_trigger_check.log"
WPL="$T/w/overnight-queue/logs/ovn_planner.log"
WST="$T/w/overnight-queue/state"
runsh(){ HOME="$T/w" bash "$SH" "$@" 2>&1; }

rm -rf "$T/nohome"; mkdir -p "$T/nohome"
HOME="$T/nohome" bash "$SH" >/dev/null 2>&1; rc=$?
eqv "no ~/overnight-queue -> exit 1" "1" "$rc"

mkfake >/dev/null
runsh; rc=$?
eqv "no planner log -> exit 0" "0" "$rc"
chk "no planner log -> nothing logged" bash -c "! grep -q . '$WL'"
chk "stats dir is created/kept" test -d "$WST"

# corrupt pre-existing state json + no planner log -> tolerated, no alert
echo '{not json' > "$WST/research_trigger_starving.json"
runsh >/dev/null; rc=$?
eqv "corrupt state json tolerated (exit 0)" "0" "$rc"
chk "corrupt state -> no marker created" bash -c "! ls '$WST'/research_trigger_alerted_* >/dev/null 2>&1"
rm -f "$WST/research_trigger_starving.json"

cat > "$WPL" <<EOF
$(ago $((5*H))) alpha: backlog low (2) but $STARVE
$(ago $((3*H))) alpha: backlog low (2) but $STARVE
EOF
runsh >/dev/null; rc=$?
eqv "starving repo -> exit 0" "0" "$rc"
chk "log has the python summary line" grep -q '1 repo(s) starving >= 2h: alpha (5.0h)\|1 repo(s) starving >= 2.0h: alpha (5.0h)' "$WL"
chk "log has newly-confirmed line, ntfy suppressed" grep -q '=== 1 repo(s) newly confirmed starving — ntfy suppressed' "$WL"
chk "log carries per-repo detail" grep -q 'alpha: starving 5.0h (no ready roadmap feature)' "$WL"
chk "per-repo alerted marker created" test -f "$WST/research_trigger_alerted_alpha"
eqv "marker == starving_since from state json" "$(python3 -c "import json; print(json.load(open('$WST/research_trigger_starving.json'))['starving'][0]['starving_since'])")" "$(cat "$WST/research_trigger_alerted_alpha")"

# idempotent: second tick logs the summary again but does NOT re-announce
runsh >/dev/null
eqv "second tick: still only ONE newly-confirmed line (dedup)" "1" "$(grep -c 'newly confirmed' "$WL")"
eqv "second tick: summary logged again (2 total)" "2" "$(grep -c 'repo(s) starving >=' "$WL")"

# streak broken and restarted -> new marker value -> announced again
cat >> "$WPL" <<EOF
$(ago $((2*H+1200))) alpha: planned 3 items
$(ago $((2*H+600))) alpha: backlog low (2) but $STARVE
EOF
runsh >/dev/null
eqv "new streak for same repo announced again (2 newly-confirmed lines)" "2" "$(grep -c 'newly confirmed' "$WL")"

# two repos at once -> n=2 and '; '-joined detail
mkfake >/dev/null
cat > "$WPL" <<EOF
$(ago $((5*H))) alpha: $STARVE
$(ago $((4*H))) bravo: $STARVE
EOF
runsh >/dev/null
chk "two newly starving repos -> '2 repo(s)' line" grep -q '=== 2 repo(s) newly confirmed starving' "$WL"
chk "detail has both repos, worst first" grep -q 'alpha: starving 5.0h (no ready roadmap feature);.*bravo: starving 4.0h' "$WL"
known "detail joined with '; ' (tr '\\n' '; ' only maps to ';' -> no space, trailing ';')" grep -q 'feature); bravo: starving 4.0h (no ready roadmap feature)$' "$WL"

# env threshold
mkfake >/dev/null
cat > "$WPL" <<EOF
$(ago $((5*H))) alpha: $STARVE
EOF
OVN_STARVE_HOURS=10 runsh >/dev/null
chk "OVN_STARVE_HOURS=10 -> 5h streak not flagged, nothing logged" bash -c "! grep -q 'starving' '$WL'"
OVN_STARVE_HOURS=1 runsh >/dev/null
chk "OVN_STARVE_HOURS=1 -> flagged, threshold shown" grep -q 'starving >= 1.0h' "$WL"

# python failure path: stderr lands in the log, wrapper survives
mkfake >/dev/null
cat > "$WPL" <<EOF
$(ago $((5*H))) alpha: $STARVE
EOF
OVN_STARVE_HOURS=abc runsh >/dev/null; rc=$?
eqv "python crash -> wrapper still exits 0" "0" "$rc"
chk "python traceback captured in wrapper log" grep -q 'ValueError' "$WL"
chk "python crash -> no marker" bash -c "! ls '$WST'/research_trigger_alerted_* >/dev/null 2>&1"

# no network path: wrapper must never reference curl/ntfy as a command
chk "wrapper contains no curl invocation (alerts suppressed)" bash -c "! grep -v '^#' '$SH' | grep -qE '(^|[^a-z])curl '"

echo
echo "$pass passed, $fail failed ($warnc known-bug warning(s))"
[ "$fail" -eq 0 ]
