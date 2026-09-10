#!/usr/bin/env bash
# ovn_tsc_gate.sh — TypeScript type-error RATCHET for the overnight gate (2026-09-04).
#
# WHY: the fleet's post-commit build-gate already reverts on "error TS[0-9]", but nothing
# ran a type-check, so type breakage was invisible — the 27B wrote type-broken TS with zero
# feedback. This runs each web app's OWN canonical type-check (the command its build uses:
# `npm run type-check` if defined, else `vue-tsc --noEmit`, else `tsc --noEmit` — critical
# because these are Vue projects where raw `tsc` mis-resolves project references and .vue
# files) and enforces a RATCHET: a repo starts at its current error count (baseline), and a
# commit is only reverted if it RAISES the count above baseline. When the fleet FIXES errors
# the baseline ratchets DOWN. Pre-existing errors never cause a revert; net-new ones do.
#
# Prints "TSC-RATCHET-REGRESSION" (the caller greps this to trigger the revert) with an
# excerpt on a regression; SEED/OK/IMPROVED otherwise. Exit mirrors that but the caller keys
# off the printed marker.
#
# Usage: ovn_tsc_gate.sh <repo_root> <baseline_dir> <repo_name> <before_sha> <after_sha>
set -uo pipefail
root="${1:-.}"; baseline_dir="${2:?baseline_dir}"; repo="${3:?repo}"
before="${4:-}"; after="${5:-HEAD}"
mkdir -p "$baseline_dir"
cd "$root" 2>/dev/null || { echo "TSC-RATCHET-SKIP (bad root)"; exit 0; }

# What TS/Vue files did THIS commit touch? (skip entirely if none — keeps non-web cycles free)
changed="$(git diff --name-only "${before:-$after~1}" "$after" 2>/dev/null | grep -E '\.(ts|tsx|vue)$' || true)"
[ -z "$changed" ] && { echo "TSC-RATCHET-SKIP (no TS/Vue files touched)"; exit 0; }

# Echo the type-check command for the CWD web dir (or empty if unavailable). Prefer
# `vue-tsc --noEmit` directly over the repo's npm "type-check" script, because some repos'
# scripts are broken (e.g. gitlark points -p at a nonexistent tsconfig.app.json → TS5058).
# The ratchet is safe even where a command is vacuous (count never exceeds baseline → no
# false revert); it only actively protects repos whose config actually type-checks src.
tc_cmd() {
  if [ -x node_modules/.bin/vue-tsc ]; then
    echo "npx --no-install vue-tsc --noEmit"
  elif [ -f package.json ] && grep -q '"type-check"' package.json; then
    echo "npm run --silent type-check"
  elif [ -x node_modules/.bin/tsc ] || [ -d node_modules/typescript ]; then
    echo "npx --no-install tsc --noEmit"
  else echo ""; fi
}

rc_overall=0
# A repo can hold >1 web app; check each tsconfig dir that owns a changed file.
while IFS= read -r tsconfig; do
  wd="$(dirname "$tsconfig")"
  echo "$changed" | grep -qE "^${wd#./}/" || [ "$wd" = "." ] || continue
  ( cd "$wd" || exit 0
    cmd="$(tc_cmd)"
    [ -z "$cmd" ] && { echo "TSC-RATCHET-SKIP ($wd: no type-checker installed)"; exit 0; }
    slug="${wd#./}"; slug="${slug//\//__}"; [ -z "$slug" ] && slug="root"
    bf="$baseline_dir/${repo}__${slug}.count"
    out="$( timeout 180 $cmd 2>&1 )"
    cnt="$(echo "$out" | grep -cE 'error TS[0-9]')"
    base="$(cat "$bf" 2>/dev/null || echo -1)"
    if [ "$base" -lt 0 ]; then
      echo "$cnt" > "$bf"; echo "TSC-RATCHET-SEED $repo/$wd: baseline=$cnt (via: $cmd)"
    elif [ "$cnt" -gt "$base" ]; then
      echo "TSC-RATCHET-REGRESSION $repo/$wd: type errors $base -> $cnt (this commit added $((cnt-base)); via: $cmd)."
      echo "$out" | grep -E 'error TS[0-9]' | head -12
      exit 1
    elif [ "$cnt" -lt "$base" ]; then
      echo "$cnt" > "$bf"; echo "TSC-RATCHET-IMPROVED $repo/$wd: type errors $base -> $cnt (baseline ratcheted down)."
    else
      echo "TSC-RATCHET-OK $repo/$wd: type errors held at $cnt."
    fi
  ) || rc_overall=1
done < <(find . -maxdepth 3 -name tsconfig.json -not -path '*/node_modules/*' 2>/dev/null)

exit "$rc_overall"
