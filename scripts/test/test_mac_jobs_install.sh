#!/usr/bin/env bash
# test_mac_jobs_install.sh - L2-mac-jobs: scripts/mac_jobs_install.sh renders the launchd plists from scripts/mac_jobs/templates to point at the live checkout.
# Dry-run is the default and must touch nothing; --apply saves the old plists first, only bootouts/bootstraps CHANGED labels, restores on a bootstrap failure; --rollback restores byte-for-byte.
# Hermetic: stub launchctl (lib_mac_fixture.sh), a sandbox LaunchAgents dir. The real launchd is never contacted. Mutants must each FAIL a scenario.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_mac_fixture.sh" || exit 1
INST="$MF_SCRIPTS/mac_jobs_install.sh"; TPL="$MF_SCRIPTS/mac_jobs/templates"
[ -f "$INST" ] && [ -d "$TPL" ] || { echo "  FAIL: installer / templates missing"; exit 1; }
mf_init
trap 'safe_rm_rf "$T"' EXIT
fails=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
RN=0
render() { sed -e "s|@LIVE@|$2|g" -e "s|@HOME@|$HOME|g" "$TPL/$1.plist"; }
snap() { ( cd "$AGENTS" && for f in *.plist; do [ -e "$f" ] && { printf '%s ' "$f"; cksum < "$f"; }; done ) 2>/dev/null; }
fresh() { # new sandbox: AGENTS with a mix of old (interactive path), identical (already live) and absent plists; a complete live dir
  RN=$((RN+1)); export OVN_MAC_STATE="$T/st$RN" LIVE="$T/home/LocalProjects/live$RN" AGENTS="$T/home/Library/LA$RN"; mkdir -p "$OVN_MAC_STATE" "$AGENTS" "$LIVE/.git"; : > "$CALLS"; : > "$T/launchctl.table"
  OLDLIVE="$T/home/LocalProjects/shared"
  for t in "$TPL"/*.plist; do
    l="$(basename "$t" .plist)"
    case "$l" in
      com.shrike.claudequeuebridge|com.shrike.qa-staging-export) render "$l" "$OLDLIVE" > "$AGENTS/$l.plist";;   # old: interactive checkout path
      com.shrike.box-deadman) render "$l" "$LIVE" > "$AGENTS/$l.plist";;                                          # already identical to the new render
      *) :;;                                                                                                       # absent: NEW
    esac
  done
  for p in $(grep -ho '@LIVE@/[^<]*' "$TPL"/*.plist | sed "s|@LIVE@|$LIVE|"); do mkdir -p "$(dirname "$p")"; : > "$p"; done
  : > "$LIVE/.git/ovn_live_checkout"
}
inst() { MAC_LIVE_DIR="$LIVE" MAC_LAUNCH_AGENTS_DIR="$AGENTS" MAC_JOBS_UID=501 bash "${INSTS:-$INST}" "$@" > "$T/out.txt" 2>&1 < /dev/null; RC=$?; }
lc() { grep -c "^launchctl $1" "$CALLS"; }

echo "== dry run is the default"
fresh; before="$(snap)"; inst
chk "dry-run: every plist byte-identical afterwards, no file added, launchctl never called, no backup dir" bash -c "[ \"\$(cd '$AGENTS' && for f in *.plist; do printf '%s ' \$f; cksum < \$f; done)\" = \"\$(cat <<'EOS'
$before
EOS
)\" ] && ! grep -q '^launchctl' '$CALLS' && [ ! -d '$OVN_MAC_STATE/plist_backups' ]"
chk "dry-run reports CHANGED / NEW / UNCHANGED and prints a unified diff" bash -c "grep -q '^CHANGED    com.shrike.claudequeuebridge' '$T/out.txt' && grep -q '^NEW        com.shrike.vercel-state-check' '$T/out.txt' && grep -q '^UNCHANGED  com.shrike.box-deadman' '$T/out.txt' && grep -q '^    +++' '$T/out.txt' && grep -q 'DRY RUN' '$T/out.txt'"
chk "dry-run diff shows the interactive path being replaced by the live path" bash -c "grep -q -- '-.*LocalProjects/shared/scripts/overnight-queue/claude_queue_bridge.sh' '$T/out.txt' && grep -q -- '+.*live$RN/scripts/overnight-queue/claude_queue_bridge.sh' '$T/out.txt'"
chk "dry-run rc 0" test "$RC" = 0

echo "== apply preconditions"
fresh; rm -f "$LIVE/.git/ovn_live_checkout"; inst --apply
chk "no live-checkout marker: REFUSED rc 2, nothing written, launchctl not called" bash -c "[ $RC -eq 2 ] && grep -q REFUSED '$T/out.txt' && ! grep -q '^launchctl' '$CALLS' && [ ! -e '$AGENTS/com.shrike.mac-live-sync.plist' ]"
fresh; rm -f "$LIVE/scripts/mac_jobs_health.sh"; inst --apply
chk "a script a plist references is missing in the live checkout: REFUSED, names it" bash -c "[ $RC -eq 2 ] && grep -q 'mac_jobs_health.sh' '$T/out.txt' && ! grep -q '^launchctl' '$CALLS'"

echo "== apply"
fresh; before="$(snap)"; inst --apply; arc=$RC
chk "apply rc 0, every template installed, rendered with the live path and the real HOME" bash -c "[ $arc -eq 0 ] && [ \$(ls '$AGENTS'/*.plist | wc -l) -eq \$(ls '$TPL'/*.plist | wc -l) ] && grep -q '$LIVE/scripts/mac_live_sync.sh' '$AGENTS/com.shrike.mac-live-sync.plist' && grep -q '$HOME/fleet_review/run_review.sh' '$AGENTS/com.shrike.fleet-review.plist'"
chk "no unrendered @LIVE@/@HOME@ placeholder anywhere, every installed file is a valid plist" bash -c "! grep -l '@LIVE@\|@HOME@' '$AGENTS'/*.plist && for f in '$AGENTS'/*.plist; do python3 -c 'import plistlib,sys; plistlib.load(open(sys.argv[1],\"rb\"))' \"\$f\" || exit 1; done"
B="$(ls -d "$OVN_MAC_STATE"/plist_backups/*/ | head -1)"
chk "the old plists were saved byte-for-byte before being replaced" bash -c "cmp -s '$B/com.shrike.claudequeuebridge.plist' <(sed -e 's|@LIVE@|$OLDLIVE|g' -e 's|@HOME@|$HOME|g' '$TPL/com.shrike.claudequeuebridge.plist')"
chk "launchctl bootout+bootstrap issued for the CHANGED label (claudequeuebridge)" bash -c "grep -q '^launchctl bootout gui/501/com.shrike.claudequeuebridge' '$CALLS' && grep -q '^launchctl bootstrap gui/501 $AGENTS/com.shrike.claudequeuebridge.plist' '$CALLS'"
chk "the UNCHANGED label (box-deadman) was NOT touched: no bootout, no bootstrap" bash -c "! grep -q 'box-deadman' '$CALLS'"
chk "only bootout/bootstrap/list are ever used (no kickstart/load/unload/remove)" bash -c "! grep '^launchctl' '$CALLS' | grep -vE '^launchctl (bootout|bootstrap|list)'"
inst --apply; : > "$CALLS"; inst --apply
chk "re-apply is idempotent: 'nothing to do', no launchctl call" bash -c "grep -q 'nothing to do' '$T/out.txt' && ! grep -q '^launchctl' '$CALLS'"

