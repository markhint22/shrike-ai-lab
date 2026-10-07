#!/usr/bin/env bash
# Bugs-first policy, review fixes (2026-10-02, branch qa/h8-bug-first): a manual-test bug must NEVER be silently AUTO-SKIPped by the paths that
# test_bug_first_select.sh / test_bug_first_loop.sh did not exercise (their stage runner was a stub):
#   R. the REAL ovn_stage_runner.sh park blocks (every manual bug is tier T3, so it always goes through the staged runner): attempt counted,
#      escalated at the cap with the shared helper (tag + bug_escalations.jsonl + ONE relay note), never '[AUTO-SKIP staged ...]'.
#   G. the REAL ovn_item_guard.sh: a cycle the runner already handled ('bug-handled' status) is not re-billed to an unrelated roadmap item;
#      without the shared helper a bug falls back to the generic caps (never an uncapped open loop).
#   S. the REAL ovn_stage_sweep.sh escalate_godot: a manual bug on a .gd file (xlite) is not routed to '[AUTO-SKIP godot(.gd) ...]'.
# Run on the box / any GNU host (the guard and the helper use sed -i).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed (the guard/helper use sed -i); run on the box"; exit 0; fi
unset OVN_BUG_FIRST OVN_BUG_FOCUS OVN_BUG_ATTEMPT_CAP OVN_GUARD_ATTEMPTS NTFY_SERVER NTFY_TOPIC OVN_BUG_BRIEF_DIR OVN_ITEM_FAIL_CAP OVN_ITEM_NOOP_CAP OVN_ITEM_TOKEN_CAP
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"; osr_cleanup' EXIT
withlibs(){ cp "$REALQ/scripts/lib_item_select.sh" "$REALQ/scripts/lib_bug_escalate.sh" "$REALQ/scripts/ovn_repeat_ids.py" "$Q/scripts/"; }
BUGPY='[T3] backend/app/foo.py — Manual-test bug (reported by Mark, flow f, 2026-10-02): the add button does nothing. First write a failing test that reproduces this, then fix it. VERIFY: `pytest backend/tests/test_foo.py` (cat:bugfix; multifile:no; src:manual) [feat:osr-20261002-manual-aaaa1111]'
PLAN_STUCK1='[{"desc":"big step","files":["backend/app/foo.py"],"verify":"pytest"}]'
PLAN_STUCK2='[{"desc":"only one sub","files":["backend/app/foo.py"],"verify":"pytest"}]'
# 2026-10-04 (QA h13 review): no -q: under pipefail an early-exiting grep SIGPIPEs the writer (rc 141) when loaded = the flaky "journal records the lazy brief".
J(){ osr_jsonl | grep -F -- "$1" >/dev/null; }
origin_prog(){ osr_origin_file OVERNIGHT_PROGRESS.md; }
bugcounts(){ cat "$Q"/state/item_fails/stage-"$OSR_REPO".*.bugcount 2>/dev/null; }
stuck_run(){ # one runner invocation that lands NOTHING (re-decompose yields <2 pieces -> step BLOCKED), plans restart from #1
  rm -f "$T/llm/n" "$T/scn/aider.n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; osr_run "$OSR_REPO"; }

echo "=== R1: the real runner, 0/1 landed on a manual bug ==="
osr_new; withlibs; osr_venv backend
osr_progress "- [ ] $BUGPY"; echo "topic-r" > "$Q/state/ntfy_topic"
export NTFY_SERVER="http://127.0.0.1:1"        # the fixture's stub curl (first on PATH) records the relay call; nothing leaves the host
stuck_run
t "attempt 1: runner really landed 0/1 (fixture sanity)" J '"passed":0,"total":1'
t "attempt 1: the bug line is NOT AUTO-SKIPped" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q AUTO-SKIP"
t "attempt 1: the bug line is still OPEN and untagged (next cycle retries it)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[T3\] backend/app/foo.py — Manual-test bug'"
t "attempt 1: ONE attempt counted (state/item_fails/stage-<repo>.<hash>.bugcount = 1)" bash -c "[ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount)\" = 1 ]"
t "attempt 1: bug_attempt journaled (run_overnight turns it into the 'bug-handled' status)" bash -c "grep -q '\"event\":\"bug_attempt\",\"attempts\":1,\"cap\":2' '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
t "attempt 1: no escalation record, no relay note yet" bash -c "[ ! -s '$Q/state/bug_escalations.jsonl' ] && ! grep -rqs 'Fleet gave up' '$T/llm'/body.*"
t "attempt 1: queue held + released around the edit" bash -c "grep -qx 'hold $OSR_REPO' '$Q/state/queue.calls' && grep -qx 'release $OSR_REPO' '$Q/state/queue.calls'"
stuck_run
t "attempt 2 (cap 2): the bug line is '[CLAUDE] [bug-escalated: 2 failed attempts (cap 2), last: stage-runner: ...]'" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -F 'Manual-test bug' | grep -q '^- \[ \] \[CLAUDE\] \[bug-escalated: 2 failed attempts (cap 2), last: stage-runner: '"
t "attempt 2: still NOT AUTO-SKIPped, anywhere" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q AUTO-SKIP"
t "attempt 2: escalation committed as the fleet identity and pushed to origin/overnight/feature" bash -c "git -C '$O' log --format='%s|%ae' overnight/feature | grep -q 'escalate manual-test bug to a Claude session after 2 failed fleet attempts|22970726+markhint22@users.noreply.github.com'"
t "attempt 2: ONE bug_escalations.jsonl line for the repo with the item hash + 2 attempts" bash -c "[ \"\$(wc -l < '$Q/state/bug_escalations.jsonl' | tr -d ' ')\" = 1 ] && grep -q '\"repo\":\"$OSR_REPO\"' '$Q/state/bug_escalations.jsonl' && grep -q '\"attempts\":2' '$Q/state/bug_escalations.jsonl' && grep -q '\"item_hash\":\"[0-9a-f]\{32\}\"' '$Q/state/bug_escalations.jsonl' && grep -q 'osr-20261002-manual-aaaa1111' '$Q/state/bug_escalations.jsonl'"
t "attempt 2: ONE relay note 'Fleet gave up after 2 attempt(s)'" bash -c "[ \"\$(grep -l 'Fleet gave up after 2 attempt' '$T/llm'/body.* 2>/dev/null | wc -l | tr -d ' ')\" = 1 ]"
t "attempt 2: runner counter cleared after the escalation" bash -c "[ -z \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount 2>/dev/null)\" ]"
stuck_run
t "a 3rd run finds nothing to pick (bug is [CLAUDE]) and adds no second escalation" bash -c "grep -q 'no doable T3+ item found' '$T/out.txt' && [ \"\$(wc -l < '$Q/state/bug_escalations.jsonl' | tr -d ' ')\" = 1 ]"
unset NTFY_SERVER
osr_cleanup

echo "=== R2: partial landing (1/2) on a manual bug ==="
osr_new; withlibs; osr_venv backend
osr_progress "- [ ] $BUGPY"
osr_plan default '[{"desc":"add foo","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"t"},{"desc":"add bar","files":["backend/app/bar.py"],"verify":"t"}]'
osr_aider 1 "$SNIP_FOO"
OVN_STAGE_REDECOMP=0 osr_run "$OSR_REPO"
t "fixture sanity: 1/2 landed + pushed" J '"passed":1,"total":2'
t "partial: the bug line is NOT AUTO-SKIPped (no 'AUTO-SKIP staged 1/2')" bash -c "! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP'"
t "partial: line stays open, not checked off" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[T3\] backend/app/foo.py — Manual-test bug' && ! git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\]'"
t "partial: one attempt counted" bash -c "[ \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount)\" = 1 ]"
osr_cleanup

echo "=== R3: benign / control paths keep the old behaviour ==="
osr_new; withlibs; osr_venv backend
osr_progress "- [ ] $ITEM_PY"
# 2026-10-07: the zero-landing RETRY BUDGET (default 3) keeps a plain item open; OVN_STAGE_ZERO_CAP=1 is the legacy immediate escalation this control checks
# (the budget itself is covered by test_stage_zero_retry.sh).
rm -f "$T/llm/n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; OVN_STAGE_ZERO_CAP=1 osr_run "$OSR_REPO"
t "NON-bug item landing nothing: still '[AUTO-SKIP staged: 27B could not land this ...]' (unchanged)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged: 27B could not land this'"
t "NON-bug item: no bug counter, no escalation record" bash -c "[ -z \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount 2>/dev/null)\" ] && [ ! -s '$Q/state/bug_escalations.jsonl' ] && ! grep -q bug_attempt '$Q'/state/stage_runs/$OSR_REPO-*[0-9].jsonl"
osr_cleanup
osr_new; withlibs; osr_venv backend
osr_progress "- [ ] $BUGPY"
rm -f "$T/llm/n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; OVN_STAGE_ZERO_CAP=1 OVN_BUG_FIRST=off osr_run "$OSR_REPO"
t "kill switch OVN_BUG_FIRST=off: the old AUTO-SKIP behaviour (bug is a plain item again)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged: 27B could not land this'"
osr_cleanup
osr_new; cp "$REALQ/scripts/lib_item_select.sh" "$REALQ/scripts/ovn_repeat_ids.py" "$Q/scripts/"; osr_venv backend      # lib_bug_escalate.sh MISSING
osr_progress "- [ ] $BUGPY"
rm -f "$T/llm/n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; OVN_STAGE_ZERO_CAP=1 osr_run "$OSR_REPO"
t "escalation helper missing: fail-safe to the old AUTO-SKIP, never an uncapped open loop" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q 'AUTO-SKIP staged: 27B could not land this' && [ -z \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount 2>/dev/null)\" ]"
osr_cleanup
osr_new; withlibs; osr_venv backend
osr_progress "- [ ] $BUGPY"
rm -f "$T/llm/n"; osr_plan 1 "$PLAN_STUCK1"; osr_plan 2 "$PLAN_STUCK2"; OVN_BUG_ATTEMPT_CAP=1 osr_run "$OSR_REPO"
t "OVN_BUG_ATTEMPT_CAP=1: escalated on the first failed staged run" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -F 'Manual-test bug' | grep -q '\[CLAUDE\] \[bug-escalated: 1 failed attempts (cap 1)'"
osr_cleanup
osr_new; withlibs; osr_venv backend
osr_progress "- [ ] $BUGPY"
osr_plan default '[{"desc":"add foo","files":["backend/app/foo.py","backend/tests/test_foo.py"],"verify":"pytest backend/tests/test_foo.py"}]'
osr_aider default "$SNIP_FOO"
osr_run "$OSR_REPO"
t "a manual bug that LANDS fully is checked off (no escalation, counter absent)" bash -c "git -C '$O' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[x\] \[T3\] backend/app/foo.py — Manual-test bug' && [ ! -s '$Q/state/bug_escalations.jsonl' ] && [ -z \"\$(cat '$Q'/state/item_fails/stage-$OSR_REPO.*.bugcount 2>/dev/null)\" ]"
osr_cleanup

echo "=== G: the real guard ==="
G="$REALQ/scripts/ovn_item_guard.sh"
new_repo(){ local r="$tmp/$1"; shift; mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t \
    && { echo '# Progress'; echo; echo '## Next Steps'; printf '%s\n' "$@"; } > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init ); echo "$r"; }
