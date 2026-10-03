#!/usr/bin/env bash
# Kotlin / legacy bug grounding in the REAL ovn_stage_runner.sh (2026-10-03, A8, branch qa/h11-bug-pipeline). Real failures reproduced (Chickadee, 10-03):
#   * 6 staged bug runs landed nothing: a NEW file re-declared a type that already exists (GroupedCategories.kt vs CategoryModels.kt: Kotlin 'Redeclaration' only at
#     the final verify, 15-25 min later), the test invented members of Stream/StreamType and used mockito-kotlin (not a dependency).
#   * the plan was re-made by the model on every attempt (3,2,4,2,1,2 steps for the same bug) and stored a step saying 'No change required'.
#   * bugs enqueued before the brief stage was deployed carry no brief (all 7 of 10-01); the escalation row said only 'staged landed 0 of 2'.
# D  duplicate-type step rejected + re-prompted with the REAL definition   |  K  real definitions + testImplementation lines injected into a Kotlin test step
# P  first plan persisted + reused on attempt 2, removed at escalation       |  V  'no change required' steps dropped; an all-vacuous plan counts as an attempt
# L  lazy bug brief on the first attempt (bounded, fail-safe)                |  E  escalation row + relay body carry the verify error and the run id
# O  OVN_BUG_FIRST=off restores the old behaviour for every one of the above
# Every behavior has a NEGATIVE control (the seeded bad input is caught) and a BENIGN control (clean input passes). Run on the box / any GNU host.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed (the escalation helper uses sed -i); run on the box"; exit 0; fi
for b in jq md5sum timeout pgrep python3; do command -v "$b" >/dev/null 2>&1 || { echo "  SKIP: needs $b"; exit 0; }; done
unset OVN_BUG_FIRST OVN_BUG_FOCUS OVN_BUG_ATTEMPT_CAP OVN_GUARD_ATTEMPTS NTFY_SERVER NTFY_TOPIC OVN_BUG_BRIEF_DIR OVN_BUG_BRIEF OVN_BUG_LAZY_BRIEF OVN_ITEM_FAIL_CAP OVN_ITEM_NOOP_CAP OVN_ITEM_TOKEN_CAP
# the box runs a LIVE fleet: only OUR marker process may count as 'another LLM consumer' in this test
export OVN_BUG_LAZY_BRIEF_BUSY_RE='ovn_prework\.sh'
tmp="$(mktemp -d)"; BGPID=""; trap 'rm -rf "$tmp"; osr_cleanup; [ -n "$BGPID" ] && kill "$BGPID" 2>/dev/null' EXIT
KT=android/app/src/main/java/com/x
FEAT=osr-20261001-manual-aaaa1111
BUGKT="[T3] $KT/ui/StreamsViewModel.kt — Manual-test bug (reported by Mark, flow countries-filter, 2026-10-01): the countries filter only shows All and Qatar. First write a failing test that reproduces this, then fix it. VERIFY: \`cd android && ./gradlew testDebugUnitTest\` (cat:bugfix; multifile:no; src:manual) [feat:$FEAT]"
BUGKT_MF="${BUGKT//multifile:no/multifile:yes}"      # the D2 controls create several new files on purpose
withlibs(){ cp "$REALQ/scripts/lib_item_select.sh" "$REALQ/scripts/lib_bug_escalate.sh" "$REALQ/scripts/ovn_repeat_ids.py" "$Q/scripts/"; mkdir -p "$Q/qa"; cp "$REALQ/qa/bug_ground.py" "$Q/qa/"; }
kotlin_repo(){
  osr_tracked "$KT/models/CategoryModels.kt" 'package com.x.models\n\ndata class GroupedCategories(\n    val countries: List<String>,\n    val genres: List<String>\n)\n\nenum class StreamType { LIVE, MOVIE }\n'
  osr_tracked "$KT/ui/StreamsViewModel.kt" 'package com.x.ui\n\nimport com.x.models.GroupedCategories\n\nclass StreamsViewModel {\n    fun load(): GroupedCategories? = null\n}\n'
  osr_tracked android/app/build.gradle.kts 'plugins { id("com.android.application") }\ndependencies {\n    testImplementation("junit:junit:4.13.2")\n    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.0")\n    implementation("androidx.core:core-ktx:1.12.0")\n}\n'
}
SNIP_OK="mkdir -p $KT/ui
printf 'package com.x.ui\nimport com.x.models.GroupedCategories\nclass StreamsViewModel { fun load(): GroupedCategories? = null\n  fun filterFixed() = 1 }\n' > $KT/ui/StreamsViewModel.kt
printf 'package com.x.ui\nclass StreamsViewModelTest { fun t() { check(StreamsViewModel().filterFixed() == 1) } }\n' > $KT/ui/StreamsViewModelTest.kt
echo 'Applied edit to StreamsViewModel.kt'"
SNIP_DUP="mkdir -p $KT/models $KT/ui
printf 'package com.x.models\ndata class GroupedCategories(val a: Int)\n' > $KT/models/GroupedCategories.kt
printf 'package com.x.ui\nclass StreamsViewModelTest { fun t() { check(true) } }\n' > $KT/ui/StreamsViewModelTest.kt
echo 'Applied edit to GroupedCategories.kt'"
plan1(){ printf '[{"desc":"%s","files":["%s","%s"],"verify":"cd android && ./gradlew testDebugUnitTest"}]' "$1" "$KT/ui/StreamsViewModel.kt" "$KT/ui/StreamsViewModelTest.kt"; }
J(){ osr_jsonl | grep -qF -- "$1"; }
args_has(){ grep -qF -- "$2" "$T/scn/aider.args.$1" 2>/dev/null; }
newfix(){ osr_new; withlibs; osr_venv backend; kotlin_repo; }
bugcount(){ cat "$Q"/state/item_fails/stage-"$OSR_REPO".*.bugcount 2>/dev/null; }

