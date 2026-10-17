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

# stub crontab on PATH: state file under $W. Failure injection: $W/crontab.lfail = "<rc>|<stderr text>" makes `crontab -l` fail; $W/crontab.ifail makes installing fail.
mkdir -p "$W/bin"; : > "$W/crontab.state"
cat > "$W/bin/crontab" <<EOS
#!/bin/sh
if [ "\$1" = "-l" ]; then
  if [ -f "$W/crontab.lfail" ]; then IFS='|' read r m < "$W/crontab.lfail"; echo "\$m" >&2; exit "\$r"; fi
  cat "$W/crontab.state"
else
  [ -f "$W/crontab.ifail" ] && exit 1
  rm -f "$W/crontab.lfail"   # once a crontab exists, listing works
  if [ "\$1" = "-" ] || [ -z "\$1" ]; then cat > "$W/crontab.state"; else cat "\$1" > "$W/crontab.state"; fi
fi
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
ok "dry-run prints the plan for every step" "grep -q 'DRY-RUN would: git config' '$W/o1' && grep -q 'DRY-RUN would: scan github.com' '$W/o1' && grep -q 'DRY-RUN would: download' '$W/o1' && grep -q 'DRY-RUN would: python3.12' '$W/o1' && grep -q 'DRY-RUN would: restore ~/overnight-queue' '$W/o1' && grep -q 'DRY-RUN would: clone repos' '$W/o1' && grep -q 'DRY-RUN would: add the backup cron lines' '$W/o1'"
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
echo K > "$SRC/.ssh/id_ed25519"; echo code > "$SRC/overnight-queue/queue.sh"; cp "$BAK" "$SRC/overnight-queue/ops/box_home_backup.sh"; echo st > "$SRC/overnight-queue/state/s.json"
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
ok "crontab got the two backup lines + the heartbeat checks, marker once" "[ \"\$(grep -c box_home_backup.sh '$W/crontab.state')\" = 2 ] && grep -q '^53 6 .*heartbeat-daily.log -mmin -1560' '$W/crontab.state' && [ \"\$(grep -c box_recover-backup-lines '$W/crontab.state')\" = 1 ] && ! grep -Eq 'run_all|reconcile|hygiene|promote|ovn_git_sync' '$W/crontab.state'"
RH="$W/h3"; rc --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >/dev/null 2>&1
ok "re-running the cron step is idempotent" "[ \"\$(grep -c box_home_backup.sh '$W/crontab.state')\" = 2 ]"

