#!/usr/bin/env bash
# Runs the REAL ovn_pipeline_audit.sh end to end in hermetic fake trees ($HOME -> temp dir) with stubbed
# crontab/fuser/ps/systemctl/curl/df/cat(syslog) and covers every audit section's OK / WARN / CRIT branch.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AUDIT=""
for c in "$HERE/../../ovn_pipeline_audit.sh" "$HERE/../ovn_pipeline_audit.sh" "$HERE/ovn_pipeline_audit.sh"; do [ -f "$c" ] && { AUDIT="$c"; break; }; done
[ -n "$AUDIT" ] || { echo "  SKIP: ovn_pipeline_audit.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
has(){ printf '%s' "$OUT" | grep -qF -- "$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
NOW_ISO(){ date -u -d "$1" +%Y-%m-%dT%H:%M:%S.000000+00:00; }

# ---- build a fake tree. $1 = name. Stubs read scenario files from $T/<name>/ctl ----
mk(){
  local n="$1" H="$T/$1/home"; R="$H/overnight-queue"; CTL="$T/$n/ctl"
  mkdir -p "$R/state" "$R/scripts/test" "$T/$n/bin" "$CTL"
  export H R CTL
  cp "$AUDIT" "$R/ovn_pipeline_audit.sh"
  # stubs -------------------------------------------------------------
  cat > "$T/$n/bin/crontab" <<EOF
#!/usr/bin/env bash
[ "\$1" = "-l" ] && cat "$CTL/crontab" 2>/dev/null
exit 0
EOF
  cat > "$T/$n/bin/fuser" <<EOF
#!/usr/bin/env bash
# "fuser <file>" -> "<file>: pid pid" when a holders file exists for that basename
b="\$(basename "\$1")"; [ -f "$CTL/fuser.\$b" ] && echo "\$1: \$(cat "$CTL/fuser.\$b")"
exit 0
EOF
  cat > "$T/$n/bin/ps" <<EOF
#!/usr/bin/env bash
case "\$1" in
  aux) cat "$CTL/ps_aux" 2>/dev/null; exit 0;;
  -o) p="\$4"; grep -qx "\$p" "$CTL/live_pids" 2>/dev/null && { echo "cmd"; exit 0; }; exit 1;;
esac
exit 0
EOF
  cat > "$T/$n/bin/systemctl" <<EOF
#!/usr/bin/env bash
[ -f "$CTL/svc_down" ] && exit 3
exit 0
EOF
  cat > "$T/$n/bin/curl" <<EOF
#!/usr/bin/env bash
cat "$CTL/curl_code" 2>/dev/null || printf 200
exit 0
EOF
  cat > "$T/$n/bin/df" <<EOF
#!/usr/bin/env bash
[ -f "$CTL/df_out" ] && { cat "$CTL/df_out"; exit 0; }
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nx 100 40 60 40%% /\n'
EOF
  # cat stub: serve the syslog fixture for the two hard-coded syslog paths, pass everything else through
  cat > "$T/$n/bin/cat" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = "/var/log/syslog.1" ]; then cat_real(){ /bin/cat "\$@"; }; /bin/cat "$CTL/syslog.1" 2>/dev/null; /bin/cat "$CTL/syslog" 2>/dev/null; exit 0; fi
exec /bin/cat "\$@"
EOF
  chmod +x "$T/$n/bin/"*
}
run(){ # $1=name, rest=args
  local n="$1"; shift
  OUT="$(cd "$T/$n/home" && HOME="$T/$n/home" PATH="$T/$n/bin:$PATH" bash "$T/$n/home/overnight-queue/ovn_pipeline_audit.sh" "$@" 2>&1)"; RC=$?
}
mkrepos(){ # $1=name; make the 7 repos: state per $2..: clean|dirty|missing
  local n="$1"; shift; local names=(gitlark iptv_apps shrike-monitor shrike-notify test-automation-agent xlite billwatch) i=0
  for r in "${names[@]}"; do
    local st="${1:-clean}"; shift || true
    local d="$T/$n/home/overnight-queue/repos/$r"
    [ "$st" = missing ] && continue
    mkdir -p "$d"; git -C "$d" init -q 2>/dev/null; git -C "$d" config user.email t@t; git -C "$d" config user.name t
    echo a > "$d/a.txt"; git -C "$d" add a.txt; git -C "$d" commit -q -m init
    [ "$st" = dirty ] && echo b > "$d/untracked.txt"
  done
}

