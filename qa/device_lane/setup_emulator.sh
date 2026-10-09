#!/usr/bin/env bash
# setup_emulator.sh - idempotent provisioning of the headless Android emulator lane (no root needed).
#   setup_emulator.sh            install missing SDK packages + create the AVD + check appium (safe to re-run)
#   setup_emulator.sh --check    read-only: report what is present/missing, change nothing
#   setup_emulator.sh --measure  also boot the AVD headless, record boot seconds + idle CPU/RAM, then shut it down
# The ONLY system-wide change ever needed is `sudo usermod -aG kvm <user>` (a human does that once; see README).
# Exit 0 = lane is ready, 1 = something missing (listed on stderr), 2 = bad usage. Last stdout line is one JSON object.
set -u
SELF="${BASH_SOURCE[0]}"; case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" && pwd)"
# shellcheck source=lane_env.sh
. "$HERE/lane_env.sh"

CHECK=0; MEASURE=0
for a in "$@"; do case "$a" in --check) CHECK=1 ;; --measure) MEASURE=1 ;; *) echo "usage: $0 [--check] [--measure]" >&2; exit 2 ;; esac; done

missing=()
have_sdk_pkg() { [ -e "$ANDROID_HOME/$1" ]; }

# 1. kvm
if kvm_ok; then KVM=ok; else KVM=no_access; missing+=("kvm access (run once: sudo usermod -aG kvm $(id -un); then log in again / use a new session)"); fi
[ -e /dev/kvm ] || { KVM=no_device; }

