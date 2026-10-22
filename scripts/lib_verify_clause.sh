#!/usr/bin/env bash
# scripts/lib_verify_clause.sh - the item-VERIFY runner shared by ovn_credit_already_satisfied.sh and the runner's auto-credit
# (lib_auto_credit.sh), 2026-10-02. Moved VERBATIM out of ovn_credit_already_satisfied.sh (its calibration history is in that
# script's header); sourcing it from there is behavior-neutral. Callers set, before calling shadow_check:
#   PROG          the progress file holding the item line
#   SHADOW_LOG    where PASS/FAIL/NO_VERIFY_CLAUSE/SKIPPED_DENYLIST rows are appended
#   _REPO_LABEL   label for the log rows
# shadow_check <line-number> runs the item's own `VERIFY: `<cmd>`` clause (denylist + real-redirect refusal, venv/godot/gradlew tool-path
# resolution, timeout, stdin from /dev/null) from the CURRENT directory and sets _LAST_VERIFY_RESULT to
#   PASS | FAIL | NO_VERIFY_CLAUSE | SKIPPED_DENYLIST | TIMEOUT | UNRUNNABLE
# TIMEOUT (rc=124) and UNRUNNABLE (rc 126/127, or a gradlew the repo does not have) are INDETERMINATE, not FAIL: the command never produced a verdict
# (harness-X X-a, 2026-10-02: the box shadow log had 50 rc=124 rows in 592 and 6 of 9 gradlew rows "FAIL" purely from the 60s cap).
# Timeouts (seconds), read from the CALLER's scope so a caller can raise them with `local`; defaults keep the historical 60s for every caller that sets nothing:
#   VERIFY_TIMEOUT_SECS        (default 60)   every clause
#   VERIFY_TIMEOUT_HEAVY_SECS  (default = VERIFY_TIMEOUT_SECS)  clauses _verify_is_heavy() recognises (gradlew/xcodebuild/mvn/npm run build/vitest/full pytest ...)
# Godot GUT (2026-10-03, integrity A6): a `gut_cmdln` clause WITHOUT -gexit never quits (xlite: 3 x 900s VERIFY hangs in one cycle), so -gexit is appended
# right after the gut_cmdln.gd token; a NARROWED run (-gtest / -gselect / -gunit_test_name) gets OVN_VERIFY_GUT_NARROW_SECS (default 120) instead of the
# heavy cap; and because GUT exits 0 even when tests FAIL, a GUT clause only PASSes when its output has no "Failing Tests N>0" / "[Failed]" and (when the
# clause writes a junit xml) the xml is green (scripts/lib_gut_xml.sh). Within ONE auto-credit call identical VERIFY commands run once (_VC_MEMO_ON=1).
# After a call: _LAST_VERIFY_RC, _LAST_VERIFY_TIMEOUT (the cap that applied), _LAST_VERIFY_WHY (one-line reason for TIMEOUT/UNRUNNABLE).
# 2026-10-10 (harness R10): a bare `VERIFY: <cmd>[.] (cat:` clause (no backticks) is READ too when ovn_spec_rules.bare_verify accepts it (OVN_VERIFY_BARE_FALLBACK=off disables;
# _LAST_VERIFY_BARE=1 marks such a verdict), and a GUT clause that calls addons/gut/cli/gut_cli.gd is rewritten to gut_cmdln.gd before it runs (OVN_VERIFY_GUT_CLI_REWRITE=off).
# spec-compiler-v2 (2026-10-09), both with kill switches:
#   B1 GUT with a missing -gtest target prints "[ERROR]: Could not find script", then runs the WHOLE suite (391 scripts, 2987 tests) and exits 0 - shadow_check
#      returned PASS and every xlite "create test file X" item looked already satisfied. Now FAIL, _LAST_VERIFY_WHY="GUT target missing".
#      OVN_GUT_MISSING_TARGET=fail|ignore (default fail).
#   B2 pytest `path::name` that exits rc=4 (not found; a class-based test is only addressable as path::Class::name) is resolved by collecting the file and
#      retried ONCE as the fully qualified id (`path::Class::name`) - only on an EXACT name match (never a -k substring match). rc=5 / "no tests ran" is a FAIL with _LAST_VERIFY_WHY="no tests collected". OVN_VERIFY_NODEID_FALLBACK=off disables the retry.
# R14 verify package (2026-10-12):
#   X1 POLARITY: the VERIFY contract is "exit 0 = pass", but items state absence checks as `cmd` + prose ("returns no matches", "fails with No such file", "returns false"). rc==0 there
#      means the thing is STILL PRESENT. shadow_check now reads the stated polarity (ovn_backlog_eligibility.verify_polarity via ovn_credit_items.py polarity) and, for `neg`, maps the exit
#      status: grep-family PASS iff rc==1 (rc>=2 is an error, never an absence), ls/test/stat/cat/find PASS iff rc is non-zero (not 124/126/127). Unknown / pos polarity: unchanged.
#      Every credit path goes through shadow_check, so one place fixes them all. OVN_VERIFY_POLARITY=off restores the old reading. Rows get ` polarity=neg`.
#   X2 GUT: _verify_normalize_gut rewrites clauses GUT cannot execute (-gdir=<file>.gd, bare -gtest=<name>.gd, -gselect=<function>) via ovn_gut_clause.py before they run, and a run that
#      reports "Nothing was run" is a FAIL (a nonexistent -gunit_test_name exits 0). OVN_GUT_CLAUSE_NORMALIZE=off disables both.
# 2026-10-13 (package verify-credit-runner, night review N4): credit-time VERIFY refused landed green work for ENVIRONMENT reasons, not item reasons.
#   A  _verify_py_root: a python/pytest clause ran with the venv python from the repo root and no PYTHONPATH, so `from backend.app.services.auth import x` (auth.py itself does
#      `from app.persistence import ...`) and a billwatch `pytest tests/test_x.py::t` (file lives in billwatch-backend/tests; the legacy ROOT tests/conftest.py does `from app.database import Base`)
#      died with ModuleNotFoundError: No module named 'app' - while the cycle's own .ovn-verify.sh (which sets the right root) was green. The project root is derived from the venv path the
#      runner already resolves (<root>/.venv/bin/python -> <root>; else the first of backend/ billwatch-backend/ iptv-backend/ that exists): the clause is run EXACTLY as before first; only a FAIL whose output is an import / missing-path error
#      (ModuleNotFoundError, ImportError, 'file or directory not found') is re-run ONCE with PYTHONPATH <root>:<repo> APPENDED to any existing value, and a relative tests/ path that is missing at
#      the cwd but present under <root> runs from <root>; that result is adopted (note=py-root-retry row). A retry, not a default, so no clause that passes today can flip (a root package
#      like billwatch-backend/alembic/ shadows the installed library on PYTHONPATH). ON; OVN_VERIFY_PY_ROOT=off restores the old run.
#   C  pytest `path::name` where `name` is only a PREFIX of the real test names (test_find_stale_run_ids vs test_find_stale_run_ids_returns_old_running_runs): exact node ids never match a
#      superstring (rc 4 'not found'). OVN_VERIFY_PYTEST_K_FALLBACK=shadow (DEFAULT) runs ONE `path -k name` retry only when the file exists and logs a `note=pytest-k-fallback` row
#      (never credits); =on adopts the retry result (label _LAST_VERIFY_WHY=name-substring, ` why=name-substring` on the PASS/FAIL row); =off disables. It loosens credit, hence shadow.

# AUDIT for the py-root retry (see above): one alerts.log line per FAIL->PASS adoption. item = progress line number + a cksum of the item's line text (the credit path has no item id).
_verify_py_root_audit(){   # <line> <root> <clause> <prog> <orig_rc>
  local _al _item _ts
  _al="${OVN_VERIFY_ALERTS_LOG:-$(dirname "${SHADOW_LOG:-$HOME/overnight-queue/state/verify_gate_shadow.log}")/alerts.log}"
  _item="$1:$(sed -n "$1p" "$4" 2>/dev/null | cksum | cut -d' ' -f1)"
  _ts="$(date '+%F %T')"
  mkdir -p "$(dirname "$_al")" 2>/dev/null
  echo "$_ts info | py-root-retry | ${_REPO_LABEL:-repo} item=${_item} FAIL->PASS under project root $2 (orig_rc=$5; OVN_VERIFY_PY_ROOT=off refuses it) clause=$(printf '%s' "$3" | head -c 200)" >> "$_al" 2>/dev/null
  return 0
}

