#!/usr/bin/env bash
# 2026-10-21 (package P2c): rc_lifecycle_e2e.secret() discarded railway_serial.sh's returncode/stderr, so a transient Railway CLI failure was reported as
# "REVENUECAT_WEBHOOK_SECRET is not set" (10-21 02:15). Now: rc!=0 -> retry once -> distinct "Railway CLI failed: rc=N <stderr first line>" error.
# Stub railway_serial.sh via RC_RAILWAY_SERIAL; sandbox from lib_safe_tmp.sh; no network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || exit 1
PY="${QA_TEST_PYTHON:-$(command -v python3.12 || command -v python3)}"
[ -n "$PY" ] || { echo "  SKIP: no python3"; exit 0; }
SRC="$HERE/../../../qa/rc_lifecycle_e2e.py"; [ -f "$SRC" ] || SRC="$HERE/../../qa/rc_lifecycle_e2e.py"
[ -f "$SRC" ] || { echo "  SKIP: rc_lifecycle_e2e.py not found"; exit 0; }
T="$(safe_mktemp_dir)" || exit 1
safe_set_sandbox_home "$T" || exit 1
mkdir -p "$HOME/.qa_railway_cwd/iptv_apps-staging"
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
mkstub(){ # <name> <fails-before-success> <ok-body>
  printf '#!/bin/sh\nc="%s/%s.count"; n=$(cat "$c" 2>/dev/null || echo 0); n=$((n+1)); echo $n > "$c"\nif [ "$n" -le %s ]; then echo "boom: connection reset" >&2; echo "second line" >&2; exit 7; fi\n%s\n' "$T" "$1" "$2" "$3" > "$T/$1.sh"
  chmod +x "$T/$1.sh"
}
mkstub once 1 'echo "OTHER=1"; echo "REVENUECAT_WEBHOOK_SECRET=s3cr3t"'
mkstub twice 99 'echo unreachable'
mkstub unset 0 'echo "OTHER=1"'
call(){ RC_RAILWAY_SERIAL="$T/$1.sh" RC_RAILWAY_RETRY_S=0 "$PY" -I - "$SRC" <<'PYEOF'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rc", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
try:
    print("VALUE:" + m.secret())
except m.SecretUnavailable as e:
    print("ERR:" + str(e))
PYEOF
}
o="$(call once)"; ok "C1: fails once then succeeds -> value (retry)" "$([ "$o" = "VALUE:s3cr3t" ] && echo 1 || echo 0)"; ok "C1b: exactly 2 attempts" "$([ "$(cat "$T/once.count")" = 2 ] && echo 1 || echo 0)"
o="$(call twice)"; echo "  twice -> $o"
ok "C2: fails twice -> distinct 'Railway CLI failed: rc=7 boom...' error" "$(case "$o" in 'ERR:Railway CLI failed: rc=7 boom: connection reset'*) echo 1;; *) echo 0;; esac)"
ok "C3: the CLI-failure message never says 'not set'" "$(case "$o" in *'not set'*) echo 0;; *) echo 1;; esac)"
ok "C4: exactly 2 attempts (one retry, no loop)" "$([ "$(cat "$T/twice.count")" = 2 ] && echo 1 || echo 0)"
o="$(call unset)"; ok "C5: CLI ok but variable absent -> still the 'is not set' error" "$(case "$o" in 'ERR:REVENUECAT_WEBHOOK_SECRET is not set'*) echo 1;; *) echo 0;; esac)"
ok "C6: CLI ok and absent -> no retry (1 attempt)" "$([ "$(cat "$T/unset.count")" = 1 ] && echo 1 || echo 0)"
safe_rm_rf "$T" || F=$((F+1))
echo "test_rc_secret_cli_failure: $P passed, $F failed"; [ "$F" = 0 ]
