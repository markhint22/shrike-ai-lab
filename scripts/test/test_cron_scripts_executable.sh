#!/usr/bin/env bash
# 2026-10-16: gpu_autoswap.sh and three other cron-invoked scripts were mode 644 in git, so cron's `./script` failed with "Permission denied" for days on the rebuilt box.
# Every script that scripts/cron.txt / ops/cron.proposed.txt invokes directly (./x.sh, scripts/x.sh) must be tracked executable.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; Q="$HERE/../.."
P=0; F=0
ok(){ if [ "$2" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
found=0
for cf in "$Q/scripts/cron.txt" "$Q/ops/cron.proposed.txt" "$Q/ops/crontab.box.snapshot.txt"; do
  [ -f "$cf" ] || continue
  while IFS= read -r f; do
    [ -f "$Q/$f" ] || continue
    found=$((found+1))
    if [ -x "$Q/$f" ]; then ok "executable: $f" 0; else ok "executable: $f" 1; fi
  done < <(grep -v '^[[:space:]]*#' "$cf" | sed -E 's#(^|[ ;&(])([^ ]*/)?(python[0-9.]*|bash|sh) +[^ ]+# #g' | grep -oE '(\./|scripts/|ops/)?[A-Za-z0-9_./-]+\.(sh|py)' | sed -E 's#^\./##; s#^(/home/[^/]+|~|\$HOME)/overnight-queue/##' | sort -u)
done
[ "$found" -gt 0 ]; ok "found cron-invoked scripts to check ($found)" $?
echo "cron_scripts_executable: $P passed, $F failed"
[ "$F" -eq 0 ]
