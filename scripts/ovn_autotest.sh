#!/usr/bin/env bash
# Adaptive + SCOPED aider --test-cmd (2026-08-28 v2): run ONLY the tests related to
# what the model just edited, fast, so the in-loop check barely touches the coding
# budget. Fast feedback lets the model fix its own mistakes; the runner's
# post-commit verification is the full-suite SAFETY NET, so this staying scoped is
# safe. Exits non-zero only on a real failure of the scoped tests.
set -uo pipefail
root="${1:-.}"
# 2026-10-09: the queue dir (for state/godot_checkonly_cache) must be resolved BEFORE the cd below.
_AT_SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
QDIR="${OVN_DIR:-$(dirname "$_AT_SELF")}"
cd "$root" 2>/dev/null || exit 0

# 2026-10-01 FIX (feedback-loops analysis): run_overnight.sh lets aider AUTO-COMMIT each edit, and aider runs --test-cmd AFTER that commit,
# so the tree is clean and the plain `git diff` list below was EMPTY -> this script exited 0 on every edit: the in-loop test/type-check
# feedback never reached the model for T1/T2 and the ongoing-* lanes (~2,600 cycles/14d; 400 NO-NEW-RED + 237 build-break reverts followed).
# Diff against the pre-implement SHA (OVN_BASE_SHA, exported per repo by run_overnight.sh via scripts/lib_autotest_base.sh) so committed AND
# uncommitted edits are both seen. No/invalid OVN_BASE_SHA (the staged runner uses --no-auto-commits) -> behaviour unchanged.
if [ -n "${OVN_BASE_SHA:-}" ] && git rev-parse -q --verify "${OVN_BASE_SHA}^{commit}" >/dev/null 2>&1; then
  changed="$( { git diff --name-only "$OVN_BASE_SHA" -- .; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )"
else
  changed="$( { git diff --name-only; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )"
fi
[ -z "$changed" ] && exit 0

