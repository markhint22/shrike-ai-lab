#!/usr/bin/env bash
# test_box_autodeploy.sh - ops/box_autodeploy.sh (package L4, 2026-10-18): gated auto-deploy + repo/box drift report, SHADOW by default.
# The real scripts run against a FAKE GitHub (a bare repo reached through the same read-only deploy-clone fetch) and a fake live tree (marker .deploy_test_tree). The live tree under
# test is a real git-archive of the fake branch (it contains the real ops scripts, lint_unsafe_rm.py and lib_safe_tmp.sh), so the lint gate runs the REAL linter.
# Cases A1..A24: shadow never touches the tree; every gate (ff, suite PASS, interval, box_clean, lint/syntax, paused, no_repeat, fetch failure, baseline unknown) blocks and is
# REPORTED with its reason; enforce deploys exactly the newest suite-PASSed fast-forward; drift is reported (modified/mode/missing/box_only/age); prune; adopt; manual rollback; modes.
# Then MUTANTS of box_autodeploy.sh / deploy_manifest.py (each removes one gate); the named case must FAIL on the mutant.
# usage: test_box_autodeploy.sh   env: L4_OPS_DIR, L4_CASES="A4 A7" (only these), L4_NO_MUTANTS=1, OVN_ROOT
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
. "$HERE/lib_deploy_fixture.sh"
export OVN_ROOT="${OVN_ROOT:-$(cd "$HERE/../.." && pwd)}"
P=0; F=0
ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
want(){ [ -z "${L4_CASES:-}" ] && return 0; case " $L4_CASES " in *" $1 "*) return 0;; esac; return 1; }
trap 'df_cleanup' EXIT
OPS="$DF_OPS"
[ -f "$OPS/box_autodeploy.sh" ] && [ -f "$OPS/box_deploy.sh" ] && [ -f "$OPS/deploy_manifest.py" ] || { echo "  FAIL: ops scripts missing in $OPS"; exit 1; }

mk(){ df_cleanup; df_init 1 || { echo "  FAIL fixture"; exit 1; }; df_env; df_install "$DF_SHA1"; Q="$DF_Q"; QT="$DF_QT"; R="$Q/state/autodeploy_report.json"; NOWR="$(date +%s)"; }
ad(){ bash "$Q/ops/box_autodeploy.sh" "$@" > "$DF_T/out" 2>&1; RC=$?; [ -n "${L4_DEBUG:-}" ] && sed 's/^/    | /' "$DF_T/out"; return 0; }
rj(){ df_json "$R" "$1"; }
paused(){ [ -e "$Q/state/PAUSED" ] && echo 1 || echo 0; }
snap0(){ SNAP="$(df_snap)"; }
same(){ [ "$(df_snap)" = "$SNAP" ] && echo 1 || echo 0; }
has_reason(){ python3 -I -c "
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if any(sys.argv[2] in r for r in d['reasons']) else 1)" "$R" "$1"; }
nlines(){ [ -f "$1" ] && grep -c . "$1" || echo 0; }

if want A1; then mk
  df_commit "c2" run_overnight.sh "#!/usr/bin/env bash
echo v2" exec VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"; snap0
  OVN_AUTODEPLOY_SUITE_CMD="echo started >> '$DF_T/suite_marker'" ad run
  ok "A1 default mode is shadow: report says would_deploy for the PASSed fast-forward commit" "$([ "$(rj mode)" = shadow ] && [ "$(rj decision)" = would_deploy ] && [ "$(rj candidate)" = "$C2" ] && echo 1 || echo 0)"
  ok "A1 shadow NEVER touches the tree: byte-identical, deployed_sha unchanged, no pause, no ledger, no work dir, no suite started" "$([ "$(same)" = 1 ] && [ "$(cat "$Q/state/deployed_sha")" = "$DF_SHA1" ] && [ "$(paused)" = 0 ] && [ ! -e "$Q/state/deploy_ledger.jsonl" ] && [ -z "$(ls -d "$QT"/deploy.* 2>/dev/null)" ] && [ ! -e "$DF_T/suite_marker" ] && echo 1 || echo 0)"
  ok "A1 report: ahead=1, tip, every gate ok (ff suite lint interval box_clean not_paused no_repeat)" "$([ "$(rj ahead)" = 1 ] && [ "$(rj tip)" = "$C2" ] && [ "$(rj gates.ff)" = ok ] && [ "$(rj gates.suite)" = ok ] && [ "$(rj gates.lint)" = ok ] && [ "$(rj gates.interval)" = ok ] && [ "$(rj gates.box_clean)" = ok ] && [ "$(rj gates.not_paused)" = ok ] && [ "$(rj gates.no_repeat)" = ok ] && echo 1 || echo 0)"
  ok "A1 the one-line status names the sha and the mode ('would deploy', '[shadow]')" "$(grep -q "would deploy ${C2:0:7}" "$Q/state/autodeploy_status.txt" && grep -q '\[shadow\]' "$Q/state/autodeploy_status.txt" && echo 1 || echo 0)"
  ok "A1 the deploy clone is read-only (push URL disabled) and run exits 0" "$([ $RC = 0 ] && [ "$(df_git -C "$DF_CL" config remote.origin.pushurl)" = DISABLED-read-only-deploy-clone ] && echo 1 || echo 0)"
