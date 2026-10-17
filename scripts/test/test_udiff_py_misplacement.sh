#!/usr/bin/env bash
# 2026-10-17 (gitlark review): size-independent unanchored-hunk detection for PYTHON docstring-only and re-declaration hunks.
#
# Real failure (box ~/overnight-queue/repos/gitlark, overnight/feature, 10-17 00:30-08:50 CDT): `supply:missing-docstring` items were answered with context-free udiff hunks
# (`@@ -25,0 +26 @@` + one `"""..."""` line).  aider appends such a hunk at the END of the file.  The files were < 300 lines, so ovn_udiff_anchor.py (min 300) let them through; a bare
# string after the last statement keeps pytest green, so the commit landed (ac1c3a13 project_config.py router: docstrings after `return config`; 7e3b268a reactions.py: three
# bare strings after the last class; 2ecb4680 reactions.py: `class MessageReactionResponse(BaseModel):` RE-DECLARED at EOF, shadowing the real class).  The item's own VERIFY
# (ast.get_docstring) then failed -> landed-uncredited -> 2 credit refusals -> park -> recovery -> 3 more repair commits: ~3h of cycles for 4 docstrings.
# Mutation control: the pre-fix detector (git show of the parent commit) must NOT flag these shapes (proves the test fails without the fix).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ANCHOR="$RO_Q/scripts/ovn_udiff_anchor.py"
W="$T/w"; mkdir -p "$W"
R="$W/repo"; mkdir -p "$R/backend/app/services" "$R/backend/tests"; git init -q "$R" 2>/dev/null
python3 - "$R" <<'PY'
import sys
r = sys.argv[1]
open(r + "/backend/app/services/reactions.py", "w").write(
    "from pydantic import BaseModel\n\n\nclass MessageReactionResponse(BaseModel):\n    id: int\n    emoji: str\n\n\n"
    "async def get_message_reactions(db, message_id):\n    counts = {}\n    for r in db:\n        counts[r] = 1\n    return counts\n\n\nclass Svc:\n    def get_message_reactions(self, db, message_id):\n        return {}\n")
open(r + "/backend/tests/test_x.py", "w").write("def test_a():\n    assert True\n")
PY
git -C "$R" add -A; git -C "$R" commit -q -m base; SHA="$(git -C "$R" rev-parse HEAD)"
scan(){ python3 "${ANCHOR_BIN:-$ANCHOR}" "$@"; }
F=backend/app/services/reactions.py
mk(){ printf '%s\n' "--- $F" "+++ $F" "$@" > "$W/h.log"; }
echo "== python docstring-only / re-declaration hunks on a SMALL file =="
mk '@@ -13,0 +14,2 @@' '+    """Count reactions per emoji for a message."""' '+'
ok "PYD1 docstring-only context-free hunk on a small .py file is flagged (was silently landed)" "$([ "$(scan "$W/h.log" "$R" --rev "$SHA" | grep -c "^$F	[0-9]*	@@ -13,0 +14,2 @@")" = 1 ] && echo 1 || echo 0)"
mk '@@ -14,0 +15,3 @@' '+    """Schema for creating a new message reaction."""' '+    """Represents a single user'"'"'s reaction to a message."""' '+    """A conversation message enriched with its aggregated reaction data."""'
ok "PYD2 three bare docstrings appended (the real 7e3b268a shape) is flagged" "$([ -n "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ -13,0 +14,6 @@' '+class MessageReactionResponse(BaseModel):' '+    """Represents a single user'"'"'s reaction to a message."""' '+'
ok "PYD3 re-declaring an existing top-level class at EOF (the real 2ecb4680 shape) is flagged" "$([ -n "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ -13,0 +14,3 @@' '+' '+async def get_message_reactions(db, message_id):' '+    return {}'
ok "PYD4 re-declaring an existing top-level def at EOF is flagged" "$([ -n "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ -13,0 +14,3 @@' '+' '+async def brand_new_helper(db):' '+    return {}'
ok "PYD5 a genuinely NEW module-level def appended at EOF stays tolerated (not flagged; small file)" "$([ -z "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ ... @@' ' class MessageReactionResponse(BaseModel):' '+    """Represents a single reaction."""' '     id: int'
ok "PYD6 a docstring hunk WITH context lines is anchored: not flagged" "$([ -z "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ -13,0 +14,2 @@' '+    x = 1' '+    y = 2'
ok "PYD7 non-docstring indented code hunk on a small file keeps the old (size-gated) behaviour: not flagged" "$([ -z "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ -13,0 +14,2 @@' '+    """Count reactions per emoji for a message."""' '+'
ok "PYD8 OVN_UDIFF_PY_DOCSTRING_ANY_SIZE=off restores the old behaviour" "$([ -z "$(OVN_UDIFF_PY_DOCSTRING_ANY_SIZE=off scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
T2=backend/tests/test_x.py
printf '%s\n' "--- $T2" "+++ $T2" '@@ -2,0 +3,1 @@' '+    """doc"""' > "$W/t.log"
ok "PYD9 test files stay exempt" "$([ -z "$(scan "$W/t.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
printf '%s\n' '--- /dev/null' "+++ backend/app/services/new.py" '@@ -0,0 +1,1 @@' '+"""Module doc."""' > "$W/n.log"
ok "PYD10 a brand-new file (module docstring) is never flagged" "$([ -z "$(scan "$W/n.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ -53,0 +54,3 @@ class Svc:' '+    def get_message_reactions(self, db, message_id):' '+        """Return counts."""' '+'
ok "PYD11 re-declaring an existing METHOD (identical signature line, the real billing.py price_for_tier shape) is flagged" "$([ -n "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
mk '@@ -13,0 +14,2 @@' '+    def totally_new_method(self):' '+        return 1'
ok "PYD12 a NEW indented method (no existing signature) keeps the old size-gated behaviour: not flagged" "$([ -z "$(scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
# mutation control: the detector as of the parent commit must miss PYD1..PYD4
if git -C "$RO_Q" rev-parse --git-dir >/dev/null 2>&1 && [ -z "${PYM_TEST_NO_MUTATION:-}" ]; then
  git -C "$RO_Q" show "HEAD:scripts/overnight-queue/scripts/ovn_udiff_anchor.py" > "$W/anchor_head.py" 2>/dev/null || git -C "$RO_Q" show "HEAD:scripts/ovn_udiff_anchor.py" > "$W/anchor_head.py" 2>/dev/null
  if [ -s "$W/anchor_head.py" ] && ! grep -q py_docstring_only "$W/anchor_head.py"; then
    mk '@@ -13,0 +14,2 @@' '+    """Count reactions per emoji for a message."""' '+'
    ok "MUTATION: the pre-fix detector (HEAD) misses the small-file docstring hunk (PYD1 would FAIL without the fix)" "$([ -z "$(ANCHOR_BIN="$W/anchor_head.py" scan "$W/h.log" "$R" --rev "$SHA")" ] && echo 1 || echo 0)"
  else
    echo "  (mutation control skipped: HEAD already carries the fix)"
  fi
fi
ro_summary
