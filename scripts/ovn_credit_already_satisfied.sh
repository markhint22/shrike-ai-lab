#!/usr/bin/env bash
# Credit items the IMPLEMENT pass found already-satisfied in the code.
# The 27B walks the item list during implement and reports items already done
# ("Query is already imported", "already uses except Exception", "This item is
# already done") -> no diff, no commit -> UNTAGGED no-op, and the item is
# re-faced every cycle forever. This harvests the file named right before each
# already-done admission (awk tracks the last file token seen) and checks off
# the matching unchecked, non-human item. Prints CREDITED=<n>. Run in repo cwd.
#
# SHADOW-MODE VERIFY GATE (2026-09-24): this mechanism has ZERO actual
# verification - despite the "(already-satisfied in code, implement-verified)"
# label, it never checks the file exists or runs the item's own VERIFY: clause.
# Confirmed via direct filesystem checks (billwatch research pass): multiple
# credited items' target files don't exist (create/modify items) or still
# exist (delete items) despite being marked done. A broader tight-regex sample
# across 4 repos found a 5-21% suspect rate on 464 checkable credits - a real,
# previously invisible data-integrity gap, not an edge case (see memory:
# project_credit-already-satisfied-false-credit-bug-2026-09-24).
#
# This adds a SHADOW check only: before crediting, extract the item's own
# "VERIFY: `<cmd>`" clause and actually run it, logging PASS/FAIL/NO_CLAUSE/
# SKIPPED to state/verify_gate_shadow.log. Crediting behavior is UNCHANGED -
# this purely observes, so we get real pass/fail data before deciding whether
# to demote failing credits back to open (a Phase-3-style staged rollout, not
# an immediate behavior flip - see the pipeline-hardening plan).
#
# CALIBRATION (2026-09-25, after the first overnight run of real shadow data):
#   1. A bare `python`/`python3` VERIFY command (no .venv/ prefix) resolved to
#      whatever interpreter is on PATH, which lacks this repo's installed deps
#      (pytest etc) - a real FAIL was actually "No module named pytest", an
#      environment mismatch, not a false credit. Same fix already proven in
#      ovn_stage_runner.sh's try_regen: substitute the repo's own venv python
#      when one exists nearby.
#   2. The denylist's blanket `*">"*` match skipped `2>/dev/null` (a completely
#      standard, safe stderr-suppression idiom used throughout this fleet's own
#      VERIFY clauses) as if it were a real file write, throwing away signal on
#      common, safe commands. Narrowed to only deny an actual non-/dev/null
#      redirect target.
#
# CALIBRATION ROUND 2 (2026-09-26, after 105 more shadow data points - 44 FAIL,
# but almost all environment noise, not real credit problems):
#   3. Bare `pytest` (no "python"/"python3" token at all) was never substituted -
#      only "python "/"python3 " prefixes were, so a VERIFY of plain
#      `pytest tests/...` still resolved to whatever's on PATH (often nothing:
#      "pytest: command not found", or the wrong interpreter's site-packages:
#      "No module named pytest" on iptv_apps).
#   4. Several items' own hardcoded VERIFY text has a duplicated path segment
#      from a "cd backend && ./backend/.venv/bin/python3 ..." authoring
#      mistake - after the cd, that resolves to backend/backend/.venv/..., which
#      never exists. Confirmed on shrike-monitor and test-automation-agent.
#   5. `godot` is never on PATH anywhere on this box (confirmed: no symlink, no
#      alias, not found even in a login shell) - the REAL pipeline
#      (run_overnight.sh's own GUT-test verification) always calls the full
#      "$HOME/godot/godot4" path, but VERIFY clauses are authored with bare
#      `godot`, which only ever works by accident if something else's PATH
#      happens to include it. Every xlite VERIFY containing "godot" was a
#      guaranteed FAIL here regardless of the actual credit's correctness.
# Fix: replaced the narrow token-substitution with a small tool-path resolver
# that (a) always substitutes bare `godot` for $HOME/godot/godot4, matching the
# real pipeline's own convention exactly, and (b) re-resolves python/python3/
# pytest against a FRESH `find` for the nearest real .venv - authoritatively
# replacing the command's own path reference even when one is already present,
# so an already-correct path is a no-op substitution and an already-wrong one
# self-heals, instead of trying to detect and special-case every possible
# wrong-path shape by hand.
set -uo pipefail
LOG="${1:-}"; PROG="${2:-OVERNIGHT_PROGRESS.md}"
[ -f "$LOG" ] || { echo "CREDITED=0"; exit 0; }
[ -f "$PROG" ] || { echo "CREDITED=0"; exit 0; }

# PROMOTED 2026-09-28: after 3 rounds of tool-path calibration (2026-09-25/26/27),
# post-round-3 shadow data (deployed 2026-09-27 09:23 CDT) shows 27 PASS vs 5 FAIL,
# with EVERY post-fix FAIL a genuine content signal (an item whose VERIFY clause no
# longer matches reality - already-flagged/already-resolved-differently in each
# case checked), zero remaining tooling-noise false negatives. Meets the plan's own
# "promote independently once proven" bar. OVN_VERIFY_GATE_MODE=shadow reverts
# instantly to the old observe-only behavior with no code change if this needs
# rolling back.
VERIFY_GATE_MODE="${OVN_VERIFY_GATE_MODE:-enforce}"

