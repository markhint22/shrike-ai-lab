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

  vpytest="$(find -L "$cddir" -maxdepth 4 -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
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
  local c="$1" tmo="${2:-60}" tok path name ccmd cout line first id idrest ids="" rep
  _verify_is_pytest "$c" || return 0
  tok="$(printf '%s' "$c" | grep -oE '[A-Za-z0-9_./-]+\.py::[A-Za-z0-9_:.-]+' | head -1)"
  [ -n "$tok" ] || return 0
  path="${tok%%::*}"; name="${tok#*::}"
  [ -n "$name" ] || return 0
  # the collection command: same command, node id -> its file, verbosity flags dropped, `--collect-only -q` (one `file::Class::name[param]` id per line)
  ccmd="$(_verify_replace_first "$c" "$tok" "$path" | sed -E 's/ -(q+|v+)( |$)/ /g; s/ -(q+|v+)( |$)/ /g')"
  cout="$(CI=true timeout "$tmo" bash -c "$ccmd --collect-only -q" 2>&1 </dev/null)" || true
  while IFS= read -r line; do
    first="${line%% *}"
    case "$first" in
      "$path"::*) ;;
      *) continue ;;
    esac
    id="${first%%\[*}"; idrest="${id#*::}"
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

_VC_MEMO=""; _VC_MEMO_ON=0   # per-call memo of identical VERIFY commands (newline separated, fields split by \037: key RESULT RC TMO WHY)
_LAST_VERIFY_RESULT=""
_LAST_VERIFY_RC=""; _LAST_VERIFY_TIMEOUT=""; _LAST_VERIFY_WHY=""; _LAST_VERIFY_BARE=""
shadow_check(){  # $1 = line number in $PROG, about to be credited. Sets $_LAST_VERIFY_RESULT.
  local ln="$1" line vcmd rc out tail_out ts tmo
  ts="$(date -u +%FT%TZ)"
  _LAST_VERIFY_RESULT=""; _LAST_VERIFY_RC=""; _LAST_VERIFY_TIMEOUT=""; _LAST_VERIFY_WHY=""
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
  local _polmark=""; [ "$_pol" = neg ] && _polmark=" polarity=neg"
  # identical command already judged in THIS call (two items sharing one VERIFY): reuse the verdict, do not run it again
  local _vckey=""
  if [ "$_VC_MEMO_ON" = 1 ]; then
    _vckey="$(printf '%s|%s' "$vcmd" "$_pol" | md5sum 2>/dev/null | cut -d' ' -f1)"
    local _vchit; _vchit="$(printf '%s\n' "$_VC_MEMO" | grep -m1 "^${_vckey}"$'\037')"
    if [ -n "$_vckey" ] && [ -n "$_vchit" ]; then
      IFS=$'\037' read -r _ _LAST_VERIFY_RESULT _LAST_VERIFY_RC _LAST_VERIFY_TIMEOUT _LAST_VERIFY_WHY <<< "$_vchit"
      echo "$ts repo=$_REPO_LABEL line=$ln result=$_LAST_VERIFY_RESULT cached=1${_polmark} cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
      return
    fi
  fi
  vcmd="$(_resolve_tool_paths "$vcmd")"
  vcmd="$(_verify_fix_gut_exit "$vcmd")"
  vcmd="$(_verify_normalize_gut "$vcmd")"   # X2: -gdir=<file>.gd / bare -gtest=<name>.gd / -gselect=<function> -> a form GUT can run (OVN_GUT_CLAUSE_NORMALIZE=off disables)
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
  out="$(CI=true timeout "$tmo" bash -c "$vcmd" 2>&1 </dev/null)"; rc=$?
  # B2: a pytest node id that does not resolve (rc=4) is retried once as `path -k name` (class-based tests are only addressable as path::Class::name)
  if [ "$rc" -eq 4 ] && [ "${OVN_VERIFY_NODEID_FALLBACK:-on}" != off ]; then
    local _v2; _v2="$(_verify_nodeid_fallback_cmd "$vcmd" "$tmo")"
    if [ -n "$_v2" ]; then
      out="$(CI=true timeout "$tmo" bash -c "$_v2" 2>&1 </dev/null)"; rc=$?
      vcmd="$_v2"
    elif _verify_is_pytest "$vcmd" && printf '%s' "$vcmd" | grep -qE '\.py::'; then
      _LAST_VERIFY_WHY="no tests collected"   # the node id names no collected test (no exact match): stays rc=4 / FAIL
    fi
  fi
  _LAST_VERIFY_RC="$rc"
  tail_out="$(printf '%s' "$out" | tail -c 300 | tr '\n' ' ')"
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
    echo "$ts repo=$_REPO_LABEL line=$ln result=PASS${_polmark} cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
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
    echo "$ts repo=$_REPO_LABEL line=$ln result=FAIL rc=$rc${_polmark} cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="FAIL"
  fi
  [ -n "$_vckey" ] && _VC_MEMO="${_VC_MEMO}${_vckey}"$'\037'"${_LAST_VERIFY_RESULT}"$'\037'"${_LAST_VERIFY_RC}"$'\037'"${_LAST_VERIFY_TIMEOUT}"$'\037'"${_LAST_VERIFY_WHY}"$'\n'
  return 0
}
