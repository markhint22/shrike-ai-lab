#!/usr/bin/env bash
# Tests for qa/h11-promote-alerting (2026-10-03, actions A3 + A10 + next_phase_qa item 6). Runs the REAL scripts in a hermetic fake HOME:
#   A. the 2026-10-03 situation through daily_promote.sh with NOTHING configured (the new default = enforce): iptv_apps' staging deploy FAILED and staging
#      serves an OLD sha => iptv_apps is HELD (log + alerts.log + ONE relay note), billwatch + gitlark (staging serves the candidate) still promote;
#      stale / missing evidence fails CLOSED; NA promotes but is reported UNVERIFIED; rollback via env, flip file and qa_enforce.sh; qa_enforce status
#   B. post-promote check (qa/promote_postcheck.py): prod deploy SUCCESS / FAILED (emergency push + alerts.log, deduped) / not seen; detached from cron
#   C. prod alembic ancestry (qa/prod_alembic_check.py; SHADOW): pass / the docstring-only-0011 incident / diverged / no snapshot / NA
#   D. staging_smoke.sh + staging_smoke.py PROVENANCE: healthy-but-stale deploy is refused
#   E. deploy_watch.sh: STAGING services watched, FAILED staging/prod => ONE emergency (urgent) + ONE alerts.log line per (repo, env, sha); ripple gone
#   F. qa_daily_shadow.sh --staging-only: one alerts.log WARN per (repo, candidate) on FAIL
# Every new behaviour has a NEGATIVE control (the seeded bad input is caught) and a BENIGN control (the clean input passes).
# curl is a PATH shim that only logs: nothing here can reach ntfy.sh, the relay or any network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ="$HERE/../.."; [ -f "$OQ/promote_to_prod.sh" ] || OQ="$HERE/.."
QA="$OQ/qa"
for f in promote_to_prod.sh daily_promote.sh staging_smoke.sh deploy_watch.sh qa/promote_gate.py qa/promote_postcheck.py qa/prod_alembic_check.py qa/qa_daily_shadow.sh qa/qa_enforce.sh; do
  [ -f "$OQ/$f" ] || { echo "  SKIP: $f not found"; exit 0; }; done
