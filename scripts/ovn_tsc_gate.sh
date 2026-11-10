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
# run_overnight.sh passes the repo PATH ("$repo" = /home/.../repos/iptv_apps), not a name: used as-is it made the baseline file
# "$baseline_dir//home/.../iptv_apps__iptv-web.count" (nonexistent dir), so the ratchet never seeded and never gated anything
# ("No such file or directory" in every iptv cycle log). Key the baseline on the repo's base name.
repo="$(basename "$repo")"
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

# 2026-11-06 (Y3 review fix 1): premeasure's private git-archive copies (1-2k files each) used to be removed only on normal return, so a
# SIGTERM/timeout kill of the gate during the (up to 180s) parent type-check leaked them (box /tmp is tmpfs; past inode exhaustion). The per-tsconfig
# work runs in subshells that a signal to this process does NOT reach, so ONE scratch root is created here, every archive lives under it, and
# EXIT/INT/TERM remove it (lib_safe_tmp safe_rm_rf, fail-closed: with the lib absent the dir is left and named on stderr) after stopping the subshells.
PRE_ROOT=""
_stl="${OVN_SAFE_TMP_LIB:-}"
[ -f "$_stl" ] || _stl="$(dirname "${BASH_SOURCE[0]:-$0}")/test/lib_safe_tmp.sh"
[ -f "$_stl" ] || _stl="$(dirname "$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null || echo "${BASH_SOURCE[0]:-$0}")")/test/lib_safe_tmp.sh"
[ -f "$_stl" ] && . "$_stl" 2>/dev/null
pre_rm() {  # pre_rm <dir>: remove one ovn_tsc_pre.* path
  local d="$1"
  case "$d" in /*/ovn_tsc_pre.*) ;; *) return 0;; esac
  case "$d" in *..*) return 0;; esac
  # fail-closed (project rule: no raw rm -r): without lib_safe_tmp the dir is left and named, never removed by a raw rm
  if declare -F safe_rm_rf >/dev/null 2>&1; then safe_rm_rf "$d" >/dev/null 2>&1 || true
  else echo "ovn_tsc_gate: lib_safe_tmp.sh not found, leaving $d (set OVN_SAFE_TMP_LIB)" >&2; fi
}
pre_cleanup() { [ -n "$PRE_ROOT" ] && pre_rm "$PRE_ROOT"; PRE_ROOT=""; }
trap pre_cleanup EXIT
# No explicit INT/TERM traps: bash defers a trap until the foreground child (timeout subshell) returns, delaying shutdown by up to minutes.
# Without them a signal kills the shell at once and the EXIT trap above still runs pre_cleanup.
if [ "${OVN_TSC_PREMEASURE:-1}" != 0 ]; then
  PRE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/ovn_tsc_pre.XXXXXX" 2>/dev/null)" || PRE_ROOT=""
  case "$PRE_ROOT" in /*/ovn_tsc_pre.*) ;; *) PRE_ROOT="";; esac
