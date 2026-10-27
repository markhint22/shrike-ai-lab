#!/usr/bin/env bash
# scripts/lib_stage_guards.sh - bash wrappers + kill switches for the staged runner's deterministic guards (scripts/ovn_stage_guards.py). 2026-10-13, package `stage`.
# Sourced by ovn_stage_runner.sh (and the tests). Every function is fail-safe: a missing python helper, an unreadable tree or a timeout means "no finding" (rc 1 / rc 0 as documented),
# never a refusal. Kill switches (each: off | shadow | enforce unless noted):
#   OVN_STAGE_MISTARGET        on|off   (default on)  MASTER switch of both mis-target guards; off disables them. On: refuse a Verify/Check/Confirm step naming a non-existent file (xlite F3)
#   OVN_STAGE_ITEM_MISTARGET   off|shadow|enforce (default shadow)  the item-level half: an item whose own (backticked) VERIFY greps a non-existent path it does not create. SHADOW logs the verdict to
#                                                    ${OVN_STAGE_SHADOW_LOG:-state/stage_guards_shadow.log} and changes nothing; flip to enforce only after that log has been read (reviewer 2026-10-13: new enforcement ships shadow)
#   OVN_STAGE_CLASS_CONFLICT   on|off   (default on)  abandon a step when Godot says the class hides an autoload singleton / global script class (xlite F3)
#   OVN_STAGE_NAMED_TESTS      off|shadow|enforce (default enforce)  every test the item / landed step promises must exist in the final tree and pass when run by node id (iptv F2)
#                                                    ENFORCE by default on purpose: this is a false-credit BUG fix (iptv F2: a repair round deleted the promised test and the item was still credited), it can only refuse a
#                                                    credit whose promised test is absent, and the first review's false positives are fixed (kt/swift/java located, unreadable languages unverifiable). Set shadow to observe first
#                                                    (findings then go to ${vlog}.shadow-named); off is the kill switch.
#   OVN_STAGE_ITEM_VERIFY      off|shadow|enforce (default shadow)   the item's own VERIFY must be RED on the pristine tree and GREEN on the final one before the item is ticked (xlite F3 / iptv F2)
#   OVN_STAGE_RED_BEFORE       off|shadow|enforce (default shadow)   the tests the change added must FAIL once the source change is reverted (iptv F6)
#   OVN_STAGE_WEB_VERIFY       off|shadow|enforce (default shadow)   vue-tsc + vitest related for changed web files (iptv F6)
_SG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_SG_PY="$_SG_DIR/ovn_stage_guards.py"
_SG_TOOLS_OK=1; type -P python3 >/dev/null 2>&1 && [ -f "$_SG_PY" ] || _SG_TOOLS_OK=0

_sg_mode(){ # $1 = value, $2 = default -> off|shadow|enforce
  case "${1:-$2}" in off|OFF|0) echo off;; shadow|SHADOW) echo shadow;; enforce|ENFORCE|on|ON|1) echo enforce;; *) echo "$2";; esac
}

# stage_step_mistarget <wt> <desc> <files(space separated)> -> rc 0 + reason on stdout when the step is mis-targeted
stage_step_mistarget(){
  [ "${OVN_STAGE_MISTARGET:-on}" = off ] && return 1
  [ "$_SG_TOOLS_OK" = 1 ] || return 1
  local wt="$1" desc="$2" files="$3" out
  # shellcheck disable=SC2086
  out="$(timeout 20 python3 "$_SG_PY" step-mistarget "$wt" "$desc" $files 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"; return 0
}

# stage_item_mistarget <wt> <item> -> rc 0 + reason when the item's own VERIFY greps a non-existent file it does not create AND the guard is enforcing. In shadow mode (the default) the verdict is
# appended to the shadow log and the function returns rc 1 (no refusal).
stage_item_mistarget(){
  [ "${OVN_STAGE_MISTARGET:-on}" = off ] && return 1
  local mode; mode="$(_sg_mode "${OVN_STAGE_ITEM_MISTARGET:-}" shadow)"
  [ "$mode" = off ] && return 1
  [ "$_SG_TOOLS_OK" = 1 ] || return 1
  local out slog
  out="$(timeout 20 python3 "$_SG_PY" item-mistarget "$1" "$2" 2>/dev/null)" || return 1
  [ -n "$out" ] || return 1
  if [ "$mode" = shadow ]; then
    slog="${OVN_STAGE_SHADOW_LOG:-state/stage_guards_shadow.log}"
    mkdir -p "$(dirname "$slog")" 2>/dev/null
    printf '%s item-mistarget(shadow) repo=%s :: %s :: %s\n' "$(date -u +%FT%TZ)" "$(basename "${OVN_STAGE_REPO:-$(basename "$1")}")" "${out:0:200}" "$(printf '%s' "$2" | cut -c1-160)" >> "$slog" 2>/dev/null
    return 1
  fi
  printf '%s' "$out"; return 0
}