# ---- GODOT (gdscript): validate every changed .gd so the model gets a real feedback loop ----
# This is the fix for the ~0% Godot pass rate: previously .gd edits got NO per-step gate at all,
# so a single Godot-3-ism (export var / yield / KinematicBody) sailed through unnoticed. Layered gate:
#   1. gdparse  — Godot-4 SYNTAX (reliable exit code; catches the Godot-3 tells). HARD fail.
#   2. godot --check-only — SEMANTIC/API (undeclared signals, unknown methods). Its EXIT CODE is
#      buggy (always 0), so we scan its OUTPUT for "Parse Error" only. HARD fail on that.
#   3. gdlint   — style/naming. ADVISORY only (xlite's own code emits lint warnings), never fails.
# 2026-10-09 (xlite godot lane): (a) a fresh worktree has no .godot import cache, so --check-only reported undeclared-identifier / 'no resource
# loaders' errors on UNEDITED files (the model chased non-errors for ~300s per attempt): run `--import` first when
# .godot/global_script_class_cache.cfg is missing (OVN_AUTOTEST_GODOT_IMPORT=off disables). (b) BASELINE-RELATIVE: a check-only error fails the step only
# when the same command does NOT report it on the pre-edit blob (OVN_BASE_SHA, else HEAD); the pre-edit result is cached by sha1(path+blob) in
# state/godot_checkonly_cache/ (OVN_GODOT_BASELINE=off restores the absolute behaviour). The comparison is per message OCCURRENCE COUNT, not membership: an edit that
# makes the engine report a message MORE times than the pre-edit blob did (a second use of an already-undeclared identifier) still fails the step. (c) when a hard error exists the gdlint advisories
# (class-definitions-order, max-line-length, trailing-whitespace) are NOT shown: they drown the one error that matters.
gd_changed="$(printf '%s\n' "$changed" | grep -iE '\.gd$' | grep -viE '(^|/)addons/' || true)"
if [ -n "$gd_changed" ]; then
  GDP="$HOME/aider-venv/bin/gdparse"; GDL="$HOME/aider-venv/bin/gdlint"; GODOT="$HOME/godot/godot4"
  gd_fail=0; gd_report=""; gd_lint=""
  is_proj=0; [ -f project.godot ] && is_proj=1
  if [ "$is_proj" = 1 ] && [ -x "$GODOT" ] && [ ! -f .godot/global_script_class_cache.cfg ] && [ "${OVN_AUTOTEST_GODOT_IMPORT:-on}" != off ]; then
    timeout 120 "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  fi
  _gd_esc="$(printf '\033')"
  # normalise one check-only message for comparison: no colours, no line numbers, squeezed blanks
  gd_norm() { printf '%s\n' "$1" | sed -E "s/${_gd_esc}\[[0-9;]*[A-Za-z]//g; s/:[0-9]+([: )]|\$)/:\\1/g; s/ at line [0-9]+//g; s/[[:space:]]+/ /g; s/^ //; s/ \$//"; }
  # gd_overlay <file> <ref> <dest>: build <dest> as a copy of $PWD made of symlinks, except the directory chain down to <file>, which are real
  # directories, and <file> itself, which is written from the blob at <ref>. Never writes into $PWD. .git is not linked.
  gd_overlay() {
    local f="$1" ref="$2" dst="$3" rest part ent b cs="$PWD" cd_="$3"
    rest="$f"
    while :; do
      case "$rest" in */*) part="${rest%%/*}"; rest="${rest#*/}";; *) part="$rest"; rest="";; esac
      for ent in "$cs"/* "$cs"/.[!.]*; do
        [ -e "$ent" ] || [ -L "$ent" ] || continue
        b="${ent##*/}"
        [ "$b" = "$part" ] && continue
        [ "$cs" = "$PWD" ] && [ "$b" = .git ] && continue
        ln -s "$ent" "$cd_/$b" 2>/dev/null || true
      done
      if [ -z "$rest" ]; then git show "$ref:$f" > "$cd_/$part" 2>/dev/null || return 1; return 0; fi
      mkdir "$cd_/$part" || return 1
      cs="$cs/$part"; cd_="$cd_/$part"
    done
  }
  # gd_sibling_sig <file> <ref> -> hash of every OTHER .gd that differs from <ref> in the live tree (edited since the base, or untracked): the pre-edit blob is
  # checked against these live siblings (symlinked into the overlay), so a baseline computed while a sibling was broken must not be reused once it is fixed
  gd_sibling_sig() {
    { git diff --name-only "$2" -- '*.gd'; git ls-files --others --exclude-standard -- '*.gd'; } 2>/dev/null | sort -u | grep -vxF -- "$1" |
      while IFS= read -r _s; do [ -f "$_s" ] && printf '%s %s\n' "$_s" "$(git hash-object "$_s" 2>/dev/null)"; done | git hash-object --stdin 2>/dev/null
  }
  # gd_baseline_errs <file> <ref> -> normalised check-only error lines the PRE-EDIT blob already produced (empty for a file that did not exist then). Duplicates are
  # kept (the caller compares occurrence counts).
  gd_baseline_errs() {
    local f="$1" ref="$2" blob key cdir cf bout brc ov cc tmpf
    blob="$(git rev-parse -q --verify "$ref:$f" 2>/dev/null)" || return 0
    # the key covers the import-cache state too (absent, or its content: it lists the class_names the siblings resolve through) and the sibling state
    cc="nocache"; [ -f .godot/global_script_class_cache.cfg ] && cc="$(git hash-object .godot/global_script_class_cache.cfg 2>/dev/null)"
    key="$(printf '%s\n%s\n%s\n%s' "$f" "$blob" "$cc" "$(gd_sibling_sig "$f" "$ref")" | git hash-object --stdin 2>/dev/null)"
    cdir="${OVN_GODOT_CACHE_DIR:-$QDIR/state/godot_checkonly_cache}"
    cf="$cdir/$key"
    if [ -n "$key" ] && [ -f "$cf" ]; then cat "$cf"; return 0; fi
    # run the very same command against an OVERLAY of the project in which ONLY <file> holds the pre-edit blob (every other entry is a symlink to the
    # live tree, so the class cache, preloads and sibling scripts resolve exactly as in the live run). The live file is never written: a TERM/kill -9
    # of this script, or a timeout of the whole test-cmd, cannot leave the pre-edit blob in it or resurrect an edit that was already reverted.
    ov="$(mktemp -d "${TMPDIR:-/tmp}/ovn_gdbase.XXXXXX")" || return 0
    trap 'rm -rf "$ov"' EXIT
    trap 'rm -rf "$ov"; exit 143' TERM INT
    gd_overlay "$f" "$ref" "$ov" || { rm -rf "$ov"; trap - EXIT TERM INT; return 0; }
    bout="$(cd "$ov" && timeout 60 "$GODOT" --headless --path . --check-only --script "res://$f" 2>&1)"; brc=$?
    rm -rf "$ov"
    trap - EXIT TERM INT
    bout="$(printf '%s\n' "$bout" | grep -iE "$GD_ERR_RE" || true)"
    bout="$(while IFS= read -r l; do [ -n "$l" ] && gd_norm "$l"; done <<< "$bout")"
    # a timed-out baseline is unknown, not 'clean': do not cache it
    # written to a temp file and moved into place (a concurrent reader never sees a half-written entry, which would read as a clean baseline); entries older
    # than a day (and orphaned temp files) are dropped on every write
    if [ "$brc" != 124 ] && [ -n "$key" ] && [ -d "$QDIR/state" ] && mkdir -p "$cdir" 2>/dev/null; then
      find "$cdir" -maxdepth 1 -type f -mtime +0 -delete 2>/dev/null
      tmpf="$cdir/.$key.tmp.$$"
      { printf '%s\n' "$bout" > "$tmpf" && mv -f "$tmpf" "$cf"; } 2>/dev/null || rm -f "$tmpf" 2>/dev/null
    fi
    printf '%s\n' "$bout"
  }
  GD_ERR_RE='Parse Error|Invalid call|not declared|Identifier .* not'
  gd_base_ref="HEAD"
  if [ -n "${OVN_BASE_SHA:-}" ] && git rev-parse -q --verify "${OVN_BASE_SHA}^{commit}" >/dev/null 2>&1; then gd_base_ref="$OVN_BASE_SHA"; fi
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    # 1. syntax (hard)
    if [ -x "$GDP" ]; then
      perr="$("$GDP" "$f" 2>&1 >/dev/null)" || {
        gd_fail=1
        gd_report="${gd_report}
[SYNTAX] $f is not valid Godot 4 GDScript (gdparse):
$(printf '%s\n' "$perr" | head -6)"
        continue   # no point compile-checking a file that won't parse
      }
    fi
    # 2. semantic/API via engine --check-only (parse OUTPUT, exit code is unreliable)
    if [ "$is_proj" = 1 ] && [ -x "$GODOT" ]; then
      cout="$(timeout 60 "$GODOT" --headless --path . --check-only --script "res://$f" 2>&1 || true)"
      cerr="$(printf '%s\n' "$cout" | grep -iE "$GD_ERR_RE" || true)"
      if [ -n "$cerr" ] && [ "${OVN_GODOT_BASELINE:-on}" != off ]; then
        # keep only the messages the pre-edit blob did NOT already produce (the model is only ever told about errors its edit introduced)
        base_errs="$(gd_baseline_errs "$f" "$gd_base_ref")"
        new_cerr=""; used=""
        while IFS= read -r ln; do
          [ -n "$ln" ] || continue
          n="$(gd_norm "$ln")"
          # the first <baseline count> occurrences of a message are the old ones; any further occurrence is new
          if [ "$(grep -cxF -- "$n" <<< "$used")" -lt "$(grep -cxF -- "$n" <<< "$base_errs")" ]; then used="${used}${n}"$'\n'; else new_cerr="${new_cerr}${ln}"$'\n'; fi
        done <<< "$cerr"
        cerr="${new_cerr%$'\n'}"
      fi
      cerr="$(printf '%s\n' "$cerr" | head -6)"
      if [ -n "$cerr" ]; then
        gd_fail=1
        gd_report="${gd_report}
