#!/usr/bin/env bash
# 2026-10-16 (box home wipe): hermetic test of ops/box_home_backup.sh. Fake HOME + fake secondary drive under a CHECKED mktemp dir; nothing real is touched.
# Proves: refuses same-filesystem / missing dest, correct content + excludes + >200MB skip, hard-link rotation, hourly prune to 48, failure => alert + nonzero + old snapshot kept,
# safe_rm_snap refuses everything outside DEST, and two MUTANTS (backup that deletes outside DEST; safe-path guard removed) are CAUGHT by the same checks.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../../ops/box_home_backup.sh"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }

# ---- checked scratch dir (explicit guards; this is the exact failure class of the 2026-10-16 wipe)
W="$(mktemp -d "${TMPDIR:-/tmp}/bbtest.XXXXXX")" || { echo "mktemp failed: abort" >&2; exit 2; }
case "$W" in /*/bbtest.??????) ;; *) echo "unsafe scratch dir '$W': abort" >&2; exit 2;; esac
[ -d "$W" ] && [ "$W" != "/" ] && [ "$W" != "${HOME:-/nonexistent}" ] || { echo "unsafe scratch dir: abort" >&2; exit 2; }
OTHERFS_CLEAN=""
cleanup(){
  [ -n "$OTHERFS_CLEAN" ] && eval "$OTHERFS_CLEAN" >/dev/null 2>&1
  case "$W" in /*/bbtest.??????) chmod -R u+rwX "$W" 2>/dev/null; find "$W" -mindepth 1 -depth -delete 2>/dev/null; rmdir "$W" 2>/dev/null;; esac
}
trap cleanup EXIT

mkhome(){   # mkhome <home>
  local h="$1"
  mkdir -p "$h/.ssh" "$h/overnight-queue/state" "$h/overnight-queue/repos/r1" "$h/overnight-queue/logs" "$h/overnight-queue/reports" \
           "$h/overnight-queue/.venv/lib" "$h/overnight-queue/scripts/__pycache__" "$h/overnight-queue/node_modules/x"
  echo key > "$h/.ssh/id_ed25519"; echo kh > "$h/.ssh/known_hosts"; echo "[user]" > "$h/.gitconfig"; echo b > "$h/.bashrc"; echo p > "$h/.profile"
  echo q > "$h/overnight-queue/queue.sh"; echo s1 > "$h/overnight-queue/state/a.json"; echo s2 > "$h/overnight-queue/state/b.json"
  echo big > "$h/overnight-queue/repos/r1/f"; echo l > "$h/overnight-queue/logs/x.log"; echo r > "$h/overnight-queue/reports/r.md"
  echo v > "$h/overnight-queue/.venv/lib/v"; echo c > "$h/overnight-queue/scripts/__pycache__/c.pyc"; echo n > "$h/overnight-queue/node_modules/x/n"
  : > "$h/overnight-queue/huge.bin"; truncate -s 201M "$h/overnight-queue/huge.bin" 2>/dev/null || dd if=/dev/null of="$h/overnight-queue/huge.bin" bs=1 seek=210000000 2>/dev/null
}
bb(){ BB_HOME="$H" BB_DEST="$D" BB_ALLOW_SAME_FS=1 bash "$SCRIPT" "$@"; }
inode(){ ls -i "$1" | awk '{print $1}'; }

H="$W/home"; D="$W/drive/box-backups"; mkhome "$H"; mkdir -p "$D"; echo canary > "$W/canary"

echo "== refusals"
ok "same-filesystem destination is refused (no BB_ALLOW_SAME_FS), nothing written" "! BB_HOME='$H' BB_DEST='$D' bash '$SCRIPT' daily && [ ! -d '$D/daily' ] && grep -q 'SAME filesystem' '$D/alerts.log'"
ok "missing destination is refused and NOT created" "! BB_HOME='$H' BB_DEST='$W/nodrive/box-backups' BB_ALLOW_SAME_FS=1 bash '$SCRIPT' daily && [ ! -e '$W/nodrive' ]"
ok "relative / dotdot / root destinations are refused" "! BB_HOME='$H' BB_DEST='rel/x' bash '$SCRIPT' daily && ! BB_HOME='$H' BB_DEST='$W/drive/../drive/box-backups' BB_ALLOW_SAME_FS=1 bash '$SCRIPT' daily && ! BB_HOME='$H' BB_DEST=/ BB_ALLOW_SAME_FS=1 bash '$SCRIPT' daily"
ok "destination equal to the home is refused" "! BB_HOME='$H' BB_DEST='$H' BB_ALLOW_SAME_FS=1 bash '$SCRIPT' daily"
rm_alert="$D/alerts.log"; : > "$rm_alert"

