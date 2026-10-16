#!/usr/bin/env bash
# 2026-10-16 (box home wipe): hermetic test of ops/box_recover.sh (fake HOME via RC_HOME, fake drive, stub crontab, throwaway ssh key). Nothing real is touched, no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OPS="$HERE/../../ops"; REC="$OPS/box_recover.sh"; BAK="$OPS/box_home_backup.sh"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }

W="$(mktemp -d "${TMPDIR:-/tmp}/rctest.XXXXXX")" || { echo "mktemp failed: abort" >&2; exit 2; }
case "$W" in /*/rctest.??????) ;; *) echo "unsafe scratch dir '$W': abort" >&2; exit 2;; esac
[ -d "$W" ] && [ "$W" != "/" ] && [ "$W" != "${HOME:-/nonexistent}" ] || { echo "unsafe scratch dir: abort" >&2; exit 2; }
cleanup(){ case "$W" in /*/rctest.??????) find "$W" -mindepth 1 -depth -delete 2>/dev/null; rmdir "$W" 2>/dev/null;; esac; }
trap cleanup EXIT

# stub crontab on PATH: state file under $W
mkdir -p "$W/bin"; : > "$W/crontab.state"
cat > "$W/bin/crontab" <<EOS
#!/bin/sh
if [ "\$1" = "-l" ]; then cat "$W/crontab.state"; else cat > "$W/crontab.state"; fi
EOS
chmod +x "$W/bin/crontab"
export PATH="$W/bin:$PATH"
export GIT_CONFIG_NOSYSTEM=1

