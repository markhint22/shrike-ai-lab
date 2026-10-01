#!/usr/bin/env bash
# qa_run_shadow.sh: always exits 0, runs gates, survives a crashing/slow gate, resolves its dir before cd (cron-style relative path).
Q="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
mkdir -p "$T/ovn/qa" "$T/ovn/state" "$T/ovn/logs"
cp "$Q/qa/qa_run_shadow.sh" "$Q/qa/qa_timeout.py" "$T/ovn/qa/"
cat > "$T/ovn/qa/gate_good.py" <<'PY'
import sys,json
print(json.dumps({"verdict":"PASS","gate":"good"}))
PY
cat > "$T/ovn/qa/gate_crash.py" <<'PY'
import sys
sys.exit(7)
PY
cat > "$T/ovn/qa/gate_slow.py" <<'PY'
import time
time.sleep(30)
PY
env -i HOME="$HOME" PATH=/usr/bin:/bin NTFY_SERVER=http://127.0.0.1:8099 QA_GATE_TIMEOUT=2 bash -c "cd '$T/ovn' && bash qa/qa_run_shadow.sh demo abc123 def456"
ok "exits 0 even with a crashing and a timing-out gate" "$([ $? = 0 ] && echo 1 || echo 0)"
L="$T/ovn/logs/qa_shadow.log"
ok "good gate logged PASS" "$(grep -q 'good: PASS' "$L" && echo 1 || echo 0)"
ok "crashing gate logged as NO-OUTPUT, not PASS" "$(grep -q 'crash: NO-OUTPUT rc=0\|crash: NO-OUTPUT' "$L" && echo 1 || echo 0)"
ok "slow gate was cut off by the timeout" "$(grep -qE 'slow: NO-OUTPUT .* [0-9]s' "$L" && [ "$(grep 'slow:' "$L" | grep -oE '[0-9]+s$' | tr -d s)" -le 6 ] && echo 1 || echo 0)"
ok "all three gates ran" "$(grep -q 'done (3 gate' "$L" && echo 1 || echo 0)"
( cd "$Q/qa" && env -i HOME="$HOME" PATH=/usr/bin:/bin OVN_DIR="$T/ovn" QA_GATE_TIMEOUT=2 bash ./qa_run_shadow.sh ) >/dev/null 2>&1
ok "missing arguments: prints usage, exits 0" "$([ $? = 0 ] && echo 1 || echo 0)"
OVN_QA_SHADOW=off bash "$T/ovn/qa/qa_run_shadow.sh" demo a b; ok "kill switch OVN_QA_SHADOW=off exits 0 without running" "$(tail -1 "$L" | grep -q 'disabled' && echo 1 || echo 0)"
# lock contention (works with either flock or the mkdir fallback): hold the lock the same way the script does, second run must skip
if PATH=/usr/bin:/bin command -v flock >/dev/null 2>&1; then
  ( exec 8>"$T/ovn/state/qa_shadow.lock"; flock 8; env -i HOME="$HOME" PATH=/usr/bin:/bin QA_LOCK_WAIT=1 bash "$T/ovn/qa/qa_run_shadow.sh" demo x y )
else
  mkdir "$T/ovn/state/qa_shadow.lock.d"; env -i HOME="$HOME" PATH=/usr/bin:/bin QA_LOCK_WAIT=1 bash "$T/ovn/qa/qa_run_shadow.sh" demo x y; rmdir "$T/ovn/state/qa_shadow.lock.d"
fi
ok "lock contention skips (does not fail or hang)" "$(tail -1 "$L" | grep -q 'skipping' && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
