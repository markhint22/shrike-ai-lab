#!/usr/bin/env bash
# test_box_bootstrap.sh - package L1: the REBUILD DRILL. A disposable fake HOME is rebuilt end to end with stubbed network:
#   ops/box_recover.sh (queue restore from a backup snapshot, 8 repo clones from bundles, godot, aider, backup cron)  ->  ops/box_bootstrap.sh (venvs incl. xdist/dev reqs, pinned android sdk with
#   SHA256 check, QA tools, crontab blocks + main snapshot, state dirs, human checklist)  ->  ops/box_verify.py as the acceptance test.
# The drill must end with ONLY human-provided items outstanding (exit 10); after those are provided the same acceptance run is clean (exit 0). Mutants of the scripts must each break a check.
# Also covers: provision_test_envs.sh OVN_PROVISION_EXTRA (default off = unchanged), dry-run changes nothing, SHA256 mismatch installs nothing, licenses are a human flag, main crontab gates.
# Nothing real is touched; no network (curl/ssh/npm/pip/python3.12 are PATH stubs). Linux: the same file runs in the box sandbox (bwrap) - see docs/BOX_RECOVERY.md.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OVN_REAL="$(cd "$HERE/../.." && pwd)"
. "$HERE/lib_safe_tmp.sh" || exit 1
REALPY="$(command -v python3)"; [ -n "$REALPY" ] || { echo "  SKIP: no python3"; exit 0; }
for t in git rsync unzip; do command -v "$t" >/dev/null 2>&1 || { echo "  SKIP: $t not installed on this host (the drill needs it)"; exit 0; }; done
W="$(safe_mktemp_dir bsdrill)" || exit 1
trap '[ "${BSD_KEEP:-0}" = 1 ] && echo "kept: $W" >&2 || safe_rm_rf "$W"' EXIT
fails=0; n=0
ok(){ n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk(){ local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
sha256(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
sha512(){ if command -v sha512sum >/dev/null 2>&1; then sha512sum "$1" | awk '{print $1}'; else shasum -a 512 "$1" | awk '{print $1}'; fi; }
mkzip(){ ( cd "$1" && "$REALPY" -m zipfile -c "$2" $(ls) ); }
safe_set_sandbox_home "$W" || exit 1
H="$HOME"; BIN="$W/bin"; mkdir -p "$BIN" "$W/tmp"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# ------------------------------------------------------------------ PATH stubs (no network, no real package manager)
cat > "$W/pipstub.sh" <<'EOF'
#!/bin/sh
# fake pip: `install` records every call and writes a dist-info per package (and per '-r file' entry); `show NAME` prints its Version
here="$(cd "$(dirname "$0")" && pwd)"; site="$(ls -d "$here"/../lib/python*/site-packages | head -1)"
echo "pip $*" >> "${STUB_PIP_LOG:?}"
mk(){ spec="$1"; name="$(printf %s "$spec" | sed -E 's/[][<>=!~; ].*$//')"; ver="$(printf %s "$spec" | sed -nE 's/^[^=]*==([0-9][0-9.]*).*$/\1/p')"; [ -n "$ver" ] || ver=1.0
  n="$(printf %s "$name" | tr 'A-Z-' 'a-z_')"; mkdir -p "$site/$n-$ver.dist-info"; printf 'Metadata-Version: 2.1\nName: %s\nVersion: %s\n' "$name" "$ver" > "$site/$n-$ver.dist-info/METADATA"; }
feed(){ f="$1"; d="$(dirname "$f")"; [ -f "$f" ] || return 0
  while IFS= read -r l; do l="$(printf %s "$l" | sed -E 's/[[:space:]]+#.*$//; s/^[[:space:]]+//; s/[[:space:]]+$//')"; [ -z "$l" ] && continue
    case "$l" in "#"*) ;; "-r "*) feed "$d/${l#-r }";; -*) ;; *) mk "$l";; esac; done < "$f"; }
case "$1" in
  install) shift; while [ $# -gt 0 ]; do case "$1" in -r) feed "$2"; shift;; -*) ;; *) mk "$1";; esac; shift; done;;
  show) n="$(printf %s "$2" | tr 'A-Z-' 'a-z_')"; d="$(ls -d "$site"/$n-*.dist-info 2>/dev/null | head -1)"; [ -n "$d" ] || exit 1
        echo "Name: $2"; echo "Version: $(basename "$d" .dist-info | sed "s/^$n-//")";;
esac
exit 0
EOF
cat > "$BIN/python3.12" <<'EOF'
#!/bin/sh
# fake python3.12: only `-m venv DIR` (a venv whose python is a shim over the real python3 with a private site dir, and a fake pip)
if [ "$1" = "-m" ] && [ "$2" = "venv" ]; then d="$3"; mkdir -p "$d/bin" "$d/lib/python3.12/site-packages"
  cp "${STUB_PIP:?}" "$d/bin/pip"; chmod 755 "$d/bin/pip"
  printf '#!/bin/sh\nPYTHONPATH="%s" exec "%s" -B "$@"\n' "$(cd "$d/lib/python3.12/site-packages" && pwd)" "${STUB_REALPY:?}" > "$d/bin/python"; chmod 755 "$d/bin/python"; exit 0; fi
