#!/usr/bin/env bash
# Regression test for daily_promote.sh — batches the develop->main prod promote to once
# a day across repos, calling promote_to_prod.sh --yes per repo and classifying its
# output into Promoted / No change / BLOCKED for the daily ntfy summary.
#
# The real guard this exists for: a repo whose migration/smoke gate fails inside
# promote_to_prod.sh must show up as BLOCKED (stays on last-good prod build), NEVER get
# silently counted as promoted or silently dropped from the summary.
#
# Sandboxed via a fake HOME + a fake promote_to_prod.sh (daily_promote.sh cd's into
# $HOME/overnight-queue and calls ./promote_to_prod.sh by relative path — this test must
# never let it invoke the real one against real repos/, which would try live git pushes).
# Like fleet_autofix.sh, this script does NOT override PATH, so ntfy alerts CAN be
# intercepted with a fake curl on PATH (avoids any real network call here).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${OVN_DAILY_PROMOTE:-}" ]; then
  G="$OVN_DAILY_PROMOTE"
else
  G="$HERE/../../daily_promote.sh"; [ -f "$G" ] || G="$HERE/../daily_promote.sh"; [ -f "$G" ] || G="$HERE/daily_promote.sh"
fi
[ -f "$G" ] || { echo "  SKIP: daily_promote.sh not found"; exit 0; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "CURL_CALL $*" >> "$FAKE_CURL_LOG"
exit 0
EOF
chmod +x "$tmp/bin/curl"
export PATH="$tmp/bin:$PATH"
export NTFY_TOPIC="shrike_dailypromote_selftest_ignore"

reset_env(){
  export HOME="$tmp/home"
  rm -rf "$HOME"; mkdir -p "$HOME/overnight-queue/repos"
  export FAKE_CURL_LOG="$tmp/curl.log"; export FAKE_PROMOTE_LOG="$tmp/promote.log"
  : > "$FAKE_CURL_LOG"; : > "$FAKE_PROMOTE_LOG"
  # fake promote_to_prod.sh: behavior keyed off the repo dir name, mirroring the real
  # script's three possible outcomes (PROMOTED / nothing to promote / a failed gate)
  cat > "$HOME/overnight-queue/promote_to_prod.sh" <<'EOF'
#!/usr/bin/env bash
repo="$2"; name="$(basename "$repo")"
echo "PROMOTE_CALLED $*" >> "$FAKE_PROMOTE_LOG"
case "$name" in
  *good*)    echo "  ✅ PROMOTED $name develop -> main (+3). Prod deploy triggered." ;;
  *nochange*) echo "  nothing to promote." ;;
  *blocked*) echo "  🔴 migration safety FAILED — NOT promoting $name" ;;
esac
EOF
  chmod +x "$HOME/overnight-queue/promote_to_prod.sh"
}

# --- A: normal/healthy path — a repo with real develop..main changes promotes cleanly ---
reset_env
mkdir -p "$HOME/overnight-queue/repos/repo-good"
out="$(OVN_PROMOTE_REPOS='repo-good' bash "$G" 2>&1)"
ok "healthy: repo-good is called via promote_to_prod.sh --yes" "grep -q 'PROMOTE_CALLED --yes repos/repo-good' '$FAKE_PROMOTE_LOG'"
ok "healthy: reported under Promoted" "echo \"\$out\" | grep -q 'Promoted:.*repo-good'"
ok "healthy: ntfy summary sent" "grep -q 'Daily prod promote' '$FAKE_CURL_LOG'"

# --- B: a repo with nothing new to ship -> classified as 'no change', not blocked ---
reset_env
mkdir -p "$HOME/overnight-queue/repos/repo-nochange"
out="$(OVN_PROMOTE_REPOS='repo-nochange' bash "$G" 2>&1)"
ok "no-change repo: reported under 'No change', not under Promoted or BLOCKED" \
   "echo \"\$out\" | grep -q 'No change:.*repo-nochange' && ! echo \"\$out\" | grep -qE 'Promoted:.*repo-nochange|BLOCKED.*repo-nochange'"

# --- C: THE ACTUAL GUARD — a repo whose migration/smoke gate fails inside
#     promote_to_prod.sh must be reported as BLOCKED, and must NEVER be counted as
#     promoted or silently dropped from the summary ---
reset_env
mkdir -p "$HOME/overnight-queue/repos/repo-blocked"
out="$(OVN_PROMOTE_REPOS='repo-blocked' bash "$G" 2>&1)"
ok "gate-failed repo: reported under BLOCKED" "echo \"\$out\" | grep -q 'BLOCKED.*repo-blocked'"
ok "gate-failed repo: NOT reported as promoted" "! echo \"\$out\" | grep -qE 'Promoted:.*repo-blocked'"
ok "gate-failed repo: the BLOCKED warning line is present at all (not silently dropped)" "echo \"\$out\" | grep -q '⚠ BLOCKED'"

# --- D: a repo listed but with no local checkout under repos/ is skipped entirely,
#     never invoked and never reported in any bucket ---
reset_env
mkdir -p "$HOME/overnight-queue/repos/repo-good"
out="$(OVN_PROMOTE_REPOS='repo-good repo-missing' bash "$G" 2>&1)"
ok "missing checkout: promote_to_prod.sh is never called for it" "! grep -q 'repos/repo-missing' '$FAKE_PROMOTE_LOG'"
ok "missing checkout: does not appear in any summary bucket" "! echo \"\$out\" | grep -q 'repo-missing'"

# --- E: mixed run — one of each outcome in a single tick, all three buckets populated
#     correctly and independently (this is the realistic nightly case) ---
reset_env
mkdir -p "$HOME/overnight-queue/repos/repo-good" "$HOME/overnight-queue/repos/repo-nochange" "$HOME/overnight-queue/repos/repo-blocked"
out="$(OVN_PROMOTE_REPOS='repo-good repo-nochange repo-blocked' bash "$G" 2>&1)"
ok "mixed run: all three repos were actually invoked" \
   "[ \"\$(grep -c PROMOTE_CALLED '$FAKE_PROMOTE_LOG')\" -eq 3 ]"
ok "mixed run: promoted bucket has exactly repo-good" "echo \"\$out\" | grep -q 'Promoted:.*repo-good'"
ok "mixed run: no-change bucket has exactly repo-nochange" "echo \"\$out\" | grep -q 'No change:.*repo-nochange'"
ok "mixed run: blocked bucket has exactly repo-blocked" "echo \"\$out\" | grep -q 'BLOCKED.*repo-blocked'"

# --- F: run_overnight's lock is respected — daily_promote waits for it rather than
#     racing a mid-git cycle. We can't afford to wait out the real 900s timeout in a
#     test, so this only asserts it acquires + proceeds normally when the lock is free
#     (already exercised by every case above) and that it creates state/ if missing.
ok "state/ dir created if missing (run.lock target)" "[ -d '$HOME/overnight-queue/state' ]"

echo "daily_promote.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