PYB="$(command -v python3.12 || command -v python3)"; [ -n "$PYB" ] || { echo "  SKIP: no python3"; exit 0; }
pass=0; fail=0
ck(){ if eval "$2" >/dev/null 2>&1; then pass=$((pass+1)); else fail=$((fail+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'cd /; rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export HOME="$T/home"; Q="$HOME/overnight-queue"; OUT="$T/out.log"
mkdir -p "$T/shim"; cd "$T"
command -v timeout >/dev/null || { printf '#!/bin/sh\nshift\nexec "$@"\n' > "$T/shim/timeout"; chmod +x "$T/shim/timeout"; }
printf '#!/bin/sh\necho "CURL_CALL $*" >> "$FAKE_CURL_LOG"\nexit 0\n' > "$T/shim/curl"; chmod +x "$T/shim/curl"
ENVPATH="$T/shim:$(dirname "$PYB"):/usr/bin:/bin:/usr/local/bin"
EXTRA=()
GREEN="chore(overnight): reconcile overnight/feature into develop (branch-hygiene, gate=tests-green)"

setup(){
  rm -rf "$T/home" "$T/origin" "$T/seed"; mkdir -p "$Q/state" "$Q/scripts" "$Q/qa" "$Q/repos" "$Q/logs" "$T/origin" "$T/seed"
  for f in qa_common release_candidate staging_check promote_gate qa_timeout prod_alembic_check promote_postcheck; do cp "$QA/$f.py" "$Q/qa/"; done
  cp "$QA/qa_enforce.sh" "$QA/qa_daily_shadow.sh" "$Q/qa/"
  cp "$OQ/promote_to_prod.sh" "$OQ/daily_promote.sh" "$OQ/staging_smoke.sh" "$Q/"; : > "$T/curl.log"; EXTRA=()
  printf 'import sys\nsys.exit(0)\n' > "$Q/scripts/check_migrations.py"
}
mkrepo(){  # $1=name  [$2=with-alembic: ok | norev (a docstring-only 0011) ]
  local n="$1" al="${2:-}" o="$T/origin/$1.git" s="$T/seed/$1"
  git init -q --bare -b main "$o"; git clone -q "$o" "$s" 2>/dev/null
  ( cd "$s" && echo base > f.txt && git add f.txt && git commit -q -m base && git branch -M main && git push -q origin main
    git checkout -q -b develop && git checkout -q -b feat1 && echo f1 > feat1.txt && git add feat1.txt && git commit -q -m "feat: one"
    if [ -n "$al" ]; then mkdir -p alembic/versions
      printf 'revision = "0009"\ndown_revision = None\n' > alembic/versions/0009_a.py
      printf 'revision: str = "0010"\ndown_revision: str = "0009"\n' > alembic/versions/0010_b.py
      if [ "$al" = norev ]; then printf '"""subscription last_event_ms (docstring only: NO revision ids)"""\n' > alembic/versions/0011_c.py
      else printf 'revision = "0011"\ndown_revision = "0010"\n' > alembic/versions/0011_c.py; fi
      git add alembic && git commit -q -m "feat: migrations"; fi
    git checkout -q develop && git merge -q --no-ff -m "$GREEN" feat1 && git push -q origin develop )
  git clone -q "$o" "$Q/repos/$n" 2>/dev/null
}
sha(){ git -C "$T/origin/$1.git" rev-parse "$2" 2>/dev/null; }
snap(){  # $1=repo then STATUS:sha newest first; SNAP_AGE seconds old; SNAP_KIND=prod_deploys for the prod export
  local kind="${SNAP_KIND:-staging_deploys}"; mkdir -p "$Q/state/$kind"; local r="$1"; shift
  "$PYB" - "$Q/state/$kind/$r.json" "${SNAP_AGE:-0}" "$@" <<'PY'
import json, os, sys, time
path, age, specs = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
deps = []
for i, sp in enumerate(specs):
    st, sh = sp.split(":", 1)
    ca = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - float(os.environ.get("SNAP_CREATED_AGE", "30")) - 60 * i))  # newest first, relative to now
    deps.append({"id": "dep%05d" % i, "status": st, "createdAt": ca, "meta": {"commitHash": sh, "branch": "develop"}})
json.dump({"repo": "x", "fetched_at": time.time() - age, "deployments": deps}, open(path, "w"))
PY
}
cronenv(){ env -i HOME="$HOME" PATH="$ENVPATH" NTFY_SERVER=http://127.0.0.1:9 FAKE_CURL_LOG="$T/curl.log" NTFY_TOPIC=selftest_ignore OVN_POSTCHECK_NO_CLI=1 \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
    ${EXTRA[@]+"${EXTRA[@]}"} "$@"; }
runp(){ cronenv bash "$Q/promote_to_prod.sh" "$@" > "$OUT" 2>&1 < /dev/null; echo $? > "$T/rc"; }
rund(){ cronenv OVN_PROMOTE_REPOS="$1" bash "$Q/daily_promote.sh" > "$OUT" 2>&1 < /dev/null; }
has(){ grep -qF -- "$1" "$OUT"; }
nalerts(){ local n=0; [ -f "$Q/state/alerts.log" ] && n="$(grep -c "$1" "$Q/state/alerts.log")"; echo "$n"; }
nnotes(){ grep -c "CURL_CALL.*Title: Promote HELD: $1" "$T/curl.log" || true; }

# ===== A. the 2026-10-03 situation, nothing configured (default = enforce) =====
setup; mkrepo iptv_apps; mkrepo billwatch; mkrepo gitlark
mI="$(sha iptv_apps main)"; mB="$(sha billwatch main)"; mG="$(sha gitlark main)"
# iptv: latest staging deploy FAILED on the candidate; staging silently serves the OLD main build. billwatch/gitlark: staging serves the candidate.
snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$mI"; snap billwatch "SUCCESS:$(sha billwatch develop)"; snap gitlark "SUCCESS:$(sha gitlark develop)"
EXTRA=(OVN_POSTCHECK=off); rund "iptv_apps billwatch gitlark"
ck "A: iptv_apps HELD: main untouched, no tag" "[ \"\$(sha iptv_apps main)\" = $mI ] && [ -z \"\$(git -C $T/origin/iptv_apps.git tag -l 'prod-*')\" ]"
ck "A: clear block line names the relation and the reason" "grep -q 'STAGING-GATE BLOCK' $OUT && grep -q 'FAIL:MISMATCH_FAILED' $OUT"
ck "A: billwatch + gitlark (green) still promoted independently (merge into main)" "[ \"\$(sha billwatch main)\" != $mB ] && [ \"\$(sha gitlark main)\" != $mG ] && git -C $T/origin/billwatch.git merge-base --is-ancestor develop main && git -C $T/origin/gitlark.git merge-base --is-ancestor develop main"
ck "A: summary: Promoted billwatch gitlark, HELD iptv_apps" "grep -qE 'Promoted: billwatch gitlark' $OUT && grep -q 'HELD.*iptv_apps' $OUT && ! grep -qE 'Promoted:.*iptv_apps' $OUT"
ck "A: summary raised to high priority for the HELD repo" "grep -q 'Priority: high' $T/curl.log"
ck "A: exactly one alerts.log line for iptv_apps, none for the promoted repos" "[ \"\$(nalerts 'iptv_apps promote SKIPPED')\" = 1 ] && [ \"\$(nalerts 'billwatch promote SKIPPED')\" = 0 ] && grep -q 'FAIL:MISMATCH_FAILED' $Q/state/alerts.log"
ck "A: exactly ONE relay note for the held repo (priority default = relay class note, not a page)" "[ \"\$(nnotes iptv_apps)\" = 1 ] && grep 'Title: Promote HELD: iptv_apps' $T/curl.log | grep -q 'Priority: default'"
ck "A: the promoted SHA is logged (prod deploy SHA) for billwatch = new main tip" "grep -q \"\\[prod-deploy\\] billwatch promoted SHA \$(sha billwatch main)\" $OUT"
# idempotence: a second run re-blocks (still FAILED) but does NOT repeat the relay note
EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/iptv_apps"
ck "A: re-run: still HELD, still ONE relay note (deduped per repo+candidate), alerts.log line is per run" "has 'STAGING-GATE BLOCK' && [ \"\$(nnotes iptv_apps)\" = 1 ] && [ \"\$(nalerts 'iptv_apps promote SKIPPED')\" = 2 ]"
# --force overrides loudly (a human decision)
runp --yes --force "$Q/repos/iptv_apps"
ck "A: --force overrides the block with a warning" "has 'would block iptv_apps but --force given' && has 'PROMOTED iptv_apps'"

# staging_deploys missing / stale / corrupt for a repo WITH staging => fail CLOSED
setup; mkrepo iptv_apps; m0="$(sha iptv_apps main)"; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/iptv_apps"
ck "A-neg: NO exported file (iptv_apps has a staging backend) => BLOCKED, reason EVIDENCE_MISSING" "has 'STAGING-GATE BLOCK' && has 'EVIDENCE_MISSING' && ! has PROMOTED && [ \"\$(sha iptv_apps main)\" = $m0 ] && [ \"\$(nalerts 'EVIDENCE_MISSING')\" = 1 ]"
setup; mkrepo iptv_apps; m0="$(sha iptv_apps main)"; SNAP_AGE=2400 snap iptv_apps "SUCCESS:$(sha iptv_apps develop)"; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/iptv_apps"
ck "A-neg: file 40 min old (>30) => BLOCKED EVIDENCE_STALE even though it would be a MATCH" "has 'STAGING-GATE BLOCK' && has 'EVIDENCE_STALE' && [ \"\$(sha iptv_apps main)\" = $m0 ]"
setup; mkrepo iptv_apps; SNAP_AGE=1500 snap iptv_apps "SUCCESS:$(sha iptv_apps develop)"; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/iptv_apps"
ck "A-benign: file 25 min old (<30) and MATCH => promotes, not UNVERIFIED" "has 'PROMOTED iptv_apps' && ! has '[unverified]' && has 'evidence=ok'"
# NA: a repo with NO staging backend promotes, but is reported UNVERIFIED (promote log + daily summary)
setup; mkrepo test-automation-agent; EXTRA=(OVN_POSTCHECK=off); rund "test-automation-agent"
ck "A: NA repo (prod-only backend) still promotes" "grep -q 'Promoted: test-automation-agent' $OUT"
ck "A: NA repo is reported UNVERIFIED in the promote log and in the summary" "grep -q '\\[unverified\\] staging gate could not verify test-automation-agent' $OUT && grep -q 'UNVERIFIED (promoted without staging provenance): test-automation-agent' $OUT"
ck "A: NA does not touch alerts.log" "[ \"\$(nalerts promote-staging-gate)\" = 0 ]"
setup; mkrepo billwatch; snap billwatch "SUCCESS:$(sha billwatch develop)"; EXTRA=(OVN_POSTCHECK=off); rund "billwatch"
ck "A-benign: a verified MATCH is NOT listed as UNVERIFIED" "grep -q 'Promoted: billwatch' $OUT && ! grep -q 'UNVERIFIED' $OUT"
# deploy of the candidate still BUILDING => HELD (transient), NOT promoted against the old build (reviewer: the smoke would hit the OLD staging)
setup; mkrepo billwatch; m0="$(sha billwatch main)"; snap billwatch "BUILDING:$(sha billwatch develop)" "SUCCESS:$(sha billwatch main)"; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/billwatch"
ck "A-neg: candidate deploy still BUILDING (enforce) => HELD reason BUILDING, main untouched, [transient-hold] printed" "has 'STAGING-GATE BLOCK' && has '(BUILDING)' && has '[transient-hold]' && ! has PROMOTED && [ \"\$(sha billwatch main)\" = $m0 ]"
ck "A-neg: a plain hold (no deferral) writes the WARN + ONE relay note" "[ \"\$(nalerts 'billwatch promote SKIPPED')\" = 1 ] && [ \"\$(nnotes billwatch)\" = 1 ]"
# BUILDING of an unknown / unrelated commit: infra-ish UNVERIFIED, proceeds
setup; mkrepo billwatch; snap billwatch "BUILDING:0123456789abcdef0123456789abcdef01234567" "SUCCESS:$(sha billwatch main)"; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/billwatch"
ck "A-benign: BUILDING with a commit unknown to the clone => proceeds UNVERIFIED (infra never blocks)" "has 'PROMOTED billwatch' && has '[unverified]'"
setup; mkrepo billwatch; snap billwatch "BUILDING:$(sha billwatch develop)" "SUCCESS:$(sha billwatch main)"; EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_STAGING_GATE=shadow); runp --yes "$Q/repos/billwatch"
ck "A: BUILDING in shadow mode proceeds UNVERIFIED (rollback path)" "has 'PROMOTED billwatch' && has '[unverified]'"
# dry-run of a held repo has NO side effects (burns neither the WARN nor the once-per-candidate relay note)
setup; mkrepo iptv_apps; snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$(sha iptv_apps main)"; EXTRA=(OVN_POSTCHECK=off); runp --dry-run "$Q/repos/iptv_apps"
ck "A-neg: --dry-run on a held repo: still reports the BLOCK, but no alerts.log line, no relay note, no marker" "has 'STAGING-GATE BLOCK' && [ \"\$(nalerts SKIPPED)\" = 0 ] && [ \"\$(nnotes iptv_apps)\" = 0 ] && [ -z \"\$(ls $Q/state/promote_held 2>/dev/null)\" ]"
runp --yes "$Q/repos/iptv_apps"
ck "A-benign: the real run after the dry run still writes the WARN and the note (not burned)" "[ \"\$(nalerts SKIPPED)\" = 1 ] && [ \"\$(nnotes iptv_apps)\" = 1 ]"
# daily_promote retry: transient hold clears while it sleeps => promoted, NO WARN, NO relay note
setup; mkrepo billwatch; snap billwatch "BUILDING:$(sha billwatch develop)" "SUCCESS:$(sha billwatch main)"; EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_RETRY_S=3)
( sleep 1; snap billwatch "SUCCESS:$(sha billwatch develop)" ) &
rund billwatch; wait
ck "A-benign: transient BUILDING hold clears during the retry window => promoted on the retry, retry line logged" "grep -q 'retry in 3s' $OUT && grep -q 'Promoted: billwatch' $OUT && ! grep -q 'HELD' $OUT"
ck "A-benign: the cleared transient hold left no alerts.log WARN and no relay note" "[ \"\$(nalerts SKIPPED)\" = 0 ] && [ \"\$(nnotes billwatch)\" = 0 ]"
setup; mkrepo billwatch; snap billwatch "BUILDING:$(sha billwatch develop)" "SUCCESS:$(sha billwatch main)"; EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_RETRY_S=1); rund billwatch
ck "A-neg: a hold that persists past the retry => HELD in the summary, ONE WARN, ONE relay note" "grep -q 'HELD.*billwatch' $OUT && ! grep -q 'Promoted: billwatch' $OUT && [ \"\$(nalerts 'billwatch promote SKIPPED')\" = 1 ] && [ \"\$(nnotes billwatch)\" = 1 ]"
setup; mkrepo iptv_apps; snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$(sha iptv_apps main)"; EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_RETRY_S=600); t0="$(date +%s)"; rund iptv_apps; t1="$(date +%s)"
ck "A-neg: a NON-transient hold (deploy FAILED) is never retried/slept on and reports at once" "[ $((t1-t0)) -lt 20 ] && ! grep -q 'retry in' $OUT && grep -q 'HELD.*iptv_apps' $OUT && [ \"\$(nalerts 'iptv_apps promote SKIPPED')\" = 1 ]"
# BEHIND (staging serves an ancestor of the candidate, e.g. hygiene merged at :00 and staging has not deployed it yet) is the same transient class
setup; mkrepo billwatch; snap billwatch "SUCCESS:$(sha billwatch main)"; EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_RETRY_S=3)
( sleep 1; snap billwatch "SUCCESS:$(sha billwatch develop)" ) &
rund billwatch; wait
ck "A-benign: BEHIND (not deployed yet) is retried once and promotes when staging catches up; no WARN" "grep -q 'FAIL:MISMATCH_BEHIND' $OUT && grep -q 'Promoted: billwatch' $OUT && [ \"\$(nalerts SKIPPED)\" = 0 ]"