fi

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
    # 2026-11-10 (Z8b-D): AUTOFIX unused imports before the ratchet judges the count. One new `vi` import (TS6133) reverted 8+ billwatch cycles against a 76-error baseline. ON by default (a pure
    # fix: it can only remove bindings tsc itself reported unused, only in files THIS commit touched, only imports this commit added; scripts/ovn_ts_unused_imports.py). OVN_TSC_UNUSED_FIX=shadow
    # logs TSC-UNUSED-IMPORTS-WOULD-FIX and edits nothing, =off restores the old behaviour. The fix is its own small commit on top (the caller refreshes AFTER_SHA from HEAD).
    ufx="${OVN_TSC_UNUSED_FIX:-on}"
    if [ "$ufx" != off ] && grep -qE 'error TS(6133|6196|6192)' <<< "$out"; then
      fixer="$(dirname "${BASH_SOURCE[0]:-$0}")/ovn_ts_unused_imports.py"
      top="$(git rev-parse --show-toplevel 2>/dev/null)"
      if [ -f "$fixer" ] && [ -n "$top" ] && command -v python3 >/dev/null 2>&1 && [ "$(git rev-parse HEAD 2>/dev/null)" = "$(git rev-parse "$after" 2>/dev/null)" ]; then
        fxargs=(--cwd "$PWD" --toplevel "$top" --before "${before:-$after~1}" --after "$after")
        [ "$ufx" = on ] || fxargs+=(--dry-run)
        fxout="$(timeout 60 python3 "$fixer" "${fxargs[@]}" <<< "$out" 2>/dev/null)"
        fxtot="$(printf '%s\n' "$fxout" | sed -n 's/^TOTAL \([0-9]*\).*/\1/p' | tail -1)"
        fxfiles="$(printf '%s\n' "$fxout" | sed -n 's/^TOTAL [0-9]* \(.*\)$/\1/p' | tail -1)"
        if [ "${fxtot:-0}" -gt 0 ] 2>/dev/null; then
          if [ "$ufx" != on ]; then
            echo "TSC-UNUSED-IMPORTS-WOULD-FIX $repo/$wd: $fxtot unused import(s) in $fxfiles (OVN_TSC_UNUSED_FIX=$ufx: nothing edited)"
            echo "$(date -u +%FT%TZ) $repo/$wd $after would-fix $fxtot $fxfiles" >> "$baseline_dir/unused_import_fix.log" 2>/dev/null || true
          else
            if git -C "$top" add -- $fxfiles >/dev/null 2>&1 && git -C "$top" commit -q -m "fix(ts): remove unused imports flagged by tsc (TS6133/TS6192/TS6196)" -- $fxfiles >/dev/null 2>&1; then
              after="$(git rev-parse HEAD)"
              echo "TSC-UNUSED-IMPORTS-FIXED $repo/$wd: removed $fxtot unused import(s) in $fxfiles (commit ${after:0:12})"
              echo "$(date -u +%FT%TZ) $repo/$wd $after fixed $fxtot $fxfiles" >> "$baseline_dir/unused_import_fix.log" 2>/dev/null || true
              out="$( timeout 180 $cmd 2>&1 )"
            else
              git -C "$top" checkout -q HEAD -- $fxfiles >/dev/null 2>&1   # from HEAD (not the index, which already holds the staged fix)
              echo "TSC-UNUSED-IMPORTS-SKIP $repo/$wd: could not commit the unused-import fix for $fxfiles; files restored"
            fi
          fi
        fi
      fi
    fi
    # 2026-10-27 (P5): SHADOW collected-test check (OVN_TEST_COLLECTED_CHECK=shadow; default off). When this
    # commit ADDED a *.test.* file, assert vitest lists it; log would-flag only, never changes the verdict.
    if [ "${OVN_TEST_COLLECTED_CHECK:-off}" = shadow ]; then
      added="$(git diff --name-only --diff-filter=A "${before:-$after~1}" "$after" 2>/dev/null | grep -E '\.test\.[A-Za-z]+$' || true)"
      if [ -n "$added" ] && [ -x node_modules/.bin/vitest ]; then
        listed="$(timeout 120 npx --no-install vitest list --filesOnly 2>/dev/null || true)"
        while IFS= read -r tf; do
          [ -z "$tf" ] && continue
          case "$tf" in "${wd#./}"/*|"$wd"/*) ;; *) [ "$wd" = "." ] || continue;; esac
          if ! grep -qF -- "$(basename "$tf")" <<< "$listed"; then   # here-string: no pipe, so no SIGPIPE-under-pipefail false negative
            echo "TEST-COLLECTED-SHADOW would-flag $repo/$wd: added $tf is NOT listed by vitest"
            echo "$(date -u +%FT%TZ) $repo/$wd $after $tf" >> "$baseline_dir/collected_shadow.log" 2>/dev/null || true
          fi
        done <<< "$added"
      fi
    fi
    cnt="$(echo "$out" | grep -cE 'error TS[0-9]')"
    base="$(cat "$bf" 2>/dev/null || echo -1)"
    # 2026-10-27 (P5): syntax errors (TS1xxx). tsc/vue-tsc DROP all semantic errors once any syntax error
    # exists, so a syntax-broken commit looks like a huge IMPROVEMENT (billwatch 67 -> 3, baseline ratcheted
    # down, semantic checking blind afterwards). Track a sidecar syntax baseline (absent = 0): more syntax
    # errors than baseline = hard REGRESSION regardless of the total; and never ratchet down while syntax
    # errors are present. OVN_TSC_SYNTAX_HARDFAIL=0 disables (rollback switch).
    # Only PARSER codes hide semantic errors. Checker codes in the TS1xxx range (TS1117 duplicate object
    # property, TS1259, TS1192, TS1205, TS1484...) coexist with TS2xxx output, so they must NOT count
    # (billwatch UnifiedBillCard.test.ts TS1117 sits next to TS2322/TS2339). Allowlist, overridable.
    synre="error TS(${OVN_TSC_SYNTAX_CODES:-1002|1003|1005|1009|1109|1110|1128|1131|1134|1135|1136|1137|1138|1160|1161})([^0-9]|$)"
    syn="$(echo "$out" | grep -cE "$synre")"
    sbf="$bf.syn"; synbase="$(cat "$sbf" 2>/dev/null || echo 0)"
    case "$synbase" in ''|*[!0-9]*) synbase=0;; esac
    # 2026-11-04 (Y3): PRE-COMMIT RE-MEASURE. The stored baseline is a static number; when it is stale (gitlark web: 2, seeded
    # 2026-10-30 while syntax errors hid every semantic error, real count 13) EVERY commit "raised" it and was reverted
    # (15x reverted(ts-regression)). Before declaring a regression, type-check the tree at $before (git archive into a private
    # temp dir, node_modules symlinked) with the same command: a commit is only a regression if it adds errors vs its OWN
    # parent. If it does not, the stored baseline is stale: re-seed it to the measured count (TSC-RATCHET-REBASED) and keep the
    # commit. Fail-safe: any failure to measure the parent leaves the old static behaviour. OVN_TSC_PREMEASURE=0 disables.
    PRE_CNT=""; PRE_SYN=""; ARC_CNT=""; ARC_SYN=""; PRE_TRIED=""
    # (premeasure temp-dir cleanup: see the top-level PRE_ROOT trap, Y3 review fix 1)
    # measure_tree <sha>: type-check a git-archive copy of <sha> (no untracked/gitignored/generated files; node_modules symlinked) with $cmd.
    # Sets M_CNT / M_SYN; rc 1 when it could not be measured.
    measure_tree() {
      local pb="$1" top pfx pt pout
      M_CNT=""; M_SYN=""
      git rev-parse --verify -q "$pb^{commit}" >/dev/null 2>&1 || return 1
      top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
      pfx="$(git rev-parse --show-prefix 2>/dev/null)"
      [ -n "$PRE_ROOT" ] && [ -d "$PRE_ROOT" ] || return 1
      pt="$(mktemp -d "$PRE_ROOT/ovn_tsc_pre.XXXXXX" 2>/dev/null)" || return 1
      [ -n "$pt" ] && [ -d "$pt" ] || return 1
      if git -C "$top" archive "$pb" 2>/dev/null | tar -x -C "$pt" 2>/dev/null && [ -d "$pt/${pfx%/}" ]; then
        [ -e "$pt/${pfx}node_modules" ] || ln -s "$PWD/node_modules" "$pt/${pfx}node_modules" 2>/dev/null
        pout="$( cd "$pt/${pfx%/}" 2>/dev/null && timeout 180 $cmd 2>&1 )"
        M_CNT="$(echo "$pout" | grep -cE 'error TS[0-9]')"; M_SYN="$(echo "$pout" | grep -cE "$synre")"
      fi
      pre_rm "$pt"
      [ -n "$M_CNT" ]
    }
    # premeasure: measure the PARENT and the AFTER commit the SAME (archive) way and compare archive-vs-archive. 2026-11-06 (Y3 review fix 3):
    # the parent archive lacks gitignored/generated/untracked files and the hoisted root node_modules that the live tree has, so a future
    # generated .d.ts could inflate PRE_CNT and fail OPEN. Symmetry self-check: if the archived AFTER count differs from the live count by more
    # than OVN_TSC_SYM_TOL (default 2), archive measurements are not trustworthy here -> return 1 (old static baseline logic) and log it.
    premeasure() {
      [ -n "$PRE_CNT" ] && return 0
      [ -n "$PRE_TRIED" ] && return 1      # an unmeasurable tree is not retried (each try can cost 180s)
      PRE_TRIED=1
      [ "${OVN_TSC_PREMEASURE:-1}" = 0 ] && return 1
      local tol="${OVN_TSC_SYM_TOL:-2}" d
      case "$tol" in ''|*[!0-9]*) tol=2;; esac
      measure_tree "${before:-$after~1}" || return 1
      local pc="$M_CNT" ps="$M_SYN"
      measure_tree "$after" || return 1
      ARC_CNT="$M_CNT"; ARC_SYN="$M_SYN"
      d=$(( ARC_CNT > cnt ? ARC_CNT - cnt : cnt - ARC_CNT ))
      if [ "$d" -gt "$tol" ]; then
        echo "TSC-PREMEASURE-ASYMMETRIC $repo/$wd: archived after-tree has $ARC_CNT type errors but the live tree has $cnt (tolerance $tol); archive measurement untrustworthy, falling back to the static baseline."
        echo "$(date -u +%FT%TZ) $repo/$wd $after archive=$ARC_CNT live=$cnt" >> "$baseline_dir/premeasure_asym.log" 2>/dev/null || true
        return 1
      fi
      PRE_CNT="$pc"; PRE_SYN="$ps"
      return 0
    }
    # Baseline writes: re-read under flock immediately before writing (the baseline was read before a re-measure that can take minutes), write
    # via temp+mv. SAFE RULE per mode: "down"  -> store min(current, value) (never loosen a concurrent ratchet);
    # "rebase" (upward re-seed, justified only against the value this gate read, $3) -> store <value> only if the stored value is still the one
    # this gate read OR is already >= <value> (so the write can only tighten); if a concurrent gate lowered it in between, keep that lower value.
    # "seed" -> only if absent.
    write_baseline() {  # file mode value [read_value]
      local f="$1" mode="$2" v="$3" rv="${4:-}" cur t
      (
        if command -v flock >/dev/null 2>&1; then { exec 9>"$f.lock"; } 2>/dev/null && flock -w 10 9 2>/dev/null; fi
        cur="$(cat "$f" 2>/dev/null)"; case "$cur" in ''|*[!0-9]*) cur="";; esac
        case "$mode" in
          seed) [ -z "$cur" ] || exit 0;;
          down) [ -n "$cur" ] && [ "$cur" -le "$v" ] && exit 0;;
          rebase) if [ -n "$cur" ] && [ "$cur" != "$rv" ] && [ "$cur" -lt "$v" ]; then
                    echo "TSC-RATCHET-NOTE $repo/$wd: baseline changed concurrently ($rv -> $cur); not loosening to $v." >&2; exit 0; fi;;
        esac
        t="$(mktemp "$f.tmp.XXXXXX" 2>/dev/null)" || { echo "$v" > "$f"; exit 0; }
        echo "$v" > "$t" && mv -f "$t" "$f" || rm -f "$t"
      )
    }
    if [ "${OVN_TSC_SYNTAX_HARDFAIL:-1}" != 0 ] && [ "$base" -ge 0 ] && [ "$syn" -gt "$synbase" ] && premeasure && [ "$ARC_SYN" -le "$PRE_SYN" ]; then
      echo "TSC-RATCHET-REBASED $repo/$wd: syntax baseline $synbase is stale (parent tree already had $PRE_SYN, this commit has $syn); re-seeded."
      write_baseline "$sbf" rebase "$syn" "$synbase"; synbase="$syn"
    fi
    if [ "${OVN_TSC_SYNTAX_HARDFAIL:-1}" != 0 ] && [ "$base" -ge 0 ] && [ "$syn" -gt "$synbase" ]; then
      echo "TSC-RATCHET-REGRESSION $repo/$wd: SYNTAX errors $synbase -> $syn (TS1xxx; semantic errors are hidden while syntax errors exist, count $base -> $cnt is not trustworthy; baseline NOT touched; via: $cmd)."
      echo "$out" | grep -E "$synre" | head -12
      exit 1
    fi
    if [ "$base" -lt 0 ]; then
      write_baseline "$bf" seed "$cnt"; [ "$syn" -gt 0 ] && write_baseline "$sbf" seed "$syn"
      echo "TSC-RATCHET-SEED $repo/$wd: baseline=$cnt (via: $cmd)"
    elif [ "${OVN_TSC_SYNTAX_HARDFAIL:-1}" != 0 ] && [ "$syn" -gt 0 ] && [ "$cnt" -lt "$base" ]; then
      echo "TSC-RATCHET-OK $repo/$wd: $syn pre-existing syntax error(s) present; count $base -> $cnt NOT ratcheted (semantic errors hidden)."
    elif [ "$cnt" -gt "$base" ] && premeasure && [ "$ARC_CNT" -le "$PRE_CNT" ]; then
      write_baseline "$bf" rebase "$cnt" "$base"
      echo "TSC-RATCHET-REBASED $repo/$wd: stored baseline $base was stale (parent tree already had $PRE_CNT, this commit has $cnt; it added none); baseline re-seeded to $cnt (via: $cmd)."
    elif [ "$cnt" -gt "$base" ]; then
      [ -n "$PRE_CNT" ] && echo "(parent tree measured $PRE_CNT, stored baseline $base; this commit: $cnt)"
      echo "TSC-RATCHET-REGRESSION $repo/$wd: type errors $base -> $cnt (this commit added $((cnt-base)); via: $cmd)."
      echo "$out" | grep -E 'error TS[0-9]' | head -12
      exit 1
    elif [ "$cnt" -lt "$base" ]; then
      write_baseline "$bf" down "$cnt"; echo "TSC-RATCHET-IMPROVED $repo/$wd: type errors $base -> $cnt (baseline ratcheted down)."
    else
      echo "TSC-RATCHET-OK $repo/$wd: type errors held at $cnt."
    fi
  ) || rc_overall=1
done < <(find . -maxdepth 3 -name tsconfig.json -not -path '*/node_modules/*' 2>/dev/null)

exit "$rc_overall"
