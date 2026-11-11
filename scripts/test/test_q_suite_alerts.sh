#!/usr/bin/env bash
# test_q_suite_alerts.sh - pkg/q-suite-alerts (2026-11-10). Hermetic: fake HOME, curl/ssh impossible (Z10 sandbox), no network.
#   S1  test_z8b.sh passes lib_subshell_cd_lint.py (it had three `( cd X && ...; git add/commit )` subshells -> the suite cron was red every 6 h via test_live_repo_guard.sh)
#       MUTATION: putting one back (`cd "$ca" ||` -> `cd "$ca" &&`) must make the lint fail again; the lint itself is untouched (a bad fixture still fails)
#   S2  qa_daily_shadow.sh --staging-only alert grace: a MISMATCH_BEHIND against a candidate committed < QA_STAGING_ALERT_GRACE_S (900) ago raises NO alerts.log WARN (deploy lag),
#       an OLD candidate (or grace=0) still does, MISMATCH_FAILED is never graced; and the GATE IS UNCHANGED: staging_check still says FAIL/MISMATCH_BEHIND and the
#       enforce promote still BLOCKS with and without the grace. MUTATIONS: grace removed (fresh BEHIND alerts), grace applied to every relation (fresh FAILED silenced)
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
OQ="$HERE/../.."; QA="$OQ/qa"
PYB="$(command -v python3.12 || command -v python3)"; [ -n "$PYB" ] || { echo "  SKIP: no python3"; exit 0; }
pass=0; fail=0
ck(){ if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'cd /; rm -rf "$T"' EXIT
. "$HERE/lib_mac_test_sandbox.sh" && mts_sandbox_init "$T" || { echo "  FAIL: Z10 mac test sandbox"; exit 1; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null

echo "== S1 z8b lint =="
LINT="$HERE/lib_subshell_cd_lint.py"
ck "S1: test_z8b.sh passes the subshell-cd lint" "$PYB $LINT $HERE/test_z8b.sh"
ck "S1: no other scripts/test/*.sh (besides the lint's own fixture file) is flagged" "$PYB $LINT \$(ls $HERE/*.sh | grep -v '/test_live_repo_guard.sh\$')"
mkdir -p "$T/mut"
"$PYB" -c 'import sys; s=open(sys.argv[1]).read(); old="( cd \"$ca\" || exit 1; git init"; assert old in s; open(sys.argv[2],"w").write(s.replace(old,"( cd \"$ca\" \x26\x26 git init",1))' "$HERE/test_z8b.sh" "$T/mut/test_z8b.sh"
ck "S1-mutation: the pre-fix form in test_z8b.sh makes the lint fail again" "! $PYB $LINT $T/mut/test_z8b.sh"
AMP='&&'; printf '#!/bin/bash\n( cd "$r" %s git init -q\n  git add -A; git commit -qm x )\n' "$AMP" > "$T/mut/bad.sh"
ck "S1: the lint still rejects an intentionally bad fixture (not weakened)" "! $PYB $LINT $T/mut/bad.sh"

echo "== S2 staging alert grace =="
safe_set_sandbox_home "$T" || exit 1; Q="$HOME/overnight-queue"; OUT="$T/out.log"
mkdir -p "$T/shim"; cd "$T"
printf '#!/bin/sh\nexit 0\n' > "$T/shim/curl"; chmod +x "$T/shim/curl"
ENVPATH="$T/shim:$(dirname "$PYB"):/usr/bin:/bin:/usr/local/bin"
GREEN="chore(overnight): reconcile overnight/feature into develop (branch-hygiene, gate=tests-green)"
cronenv(){ env -i HOME="$HOME" PATH="$ENVPATH" NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 NTFY_TOPIC=selftest_ignore OVN_POSTCHECK=off OVN_POSTCHECK_NO_CLI=1 OVN_POSTCHECK_HEALTH=off OVN_POSTCHECK_VERCEL=off \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null "$@"; }
setup(){
  rm -rf "${T:?}/home" "${T:?}/origin" "${T:?}/seed"; mkdir -p "$Q/state" "$Q/scripts" "$Q/qa" "$Q/repos" "$Q/logs" "$T/origin" "$T/seed"
  for f in qa_common release_candidate staging_check promote_gate qa_timeout prod_alembic_check prod_alembic_snapshot vercel_prod_state promote_postcheck; do cp "$QA/$f.py" "$Q/qa/"; done
  cp "$QA/qa_daily_shadow.sh" "$QA/qa_enforce.sh" "$Q/qa/"; cp "$OQ/promote_to_prod.sh" "$OQ/daily_promote.sh" "$OQ/staging_smoke.sh" "$Q/"
  printf 'import sys\nsys.exit(0)\n' > "$Q/scripts/check_migrations.py"
}
mkrepo(){  # $1=name  $2=optional unix time for every commit (old candidate)
  local n="$1" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s" || exit 1
    if [ -n "${2:-}" ]; then export GIT_COMMITTER_DATE="@$2 +0000" GIT_AUTHOR_DATE="@$2 +0000"; fi
    echo base > f.txt && git add f.txt && git commit -q -m base && git branch -M main && git push -q origin main
    git checkout -q -b develop && git checkout -q -b feat1 && echo f1 > feat1.txt && git add feat1.txt && git commit -q -m "feat: one"
    git checkout -q develop && git merge -q --no-ff -m "$GREEN" feat1 && git push -q origin develop )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
}
sha(){ git -C "$T/origin/$1.git" rev-parse "$2" 2>/dev/null; }
snap(){  # $1=repo then STATUS:sha newest first
  mkdir -p "$Q/state/staging_deploys"; local r="$1"; shift
  "$PYB" - "$Q/state/staging_deploys/$r.json" "$@" <<'PY'
import json, sys, time
path, specs = sys.argv[1], sys.argv[2:]
deps = []
for i, sp in enumerate(specs):
    st, sh = sp.split(":", 1)
    ca = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - 30 - 60 * i))
    deps.append({"id": "dep%05d" % i, "status": st, "createdAt": ca, "meta": {"commitHash": sh, "branch": "develop"}})