# rollback paths
setup; mkrepo iptv_apps; snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$(sha iptv_apps main)"; EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_STAGING_GATE=shadow); runp --yes "$Q/repos/iptv_apps"
ck "rollback env OVN_PROMOTE_STAGING_GATE=shadow: the FAILED repo promotes (log only), mode=shadow" "has 'PROMOTED iptv_apps' && has 'mode=shadow'"
setup; mkrepo iptv_apps; snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$(sha iptv_apps main)"; EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_STAGING_GATE=enforce QA_STATE_DIR="$Q/state")
cronenv OVN_DIR="$Q" bash "$Q/qa/qa_enforce.sh" staging_check shadow > "$OUT" 2>&1
ck "qa_enforce.sh staging_check shadow writes the flip file" "grep -q 'staging_check: default(shadow) -> shadow' $OUT || grep -q -- '-> shadow' $OUT"
EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/iptv_apps"
ck "flip file shadow (no env): the FAILED repo promotes" "has 'PROMOTED iptv_apps' && has 'mode=shadow'"
EXTRA=(OVN_POSTCHECK=off OVN_PROMOTE_STAGING_GATE=enforce); snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$(sha iptv_apps main)"; git -C "$Q/repos/iptv_apps" fetch -q
ck "env OVN_PROMOTE_STAGING_GATE outranks the flip file" "[ \"\$(cronenv OVN_DIR=$Q QA_STATE_DIR=$Q/state bash $Q/qa/qa_enforce.sh status 2>&1 | grep -c 'staging_check.*enforce.*env(OVN_PROMOTE_STAGING_GATE)')\" = 1 ]"
setup; EXTRA=(OVN_DIR="$Q" QA_STATE_DIR="$Q/state")
cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash "$Q/qa/qa_enforce.sh" status > "$OUT" 2>&1
ck "qa_enforce.sh status: staging_check shows ENFORCE from the default" "grep -q 'staging_check .*enforce .*default(enforce)' $OUT"
cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash "$Q/qa/qa_enforce.sh" staging_check shadow > /dev/null 2>&1; cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash "$Q/qa/qa_enforce.sh" status > "$OUT" 2>&1
ck "qa_enforce.sh status after the flip: shadow, source=file" "grep -q 'staging_check .*shadow .*source=file' $OUT"
cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash "$Q/qa/qa_enforce.sh" staging_check enforce > "$OUT" 2>&1
ck "qa_enforce.sh staging_check enforce is accepted (promote_gate.py exists)" "grep -q 'ENFORCING' $OUT"
EXTRA=()