echo "== bootstrap failure restores the old plist"
fresh; echo "com.shrike.claudequeuebridge" > "$T/launchctl.bootstrap_fail"; oldsum="$(cksum < "$AGENTS/com.shrike.claudequeuebridge.plist")"; inst --apply
chk "rc 1, the failing label's previous plist is back byte-for-byte, the failure is reported" bash -c "[ $RC -eq 1 ] && [ \"\$(cksum < '$AGENTS/com.shrike.claudequeuebridge.plist')\" = '$oldsum' ] && grep -q 'FAILED    com.shrike.claudequeuebridge' '$T/out.txt'"
rm -f "$T/launchctl.bootstrap_fail"

echo "== rollback"
fresh; before="$(snap)"; inst --apply; TS="$(ls "$OVN_MAC_STATE/plist_backups" | head -1)"; : > "$CALLS"
inst --rollback
chk "rollback dry-run: reports RESTORE/REMOVE, changes nothing" bash -c "grep -q 'RESTORE com.shrike.claudequeuebridge' '$T/out.txt' && grep -q 'REMOVE  com.shrike.vercel-state-check' '$T/out.txt' && ! grep -q '^launchctl' '$CALLS' && grep -q '$LIVE/scripts' '$AGENTS/com.shrike.claudequeuebridge.plist'"
inst --rollback "$TS" --apply
chk "rollback --apply: restored plists are byte-identical to the pre-install ones and new ones are removed" bash -c "[ \"\$(cd '$AGENTS' && for f in *.plist; do printf '%s ' \$f; cksum < \$f; done)\" = \"\$(cat <<'EOS'
$before
EOS
)\" ]"
chk "rollback --apply: bootout issued for the removed labels and bootstrap for the restored ones" bash -c "grep -q '^launchctl bootout gui/501/com.shrike.vercel-state-check' '$CALLS' && grep -q '^launchctl bootstrap gui/501 $AGENTS/com.shrike.claudequeuebridge.plist' '$CALLS'"

