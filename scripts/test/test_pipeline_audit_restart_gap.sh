#!/usr/bin/env bash
# ovn_pipeline_audit.sh (2026-10-09): (1) the ~3 s RestartSec gap of the idle restart loop made `systemctl is-active` print "activating", which the audit
# reported as "[CRIT] overnight-queue.service is NOT active" (2 of ~11 runs): activating now counts as alive and a dead state is retried before it is CRIT;
# (2) the CRITICAL push lived only in the crontab line (`|| curl https://ntfy.sh/...`, bypassing the notification relay): the audit now posts it itself
# through "$NTFY_SERVER/$topic" (priority urgent = relay emergency); with NTFY_SERVER unset/empty it pushes NOTHING (no direct ntfy.sh fallback, a manual run
# must not spend the shared per-IP quota) and only logs the CRIT lines to state/alerts.log.
# Runs the REAL ovn_pipeline_audit.sh end to end in a hermetic fake $HOME with stub systemctl (state sequence), stub curl (records every call) and no network,
# then runs the same scenarios against 5 mutants of the script, each of which must be caught.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
AUDIT=""
for c in "$HERE/../../ovn_pipeline_audit.sh" "$HERE/../ovn_pipeline_audit.sh"; do [ -f "$c" ] && { AUDIT="$c"; break; }; done
[ -n "$AUDIT" ] || { echo "  SKIP: ovn_pipeline_audit.sh not found"; exit 0; }
AUDIT="$(cd "$(dirname "$AUDIT")" && pwd)/$(basename "$AUDIT")"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # /private/var vs /var on macOS
P=0; F=0
# assertions are evaluated with pipefail OFF (no `x | grep -q` flakiness); conditions use grep -c / [ ] only
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $SUITE: $1"; fi; }

RELAY="http://relay.invalid:8099"
build(){  # $1=audit script to test -> fake tree in $W
  W="$T/w.$RANDOM"; H="$W/home"; R="$H/overnight-queue"; CTL="$W/ctl"; BIN="$W/bin"
  mkdir -p "$R/state" "$R/scripts/test" "$CTL" "$BIN"
  cp "$1" "$R/ovn_pipeline_audit.sh"
  for r in gitlark iptv_apps shrike-monitor shrike-notify test-automation-agent xlite billwatch; do mkdir -p "$R/repos/$r/.git"; done
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/crontab"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/fuser"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ps"
  printf '#!/usr/bin/env bash\nprintf "Filesystem 1024-blocks Used Available Capacity Mounted\\nx 100 40 60 40%% /\\n"\n' > "$BIN/df"
  # systemctl: pops the next state from $CTL/svc_seq (the last one repeats); prints it like `systemctl is-active`; exit 0 only for "active"
  cat > "$BIN/systemctl" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = show ]; then echo "NRestarts=7"; exit 0; fi   # \`systemctl show -p NRestarts ...\`: not a state probe, not counted
echo x >> "$CTL/svc_calls"
n=\$(wc -l < "$CTL/svc_calls" | tr -d ' ')
st="\$(sed -n "\${n}p" "$CTL/svc_seq")"; [ -n "\$st" ] || st="\$(tail -1 "$CTL/svc_seq")"
echo "\$st"; [ "\$st" = active ]
EOF
  # curl: LiteLLM probe (-w) answers 200; every other call is a push and is only recorded
  cat > "$BIN/curl" <<EOF
#!/usr/bin/env bash
case "\$*" in *"-w "*) printf 200; exit 0;; esac
echo "\$*" >> "$CTL/curl_pushes"
[ -f "$CTL/curl_fail" ] && exit 22
exit 0
EOF
  chmod +x "$BIN/"*
}
scenario(){  # $1=state sequence (space separated) ; extra env passed via $2.. as VAR=val ; sets OUT RC
  local seq="$1"; shift
  : > "$CTL/svc_calls"; : > "$CTL/curl_pushes"; printf '%s\n' $seq > "$CTL/svc_seq"
  local srv=(NTFY_SERVER="$RELAY"); [ "${NOSRV:-}" = 1 ] && srv=()   # NOSRV=1: the variable is not in the environment at all
  : > "$R/state/alerts.log"
  OUT="$(cd "$H" && env -i HOME="$H" PATH="$BIN:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" ${srv[@]+"${srv[@]}"} NTFY_TOPIC=selftest OVN_AUDIT_SVC_SLEEP=0 "$@" bash "$R/ovn_pipeline_audit.sh" --quiet 2>&1)"; RC=$?
}
probes(){ wc -l < "$CTL/svc_calls" | tr -d ' '; }
pushes(){ wc -l < "$CTL/curl_pushes" | tr -d ' '; }
crit_n(){ printf '%s\n' "$OUT" | grep -c 'overnight-queue.service is NOT active'; }
ntfy_direct(){ grep -c 'ntfy\.sh' "$CTL/curl_pushes"; }