[API] $f has Godot-4 semantic errors (godot --check-only):
$cerr"
      fi
    fi
    # 3. lint (advisory — surfaces Godot-3 naming/structure hints without blocking)
    if [ -x "$GDL" ]; then
      lout="$("$GDL" "$f" 2>&1 | grep -iE 'Error:|Warning:' | head -4 || true)"
      [ -n "$lout" ] && gd_lint="${gd_lint}
[lint-advisory] $f:
$lout"
    fi
  done <<< "$gd_changed"
  if [ "$gd_fail" = 1 ]; then
    echo "GODOT 4 VALIDATION FAILED — fix these before finishing (this is Godot 4.x, never Godot 3):"
    printf '%s\n' "$gd_report"
    exit 1
  fi
  # .gd validated clean; if the change was ONLY gdscript, we're done (no vitest/pytest needed)
  gd_report="${gd_report}${gd_lint}"   # advisories are only shown when no hard error was found
  printf '%s\n' "$changed" | grep -viE '\.gd$' | grep -qE '\.(ts|tsx|vue|js|jsx|py)$' || { [ -n "$gd_report" ] && printf '%s\n' "$gd_report"; exit 0; }
fi

nearest_pkg() {
  local d="$1"
  while [ -n "$d" ] && [ "$d" != "." ] && [ "$d" != "/" ]; do
    [ -f "$d/package.json" ] && { echo "$d"; return 0; }
    d="$(dirname "$d")"
  done
  [ -f "package.json" ] && echo "."
}