# stage_class_conflict <aider output file> -> rc 0 + the offending line when Godot reported a class_name / autoload conflict
stage_class_conflict(){
  [ "${OVN_STAGE_CLASS_CONFLICT:-on}" = off ] && return 1
  local hit
  hit="$(grep -aoE 'Class "[A-Za-z0-9_]+" hides (an autoload singleton|a global script class|a native class)[^"]{0,40}' "$1" 2>/dev/null | head -1)"
  [ -n "$hit" ] || return 1
  printf '%s' "$hit"; return 0
}

# stage_named_tests_check <wt> <vlog> <item> <step lines: "desc<TAB>verify" per landed step> <venv pytest abs path or ""> <pkg dir rel to the repo ("." ok)>
# rc 0 = fine (or shadow / off / nothing promised), rc 1 = a promised test is missing or did not pass (enforce). Failure text is appended to <vlog> as `-- QUALITY FAIL: ...` lines
# (the repair loop feeds those lines to the model); shadow mode writes them to <vlog>.shadow-named instead.
stage_named_tests_check(){
  local mode; mode="$(_sg_mode "${OVN_STAGE_NAMED_TESTS:-}" enforce)"
  [ "$mode" = off ] && return 0
  [ "$_SG_TOOLS_OK" = 1 ] || return 0
  local wt="$1" vlog="$2" item="$3" steps="$4" vpt="${5:-}" pkg="${6:-.}" names="" n line d v res missing node rc out msgs="" nrun=0
  names="$(timeout 20 python3 "$_SG_PY" named-tests-item "$item" 2>/dev/null)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    d="${line%%$'\t'*}"; v="${line#*$'\t'}"; [ "$v" = "$line" ] && v=""
    # a landed STEP's promise is its description only: the plan's `verify` string is the model's guess (it routinely names a test it then writes under another name), the item's own VERIFY is checked above
    names="${names}"$'\n'"$(timeout 20 python3 "$_SG_PY" named-tests "$d" "" 2>/dev/null)"
  done <<< "$steps"
  names="$(printf '%s\n' "$names" | grep -E '^test_[A-Za-z0-9_]+$' | awk '!s[$0]++')"
  [ -n "$names" ] || return 0
  # shellcheck disable=SC2086
  # OVN_SG_CONTEXT = the promise text (item line + landed step descriptions): a test not found whose promise points only at TS / JS / Rust ... test files (languages not read with confidence) is UNVERIFIABLE, never "missing"; Kotlin / Java / Swift are located, so a promised test of those that is defined nowhere IS missing
  res="$(OVN_SG_CONTEXT="${item}"$'\n'"${steps}" timeout 90 python3 "$_SG_PY" resolve-tests "$wt" $names 2>/dev/null)" || return 0
  [ -n "$res" ] || return 0
  missing="$(printf '%s' "$res" | jq -r '.missing | join(" ")' 2>/dev/null)"
  if [ -n "$missing" ]; then
    msgs="${msgs}-- QUALITY FAIL: the change promised test(s) that do not exist in the final tree (never written, or deleted by a repair round): ${missing} - re-add them; a repair must not remove the test it was meant to fix --"$'\n'
  fi
  # run every python node by id: rc 0 = passed; rc 4 / 5 (not found / nothing collected) is a failure, never a pass
  if [ -n "$vpt" ] && [ -x "$vpt" ] && [ -d "$wt/$pkg" ]; then
    while IFS= read -r node; do
      [ -n "$node" ] || continue
      case "$pkg" in .) rel="$node";; *) case "$node" in "$pkg"/*) rel="${node#"$pkg"/}";; *) continue;; esac;; esac
      out="$( cd "$wt/$pkg" && timeout 300 "$vpt" -q -o addopts="" -p no:cacheprovider "$rel" 2>&1 )"; rc=$?
      nrun=$((nrun+1))
      if [ "$rc" -ne 0 ]; then
        msgs="${msgs}-- QUALITY FAIL: promised test ${rel} did not pass when run by node id (rc=${rc}; 4/5 = not found / not collected) --"$'\n'"FAILED ${rel} - $(printf '%s' "$out" | tail -3 | tr '\n' ' ' | cut -c1-240)"$'\n'
      fi
    done < <(printf '%s' "$res" | jq -r '.found[] | select(.kind=="py") | .node' 2>/dev/null | awk '!s[$0]++')
  fi
  [ -n "$msgs" ] || return 0
  if [ "$mode" = shadow ]; then printf '%s' "$msgs" >> "${vlog}.shadow-named" 2>/dev/null; return 0; fi
  printf '%s' "$msgs" >> "$vlog" 2>/dev/null
  return 1
}

# stage_item_verify_run <dir> <item> -> prints RESULT|WHY (PASS FAIL NO_VERIFY_CLAUSE SKIPPED_DENYLIST TIMEOUT UNRUNNABLE) of the item's own VERIFY run from <dir>, via the same shadow_check every credit path uses.
# Its probe rows go to their OWN log (OVN_STAGE_IV_SHADOW_LOG, default state/stage_item_verify_shadow.log), never into verify_gate_shadow.log: the pre-change probe is FAIL by design and would inflate the
# daily digest's verify_shadow red counts
stage_item_verify_run(){
  local dir="$1" item="$2" tmp r rdir vbin=""
  [ -f "$_SG_DIR/lib_verify_clause.sh" ] || { printf 'NO_VERIFY_CLAUSE|lib missing'; return 0; }
  # 2026-10-18 (gitlark landing audit): the stage WORKTREE has no .venv (gitignored), so shadow_check's `find .venv/bin/python` found nothing and a bare `python` clause ran under the box's aider-venv
  # python (no pytest, no jose): every python item VERIFY was FAIL both before AND after the change (`No module named pytest` / `No module named 'jose'`), so the item_verify verdict was noise.
  # Put the REPO clone's venv bin first on PATH for the probe (no tree write, so stage_tree_restore has nothing to undo). OVN_STAGE_REPO_DIR overrides; default repos/<OVN_STAGE_REPO>.
  rdir="${OVN_STAGE_REPO_DIR:-repos/${OVN_STAGE_REPO:-}}"
  if [ -d "$rdir" ]; then
    vbin="$(find -L "$rdir" -maxdepth 4 \( -path '*/.venv/bin/python3' -o -path '*/.venv/bin/python' \) 2>/dev/null | head -1)"
    [ -n "$vbin" ] && vbin="$(cd "$(dirname "$vbin")" 2>/dev/null && pwd)"
  fi
  tmp="$(mktemp)"; printf '%s\n' "- [ ] ${item}" > "$tmp"
  r="$( cd "$dir" 2>/dev/null && {
      set +u
      [ -n "$vbin" ] && export PATH="$vbin:$PATH" VIRTUAL_ENV="${vbin%/bin}"
      PROG="$tmp"; SHADOW_LOG="${OVN_STAGE_IV_SHADOW_LOG:-${HOME}/overnight-queue/state/stage_item_verify_shadow.log}"; _REPO_LABEL="stage-$(basename "${OVN_STAGE_REPO:-repo}")"
      VERIFY_TIMEOUT_SECS="${OVN_STAGE_ITEM_VERIFY_TIMEOUT:-90}"; VERIFY_TIMEOUT_HEAVY_SECS="$VERIFY_TIMEOUT_SECS"; _VC_MEMO=""; _VC_MEMO_ON=0
      mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
      # shellcheck disable=SC1091
      . "$_SG_DIR/lib_verify_clause.sh" 2>/dev/null
      declare -F shadow_check >/dev/null 2>&1 || { printf 'NO_VERIFY_CLAUSE|shadow_check missing'; exit 0; }
      OVN_VERIFY_VENV_FALLBACK="${OVN_VERIFY_VENV_FALLBACK:-${HOME}/overnight-queue/repos/${OVN_STAGE_REPO:-}}"; export OVN_VERIFY_VENV_FALLBACK   # worktree has no .venv: see _resolve_tool_paths
      shadow_check 1 >/dev/null 2>&1
      # P8 (2026-10-26): pytest rc 4/5 (no test collected / usage error: the test the item names does not exist, or the node id is wrong) is an ITEM-vs-SPEC problem, not a code failure, yet it was lumped in
      # with rc 1 as FAIL. OVN_STAGE_IV_RC45=off|shadow|on (default SHADOW): shadow logs `note=rc45-spec-problem would=SPEC_PROBLEM` to the item-verify shadow log and leaves the verdict FAIL; on prints
      # SPEC_PROBLEM (pre = red-expected, post = refused with a distinct reason). rc 1 (real red test) is never reclassified.
      if [ "${OVN_STAGE_IV_RC45:-shadow}" != off ] && [ "${_LAST_VERIFY_RESULT:-}" = FAIL ] && { [ "${_LAST_VERIFY_RC:-}" = 4 ] || [ "${_LAST_VERIFY_RC:-}" = 5 ]; } && case "$item" in *pytest*) true;; *) false;; esac; then
        echo "$(date -u +%FT%TZ) repo=$_REPO_LABEL note=rc45-spec-problem mode=${OVN_STAGE_IV_RC45:-shadow} would=SPEC_PROBLEM rc=${_LAST_VERIFY_RC} why=$(printf '%s' "${_LAST_VERIFY_WHY:-}" | tr -d '\n|' | head -c 80)" >> "$SHADOW_LOG" 2>/dev/null
        if [ "${OVN_STAGE_IV_RC45:-shadow}" = on ]; then printf 'SPEC_PROBLEM|pytest rc=%s %s' "${_LAST_VERIFY_RC}" "$(printf '%s' "${_LAST_VERIFY_WHY:-}" | tr -d '\n|')"; exit 0; fi
      fi
      printf '%s|%s' "${_LAST_VERIFY_RESULT:-NO_VERIFY_CLAUSE}" "${_LAST_VERIFY_WHY:-}"
    } )"
  rm -f "$tmp"
  [ -n "$r" ] || r="NO_VERIFY_CLAUSE|no verdict"
  printf '%s' "$r"
}

