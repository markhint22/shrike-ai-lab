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
_verify_is_narrow_gut(){ _verify_is_gut "$1" || return 1; case "$1" in *-gtest*|*-gselect*|*-gunit_test_name*) return 0;; esac; return 1; }
# 0 (true) when GUT output reports failures. Real GUT 9.4.0 output (captured on the box): the summary is "  Failing         1" (printed only when
# non-zero, no word "Tests") and each detail line is ANSI-coloured: ESC[31m    [Failed]:  ... - so strip ANSI first. Older/other layouts kept:
# "Failing Tests  N", "---- N failing tests ----".
_verify_gut_output_failed(){
  local esc; esc="$(printf '\033')"
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
_LAST_VERIFY_RC=""; _LAST_VERIFY_TIMEOUT=""; _LAST_VERIFY_WHY=""
shadow_check(){  # $1 = line number in $PROG, about to be credited. Sets $_LAST_VERIFY_RESULT.
  local ln="$1" line vcmd rc out tail_out ts tmo
  ts="$(date -u +%FT%TZ)"
  _LAST_VERIFY_RESULT=""; _LAST_VERIFY_RC=""; _LAST_VERIFY_TIMEOUT=""; _LAST_VERIFY_WHY=""
  line="$(sed -n "${ln}p" "$PROG" 2>/dev/null)"
  # VERIFY clause convention across this fleet: VERIFY: `<cmd>`. (backtick-delimited)
  vcmd="$(printf '%s' "$line" | grep -oE 'VERIFY:[[:space:]]*`[^`]+`' | head -1 | sed -E 's/^VERIFY:[[:space:]]*`//; s/`$//')"
  if [ -z "$vcmd" ]; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=NO_VERIFY_CLAUSE" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="NO_VERIFY_CLAUSE"
    return
  fi
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
  # identical command already judged in THIS call (two items sharing one VERIFY): reuse the verdict, do not run it again
  local _vckey=""
  if [ "$_VC_MEMO_ON" = 1 ]; then
    _vckey="$(printf '%s' "$vcmd" | md5sum 2>/dev/null | cut -d' ' -f1)"
    local _vchit; _vchit="$(printf '%s\n' "$_VC_MEMO" | grep -m1 "^${_vckey}"$'\037')"
    if [ -n "$_vckey" ] && [ -n "$_vchit" ]; then
      IFS=$'\037' read -r _ _LAST_VERIFY_RESULT _LAST_VERIFY_RC _LAST_VERIFY_TIMEOUT _LAST_VERIFY_WHY <<< "$_vchit"
      echo "$ts repo=$_REPO_LABEL line=$ln result=$_LAST_VERIFY_RESULT cached=1 cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
      return
    fi
  fi
  vcmd="$(_resolve_tool_paths "$vcmd")"
  vcmd="$(_verify_fix_gut_exit "$vcmd")"
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
  _LAST_VERIFY_RC="$rc"
  tail_out="$(printf '%s' "$out" | tail -c 300 | tr '\n' ' ')"
  # GUT exits 0 on failing tests: the output summary / junit xml decide, not the exit code
  if [ "$rc" -eq 0 ] && _verify_is_gut "$vcmd"; then
    local _gx; _gx="$(_verify_gut_xml_path "$vcmd")"
    if _verify_gut_output_failed "$out" || { [ -n "$_gx" ] && ! gut_xml_green "$_gx"; }; then rc=1; tail_out="GUT-reported-failures $tail_out"; fi
  fi
  if [ "$rc" -eq 0 ]; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=PASS cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="PASS"
  elif [ "$rc" -eq 124 ]; then
    _LAST_VERIFY_WHY="VERIFY timed out (rc=124) after ${tmo}s"
    echo "$ts repo=$_REPO_LABEL line=$ln result=TIMEOUT rc=124 timeout=${tmo}s cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="TIMEOUT"
  elif [ "$rc" -eq 126 ] || [ "$rc" -eq 127 ]; then
    _LAST_VERIFY_WHY="VERIFY not runnable: rc=${rc}"   # never echo the output tail: this string goes to alerts.log (wider channel than the shadow log)
    echo "$ts repo=$_REPO_LABEL line=$ln result=UNRUNNABLE rc=$rc cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="UNRUNNABLE"
  else
    echo "$ts repo=$_REPO_LABEL line=$ln result=FAIL rc=$rc cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="FAIL"
  fi
  [ -n "$_vckey" ] && _VC_MEMO="${_VC_MEMO}${_vckey}"$'\037'"${_LAST_VERIFY_RESULT}"$'\037'"${_LAST_VERIFY_RC}"$'\037'"${_LAST_VERIFY_TIMEOUT}"$'\037'"${_LAST_VERIFY_WHY}"$'\n'
  return 0
}