# gate unit decisions (pure)
ck "decide_block: FAIL+enforce blocks / FAIL+shadow does not / PASS never / NA unverified / stale+enforce blocks / stale+shadow proceeds unverified / BUILDING holds under enforce only / other UNVERIFIED proceeds" \
  "cd $Q/qa && $PYB -c '
import promote_gate as g
d=g.decide_block
assert d(\"enforce\",\"FAIL\",\"MISMATCH_FAILED\",True,\"ok\")[0]
assert not d(\"shadow\",\"FAIL\",\"MISMATCH_FAILED\",True,\"ok\")[0]
assert d(\"enforce\",\"PASS\",\"MATCH\",True,\"ok\")==(False,False,\"\")
assert d(\"enforce\",\"NA\",\"\",False,\"missing\")[:2]==(False,True)
assert d(\"enforce\",\"UNVERIFIED\",\"BUILDING\",True,\"ok\")==(True,True,\"BUILDING\")
assert d(\"shadow\",\"UNVERIFIED\",\"BUILDING\",True,\"ok\")[0] is False
assert d(\"enforce\",\"UNVERIFIED\",\"UNVERIFIED\",True,\"ok\")[0] is False
assert d(\"enforce\",\"UNVERIFIED\",\"\",True,\"stale\")[0]
r=d(\"shadow\",\"UNVERIFIED\",\"\",True,\"missing\"); assert r[0] is False and r[1] is True
r=d(\"enforce\",\"UNVERIFIED\",\"\",True,\"ok\"); assert r[0] is False and r[1] is True
'"

# ===== B. post-promote check =====
# B1 detached from the cron critical path: the watcher keeps polling (deploy BUILDING) while promote + a $(...) capture return at once
setup; mkrepo billwatch; snap billwatch "SUCCESS:$(sha billwatch develop)"; SNAP_KIND=prod_deploys snap billwatch "BUILDING:$(git -C $T/origin/billwatch.git rev-parse main)"
EXTRA=(OVN_POSTCHECK_TIMEOUT=6 OVN_POSTCHECK_INTERVAL=1); t0="$(date +%s)"
cap="$(cronenv bash "$Q/promote_to_prod.sh" --yes "$Q/repos/billwatch" 2>&1 < /dev/null)"; t1="$(date +%s)"; printf '%s\n' "$cap" > "$OUT"
psha="$(sha billwatch main)"
ck "B: detached: promote + command-substitution capture return promptly (<4s) while the watcher is still polling" "[ $((t1-t0)) -lt 4 ] && has 'post-promote check started (detached)' && has \"[prod-deploy] billwatch promoted SHA $psha\""
for i in $(seq 1 25); do grep -q UNVERIFIED "$Q/logs/promote_postcheck.log" 2>/dev/null && break; sleep 1; done
ck "B: the detached watcher finished on its own: building never reached a final state => UNVERIFIED line + WARN, NO push" "grep -q 'UNVERIFIED' $Q/logs/promote_postcheck.log && [ \"\$(nalerts 'WARN | promote-postcheck')\" = 1 ] && ! grep -q 'Priority: urgent' $T/curl.log"
# B2 benign: SUCCESS => one log line, no alert, no push
setup; mkrepo billwatch; SNAP_KIND=prod_deploys snap billwatch "SUCCESS:$(git -C $T/origin/billwatch.git rev-parse develop)"
cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash -c "cd $Q/qa && $PYB promote_postcheck.py watch --repo billwatch --sha $(sha billwatch develop) --once" > "$OUT" 2>&1
ck "B-benign: prod deploy SUCCESS => logged SUCCESS, no alerts.log line, no push" "grep -q 'SUCCESS' $Q/logs/promote_postcheck.log && [ \"\$(nalerts promote-postcheck)\" = 0 ] && ! grep -q 'CURL_CALL' $T/curl.log"
# B3 negative: FAILED => emergency push through the relay (urgent) + one ERROR alerts.log line; deduped per (repo, sha)
setup; mkrepo billwatch; D="$(sha billwatch develop)"; SNAP_KIND=prod_deploys snap billwatch "FAILED:$D" "SUCCESS:$(sha billwatch main)"
for i in 1 2; do cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash -c "cd $Q/qa && $PYB promote_postcheck.py watch --repo billwatch --sha $D --once" > "$OUT" 2>&1; done
ck "B-neg: prod deploy FAILED => ONE urgent push to the relay URL, ONE ERROR alerts.log line (second run deduped)" "[ \"\$(grep -c 'Priority: urgent' $T/curl.log)\" = 1 ] && grep 'Priority: urgent' $T/curl.log | grep -q '127.0.0.1:9/selftest_ignore' && [ \"\$(nalerts 'ERROR | promote-postcheck')\" = 1 ] && grep -q 'FAILED' $Q/logs/promote_postcheck.log"
ck "B-neg: the push names the repo and says prod is on the previous build" "grep 'Priority: urgent' $T/curl.log | grep -q 'PROD deploy FAILED after promote: billwatch' && grep -q 'previous build' $T/curl.log"
# B4 a FAILED deploy of an OLDER sha is not ours: no alarm
setup; mkrepo billwatch; D="$(sha billwatch develop)"; SNAP_KIND=prod_deploys snap billwatch "SUCCESS:$D" "FAILED:$(sha billwatch main)"
cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash -c "cd $Q/qa && $PYB promote_postcheck.py watch --repo billwatch --sha $D --once" > "$OUT" 2>&1
ck "B-benign: an older sha's FAILED deploy does not alarm for the promoted sha" "[ \"\$(nalerts ERROR)\" = 0 ] && ! grep -q 'Priority: urgent' $T/curl.log"
# B5 no evidence at all: UNVERIFIED warn, never a push, never a crash
setup; mkrepo billwatch; cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" OVN_POSTCHECK_TIMEOUT=1 bash -c "cd $Q/qa && $PYB promote_postcheck.py watch --repo billwatch --sha $(sha billwatch develop) --once" > "$OUT" 2>&1; echo $? > "$T/rc"
ck "B: no prod evidence => exit 0, UNVERIFIED WARN, no push" "[ \"\$(cat $T/rc)\" = 0 ] && [ \"\$(nalerts 'WARN')\" = 1 ] && ! grep -q 'CURL_CALL' $T/curl.log"
# B5b repos without a Railway prod export are not watched (no permanent 30-min UNVERIFIED WARN)
setup; mkrepo xlite; EXTRA=(OVN_POSTCHECK_TIMEOUT=2 OVN_POSTCHECK_INTERVAL=1); runp --yes "$Q/repos/xlite"; sleep 4
ck "B-benign: promoted repo with no prod export (xlite) => 'no prod deploy source', no watcher, no alerts.log WARN" "has 'PROMOTED xlite' && has 'no prod deploy source for xlite' && ! has 'post-promote check started' && [ ! -e $Q/logs/promote_postcheck.log ] && [ \"\$(nalerts promote-postcheck)\" = 0 ]"
setup; mkrepo billwatch; snap billwatch "SUCCESS:$(sha billwatch develop)"; EXTRA=(OVN_POSTCHECK_TIMEOUT=2 OVN_POSTCHECK_INTERVAL=1); runp --yes "$Q/repos/billwatch"
ck "B-neg: a repo IN the prod export set (billwatch) still starts the watcher" "has 'post-promote check started (detached)'"
sleep 4
# B5c re-promote of a sha whose OLD prod deploy FAILED: the stale row must not raise a false emergency (since-filter), the fresh one must
setup; mkrepo billwatch; D="$(sha billwatch develop)"; SNAP_CREATED_AGE=7200 SNAP_KIND=prod_deploys snap billwatch "FAILED:$D"
cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash -c "cd $Q/qa && $PYB promote_postcheck.py watch --repo billwatch --sha $D --once" > "$OUT" 2>&1
ck "B-benign: an OLD (2h) FAILED deploy of the same sha is ignored by the new watcher: no emergency, no ERROR, UNVERIFIED only" "[ \"\$(nalerts 'ERROR')\" = 0 ] && ! grep -q 'Priority: urgent' $T/curl.log && [ ! -e $Q/state/promote_postcheck/billwatch_\${D:0:10}.done ]"
SNAP_KIND=prod_deploys snap billwatch "FAILED:$D"
cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash -c "cd $Q/qa && $PYB promote_postcheck.py watch --repo billwatch --sha $D --once" > "$OUT" 2>&1
ck "B-neg: a FRESH FAILED deploy of the same sha still pages (the done marker was not burned by the stale row)" "[ \"\$(grep -c 'Priority: urgent' $T/curl.log)\" = 1 ] && [ \"\$(nalerts 'ERROR | promote-postcheck')\" = 1 ]"
# B6 kill switch + dry-run never start it
setup; mkrepo billwatch; snap billwatch "SUCCESS:$(sha billwatch develop)"; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/billwatch"
ck "B: OVN_POSTCHECK=off logs the SHA but starts no watcher" "has '[prod-deploy] billwatch promoted SHA' && ! has 'post-promote check started'"
setup; mkrepo billwatch; snap billwatch "SUCCESS:$(sha billwatch develop)"; runp --dry-run "$Q/repos/billwatch"
ck "B: dry-run starts no watcher and prints no prod-deploy line" "! has '[prod-deploy]' && [ ! -e $Q/logs/promote_postcheck.out ]"

# ===== C. prod alembic ancestry (SHADOW) =====
pac(){ cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash -c "cd $Q/qa && $PYB prod_alembic_check.py check --repo $1 --sha $(sha $1 develop) --no-record" 2>&1 | tail -1; }
rec(){ cronenv OVN_DIR="$Q" QA_STATE_DIR="$Q/state" bash -c "cd $Q/qa && $PYB prod_alembic_check.py record --repo $1 --revision $2" >/dev/null 2>&1; }
jv(){ "$PYB" -c 'import sys,json; d=json.loads(sys.stdin.read()); print(d["verdict"], d["summary"])'; }
setup; mkrepo billwatch ok; rec billwatch 0009; r="$(pac billwatch | jv)"
ck "C-benign: prod at 0009, head 0011 => PASS strict ancestor (2 pending)" "[ \"\${r%% *}\" = PASS ] && echo \"\$r\" | grep -q 'strict ancestor' && echo \"\$r\" | grep -q '2 pending'"
rec billwatch 0011; r="$(pac billwatch | jv)"
ck "C-benign: prod already at head => PASS" "[ \"\${r%% *}\" = PASS ] && echo \"\$r\" | grep -q 'no pending'"
rec billwatch zzz99; r="$(pac billwatch | jv)"
ck "C-neg: prod revision not in the candidate history => FAIL (ahead / diverged)" "[ \"\${r%% *}\" = FAIL ] && echo \"\$r\" | grep -q 'NOT in the candidate'"
rm -rf "$Q/state/prod_alembic"; r="$(pac billwatch | jv)"
ck "C: no prod snapshot => UNVERIFIED (never FAIL)" "[ \"\${r%% *}\" = UNVERIFIED ]"
rec billwatch 0009; "$PYB" -c "
import json,time; p='$Q/state/prod_alembic/billwatch.json'; j=json.load(open(p)); j['fetched_at']=time.time()-200000; json.dump(j,open(p,'w'))"; r="$(pac billwatch | jv)"
ck "C: stale prod snapshot (>24h) => UNVERIFIED" "[ \"\${r%% *}\" = UNVERIFIED ] && echo \"\$r\" | grep -q stale"
setup; mkrepo plain; r="$(pac plain | jv)"
ck "C: repo without alembic => NA" "[ \"\${r%% *}\" = NA ]"
setup; mkrepo iptv_apps norev; rec iptv_apps 0010; r="$(pac iptv_apps | jv)"
ck "C-neg: the 0011 incident (docstring-only migration, no revision) => FAIL even with a good prod snapshot" "[ \"\${r%% *}\" = FAIL ] && echo \"\$r\" | grep -q 'without a revision id' && echo \"\$r\" | grep -q 0011_c.py"
rm -rf "$Q/state/prod_alembic"; r="$(pac iptv_apps | jv)"
ck "C-neg: the structural FAIL needs no prod snapshot" "[ \"\${r%% *}\" = FAIL ]"
# through the promote: shadow => WARN once per (repo, sha), promote STILL happens
setup; mkrepo iptv_apps norev; snap iptv_apps "SUCCESS:$(sha iptv_apps develop)"; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/iptv_apps"
ck "C-neg: promote shows [prod-alembic] FAIL (shadow), ONE alerts.log WARN, and still PROMOTES" "has '[prod-alembic] FAIL (shadow)' && has 'PROMOTED iptv_apps' && [ \"\$(nalerts 'promote-prod-alembic')\" = 1 ]"
setup; mkrepo billwatch ok; snap billwatch "SUCCESS:$(sha billwatch develop)"; rec billwatch 0009; EXTRA=(OVN_POSTCHECK=off); runp --yes "$Q/repos/billwatch"
ck "C-benign: healthy chain => [prod-alembic] PASS, no alerts" "has '[prod-alembic] PASS (shadow)' && [ \"\$(nalerts promote-prod-alembic)\" = 0 ]"

# ===== D. smoke PROVENANCE =====
cat > "$T/shim/curl_smoke" <<'STUB'
#!/usr/bin/env bash
w=""; d=0; prev=""
for a in "$@"; do [ "$prev" = "-w" ] && w="$a"; [ "$prev" = "-D" ] && d=1; prev="$a"; done
if [ "$d" = 1 ]; then printf 'HTTP/1.1 200 OK\r\n\r\n'; exit 0; fi
case "$w" in *http_code*) printf 200;; *content_type*) printf application/json;; *) printf '%s' "${STUB_BODY:-}";; esac
STUB
chmod +x "$T/shim/curl_smoke"; mkdir -p "$T/smokebin"; cp "$T/shim/curl_smoke" "$T/smokebin/curl"
sm(){ PATH="$T/smokebin:$PATH" bash "$OQ/staging_smoke.sh" https://b.example > "$OUT" 2>&1; echo $? > "$T/rc"; }
setup; mkrepo app; E="$(sha app develop)"; M="$(sha app main)"
STUB_BODY="{\"status\":\"ok\",\"commit\":\"$M\"}" STAGING_EXPECT_SHA="$E" sm
ck "D-neg: /health serves the OLD commit (healthy but stale) => smoke FAILS with the provenance message" "[ \"\$(cat $T/rc)\" = 1 ] && has 'provenance' && has 'STALE deploy' && has 'SMOKE FAIL'"
STUB_BODY="{\"status\":\"ok\",\"git_sha\":\"$E\"}" STAGING_EXPECT_SHA="$E" sm
ck "D-benign: /health serves the candidate => smoke passes with a provenance tick" "[ \"\$(cat $T/rc)\" = 0 ] && has 'provenance: staging serves the candidate'"
STUB_BODY="{\"status\":\"ok\",\"commit\":\"$E\"}" STAGING_EXPECT_SHA="${E:0:12}" sm
ck "D-benign: short candidate prefix matches" "[ \"\$(cat $T/rc)\" = 0 ]"
STUB_BODY="{\"status\":\"ok\"}" STAGING_EXPECT_SHA="$E" sm
ck "D: /health without a commit field => says UNVERIFIED out loud, does not fail" "[ \"\$(cat $T/rc)\" = 0 ] && has 'provenance UNVERIFIED' && has 'SMOKE PASS'"
mkdir -p "$T/clone"; git clone -q "$T/origin/app.git" "$T/clone/app" 2>/dev/null; git -C "$T/clone/app" fetch -q origin
( cd "$T/seed/app" && git checkout -q develop && echo newer > newer.txt && git add newer.txt && git commit -q -m newer && git push -q origin develop ); git -C "$T/clone/app" fetch -q origin; N="$(sha app develop)"
STUB_BODY="{\"status\":\"ok\",\"commit\":\"$N\"}" STAGING_EXPECT_SHA="$E" STAGING_REPO_DIR="$T/clone/app" sm
ck "D-benign: staging serves a NEWER commit that contains the candidate (clone given) => passes" "[ \"\$(cat $T/rc)\" = 0 ] && has 'contains the candidate'"
STUB_BODY="{\"status\":\"ok\",\"commit\":\"$M\"}" STAGING_EXPECT_SHA="$E" STAGING_REPO_DIR="$T/clone/app" sm
ck "D-neg: with the clone, an OLDER served commit still FAILS" "[ \"\$(cat $T/rc)\" = 1 ] && has 'STALE deploy'"
# staging_smoke.py provenance step (pure)
ck "staging_smoke.py: provenance step fail / ok / na" "cd $Q/qa && cp $QA/staging_smoke.py . && cp $QA/staging_smoke.conf . 2>/dev/null; $PYB -c '
import staging_smoke as s
def run(j, exp):
    r = s.Run(\"billwatch\", \"https://x-staging.up.railway.app\", {}, {}); r.health_json = j; return r.provenance(exp)
assert run({\"commit\": \"a\"*40}, \"b\"*40) == \"fail\"
assert run({\"commit\": \"abcdef1234567\"}, \"abcdef1234567890\") == \"ok\"
assert run({\"status\": \"ok\"}, \"b\"*40) == \"na\"
assert run(None, \"b\"*40) == \"na\"
'"
setup; mkrepo app
# the promote passes the candidate to the smoke: stub curl in $T/shim reports a commit via the -w-less call
cat > "$T/shim/curl" <<'STUB'
#!/bin/sh
case "$*" in *http_code*) printf 200;; *content_type*) printf application/json;; *-D*) printf 'HTTP/1.1 200 OK\r\n\r\n';; *) printf '{"commit":"%s"}' "$FAKE_SERVED";; esac
STUB
chmod +x "$T/shim/curl"; m0="$(sha app main)"
echo "https://back.example" > "$Q/state/staging_url_app"; snap app "SUCCESS:$(sha app develop)"; EXTRA=(OVN_POSTCHECK=off FAKE_SERVED="$(sha app main)"); runp --yes "$Q/repos/app"
ck "D-neg (end to end): the promote's smoke gets the candidate sha and REFUSES the stale-serving staging" "has 'provenance' && has 'smoke failed' && ! has 'PROMOTED' && [ \"\$(sha app main)\" = $m0 ]"
EXTRA=(OVN_POSTCHECK=off FAKE_SERVED="$(sha app develop)"); runp --yes "$Q/repos/app"
ck "D-benign (end to end): staging serving the candidate promotes" "has 'provenance: staging serves the candidate' && has 'PROMOTED app'"
printf '#!/bin/sh\necho "CURL_CALL $*" >> "$FAKE_CURL_LOG"\nexit 0\n' > "$T/shim/curl"

# ===== E. deploy_watch.sh =====
DW="$OQ/deploy_watch.sh"; FX="$T/fx"
ck "E: ripple / social-media-manager / task-manager are no longer monitored" "! grep -qE '^(ripple|task-manager|social)[a-z-]*\\|' $DW && ! grep -qE '^[a-z-]+\\|(social-media-manager|task-manager-platform)\\|' $DW"
ck "E: the 3 Railway STAGING services are in SURFACES (alert-only, fleet=0)" "[ \"\$(grep -cE '^[a-z]+-staging\\|[a-z_]+\\|.*\\|railway\\|[0-9a-f-]+:staging:[0-9a-f-]+\\|.*\\|0\$' $DW)\" = 3 ]"
dwsetup(){ rm -rf "$T/dwhome" "$FX"; mkdir -p "$T/dwhome" "$FX"; unset RW_ST_STAGING RW_ST_PROD RW_SHA_STAGING RW_SHA_PROD RW_ID_STAGING RW_ID_PROD; }
curl(){ echo "curl $*" >> "$FX/curl.log"; [ -e "$FX/curl_fail" ] && return 22; case "$*" in *ntfy.sh*|*127.0.0.1*) return 0;; *"%{http_code}"*) printf 200;; esac; return 0; }
ssh(){ echo "ssh $*" >> "$FX/ssh.log"; cat > /dev/null 2>&1 < /dev/null; local a; for a in "$@"; do case "$a" in ITEM_B64=*) printf '%s' "${a#ITEM_B64=}" | base64 -d >> "$FX/items.log"; echo >> "$FX/items.log";; esac; done; echo enqueued; return 0; }
railway(){ echo "railway $*" >> "$FX/rw.log"
  local env="" a prev="" which=PROD sid=""
  for a in "$@"; do [ "$prev" = "--environment" ] && env="$a"; [ "$prev" = "--service" ] && sid="$a"; prev="$a"; done
  [ "$env" = staging ] && which=STAGING
  case "$1" in link) return 0;; deployment)
    local vs="RW_ST_$which" vsha="RW_SHA_$which" vid="RW_ID_$which"
    printf '[{"id":"%s","status":"%s","meta":{"commitHash":"%s"}}]\n' "${!vid:-dep1}" "${!vs:-SUCCESS}" "${!vsha:-aaaaaaaaaaaa}";; logs) echo "boom";; esac; }
vercel(){ echo "vercel $*" >> "$FX/vc.log"; case "$1" in ls) echo "  https://${2}-x1.vercel.app Ready";; inspect) echo "    status      ● Ready";; esac; }
export -f curl ssh railway vercel; export FX
dw(){ HOME="$T/dwhome" NTFY_TOPIC=selftest bash "$DW" > "$FX/out.log" 2>&1; echo $? > "$FX/rc"; }
urg(){ local n; n="$(grep -c "Priority: urgent" "$FX/curl.log" 2>/dev/null)"; echo "${n:-0}"; }
hi(){ local n; n="$(grep -c "Priority: high" "$FX/curl.log" 2>/dev/null)"; echo "${n:-0}"; }
al(){ local n; n="$(grep -c "$1" "$T/dwhome/.deploy_watch/alerts.log" 2>/dev/null)"; echo "${n:-0}"; }
dwsetup; dw
ck "E-benign: everything healthy => no urgent push, no alerts.log, no enqueue" "[ \"\$(cat $FX/rc)\" = 0 ] && [ \"\$(urg)\" = 0 ] && [ ! -e $T/dwhome/.deploy_watch/alerts.log ] && [ ! -s $FX/items.log ]"
ck "E: staging env is polled via the railway CLI (--environment staging) for all 3 services" "[ \"\$(grep -c 'deployment list.*--environment staging' $FX/rw.log)\" = 3 ] && ! grep -q 'social-media-manager' $FX/vc.log"
ck "E: staging OK lines logged" "grep -q 'billwatch-staging: OK' $FX/out.log && grep -q 'gitlark-staging: OK' $FX/out.log"
# staging FAILED
dwsetup; export RW_ST_STAGING=FAILED RW_SHA_STAGING=da4caaf42c76be991fd0fff04c05fea211773e98 RW_ID_STAGING=f5ab74c4; dw
ck "E-neg: staging FAILED => ONE high-priority push per repo (3 services), each naming 'staging'; NOT urgent (the promote gate holds the repo)" "[ \"\$(hi)\" = 3 ] && [ \"\$(urg)\" = 0 ] && grep 'Priority: high' $FX/curl.log | grep -q 'staging deploy FAILED'"
ck "E-neg: ONE alerts.log line per repo with the sha" "[ \"\$(al 'ERROR | deploy-watch | iptv_apps staging deploy FAILED (sha da4caaf42c')\" = 1 ] && [ \"\$(al 'ERROR | deploy-watch')\" = 3 ]"
ck "E-neg: the alerts.log line is also sent to the box (best-effort ssh)" "[ \"\$(grep -c 'alerts.log' $FX/ssh.log)\" -ge 3 ]"
ck "E: staging FAILED is alert-only: nothing enqueued from deploy_watch" "[ ! -s $FX/items.log ]"
dw
ck "E: same deploy again => no second push, no second line" "[ \"\$(hi)\" = 3 ] && [ \"\$(al 'ERROR | deploy-watch')\" = 3 ]"
RW_ID_STAGING=f5ab74c5 dw
ck "E: NEW deploy id, SAME broken sha => still deduped per (repo, env, sha)" "[ \"\$(hi)\" = 3 ] && [ \"\$(al 'ERROR | deploy-watch')\" = 3 ]"
RW_ID_STAGING=f5ab74c6 RW_SHA_STAGING=9f66e8dbabc762fbc9891fa26dfa7bf2c9403f1a dw
ck "E: a different failing sha => a fresh emergency (3 more)" "[ \"\$(hi)\" = 6 ] && [ \"\$(al 'ERROR | deploy-watch')\" = 6 ]"
RW_ST_STAGING=SUCCESS dw
ck "E: staging recovers => recovery ping is low priority, not urgent" "grep -q 'Priority: low' $FX/curl.log && [ \"\$(urg)\" = 0 ]"
# the dedupe marker is written only after the push worked: a failed push is retried on the next run (and alerts.log is not duplicated meanwhile)
dwsetup; export RW_ST_STAGING=FAILED RW_SHA_STAGING=aaaabbbbccccddddeeeeffff00001111 RW_ID_STAGING=z1; touch "$FX/curl_fail"; dw
ck "E-neg: push FAILS (network) => NO dedupe marker is written, failure logged" "[ -z \"\$(ls $T/dwhome/.deploy_watch/ | grep '^emerg_.*staging_aaaabbbb[0-9a-f]*$')\" ] && grep -q 'emergency push FAILED' $FX/out.log"
rm -f "$FX/curl_fail"; RW_ID_STAGING=z2 dw
ck "E-benign: next run retries the push (3 pushes), writes the marker, alerts.log has ONE line per repo (not duplicated by the retry)" "[ \"\$(ls $T/dwhome/.deploy_watch/ | grep -c '^emerg_.*staging_aaaabbbb[0-9a-f]*$')\" = 3 ] && [ \"\$(al 'ERROR | deploy-watch')\" = 3 ]"
RW_ID_STAGING=z3 dw
ck "E: after the successful retry no further push" "[ \"\$(grep -c 'Priority: high' $FX/curl.log)\" = 6 ]"
# prod FAILED: still enqueues the model fix (other track owns that logic) AND now pushes an emergency
dwsetup; export RW_ST_PROD=FAILED RW_SHA_PROD=deadbeefdeadbeef RW_ID_PROD=p1; dw
ck "E-neg: prod FAILED => urgent emergency per backend + alerts.log line with 'prod'" "[ \"\$(grep 'Priority: urgent' $FX/curl.log | grep -c 'prod deploy FAILED')\" = 3 ] && [ \"\$(al 'ERROR | deploy-watch | billwatch prod deploy FAILED (sha deadbeefde')\" = 1 ]"
ck "E: prod FAILED still enqueues the fix item for the fleet repos (existing behaviour kept)" "[ \"\$(grep -c 'EMERGENCY DEPLOY FIX' $FX/items.log)\" = 3 ]"
dw
ck "E: prod same sha again => no second emergency" "[ \"\$(grep 'Priority: urgent' $FX/curl.log | grep -c 'prod deploy FAILED')\" = 3 ]"
dwsetup; DRYRUN=1 HOME="$T/dwhome" bash -c 'export RW_ST_PROD=FAILED RW_SHA_PROD=cafebabecafebabe RW_ID_PROD=p9; bash '"$DW" > "$FX/out.log" 2>&1
ck "E: DRYRUN prints the would-be alerts.log line and sends/writes nothing" "grep -q '\\[alerts.log\\] .*prod deploy FAILED' $FX/out.log && [ ! -e $T/dwhome/.deploy_watch/alerts.log ] && ! grep -q 'Priority' $FX/curl.log 2>/dev/null"
/bin/bash -n "$DW" && ck "E: deploy_watch.sh parses under /bin/bash (the Mac runs it with 3.2 or 5)" "true" || ck "E: bash -n" "false"
unset -f curl ssh railway vercel

# ===== F. qa_daily_shadow.sh --staging-only =====
setup; mkrepo iptv_apps; mkrepo billwatch; snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$(sha iptv_apps main)"; snap billwatch "SUCCESS:$(sha billwatch develop)"
shd(){ cronenv OVN_DIR="$Q" QA_DAILY_STAGING_REPOS="iptv_apps billwatch" QA_GATE_TIMEOUT=60 bash "$Q/qa/qa_daily_shadow.sh" --staging-only > "$OUT" 2>&1; echo $? > "$T/rc"; }
shd; shd
ck "F-neg: staging FAIL => ONE alerts.log WARN for iptv_apps across two hourly runs (deduped per candidate sha)" "[ \"\$(nalerts 'WARN | qa-staging-check | iptv_apps candidate')\" = 1 ] && grep -q 'MISMATCH_FAILED' $Q/state/alerts.log"
ck "F-benign: the MATCH repo raises nothing" "[ \"\$(nalerts billwatch)\" = 0 ] && [ \"\$(cat $T/rc)\" = 0 ]"
ck "F: --staging-only skips the release_candidate loop" "! grep -q 'release_candidate' $Q/logs/qa_daily_shadow.log && grep -q 'staging_check iptv_apps: FAIL' $Q/logs/qa_daily_shadow.log"
( cd "$T/seed/iptv_apps" && git checkout -q develop && git checkout -q -b feat2 && echo more > more.txt && git add more.txt && git commit -q -m "feat: two" && git checkout -q develop && git merge -q --no-ff -m "$GREEN" feat2 && git push -q origin develop ); git -C "$Q/repos/iptv_apps" fetch -q origin; snap iptv_apps "FAILED:$(sha iptv_apps develop)" "SUCCESS:$(sha iptv_apps main)"; shd
ck "F: a NEW candidate sha failing => a second WARN (per-sha, not per-repo-forever)" "[ \"\$(nalerts 'WARN | qa-staging-check | iptv_apps candidate')\" = 2 ]"
ck "F: hourly cron line exists in the (uninstalled) cron file with the relay NTFY_SERVER" "grep -qE '^20 \\* \\* \\* \\* NTFY_SERVER=http://127.0.0.1:8099 .*qa_daily_shadow.sh --staging-only' $QA/promote_alerting_cron.txt"

echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
