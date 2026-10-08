#!/usr/bin/env bash
# Wave-3 extra coverage for scripts/ovn_batch_park_stragglers.sh: the dedup skip, the push-failure branch (dedup NOT
# recorded so the next run retries), and the "0 items actually tagged" branch (local clone shows open stragglers that the
# remote branch no longer has) with the quiet no-alert tail. Hermetic: fake HOME, bare-remote fixtures.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$HERE/.."; [ -f "$SRC_DIR/ovn_batch_park_stragglers.sh" ] || SRC_DIR="$HERE/../scripts"
SCRIPT="$SRC_DIR/ovn_batch_park_stragglers.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: $SCRIPT not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
WD="$tmp/overnight-queue"; mkdir -p "$WD/repos" "$WD/logs" "$WD/state" "$WD/scripts"
for f in ovn_batch_park_stragglers.sh ovn_batch_stragglers.py ovn_batch_park_tagger.py lib_worktree.sh; do cp "$SRC_DIR/$f" "$WD/scripts/$f"; done
now="$(date +%s)"
ts_of(){ python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
row(){ printf '{"repo":"%s","feat_tag":"%s","class":"%s","ts":"%s"}\n' "$1" "$2" "$3" "$(ts_of $(( now - 30*3600 )))"; }
fbatch(){ row "$1" "$2" landed; row "$1" "$2" noop; row "$1" "$2" noop; row "$1" "$2" reverted; row "$1" "$2" noop; }
new_git_repo(){
  local bare="$tmp/bare-$1.git" wt="$WD/repos/$1"
  git init -q --bare "$bare"; mkdir -p "$wt"
  ( cd "$wt" && git init -q && git config user.email t@t.com && git config user.name t && git remote add origin "$bare" \
    && printf '%s\n' "$2" > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init \
    && git branch -M overnight/feature && git push -q -u origin overnight/feature )
}
run(){ HOME="$tmp" bash "$WD/scripts/ovn_batch_park_stragglers.sh" >/dev/null 2>&1; }
LOG="$WD/logs/ovn_batch_park_stragglers.log"
OUTF="$WD/state/outcomes.jsonl"

echo "== dedup: an already-processed tag is skipped"
new_git_repo rD "## Next Steps
- [ ] [T1] a.py — straggler. [feat:rD-bad]"
fbatch rD rD-bad >> "$OUTF"
echo "rD-bad" > "$WD/state/batch_stragglers_parked.txt"
b="$(git -C "$tmp/bare-rD.git" rev-parse overnight/feature)"; run
ok "dedup'd batch leaves the remote untouched" "[ '$b' = \"\$(git -C '$tmp/bare-rD.git' rev-parse overnight/feature)\" ]"
ok "dedup'd batch logs no park action" "! grep -q 'rD/rD-bad' '$LOG'"
ok "with nothing new the run logs the quiet tail" "grep -q 'no new batches to park this run' '$LOG'"

echo "== push failure: dedup not recorded, retry next run"
: > "$WD/state/batch_stragglers_parked.txt"; : > "$OUTF"
new_git_repo rE "## Next Steps
- [ ] [T1] a.py — straggler. [feat:rE-bad]"
fbatch rE rE-bad >> "$OUTF"
printf '#!/bin/sh\nexit 1\n' > "$tmp/bare-rE.git/hooks/pre-receive"; chmod +x "$tmp/bare-rE.git/hooks/pre-receive"
b="$(git -C "$tmp/bare-rE.git" rev-parse overnight/feature)"; run
ok "rejected push leaves the remote unchanged" "[ '$b' = \"\$(git -C '$tmp/bare-rE.git' rev-parse overnight/feature)\" ]"
ok "push failure is logged" "grep -q 'push FAILED for rE/rE-bad' '$LOG'"
ok "push failure does NOT record the tag in dedup (retry next run)" "! grep -qxF rE-bad '$WD/state/batch_stragglers_parked.txt'"
ok "no success alert path: quiet tail logged" "grep -q 'no new batches to park this run' '$LOG'"
rm -f "$tmp/bare-rE.git/hooks/pre-receive"
run
ok "after the remote recovers the next run parks + records the tag" "grep -qxF rE-bad '$WD/state/batch_stragglers_parked.txt' && git -C '$tmp/bare-rE.git' show overnight/feature:OVERNIGHT_PROGRESS.md | grep -q AUTO-SKIP"

echo "== nothing taggable on the remote: dedup marked, no commit"
: > "$OUTF"
new_git_repo rF "## Next Steps
- [x] [T1] a.py — done already. [feat:rF-bad]"
printf '%s\n' "## Next Steps" "- [ ] [T1] a.py — looks open locally. [feat:rF-bad]" > "$WD/repos/rF/OVERNIGHT_PROGRESS.md"
fbatch rF rF-bad >> "$OUTF"
b="$(git -C "$tmp/bare-rF.git" rev-parse overnight/feature)"; run
ok "no commit pushed when the tagger tags 0 lines" "[ '$b' = \"\$(git -C '$tmp/bare-rF.git' rev-parse overnight/feature)\" ]"
ok "0-tagged branch logged" "grep -q '0 items actually tagged for rF/rF-bad' '$LOG'"
ok "0-tagged branch still marks dedup" "grep -qxF rF-bad '$WD/state/batch_stragglers_parked.txt'"

echo "$P passed, $F failed"; [ "$F" -eq 0 ]