echo "== daily snapshot"
BB_DAY=Mon bb daily >"$W/out1" 2>&1; rc1=$?
ok "daily backup exits 0" "[ $rc1 = 0 ]"
M="$D/daily/Mon"
ok "ssh keys, dotfiles, queue code and state are in the snapshot" "[ -f '$M/.ssh/id_ed25519' ] && [ -f '$M/.ssh/known_hosts' ] && [ -f '$M/.gitconfig' ] && [ -f '$M/.bashrc' ] && [ -f '$M/.profile' ] && [ -f '$M/overnight-queue/queue.sh' ] && [ -f '$M/overnight-queue/state/a.json' ]"
ok "repos/ logs/ reports/ .venv __pycache__ node_modules are excluded" "[ ! -e '$M/overnight-queue/repos' ] && [ ! -e '$M/overnight-queue/logs' ] && [ ! -e '$M/overnight-queue/reports' ] && [ ! -e '$M/overnight-queue/.venv' ] && [ ! -e '$M/overnight-queue/scripts/__pycache__' ] && [ ! -e '$M/overnight-queue/node_modules' ]"
ok "a file over 200MB is skipped" "[ ! -e '$M/overnight-queue/huge.bin' ]"
ok "manifest has all sections" "grep -q 'aider version' '$M/manifest.txt' && grep -q 'pip freeze' '$M/manifest.txt' && grep -q '## godot' '$M/manifest.txt' && grep -q 'crontab -l' '$M/manifest.txt' && grep -q 'systemctl cat overnight-queue' '$M/manifest.txt' && grep -q 'docker ps' '$M/manifest.txt'"
ok "heartbeat line written to the DAILY heartbeat file only" "grep -q 'daily OK Mon' '$D/heartbeat-daily.log' && [ ! -e '$D/heartbeat.log' ] && [ ! -e '$D/heartbeat-hourly.log' ]"
ok "no .tmp dir left behind" "[ -z \"\$(ls -A '$D/daily' | grep '^\\.tmp')\" ]"

echo "== rotation (--link-dest)"
echo changed > "$H/overnight-queue/state/b.json"
BB_DAY=Tue bb daily >/dev/null 2>&1
T="$D/daily/Tue"
ok "unchanged file is a hard link to the previous day's copy" "[ \"\$(inode '$M/overnight-queue/queue.sh')\" = \"\$(inode '$T/overnight-queue/queue.sh')\" ]"
ok "changed file is a distinct copy; Monday still has the old content" "[ \"\$(cat '$T/overnight-queue/state/b.json')\" = changed ] && [ \"\$(cat '$M/overnight-queue/state/b.json')\" = s2 ]"
echo changed2 > "$H/overnight-queue/state/b.json"
BB_DAY=Mon bb daily >/dev/null 2>&1
ok "re-running the same weekday replaces that day only; Tuesday untouched" "[ \"\$(cat '$M/overnight-queue/state/b.json')\" = changed2 ] && [ \"\$(cat '$T/overnight-queue/state/b.json')\" = changed ]"
ok "outside canary survived" "[ -f '$W/canary' ]"

echo "== failure path"
mv "$H/.ssh" "$W/ssh.moved"
BB_DAY=Mon bb daily >/dev/null 2>&1; rcf=$?
ok "missing ~/.ssh => non-zero exit" "[ $rcf != 0 ]"
ok "failure appended an ALERT line" "grep -q 'ALERT' '$D/alerts.log'"
ok "the previous good Monday snapshot is still intact" "[ -f '$M/.ssh/id_ed25519' ] && [ \"\$(cat '$M/overnight-queue/state/b.json')\" = changed2 ]"
mv "$W/ssh.moved" "$H/.ssh"

