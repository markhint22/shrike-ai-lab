#!/usr/bin/env bash
# Regression test for the notification half of Phase 6c (failure triage):
#   (A) digest_notify.sh folds a CAPPED "new failure patterns" section into the routine digest,
#       only for patterns first seen inside the window, and does NOT re-report regressions
#       (those are the hourly runner's job).
#   (B) ovn_failure_triage_cron.sh pushes exactly ONE high-priority alert when a pattern already
#       marked "fixed" recurs, pushes nothing for merely-new patterns or quiet runs, and never
#       drops a regression whose push failed (kept pending, re-sent next run).
# Everything runs in a throwaway fixture HOME with a stub curl — never touches production data
# or the real network.
set -uo pipefail
OQ="${OVN_QUEUE_DIR:-$HOME/overnight-queue}"
D="$OQ/digest_notify.sh"
CRON="$OQ/scripts/ovn_failure_triage_cron.sh"
TRIAGE="$OQ/scripts/ovn_failure_triage.py"
for f in "$D" "$CRON" "$TRIAGE"; do
  [ -f "$f" ] || { echo "  SKIP: $f not found on this host"; exit 0; }
done

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
iso_ago(){ python3 -c "import sys,datetime as d;print((d.datetime.now(d.timezone.utc)-d.timedelta(hours=float(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%SZ'))" "$1"; }

# stub curl: records title/priority/body of every send; fails while $tmp/curl_fail exists
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<CURLEOF
#!/usr/bin/env bash
[ -f "$tmp/curl_fail" ] && exit 1
title=""; prio=""; body=""; prev=""
for a in "\$@"; do
  case "\$prev" in
    -H) case "\$a" in Title:*) title="\${a#Title: }";; Priority:*) prio="\${a#Priority: }";; esac;;
    -d) body="\$a";;
  esac
  prev="\$a"
done
printf 'TITLE=%s|PRIO=%s|BODY=%s\n@@END@@\n' "\$title" "\$prio" "\$body" >> "$tmp/sends.log"
exit 0
CURLEOF
chmod +x "$tmp/bin/curl"

# ---------------------------------------------------------------- (A) digest section
mkA="$tmp/A"; mkdir -p "$mkA/state" "$mkA/scripts" "$mkA/repos/demo" "$mkA/backlog"
cp "$D" "$mkA/digest_notify.sh"
for f in ovn_landed_detail.py ovn_tier_stats.py ovn_stats.py ovn_planning_stats.py ovn_feature_groups.py ovn_outcome_buckets.py ovn_failure_triage.py; do
  [ -f "$OQ/scripts/$f" ] && cp "$OQ/scripts/$f" "$mkA/scripts/$f"
done
echo faketopic > "$mkA/state/ntfy_topic"; echo '{}' > "$mkA/tasks.json"
now="$(date +%s)"
printf '%s\tdemo\tpass\t{py.other.T2.tested}\tapp/a.py\n' "$now" > "$mkA/state/task_stats.log"
printf '%s\t1\t0\t0\t0\t0\tPASS=demo\tFAIL=\tREV=\tERR=\n' "$now" > "$mkA/state/digest_buffer.log"
: > "$mkA/repos/demo/OVERNIGHT_PROGRESS.md"; : > "$mkA/repos/demo/OVERNIGHT_DONE.md"; : > "$mkA/backlog/demo.md"

run_digest(){
  rm -f "$tmp/sends.log"
  printf '%s\t1\t0\t0\t0\t0\tPASS=demo\tFAIL=\tREV=\tERR=\n' "$(date +%s)" > "$mkA/state/digest_buffer.log"
  ( cd "$mkA" && PATH="$tmp/bin:$PATH" HOME="$mkA" bash "$mkA/digest_notify.sh" >/dev/null 2>&1 )
}

# A1: no registry at all -> no section
run_digest
ok "A1 no triage registry -> digest has no new-pattern section" "! grep -q 'seen for the first time' '$tmp/sends.log'"

# A2: 2 patterns first seen in-window + 1 old + 1 fixed-and-regressed-in-window
python3 - "$mkA/state/failure_clusters.json" "$(iso_ago 1)" "$(iso_ago 200)" <<'EOF'
import json,sys
p,recent,old=sys.argv[1:4]
reg={
 "demo::python:ValueError: bad thing": {"first_seen":recent,"last_seen":recent,"count":3,"status":"new","sample_item_hashes":[]},
 "demo::gradle:build exploded":        {"first_seen":recent,"last_seen":recent,"count":1,"status":"new","sample_item_hashes":[]},
 "demo::js:old chestnut":              {"first_seen":old,"last_seen":recent,"count":9,"status":"new","sample_item_hashes":[]},
 "demo::aider:hunk-failed-to-apply":   {"first_seen":old,"last_seen":recent,"count":4,"status":"fixed","fix_commit":"abc1234",
                                         "regression_events":[{"ts":recent,"item_hash":"h"}],"sample_item_hashes":[]},
}
json.dump(reg,open(p,"w"))
EOF
run_digest
ok "A2 digest lists in-window new patterns under a plain-language header" "grep -q '2 failure pattern(s) seen for the first time' '$tmp/sends.log'"
ok "A2 digest names the repo and error of a new pattern" "grep -q 'demo: python:ValueError: bad thing' '$tmp/sends.log'"
ok "A2 digest does NOT list an old pattern that merely recurred" "! grep -q 'old chestnut' '$tmp/sends.log'"
ok "A2 digest does NOT re-report a regression (hourly runner owns that)" "! grep -q 'hunk-failed-to-apply' '$tmp/sends.log'"
ok "A2 the digest is still ONE routine push (not a second regression push)" "[ \$(grep -c '@@END@@' '$tmp/sends.log') -eq 1 ]"

