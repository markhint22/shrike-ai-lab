#!/usr/bin/env bash
# ovn_slo_export_tip.sh - MAC side of the deploy-lag SLO (package L5-fleet-slo, 2026-10-18). Publishes "what is the claude/feature tip, and when was each commit made" to the GPU box
# as state/claude_feature_tip.json, so scripts/ovn_fleet_slo.py can say "the box runs code N commits / H hours behind the branch".
#
# It NEVER touches an interactive checkout (2026-10-17: an interleaved pull in the shared checkout left it on a detached HEAD in a 1244-commit rebase): it keeps its OWN bare
# clone ($OVN_SLO_TIP_CACHE, default ~/.ovn_slo_tip.git) and only ever runs `git fetch` on it. Read-only on the box except the one state file (written to a temp name, then mv'd, only after
# the JSON proves non-empty: a failed export never replaces a good file with an empty one).
#
# usage:  ovn_slo_export_tip.sh [--stdout]        (--stdout: print the JSON, send nothing)
# env:    OVN_SLO_TIP_REMOTE (default: origin URL of the checkout this script lives in, read-only), OVN_SLO_TIP_CACHE, OVN_SLO_BOX (default mhintermeister@100.79.64.64 then the LAN address),
#         OVN_SLO_BOX_DIR (default overnight-queue), OVN_SLO_SSH (default 'ssh -o BatchMode=yes -o ConnectTimeout=10'), OVN_SLO_BRANCH (default claude/feature), OVN_SLO_PATH (scripts/overnight-queue)
# schedule (proposed, NOT installed): hourly from launchd/cron on the Mac, e.g.  17 * * * * bash $HOME/LocalProjects/shared/scripts/overnight-queue/scripts/ovn_slo_export_tip.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE="${OVN_SLO_TIP_CACHE:-$HOME/.ovn_slo_tip.git}"
BRANCH="${OVN_SLO_BRANCH:-claude/feature}"
PATHSPEC="${OVN_SLO_PATH-scripts/overnight-queue}"
REMOTE="${OVN_SLO_TIP_REMOTE:-$(git -C "$HERE" remote get-url origin 2>/dev/null)}"
SSHC="${OVN_SLO_SSH:-ssh -o BatchMode=yes -o ConnectTimeout=10}"
BOXES="${OVN_SLO_BOX:-mhintermeister@100.79.64.64 mhintermeister@192.168.68.145}"
BOXDIR="${OVN_SLO_BOX_DIR:-overnight-queue}"
STDOUT=0; [ "${1:-}" = "--stdout" ] && STDOUT=1
die(){ echo "ovn_slo_export_tip: $*" >&2; exit 1; }
[ -n "$REMOTE" ] || die "no remote (set OVN_SLO_TIP_REMOTE)"
case "$CACHE" in /*) ;; *) die "OVN_SLO_TIP_CACHE must be absolute";; esac
if [ ! -d "$CACHE" ]; then
  git clone -q --bare --single-branch --branch "$BRANCH" "$REMOTE" "$CACHE" 2>/dev/null || die "clone of $REMOTE failed"
else
  git --git-dir="$CACHE" fetch -q "$REMOTE" "+refs/heads/$BRANCH:refs/heads/$BRANCH" 2>/dev/null || die "fetch of $BRANCH failed (the cache is left as it was)"
fi
J="$(python3 "$HERE/ovn_fleet_slo.py" --export-tip --git-dir "$CACHE" --ref "refs/heads/$BRANCH" --path "$PATHSPEC" --limit "${OVN_SLO_LIMIT:-300}")" || die "export failed"
printf '%s' "$J" | python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("ok") and d.get("commits") else 1)' || die "export has no commits: nothing sent"
if [ "$STDOUT" = 1 ]; then printf '%s\n' "$J"; exit 0; fi
for b in $BOXES; do
  # shellcheck disable=SC2086
  if printf '%s\n' "$J" | $SSHC "$b" "cat > $BOXDIR/state/.claude_feature_tip.tmp && mv -f $BOXDIR/state/.claude_feature_tip.tmp $BOXDIR/state/claude_feature_tip.json" 2>/dev/null; then echo "ovn_slo_export_tip: sent to $b"; exit 0; fi
done
die "could not reach the box on any address"
