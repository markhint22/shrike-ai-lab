#!/usr/bin/env bash
# Z4 (2026-11-07): scripts/mac-native-build-check.sh log lines carry a timestamp and a broken build names its first error line (the 11-05..11-07 "NATIVE BUILD BROKEN: tvOS iOS" x6 had no
# timestamps and no cause; it was an Xcode-update / CoreSimulator-out-of-date host problem, not code). Hermetic: local bare origin, stub xcodebuild + gradlew, no network, no Xcode.
# Mutants: M1 no timestamp; M2 cause line dropped.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
S="${MAC_NATIVE_BUILD_CHECK:-$HERE/../../../mac-native-build-check.sh}"
[ -f "$S" ] || { echo "  SKIP: mac-native-build-check.sh not found"; exit 77; }
command -v timeout >/dev/null 2>&1 || [ -x /opt/homebrew/bin/timeout ] || { echo "  SKIP: no timeout(1) on this host"; exit 77; }
export TZ=UTC NTFY_SERVER=http://127.0.0.1:9
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT
n=0; fails=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then echo "  ok   $1"; else echo "  FAIL $1"; fails=$((fails+1)); fi; }
chk() { local d="$1"; shift; "$@" >/dev/null 2>&1; ok "$d" $?; }
git init -q --bare "$T/origin.git"; git init -q "$T/src"; mkdir -p "$T/src/iptv-ios" "$T/src/iptv-android"; : > "$T/src/iptv-ios/x"; printf '#!/bin/sh\nexit 0\n' > "$T/src/iptv-android/gradlew"; chmod +x "$T/src/iptv-android/gradlew"
git -C "$T/src" add -A; git -C "$T/src" -c user.email=t@t -c user.name=t commit -q -m init; git -C "$T/src" branch -M overnight/feature; git -C "$T/src" remote add origin "$T/origin.git"; git -C "$T/src" push -q origin overnight/feature
git clone -q "$T/origin.git" "$T/inter"; mkdir -p "$T/bin"
runit() { # runit <script> <xcodebuild-exit> -> $T/out.txt
  printf '#!/bin/sh\n[ "%s" = 0 ] && exit 0\necho "CoreSimulator is out of date. Current version (1174.9.2) is older than build version (1174.21.0)." >&2\nexit 70\n' "$2" > "$T/bin/xcodebuild"; chmod +x "$T/bin/xcodebuild"
  rm -rf "$T/wt" "$T/logs"; git -C "$T/inter" worktree prune; mkdir -p "$T/logs"
  ( safe_set_sandbox_home "$T" || exit 1; export PATH="$T/bin:$PATH" IPTV_BUILD_CHECK_WORKTREE="$T/wt" IPTV_REPO="$T/inter" TMPDIR="$T/logs" ANDROID_HOME="$T/sdk" JAVA_HOME="$T/jdk"; bash "$1" > "$T/out.txt" 2>&1 < /dev/null ); RC=$?
}
TSRE='^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} '
runit "$S" 0
chk "green: rc 0 and the log line starts with a timestamp" bash -c "[ $RC -eq 0 ] && grep -Eq '$TSRE.*native build OK \\(' '$T/out.txt'"
runit "$S" 70
chk "broken: rc 1, the log line starts with a timestamp and names the tvOS iOS targets" bash -c "[ $RC -eq 1 ] && grep -Eq '$TSRE.*NATIVE BUILD BROKEN: tvOS iOS \\(HEAD ' '$T/out.txt'"
chk "broken: the first error line (CoreSimulator is out of date) is in the log line" grep -q "first error: CoreSimulator is out of date" "$T/out.txt"
echo "== mutants"
python3 - "$S" "$T/m1.sh" "$T/m2.sh" <<'PY'
import sys
s = open(sys.argv[1]).read()
a = "say(){ echo \"$(ts) $*\"; }"; assert s.count(a) == 1
open(sys.argv[2], "w").write(s.replace(a, "say(){ echo \"$*\"; }"))
b = '${cause:+ first error: $cause}'; assert s.count(b) == 1
open(sys.argv[3], "w").write(s.replace(b, ''))
PY
runit "$T/m1.sh" 70
chk "M1 (no timestamp) is caught: the line does not start with a timestamp" bash -c "! grep -Eq '$TSRE' '$T/out.txt'"
runit "$T/m2.sh" 70
chk "M2 (no cause) is caught: no 'first error' text" bash -c "! grep -q 'first error' '$T/out.txt'"
echo; echo "z4 native build check: $((n-fails))/$n passed"; [ "$fails" = 0 ]