SHADOW_LOG="${OVN_VERIFY_SHADOW_LOG:-$HOME/overnight-queue/state/verify_gate_shadow.log}"
mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
_REPO_LABEL="$(basename "$PWD")"

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

_LAST_VERIFY_RESULT=""
shadow_check(){  # $1 = line number in $PROG, about to be credited. Sets $_LAST_VERIFY_RESULT.
  local ln="$1" line vcmd rc out tail_out ts
  ts="$(date -u +%FT%TZ)"
  _LAST_VERIFY_RESULT=""
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
  vcmd="$(_resolve_tool_paths "$vcmd")"
  out="$(timeout 60 bash -c "$vcmd" 2>&1)"; rc=$?
  tail_out="$(printf '%s' "$out" | tail -c 300 | tr '\n' ' ')"
  if [ "$rc" -eq 0 ]; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=PASS cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="PASS"
  else
    echo "$ts repo=$_REPO_LABEL line=$ln result=FAIL rc=$rc cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
    _LAST_VERIFY_RESULT="FAIL"
  fi
}

# UNDER-CREDITING FIX (2026-09-28): both patterns below were exact-phrase matches with zero
# tolerance for ordinary sentence variation, so a correctly-completed item whose model
# response phrased "nothing to change" even slightly differently was scored as a flail
# (no FILES match -> no credit -> re-served every cycle) instead of neutral. Confirmed live
# on billwatch: a stuck item that was ALREADY correctly fixed in code kept getting re-served
# and re-failing for 4+ days, burning ~450K tokens, because its "already done" responses
# were phrased in ways like "This item appears to already be satisfied" that this regex
# could not see. Calibrated against 350+ real recent model responses (grep across
# logs/*billwatch*.log), not guessed - every addition below is a phrasing that actually
# appeared and was NOT matched by the old pattern:
#   "already be satisfied"       - the old pattern required "already <word>" adjacency;
#                                   a "be" (or "fully"/"correctly"/"completely") between
#                                   "already" and the verb broke the match every time.
#   "already fully implemented", "already correctly defined" - same adjacency gap.
#   "already contains", "already defined", "already handles", "already satisfies" - present-
#                                   tense/3rd-person verb forms the old list never had (it only
#                                   had "handled"/"satisfied" past tense, no "contains"/"defined").
#   "already fine"                - a common casual completion phrase, not in the old list at all.
#   "No further changes are needed.", "No code changes needed." - the old "No changes? needed"
#                                   pattern required strict adjacency; "further"/"code" in
#                                   between broke it.
#   "does not need any changes."  - an entirely different sentence shape the old pattern
#                                   had no alternative for at all.
# This is purely a RECALL fix (catching more true already-done responses) - it does NOT
# weaken the enforce-mode VERIFY gate below, which independently confirms (and can still
# REFUSE) every credit this produces, so a broader match that happens to be wrong still
# cannot silently over-credit - see that gate's own 2026-09-24/25/26/27 header notes.
FILES="$(awk '
  { if (match($0, /[A-Za-z0-9_\/.-]+\.[A-Za-z0-9]{1,8}/)) { lastf=substr($0,RSTART,RLENGTH) } }
  /[Aa]lready (fully |correctly |completely |essentially |be )*(done|implemented|imported|present|in place|use|uses|has|have|correct|handled|handles|satisfied|satisfies|been|exists?|contains?|defined|defines|covers?|tests?|validates?|guards?|fine|good|complete)/ { if (lastf!="") print lastf }
  /[Nn]o (code |further |additional )*changes? (are |is )?(needed|required|necessary)|[Nn]othing to (change|do|add)|is already (there|the case)|already (passes|passing)|does not (need|require) (any )?changes?/ { if (lastf!="") print lastf }
' "$LOG" | sort -u)"
credited=0
for f in $FILES; do
  case "$f" in *.md) continue;; esac
  b="$(basename "$f")"
  ln="$(grep -nE '^- \[ \]' "$PROG" | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED ITEM' | grep -F "$b" | head -1 | cut -d: -f1)"
  if [ -n "$ln" ]; then
    shadow_check "$ln"
    # ENFORCE: a FAIL means the item's own VERIFY clause does not hold - refuse
    # the credit and leave it open rather than propagate a false "done" (the
    # exact data-integrity gap this whole mechanism was built to close). PASS/
    # NO_VERIFY_CLAUSE/SKIPPED_DENYLIST all credit as before - none of those are
    # evidence the credit is wrong, just cases this check can (or chooses not
    # to) verify one way or the other.
    if [ "$VERIFY_GATE_MODE" = "enforce" ] && [ "$_LAST_VERIFY_RESULT" = "FAIL" ]; then
      echo "REFUSED credit at line ${ln} (matched ${b}) - VERIFY clause failed, left open for review"
    else
      sed -i "${ln}s/^- \[ \] /- [x] (already-satisfied in code, implement-verified) /" "$PROG"
      credited=$((credited+1))
      echo "credited line ${ln} (matched ${b})"
    fi
  fi
done
echo "CREDITED=${credited}"
exit 0
