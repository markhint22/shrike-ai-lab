#!/usr/bin/env bash
# Tests for scripts/ovn_batch_stragglers.py (2026-09-25) — the low-grade "handling"
# companion to the letter-grade scorecard. Reads state/outcomes.jsonl and
# repos/<name>/OVERNIGHT_PROGRESS.md against a fixture $HOME (never touches
# production data), matching test_batch_scorecard.sh's convention.
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS_DIR:-$HOME/overnight-queue/scripts}"
SCRIPT="$SCRIPTS/ovn_batch_stragglers.py"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

if [ ! -f "$SCRIPT" ]; then
  echo "  SKIP: $SCRIPT not found on this host"
  echo "ovn_batch_stragglers.py: 0 passed, 0 failed"
  exit 0
fi

tmp="$(mktemp -d)"; export HOME="$tmp"
mkdir -p "$HOME/overnight-queue/state" "$HOME/overnight-queue/repos/fakerepo"
OUTF="$HOME/overnight-queue/state/outcomes.jsonl"
PROG="$HOME/overnight-queue/repos/fakerepo/OVERNIGHT_PROGRESS.md"
now="$(date +%s)"
ts_of(){ python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }
row(){ # tag class ago_h
  local tag="$1" cls="$2" ago_h="$3"
  local t=$(( now - ago_h * 3600 ))
  printf '{"repo":"fakerepo","feat_tag":"%s","class":"%s","ts":"%s"}\n' "$tag" "$cls" "$(ts_of "$t")"
}

# --- 1: no outcomes file -> prints nothing ---
out0="$(python3 "$SCRIPT" 2>&1)"
ok "missing outcomes.jsonl: prints nothing" "[ -z \"\$out0\" ]"

# --- 2: F-grade batch but UNDER min-sample (default 5) -> not flagged ---
: > "$OUTF"
{ row small-bad noop 30; row small-bad reverted 30; } >> "$OUTF"
printf -- '- [ ] [T1] a.py — thing. [feat:small-bad]\n' > "$PROG"
out1="$(python3 "$SCRIPT" 2>&1)"
ok "under min-sample: not flagged" "[ -z \"\$out1\" ]"

# --- 3: F-grade batch, min-sample met, but too YOUNG -> not flagged ---
: > "$OUTF"
for i in 1 2 3 4 5; do row young-bad noop 2 >> "$OUTF"; done
printf -- '- [ ] [T1] a.py — thing. [feat:young-bad]\n' > "$PROG"
out2="$(python3 "$SCRIPT" 2>&1)"
ok "under min-age: not flagged" "[ -z \"\$out2\" ]"

# --- 4: F-grade, sample+age met, HAS open stragglers -> flagged with correct fields ---
: > "$OUTF"
{ row real-bad landed 30; row real-bad noop 30; row real-bad noop 30; row real-bad reverted 30; row real-bad noop 30; } >> "$OUTF"
cat > "$PROG" << 'EOF'
- [ ] [T1] a.py — straggler one. [feat:real-bad]
- [ ] [T1] b.py — straggler two. [feat:real-bad]
- [x] [T1] c.py — already done. [feat:real-bad]
EOF
out3="$(python3 "$SCRIPT" --min-age-hours=24 --min-sample=5 2>&1)"
ok "flags the batch"                      "printf '%s' \"\$out3\" | grep -q '\"tag\": \"real-bad\"'"
ok "reports correct landed/n"             "printf '%s' \"\$out3\" | grep -q '\"landed\": 1, \"n\": 5'"
ok "reports correct pct (20)"             "printf '%s' \"\$out3\" | grep -q '\"pct\": 20'"
ok "reports straggler_count=2 (excludes the checked-off line)" "printf '%s' \"\$out3\" | grep -q '\"straggler_count\": 2'"
ok "straggler text includes item a"       "printf '%s' \"\$out3\" | grep -q 'straggler one'"
ok "straggler text includes item b"       "printf '%s' \"\$out3\" | grep -q 'straggler two'"
ok "does NOT include the already-checked item" "! printf '%s' \"\$out3\" | grep -q 'already done'"

# --- 5: same batch but grade is NOT F (>=25% landed) -> not flagged ---
: > "$OUTF"
{ row ok-batch landed 30; row ok-batch landed 30; row ok-batch noop 30; row ok-batch noop 30; row ok-batch noop 30; } >> "$OUTF"
printf -- '- [ ] [T1] a.py — thing. [feat:ok-batch]\n' > "$PROG"
out4="$(python3 "$SCRIPT" --min-age-hours=24 --min-sample=5 2>&1)"
ok "grade D/C/B/A (40%% landed): not flagged" "[ -z \"\$out4\" ]"

# --- 6: F-grade batch but ALL remaining items already AUTO-SKIP/HUMAN-ONLY tagged -> not flagged ---
: > "$OUTF"
{ row all-skipped noop 30; row all-skipped noop 30; row all-skipped noop 30; row all-skipped noop 30; row all-skipped reverted 30; } >> "$OUTF"
cat > "$PROG" << 'EOF'
- [ ] [AUTO-SKIP after 4 no-op cycles] [T1] a.py — thing. [feat:all-skipped]
- [ ] [HUMAN-ONLY BLOCKED] [T1] b.py — thing. [feat:all-skipped]
EOF
out5="$(python3 "$SCRIPT" --min-age-hours=24 --min-sample=5 2>&1)"
ok "batch with no un-parked stragglers left: not flagged" "[ -z \"\$out5\" ]"

echo "ovn_batch_stragglers.py: $P passed, $F failed"
[ "$F" -eq 0 ]
