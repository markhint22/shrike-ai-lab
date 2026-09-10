#!/usr/bin/env bash
# For each web dir: inject a guaranteed type error into src/, then try candidate type-check
# commands and report (error-count, does-it-see-the-probe). Finds the command that ACTUALLY
# type-checks the source (including new files) for these Vue+Vite+references projects.
set -uo pipefail
cd "$HOME/overnight-queue"
probe() {
  local dir="$1"; [ -d "$dir" ] || { echo "MISSING $dir"; return; }
  echo "========================= $dir ========================="
  ( cd "$dir"
    local sd="src"; [ -d "$sd" ] || sd="."
    printf 'export const __PROBE_BAD: number = "not a number at all";\n' > "$sd/__gate_probe.ts"
    for cmd in \
      "npx --no-install vue-tsc --noEmit" \
      "npx --no-install vue-tsc --noEmit -p tsconfig.json" \
      "npx --no-install vue-tsc -b --force" ; do
      out="$( timeout 150 $cmd 2>&1 )"
      cnt="$(echo "$out" | grep -cE 'error TS[0-9]')"
      seen="no"; echo "$out" | grep -q "__gate_probe" && seen="YES-sees-probe"
      printf "  %-45s errs=%-3s %s\n" "$cmd" "$cnt" "$seen"
    done
    rm -f "$sd/__gate_probe.ts"
  )
}
probe repos/iptv_apps/iptv-web
probe repos/billwatch/billwatch-web
probe repos/gitlark/web
