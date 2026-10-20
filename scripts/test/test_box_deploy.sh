#!/usr/bin/env bash
# test_box_deploy.sh - ops/box_deploy.sh (package L4, 2026-10-18): the crash-safe, self-verifying on-box deploy.
# Real script, fake live tree under a private temp dir (marker .deploy_test_tree + OVN_DEPLOY_TEST_HOOKS=1); no real queue, systemd or network is touched.
# Cases D1..D19 cover: the happy path, exec-bit-only drift (the 2026-10-18 mode-644 cron scripts), mid-copy failure, verify mismatch, syntax errors (sh + py), failed smoke
# (no cycle / new Permission denied), kill -9 mid-copy and before the copy (watchdog), SIGTERM, an UNVERIFIED rollback (rc 3, queue kept paused), busy abort, a pre-existing
# operator pause, orphan recovery after the watchdog is gone too, prune + its rollback, tarball input, refusals. Every failure case proves the live tree is BYTE-IDENTICAL
# (sha256 + exec bit, no leftover temp file) to its pre-deploy state and the queue is not left paused.
# Then MUTANTS of box_deploy.sh (each breaks one safety property); the named case must FAIL on the mutant.
# usage: test_box_deploy.sh   env: L4_OPS_DIR (ops dir to test), L4_CASES="D2 D8" (run only these), OVN_ROOT
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/lib_deploy_fixture.sh"
export OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
b(){ if "$@" >/dev/null 2>&1; then echo 1; else echo 0; fi; }
want(){ [ -z "${L4_CASES:-}" ] && return 0; case " $L4_CASES " in *" $1 "*) return 0;; esac; return 1; }
BG=""
bgkill(){ local p; for p in $BG; do kill -9 "$p" 2>/dev/null; done; BG=""; }
trap 'bgkill; df_cleanup' EXIT
OPS="$DF_OPS"
[ -f "$OPS/box_deploy.sh" ] && [ -f "$OPS/deploy_manifest.py" ] || { echo "  FAIL: box_deploy.sh / deploy_manifest.py missing in $OPS"; exit 1; }

mk(){ # fresh live tree + a stage that changes a.sh (+x), b.py, adds sub/new.sh, leaves queue.sh alone
  df_cleanup; df_init 0 || exit 1; df_env
  Q="$DF_Q"; QT="$DF_QT"; ST="$DF_T/stage"; mkdir -p "$Q/sub" "$ST/sub"
  printf '#!/usr/bin/env bash\necho a-old\n' > "$Q/a.sh"; chmod +x "$Q/a.sh"
  printf 'print("b-old")\n' > "$Q/b.py"; printf '#!/usr/bin/env bash\necho q\n' > "$Q/queue.sh"; chmod +x "$Q/queue.sh"
  printf '#!/usr/bin/env bash\necho c\n' > "$Q/sub/c.sh"; chmod +x "$Q/sub/c.sh"
  printf '#!/usr/bin/env bash\necho r\n' > "$Q/run_overnight.sh"; chmod +x "$Q/run_overnight.sh"
  printf 'sub: runtime\n' > "$Q/backlog.keep"; echo oldsha > "$Q/state/deployed_sha"
  printf '#!/usr/bin/env bash\necho a-NEW\n' > "$ST/a.sh"; chmod +x "$ST/a.sh"
  printf 'print("b-NEW")\n' > "$ST/b.py"; cp -p "$Q/queue.sh" "$ST/queue.sh"; cp -p "$Q/sub/c.sh" "$ST/sub/c.sh"; cp -p "$Q/run_overnight.sh" "$ST/run_overnight.sh"
  printf '#!/usr/bin/env bash\necho new\n' > "$ST/sub/new.sh"; chmod +x "$ST/sub/new.sh"
  BEFORE="$(df_snap)"
}
dep(){ bash "$OPS/box_deploy.sh" "$@" > "$DF_T/out" 2>&1; RC=$?; }
wd(){ ls -d "$QT"/deploy.* 2>/dev/null | head -1; }
same_tree(){ [ "$(df_snap)" = "$BEFORE" ] && echo 1 || echo 0; }
paused(){ [ -e "$Q/state/PAUSED" ] && echo 1 || echo 0; }
sha_of(){ python3 -I "$OPS/deploy_manifest.py" hashes "$Q" <<< "$1" | cut -d' ' -f1; }
lastrow(){ tail -1 "$Q/state/deploy_ledger.jsonl" 2>/dev/null | python3 -I -c "import json,sys;print(json.loads(sys.stdin.read() or '{}').get('$1',''))" 2>/dev/null; }
wait_for(){ local n=0; while [ $n -lt "$2" ]; do eval "$1" && return 0; sleep 0.5; n=$((n+1)); done; return 1; }

