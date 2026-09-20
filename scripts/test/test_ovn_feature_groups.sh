#!/usr/bin/env bash
# Tests for scripts/ovn_feature_groups.py (2026-09-20) — feature-level %-complete tracking +
# completion detection. See that script's own header for the full investigation: a real
# roadmap/<repo>.md feature-grouping structure exists, but the link from a decomposed item
# back to its parent feature was thrown away once the item left backlog/<repo>.md; this script
# groups by the new durable [feat:ID] tag when present (real), and falls back to grouping by
# target file when absent (an explicitly-labeled approximation, never used for completion
# pushes). Runs entirely against a fixture OVN_QUEUE_DIR so it never touches production data.
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS_DIR:-$HOME/overnight-queue/scripts}"
SCRIPT="$SCRIPTS/ovn_feature_groups.py"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

if [ ! -f "$SCRIPT" ]; then
  echo "  SKIP: $SCRIPT not found on this host"
  echo "ovn_feature_groups.py: 0 passed, 0 failed"
  exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repos/demo" "$tmp/backlog" "$tmp/state" "$tmp/roadmap"
export OVN_QUEUE_DIR="$tmp" OVN_REPOS_DIR="$tmp/repos" OVN_BACKLOG_DIR="$tmp/backlog" OVN_TASK_STATS="$tmp/state/task_stats.log" OVN_ROADMAP_DIR="$tmp/roadmap"

# --- 1: a real [feat:] group, partially done, not yet complete ---
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
- [ ] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
EOF
: > "$tmp/repos/demo/OVERNIGHT_DONE.md"
: > "$tmp/backlog/demo.md"
out1="$(python3 "$SCRIPT" demo --json 2>&1)"
ok "partial feat group reports 1/2 (50%)" "printf '%s' \"\$out1\" | grep -q '\"checked\": 1, \"total\": 2'"
ok "partial feat group is NOT done" "printf '%s' \"\$out1\" | grep -q '\"done\": false'"

# --- 2: landing the last item marks it done, but ONLY once the backlog has nothing left queued for it ---
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
- [x] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
EOF
echo '- [ ] [T3] `app/c.py` — more. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]' >> "$tmp/backlog/demo.md"
out2="$(python3 "$SCRIPT" demo --json 2>&1)"
ok "fully-checked-but-backlog-still-has-work is NOT reported done" "printf '%s' \"\$out2\" | grep -q '\"done\": false'"
ok "backlog_remaining reflects the still-queued item" "printf '%s' \"\$out2\" | grep -q '\"backlog_remaining\": 1'"

: > "$tmp/backlog/demo.md"
out3="$(python3 "$SCRIPT" demo --json 2>&1)"
ok "fully-checked AND backlog empty -> reported done" "printf '%s' \"\$out3\" | grep -q '\"done\": true'"

# --- 3: items with no [feat:] tag fall back to file-based approximate grouping ---
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T1] `app/shared.py` — fix 1. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `app/shared.py` — fix 2. VERIFY: x. (cat:python; multifile:no)
EOF
: > "$tmp/backlog/demo.md"
out4="$(python3 "$SCRIPT" demo 2>&1)"
ok "untagged items are grouped by shared target file" "printf '%s' \"\$out4\" | grep -q 'shared.py: 2/2'"
ok "file-based grouping is explicitly labeled approximate" "printf '%s' \"\$out4\" | grep -qi 'approx'"