guard(){ ( cd "$tmp" && env -i PATH="$PATH" bash "$G" "$1" "$2" "$3" "$4" "" ) >/dev/null 2>&1; }
BUGLINE="- [ ] [CLAUDE] [bug-escalated: 2 failed attempts (cap 2)] - [ ] [T3] \`a.py\` — Manual-test bug (reported by Mark, flow f, 2026-10-02): x. (cat:bugfix; src:manual) [feat:osr-20261002-manual-aaaa1111]"
RA='- [ ] [T2] `app/roadmap_a.py` — new feature A. (cat:python)'
BH='no-op(stage-unverified) stage(higher-tier) bug-handled'
r="$(new_repo g1 "$BUGLINE" "$RA")"; st="$tmp/g1st"; mkdir -p "$st"
for i in 1 2 3; do guard "$r" "$BH" "$st" ongoing-x; done
t "bug-handled cycle x3 with the bug already parked: NO streak state is billed to the unrelated roadmap item" bash -c "[ -z \"\$(ls '$st'/item_fails 2>/dev/null)\" ]"
for i in 4 5; do guard "$r" "$BH" "$st" ongoing-x; done
t "...and the roadmap item is not AUTO-SKIPped" bash -c "! grep -q 'AUTO-SKIP' '$r/OVERNIGHT_PROGRESS.md'"
r="$(new_repo g2 "$BUGLINE" "$RA")"; st="$tmp/g2st"; mkdir -p "$st"
for i in 1 2 3 4; do guard "$r" 'no-op(stage-unverified) stage(higher-tier)' "$st" ongoing-x; done
t "CONTROL (the old behaviour): the same status WITHOUT the marker is billed to the roadmap item and parks it after 4" bash -c "grep -F 'roadmap_a.py' '$r/OVERNIGHT_PROGRESS.md' | grep -q 'AUTO-SKIP after 4 no-op cycles'"
t "run_overnight.sh best-of-N loop does not retry a 'bug-handled' status (the runner already counted it)" bash -c "grep -q \"grep -qF 'bug-handled' && echo\" '$REALQ/run_overnight.sh'"
# fail-safe: the guard without the shared helper must not run an uncapped open loop on a bug
mkdir -p "$tmp/gnolib/scripts"; cp "$G" "$REALQ/scripts/lib_item_select.sh" "$tmp/gnolib/scripts/"; [ -f "$REALQ/scripts/ovn_extract_failure.sh" ] && cp "$REALQ/scripts/ovn_extract_failure.sh" "$tmp/gnolib/scripts/"
OPENBUG='- [ ] [T3] `a.py` — Manual-test bug (reported by Mark, flow f, 2026-10-02): x. (cat:bugfix; src:manual) [feat:osr-20261002-manual-bbbb2222]'
r="$(new_repo g3 "$OPENBUG")"; st="$tmp/g3st"; mkdir -p "$st"
for i in 1 2 3; do ( cd "$tmp" && env -i PATH="$PATH" bash "$tmp/gnolib/scripts/ovn_item_guard.sh" "$r" 'reverted(build-break)' "$st" ongoing-x "" ) >/dev/null 2>&1; done
t "helper missing: the bug falls back to the generic fail cap (AUTO-SKIP after 3), not an uncapped open loop" bash -c "grep -q 'AUTO-SKIP after 3 failed-to-land cycles' '$r/OVERNIGHT_PROGRESS.md'"
r="$(new_repo g4 "$OPENBUG")"; st="$tmp/g4st"; mkdir -p "$st"
guard "$r" 'reverted(build-break)' "$st" ongoing-x; guard "$r" 'reverted(build-break)' "$st" ongoing-x
t "helper present (shared lib): the guard still escalates the bug at 2 via ovn_bug_escalate" bash -c "grep -q '\[CLAUDE\] \[bug-escalated: 2 failed attempts (cap 2)' '$r/OVERNIGHT_PROGRESS.md' && [ \"\$(wc -l < '$st/bug_escalations.jsonl' | tr -d ' ')\" = 1 ]"