echo "=== D: a step that creates a new file re-declaring an existing type ==="
newfix; osr_progress "- [ ] $BUGKT"
osr_plan 1 "$(plan1 'add a filter test and fix the countries filter')"
osr_aider 1 "$SNIP_DUP"; osr_aider 2 "$SNIP_OK"
osr_run "$OSR_REPO"
t "NEGATIVE: attempt 1 is REJECTED as duplicate-type (not left for the final verify)" J '"fail_reason":"duplicate-type"'
t "the rejection is logged with the offending type" grep -q 'REJECTED (duplicate type)' "$T/out.txt"
t "the re-prompt of attempt 2 carries the REAL definition of GroupedCategories" args_has 2 'data class GroupedCategories('
t "... including its real members" args_has 2 'val countries: List<String>'
t "... and tells the model not to create the file" args_has 2 'Do NOT create'
t "attempt 1 had no re-prompt text yet" bash -c "! grep -qF 'Do NOT create' '$T/scn/aider.args.1'"
t "attempt 2 (edits only existing files) PASSES and lands" J '"passed":1,"total":1'
t "the duplicate file never reached origin" bash -c "! git -C '$O' ls-tree -r --name-only overnight/feature | grep -q 'models/GroupedCategories.kt'"
osr_cleanup

echo "=== D2: benign controls (clean new file; same simple name in ANOTHER package; private class) ==="
newfix; osr_progress "- [ ] $BUGKT_MF"
osr_plan 1 "$(plan1 'add a filter test and fix the countries filter')"
osr_aider 1 "mkdir -p $KT/ui $KT/other
printf 'package com.x.ui\nclass StreamsViewModel { fun filterFixed() = 1 }\n' > $KT/ui/StreamsViewModel.kt
printf 'package com.x.ui\nimport com.x.models.GroupedCategories\nclass StreamsViewModelTest { fun t() { check(StreamsViewModel().filterFixed() == 1) } }\n' > $KT/ui/StreamsViewModelTest.kt
printf 'package com.x.ui\ndata class BrandNewThing(val a: Int)\n' > $KT/ui/BrandNewThing.kt
printf 'package com.x.other\ndata class GroupedCategories(val z: Int)\n' > $KT/other/GroupedCategories.kt
printf 'package com.x.models\nprivate class StreamType\n' > $KT/ui/PrivateStreamType.kt
echo 'Applied edit'"
osr_run "$OSR_REPO"
t "BENIGN: new type / other package / private class => no duplicate-type rejection" bash -c "! grep -q 'duplicate-type' <(cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl)"
t "BENIGN: the step passes on attempt 1" J '"passed":1,"total":1'
osr_cleanup