echo "== crontab step (a): rc handling, always save the old crontab first"
cronstate(){ cat "$W/crontab.state"; }
RH="$W/h9"; mkdir -p "$RH/overnight-queue/ops"; cp "$BAK" "$RH/overnight-queue/ops/box_home_backup.sh"
printf '%s\n' '0 1 * * * /usr/bin/precious-job' '5 5 * * * other' > "$W/crontab.state"; cp "$W/crontab.state" "$W/cron.before"
echo "2|crontab: error while loading shared libraries" > "$W/crontab.lfail"
ndrv(){ ls "$W"/drive/box-backups/crontab.pre-recover.* 2>/dev/null | wc -l | tr -d " "; }
N0="$(ndrv)"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o9" 2>&1; r9=$?
ok "crontab -l failing with rc=2: step fails (exit 1), crontab byte-identical, no save file written anywhere, nothing installed" "[ $r9 = 1 ] && cmp -s '$W/crontab.state' '$W/cron.before' && grep -q 'NOT touching the crontab' '$W/o9' && [ \"\$(ndrv)\" = \"$N0\" ] && [ -z \"\$(ls '$RH'/crontab.pre-recover.* 2>/dev/null)\" ]"
echo "1|crontab: some other transient failure" > "$W/crontab.lfail"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o9b" 2>&1; r9=$?
ok "rc=1 WITHOUT 'no crontab for' is a failure too: crontab untouched" "[ $r9 = 1 ] && cmp -s '$W/crontab.state' '$W/cron.before'"
rm -f "$W/crontab.lfail"
echo "1|no crontab for mhintermeister" > "$W/crontab.lfail"; : > "$W/crontab.state"
RC_HOME="$RH" RC_BACKUPS="$W/nodrive_here" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o9c" 2>&1; r9=$?
ok "rc=1 + 'no crontab for' is an EMPTY crontab: lines installed, empty save written to ~ (drive absent)" "[ $r9 = 0 ] && [ \"\$(grep -c box_home_backup.sh '$W/crontab.state')\" = 2 ] && ls '$RH'/crontab.pre-recover.* >/dev/null"
rm -f "$W/crontab.lfail" "$RH"/crontab.pre-recover.*
cp "$W/cron.before" "$W/crontab.state"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o9d" 2>&1; r9=$?
SV="$(ls "$W"/drive/box-backups/crontab.pre-recover.* 2>/dev/null | tail -1)"
ok "existing crontab saved byte-for-byte on the backup drive (mounted) before replacement" "[ $r9 = 0 ] && [ -n '$SV' ] && cmp -s '$SV' '$W/cron.before' && grep -q 'saved to' '$W/o9d'"
ok "existing jobs are preserved in the new crontab alongside the added lines" "grep -q precious-job '$W/crontab.state' && grep -q 'other' '$W/crontab.state' && grep -c box_recover-backup-lines '$W/crontab.state' | grep -q '^1\$'"
ok "no save file landed in ~ when the drive is mounted" "[ -z \"\$(ls '$RH'/crontab.pre-recover.* 2>/dev/null)\" ]"
cp "$W/cron.before" "$W/crontab.state"; touch "$W/crontab.ifail"
RC_HOME="$RH" RC_BACKUPS="$W/nodrive_here" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o9e" 2>&1; r9=$?
ok "install failure: exit 1, old crontab still in place, and a save file exists in ~ to restore from" "[ $r9 = 1 ] && cmp -s '$W/crontab.state' '$W/cron.before' && ls '$RH'/crontab.pre-recover.* >/dev/null && grep -q 'crontab install FAILED' '$W/o9e'"
rm -f "$W/crontab.ifail" "$RH"/crontab.pre-recover.*

echo "== crontab step (b): backup lines only when ops/box_home_backup.sh exists"
RH="$W/h10"; mkdir -p "$RH/overnight-queue/ops"   # non-empty queue => use --skip-queue; no script inside
printf '%s\n' '9 9 * * * keepme' > "$W/crontab.state"; cp "$W/crontab.state" "$W/cron.before"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o10" 2>&1; r10=$?
ok "script absent: exit 1, crontab unchanged, message says why" "[ $r10 = 1 ] && cmp -s '$W/crontab.state' '$W/cron.before' && grep -q 'does not exist' '$W/o10' && grep -q 'FAILED: crontab' '$W/o10'"
ok "the plan text mentions the existence condition (dry-run)" "RC_HOME='$RH' RC_BACKUPS='$W/drive/box-backups' bash '$REC' --dry-run --skip-queue >'$W/o10b' 2>&1; grep -q 'ONLY if ops/box_home_backup.sh exists' '$W/o10b'"

