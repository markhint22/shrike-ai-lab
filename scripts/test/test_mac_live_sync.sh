#!/usr/bin/env bash
# test_mac_live_sync.sh - L2-mac-jobs: scripts/mac_live_sync.sh keeps the dedicated live checkout current and RECOVERS the incident states (2026-10-17/18: detached HEAD in a half-done rebase).
# Hermetic (lib_mac_fixture.sh): sandbox HOME, local bare origin, stub curl/ssh. Mutants (edited copies of the script) must each make the guarding scenario FAIL.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_mac_fixture.sh" || exit 1
SYNC="$MF_SCRIPTS/mac_live_sync.sh"; [ -f "$SYNC" ] && [ -f "$MF_SCRIPTS/mac_lib.sh" ] || { echo "  FAIL: mac_live_sync.sh / mac_lib.sh missing"; exit 1; }
mf_init
trap 'safe_rm_rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
sync_() { # sync_ <mode> [script]
  local m="$1" s="${2:-$SYNC}"; OVN_MAC_JOBS="$m" MAC_LIVE_DIR="$LIVE" MAC_LIVE_ORIGIN="$ORIGIN" bash "$s" > "$T/out.txt" 2>&1
}
status() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$OVN_MAC_STATE/live_sync.json" "$1" 2>/dev/null; }
RN=0
reset_live() { RN=$((RN+1)); export LIVE="$T/home/LocalProjects/live$RN" OVN_MAC_STATE="$T/state$RN"; mkdir -p "$OVN_MAC_STATE"; : > "$CALLS"; }   # a fresh path per scenario (safe_rm_rf refuses git checkout roots)
lhead() { git -C "$LIVE" rev-parse --short HEAD; }

echo "== off / shadow / clone"
reset_live; sync_ off
chk "off: exits 0, creates nothing (no checkout, no status file)" bash -c "[ ! -e '$LIVE' ] && [ ! -e '$OVN_MAC_STATE/live_sync.json' ]"
sync_ shadow
chk "shadow + missing checkout: does NOT clone, reports state=missing" bash -c "[ ! -e '$LIVE' ] && [ \"$(status state)\" = missing ]"
sync_ enforce
chk "enforce clones: branch develop-live, HEAD == origin/develop, live marker written" bash -c "[ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && [ '$(lhead)' = '$(mf_origin_head)' ] && [ -f '$LIVE/.git/ovn_live_checkout' ]"
chk "enforce clone: tracks origin/develop" bash -c "[ \"\$(git -C '$LIVE' rev-parse --abbrev-ref develop-live@{upstream})\" = origin/develop ]"
chk "status ok + a sync heartbeat written" bash -c "[ \"$(status state)\" = ok ] && [ -s '$OVN_MAC_STATE/hb/mac-live-sync' ]"

echo "== fast-forward"
mf_up_commit scripts/job.sh "job v2" "upstream v2"
sync_ shadow
chk "shadow: behind origin -> NOT fast-forwarded, state=behind reported" bash -c "[ '$(lhead)' != '$(mf_origin_head)' ] && [ \"$(status state)\" = behind ] && [ \"$(status behind)\" = 1 ]"
sync_ enforce
chk "enforce: fast-forwards to origin/develop" bash -c "[ '$(lhead)' = '$(mf_origin_head)' ] && grep -q 'job v2' '$LIVE/scripts/job.sh'"

echo "== INCIDENT: detached HEAD + stale rebase-merge"
mf_wedge_rebase "$LIVE" scripts/job.sh || { echo "  FAIL fixture: could not wedge a rebase"; exit 1; }
chk "fixture: really wedged (rebase-merge dir + detached HEAD)" bash -c "[ -d '$LIVE/.git/rebase-merge' ] && ! git -C '$LIVE' symbolic-ref -q HEAD >/dev/null"
sync_ shadow
chk "shadow: wedged checkout is REPORTED (wedged_unrepaired) and left exactly as is" bash -c "[ \"$(status state)\" = wedged_unrepaired ] && [ -d '$LIVE/.git/rebase-merge' ]"
chk "shadow: emergency alert pushed to the relay with X-Ovn-Level: emergency" bash -c "grep -q 'X-Ovn-Level: emergency' '$CALLS' && grep -q 'wedged' '$OVN_MAC_STATE/alerts.log'"
sync_ enforce
chk "enforce: recovered - attached to develop-live, HEAD == origin/develop, no rebase-merge dir, clean tree" bash -c "[ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && [ '$(lhead)' = '$(mf_origin_head)' ] && [ ! -d '$LIVE/.git/rebase-merge' ] && [ -z \"\$(git -C '$LIVE' status --porcelain --untracked-files=no)\" ]"
chk "enforce: the local conflicting commit was kept on a rescue/ branch (nothing lost)" bash -c "git -C '$LIVE' branch --list 'rescue/*' | grep -q rescue && git -C '$LIVE' log -1 --format=%s \$(git -C '$LIVE' branch --list 'rescue/*' | head -1 | tr -d ' *') | grep -q 'local conflicting'"
chk "enforce: state=recovered" bash -c "[ \"$(status state)\" = recovered ]"
sync_ enforce
chk "next run: ok again" bash -c "[ \"$(status state)\" = ok ]"