echo "=== V2/D3: review fixes - vacuous-step anchoring; nested / other-source-set declarations are legal ==="
BG="$REALQ/qa/bug_ground.py"
fs(){ printf '%s' "$1" | python3 "$BG" filter-steps | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))'; }
for d in 'Write a failing test; no changes to production code are required yet' 'Add filterCountries() to StreamsViewModel so that no change is needed in the UI layer' 'Update the adapter (no modifications required to the Fragment)' 'Add the missing enum entry; nothing to change in the repository'; do
  t "BENIGN: a real step that merely mentions 'no change needed' is KEPT: ${d:0:48}" bash -c "[ \"\$(printf '[{\"desc\":\"%s\"}]' '$d' | python3 '$BG' filter-steps | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')\" = 1 ]"
done
t "NEGATIVE: 'No other changes required.' is still dropped" bash -c "[ \"\$(printf '[{\"desc\":\"No other changes required.\"}]' | python3 '$BG' filter-steps | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')\" = 0 ]"
t "NEGATIVE: 'Step 2: nothing to change here' is still dropped" bash -c "[ \"\$(printf '[{\"desc\":\"Step 2: nothing to change here\"}]' | python3 '$BG' filter-steps | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')\" = 0 ]"
dr="$tmp/dupes"; rm -rf "$dr"; mkdir -p "$dr/app/src/main/java/com/x" "$dr/app/src/test/java/com/x" "$dr/other/src/main/java/com/x"
printf 'package com.x
class Outer {
    data class Stream(val a: Int)
}
data class Mode(val m: Int)
class RealTop
' > "$dr/app/src/main/java/com/x/Outer.kt"
printf 'package com.x
data class Mode(val m: Int)
' > "$dr/other/src/main/java/com/x/Mode.kt"
git -C "$dr" init -q && git -C "$dr" add . && git -C "$dr" -c user.email=t@t -c user.name=t commit -q -m i
printf 'package com.x
data class Stream(val b: Int)
' > "$dr/app/src/main/java/com/x/Stream.kt"
printf 'package com.x
data class Mode(val z: Int)
' > "$dr/app/src/test/java/com/x/Mode.kt"
t "BENIGN: a new top-level Stream next to a NESTED Outer.Stream + a test-source Mode => not a duplicate" bash -c "[ -z \"\$(python3 '$BG' dupes --wt '$dr' 2>/dev/null)\" ]"
printf 'package com.x
class RealTop
' > "$dr/app/src/main/java/com/x/RealTop2.kt"
t "NEGATIVE: a new same-module top-level RealTop IS still rejected" bash -c "python3 '$BG' dupes --wt '$dr' 2>/dev/null | grep -q 'ALREADY EXIST'"

echo "=== K: real definitions + the module's testImplementation lines in a Kotlin TEST step ==="
newfix; osr_progress "- [ ] $BUGKT"
osr_plan 1 "$(plan1 'add a test for the filter and fix it')"
osr_aider 1 "$SNIP_OK"
osr_run "$OSR_REPO"
t "the step prompt carries the REAL GroupedCategories definition (found through the types the source file uses)" args_has 1 'val genres: List<String>'
t "... and the real StreamType enum is NOT injected unless a file/desc names it" bash -c "! grep -qF 'enum class StreamType' '$T/scn/aider.args.1'"
t "the module's real test dependencies are listed" args_has 1 'kotlinx-coroutines-test'
t "... only testImplementation lines (the implementation line is not a test dependency)" bash -c "! grep -qF 'core-ktx' '$T/scn/aider.args.1'"
t "... with the warning that anything else does not resolve" args_has 1 'mockito-kotlin'
osr_cleanup
newfix; osr_progress "- [ ] $BUGKT"
printf '%s' "[{\"desc\":\"fix the filter in StreamType handling\",\"files\":[\"$KT/ui/StreamsViewModel.kt\"],\"verify\":\"x\"}]" > "$T/llm/plan.1"
osr_aider 1 "$SNIP_OK"
osr_run "$OSR_REPO"
t "NEGATIVE-control: a SOURCE-only (non-test) step gets no Kotlin test context" bash -c "! grep -qF 'testImplementation' '$T/scn/aider.args.1'"
t "... but a type its desc names is not injected either (no test => no ctx)" bash -c "! grep -qF 'REAL definitions' '$T/scn/aider.args.1'"
osr_cleanup

