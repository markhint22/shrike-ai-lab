#!/usr/bin/env bash
# lib_gradle_infra.sh - Gradle host-infra classification for the gradle gates (2026-11-11, package q-infra-gates).
#
# 2026-11-11 incident: unattended-upgrades replaced openjdk-17 / libc-bin on the box at 06:17-06:19 while a long-lived Gradle 8.13 daemon kept running on the replaced files. From then on
# every child process that daemon spawned failed (`Failed to exec spawn helper`, `AAPT2 ... Daemon startup failed`), and the iptv_apps hygiene gate was scored RED for 9 h (10 overnight passes,
# the claude lane since 11:34) although no commit was at fault. A restart of the daemon (`./gradlew --stop`) is the whole cure.
#
# ovn_gradle_run <gradle dir> <out file> [timeout s]   runs `./gradlew test --console=plain` (same ANDROID_HOME/local.properties setup the gates always used), output to <out file>, returns gradle's rc.
#   1. preflight: a Gradle daemon whose java binary is `(deleted)` in /proc/<pid>/exe is stopped with `./gradlew --stop` BEFORE the build (the replaced-JDK state itself).
#   2. a failed run whose output carries an INFRA signature (below) is retried ONCE after `./gradlew --stop` (that exact project dir; never a kill).
#      Signatures count only in infrastructure context (Caused by:/What went wrong block/banner lines) and NEVER when the output also carries test-failure markers (FAILED test lines, "N tests
#      completed, M failed", assertion text): a real red that merely quotes an infra message stays an ordinary RED. `./gradlew --stop` stops EVERY daemon of that gradle version, so it is
#      serialized (flock) and skipped - with one short wait before the retry - while another gradle client (gradlew/GradleWrapperMain) is active.
#   3. still failing with an infra signature on the retry -> OVN_GRADLE_INFRA_RED=1 (INFRA-RED: neither a code failure nor mergeable). The caller keeps its merge decision conservative.
# Kill switch (pure bugfix, default ON): OVN_GRADLE_INFRA_RETRY=off = no preflight stop, no retry, no classification (byte-identical old behaviour: one run, rc as is).
# ovn_gradle_infra_text <file>      0 = the file carries an infra signature (always 1 when the switch is off).
# ovn_gradle_infra_alert <state dir> <label> <msg>   ONE alerts.log 'warn' per label per OVN_GRADLE_INFRA_ALERT_SEC (default 3600) under the distinct key `gradle-infra-red`.
# Env for tests: OVN_GRADLE_PROC_ROOT (default /proc) lets a fake /proc tree stand in for the real one.

_OVN_GRADLE_INFRA_RE='Failed to exec spawn helper|AAPT2[^[:cntrl:]]*Daemon startup failed|Daemon startup failed|Could not connect to the Gradle daemon|java\.io\.IOException: error=(2|12)([^0-9]|$)|Unable to start the daemon process'
OVN_GRADLE_INFRA_RED=0

_ovn_gi_log() { if declare -F log >/dev/null 2>&1; then log "$*"; else echo "[gradle-infra] $*" >&2; fi; }

# Test-failure markers: when ANY of these is present the run is an ordinary RED, never infra (a real failure whose output merely quotes an infra-looking message must not be hidden).
_OVN_GRADLE_TESTFAIL_RE='^[[:space:]]*FAILED:|^[[:space:]]*[A-Za-z_][^[:space:]]* > .* FAILED[[:space:]]*$|[0-9]+ tests? completed, [0-9]+ failed|There were failing tests|<failure[ >]|AssertionFailedError|AssertionError|ComparisonFailure'
# A signature only counts in INFRASTRUCTURE context: a `Caused by:` line, a line that BEGINS with the signature/exception (the daemon-start banners, the AAPT2 / IOException lines), an
# `Execution failed for task` line, or any line inside a `* What went wrong:` block (until `* Try:`). A signature quoted mid-line (`expected java.io.IOException: error=2 ...`) never counts.
_OVN_GRADLE_INFRA_LINE_RE='^[[:space:]>*-]*(Caused by:|java\.io\.IOException|AAPT2|Unable to start the daemon process|Could not connect to the Gradle daemon|Daemon startup failed|Failed to exec spawn helper|Execution failed for task)'

ovn_gradle_infra_text() {
  [ "${OVN_GRADLE_INFRA_RETRY:-on}" = off ] && return 1
  [ -s "${1:-}" ] || return 1
  grep -aqE "$_OVN_GRADLE_TESTFAIL_RE" "$1" 2>/dev/null && return 1   # test failures exist: ordinary RED
  OVN_GI_SIG="$_OVN_GRADLE_INFRA_RE" OVN_GI_CTX="$_OVN_GRADLE_INFRA_LINE_RE" awk '
    /^[[:space:]]*\* What went wrong:/ { wb = 1; next }
    /^[[:space:]]*\* Try:/ { wb = 0 }
    ($0 ~ ENVIRON["OVN_GI_SIG"]) && (wb || $0 ~ ENVIRON["OVN_GI_CTX"]) { hit = 1; exit }
    END { exit hit ? 0 : 1 }' "$1" 2>/dev/null
}