rc(){ RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" "$@"; }
SKIPALL="--skip-godot --skip-aider --skip-hostkey --skip-repos --no-cron"

echo "== dry-run changes nothing and prints the plan"
RH="$W/h1"; mkdir -p "$RH"
rc --dry-run >"$W/o1" 2>&1; rcd=$?
ok "dry-run exits 0" "[ $rcd = 0 ]"
ok "dry-run prints the plan for every step" "grep -q 'DRY-RUN would: git config' '$W/o1' && grep -q 'DRY-RUN would: scan github.com' '$W/o1' && grep -q 'DRY-RUN would: download' '$W/o1' && grep -q 'DRY-RUN would: python3.12' '$W/o1' && grep -q 'DRY-RUN would: restore ~/overnight-queue' '$W/o1' && grep -q 'DRY-RUN would: clone repos' '$W/o1' && grep -q 'DRY-RUN would: add the two backup cron' '$W/o1'"
ok "dry-run names the clone-of-mirror fallback when no snapshot exists" "grep -q 'overnight-live' '$W/o1'"
ok "dry-run created nothing in the fake home and nothing in the crontab" "[ -z \"\$(ls -A '$RH')\" ] && [ ! -s '$W/crontab.state' ]"

echo "== refuses a non-empty ~/overnight-queue"
RH="$W/h2"; mkdir -p "$RH/overnight-queue"; echo precious > "$RH/overnight-queue/keep.me"
rc $SKIPALL >"$W/o2" 2>&1; rc2=$?
ok "exit 3 with REFUSING" "[ $rc2 = 3 ] && grep -q REFUSING '$W/o2'"
ok "existing file untouched and no other step ran (no dotfiles, no gitconfig)" "[ \"\$(cat '$RH/overnight-queue/keep.me')\" = precious ] && [ ! -e '$RH/.bashrc' ] && [ ! -e '$RH/.gitconfig' ]"
ok "also refused in dry-run" "RC_HOME='$RH' bash '$REC' --dry-run >/dev/null 2>&1; [ \$? = 3 ]"
ok "an EMPTY queue dir is allowed" "mkdir -p '$W/h2b/overnight-queue' && RC_HOME='$W/h2b' RC_BACKUPS='$W/nodrive' bash '$REC' --dry-run >/dev/null 2>&1"

echo "== restore from a real backup snapshot made by box_home_backup.sh"
SRC="$W/srchome"; mkdir -p "$SRC/.ssh" "$SRC/overnight-queue/state" "$SRC/overnight-queue/ops"
echo K > "$SRC/.ssh/id_ed25519"; echo code > "$SRC/overnight-queue/queue.sh"; echo st > "$SRC/overnight-queue/state/s.json"
mkdir -p "$W/drive/box-backups"
BB_HOME="$SRC" BB_DEST="$W/drive/box-backups" BB_ALLOW_SAME_FS=1 BB_DAY=Wed bash "$BAK" daily >/dev/null 2>&1
echo st2 > "$SRC/overnight-queue/state/s.json"
BB_HOME="$SRC" BB_DEST="$W/drive/box-backups" BB_ALLOW_SAME_FS=1 BB_HOUR=2026101612 bash "$BAK" hourly >/dev/null 2>&1
sleep 1; touch "$W/drive/box-backups/hourly/2026101612"
RH="$W/h3"; mkdir -p "$RH"
rc --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o3" 2>&1; rc3=$?
ok "recovery exits 0" "[ $rc3 = 0 ]"
ok "queue code restored from the daily snapshot" "[ \"\$(cat '$RH/overnight-queue/queue.sh')\" = code ]"
ok "newer hourly state overlaid" "[ \"\$(cat '$RH/overnight-queue/state/s.json')\" = st2 ]"
ok "repos/ logs/ reports/ recreated empty" "[ -d '$RH/overnight-queue/repos' ] && [ -d '$RH/overnight-queue/logs' ] && [ -d '$RH/overnight-queue/reports' ]"
ok "~/.ssh restored with 700 and the key" "[ -f '$RH/.ssh/id_ed25519' ] && [ \"\$(stat -c %a '$RH/.ssh' 2>/dev/null || stat -f %Lp '$RH/.ssh')\" = 700 ]"
ok "git identity set in the fake home only" "[ \"\$(HOME='$RH' git config --global user.name)\" = 'Mark Hintermeister' ] && [ \"\$(HOME='$RH' git config --global user.email)\" = 'Markhint22@yahoo.com' ]"
ok "dotfiles created" "[ -f '$RH/.bashrc' ] && [ -f '$RH/.profile' ]"
ok "the summary lists what was done" "grep -q 'SUMMARY (DONE)' '$W/o3' && grep -q 'overnight-queue' '$W/o3'"
ok "crontab got exactly the two backup lines, marker once" "[ \"\$(grep -c box_home_backup.sh '$W/crontab.state')\" = 2 ] && [ \"\$(grep -c box_recover-backup-lines '$W/crontab.state')\" = 1 ] && ! grep -Eq 'run_all|reconcile|hygiene|promote|ovn_git_sync' '$W/crontab.state'"
RH="$W/h3"; rc --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >/dev/null 2>&1
ok "re-running the cron step is idempotent" "[ \"\$(grep -c box_home_backup.sh '$W/crontab.state')\" = 2 ]"

echo "== mirror fallback is used only when there is no snapshot (dry-run text)"
RH="$W/h4"; mkdir -p "$RH"
RC_HOME="$RH" RC_BACKUPS="$W/empty" bash "$REC" --dry-run >"$W/o4" 2>&1
ok "no snapshot => plan says git clone" "grep -q 'git clone of https://github.com/markhint22/shrike-ai-lab.git' '$W/o4'"

echo "== github host key fingerprint verification"
ssh-keygen -q -t ed25519 -N '' -f "$W/fake_key" >/dev/null 2>&1
echo "github.com $(cut -d' ' -f1,2 "$W/fake_key.pub")" > "$W/fake_hostline"
RH="$W/h5"; mkdir -p "$RH"
RC_GITHUB_KEYFILE="$W/fake_hostline" rc --skip-queue --skip-godot --skip-aider --skip-repos --no-cron >"$W/o5" 2>&1; rc5=$?
ok "a wrong host key is REJECTED (non-zero, not added)" "[ $rc5 != 0 ] && grep -q MISMATCH '$W/o5' && [ ! -s '$RH/.ssh/known_hosts' ]"
# positive path: temporarily pin the fake key's fingerprint in a copy of the script
FP="$(ssh-keygen -lf "$W/fake_key.pub" | awk '{print $2}')"
sed "s|^GH_FPR=.*|GH_FPR=\"$FP\"|" "$REC" > "$W/rec_pinned.sh"
RH="$W/h6"; mkdir -p "$RH"
RC_HOME="$RH" RC_BACKUPS="$W/empty" RC_GITHUB_KEYFILE="$W/fake_hostline" bash "$W/rec_pinned.sh" --skip-queue --skip-godot --skip-aider --skip-repos --no-cron >"$W/o6" 2>&1
ok "a key matching the pinned fingerprint is added to known_hosts" "grep -q 'github.com ssh-ed25519' '$RH/.ssh/known_hosts'"
ok "the real script pins the documented GitHub fingerprint" "grep -q 'GH_FPR=\"SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU\"' '$REC'"

echo "== godot SHA512 check"
echo notazip > "$W/fake.zip"
RH="$W/h7"; mkdir -p "$RH"
RC_GODOT_ZIP="$W/fake.zip" rc --skip-queue --skip-aider --skip-hostkey --skip-repos --no-cron >"$W/o7" 2>&1; rc7=$?
ok "a zip with the wrong SHA512 is NOT installed" "[ $rc7 != 0 ] && grep -q 'SHA512 MISMATCH' '$W/o7' && [ ! -e '$RH/godot/godot' ]"

echo "== repo clones from bundles"
mkdir -p "$W/mk/r"; ( cd "$W/mk/r" && git init -q && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m init && git bundle create "$W/bundles_r1.bundle" --all >/dev/null 2>&1 ); mkdir -p "$W/bundles"; mv "$W/bundles_r1.bundle" "$W/bundles/iptv_apps.bundle"
RH="$W/h8"; mkdir -p "$RH"
RC_REPOS="iptv_apps" rc --skip-godot --skip-aider --skip-hostkey --no-cron --bundles "$W/bundles" >"$W/o8" 2>&1
ok "clone from bundle, origin set to github ssh url" "[ -d '$RH/overnight-queue/repos/iptv_apps/.git' ] && [ \"\$(git -C '$RH/overnight-queue/repos/iptv_apps' remote get-url origin)\" = 'git@github.com:markhint22/iptv_apps.git' ]"

echo; echo "box_recover: pass=$P fail=$F"
[ "$F" = 0 ]