echo "== hourly + prune to 48"
for i in $(seq 1 50); do mkdir -p "$D/hourly/$(printf '20260101%02d' $((i % 100)))x" 2>/dev/null; done   # junk-named dirs must never be pruned
i=0; while [ $i -lt 50 ]; do mkdir -p "$D/hourly/$(printf '20260%05d' $((10100 + i)))"; i=$((i+1)); done
BB_HOUR=2026101612 bb hourly >/dev/null 2>&1; rch=$?
n="$(ls -1 "$D/hourly" | grep -Ec '^[0-9]{10}$')"
ok "hourly exits 0 and stores state/" "[ $rch = 0 ] && [ -f '$D/hourly/2026101612/state/a.json' ]"
ok "exactly 48 hourly snapshots remain" "[ '$n' = 48 ]"
ok "the newest kept, the oldest pruned" "[ -d '$D/hourly/2026101612' ] && [ ! -d '$D/hourly/2026010100' ] && [ ! -d '$D/hourly/202610100' ]"
ok "odd-named dirs (not 10 digits) are never pruned" "[ -d '$D/hourly/2026010101x' ]"

echo "== safe_rm_snap boundaries"
mkdir -p "$W/victim/sub"; echo v > "$W/victim/sub/f"; mkdir -p "$D/daily/Sun"; ln -s "$W/victim" "$D/daily/linkd"
sr(){ BB_SOURCE_ONLY=1 BB_HOME="$H" BB_DEST="$D" bash -c ". '$1'; safe_rm_snap '$2'" >/dev/null 2>&1; }
ok "refuses a directory outside DEST" "! sr '$SCRIPT' '$W/victim' && [ -f '$W/victim/sub/f' ]"
ok "refuses dotdot escape" "! sr '$SCRIPT' '$D/daily/../../victim' && [ -f '$W/victim/sub/f' ]"
ok "refuses a symlink inside DEST/daily (and its target survives)" "! sr '$SCRIPT' '$D/daily/linkd' && [ -f '$W/victim/sub/f' ]"
ok "refuses a nested path and DEST itself" "! sr '$SCRIPT' '$D/daily/Mon/overnight-queue' && ! sr '$SCRIPT' '$D' && [ -f '$M/overnight-queue/queue.sh' ]"
ok "removes a legitimate snapshot dir" "sr '$SCRIPT' '$D/daily/Sun' && [ ! -e '$D/daily/Sun' ]"

echo "== BB_KEEP_HOURLY validation + the fresh snapshot is never pruned"
KD="$W/kdrive/box-backups"; mkdir -p "$KD/hourly/2026111500" "$KD/hourly/2026111501" "$KD/daily"
kb(){ BB_HOME="$H" BB_DEST="$KD" BB_ALLOW_SAME_FS=1 BB_HOUR="$1" BB_KEEP_HOURLY="$2" bash "$SCRIPT" hourly; }
for v in abc 0 -1 01 "1 2" "3;touch $W/pwned" 1.5; do
  kb 2026111502 "$v" >/dev/null 2>&1; r=$?
  ok "BB_KEEP_HOURLY='$v' is rejected (exit 64), nothing pruned, nothing created" "[ $r = 64 ] && [ -d '$KD/hourly/2026111500' ] && [ -d '$KD/hourly/2026111501' ] && [ ! -e '$KD/hourly/2026111502' ] && [ ! -e '$W/pwned' ]"
done
kb 2026010101 1 >/dev/null 2>&1; r=$?
ok "BB_KEEP_HOURLY=1 with an OLD fresh name: the fresh snapshot survives, all others pruned" "[ $r = 0 ] && [ -f '$KD/hourly/2026010101/state/a.json' ] && [ ! -e '$KD/hourly/2026111500' ] && [ ! -e '$KD/hourly/2026111501' ]"

echo "== symlinked daily / hourly / snapshot names are refused (real dirs on the same device required)"
mkdir -p "$W/victim3"; echo v > "$W/victim3/f"
SD="$W/sdrive/box-backups"; mkdir -p "$SD"; ln -s "$W/victim3" "$SD/daily"
BB_HOME="$H" BB_DEST="$SD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
ok "DEST/daily symlink: refused, target dir untouched (still only f)" "[ $r != 0 ] && [ \"\$(ls -A '$W/victim3')\" = f ] && grep -q 'symlink' '$SD/alerts.log'"
find "$SD/daily" -maxdepth 0 -type l -delete; mkdir -p "$SD/daily"; ln -s "$W/victim3" "$SD/hourly"
BB_HOME="$H" BB_DEST="$SD" BB_ALLOW_SAME_FS=1 BB_HOUR=2026101612 bash "$SCRIPT" hourly >/dev/null 2>&1; r=$?
ok "DEST/hourly symlink: refused, target dir untouched" "[ $r != 0 ] && [ \"\$(ls -A '$W/victim3')\" = f ]"
find "$SD/hourly" -maxdepth 0 -type l -delete; ln -s "$W/victim3" "$SD/daily/Mon"
BB_HOME="$H" BB_DEST="$SD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
ok "snapshot name is a symlink: refused, target dir untouched, link kept" "[ $r != 0 ] && [ \"\$(ls -A '$W/victim3')\" = f ] && [ -L '$SD/daily/Mon' ]"