echo "== merge in progress"
mf_wedge_merge "$LIVE" scripts/job.sh || { echo "  FAIL fixture: could not wedge a merge"; exit 1; }
sync_ enforce
chk "merge-in-progress recovered (no MERGE_HEAD, HEAD == origin)" bash -c "[ ! -f '$LIVE/.git/MERGE_HEAD' ] && [ '$(lhead)' = '$(mf_origin_head)' ] && [ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ]"

echo "== wrong branch / detached at an old commit"
git -C "$LIVE" checkout -q --detach HEAD~1; sync_ enforce
chk "detached HEAD (no operation) is re-attached and fast-forwarded" bash -c "[ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ] && [ '$(lhead)' = '$(mf_origin_head)' ]"
git -C "$LIVE" checkout -q -b scratch-branch; sync_ enforce
chk "wrong branch is recovered to develop-live" bash -c "[ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ]"

echo "== stale index.lock"
git -C "$LIVE" checkout -q -B develop-live origin/develop; git -C "$LIVE" checkout -q --detach
: > "$LIVE/.git/index.lock"; touch -t 202001010000 "$LIVE/.git/index.lock"; sync_ enforce
chk "an old index.lock (no git running) is cleared during recovery" bash -c "[ ! -e '$LIVE/.git/index.lock' ] && [ \"\$(git -C '$LIVE' symbolic-ref --short HEAD)\" = develop-live ]"

echo "== dirty: refuse"
printf 'hand edit\n' >> "$LIVE/README.md"; : > "$CALLS"
sync_ enforce
chk "dirty tracked file: REFUSED, content untouched, state=dirty" bash -c "[ \"$(status state)\" = dirty ] && tail -1 '$LIVE/README.md' | grep -q 'hand edit'"
chk "dirty: emergency alert" bash -c "grep -q 'X-Ovn-Level: emergency' '$CALLS'"
git -C "$LIVE" checkout -q -- README.md
mf_up_commit README.md "readme 2" "up readme"; printf 'x\n' >> "$LIVE/README.md"; sync_ enforce
chk "dirty + behind: still refused (no ff over a dirty tree)" bash -c "[ \"$(status state)\" = dirty ] && [ '$(lhead)' != '$(mf_origin_head)' ]"
git -C "$LIVE" checkout -q -- README.md; sync_ enforce

echo "== diverged"
git -C "$LIVE" checkout -q -B develop-live origin/develop
printf 'queue local\n' > "$LIVE/CLAUDE_QUEUE.md"; git -C "$LIVE" commit -q -am "bridge unpushed"
mf_up_commit scripts/job.sh "job v3" "up v3"; sync_ enforce
chk "diverged ONLY in queue docs: rescued + reset to origin/develop" bash -c "[ '$(lhead)' = '$(mf_origin_head)' ] && git -C '$LIVE' branch --list 'rescue/*' | grep -q rescue"
git -C "$LIVE" checkout -q -B develop-live origin/develop
printf 'code local\n' > "$LIVE/scripts/job.sh"; git -C "$LIVE" commit -q -am "local code change"
mf_up_commit README.md "readme 3" "up readme3"; : > "$CALLS"; before="$(lhead)"; sync_ enforce
chk "diverged in CODE: REFUSED, local commit preserved, state=diverged" bash -c "[ \"$(status state)\" = diverged ] && [ '$(lhead)' = '$before' ]"
chk "diverged in code: emergency alert" bash -c "grep -q 'X-Ovn-Level: emergency' '$CALLS'"
git -C "$LIVE" checkout -q -B develop-live origin/develop

