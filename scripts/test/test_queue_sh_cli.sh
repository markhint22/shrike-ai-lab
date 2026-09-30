#!/usr/bin/env bash
# Runs the REAL queue.sh (phone/SSH control CLI) against a fake $HOME tree and exercises every subcommand:
# status (service up/down, paused, reports, disabled tasks manual vs safety-valve, holds, alerts, docker),
# pause/resume (only ever the FAKE state/PAUSED), report/log/list/enable/disable/repos/add/remove/hold/release/alerts/ack, usage.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
QS=""
for c in "$HERE/../../queue.sh" "$HERE/../queue.sh" "$HERE/queue.sh"; do [ -f "$c" ] && { QS="$c"; break; }; done
[ -n "$QS" ] || { echo "  SKIP: queue.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
has(){ printf '%s' "$OUT" | grep -qF -- "$1" && echo 1 || echo 0; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
HOME_="$T/home"; D="$HOME_/overnight-queue"; BIN="$T/bin"
mkdir -p "$D/state/failures" "$D/reports" "$D/logs/2026-09-29" "$D/logs/2026-09-30" "$D/repos/alpha/.git" "$D/repos/beta" "$BIN"
cat > "$D/tasks.json" <<'EOF'
[
 {"id":"t-on","type":"aider_fix","enabled":true,"repo":"/x/repos/alpha","prompt":"p"},
 {"id":"t-default","repo":"/x/repos/alpha"},
 {"id":"t-manual-off","enabled":false,"repo":"/x/repos/alpha"},
 {"id":"t-valve-off","enabled":false,"repo":"/x/repos/alpha"}
]
EOF
echo 3 > "$D/state/failures/t-valve-off.count"
# stubs
cat > "$BIN/systemctl" <<EOF
#!/usr/bin/env bash
[ -f "$T/svc_down" ] && exit 3
exit 0
EOF
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "shrike-llama: Up 3 hours"
EOF
chmod +x "$BIN"/*
cat > "$D/run_overnight.sh" <<EOF
#!/usr/bin/env bash
echo "STUB run_overnight ran" > "$T/run_now.marker"
echo "run-now stub output"
EOF
chmod +x "$D/run_overnight.sh"
q(){ OUT="$(HOME="$HOME_" PATH="$BIN:$PATH" bash "$QS" "$@" 2>&1)"; RC=$?; }

# ---- status: minimal tree, service up, not paused, no reports, no alerts ----
q
ok "status (default cmd) exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "status: service active line" "$(has 'overnight-queue.service: active')"
ok "status: not paused" "$(has 'Not paused')"
ok "status: no report yet" "$(has 'None yet')"
ok "status: disabled tasks distinguish manual vs safety valve (manual)" "$(has 't-manual-off  (manually disabled)')"
ok "status: safety-valve disabled shows failure count" "$(has 't-valve-off  <- AUTO-DISABLED by safety valve (failed 3x in a row)')"
ok "status: enabled tasks not listed as disabled" "$(printf '%s' "$OUT" | grep -qE '^  t-(on|default)' && echo 0 || echo 1)"
ok "status: no holds" "$(printf '%s' "$OUT" | sed -n '/=== holds/,/=== recent/p' | grep -q '^None' && echo 1 || echo 0)"
ok "status: no alerts" "$(printf '%s' "$OUT" | sed -n '/=== recent alerts/,/=== inference/p' | grep -q '^None' && echo 1 || echo 0)"
ok "status: docker line" "$(has 'shrike-llama: Up 3 hours')"

# ---- status: service down, paused, a report, hold, alerts ----
touch "$T/svc_down"; touch "$D/state/PAUSED"
echo "# report A" > "$D/reports/2026-09-29.md"; sleep 1; echo "# report B" > "$D/reports/2026-09-30.md"
touch "$D/state/HOLD_alpha"
printf 'alert one\nalert two\n' > "$D/state/alerts.log"
q status
ok "status: service NOT ACTIVE" "$(has 'overnight-queue.service: NOT ACTIVE')"
ok "status: PAUSED shown" "$(has 'PAUSED (queue.sh resume to continue)')"
ok "status: latest report name" "$(has '2026-09-30  (queue.sh report for the full table)')"
ok "status: hold listed" "$(has 'alpha  (queue.sh release alpha to clear)')"
ok "status: alerts tail shown" "$(has 'alert two')"
rm -f "$T/svc_down"

# ---- a task with no failure counter file and all tasks enabled -> "None" ----
cp "$D/tasks.json" "$T/tasks.bak"
echo '[{"id":"only","repo":"/x/repos/alpha"}]' > "$D/tasks.json"
q status
ok "status: all enabled -> disabled section says None" "$(printf '%s' "$OUT" | sed -n '/=== disabled tasks/,/=== holds/p' | grep -q '^None' && echo 1 || echo 0)"
cp "$T/tasks.bak" "$D/tasks.json"

# ---- pause / resume (fake tree only) ----
rm -f "$D/state/PAUSED"; rmdir "$D/state" 2>/dev/null
q pause
ok "pause message" "$(has 'Paused. In-progress task still finishes')"
ok "pause creates the flag in the FAKE tree" "$([ -f "$D/state/PAUSED" ] && echo 1 || echo 0)"
q resume
ok "resume message" "$(has 'Resumed.')"
ok "resume removes the flag" "$([ ! -f "$D/state/PAUSED" ] && echo 1 || echo 0)"

# ---- report ----
q report
ok "report (latest) cats the newest file" "$(has '# report B')"
q report 2
ok "report 2 cats the second newest" "$(has '# report A')"
q report 9
ok "report N beyond history -> No report found." "$(has 'No report found.')"

# ---- log ----
q log
ok "log without id -> usage, exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh log <task-id>')" = 1 ] && echo 1 || echo 0)"
q log t-on
ok "log missing -> No log found" "$(has 'No log found for t-on.')"
seq 1 100 > "$D/logs/2026-09-29/t-on.log"; sleep 1; printf 'newest line 1\nnewest line 2\n' > "$D/logs/2026-09-30/t-on.log"
q log t-on
ok "log tails the most recent log" "$(has 'newest line 2')"
ok "log does not show the older file" "$(printf '%s' "$OUT" | grep -qx '100' && echo 0 || echo 1)"

# ---- run-now ----
q run-now
ok "run-now executes run_overnight.sh" "$([ -f "$T/run_now.marker" ] && [ "$(has 'run-now stub output')" = 1 ] && echo 1 || echo 0)"

# ---- list / enable / disable ----
q list
ok "list: explicit enabled" "$(has 't-on  [aider_fix]  enabled=true')"
ok "list: missing enabled defaults to true and type to aider_fix" "$(has 't-default  [aider_fix]  enabled=true')"
ok "list: false shown as false (not //-defaulted)" "$(has 't-manual-off  [aider_fix]  enabled=false')"
q enable
ok "enable w/o id -> usage exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh enable <task-id>')" = 1 ] && echo 1 || echo 0)"
q enable t-valve-off
ok "enable prints counter reset" "$(has 'Enabled t-valve-off (failure counter reset).')"
ok "enable clears the failure counter file" "$([ ! -f "$D/state/failures/t-valve-off.count" ] && echo 1 || echo 0)"
ok "enable flips enabled=true in tasks.json" "$([ "$(jq -r '.[]|select(.id=="t-valve-off").enabled' "$D/tasks.json")" = true ] && echo 1 || echo 0)"
q disable
ok "disable w/o id -> usage exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh disable <task-id>')" = 1 ] && echo 1 || echo 0)"
q disable t-on
ok "disable message" "$(has 'Disabled t-on.')"
ok "disable flips enabled=false" "$([ "$(jq -r '.[]|select(.id=="t-on").enabled' "$D/tasks.json")" = false ] && echo 1 || echo 0)"

# ---- repos ----
q repos
ok "repos lists clones" "$(has 'alpha')"

# ---- add ----
q add
ok "add w/o args -> usage + available repos, exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh add <task-id>')" = 1 ] && [ "$(has 'Available repos:')" = 1 ] && echo 1 || echo 0)"
q add newid alpha
ok "add with empty prompt rejected" "$([ "$RC" = 1 ] && [ "$(has "prompt can't be empty")" = 1 ] && echo 1 || echo 0)"
q add newid nosuchrepo do something
ok "add unknown repo rejected" "$([ "$RC" = 1 ] && [ "$(has 'No cloned repo at')" = 1 ] && echo 1 || echo 0)"
ok "add: dir without .git rejected (beta)" "$(q add newid beta x y; [ "$RC" = 1 ] && [ "$(has 'No cloned repo at')" = 1 ] && echo 1 || echo 0)"
q add t-on alpha another prompt
ok "add duplicate id rejected" "$([ "$RC" = 1 ] && [ "$(has "A task with id 't-on' already exists")" = 1 ] && echo 1 || echo 0)"
q add newid alpha fix the flaky thing in foo.py please
ok "add succeeds" "$([ "$RC" = 0 ] && [ "$(has "Added 'newid' (repo: alpha, enabled)")" = 1 ] && echo 1 || echo 0)"
ok "add stores the multi-word prompt verbatim" "$([ "$(jq -r '.[]|select(.id=="newid").prompt' "$D/tasks.json")" = 'fix the flaky thing in foo.py please' ] && echo 1 || echo 0)"
ok "add stores the repo path under repos/" "$([ "$(jq -r '.[]|select(.id=="newid").repo' "$D/tasks.json")" = "$D/repos/alpha" ] && echo 1 || echo 0)"

# ---- remove ----
q remove
ok "remove w/o id -> usage exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh remove <task-id>')" = 1 ] && echo 1 || echo 0)"
q remove newid
ok "remove message" "$(has 'Removed newid.')"
ok "remove deletes from tasks.json" "$([ "$(jq -r '[.[]|select(.id=="newid")]|length' "$D/tasks.json")" = 0 ] && echo 1 || echo 0)"

# ---- hold / release ----
q hold
ok "hold w/o repo -> usage exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh hold <repo-name>')" = 1 ] && echo 1 || echo 0)"
rm -f "$D/state/HOLD_alpha"
q hold alpha
ok "hold creates HOLD_<repo>" "$([ -f "$D/state/HOLD_alpha" ] && [ "$(has 'Held alpha.')" = 1 ] && echo 1 || echo 0)"
q release
ok "release w/o repo -> usage exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh release <repo-name>')" = 1 ] && echo 1 || echo 0)"
q release alpha
ok "release removes HOLD_<repo>" "$([ ! -f "$D/state/HOLD_alpha" ] && [ "$(has 'Released alpha.')" = 1 ] && echo 1 || echo 0)"

# ---- alerts / ack ----
: > "$D/state/alerts.log"
q alerts
ok "alerts with empty log -> No alerts." "$(has 'No alerts.')"
q ack
ok "ack with nothing -> No alerts to ack." "$(has 'No alerts to ack.')"
seq 1 30 | sed 's/^/alert /' > "$D/state/alerts.log"
q alerts 3
ok "alerts N tails N lines" "$([ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 3 ] && [ "$(has 'alert 30')" = 1 ] && echo 1 || echo 0)"
q alerts
ok "alerts default tails 20" "$([ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" = 20 ] && echo 1 || echo 0)"
q ack
ok "ack archives then clears" "$([ "$(has 'Acknowledged; history kept')" = 1 ] && [ ! -s "$D/state/alerts.log" ] && [ "$(wc -l < "$D/state/alerts.log.acked" | tr -d ' ')" = 30 ] && echo 1 || echo 0)"

# ---- usage ----
q bogus-subcommand
ok "unknown subcommand -> usage, exit 1" "$([ "$RC" = 1 ] && [ "$(has 'Usage: queue.sh {status|pause|resume')" = 1 ] && echo 1 || echo 0)"

echo "queue_sh_cli: $P passed, $F failed"
[ "$F" = 0 ]
