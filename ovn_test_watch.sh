#!/usr/bin/env bash
# ovn_test_watch.sh — periodic FULL-SUITE health watchdog (server cron, lock-aware).
#
# The per-cycle gate only runs tests RELATED to the files a commit touched, so a pre-existing or
# flaky failure in untouched code can sit red for days without the fleet noticing. This watchdog
# runs each repo's WHOLE suite on the latest overnight/feature, and when a suite is red it files an
# [EMERGENCY] triage-and-fix item at the TOP of that repo's Next Steps (worked first next cycle) and
# alerts. It reuses the fleet's already-provisioned .venv/node_modules (no re-provision).
#
# 2026-10-02 REDESIGN (no more run.lock): it used to hold the fleet's run.lock (flock -w 3600) for the whole sweep and
# run every suite on the SHARED live clone, so it (a) waited 42+ min behind a dev pass (a pass holds run.lock 45-60 min),
# (b) idled the GPU ~7-20 min per sweep while it held the lock, and (c) was kill -9'd by lock_guard.sh until that was
# patched. Now each repo is tested in a DETACHED WORKTREE of origin/overnight/feature (fetched read-only; envs symlinked
# in via wt_link_envs), so the live checkout is never touched and the SUITES never need run.lock. Only a second sweep is
# excluded, by its own state/test_watch.lock. EMERGENCY items are written through a short-lived worktree + wt_push
# (HEAD:overnight/feature) so the live working tree/index is never edited out from under a running cycle; that write+push
# alone (seconds) takes run.lock, deferring when a cycle is live - see emergency_enqueue for why.
#
# Cron (server):  17 */6 * * *  cd ~/overnight-queue && ./ovn_test_watch.sh >> logs/ovn_test_watch.log 2>&1
set -uo pipefail
# 2026-10-04: GUT also descends into tests/*/ (release/battle/steam were never run). Verified green on xlite claude/feature (389 scripts, 2862 tests, 0 failing).
# Kill switch: OVN_GUT_SUBDIRS=off.
GUT_SUBDIRS="-ginclude_subdirs"; [ "${OVN_GUT_SUBDIRS:-on}" = "off" ] && GUT_SUBDIRS=""
# locate sibling libs BEFORE the cd (BASH_SOURCE, not $0: unit tests `source` this file, where $0 is the caller's)
TW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HOME/overnight-queue" || exit 1
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
REPOS="${*:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor shrike-labs-website}"
GODOT="$HOME/godot/godot4"
log(){ echo "$(date '+%F %T') $*"; }

source "$TW_DIR/scripts/lib_pytest_parallel.sh" 2>/dev/null || ovn_pytest_par_args(){ :; }
# shellcheck source=./scripts/lib_worktree.sh
source "$TW_DIR/scripts/lib_worktree.sh" || { log "lib_worktree.sh missing — cannot isolate the sweep"; exit 1; }

# ---- exclude only a SECOND sweep (own lock, bounded wait); the fleet's run.lock is deliberately NOT taken ----
mkdir -p state
exec 201>state/test_watch.lock
if ! flock -w "${OVN_TW_LOCK_WAIT:-120}" 201; then log "another test-health sweep still holds test_watch.lock (waited ${OVN_TW_LOCK_WAIT:-120}s) — skipping this pass"; exit 0; fi
# fd 201 is inherited by every child; run the long test commands with it closed (tw_run) so a leaked vitest/xdist
# worker can never keep the lock held after this script exits (the orphan-lock failure lock_guard.sh exists for).
tw_run(){ "$@" 201>&-; }

