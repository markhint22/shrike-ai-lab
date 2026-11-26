#!/usr/bin/env bash
# scripts/lib_postcycle_contract.sh - SOURCE this. POST-CYCLE CONTRACT HOOK (q-contract, 2026-11-25). Doc: docs/Q_CONTRACT_2026-11-25.md.
#
# Why: gitlark's hygiene gate went red three times in 3 days (11-23 4h, 11-24 4h, 11-24 23:00 -> 11-25 18h+) because a cycle changed a router / response schema / route tag and the
# generated or hand-kept artifacts the repo's OWN tests pin were not in step: docs/openapi.json (frozen contract), openapi_meta.TAG_DESCRIPTIONS (+ docs/API_TAGS.md). The existing
# auto-regen (run_overnight.sh, BEFORE verify) cannot see an edit the Tier-2 FIX-UP makes afterwards (b0c5e870: the fix-up retyped PlanResponse dates, the contract drifted), and
# nothing regenerates a tag description. The per-cycle verify never runs these tests (they import app.main only; the related-test selector finds no module name). They take 0.2 s.
#
# ovn_postcycle_contract BEFORE_SHA AFTER_SHA TASK_LOG ITEM_ID   (call AFTER verify/fix-up, BEFORE the commit/push phase; cwd = the repo)
#   return 0 = carry on (OVN_PCC_AFTER = the sha to land; a regen commit may have been added), return 1 = REVERT this cycle as red (enforce only; the caller resets to BEFORE_SHA).
# What it does (only when the cycle diff TRIGGERS: a changed file under app/routers/ or app/schemas/, core/openapi_meta.py, docs/API_TAGS.md|openapi.json, or an added line with
# include_router / APIRouter(...tags...) / tags=[ ):
#   1. run the repo's artifact tests (tests/test_openapi*.py, tests/test_api_tags_doc.py; or the .ovn-postcycle.conf list) with the repo's own verify venv;
#   2. green -> done. Red -> compare with the SAME tests at BEFORE_SHA (git archive, scratch dir): only ids that were green before are THIS cycle's fault (an inherited red never
#      reverts a later cycle: that would cascade);
#   3. if an export script exists (scripts/export_openapi.py) run it and re-test; a regen that makes every NEW id green is committed with the cycle (pathspec commit, only the files
#      the regen changed); NEW ids still red after the regen (e.g. an undescribed tag: no regen can write that) -> revert as red.
# OVN_POSTCYCLE_CONTRACT=off|shadow|enforce (default shadow). shadow measures everything, logs would-regen / would-revert rows to state/contract_regen_shadow.log and changes NOTHING
# (the regen's file changes are undone). enforce acts, but only for repos in OVN_POSTCYCLE_ENFORCE_REPOS (default "gitlark"); every other repo stays shadow even when set to enforce.
# REGEN GUARDS (never commit a wrong regen; each skip changes nothing, logs a row, returns 0): venv-mismatch (the verify venv's pydantic/fastapi/langsmith differ from the repo's requirements*.txt
# `==` pins), predirty (an artifact file was already dirty before the hook), regen-removes-paths (the regen drops a `paths` key / "/x": { line from the artifact).
# OVN_PCC_REPO / OVN_PCC_VENV_ROOT: the stage runner (a /tmp worktree with no venv) names the repo and the checkout that owns the venv. contract_regen_shadow.log is bounded (last 5000 lines once >6000).
# Never acts when the tests cannot run (no venv, timeout, import error without a test id): row "unrunnable", return 0.
type ovn_hto >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/lib_helper_timeout.sh" 2>/dev/null || ovn_hto(){ shift 2; "$@"; }

OVN_PCC_PATH_ERE='(^|/)app/(routers|schemas)/|(^|/)core/openapi_meta\.py$|(^|/)docs/(API_TAGS\.md|openapi\.json)$'
OVN_PCC_ADDED_ERE='^\+[^+].*(include_router|APIRouter\(.*tags|tags=\[)'

