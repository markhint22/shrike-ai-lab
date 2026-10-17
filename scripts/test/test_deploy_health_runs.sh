#!/usr/bin/env bash
# deploy_health.sh must actually RUN (not just pass bash -n): a quoted phrase inside a comment in the multi-line SURFACES
# string once closed the string early -> 'SURFACES: unbound variable', the check silently did nothing for hours.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d) || exit 1; trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "ok - $1"; }; bad(){ echo "FAIL - $1"; fail=1; }
# Hermetic curl stub. deploy_health.sh PREPENDS /opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin to PATH, so a stub dir on PATH is
# shadowed by the real curl (which then hits the live URLs: 000 in a network-less sandbox -> "8 currently failing", and
# a real-network dependency anywhere else). An exported shell function beats any PATH lookup and survives the script's
# own PATH rewrite and the $(code ...) subshells.
curl(){ printf '%s' "$STUB_CODE"; }
export -f curl
out=$(STUB_CODE=200 DRYRUN=1 bash deploy_health.sh 2>&1)
echo "$out" | grep -q "unbound variable" && bad "unbound variable" || ok "no unbound variable / stray command errors"
echo "$out" | grep -qE "No such file or directory|command not found" && bad "shell errors in output" || ok "no shell errors"
n=$(echo "$out" | grep -oE "[0-9]+ surfaces checked" | grep -oE "^[0-9]+")
[ "${n:-0}" -ge 8 ] && ok "all surfaces checked ($n)" || bad "only ${n:-0} surfaces checked"
echo "$out" | grep -q "0 currently failing" && ok "stubbed-200 -> 0 failing" || bad "failing count wrong"
# negative control: proves the stub (not the real network) drives the result
out5=$(STUB_CODE=503 DRYRUN=1 bash deploy_health.sh 2>&1)
echo "$out5" | grep -q "8 surfaces checked, 8 currently failing" && ok "stubbed-503 -> 8 failing (stub is what answers)" || bad "stub not in effect (503 control)"
exit $fail