echo "=== S: the real stage sweep (escalate_godot) ==="
sw_new(){ T="$(mktemp -d)"; H="$T/home"; Q="$H/overnight-queue"; mkdir -p "$Q/state" "$Q/logs" "$Q/repos" "$T/bin"
  printf '#!/usr/bin/env bash\necho "$*" >> "$HOME/overnight-queue/state/runner.calls"\nexit 0\n' > "$Q/ovn_stage_runner.sh"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"; printf '#!/usr/bin/env bash\nexit 0\n' > "$T/bin/sleep"; chmod +x "$T/bin/pgrep" "$T/bin/sleep"; }
sw_repo(){ local r="$1"; shift; local d="$Q/repos/$r" o="$T/origin-$r.git"
  git init -q --bare "$o"; git init -q "$d"; git -C "$d" checkout -q -b overnight/feature
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  { echo "# Progress"; echo "## Next"; local l; for l in "$@"; do echo "$l"; done; } > "$d/OVERNIGHT_PROGRESS.md"
  git -C "$d" add -A; git -C "$d" commit -q -m seed; git -C "$d" remote add origin "$o"; git -C "$d" push -q origin overnight/feature 2>/dev/null; }
sw_run(){ ( cd "$T" && HOME="$H" PATH="$T/bin:$PATH" bash "$SWEEP" ) > "$T/out.txt" 2>&1 < /dev/null; RC=$?; }
ofile(){ git -C "$T/origin-$1.git" show overnight/feature:OVERNIGHT_PROGRESS.md; }
GB='- [ ] [T3] game/scripts/hud.gd — Manual-test bug (reported by Mark, flow hud, 2026-10-02): the HP bar overlaps the minimap. First write a failing test that reproduces this. VERIFY: `true`. (cat:bugfix; src:manual) [feat:xlite-20261002-manual-cccc3333]'
GSTEP='- [ ] [T3] game/scripts/hud_test.gd — step 2 of 2 of the bug above (cat:bugfix; src:manual) [feat:xlite-20261002-manual-cccc3333]'
GR='- [ ] [T4] game/scripts/enemy.gd — roadmap: new enemy AI (cat:godot)'
sw_new; sw_repo xlite "$GB" "$GSTEP" "$GR"
sw_run
t "bug on a .gd file (and its sibling step) are NOT routed to AUTO-SKIP godot" bash -c "! git -C '$T/origin-xlite.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep 'Manual-test bug\|step 2 of 2' | grep -q AUTO-SKIP"
t "bug line left byte-identical for the fleet to work" bash -c "git -C '$T/origin-xlite.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -qF -- '$GB'"
t "a plain roadmap .gd item IS still routed to Claude (unchanged)" bash -c "git -C '$T/origin-xlite.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q '^- \[ \] \[AUTO-SKIP godot(.gd) — 27B measured 0%, route to CLAUDE\] \[T4\] game/scripts/enemy.gd'"
osr_cleanup
sw_new; sw_repo xlite "$GB" "$GR"
OVN_BUG_FIRST=off sw_run
t "kill switch OVN_BUG_FIRST=off: the bug is routed like any .gd item again (old behaviour)" bash -c "git -C '$T/origin-xlite.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep 'Manual-test bug' | grep -q 'AUTO-SKIP godot(.gd)'"
osr_cleanup
sw_new; sw_repo xlite "$GB"
sw_run
t "only a manual bug present: nothing to commit (no churn commit beyond the seed)" bash -c "[ \"\$(git -C '$T/origin-xlite.git' log --oneline overnight/feature | wc -l | tr -d ' ')\" = 1 ]"
osr_cleanup

osr_summary