# pids (one per line) of Gradle daemons whose java executable was deleted/replaced underneath them
ovn_gradle_deleted_daemons() {
  local root="${OVN_GRADLE_PROC_ROOT:-/proc}" d pid exe cmd
  [ -d "$root" ] || return 0
  for d in "$root"/[0-9]*; do
    [ -d "$d" ] || continue
    pid="${d##*/}"
    cmd="$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)" || continue
    case "$cmd" in *org.gradle.launcher.daemon.bootstrap.GradleDaemon*) ;; *) continue;; esac   # a java GradleDaemon main class, not any argv that mentions 'GradleDaemon'
    exe="$(readlink "$d/exe" 2>/dev/null)" || continue
    case "$exe" in *"(deleted)"*) ;; *) continue;; esac
    exe="${exe% (deleted)}"; exe="${exe##*/}"
    case "$exe" in java*) echo "$pid";; esac   # only java processes are ever candidates
  done
  return 0
}

# pids (one per line) of OTHER gradle client processes (gradlew wrapper script / GradleWrapperMain) - daemons are not clients. `./gradlew --stop` stops EVERY daemon of that gradle version,
# including the ones serving another repo's build, so it is only run when no other client is active.
ovn_gradle_active_clients() {
  local root="${OVN_GRADLE_PROC_ROOT:-/proc}" d pid a0 a
  [ -d "$root" ] || return 0
  for d in "$root"/[0-9]*; do
    [ -d "$d" ] || continue
    pid="${d##*/}"; [ "$pid" = "$$" ] && continue; [ "$pid" = "${BASHPID:-$$}" ] && continue
    [ -r "$d/cmdline" ] || continue
    local -a argv=(); local _t
    while IFS= read -r -d '' _t; do argv+=("$_t"); done < "$d/cmdline" 2>/dev/null
    [ "${#argv[@]}" -gt 0 ] || continue
    case "$(printf '%s ' "${argv[@]}")" in *org.gradle.launcher.daemon.bootstrap.GradleDaemon*) continue;; esac
    a0="${argv[0]##*/}"
    case "$a0" in sh|bash|dash|java*|timeout) ;; *) continue;; esac
    for a in "${argv[@]:1}"; do
      case "$a" in *org.gradle.wrapper.GradleWrapperMain*|gradlew|*/gradlew) echo "$pid"; break;; esac
    done
  done
  return 0
}

# <gradle dir>: the project's own wrapper stops its daemons; bounded, never fatal. Serialized by flock on OVN_GRADLE_STOP_LOCK and only run when no other gradle client is active; otherwise the
# stop is SKIPPED (returns 1) after a short wait (OVN_GRADLE_STOP_WAIT, default 20 s) so the caller's single retry runs against whatever daemon is there. Returns 0 = stop ran.
_ovn_gradle_stop() {
  local lk="${OVN_GRADLE_STOP_LOCK:-${STATE_DIR:-${TMPDIR:-/tmp}}/gradle_stop.lock}" wait_s="${OVN_GRADLE_STOP_WAIT:-20}" rc=0
  case "$wait_s" in ''|*[!0-9]*) wait_s=20;; esac
  mkdir -p "$(dirname "$lk")" 2>/dev/null
  (
    if command -v flock >/dev/null 2>&1 && exec 9>"$lk" 2>/dev/null; then flock -w 120 9 || exit 2; fi
    if [ -n "$(ovn_gradle_active_clients)" ]; then
      _ovn_gi_log "  gradle-infra: another gradle client is active - NOT running ./gradlew --stop (it would stop that build's daemon); waiting ${wait_s}s then retrying once"
      sleep "$wait_s"; exit 1
    fi
    cd "$1" 2>/dev/null && timeout 90 ./gradlew --stop >/dev/null 2>&1
    exit 0
  ) || rc=$?
  return "$rc"
}

_ovn_gradle_attempt() {   # <gradle dir> <timeout> <out file (appended)>
  ( cd "$1" &&
    export ANDROID_HOME="$HOME/android-sdk" &&
    [ -f local.properties ] || echo "sdk.dir=$ANDROID_HOME" > local.properties &&
    timeout "$2" ./gradlew test --console=plain ) >> "$3" 2>&1
}

