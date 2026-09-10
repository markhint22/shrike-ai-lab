#!/usr/bin/env bash
# Adaptive + SCOPED aider --test-cmd (2026-08-28 v2): run ONLY the tests related to
# what the model just edited, fast, so the in-loop check barely touches the coding
# budget. Fast feedback lets the model fix its own mistakes; the runner's
# post-commit verification is the full-suite SAFETY NET, so this staying scoped is
# safe. Exits non-zero only on a real failure of the scoped tests.
set -uo pipefail
root="${1:-.}"
cd "$root" 2>/dev/null || exit 0

changed="$( { git diff --name-only; git diff --cached --name-only; git ls-files --others --exclude-standard; } 2>/dev/null | sort -u )"
[ -z "$changed" ] && exit 0

# ---- GODOT (gdscript): validate every changed .gd so the model gets a real feedback loop ----
# This is the fix for the ~0% Godot pass rate: previously .gd edits got NO per-step gate at all,
# so a single Godot-3-ism (export var / yield / KinematicBody) sailed through unnoticed. Layered gate:
#   1. gdparse  — Godot-4 SYNTAX (reliable exit code; catches the Godot-3 tells). HARD fail.
#   2. godot --check-only — SEMANTIC/API (undeclared signals, unknown methods). Its EXIT CODE is
#      buggy (always 0), so we scan its OUTPUT for "Parse Error" only. HARD fail on that.
#   3. gdlint   — style/naming. ADVISORY only (xlite's own code emits lint warnings), never fails.
gd_changed="$(printf '%s\n' "$changed" | grep -iE '\.gd$' | grep -viE '(^|/)addons/' || true)"
if [ -n "$gd_changed" ]; then
  GDP="$HOME/aider-venv/bin/gdparse"; GDL="$HOME/aider-venv/bin/gdlint"; GODOT="$HOME/godot/godot4"
  gd_fail=0; gd_report=""
  is_proj=0; [ -f project.godot ] && is_proj=1
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
      cerr="$(printf '%s\n' "$cout" | grep -iE 'Parse Error|Invalid call|not declared|Identifier .* not' | head -6)"
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
      [ -n "$lout" ] && gd_report="${gd_report}
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
