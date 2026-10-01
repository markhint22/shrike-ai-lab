#!/usr/bin/env bash
# deploy_health.sh must actually RUN (not just pass bash -n): a quoted phrase inside a comment in the multi-line SURFACES
# string once closed the string early -> 'SURFACES: unbound variable', the check silently did nothing for hours.
cd "$(dirname "$0")/../.." || exit 1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; ok(){ echo "ok - $1"; }; bad(){ echo "FAIL - $1"; fail=1; }
mkdir -p "$T/bin"; printf '#!/usr/bin/env bash\nprintf 200\n' > "$T/bin/curl"; chmod +x "$T/bin/curl"
out=$(PATH="$T/bin:$PATH" DRYRUN=1 bash deploy_health.sh 2>&1)
echo "$out" | grep -q "unbound variable" && bad "unbound variable" || ok "no unbound variable / stray command errors"
echo "$out" | grep -qE "No such file or directory|command not found" && bad "shell errors in output" || ok "no shell errors"
n=$(echo "$out" | grep -oE "[0-9]+ surfaces checked" | grep -oE "^[0-9]+")
[ "${n:-0}" -ge 8 ] && ok "all surfaces checked ($n)" || bad "only ${n:-0} surfaces checked"
echo "$out" | grep -q "0 currently failing" && ok "stubbed-200 -> 0 failing" || bad "failing count wrong"
exit $fail