# =====================================================================================================
# Scenario A: healthy pipeline -> all OK, exit 0, --quiet hides OK lines
# =====================================================================================================
mk A
cat > "$CTL/crontab" <<'EOF'
# a comment line
* * * * * cd ~/overnight-queue && ./every_min.sh >> logs/x.log 2>&1
*/5 * * * * cd ~/overnight-queue && ./five_min.sh
0 * * * * cd ~/overnight-queue && ./hourly.sh
17 */6 * * * cd ~/overnight-queue && ./six_hourly.sh
30 3 * * * cd ~/overnight-queue && ./daily.sh
5 2 * * * /home/x/overnight-queue/scripts/tooled.py
EOF
mkdir -p "$R/scripts"
for s in every_min five_min hourly six_hourly daily; do printf '#!/usr/bin/env bash\nexit 0\n' > "$R/$s.sh"; chmod +x "$R/$s.sh"; done
printf 'print("hi")\n' > "$R/scripts/tooled.py"; chmod +x "$R/scripts/tooled.py"
# run_overnight.sh calls internal helpers
cat > "$R/run_overnight.sh" <<'EOF'
#!/usr/bin/env bash
bash "$SCRIPT_DIR/scripts/helper_a.sh"
"./helper_b.sh"
EOF
printf '#!/usr/bin/env bash\n' > "$R/scripts/helper_a.sh"; printf '#!/usr/bin/env bash\n' > "$R/helper_b.sh"
# tests reference (some of) the scripts
echo "# placeholder so grep's scripts/test/*.py glob resolves" > "$R/scripts/test/test_x.py"
cat > "$R/scripts/test/test_x.sh" <<'EOF'
every_min.sh five_min.sh hourly.sh six_hourly.sh daily.sh tooled.py helper_a.sh helper_b.sh
EOF
# syslog: each script dispatched "just now" (2 min ago) -> inside every threshold
{
  for s in every_min five_min hourly six_hourly daily tooled; do
    echo "$(NOW_ISO '2 minutes ago') host CRON[123]: (u) CMD (cd ~/overnight-queue && ./$s.sh)"
  done
} > "$CTL/syslog"
# the .py cron line isn't matched by the './x' pattern of section 2 -> skipped silently
touch "$R/state/run.lock"; echo "11 22 33" > "$CTL/fuser.run.lock"; printf '22\n' > "$CTL/live_pids"
touch "$R/state/stage.lock"                     # exists, nobody holds it
: > "$CTL/ps_aux"; echo "USER PID %CPU %MEM VSZ RSS TTY S START TIME COMMAND" > "$CTL/ps_aux"; echo "root 1 0 0 1 1 ? S 00:00 0:00 init" >> "$CTL/ps_aux"
mkrepos A clean clean clean clean clean clean clean
printf '{"a":1}\n\n{"b":2}\n' > "$R/state/outcomes.jsonl"
run A
ok "A: healthy run exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "A: section 1 syntax OK for .sh" "$(has 'every_min.sh: syntax OK')"
ok "A: section 1 syntax OK for .py (absolute overnight-queue path form)" "$(has 'scripts/tooled.py: syntax OK')"
ok "A: empty-interval '* * * * *' passes at 1min cadence" "$(has 'every_min.sh: cron dispatched it')"
ok "A: */5 interval parsed" "$(has 'expected every ~5min')"
ok "A: hourly interval (min fixed, hour *) parsed as 60" "$(has 'expected every ~60min')"
ok "A: */6 hour field parsed as 360" "$(has 'expected every ~360min')"
ok "A: daily fixed-hour parsed as 1440" "$(has 'expected every ~1440min')"
ok "A: section 3 internal script exists" "$(has 'run_overnight.sh -> scripts/helper_a.sh exists')"
ok "A: section 3 ./relative internal script exists" "$(has 'run_overnight.sh -> helper_b.sh exists')"
ok "A: section 4 tested script" "$(has 'every_min.sh: has test coverage')"
ok "A: multi-PID lock with one live PID is OK" "$(has 'state/run.lock held by live PID(s)')"
ok "A: un-held lock OK" "$(has 'state/stage.lock not currently held')"
ok "A: no zombies" "$(has 'no zombie processes')"
ok "A: service active" "$(has 'overnight-queue.service is active')"
ok "A: LiteLLM reachable (HTTP 200)" "$(has 'LiteLLM (localhost:4000) is reachable (HTTP 200)')"
ok "A: fleet not paused" "$(has 'fleet is not paused')"
ok "A: repos clean" "$(has 'repos/gitlark on')"
ok "A: disk OK" "$(has 'disk space OK: 60% free')"
ok "A: outcomes.jsonl valid (blank lines skipped)" "$(has 'state/outcomes.jsonl: all lines valid JSON')"
ok "A: summary line" "$(has '0 warnings, 0 critical')"
ok "A: pass() lines shown without --quiet" "$(has '[ OK ]')"
run A --quiet
ok "A: --quiet exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "A: --quiet suppresses OK lines" "$(printf '%s' "$OUT" | grep -qF '[ OK ]' && echo 0 || echo 1)"
ok "A: --quiet still prints summary" "$(has 'Pipeline audit:')"

