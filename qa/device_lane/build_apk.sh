#!/usr/bin/env bash
# build_apk.sh - build the Chickadee Android debug APK (and extract the e2e suite) for ONE ref, in a scratch copy.
#   build_apk.sh --repo-dir DIR --ref REF --api-base URL --out DIR [--build-timeout S]
# Never touches the live clone: sources come from `git archive` (read-only), the build happens in a /tmp copy that is deleted
# afterwards. The APK is cached by <sha>+<api-base>, so an unchanged develop head is built once.
# Prints (last stdout line, JSON): {"ok":true,"sha":..,"apk":path,"e2e_dir":path,"cached":bool,"build_seconds":n}
# Exit: 0 ok, 3 repo/ref problem, 4 build failed or timed out (caller maps both to UNVERIFIED).
set -u
SELF="${BASH_SOURCE[0]}"; case "$SELF" in /*) ;; *) SELF="$PWD/$SELF" ;; esac
HERE="$(cd "$(dirname "$SELF")" && pwd)"
. "$HERE/lane_env.sh"

REPO_DIR=""; REF="origin/develop"; API_BASE=""; OUT=""; BTO="${DL_BUILD_TIMEOUT:-1800}"
while [ $# -gt 0 ]; do case "$1" in
  --repo-dir) REPO_DIR="$2"; shift 2 ;; --ref) REF="$2"; shift 2 ;; --api-base) API_BASE="$2"; shift 2 ;;
  --out) OUT="$2"; shift 2 ;; --build-timeout) BTO="$2"; shift 2 ;; *) echo "bad arg $1" >&2; exit 2 ;; esac; done
[ -n "$REPO_DIR" ] && [ -n "$OUT" ] && [ -n "$API_BASE" ] || { echo "usage: $0 --repo-dir D --ref R --api-base U --out D" >&2; exit 2; }
fail() { printf '{"ok":false,"error":"%s"}\n' "$1"; exit "${2:-4}"; }

SHA="$(git -C "$REPO_DIR" rev-parse --verify -q "$REF^{commit}")" || fail "ref $REF not found in repo" 3
mkdir -p "$OUT/apk" "$OUT/e2e" || fail "cannot create out dir" 3
KEY="${SHA:0:12}-$(printf '%s' "$API_BASE" | cksum | cut -d' ' -f1)"
APK="$OUT/apk/chickadee-$KEY.apk"
E2E="$OUT/e2e/$KEY"
SCRATCH="$(mktemp -d /tmp/qa-dl-build.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

# --- e2e suite (always re-extracted: tiny) -------------------------------------------------------------------------------
rm -rf "$E2E"; mkdir -p "$E2E"
git -C "$REPO_DIR" archive "$SHA" iptv-android/e2e | tar -x -C "$SCRATCH" || fail "git archive e2e failed" 3
cp -R "$SCRATCH/iptv-android/e2e/." "$E2E/"
# Staging-account support WITHOUT editing the repo: the suite hardcodes the PROD test accounts as literals in ~15 specs.
# prep_e2e.py rewrites them to env lookups on THIS scratch copy only (see its docstring).
"$(dl_py)" "$HERE/prep_e2e.py" "$E2E" >"$E2E/.qa_prep.json" 2>/dev/null || fail "prep_e2e failed" 4
if [ -f "$E2E/package-lock.json" ]; then
  (cd "$E2E" && dl_timeout_fwd 300 npm ci --no-audit --no-fund --prefer-offline >"$SCRATCH/npm.log" 2>&1) || { tail -3 "$SCRATCH/npm.log" >&2; fail "npm ci failed for e2e" 4; }
fi

# --- APK ------------------------------------------------------------------------------------------------------------------
if [ -s "$APK" ]; then
  printf '{"ok":true,"sha":"%s","apk":"%s","e2e_dir":"%s","cached":true,"build_seconds":0}\n' "$SHA" "$APK" "$E2E"; exit 0
fi
git -C "$REPO_DIR" archive "$SHA" iptv-android | tar -x -C "$SCRATCH" || fail "git archive android failed" 3
SRC="$SCRATCH/iptv-android"
[ -f "$SRC/app/build.gradle.kts" ] || fail "no iptv-android/app/build.gradle.kts at $REF" 3
# Point the debug build at the requested backend (both build types hardcode the prod URL).
sed -i.bak -E "s#\\\\\"https://api\\.chickadeestream\\.com\\\\\"#\\\\\"${API_BASE}\\\\\"#g" "$SRC/app/build.gradle.kts"
grep -q "$API_BASE" "$SRC/app/build.gradle.kts" || fail "could not patch API_BASE_URL (build.gradle.kts layout changed?)" 4
chmod +x "$SRC/gradlew"
t0=$(date +%s)
# --no-daemon: leaves no gradle daemon behind. KEYSTORE_PASSWORD unset: debug build must not try release signing.
( cd "$SRC" && dl_timeout_fwd "$BTO" env -u KEYSTORE_PASSWORD GRADLE_OPTS="-Xmx3g" nice -n 10 ./gradlew --no-daemon --console=plain \
    -Dorg.gradle.jvmargs=-Xmx3g :app:assembleGoogleTvDebug -x lint >"$SCRATCH/gradle.log" 2>&1 ) || {
  tail -12 "$SCRATCH/gradle.log" | sed -E 's/(pass(word)?|token|secret)[=: ]+[^ ]+/\1=<redacted>/Ig' >&2; fail "gradle build failed or timed out" 4; }
BUILT="$(find "$SRC/app/build/outputs/apk/googleTv/debug" -name '*.apk' 2>/dev/null | head -1)"
[ -n "$BUILT" ] || fail "gradle succeeded but no debug apk found" 4
cp "$BUILT" "$APK"
printf '{"ok":true,"sha":"%s","apk":"%s","e2e_dir":"%s","cached":false,"build_seconds":%d}\n' "$SHA" "$APK" "$E2E" "$(( $(date +%s) - t0 ))"