echo "== sanity floor: a snapshot that shrank below 50% (files or bytes) does not replace the old one"
FD="$W/fdrive/box-backups"; mkdir -p "$FD"; FH="$W/fhome"; mkhome "$FH"
fb(){ BB_HOME="$FH" BB_DEST="$FD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon "$@" bash "$SCRIPT" daily; }
BB_HOME="$FH" BB_DEST="$FD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1
rm -f "$FH/.gitconfig" "$FH/.bashrc" "$FH/.profile" "$FH/.ssh/known_hosts" "$FH/overnight-queue/queue.sh" "$FH/overnight-queue/state/"*
BB_HOME="$FH" BB_DEST="$FD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
ok "file-count drop: exit non-zero, ALERT names the floor, old snapshot intact" "[ $r != 0 ] && grep -q 'REFUSING to replace daily/Mon' '$FD/alerts.log' && [ -f '$FD/daily/Mon/overnight-queue/queue.sh' ] && [ -f '$FD/daily/Mon/.ssh/known_hosts' ]"
ok "no .old- or half state left; the refused build is parked in .tmp-Mon" "[ ! -e '$FD/daily/.old-Mon' ] && [ -d '$FD/daily/.tmp-Mon' ]"
BB_HOME="$FH" BB_DEST="$FD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon BB_FORCE=1 bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
ok "BB_FORCE=1 replaces it" "[ $r = 0 ] && [ ! -e '$FD/daily/Mon/overnight-queue/queue.sh' ] && [ -f '$FD/daily/Mon/.ssh/id_ed25519' ] && [ ! -e '$FD/daily/.tmp-Mon' ] && [ ! -e '$FD/daily/.old-Mon' ]"
BD="$W/bdrive/box-backups"; mkdir -p "$BD"; BH="$W/bhome"; mkhome "$BH"; dd if=/dev/zero of="$BH/overnight-queue/blob" bs=1024 count=600 2>/dev/null
BB_HOME="$BH" BB_DEST="$BD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1
: > "$BH/overnight-queue/blob"
BB_HOME="$BH" BB_DEST="$BD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
ok "bytes drop with the SAME file count: refused, old 600KB blob kept" "[ $r != 0 ] && [ \"\$(wc -c < '$BD/daily/Mon/overnight-queue/blob' | tr -d ' ')\" = 614400 ]"
ok "a normal small change is accepted (floor does not block routine runs)" "echo changed > '$H/overnight-queue/state/a.json'; BB_DAY=Mon bb daily >/dev/null 2>&1"

echo "== floor: hourly (names unique per hour) must not rotate good snapshots out when state/ is wiped"
HD="$W/hwdrive/box-backups"; mkdir -p "$HD"; HW="$W/hwhome"; mkhome "$HW"; i=0; while [ $i -lt 18 ]; do echo "x$i" > "$HW/overnight-queue/state/f$i"; i=$((i+1)); done
hb(){ BB_HOME="$HW" BB_DEST="$HD" BB_ALLOW_SAME_FS=1 BB_KEEP_HOURLY=3 BB_HOUR="$1" bash "$SCRIPT" hourly; }
for hh in 2026101001 2026101002 2026101003 2026101004; do hb $hh >/dev/null 2>&1; done
ok "four good hourly snapshots exist (state has 20 files), pruned to 3 kept" "[ \"\$(count_state 2>/dev/null || find '$HD/hourly/2026101004/state' -type f | wc -l | tr -d ' ')\" = 20 ] && [ \"\$(ls -1 '$HD/hourly' | grep -Ec '^[0-9]{10}\$')\" = 3 ]"
rm -f "$HW/overnight-queue/state/"*
hrcs=""; for hh in 2026101005 2026101006 2026101007 2026101008 2026101009; do hb $hh >/dev/null 2>&1; hrcs="$hrcs $?"; done
ok "wiped state/: every hourly run is refused (non-zero) instead of 'OK'" "! printf '%s' '$hrcs' | grep -q '\b0\b'"
ok "the three newest GOOD hourly snapshots are all still there with 20 files, nothing new was published" "[ \"\$(find '$HD/hourly/2026101004/state' -type f | wc -l | tr -d ' ')\" = 20 ] && [ -d '$HD/hourly/2026101002' ] && [ ! -e '$HD/hourly/2026101009' ] && [ ! -e '$HD/hourly/2026101005' ]"
ok "the refusal is alerted and names the component" "grep -q 'REFUSING to add hourly/2026101009: component state' '$HD/alerts.log'"
ok "no hourly heartbeat line for the refused hours" "! grep -q '2026101005\\|2026101009' '$HD/heartbeat-hourly.log'"
BB_HOME="$HW" BB_DEST="$HD" BB_ALLOW_SAME_FS=1 BB_KEEP_HOURLY=3 BB_HOUR=2026101010 BB_FORCE=1 bash "$SCRIPT" hourly >/dev/null 2>&1
ok "BB_FORCE=1 publishes the empty state deliberately" "[ -d '$HD/hourly/2026101010/state' ]"

echo "== floor: daily compares with YESTERDAY (not only the same weekday) and per component"
DD2="$W/dddrive/box-backups"; mkdir -p "$DD2"; DH2="$W/ddhome"; mkhome "$DH2"; i=0; while [ $i -lt 8 ]; do echo "q$i" > "$DH2/overnight-queue/q$i.sh"; i=$((i+1)); done
bd(){ BB_HOME="$DH2" BB_DEST="$DD2" BB_ALLOW_SAME_FS=1 BB_DAY="$1" bash "$SCRIPT" daily; }
bd Mon >/dev/null 2>&1
rm -f "$DH2/overnight-queue/"*.sh "$DH2/overnight-queue/state/"*; rm -f "$DH2/.ssh/id_ed25519"
bd Tue >"$W/ddo" 2>&1; r=$?
ok "Tuesday with the queue emptied and the key gone: refused, no Tue snapshot, Mon intact" "[ $r != 0 ] && [ ! -e '$DD2/daily/Tue' ] && [ -f '$DD2/daily/Mon/.ssh/id_ed25519' ] && [ -f '$DD2/daily/Mon/overnight-queue/q3.sh' ]"
ok "the daily heartbeat was NOT refreshed by the refused run" "[ \"\$(grep -c 'daily OK' '$DD2/heartbeat-daily.log')\" = 1 ]"
echo key > "$DH2/.ssh/id_ed25519"; i=0; while [ $i -lt 8 ]; do echo "q$i" > "$DH2/overnight-queue/q$i.sh"; i=$((i+1)); done
echo s1 > "$DH2/overnight-queue/state/a.json"; echo s2 > "$DH2/overnight-queue/state/b.json"
rm -f "$DH2/.ssh/id_ed25519"
bd Mon >/dev/null 2>&1; r=$?
ok "same-day re-run after ONLY the private key vanished (file count drop is just 1 of 2 in .ssh): refused, the good Mon snapshot keeps the key" "[ $r != 0 ] && [ -f '$DD2/daily/Mon/.ssh/id_ed25519' ]"
echo key > "$DH2/.ssh/id_ed25519"; echo more > "$DH2/overnight-queue/new.sh"
bd Tue >/dev/null 2>&1; r=$?
ok "healthy source: Tuesday is accepted (routine runs are not blocked) and has the key" "[ $r = 0 ] && [ -f '$DD2/daily/Tue/.ssh/id_ed25519' ]"
ok "daily success never touches the hourly heartbeat" "[ ! -e '$DD2/heartbeat-hourly.log' ] && [ ! -e '$DD2/heartbeat.log' ]"

echo "== heartbeat: a failing daily is not masked by a succeeding hourly"
HB2="$W/hbdrive2/box-backups"; mkdir -p "$HB2"; HH2="$W/hbhome2"; mkhome "$HH2"
BB_HOME="$HH2" BB_DEST="$HB2" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1
find "$HB2/heartbeat-daily.log" -maxdepth 0 -type f -exec touch -t 202001010000 {} +
mv "$HH2/.ssh" "$W/hh2.ssh"
BB_HOME="$HH2" BB_DEST="$HB2" BB_ALLOW_SAME_FS=1 BB_DAY=Tue bash "$SCRIPT" daily >/dev/null 2>&1; rd=$?
BB_HOME="$HH2" BB_DEST="$HB2" BB_ALLOW_SAME_FS=1 BB_HOUR=2026101612 bash "$SCRIPT" hourly >/dev/null 2>&1; rh=$?
ok "daily fails (missing .ssh), hourly succeeds" "[ $rd != 0 ] && [ $rh = 0 ]"
ok "the daily heartbeat is still the OLD one (stale => the dead-man check fires), the hourly one is fresh" "[ -z \"\$(find '$HB2/heartbeat-daily.log' -mmin -1560)\" ] && [ -n \"\$(find '$HB2/heartbeat-hourly.log' -mmin -180)\" ]"
mv "$W/hh2.ssh" "$HH2/.ssh"

echo "== swap safety (rename-swap, nothing destroyed on failure)"
WD="$W/wdrive/box-backups"; mkdir -p "$WD"; WH="$W/whome"; mkhome "$WH"
wb(){ BB_HOME="$WH" BB_DEST="$WD" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$SCRIPT" daily; }
wb >/dev/null 2>&1; echo v2 > "$WH/overnight-queue/queue.sh"
mkdir -p "$W/mvbin"; REALMV="$(command -v mv)"
printf '#!/bin/sh\nfor a in "$@"; do case "$a" in *.tmp-*) exit 1;; esac; done\nexec %s "$@"\n' "$REALMV" > "$W/mvbin/mv"; chmod +x "$W/mvbin/mv"
PATH="$W/mvbin:$PATH" wb >/dev/null 2>&1; r=$?
ok "swap failure (mv tmp->name fails): non-zero, previous snapshot restored byte-for-byte" "[ $r != 0 ] && [ \"\$(cat '$WD/daily/Mon/overnight-queue/queue.sh')\" = q ] && [ ! -e '$WD/daily/.old-Mon' ]"
ok "the .tmp- build is KEPT after the failed swap, and an ALERT names it" "[ -f '$WD/daily/.tmp-Mon/overnight-queue/queue.sh' ] && grep -q 'swap failed' '$WD/alerts.log'"
wb >/dev/null 2>&1; r=$?
ok "next run (no failure) completes the swap and clears the .tmp-" "[ $r = 0 ] && [ \"\$(cat '$WD/daily/Mon/overnight-queue/queue.sh')\" = v2 ] && [ ! -e '$WD/daily/.tmp-Mon' ]"
# interrupted swap: Mon was renamed to .old-Mon and the process died
$REALMV "$WD/daily/Mon" "$WD/daily/.old-Mon"; mkdir -p "$WD/daily/.tmp-Mon/junk"
mv "$WH/.ssh" "$W/ssh.moved2"
wb >/dev/null 2>&1
mv "$W/ssh.moved2" "$WH/.ssh"
ok "interrupted swap (.old-Mon, no Mon) is repaired even when the run itself then fails" "[ \"\$(cat '$WD/daily/Mon/overnight-queue/queue.sh')\" = v2 ] && [ ! -e '$WD/daily/.old-Mon' ] && grep -q 'recovered daily/Mon' '$WD/alerts.log'"
# deletion failure of the old snapshot must not lose or hide the new one
mkdir -p "$WD/daily/Mon/overnight-queue/locked"; echo x > "$WD/daily/Mon/overnight-queue/locked/f"; chmod 555 "$WD/daily/Mon/overnight-queue/locked"
if touch "$WD/daily/Mon/overnight-queue/locked/probe" 2>/dev/null; then
  echo "  SKIP delete-failure case: running as a user that ignores directory permissions (root?)"
else
  echo v3 > "$WH/overnight-queue/queue.sh"
  wb >/dev/null 2>&1; r=$?
  ok "old snapshot undeletable: new snapshot IS in place and complete, run exits 0" "[ $r = 0 ] && [ \"\$(cat '$WD/daily/Mon/overnight-queue/queue.sh')\" = v3 ] && [ -f '$WD/daily/Mon/.ssh/id_ed25519' ]"
  ok "the old copy survives under a dot name (never half-deleted under a snapshot name) and an ALERT says so" "[ -d '$WD/daily/.old-Mon' ] && [ ! -e '$WD/daily/Mon/overnight-queue/locked' ] && grep -q 'could not delete old snapshot' '$WD/alerts.log'"
  chmod -R u+rwX "$WD/daily/.old-Mon"
  wb >/dev/null 2>&1
  ok "once deletable, the next run cleans the leftover" "[ ! -e '$WD/daily/.old-Mon' ]"
fi

echo "== a REAL different filesystem (Linux /dev/shm or a macOS disk image), no BB_ALLOW_SAME_FS"
OFS=""
if [ "$(uname -s)" = Linux ] && [ -d /dev/shm ] && [ -w /dev/shm ]; then
  OFS="$(mktemp -d /dev/shm/bbtest-ofs.XXXXXX 2>/dev/null)" && OTHERFS_CLEAN="find '$OFS' -mindepth 1 -depth -delete; rmdir '$OFS'" || OFS=""
elif [ "$(uname -s)" = Darwin ] && command -v hdiutil >/dev/null 2>&1; then
  mkdir -p "$W/ofs_mp"
  if hdiutil create -size 16m -fs HFS+ -volname bbtestofs -type SPARSE "$W/ofs" >/dev/null 2>&1 && hdiutil attach -nobrowse -mountpoint "$W/ofs_mp" "$W/ofs.sparseimage" >/dev/null 2>&1; then
    OFS="$W/ofs_mp"; OTHERFS_CLEAN="hdiutil detach -force '$W/ofs_mp'"
  fi
fi
devt(){ stat -L -c %d "$1" 2>/dev/null || stat -L -f %d "$1"; }
if [ -z "$OFS" ] || [ "$(devt "$OFS")" = "$(devt "$W")" ]; then
  echo "  SKIP real-different-filesystem cases: no second filesystem available here (the separate-fs refusal is still proven by the same-fs case above and its mutant below)"
else
  RD="$OFS/box-backups"; mkdir -p "$RD"
  BB_HOME="$H" BB_DEST="$RD" BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
  ok "different-device DEST works without BB_ALLOW_SAME_FS" "[ $r = 0 ] && [ -f '$RD/daily/Mon/.ssh/id_ed25519' ]"
  mkdir -p "$W/homefs_dest"; ln -s "$W/homefs_dest" "$OFS/linkdest"
  BB_HOME="$H" BB_DEST="$OFS/linkdest" BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
  ok "DEST that is a symlink (on the other fs) to a dir on the HOME fs is refused: the resolved target decides" "[ $r != 0 ] && [ -z \"\$(ls -A '$W/homefs_dest' | grep -v '^alerts.log\$')\" ] && [ ! -e '$W/homefs_dest/daily' ]"
  find "$RD/daily" -mindepth 1 -delete; rmdir "$RD/daily"; mkdir -p "$W/homefs_daily"; ln -s "$W/homefs_daily" "$RD/daily"
  BB_HOME="$H" BB_DEST="$RD" BB_DAY=Mon bash "$SCRIPT" daily >/dev/null 2>&1; r=$?
  ok "DEST on the other fs but DEST/daily a symlink to the home fs: refused, nothing written there" "[ $r != 0 ] && [ -z \"\$(ls -A '$W/homefs_daily')\" ]"
  find "$RD/daily" -maxdepth 0 -type l -delete
fi

echo "== MUTANTS of the new guards must be caught"
mfs(){ BB_HOME="$H" BB_DEST="$W/mfsdrive/box-backups" bash "$1" daily >/dev/null 2>&1; }   # no BB_ALLOW_SAME_FS: same-fs DEST must be refused
refuses_samefs(){ mkdir -p "$W/mfsdrive/box-backups"; find "$W/mfsdrive/box-backups" -mindepth 1 -delete 2>/dev/null; ! mfs "$1" && [ ! -d "$W/mfsdrive/box-backups/daily/$(date +%a)" ]; }
sed 's|^    \[ "\$dh" != "\$dd" \] \|\| die .*|    :|' "$SCRIPT" > "$W/mutFS.sh"
ok "mutant FS differs from the original and still parses" "! cmp -s '$SCRIPT' '$W/mutFS.sh' && bash -n '$W/mutFS.sh'"
ok "the real script refuses a same-filesystem DEST" "refuses_samefs '$SCRIPT'"
ok "MUTANT (separate-filesystem check removed) is CAUGHT: it accepts a same-fs DEST" "! refuses_samefs '$W/mutFS.sh'"
sed -e '/is a symlink: refusing (snapshots/d' -e '/is not a real directory: refusing/d' "$SCRIPT" > "$W/mutSL.sh"
refuses_symlink(){ local d="$W/msl/box-backups"; find "$W/msl" -mindepth 1 -delete 2>/dev/null; mkdir -p "$d" "$W/msl_v"; find "$W/msl_v" -mindepth 1 -delete; ln -s "$W/msl_v" "$d/daily"
  BB_HOME="$H" BB_DEST="$d" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$1" daily >/dev/null 2>&1; [ -z "$(ls -A "$W/msl_v")" ]; }
mkdir -p "$W/msl"
ok "mutant SL differs and parses" "! cmp -s '$SCRIPT' '$W/mutSL.sh' && bash -n '$W/mutSL.sh'"
ok "the real script never writes through a symlinked daily" "refuses_symlink '$SCRIPT'"
ok "MUTANT (real-dir/symlink check removed) is CAUGHT: it writes through the symlink" "! refuses_symlink '$W/mutSL.sh'"
sed '/BB_KEEP_HOURLY must be a positive integer/d' "$SCRIPT" > "$W/mutKP.sh"
keeps_dirs(){ local d="$W/mkp/box-backups"; find "$W/mkp" -mindepth 1 -delete 2>/dev/null; mkdir -p "$d/hourly/2026111500" "$d/hourly/2026111501" "$d/daily"
  BB_HOME="$H" BB_DEST="$d" BB_ALLOW_SAME_FS=1 BB_HOUR=2026111502 BB_KEEP_HOURLY=abc bash "$1" hourly >/dev/null 2>&1; [ -d "$d/hourly/2026111500" ] && [ -d "$d/hourly/2026111501" ]; }
mkdir -p "$W/mkp"
ok "mutant KP differs and parses" "! cmp -s '$SCRIPT' '$W/mutKP.sh' && bash -n '$W/mutKP.sh'"
ok "the real script keeps every hourly dir when BB_KEEP_HOURLY=abc" "keeps_dirs '$SCRIPT'"
ok "MUTANT (keep validation removed) is CAUGHT: non-numeric keep prunes the history" "! keeps_dirs '$W/mutKP.sh'"

echo "== MUTANTS must be caught by the same checks"
# check_script <script>: 0 only when the script behaves safely (outside canary and outside victim both survive a backup run and a bad safe_rm_snap call)
check_script(){
  local s="$1" h="$W/mh" d="$W/md/box-backups"
  find "${W:?}/mh" "${W:?}/md" -mindepth 1 -depth -delete 2>/dev/null; mkdir -p "$W/md/box-backups"
  mkhome "$h"; echo canary > "$W/canary"; mkdir -p "$W/victim2"; echo v > "$W/victim2/f"
  BB_HOME="$h" BB_DEST="$d" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$s" daily >/dev/null 2>&1
  BB_HOME="$h" BB_DEST="$d" BB_ALLOW_SAME_FS=1 BB_DAY=Mon bash "$s" daily >/dev/null 2>&1
  BB_SOURCE_ONLY=1 BB_HOME="$h" BB_DEST="$d" bash -c ". '$s'; safe_rm_snap '$W/victim2'" >/dev/null 2>&1
  [ -f "$W/canary" ] && [ -f "$W/victim2/f" ]
}
mkdir -p "$W/mh" "$W/md"
ok "the real script passes the safety check" "check_script '$SCRIPT'"
# mutant A: a backup that also deletes a file outside its destination
sed 's|^build_snapshot(){|build_snapshot(){ rm -f "$BB_HOME/../canary";|' "$SCRIPT" > "$W/mutA.sh"
# mutant B: the fixed-prefix / name guard removed from safe_rm_snap
sed -e 's|\*) echo "safe_rm_snap: REFUSED (outside DEST/daily\|hourly): $d" >&2; return 2;;|*) :;;|' -e 's|if ! printf .%s. "$rel" . grep -Eq .*; then|if false; then|' "$SCRIPT" > "$W/mutB.sh"
ok "mutant A differs from the original (sed applied)" "! cmp -s '$SCRIPT' '$W/mutA.sh'"
ok "mutant B differs from the original (sed applied)" "! cmp -s '$SCRIPT' '$W/mutB.sh'"
ok "MUTANT A (deletes outside DEST) FAILS the safety check" "! check_script '$W/mutA.sh'"
ok "MUTANT B (guard removed) FAILS the safety check" "! check_script '$W/mutB.sh'"

echo; echo "box_home_backup: pass=$P fail=$F"
[ "$F" = 0 ]