# stage_ctx_exceeded <aider output file> -> rc 0 when the 27B context window was blown. 2026-10-18 (xlite audit): the runner's own regex only knew 'context size has been exceeded' / 'context length',
# but litellm reports 'ContextWindowExceededError ... request (73789 tokens) exceeds the available context size (65536 tokens)': three xlite attempts were filed as fail_reason=no-edit, so the
# shrink-and-retry (map/2, drop architect+AGENTS.md) never ran and the same oversized prompt was resent (3 identical overflows per attempt pair, item escalated for the wrong reason).
stage_ctx_exceeded(){ grep -qiE 'context size has been exceeded|context length|context_length|prompt is too long|exceed_context|contextwindowexceeded|exceeds the available context size|exceeds the context (window|size)' "${1:-/dev/null}" 2>/dev/null; }

# 2026-10-20: `test -f X && exit 1 || exit 0` (the absence assertion of every 'Delete the file' item) is a text probe too: TAA token_aggregator.py was re-added by the repair round (pre=FAIL post=FAIL) and still landed credited because this form was not recognised.
# stage_item_verify_textonly <item> -> rc 0 when the item's FIRST backticked VERIFY command is a pure text/file probe (grep / test / [ / !-negated grep), with no runner, interpreter or build tool in it.
# 2026-10-18 (xlite landing audit): such a probe is deterministic and environment-independent, so a RED verdict after the change is a real "the item was not done" - unlike a pytest/gradle/godot
# VERIFY, whose FAIL can be an env gap. The xlite items 'delete generate_intent / intent_label' (a repair round re-added both), 'return "" for unknown directives' and 'if ... directive_label in
# mission_hub.gd' were ticked [x] while their own grep was RED (item_verify decision=refuse, but shadow mode only journals). The runner enforces the RED-after refusal for these (OVN_STAGE_ITEM_VERIFY_TEXT).
stage_item_verify_textonly(){
  local cmd
  cmd="$(printf '%s' "$1" | grep -oE 'VERIFY: `[^`]+`' | head -1 | sed -E 's/^VERIFY: `//; s/`$//')"
  cmd="$(printf '%s' "$cmd" | sed -E 's/ *&& *echo +[A-Za-z0-9_"'"'"']+ *\|\| *echo +[A-Za-z0-9_"'"'"']+ *$//; s/ *&& *echo +[A-Za-z0-9_"]+ *$//; s/ *&& *exit +1 *\|\| *exit +0 *$//')"   # `test ! -f x && echo PASS`: the echo only prints the verdict; 2026-10-18: also `X && echo FAIL || echo PASS` (lib_verify_clause.sh OVN_VERIFY_ECHO_VERDICT re-reads it by X's exit status)
  [ -n "$cmd" ] || return 1
  case "$cmd" in grep\ *|egrep\ *|test\ *|'['\ *|'! grep '*|'!grep '*) ;; *) return 1;; esac
  if printf '%s' "$cmd" | grep -qiE '(^|[^A-Za-z0-9_])(python3?|pytest|godot|gdparse|gradle|gradlew|npm|npx|node|vitest|jest|swift|swiftc|xcodebuild|docker|make|cargo|go|bash|sh|eval|exec|curl|ruby|php|java|kotlinc)([^A-Za-z0-9_]|$)'; then return 1; fi
  case "$cmd" in *'$('*|*'`'*|*';'*|*'&&'*|*'||'*) return 1;; esac
  return 0
}

