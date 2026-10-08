#!/usr/bin/env bash
# Wave-3: run the REAL ovn_credit_already_satisfied.sh (not an extracted copy of _resolve_tool_paths) so the tool-path
# self-healing is attributed to the script: `cd <dir> &&` prefix search root, venv pytest substitution, and the
# ./gradlew rebuild ("cd <real gradle dir> && ./gradlew <args>"). Fake venv pytest / gradlew write marker files.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../ovn_credit_already_satisfied.sh"; [ -f "$SCRIPT" ] || SCRIPT="$HERE/../../scripts/ovn_credit_already_satisfied.sh"
[ -f "$SCRIPT" ] || { echo "  SKIP: script not found"; exit 0; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1
mkdir -p backend/.venv/bin android/app backend/tests
cat > backend/.venv/bin/pytest <<EOF2
#!/usr/bin/env bash
echo "pytest-called \$PWD \$*" >> "$tmp/markers"; exit 0
EOF2
chmod +x backend/.venv/bin/pytest
cat > android/gradlew <<EOF2
#!/usr/bin/env bash
echo "gradlew-called \$PWD \$*" >> "$tmp/markers"; exit 0
EOF2
chmod +x android/gradlew
echo "x=1" > backend/tests/test_alpha.py; echo "x=1" > android/app/Beta.kt; echo "x=1" > backend/tests/test_gamma.py
cat > OVERNIGHT_PROGRESS.md <<'EOF2'
# progress
- [ ] [T1] backend/tests/test_alpha.py — alpha. VERIFY: `cd backend && pytest tests/test_alpha.py -q`. (cat:python)
- [ ] [T1] android/app/Beta.kt — beta. VERIFY: `./gradlew :app:testDebugUnitTest --tests Beta`. (cat:kotlin)
- [ ] [T1] backend/tests/test_gamma.py — gamma. VERIFY: `pytest backend/tests/test_gamma.py`. (cat:python)
EOF2
cat > task.log <<'EOF2'
Checking test_alpha.py — already present, no changes needed.
Checking Beta.kt — already present, no changes needed.
Checking test_gamma.py — already present, no changes needed.
EOF2
SL="$tmp/state/shadow.log"
out="$(OVN_VERIFY_SHADOW_LOG="$SL" OVN_VERIFY_GATE_MODE=shadow OVN_PATH_GATE=off bash "$SCRIPT" task.log OVERNIGHT_PROGRESS.md 2>&1)"
ok "all three items credited" "echo \"$out\" | grep -q 'CREDITED=3'"
ok "cd-prefixed pytest resolved to the real venv pytest and run from backend/ context" "grep -q 'pytest-called .*tests/test_alpha.py' '$tmp/markers'"
ok "shadow log records the absolute venv pytest path for the cd-prefixed command" "grep 'line=2 ' '$SL' | grep -q 'result=PASS' && grep 'line=2 ' '$SL' | grep -q '$tmp/backend/.venv/bin/pytest'"
ok "bare pytest (no cd prefix) also resolved to the venv pytest" "grep 'line=4 ' '$SL' | grep -q '$tmp/backend/.venv/bin/pytest backend/tests/test_gamma.py'"
ok "gradlew clause is rebuilt as 'cd <android dir> && ./gradlew <args>'" "grep 'line=3 ' '$SL' | grep -q \"cmd=cd $tmp/android && ./gradlew :app:testDebugUnitTest --tests Beta\""
ok "gradlew really ran with the gradle project dir as PWD" "grep -q 'gradlew-called $tmp/android :app:testDebugUnitTest' '$tmp/markers'"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