# ---- worktree bookkeeping: every worktree we open is closed on ANY exit (normal, error, TERM/INT/HUP) ----
TW_OPEN=""   # newline-separated "<repo_dir>|<worktree>" for worktrees currently open
TW_LAST=""   # worktree path of the most recent tw_open (a global, not stdout: $(...) would lose the TW_OPEN bookkeeping in a subshell)
tw_open(){ # $1=repo_dir -> sets TW_LAST to a new detached worktree of origin/overnight/feature (envs linked in)
  local w; TW_LAST=""
  w="$(wt_open "$1" overnight/feature --detach --tag=tw)" || return 1
  TW_OPEN="${TW_OPEN}${1}|${w}"$'\n'
  wt_link_envs "$1" "$w"
  TW_LAST="$w"
}
tw_close(){ # $1=repo_dir $2=worktree
  wt_close "$1" "$2"; rm -rf "$2" 2>/dev/null
  TW_OPEN="$(printf '%s' "$TW_OPEN" | grep -vF -- "|$2" || true)"
  [ -n "$TW_OPEN" ] && TW_OPEN="${TW_OPEN}"$'\n'
}
tw_cleanup(){ local e; while IFS= read -r e; do [ -n "$e" ] && { wt_close "${e%%|*}" "${e#*|}"; rm -rf "${e#*|}" 2>/dev/null; }; done <<<"$TW_OPEN"; TW_OPEN=""; }
trap tw_cleanup EXIT
trap 'log "terminated — cleaning up worktrees"; exit 143' TERM INT HUP
# We hold test_watch.lock, so any /tmp/wt-tw-* worktree still registered is an orphan of a SIGKILL'd earlier sweep.
for _r in $REPOS; do
  [ -d "repos/$_r/.git" ] || continue
  while IFS= read -r _w; do
    case "$_w" in /tmp/wt-tw-*|/private/tmp/wt-tw-*) log "$_r: reaping orphaned test-watch worktree $_w"; wt_close "repos/$_r" "$_w"; rm -rf "$_w" 2>/dev/null;; esac
  done < <(git -C "repos/$_r" worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')
  git -C "repos/$_r" worktree prune >/dev/null 2>&1 || true
done
SWEEP_T0="$(date +%s)"
log "=== test-health sweep start ==="

# backticked repo-relative paths of the failing test files found in $2 (subdir prefix $1), so the fleet's
# preloader hands them to the model - an item naming no file left the 27B "unable to guess their contents".
files_from(){
  local sub="${1:-}" pre=""; sub="${sub#/}"; [ -n "$sub" ] && pre="${sub}/"
  printf '%s' "$2" | grep -oE '(src|tests?|app)/[A-Za-z0-9_./@-]+\.(py|ts|tsx|js|vue|gd)' | sort -u | head -3 | sed "s#^#\`${pre}#; s#\$#\`#" | paste -sd' ' -
}

# 2026-10-02 (review fix): the EMERGENCY write+push is the ONE step that needs the fleet's run.lock, held for seconds (never for
# the suite). A cycle can be mid-flight with an unpushed local commit that flips the top "## Next Steps" checkbox; our
# inserted line is adjacent to that line, so origin advancing under it makes the cycle's `pull --rebase` conflict and its
# push-rejected path (run_overnight.sh "push-diverged") does `reset --hard origin/<branch>` - discarding a verified,
# landed commit, code included (reproduced in a scratch repo). run.lock is held for a whole pass, so: take it with a short
# wait; if a cycle is live, DEFER the filing (nothing pushed, nothing lost) and retry at the end of the sweep with a long
# wait; if still busy the next sweep re-detects the red suite and tries again. The fd (202) is closed before the ntfy.
TW_DEFERRED=""   # newline-separated "repo<TAB>area<TAB>detail<TAB>files" emergencies not yet filed because run.lock was busy
emergency_enqueue(){ # $1=repo $2=area $3=failing-detail [$4=files]   (EW_LOCK_WAIT overrides the run.lock wait, seconds)
  local repo="$1" area="$2" detail="$3" files="${4:-}" lw="${EW_LOCK_WAIT:-${OVN_TW_EMERG_LOCK_WAIT:-30}}"
  [ -d "repos/$repo/.git" ] || return 0
  mkdir -p state
  exec 202>state/run.lock
  if ! flock -w "$lw" 202; then
    exec 202>&-
    log "$repo/$area: run.lock busy (a fleet cycle is live, waited ${lw}s) - EMERGENCY filing DEFERRED, nothing pushed"
    TW_DEFERRED="${TW_DEFERRED}${repo}"$'\t'"${area}"$'\t'"${detail//$'\n'/ }"$'\t'"${files//$'\n'/ }"$'\n'
    return 0
  fi
  EW_ALERT=0
  _emergency_write "$repo" "$area" "$detail" "$files"
  exec 202>&-   # release run.lock BEFORE the (slow, network) ntfy alert
  [ "$EW_ALERT" = 1 ] && curl -fsS --max-time 8 -H "Title: ${repo} ${area} tests are red" -H "Tags: rotating_light" -H "Priority: high" \
    -d "The full-suite watchdog found ${area} failing in ${repo}. An [EMERGENCY] triage+fix item was queued at the top of its Next Steps — the fleet will work it first next cycle. Failing: ${detail:0:300}" \
    "${NTFY_SERVER:-https://ntfy.sh}/$TOPIC" >/dev/null 2>&1 || true
  return 0
}
# retry what was deferred, once, with a long run.lock wait (called at the end of the sweep; may re-defer into TW_DEFERRED for logging only)
tw_retry_deferred(){
  local pending="$TW_DEFERRED" r a d f
  TW_DEFERRED=""
  [ -n "$pending" ] || return 0
  while IFS=$'\t' read -r r a d f; do
    [ -n "$r" ] || continue
    log "$r/$a: retrying deferred EMERGENCY filing (waiting up to ${OVN_TW_EMERG_RETRY_WAIT:-900}s for run.lock)"
    EW_LOCK_WAIT="${OVN_TW_EMERG_RETRY_WAIT:-900}" emergency_enqueue "$r" "$a" "$d" "$f"
  done <<<"$pending"
  [ -z "$TW_DEFERRED" ] || log "EMERGENCY filing still deferred after retry (fleet cycle still live) - the next sweep re-detects the red suite and files it"
}
_emergency_write(){ # body of emergency_enqueue, run while holding run.lock; sets EW_ALERT=1 when the alert should go out
  local repo="$1" area="$2" detail="$3" files="${4:-}"
  local rdir="repos/$repo" ew pf
  [ -d "$rdir/.git" ] || return 0
  # 2026-10-02: the file is edited in a throwaway worktree of the CURRENT origin/overnight/feature (re-fetched: the suite
  # that just ran can be 10+ min old) and pushed HEAD:overnight/feature, never in the live clone's working tree/index.
  # The caller (emergency_enqueue) holds run.lock around this, so no cycle is live and none has an unpushed commit that
  # our adjacent insertion could conflict with; nothing in the live tree is written, and the fleet picks the commit up at
  # its next cycle start (run_overnight.sh fast-forwards a clone that is behind origin, replays a progress-only divergence).
  timeout 60 git -C "$rdir" fetch -q origin +refs/heads/overnight/feature:refs/remotes/origin/overnight/feature 2>/dev/null
  tw_open "$rdir" || { log "$repo/$area: worktree open failed — emergency NOT filed this pass (re-detected next sweep)"; return 0; }
  ew="$TW_LAST"
  pf="$ew/OVERNIGHT_PROGRESS.md"
  [ -f "$pf" ] || { tw_close "$rdir" "$ew"; return 0; }
  local item="- [ ] [EMERGENCY][T2] ${area} suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ${detail}${files:+ Files to read and fix: ${files}}"
  # already filed an OPEN emergency for this area? don't pile duplicates. 2026-09-16 FIX: this
  # used to grep -F the whole file, matching RETIRED/closed items too (a "- [x] (retired-...)"
  # line from a stale-clone auto-retirement sweep counted as "already queued" forever after) —
  # found live on gitlark, where a real openapi-contract test failure has been silently
  # unactionable since 2026-08-30 because an unrelated dead-path retirement of an old emergency
  # for the same area permanently blocked every later re-file. Only an un-checked `- [ ] ...`
  # line for this area should count as "already queued".
  if grep -qE "^- \[ \] .*\[EMERGENCY\]\[T2\] ${area} suite is RED" "$pf"; then log "$repo/$area: emergency already queued (open) — skip"; tw_close "$rdir" "$ew"; return 0; fi
  # insert right after the "## Next Steps" header so it's the top item worked next cycle
  python3 - "$pf" "$item" <<'PY'
import sys
pf, item = sys.argv[1], sys.argv[2]
lines = open(pf, encoding="utf-8").read().splitlines(keepends=True)
out, inserted = [], False
for ln in lines:
    out.append(ln)
    if not inserted and ln.strip().lower().startswith("## next steps"):
        out.append(item + "\n")
        inserted = True
if not inserted:  # no Next Steps header — prepend a section
    out = ["## Next Steps\n", item + "\n", "\n"] + out
open(pf, "w", encoding="utf-8").write("".join(out))
PY
  ( cd "$ew" && git add OVERNIGHT_PROGRESS.md \
      && git -c user.email=22970726+markhint22@users.noreply.github.com -c user.name=shrike-fleet commit -q -m "fix(queue): [EMERGENCY] ${area} suite red — triage+fix queued by test-watch" ) \
    && [ "$(wt_push "$ew" overnight/feature)" = ok ] && log "$repo/$area: EMERGENCY fix item queued + pushed"
  tw_close "$rdir" "$ew"
  EW_ALERT=1
}

for r in $REPOS; do
  rd="repos/$r"; [ -d "$rd" ] || { log "$r: no clone — skip"; continue; }
  REPO_T0="$(date +%s)"
  # latest overnight/feature, fetched READ-ONLY (updates only the remote-tracking ref; the live checkout/branch/index are
  # never touched - the old checkout+reset --hard on the shared clone is exactly what needed run.lock)
  if ! timeout 120 git -C "$rd" fetch -q origin +refs/heads/overnight/feature:refs/remotes/origin/overnight/feature 2>/dev/null; then
    log "$r: git sync failed — skip"; continue
  fi
  if ! tw_open "$rd"; then log "$r: worktree open failed — skip"; continue; fi
  wt="$TW_LAST"
  log "$r: running full suite on overnight/feature"

  # ---- PYTHON: every provisioned .venv/bin/pytest, full suite ----
  # discovery runs on the LIVE clone (find does not descend into the symlinked .venv inside the worktree); the suite
  # itself runs at the same relative path inside the worktree. dn = the live dir's name (area / log text), not the tmp worktree's.
  while IFS= read -r -d '' vp; do
    dl="${vp%/.venv/bin/pytest}"; rel="${dl#$rd}"; d="$wt$rel"; dn="$(basename "$dl")"
    [ -d "$d" ] || { log "$r: ${dn} has no counterpart in origin/overnight/feature — skip pytest"; continue; }
    # 2026-09-16 FIX: was `timeout 360 ... | tail -25`, which piped away timeout's own exit
    # code (only tail's, always 0, survived into $?) — a suite that had grown past 360s (real
    # case: iptv_apps measured at 383s) got silently reported GREEN because a truncated run
    # never printed a "N failed" summary line for the grep below to match. Bumped the cap
    # (360->600s, real worst case seen was 383s) AND now capture the real exit code
    # separately from the tail-for-logging step, so a timeout is its own explicit branch
    # instead of falling through to "no failures seen" -> green.
    # 2026-10-02: xdist (allowlisted repos only, import-guarded; see scripts/lib_pytest_parallel.sh). iptv_apps ran serially here, took >600s under
    # load, was filed RED (false EMERGENCY) and then re-ran for up to 900s while holding run.lock - ~25 min of idle GPU per sweep.
    XD="$(ovn_pytest_par_args "${r##*/}" "$d/.venv/bin")"
    raw="$( cd "$d" && tw_run timeout 600 ./.venv/bin/pytest -q --no-cov $XD 2>&1 )"; rc=$?
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 5 ]; then
      # one confirmation re-run under the same lock (fleet paused) before filing an EMERGENCY: a timeout or a
      # red seen once is usually contention/flake - 2026-09-30 billwatch "timed out" at 600s but runs in 90s alone
      log "$r: pytest not green (rc=$rc) in ${dn} - re-running once to rule out contention/flake"
      raw="$( cd "$d" && tw_run timeout 900 ./.venv/bin/pytest -q --no-cov $XD 2>&1 )"; rc=$?
    fi
    out="$(printf '%s' "$raw" | tail -25)"
    if [ "$rc" -eq 124 ]; then
      log "$r: pytest TIMED OUT in ${dn} after 600s (suite may have grown too slow, or something hung) — treating as RED, not green"
      emergency_enqueue "$r" "${dn} pytest" "full suite did not finish within 600s (timed out, exit 124) — check whether the suite has grown past the cap or a test is hanging"
    elif printf '%s' "$out" | grep -qE '[0-9]+ (failed|error)'; then
      fails="$(printf '%s' "$out" | grep -E 'FAILED|ERROR ' | head -5 | sed 's/  */ /g' | paste -sd'; ' -)"
      [ -z "$fails" ] && fails="$(printf '%s' "$out" | grep -E '[0-9]+ (failed|error)' | tail -1)"
      log "$r: pytest RED in ${dn} — $fails"
      emergency_enqueue "$r" "${dn} pytest" "${fails:-see log}" "$(files_from "$rel" "$fails")"
    else
      log "$r: pytest green in ${dn} ($(printf '%s' "$out" | grep -oE '[0-9]+ passed' | tail -1))"
    fi
  done < <(find "$rd" -maxdepth 4 -type f -path "*/.venv/bin/pytest" -print0 2>/dev/null)

  # ---- WEB: vitest full run + build, per web package (package.json is tracked, so discovery runs in the worktree; node_modules is the symlinked live one) ----
  while IFS= read -r -d '' pj; do
    wd="$(dirname "$pj")"; rel="${wd#$wt}"
    # name = the package dir's name; a root-level package (shrike-labs-website) is named after the repo, not the tmp worktree
    wn="${wd##*/}"; [ "$wd" = "$wt" ] && wn="$r"
    grep -q '"vitest"' "$pj" 2>/dev/null || continue
    [ -d "$wd/node_modules/vitest" ] || { log "$r: ${wn} not provisioned (no node_modules) — skip web"; continue; }
    # 2026-09-16 FIX: same pipe-swallows-exit-code + false-green-on-timeout fix as pytest above.
    raw="$( cd "$wd" && CI=true tw_run timeout 400 npx vitest run 2>&1 )"; rc=$?
    if [ "$rc" -ne 0 ]; then
      log "$r: vitest not green (rc=$rc) in ${wn} - re-running once to rule out contention/flake"
      raw="$( cd "$wd" && CI=true tw_run timeout 600 npx vitest run 2>&1 )"; rc=$?
    fi
    out="$(printf '%s' "$raw" | tail -25)"
    if [ "$rc" -eq 124 ]; then
      log "$r: vitest TIMED OUT in ${wn} after 400s — treating as RED, not green"
      emergency_enqueue "$r" "${wn} vitest" "full suite did not finish within 400s (timed out, exit 124) — check whether the suite has grown past the cap or a test is hanging"
    elif printf '%s' "$out" | grep -qE '[0-9]+ failed|✖|FAIL '; then
      fails="$(printf '%s' "$out" | grep -E 'FAIL |✖' | head -5 | paste -sd'; ' -)"
      log "$r: vitest RED in ${wn}"
      emergency_enqueue "$r" "${wn} vitest" "${fails:-see log}" "$(files_from "$rel" "$fails")"
    else
      log "$r: vitest green in ${wn} ($(printf '%s' "$out" | grep -oE '[0-9]+ passed' | tail -1))"
    fi
  done < <(find "$wt" -maxdepth 3 -type f -name package.json -not -path '*/node_modules/*' -print0 2>/dev/null)

  # ---- GODOT (xlite): GUT full suite ----
  if [ -x "$GODOT" ]; then
    while IFS= read -r -d '' gp; do
      gd="$(dirname "$gp")"
      [ -d "$gd/addons/gut" ] || continue
      # a fresh worktree has no (gitignored) .godot/ or *.import: copy the live clone's so --import is incremental (see wt_seed_godot)
      wt_seed_godot "$rd" "$wt" "$(dirname "${gp#$wt/}")"
      ( cd "$gd" && tw_run timeout 90 "$GODOT" --headless --path . --import >/dev/null 2>&1 )
      out="$( cd "$gd" && tw_run timeout 60 "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests $GUT_SUBDIRS -gexit 2>&1 | tail -30 )"
      if printf '%s' "$out" | grep -qE 'Failing|[1-9][0-9]* failing|Errors|SCRIPT ERROR'; then
        fails="$(printf '%s' "$out" | grep -iE 'failing|error' | head -5 | paste -sd'; ' -)"
        log "$r: GUT RED — $fails"
        emergency_enqueue "$r" "godot GUT" "${fails:-see log}"
      else
        log "$r: GUT green ($(printf '%s' "$out" | grep -oiE '[0-9]+ passed' | tail -1))"
      fi
    done < <(find "$wt" -maxdepth 3 -type f -name project.godot -print0 2>/dev/null)
  fi

  tw_close "$rd" "$wt"
  log "$r: suite wall time $(( $(date +%s) - REPO_T0 ))s"
done

tw_retry_deferred
log "=== test-health sweep complete ==="
log "total sweep wall time $(( $(date +%s) - SWEEP_T0 ))s"