# stage_layout_listing <wt> -> the "Real source paths" block of the decomposer prompt. 2026-10-18 (gitlark landing audit): the old inline `find ... | sort | head -100` was filled by the
# alphabetically-first 100 files (backend/alembic x26, alembic.backup, backend/app x71) so backend/tests never reached the planner; it invented repo-root `tests/...` paths ("declared file is empty
# - write the full content: tests/test_memory_router.py" x6 in one gitlark run, plus ghost root tests that pytest never collects). Now: migration/backup trees are dropped, source files get 70
# lines (max 25 per directory so one big package cannot crowd out web/ etc.), and every directory that holds test files is listed with its file count so the planner knows where tests live. Bounded (<= ~90 lines).
stage_layout_listing(){
  local wt="$1" all src tdirs
  all="$(cd "$wt" 2>/dev/null && find . -maxdepth 4 \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.vue' -o -name '*.gd' -o -name '*.kt' \) -not -path '*/node_modules/*' -not -path '*/.venv/*' -not -path '*/.godot/*' -not -path '*/alembic*/*' -not -path '*/migrations/*' 2>/dev/null | sed 's#^\./##' | sort)"
  src="$(printf '%s\n' "$all" | grep -vE '(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]*$|_test\.py$|\.(test|spec)\.[a-z]+$' | awk '{d=$0; sub(/\/[^\/]*$/,"",d); if (++n[d] <= 25) print}' | head -70)"
  tdirs="$(printf '%s\n' "$all" | grep -E '(^|/)(tests?|__tests__|spec)/|(^|/)test_[^/]*$|_test\.py$|\.(test|spec)\.[a-z]+$' | sed -E 's#/[^/]*$##' | sort | uniq -c | sort -rn | head -15 | awk '{printf "%s/  (%s test files)\n", $2, $1}')"
  printf '%s\n' "$src"
  [ -n "$tdirs" ] && printf '%s\n%s\n' "Test directories (put NEW tests in one of these existing directories, never in a new repo-root tests/):" "$tdirs"
  return 0
}