# ---- WEB (vitest): only changed specs, or tests related to changed source ----
web_dir=""; specs=""; srcs=""
while IFS= read -r f; do
  case "$f" in
    *.ts|*.tsx|*.vue|*.js|*.jsx)
      pd="$(nearest_pkg "$(dirname "$f")")"; [ -z "$pd" ] && continue
      { [ -d "$pd/node_modules/vitest" ] || grep -q '"vitest"' "$pd/package.json" 2>/dev/null; } || continue
      web_dir="$pd"
      rel="${f#"$pd"/}"; [ "$pd" = "." ] && rel="$f"
      case "$rel" in *.test.*|*.spec.*) specs="$specs $rel";; *) srcs="$srcs $rel";; esac ;;
  esac
done <<< "$changed"

if [ -n "$web_dir" ]; then
  cd "$web_dir"
  # scoped type-check (2026-09-04): surface type errors in the files THIS edit touched so
  # the model self-corrects mid-cycle. Only the model's OWN changed files fail the check;
  # pre-existing errors elsewhere are ignored. Toggle OVN_TSC_MIDCYCLE=0.
  if [ "${OVN_TSC_MIDCYCLE:-1}" = 1 ]; then
    _chset="$(printf "%s\n%s\n" "$specs" "$srcs" | tr " " "\n" | sed "/^$/d")"
    if [ -n "$_chset" ] && { [ -x node_modules/.bin/vue-tsc ] || [ -x node_modules/.bin/tsc ] || [ -d node_modules/typescript ]; }; then
      if [ -x node_modules/.bin/vue-tsc ]; then _tcmd="npx --no-install vue-tsc --noEmit"
      elif grep -q '"type-check"' package.json 2>/dev/null; then _tcmd="npm run --silent type-check"
      else _tcmd="npx --no-install tsc --noEmit"; fi
      _tscout="$(timeout 120 $_tcmd 2>&1)"
      _own="$(printf "%s\n" "$_tscout" | grep -E "error TS[0-9]" | grep -Ff <(printf "%s\n" "$_chset") || true)"
      if [ -n "$_own" ]; then
        echo "TYPE ERRORS in files you just edited — fix these before finishing:"
        printf "%s\n" "$_own" | head -20
        exit 1
      fi
    fi
  fi
  if [ -n "$specs" ]; then
    CI=true timeout 75 npx vitest run $specs 2>&1 | tail -30
    exit "${PIPESTATUS[0]}"
  elif [ -n "$srcs" ]; then
    CI=true timeout 75 npx vitest related $srcs --run 2>&1 | tail -30
    exit "${PIPESTATUS[0]}"
  fi
  exit 0