# Substitute a nearby repo .venv's python for a bare `python`/`python3` token, so a
# VERIFY clause that omits the .venv/ prefix (some do, some don't - an authoring
# inconsistency, not something this shadow check should mistake for a false credit)
# runs with the repo's actual installed deps instead of whatever's on PATH.
_resolve_tool_paths(){
  local cmd="$1" vpy vpytest vgradlew cddir="."

  # godot: never resolvable bare on this box (verified: no symlink/alias/PATH
  # entry anywhere, including a login shell) - the real pipeline always uses
  # $HOME/godot/godot4. Substitute unconditionally when present as a bare
  # command word (start of string, or after && / ;).
  cmd="$(printf '%s' "$cmd" | sed -E "s#(^|&& |; )godot #\1${HOME}/godot/godot4 #g")"

  # If the command starts with "cd <dir> && ...", resolve venv search from
  # THAT directory - it's where the rest of the command actually runs, and
  # it's also where a "cd backend && ./backend/.venv/..." double-prefix
  # mistake needs to be searched from to self-heal (searching from repo root
  # would just re-find the same non-existent nested path).
  case "$cmd" in
    "cd "*" && "*) cddir="$(printf '%s' "$cmd" | sed -E 's#^cd ([^ ]+) && .*#\1#')" ;;
  esac

  # 2026-09-27 FIX (round 3): two real gaps found in live shadow data even
  # after round 2's fix.
  #   (1) `find` without `-L` cannot descend into a SYMLINKED .venv at all -
  #       it never even attempts to read what the link points to, so a repo
  #       whose .venv is (correctly, by design) a symlink got zero matches
  #       here regardless of whether the symlink target was actually healthy.
  #       Confirmed live on iptv_apps: `.venv -> .../.venv` is a symlink even
  #       in its intended-healthy shape, not just when self-corrupted. `-L`
  #       fixes the general case; a genuinely BROKEN symlink still correctly
  #       yields no match either way (out of scope here - that corruption bug
  #       is tracked separately, not something this checker should paper over).
  #   (2) $vpy was being substituted back into the command as the SAME
  #       relative-to-repo-root path `find` returned (e.g. "backend/.venv/bin/
  #       python3") even when the command already had a "cd backend && "
  #       prefix - after that cd, that path is interpreted relative to
  #       backend/, silently doubling to a nonexistent "backend/backend/.venv/
  #       ...". Converting to an ABSOLUTE path once, right after finding it,
  #       makes the substitution correct regardless of any cd prefix already
  #       in the command - the actual root fix, not another special case for
  #       one more path shape.
  vpy="$(find -L "$cddir" -maxdepth 4 \( -path '*/.venv/bin/python3' -o -path '*/.venv/bin/python' \) 2>/dev/null | head -1)"
  if [ -n "$vpy" ]; then
    vpy="$(cd "$(dirname "$vpy")" 2>/dev/null && pwd)/$(basename "$vpy")"
    # Authoritatively replace ANY existing venv-python path reference (correct
    # or not) plus any bare python/python3 token with the one just verified to
    # actually exist - a no-op if the text was already right, a self-heal if
    # it wasn't (e.g. a duplicated "backend/backend/.venv" segment).
    cmd="$(printf '%s' "$cmd" | sed -E "s#[./A-Za-z0-9_-]*\.venv/bin/python3?#${vpy}#g; s#(^|&& |; )python3? #\1${vpy} #g")"
  fi

  # 2026-10-18 (test-automation-agent audit): a stage worktree has no .venv (gitignored), so bare `pytest` died rc=127 "command not found" and every
  # pytest item-verify row was UNRUNNABLE (decision no-evidence). OVN_VERIFY_VENV_FALLBACK=<fleet repo dir> (set only by stage_item_verify_run) lets
  # the search fall back to the live clone's venv; the clause still runs in the worktree cwd, against the worktree's code.
  if [ -z "$(find -L "$cddir" -maxdepth 4 -path '*/.venv/bin/pytest' 2>/dev/null | head -1)" ] && [ -n "${OVN_VERIFY_VENV_FALLBACK:-}" ] && [ -d "$OVN_VERIFY_VENV_FALLBACK" ]; then
    vpytest="$(find -L "$OVN_VERIFY_VENV_FALLBACK" -maxdepth 4 -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
  else
    vpytest="$(find -L "$cddir" -maxdepth 4 -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
  fi
  if [ -n "$vpytest" ]; then
    vpytest="$(cd "$(dirname "$vpytest")" 2>/dev/null && pwd)/$(basename "$vpytest")"
    cmd="$(printf '%s' "$cmd" | sed -E "s#[./A-Za-z0-9_-]*\.venv/bin/pytest#${vpytest}#g; s#(^|&& |; )pytest #\1${vpytest} #g")"
  fi

  # (3) `./gradlew` VERIFY clauses are authored assuming the repo root as cwd,
  # but this checker's own cwd is wherever it was invoked from and may not be
  # the actual repo root, or a "cd <subdir> &&" prefix may have moved it
  # elsewhere first - confirmed live on billwatch (3 distinct FAILs, "No such
  # file or directory"). Find the real gradlew and always substitute an
  # absolute path, same self-healing approach as the python/pytest case above.
  case "$cmd" in
    *gradlew*)
      vgradlew="$(find . -maxdepth 3 -name gradlew -type f 2>/dev/null | head -1)"
      if [ -n "$vgradlew" ]; then
        local vgdir gargs
        vgdir="$(cd "$(dirname "$vgradlew")" 2>/dev/null && pwd)"
        # gradlew must run with ITS OWN project directory as $PWD (it looks for
        # settings.gradle/build.gradle relative to the CURRENT directory, not
        # relative to the script's own location on disk) - unlike the python/
        # pytest case above, substituting an absolute path in place isn't
        # enough (confirmed live: BUILD FAILED, missing settings.gradle,
        # because it ran from the repo root instead of the android subdir).
        # Extract everything after the LAST gradlew token (the real args,
        # dropping any existing likely-wrong "cd ... &&" prefix) and rebuild.
        gargs="$(printf '%s' "$cmd" | sed -E 's#^.*gradlew##')"
        cmd="cd ${vgdir} && ./gradlew${gargs}"
      fi
      ;;
  esac

  printf '%s' "$cmd"
}

# True (0) if $1 contains a redirect to something other than /dev/null (a real
# destructive write this shadow check should refuse to execute), false (1) if the
# only redirects present are the standard `>/dev/null` / `2>/dev/null` idiom.
_has_real_redirect(){
  local stripped
  stripped="$(printf '%s' "$1" | sed -E 's/[0-9]*>>?[[:space:]]*\/dev\/null//g')"
  case "$stripped" in
    *">"*) return 0 ;;
    *) return 1 ;;
  esac
}

# True (0) when the VERIFY command is a slow test/build runner: gradlew, xcodebuild, mvn, `npm run build`, `npm test`, vitest/jest, Godot GUT, or a pytest run that
# is NOT narrowed (also a Godot GUT run, `gut_cmdln`: first-time import can take minutes) (no -k and no explicit test file/node id). A narrowed pytest (`-k name`, `tests/test_x.py`, `file::test`) is NOT heavy.
_verify_is_heavy(){
  local c="$1"
  case "$c" in
    *gradlew*|*xcodebuild*|*"mvn "*|*"npm run build"*|*"npm test"*|*"npm run test"*|*vitest*|*gut_cmdln*|*"jest "*|*"npx jest"*|*"yarn build"*|*"yarn test"*) return 0 ;;
  esac
  case "$c" in
    *pytest*)
      case "$c" in
        *" -k "*|*" -k="*|*" -k'"*|*'-k"'*|*"::"*|*".py"*) return 1 ;;
      esac
      return 0 ;;
  esac
  return 1
}