echo "== the shipped heartbeat-staleness line is ACTIVE and does what it says"
RH="$W/h11"; mkdir -p "$RH/overnight-queue/ops" "$RH/overnight-queue/logs"; cp "$BAK" "$RH/overnight-queue/ops/box_home_backup.sh"; : > "$W/crontab.state"
mkdir -p "$W/hbdrive"
RC_HOME="$RH" RC_BACKUPS="$W/hbdrive" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >/dev/null 2>&1
HBLINE="$(grep '^53 6 ' "$W/crontab.state" | cut -d' ' -f6-)"
HBHLINE="$(grep '^54 6 ' "$W/crontab.state" | cut -d' ' -f6-)"
ok "an uncommented 53 6 DAILY heartbeat line and a 54 6 HOURLY heartbeat line are in the crontab" "[ -n '$HBLINE' ] && [ -n '$HBHLINE' ] && printf '%s' '$HBLINE' | grep -q 'heartbeat-daily.log' && printf '%s' '$HBHLINE' | grep -q 'heartbeat-hourly.log'"
: > "$W/hbdrive/heartbeat-daily.log"
sh -c "$HBLINE" >/dev/null 2>&1
ok "fresh heartbeat => no alert" "[ ! -s '$RH/overnight-queue/logs/box_backup_alert.log' ]"
touch -t 202001010000 "$W/hbdrive/heartbeat-daily.log"
sh -c "$HBLINE" >/dev/null 2>&1
ok "stale heartbeat (2020) => STALE alert line" "grep -q 'heartbeat STALE' '$RH/overnight-queue/logs/box_backup_alert.log'"
find "$RH/overnight-queue/logs" -type f -name box_backup_alert.log -delete; find "$W/hbdrive" -name heartbeat-daily.log -delete
sh -c "$HBLINE" >/dev/null 2>&1
ok "missing heartbeat (drive unmounted) => STALE alert line" "grep -q 'heartbeat STALE' '$RH/overnight-queue/logs/box_backup_alert.log'"
find "$RH/overnight-queue/logs" -type f -name box_backup_alert.log -delete; : > "$W/hbdrive/heartbeat-daily.log"; touch -t "$(date -v-25H +%Y%m%d%H%M 2>/dev/null || date -d '25 hours ago' +%Y%m%d%H%M)" "$W/hbdrive/heartbeat-daily.log"
sh -c "$HBLINE" >/dev/null 2>&1
ok "25h-old heartbeat is still fine (limit is 26h)" "[ ! -s '$RH/overnight-queue/logs/box_backup_alert.log' ]"
# the hourly line: fresh/stale/missing are judged on its own file, independent of the daily one
find "$RH/overnight-queue/logs" -type f -name box_backup_alert.log -delete; : > "$W/hbdrive/heartbeat-daily.log"; : > "$W/hbdrive/heartbeat-hourly.log"
sh -c "$HBHLINE" >/dev/null 2>&1
ok "fresh hourly heartbeat => no alert" "[ ! -s '$RH/overnight-queue/logs/box_backup_alert.log' ]"
touch -t "$(date -v-4H +%Y%m%d%H%M 2>/dev/null || date -d '4 hours ago' +%Y%m%d%H%M)" "$W/hbdrive/heartbeat-hourly.log"
sh -c "$HBLINE" >/dev/null 2>&1
ok "a fresh DAILY heartbeat does not mask a stale HOURLY one: the daily check stays silent" "[ ! -s '$RH/overnight-queue/logs/box_backup_alert.log' ]"
sh -c "$HBHLINE" >/dev/null 2>&1
ok "4h-old hourly heartbeat => HOURLY STALE alert" "grep -q 'HOURLY heartbeat STALE' '$RH/overnight-queue/logs/box_backup_alert.log'"
find "$RH/overnight-queue/logs" -type f -name box_backup_alert.log -delete; touch -t 202001010000 "$W/hbdrive/heartbeat-daily.log"; : > "$W/hbdrive/heartbeat-hourly.log"
sh -c "$HBLINE" >/dev/null 2>&1; sh -c "$HBHLINE" >/dev/null 2>&1
ok "stale DAILY with a fresh HOURLY heartbeat => DAILY STALE alert (a succeeding hourly cannot hide a dead daily)" "grep -q 'DAILY heartbeat STALE' '$RH/overnight-queue/logs/box_backup_alert.log' && ! grep -q 'HOURLY heartbeat STALE' '$RH/overnight-queue/logs/box_backup_alert.log'"
ok "cron.proposed.txt ships the same two lines ACTIVE (uncommented)" "grep -q '^53 6 \* \* \* .*heartbeat-daily.log.*-mmin -1560\\|^53 6 \* \* \* .*-mmin -1560.*heartbeat-daily.log' '$HERE/../../ops/cron.proposed.txt' && grep -q '^54 6 \* \* \* .*heartbeat-hourly.log' '$HERE/../../ops/cron.proposed.txt'"