# =====================================================================================================
# Scenario B: everything broken -> CRIT findings + exit 1
# =====================================================================================================
mk B
cat > "$CTL/crontab" <<'EOF'
* * * * * cd ~/overnight-queue && ./ghost.sh
* * * * * cd ~/overnight-queue && ./nonexec.sh
* * * * * cd ~/overnight-queue && ./badsyntax.sh
* * * * * cd ~/overnight-queue && ./badpy.py
* * * * * cd ~/overnight-queue && ./stale.sh
* * * * * cd ~/overnight-queue && ./nosyslog.sh
* * * * * cd ~/overnight-queue && ./badts.sh
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/nonexec.sh"     # exists, not executable
printf '#!/usr/bin/env bash\nif then fi (\n' > "$R/badsyntax.sh"; chmod +x "$R/badsyntax.sh"
printf 'def (:\n' > "$R/badpy.py"; chmod +x "$R/badpy.py"
for s in stale nosyslog badts; do printf '#!/usr/bin/env bash\n' > "$R/$s.sh"; chmod +x "$R/$s.sh"; done
{
  echo "$(NOW_ISO '3 hours ago') host CRON[1]: (u) CMD (cd ~/overnight-queue && ./stale.sh)"
  echo "2026-99-99T99:99:99 host CRON[1]: (u) CMD (cd ~/overnight-queue && ./badts.sh)"
} > "$CTL/syslog"
echo "$(NOW_ISO '5 days ago') old line for stale.sh" > "$CTL/syslog.1"
cat > "$R/run_overnight.sh" <<'EOF'
bash "$SCRIPT_DIR/scripts/missing_helper.sh"
EOF
touch "$R/state/run.lock"; echo "77 88" > "$CTL/fuser.run.lock"; : > "$CTL/live_pids"   # orphaned
touch "$R/state/reconcile.lock"; echo "5" > "$CTL/fuser.reconcile.lock"; echo 5 > "$CTL/live_pids"
printf 'USER PID\nroot 9 0 0 0 0 ? Z 00:00 0:00 [defunct]\n' > "$CTL/ps_aux"
touch "$CTL/svc_down"; printf 000 > "$CTL/curl_code"
touch -d '3 hours ago' "$R/state/PAUSED"
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nx 100 95 5 95%% /\n' > "$CTL/df_out"
mkrepos B missing dirty clean missing clean dirty clean
printf '{"ok":1}\nNOT JSON\n{broken\n' > "$R/state/outcomes.jsonl"
run B
ok "B: exit 1 when CRIT findings" "$([ "$RC" = 1 ] && echo 1 || echo 0)"
ok "B: cron script missing -> CRIT" "$(has "cron references 'ghost.sh' but it does not exist")"
ok "B: non-executable -> WARN" "$(has "'nonexec.sh' is cron-referenced but not executable")"
ok "B: bash syntax error -> CRIT" "$(has 'badsyntax.sh: SYNTAX ERROR')"
ok "B: python syntax error -> CRIT" "$(has 'badpy.py: SYNTAX ERROR')"
ok "B: stale cron dispatch -> WARN" "$(has 'stale.sh: cron last dispatched it')"
ok "B: no syslog dispatch -> WARN" "$(has 'nosyslog.sh: no cron dispatch found in syslog')"
ok "B: unparsable syslog timestamp -> WARN" "$(has "badts.sh: could not parse syslog timestamp")"
ok "B: internal missing -> CRIT" "$(has "run_overnight.sh calls 'scripts/missing_helper.sh' but it does not exist")"
ok "B: untested active script -> WARN" "$(has 'ghost.sh: NO test file references it')"
ok "B: orphaned lock -> CRIT" "$(has 'state/run.lock appears held but none of PID(s)77 88 are real processes')"
ok "B: live single-holder lock OK" "$(has 'state/reconcile.lock held by live PID(s):5')"
ok "B: zombie -> WARN" "$(has '1 zombie process(es) found')"
ok "B: service down -> CRIT" "$(has 'overnight-queue.service is NOT active')"
ok "B: LiteLLM unreachable -> CRIT" "$(has 'LiteLLM (localhost:4000) is NOT reachable')"
ok "B: stale PAUSED -> CRIT" "$(has 'state/PAUSED has existed for')"
ok "B: missing repo -> CRIT" "$(has 'repos/gitlark is not a git repo')"
ok "B: dirty repo -> WARN" "$(has 'repos/iptv_apps (')"
ok "B: disk nearly full -> CRIT" "$(has 'disk space critically low: only 5% free')"
ok "B: malformed outcomes lines -> WARN" "$(has 'state/outcomes.jsonl has 2 malformed line(s)')"