_VC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib_gut_xml.sh
[ -f "$_VC_DIR/lib_gut_xml.sh" ] && . "$_VC_DIR/lib_gut_xml.sh"
declare -F gut_xml_green >/dev/null 2>&1 || gut_xml_green(){ return 0; }   # lib missing: the xml check simply does not add a verdict

# append -gexit to a godot gut_cmdln clause that lacks it (prints the command unchanged for anything else)
_verify_fix_gut_exit(){
  local c="$1"
  case "$c" in
    *gut_cmdln*)
      case "$c" in *-gexit*) ;; *) c="$(printf '%s' "$c" | sed -E 's#(gut_cmdln\.gd)#\1 -gexit#')" ;; esac ;;
  esac
  printf '%s' "$c"
}
_verify_is_gut(){ case "$1" in *gut_cmdln*) return 0;; esac; return 1; }
# 2026-10-16 (overnight review, xlite): the roadmap writes a bare `gut -gdir=tests -gselect=... -gexit` shorthand. No `gut` binary exists on the box (rc 127 on every run, 50 UNRUNNABLE rows
# in one night), so the clause could never PASS and an ALREADY-DONE scout credit ran on an UNRUNNABLE verdict. The command word `gut` (at the start of the clause or after ; && || |)
# becomes the GUT entry point, so the existing -gexit and -gdir/-gtest/-gselect repairs apply. OVN_GUT_ALIAS=off disables. `cd gut`, `gut_cmdln` and `grep gut` are untouched.
_verify_gut_alias(){
  local c="$1"
  case "$c" in *gut_cmdln*) printf '%s' "$c"; return 0 ;; esac
  if [ "${OVN_GUT_ALIAS:-on}" = off ]; then printf '%s' "$c"; return 0; fi
  printf '%s' "$c" | sed -E 's/(^|[;&|][[:space:]]*)gut([[:space:]])/\1godot --headless -s addons\/gut\/gut_cmdln.gd\2/g'
}
# X2: prints the clause with GUT shapes that can never run rewritten (ovn_gut_clause.py); prints it unchanged for a non-GUT clause, when OVN_GUT_CLAUSE_NORMALIZE=off, or on any error.
# The project root is the cwd (or the target of a leading `cd X &&`).
_verify_normalize_gut(){
  local c="$1" base="." out
  # 2026-10-13 (intake package, F4/P8): also shapes that cannot run AT ALL and that are not GUT-runner calls: a `/path/to/<repo>` placeholder cd, and `[cd D &&] godot -s <GutTest>.gd`
  # (a GUT test is not a SceneTree script). ovn_gut_clause.normalize decides (it leaves everything else untouched); this only decides whether to ask it. Same kill switch.
  if [ "${OVN_GUT_CLAUSE_NORMALIZE:-on}" = off ] || [ ! -f "$_VC_DIR/ovn_gut_clause.py" ]; then printf '%s' "$c"; return 0; fi
  local _gs_re='godot[^;&|]*[[:space:]](-s|--script)[[:space:]=]'
  if ! _verify_is_gut "$c" && [[ "$c" != */path/to/* ]] && ! [[ "$c" =~ $_gs_re ]]; then printf '%s' "$c"; return 0; fi
  # the project root is the cwd (or the target of a leading `cd X &&`) - for a GUT runner call only: any other shape is judged from the cwd
  if _verify_is_gut "$c"; then
    case "$c" in "cd "*) base="$(printf '%s' "$c" | sed -E 's/^cd +([^ ;&]+).*/\1/')"; [ -d "$base" ] || base="." ;; esac
  fi
  out="$(printf '%s' "$c" | timeout 20 python3 "$_VC_DIR/ovn_gut_clause.py" normalize "$base" 2>/dev/null)" || out=""
  if [ -n "$out" ]; then printf '%s' "$out"; else printf '%s' "$c"; fi
}
_verify_is_narrow_gut(){ _verify_is_gut "$1" || return 1; case "$1" in *-gtest*|*-gselect*|*-gunit_test_name*) return 0;; esac; return 1; }
_verify_is_pytest(){ case "$1" in *pytest*) return 0;; esac; return 1; }
# P5 (2026-10-21, shadow evidence): which non-0 outcomes are UNRUNNABLE (the command never produced a verdict about the item) rather than a real FAIL. Prints a kind or nothing.
#   rc126/rc127 (not executable / not found), npx-tsc-missing (npx prints "To get access to the TypeScript compiler" and exits 1 when typescript is not installed),
#   module-not-found-clause (a `python -c` clause whose OWN traceback, File "<string>", ends in ModuleNotFoundError: an import root that does not exist from this cwd).
# LOG-ONLY: shadow_check logs these rows as result=UNRUNNABLE why=<kind> so FAIL counts stop including them, but _LAST_VERIFY_RESULT stays FAIL (no decision changes).
# OVN_VERIFY_UNRUNNABLE_SHAPES=off restores the old FAIL rows.
_verify_unrunnable_kind(){  # $1=rc $2=cmd $3=output
  local _rc="$1" _cmd="$2" _o="$3"
  [ "$_rc" -eq 0 ] 2>/dev/null && return 0
  case "$_rc" in 126|127) printf 'rc%s' "$_rc"; return 0;; esac
  if grep -aq 'To get access to the TypeScript compiler' <<< "$_o"; then printf 'npx-tsc-missing'; return 0; fi
  if [[ "$_cmd" =~ (^|[[:space:]/])python[0-9.]*[[:space:]]+(-[A-Za-z]+[[:space:]]+)*-c([[:space:]]|$) ]] && grep -aq 'ModuleNotFoundError' <<< "$_o" && grep -aEq 'File "<string>", line [0-9]+' <<< "$_o"; then
    printf 'module-not-found-clause'; return 0
  fi
  return 0
}
# B2: replace the first occurrence of the literal $2 in the command $1 by $3 (sed with `|` delimiter; bash 3.2 safe: no ${var/pat/rep} with quoted patterns). $2 is a node-id token
# ([A-Za-z0-9_./:-]), $3 is a space separated list of such tokens, so neither can contain `|`, `&` or `\`.
_verify_replace_first(){
  local c="$1" from="$2" to="$3" esc
  esc="$(printf '%s' "$from" | sed 's/\./\\./g')"   # the only regex metacharacter a node-id token can contain is `.`
  printf '%s' "$c" | sed "s|${esc}|${to}|"
}
# B2: a pytest node id `a/b.py::name` that rc=4'd (class-based tests are only addressable as a/b.py::Class::name) is resolved by COLLECTING the file (`--collect-only -q`) and
# accepting only an EXACT match: a collected id whose segments after the path equal `name` or end with `::name` (a trailing [param] id is ignored). A substring match is NOT
# a match (`-k test_foo` selects test_foo_bar, which would credit an unimplemented "add test_foo" item). On a match it prints the command with the node id replaced by the
# fully qualified collected id(s) (so only those tests run); it prints nothing when there is no exact match or the command has no node id. $2 = timeout seconds.
_verify_nodeid_fallback_cmd(){
  local c="$1" tmo="${2:-60}" tok path name ccmd cout line first cfile id idrest ids="" rep
  _verify_is_pytest "$c" || return 0
  tok="$(printf '%s' "$c" | grep -oE '[A-Za-z0-9_./-]+\.py::[A-Za-z0-9_:.-]+' | head -1)"
  [ -n "$tok" ] || return 0
  path="${tok%%::*}"; name="${tok#*::}"
  [ -n "$name" ] || return 0
  # the collection command: same command, node id -> its file, verbosity flags dropped, `--collect-only -q` (one `file::Class::name[param]` id per line)
  ccmd="$(_verify_replace_first "$c" "$tok" "$path" | sed -E 's/ -(q+|v+)( |$)/ /g; s/ -(q+|v+)( |$)/ /g')"
  cout="$(_verify_run "$tmo" "$ccmd --collect-only -q")" || true
  while IFS= read -r line; do
    first="${line%% *}"
    case "$first" in
      *::*) ;;
      *) continue ;;
    esac
    # 2026-10-22 (PKG-B): with a rootdir/pytest.ini below the cwd (test-automation-agent + gitlark: backend/pytest.ini) pytest prints ids RELATIVE TO THE ROOTDIR (`tests/t.py::T::m` for the
    # clause path `backend/tests/t.py`). Accept a collected file part that equals the clause path or is a path-component suffix of it, and rebuild the retry id from the ORIGINAL path.
    # OVN_VERIFY_NODEID_FALLBACK=off (the existing kill switch) still disables the whole fallback; OVN_VERIFY_NODEID_ROOTDIR=off restores the exact-path-only match.
    cfile="${first%%::*}"
    if [ "$cfile" != "$path" ]; then
      [ "${OVN_VERIFY_NODEID_ROOTDIR:-on}" = off ] && continue
      case "$path" in */"$cfile") ;; *) continue ;; esac
    fi
    id="${first%%\[*}"; idrest="${id#*::}"; id="$path::$idrest"
    if [ "$idrest" = "$name" ] || case "$idrest" in *"::$name") true ;; *) false ;; esac; then
      case "