# 2. SDK packages (emulator, platform-tools, system image)
need_pkgs=()
have_sdk_pkg emulator/emulator || need_pkgs+=("emulator")
have_sdk_pkg platform-tools/adb || need_pkgs+=("platform-tools")
IMG_DIR="$(printf '%s' "$DL_IMAGE" | tr ';' '/')"
have_sdk_pkg "$IMG_DIR/system.img" || need_pkgs+=("$DL_IMAGE")
if [ ${#need_pkgs[@]} -gt 0 ]; then
  if [ "$CHECK" = 1 ]; then missing+=("sdk packages: ${need_pkgs[*]}")
  elif [ -x "$SDKMANAGER" ]; then
    dl_log "installing SDK packages: ${need_pkgs[*]}"
    # licenses are accepted non-interactively; the user already holds android-sdk-license on this box.
    # Signal-safe: yes | would SIGPIPE; feed a finite stream instead.
    { for _ in $(seq 1 40); do echo y; done; } | "$SDKMANAGER" --sdk_root="$ANDROID_HOME" "${need_pkgs[@]}" >/tmp/qa-dl-sdkmanager.$$.log 2>&1 \
      || { tail -5 /tmp/qa-dl-sdkmanager.$$.log >&2; missing+=("sdkmanager failed for: ${need_pkgs[*]}"); }
    rm -f /tmp/qa-dl-sdkmanager.$$.log
  else missing+=("sdkmanager not found at $SDKMANAGER"); fi
fi

# 3. AVD
mkdir -p "$ANDROID_AVD_HOME" 2>/dev/null
if [ ! -f "$ANDROID_AVD_HOME/$DL_AVD.ini" ]; then
  if [ "$CHECK" = 1 ]; then missing+=("avd $DL_AVD")
  elif [ -x "$AVDMANAGER" ] && have_sdk_pkg "$IMG_DIR/system.img"; then
    dl_log "creating AVD $DL_AVD"
    echo no | "$AVDMANAGER" create avd -n "$DL_AVD" -k "$DL_IMAGE" -d pixel_6 --force >/dev/null 2>&1 \
      || missing+=("avdmanager create avd failed")
  else missing+=("cannot create avd (avdmanager or system image missing)"); fi
fi
CFG="$ANDROID_AVD_HOME/$DL_AVD.avd/config.ini"
if [ -f "$CFG" ] && [ "$CHECK" = 0 ]; then
  # deterministic, modest resources; no soft-keyboard weirdness; no camera/audio/sensors we do not test.
  setkey() { if grep -q "^$1=" "$CFG"; then sed -i.bak "s|^$1=.*|$1=$2|" "$CFG"; else echo "$1=$2" >>"$CFG"; fi; }
  setkey hw.ramSize "$DL_RAM_MB"; setkey hw.cpu.ncore "$DL_CORES"; setkey disk.dataPartition.size 6G
  setkey hw.audioInput no; setkey hw.audioOutput no; setkey hw.camera.back none; setkey hw.camera.front none
  setkey hw.gpu.enabled yes; setkey hw.gpu.mode swiftshader_indirect; setkey showDeviceFrame no
  rm -f "$CFG.bak"
fi

# 4. appium + uiautomator2 driver (private npm prefix; production dir is never touched)
if [ ! -x "$DL_APPIUM_BIN" ]; then
  if [ "$CHECK" = 1 ] || ! command -v npm >/dev/null 2>&1; then missing+=("appium at $DL_APPIUM_BIN")
  else
    dl_log "installing appium into $(dirname "$(dirname "$(dirname "$DL_APPIUM_BIN")")")"
    d="$(dirname "$(dirname "$(dirname "$DL_APPIUM_BIN")")")"; mkdir -p "$d" && (cd "$d" && { [ -f package.json ] || npm init -y >/dev/null 2>&1; } && npm install appium@3 >/dev/null 2>&1) \
      || missing+=("npm install appium failed")
  fi
fi
if [ -x "$DL_APPIUM_BIN" ]; then
  if ! "$DL_APPIUM_BIN" driver list --installed 2>&1 | grep -q uiautomator2; then
    if [ "$CHECK" = 1 ]; then missing+=("appium uiautomator2 driver"); else
      dl_log "installing appium uiautomator2 driver"
      "$DL_APPIUM_BIN" driver install uiautomator2 >/dev/null 2>&1 || missing+=("appium driver install uiautomator2 failed"); fi
  fi
fi
command -v node >/dev/null 2>&1 || missing+=("node")
command -v java >/dev/null 2>&1 || missing+=("java (17+)")

# 5. optional boot measurement
BOOT_S=null; IDLE_CPU=null; IDLE_RSS_MB=null
if [ "$MEASURE" = 1 ] && [ ${#missing[@]} -eq 0 ]; then
  TMPD="$(mktemp -d /tmp/qa-dl-measure.XXXXXX)"
  trap 'stop_emulator "$TMPD/emu.pid"; stop_adb_if_idle; rm -rf "$TMPD"' EXIT
  if start_emulator "$TMPD/emu.pid" "$TMPD/emu.log"; then
    BOOT_S="$DL_BOOT_SECONDS"
    sleep 45   # let boot-time churn settle; this is the "idle" window
    epid="$(pgrep -f "qemu-system.*-port $DL_EMU_PORT" | head -1)"
    if [ -n "$epid" ]; then
      # CPU over a 30s window from /proc ticks (cores-worth, i.e. 100 = one core fully busy), RSS in MB.
      t1="$(awk '{print $14+$15}' "/proc/$epid/stat" 2>/dev/null)"; sleep 30; t2="$(awk '{print $14+$15}' "/proc/$epid/stat" 2>/dev/null)"
      hz="$(getconf CLK_TCK 2>/dev/null || echo 100)"
      IDLE_CPU="$(awk -v a="$t1" -v b="$t2" -v hz="$hz" 'BEGIN{printf "%.1f", (b-a)/hz/30*100}')"
      IDLE_RSS_MB="$(awk '/VmRSS/ {printf "%d", $2/1024}' "/proc/$epid/status" 2>/dev/null)"
    fi
  else missing+=("emulator failed to boot headless (see $TMPD/emu.log tail below)"); tail -5 "$TMPD/emu.log" >&2; fi
fi

ok=true; [ ${#missing[@]} -gt 0 ] && ok=false
printf '{"ready":%s,"kvm":"%s","avd":"%s","image":"%s","boot_seconds":%s,"idle_cpu_pct_of_one_core":%s,"idle_rss_mb":%s,"missing":[' \
  "$ok" "$KVM" "$DL_AVD" "$DL_IMAGE" "$BOOT_S" "$IDLE_CPU" "$IDLE_RSS_MB"
sep=""; for m in "${missing[@]:-}"; do [ -n "$m" ] || continue; printf '%s"%s"' "$sep" "$(printf '%s' "$m" | sed 's/\\/\\\\/g; s/"/\\"/g')"; sep=","; done
printf ']}\n'
for m in "${missing[@]:-}"; do [ -n "$m" ] && echo "MISSING: $m" >&2; done
[ "$ok" = true ]