fi
if want A2; then mk
  df_commit "c2" VERSION v2 >/dev/null; snap0
  OVN_AUTODEPLOY_SUITE_CMD="echo started >> '$DF_T/suite_marker'" ad run
  ok "A2 no suite PASS for any undeployed commit: blocked, reason says so, tree untouched" "$([ "$(rj decision)" = blocked ] && has_reason 'no suite PASS' && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  ok "A2 shadow reports it WOULD start the suite but does not start it" "$([ "$(rj suite_would_start)" = true ] && [ "$(rj suite_started)" = false ] && [ ! -e "$DF_T/suite_marker" ] && echo 1 || echo 0)"
fi
if want A3; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD="echo \$SHA >> '$DF_T/suite_marker'" ad run
  sleep 1
  ok "A3 enforce + no PASS: the candidate suite is started for the TIP (and nothing is deployed)" "$([ "$(rj suite_started)" = true ] && [ "$(head -1 "$DF_T/suite_marker" 2>/dev/null)" = "$C2" ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD="echo \$SHA >> '$DF_T/suite_marker'" ad run
  sleep 1
  ok "A3 the next hourly pass does NOT start a second suite for the same tip (12 h dedupe)" "$([ "$(nlines "$DF_T/suite_marker")" = 1 ] && echo 1 || echo 0)"
  echo "sha=$C2
rc=3" > "$Q/state/suite_fail_$C2"; rm -f "$Q/state/autodeploy_suite_trigger"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD="echo \$SHA >> '$DF_T/suite_marker'" ad run
  ok "A3 a FAILED suite on the tip is reported loudly and is not re-run in a loop" "$([ "$(nlines "$DF_T/suite_marker")" = 1 ] && has_reason 'suite FAILED' && echo 1 || echo 0)"
fi
if want A3c; then mk
  df_commit "c2" VERSION v2 >/dev/null; snap0
  bash -c 'sleep 27.1828' & SL=$!; disown "$SL" 2>/dev/null; sleep 0.3
  OVN_AUTODEPLOY_SUITE_PATTERN='sleep 27\.1828' OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD="echo x >> '$DF_T/suite_marker'" ad run; sleep 1
  ok "A3c a suite already running (pgrep) is not duplicated; the report says so" "$([ ! -e "$DF_T/suite_marker" ] && [ "$(rj suite_action)" = 'a suite is running' ] && echo 1 || echo 0)"
  kill -9 "$SL" 2>/dev/null
fi
if want A4; then mk
  df_commit "c2" run_overnight.sh "#!/usr/bin/env bash
echo v2" exec VERSION v2 queue.sh "#!/usr/bin/env bash
echo q2" exec >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  df_commit "c3 (tip, no suite PASS yet)" VERSION v3 >/dev/null; C3="$DF_SHA"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A4 enforce deploys the NEWEST suite-PASSed commit (c2), not the unproven tip (c3): exit 0, decision deployed" "$([ $RC = 0 ] && [ "$(rj decision)" = deployed ] && [ "$(cat "$Q/state/deployed_sha")" = "$C2" ] && [ "$(cat "$Q/VERSION")" = v2 ] && echo 1 || echo 0)"
  ok "A4 files changed on the box, ledger outcome ok, queue not left paused, deployed_sha_prev = the old baseline" "$(grep -q 'echo v2' "$Q/run_overnight.sh" && grep -q '"outcome": "ok"' "$Q/state/deploy_ledger.jsonl" && [ "$(paused)" = 0 ] && [ "$(cat "$Q/state/deployed_sha_prev")" = "$DF_SHA1" ] && echo 1 || echo 0)"
  ok "A4 after the deploy the drift against deployed_sha is clean and 1 commit (the tip) is still ahead" "$([ "$(rj drift.clean)" = true ] && [ "$(rj ahead)" = 1 ] && echo 1 || echo 0)"
  ok "A4 the exec bit of the deployed scripts is right (queue.sh 755)" "$([ -x "$Q/queue.sh" ] && [ -x "$Q/run_overnight.sh" ] && echo 1 || echo 0)"
