#!/usr/bin/env bash
# read-only: run each open [CLAUDE] line's own VERIFY against a scratch checkout of origin/overnight/feature
r="$1"; Q="$HOME/overnight-queue"; WT="/tmp/wt-ct-$r"; OUT="/tmp/ct_$r.tsv"; : > "$OUT"
cd "$Q/repos/$r" || exit 1
git fetch -q origin overnight/feature 2>/dev/null
git worktree remove --force "$WT" 2>/dev/null; git worktree add -q --detach "$WT" origin/overnight/feature || exit 1
trap 'cd "$Q/repos/$r" && git worktree remove --force "$WT" 2>/dev/null; git worktree prune' EXIT
[ -d "$Q/repos/$r/iptv-backend/.venv" ] && ln -s "$Q/repos/$r/iptv-backend/.venv" "$WT/iptv-backend/.venv" 2>/dev/null
cd "$WT" || exit 1
export PROG="$WT/OVERNIGHT_PROGRESS.md" SHADOW_LOG="/tmp/ct_$r.shadow.log" _REPO_LABEL="$r" HOME="$HOME"
export VERIFY_TIMEOUT_SECS=90 VERIFY_TIMEOUT_HEAVY_SECS=240 _VC_MEMO_ON=1
source "$Q/scripts/lib_verify_clause.sh"
n=0
while IFS=: read -r ln rest; do
  n=$((n+1)); _LAST_VERIFY_RESULT=""
  shadow_check "$ln" >/dev/null 2>&1 </dev/null
  printf '%s\t%s\t%s\n' "$ln" "${_LAST_VERIFY_RESULT:-?}" "$(sed -n "${ln}p" "$PROG" | cut -c1-200)" >> "$OUT"
done < <(grep -n '^- \[ \] .*CLAUDE' "$PROG" | cut -d: -f1 | sed 's/$/:/')
echo "DONE $r $n" >> "$OUT"