# stage_tree_restore <wt> <snapshot of `git status --porcelain -uall` taken before a read-only probe ran> - undo whatever the probe (an item VERIFY run) left behind: untracked files that were not in the
# snapshot are removed, modified tracked files are checked out again. NOT `git clean`: the node_modules / .godot symlinks the runner provisioned are untracked (and not ignored in every repo) and must survive.
stage_tree_restore(){
  local wt="$1" snap="$2" line st path
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case $'\n'"$snap"$'\n' in *$'\n'"$line"$'\n'*) continue;; esac
    st="${line:0:2}"; path="${line:3}"
    case "$path" in \"*) continue;; esac     # a quoted (odd) name: leave it alone
    case "$st" in
      '??') rm -rf -- "${wt:?}/${path%/}" 2>/dev/null ;;
      *)    git -C "$wt" checkout -q -- "$path" 2>/dev/null ;;
    esac
  done < <(git -C "$wt" status --porcelain -uall 2>/dev/null)
  return 0
}

# stage_item_verify_decision <pre RESULT> <post RESULT> -> prints OK | refuse:<reason>. Credit needs the VERIFY RED before (FAIL) and GREEN after (PASS). An indeterminate verdict
# (TIMEOUT / UNRUNNABLE / NO_VERIFY_CLAUSE / SKIPPED_DENYLIST) on either side is "no evidence": OK, exactly as the other credit gates treat it.
stage_item_verify_decision(){
  local pre="${1%%|*}" post="${2%%|*}"
  case "$post" in FAIL) echo "refuse:the item's own VERIFY is RED after the change"; return 0;; esac
  # P8: OVN_STAGE_IV_RC45=on only. After the change the VERIFY still collects NO test (pytest rc 4/5): the item names a test that was not created / a node id that does not resolve. Still not credited, but the
  # reason says it is an item-vs-spec problem. A SPEC_PROBLEM *before* the change is the expected red of a create-the-test item: it falls through to OK.
  case "$post" in SPEC_PROBLEM) echo "refuse:the item's own VERIFY collects no test after the change (pytest rc 4/5): the test it names does not exist - item-vs-spec problem"; return 0;; esac
  # 2026-10-22 (PKG-B): "already GREEN before any step" could be credited as already satisfied (43 refusals in 7d looped items through retries). It loosens credit (a clause like
  # `PROBE && echo FAIL || echo PASS` is PASS before and after), so it is OPT-IN: OVN_STAGE_ITEM_VERIFY_ALREADY_GREEN=credit enables it (caller treats anything not starting `refuse` as credit); default = old refusal.
  case "$pre" in PASS) [ "$post" = PASS ] && {
    if [ "${OVN_STAGE_ITEM_VERIFY_ALREADY_GREEN:-refuse}" != credit ]; then echo "refuse:the item's own VERIFY was already GREEN before any step ran (nothing was red, nothing was fixed)"
    else echo "OK:already-satisfied: the item's own VERIFY was already GREEN before any step ran"; fi
    return 0; };; esac
  echo OK
}