echo "== lock + fetch failure"
mkdir -p "$OVN_MAC_STATE/live_sync.lock"; echo $$ > "$OVN_MAC_STATE/live_sync.lock/pid"; : > "$OVN_MAC_STATE/live_sync.log"
sync_ enforce
chk "lock held by a live pid: this tick is skipped" grep -q "holds the lock" "$OVN_MAC_STATE/live_sync.log"
rm -f "$OVN_MAC_STATE/live_sync.lock/pid"; rmdir "$OVN_MAC_STATE/live_sync.lock"
git -C "$LIVE" remote set-url origin "$T/does-not-exist.git"; sync_ enforce
chk "fetch failure: state=fetch_failed, checkout untouched, still exit 0" bash -c "[ \"$(status state)\" = fetch_failed ]"
git -C "$LIVE" remote set-url origin "$ORIGIN"

echo "== mutants (each guarded behaviour must be load-bearing)"
MUT="$T/mut"; mkdir -p "$MUT"; cp "$MF_SCRIPTS"/mac_*.sh "$MUT/"
mutant() { # name old new  -> prepares $MUT/mac_live_sync.sh from the real script
  mutate "$SYNC" "$MUT/mac_live_sync.sh" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }
}
# M1: recovery never aborts the half-done operation
if mutant "no-abort" '  mac_git_abort_all "$D"
  if git -C "$D" checkout' '  if git -C "$D" checkout'; then
  reset_live; sync_ enforce; mf_wedge_rebase "$LIVE" scripts/job.sh; sync_ enforce "$MUT/mac_live_sync.sh"
  chk "M1 (no abort) is caught: the stale rebase-merge dir survives, so the recovery scenario FAILS" bash -c "[ -d '$LIVE/.git/rebase-merge' ] || [ \"$(status state)\" != recovered ]"
fi
# M2: shadow repairs too
if mutant "shadow-repairs" 'if [ "$MODE" != enforce ]; then
    say "SHADOW: wedged' 'if false; then
    say "SHADOW: wedged'; then
  reset_live; sync_ enforce; mf_wedge_rebase "$LIVE" scripts/job.sh; sync_ shadow "$MUT/mac_live_sync.sh"
  chk "M2 (shadow repairs) is caught: the wedged checkout was modified in shadow" bash -c "[ ! -d '$LIVE/.git/rebase-merge' ]"
fi
# M3: dirty tree is not refused
if mutant "no-dirty-refusal" 'if mac_git_dirty "$D"; then' 'if false; then'; then
  reset_live; sync_ enforce; mf_up_commit README.md "readme M3" "m3"; printf 'x\n' >> "$LIVE/README.md"; sync_ enforce "$MUT/mac_live_sync.sh"
  chk "M3 (no dirty refusal) is caught: state is no longer dirty / the tree was touched" bash -c "[ \"$(status state)\" != dirty ]"
fi
# M4: any divergence is reset (code commits lost)
if mutant "reset-any-divergence" 'if [ "$only_queue" = 1 ] && [ "$MODE" = enforce ]; then' 'if [ "$MODE" = enforce ]; then'; then
  reset_live; sync_ enforce; printf 'code local\n' > "$LIVE/scripts/job.sh"; git -C "$LIVE" commit -q -am "local code"; b="$(lhead)"
  mf_up_commit README.md "readme M4" "m4"; sync_ enforce "$MUT/mac_live_sync.sh"
  chk "M4 (reset any divergence) is caught: the local code commit is gone from HEAD" bash -c "[ '$(lhead)' != '$b' ]"
fi
# M5: non-fast-forward merge instead of --ff-only is NOT used; mutant makes ff a hard reset even when ahead (queue/code commit dropped)
if mutant "ff-ignores-ahead" 'if [ "$ahead" -eq 0 ]; then
  if [ "$MODE" != enforce ]' 'if true; then
  if [ "$MODE" != enforce ]'; then
  reset_live; sync_ enforce; printf 'code local\n' > "$LIVE/scripts/job.sh"; git -C "$LIVE" commit -q -am "local code"
  mf_up_commit README.md "readme M5" "m5"; sync_ enforce "$MUT/mac_live_sync.sh"
  chk "M5 (ff attempted while diverged) is caught: state becomes ff_failed instead of diverged" bash -c "[ \"$(status state)\" != diverged ]"
fi

echo; echo "mac_live_sync: $((n-fails))/$n passed"; [ "$fails" = 0 ]
