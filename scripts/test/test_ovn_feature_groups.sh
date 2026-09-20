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
mkdir -p "$tmp/repos/demo" "$tmp/backlog" "$tmp/state"
export OVN_QUEUE_DIR="$tmp" OVN_REPOS_DIR="$tmp/repos" OVN_BACKLOG_DIR="$tmp/backlog" OVN_TASK_STATS="$tmp/state/task_stats.log"

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

echo "ovn_feature_groups.py: $P passed, $F failed"
[ "$F" -eq 0 ]