echo "fake python3.12: unsupported: $*" >&2; exit 2
EOF
printf '#!/bin/sh\nexit 0\n' > "$BIN/npm"; printf '#!/bin/sh\nexit 255\n' > "$BIN/ssh"
printf '#!/bin/sh\necho "curl stub: network is not available in this test: $*" >&2; exit 7\n' > "$BIN/curl"
printf '%s\n' '#!/bin/sh' "F=\"$W/crontab.stub\"" 'case "$1" in -l) [ -f "$F" ] || { echo "no crontab for u" >&2; exit 1; }; cat "$F";; *) cp "$1" "$F";; esac' > "$BIN/crontab"
printf '%s\n' '#!/bin/sh' 'echo "shrike-llama-dflash-35b	Up 20 hours (healthy)"' 'echo "shrike-litellm	Up 8 days"' > "$BIN/docker"
printf '%s\n' '#!/bin/sh' '[ "$1" = "is-active" ] || exit 2' 'echo active' > "$BIN/systemctl"
chmod 755 "$BIN"/*
export STUB_PIP="$W/pipstub.sh" STUB_REALPY="$REALPY" STUB_PIP_LOG="$W/pip.log"; : > "$W/pip.log"
export PATH="$BIN:$PATH"

# ------------------------------------------------------------------ fixtures: backup snapshot, bundles, godot zip, android zip, qa-tools fixtures
DRIVE="$W/drive/box-backups"; SNAP="$DRIVE/daily/20261018"; mkdir -p "$SNAP/overnight-queue" "$DRIVE/hourly"
rsync -a "$OVN_REAL/" "$SNAP/overnight-queue/" --exclude state --exclude logs --exclude repos --exclude __pycache__
mkdir -p "$SNAP/overnight-queue/state"
"$REALPY" - "$SNAP/overnight-queue/state/qwen_explore.jsonl" <<'PYEOF'
import json, sys, time
open(sys.argv[1], "w").write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "repo": "xlite", "result": "empty"}) + "\n")
PYEOF
: > "$DRIVE/heartbeat-daily.log"; : > "$DRIVE/heartbeat-hourly.log"; echo "/dev/x $W/drive ext4 rw 0 0" > "$W/mounts"
BUN="$W/bundles"; mkdir -p "$BUN"
mkrepo(){ # name subdir
  local r="$1" s="${2:-}" d="$W/mk/$1"; mkdir -p "$d/${s:-.}"; ( cd "$d" && git init -q -b main
    if [ -n "$s" ]; then printf 'fastapi\nuvicorn[standard]>=0.1\n' > "$s/requirements.txt"
      case "$r" in billwatch|gitlark|iptv_apps) printf -- '-r requirements.txt\npytest>=7.0\npytest-mock>=3.12\n' > "$s/requirements-dev.txt";; esac
    else echo x > README; fi
    git add -A && git commit -q -m init && git bundle create "$BUN/$r.bundle" --all >/dev/null 2>&1 ); }
mkrepo billwatch billwatch-backend; mkrepo gitlark backend; mkrepo iptv_apps iptv-backend; mkrepo test-automation-agent backend; mkrepo shrike-monitor backend; mkrepo shrike-notify backend; mkrepo xlite; mkrepo shrike-labs-website
mkdir -p "$W/gz"; printf '#!/bin/sh\necho 4.3.stable.official.drill\n' > "$W/gz/Godot_v4.3-stable_linux.x86_64"; chmod 755 "$W/gz/Godot_v4.3-stable_linux.x86_64"; mkzip "$W/gz" "$W/godot.zip"
GODOT_SHA="$(sha512 "$W/godot.zip")"
mkdir -p "$W/az/cmdline-tools/bin"
cat > "$W/az/cmdline-tools/bin/sdkmanager" <<'EOF'
#!/bin/sh
# fake sdkmanager: --licenses writes the license file; package args create the pinned directories
root=""; lic=0; pk=""
for a in "$@"; do case "$a" in --sdk_root=*) root="${a#--sdk_root=}";; --licenses) lic=1;; -*) ;; *) pk="$pk $a";; esac; done
[ -n "$root" ] || exit 2
echo "sdkmanager $*" >> "${STUB_SDK_LOG:?}"
if [ "$lic" = 1 ]; then head -c 64 >/dev/null; mkdir -p "$root/licenses"; echo 24333f8a63b6825ea9c5514f83c2829b004d1fee > "$root/licenses/android-sdk-license"; exit 0; fi
[ -s "$root/licenses/android-sdk-license" ] || { echo "licenses not accepted" >&2; exit 1; }
for p in $pk; do case "$p" in
  platforms\;*) d="$root/platforms/${p#platforms;}"; mkdir -p "$d"; : > "$d/android.jar";;
  build-tools\;*) d="$root/build-tools/${p#build-tools;}"; mkdir -p "$d"; echo "Pkg.Revision=${p#build-tools;}" > "$d/source.properties";;
  platform-tools) mkdir -p "$root/platform-tools"; printf '#!/bin/sh\nexit 0\n' > "$root/platform-tools/adb"; chmod 755 "$root/platform-tools/adb";;
esac; done
exit 0
EOF
chmod 755 "$W/az/cmdline-tools/bin/sdkmanager"; printf 'Pkg.Revision=22.0\nPkg.Path=cmdline-tools;22.0\n' > "$W/az/cmdline-tools/source.properties"; mkzip "$W/az" "$W/android.zip"
ANDROID_SHA="$(sha256 "$W/android.zip")"; export STUB_SDK_LOG="$W/sdk.log"; : > "$W/sdk.log"
# the QA tools installer's own test hooks (same fixture shapes its own test uses)
cat > "$W/qa_pipstub.sh" <<'EOF'
#!/bin/sh
bin="$1"; shift
for spec in "$@"; do name="${spec%%==*}"; ver="${spec#*==}"
  case "$name" in semgrep) printf '#!/bin/sh\necho "%s"\n' "$ver" > "$bin/$name";;
    mutmut) printf '#!/bin/sh\n[ "$1" = --version ] && { echo "Error: no source paths" >&2; exit 1; }\necho "mutmut help"\n' > "$bin/$name";;
    *) printf '#!/bin/sh\necho "%s %s"\n' "$name" "$ver" > "$bin/$name";; esac
  chmod 755 "$bin/$name"
  if [ "$name" = mutmut ]; then for sp in "$bin"/../lib/python*/site-packages; do [ -d "$sp" ] && { mkdir -p "$sp/mutmut" "$sp/libcst"; : > "$sp/mutmut/__init__.py"; : > "$sp/libcst/__init__.py"; }; done; fi
  for sp in "$bin"/../lib/python*/site-packages; do [ -d "$sp" ] && { nn="$(printf %s "$name" | tr - _)"; mkdir -p "$sp/$nn-$ver.dist-info"; printf 'Metadata-Version: 2.1\nName: %s\nVersion: %s\n' "$name" "$ver" > "$sp/$nn-$ver.dist-info/METADATA"; }; done