if want D1; then mk
  dep --stage "$ST" --sha abc1234 --prev-sha oldsha
  ok "D1 happy path: rc 0" "$([ $RC = 0 ] && echo 1 || echo 0)"
  ok "D1 files replaced byte-for-byte (a.sh, b.py) and the new file added with its exec bit" "$([ "$(cat "$Q/a.sh")" = "$(cat "$ST/a.sh")" ] && [ "$(cat "$Q/b.py")" = 'print("b-NEW")' ] && [ -x "$Q/sub/new.sh" ] && echo 1 || echo 0)"
  ok "D1 untouched file keeps its inode content; runtime file never touched" "$([ "$(cat "$Q/backlog.keep")" = 'sub: runtime' ] && echo 1 || echo 0)"
  ok "D1 state/deployed_sha = the deployed sha, deployed_sha_prev = the previous one" "$([ "$(cat "$Q/state/deployed_sha")" = abc1234 ] && [ "$(cat "$Q/state/deployed_sha_prev")" = oldsha ] && echo 1 || echo 0)"
  ok "D1 ledger row outcome=ok with sha + counts" "$([ "$(lastrow outcome)" = ok ] && [ "$(lastrow sha)" = abc1234 ] && [ "$(lastrow changed)" = 3 ] && echo 1 || echo 0)"
  ok "D1 queue not left paused" "$([ "$(paused)" = 0 ] && echo 1 || echo 0)"
  ok "D1 backup tar holds the OLD a.sh and b.py" "$([ "$(tar -xOf "$(wd)/backup.tar" a.sh | grep -c a-old)" = 1 ] && echo 1 || echo 0)"
  ok "D1 no leftover .new temp file" "$([ -z "$(find "$Q" -name '*.new.*')" ] && echo 1 || echo 0)"
fi
if want D2; then mk
  OVN_DEPLOY_FAIL_COPY_AT=2 dep --stage "$ST" --sha abc1234
  ok "D2 mid-copy failure: rc 1 (failed, rolled back)" "$([ $RC = 1 ] && echo 1 || echo 0)"
  ok "D2 tree BYTE-IDENTICAL to the pre-deploy state (sha256+exec bit, no temp leftovers, new-only file gone)" "$(same_tree)"
  ok "D2 rollback_status says RESTORED and the deploy log says VERIFIED" "$([ "$(cat "$(wd)/rollback_status")" = RESTORED ] && grep -q 'ROLLBACK VERIFIED' "$(wd)/deploy.log" && echo 1 || echo 0)"
  ok "D2 deployed_sha untouched, ledger outcome rolled_back, alerts.log has the WARN" "$([ "$(cat "$Q/state/deployed_sha")" = oldsha ] && [ "$(lastrow outcome)" = rolled_back ] && grep -q 'ROLLED BACK' "$Q/state/alerts.log" && echo 1 || echo 0)"
  ok "D2 queue not left paused" "$([ "$(paused)" = 0 ] && echo 1 || echo 0)"
fi
if want D3; then mk
  OVN_DEPLOY_FAIL_VERIFY=1 dep --stage "$ST" --sha abc1234
  ok "D3 verify mismatch (torn write): rc 1 + tree byte-identical to before" "$([ $RC = 1 ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
  ok "D3 the log names the verify mismatch" "$(grep -q 'verify mismatch' "$(wd)/deploy.log" && echo 1 || echo 0)"
