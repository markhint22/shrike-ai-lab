#!/usr/bin/env bash
# 2026-10-09 (harness-credit-integrity item 10): ovn_aider_attempt_verdict <log-slice-file> -> applied | nomatch-partial | no-edit-unfenced | no-edit,
# plus ovn_udiff_retry_decision (what the implement loop does with it) and the loop wiring.
# Fixtures in fixtures/aider_attempt/ are REAL slices cut (read-only) from the box's logs/<ts>/ongoing-xlite.log:
#   real_enemy_faction_map_nomatch_partial_commit.txt  20261009-062549 lines 32-137: 'UnifiedDiffNoMatch: hunk failed to apply!' then aider's partial 'Commit c1d004f' (the
#                                                      enemy_scaling.gd / enemy_faction_map.gd shape: a half-applied edit committed, cut where that invocation ended)
#   real_enemy_faction_map_nomatch_then_recovered.txt  the SAME run through line 187: aider's reflection re-sent a good diff, 'Applied edit' + 'Commit 76601d6' => applied
#   real_tech_tree_inline_diff.txt                     20261007-104309 lines 33-95: the model wrote the diff INLINE (headers collapsed onto one line, '+' lines became bullets):
#                                                      nothing applied (the dot_damage.gd inline-diff shape)
#   real_dot_damage_applied.txt                        20261008-151215: a clean 'Applied edit' + 'Commit'
#   real_no_changes_needed.txt                         20261008-071927: prose 'I will produce no diff' - a legitimate no-edit
# The platform.gd blank-only hunk has no surviving log; it is reconstructed below from the incident description (synthetic, labelled).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; RUN="$S/../run_overnight.sh"; FX="$HERE/fixtures/aider_attempt"
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
# shellcheck disable=SC1090
. "$S/lib_fixup.sh"
v(){ ovn_aider_attempt_verdict "$1"; }

# ---- real slices ----
ok "real: NoMatch then aider's partial commit (cut where the invocation ended) => nomatch-partial" "[ \"\$(v '$FX/real_enemy_faction_map_nomatch_partial_commit.txt')\" = nomatch-partial ]"
ok "real: the same run through the self-corrected 'Applied edit' => applied (a recovered NoMatch must NOT be reset)" "[ \"\$(v '$FX/real_enemy_faction_map_nomatch_then_recovered.txt')\" = applied ]"
ok "real: inline diff (headers collapsed, bullets), nothing applied => no-edit-unfenced" "[ \"\$(v '$FX/real_tech_tree_inline_diff.txt')\" = no-edit-unfenced ]"
ok "real: clean 'Applied edit' + Commit (zero-context additions hunk) => applied" "[ \"\$(v '$FX/real_dot_damage_applied.txt')\" = applied ]"
ok "real: 'I will produce no diff' prose => no-edit (not unfenced: nothing to re-ask for)" "[ \"\$(v '$FX/real_no_changes_needed.txt')\" = no-edit ]"