# --- 3b: a code-snippet backtick that merely LOOKS extension-shaped (e.g. ends in "1.0" or
# "OS.execute") must NOT be mistaken for a target file. Confirmed live on a real xlite scan:
# ~15 of ~49 "file" groups were exactly this false-positive shape before the fix.
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T1] `static func get_multiplier(is_flanking: bool) -> float: return 1.5 if is_flanking else 1.0` — thing. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `static func get_multiplier(is_flanking: bool) -> float: return 1.5 if is_flanking else 1.0` — thing2. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `OS.execute` — thing. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `OS.execute` — thing2. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `app/real.gd` — thing. VERIFY: x. (cat:godot; multifile:no)
- [x] [T1] `app/real.gd` — thing2. VERIFY: x. (cat:godot; multifile:no)
EOF
: > "$tmp/backlog/demo.md"
out4b="$(python3 "$SCRIPT" demo --json 2>&1)"
ok "a code-snippet ending in a number is not treated as a file" "! printf '%s' \"\$out4b\" | grep -q 'else 1.0'"
ok "a dotted method call is not treated as a file" "! printf '%s' \"\$out4b\" | grep -q 'OS.execute'"
ok "a real .gd file is still correctly grouped" "printf '%s' \"\$out4b\" | grep -q 'app/real.gd'"

# --- 4: a group below --min-total is not reported at all ---
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T1] `app/lonely.py` — the only item touching this file. VERIFY: x. (cat:python; multifile:no)
EOF
out5="$(python3 "$SCRIPT" demo 2>&1)"
ok "a single-item file group is not reported (min-total default 2)" "[ -z \"\$out5\" ]"

# --- 5: --digest cross-references recent landed activity (task_stats.log) against groups ---
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
- [ ] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-widget]
EOF
now="$(date +%s)"
printf '%s\tdemo\tpass\t{py.other.T2.tested}\tapp/a.py\n' "$now" > "$tmp/state/task_stats.log"
out6="$(python3 "$SCRIPT" --digest 3 2>&1)"
ok "digest mode surfaces the touched group's progress" "printf '%s' \"\$out6\" | grep -q 'demo-20260101-widget: 1/2'"

# a group that had NO activity in the window is not surfaced even if it exists
cat >> "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T1] `app/other.py` — old. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `app/other.py` — old2. VERIFY: x. (cat:python; multifile:no)
EOF
out7="$(python3 "$SCRIPT" --digest 3 2>&1)"
ok "an untouched-this-window group is not surfaced in the digest" "! printf '%s' \"\$out7\" | grep -q 'other.py'"

# --- 6: feature_title() re-derives ovn_planner.sh's slug (from the FULL remaining roadmap
# line text - title + why + tags - not just the title) to resolve a [feat:ID] tag to a
# human-readable title. See ovn_planner.sh's own feat_id minting comment for why the slug
# has to come from the whole line, not just the title.
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-bill-caching-done-c-1]
- [ ] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-bill-caching-done-c-1]
EOF
: > "$tmp/backlog/demo.md"
cat > "$tmp/roadmap/demo.md" <<'EOF'
- [ ] [P2] [decomposed] Bill Caching — done. {c:1}
EOF
out8="$(python3 -c "
import sys; sys.path.insert(0, '$SCRIPTS')
import ovn_feature_groups as ofg
print(ofg.feature_title('demo', 'demo-20260101-bill-caching-done-c-1'))
" 2>&1)"
ok "feature_title resolves a real roadmap line to its human title" "[ \"\$out8\" = 'Bill Caching' ]"
out9="$(python3 -c "
import sys; sys.path.insert(0, '$SCRIPTS')
import ovn_feature_groups as ofg
print(ofg.feature_title('demo', 'demo-20260101-no-such-slug'))
" 2>&1)"
ok "feature_title returns None (never fabricates) when no roadmap line's slug matches" "[ \"\$out9\" = 'None' ]"

# --- 7: --in-progress lists every real, not-yet-done feat group across ALL repos, with its
# resolved title, and NEVER a file-kind approximate group.
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-bill-caching-done-c-1]
- [ ] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-bill-caching-done-c-1]
- [x] [T1] `app/shared.py` — fix 1. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `app/shared.py` — fix 2. VERIFY: x. (cat:python; multifile:no)
EOF
: > "$tmp/backlog/demo.md"
out10="$(python3 "$SCRIPT" --in-progress 2>&1)"
ok "in-progress shows the real feat group with its human title, not the raw id" \
  "printf '%s' \"\$out10\" | grep -q 'demo \"Bill Caching\" — 1/2 items (50%)'"