run_suite(){  # $1=label $2=audit path
  SUITE="$1"; P0=$F
  build "$2"
  scenario "active"
  ok "baseline: active service, no CRIT, exit 0, one probe, nothing pushed (the fake tree itself is clean)" "[ $RC -eq 0 ] && [ \"\$(crit_n)\" = 0 ] && [ \"\$(probes)\" = 1 ] && [ \"\$(pushes)\" = 0 ]"
  scenario "activating activating active"
  ok "activating (restart gap) then active: no CRIT, no stuck-activating WARN, exit 0" "[ $RC -eq 0 ] && [ \"\$(crit_n)\" = 0 ] && [ \"\$(printf '%s\n' \"\$OUT\" | grep -c 'stayed')\" = 0 ]"
  ok "a restart-gap push is never sent" "[ \"\$(pushes)\" = 0 ]"
  scenario "activating"
  ok "state 'activating' at EVERY probe (restart loop, never seen active): not down -> no CRIT, exit 0, no push; but all 3 probes were taken" "[ $RC -eq 0 ] && [ \"\$(crit_n)\" = 0 ] && [ \"\$(pushes)\" = 0 ] && [ \"\$(probes)\" = 3 ]"
  ok "state 'activating' at every probe is a WARN (not a silent pass) naming the state, the probe count and NRestarts" "[ \"\$(printf '%s\n' \"\$OUT\" | grep -c \"WARN.*stayed 'activating' for all 3 probes.*NRestarts=7\")\" = 1 ] && [ \"\$(printf '%s\n' \"\$OUT\" | grep -c 'service is activating')\" = 0 ]"
  scenario "activating active"
  ok "activating then active: a plain pass (no stuck-activating WARN), 2 probes" "[ $RC -eq 0 ] && [ \"\$(printf '%s\n' \"\$OUT\" | grep -c 'stayed')\" = 0 ] && [ \"\$(probes)\" = 2 ]"
  scenario "failed failed active"
  ok "failed twice then active: recovered inside the retries -> no CRIT, 3 probes" "[ $RC -eq 0 ] && [ \"\$(crit_n)\" = 0 ] && [ \"\$(probes)\" = 3 ]"
  scenario "failed failed failed"
  ok "failed x3: CRIT with the state and probe count in the message, exit 1" "[ $RC -eq 1 ] && [ \"\$(crit_n)\" = 1 ] && [ \"\$(printf '%s\n' \"\$OUT\" | grep -c 'state: failed after 3 probes')\" = 1 ]"
  ok "failed x3: exactly 3 probes (not 1, not unbounded)" "[ \"\$(probes)\" = 3 ]"
  ok "failed x3: exactly ONE push, to the relay URL + topic, priority urgent, carrying the CRIT text" "[ \"\$(pushes)\" = 1 ] && [ \"\$(grep -c -F -- \"$RELAY/selftest\" \"$CTL/curl_pushes\")\" = 1 ] && [ \"\$(grep -c 'Priority: urgent' \"$CTL/curl_pushes\")\" = 1 ] && [ \"\$(grep -c 'overnight-queue.service is NOT active' \"$CTL/curl_pushes\")\" = 1 ]"
  ok "failed x3: NO direct ntfy.sh post (the old cron '|| curl https://ntfy.sh/...' bypass)" "[ \"\$(ntfy_direct)\" = 0 ]"
  scenario "inactive inactive inactive"
  ok "inactive x3 is CRIT too" "[ $RC -eq 1 ] && [ \"\$(crit_n)\" = 1 ]"
  scenario "failed failed failed" OVN_AUDIT_NOTIFY=0
  ok "OVN_AUDIT_NOTIFY=0: still CRIT / exit 1 but nothing is pushed" "[ $RC -eq 1 ] && [ \"\$(crit_n)\" = 1 ] && [ \"\$(pushes)\" = 0 ]"
  scenario "activating" OVN_AUDIT_RESTART_GAP_OK=0 OVN_AUDIT_SVC_RETRIES=1
  ok "kill switches (RESTART_GAP_OK=0, RETRIES=1) restore the old behaviour: activating is CRIT after a single probe" "[ $RC -eq 1 ] && [ \"\$(crit_n)\" = 1 ] && [ \"\$(probes)\" = 1 ]"
  scenario "failed failed failed" NTFY_SERVER=
  ok "NTFY_SERVER empty: still CRIT / exit 1, but NOTHING is pushed (no direct ntfy.sh fallback, curl is never called for a push)" "[ $RC -eq 1 ] && [ \"\$(crit_n)\" = 1 ] && [ \"\$(pushes)\" = 0 ] && [ \"\$(ntfy_direct)\" = 0 ]"
  ok "NTFY_SERVER empty: the CRIT line is logged to state/alerts.log instead (crit | pipeline_audit | ... NOT active ... not pushed)" "[ \"\$(grep -c 'crit | pipeline_audit | .*overnight-queue.service is NOT active.*not pushed' \"$R/state/alerts.log\")\" = 1 ]"
  NOSRV=1 scenario "failed failed failed"
  ok "NTFY_SERVER not in the environment at all (interactive shell / systemd): exit 1, zero pushes, zero direct ntfy.sh posts" "[ $RC -eq 1 ] && [ \"\$(crit_n)\" = 1 ] && [ \"\$(pushes)\" = 0 ] && [ \"\$(ntfy_direct)\" = 0 ]"
  ok "NTFY_SERVER not set: the CRIT line is in state/alerts.log" "[ \"\$(grep -c 'crit | pipeline_audit' \"$R/state/alerts.log\")\" = 1 ]"
  # 2026-10-09: relay configured but UNREACHABLE (curl fails): the CRIT must not vanish silently
  : > "$CTL/curl_fail"; scenario "failed failed failed"; rm -f "$CTL/curl_fail"
  ok "relay unreachable: still CRIT / exit 1 and the failed push is recorded in state/alerts.log (push FAILED)" "[ $RC -eq 1 ] && [ \"\$(grep -c 'push FAILED' \"$R/state/alerts.log\")\" = 1 ]"
  scenario "failed failed failed"
  ok "relay reachable: no 'push FAILED' line (the failure branch is not taken on success)" "[ \"\$(grep -c 'push FAILED' \"$R/state/alerts.log\")\" = 0 ]"
  scenario "active" NTFY_SERVER=
  ok "a clean run with no relay writes nothing to alerts.log" "[ \"\$(wc -c < \"$R/state/alerts.log\" | tr -d ' ')\" = 0 ]"
  SUITE_FAILS=$((F - P0))
}