done
EOF
chmod 755 "$W/qa_pipstub.sh"
case "$(uname -s)-$(uname -m)" in Linux-x86_64) GA=linux_x64;; Linux-aarch64|Linux-arm64) GA=linux_arm64;; Darwin-arm64) GA=darwin_arm64;; Darwin-x86_64) GA=darwin_x64;; *) GA=none;; esac
mkdir -p "$W/gl" "$W/glw"; printf '#!/bin/sh\necho 8.18.4 drill\n' > "$W/glw/gitleaks"; chmod 755 "$W/glw/gitleaks"; tar -czf "$W/gl/gitleaks_8.18.4_${GA}.tar.gz" -C "$W/glw" gitleaks
GLSHA="$(sha256 "$W/gl/gitleaks_8.18.4_${GA}.tar.gz")"; printf '%s  gitleaks_8.18.4_%s.tar.gz\n' "$GLSHA" "$GA" > "$W/gl/gitleaks_8.18.4_checksums.txt"
export QA_TOOLS_TEST_HOOKS=1 QA_TOOLS_PIP_STUB="$W/qa_pipstub.sh" QA_TOOLS_GITLEAKS_DIR="$W/gl" QA_TOOLS_GITLEAKS_SHA256="$GLSHA" QA_TOOLS_PYTHON="$REALPY"
# box_verify's environment-provided facts (the drill's "box")
export BV_BACKUPS="$DRIVE" BV_PROC_MOUNTS="$W/mounts" BV_TMP="$W/tmp" BV_DISK_MAX_PCT=101 BV_INODE_MAX_PCT=101
export BS_TEST_HOOKS=1 BS_ANDROID_ZIP="$W/android.zip" BS_ANDROID_SHA256="$ANDROID_SHA" BS_GH_CHECK=ok

OPS="$H/overnight-queue/ops"
tree_hash(){ ( cd "$1" && find . -path ./overnight-queue/repos -prune -o -type f -exec cksum {} + 2>/dev/null | LC_ALL=C sort | cksum ); }

echo "== phase 1: box_recover.sh rebuilds the home from the backup snapshot (stubbed network)"
RC_HOME="$H" RC_BACKUPS="$DRIVE" RC_GODOT_ZIP="$W/godot.zip" RC_GODOT_SHA512_OVERRIDE="$GODOT_SHA" RC_PYTHON=python3.12 \
  bash "$OVN_REAL/ops/box_recover.sh" --skip-hostkey --bundles "$BUN" > "$W/recover.out" 2>&1; rrc=$?
chk "box_recover rebuilds: exit 0, queue restored from the snapshot" bash -c "[ $rrc = 0 ] && [ -f '$OPS/box_verify.py' ] && [ -f '$H/overnight-queue/state/qwen_explore.jsonl' ]"
chk "  all 8 repo clones present (default RC_REPOS now = the box's 8 incl. shrike-monitor + shrike-notify)" bash -c "for r in iptv_apps xlite billwatch gitlark test-automation-agent shrike-labs-website shrike-monitor shrike-notify; do [ -d '$H/overnight-queue/repos/'\$r/.git ] || exit 1; done"
chk "  godot installed with BOTH ~/godot/godot4 (what run_overnight.sh runs) and ~/godot/godot" bash -c "[ -x '$H/godot/godot4' ] && [ -x '$H/godot/godot' ] && '$H/godot/godot4' --version | grep -q '^4.3'"
chk "  aider-chat installed at the PIN from ops/box_pins.env (a fresh rebuild does not drift to latest)" bash -c "grep -q 'aider-chat==0.86.2' '$W/pip.log' && [ -d '$H/aider-venv/lib/python3.12/site-packages/aider_chat-0.86.2.dist-info' ]"
chk "  before bootstrap the drill box is NOT healthy (box_verify sees the missing venvs, sdk, tools: the thing it exists for)" bash -c "BV_HOME='$H' BV_OVN='$H/overnight-queue' python3 -B '$OPS/box_verify.py' --no-record --strict >/dev/null; [ \$? = 1 ]"

echo "== phase 2: dry-run changes nothing"
b1="$(tree_hash "$H")"; cs1="$(cksum < "$W/crontab.stub")"
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --dry-run --install-main-crontab > "$W/dry.out" 2>&1; drc=$?
chk "dry-run exits 0, prints the plan for every step, and the human checklist" bash -c "[ $drc = 0 ] && grep -q 'DRY-RUN would: OVN_PROVISION_EXTRA=on' '$W/dry.out' && grep -q 'DRY-RUN would: download' '$W/dry.out' && grep -q 'DRY-RUN would: HOME=' '$W/dry.out' && grep -q 'HUMAN CHECKLIST' '$W/dry.out' && grep -q 'DRY-RUN would: python3 ops/box_verify.py' '$W/dry.out'"
ok "  crontab untouched by the dry-run" "$([ "$(cksum < "$W/crontab.stub")" = "$cs1" ] && echo 0 || echo 1)"
b2="$(tree_hash "$H")"; ok "  home tree hash identical before/after dry-run" "$([ "$b1" = "$b2" ] && echo 0 || echo 1)"
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --only nonsense >/dev/null 2>&1; chk "an unknown step name is refused (exit 3)" test $? -eq 3

