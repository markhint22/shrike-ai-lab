#!/usr/bin/env bash
# Tests for scripts/ovn_batch_scorecard.py (2026-09-25 letter-grade redesign).
# Reads state/outcomes.jsonl against a fixture $HOME so it never touches production
# data (same convention as test_ovn_landed_detail.sh).
set -uo pipefail
SCRIPTS="${OVN_SCRIPTS_DIR:-$HOME/overnight-queue/scripts}"
SCRIPT="$SCRIPTS/ovn_batch_scorecard.py"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

if [ ! -f "$SCRIPT" ]; then
  echo "  SKIP: $SCRIPT not found on this host"
  echo "ovn_batch_scorecard.py: 0 passed, 0 failed"
  exit 0
fi

tmp="$(mktemp -d)"; export HOME="$tmp"; mkdir -p "$HOME/overnight-queue/state"
OUTF="$HOME/overnight-queue/state/outcomes.jsonl"
now="$(date +%s)"
ts_of(){ python3 -c "import time,sys; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(int(sys.argv[1]))))" "$1"; }

row(){ # repo tag class ts_ago_hours
  local repo="$1" tag="$2" cls="$3" ago_h="$4"
  local t=$(( now - ago_h * 3600 ))
  printf '{"repo":"%s","feat_tag":"%s","class":"%s","ts":"%s","tokens_sent":100,"tokens_recv":100}\n' \
    "$repo" "$tag" "$cls" "$(ts_of "$t")"
}

# --- 1: missing file prints nothing ---
out0="$(python3 "$SCRIPT" 2>&1)"
ok "missing outcomes.jsonl: prints nothing" "[ -z \"\$out0\" ]"

# --- 2: a batch younger than min-age-hours (default 24) is excluded entirely ---
: > "$OUTF"
row billwatch bw-fresh landed 2 >> "$OUTF"
out1="$(python3 "$SCRIPT" 2>&1)"
ok "batch younger than 24h is excluded" "[ -z \"\$out1\" ]"

# --- 3: grade bucketing — A/B/C/D/F assigned correctly by land-rate ---
: > "$OUTF"
{
  # A: 100% (2/2)
  row repoA a-tag landed 30; row repoA a-tag landed 30
  # B: 80% (4/5)
  row repoB b-tag landed 30; row repoB b-tag landed 30; row repoB b-tag landed 30; row repoB b-tag landed 30; row repoB b-tag noop 30
  # C: 50% (1/2)
  row repoC c-tag landed 30; row repoC c-tag noop 30
  # D: 33% (1/3)
  row repoD d-tag landed 30; row repoD d-tag noop 30; row repoD d-tag noop 30
  # F: 0% (0/2)
  row repoF f-tag noop 30; row repoF f-tag reverted 30
} >> "$OUTF"
out2="$(python3 "$SCRIPT" --worst=100 2>&1)"
ok "shows the header with total batch count"      "printf '%s' \"\$out2\" | grep -q '5 batch(es)'"
ok "grade distribution shows A: 1 batch"           "printf '%s' \"\$out2\" | grep -qE 'A \\(90-100%\\)\\s+1 batch'"
ok "grade distribution shows B: 1 batch"           "printf '%s' \"\$out2\" | grep -qE 'B \\(75-89%\\)\\s+1 batch'"
ok "grade distribution shows C: 1 batch"           "printf '%s' \"\$out2\" | grep -qE 'C \\(50-74%\\)\\s+1 batch'"
ok "grade distribution shows D: 1 batch"           "printf '%s' \"\$out2\" | grep -qE 'D \\(25-49%\\)\\s+1 batch'"
ok "grade distribution shows F: 1 batch"           "printf '%s' \"\$out2\" | grep -qE 'F \\(0-24%\\)\\s+1 batch'"
ok "detail list includes the D batch"              "printf '%s' \"\$out2\" | grep -q 'd-tag'"
ok "detail list includes the F batch"              "printf '%s' \"\$out2\" | grep -q 'f-tag'"
ok "detail list does NOT include the A batch"      "! printf '%s' \"\$out2\" | grep -q 'a-tag'"
ok "detail list does NOT include the C batch"      "! printf '%s' \"\$out2\" | grep -q 'c-tag'"
ok "summary trailer reports flagged=2 (D+F)"       "printf '%s' \"\$out2\" | grep -q '#SUMMARY.*flagged=2'"
ok "summary trailer reports total=5"               "printf '%s' \"\$out2\" | grep -q '#SUMMARY total=5'"

# --- 4: --worst caps the detail list and adds a footer instead of silently dropping ---
out3="$(python3 "$SCRIPT" --worst=1 2>&1)"
ok "worst=1 shows only 1 detail line (the F batch, worst first)" "printf '%s' \"\$out3\" | grep -q 'f-tag'"
ok "worst=1 does NOT show the D batch in detail"                  "! printf '%s' \"\$out3\" | grep -q 'd-tag'"
ok "worst=1 explicitly footers the hidden count"                  "printf '%s' \"\$out3\" | grep -q '1 more D/F batch'"
ok "summary trailer is UNCHANGED by the --worst cap (still flagged=2)" "printf '%s' \"\$out3\" | grep -q '#SUMMARY.*flagged=2'"

# --- 5: an all-healthy fleet reports zero flagged, no alarming detail section ---
: > "$OUTF"
{ row repoH h-tag landed 30; row repoH h-tag landed 30; } >> "$OUTF"
out4="$(python3 "$SCRIPT" 2>&1)"
ok "all-A fleet: flagged=0 in summary"          "printf '%s' \"\$out4\" | grep -q '#SUMMARY.*flagged=0'"
ok "all-A fleet: says nothing needs a look"     "printf '%s' \"\$out4\" | grep -q 'nothing needs a look'"

echo "ovn_batch_scorecard.py: $P passed, $F failed"
[ "$F" -eq 0 ]
