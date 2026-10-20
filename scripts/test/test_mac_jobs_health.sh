#!/usr/bin/env bash
# test_mac_jobs_health.sh - L2-mac-jobs: scripts/mac_jobs_health.py (+ .sh, mac_jobs.manifest, job heartbeats). The supervisor must make the 2026-10-17/18 incidents LOUD within an hour:
# a launchd job exiting 127 for hours (qa-staging-export), a dead bridge, a wedged live checkout. Hermetic: stub launchctl/curl/ssh (lib_mac_fixture.sh), time pinned by MAC_JOBS_NOW. Mutants must FAIL a scenario.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_mac_fixture.sh" || exit 1
HP="$MF_SCRIPTS/mac_jobs_health.py"; HS="$MF_SCRIPTS/mac_jobs_health.sh"
[ -f "$HP" ] && [ -f "$HS" ] && [ -f "$MF_SCRIPTS/mac_jobs.manifest" ] || { echo "  FAIL: health script/manifest missing"; exit 1; }
mf_init
trap 'safe_rm_rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
RN=0; NOW=0; MAN=""
fresh() { # fresh state dir + manifest + launchctl table (all four jobs loaded, exit 0)
  RN=$((RN+1)); export OVN_MAC_STATE="$T/st$RN"; mkdir -p "$OVN_MAC_STATE/hb"; : > "$CALLS"; NOW="$(date +%s)"; MAN="$OVN_MAC_STATE/test.manifest"
  { echo "# test manifest"
    echo "com.t.a | 600  | $OVN_MAC_STATE/a.log | hb/a | critical"
    echo "com.t.b | 7200 | $OVN_MAC_STATE/b.log | hb/b |"
    echo "com.t.c | 600  | $OVN_MAC_STATE/c.log | hb/c | nokick"
    echo "com.t.d | 600  | $OVN_MAC_STATE/d.log | hb/d |"; } > "$MAN"
  table "com.t.a:-:0" "com.t.b:-:0" "com.t.c:-:0" "com.t.d:-:0"
  for j in a b c d; do hb $j 100; done; live_ok
}
table() { { printf 'PID\tStatus\tLabel\n'; local e; for e in "$@"; do IFS=: read -r l p s <<< "$e"; printf '%s\t%s\t%s\n' "$p" "$s" "$l"; done; } > "$T/launchctl.table"; }
hb() { echo $((NOW - $2)) > "$OVN_MAC_STATE/hb/$1"; }
setlog() { printf '%s\n' "$2" > "$OVN_MAC_STATE/$1.log"; python3 -c 'import os,sys; os.utime(sys.argv[1], (int(sys.argv[2]), int(sys.argv[2])))' "$OVN_MAC_STATE/$1.log" "$3"; }
live_ok() { printf '{"ts": %d, "mode": "enforce", "state": "ok", "head": "abc1234", "behind": 0, "ahead": 0, "detail": "", "dir": "x"}' "$NOW" > "$OVN_MAC_STATE/live_sync.json"; }
run_h() { # run_h <mode> [now-offset] [script]
  local m="$1" off="${2:-0}" s="${3:-$HP}"
  OVN_MAC_JOBS="$m" MAC_JOBS_MANIFEST="$MAN" MAC_JOBS_NOW=$((NOW + off)) MAC_JOBS_UID=501 MAC_JOBS_NO_BOX=1 python3 "$s" --print > "$T/hout.txt" 2>&1 < /dev/null
}
jf() { python3 -c 'import json,sys
d=json.load(open(sys.argv[1]+"/health.json"))
for j in d["jobs"]:
    if j["label"]==sys.argv[2]: print(j.get(sys.argv[3])); break' "$OVN_MAC_STATE" "$1" "$2" 2>/dev/null; }
kicks() { grep -c "^launchctl kickstart gui/501/$1\$" "$CALLS" 2>/dev/null; }

echo "== healthy"
fresh; run_h shadow
chk "all jobs fresh + exit 0: healthy=true, no alerts, no kickstart, health.json + health.log written" bash -c "python3 -c 'import json,sys; d=json.load(open(\"$OVN_MAC_STATE/health.json\")); sys.exit(0 if d[\"healthy\"] and all(j[\"status\"]==\"ok\" for j in d[\"jobs\"]) else 1)' && ! grep -qE 'curl|kickstart|ssh' '$CALLS' && [ -s '$OVN_MAC_STATE/health.log' ]"
chk "one-line summary names the mode and the live checkout state" grep -q "mac-jobs\[shadow\]: 5/5 ok; live=ok@abc1234" "$T/hout.txt"

echo "== launchd exit 127 (the qa-staging-export incident)"
fresh; table "com.t.a:-:127" "com.t.b:-:0" "com.t.c:-:0" "com.t.d:-:0"; run_h shadow
chk "shadow: status=failed with the 127 hint, NO kickstart (would_kick recorded), emergency push to the relay" bash -c "[ \"$(jf com.t.a status)\" = failed ] && [ \"$(kicks com.t.a)\" = 0 ] && [ \"$(jf com.t.a action)\" = 'would_kick (shadow)' ] && grep -q 'X-Ovn-Level: emergency' '$CALLS' && python3 -c 'import json; d=json.load(open(\"$OVN_MAC_STATE/health.json\")); print(d[\"jobs\"][0][\"detail\"])' | grep -q '127 = command not found'"
fresh; table "com.t.a:-:127" "com.t.b:-:0" "com.t.c:-:0" "com.t.d:-:0"; run_h enforce
chk "enforce: kickstart gui/501/com.t.a issued exactly once" bash -c "[ \"$(kicks com.t.a)\" = 1 ] && [ \"$(jf com.t.a action)\" = kickstarted ]"
chk "summary line surfaces the failed job" grep -q "com.t.a failed" "$T/hout.txt"
fresh; table "com.t.a:-:127" "com.t.b:-:0" "com.t.c:-:0" "com.t.d:-:0"; MF_LC_KICK_RC=1 run_h enforce
chk "kickstart that itself fails is recorded as kickstart_failed (still counts toward the budget)" bash -c "[ \"$(jf com.t.a action | cut -c1-16)\" = kickstart_failed ] && [ \"$(jf com.t.a kicks_24h)\" = 1 ]"

echo "== stale heartbeat"
fresh; hb b 9000; run_h enforce
chk "stale (non-critical): kickstarted; alert is the buffered kind (no emergency header) + box alerts.log line" bash -c "[ \"$(jf com.t.b status)\" = stale ] && [ \"$(kicks com.t.b)\" = 1 ] && ! grep -q 'X-Ovn-Level: emergency' '$CALLS' && grep -q 'alerts.log' '$CALLS'"
fresh; hb a 5000; run_h shadow
chk "stale CRITICAL job: emergency level" bash -c "[ \"$(jf com.t.a status)\" = stale ] && grep -q 'X-Ovn-Level: emergency' '$CALLS'"
chk "fresh job next to a stale one stays ok" bash -c "[ \"$(jf com.t.d status)\" = ok ]"

echo "== kick budget (3 per rolling 24h)"
fresh; hb b 9000
run_h enforce 0; run_h enforce 60; run_h enforce 120
chk "3 kickstarts so far" bash -c "[ \"$(kicks com.t.b)\" = 3 ]"
run_h enforce 180
chk "4th run: NO 4th kickstart, action=kick_budget_exhausted, emergency alert for the budget" bash -c "[ \"$(kicks com.t.b)\" = 3 ] && [ \"$(jf com.t.b action)\" = kick_budget_exhausted ] && grep -q 'still stale after 3 kickstarts' '$OVN_MAC_STATE/alerts.log'"
fresh; hb b 9000; OLD=$NOW; run_h enforce 0; run_h enforce 1; run_h enforce 2; hb b 99999; run_h enforce 90000
chk "rolling window: a stale job 25h after the first kicks is kicked again (kick #4)" bash -c "[ \"$(kicks com.t.b)\" = 4 ]"

echo "== never kicked: running / nokick / not loaded"
fresh; table "com.t.a:-:0" "com.t.b:-:0" "com.t.c:-:0" "com.t.d:4242:0"; hb d 5000; run_h enforce
chk "a job that is currently RUNNING (pid) is never kickstarted" bash -c "[ \"$(jf com.t.d status)\" = stale ] && [ \"$(kicks com.t.d)\" = 0 ]"
fresh; hb c 5000; run_h enforce
chk "a nokick job is alerted but never kickstarted" bash -c "[ \"$(jf com.t.c status)\" = stale ] && [ \"$(kicks com.t.c)\" = 0 ]"
fresh; table "com.t.a:-:0" "com.t.b:-:0" "com.t.c:-:0"; run_h enforce
chk "label missing from launchctl list: not_loaded, needs_bootstrap, no kickstart" bash -c "[ \"$(jf com.t.d status)\" = not_loaded ] && [ \"$(jf com.t.d action)\" = needs_bootstrap ] && [ \"$(kicks com.t.d)\" = 0 ]"

echo "== log errors newer than the last success"
fresh; hb a 100; setlog a "Traceback (most recent call last): boom" $((NOW - 10)); run_h enforce
chk "fresh heartbeat but a Traceback logged AFTER it: degraded, warn alert, never kicked" bash -c "[ \"$(jf com.t.a status)\" = degraded ] && [ \"$(kicks com.t.a)\" = 0 ] && grep -q 'degraded' '$OVN_MAC_STATE/alerts.log'"
fresh; hb a 100; setlog a "Traceback (most recent call last): old" $((NOW - 5000)); run_h enforce
chk "an error OLDER than the last success is ignored (no stale-forever log alarm)" bash -c "[ \"$(jf com.t.a status)\" = ok ]"
fresh; hb a 5000; setlog a "command not found: python3" $((NOW - 10)); run_h shadow
chk "stale + log error: the error line is quoted in the detail" bash -c "python3 -c 'import json; d=json.load(open(\"$OVN_MAC_STATE/health.json\")); print([j for j in d[\"jobs\"] if j[\"label\"]==\"com.t.a\"][0][\"detail\"])' | grep -q 'command not found'"

echo "== never ran"
fresh; rm -f "$OVN_MAC_STATE/hb/d"; run_h enforce
chk "no heartbeat yet, first sighting: pending (no alarm on a new job)" bash -c "[ \"$(jf com.t.d status)\" = pending ] && [ \"$(kicks com.t.d)\" = 0 ]"
run_h enforce 700
chk "still no heartbeat after its window: stale" bash -c "[ \"$(jf com.t.d status)\" = stale ]"

echo "== alert dedupe + recovery"
fresh; hb a 5000; : > "$CALLS"; run_h shadow 0; run_h shadow 60
chk "same stale job twice within the cooldown: ONE relay push" bash -c "[ \$(grep -c 'Title: Mac jobs: com.t.a:stale' '$CALLS') -eq 1 ] && [ \$(grep -c 'com.t.a:stale' '$OVN_MAC_STATE/alerts.log') -eq 2 ]"
run_h shadow 22000
chk "after the cooldown (6h) the same alert is pushed again" bash -c "[ \$(grep -c 'Title: Mac jobs: com.t.a:stale' '$CALLS') -eq 2 ]"
fresh; hb a 5000; run_h shadow 0; : > "$CALLS"; hb a 1; run_h shadow 30
chk "recovery: one 'recovered' line delivered when the job is ok again" bash -c "grep -q 'recovered' '$OVN_MAC_STATE/alerts.log' && grep -q 'recovered' '$CALLS'"
: > "$CALLS"; run_h shadow 60
chk "...and not repeated on the next healthy run" bash -c "! grep -q recovered '$CALLS'"

echo "== live checkout"
fresh; printf '{"ts": %d, "mode": "enforce", "state": "diverged", "head": "abc", "behind": 3, "ahead": 1, "detail": "ahead=1 behind=3", "dir": "x"}' "$NOW" > "$OVN_MAC_STATE/live_sync.json"; run_h enforce
chk "live_sync state=diverged -> live-sync failed, emergency, never kickstarted (nokick)" bash -c "[ \"$(jf live-sync status)\" = failed ] && grep -q 'X-Ovn-Level: emergency' '$CALLS' && ! grep -q 'kickstart' '$CALLS'"
fresh; printf '{"ts": %d, "mode": "enforce", "state": "ok", "head": "abc", "behind": 0, "ahead": 0, "detail": "", "dir": "x"}' $((NOW - 7200)) > "$OVN_MAC_STATE/live_sync.json"; run_h enforce
chk "a live sync that has not run for 2h (limit 30m) is stale" bash -c "[ \"$(jf live-sync status)\" = stale ]"

echo "== modes"
fresh; hb b 9000; OVN_MAC_JOBS=off MAC_JOBS_MANIFEST="$MAN" MAC_JOBS_NOW=$NOW python3 "$HP" >/dev/null 2>&1 < /dev/null
chk "off: nothing written, nothing called" bash -c "[ ! -e '$OVN_MAC_STATE/health.json' ] && [ ! -s '$CALLS' ]"
fresh; hb b 9000; echo enforce > "$OVN_MAC_STATE/mode"
env -u OVN_MAC_JOBS MAC_JOBS_MANIFEST="$MAN" MAC_JOBS_NOW=$NOW MAC_JOBS_UID=501 MAC_JOBS_NO_BOX=1 python3 "$HP" >/dev/null 2>&1 < /dev/null
chk "the one-line mode FILE flips every job to enforce when the env var is unset" bash -c "[ \"$(kicks com.t.b)\" = 1 ]"
: > "$CALLS"; hb b 9000; OVN_MAC_JOBS=shadow MAC_JOBS_MANIFEST="$MAN" MAC_JOBS_NOW=$((NOW+10)) MAC_JOBS_UID=501 MAC_JOBS_NO_BOX=1 python3 "$HP" >/dev/null 2>&1 < /dev/null
chk "the env var wins over the mode file (rollback to shadow = no kickstart)" bash -c "[ \"$(kicks com.t.b)\" = 0 ]"
fresh; echo bogus > "$OVN_MAC_STATE/mode"; hb b 9000; env -u OVN_MAC_JOBS MAC_JOBS_MANIFEST="$MAN" MAC_JOBS_NOW=$NOW MAC_JOBS_UID=501 MAC_JOBS_NO_BOX=1 python3 "$HP" >/dev/null 2>&1 < /dev/null
chk "an unknown mode value behaves as shadow (fail safe: no kickstart)" bash -c "[ \"$(kicks com.t.b)\" = 0 ] && [ \"$(jf com.t.b action)\" = 'would_kick (shadow)' ]"

echo "== launchctl list itself failing / box copy / manifest errors"
fresh; MF_LC_LIST_RC=1 run_h shadow
chk "launchctl list failure: reported in the summary, jobs NOT mislabeled not_loaded" bash -c "grep -q 'launchctl list FAILED' '$T/hout.txt' && [ \"$(jf com.t.a status)\" = ok ]"
fresh; OVN_MAC_JOBS=shadow MAC_JOBS_MANIFEST="$MAN" MAC_JOBS_NOW=$NOW MAC_JOBS_UID=501 MF_SSH_CAPTURE=1 python3 "$HP" >/dev/null 2>&1 < /dev/null
chk "health.json is copied to the box over ssh (stdin carries the JSON with the summary)" bash -c "grep -q 'mac_jobs_health.json' '$CALLS' && grep -l '\"summary\"' '$T'/ssh_stdin.*"
fresh; printf 'this is not a manifest line\n' > "$MAN"; run_h shadow
chk "malformed manifest: exit 0 (never crash-loops launchd), emergency alert health-manifest" bash -c "grep -q 'health-manifest' '$OVN_MAC_STATE/alerts.log'"
fresh; : > "$CALLS"; OVN_MAC_JOBS=shadow MAC_JOBS_MANIFEST="$MAN" MAC_JOBS_NOW=$NOW MAC_JOBS_NO_BOX=1 OVN_MAC_STATE="$OVN_MAC_STATE" bash "$HS" >/dev/null 2>&1 < /dev/null
chk "mac_jobs_health.sh wrapper runs the supervisor and touches its own heartbeat" bash -c "[ -s '$OVN_MAC_STATE/health.json' ] && [ -s '$OVN_MAC_STATE/hb/mac-jobs-health' ]"

echo "== manifest / templates / heartbeat wiring (the real files)"
python3 - "$MF_SCRIPTS" "$MF_REPO" > "$T/wiring.txt" 2>&1 <<'PYEOF'
import os, re, sys
sys.path.insert(0, sys.argv[1])
import importlib.util
spec = importlib.util.spec_from_file_location("hp", os.path.join(sys.argv[1], "mac_jobs_health.py")); hp = importlib.util.module_from_spec(spec); spec.loader.exec_module(hp)
jobs = hp.parse_manifest(os.path.join(sys.argv[1], "mac_jobs.manifest"))
tpl = set(f[:-6] for f in os.listdir(os.path.join(sys.argv[1], "mac_jobs", "templates")) if f.endswith(".plist"))
src = ""
for root, dirs, files in os.walk(sys.argv[2]):
    dirs[:] = [d for d in dirs if d not in (".git", "node_modules", "__pycache__", "state", "repos", "test")]
    for f in files:
        if f.endswith((".sh", ".py")):
            try: src += open(os.path.join(root, f), errors="replace").read()
            except OSError: pass
bad = 0
for j in jobs:
    if j["label"] not in tpl: print("NO TEMPLATE for", j["label"]); bad += 1
    name = os.path.basename(j["hb"])
    if not re.search(r"hb/" + re.escape(name) + r"\b|mac_hb_touch " + re.escape(name) + r"\b", src): print("NO SCRIPT writes heartbeat", name); bad += 1
print("jobs=%d templates=%d bad=%d" % (len(jobs), len(tpl), bad)); sys.exit(1 if bad else 0)
PYEOF
ok "every manifest job has a plist template and a script that writes its heartbeat ($(tail -1 "$T/wiring.txt"))" $?
chk "every plist template parses as a plist" bash -c "for f in '$MF_SCRIPTS'/mac_jobs/templates/*.plist; do python3 -c 'import plistlib,sys; plistlib.load(open(sys.argv[1],\"rb\"))' \"\$f\" || exit 1; done"
chk "no template still points at the interactive checkout path (only exception: the qa-notes DATA dir QA_NOTES_LOGS_DIR, see test_mac_review_fixes.sh D4)" bash -c "! grep -H 'LocalProjects/shared/' '$MF_SCRIPTS'/mac_jobs/templates/*.plist | grep -v '<key>QA_NOTES_LOGS_DIR</key><string>@HOME@/LocalProjects/shared/qa/manual_logs</string>'"

echo "== heartbeat only on SUCCESS: qa-staging-export.sh (behavioural, real script text)"
SB="$T/exp"; mkdir -p "$SB/scripts/overnight-queue/qa" "$SB/bin" "$SB/home/overnight-queue/state/staging_deploys"
sed 's|^export PATH=.*$|:|' "$MF_SCRIPTS/qa-staging-export.sh" > "$SB/scripts/qa-staging-export.sh"      # only the PATH reset is removed so PATH stubs apply
cp "$MF_SCRIPTS/overnight-queue/qa/qa_timeout.py" "$SB/scripts/overnight-queue/qa/"
printf 'print("")\n' > "$SB/scripts/railway_config_guard.py"
printf 'import os,sys\nif os.environ.get("FAKE_FAIL") and "--repo" in sys.argv and sys.argv[sys.argv.index("--repo")+1]==os.environ["FAKE_FAIL"]:\n    print("boom")\nelse:\n    print("\\"exported 1 deployments\\"")\n' > "$SB/scripts/overnight-queue/qa/staging_check.py"
echo '{}' > "$SB/home/overnight-queue/state/staging_deploys/billwatch.json"
for x in ssh scp; do printf '#!/bin/sh\nexit 0\n' > "$SB/bin/$x"; chmod 755 "$SB/bin/$x"; done
fresh; rm -f "$OVN_MAC_STATE/hb/qa-staging-export"
( PATH="$SB/bin:$PATH" HOME="$SB/home" OVN_DIR="$SB/home/overnight-queue" OVN_MAC_STATE="$OVN_MAC_STATE" QA_STAGING_REPOS="billwatch gitlark" QA_PROD_EXPORT_REPOS="billwatch" bash "$SB/scripts/qa-staging-export.sh" > "$T/exp.out" 2>&1 < /dev/null ); erc=$?
chk "all repos exported + copied: exit 0 and the success heartbeat is written" bash -c "[ $erc -eq 0 ] && [ -s '$OVN_MAC_STATE/hb/qa-staging-export' ]"
rm -f "$OVN_MAC_STATE/hb/qa-staging-export"
( PATH="$SB/bin:$PATH" HOME="$SB/home" OVN_DIR="$SB/home/overnight-queue" OVN_MAC_STATE="$OVN_MAC_STATE" FAKE_FAIL=gitlark QA_STAGING_REPOS="billwatch gitlark" QA_PROD_EXPORT_REPOS="billwatch" bash "$SB/scripts/qa-staging-export.sh" > "$T/exp.out" 2>&1 < /dev/null ); erc=$?
chk "one repo's export failed: exit still 0 but NO heartbeat (so it goes stale and is flagged)" bash -c "[ $erc -eq 0 ] && [ ! -e '$OVN_MAC_STATE/hb/qa-staging-export' ]"

echo "== mutants"
MUT="$T/mut"; mkdir -p "$MUT"; cp "$MF_SCRIPTS"/mac_jobs_health.py "$MUT/"
mutant() { mutate "$HP" "$MUT/mac_jobs_health.py" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; }
if mutant kick-in-shadow 'if md == "enforce":
                    ok, msg = kickstart' 'if True:
                    ok, msg = kickstart'; then
  fresh; hb b 9000; run_h shadow 0 "$MUT/mac_jobs_health.py"
  chk "M1 (kickstart in shadow) is caught" bash -c "[ \"$(kicks com.t.b)\" = 1 ]"
fi
if mutant no-budget 'len(recent) < max_kicks' 'True'; then
  fresh; hb b 9000; for o in 0 1 2 3 4; do run_h enforce $o "$MUT/mac_jobs_health.py"; done
  chk "M2 (no kick budget) is caught: 5 kickstarts instead of 3" bash -c "[ \"$(kicks com.t.b)\" -gt 3 ]"
fi
if mutant kick-running 'and not r["running"]' ''; then
  fresh; table "com.t.a:-:0" "com.t.b:-:0" "com.t.c:-:0" "com.t.d:4242:0"; hb d 5000; run_h enforce 0 "$MUT/mac_jobs_health.py"
  chk "M3 (kick running jobs) is caught" bash -c "[ \"$(kicks com.t.d)\" = 1 ]"
fi
if mutant ignore-exit-status 'elif st not in (None, 0) and not running:' 'elif False:'; then
  fresh; table "com.t.a:-:127" "com.t.b:-:0" "com.t.c:-:0" "com.t.d:-:0"; run_h enforce 0 "$MUT/mac_jobs_health.py"
  chk "M4 (ignore launchctl exit status) is caught: the 127 job is no longer failed" bash -c "[ \"$(jf com.t.a status)\" != failed ]"
fi
if mutant ignore-stale 'elif age > job["max_age"]:' 'elif False:'; then
  fresh; hb b 9000; run_h enforce 0 "$MUT/mac_jobs_health.py"
  chk "M5 (ignore heartbeat age) is caught" bash -c "[ \"$(jf com.t.b status)\" != stale ]"
fi
if mutant old-log-errors 'if since is not None and st.st_mtime <= since:
        return []' 'pass'; then
  fresh; hb a 100; setlog a "Traceback old" $((NOW - 5000)); run_h enforce 0 "$MUT/mac_jobs_health.py"
  chk "M6 (old log errors count) is caught: an old error makes the job degraded" bash -c "[ \"$(jf com.t.a status)\" = degraded ]"
fi
if mutant no-dedupe 'if t - last < int(os.environ.get("MAC_ALERT_COOLDOWN_S", "21600")):
        return False' 'pass'; then
  fresh; hb a 5000; : > "$CALLS"; run_h shadow 0 "$MUT/mac_jobs_health.py"; run_h shadow 60 "$MUT/mac_jobs_health.py"
  chk "M7 (no alert dedupe) is caught: two relay pushes for one stale job" bash -c "[ \$(grep -c '^curl' '$CALLS') -eq 2 ]"
fi
if mutant nokick-ignored 'kickable = "nokick" not in job["flags"] and' 'kickable = True and'; then
  fresh; hb c 5000; run_h enforce 0 "$MUT/mac_jobs_health.py"
  chk "M8 (nokick ignored) is caught" bash -c "[ \"$(kicks com.t.c)\" = 1 ]"
fi

echo; echo "mac_jobs_health: $((n-fails))/$n passed"; [ "$fails" = 0 ]