echo "== ~/.ssh: a ~/.ssh created by an earlier run (known_hosts only) is still repaired on a re-run"
RH="$W/h12"; mkdir -p "$RH"; ssh-keygen -q -t ed25519 -N '' -f "$W/fake_key2" >/dev/null 2>&1
echo "github.com $(cut -d' ' -f1,2 "$W/fake_key2.pub")" > "$W/fake_hostline2"
FP2="$(ssh-keygen -lf "$W/fake_key2.pub" | awk '{print $2}')"; sed "s|^GH_FPR=.*|GH_FPR=\"$FP2\"|" "$REC" > "$W/rec_pinned2.sh"
RC_HOME="$RH" RC_BACKUPS="$W/emptydrive" RC_GITHUB_KEYFILE="$W/fake_hostline2" bash "$W/rec_pinned2.sh" --skip-queue --skip-godot --skip-aider --skip-repos --no-cron >"$W/o12a" 2>&1
ok "run 1 (no backup yet): says a new key is needed, and the host-key step created ~/.ssh with only known_hosts" "grep -q 'NEW key must be created' '$W/o12a' && [ -f '$RH/.ssh/known_hosts' ] && [ ! -e '$RH/.ssh/id_ed25519' ]"
echo "mine" > "$RH/.ssh/known_hosts.keep"; cp "$RH/.ssh/known_hosts" "$W/kh.before"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" RC_GITHUB_KEYFILE="$W/fake_hostline2" bash "$W/rec_pinned2.sh" --skip-queue --skip-godot --skip-aider --skip-repos --no-cron >"$W/o12b" 2>&1
ok "run 2 (snapshot now exists): the key is restored into the existing ~/.ssh, mode 600, dir 700" "[ \"\$(cat '$RH/.ssh/id_ed25519')\" = K ] && [ \"\$(stat -c %a '$RH/.ssh/id_ed25519' 2>/dev/null || stat -f %Lp '$RH/.ssh/id_ed25519')\" = 600 ] && [ \"\$(stat -c %a '$RH/.ssh' 2>/dev/null || stat -f %Lp '$RH/.ssh')\" = 700 ]"
ok "... existing files were NOT overwritten and the summary says what was restored" "cmp -s '$RH/.ssh/known_hosts' '$W/kh.before' && [ -f '$RH/.ssh/known_hosts.keep' ] && grep -q 'got the missing files' '$W/o12b'"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" RC_GITHUB_KEYFILE="$W/fake_hostline2" bash "$W/rec_pinned2.sh" --skip-queue --skip-godot --skip-aider --skip-repos --no-cron >"$W/o12c" 2>&1
ok "run 3: nothing left to restore, and it says so" "grep -q 'already holds every file' '$W/o12c'"
RH="$W/h13"; mkdir -p "$RH/.ssh"   # partially wiped home: an EMPTY ~/.ssh
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos --no-cron >/dev/null 2>&1
ok "an empty existing ~/.ssh is restored too" "[ \"\$(cat '$RH/.ssh/id_ed25519')\" = K ]"
RH="$W/h14"; mkdir -p "$RH"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" --dry-run --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos --no-cron >"$W/o14" 2>&1
ok "dry-run plans the .ssh restore and writes nothing" "grep -q 'DRY-RUN would: restore missing ~/.ssh files' '$W/o14' && [ -z \"\$(ls -A '$RH')\" ]"

echo "== a failed queue restore leaves NO half-restored ~/overnight-queue, and a re-run completes it"
PS="$W/psrc"; mkdir -p "$PS/overnight-queue/ops" "$PS/.ssh"; echo k > "$PS/.ssh/id_ed25519"
for n in a1 a2 a3; do echo "$n" > "$PS/overnight-queue/$n"; done; cp "$BAK" "$PS/overnight-queue/ops/box_home_backup.sh"; echo secret > "$PS/overnight-queue/locked.f"
PD="$W/pdrive/box-backups"; mkdir -p "$PD"; BB_HOME="$PS" BB_DEST="$PD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$BAK" daily >/dev/null 2>&1
# the snapshot is built by rsync as the same user, so make the SNAPSHOT copy unreadable instead
chmod 000 "$PD/daily/Mon/overnight-queue/locked.f" 2>/dev/null
if [ -r "$PD/daily/Mon/overnight-queue/locked.f" ]; then
  echo "  SKIP failed-restore cases: running as a user that ignores file permissions (root?)"