# stage_red_before_check <wt> <base-ref> <vlog> <venv pytest abs path or ""> <pkg> -> rc 0 fine / shadow, rc 1 only in enforce mode when a test the change added PASSES with the source change reverted.
# Prints one line `RB <verdict> <detail>` on stdout for the caller to journal; verdicts: red-ok | weak | skipped-<why>.
stage_red_before_check(){
  local mode; mode="$(_sg_mode "${OVN_STAGE_RED_BEFORE:-}" shadow)"
  [ "$mode" = off ] && return 0
  [ "$_SG_TOOLS_OK" = 1 ] || return 0
  local wt="$1" base="$2" vlog="$3" vpt="${4:-}" pkg="${5:-.}" srcs nodes tmp node rel rc out nfail=0 nrun=0 f
  [ -n "$vpt" ] && [ -x "$vpt" ] || { echo "RB skipped-no-pytest"; return 0; }
  srcs="$(git -C "$wt" diff --name-only "$base..HEAD" -- '*.py' 2>/dev/null | grep -vE '(^|/)(tests?|__tests__)/|(^|/)test_[^/]*$|_test\.py$|(^|/)conftest\.py$')"
  [ -n "$srcs" ] || { echo "RB skipped-no-source-change"; return 0; }
  nodes="$(timeout 30 python3 "$_SG_PY" new-tests "$wt" "$base" 2>/dev/null)"
  [ -n "$nodes" ] || { echo "RB skipped-no-new-python-test"; return 0; }
  tmp="$(mktemp -d /tmp/stage-rb.XXXXXX)" || { echo "RB skipped-mktemp-failed"; return 0; }
  [ -n "$tmp" ] && [ -d "$tmp" ] || { echo "RB skipped-mktemp-failed"; return 0; }   # 2026-10-16: an empty tmp made "$tmp/t" = /t
  : > "$tmp/weak"     # 2026-10-18: absent when every new test failed as it should; `tr < $tmp/weak` then printed "No such file or directory" into the stage log on every healthy run
  if ! git -C "$wt" worktree add -q --detach "$tmp/t" HEAD >/dev/null 2>&1; then rm -rf "$tmp"; echo "RB skipped-worktree-failed"; return 0; fi
  # revert ONLY the non-test python source files of the change to their pre-change state (new files are removed)
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if git -C "$wt" cat-file -e "$base:$f" 2>/dev/null; then git -C "$tmp/t" checkout -q "$base" -- "$f" 2>/dev/null; else rm -f "$tmp/t/$f"; fi
  done <<< "$srcs"
  if [ "$pkg" != "." ] && [ ! -d "$tmp/t/$pkg" ]; then git -C "$wt" worktree remove --force "$tmp/t" >/dev/null 2>&1; rm -rf "$tmp"; echo "RB skipped-no-package-dir"; return 0; fi
  while IFS= read -r node; do
    [ -n "$node" ] || continue
    case "$pkg" in .) rel="$node";; *) case "$node" in "$pkg"/*) rel="${node#"$pkg"/}";; *) continue;; esac;; esac
    out="$( cd "$tmp/t/$pkg" && timeout 180 "$vpt" -q -o addopts="" -p no:cacheprovider "$rel" 2>&1 )"; rc=$?
    nrun=$((nrun+1))
    [ "$rc" -eq 0 ] && { nfail=$((nfail+1)); echo "$rel" >> "$tmp/weak"; }
  done <<< "$nodes"
  git -C "$wt" worktree remove --force "$tmp/t" >/dev/null 2>&1
  local weak; weak="$(tr '\n' ' ' < "$tmp/weak" 2>/dev/null | cut -c1-300)"; rm -rf "$tmp"
  [ "$nrun" -gt 0 ] || { echo "RB skipped-nodes-outside-package"; return 0; }
  if [ "$nfail" -eq 0 ]; then echo "RB red-ok ${nrun} new test(s) fail without the source change"; return 0; fi
  echo "RB weak ${nfail}/${nrun} new test(s) PASS with the source change reverted: ${weak}"
  if [ "$mode" = enforce ]; then
    printf '%s\n' "-- QUALITY FAIL: the test(s) ${weak}pass without the source change - they prove nothing; make them fail on the old behaviour (assert the NEW behaviour) --" >> "$vlog" 2>/dev/null
    return 1
  fi
  return 0
}

# stage_web_verify <wt> <base-ref> <vlog> -> rc 0 fine / shadow / nothing to check, rc 1 only in enforce mode when vue-tsc or vitest-related fails for the changed web files.
# Prints `WEB <verdict> <detail>`; the full output goes to <vlog>.web.log (never into the verify log the repair loop greps, unless enforcing).
stage_web_verify(){
  local mode; mode="$(_sg_mode "${OVN_STAGE_WEB_VERIFY:-}" shadow)"
  [ "$mode" = off ] && return 0
  local wt="$1" base="$2" vlog="$3" changed pj wd rel files f rc_t=0 rc_v=0 ran=0 wl="${3}.web.log" msg=""
  changed="$(git -C "$wt" diff --name-only "$base..HEAD" 2>/dev/null | grep -E '\.(vue|ts|tsx|js|jsx)$')"
  [ -n "$changed" ] || { echo "WEB skipped-no-web-change"; return 0; }
  : > "$wl"
  while IFS= read -r pj; do
    [ -n "$pj" ] || continue
    wd="$(dirname "$pj")"; rel="${wd#"$wt"/}"; [ "$wd" = "$wt" ] && rel="."
    [ -e "$wd/node_modules" ] || continue
    files=""
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if [ "$rel" = "." ]; then files="$files $f"; else case "$f" in "$rel"/*) files="$files ${f#"$rel"/}";; esac; fi
    done <<< "$changed"
    files="${files# }"; [ -n "$files" ] || continue
    ran=1
    if grep -q '"vue-tsc"' "$pj" 2>/dev/null; then
      echo "-- vue-tsc --noEmit in $rel --" >> "$wl"
      ( cd "$wd" && timeout 240 npx vue-tsc --noEmit ) >> "$wl" 2>&1 || rc_t=$?
    fi
    if grep -q '"vitest"' "$pj" 2>/dev/null; then
      echo "-- vitest related in $rel: $files --" >> "$wl"
      # shellcheck disable=SC2086
      ( cd "$wd" && CI=true timeout 240 npx vitest related --run --passWithNoTests $files ) >> "$wl" 2>&1 || rc_v=$?
    fi
  done < <(find "$wt" -maxdepth 3 -name package.json -not -path '*/node_modules/*' 2>/dev/null)
  [ "$ran" = 1 ] || { echo "WEB skipped-no-provisioned-package"; return 0; }
  if [ "$rc_t" -eq 0 ] && [ "$rc_v" -eq 0 ]; then echo "WEB ok vue-tsc and vitest related green"; return 0; fi
  [ "$rc_t" -ne 0 ] && msg="vue-tsc rc=${rc_t}"
  [ "$rc_v" -ne 0 ] && msg="${msg:+$msg, }vitest related rc=${rc_v}"
  echo "WEB red ${msg} (see ${wl##*/})"
  if [ "$mode" = enforce ]; then
    { printf '%s\n' "-- QUALITY FAIL: web verification failed for the changed web files (${msg}) --"; tail -12 "$wl"; } >> "$vlog" 2>/dev/null
    return 1
  fi
  return 0
}

