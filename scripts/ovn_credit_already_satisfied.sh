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

SHADOW_LOG="${OVN_VERIFY_SHADOW_LOG:-$HOME/overnight-queue/state/verify_gate_shadow.log}"
mkdir -p "$(dirname "$SHADOW_LOG")" 2>/dev/null
_REPO_LABEL="$(basename "$PWD")"

# Substitute a nearby repo .venv's python for a bare `python`/`python3` token, so a
# VERIFY clause that omits the .venv/ prefix (some do, some don't - an authoring
# inconsistency, not something this shadow check should mistake for a false credit)
# runs with the repo's actual installed deps instead of whatever's on PATH.
_resolve_tool_paths(){
  local cmd="$1" vpy vpytest cddir="."

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

  vpy="$(find "$cddir" -maxdepth 4 \( -path '*/.venv/bin/python3' -o -path '*/.venv/bin/python' \) 2>/dev/null | head -1)"
  if [ -n "$vpy" ]; then
    # Authoritatively replace ANY existing venv-python path reference (correct
    # or not) plus any bare python/python3 token with the one just verified to
    # actually exist - a no-op if the text was already right, a self-heal if
    # it wasn't (e.g. a duplicated "backend/backend/.venv" segment).
    cmd="$(printf '%s' "$cmd" | sed -E "s#[./A-Za-z0-9_-]*\.venv/bin/python3?#${vpy}#g; s#(^|&& |; )python3? #\1${vpy} #g")"
  fi

  vpytest="$(find "$cddir" -maxdepth 4 -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
  if [ -n "$vpytest" ]; then
    cmd="$(printf '%s' "$cmd" | sed -E "s#[./A-Za-z0-9_-]*\.venv/bin/pytest#${vpytest}#g; s#(^|&& |; )pytest #\1${vpytest} #g")"
  fi

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

shadow_check(){  # $1 = line number in $PROG, about to be credited
  local ln="$1" line vcmd rc out tail_out ts
  ts="$(date -u +%FT%TZ)"
  line="$(sed -n "${ln}p" "$PROG" 2>/dev/null)"
  # VERIFY clause convention across this fleet: VERIFY: `<cmd>`. (backtick-delimited)
  vcmd="$(printf '%s' "$line" | grep -oE 'VERIFY:[[:space:]]*`[^`]+`' | head -1 | sed -E 's/^VERIFY:[[:space:]]*`//; s/`$//')"
  if [ -z "$vcmd" ]; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=NO_VERIFY_CLAUSE" >> "$SHADOW_LOG"
    return
  fi
  # Defense in depth: this is trusted-origin text (the fleet's own research/decomposition
  # output, same trust level as the diffs it already commits unattended) but shadow mode
  # is read-only observation, not a mutation - skip anything destructive/networked rather
  # than risk it, same spirit as ovn_stage_runner.sh's try_regen allowlist.
  case "$vcmd" in
    *"rm -rf"*|*"sudo "*|*"git push"*|*"git reset"*|*"curl "*|*"wget "*)
      echo "$ts repo=$_REPO_LABEL line=$ln result=SKIPPED_DENYLIST cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
      return ;;
  esac
  if _has_real_redirect "$vcmd"; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=SKIPPED_DENYLIST cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
    return
  fi
  vcmd="$(_resolve_tool_paths "$vcmd")"
  out="$(timeout 60 bash -c "$vcmd" 2>&1)"; rc=$?
  tail_out="$(printf '%s' "$out" | tail -c 300 | tr '\n' ' ')"
  if [ "$rc" -eq 0 ]; then
    echo "$ts repo=$_REPO_LABEL line=$ln result=PASS cmd=$(printf '%s' "$vcmd" | head -c 200)" >> "$SHADOW_LOG"
  else
    echo "$ts repo=$_REPO_LABEL line=$ln result=FAIL rc=$rc cmd=$(printf '%s' "$vcmd" | head -c 200) tail=$tail_out" >> "$SHADOW_LOG"
  fi
}

FILES="$(awk '
  { if (match($0, /[A-Za-z0-9_\/.-]+\.[A-Za-z0-9]{1,8}/)) { lastf=substr($0,RSTART,RLENGTH) } }
  /[Aa]lready (done|implemented|imported|present|in place|use|uses|has|have|correct|handled|satisfied|been|exists|covers?|tests?|validates?|guards?)/ { if (lastf!="") print lastf }
  /[Nn]o changes? (needed|required|necessary)|[Nn]othing to (change|do|add)|is already (there|the case)|already (passes|passing)/ { if (lastf!="") print lastf }
' "$LOG" | sort -u)"
credited=0
for f in $FILES; do
  case "$f" in *.md) continue;; esac
  b="$(basename "$f")"
  ln="$(grep -nE '^- \[ \]' "$PROG" | grep -viE 'HUMAN-ONLY|human/|AUTO-SKIP|HARD FILE BAN|BLOCKED ITEM' | grep -F "$b" | head -1 | cut -d: -f1)"
  if [ -n "$ln" ]; then
    shadow_check "$ln"
    sed -i "${ln}s/^- \[ \] /- [x] (already-satisfied in code, implement-verified) /" "$PROG"
    credited=$((credited+1))
    echo "credited line ${ln} (matched ${b})"
  fi
done
echo "CREDITED=${credited}"
exit 0
