#!/usr/bin/env bash
# Regression test: ovn_git_sync.sh (2026-09-10) — the overnight-queue directory's own
# git-history sync. Established after discovering the git-tracked mirror in shrike-ai-lab
# had rotted since 2026-08-25 (scripts kept evolving on the server, nobody synced them
# back). Verifies: a no-op cycle (nothing changed) makes no commit; a real change gets
# committed and pushed; the commit message is dated; and it never touches anything outside
# its own sandboxed repo (tested against a throwaway git repo + bare "origin", never the
# real overnight-queue tree).
set -uo pipefail
G="${OVN_GIT_SYNC:-$HOME/overnight-queue/ovn_git_sync.sh}"
[ -f "$G" ] || { echo "  SKIP: $G not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# bare "origin" to push against, standing in for GitHub
BARE="$tmp/origin.git"
git init -q --bare "$BARE"

WD="$tmp/home/overnight-queue"
mkdir -p "$WD"
( cd "$WD" && git init -q && git config user.email t@t.com && git config user.name t \
  && git remote add origin "$BARE" \
  && echo "v1" > queue.sh && git add -A && git commit -q -m init \
  && git checkout -q -b overnight-live && git push -q -u origin overnight-live )

run(){ ( HOME="$tmp/home" bash "$G" ); }

# --- A: no-op cycle (nothing changed) -> no new commit, no crash ---
before="$(cd "$WD" && git rev-parse HEAD)"
run
after="$(cd "$WD" && git rev-parse HEAD)"
ok "no-op cycle makes no new commit" "[ '$before' = '$after' ]"

# --- B: a real change gets committed and pushed ---
echo "v2" > "$WD/queue.sh"
run
after2="$(cd "$WD" && git rev-parse HEAD)"
ok "a real change produces a new commit" "[ '$after' != '$after2' ]"
ok "commit message is dated auto-sync" "cd '$WD' && git log -1 --format=%s | grep -qE '^auto-sync [0-9]{4}-[0-9]{2}-[0-9]{2}'"
remote_head="$(cd "$BARE" && git rev-parse overnight-live)"
ok "the change was actually pushed to origin, not just committed locally" "[ '$remote_head' = '$after2' ]"

# --- C: a second no-op cycle right after a real sync also makes no commit ---
before3="$(cd "$WD" && git rev-parse HEAD)"
run
after3="$(cd "$WD" && git rev-parse HEAD)"
ok "immediately-following no-op cycle stays a no-op" "[ '$before3' = '$after3' ]"

echo "git_sync: $P passed, $F failed"
[ "$F" -eq 0 ]