# ---- 2026-10-20 stage-unverified review: delete-handling helpers (pure bash/git, testable on the Mac) ----
# stage_changed_live_files <wt> [range]: files the run ADDED/COPIED/MODIFIED/RENAMED (never deleted ones). The QUALITY "changed test must exercise the changed source" check ran over
# deleted paths too: a run that deleted an orphaned test + its dead source had srcs/tests non-empty, no symbol/route/module to grep in a file that no longer exists, hit=0 ->
# '-- QUALITY FAIL: no changed test exercises the changed source' on a perfectly good deletion (TAA plan_snapshot, 2 runs 10-20; identical delete landed in a third). OVN_STAGE_QUALITY_LIVE_ONLY=off restores the old list.
stage_changed_live_files(){
  local wt="$1" range="${2:-origin/overnight/feature..HEAD}" filt="--diff-filter=ACMR"
  [ "${OVN_STAGE_QUALITY_LIVE_ONLY:-on}" = off ] && filt=""
  # shellcheck disable=SC2086
  git -C "$wt" diff --name-only $filt "$range" 2>/dev/null
}

# stage_item_wants_delete <item text> <repo-relative path>: does the text state an intent to delete exactly file $2? Looks at VERIFY `test ! -f|-e <path>` / `test -f <path> && exit 1`,
# "Delete|Remove the file|module [entirely|<path>]", "Delete <path>" and (2026-10-20) "Delete ... file <path>" (planner step descs such as "Delete the orphaned test file <path>").
# The caller may pass item + step desc + step VERIFY joined by newlines.
stage_item_wants_delete(){
  local itm="$1" p="$2" head line
  head="$(printf '%s' "$itm" | sed -E 's/VERIFY:.*$//')"
  case "$itm" in *"test ! -f $p"*|*"test ! -e $p"*|*"[ ! -f $p ]"*|*"test -f $p && exit 1"*|*"test -e $p && exit 1"*) return 0;; esac
  printf '%s' "$head" | grep -qiE "(delete|remove)[[:space:]]+(the[[:space:]]+)?(file|module)([[:space:]]+entirely)?([[:space:]]|\.|,|$)" && case "$head" in *"$p"*) return 0;; esac
  printf '%s' "$head" | grep -qiF -- "delete $p" && return 0
  while IFS= read -r line; do
    case "$line" in *[Dd]elete*[[:space:]]file[[:space:]]*"$p"*|*[Rr]emove*[[:space:]]file[[:space:]]*"$p"*) return 0;; esac
  done <<< "$head"
  return 1
}