# A3: 8 new patterns -> capped at 5 bullets + "…and 3 more"
python3 - "$mkA/state/failure_clusters.json" "$(iso_ago 1)" <<'EOF'
import json,sys
p,recent=sys.argv[1:3]
reg={"demo::python:Err%d: msg" % i: {"first_seen":recent,"last_seen":recent,"count":1,"status":"new","sample_item_hashes":[]} for i in range(8)}
json.dump(reg,open(p,"w"))
EOF
run_digest
ok "A3 header reports the true total (8)" "grep -q '8 failure pattern(s) seen for the first time' '$tmp/sends.log'"
ok "A3 shows at most 5 bullets" "[ \$(grep -c '  • demo:' '$tmp/sends.log') -eq 5 ]"
ok "A3 says how many more were omitted" "grep -q '…and 3 more' '$tmp/sends.log'"

# ---------------------------------------------------------------- (B) hourly runner
mkB="$tmp/B"; mkdir -p "$mkB/overnight-queue/state" "$mkB/overnight-queue/scripts" "$mkB/overnight-queue/logs"
for f in ovn_failure_triage.py ovn_outcome_buckets.py lib_lock.sh; do cp "$OQ/scripts/$f" "$mkB/overnight-queue/scripts/$f"; done
cp "$CRON" "$mkB/overnight-queue/scripts/ovn_failure_triage_cron.sh"
echo faketopic > "$mkB/overnight-queue/state/ntfy_topic"
BST="$mkB/overnight-queue/state"
SIG="no-log:fail_reason=build-red;status=reverted(build-break)"
add_outcome(){ python3 - "$BST/outcomes.jsonl" "$1" "$2" <<'EOF'
import json,sys,datetime as d
p,status,reason=sys.argv[1:4]
rec={"ts":d.datetime.now(d.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),"repo":"demo","id":"ongoing-demo","type":"aider_fix",
     "tier":"2","category":"test","class":"reverted","severity":"bad","attempt":1,"fail_reason":reason,"status":status,
     "tokens_sent":1,"tokens_recv":1,"duration_s":1,"item_hash":"h1","feat_tag":""}
open(p,"a").write(json.dumps(rec)+"\n")
EOF
}
run_cron(){ rm -f "$tmp/sends.log"; ( PATH="$tmp/bin:$PATH" HOME="$mkB" bash "$mkB/overnight-queue/scripts/ovn_failure_triage_cron.sh" >/dev/null 2>&1 ); echo $?; }

# B1: a brand-new pattern only -> no push at all
add_outcome "reverted(build-break)" "build-red"
rc="$(run_cron)"
ok "B1 runner exits 0" "[ '$rc' = 0 ]"
ok "B1 a merely-new pattern sends NO push (it goes in the digest instead)" "[ ! -f '$tmp/sends.log' ]"
ok "B1 the pattern is registered as new" "python3 -c \"import json;r=json.load(open('$BST/failure_clusters.json'));assert r['demo::$SIG']['status']=='new'\""

# B2: mark it fixed, then it recurs -> exactly one high-priority push
python3 - "$BST/failure_clusters.json" "demo::$SIG" <<'EOF'
import json,sys
p,k=sys.argv[1:3]; r=json.load(open(p)); r[k]["status"]="fixed"; r[k]["fix_commit"]="abc1234"; r[k]["generator_addressed"]="yes"
json.dump(r,open(p,"w"))
EOF
add_outcome "reverted(build-break)" "build-red"
rc="$(run_cron)"
ok "B2 exactly one push for the regression" "[ \$(grep -c '@@END@@' '$tmp/sends.log') -eq 1 ]"
ok "B2 the push is high priority" "grep -q 'PRIO=high' '$tmp/sends.log'"
ok "B2 the title is plain language" "grep -q 'TITLE=A bug we already fixed is back' '$tmp/sends.log'"
ok "B2 the body names the repo and the fixing commit" "grep -q 'demo:' '$tmp/sends.log' && grep -q 'abc1234' '$tmp/sends.log'"
ok "B2 the body tells the reader how to record the re-fix" "grep -q -- '--ack' '$tmp/sends.log'"

# B3: quiet run (no new outcomes) -> no push, no duplicate of the earlier regression
rc="$(run_cron)"
ok "B3 a quiet run sends nothing (each regression event is reported exactly once)" "[ ! -f '$tmp/sends.log' ]"

# B4: regression whose push FAILS is kept pending, then delivered next run
add_outcome "reverted(build-break)" "build-red"
touch "$tmp/curl_fail"
rc="$(run_cron)"
ok "B4 runner still exits 0 when the push fails" "[ '$rc' = 0 ]"
ok "B4 the un-sent regression is kept pending, not dropped" "[ -s '$BST/failure_triage_pending_push.txt' ]"
rm -f "$tmp/curl_fail"
rc="$(run_cron)"
ok "B4 next run delivers the pending regression" "grep -q 'PRIO=high' '$tmp/sends.log'"
ok "B4 and clears the pending file" "[ ! -e '$BST/failure_triage_pending_push.txt' ]"

echo "Failure-triage notifications: $P passed, $F failed"
[ "$F" -eq 0 ]