else
  RH="$W/h15"; mkdir -p "$RH"; : > "$W/crontab.state"
  RC_HOME="$RH" RC_BACKUPS="$PD" bash "$REC" --skip-godot --skip-aider --skip-repos --skip-hostkey >"$W/o15a" 2>&1; r15=$?
  ok "restore failure: exit 1 and FAILED: queue restore" "[ $r15 = 1 ] && grep -q 'FAILED: queue restore' '$W/o15a'"
  ok "~/overnight-queue was NOT created (no half-restored dir); the stage holds the partial copy and the message says how to continue" "[ ! -e '$RH/overnight-queue' ] && [ -f '$RH/.overnight-queue.restore/a1' ] && grep -q 'NOT created' '$W/o15a'"
  ok "no backup cron lines were installed pointing at the partial queue" "[ ! -s '$W/crontab.state' ] && grep -q 'does not exist' '$W/o15a'"
  chmod 644 "$PD/daily/Mon/overnight-queue/locked.f"
  RC_HOME="$RH" RC_BACKUPS="$PD" bash "$REC" --skip-godot --skip-aider --skip-repos --skip-hostkey >"$W/o15b" 2>&1; r15=$?
  ok "after fixing the cause the SAME command line succeeds (no REFUSING, exit 0)" "[ $r15 = 0 ] && ! grep -q REFUSING '$W/o15b'"
  ok "the full queue is in place, the stage is gone, and the cron lines were installed" "[ -f '$RH/overnight-queue/a3' ] && [ -f '$RH/overnight-queue/locked.f' ] && [ ! -e '$RH/.overnight-queue.restore' ] && [ \"\$(grep -c box_home_backup.sh '$W/crontab.state')\" = 2 ]"
  RC_HOME="$W/h16" ; mkdir -p "$RC_HOME/overnight-queue"
  RC_HOME="$W/h16" RC_BACKUPS="$PD" bash "$REC" --skip-godot --skip-aider --skip-repos --skip-hostkey --no-cron >/dev/null 2>&1; r16=$?
  ok "an EMPTY pre-existing ~/overnight-queue dir is replaced by the staged restore" "[ $r16 = 0 ] && [ -f '$W/h16/overnight-queue/a1' ]"
fi

echo "== an older v1 backup cron block is replaced by the v2 block (its shared heartbeat is no longer written)"
RH="$W/h17"; mkdir -p "$RH/overnight-queue/ops"; cp "$BAK" "$RH/overnight-queue/ops/box_home_backup.sh"
printf '%s\n' '0 1 * * * /usr/bin/precious-job' '# box_recover-backup-lines' '17 3 * * * old daily box_home_backup.sh' '41 * * * * old hourly box_home_backup.sh' '53 6 * * * old heartbeat.log -mmin -1560' '5 5 * * * after-job' > "$W/crontab.state"; cp "$W/crontab.state" "$W/cron.v1"
RC_HOME="$RH" RC_BACKUPS="$W/drive/box-backups" bash "$REC" --skip-queue --skip-godot --skip-aider --skip-hostkey --skip-repos >"$W/o17" 2>&1; r17=$?
SV17="$(ls -t "$W"/drive/box-backups/crontab.pre-recover.* 2>/dev/null | head -1)"
ok "v1 block gone, v2 block present once, other jobs preserved, exactly 2 backup lines" "[ $r17 = 0 ] && ! grep -q 'old daily' '$W/crontab.state' && ! grep -q 'old heartbeat' '$W/crontab.state' && grep -q precious-job '$W/crontab.state' && grep -q after-job '$W/crontab.state' && grep -qx '# box_recover-backup-lines v2' '$W/crontab.state' && [ \"\$(grep -c box_home_backup.sh '$W/crontab.state')\" = 2 ]"
ok "the ORIGINAL (v1) crontab is what was saved" "cmp -s '$SV17' '$W/cron.v1'"

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