ovn_gradle_run() {
  local gd="$1" out="$2" to="${3:-${TEST_TIMEOUT:-900}}" rc rc2 tmp dead
  OVN_GRADLE_INFRA_RED=0
  : > "$out"
  if [ "${OVN_GRADLE_INFRA_RETRY:-on}" != off ]; then
    dead="$(ovn_gradle_deleted_daemons | tr '\n' ' ')"
    if [ -n "${dead// /}" ]; then
      _ovn_gi_log "  gradle-infra: daemon(s) running on a deleted java binary (pid ${dead% }) - ./gradlew --stop in $gd before building"
      echo "--- gradle-infra: stopped daemon(s) on a deleted java binary (pid ${dead% }) ---" >> "$out"
      _ovn_gradle_stop "$gd"
    fi
  fi
  _ovn_gradle_attempt "$gd" "$to" "$out"; rc=$?
  [ "$rc" -ne 0 ] || return 0
  ovn_gradle_infra_text "$out" || return "$rc"
  _ovn_gi_log "  gradle-infra: infra signature in the gradle output (host/daemon fault, not a test) - ./gradlew --stop in $gd and retrying once"
  echo "--- gradle-infra: infra signature; ./gradlew --stop and retry once ---" >> "$out"
  _ovn_gradle_stop "$gd"
  tmp="$(mktemp)" || { OVN_GRADLE_INFRA_RED=1; return "$rc"; }
  _ovn_gradle_attempt "$gd" "$to" "$tmp"; rc2=$?
  cat "$tmp" >> "$out"
  if [ "$rc2" -ne 0 ] && ovn_gradle_infra_text "$tmp"; then
    OVN_GRADLE_INFRA_RED=1
    echo "--- gradle-infra: INFRA-RED (same class of signature after the retry; not a code verdict) ---" >> "$out"
  else
    [ "$rc2" -eq 0 ] && _ovn_gi_log "  gradle-infra: the retry after ./gradlew --stop passed (daemon fault cleared)"
  fi
  rm -f "$tmp"
  return "$rc2"
}

# Consecutive INFRA-RED passes per repo+lane (state/gradle_infra_red_count/<repo>__<lane>): ovn_gradle_infra_red_count <state dir> <repo> <lane> inc|reset|get -> prints the (new) count.
# A pass with any other verdict (green, ordinary red, nothing to gate) resets it; the caller falls through to normal red scoring once it exceeds OVN_HYG_INFRA_RED_MAX (default 3).
ovn_gradle_infra_red_count() {
  local sd="${1:-}" f n=0
  f="$sd/gradle_infra_red_count/${2:-?}__${3//[^A-Za-z0-9._-]/_}"
  if [ "${4:-get}" = reset ]; then rm -f "$f" 2>/dev/null; echo 0; return 0; fi
  [ -f "$f" ] && read -r n < "$f" 2>/dev/null
  case "$n" in ''|*[!0-9]*) n=0;; esac
  if [ "${4:-get}" = inc ]; then
    n=$((n + 1))
    # FAIL SAFE toward escalation: if the counter cannot be written (dir unwritable, disk full) or does not read back, a stuck `inc` would return 1 forever and the lane would stay INFRA-RED with
    # no escalation. Report a count past the budget instead, so the caller falls through to normal red scoring (review flag + streak -> the stuck check pages).
    if ! { mkdir -p "${f%/*}" 2>/dev/null && { printf '%s\n' "$n" > "$f.$$"; } 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null && [ "$(cat "$f" 2>/dev/null)" = "$n" ]; }; then
      rm -f "$f.$$" 2>/dev/null
      local mx="${OVN_HYG_INFRA_RED_MAX:-3}"; case "$mx" in ''|*[!0-9]*) mx=3;; esac
      _ovn_gi_log "  gradle-infra: INFRA-RED counter ${f%/*} is not writable - failing safe toward escalation" >&2   # stderr: the caller captures stdout (the count) via $(...)
      [ "$n" -gt "$mx" ] || n=$((mx + 1))
    fi
  fi
  echo "$n"
}

ovn_gradle_infra_alert() {   # <state dir> <label> <msg> [level warn|crit]
  local sd="${1:-}" lbl="${2:-?}" msg="${3:-}" lvl="${4:-warn}" f now last gap
  [ -n "$sd" ] && [ -d "$sd" ] || return 0
  gap="${OVN_GRADLE_INFRA_ALERT_SEC:-3600}"; case "$gap" in ''|*[!0-9]*) gap=3600;; esac
  f="$sd/gradle_infra_red.${lbl//[^A-Za-z0-9._-]/_}"; [ "$lvl" = warn ] || f="$f.$lvl"
  now="$(date +%s)"; last=0; [ -f "$f" ] && read -r last < "$f" 2>/dev/null
  case "$last" in ''|*[!0-9]*) last=0;; esac
  [ $((now - last)) -ge "$gap" ] || return 0
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${lvl} | gradle-infra-red | ${lbl}: ${msg}" >> "$sd/alerts.log" 2>/dev/null || return 0
  printf '%s\n' "$now" > "$f.$$" 2>/dev/null && mv -f "$f.$$" "$f" 2>/dev/null
  return 0
}