fi

# ---- BACKEND (pytest) ----
pytest_dir="$(find . -maxdepth 4 -type f -path '*/.venv/bin/pytest' 2>/dev/null | head -1 | sed 's#/.venv/bin/pytest##')"
if [ -n "$pytest_dir" ]; then
  # classify the changed python into SOURCE modules vs TEST files (both relative to the pytest dir)
  tfiles=""; src_mods=""
  while IFS= read -r f; do
    case "$f" in *.py) ;; *) continue ;; esac
    [ -f "$f" ] || continue
    case "$f" in "${pytest_dir#./}"/*|"$pytest_dir"/*) rel="${f#"${pytest_dir#./}"/}"; rel="${rel#"$pytest_dir"/}";; *) rel="$f";; esac
    case "$(basename "$f")" in
      test_*.py|*_test.py) tfiles="$tfiles $rel" ;;
      *) src_mods="$src_mods $(basename "${f%.py}")" ;;
    esac
  done <<< "$changed"
  cd "$pytest_dir"

  # FIX 2 (OVN_GATE_STRICT, 2026-09-08): a new/changed test must actually EXERCISE the changed source.
  # This was the #1 live false-pass (13 on T3): the model writes a test that never calls the code it
  # changed, so it "passes" while proving nothing. Catch it IN-LOOP (fail the step) so the model fixes
  # the test, instead of silently failing at final full-verify. Lenient to avoid false-rejects: a test
  # counts as exercising the change if it names a changed module OR drives an endpoint via TestClient
  # (endpoint tests legitimately use client.get('/path') rather than importing the router module).
  if [ "${OVN_GATE_STRICT:-1}" = 1 ] && [ -n "$src_mods" ] && [ -n "$tfiles" ]; then
    _exercises=0
    for tf in $tfiles; do
      [ -f "$tf" ] || continue
      for m in $src_mods; do grep -qE "\\b${m}\\b" "$tf" 2>/dev/null && _exercises=1; done
      grep -qE '\.(get|post|put|delete|patch)\(' "$tf" 2>/dev/null && _exercises=1
    done
    if [ "$_exercises" = 0 ]; then
      echo "TEST DOES NOT EXERCISE YOUR CHANGE: the test file(s) you wrote never import or call the code you changed (${src_mods# }). A test that doesn't touch the changed code proves nothing and will be rejected. Import and CALL the new/changed symbol and assert on its behavior — or, for an endpoint, drive it with the TestClient (client.get('/path'))."
      exit 1
    fi
  fi

  # FIX 1 (OVN_GATE_STRICT, 2026-09-08): run the changed tests PLUS the test file that matches each
  # changed source module (test_<module>.py anywhere), so an integration break is caught IN-LOOP. This
  # is what made T4 items land-all-steps but then fail at final full-verify (4/5 landed, only 1 verified):
  # each step passed its own scoped test, but the combined change broke a sibling test never run in-loop.
  runset="$tfiles"
  if [ "${OVN_GATE_STRICT:-1}" = 1 ] && [ -n "$src_mods" ]; then
    for m in $src_mods; do
      for cand in $(find . -maxdepth 6 \( -name "test_${m}.py" -o -name "${m}_test.py" \) 2>/dev/null | sed 's#^\./##'); do
        case " $runset " in *" $cand "*) ;; *) runset="$runset $cand" ;; esac
      done
    done
  fi

  if [ -n "$(printf '%s' "$runset" | tr -d ' ')" ]; then
    timeout 120 ./.venv/bin/pytest -q --no-cov -x $runset 2>&1 | tail -30
  else
    timeout 120 ./.venv/bin/pytest -q --no-cov -x 2>&1 | tail -30
  fi
  exit "${PIPESTATUS[0]}"
fi
exit 0
