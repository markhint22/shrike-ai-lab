#!/usr/bin/env bash
# Regression test for scripts/ovn_gradle_flavor_guard.sh (2026-09-20) — an earlier audit
# found Android test items get VERIFY commands using the ambiguous Gradle task
# ":app:testDebugUnitTest", which fails with "Task '...' is ambiguous in project ':app'"
# once product flavors exist (iptv_apps/iptv-android/app: googleTv + fireTv). Confirmed
# billwatch-android has NO product flavors declared, so it is NOT affected. This guard is
# shared by ovn_planner.sh and ovn_recover_parked.sh (both LLM-decompose items with a
# freeform VERIFY command) - tests the real script directly against real repo layouts.
set -uo pipefail
GUARD="${OVN_GRADLE_FLAVOR_GUARD:-$HOME/overnight-queue/scripts/ovn_gradle_flavor_guard.sh}"
[ -f "$GUARD" ] || { echo "  SKIP: $GUARD not found on this host"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# ---- 1. repo WITH product flavors -> ambiguous task rewritten to the umbrella task ----
flavored="$tmp/flavored_repo"
mkdir -p "$flavored/app"
cat > "$flavored/app/build.gradle.kts" <<'EOF'
android {
    productFlavors {
        create("googleTv") { dimension = "tv" }
        create("fireTv") { dimension = "tv" }
    }
}
EOF
line='- [ ] [T2] app/src/test/foo/BarTest.kt — add test VERIFY: `./gradlew :app:testDebugUnitTest --tests "com.x.BarTest"` passes. (cat:android; multifile:no)'
out="$(printf '%s\n' "$line" | bash "$GUARD" "$flavored" 2>/tmp/_guard_stderr.$$)"
stderr_out="$(cat "/tmp/_guard_stderr.$$" 2>/dev/null)"; rm -f "/tmp/_guard_stderr.$$"
ok "flavored repo: ambiguous task rewritten to the umbrella :app:test" 'printf "%s" "$out" | grep -qE ":app:test( |\`)"'
ok "flavored repo: ambiguous task no longer present" '! printf "%s" "$out" | grep -q "testDebugUnitTest"'
ok "flavored repo: rest of the item line is unchanged" 'printf "%s" "$out" | grep -q "add test VERIFY"'
ok "flavored repo: emits a stderr note that a rewrite happened" '[ -n "$stderr_out" ]'

# ---- 2. repo WITHOUT product flavors (the billwatch shape) -> line passes through untouched ----
unflavored="$tmp/unflavored_repo"
mkdir -p "$unflavored/app"
cat > "$unflavored/app/build.gradle.kts" <<'EOF'
android {
    defaultConfig { applicationId = "com.billwatch.app" }
}
EOF
out2="$(printf '%s\n' "$line" | bash "$GUARD" "$unflavored" 2>/dev/null)"
ok "unflavored repo: line passes through completely unchanged" '[ "$out2" = "$line" ]'
ok "unflavored repo: ambiguous task is still present (no flavors, no ambiguity, no rewrite needed)" 'printf "%s" "$out2" | grep -q "testDebugUnitTest"'

# ---- 3. non-Android item -> passes through untouched regardless ----
py_line='- [ ] [T2] app/service.py — add a helper VERIFY: `pytest tests/test_service.py` passes. (cat:python; multifile:no)'
out3="$(printf '%s\n' "$py_line" | bash "$GUARD" "$flavored" 2>/dev/null)"
ok "non-Android item in a flavored repo -> untouched (no gradle task to rewrite)" '[ "$out3" = "$py_line" ]'

echo "gradle flavor guard: $P passed, $F failed"
[ "$F" -eq 0 ]
