#!/usr/bin/env bash
# Wave-3 extra coverage for scripts/ovn_failure_triage_cron.sh: (1) lock contention -> skip + exit 0 (stub flock),
# (2) regression found with NO ntfy topic -> kept in the pending file, no push attempted, exit 0.
# Hermetic fixture HOME + stub curl/flock; never touches production state or the network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SD="$HERE/.."; [ -f "$SD/ovn_failure_triage_cron.sh" ] || SD="$HERE/../scripts"
CRON="$SD/ovn_failure_triage_cron.sh"
[ -f "$CRON" ] || { echo "  SKIP: cron script not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/overnight-queue"/{state,scripts,logs}
Q="$tmp/home/overnight-queue"; BST="$Q/state"
for f in ovn_failure_triage.py ovn_outcome_buckets.py lib_lock.sh; do cp "$SD/$f" "$Q/scripts/$f"; done
cp "$CRON" "$Q/scripts/ovn_failure_triage_cron.sh"
cat > "$tmp/bin/curl" <<CURL
#!/usr/bin/env bash
echo "curl \$*" >> "$tmp/curl.calls"; exit 0
CURL
chmod +x "$tmp/bin/curl"
run_cron(){ ( PATH="$tmp/bin:$PATH" HOME="$tmp/home" NTFY_TOPIC="" bash "$Q/scripts/ovn_failure_triage_cron.sh" >/dev/null 2>&1 ); echo $?; }
LOG="$Q/logs/ovn_failure_triage.log"

echo "== lock contention"
cat > "$tmp/bin/flock" <<'FL'
#!/usr/bin/env bash
exit 1
FL
chmod +x "$tmp/bin/flock"
rc="$(run_cron)"
ok "contended lock -> exit 0" "[ '$rc' = 0 ]"
ok "contended lock logs the skip" "grep -q 'another triage pass holds the lock' '$LOG'"
ok "contended lock never runs the detector (no detection line)" "! grep -q 'detection pass rc=' '$LOG'"
rm -f "$tmp/bin/flock"

echo "== regression but no topic"
SIG="no-log:fail_reason=build-red;status=reverted(build-break)"
add_outcome(){ python3 - "$BST/outcomes.jsonl" <<'PY'
import json,sys,datetime as d
rec={"ts":d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),"repo":"demo","id":"ongoing-demo","type":"aider_fix",
     "tier":"2","category":"test","class":"reverted","severity":"bad","attempt":1,"fail_reason":"build-red","status":"reverted(build-break)",
     "tokens_sent":1,"tokens_recv":1,"duration_s":1,"item_hash":"h1","feat_tag":""}
open(sys.argv[1],"a").write(json.dumps(rec)+"\n")
PY
}
add_outcome; run_cron >/dev/null     # registers the pattern as new
python3 - "$BST/failure_clusters.json" "demo::$SIG" <<'PY'
import json,sys
p,k=sys.argv[1:3]; r=json.load(open(p)); r[k]["status"]="fixed"; r[k]["fix_commit"]="abc1234"; r[k]["generator_addressed"]="yes"
json.dump(r,open(p,"w"))
PY
add_outcome
rm -f "$BST/ntfy_topic" "$tmp/curl.calls"
rc="$(run_cron)"
ok "no-topic regression run exits 0" "[ '$rc' = 0 ]"
ok "it logs that no topic is configured" "grep -q 'no ntfy topic configured' '$LOG'"
ok "the regression is kept pending" "grep -q 'abc1234\|demo' '$BST/failure_triage_pending_push.txt'"
ok "no push attempted without a topic" "[ ! -f '$tmp/curl.calls' ]"
echo topic1 > "$BST/ntfy_topic"
rc="$(run_cron)"
ok "once a topic exists the pending regression is delivered" "grep -q 'ntfy.sh/topic1' '$tmp/curl.calls'"
ok "and the pending file is cleared" "[ ! -e '$BST/failure_triage_pending_push.txt' ]"

echo "$P passed, $F failed"; [ "$F" -eq 0 ]
