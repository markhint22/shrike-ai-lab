#!/usr/bin/env bash
# Auto-commit + push the overnight-queue directory itself to shrike-ai-lab
# (branch: overnight-live). Established 2026-09-10 after discovering the git
# history had rotted since 2026-08-25 - scripts kept evolving on the server
# but nobody was manually syncing them back into shrike-ai-lab anymore.
# Runs on a cron; a no-op commit attempt is expected and harmless most cycles.
#
# 2026-10-09: the sync silently failed for 7 days (last auto-sync commit 10-02). `git add -A` walks the whole tree, including the
# fleet's transient state/ files, and aborts ("fatal: unable to stat 'state/HOLD_xlite'", 28 log lines) when one disappears mid-scan;
# nothing was staged so the script exited 0 and nobody noticed. Now:
#   * only EXPLICIT source dirs + the root *.sh/*.py/*.md (and already-tracked root files) are added; state/ logs/ repos/ worktrees/ are never
#     named, nested repos (a dir containing .git) are excluded, __pycache__ / ._* / *.pyc inside the added dirs are excluded, deletions of tracked
#     files/dirs are staged, and a named path that .gitignore ignores (and that has nothing tracked) is skipped instead of failing every run
#   * a stat failure is retried once; a persistent failure writes a warn line to state/alerts.log and exits 1
#   * state/git_sync_last_ok is touched on a successful cycle only when HEAD == origin/overnight-live (add ok, and either nothing to commit AND nothing
#     unpushed, or commit+push ok; an idle cycle retries a push that failed earlier and leaves the marker alone if it fails again);
#     a marker older than OVN_GIT_SYNC_STALE_H (default 24) hours (or missing) appends a warn line to state/alerts.log at the top of the run
#   * OVN_GIT_SYNC_LEGACY=1 restores the old `git add -A`
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
STATE="$PWD/state"; mkdir -p "$STATE"
MARK="$STATE/git_sync_last_ok"; ALERTS="$STATE/alerts.log"
alert(){ echo "$(date '+%F %T') warn | git_sync | $*" >> "$ALERTS"; }

# staleness check first, so a run that fails below still leaves the evidence
now="$(date +%s)"
if [ -f "$MARK" ]; then
  mt="$(stat -c %Y "$MARK" 2>/dev/null || stat -f %m "$MARK" 2>/dev/null || echo 0)"
  age_h=$(( (now - mt) / 3600 ))
  [ "$age_h" -ge "${OVN_GIT_SYNC_STALE_H:-24}" ] && alert "last successful sync was ${age_h}h ago (marker $MARK older than ${OVN_GIT_SYNC_STALE_H:-24}h) - the overnight-live mirror is stale"
else
  alert "no successful sync recorded yet ($MARK missing) - the overnight-live mirror may be stale"
fi

# explicit pathspec: source dirs + root source files + every root file git already tracks (tasks.json, alert_suppress.txt, ...).
# Deletions are synced too: a tracked root file / a tracked whole dir that is gone from disk stays in the pathspec (git add -A -- <gone path> stages the removal).
# A named path that .gitignore ignores AND that has no tracked files is dropped: `git add` exits 1 on such a pathspec, which would fail every run.
# Directories that contain a nested .git (embedded repo) are excluded - otherwise they would be committed as a broken gitlink.
tracked_any(){ [ -n "$(git ls-files -- "$1" 2>/dev/null | head -n 1)" ]; }
upd=()   # ignored-by-.gitignore paths that DO have tracked files: only their tracked content is synced (`add -u`), `add -A` would exit 1 on them
want(){  # $1=path -> 0 = add with -A, 1 = skip (ignored and nothing tracked / absent); an ignored-but-tracked path goes to upd[] and returns 1
  if tracked_any "$1"; then
    if git check-ignore --no-index -q -- "$1" 2>/dev/null; then upd+=("$1"); return 1; fi
    return 0
  fi
  [ -e "$1" ] || return 1
  git check-ignore --no-index -q -- "$1" 2>/dev/null && return 1
  return 0
}
SRC_DIRS="scripts qa backlog roadmap tools docs art assets attic reports staging_agents systemd"
paths=(); excl=()
cand="$SRC_DIRS"
for d in proposals-*; do [ -e "$d" ] && cand="$cand $d"; done   # (an unmatched glob stays literal, hence the -e test)
while IFS= read -r d; do   # tracked top-level dirs that vanished from disk (the glob above only sees existing ones)
  case "$d" in scripts|qa|backlog|roadmap|tools|docs|art|assets|attic|reports|staging_agents|systemd|proposals-*) cand="$cand $d";; esac