echo "== phase 3: guards before the real run"
BS_HOME="$H" BS_ANDROID_SHA256="0000000000000000000000000000000000000000000000000000000000000000" bash "$OPS/box_bootstrap.sh" --only android > "$W/shabad.out" 2>&1; shrc=$?
chk "android zip with the WRONG sha256 is NOT unzipped (exit 1, nothing under ~/android-sdk)" bash -c "[ $shrc = 1 ] && grep -q 'SHA256 MISMATCH' '$W/shabad.out' && [ ! -e '$H/android-sdk/cmdline-tools/latest' ]"
BS_HOME="$H" BS_TEST_HOOKS=0 bash "$OPS/box_bootstrap.sh" --only android > "$W/nohook.out" 2>&1
chk "test hooks are ignored without BS_TEST_HOOKS=1 (warning, and the real download path is taken: the curl stub fails)" bash -c "grep -q 'ignoring BS_ANDROID_ZIP' '$W/nohook.out' && grep -q 'download of' '$W/nohook.out' && [ ! -e '$H/android-sdk/cmdline-tools/latest' ]"
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --only android > "$W/nolic.out" 2>&1; nlrc=$?
chk "without --accept-android-licenses: cmdline-tools installed but packages PENDING with the exact command (a licence is a human decision)" bash -c "[ -x '$H/android-sdk/cmdline-tools/latest/bin/sdkmanager' ] && grep -q 'PENDING: android: licenses are not accepted' '$W/nolic.out' && [ ! -d '$H/android-sdk/platforms/android-34' ] && grep -q 'sdkmanager --sdk_root=' '$W/nolic.out'"
chk "  the pinned cmdline-tools zip passed the SHA256 check before unzip" grep -q 'SHA256 verified before unzip' "$W/nolic.out"
mv "$H/android-sdk" "$W/android-sdk.aside"
BS_HOME="$H" BS_GH_CHECK=fail bash "$OPS/box_bootstrap.sh" --only cron --install-main-crontab > "$W/cronnogh.out" 2>&1
chk "main crontab is NOT installed when GitHub ssh does not authenticate (PENDING; those lines push)" bash -c "grep -q 'GitHub ssh does not authenticate' '$W/cronnogh.out' && ! crontab -l | grep -q 'branch_hygiene.sh'"
chk "  but the managed blocks, backup lines and the box_verify line did go in" bash -c "crontab -l | grep -q 'SUPPLY-LINES BEGIN' && crontab -l | grep -q 'QA-GATES BEGIN' && crontab -l | grep -q 'ops/box_verify.sh' && crontab -l | grep -q 'box_home_backup.sh daily'"
mv "$W/android-sdk.aside" "$H/android-sdk"

echo "== L1 repair round: venvs refuse on a live queue (3b), PAUSED is created before the main crontab (3c), android mv failure rolls back (3d)"
mutf(){ "$REALPY" - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
s = open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4]
assert s.count(old) == 1, "anchor %r found %d" % (old, s.count(old))
open(sys.argv[2], "w").write(s.replace(old, new))
PYEOF
}
# 3b: the box now has the managed cron blocks (phase 3) and is not paused -> the venv step must refuse and touch nothing
: > "$W/pip.log"
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --only venvs > "$W/venvlive.out" 2>&1; vlrc=$?
chk "venvs step on a box whose crontab runs queue jobs and is NOT paused: REFUSED (exit 1), pip never ran" bash -c "[ $vlrc = 1 ] && grep -q 'venvs: REFUSED, the queue is live' '$W/venvlive.out' && [ ! -s '$W/pip.log' ]"
chk "  the refusal names the exact commands (queue.sh pause / resume, then the same bootstrap command)" bash -c "grep -q 'queue.sh pause' '$W/venvlive.out' && grep -q -- '--only venvs' '$W/venvlive.out'"
mkdir -p "$H/overnight-queue/state"; : > "$H/overnight-queue/state/PAUSED"
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --only venvs --no-verify > "$W/venvpaused.out" 2>&1; vprc=$?
chk "  with state/PAUSED present the same step runs (exit 0, pip reached)" bash -c "[ $vprc = 0 ] && [ -s '$W/pip.log' ]"
rm -f "$H/overnight-queue/state/PAUSED"
# the queue is paused for the rest of the drill, like a human rebuilding a box would (queue.sh pause semantics)
mkdir -p "$H/overnight-queue/state"; : > "$H/overnight-queue/state/PAUSED"

# 3c: state/PAUSED is created BEFORE the main crontab is installed, with queue.sh pause semantics; refused when it cannot be created
H2="$W/h2"; mkdir -p "$H2/overnight-queue"
rsync -a "$OVN_REAL/" "$H2/overnight-queue/" --exclude state --exclude logs --exclude repos --exclude __pycache__ --exclude .git
mkdir -p "$H2/overnight-queue/state" "$H2/overnight-queue/logs" "$H2/overnight-queue/repos"
cp "$W/crontab.stub" "$W/crontab.drill"
REALCRON="$W/bin/crontab"; cp "$REALCRON" "$W/crontab.realstub"
printf '%s\n' '#!/bin/sh' "F=\"$W/crontab.stub\"" 'case "$1" in -l) [ -f "$F" ] || { echo "no crontab for u" >&2; exit 1; }; cat "$F";;' "  *) if [ -e \"$H2/overnight-queue/state/PAUSED\" ]; then echo yes >> \"$W/paused_at_install\"; else echo no >> \"$W/paused_at_install\"; fi; cp \"\$1\" \"\$F\";; esac" > "$W/bin/crontab"; chmod 755 "$W/bin/crontab"
: > "$W/paused_at_install"; : > "$W/crontab.stub"
mkdir -p "$H2/overnight-queue/ops"
BS_HOME="$H2" bash "$H2/overnight-queue/ops/box_bootstrap.sh" --only cron --install-main-crontab > "$W/pause1.out" 2>&1; p1rc=$?
chk "fresh box, GitHub ok, no state/PAUSED: main crontab installed (hygiene line present)" bash -c "crontab -l | grep -q 'branch_hygiene.sh'"
chk "  state/PAUSED EXISTS afterwards, empty, and queue.sh-style pause_log line 'pause by=box_bootstrap' was written" bash -c "[ -f '$H2/overnight-queue/state/PAUSED' ] && [ ! -s '$H2/overnight-queue/state/PAUSED' ] && grep -q ' pause by=box_bootstrap' '$H2/overnight-queue/state/pause_log'"
chk "  and it already existed at the moment crontab was INSTALLED (created BEFORE the pushing lines go live)" bash -c "grep -q '^yes' '$W/paused_at_install' && ! grep -q '^no' '$W/paused_at_install'"
chk "  the success message says the queue is PAUSED and how it resumes" bash -c "grep -q 'queue is PAUSED' '$W/pause1.out' && grep -q 'queue.sh resume' '$W/pause1.out'"
# an existing flag keeps its age (queue.sh pause is idempotent)
touch -t 202001010000 "$H2/overnight-queue/state/PAUSED"; : > "$W/crontab.stub"
BS_HOME="$H2" bash "$H2/overnight-queue/ops/box_bootstrap.sh" --only cron --install-main-crontab > "$W/pause2.out" 2>&1
chk "an existing state/PAUSED is left alone (mtime kept: pause_guard ages it)" bash -c "[ \"\$(stat -c %Y '$H2/overnight-queue/state/PAUSED' 2>/dev/null || stat -f %m '$H2/overnight-queue/state/PAUSED')\" -lt 1600000000 ]"
# cannot create the flag -> the main crontab is NOT installed
if [ "$(id -u)" != 0 ]; then
  rm -f "$H2/overnight-queue/state/PAUSED"; : > "$W/crontab.stub"; chmod 555 "$H2/overnight-queue/state"
  BS_HOME="$H2" bash "$H2/overnight-queue/ops/box_bootstrap.sh" --only cron --install-main-crontab > "$W/pause3.out" 2>&1; p3rc=$?
  chmod 755 "$H2/overnight-queue/state"
  chk "state/PAUSED cannot be created: main crontab NOT installed, exit 1, message says why" bash -c "[ $p3rc = 1 ] && ! crontab -l | grep -q 'branch_hygiene.sh' && grep -q 'could not create' '$W/pause3.out'"