ok "in-progress never surfaces the file-based approximate group" \
  "! printf '%s' \"\$out10\" | grep -q 'shared.py'"

# a feat group that's already done (100% + nothing left in the backlog) is NOT "in progress"
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T2] `app/a.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-bill-caching-done-c-1]
- [x] [T2] `app/b.py` — thing. VERIFY: x. (cat:python; multifile:no) [feat:demo-20260101-bill-caching-done-c-1]
EOF
: > "$tmp/backlog/demo.md"
out11="$(python3 "$SCRIPT" --in-progress 2>&1)"
ok "a fully-done feat group is not listed as in-progress" "[ -z \"\$out11\" ]"

# --- 8: --ready-count prints a single integer - real feat groups that are BOTH done and
# had a landed item in the trailing window (the digest's "N feature(s) ready to test" line).
now="$(date +%s)"
printf '%s\tdemo\tpass\t{py.other.T2.tested}\tapp/b.py\n' "$now" > "$tmp/state/task_stats.log"
out12="$(python3 "$SCRIPT" --ready-count 3 2>&1)"
ok "ready-count is 1 when a real feat group just completed in-window" "[ \"\$out12\" = '1' ]"
old_ts=$(( now - 30 * 3600 ))   # 30h ago, outside a 3h window
printf '%s\tdemo\tpass\t{py.other.T2.tested}\tapp/b.py\n' "$old_ts" > "$tmp/state/task_stats.log"
out13="$(python3 "$SCRIPT" --ready-count 3 2>&1)"
ok "ready-count is 0 once the completing landed row falls outside the window" "[ \"\$out13\" = '0' ]"

# --- 9: ovn_planner.sh's own decompose format does NOT backtick-wrap the target file (only
# inline code snippets and the VERIFY command are backticked) - confirmed live on a real
# xlite item. The file must still be recorded via the bare leading-token fallback, not
# silently dropped (which would leave every planner-decomposed [feat:] group's `files` set
# permanently empty and break feature-to-landed-item attribution for all NEW features).
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [ ] [T1] app/ap_pool.py — Add `static func percent_full(current, cap)` that returns 0 if `cap <= 0`. VERIFY: `grep -q "percent_full" app/ap_pool.py`. (cat:python; multifile:no) [feat:demo-20260101-real-planner-format]
- [ ] [T2] tests/test_ap_pool.py — Add `test_percent_full_zero_cap`. VERIFY: pytest tests/test_ap_pool.py. (cat:test; multifile:no) [feat:demo-20260101-real-planner-format]
EOF
: > "$tmp/backlog/demo.md"
out14="$(python3 -c "
import sys; sys.path.insert(0, '$SCRIPTS')
import ovn_feature_groups as ofg
print(ofg.feat_lookup_for_file('demo', 'app/ap_pool.py'))
" 2>&1)"
ok "a planner-format item's bare (non-backtick) target file is still recorded and matchable" \
  "printf '%s' \"\$out14\" | grep -q 'demo-20260101-real-planner-format'"
# the false-positive guards from test 3b must still hold with the new fallback in place
cat > "$tmp/repos/demo/OVERNIGHT_PROGRESS.md" <<'EOF'
- [x] [T1] `static func get_multiplier(is_flanking: bool) -> float: return 1.5 if is_flanking else 1.0` — thing. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `static func get_multiplier(is_flanking: bool) -> float: return 1.5 if is_flanking else 1.0` — thing2. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `OS.execute` — thing. VERIFY: x. (cat:python; multifile:no)
- [x] [T1] `OS.execute` — thing2. VERIFY: x. (cat:python; multifile:no)
EOF
: > "$tmp/backlog/demo.md"
out15="$(python3 "$SCRIPT" demo --json 2>&1)"
ok "the bare-leading-token fallback does not resurrect the code-snippet false positives" \
  "[ \"\$out15\" = '[]' ]"

echo "ovn_feature_groups.py: $P passed, $F failed"
[ "$F" -eq 0 ]