echo "== --only"
fresh; inst --only com.shrike.claudequeuebridge --apply
chk "--only touches exactly one label" bash -c "[ \$(ls '$AGENTS'/*.plist | wc -l) -eq 3 ] && [ \$(grep -c '^launchctl bootstrap' '$CALLS') -eq 1 ]"

echo "== mutants"
MUT="$T/mut"; mkdir -p "$MUT/mac_jobs"; cp "$MF_SCRIPTS"/mac_*.sh "$MUT/"; cp -R "$TPL" "$MUT/mac_jobs/templates"
mutant() { mutate "$INST" "$MUT/mac_jobs_install.sh" "$2" "$3" || { ok "mutant $1: anchor exists" 1; return 1; }; }
if mutant dry-run-writes 'if [ "$APPLY" != 1 ]; then
  [ -n "$missing" ]' 'if false; then
  [ -n "$missing" ]'; then
  fresh; before="$(snap)"; INSTS="$MUT/mac_jobs_install.sh" inst
  chk "M1 (dry-run applies) is caught: plists changed without --apply" bash -c "[ \"\$(cd '$AGENTS' && for f in *.plist; do printf '%s ' \$f; cksum < \$f; done)\" != \"\$(cat <<'EOS'
$before
EOS
)\" ]"
fi
if mutant no-marker-check '[ -f "$LIVE/.git/ovn_live_checkout" ] || { echo "REFUSED: $LIVE is not a live checkout' ': || { echo "REFUSED: $LIVE is not a live checkout'; then
  fresh; rm -f "$LIVE/.git/ovn_live_checkout"; INSTS="$MUT/mac_jobs_install.sh" inst --apply
  chk "M2 (no live-marker precondition) is caught: it installed pointing at a non-live dir" bash -c "[ -e '$AGENTS/com.shrike.mac-live-sync.plist' ]"
fi
if mutant no-restore 'if [ "$had" = 1 ]; then cp "$BK/$label.plist"' 'if false; then cp "$BK/$label.plist"'; then
  fresh; echo "com.shrike.claudequeuebridge" > "$T/launchctl.bootstrap_fail"; oldsum="$(cksum < "$AGENTS/com.shrike.claudequeuebridge.plist")"; INSTS="$MUT/mac_jobs_install.sh" inst --apply
  chk "M3 (no restore on bootstrap failure) is caught: the broken new plist stays" bash -c "[ \"\$(cksum < '$AGENTS/com.shrike.claudequeuebridge.plist')\" != '$oldsum' ]"
  rm -f "$T/launchctl.bootstrap_fail"
fi
if mutant touch-unchanged 'elif cmp -s "$cur" "$R/$label.plist"; then' 'elif false; then'; then
  fresh; INSTS="$MUT/mac_jobs_install.sh" inst --apply
  chk "M4 (re-bootstraps unchanged labels) is caught: box-deadman was booted although identical" bash -c "grep -q 'box-deadman' '$CALLS'"
fi
if mutant no-backup 'if [ -f "$AGENTS/$label.plist" ]; then cp "$AGENTS/$label.plist" "$BK/$label.plist"; else : > "$BK/$label.new"; fi' ':'; then
  fresh; INSTS="$MUT/mac_jobs_install.sh" inst --apply
  chk "M5 (old plists not saved) is caught: no backup of claudequeuebridge" bash -c "[ ! -e \"\$(ls -d '$OVN_MAC_STATE'/plist_backups/*/ | head -1)com.shrike.claudequeuebridge.plist\" ]"
fi

echo; echo "mac_jobs_install: $((n-fails))/$n passed"; [ "$fails" = 0 ]