else echo "  skip (running as root: cannot make state/ unwritable)"; fi
# MUTANT: the ensure_paused gate removed -> nothing creates PAUSED
mutf "$OVN_REAL/ops/box_bootstrap.sh" "$H2/overnight-queue/ops/box_bootstrap.m.sh" '    elif ! ensure_paused; then fail' '    elif false; then fail' || ok "mutant PAUSED anchor" 1
rm -f "$H2/overnight-queue/state/PAUSED" "$H2/overnight-queue/state/pause_log"; : > "$W/crontab.stub"
BS_HOME="$H2" bash "$H2/overnight-queue/ops/box_bootstrap.m.sh" --only cron --install-main-crontab > "$W/pause4.out" 2>&1
chk "MUTANT without ensure_paused is caught (crontab installed but no state/PAUSED: the incident)" bash -c "crontab -l | grep -q 'branch_hygiene.sh' && [ ! -e '$H2/overnight-queue/state/PAUSED' ]"
cp "$W/crontab.realstub" "$W/bin/crontab"; cp "$W/crontab.drill" "$W/crontab.stub"
# MUTANT: queue_quiet always true -> the venv step would run on the live queue
mutf "$OVN_REAL/ops/box_bootstrap.sh" "$H2/overnight-queue/ops/box_bootstrap.q.sh" '  if ! queue_quiet; then fail' '  if false; then fail' || ok "mutant queue_quiet anchor" 1
rm -f "$H/overnight-queue/state/PAUSED"; : > "$W/pip.log"
BS_HOME="$H" BS_OVN="$H/overnight-queue" bash "$H2/overnight-queue/ops/box_bootstrap.q.sh" --only venvs --no-verify > "$W/venvlive.m.out" 2>&1
chk "MUTANT without the live-queue refusal is caught (pip ran against a live queue)" bash -c "[ -s '$W/pip.log' ]"
: > "$H/overnight-queue/state/PAUSED"

# 3d: android: the new copy cannot be moved into place -> the OLD cmdline-tools is restored, the step fails loudly, no leftovers
REALMV="$(command -v mv)"
mkdir -p "$W/mvfail"; printf '%s\n' '#!/bin/sh' 'for a in "$@"; do last="$a"; done' 'case "$1" in */.bootstrap-extract.*/cmdline-tools) echo "mv: stub: simulated failure" >&2; exit 1;; esac' "exec \"$REALMV\" \"\$@\"" > "$W/mvfail/mv"; chmod 755 "$W/mvfail/mv"
H4="$W/h4"; mkdir -p "$H4/android-sdk/cmdline-tools/latest/bin"
printf '#!/bin/sh\nexit 0\n' > "$H4/android-sdk/cmdline-tools/latest/bin/sdkmanager"; chmod 755 "$H4/android-sdk/cmdline-tools/latest/bin/sdkmanager"; printf 'Pkg.Revision=11.0\n' > "$H4/android-sdk/cmdline-tools/latest/source.properties"
PATH="$W/mvfail:$PATH" BS_HOME="$H4" BS_OVN="$H/overnight-queue" bash "$OPS/box_bootstrap.sh" --only android --no-verify > "$W/mvf.out" 2>&1; mvrc=$?
chk "android: the final mv fails -> exit 1, FAILED line says the previous copy was RESTORED, no 'cmdline-tools installed' success line" bash -c "[ $mvrc = 1 ] && grep -q 'previous copy was RESTORED' '$W/mvf.out' && ! grep -q 'cmdline-tools installed from the pinned zip' '$W/mvf.out'"
chk "  the OLD good cmdline-tools (revision 11.0) is back in place and still works; no latest.old-* left behind" bash -c "grep -q 'Pkg.Revision=11.0' '$H4/android-sdk/cmdline-tools/latest/source.properties' && [ -x '$H4/android-sdk/cmdline-tools/latest/bin/sdkmanager' ] && [ -z \"\$(ls -d '$H4'/android-sdk/cmdline-tools/latest.old-* 2>/dev/null)\" ]"
chk "  the failed run left no .bootstrap-extract.* and no ~/.bootstrap-dl behind" bash -c "[ -z \"\$(ls -d '$H4'/android-sdk/.bootstrap-extract.* 2>/dev/null)\" ] && [ ! -e '$H4/.bootstrap-dl' ]"
# MUTANT: the mv result ignored (the old behaviour)
mutf "$OVN_REAL/ops/box_bootstrap.sh" "$H2/overnight-queue/ops/box_bootstrap.a.sh" '      if ! mv "$ex/cmdline-tools" "$sdk/cmdline-tools/latest"; then' '      mv "$ex/cmdline-tools" "$sdk/cmdline-tools/latest"; if false; then' || ok "mutant android mv anchor" 1
H4b="$W/h4b"; mkdir -p "$H4b/android-sdk/cmdline-tools/latest/bin"; cp "$H4/android-sdk/cmdline-tools/latest/bin/sdkmanager" "$H4b/android-sdk/cmdline-tools/latest/bin/sdkmanager"; printf 'Pkg.Revision=11.0\n' > "$H4b/android-sdk/cmdline-tools/latest/source.properties"
PATH="$W/mvfail:$PATH" BS_HOME="$H4b" BS_OVN="$H/overnight-queue" bash "$H2/overnight-queue/ops/box_bootstrap.a.sh" --only android --no-verify > "$W/mvf.m.out" 2>&1
chk "MUTANT that ignores the mv status is caught (success claimed while the SDK has no cmdline-tools)" bash -c "grep -q 'cmdline-tools installed from the pinned zip' '$W/mvf.m.out' && [ ! -e '$H4b/android-sdk/cmdline-tools/latest/bin/sdkmanager' ]"
chk "a failed DOWNLOAD (curl stub) leaves no ~/.bootstrap-dl either" bash -c "[ ! -e '$H/.bootstrap-dl' ]"