# ---- synthetic shapes ----
# platform.gd blank-only hunk (reconstruction): a rendered code block whose hunk lines are all blank
printf '%s\n' 'Added scripts/platform.gd to the chat.' '' 'I will tidy the blank line.' '' '--- scripts/platform.gd' '+++ scripts/platform.gd' '@@ -10,3 +10,3 @@ static func classify(features: PackedStringArray) -> int:' ' ' '-' '+' '' 'Tokens: 9k sent, 60 received.' > "$W/blank_only.log"
ok "synthetic (platform.gd): rendered diff whose hunk is blank-only, nothing applied => no-edit-unfenced" "[ \"\$(v '$W/blank_only.log')\" = no-edit-unfenced ]"
# the same with a real ```diff fence
printf '%s\n' 'Here is the change:' '```diff' '--- scripts/platform.gd' '+++ scripts/platform.gd' '@@ -10,3 +10,3 @@' ' ' '-' '+' '```' 'Tokens: 9k sent, 60 received.' > "$W/blank_fenced.log"
ok "synthetic: a real fenced diff block with a blank-only hunk => no-edit-unfenced" "[ \"\$(v '$W/blank_fenced.log')\" = no-edit-unfenced ]"
# fenced diff, zero context lines, real change, nothing applied
printf '%s\n' '```diff' '--- a/x.gd' '+++ b/x.gd' '@@ -5,0 +6,2 @@' '+var a = 1' '+var b = 2' '```' > "$W/zero_ctx.log"
ok "synthetic: fenced zero-context hunk that did not apply => no-edit-unfenced" "[ \"\$(v '$W/zero_ctx.log')\" = no-edit-unfenced ]"
# a well-formed diff with context that simply did not apply (no error text) is NOT re-asked
printf '%s\n' '--- scripts/x.gd' '+++ scripts/x.gd' '@@ -5,3 +5,4 @@ func f():' ' 	var a = 1' '+	var b = 2' ' 	return a' ' ' > "$W/wellformed.log"
ok "control: a well-formed rendered diff with context lines and no aider error => no-edit (not unfenced)" "[ \"\$(v '$W/wellformed.log')\" = no-edit ]"
# stray hunk marker with no code block at all
printf '%s\n' 'I would change it like this: @@ -17,6 +17,8 @@ const X := { and add two entries.' '@@ -17,6 +17,8 @@ const X := {' 'Tokens: 1k sent, 2 received.' > "$W/stray.log"
ok "synthetic: a stray '@@ ' hunk marker with no code block => no-edit-unfenced" "[ \"\$(v '$W/stray.log')\" = no-edit-unfenced ]"
# NoMatch with NOTHING applied or committed: not a partial
printf '%s\n' 'UnifiedDiffNoMatch: hunk failed to apply!' 'x.gd does not contain lines that match the diff you provided!' > "$W/nomatch_only.log"
ok "NoMatch with nothing applied/committed => no-edit (the existing flow handles it; nothing to reset)" "[ \"\$(v '$W/nomatch_only.log')\" = no-edit ]"
# 'did not match' is aider's only with its own frame
printf '%s\n' 'The LLM did not conform to the edit format.' 'The hunk did not match the file.' 'Applied edit to a.gd' 'Commit abc1234 x' > "$W/framed.log"
printf '%s\n' 'I checked and the old code did not match what the item describes, so I stop.' > "$W/prose.log"
ok "'did not match' next to aider's 'did not conform to the edit format' frame counts as NoMatch, a recovery after it is applied" "[ \"\$(v '$W/framed.log')\" = applied ]"
printf '%s\n' 'The LLM did not conform to the edit format.' 'The hunk did not match the file.' 'Commit abc1234 half' > "$W/framed_partial.log"
ok "'did not match' with the aider frame and a commit and NO later 'Applied edit' => nomatch-partial" "[ \"\$(v '$W/framed_partial.log')\" = nomatch-partial ]"
ok "prose containing 'did not match' WITHOUT aider's frame is not a NoMatch => no-edit" "[ \"\$(v '$W/prose.log')\" = no-edit ]"
printf '%s\n' 'Applied edit to a.gd' 'Commit abc1234 first' 'UnifiedDiffNoMatch: hunk failed to apply!' > "$W/applied_then_nomatch.log"
ok "'Applied edit' + Commit, THEN a NoMatch as the last event => nomatch-partial" "[ \"\$(v '$W/applied_then_nomatch.log')\" = nomatch-partial ]"
: > "$W/empty.log"
ok "empty slice => no-edit" "[ \"\$(v '$W/empty.log')\" = no-edit ]"
ok "missing file => no-edit (never crashes)" "[ \"\$(v '$W/nonexistent.log')\" = no-edit ]"
printf '%s\n' 'Applied edit to a.gd' > "$W/applied_nocommit.log"
ok "'Applied edit' without a Commit line (staged runner / --no-auto-commits) => applied" "[ \"\$(v '$W/applied_nocommit.log')\" = applied ]"
printf '%s\n' 'Commit abc1234 something' > "$W/commit_only.log"
ok "a Commit line alone => applied" "[ \"\$(v '$W/commit_only.log')\" = applied ]"

# ---- the loop's decision ----
d(){ ovn_udiff_retry_decision "$@"; }
ok "decision: nomatch-partial, first time, tree moved => reset-retry" "[ \"\$(d nomatch-partial 0 0 1)\" = reset-retry ]"
ok "decision: nomatch-partial a SECOND time => none (retry once)" "[ \"\$(d nomatch-partial 1 0 1)\" = none ]"
ok "decision: nomatch-partial but nothing to discard (tree clean) => none" "[ \"\$(d nomatch-partial 0 0 0)\" = none ]"
ok "decision: no-edit-unfenced, first time, tree unchanged => nudge-retry" "[ \"\$(d no-edit-unfenced 0 0 0)\" = nudge-retry ]"
ok "decision: no-edit-unfenced a SECOND time => none" "[ \"\$(d no-edit-unfenced 0 1 0)\" = none ]"
ok "decision: no-edit-unfenced but the tree changed => none" "[ \"\$(d no-edit-unfenced 0 0 1)\" = none ]"
ok "decision: the nomatch retry flag does not block the unfenced retry (independent budgets)" "[ \"\$(d no-edit-unfenced 1 0 0)\" = nudge-retry ]"
ok "decision: applied / no-edit => none" "[ \"\$(d applied 0 0 1)\" = none ] && [ \"\$(d no-edit 0 0 0)\" = none ]"
ok "kill switch OVN_UDIFF_RETRY=off => none for every verdict" "[ \"\$(OVN_UDIFF_RETRY=off d nomatch-partial 0 0 1)\" = none ] && [ \"\$(OVN_UDIFF_RETRY=off d no-edit-unfenced 0 0 0)\" = none ]"
# nudge text
N="$(ovn_udiff_nudge_text)"
ok "nudge text is exactly the specified sentence (fenced diff, 3 lines of context, enclosing func/def line)" "[ \"\$N\" = 'Your reply had no fenced \`\`\`diff block or used a zero-context hunk. Resend the change as a fenced \`\`\`diff block with at least 3 lines of unchanged context and the exact enclosing \`func\`/\`def\` line.' ]"