_pcc_state_dir(){ printf '%s' "${OVN_STATE_DIR:-${STATE_DIR:-${SCRIPT_DIR:-.}/state}}"; }
_pcc_say(){ [ -n "${1:-}" ] && [ -w "$(dirname "$1")" ] && printf '%s\n' "$2" >> "$1" 2>/dev/null; return 0; }

# one TSV row: ts repo mode action before after new_ids inherited_ids detail n
# the log is BOUNDED (trimmed to the last 5000 lines atomically, tmp+mv, once it passes 6000) and n counts only within the recent tail (never a grep of the whole file per row).
_pcc_trim(){  # LOGFILE
  local lg="$1" tmpf
  [ -f "$lg" ] || return 0
  [ "$(wc -l < "$lg" 2>/dev/null | tr -d ' ')" -gt "${OVN_PCC_LOG_MAX:-6000}" ] 2>/dev/null || return 0
  tmpf="$lg.tmp.$$"
  if tail -n "${OVN_PCC_LOG_KEEP:-5000}" "$lg" > "$tmpf" 2>/dev/null; then mv -f "$tmpf" "$lg" 2>/dev/null || rm -f "$tmpf"; else rm -f "$tmpf"; fi
  return 0
}
_pcc_row(){  # action new inherited detail
  local sd lg n; sd="$(_pcc_state_dir)"; mkdir -p "$sd" 2>/dev/null; lg="$sd/contract_regen_shadow.log"
  _pcc_trim "$lg"
  n=$(( $(tail -n 1000 "$lg" 2>/dev/null | grep -c "	${_PCC_REPO:-$(basename "$PWD")}	[a-z-]*	$1	" || true) + 1 ))
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\tn=%s\n' "$(date -u '+%F %T')" "${_PCC_REPO:-$(basename "$PWD")}" "${_PCC_MODE_EFF:-?}" "$1" "${_PCC_B:0:12}" "${_PCC_A:0:12}" "${2:-}" "${3:-}" "${4:-}" "$n" >> "$lg" 2>/dev/null
  return 0
}

# --- regen safety guards (q-contract fix, 2026-11-25) ---
# (a) the venv that produces a regen must be the one the repo pins: a different pydantic/fastapi/langsmith renders the schema differently (pydantic 2.10 flips allOf:[{$ref}] to a bare $ref
#     over the whole file) and the regen would turn an inherited-red frozen-contract test green with a WRONG file. rc 0 = ok (or no documented pins), rc 1 = mismatch (prints "pkg installed!=pin").
ovn_pcc_venv_mismatch(){  # uses PCC_DIR PCC_PY
  local f line pkg pin got
  for f in "$PCC_DIR"/requirements*.txt ./requirements*.txt; do
    [ -f "$f" ] || continue
    while IFS= read -r line; do
      pkg="${line%%==*}"; pin="${line#*==}"; pin="${pin%%[ ;#]*}"
      case "$pkg" in pydantic|fastapi|langsmith) ;; *) continue;; esac
      got="$("$PCC_PY" -c "import importlib.metadata as m; print(m.version('$pkg'))" 2>/dev/null)" || continue
      [ -n "$got" ] || continue
      [ "$got" = "$pin" ] || { printf '%s installed %s != pin %s' "$pkg" "$got" "$pin"; return 1; }
    done < <(grep -E '^(pydantic|fastapi|langsmith)==' "$f" 2>/dev/null | tr -d '\r')
  done
  return 0
}
# (b) a regen must never REMOVE an API path: prints the removed path keys (deleted "/..." keys not re-added), rc 0 = something was removed. Path keys are the lines `"/x": {` of the
#     JSON (any indent) or, for a plain-text artifact, a line starting with `/`.
_PCC_PATHKEY_ERE='^[-+][[:space:]]*("/[^"]*"[[:space:]]*:[[:space:]]*\{|/[^[:space:]"]*[[:space:]]*$)'
ovn_pcc_removed_paths(){  # PATHSPEC...: the changed artifact files (tracked ones only matter)
  local d del add out
  d="$(git diff -U0 -- "$@" 2>/dev/null | grep -E "$_PCC_PATHKEY_ERE" | grep -vE '^(---|\+\+\+)')"
  del="$(printf '%s\n' "$d" | grep '^-' | sed -E 's/^-[[:space:]]*//; s/[[:space:]]*:.*$//' | LC_ALL=C sort -u)"
  add="$(printf '%s\n' "$d" | grep '^+' | sed -E 's/^\+[[:space:]]*//; s/[[:space:]]*:.*$//' | LC_ALL=C sort -u)"
  out="$(_pcc_ids_minus "$del" "$add")"
  [ -n "$out" ] || return 1
  printf '%s' "$(printf '%s' "$out" | tr '\n' ',' | cut -c1-200)"
  return 0
}
# undo exactly the listed porcelain paths: tracked -> checkout, untracked -> clean (the regen can create new files too)
_pcc_undo(){  # newline list of paths
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    p="${p%\"}"; p="${p#\"}"
    if git ls-files --error-unmatch -- "$p" >/dev/null 2>&1; then git checkout -q -- "$p" 2>/dev/null
    else git clean -fdq -- "$p" 2>/dev/null; fi
  done <<< "$1"
  return 0
}