echo "== phase 4: THE DRILL - full bootstrap (licences accepted, main crontab with GitHub ok)"
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --accept-android-licenses --install-main-crontab > "$W/boot.out" 2>&1; brc=$?
chk "bootstrap ends at exit 10: ONLY human-provided items remain" bash -c "[ $brc = 10 ] && grep -q 'RESULT: only human-provided items remain' '$W/boot.out'"
chk "  acceptance printed from box_verify: 0 automated drift items" bash -c "grep -q 'ACCEPTANCE (box_verify): .* 0 automated' '$W/boot.out'"
"$REALPY" - "$W/boot.out" > "$W/boot.keys" <<'PYEOF'
import re, sys
for l in open(sys.argv[1]):
    m = re.match(r"\[bootstrap\]\s+(WARN|CRIT)\s+(\S+)\s+(\S+): ", l)
    if m: print(m.group(2), m.group(3))
PYEOF
chk "  the outstanding items are exactly the human list: billwatch_db_url, 3 staging urls, qa_creds, fuzz baseline, contract_fuzz cron" bash -c "[ \"\$(sort '$W/boot.keys' | tr '\n' ';')\" = 'human cron_off:contract_fuzz;human state:billwatch_db_url_missing;human state:contract_fuzz_baseline_iptv_apps;human state:qa_creds_iptv_apps;human state:staging_url_billwatch;human state:staging_url_gitlark;human state:staging_url_iptv_apps;' ]"
chk "  venvs: every python repo has pytest-xdist AND (billwatch/gitlark/iptv_apps) requirements-dev installed (EXTRA=on reached pip)" bash -c "for d in billwatch/billwatch-backend gitlark/backend iptv_apps/iptv-backend test-automation-agent/backend shrike-monitor/backend shrike-notify/backend; do ls -d '$H/overnight-queue/repos/'\$d/.venv/lib/python3.12/site-packages/pytest_xdist-*.dist-info >/dev/null 2>&1 || exit 1; done; ls -d '$H/overnight-queue/repos/gitlark/backend/.venv/lib/python3.12/site-packages/pytest_mock-'*.dist-info >/dev/null"
chk "  android: pinned platforms android-34/36 and build-tools 34/35/36 + platform-tools installed through sdkmanager" bash -c "for x in platforms/android-34 platforms/android-36 build-tools/34.0.0 build-tools/35.0.0 build-tools/36.0.0 platform-tools; do [ -e '$H/android-sdk/'\$x ] || exit 1; done"
chk "  qa tools: all 8 pinned tools in ~/qa-venv" bash -c "for t in bandit semgrep pip-audit mutmut schemathesis mypy ruff gitleaks; do [ -x '$H/qa-venv/bin/'\$t ] || exit 1; done"
chk "  crontab: both managed blocks, the main snapshot (hygiene line), backup lines exactly once, the box_verify line" bash -c "c=\$(crontab -l); echo \"\$c\" | grep -q 'SUPPLY-LINES BEGIN' && echo \"\$c\" | grep -q 'QA-GATES BEGIN' && echo \"\$c\" | grep -q 'branch_hygiene.sh' && [ \$(echo \"\$c\" | grep -c 'box_home_backup.sh daily') = 1 ] && [ \$(echo \"\$c\" | grep -c 'box_home_backup.sh hourly') = 1 ] && echo \"\$c\" | grep -q 'ops/box_verify.sh'"
chk "  state dirs: qa_creds mode 700, qa_shadow present" bash -c "[ \"\$(stat -c %a '$H/overnight-queue/state/qa_creds' 2>/dev/null || stat -f %Lp '$H/overnight-queue/state/qa_creds')\" = 700 ] && [ -d '$H/overnight-queue/state/qa_shadow' ]"
chk "  the human checklist printed the exact Railway regeneration command and per-repo staging URL commands" bash -c "grep -q 'railway variables --project 38d377fc-d005-41fc-9675-e84659ef7ce1 --environment production --service Postgres' '$W/boot.out' && grep -q 'echo https://billwatch-staging.up.railway.app > state/staging_url_billwatch' '$W/boot.out' && grep -q 'state/qa_creds/iptv_apps.json' '$W/boot.out'"
chk "  nothing secret was invented or printed: no value written to state/billwatch_db_url or qa_creds" bash -c "[ ! -e '$H/overnight-queue/state/billwatch_db_url' ] && [ ! -e '$H/overnight-queue/state/qa_creds/iptv_apps.json' ]"