F0=0
run_suite "real" "$AUDIT"; REAL_FAILS=$SUITE_FAILS
[ "$REAL_FAILS" -eq 0 ] && echo "  ok   real script: all scenario assertions hold"

mutate(){  # $1=label $2=old $3=new : the suite run against the mutant must report >0 failures
  OLD="$2" NEW="$3" python3 - "$AUDIT" "$T/mutant.sh" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) < 1:
    sys.exit("mutation anchor not found: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { F=$((F+1)); echo "  FAIL: mutation '$1' could not be applied"; return; }
  local Pb=$P Fb=$F; local out
  out="$(run_suite "mutant" "$T/mutant.sh" 2>&1)"
  local mf=$SUITE_FAILS
  # the mutant run's own FAIL lines are expected: roll the counters back and judge by the number of failures it produced
  P=$Pb; F=$Fb
  if [ "$(printf '%s\n' "$out" | grep -c 'FAIL: mutant')" -gt 0 ]; then P=$((P+1)); echo "  ok   mutation caught: $1"; else F=$((F+1)); echo "  FAIL: mutation NOT caught: $1"; fi
}
mutate "activating no longer counted alive" 'activating|reloading) if [ "${OVN_AUDIT_RESTART_GAP_OK:-1}" != 0 ]; then' 'activating|reloading) if false; then'
mutate "activating breaks out on the first probe (old behaviour: a crash loop passes)" 'case "$svc_state" in active) break;; esac' 'case "$svc_state" in active|activating|reloading) break;; esac'
mutate "stuck activating passes silently instead of WARN" 'warn "overnight-queue.service stayed' 'pass "overnight-queue.service stayed'
mutate "no retries (single probe)" '${OVN_AUDIT_SVC_RETRIES:-3}' '1'
mutate "push goes straight to ntfy.sh" '"${NTFY_SERVER}/' '"https://ntfy.sh/'
mutate "empty NTFY_SERVER falls back to ntfy.sh (the reviewed defect)" 'if [ -n "${NTFY_SERVER:-}" ]; then' 'if true; then'
mutate "empty NTFY_SERVER: nothing pushed but also nothing logged" '>> "$PWD/state/alerts.log"' '>> /dev/null'
mutate "CRIT push dropped" 'if [ "$CRIT" -gt 0 ] && [ "${OVN_AUDIT_NOTIFY:-1}" != 0 ]; then' 'if false; then'
mutate "dead service reported as pass" '*) crit "overnight-queue.service is NOT active (state: ${svc_state:-unknown}' '*) pass "overnight-queue.service is NOT active (state: ${svc_state:-unknown}'

echo "pipeline_audit_restart_gap: $P passed, $F failed"
[ "$F" -eq 0 ]
