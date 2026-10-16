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
cleanup(){ case "$W" in /*/bbtest.??????) find "$W" -mindepth 1 -depth -delete 2>/dev/null; rmdir "$W" 2>/dev/null;; esac; }
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
ok "heartbeat line written" "grep -q 'daily OK Mon' '$D/heartbeat.log'"
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
