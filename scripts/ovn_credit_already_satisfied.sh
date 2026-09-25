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
_resolve_venv_cmd(){
  local cmd="$1" vpy
  case "$cmd" in
    python\ *|python3\ *|*'&& python '*|*'&& python3 '*|*'; python '*|*'; python3 '*)
      vpy="$(find . -maxdepth 4 \( -path '*/.venv/bin/python3' -o -path '*/.venv/bin/python' \) 2>/dev/null | head -1)"
      if [ -n "$vpy" ]; then
        cmd="$(printf '%s' "$cmd" | sed -E "s#(^|&& |; )python3? #\\1${vpy} #")"
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
  vcmd="$(_resolve_venv_cmd "$vcmd")"
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