echo "=== P: the first plan is persisted and reused on attempt 2 ==="
newfix; osr_progress "- [ ] $BUGKT"; echo "topic-p" > "$Q/state/ntfy_topic"
PLAN_A="$(plan1 'PLAN-A the first plan step')"
PLAN_B="$(plan1 'PLAN-B a different second plan')"
stuck(){ rm -f "$T/llm/n" "$T/scn/aider.n"; osr_plan 1 "$1"; osr_plan 2 '[{"desc":"only one sub","files":["x.kt"],"verify":"v"}]'; osr_run "$OSR_REPO"; }
stuck "$PLAN_A"
t "attempt 1 persisted its plan (state/bug_plans/<hash>.json)" bash -c "[ \"\$(ls '$Q'/state/bug_plans/*.json | wc -l | tr -d ' ')\" = 1 ] && grep -q 'PLAN-A' '$Q'/state/bug_plans/*.json"
t "attempt 1: one attempt counted" bash -c "[ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount)\" = 1 ]"
stuck "$PLAN_B"
t "attempt 2 REUSED the persisted plan (the model's new PLAN-B was never used)" bash -c "grep -q 'reusing the plan persisted' '$T/out.txt'"
t "... the journal of attempt 2 shows PLAN-A as the plan" bash -c "grep -h '\"event\":\"decomposed\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | tail -1 | grep -q 'PLAN-A' && ! grep -h '\"event\":\"decomposed\"' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl | tail -1 | grep -q 'PLAN-B'"
t "attempt 2 reached the cap: escalated, and the persisted plan is removed with it" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'bug-escalated: 2 failed attempts' && [ -z \"\$(ls '$Q'/state/bug_plans/*.json 2>/dev/null)\" ]"
osr_cleanup
# benign: the plan of a bug that LANDS is removed too, and a stale / corrupt plan file is ignored (fresh decompose)
newfix; osr_progress "- [ ] $BUGKT"
mkdir -p "$Q/state/bug_plans"; h="$(printf '%s' "$BUGKT" | md5sum | cut -d' ' -f1)"; echo 'not json {' > "$Q/state/bug_plans/$h.json"
osr_plan 1 "$(plan1 'PLAN-FRESH decompose')"; osr_aider 1 "$SNIP_OK"
osr_run "$OSR_REPO"
t "BENIGN: a corrupt persisted plan is ignored (fresh decompose, run lands)" bash -c "! grep -q 'reusing the plan persisted' '$T/out.txt'"
t "... and it landed" J '"passed":1,"total":1'
t "... and its plan file is gone after the full pass" bash -c "[ ! -e '$Q/state/bug_plans/$h.json' ]"
osr_cleanup

echo "=== V: 'no change required' steps ==="
newfix; osr_progress "- [ ] $BUGKT"
osr_plan 1 "[{\"desc\":\"No change required in this file as it is a data model; the fix is server-side\",\"files\":[\"$KT/models/CategoryModels.kt\"],\"verify\":\"x\"}]"
osr_run "$OSR_REPO"
t "NEGATIVE: an all-vacuous plan => decompose produced no steps" grep -q 'decompose produced no steps' "$T/out.txt"
t "... counted as an attempt (the MODEL had nothing; it escalates at the cap instead of looping forever)" bash -c "[ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount)\" = 1 ]"
t "... and the bug line stays OPEN, not AUTO-SKIPped" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[T3\] ' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q AUTO-SKIP"
osr_cleanup
newfix; osr_progress "- [ ] $BUGKT"
osr_plan 1 "[{\"desc\":\"Nothing to change in the model file\",\"files\":[\"$KT/models/CategoryModels.kt\"],\"verify\":\"x\"},{\"desc\":\"fix the countries filter and add its test\",\"files\":[\"$KT/ui/StreamsViewModel.kt\",\"$KT/ui/StreamsViewModelTest.kt\"],\"verify\":\"v\"}]"
osr_aider 1 "$SNIP_OK"
osr_run "$OSR_REPO"
t "BENIGN: the vacuous step is dropped, the real one runs (1 step)" J '"event":"decomposed","steps":1'
t "BENIGN: and lands" J '"passed":1,"total":1'
osr_cleanup
newfix; osr_progress "- [ ] $BUGKT"; touch "$T/llm/fail"
osr_run "$OSR_REPO"
t "BENIGN: an LLM outage (empty reply) is NOT counted as a bug attempt (infra failure)" bash -c "grep -q 'decompose produced no steps' '$T/out.txt' && [ -z \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount 2>/dev/null)\" ]"
osr_cleanup

echo "=== L: lazy bug brief ==="
STUB_INGEST='#!/usr/bin/env python3
import json, os, subprocess, sys
a = sys.argv[1:]
q = os.environ["OVN_DIR"]
open(os.path.join(q, "state", "brief.calls"), "a").write(" ".join(a) + "\n")
if os.environ.get("STUB_BRIEF_FAIL"):
    sys.exit(3)
rd = os.path.join(q, "repos", "osrrepo")
feat = "osr-20261001-manual-aaaa1111"
os.makedirs(os.path.join(q, "state", "bug_briefs"), exist_ok=True)
json.dump({"status": "ok"}, open(os.path.join(q, "state", "bug_briefs", feat + ".json"), "w"), indent=1)
g = lambda *x: subprocess.run(["git", "-C", rd] + list(x), capture_output=True)
g("fetch", "-q", "origin", "overnight/feature"); g("reset", "-q", "--hard", "origin/overnight/feature")
p = os.path.join(rd, "OVERNIGHT_PROGRESS.md")
t = open(p).read().split("\n")
out = []
for l in t:
    if "[feat:" + feat + "]" in l and l.startswith("- [ ] "):
        out.append(l.replace("flow countries-filter", "flow countries-filter (brief:1/2)", 1))
        out.append(l.replace("flow countries-filter", "flow countries-filter (brief:2/2)", 1))
    else:
        out.append(l)
open(p, "w").write("\n".join(out))
g("add", "OVERNIGHT_PROGRESS.md"); g("-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "brief"); g("push", "-q", "origin", "HEAD:overnight/feature")
'
lazy_fix(){ newfix; osr_progress "- [ ] $BUGKT"; printf '%s' "$STUB_INGEST" > "$Q/qa/manual_notes_ingest.py"
  printf '{"entries":{"abc123":{"id":"abc123","feat":"%s","status":"%s"}}}' "$FEAT" "${1:-open}" > "$Q/state/manual_notes.json"
  osr_plan 1 "$(plan1 'add a filter test and fix the countries filter')"; osr_aider 1 "$SNIP_OK"; }
lazy_fix
osr_run "$OSR_REPO"
t "an un-briefed OPEN bug is briefed on its first attempt (exactly one 'brief --id abc123 --force' call)" bash -c "[ \"\$(cat '$Q/state/brief.calls')\" = 'brief --id abc123 --force' ]"
t "... the run re-picked and LANDED the brief's first step (step 1/2 checked off, step 2/2 still open)" bash -c "p=\$(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md); echo \"\$p\" | grep -F '(brief:1/2)' | grep -q '^- \[x\] ' && echo \"\$p\" | grep -F '(brief:2/2)' | grep -q '^- \[ \] ' && grep -q 'lazy bug brief applied' '$T/out.txt'"
t "... the journal records the lazy brief" J '"event":"lazy_bug_brief"'
t "... marker file written (never tried twice)" bash -c "[ -f '$Q/state/bug_lazy/$FEAT' ]"
osr_cleanup
lazy_fix; mkdir -p "$Q/state/bug_briefs"; echo '{"status": "ok"}' > "$Q/state/bug_briefs/$FEAT.json"
osr_run "$OSR_REPO"
t "BENIGN: a bug that already has a brief file is not briefed again" bash -c "[ ! -f '$Q/state/brief.calls' ]"
osr_cleanup
lazy_fix fixed
osr_run "$OSR_REPO"
t "NEGATIVE: a bug that is no longer OPEN (Claude fixed it / closed) is not briefed" bash -c "[ ! -f '$Q/state/brief.calls' ] && grep -q 'skipped (no open manual_notes entry' '$T/out.txt'"
osr_cleanup
lazy_fix
bash -c 'exec -a ovn_prework.sh sleep 40' & BGPID=$!
sleep 0.3
osr_run "$OSR_REPO"
kill "$BGPID" 2>/dev/null; BGPID=""
t "NEGATIVE: another LLM consumer is running (GPU contention) => skipped, the run continues with the single item" bash -c "[ ! -f '$Q/state/brief.calls' ] && grep -q 'skipped (another LLM consumer' '$T/out.txt' && grep -q 'DONE: 1/1' '$T/out.txt'"
osr_cleanup
lazy_fix
STUB_BRIEF_FAIL=1 osr_run "$OSR_REPO"
t "NEGATIVE: a failing brief leaves the single item and the run still lands it" bash -c "grep -q 'no usable brief' '$T/out.txt' && grep -q 'DONE: 1/1' '$T/out.txt'"
osr_cleanup
lazy_fix
OVN_BUG_LAZY_BRIEF=off osr_run "$OSR_REPO"
t "OVN_BUG_LAZY_BRIEF=off => never briefs" bash -c "[ ! -f '$Q/state/brief.calls' ]"
osr_cleanup
lazy_fix
OVN_BUG_BRIEF=off osr_run "$OSR_REPO"
t "OVN_BUG_BRIEF=off (the stage's own kill switch) => never briefs" bash -c "[ ! -f '$Q/state/brief.calls' ]"
osr_cleanup

echo "=== E: escalation row + relay body carry the verify error and the run id ==="
newfix; osr_progress "- [ ] $BUGKT"; echo "topic-e" > "$Q/state/ntfy_topic"
echo fail > "$T/scn/pytest.mode"
osr_plan default "$(plan1 'add a filter test and fix the countries filter')"; osr_aider default "$SNIP_OK"
export NTFY_SERVER="http://127.0.0.1:1"
OVN_VERIFY_REPAIR_ROUNDS=0 osr_run "$OSR_REPO"
OVN_VERIFY_REPAIR_ROUNDS=0 osr_run "$OSR_REPO"
t "fixture: the bug was escalated after 2 failed (verify red) attempts" bash -c "grep -q 'bug-escalated: 2 failed attempts' <(git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md)"
t "the escalation row carries the first verify error line" bash -c "grep -q '\"verify_error\":\"FAILED' '$Q/state/bug_escalations.jsonl'"
t "... the stage run id" bash -c "grep -q '\"run\":\"[0-9]\{8\}-' '$Q/state/bug_escalations.jsonl'"
t "... the flow name" bash -c "grep -q '\"flow\":\"countries-filter' '$Q/state/bug_escalations.jsonl'"
t "... and last_failure names the verify error, not only 'staged landed 0 of 1'" bash -c "grep -q 'last_failure\":\"[^\"]*| verify: FAILED' '$Q/state/bug_escalations.jsonl'"
t "the relay body names the flow, the last error and the run" bash -c "b=\$(cat '$T'/llm/body.* | grep -o 'Fleet gave up[^\"]*' | head -1); echo \"\$b\" | grep -q 'countries-filter' && echo \"\$b\" | grep -q 'Last error: FAILED' && echo \"\$b\" | grep -q 'run [0-9]\{8\}-'"
unset NTFY_SERVER
osr_cleanup

echo "=== O: OVN_BUG_FIRST=off restores the old behaviour ==="
newfix; osr_progress "- [ ] $BUGKT"
osr_plan 1 "$(plan1 'add a filter test and fix the countries filter')"; osr_aider 1 "$SNIP_DUP"; osr_aider 2 "$SNIP_DUP"
OVN_BUG_FIRST=off osr_run "$OSR_REPO" "$BUGKT"
t "off: a duplicate-type step is NOT pre-rejected (the old runner left it for the final verify)" bash -c "! grep -q 'duplicate-type' <(cat '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl)"
t "off: no Kotlin context injected into the prompt" bash -c "! grep -qF 'REAL definitions' '$T/scn/aider.args.1'"
t "off: no plan persisted" bash -c "[ ! -d '$Q/state/bug_plans' ]"
osr_cleanup
newfix; osr_progress "- [ ] $BUGKT"; printf '{"entries":{"abc123":{"id":"abc123","feat":"%s","status":"open"}}}' "$FEAT" > "$Q/state/manual_notes.json"
printf '%s' "$STUB_INGEST" > "$Q/qa/manual_notes_ingest.py"
osr_plan 1 "[{\"desc\":\"No change required here\",\"files\":[\"$KT/models/CategoryModels.kt\"],\"verify\":\"x\"}]"
OVN_BUG_FIRST=off osr_run "$OSR_REPO" "$BUGKT"
t "off: a 'no change required' step is not filtered and no lazy brief runs" bash -c "[ ! -f '$Q/state/brief.calls' ] && ! grep -q 'decompose produced no steps' '$T/out.txt'"
osr_cleanup
newfix; osr_progress "- [ ] $BUGKT"; rm -f "$Q/qa/bug_ground.py"
osr_plan 1 "$(plan1 'add a filter test and fix the countries filter')"; osr_aider 1 "$SNIP_OK"
osr_run "$OSR_REPO"
t "FAIL-SAFE: qa/bug_ground.py missing (file-by-file deploy) => the old runner behaviour, run still lands" bash -c "grep -q 'DONE: 1/1' '$T/out.txt' && [ ! -d '$Q/state/bug_plans' ]"
osr_cleanup

osr_summary