# ---- simulate the loop's decision sequence end to end for the real slices ----
seq(){ # slice -> decision at first sight, tree-moved derived from the verdict shape (partial commit => moved)
  local verdict moved=0; verdict="$(v "$1")"; [ "$verdict" = nomatch-partial ] && moved=1
  ovn_udiff_retry_decision "$verdict" 0 0 "$moved"; }
ok "loop simulation: the partial-commit slice => reset-retry; the inline-diff slice => nudge-retry; the recovered and applied slices => none" "[ \"\$(seq '$FX/real_enemy_faction_map_nomatch_partial_commit.txt')\" = reset-retry ] && [ \"\$(seq '$FX/real_tech_tree_inline_diff.txt')\" = nudge-retry ] && [ \"\$(seq '$FX/real_enemy_faction_map_nomatch_then_recovered.txt')\" = none ] && [ \"\$(seq '$FX/real_dot_damage_applied.txt')\" = none ]"

# ---- wiring (code lines) ----
ok "run_overnight.sh classifies each implement attempt's own log slice and consults ovn_udiff_retry_decision" "[ \"\$(grep -c 'ovn_aider_attempt_verdict \"\$_ovn_slice\"' '$RUN')\" = 1 ] && [ \"\$(grep -c 'case \"\$(ovn_udiff_retry_decision ' '$RUN')\" = 1 ]"
ok "the pre-attempt sha and log offset are captured before the aider call" "[ \"\$(grep -c '^      _ovn_att_sha=\"\$(git rev-parse HEAD)\"; _ovn_att_off=' '$RUN')\" = 1 ]"
ok "retry flags start at 0 once per implement loop" "[ \"\$(grep -c '^    _ovn_retry_nm=0; _ovn_retry_unf=0' '$RUN')\" = 1 ]"
ok "the verdict step sits BEFORE the commit-detection (NOW_SHA) block, so a partial commit is seen before it ends the loop" "[ \"\$(grep -n 'ovn_aider_attempt_verdict \"\$_ovn_slice\"' '$RUN' | head -1 | cut -d: -f1)\" -lt \"\$(grep -n '^      NOW_SHA=\"\$(git rev-parse HEAD)\"' '$RUN' | head -1 | cut -d: -f1)\" ]"
# ---- MUTATION controls ----
python3 - "$S/lib_fixup.sh" "$W" <<'PY'
import sys
s = open(sys.argv[1]).read()
def mut(a, b, out):
    assert s.count(a) == 1, a
    open(sys.argv[2] + "/" + out, "w").write(s.replace(a, b))
mut('    if pa > pn:\n        print("applied")', '    if False:\n        print("applied")', "m_recover.sh")
mut('if not real or not ctx:', 'if False:', "m_blank.sh")
mut('elif inline or stray:', 'elif False:', "m_inline.sh")
PY
ok "MUTATION: without the 'recovered after NoMatch' rule the self-corrected real slice is wrongly nomatch-partial (it would be reset)" "[ \"\$( ( . '$W/m_recover.sh'; ovn_aider_attempt_verdict '$FX/real_enemy_faction_map_nomatch_then_recovered.txt' ) )\" = nomatch-partial ]"
ok "MUTATION: without the blank/zero-context rule the blank-only hunk is wrongly no-edit" "[ \"\$( ( . '$W/m_blank.sh'; ovn_aider_attempt_verdict '$W/blank_only.log' ) )\" = no-edit ]"
ok "MUTATION: without the inline rule the real inline-diff slice is wrongly no-edit" "[ \"\$( ( . '$W/m_inline.sh'; ovn_aider_attempt_verdict '$FX/real_tech_tree_inline_diff.txt' ) )\" = no-edit ]"
echo "$P passed, $F failed"; [ "$F" -eq 0 ]