# does the cycle diff trigger? prints the reason, rc 0 = yes
ovn_pcc_trigger(){  # BEFORE AFTER
  local b="$1" a="$2" f
  f="$(git diff --name-only "$b" "$a" 2>/dev/null | grep -E "$OVN_PCC_PATH_ERE" | head -1)"
  [ -n "$f" ] && { printf 'path:%s' "$f"; return 0; }
  f="$(git diff -U0 "$b" "$a" -- '*.py' 2>/dev/null | grep -E "$OVN_PCC_ADDED_ERE" | head -1 | cut -c1-80)"
  [ -n "$f" ] && { printf 'added:%s' "$f"; return 0; }
  return 1
}

# config -> PCC_DIR (repo-relative dir that holds tests/), PCC_TESTS (space list, relative to PCC_DIR), PCC_REGEN (relative to PCC_DIR or empty), PCC_PY (absolute) ; rc 1 = n/a
# a repo-owned .ovn-postcycle.conf (key=value lines, PARSED never sourced: dir= tests= regen= python=) overrides the autodetect.
ovn_pcc_config(){
  PCC_DIR=""; PCC_TESTS=""; PCC_REGEN=""; PCC_PY=""
  local conf=".ovn-postcycle.conf" k v d cand
  if [ -f "$conf" ]; then
    while IFS='=' read -r k v; do
      case "$k" in dir) PCC_DIR="$v";; tests) PCC_TESTS="$v";; regen) PCC_REGEN="$v";; python) PCC_PY="$v";; esac
    done < <(grep -E '^(dir|tests|regen|python)=' "$conf")
  fi
  if [ -z "$PCC_DIR" ]; then
    for cand in backend . $(find . -maxdepth 2 -type d -name tests -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/venv/*' 2>/dev/null | sed 's#^\./##; s#/tests$##' | sort); do
      ls "$cand"/tests/test_openapi*.py >/dev/null 2>&1 && { PCC_DIR="$cand"; break; }
    done
  fi
  [ -n "$PCC_DIR" ] && [ -d "$PCC_DIR/tests" ] || return 1
  if [ -z "$PCC_TESTS" ]; then
    PCC_TESTS="$( (cd "$PCC_DIR" && ls tests/test_openapi*.py tests/test_api_tags_doc.py 2>/dev/null) | tr '\n' ' ' )"
  fi
  [ -n "${PCC_TESTS// /}" ] || return 1
  [ -z "$PCC_REGEN" ] && [ -f "$PCC_DIR/scripts/export_openapi.py" ] && PCC_REGEN="scripts/export_openapi.py"
  if [ -z "$PCC_PY" ]; then
    for d in "$PCC_DIR/.venv/bin/python3" "$PCC_DIR/.venv/bin/python" "$PCC_DIR/venv/bin/python3" "$PCC_DIR/venv/bin/python" ".venv/bin/python3" "venv/bin/python3"; do
      [ -x "$d" ] && { PCC_PY="$(cd "$(dirname "$d")" && pwd)/$(basename "$d")"; break; }
    done
    # OVN_PCC_VENV_ROOT: the stage runner works in a git worktree that has no (gitignored) venv; the repo checkout it was cut from does.
    if [ -z "$PCC_PY" ] && [ -n "${OVN_PCC_VENV_ROOT:-}" ]; then
      for d in "$OVN_PCC_VENV_ROOT/$PCC_DIR/.venv/bin/python3" "$OVN_PCC_VENV_ROOT/$PCC_DIR/.venv/bin/python" "$OVN_PCC_VENV_ROOT/$PCC_DIR/venv/bin/python3" "$OVN_PCC_VENV_ROOT/$PCC_DIR/venv/bin/python" "$OVN_PCC_VENV_ROOT/.venv/bin/python3" "$OVN_PCC_VENV_ROOT/venv/bin/python3"; do
        [ -x "$d" ] && { PCC_PY="$(cd "$(dirname "$d")" && pwd)/$(basename "$d")"; break; }
      done
    fi
  fi
  return 0
}

# run the tests in a tree: FIRST line "rc=<pytest rc>", then one failing id per line (file::test, the " - message" tail stripped). Always returns 0.
# (called inside $( ), so the rc travels on stdout, never in a variable)
_pcc_tests(){  # TREE_ROOT (the repo root or an archive of it)
  local root="$1" out rc t="" f
  for f in $PCC_TESTS; do [ -f "$root/$PCC_DIR/$f" ] && t="$t $f"; done
  [ -n "$t" ] || { echo "rc=5"; return 0; }
  # shellcheck disable=SC2086
  out="$(cd "$root/$PCC_DIR" && PYTHONDONTWRITEBYTECODE=1 ovn_hto "${OVN_PCC_TIMEOUT:-120}" postcycle_contract_tests "$PCC_PY" -m pytest -q -p no:cacheprovider --no-header $t 2>&1)"
  rc=$?
  echo "rc=$rc"
  printf '%s\n' "$out" | grep -E '^(FAILED|ERROR) ' | awk '{print $2}' | LC_ALL=C sort -u
  return 0
}
_pcc_rc(){ printf '%s\n' "$1" | sed -n '1s/^rc=//p'; }
_pcc_ids(){ printf '%s\n' "$1" | sed '1d'; }
# LC_ALL=C on every sort AND comm: comm warns/misreads when the locale of sort and comm differ (seen on the box: "file 2 is not in sorted order")
_pcc_ids_minus(){ LC_ALL=C comm -23 <(printf '%s\n' "$1" | sed '/^$/d' | LC_ALL=C sort -u) <(printf '%s\n' "$2" | sed '/^$/d' | LC_ALL=C sort -u); }
_pcc_join(){ printf '%s' "$1" | sed '/^$/d' | tr '\n' ';' | sed 's/;$//'; }

ovn_postcycle_contract(){  # BEFORE AFTER TASK_LOG ITEM_ID
  local b="$1" a="$2" tl="${3:-}" mode eff repo why f1 rc1 f0 f2 new1 new2 inh before_dirty after_dirty changed="" x tmp base_rc
  OVN_PCC_AFTER="$a"; OVN_PCC_STATUS="off"
  mode="${OVN_POSTCYCLE_CONTRACT:-shadow}"
  [ "$mode" = off ] && return 0
  repo="${OVN_PCC_REPO:-$(basename "$PWD")}"; _PCC_REPO="$repo"   # OVN_PCC_REPO: the stage runner runs in a /tmp/stage-<repo>.XXXX worktree whose dirname is not the repo name
  ovn_pcc_config || { OVN_PCC_STATUS="na"; return 0; }
  why="$(ovn_pcc_trigger "$b" "$a")" || { OVN_PCC_STATUS="no-trigger"; return 0; }
  eff="$mode"
  if [ "$mode" = enforce ]; then
    case " ${OVN_POSTCYCLE_ENFORCE_REPOS:-gitlark} " in *" $repo "*) ;; *) eff=shadow;; esac
  fi
  _PCC_MODE_EFF="$eff"; _PCC_B="$b"; _PCC_A="$a"
  if [ -z "$PCC_PY" ]; then OVN_PCC_STATUS="unrunnable"; _pcc_row unrunnable "" "" "no venv python ($why)"; return 0; fi
  f1="$(_pcc_tests "$PWD")"; rc1="$(_pcc_rc "$f1")"; f1="$(_pcc_ids "$f1")"
  if [ "$rc1" -eq 0 ]; then OVN_PCC_STATUS="pass"; _pcc_row pass "" "" "trigger=$why"; return 0; fi
  if [ -z "$f1" ]; then OVN_PCC_STATUS="unrunnable"; _pcc_row unrunnable "" "" "rc=$rc1 no failing id (timeout/import error) trigger=$why"; return 0; fi
  # baseline: the same tests at BEFORE_SHA
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/ovn-pcc.XXXXXX" 2>/dev/null)" || { OVN_PCC_STATUS="unrunnable"; _pcc_row unrunnable "" "" "no scratch dir"; return 0; }
  if ! { git archive "$b" -- "$PCC_DIR" $([ -d docs ] && echo docs) 2>/dev/null | tar -x -C "$tmp" 2>/dev/null; }; then
    rm -rf "$tmp"; OVN_PCC_STATUS="unrunnable"; _pcc_row unrunnable "$(_pcc_join "$f1")" "" "baseline archive failed"; return 0
  fi
  f0="$(_pcc_tests "$tmp")"; base_rc="$(_pcc_rc "$f0")"; f0="$(_pcc_ids "$f0")"
  rm -rf "$tmp"
  # a baseline that could not run at all (timeout / interpreter error: no failing id, rc not 0/5) proves nothing: never blame the cycle on it
  if [ -z "$f0" ]; then case "$base_rc" in 0|5) ;; *) OVN_PCC_STATUS="unrunnable"; _pcc_row unrunnable "$(_pcc_join "$f1")" "" "baseline rc=$base_rc without a failing id"; return 0;; esac; fi
  new1="$(_pcc_ids_minus "$f1" "$f0")"; inh="$(_pcc_ids_minus "$f1" "$new1")"
  # regen attempt (only when an export script exists and a contract test is among the red ids): measured on the live tree, undone in shadow.
  # GUARDS (q-contract fix): never regen from a venv whose pydantic/fastapi/langsmith differ from the repo's pins (venv-mismatch); never when an artifact is already dirty before the hook (the
  # changed list could not be computed against the cycle's own commit); never COMMIT/KEEP a regen that removes an API path (regen-removes-paths). Each skip leaves the tree as it was.
  f2="$f1"; skip=""
  if [ -n "$PCC_REGEN" ] && printf '%s\n' "$f1" | grep -q 'openapi_contract'; then
    before_dirty="$(git status --porcelain 2>/dev/null | LC_ALL=C sort)"
    if vm="$(ovn_pcc_venv_mismatch)"; then
      if printf '%s\n' "$before_dirty" | sed 's/^...//' | grep -qE "$OVN_PCC_PATH_ERE"; then
        skip="predirty"; skipd="artifact dirty before the hook: $(printf '%s\n' "$before_dirty" | sed 's/^...//' | grep -E "$OVN_PCC_PATH_ERE" | head -1)"
      else
        ( cd "$PCC_DIR" && ovn_hto 120 postcycle_contract_regen "$PCC_PY" "$PCC_REGEN" ) >> "${tl:-/dev/null}" 2>&1
        after_dirty="$(git status --porcelain 2>/dev/null | LC_ALL=C sort)"
        changed="$(LC_ALL=C comm -13 <(printf '%s\n' "$before_dirty" | sed '/^$/d') <(printf '%s\n' "$after_dirty" | sed '/^$/d') | sed 's/^...//')"
        if [ -n "$changed" ]; then
          # shellcheck disable=SC2086
          if rm_paths="$(ovn_pcc_removed_paths $changed)"; then
            _pcc_undo "$changed"; changed=""; skip="regen-removes-paths"; skipd="removed: $rm_paths"
          else
            f2="$(_pcc_tests "$PWD")"; f2="$(_pcc_ids "$f2")"
          fi
        fi
      fi
    else
      skip="venv-mismatch"; skipd="$vm"
    fi
  fi
  new2="$(_pcc_ids_minus "$f2" "$f0")"
  # a guard refused the regen: the contract ids it would have healed are NOT judged here (no heal available is not a reason to throw the cycle's work away; the old behaviour was to land it);
  # any OTHER new red id (an undescribed tag) still reverts in enforce.
  if [ -n "$skip" ]; then new2="$(printf '%s\n' "$new2" | grep -v 'openapi_contract' || true)"; fi
  if [ -z "$new2" ]; then
    if [ -n "$changed" ]; then
      if [ "$eff" = enforce ]; then
        # shellcheck disable=SC2086
        git add -- $changed 2>/dev/null
        # shellcheck disable=SC2086
        if git commit -q -m "chore(contract): regenerate artifacts after the cycle's final state (postcycle contract hook)" -- $changed >/dev/null 2>&1; then
          OVN_PCC_AFTER="$(git rev-parse HEAD)"; OVN_PCC_STATUS="regen"
          _pcc_say "$tl" "--- POSTCYCLE CONTRACT: the cycle left $(_pcc_join "$new1") red; regenerated $(printf '%s' "$changed" | tr '\n' ' ')and committed (tests green) ---"
          _PCC_A="$OVN_PCC_AFTER"; _pcc_row regen "$(_pcc_join "$new1")" "$(_pcc_join "$inh")" "files=$(printf '%s' "$changed" | tr '\n' ',') trigger=$why"
          return 0
        fi
        OVN_PCC_STATUS="unrunnable"; _pcc_row unrunnable "$(_pcc_join "$new1")" "" "regen commit failed"; return 0
      fi
      # shadow: undo exactly what the regen changed
      _pcc_undo "$changed"
      OVN_PCC_STATUS="would-regen"
      _pcc_say "$tl" "--- POSTCYCLE CONTRACT (shadow): would regenerate $(printf '%s' "$changed" | tr '\n' ' ')- fixes $(_pcc_join "$new1") ---"
      _pcc_row would-regen "$(_pcc_join "$new1")" "$(_pcc_join "$inh")" "files=$(printf '%s' "$changed" | tr '\n' ',') trigger=$why"
      return 0
    fi
    if [ -n "$skip" ]; then   # the regen was refused by a guard: nothing committed, nothing changed, never a revert for it
      OVN_PCC_STATUS="$skip"
      _pcc_say "$tl" "--- POSTCYCLE CONTRACT: regen skipped ($skip: $skipd) - nothing committed ---"
      _pcc_row "$skip" "$(_pcc_join "$new1")" "$(_pcc_join "$inh")" "$skipd trigger=$why"
      return 0
    fi
    OVN_PCC_STATUS="inherited-red"
    _pcc_row inherited-red "" "$(_pcc_join "$inh")" "red before this cycle too (base_rc=$base_rc) trigger=$why"
    return 0
  fi
  # NEW red ids no regen can fix
  if [ -n "$changed" ]; then
    _pcc_undo "$changed"
  fi
  if [ "$eff" = enforce ]; then
    OVN_PCC_STATUS="revert"
    _pcc_say "$tl" "--- POSTCYCLE CONTRACT: the cycle turned $(_pcc_join "$new2") red and no regen fixes it - reverting as red ---"
    _pcc_row revert "$(_pcc_join "$new2")" "$(_pcc_join "$inh")" "trigger=$why"
    return 1
  fi
  OVN_PCC_STATUS="would-revert"
  _pcc_say "$tl" "--- POSTCYCLE CONTRACT (shadow): would REVERT - the cycle turned $(_pcc_join "$new2") red and no regen fixes it ---"
  _pcc_row would-revert "$(_pcc_join "$new2")" "$(_pcc_join "$inh")" "trigger=$why"
  return 0
}