# stage_pure_delete_paths <wt> <step desc> <step files> <item> <step verify>: tracked paths a step must DELETE, one per line. aider cannot delete a file ("I can't directly delete files"):
# a planner step 'Delete truncate.py and add a test asserting its absence' wrote only the test, was recorded verdict:pass, and died at the final verify (TAA 10-20, 5 stage-unverified rows).
# Emitted only when ALL hold: the desc starts with Delete/Remove, it names the path (full path or basename), the path is tracked in HEAD, and the step/item VERIFY itself asserts absence
# (`test ! -f p` / `test -f p && exit 1`) - so this can never delete a file the item did not ask to lose. OVN_STAGE_PURE_DELETE=off disables.
stage_pure_delete_paths(){
  [ "${OVN_STAGE_PURE_DELETE:-on}" = off ] && return 0
  local wt="$1" desc="$2" files="$3" item="$4" verify="$5" p b be
  printf '%s' "$desc" | grep -qiE '^[[:space:]]*(delete|remove)\b' || return 0
  for p in $files; do
    [ -n "$p" ] && git -C "$wt" cat-file -e "HEAD:$p" 2>/dev/null || continue
    b="${p##*/}"
    case "$desc" in *"$p"*|*"$b"*) : ;; *) continue;; esac
    be="$(printf '%s' "$b" | sed -E 's/[][\.^$*+?(){}|\\/]/\\&/g')"
    if printf '%s\n%s' "$verify" "$item" | grep -qE "test[[:space:]]+(![[:space:]]+)?-[fe][[:space:]]+[^[:space:]]*${be}([[:space:]]|\"|'|\`|;|&|$)"; then
      printf '%s\n' "$p"
    fi
  done
}