$ids
" in
        *"
$id
"*) ;;
        *) ids="${ids:+$ids
}$id" ;;
      esac
    fi
  done <<< "$cout"
  [ -n "$ids" ] || return 0
  rep="$(printf '%s' "$ids" | tr '\n' ' ' | sed 's/ $//')"
  _verify_replace_first "$c" "$tok" "$rep"
}
# B1b: 0 (true) when a GUT clause's -gdir=<dir>[,<dir>...] names a FILE-LIKE path (it ends in `.gd`: a test file passed where a directory belongs) that does not exist (relative to the
# cwd = the project root, `res://` stripped; also tried under a leading `cd X &&` / `--path X`). GUT then reports nothing wrong and the run exits 0 (live xlite item:
# `-gdir=res://test/battle/test_overwatch.gd`, a file that never existed, came back passes-before) - the target is not there, same class as the -gtest hole.
# Deliberately NOT flagged: a plain nonexistent directory (`-gdir=res://tests`): the existing test_run_integrity_lib fixtures run a stub godot against an empty tree with exactly
# that clause and expect PASS; flagging directories needs that fixture to create the directory first (left to the owner of that suite).
_verify_gut_gdir_missing(){
  local c="$1" spec ent base="" bases=. b found
  spec="$(printf '%s' "$c" | grep -oE -- '-gdir=[^ ]+' | head -1 | sed 's/^-gdir=//; s/["'"'"']//g')"
  [ -n "$spec" ] || return 1
  case "$c" in "cd "*) base="$(printf '%s' "$c" | sed -E 's/^cd +([^ ;&]+).*/\1/')"; [ -n "$base" ] && bases="$bases $base" ;; esac
  base="$(printf '%s' "$c" | grep -oE -- '--path[= ][^ ]+' | head -1 | sed -E 's/^--path[= ]//; s/["'"'"']//g')"
  [ -n "$base" ] && bases="$bases $base"
  local IFS_OLD="$IFS"; IFS=,
  for ent in $spec; do
    IFS="$IFS_OLD"
    ent="${ent#res://}"
    case "$ent" in *.gd) ;; *) continue ;; esac
    found=0
    for b in $bases; do [ -e "$b/$ent" ] && { found=1; break; }; done
    if [ "$found" = 0 ]; then IFS="$IFS_OLD"; return 0; fi
    IFS=,
  done
  IFS="$IFS_OLD"
  return 1
}
# 0 (true) when GUT output reports failures. Real GUT 9.4.0 output (captured on the box): the summary is "  Failing         1" (printed only when
# non-zero, no word "Tests") and each detail line is ANSI-coloured: ESC[31m    [Failed]:  ... - so strip ANSI first. Older/other layouts kept:
# "Failing Tests  N", "---- N failing tests ----".
_verify_gut_output_failed(){
  local esc; esc="$(printf '\033')"
  if [ "${OVN_GUT_CLAUSE_NORMALIZE:-on}" != off ] && grep -aq 'Nothing was run' <<< "$1"; then return 0; fi   # X2: a nonexistent -gunit_test_name / empty selection exits 0 having run nothing
  printf '%s' "$1" | sed "s/${esc}\\[[0-9;]*[A-Za-z]//g" | grep -aEq 'Failing Tests[[:space:]]+[1-9][0-9]*|^[[:space:]]*Failing[[:space:]]+[1-9][0-9]*|\[Failed\]:|^[[:space:]]*\* *\[Failed\]|-+ *[1-9][0-9]* failing tests? *-+'
}
# the junit xml a clause asks for (-gjunit_xml_file=res://x.xml or a plain path), resolved against the cwd; empty when none exists
_verify_gut_xml_path(){
  local c="$1" p
  p="$(printf '%s' "$c" | grep -oE -- '-gjunit_xml_file=[^ ]+' | head -1 | sed 's/^-gjunit_xml_file=//; s/["'"'"']//g')"
  [ -n "$p" ] || return 0
  p="${p#res://}"
  [ -f "$p" ] && printf '%s' "$p"
}

