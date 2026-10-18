#!/usr/bin/env bash
# 2026-10-18 xlite audit: stage_ctx_exceeded must recognise litellm's real overflow text (the runner filed three xlite overflows as no-edit and never shrank the prompt).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_osr_fixture.sh"
. "$HERE/../lib_stage_guards.sh"
D="$( { declare -F safe_mktemp_dir >/dev/null 2>&1 && safe_mktemp_dir; } || mktemp -d "${TMPDIR:-/tmp}/ctxexc.XXXXXX")" || exit 1; [ -n "$D" ] && [ -d "$D" ] || exit 1; trap 'rm -rf "$D"' EXIT
# verbatim from state/stage_runs/xlite-20261018-001658-1981516-s0.log (aider 0.86.2 + litellm)
cat > "$D/real.log" <<'LOG'
Your estimated chat context of 70,394 tokens exceeds the 55,000 token limit for
openai/qwen-dflash-27B!
litellm.BadRequestError: OpenAIException - litellm.ContextWindowExceededError:
litellm.BadRequestError: ContextWindowExceededError: OpenAIException - request
(73789 tokens) exceeds the available context size (65536 tokens), try increasing
it
LOG
printf 'The request exceeds the available context size (65536 tokens)\n' > "$D/wrapped.log"
printf 'Applied edit to scripts/a.gd\nTokens: 5.7k sent, 2.1k received.\n' > "$D/ok.log"
printf 'the file defines a context_menu and a size limit that was exceeded by 3 items\n' > "$D/benign.log"
printf 'context size has been exceeded\n' > "$D/old.log"
old_regex(){ grep -qiE 'context size has been exceeded|context length|context_length|prompt is too long|exceed_context' "$1"; }
t "C1 the real litellm overflow log is recognised" stage_ctx_exceeded "$D/real.log"
t "C2 MUTANT: the old regex did NOT match that log (the live defect)" bash -c "$(declare -f old_regex); ! old_regex '$D/real.log'"
t "C3 a line-wrapped 'exceeds the available context size' is recognised" stage_ctx_exceeded "$D/wrapped.log"
t "C4 the old wording still matches" stage_ctx_exceeded "$D/old.log"
t "C5 a normal successful aider log is not an overflow" bash -c "$(declare -f stage_ctx_exceeded); ! stage_ctx_exceeded '$D/ok.log'"
t "C6 benign prose containing 'context' and 'exceeded' separately is not an overflow" bash -c "$(declare -f stage_ctx_exceeded); ! stage_ctx_exceeded '$D/benign.log'"
t "C7 a missing file is not an overflow" bash -c "$(declare -f stage_ctx_exceeded); ! stage_ctx_exceeded '$D/nope.log'"
osr_summary
