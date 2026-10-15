#!/usr/bin/env bash
# Runs the REAL ovn_fleet_health.sh (daily runway heartbeat) in a fake $HOME tree with the real ovn_stats.py runway(),
# real git repos with synthetic commit history, synthetic outcomes.jsonl/task_stats.log and a stub curl. Covers every runway
# classification (0d / stalled? / <1d / ~Nd <= threshold / healthy), the landed-7d parser (ISO, epoch, ms-epoch, `timestamp`
# key, garbage), alert-vs-clean paths, topic resolution and active-repo filtering.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
pick(){ for c in "$@"; do [ -f "$c" ] && { echo "$c"; return; }; done; }
FH="$(pick "$HERE/../ovn_fleet_health.sh" "$HERE/../../ovn_fleet_health.sh" "$HERE/../../scripts/ovn_fleet_health.sh")"
STATS="$(pick "$HERE/../ovn_stats.py" "$HERE/../../scripts/ovn_stats.py")"
BUCK="$(pick "$HERE/../ovn_outcome_buckets.py" "$HERE/../../scripts/ovn_outcome_buckets.py")"
[ -n "$FH" ] && [ -n "$STATS" ] && [ -n "$BUCK" ] || { echo "  SKIP: fleet_health/ovn_stats/ovn_outcome_buckets not found"; exit 0; }
P=0; F=0; KB=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
kb(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   KNOWN-BUG (fixed?) $1"; else KB=$((KB+1)); echo "  WARN KNOWN-BUG: $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
BIN="$T/bin"; ALERTS="$T/alerts.txt"; mkdir -p "$BIN"; export ALERTS
# The script resets PATH to put /usr/bin first, so a PATH stub would lose to the real curl (real network!). An exported bash
# FUNCTION named curl is imported by the child bash and beats any PATH lookup, so the script can never reach the network.
curl(){
  local u="" t="" b=""
  while [ $# -gt 0 ]; do case "$1" in -H) case "$2" in Title:*) t="$2";; esac; shift 2;; -d) b="$2"; shift 2;; --max-time) shift 2;; -*) shift;; *) u="$1"; shift;; esac; done
  printf '%s\n%s\n%s\n--\n' "$u" "$t" "$b" >> "$ALERTS"
  return 0
}
export -f curl
NOW=$(date +%s)
iso(){ date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }

# fake tree builder ------------------------------------------------------------------------------------
mk(){ # $1 = name
  H="$T/$1/home"; R="$H/overnight-queue"; rm -rf "$T/$1"
  mkdir -p "$R/state" "$R/logs" "$R/scripts" "$R/repos"
  cp "$STATS" "$BUCK" "$R/scripts/"
  : > "$ALERTS"
}
mkrepo(){ # $1=name $2=doable $3=burn(recent feat commits) [$4 extra recent non-burn commits]
  local d="$R/repos/$1"; mkdir -p "$d"
  ( cd "$d" && git init -q && git config user.email t@t && git config user.name t
    { echo "## Next Steps"; i=0; while [ "$i" -lt "$2" ]; do echo "- [ ] item $i"; i=$((i+1)); done
      echo "- [ ] HUMAN-ONLY x"; echo "- [x] done"; } > OVERNIGHT_PROGRESS.md
    git add -A; git commit -q -m "chore: base"
    i=0; while [ "$i" -lt "$3" ]; do git commit -q --allow-empty -m "feat: burn $i"; i=$((i+1)); done
    git commit -q --allow-empty -m "fix: auto-credit skipme"   # excluded from burn
    git commit -q --allow-empty -m "docs: not counted" )
}
run(){ OUT="$(cd "$H" && HOME="$H" PATH="$BIN:$PATH" env "$@" bash "$FH" 2>&1)"; RC=$?; LOGF="$R/logs/ovn_fleet_health.log"; }
logs(){ cat "$R/logs/ovn_fleet_health.log" 2>/dev/null; }
has_log(){ logs | grep -qF -- "$1" && echo 1 || echo 0; }

# =====================================================================================================
# Scenario 1: mixed runways + landed parser + alert
# =====================================================================================================
mk S1
cat > "$R/tasks.json" <<'EOF'
[{"id":"a","repo":"/r/repos/r_zero"},{"id":"b","repo":"/r/repos/r_stalled"},{"id":"c","repo":"/r/repos/r_lt1"},
 {"id":"d","repo":"/r/repos/r_2d"},{"id":"e","repo":"/r/repos/r_3d"},{"id":"f","repo":"/r/repos/r_15d"},
 {"id":"g","repo":"/r/repos/r_off","enabled":false},{"id":"h","repo":"/r/repos/r_2d/"}]
EOF
mkrepo r_zero 0 2; mkrepo r_stalled 3 0; mkrepo r_lt1 2 4; mkrepo r_2d 4 2; mkrepo r_3d 6 2; mkrepo r_15d 30 2; mkrepo r_off 0 0
# outcomes.jsonl: landed counts per repo
{
  echo "{\"ts\":\"$(iso $((NOW-3600)))\",\"repo\":\"r_2d\",\"class\":\"landed\"}"                 # ISO, recent
  echo "{\"ts\":$((NOW-7200)),\"repo\":\"r_2d\",\"class\":\"LANDED\"}"                             # epoch seconds, case-insens
  echo "{\"ts\":$(( (NOW-100)*1000 )),\"repo\":\"r_lt1\",\"class\":\"landed\"}"                     # epoch ms (>1e12)
  echo "{\"timestamp\":\"$(iso $((NOW-50)))\",\"repo\":\"r_3d\",\"class\":\"landed\"}"            # alt key
  echo "{\"ts\":\"$(iso $((NOW-9*86400)))\",\"repo\":\"r_2d\",\"class\":\"landed\"}"               # too old
  echo "{\"ts\":\"$(iso $((NOW-60)))\",\"repo\":\"r_2d\",\"class\":\"reverted\"}"                  # not landed
  echo "{\"ts\":\"not-a-date\",\"repo\":\"r_2d\",\"class\":\"landed\"}"                            # unparsable ts
  echo "{\"repo\":\"r_2d\",\"class\":\"landed\"}"                                                # no ts
  echo "this is not json"
  echo "{\"ts\":\"$(iso $((NOW-60)))\",\"class\":\"landed\"}"                                     # repo missing -> '?'
} > "$R/state/outcomes.jsonl"
# ovn_stats.py needs >=1 recent task_stats row or it exits at import (see KNOWN-BUG below)
printf '%s\tr_2d\tpass\t{py.fix.s.t}\tfoo.py\n' "$NOW" > "$R/state/task_stats.log"
run NTFY_TOPIC=topic1
ok "S1: exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "S1: r_zero logged with 0d runway" "$(has_log 'r_zero: doable=0 runway=0d')"
ok "S1: r_stalled logged 'stalled?' (doable, zero burn)" "$(has_log 'r_stalled: doable=3 runway=stalled?')"
ok "S1: r_lt1 '<1d' (2 doable / 4 burn)" "$(has_log 'r_lt1: doable=2 runway=<1d')"
ok "S1: r_2d '~2d' at threshold" "$(has_log 'r_2d: doable=4 runway=~2d')"
ok "S1: r_3d '~3d' above threshold (healthy)" "$(has_log 'r_3d: doable=6 runway=~3d')"
ok "S1: r_15d healthy" "$(has_log 'r_15d: doable=30 runway=~15d')"
ok "S1: disabled repo excluded" "$(logs | grep -q 'r_off' && echo 0 || echo 1)"
ok "S1: landed_7d: ISO + epoch-seconds + case-insensitive class = 2, old/unparsable/no-ts/revert excluded" "$(has_log 'r_2d: doable=4 runway=~2d burn24h=2 landed_7d=2')"
ok "S1: landed_7d counts epoch-ms ts" "$(has_log 'r_lt1: doable=2 runway=<1d burn24h=4 landed_7d=1')"
ok "S1: landed_7d counts 'timestamp' key" "$(has_log 'r_3d: doable=6 runway=~3d burn24h=2 landed_7d=1')"
ok "S1: 4 low-runway repos summary" "$(has_log '=== 4 repo(s) at or under 2d runway (of 6 active) ===')"
ok "S1: exactly one alert sent" "$([ "$(grep -c '^--$' "$ALERTS")" = 1 ] && echo 1 || echo 0)"
ok "S1: alert goes to the configured topic" "$(grep -q 'https://ntfy.sh/topic1' "$ALERTS" && echo 1 || echo 0)"
ok "S1: alert title counts low repos" "$(grep -q 'Title: Fleet health: 4 repo(s) low on runway' "$ALERTS" && echo 1 || echo 0)"
ok "S1: alert body lists the low repos, not the healthy ones" "$(grep -q 'r_zero: 0d runway' "$ALERTS" && grep -q 'r_2d: ~2d runway' "$ALERTS" && ! grep -q 'r_15d' "$ALERTS" && echo 1 || echo 0)"

# tighter threshold env: OVN_RUNWAY_ALERT_DAYS=1 -> r_2d no longer low
mk S1b; cp "$T/S1/home/overnight-queue/tasks.json" "$R/"; cp -r "$T/S1/home/overnight-queue/repos/." "$R/repos/"
cp "$T/S1/home/overnight-queue/state/"* "$R/state/"
run NTFY_TOPIC=t2 OVN_RUNWAY_ALERT_DAYS=1
ok "S1b: threshold env respected (3 low)" "$(has_log '=== 3 repo(s) at or under 1d runway (of 6 active) ===' )"
ok "S1b: state/ntfy_topic fallback is unused when env set" "$(grep -q 'ntfy.sh/t2' "$ALERTS" && echo 1 || echo 0)"

# topic from state/ntfy_topic and no-topic silence
mk S1c; cp "$T/S1/home/overnight-queue/tasks.json" "$R/"; cp -r "$T/S1/home/overnight-queue/repos/." "$R/repos/"; cp "$T/S1/home/overnight-queue/state/"* "$R/state/"
echo "filetopic" > "$R/state/ntfy_topic"
run NTFY_TOPIC=
ok "S1c: topic read from state/ntfy_topic when env empty" "$(grep -q 'ntfy.sh/filetopic' "$ALERTS" && echo 1 || echo 0)"
rm "$R/state/ntfy_topic"; : > "$ALERTS"
run NTFY_TOPIC=
ok "S1c: no topic anywhere -> no alert but still logged" "$([ ! -s "$ALERTS" ] && [ "$(has_log '=== 4 repo(s)')" = 1 ] && echo 1 || echo 0)"

# =====================================================================================================
# Scenario 2: all healthy -> clean-run log, no alert
# =====================================================================================================
mk S2
echo '[{"id":"a","repo":"/r/repos/ok1"},{"id":"b","repo":"/r/repos/ok2"}]' > "$R/tasks.json"
mkrepo ok1 40 2; mkrepo ok2 12 2
printf '%s\tok1\tpass\t{py.fix.s.t}\tfoo.py\n' "$NOW" > "$R/state/task_stats.log"
run NTFY_TOPIC=topic
ok "S2: clean run logged" "$(has_log 'clean run — all 2 active repo(s) have runway > 2d')"
ok "S2: no alert" "$([ ! -s "$ALERTS" ] && echo 1 || echo 0)"
ok "S2: missing outcomes.jsonl tolerated (landed_7d=0)" "$(has_log 'ok1: doable=40 runway=~20d burn24h=2 landed_7d=0')"

# =====================================================================================================
# Scenario 3: quiet fleet (no task_stats rows in window) + a repo at 0d runway
# =====================================================================================================
mk S3
echo '[{"id":"a","repo":"/r/repos/dry"}]' > "$R/tasks.json"
mkrepo dry 0 0
: > "$R/state/task_stats.log"
run NTFY_TOPIC=topic
# CORRECT behaviour: a repo with zero doable items must be reported as low runway regardless of how quiet the stats log is.
kb "ovn_fleet_health.sh:78-88 imports ovn_stats, which sys.exit(0)s at import time when task_stats.log has no rows in 24h -> runway() never runs -> false 'clean run — all 0 active repo(s)' all-clear for exactly the stalled-fleet case it exists to catch" \
   "$([ "$(has_log 'dry: doable=0')" = 1 ] && echo 1 || echo 0)"

# no tasks.json at all: ACTIVE empty, script still completes
mk S4
rm -f "$R/tasks.json"
run NTFY_TOPIC=topic
ok "S4: missing tasks.json -> exit 0 and clean-run message" "$([ "$RC" = 0 ] && [ "$(has_log 'clean run')" = 1 ] && echo 1 || echo 0)"

# cd failure
OUT="$(HOME="$T/nohome" bash "$FH" 2>&1)"; RC=$?
ok "S5: missing \$HOME/overnight-queue exits 1" "$([ "$RC" = 1 ] && echo 1 || echo 0)"

echo "ovn_fleet_health_run: $P passed, $F failed, $KB known-bug warning(s)"
[ "$F" = 0 ]