json.dump({"repo": "x", "fetched_at": time.time(), "deployments": deps}, open(path, "w"))
PY
}
shd(){ rm -rf "${Q:?}/state/qa_shadow_alerted"; : > "$Q/state/alerts.log"; cronenv OVN_DIR="$Q" QA_STAGING_ALERT_GRACE_S="${GRACE:-}" QA_DAILY_STAGING_REPOS="app" QA_GATE_TIMEOUT=60 bash "$Q/qa/qa_daily_shadow.sh" --staging-only > "$OUT" 2>&1; }
nal(){ grep -c "WARN | qa-staging-check | app candidate" "$Q/state/alerts.log" 2>/dev/null || true; }
chk(){ cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" "$PYB" "$Q/qa/staging_check.py" check --repo app --release-plan --provider file --no-record 2>/dev/null | tail -1; }
field(){ "$PYB" -c 'import sys,json; d=json.loads(sys.stdin.read()); print(eval(sys.argv[1]))' "$1"; }
runp(){ cronenv QA_STAGING_ALERT_GRACE_S="${GRACE:-}" bash "$Q/promote_to_prod.sh" --yes "$Q/repos/app" > "$OUT" 2>&1 < /dev/null; }

setup; mkrepo app; m0="$(sha app main)"
snap app "SUCCESS:$m0"                           # staging serves the OLD main build: BEHIND the fresh develop candidate
unset GRACE
shd
ck "S2: fresh candidate + BEHIND: NO alerts.log WARN (deploy lag is not an alert)" "[ \"\$(nal)\" = 0 ]"
ck "S2: the shadow row is still recorded FAIL / MISMATCH_BEHIND (gate evidence untouched)" "grep -q 'MISMATCH_BEHIND' $Q/state/qa_shadow/staging_check.jsonl && grep -q '\"verdict\": \"FAIL\"' $Q/state/qa_shadow/staging_check.jsonl"
CK="$(chk)"
ck "S2-gate: staging_check verdict is FAIL and relation MISMATCH_BEHIND with the grace default" "[ \"\$(printf '%s' '$CK' | field 'd[\"verdict\"]+d[\"details\"][\"relation\"]')\" = FAILMISMATCH_BEHIND ]"
ck "S2-gate: details carry candidate_age_s (information only)" "[ \"\$(printf '%s' '$CK' | field 'type(d[\"details\"][\"candidate_age_s\"]).__name__')\" = int ]"
CK0="$(QA_STAGING_ALERT_GRACE_S=0 chk)"
ck "S2-gate: verdict/relation/summary identical with the grace OFF" "[ \"\$(printf '%s' '$CK' | field 'd[\"verdict\"]+d[\"details\"][\"relation\"]+d[\"summary\"]')\" = \"\$(printf '%s' '$CK0' | field 'd[\"verdict\"]+d[\"details\"][\"relation\"]+d[\"summary\"]')\" ]"
runp
ck "S2-gate: enforce promote still BLOCKS the BEHIND candidate (grace default)" "grep -q 'STAGING-GATE BLOCK' $OUT && [ \"\$(sha app main)\" = $m0 ]"
GRACE=0 runp
ck "S2-gate: enforce promote blocks identically with the grace OFF" "grep -q 'STAGING-GATE BLOCK' $OUT && [ \"\$(sha app main)\" = $m0 ]"
GRACE=0 shd
ck "S2: grace=0 (off): the fresh BEHIND alerts as before (one WARN)" "[ \"\$(nal)\" = 1 ]"
unset GRACE; shd
ck "S2: suppressed pass writes no dedupe marker (a later pass can still alert)" "[ -z \"\$(ls $Q/state/qa_shadow_alerted 2>/dev/null)\" ]"
# OLD candidate (committed 1 h ago): BEHIND alerts at once
setup; mkrepo app "$(( $(date +%s) - 3600 ))"; snap app "SUCCESS:$(sha app main)"; unset GRACE; shd
ck "S2: OLD candidate (1 h) + BEHIND: alerts (grace window over)" "[ \"\$(nal)\" = 1 ]"
# FAILED is never graced, even with a fresh candidate
setup; mkrepo app; snap app "FAILED:$(sha app develop)" "SUCCESS:$(sha app main)"; unset GRACE; shd
ck "S2: fresh candidate + latest deploy FAILED (MISMATCH_FAILED): still alerts" "[ \"\$(nal)\" = 1 ] && grep -q MISMATCH_FAILED $Q/state/alerts.log"
# future-dated candidate (clock skew, +30 days) with a BEHIND snapshot: no usable age => fail open, the alert is NOT suppressed
setup; mkrepo app "$(( $(date +%s) + 30*86400 ))"; snap app "SUCCESS:$(sha app main)"; unset GRACE; shd
ck "S2: future-dated candidate (+30d) + BEHIND: alerts (1 WARN, age unknown fails open)" "[ \"\$(nal)\" = 1 ]"
CKF="$(chk)"
ck "S2: future-dated candidate: candidate_age_s is null and the verdict path is unchanged (FAIL/MISMATCH_BEHIND)" "[ \"\$(printf '%s' '$CKF' | field 'str(d[\"details\"][\"candidate_age_s\"])+d[\"verdict\"]+d[\"details\"][\"relation\"]')\" = NoneFAILMISMATCH_BEHIND ]"
# mutants of the installed qa_daily_shadow.sh
mutate(){ "$PYB" - "$Q/qa/qa_daily_shadow.sh" "$1" <<'PY'
import sys
p, kind = sys.argv[1], sys.argv[2]
s = open(p).read()
line = 'if dt.get("relation")=="MISMATCH_BEHIND" and g>0 and isinstance(age,int) and age<g: sys.exit(0)'
assert line in s
if kind == "nograce":
    s = s.replace(line, "pass")
elif kind == "anyrel":
    s = s.replace('dt.get("relation")=="MISMATCH_BEHIND" and ', "")
open(p, "w").write(s)
PY
}
setup; mkrepo app; snap app "SUCCESS:$(sha app main)"; mutate nograce; unset GRACE; shd
ck "S2-mutant: grace removed => the fresh BEHIND alerts (test catches it)" "[ \"\$(nal)\" = 1 ]"
setup; mkrepo app; snap app "FAILED:$(sha app develop)" "SUCCESS:$(sha app main)"; mutate anyrel; unset GRACE; shd
ck "S2-mutant: grace applied to every relation => fresh FAILED silenced (test catches it)" "[ \"\$(nal)\" = 0 ]"

echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
