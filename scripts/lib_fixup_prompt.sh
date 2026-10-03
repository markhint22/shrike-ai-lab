#!/usr/bin/env bash
# scripts/lib_fixup_prompt.sh - FACT-BASED fix-up prompts (2026-10-02, QA harness-X, X3).
#
# WHY: the Tier-2 / BUILD-GATE / MIGRATION fix-ups sent "The test suite is failing after your last change: <summary>. Fix this SPECIFIC
# failure." into a FRESH aider session that has no memory of any change. Seeing "your last change", the 27B reached for the only "previous
# change" it knows - aider's built-in udiff example (replace is_prime with sympy in mathweb/flask/app.py) - and stalled or asked for
# clarification: 7 of 7 fix-ups on 2026-10-02 were wasted (5 "made no change", 2 re-verified red); 6 of 7 logs contain the is_prime
# contamination (e.g. logs/20261002-121658/ongoing-iptv-apps.log ~663-792). Not a model fault: the harness asked about a change the session
# never saw. The fix is to put the FACTS in the message: the diff that was committed, the failing test ids + assertion lines, the files
# pre-loaded, wording that says "was just committed" (never "your last change"), and an explicit "ignore any example from your instructions".
#
# Budget: the whole message stays well inside the 65k context (diff <= OVN_FIXUP_DIFF_CHARS ~3k tokens, evidence <= OVN_FIXUP_EVIDENCE_CHARS).
#
#   ovn_fixup_diff_facts <before> <after>          the committed diff, per-file truncated, total-capped
#   ovn_fixup_failure_facts <task_log> [summary]   failing test ids + assertion/traceback lines (verbatim, capped)
#   ovn_fixup_failing_test_files <task_log>        existing repo files named by FAILED ids / vitest lines
#   ovn_fixup_extra_files <task_log> <already-listed files...>   failing test files to pre-load, within a byte budget
#   ovn_fixup_prompt <headline> <before> <after> <evidence> <instructions>   the assembled message
_FP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$_FP_DIR/lib_path_normalize.sh" ] && . "$_FP_DIR/lib_path_normalize.sh"
declare -F ovn_normalize_path >/dev/null 2>&1 || ovn_normalize_path(){ printf '%s\n' "$2"; }

OVN_FIXUP_DIFF_CHARS="${OVN_FIXUP_DIFF_CHARS:-12000}"       # ~3k tokens for the whole diff
OVN_FIXUP_DIFF_FILE_LINES="${OVN_FIXUP_DIFF_FILE_LINES:-70}" # per-file line cap
OVN_FIXUP_LINE_CHARS="${OVN_FIXUP_LINE_CHARS:-200}"          # per-line cap (a minified blob must not eat the budget)
OVN_FIXUP_EVIDENCE_CHARS="${OVN_FIXUP_EVIDENCE_CHARS:-5000}"
OVN_FIXUP_FILES_BYTES="${OVN_FIXUP_FILES_BYTES:-120000}"     # total bytes of --file content (~30k tokens)

ovn_fixup_diff_facts() {
  local before="$1" after="$2" budget="$OVN_FIXUP_DIFF_CHARS" used=0 f d n files omitted="" chunk
  files="$(git diff --name-only "$before" "$after" -- . ':(exclude)OVERNIGHT_PROGRESS.md' ':(exclude)OVERNIGHT_DONE.md' \
            ':(exclude)*package-lock.json' ':(exclude)*yarn.lock' ':(exclude)*.lock' ':(exclude)*.min.js' 2>/dev/null | grep -v '^$')"
  if [ -z "$files" ]; then echo "(no source changes in the committed diff)"; return 0; fi
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ "$used" -ge "$budget" ]; then omitted="$omitted $f"; continue; fi
    d="$(git diff --no-color -U2 "$before" "$after" -- "$f" 2>/dev/null)"
    n="$(printf '%s\n' "$d" | wc -l | tr -d ' ')"
    chunk="$(printf '%s\n' "$d" | head -n "$OVN_FIXUP_DIFF_FILE_LINES" | cut -c1-"$OVN_FIXUP_LINE_CHARS")"
    [ "$n" -gt "$OVN_FIXUP_DIFF_FILE_LINES" ] && chunk="$chunk
[... diff for $f truncated: $((n - OVN_FIXUP_DIFF_FILE_LINES)) more lines; the full file is in the chat ...]"
    # never let one file exceed what is left of the total budget
    local left=$((budget - used))
    if [ "${#chunk}" -gt "$left" ]; then chunk="$(printf '%s' "$chunk" | head -c "$left")