fi
if want D4; then mk
  printf '#!/usr/bin/env bash\nif then fi (\n' > "$ST/sub/new.sh"
  dep --stage "$ST" --sha abc1234
  ok "D4 a .sh with a syntax error in the new tree: rc 1, rolled back, tree byte-identical" "$([ $RC = 1 ] && [ "$(same_tree)" = 1 ] && grep -q 'SYNTAX FAIL' "$(wd)/syntax.out" && echo 1 || echo 0)"
  mk; printf 'def broken(:\n' > "$ST/b.py"
  dep --stage "$ST" --sha abc1234
  ok "D4b a .py with a syntax error: rc 1, rolled back, tree byte-identical" "$([ $RC = 1 ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
fi
if want D5; then mk
  OVN_DEPLOY_CYCLE_PROBE_CMD=false OVN_DEPLOY_SMOKE_WAIT=2 dep --stage "$ST" --sha abc1234
  ok "D5 smoke: no queue cycle starts -> rc 1, rolled back AFTER the resume, tree byte-identical, queue running" "$([ $RC = 1 ] && [ "$(same_tree)" = 1 ] && [ "$(paused)" = 0 ] && grep -q 'smoke failed: no queue cycle' "$(wd)/deploy.log" && echo 1 || echo 0)"
  mk
  OVN_DEPLOY_CYCLE_PROBE_CMD="echo '[x] bash: /home/u/overnight-queue/gpu_autoswap.sh: Permission denied' >> '$Q/logs/cron.log'; true" dep --stage "$ST" --sha abc1234
  ok "D5b smoke: a NEW 'Permission denied' in a log after the resume -> rolled back, tree identical" "$([ $RC = 1 ] && [ "$(same_tree)" = 1 ] && grep -q "Permission denied" "$(wd)/deploy.log" && echo 1 || echo 0)"
  mk; echo "old Permission denied from yesterday" > "$Q/logs/old.log"
  dep --stage "$ST" --sha abc1234
  ok "D5c smoke: a PRE-EXISTING 'Permission denied' line is not blamed on the deploy" "$([ $RC = 0 ] && echo 1 || echo 0)"