echo "== phase 5: idempotent re-run"
cron1="$(crontab -l | cksum)"; sdk1="$(find "$H/android-sdk" -type f | wc -l | tr -d ' ')"
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --accept-android-licenses --install-main-crontab > "$W/boot2.out" 2>&1; b2rc=$?
chk "second run: same result (exit 10), crontab byte-identical, no duplicate lines, same android file count" bash -c "[ $b2rc = 10 ] && [ \"\$(crontab -l | cksum)\" = '$cron1' ] && [ \"\$(find '$H/android-sdk' -type f | wc -l | tr -d ' ')\" = '$sdk1' ]"
chk "  the populated crontab was NOT replaced by the snapshot (refused, pending note)" grep -q 'already has active lines' "$W/boot2.out"

echo "== phase 6: the human provides the secrets -> the SAME acceptance run is clean"
SD="$H/overnight-queue/state"
printf 'postgresql://u:p@h/db\n' > "$SD/billwatch_db_url"; chmod 600 "$SD/billwatch_db_url"
for r in billwatch gitlark iptv_apps; do echo "https://$r-staging.example" > "$SD/staging_url_$r"; done
printf '{"email":"qa@example.test","password":"x"}' > "$SD/qa_creds/iptv_apps.json"; chmod 600 "$SD/qa_creds/iptv_apps.json"; echo '{}' > "$SD/qa_shadow/contract_fuzz_baseline_iptv_apps.json"
( cd "$H/overnight-queue" && HOME="$H" OVN_DIR="$H/overnight-queue" bash ops/install_qa_cron.sh --apply --enable contract_fuzz ) >/dev/null 2>&1
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --only verify > "$W/boot3.out" 2>&1; b3rc=$?
chk "acceptance: exit 0, 0 drift - a full rebuild reaches the desired state" bash -c "[ $b3rc = 0 ] && grep -q 'ACCEPTANCE (box_verify): 0 drift' '$W/boot3.out' && grep -q 'RESULT: clean' '$W/boot3.out'"

echo "== BS_BACKUPS reaches the acceptance run (L1 review: a non-default backup path gave a false backup:* crit)"
BK2="$W/drive/box-backups2"; mkdir -p "$BK2"; : > "$BK2/heartbeat-daily.log"; : > "$BK2/heartbeat-hourly.log"
env -u BV_BACKUPS BS_HOME="$H" BS_BACKUPS="$BK2" bash "$OPS/box_bootstrap.sh" --only verify > "$W/bk.out" 2>&1; bkrc=$?
chk "backups at a NON-default path given as BS_BACKUPS: acceptance exits 0 (the heartbeats are read from there)" test "$bkrc" = 0
"$REALPY" -c 'import os,sys,time; t=time.time()-27*3600; os.utime(sys.argv[1],(t,t))' "$BK2/heartbeat-daily.log"
env -u BV_BACKUPS BS_HOME="$H" BS_BACKUPS="$BK2" bash "$OPS/box_bootstrap.sh" --only verify > "$W/bk2.out" 2>&1; bk2rc=$?
chk "  and a STALE heartbeat in that path IS reported (proves it really reads BS_BACKUPS): exit 1 + backup:daily_heartbeat_stale" bash -c "[ $bk2rc = 1 ] && grep -q 'backup:daily_heartbeat_stale' '$W/bk2.out'"
: > "$BK2/heartbeat-daily.log"
cp "$OVN_REAL/ops/box_bootstrap.sh" "$H/overnight-queue/ops/box_bootstrap.b.sh"
"$REALPY" - "$H/overnight-queue/ops/box_bootstrap.b.sh" <<'PYEOF'
import sys
p = sys.argv[1]; s = open(p).read(); old = 'BV_BACKUPS="${BS_BACKUPS:-${BV_BACKUPS:-}}" '
assert s.count(old) == 1
open(p, "w").write(s.replace(old, ""))
PYEOF
env -u BV_BACKUPS BS_HOME="$H" BS_BACKUPS="$BK2" bash "$H/overnight-queue/ops/box_bootstrap.b.sh" --only verify > "$W/bk3.out" 2>&1; bk3rc=$?
chk "MUTANT that does not forward BS_BACKUPS is caught (false backup:* drift on a healthy box: exit != 0)" test "$bk3rc" != 0
rm -f "$H/overnight-queue/ops/box_bootstrap.b.sh"