fi
if want A5; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  ad run; df_install "$C2"                                  # the clone now knows c2; the box claims c2
  df_git -C "$DF_WK" reset -q --hard "$DF_SHA1"; df_commit "c3 rewritten history" VERSION v3x >/dev/null; C3="$DF_SHA"; df_pass "$C3"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A5 a branch rewrite (deployed_sha is not an ancestor of the PASSed candidate) is blocked by the ff gate" "$([ "$(rj decision)" = blocked ] && has_reason 'ff:' && [ "$(rj gates.ff)" != ok ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
fi
if want A6; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  df_commit "c3" VERSION v3 >/dev/null; C3="$DF_SHA"; df_pass "$C3"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_NOW=$((NOWR + 3600)) OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A6 a second deploy 1 h after the first is blocked by the interval gate (default 6 h), tree untouched" "$([ "$(rj decision)" = blocked ] && has_reason 'interval:' && [ "$(same)" = 1 ] && [ "$(cat "$Q/state/deployed_sha")" = "$C2" ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_NOW=$((NOWR + 7*3600)) OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A6 7 h later it deploys" "$([ "$(rj decision)" = deployed ] && [ "$(cat "$Q/state/deployed_sha")" = "$C3" ] && echo 1 || echo 0)"
fi
if want A7; then mk
  df_commit "c2" run_overnight.sh "#!/usr/bin/env bash
echo v2" exec >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  printf '#!/usr/bin/env bash\necho HOTPATCHED-ON-BOX\n' > "$Q/run_overnight.sh"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A7 a box-only hot patch blocks the deploy (it would be overwritten): blocked, reason box_clean, tree untouched" "$([ "$(rj decision)" = blocked ] && has_reason 'box_clean:' && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  ok "A7 the drift report names the file as modified (count 1)" "$([ "$(rj drift.modified_n)" = 1 ] && [ "$(rj drift.modified)" = "['run_overnight.sh']" ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_ALLOW_BOX_EDITS=1 OVN_AUTODEPLOY_SUITE_CMD=true ad run
  BK="$(ls -d "$QT"/deploy.* | head -1)/backup.tar"
  ok "A7 OVN_AUTODEPLOY_ALLOW_BOX_EDITS=1 deploys anyway, and the backup tar keeps the hot patch" "$([ "$(rj decision)" = deployed ] && [ "$(tar -xOf "$BK" run_overnight.sh | grep -c HOTPATCHED)" = 1 ] && echo 1 || echo 0)"
fi
if want A8; then mk
  df_commit "c2 unsafe rm" scripts/bad.sh '#!/usr/bin/env bash
X="$1"
rm -rf "$X"/data' exec >/dev/null; C2="$DF_SHA"; df_pass "$C2"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A8 a candidate that fails the unsafe-rm lint is blocked (lint gate), tree untouched" "$([ "$(rj decision)" = blocked ] && has_reason 'lint:' && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  mk; df_commit "c2 syntax" scripts/broken.sh '#!/usr/bin/env bash
if then fi (' exec >/dev/null; C2="$DF_SHA"; df_pass "$C2"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A8b a candidate with a shell syntax error is blocked (lint gate: syntax)" "$([ "$(rj decision)" = blocked ] && has_reason 'syntax' && [ "$(same)" = 1 ] && echo 1 || echo 0)"
fi
if want A9; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  rm -f "$Q/state/deployed_sha"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A9 no state/deployed_sha: 'baseline unknown', nothing deployed even in enforce, drift reported against the tip" "$([ "$(rj decision)" = blocked ] && [ "$(rj baseline_known)" = false ] && has_reason 'baseline unknown' && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  ad adopt "$C2"
  ok "A9b adopt refuses a sha the box does not match (rc 2, lists the files), deployed_sha not written" "$([ $RC = 2 ] && grep -q 'REFUSED' "$DF_T/out" && grep -q 'VERSION' "$DF_T/out" && [ ! -e "$Q/state/deployed_sha" ] && echo 1 || echo 0)"
  ad adopt "$DF_SHA1"
  ok "A9c adopt of the sha the box really runs records the baseline (rc 0)" "$([ $RC = 0 ] && [ "$(cat "$Q/state/deployed_sha")" = "$DF_SHA1" ] && grep -q '"outcome": "adopted"' "$Q/state/deploy_ledger.jsonl" && echo 1 || echo 0)"
  rm -f "$Q/state/deployed_sha"; ad adopt "$C2" --force
  ok "A9d adopt --force records a mismatching baseline on purpose" "$([ $RC = 0 ] && [ "$(cat "$Q/state/deployed_sha")" = "$C2" ] && echo 1 || echo 0)"
fi
if want A10; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"; touch "$Q/state/PAUSED"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A10 a queue paused by an operator blocks the deploy (not_paused) and stays paused" "$([ "$(rj decision)" = blocked ] && has_reason 'not_paused:' && [ "$(same)" = 1 ] && [ "$(paused)" = 1 ] && echo 1 || echo 0)"
fi
if want A11; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"; snap0
  OVN_AUTODEPLOY=off ad run
  ok "A11 OVN_AUTODEPLOY=off: exits 0, writes NO report, touches nothing" "$([ $RC = 0 ] && [ ! -e "$R" ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY=enforec ad run
  ok "A11b a typo in the mode is treated as SHADOW (never enforce) and reported as a config error" "$([ "$(rj mode)" = shadow ] && [ -n "$(rj mode_error)" ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY_BRANCH=main ad run
  ok "A11c a branch other than claude/feature|develop is refused (rc 2)" "$([ $RC = 2 ] && echo 1 || echo 0)"
fi
if want A12; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"; ad run          # the clone is populated
  snap0
  OVN_DEPLOY_REMOTE="$DF_T/does-not-exist.git" OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A12 GitHub unreachable: rc 0 (cron quiet), report fetch_ok=false with the reason, NOTHING deployed even though a PASSed candidate is cached" "$([ $RC = 0 ] && [ "$(rj fetch_ok)" = false ] && has_reason 'fetch' && [ "$(rj decision)" = blocked ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
fi
if want A13; then mk
  rm -f "$Q/queue.sh"; chmod -x "$Q/run_overnight.sh"; echo v1-box-edit > "$Q/VERSION"; echo junk > "$Q/box_only_file.txt"
  OLDT=$((NOWR - 30*3600 - 120)); GIT_COMMITTER_DATE="@$OLDT +0000" df_commit "c2 old" scripts/lib_lock.sh "#!/usr/bin/env bash
echo v2" exec >/dev/null
  OVN_AUTODEPLOY_NOW=$NOWR ad run
  ok "A13 drift: 1 modified (VERSION), 1 mode-only (run_overnight.sh 644), 1 missing (queue.sh), box-only counted (informational)" "$([ "$(rj drift.modified_n)" = 1 ] && [ "$(rj drift.mode_n)" = 1 ] && [ "$(rj drift.missing_n)" = 1 ] && [ "$(rj drift.box_only_n)" -ge 1 ] && [ "$(rj drift.clean)" = false ] && echo 1 || echo 0)"
  ok "A13 age of the oldest undeployed commit is reported (30 h) and appears in the hourly line" "$([ "$(rj oldest_age_h)" = 30 ] && grep -q 'oldest undeployed 30h' "$Q/state/autodeploy_status.txt" && grep -q '1 modified, 1 mode, 1 missing' "$Q/state/autodeploy_status.txt" && echo 1 || echo 0)"
fi
if want A14; then mk
  df_commit "add gone + keep" scripts/gone.sh "#!/usr/bin/env bash
echo gone" exec scripts/kept.sh "#!/usr/bin/env bash
echo kept" exec >/dev/null; CG="$DF_SHA"; df_install "$CG"
  df_commit "delete gone and kept" scripts/gone.sh -DELETE- scripts/kept.sh -DELETE- >/dev/null; C3="$DF_SHA"; df_pass "$C3"
  printf '#!/usr/bin/env bash\necho box-modified-kept\n' > "$Q/scripts/kept.sh"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_ALLOW_BOX_EDITS=1 OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A14 a file deleted upstream and unmodified on the box is pruned; a box-modified one is left alone (reported as S)" "$([ "$(rj decision)" = deployed ] && [ ! -e "$Q/scripts/gone.sh" ] && [ -e "$Q/scripts/kept.sh" ] && echo 1 || echo 0)"
fi
if want A15; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"; snap0
  OVN_DEPLOY_FAIL_VERIFY=1 OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A15 a failing deploy (verify mismatch) is rolled back VERIFIED: exit 1, decision rolled_back, tree byte-identical, queue running" "$([ $RC = 1 ] && [ "$(rj decision)" = rolled_back ] && [ "$(same)" = 1 ] && [ "$(paused)" = 0 ] && [ "$(cat "$Q/state/deployed_sha")" = "$DF_SHA1" ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_NOW=$((NOWR + 10*3600)) OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A15 the SAME sha is not retried automatically (no_repeat: needs a human), still blocked 10 h later" "$([ "$(rj decision)" = blocked ] && has_reason 'no_repeat:' && [ "$(same)" = 1 ] && echo 1 || echo 0)"
fi
if want A16; then mk
  mkdir "$Q/state/autodeploy.lock.d"; echo $$ > "$Q/state/autodeploy.lock.d/pid"; snap0
  OVN_AUTODEPLOY=enforce ad run
  ok "A16 a second pass while one is running exits 0 without writing a report" "$([ $RC = 0 ] && [ ! -e "$R" ] && grep -q 'another pass' "$DF_T/out" && echo 1 || echo 0)"
  rm -f "$Q/state/autodeploy.lock.d/pid"; rmdir "$Q/state/autodeploy.lock.d"
  echo 999999 > /dev/null; mkdir "$Q/state/autodeploy.lock.d"; echo 2147483 > "$Q/state/autodeploy.lock.d/pid"
  ad run
  ok "A16b a STALE lock (dead pid) is taken over" "$([ -f "$R" ] && echo 1 || echo 0)"
fi
if want A17; then mk
  ad run
  ok "A17 nothing ahead: up_to_date, no suite started even in enforce" "$([ "$(rj decision)" = up_to_date ] && [ "$(rj ahead)" = 0 ] && grep -q 'up to date' "$Q/state/autodeploy_status.txt" && echo 1 || echo 0)"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD="echo x >> '$DF_T/suite_marker'" ad run; sleep 1
  ok "A17b enforce + up to date starts nothing" "$([ ! -e "$DF_T/suite_marker" ] && echo 1 || echo 0)"
fi
if want A18; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"
  printf 'sha=%s\nrc=1\nts=1\n' "$C2" > "$Q/state/suite_pass_$C2"; snap0
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A18 a suite_pass file with rc=1 is NOT a pass" "$([ "$(rj decision)" = blocked ] && [ "$(rj candidate)" = "" ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
  printf 'sha=%s\nrc=0\nts=1\n' "deadbeefdeadbeef" > "$Q/state/suite_pass_$C2"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A18b a suite_pass file naming a DIFFERENT sha is NOT a pass for this commit (no copying a pass file)" "$([ "$(rj decision)" = blocked ] && [ "$(rj candidate)" = "" ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
fi
if want A19; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_commit "c3" VERSION v3 >/dev/null; C3="$DF_SHA"
  ad run; df_install "$C3"; snap0                      # the clone knows c2 and c3; the box runs c3
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad deploy-sha "$C2"
  ok "A19 deploy-sha <older sha> (manual rollback of a good deploy) in enforce deploys it and records it" "$([ $RC = 0 ] && [ "$(cat "$Q/state/deployed_sha")" = "$C2" ] && [ "$(cat "$Q/VERSION")" = v2 ] && [ "$(cat "$Q/state/deployed_sha_prev")" = "$C3" ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY=shadow ad deploy-sha "$C3"
  ok "A19b deploy-sha is refused in shadow mode (rc 2) and changes nothing" "$([ $RC = 2 ] && [ "$(cat "$Q/VERSION")" = v2 ] && echo 1 || echo 0)"
fi
if want A20; then mk
  ( OVN_DEPLOY_TEST_HOOKS= bash "$Q/ops/box_autodeploy.sh" run > "$DF_T/out" 2>&1 ); r=$?
  ok "A20 without the test hooks the OVN_QUEUE_DIR override is refused (rc 2, 'test-only')" "$([ $r = 2 ] && grep -q 'test-only' "$DF_T/out" && echo 1 || echo 0)"
fi
if want A21; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A21 the deploy ledger gains one row per deploy with sha, prev_sha, counts and the work dir" "$(grep -q "\"sha\": \"$C2\"" "$Q/state/deploy_ledger.jsonl" && grep -q "\"prev_sha\": \"$DF_SHA1\"" "$Q/state/deploy_ledger.jsonl" && grep -q work_dir "$Q/state/deploy_ledger.jsonl" && echo 1 || echo 0)"
fi

if want A22; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  df_commit "c3" VERSION v3 >/dev/null; C3="$DF_SHA"; df_pass "$C3"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  df_commit "c4 (a newer commit with a suite PASS)" VERSION v4 >/dev/null; C4="$DF_SHA"; df_pass "$C4"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad deploy-sha "$DF_SHA1"
  ok "A22 deploy-sha <c1> while a newer suite-PASSed commit (c4) exists deploys c1's tree: VERSION v1 on the box (was: c4's tree v4 with deployed_sha=c1), rc 0" "$([ $RC = 0 ] && [ "$(cat "$Q/VERSION")" = v1 ] && echo 1 || echo 0)"
  ok "A22 state/deployed_sha names c1, deployed_sha_prev names c3 (the documented 'deploy-sha \$(cat deployed_sha_prev)' undo is a real rollback)" "$([ "$(cat "$Q/state/deployed_sha")" = "$DF_SHA1" ] && [ "$(cat "$Q/state/deployed_sha_prev")" = "$C3" ] && echo 1 || echo 0)"
  ok "A22 the report's drift against deployed_sha is clean (it must be computed against what was really deployed, so a mismatch cannot hide)" "$([ "$(rj drift.clean)" = true ] && echo 1 || echo 0)"
  ad run
  ok "A22 the next pass sees the box at c1 with no modified file (a wrong tree would show up as modified)" "$([ "$(rj drift.modified_n)" = 0 ] && [ "$(rj drift.missing_n)" = 0 ] && echo 1 || echo 0)"
fi
if want A23; then mk
  df_commit "c2" VERSION v2 >/dev/null; ad run
  ok "A23 precondition: shadow wrote a report and a status file" "$([ -f "$R" ] && [ -f "$Q/state/autodeploy_status.txt" ] && echo 1 || echo 0)"
  snap0; OVN_AUTODEPLOY=off ad run
  ok "A23 OVN_AUTODEPLOY=off REMOVES the old report + status (the hourly update must not call a deliberately-off job a stale high-priority one), tree untouched, rc 0" "$([ $RC = 0 ] && [ ! -e "$R" ] && [ ! -e "$Q/state/autodeploy_status.txt" ] && [ "$(same)" = 1 ] && echo 1 || echo 0)"
fi
if want A24; then mk
  ad run
  df_git -C "$DF_CL" config gc.auto 0; df_git -C "$DF_CL" config fetch.unpackLimit 1000000     # keep the fetched objects loose
  MANY=(); for i in $(seq 1 3000); do MANY+=("many/f$i.txt" "content $i"); done
  df_commit "c2 many files" "${MANY[@]}" >/dev/null
  OVN_AUTODEPLOY_GC_AUTO=0 ad run                  # fetches c2 as ~3000 loose objects; gc disabled this pass
  ok "A24 precondition: the clone has thousands of loose objects" "$([ "$(df_git -C "$DF_CL" count-objects -v | sed -n 's/^count: //p')" -gt 1000 ] && echo 1 || echo 0)"
  ok "A24 with gc.auto=0 (the old hard-coded config) nothing is ever packed" "$([ "$(df_git -C "$DF_CL" config gc.auto)" = 0 ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY_GC_AUTO=1 ad run
  ok "A24 an existing clone created with gc.auto=0 is migrated to a real threshold" "$([ "$(df_git -C "$DF_CL" config gc.auto)" = 1 ] && echo 1 || echo 0)"
  ok "A24 the hourly fetch's auto-gc now fires on the deploy clone: loose objects are packed (count 0), the clone still works" "$([ "$(df_git -C "$DF_CL" count-objects -v | sed -n 's/^count: //p')" = 0 ] && [ -n "$(rj tip)" ] && echo 1 || echo 0)"
  mk; ad run
  ok "A24 a fresh clone gets the default threshold 2000 (not 0)" "$([ "$(df_git -C "$DF_CL" config gc.auto)" = 2000 ] && echo 1 || echo 0)"
fi
if want A25; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"; df_pass "$C2"
  echo box-edit > "$Q/VERSION"; rm -f "$Q/state/deployed_sha"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A25 baseline unknown: the blocked reason names the bootstrap commands (deploy-sha / adopt)" "$([ "$(rj decision)" = blocked ] && has_reason 'deploy-sha' && has_reason 'adopt' && echo 1 || echo 0)"
  ad adopt "$DF_SHA1"; ad adopt "$DF_SHA1" --force
  ok "A25 a forced adopt of a box that differs records the baseline" "$([ "$(cat "$Q/state/deployed_sha")" = "$DF_SHA1" ] && echo 1 || echo 0)"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A25 ...then box_clean blocks the auto deploy and its reason names the exact realign command (deploy-sha <12-char deployed sha>)" "$([ "$(rj decision)" = blocked ] && has_reason 'box_clean:' && has_reason "deploy-sha ${DF_SHA1:0:12}" && echo 1 || echo 0)"
  df_commit "c3" VERSION v3 >/dev/null; C3="$DF_SHA"; df_pass "$C3"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad deploy-sha "$C3"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A25 the bootstrap path ends clean: deploy-sha <tip> deploys exactly that tree, the next pass is up_to_date with clean drift" "$([ "$(cat "$Q/VERSION")" = v3 ] && [ "$(rj decision)" = up_to_date ] && [ "$(rj drift.clean)" = true ] && echo 1 || echo 0)"
fi
if want A26; then mk
  df_commit "c2" VERSION v2 >/dev/null; C2="$DF_SHA"
  printf 'sha=%s\nrc=3\nts=1\nattempts=1\n' "$C2" > "$Q/state/suite_fail_$C2"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD="echo \$SHA >> '$DF_T/suite_marker'" ad run; sleep 1
  ok "A26 ONE failed suite attempt (attempts=1 < 2) on the tip is retried: the candidate suite is started again, the note says 'will retry'" "$([ "$(head -1 "$DF_T/suite_marker" 2>/dev/null)" = "$C2" ] && has_reason 'will retry' && echo 1 || echo 0)"
  rm -f "$DF_T/suite_marker" "$Q/state/autodeploy_suite_trigger"; printf 'sha=%s\nrc=3\nts=1\nattempts=2\n' "$C2" > "$Q/state/suite_fail_$C2"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD="echo \$SHA >> '$DF_T/suite_marker'" ad run; sleep 1
  ok "A26 after OVN_AUTODEPLOY_SUITE_RETRIES (2) attempts the tip is given up on loudly and not re-run" "$([ ! -e "$DF_T/suite_marker" ] && has_reason 'suite FAILED' && echo 1 || echo 0)"
  rm -f "$Q/state/suite_fail_$C2"; printf 'sha=%s\nrc=78\nts=1\nreason=rsync failed\n' "$C2" > "$Q/state/autodeploy_suite_error"
  OVN_AUTODEPLOY=enforce OVN_AUTODEPLOY_SUITE_CMD=true ad run
  ok "A26b a recorded setup error of the candidate suite (rsync/clone/tar) is named in the report instead of a bare 'already started'" "$(has_reason 'could not start' && has_reason 'rsync failed' && echo 1 || echo 0)"
fi

# ---------------------------------------------------------------- mutants
if [ -z "${L4_NO_MUTANTS:-}" ] && [ -z "${L4_CASES:-}" ]; then
  MT="$(safe_mktemp_dir dfm)" || exit 1
  trap 'df_cleanup; safe_rm_rf "$MT"' EXIT
  mutant(){ # label old new cases [file]
    local lab="$1" old="$2" new="$3" cases="$4" mf="${5:-box_autodeploy.sh}" d="$MT/m$RANDOM"
    mkdir -p "$d"; cp -p "$OPS"/*.sh "$OPS"/*.py "$d"/
    OLD="$old" NEW="$new" python3 - "$OPS/$mf" "$d/$mf" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"][:70])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
    [ $? -eq 0 ] || { ok "mutant '$lab' could not be applied" 0; return; }
    L4_OPS_DIR="$d" L4_CASES="$cases" L4_NO_MUTANTS=1 bash "$HERE/test_box_autodeploy.sh" > "$MT/mut.out" 2>&1
    if [ "$(grep -c '^  FAIL ' "$MT/mut.out")" -gt 0 ] && [ "$(grep -c Traceback "$MT/mut.out")" -eq 0 ]; then ok "mutant caught: $lab" 1; else ok "mutant NOT caught: $lab" 0; sed -n 1,10p "$MT/mut.out"; fi
  }
  mutant "default mode is enforce instead of shadow" 'MODE="${OVN_AUTODEPLOY:-shadow}"' 'MODE="${OVN_AUTODEPLOY:-enforce}"' "A1"
  mutant "shadow mode deploys too (mode check dropped)" 'if [ "$MODE" = enforce ] && { [ "$DECISION" = would_deploy ] || [ "$DECISION" = manual ]; }; then' 'if { [ "$DECISION" = would_deploy ] || [ "$DECISION" = manual ]; }; then' "A1"
  mutant "ff gate removed" 'if git_ merge-base --is-ancestor "$DEPLOYED" "$CAND" 2>/dev/null; then G_FF=ok;' 'if true; then G_FF=ok;' "A5"
  mutant "any suite_pass file accepted" '  [ -f "$f" ] && grep -qx "sha=$1" "$f" && grep -qx "rc=0" "$f"' '  [ -f "$f" ]' "A18"
  mutant "suite pass must not name the sha (copied pass file accepted)" 'grep -qx "sha=$1" "$f" && ' '' "A18"
  mutant "interval gate removed" 'if [ "$LAST_OK" -gt 0 ] && [ $((NOW - LAST_OK)) -lt $((MIN_H * 3600)) ]; then' 'if false; then' "A6"
  mutant "box_clean gate removed" 'if [ "$MODN" -gt 0 ] && [ "${OVN_AUTODEPLOY_ALLOW_BOX_EDITS:-0}" != 1 ]; then' 'if false; then' "A7"
  mutant "lint/syntax gate not enforced" '[ "$G_LINT" = ok ] || block "lint: $G_LINT"' ':' "A8"
  mutant "paused-queue gate removed" 'if [ -e "$PAUSED" ]; then G_PAUSE="queue is paused (operator)"; block "not_paused: $G_PAUSE"; else G_PAUSE=ok; fi' 'G_PAUSE=ok' "A10"
  mutant "fetch failure not reported/blocked" '[ "$FETCH_OK" = 1 ] || block "$FETCH_ERR"' ':' "A12"
  mutant "rolled-back sha retried" 'if [ "$rb" -gt 0 ]; then G_REP=' 'if false; then G_REP=' "A15"
  mutant "suite dedupe removed (a suite per hour per tip)" 'elif [ "$tsha" = "$TIP" ] && [ $((NOW - ${tts:-0})) -lt 43200 ]; then' 'elif false; then' "A3"
  mutant "a running suite is not detected (suites pile up)" '  [ -n "$pat" ] && pgrep -u "$(id -u)" -f "$pat" >/dev/null 2>&1' '  false' "A3c"
  mutant "baseline-unknown adoption accepts a mismatching box silently" 'if [ "$clean" != True ] && [ "$force" != "--force" ]; then' 'if false; then' "A9"
  mutant "prune deletes box-modified files too" '("P " if b[k][0] == o[k][0] else "S ")' '("P " if True else "S ")' "A14" deploy_manifest.py
  mutant "drift ignores exec-bit-only differences" 'mode = sorted(k for k in r if k in b and b[k][0] == r[k][0] and b[k][1] != r[k][1])' 'mode = []' "A13" deploy_manifest.py
  mutant "deploy-sha reuses an auto-candidate's extracted tree" '  safe_rm_rf "$W/new"
  extract "$CAND" "$W/new"' '  [ -d "$W/new" ] || extract "$CAND" "$W/new"' "A22"
  mutant "off mode leaves the old report behind" 'rm -f "$_oq/state/autodeploy_report.json" "$_oq/state/autodeploy_status.txt"' ':' "A23"
  mutant "deploy clone gc threshold left at 0" 'git_ config gc.auto "${OVN_AUTODEPLOY_GC_AUTO:-2000}" || return 1' 'git_ config gc.auto 0 || return 1' "A24"
  mutant "baseline-unknown reason lacks the bootstrap commands" '(bootstrap: OVN_AUTODEPLOY=enforce box_autodeploy.sh deploy-sha <sha>, or box_autodeploy.sh adopt <sha> [--force])' '(run adopt)' "A25"
  mutant "box_clean reason lacks the realign command" 'to realign: OVN_AUTODEPLOY=enforce box_autodeploy.sh deploy-sha ${DEPLOYED:0:12}, or ' 'or ' "A25"
  mutant "any failed suite attempt is final (no retry)" '  [ "$a" -ge "$SUITE_TRIES" ]' '  return 0' "A26"
  mutant "a failing suite is retried forever" '  [ "$a" -ge "$SUITE_TRIES" ]' '  return 1' "A26"
  mutant "off mode still runs" 'if [ "$MODE" = off ] && [ "$CMD" = run ]; then' 'if false; then' "A11"
fi
echo "  box_autodeploy: $P passed, $F failed"
[ "$F" -eq 0 ]