fi
if want D6; then mk
  OVN_DEPLOY_HOLD_AT=2 OVN_DEPLOY_HOLD_S=60 bash "$OPS/box_deploy.sh" --stage "$ST" --sha abc1234 > "$DF_T/out" 2>&1 &
  DP=$!; BG="$BG $DP"; disown "$DP" 2>/dev/null
  wait_for '[ -e "$(wd)/hold_reached" ]' 40; hr=$?
  SPID="$(pgrep -P $DP sleep 2>/dev/null | head -1)"
  ok "D6 precondition: the deploy is mid-copy (hold reached, queue paused, a.sh already replaced)" "$([ $hr = 0 ] && [ "$(paused)" = 1 ] && grep -q a-NEW "$Q/a.sh" && echo 1 || echo 0)"
  kill -9 "$DP" 2>/dev/null; [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
  wait_for '[ -e "$(wd)/finished" ]' 40; fr=$?
  ok "D6 kill -9 mid-copy: the WATCHDOG rolled back (finished latch written)" "$([ $fr = 0 ] && echo 1 || echo 0)"
  ok "D6 tree BYTE-IDENTICAL to the pre-deploy state" "$(same_tree)"
  ok "D6 queue resumed (PAUSED removed) and the deploy lock released" "$([ "$(paused)" = 0 ] && [ ! -d "$Q/state/box_deploy.lock.d" ] && echo 1 || echo 0)"
  ok "D6 rollback verified in the log; deployed_sha untouched" "$(grep -q 'ROLLBACK VERIFIED' "$(wd)/deploy.log" && [ "$(cat "$Q/state/deployed_sha")" = oldsha ] && echo 1 || echo 0)"
fi
if want D7; then mk
  # (2026-10-18 L4 repair: the drain is now UNPAUSED, so the work that keeps the queue busy while we wait for idle AFTER the pause is started by the on-pause hook)
  OVN_DEPLOY_BUSY_PATTERN='sleep 31\.4159' OVN_DEPLOY_ON_PAUSE_CMD="nohup bash -c 'sleep 31.4159' >/dev/null 2>&1 &" OVN_DEPLOY_POLL_S=1 bash "$OPS/box_deploy.sh" --stage "$ST" --sha abc1234 --max-wait-min 5 > "$DF_T/out" 2>&1 &
  DP=$!; BG="$BG $DP"; disown "$DP" 2>/dev/null
  wait_for '[ "$(paused)" = 1 ]' 30; pr=$?
  kill -9 "$DP" 2>/dev/null
  wait_for '[ "$(paused)" = 0 ]' 40; rr=$?
  ok "D7 kill -9 while waiting for idle: the queue WAS paused, the watchdog un-pauses it, nothing was touched" "$([ $pr = 0 ] && [ $rr = 0 ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
  pkill -9 -f 'sleep 31\.4159' 2>/dev/null
fi
if want D8; then mk
  OVN_DEPLOY_HOLD_AT=2 OVN_DEPLOY_HOLD_S=60 bash "$OPS/box_deploy.sh" --stage "$ST" --sha abc1234 > "$DF_T/out" 2>&1 &
  DP=$!; BG="$BG $DP"; disown "$DP" 2>/dev/null
  wait_for '[ -e "$(wd)/hold_reached" ]' 40
  kill -TERM "$DP" 2>/dev/null; sleep 0.3; pkill -P "$DP" sleep 2>/dev/null   # bash runs a trap only after its foreground child (the hook sleep) ends
  wait_for '[ -e "$(wd)/finished" ]' 40
  ok "D8 SIGTERM mid-copy: the TRAP (not the watchdog) rolls back (verified), tree byte-identical, queue resumed" "$([ "$(same_tree)" = 1 ] && [ "$(paused)" = 0 ] && grep -q 'ROLLBACK VERIFIED' "$(wd)/deploy.log" && grep -q 'ROLLBACK START: interrupted in phase copying' "$(wd)/deploy.log" && echo 1 || echo 0)"
  pkill -P "$DP" sleep 2>/dev/null
fi
if want D9; then mk
  OVN_DEPLOY_FAIL_VERIFY=1 OVN_DEPLOY_FAIL_RESTORE=1 dep --stage "$ST" --sha abc1234
  ok "D9 UNVERIFIED rollback: rc 3, rollback_status ROLLBACK_FAILED (never RESTORED)" "$([ $RC = 3 ] && grep -q '^ROLLBACK_FAILED' "$(wd)/rollback_status" && echo 1 || echo 0)"
  ok "D9 CRIT alert in alerts.log, ledger rollback_failed, queue deliberately kept PAUSED" "$(grep -q 'CRIT | box_deploy' "$Q/state/alerts.log" && [ "$(lastrow outcome)" = rollback_failed ] && [ "$(paused)" = 1 ] && echo 1 || echo 0)"
  ok "D9 deployed_sha not advanced" "$([ "$(cat "$Q/state/deployed_sha")" = oldsha ] && echo 1 || echo 0)"
fi
if want D10; then mk
  OVN_DEPLOY_BUSY_PATTERN='sleep 31\.4159' bash -c 'sleep 31.4159' & SL=$!; BG="$BG $SL"; disown "$SL" 2>/dev/null; sleep 0.3
  OVN_DEPLOY_BUSY_PATTERN='sleep 31\.4159' dep --stage "$ST" --sha abc1234 --max-wait-min 0
  ok "D10 the queue never goes idle: rc 4, NOTHING touched, our pause removed, ledger aborted_busy" "$([ $RC = 4 ] && [ "$(same_tree)" = 1 ] && [ "$(paused)" = 0 ] && [ "$(lastrow outcome)" = aborted_busy ] && echo 1 || echo 0)"
  ok "D10 the busy abort never paused the queue at all (zero downtime): the log says it was NOT paused and has no 'paused' line" "$(grep -q 'it was NOT paused' "$(wd)/deploy.log" && ! grep -qE '^[0-9:]+ paused' "$(wd)/deploy.log" && echo 1 || echo 0)"
  kill -9 "$SL" 2>/dev/null
fi
if want D19; then mk
  OVN_DEPLOY_BUSY_PATTERN='sleep 31\.4159' bash -c 'sleep 31.4159' & SL=$!; BG="$BG $SL"; disown "$SL" 2>/dev/null; sleep 0.3
  OVN_DEPLOY_BUSY_PATTERN='sleep 31\.4159' OVN_DEPLOY_POLL_S=1 bash "$OPS/box_deploy.sh" --stage "$ST" --sha abc1234 --max-wait-min 5 > "$DF_T/out" 2>&1 &
  DP=$!; BG="$BG $DP"; disown "$DP" 2>/dev/null
  everp=0; for _i in 1 2 3 4 5 6 7 8; do sleep 0.5; [ "$(paused)" = 1 ] && everp=1; done
  alive=0; kill -0 "$DP" 2>/dev/null && alive=1
  ok "D19 a BUSY box is drained WITHOUT pausing: for 4 s of waiting the queue was never paused and the deploy is still waiting" "$([ $everp = 0 ] && [ $alive = 1 ] && echo 1 || echo 0)"
  kill -9 "$DP" 2>/dev/null; wait_for '[ ! -d "$Q/state/box_deploy.lock.d" ]' 40; lr=$?
  ok "D19 kill -9 during the unpaused drain: the watchdog releases the lock, nothing touched, never paused" "$([ $lr = 0 ] && [ "$(same_tree)" = 1 ] && [ "$(paused)" = 0 ] && echo 1 || echo 0)"
  kill -9 "$SL" 2>/dev/null
fi
if want D20; then mk
  t0=$SECONDS
  OVN_DEPLOY_BUSY_PATTERN='sleep 31\.4159' OVN_DEPLOY_ON_PAUSE_CMD="nohup bash -c 'sleep 31.4159' >/dev/null 2>&1 &" OVN_DEPLOY_POLL_S=1 OVN_DEPLOY_PAUSE_MAX_MIN=0 dep --stage "$ST" --sha abc1234 --max-wait-min 1
  el=$((SECONDS - t0))
  ok "D20 work that starts AFTER the pause: the pause is BOUNDED (PAUSE_MAX_MIN=0 here, not the 1-min drain bound): rc 4 within a few seconds, resumed, nothing touched, ledger aborted_busy" "$([ $RC = 4 ] && [ "$el" -le 20 ] && [ "$(paused)" = 0 ] && [ "$(same_tree)" = 1 ] && [ "$(lastrow outcome)" = aborted_busy ] && grep -q 'after the pause' "$(wd)/deploy.log" && echo 1 || echo 0)"
  pkill -9 -f 'sleep 31\.4159' 2>/dev/null
fi
if want D21; then mk
  OVN_DEPLOY_CYCLE_PROBE_CMD="echo '[2026-10-18] /home/u/overnight-queue/repos/gitlark: git@github.com: Permission denied (publickey).' >> '$Q/logs/gitlark_control_consumer.log'; echo 'tar: /var/lib/x: Cannot open: Permission denied' >> '$Q/logs/foreign.log'; echo 'git@github.com: Permission denied (publickey).' >> '$Q/logs/plain.log'; echo 'tar: /var/lib/x: Cannot open: Permission denied' >> '$Q/logs/other.log'; true" dep --stage "$ST" --sha abc1234
  ok "D21 unrelated 'Permission denied' lines written by other cron jobs during the window (ssh/git publickey, a foreign path) do NOT roll back a good deploy" "$([ $RC = 0 ] && [ "$(cat "$Q/state/deployed_sha")" = abc1234 ] && echo 1 || echo 0)"
  mk
  OVN_DEPLOY_CYCLE_PROBE_CMD="echo 'bash: ./a.sh: Permission denied' >> '$Q/logs/other.log'; true" dep --stage "$ST" --sha abc1234
  ok "D21b a 'Permission denied' that names a file THIS deploy touched (a.sh) still rolls the deploy back, tree identical" "$([ $RC = 1 ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
fi
if want D11; then mk
  touch "$Q/state/PAUSED"
  dep --stage "$ST" --sha abc1234
  ok "D11 an OPERATOR's pause is never removed by the deploy" "$([ $RC = 0 ] && [ "$(paused)" = 1 ] && echo 1 || echo 0)"
  mk; touch "$Q/state/PAUSED"; OVN_DEPLOY_FAIL_VERIFY=1 dep --stage "$ST" --sha abc1234
  ok "D11b ... nor after a failed deploy + rollback" "$([ $RC = 1 ] && [ "$(paused)" = 1 ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
fi
if want D12; then mk
  # a dead deploy that left the tree half-changed AND whose watchdog is gone too: the NEXT deploy must recover it first
  OVN_DEPLOY_HOLD_AT=2 OVN_DEPLOY_HOLD_S=60 bash "$OPS/box_deploy.sh" --stage "$ST" --sha abc1234 > "$DF_T/out" 2>&1 &
  DP=$!; BG="$BG $DP"; disown "$DP" 2>/dev/null
  wait_for '[ -e "$(wd)/hold_reached" ]' 40
  OLDW="$(wd)"; SPID="$(pgrep -P $DP sleep 2>/dev/null | head -1)"
  pkill -9 -f "box_deploy.sh --watchdog $DP" 2>/dev/null; kill -9 "$DP" 2>/dev/null; [ -n "$SPID" ] && kill "$SPID" 2>/dev/null
  sleep 1
  half="$([ "$(same_tree)" = 0 ] && [ "$(paused)" = 1 ] && echo 1 || echo 0)"
  ok "D12 precondition: tree half-deployed, queue paused, watchdog and deploy both dead" "$half"
  mk2="$ST"; dep --stage "$mk2" --sha abc1234
  ok "D12 the next deploy recovered the orphan (old work dir rolled back + finished) and then deployed cleanly" "$([ $RC = 0 ] && [ -e "$OLDW/finished" ] && grep -q 'ROLLBACK VERIFIED' "$OLDW/deploy.log" && grep -q a-NEW "$Q/a.sh" && [ "$(paused)" = 0 ] && echo 1 || echo 0)"
fi
if want D13; then mk
  printf '#!/usr/bin/env bash\necho old-gone\n' > "$Q/sub/gone.sh"; chmod +x "$Q/sub/gone.sh"; BEFORE="$(df_snap)"
  printf 'P sub/gone.sh\nS run_overnight.sh\n' > "$DF_T/prune.txt"
  dep --stage "$ST" --sha abc1234 --prune-file "$DF_T/prune.txt"
  ok "D13 prune: the upstream-deleted file is removed (P), a box-modified one marked S is left alone" "$([ $RC = 0 ] && [ ! -e "$Q/sub/gone.sh" ] && [ -e "$Q/run_overnight.sh" ] && echo 1 || echo 0)"
  mk; printf '#!/usr/bin/env bash\necho old-gone\n' > "$Q/sub/gone.sh"; chmod +x "$Q/sub/gone.sh"; BEFORE="$(df_snap)"
  printf 'P sub/gone.sh\n' > "$DF_T/prune.txt"
  OVN_DEPLOY_FAIL_VERIFY=1 dep --stage "$ST" --sha abc1234 --prune-file "$DF_T/prune.txt"
  ok "D13b a pruned file is RESTORED by the rollback (tree byte-identical, gone.sh back with its exec bit)" "$([ $RC = 1 ] && [ "$(same_tree)" = 1 ] && [ -x "$Q/sub/gone.sh" ] && echo 1 || echo 0)"
fi
if want D14; then mk
  chmod -x "$Q/queue.sh"; BEFORE="$(df_snap)"       # identical bytes, mode 644: exactly the 2026-10-18 gpu_autoswap.sh case
  dep --stage "$ST" --sha abc1234
  ok "D14 exec-bit-only drift (same bytes, mode 644 on the box, 755 in the stage) is FIXED by the deploy" "$([ $RC = 0 ] && [ -x "$Q/queue.sh" ] && echo 1 || echo 0)"
  mk; chmod -x "$Q/queue.sh"; BEFORE="$(df_snap)"
  OVN_DEPLOY_FAIL_VERIFY=1 dep --stage "$ST" --sha abc1234
  ok "D14b ... and a rollback restores the OLD mode (644) too" "$([ $RC = 1 ] && [ ! -x "$Q/queue.sh" ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
fi
if want D15; then mk
  ( cd "$ST" && tar -cf "$DF_T/dep.tar" . 2>/dev/null )
  dep --tar "$DF_T/dep.tar" --sha abc1234
  ok "D15 --tar: a tarball stage deploys the same way" "$([ $RC = 0 ] && grep -q a-NEW "$Q/a.sh" && echo 1 || echo 0)"
fi
if want D16; then mk
  ( OVN_DEPLOY_TEST_HOOKS= OVN_QUEUE_DIR="$Q" bash "$OPS/box_deploy.sh" --stage "$ST" > "$DF_T/out" 2>&1 ); r1=$?
  ok "D16 without the test hooks OVN_QUEUE_DIR is refused (rc 2), nothing touched" "$([ $r1 = 2 ] && [ "$(same_tree)" = 1 ] && grep -q 'test-only' "$DF_T/out" && echo 1 || echo 0)"
  printf 'P ../../etc/passwd\n' > "$DF_T/prune.txt"; dep --stage "$ST" --prune-file "$DF_T/prune.txt"
  ok "D16b a path escaping the tree in the prune list is refused (rc 2), nothing touched" "$([ $RC = 2 ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
  dep --stage "$DF_T/nonexistent" ; ok "D16c a missing stage dir is refused (rc 2)" "$([ $RC = 2 ] && echo 1 || echo 0)"
  mkdir "$Q/state/box_deploy.lock.d"; echo $$ > "$Q/state/box_deploy.lock.d/pid"
  dep --stage "$ST" --sha abc1234
  ok "D16d a live deploy lock: rc 4 and nothing touched" "$([ $RC = 4 ] && [ "$(same_tree)" = 1 ] && echo 1 || echo 0)"
fi
if want D17; then mk
  dep --stage "$ST"
  ok "D17 without --sha the deploy works but state/deployed_sha is NOT touched" "$([ $RC = 0 ] && [ "$(cat "$Q/state/deployed_sha")" = oldsha ] && echo 1 || echo 0)"
  mk; dep --stage "$ST" --sha abc1234; cp -p "$Q/a.sh" "$DF_T/a.after"; before2="$(df_snap)"
  dep --stage "$ST" --sha abc1234
  ok "D17b re-deploying the same tree changes nothing (0 changed) and still succeeds" "$([ $RC = 0 ] && [ "$(df_snap)" = "$before2" ] && grep -q '0 changed' "$DF_T/out" && echo 1 || echo 0)"
fi

if want D18; then mk
  chmod 000 "$Q/b.py"; BEFORE="$(df_snap 2>/dev/null)"
  dep --stage "$ST" --sha abc1234
  chmod 644 "$Q/b.py"
  ok "D18 a touched file that cannot be read (no backup/pre-hash possible): rc 4, NOTHING changed, queue not left paused" "$([ $RC = 4 ] && grep -q a-old "$Q/a.sh" && [ "$(paused)" = 0 ] && grep -q 'backup failed' "$(wd)/deploy.log" && echo 1 || echo 0)"
fi

# ---------------------------------------------------------------- mutants of box_deploy.sh: each must be CAUGHT by the named case
if [ -z "${L4_NO_MUTANTS:-}" ] && [ -z "${L4_CASES:-}" ]; then
  MT="$(safe_mktemp_dir dfm)" || exit 1
  trap 'bgkill; df_cleanup; safe_rm_rf "$MT"' EXIT
  mutant(){ # label old new cases [file=box_deploy.sh]
    local lab="$1" old="$2" new="$3" cases="$4" mf="${5:-box_deploy.sh}" d="$MT/m$RANDOM"
    mkdir -p "$d"; cp -p "$OPS"/*.sh "$OPS"/*.py "$d"/
    OLD="$old" NEW="$new" python3 - "$OPS/$mf" "$d/$mf" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"][:70])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
    [ $? -eq 0 ] || { ok "mutant '$lab' could not be applied" 0; return; }
    L4_OPS_DIR="$d" L4_CASES="$cases" L4_NO_MUTANTS=1 bash "$HERE/test_box_deploy.sh" > "$MT/mut.out" 2>&1
    if [ "$(grep -c '^  FAIL ' "$MT/mut.out")" -gt 0 ] && [ "$(grep -c Traceback "$MT/mut.out")" -eq 0 ]; then ok "mutant caught: $lab" 1; else ok "mutant NOT caught: $lab" 0; sed -n 1,12p "$MT/mut.out"; fi
  }
  mutant "rollback reports RESTORED without verifying the files" 'if [ "$trc" -eq 0 ] && [ "$bad" -eq 0 ]; then' 'if true; then' "D9"
  mutant "rollback does not remove files that did not exist before" 'while IFS= read -r f; do [ -n "$f" ] && rm -f "$Q/$f"; done < "$W/new_only.list"' ': ' "D3"
  mutant "no watchdog (kill -9 leaves the queue paused / tree half-deployed)" 'nohup bash "$W/box_deploy.sh" --watchdog "$$" "$W" >> "$W/watchdog.log" 2>&1 < /dev/null &' ':' "D6 D7"
  mutant "the EXIT/TERM trap does not roll back (only the watchdog would)" 'if phase_needs_rollback "$ph"; then
      if do_rollback "interrupted in phase' 'if false; then
      if do_rollback "interrupted in phase' "D8"
  mutant "a pause that was not ours is removed" 'if [ -e "$W/we_paused" ]; then rm -f "$PAUSED"' 'if true; then rm -f "$PAUSED"' "D11"
  mutant "verify step skipped (torn write goes live)" 'vbad=$(diff "$W/stage.hashes" "$W/post.hashes" | grep -c '"'"'^>'"'"')' 'vbad=0' "D3"
  mutant "syntax errors are not fatal" '[ "$src_" -eq 0 ] || fail_and_rollback' '[ 0 -eq 0 ] || fail_and_rollback' "D4"
  mutant "smoke result ignored" '[ -z "$why" ] || fail_and_rollback "smoke failed: $why"' ':' "D5"
  mutant "deploys onto a busy queue (post-pause wait ignored)" 'if ! wait_idle "$IDLEW"; then
  if [ "${OVN_DEPLOY_PROCEED_BUSY:-0}" != 1 ]; then' 'if ! wait_idle "$IDLEW"; then
  if false; then' "D20"
  mutant "deploys onto a busy queue (drain ignored)" '    if [ "${OVN_DEPLOY_PROCEED_BUSY:-0}" != 1 ]; then
      say "ABORT: the queue did not go idle within' '    if false; then
      say "ABORT: the queue did not go idle within' "D10"
  mutant "pause BEFORE the drain again (busy box = paused fleet)" 'if [ "$WAS_PAUSED" = 0 ]; then
  # drain WITHOUT pausing' 'if [ "$WAS_PAUSED" = 0 ]; then touch "$PAUSED"; : > "$W/we_paused"
  # drain WITHOUT pausing' "D19"
  mutant "the pause is unbounded (waits the full drain window while paused)" '[ "$((PMAX*60))" -lt "$IDLEW" ] && IDLEW="$((PMAX*60))"' ':' "D20"
  mutant "ssh/git auth noise counts as a deploy failure" "grep -v -i -E 'publickey|password|keyboard-interactive|Host key verification|Could not read from remote'" "cat" "D21"
  mutant "any Permission denied line counts (no attribution to the deploy)" '| { grep -c -F -e "$Q/" -e overnight-queue ${names:+-f "$names"} 2>/dev/null || true; }' '| { grep -c . || true; }' "D21"
  mutant "no backup status check (an unreadable file is not noticed)" 'if [ "$brc" -ne 0 ] || [ "$nb" -ne "$ne" ]; then' 'if false; then' "D18"
  mutant "orphan recovery skipped" '  if [ -n "$ow" ]; then bash "$W/box_deploy.sh" --recover "${opid:-0}" "$ow" || { say "orphan recovery FAILED"; exit 3; }; fi' ':' "D12"
  mutant "exec-bit-only differences are not copied (the 2026-10-18 mode-644 cron scripts)" ' or b[k][1] != s[k][1])' ')' "D14" deploy_manifest.py
fi
echo "  box_deploy: $P passed, $F failed"
[ "$F" -eq 0 ]