# =====================================================================================================
# Scenario C: empty crontab, fresh PAUSED (warn), unreadable df, no outcomes file
# =====================================================================================================
mk C
: > "$CTL/crontab"
: > "$R/run_overnight.sh"
touch "$R/state/PAUSED"
printf '' > "$CTL/df_out"
mkrepos C clean clean clean clean clean clean clean
run C
ok "C: empty crontab -> WARN, not CRIT" "$(has 'crontab is empty or unreadable')"
ok "C: fresh PAUSED -> WARN only" "$(has 'state/PAUSED exists (')"
ok "C: no CRIT at all -> exit 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "C: empty df output skips the disk verdict" "$(printf '%s' "$OUT" | grep -qE 'disk space' && echo 0 || echo 1)"
ok "C: missing outcomes.jsonl is tolerated" "$(printf '%s' "$OUT" | grep -qF 'malformed' && echo 0 || echo 1)"

# audit cd's into $HOME/overnight-queue: missing dir -> exit 1
mkdir -p "$T/D/empty"; OUT="$(HOME="$T/D/empty" bash "$AUDIT" 2>&1)"; RC=$?
ok "D: missing \$HOME/overnight-queue exits 1" "$([ "$RC" = 1 ] && echo 1 || echo 0)"

echo "ovn_pipeline_audit_run: $P passed, $F failed"
[ "$F" = 0 ]