# ---- A: project root for python/pytest clauses (package verify-credit-runner) ----
# CREDIT DECISION (2026-10-14, review finding): unlike the -k fallback (C, shadow by default), this retry is ADOPTED by default (OVN_VERIFY_PY_ROOT=on). It can turn a FAIL into a PASS, but only
# for a clause that failed with an import/missing-path error and passes under the project root - the same tree the repo's own gates import from. Kept on deliberately: shadowing it would
# bring back the false REFUSED credits it was written to fix (billwatch/iptv ModuleNotFoundError). Set OVN_VERIFY_PY_ROOT=off to refuse such clauses again.
# _verify_py_root <cmd>: prints the absolute project root a python/pytest clause should import from, or nothing (not a python clause, kill switch, no candidate). The cwd is the repo root.
_verify_py_root(){
  local c="$1" repo vpath root="" cand
  [ "${OVN_VERIFY_PY_ROOT:-on}" = off ] && return 0
  case "$c" in *python*|*pytest*) ;; *) return 0 ;; esac
  repo="$(pwd)"
  vpath="$(printf '%s' "$c" | grep -oE '[^ "'"'"'=]*/\.venv/bin/(python3?|pytest)' | head -1)"
  if [ -n "$vpath" ]; then
    root="${vpath%/.venv/bin/*}"
    case "$root" in /*) ;; *) root="$repo/$root" ;; esac
    [ -d "$root" ] || root=""
    [ "$root" = "$repo" ] && root=""   # a repo-root venv says nothing about the package root
  fi
  if [ -z "$root" ]; then
    for cand in backend billwatch-backend iptv-backend; do
      if [ -d "$repo/$cand" ]; then root="$repo/$cand"; break; fi
    done
  fi
  [ -n "$root" ] && printf '%s' "$root"
  return 0
}
# _verify_py_cwd <cmd> <root>: prints <root> when the clause names a relative tests/ path that does NOT exist at the cwd but DOES under <root> (and the clause does not cd by itself)
_verify_py_cwd(){
  local c="$1" root="$2" p
  [ -n "$root" ] || return 0
  case "$c" in "cd "*) return 0 ;; esac
  p="$(printf '%s' "$c" | grep -oE '(^|[ =])tests/[A-Za-z0-9_./-]*' | head -1 | sed -E 's/^[ =]//')"
  [ -n "$p" ] || return 0
  if [ ! -e "$p" ] && [ -e "$root/$p" ]; then printf '%s' "$root"; fi
  return 0
}
# _verify_py_import_failure <output>: rc 0 when a failed clause's output says an import or a path could not be resolved (the only failures the project-root retry can change)
_verify_py_import_failure(){
  printf '%s' "$1" | grep -aEq 'ModuleNotFoundError|ImportError|No module named|ERROR: file or directory not found|file or directory not found'
}
# the root/PYTHONPATH decided for the clause being judged (set by shadow_check, read by _verify_run)
_VPY_PP=""; _VPY_CD=""
# _verify_run <timeout> <cmd>: the one place a VERIFY clause is executed (stdout+stderr, stdin from /dev/null, CI=true). Without a python root it is byte-for-byte the old call.
_verify_run(){
  local tmo="$1" c="$2"
  if [ -n "$_VPY_PP" ] || [ -n "$_VPY_CD" ]; then
    (
      if [ -n "$_VPY_CD" ]; then cd "$_VPY_CD" || exit 127; fi
      if [ -n "$_VPY_PP" ]; then export PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}$_VPY_PP"; fi
      CI=true timeout "$tmo" bash -c "$c" 2>&1 </dev/null
    )
  else
    CI=true timeout "$tmo" bash -c "$c" 2>&1 </dev/null
  fi
}
# ---- C: `path::name` where name is a prefix/substring of the real test names ----
# _verify_k_fallback_cmd <cmd>: prints the clause with the first `file.py::name` node id replaced by `file.py -k name`, only for a plain name (no Class:: part), when the file exists
# (at the cwd or under the python root) and the clause has no -k of its own. Prints nothing otherwise.
_verify_k_fallback_cmd(){
  local c="$1" tok path name
  _verify_is_pytest "$c" || return 0
  case "$c" in *" -k "*|*" -k="*) return 0 ;; esac
  # a clause that cds first resolves its file against a directory this helper does not know: no fallback (documented, not guessed)
  case "$c" in "cd "*|*"&& cd "*|*"; cd "*|*"|| cd "*) return 0 ;; esac
  # `-k` applies to EVERY file argument: with two node ids `a.py -k t1 b.py::t2` would match t1 in both files and could credit a partial match - no fallback
  [ "$(printf '%s' "$c" | grep -oE '[A-Za-z0-9_./-]+\.py::' | wc -l | tr -d ' ')" -le 1 ] || return 0
  tok="$(printf '%s' "$c" | grep -oE '[A-Za-z0-9_./-]+\.py::[A-Za-z0-9_:.-]+' | head -1)"
  [ -n "$tok" ] || return 0
  path="${tok%%::*}"; name="${tok#*::}"
  case "$name" in ''|*:*) return 0 ;; esac
  if [ ! -f "$path" ] && ! { [ -n "$_VPY_CD" ] && [ -f "$_VPY_CD/$path" ]; }; then return 0; fi
  _verify_replace_first "$c" "$tok" "$path -k $name"
}

_VC_MEMO=""; _VC_MEMO_ON=0   # per-call memo of identical VERIFY commands (newline separated, fields split by \037: key RESULT RC TMO WHY ADOPT_ROOT ADOPT_ORIG_RC)
_LAST_VERIFY_RESULT=""
_LAST_VERIFY_RC=""; _LAST_VERIFY_TIMEOUT=""; _LAST_VERIFY_WHY=""; _LAST_VERIFY_BARE=""; _LAST_VERIFY_TOOLMISSING=""
# _verify_echo_verdict <vcmd> -> prints `neg|<probe>` / `pos|<probe>` when the clause is `PROBE && echo <FAIL-word> || echo <PASS-word>` (neg), `PROBE && echo <PASS-word> || echo <FAIL-word>` (pos)
# or `PROBE || echo <FAIL-word>` (pos); prints nothing otherwise (incl. a probe that itself contains && / || / ; / $( / backticks: not safely re-readable).
_verify_echo_verdict() {
  local c="$1" fw='(FAIL|FAILED|FAILS|BAD|ERROR|NOT[ _A-Za-z]*|STILL[ _A-Za-z]*|FOUND|PRESENT|EXISTS|NO)' pw='(PASS|PASSED|OK|GOOD|YES|ABSENT|GONE|DONE|CLEAN)' q='["'"'"']?' probe kind=""
  c="$(printf '%s' "$c" | sed -E 's/[[:space:]]+$//; s/;[[:space:]]*$//')"
  if   printf '%s' "$c" | grep -qiE "&&[[:space:]]*echo[[:space:]]+${q}${fw}${q}[[:space:]]*\|\|[[:space:]]*echo[[:space:]]+${q}${pw}${q}\$"; then
    kind=neg; probe="$(printf '%s' "$c" | sed -E "s/[[:space:]]*&&[[:space:]]*echo[[:space:]]+[^|]*\|\|.*\$//")"
  elif printf '%s' "$c" | grep -qiE "&&[[:space:]]*echo[[:space:]]+${q}${pw}${q}[[:space:]]*\|\|[[:space:]]*echo[[:space:]]+${q}${fw}${q}\$"; then
    kind=pos; probe="$(printf '%s' "$c" | sed -E "s/[[:space:]]*&&[[:space:]]*echo[[:space:]]+[^|]*\|\|.*\$//")"
  elif printf '%s' "$c" | grep -qiE "[^|]\|\|[[:space:]]*echo[[:space:]]+${q}${fw}${q}\$" && ! printf '%s' "$c" | grep -qE '&&'; then
    kind=pos; probe="$(printf '%s' "$c" | sed -E "s/[[:space:]]*\|\|[[:space:]]*echo[[:space:]]+[^|]*\$//")"
  else return 0; fi
  [ -n "$probe" ] || return 0
  case "$probe" in *'$('*|*'`'*|*';'*|*'&&'*|*'||'*) return 0 ;; esac
  printf '%s|%s' "$kind" "$probe"
}

shadow_check(){  # $1 = line number in $PROG, about to be credited. Sets $_LAST_VERIFY_RESULT.
  local ln="$1" line vcmd rc out tail_out ts tmo
  ts="$(date -u +%FT%TZ)"
  _LAST_VERIFY_RESULT=""; _LAST_VERIFY_RC=""; _LAST_VERIFY_TIMEOUT=""; _LAST_VERIFY_WHY=""; _LAST_VERIFY_TOOLMISSING=""
  line="$(sed -n "${ln}p" "$PROG" 2>/dev/null)"
  # VERIFY clause convention across this fleet: VERIFY: `<cmd>`. (backtick-delimited)
  vcmd="$(printf '%s' "$line" | grep -oE 'VERIFY:[[:space:]]*`[^`]+`' | head -1 | sed -E 's/^VERIFY:[[:space:]]*`//; s/`$//')"
  # 2026-10-10 (harness R10, IPTV-2): the planner/decomposer also emit the UNBACKTICKED form `VERIFY: <cmd>[.] (cat:...)`. This reader only knew the backticked one, so such
  # items answered NO_VERIFY_CLAUSE and were credited on a path match alone (iptv: 56 of 99 items; xlite: get_max_directive_value T1/T2 ticked with no function written). Fall back
  # to the bare clause, but only when ovn_spec_rules.bare_verify (the R01 repair's safety test: known tool word, balanced quotes, no prose) accepts it. Kill switch
  # OVN_VERIFY_BARE_FALLBACK=off. _LAST_VERIFY_BARE=1 marks a verdict reached through the fallback.
  _LAST_VERIFY_BARE=""
  if [ -z "$vcmd" ] && [ "${OVN_VERIFY_BARE_FALLBACK:-on}" != off ] && [ -f "$_VC_DIR/ovn_credit_items.py" ]; then
    vcmd="$(timeout 10 python3 "$_VC_DIR/ovn_credit_items.py" bare-verify "$PROG" "$ln" 2>/dev/null | head -1)"
    [ -n "$vcmd" ] && _LAST_VERIFY_BARE=1
  fi
  if [ -z "$vcmd" ]; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=NO_VERIFY_CLAUSE" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="NO_VERIFY_CLAUSE"
    return
  fi
  # 2026-10-10 (harness R10, BX-06): addons/gut/cli/gut_cli.gd `extends Node` - it is not a SceneTree script, so `godot -s` on it can never run a test and the clause can never PASS
  # (xlite techs_data: 20 progress lines, ALREADY-DONE x6 + fixup-undid-item x3 + build-break). The entry point is addons/gut/gut_cmdln.gd: rewrite it at run time (the same repair
  # spec rule R11 applies at ingest, for items already in the queue). OVN_VERIFY_GUT_CLI_REWRITE=off disables.
  case "$vcmd" in
    *addons/gut/cli/gut_cli.gd*)
      if [ "${OVN_VERIFY_GUT_CLI_REWRITE:-on}" != off ]; then vcmd="$(printf '%s' "$vcmd" | sed 's#addons/gut/cli/gut_cli[.]gd#addons/gut/gut_cmdln.gd#g')"; fi ;;
  esac
  # Defense in depth: this is trusted-origin text (the fleet's own research/decomposition
  # output, same trust level as the diffs it already commits unattended) but shadow mode
  # is read-only observation, not a mutation - skip anything destructive/networked rather
  # than risk it, same spirit as ovn_stage_runner.sh's try_regen allowlist.
  case "$vcmd" in
    *"rm -rf"*|*"sudo "*|*"git push"*|*"git reset"*|*"curl "*|*"wget "*)
      echo "$ts repo=$_REPO_LABEL line=$ln result=SKIPPED_DENYLIST cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
      _LAST_VERIFY_RESULT="SKIPPED_DENYLIST"
      return ;;
  esac
  if _has_real_redirect "$vcmd"; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=SKIPPED_DENYLIST cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="SKIPPED_DENYLIST"
    return
  fi
  # R14 (X1): the polarity the item states for its own command (`neg grep` / `neg exit` / `pos` / `unknown`); two items may share one command with opposite narration, so it is part of the memo key
  local _pol="unknown" _poltool=""
  if [ "${OVN_VERIFY_POLARITY:-on}" != off ] && [ -f "$_VC_DIR/ovn_credit_items.py" ]; then
    _pol="$(timeout 10 python3 "$_VC_DIR/ovn_credit_items.py" polarity "$PROG" "$ln" 2>/dev/null | head -1)"
    case "$_pol" in "neg grep") _pol=neg; _poltool=grep ;; "neg exit") _pol=neg; _poltool=exit ;; "neg "*) _pol=unknown ;; pos) _pol=pos ;; *) _pol=unknown ;; esac
  fi
  # 2026-10-18 (iptv overnight audit): `PROBE && echo "FAIL" || echo "PASS"` (and `PROBE && echo PASS || echo FAIL`, `PROBE || echo FAIL`) ALWAYS exits 0: the echo, not the probe, decides the exit
  # status. iptv `Remove the definitions of check_session_limit...` carried `grep -E "def check_session_limit|..." file && echo "FAIL" || echo "PASS"`: with every def still present the clause
  # read PASS BEFORE and AFTER (item_verify refuse:already GREEN), the staged repair round re-added the deleted functions and the item was ticked [x] (staged 4/4 DONE) with nothing deleted.
  # Re-read such a clause by the PROBE's own exit status: an echo-FAIL-on-success clause states an absence (neg), an echo-PASS-on-success clause states a presence (pos).
  # OVN_VERIFY_ECHO_VERDICT=shadow (default: logs `note=echo-verdict mode=shadow would=...` to the shadow log, verdicts unchanged) | on (apply) | off.
  local _evmode="${OVN_VERIFY_ECHO_VERDICT:-shadow}" _evr="" _evk="" _evp=""
  if [ "$_evmode" != off ]; then
    _evr="$(_verify_echo_verdict "$vcmd")"
    if [ -n "$_evr" ]; then
      _evk="${_evr%%|*}"; _evp="${_evr#*|}"
      if [ "$_evmode" = on ]; then
        vcmd="$_evp"
        if [ "$_evk" = neg ]; then
          _pol=neg; _poltool=exit
          case "$(printf '%s' "$_evp" | sed -E 's/.*\| *//')" in grep\ *|egrep\ *|fgrep\ *) _poltool=grep ;; esac
        else _pol=pos; _poltool=""; fi
      else
        echo "$ts repo=$_REPO_LABEL line=$ln note=echo-verdict mode=shadow would=$_evk probe=$(printf '%s' "$_evp" | head -c 200)" >> "$SHADOW_LOG"
      fi
    fi
  fi
  local _polmark=""; [ "$_pol" = neg ] && _polmark=" polarity=neg"
  # identical command already judged in THIS call (two items sharing one VERIFY): reuse the verdict, do not run it again
  local _vckey=""
  if [ "$_VC_MEMO_ON" = 1 ]; then
    _vckey="$(printf '%s|%s' "$vcmd" "$_pol" | md5sum 2>/dev/null | cut -d' ' -f1)"
    local _vchit; _vchit="$(printf '%s\n' "$_VC_MEMO" | grep -m1 "^${_vckey}"$'\037')"
    if [ -n "$_vckey" ] && [ -n "$_vchit" ]; then
      local _vmr="" _vmo=""   # root + original rc of a py-root-retry adoption, when the cached verdict came from one (2026-10-14 audit fix)
      IFS=$'\037' read -r _ _LAST_VERIFY_RESULT _LAST_VERIFY_RC _LAST_VERIFY_TIMEOUT _LAST_VERIFY_WHY _vmr _vmo <<< "$_vchit"
      echo "$ts repo=$_REPO_LABEL line=$ln result=$_LAST_VERIFY_RESULT cached=1${_polmark} cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
      # AUDIT (2026-10-14, review finding): a replayed PASS that the first run adopted via the py-root retry is a credit too - audit it, so the false-green trail is complete
      if [ "$_LAST_VERIFY_RESULT" = PASS ] && [ -n "$_vmr" ]; then _verify_py_root_audit "$ln" "$_vmr" "$vcmd" "$PROG" "$_vmo"; fi
      return
    fi
  fi
  vcmd="$(_resolve_tool_paths "$vcmd")"
  # 2026-10-16 (review): the gut alias is SHADOW by default. The verdict keeps the clause as written. OVN_GUT_ALIAS=on applies the rewrite to the verdict;
  # OVN_GUT_ALIAS=off does nothing. Any other value (unset included) runs the aliased form once for the record only (note row, no result= token).
  local _gamode="${OVN_GUT_ALIAS:-shadow}" _gaws
  if [ "$_gamode" = on ]; then
    vcmd="$(_verify_gut_alias "$vcmd")"
  elif [ "$_gamode" != off ]; then
    _gaws="$(_verify_gut_alias "$vcmd")"
    if [ -n "$_gaws" ] && [ "$_gaws" != "$vcmd" ]; then
      local _gout _grc _gwould
      _gout="$(_verify_run "${VERIFY_TIMEOUT_SECS:-60}" "$_gaws")"; _grc=$?
      if [ "$_grc" -eq 0 ]; then _gwould=PASS; else _gwould=FAIL; fi
      echo "$ts repo=$_REPO_LABEL line=$ln note=gut-alias mode=shadow would=$_gwould rc=$_grc aliased=$(printf '%s' "$_gaws" | head -c 200) cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
    fi
  fi
  vcmd="$(_verify_fix_gut_exit "$vcmd")"
  vcmd="$(_verify_normalize_gut "$vcmd")"   # X2: -gdir=<file>.gd / bare -gtest=<name>.gd / -gselect=<function> -> a form GUT can run (OVN_GUT_CLAUSE_NORMALIZE=off disables)
  # A (verify-credit-runner): the python project root / PYTHONPATH this clause is judged under (see _verify_py_root); empty = run exactly as before
  # RETRY, not default (reviewer finding, major): the clause FIRST runs exactly as before (so every clause that already passes keeps its result by construction - a root package such as
  # billwatch-backend/alembic/ with an __init__.py would otherwise shadow the installed alembic on PYTHONPATH and break `alembic ...` / migration-drift clauses). Only a FAIL that looks like
  # a missing-import / missing-path problem is re-run ONCE under the project root and that result is adopted (see the retry below).
  _VPY_PP=""; _VPY_CD=""; _VADOPT_ROOT=""; _VADOPT_ORIG=""
  local _vroot _vpp_cand="" _vcd_cand=""; _vroot="$(_verify_py_root "$vcmd")"
  if [ -n "$_vroot" ]; then _vpp_cand="$_vroot:$(pwd)"; _vcd_cand="$(_verify_py_cwd "$vcmd" "$_vroot")"; fi
  tmo="${VERIFY_TIMEOUT_SECS:-60}"
  if [ -n "${VERIFY_TIMEOUT_HEAVY_SECS:-}" ] && _verify_is_heavy "$vcmd"; then tmo="$VERIFY_TIMEOUT_HEAVY_SECS"; fi
  if _verify_is_narrow_gut "$vcmd"; then tmo="${OVN_VERIFY_GUT_NARROW_SECS:-120}"; fi
  case "$tmo" in ''|*[!0-9]*) tmo=60 ;; esac
  _LAST_VERIFY_TIMEOUT="$tmo"
  # a gradlew clause whose gradlew does not exist in this repo cannot run at all: that is "not runnable", not a failed check
  case "$vcmd" in
    *gradlew*) if ! printf '%s' "$vcmd" | grep -q '^cd /' && ! [ -f ./gradlew ]; then
                 _LAST_VERIFY_RC=127; _LAST_VERIFY_WHY="VERIFY not runnable: gradlew not found in this repo"
                 echo "$ts repo=$_REPO_LABEL line=$ln result=UNRUNNABLE rc=127 why=gradlew-not-found cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
                 _LAST_VERIFY_RESULT="UNRUNNABLE"; return
               fi ;;
  esac
  # stdin from /dev/null (harness-X X-b): a VERIFY that reads stdin (xargs, `read`, an interactive prompt) used to swallow the remaining item
  # lines of the caller's here-string loop.
  # 2026-10-02 (follow-up 3): CI=true so watch-mode runners (vitest/jest: `npm run test -- X` printed "Waiting for file changes" after passing in 1.4s and then sat
  # until the timeout: 48 of the 50 rc=124 rows in the shadow log) run once and exit.
  out="$(_verify_run "$tmo" "$vcmd")"; rc=$?
  # A (verify-credit-runner) retry: a FAIL (not a timeout / not-runnable) whose output is an import or missing-path error is re-run ONCE under the project root; that result is adopted
  # (and the root stays in force for the B2/C retries below). A PASS never reaches this branch. The note row carries no result= token (readers count result= rows).
  if [ -n "$_vpp_cand" ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 126 ] && [ "$rc" -ne 127 ] && _verify_py_import_failure "$out"; then
    local _rout _rrc _rwould
    _VPY_PP="$_vpp_cand"; _VPY_CD="$_vcd_cand"
    _rout="$(_verify_run "$tmo" "$vcmd")"; _rrc=$?
    if [ "$_rrc" -eq 0 ]; then _rwould=PASS; else _rwould=FAIL; fi
    echo "$ts repo=$_REPO_LABEL line=$ln note=py-root-retry would=$_rwould orig_rc=$rc rc=$_rrc root=$_vroot cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
    # AUDIT (2026-10-14, review finding): the retry is adopted by default, so every FAIL it turns into a PASS is written to state/alerts.log (same dir as the shadow log;
    # OVN_VERIFY_ALERTS_LOG overrides) with the item and the clause. A false green is then visible without reading the shadow log. Kill switch OVN_VERIFY_PY_ROOT=off.
    if [ "$_rrc" -eq 0 ]; then
      _verify_py_root_audit "$ln" "$_vroot" "$vcmd" "$PROG" "$rc"
      _VADOPT_ROOT="$_vroot"; _VADOPT_ORIG="$rc"   # carried in the memo so a replayed credit is audited too
    fi
    out="$_rout"; rc="$_rrc"
  fi
  # B2: a pytest node id that does not resolve (rc=4) is retried once as `path -k name` (class-based tests are only addressable as path::Class::name)
  local _exact_retry=0 _whymark=""
  if [ "$rc" -eq 4 ] && [ "${OVN_VERIFY_NODEID_FALLBACK:-on}" != off ]; then
    local _v2; _v2="$(_verify_nodeid_fallback_cmd "$vcmd" "$tmo")"
    if [ -n "$_v2" ]; then
      out="$(_verify_run "$tmo" "$_v2")"; rc=$?
      vcmd="$_v2"; _exact_retry=1
    elif _verify_is_pytest "$vcmd" && printf '%s' "$vcmd" | grep -qE '\.py::'; then
      _LAST_VERIFY_WHY="no tests collected"   # the node id names no collected test (no exact match): stays rc=4 / FAIL
    fi
  fi
  # C (verify-credit-runner): `path::name` that names only a PREFIX of the real tests (rc 4/5, 'not found' / 'no tests ran' / 'deselected'): ONE `path -k name` retry, file must exist.
  # shadow (default) runs it for the record and keeps the original verdict; on adopts it (label name-substring); off = old behaviour.
  local _kmode="${OVN_VERIFY_PYTEST_K_FALLBACK:-shadow}"
  if [ "$_kmode" != off ] && [ "$_exact_retry" = 0 ] && { [ "$rc" -eq 4 ] || [ "$rc" -eq 5 ]; } && _verify_is_pytest "$vcmd" && grep -aEqi 'not found|no tests ran|deselected' <<< "$out"; then
    local _kcmd _kout _krc _kwould
    _kcmd="$(_verify_k_fallback_cmd "$vcmd")"
    if [ -n "$_kcmd" ]; then
      _kout="$(_verify_run "$tmo" "$_kcmd")"; _krc=$?
      if [ "$_krc" -eq 0 ] && ! grep -aq 'no tests ran' <<< "$_kout"; then _kwould=PASS; else _kwould=FAIL; fi
      echo "$ts repo=$_REPO_LABEL line=$ln note=pytest-k-fallback mode=$_kmode would=$_kwould krc=$_krc orig_rc=$rc cmd=$(printf '%s' "$_kcmd" | head -c 200)" >> "$SHADOW_LOG"
      if [ "$_kmode" = on ]; then
        out="$_kout"; rc="$_krc"; vcmd="$_kcmd"; _LAST_VERIFY_WHY="name-substring"; _whymark=" why=name-substring"
      fi
    fi
  fi
  _LAST_VERIFY_RC="$rc"
  tail_out="$(printf '%s' "$out" | tail -c 300 | tr '\n' ' ')"
  # 2026-10-18 (shrike-monitor landing audit): a pytest clause run with an interpreter that has no pytest (`python -m pytest ...` resolving to the runner's aider-venv python in a fresh stage
  # worktree, which carries no .venv) exits 1 with "No module named pytest". That is rc 1 = FAIL, but the command never produced a verdict about the item: it is INDETERMINATE (UNRUNNABLE, rc 127),
  # exactly like `pytest: command not found`. Read as FAIL it made the stage item-VERIFY gate (OVN_STAGE_ITEM_VERIFY) call every correct python item "RED after the change" (5 of 5 shrike-monitor
  # python rows), which would refuse real credits the moment the gate is enforced. _LAST_VERIFY_RC keeps the raw status. OVN_VERIFY_MISSING_PYTEST=off restores the old FAIL.
  if [ "${OVN_VERIFY_MISSING_PYTEST:-on}" != off ] && _verify_is_pytest "$vcmd" && [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 126 ] && [ "$rc" -ne 127 ] \
     && grep -aEq "No module named ['\"]?pytest([^A-Za-z_-]|$)" <<< "$out"; then
    rc=127; tail_out="pytest-not-installed $tail_out"
  fi
  # 2026-10-22 (PKG-B): the same holds for a lint/type tool the interpreter does not have: `python -m mypy app/` in a venv without mypy exits 1 with "No module named mypy" (TAA billing item: AUTO-SKIPped
  # after 2 credit refusals), and `npx tsc` in a checkout without typescript prints npm's "To get access to the TypeScript compiler" banner and exits 1 (gitlark: 4 cycles). Neither produced a verdict
  # about the item: UNRUNNABLE (rc 127, tagged tool-not-installed), so it is never counted as a credit refusal. The tool must be named by the clause itself (a test run whose OUTPUT merely mentions
  # a missing module stays FAIL). OVN_VERIFY_MISSING_TOOL=off restores the old FAIL.
  if [ "${OVN_VERIFY_MISSING_TOOL:-on}" != off ] && [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 126 ] && [ "$rc" -ne 127 ]; then
    local _mt
    for _mt in mypy ruff flake8 pylint black pyright; do
      if grep -aEq "No module named ['\"]?${_mt}([^A-Za-z_-]|$)" <<< "$out" && grep -aEq "(^|[^A-Za-z_./-])${_mt}([^A-Za-z_-]|$)" <<< "$vcmd"; then
        rc=127; _LAST_VERIFY_TOOLMISSING="$_mt"; tail_out="tool-not-installed:${_mt} $tail_out"; break
      fi
    done
    if [ "$rc" -ne 127 ] && grep -aq 'To get access to the TypeScript compiler' <<< "$out" && grep -aEq '(^|[^A-Za-z_-])(npx|tsc)([^A-Za-z_-]|$)' <<< "$vcmd"; then
      rc=127; _LAST_VERIFY_TOOLMISSING=tsc; tail_out="tool-not-installed:tsc $tail_out"
    fi
  fi
  # B2: nothing collected is not a pass (and not "no signal" either): rc=5, or rc=0 with pytest's "no tests ran"
  if _verify_is_pytest "$vcmd"; then
    if [ "$rc" -eq 5 ]; then _LAST_VERIFY_WHY="no tests collected"
    elif [ "$rc" -eq 0 ] && grep -aq 'no tests ran' <<< "$out"; then rc=1; _LAST_VERIFY_WHY="no tests collected"; tail_out="no-tests-ran $tail_out"; fi
  fi
  # B1: GUT prints "Could not find script" for a missing -gtest target, then runs the whole suite and exits 0 - the target is not there, so the clause did not pass
  if _verify_is_gut "$vcmd" && [ "${OVN_GUT_MISSING_TARGET:-fail}" != ignore ] && { grep -aq 'Could not find script' <<< "$out" || _verify_gut_gdir_missing "$vcmd"; }; then
    [ "$rc" -eq 0 ] && rc=1
    _LAST_VERIFY_WHY="GUT target missing"
    tail_out="GUT-target-missing $tail_out"
  fi
  # B3 (intake package, platform P3, 2026-10-13): a GUT checkout WITHOUT the godot import cache (.godot/, gitignored: a fresh worktree has none) prints "Some GUT class_names have not been
  # imported" and exits 0 having run NOTHING - the spec gate (ovn_spec_gate.py scan, a clean detached worktree) read that as PASS, so every GUT item was 'passes-before' (6 of 6 rows, 430ms
  # each: the real run takes seconds). It is INDETERMINATE, not a pass and not a failure of the item: UNRUNNABLE (rc 127). A script that fails to load is tagged so the classifier can tell it
  # from an assertion failure. OVN_GUT_CLAUSE_NORMALIZE=off disables both (same switch as X2).
  if _verify_is_gut "$vcmd" && [ "${OVN_GUT_CLAUSE_NORMALIZE:-on}" != off ]; then
    if [ "$rc" -eq 0 ] && grep -aq 'GUT class_names have not been imported' <<< "$out"; then
      rc=127; _LAST_VERIFY_RC=127; tail_out="GUT-not-imported $tail_out"
    elif grep -aEq 'Failed to load script|Parse Error' <<< "$out"; then
      tail_out="GUT-load-failed $tail_out"
    fi
  fi
  # GUT exits 0 on failing tests: the output summary / junit xml decide, not the exit code
  if [ "$rc" -eq 0 ] && _verify_is_gut "$vcmd"; then
    local _gx; _gx="$(_verify_gut_xml_path "$vcmd")"
    if _verify_gut_output_failed "$out" || { [ -n "$_gx" ] && ! gut_xml_green "$_gx"; }; then rc=1; tail_out="GUT-reported-failures $tail_out"; fi
  fi
  # R14 (X1): an item that states an ABSENCE ("returns no matches", "fails with No such file") passes only when the command's exit status says so. grep family: rc 1 = absent (rc 2 is an
  # error, not an absence); ls/test/stat/cat/find: any non-zero except 124/126/127. 124/126/127 stay indeterminate (handled below). _LAST_VERIFY_RC keeps the RAW status.
  # R15: a pipeline's status is its LAST stage's: `grep X missing_dir | grep -v y` and `cd missing && grep ...` exit 1 and read as "absent". ovn_verify_safe.py neg-check re-evaluates the clause
  # stage by stage (grep >= 2 anywhere, a failing cd): INDETERMINATE -> not credited (rc stays a FAIL, never mapped to absent); ABSENT-DELETED = a lone grep on a file the item itself deletes
  # (rc 2 forever otherwise) -> satisfied-absent. OVN_VERIFY_NEG_STAGES=off disables.
  local _negv="OK"
  if [ "$_pol" = neg ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 126 ] && [ "$rc" -ne 127 ] && [ "${OVN_VERIFY_NEG_STAGES:-on}" != off ] && [ -f "$_VC_DIR/ovn_verify_safe.py" ]; then
    _negv="$(timeout 40 python3 "$_VC_DIR/ovn_verify_safe.py" neg-check "$PROG" "$ln" "$vcmd" 2>/dev/null | head -1)"
    [ -n "$_negv" ] || _negv="OK"
  fi
  if [ "$_negv" = ABSENT-DELETED ]; then
    rc=0; tail_out="neg-polarity-absent-deleted $tail_out"
  elif [ "${_negv#INDETERMINATE}" != "$_negv" ]; then
    [ "$rc" -ge 2 ] || rc=2
    _LAST_VERIFY_WHY="VERIFY states an absence but a stage errored (${_negv#INDETERMINATE:}): not an absence"; tail_out="neg-polarity-indeterminate $tail_out"
  elif [ "$_pol" = neg ] && [ "$rc" -ne 124 ] && [ "$rc" -ne 126 ] && [ "$rc" -ne 127 ]; then
    if [ "$rc" -eq 0 ]; then
      rc=1; _LAST_VERIFY_WHY="VERIFY states an absence (negative polarity) but the command succeeded: the thing is still present"; tail_out="neg-polarity-still-present $tail_out"
    elif [ "$_poltool" = exit ] || { [ "$_poltool" = grep ] && [ "$rc" -eq 1 ]; }; then
      rc=0; tail_out="neg-polarity-absent $tail_out"
    fi
  fi
  if [ "$rc" -eq 0 ]; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=PASS${_polmark}${_whymark} cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="PASS"
  elif [ "$rc" -eq 124 ]; then
    _LAST_VERIFY_WHY="VERIFY timed out (rc=124) after ${tmo}s"
    echo "$ts repo=$_REPO_LABEL line=$ln result=TIMEOUT rc=124${_polmark} timeout=${tmo}s cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="TIMEOUT"
  elif [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
    _LAST_VERIFY_WHY="VERIFY not runnable: rc=${rc}"   # never echo the output tail: this string goes to alerts.log (wider channel than the shadow log)
    echo "$ts repo=$_REPO_LABEL line=$ln result=UNRUNNABLE rc=$rc cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="UNRUNNABLE"
  else
    local _unrk=""
    [ "${OVN_VERIFY_UNRUNNABLE_SHAPES:-shadow}" != off ] && _unrk="$(_verify_unrunnable_kind "$rc" "$vcmd" "$out")"
    if [ -n "$_unrk" ]; then
      echo "$ts repo=$_REPO_LABEL line=$ln result=UNRUNNABLE rc=$rc why=$_unrk mode=shadow${_polmark} cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    else
      echo "$ts repo=$_REPO_LABEL line=$ln result=FAIL rc=$rc${_polmark}${_whymark} cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    fi
    _LAST_VERIFY_RESULT="FAIL"
  fi
  [ -n "$_vckey" ] && _VC_MEMO="${_VC_MEMO}${_vckey}"$'\037'"${_LAST_VERIFY_RESULT}"$'\037'"${_LAST_VERIFY_RC}"$'\037'"${_LAST_VERIFY_TIMEOUT}"$'\037'"${_LAST_VERIFY_WHY}"$'\037'"${_VADOPT_ROOT}"$'\037'"${_VADOPT_ORIG}"$'\n'
  return 0
}
