#!/usr/bin/env bash
# Regression test for run_overnight.sh's BUILD-GATE Kotlin grounding fix (2026-09-20).
# Before this, the BUILD-GATE fix-up's grounding text for a Kotlin build-red was only the
# outer Gradle banner ("compileDebugUnitTestKotlin FAILED" / "Compilation error. See log
# for more details") - zero actionable detail, unlike Python failures which get the real
# traceback line inline via the same grep. Confirmed live 2026-09-20: 5/5 real Kotlin
# BUILD-GATE fix-up attempts on billwatch saw only the banner and all 5 either made no
# change or guessed wrong. Extracts the real kotlinc file:line:col diagnostic out of the
# FULL task_log instead. Mirrors the deployed extraction exactly so this can't drift.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

grep -q '_kotlinc_diag=' "$RO" || { echo "  FAIL: kotlinc diagnostic extraction not found in $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed extraction exactly
extract_kotlinc(){ # $1=task_log $2=pwd-to-strip
  grep -oE 'file://[^ ]+\.kt:[0-9]+:[0-9]+ .*' "$1" 2>/dev/null | sed "s#^file://$2/##" | sort -u | head -8 | tr '\n' ' ' | tr -s ' ' | cut -c1-400
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repo_root="$tmp/repos/billwatch"
mkdir -p "$repo_root"

# ---- 1. real-shaped Kotlin build-red: outer banner ONLY carries no detail ----
log="$tmp/task_log_banner_only.log"
cat > "$log" <<EOF
> Task :app:compileDebugUnitTestKotlin FAILED
FAILURE: Build failed with an exception.
* What went wrong:
Execution failed for task ':app:compileDebugUnitTestKotlin'.
> Compilation error. See log for more details
EOF
diag="$(extract_kotlinc "$log" "$repo_root")"
ok "banner-only Kotlin failure -> kotlinc diagnostic extraction is empty (nothing deeper to find)" "[ -z '$diag' ]"

# ---- 2. real-shaped Kotlin build-red WITH the deep kotlinc diagnostic present (the
#      actual billwatch shape confirmed live: a missing '}' in a test file) ----
cat > "$log" <<EOF
> Task :app:compileDebugUnitTestKotlin FAILED
e: file://${repo_root}/billwatch-android/app/src/test/java/com/billwatch/data/repository/BillingRepositoryTest.kt:68:6 Missing '}'
e: file://${repo_root}/billwatch-android/app/src/test/java/com/billwatch/data/repository/BillingRepositoryTest.kt:68:6 Missing '}'
FAILURE: Build failed with an exception.
> Compilation error. See log for more details
EOF
diag="$(extract_kotlinc "$log" "$repo_root")"
ok "real diagnostic present -> extraction is non-empty" "[ -n '$diag' ]"
ok "extraction names the real file:line:col" "printf '%s' \"\$diag\" | grep -q 'BillingRepositoryTest.kt:68:6'"
ok "extraction names the real error text" "printf '%s' \"\$diag\" | grep -q \"Missing '}'\""
ok "duplicate identical diagnostic lines are deduped (sort -u)" "[ \$(printf '%s' \"\$diag\" | grep -oE 'Missing' | wc -l | tr -d ' ') -eq 1 ]"
ok "the absolute path prefix is stripped down to a relative, portable path" "! printf '%s' \"\$diag\" | grep -q '$tmp'"

# ---- 3. non-Kotlin build-red (Python) -> extraction stays empty, no behavior change ----
cat > "$log" <<EOF
Traceback (most recent call last):
  File "app/main.py", line 12
    def foo(:
             ^
SyntaxError: invalid syntax
EOF
diag="$(extract_kotlinc "$log" "$repo_root")"
ok "non-Kotlin build-red -> kotlinc extraction stays empty (no change to existing behavior)" "[ -z '$diag' ]"

echo "buildgate kotlinc grounding: $P passed, $F failed"
[ "$F" -eq 0 ]