done < <(git ls-files 2>/dev/null | grep / | cut -d/ -f1 | sort -u)
for d in $(printf '%s\n' $cand | sort -u); do
  want "$d" && paths+=("$d")
done
for f in *.sh *.py *.md; do [ -f "$f" ] && want "$f" && paths+=("$f"); done
while IFS= read -r f; do [ -n "$f" ] && paths+=("$f"); done < <(git ls-files 2>/dev/null | grep -v /)   # tracked root files, existing or deleted
for d in "${paths[@]+"${paths[@]}"}"; do   # nested repos under the named dirs (and a named dir that itself is one)
  [ -d "$d" ] || continue
  while IFS= read -r g; do
    [ -n "$g" ] && excl+=(":(exclude)$(dirname "$g")")
  done < <(find "$d" -name .git -prune -print 2>/dev/null)
done
excl+=(':(exclude,glob)**/__pycache__/**' ':(exclude,glob)**/._*' ':(exclude,glob)**/*.pyc')

do_add(){
  if [ "${OVN_GIT_SYNC_LEGACY:-0}" = "1" ]; then git add -A 2>"$ERR"
  else
    git -c advice.addEmbeddedRepo=false add -A -- ${paths[@]+"${paths[@]}"} "${excl[@]}" 2>"$ERR" || return $?
    [ "${#upd[@]}" -eq 0 ] || git add -u -- "${upd[@]}" 2>>"$ERR"
  fi
}
ERR="$(mktemp "${TMPDIR:-/tmp}/ovn_git_sync.XXXXXX")"; trap 'rm -f "$ERR"' EXIT
do_add; rc=$?
if [ "$rc" -ne 0 ] && grep -q "unable to stat" "$ERR"; then   # a transient file vanished between the directory scan and the stat: one retry
  sleep "${OVN_GIT_SYNC_RETRY_SLEEP:-3}"
  do_add; rc=$?
fi
if [ "$rc" -ne 0 ]; then
  alert "git add failed (rc=$rc): $(tr '\n' ' ' < "$ERR" | cut -c1-200)"
  exit 1
fi
# the marker means "origin/overnight-live == HEAD": it is touched ONLY when nothing is left unpushed. A commit whose push failed stays local, and the NEXT
# idle cycle (nothing staged) must retry that push and keep alerting - not take the "nothing to commit" branch and write a fresh marker (which silenced
# the 24 h stale-sync alert while the mirror was stale).
unpushed(){  # 0 = HEAD has commits origin/overnight-live does not (or the remote-tracking ref is unknown: push to find out)
  git rev-parse -q --verify refs/remotes/origin/overnight-live >/dev/null 2>&1 || return 0
  [ "$(git rev-list --count refs/remotes/origin/overnight-live..HEAD 2>/dev/null || echo 1)" != 0 ]
}
push_or_fail(){ git push -q origin overnight-live || { alert "git push origin overnight-live failed ($(git rev-list --count refs/remotes/origin/overnight-live..HEAD 2>/dev/null || echo '?') local commit(s) not on origin)"; exit 1; }; }
if git diff --cached --quiet; then   # nothing changed this cycle
  if unpushed; then push_or_fail; fi  # retry a push that failed on an earlier cycle (exits 1 without touching the marker if it fails again)
  touch "$MARK"; exit 0
fi
git commit -q -m "auto-sync $(date "+%F %T")" || { alert "git commit failed"; exit 1; }
push_or_fail
touch "$MARK"
