#!/usr/bin/env bash
# docs/patches/overnight-live.gitignore (qacov B11): the proposed live-dir .gitignore must (1) hide every kind of junk `git status` shows on the box today, (2) hide NOTHING
# that ovn_git_sync.sh mirrors, and (3) leave the sync's committed path set exactly as it was. Runs the REAL ovn_git_sync.sh (HOME redirected to a fixture, a local bare origin; the
# real overnight-queue and the real remote are never touched) twice - once with the live dir's current one-line .gitignore, once with the proposal - and compares what each
# commit contains. A too-broad .gitignore (MUTANT) must change that set. SKIPs when the proposal file or git is missing. bash 3.2 ok.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SYNC="$HERE/../../ovn_git_sync.sh"; [ -f "$SYNC" ] || SYNC="$HERE/../ovn_git_sync.sh"
PROP="$HERE/../../../../docs/patches/overnight-live.gitignore"; [ -f "$PROP" ] || PROP="$HERE/../../docs/patches/overnight-live.gitignore"
[ -f "$SYNC" ] || { echo "  SKIP: ovn_git_sync.sh not found"; exit 0; }
# The live dir on the box carries no docs/, so there this test is a no-op: it only runs on a checkout. OVN_TEST_REQUIRE_DOCS=1 turns that SKIP into a FAILURE (scripts/test/premerge_docs_tests.sh sets it).
[ -f "$PROP" ] || { if [ "${OVN_TEST_REQUIRE_DOCS:-0}" = 1 ]; then echo "  FAIL: docs/patches/overnight-live.gitignore not present next to this tree and OVN_TEST_REQUIRE_DOCS=1"; exit 1; fi
                    echo "  SKIP: docs/patches/overnight-live.gitignore not present next to this tree - NOTHING WAS TESTED; run it from a checkout (premerge_docs_tests.sh)"; exit 0; }
