#!/usr/bin/env bash
# Re-seed tsc baselines using each repo's CANONICAL type-check command.
set -uo pipefail
cd "$HOME/overnight-queue"
rm -f state/tsc_baseline/*.count
mkdir -p state/tsc_baseline
seed(){
  local repo="$1" wd="$2" dir="repos/$1/$2"; local slug="${wd//\//__}"
  [ -d "$dir" ] || { echo "  $repo/$wd: missing"; return; }
  local cmd="npx --no-install vue-tsc --noEmit"
  grep -q '"type-check"' "$dir/package.json" 2>/dev/null && cmd="npm run --silent type-check"
  local cnt
  cnt="$( cd "$dir" && timeout 180 $cmd 2>&1 | grep -cE 'error TS[0-9]' )"
  echo "$cnt" > "state/tsc_baseline/${repo}__${slug}.count"
  echo "  ${repo}__${slug}.count = $cnt   (via: $cmd)"
}
seed iptv_apps iptv-web
seed billwatch billwatch-web
seed gitlark web