echo "== provision_test_envs.sh OVN_PROVISION_EXTRA (default off = unchanged)"
PV="$(safe_mktemp_dir_in "$W" pv)" || exit 1; mkdir -p "$PV/overnight-queue/repos/billwatch/billwatch-backend" "$PV/overnight-queue/repos/shrike-notify/backend" "$PV/overnight-queue/repos/iptv_apps/iptv-backend"
for d in billwatch/billwatch-backend shrike-notify/backend iptv_apps/iptv-backend; do printf 'fastapi\n' > "$PV/overnight-queue/repos/$d/requirements.txt"; done
printf -- '-r requirements.txt\npytest-mock\n' > "$PV/overnight-queue/repos/billwatch/billwatch-backend/requirements-dev.txt"
pvrun(){ : > "$W/pip.log"; ( HOME="$PV" bash "$OVN_REAL/${1:-provision_test_envs.sh}" ) > "$W/pv.out" 2>&1; }
OVN_PROVISION_EXTRA=off pvrun
chk "default (EXTRA off): no pytest-xdist for billwatch, no requirements-dev.txt install (exactly the old behaviour)" bash -c "! grep -q 'requirements-dev.txt' '$W/pip.log' && [ \$(grep -c 'pytest-xdist' '$W/pip.log') = 1 ]"
chk "  (the one xdist install is the pre-existing iptv_apps allowlist)" bash -c "grep -q 'pytest-xdist' '$W/pip.log'"
OVN_PROVISION_EXTRA=on pvrun
chk "EXTRA=on: pytest-xdist for ALL three python repos and requirements-dev.txt where the repo has one" bash -c "[ \$(grep -c 'pytest-xdist' '$W/pip.log') -ge 4 ] && grep -q 'install --quiet -r requirements-dev.txt' '$W/pip.log' && [ \$(grep -c 'requirements-dev.txt' '$W/pip.log') = 1 ]"
# mutants of the provisioner
mutf(){ "$REALPY" - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
s = open(sys.argv[1]).read(); old, new = sys.argv[3], sys.argv[4]
assert s.count(old) == 1, "anchor %r found %d" % (old, s.count(old))
open(sys.argv[2], "w").write(s.replace(old, new))
PYEOF
}
mutf "$OVN_REAL/provision_test_envs.sh" "$W/m_prov.sh" 'if [ "${OVN_PROVISION_EXTRA:-off}" = on ]; then' 'if false; then' || ok "mutant anchor provision" 1
: > "$W/pip.log"; ( OVN_PROVISION_EXTRA=on HOME="$PV" bash "$W/m_prov.sh" ) > "$W/pv.out" 2>&1
chk "MUTANT EXTRA ignored is caught (no requirements-dev.txt install with EXTRA=on)" bash -c "! grep -q 'requirements-dev.txt' '$W/pip.log'"

echo "== bootstrap mutants"
mutb(){ mutf "$OVN_REAL/ops/box_bootstrap.sh" "$1" "$2" "$3"; }
mkdir -p "$W/mops"; cp "$OVN_REAL/ops/"* "$W/mops/" 2>/dev/null
# M1: sha256 check removed -> a tampered zip would be unzipped
mutb "$W/mops/box_bootstrap.sh" 'if [ "$got" != "$want" ]; then fail' 'if false; then fail' || ok "mutant1 anchor" 1
mv "$H/android-sdk/cmdline-tools/latest" "$W/latest.aside"
BS_OVN="$H/overnight-queue" BS_HOME="$H" BS_ANDROID_SHA256="0000000000000000000000000000000000000000000000000000000000000000" bash "$W/mops/box_bootstrap.sh" --only android > "$W/m1.out" 2>&1
chk "MUTANT no SHA256 check is caught (a zip with the wrong hash got installed)" test -x "$H/android-sdk/cmdline-tools/latest/bin/sdkmanager"
safe_rm_rf "$H/android-sdk/cmdline-tools/latest"; mv "$W/latest.aside" "$H/android-sdk/cmdline-tools/latest"
# M2: github gate removed
mutb "$W/mops/box_bootstrap.sh" 'elif ! gh_ok; then pend' 'elif false; then pend' || ok "mutant2 anchor" 1
cp "$W/crontab.stub" "$W/crontab.keep"; : > "$W/crontab.stub"
BS_OVN="$H/overnight-queue" BS_HOME="$H" BS_GH_CHECK=fail bash "$W/mops/box_bootstrap.sh" --only cron --install-main-crontab > "$W/m2.out" 2>&1
chk "MUTANT main crontab without the GitHub gate is caught (the pushing lines were installed)" bash -c "crontab -l | grep -q 'branch_hygiene.sh'"
cp "$W/crontab.keep" "$W/crontab.stub"
# M3: licences accepted without the flag
mutb "$W/mops/box_bootstrap.sh" 'if [ "$LIC" = 1 ]; then yes |' 'if true; then yes |' || ok "mutant3 anchor" 1
mv "$H/android-sdk" "$W/sdk.aside2"
BS_OVN="$H/overnight-queue" BS_HOME="$H" bash "$W/mops/box_bootstrap.sh" --only android > "$W/m3.out" 2>&1
chk "MUTANT licences auto-accepted is caught (platforms installed without --accept-android-licenses)" test -d "$H/android-sdk/platforms/android-34"
safe_rm_rf "$H/android-sdk"; mv "$W/sdk.aside2" "$H/android-sdk"
# M4: acceptance exit code always 0
mutb "$W/mops/box_bootstrap.sh" 'sys.exit(0 if not it else (10 if all(i["class"] == "human" for i in it) else 1))' 'sys.exit(0)' || ok "mutant4 anchor" 1
mv "$SD/billwatch_db_url" "$W/dburl.aside"
BS_OVN="$H/overnight-queue" BS_HOME="$H" bash "$W/mops/box_bootstrap.sh" --only verify > "$W/m4.out" 2>&1; m4rc=$?
BS_HOME="$H" bash "$OPS/box_bootstrap.sh" --only verify > "$W/real4.out" 2>&1; r4rc=$?
chk "REAL acceptance exits 10 with a human item outstanding, the MUTANT (always 0) is caught" bash -c "[ $r4rc = 10 ] && [ $m4rc = 0 ]"
mv "$W/dburl.aside" "$SD/billwatch_db_url"
# M5: box_recover godot4 link removed
mutf "$OVN_REAL/ops/box_recover.sh" "$W/mops/box_recover.sh" '    ln -sf "Godot_v${GODOT_VER}_linux.x86_64" "$dl/godot4"' '    true' || ok "mutant5 anchor" 1
H5="$W/h5"; mkdir -p "$H5"; RC_HOME="$H5" RC_BACKUPS="$W/nodrive" RC_GODOT_ZIP="$W/godot.zip" RC_GODOT_SHA512_OVERRIDE="$GODOT_SHA" bash "$W/mops/box_recover.sh" --skip-queue --skip-aider --skip-hostkey --skip-repos --no-cron >/dev/null 2>&1
chk "MUTANT no godot4 link is caught (run_overnight.sh would silently skip every Godot verify): the real script has it, the mutant does not" bash -c "[ ! -e '$H5/godot/godot4' ] && [ -e '$H5/godot/godot' ]"

echo "test_box_bootstrap: $((n-fails)) passed, $fails failed"
[ "$fails" = 0 ]