[... diff for $f cut at the size budget ...]"; fi
    printf '%s\n' "$chunk"
    used=$((used + ${#chunk}))
  done <<< "$files"
  [ -n "$omitted" ] && printf '[... more files changed (diff omitted for size):%s ...]\n' "$omitted"
  return 0
}

# Verbatim failure facts from the TAIL of the task log (the verify output just appended), capped. Falls back to <summary>.
ovn_fixup_failure_facts() {
  local log="$1" summary="${2:-}" tailtxt ids asserts out
  if [ -f "$log" ]; then
    tailtxt="$(tail -n 700 "$log" 2>/dev/null | cut -c1-400)"
    ids="$(printf '%s\n' "$tailtxt" | grep -aE '^(FAILED|ERROR) ' | awk '!s[$0]++' | tail -n 10 | cut -c1-300)"
    asserts="$(printf '%s\n' "$tailtxt" | grep -aE '^(E +|>.*assert|.*AssertionError|.*Error: |.*Expected|.*Received| *❯ .*\.(test|spec)\.[jt]sx?)' | awk '!s[$0]++' | tail -n 16 | cut -c1-240)"
  fi
  out=""
  [ -n "${ids:-}" ] && out="Failing tests:
${ids}"
  [ -n "${asserts:-}" ] && out="${out}${out:+

}Assertion / traceback lines:
${asserts}"
  [ -z "$out" ] && out="${summary}"
  printf '%s' "$out" | head -c "$OVN_FIXUP_EVIDENCE_CHARS"
}

# repo-relative existing files named by pytest FAILED/ERROR ids (path::test) and vitest/jest "❯ path.test.ts" lines
ovn_fixup_failing_test_files() {
  local log="$1" cand p real seen=""
  [ -f "$log" ] || return 0
  cand="$(tail -n 700 "$log" 2>/dev/null | grep -aoE '^(FAILED|ERROR) [^: ]+\.py|❯ [^ ]+\.(test|spec)\.[jt]sx?|^ *(FAIL|✗|×) +[^ ]+\.(test|spec)\.[jt]sx?' \
          | sed -E 's/^(FAILED|ERROR) //; s/^❯ //; s/^ *(FAIL|✗|×) +//' | awk '!s[$0]++' | head -n 8)"
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    real="$p"; [ -f "$real" ] || real="$(ovn_normalize_path "$PWD" "$p")"
    [ -f "$real" ] || continue
    case " $seen " in *" $real "*) continue;; esac
    seen="$seen $real"; printf '%s\n' "$real"
  done <<< "$cand"
}

# failing test files to pre-load that are not already listed, each <=30KB, total (listed + extras) <= OVN_FIXUP_FILES_BYTES, max 4 extras
ovn_fixup_extra_files() {
  local log="$1"; shift
  local total=0 f sz n=0
  for f in "$@"; do [ -f "$f" ] && total=$((total + $(wc -c < "$f" 2>/dev/null || echo 0))); done
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    case " $* " in *" $f "*) continue;; esac
    sz="$(wc -c < "$f" 2>/dev/null || echo 999999)"
    [ "$sz" -le 30000 ] || continue
    [ $((total + sz)) -le "$OVN_FIXUP_FILES_BYTES" ] || continue
    [ "$n" -lt 4 ] || break
    total=$((total + sz)); n=$((n + 1)); printf '%s\n' "$f"
  done < <(ovn_fixup_failing_test_files "$log")
}

ovn_fixup_prompt() {
  local headline="$1" before="$2" after="$3" evidence="$4" instr="$5"
  printf '%s\n\n' "$headline"
  printf 'The following change was just committed to this repository. It was made in an EARLIER, separate session: you have no memory of it, and nothing from the examples in your instructions is part of it. This is the actual diff (long diffs are truncated; the full current files are in the chat):\n\n'
  ovn_fixup_diff_facts "$before" "$after"
  printf '\nFAILURE (verbatim from the verify run):\n%s\n\n' "$evidence"
  printf 'IMPORTANT: ignore any example from your instructions (is_prime, sympy, mathweb, flask/app.py or anything like them). Those are unrelated to this repository and are NOT the change above. Work only on the failure above, in the files already in the chat.\n\n'
  printf '%s' "$instr"
}