command -v git >/dev/null || { echo "  SKIP: no git"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t GIT_CONFIG_NOSYSTEM=1
OLD_GI='!qa/device_lane/known_issues.json'
grep -v '^#' "$PROP" | grep -v '^$' > "$T/proposal.gitignore"

# mkfix <name> <gitignore file>: a live dir with tracked sources, then junk + real changes on top. HOME=$T/<name>/home
mkfix(){
  local h="$T/$1/home" q="$T/$1/home/overnight-queue"
  mkdir -p "$q" "$T/$1"
  git init -q --bare "$T/$1/origin.git"
  ( cd "$q" && git init -q -b overnight-live && git remote add origin "$T/$1/origin.git"
    mkdir -p scripts qa/device_lane backlog roadmap reports tools docs
    echo "print(1)" > scripts/a.py; echo "x" > qa/q.py; echo '[]' > qa/device_lane/known_issues.json; echo "- [ ] a" > backlog/x.md; echo r > roadmap/r.md
    echo '[]' > tasks.json; echo "# notes" > NOTES.md; echo "#!/bin/sh" > top.sh; echo "# d" > docs/d.md
    cp "$2" .gitignore
    git add -A && git commit -q -m init && git push -q -u origin overnight-live ) >/dev/null 2>&1
  # real changes (all must be mirrored): a new script, a modified backlog, a new report, a new quarantine file inside the named backlog dir, a deleted tracked file
  echo "print(2)" > "$q/scripts/new.py"; echo "- [ ] b" >> "$q/backlog/x.md"; echo rep > "$q/reports/20261010-081418.md"
  mkdir -p "$q/backlog/quarantine"; echo "- [ ] quarantined" > "$q/backlog/quarantine/xlite.md"; rm -f "$q/roadmap/r.md"; echo "# n2" >> "$q/NOTES.md"
  # junk (none may be mirrored, all should be hidden by the proposal)
  mkdir -p "$q/logs" "$q/state" "$q/prework" "$q/worktrees/w" "$q/provision-logs" "$q/www" "$q/_archive_pre_git_bak" "$q/scripts/__pycache__" "$q/qa/__pycache__" "$q/repos/r"
  echo l > "$q/logs/a.log"; echo s > "$q/state/HOLD_xlite"; echo p > "$q/prework/p.tsv"; echo w > "$q/worktrees/w/f"; echo l > "$q/provision-logs/l.log"; echo h > "$q/www/fleet_dashboard.html"
  echo b > "$q/_archive_pre_git_bak/a.bak"; echo c > "$q/scripts/__pycache__/y.cpython-312.pyc"; echo c > "$q/qa/__pycache__/z.pyc"; echo d > "$q/._run_overnight.sh"; echo d > "$q/scripts/._lib_x.py"
  ( cd "$q/repos/r" && git init -q && echo e > e.txt && git add -A && git commit -q -m e ) >/dev/null 2>&1
  printf '%s' "$q"
}
sync(){ ( HOME="$T/$1/home"; export HOME; bash "$SYNC" ) > "$T/$1/sync.out" 2>&1; echo $? > "$T/$1/rc"; }
committed(){ git -C "$T/$1/home/overnight-queue" show --name-status --format= HEAD | LC_ALL=C sort; }

QA="$(mkfix old <(printf '%s\n' "$OLD_GI"))"; QB="$(mkfix new "$T/proposal.gitignore")"
git -C "$QA" status --porcelain > "$T/old.status.before"; git -C "$QB" status --porcelain > "$T/new.status.before"
ok "control: with today's one-line .gitignore, git status is noisy (junk dirs + __pycache__ + ._* are all listed as untracked)" "grep -q 'logs/' '$T/old.status.before' && grep -q 'state/' '$T/old.status.before' && grep -q 'repos/' '$T/old.status.before' && grep -q '\\.\\_run_overnight' '$T/old.status.before' && grep -q 'www/' '$T/old.status.before'"
ok "with the proposal, git status lists NONE of the junk (logs state repos prework worktrees provision-logs www _archive __pycache__ ._*)" "! grep -qE 'logs/|state/|repos/|prework/|worktrees/|provision-logs/|www/|_archive_pre_git_bak/|__pycache__|\\._' '$T/new.status.before'"
ok "with the proposal, the real changes are still visible to git (new script, report, quarantine file, modified backlog, deleted roadmap file)" "grep -q 'scripts/new.py' '$T/new.status.before' && grep -q 'reports/' '$T/new.status.before' && grep -q 'backlog/quarantine/' '$T/new.status.before' && grep -q 'backlog/x.md' '$T/new.status.before' && grep -q 'roadmap/r.md' '$T/new.status.before'"
sync old; sync new
ok "both syncs exit 0 and push" "[ \"\$(cat '$T/old/rc')\" = 0 ] && [ \"\$(cat '$T/new/rc')\" = 0 ] && [ \"\$(git -C '$T/old/origin.git' rev-parse overnight-live)\" = \"\$(git -C '$QA' rev-parse HEAD)\" ] && [ \"\$(git -C '$T/new/origin.git' rev-parse overnight-live)\" = \"\$(git -C '$QB' rev-parse HEAD)\" ]"
committed old > "$T/old.committed"; committed new > "$T/new.committed"
ok "the sync commits the SAME path set with and without the proposal (identical name-status list)" "[ -s '$T/old.committed' ] && cmp -s '$T/old.committed' '$T/new.committed'"
ok "that set is exactly the real changes: new script, report, quarantine file, modified backlog + NOTES.md, deleted roadmap file - and no junk, no embedded repo" "[ \"\$(awk '{print \$2}' '$T/new.committed' | LC_ALL=C sort | tr '\\n' ' ')\" = 'NOTES.md backlog/quarantine/xlite.md backlog/x.md reports/20261010-081418.md roadmap/r.md scripts/new.py ' ]"
git -C "$QB" status --porcelain > "$T/new.status.after"
ok "after the sync, git status is CLEAN with the proposal (0 lines; the old .gitignore still shows the junk)" "[ ! -s '$T/new.status.after' ] && [ -n \"\$(git -C '$QA' status --porcelain)\" ]"
ok ".gitignore itself is a tracked root file: a modified one is mirrored by the sync (the proposal ships on the next tick)" "git -C '$QB' ls-files --error-unmatch .gitignore"
# real source paths are not ignored, junk is
for pth in scripts/a.py qa/q.py qa/device_lane/known_issues.json backlog/x.md backlog/quarantine/x.md roadmap/r.md reports/r.md tools/t.py docs/d.md art/a.png assets/a.png attic/a.py systemd/a.service staging_agents/a.md proposals-2026-10-04/a.md tasks.json NOTES.md top.sh scripts/test/fixtures/x/state/s.json scripts/test/fixtures/x/logs/l.log; do
  ok "not ignored: $pth" "! git -C '$QB' check-ignore -q --no-index -- '$pth'"
done
for pth in logs/a.log state/x repos/r/e.txt prework/p worktrees/w/f provision-logs/l www/fleet_dashboard.html _archive_pre_git_bak/a scripts/__pycache__/y.pyc qa/device_lane/__pycache__/z.pyc ._x scripts/._x; do
  ok "ignored: $pth" "git -C '$QB' check-ignore -q --no-index -- '$pth'"
done
# mutant: a too-broad rule (ignores scripts/) changes what the sync commits -> the equivalence assertion fails on it
{ cat "$T/proposal.gitignore"; echo "scripts/"; } > "$T/mutant.gitignore"
QM="$(mkfix mut "$T/mutant.gitignore")"; sync mut; committed mut > "$T/mut.committed"
ok "MUTANT (.gitignore also ignores scripts/): the committed set DIFFERS from the baseline - proves the equivalence assertion bites" "! cmp -s '$T/old.committed' '$T/mut.committed'"
{ cat "$T/proposal.gitignore"; echo "backlog/quarantine/"; } > "$T/mutant2.gitignore"
QM2="$(mkfix mut2 "$T/mutant2.gitignore")"; sync mut2; committed mut2 > "$T/mut2.committed"
ok "MUTANT (the analysis' extra backlog/quarantine/ rule): the sync would silently stop mirroring the quarantine file - the set differs" "! cmp -s '$T/old.committed' '$T/mut2.committed'"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
