#!/usr/bin/env bash
# Regression test: ovn_hygiene_stuck_check.sh must escalate a persistently-stuck
# branch_hygiene.sh gate instead of leaving it silent forever (2026-09-10).
#
# Real incidents this closes: branch_hygiene.sh already writes a
# state/branch_hygiene_review_<repo> flag on every failure (gate red, conflict, push failed,
# worktree failed) and clears it on success — but nothing ever read that flag to alert a human.
# gitlark sat stuck 9h (a broken frozen-contract test) and billwatch sat stuck 17h (98 commits
# piled up) before either was found — both by manually reading logs, not by any notification.
# Verifies the full sequence: newly-stuck (silent) -> crosses threshold (ONE alert) -> still
# stuck immediately after (silent, cooldown) -> still stuck past the reminder window (ONE
# reminder) -> recovers (ONE recovery note, markers cleared) -> a blip that recovers BEFORE
# crossing the threshold never alerts at all (no noise for transient failures).
set -uo pipefail
H="${OVN_HYGIENE_STUCK_CHECK:-$HOME/overnight-queue/ovn_hygiene_stuck_check.sh}"
[ -f "$H" ] || { echo "  SKIP: $H not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
wd="$tmp/overnight-queue"
mkdir -p "$wd/state" "$tmp/bin"
cp "$H" "$wd/ovn_hygiene_stuck_check.sh"

ALERT_LOG="$tmp/alerts.log"; : > "$ALERT_LOG"
cat > "$tmp/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do echo "\$a" >> "$ALERT_LOG"; done
exit 0
EOF
chmod +x "$tmp/bin/curl"

run(){ ( cd "$wd" && HOME="$tmp" PATH="$tmp/bin:$PATH" bash ovn_hygiene_stuck_check.sh >/dev/null 2>&1 ); }

echo "gate FAILED (build/tests red): overnight/feature +5" > "$wd/state/branch_hygiene_review_gitlark"
run
ok "newly-stuck fires no alert yet" "[ ! -s '$ALERT_LOG' ]"
ok "newly-stuck creates the since-marker" "[ -f '$wd/state/hygiene_stuck_since_gitlark' ]"

echo $(( $(date +%s) - 3*3600 )) > "$wd/state/hygiene_stuck_since_gitlark"
run
ok "crossing the 2h threshold fires exactly one STUCK alert" \
   "[ \$(grep -c 'Branch hygiene STUCK: gitlark' '$ALERT_LOG') -eq 1 ]"

: > "$ALERT_LOG"
run; run
ok "still-stuck immediately after: no repeat alert (cooldown)" "[ ! -s '$ALERT_LOG' ]"

echo $(( $(date +%s) - 7*3600 )) > "$wd/state/hygiene_stuck_alerted_gitlark"
run
ok "still-stuck past the reminder window fires exactly one reminder" \
   "[ \$(grep -c 'Branch hygiene STILL STUCK: gitlark' '$ALERT_LOG') -eq 1 ]"

: > "$ALERT_LOG"
rm -f "$wd/state/branch_hygiene_review_gitlark"
run
ok "recovery after crossing threshold fires exactly one recovery note" \
   "[ \$(grep -c 'Branch hygiene recovered: gitlark' '$ALERT_LOG') -eq 1 ]"
ok "recovery clears both markers" \
   "[ ! -f '$wd/state/hygiene_stuck_since_gitlark' ] && [ ! -f '$wd/state/hygiene_stuck_alerted_gitlark' ]"

# a transient blip that recovers BEFORE crossing the threshold must never alert at all
: > "$ALERT_LOG"
echo "gate FAILED: overnight/feature +2" > "$wd/state/branch_hygiene_review_billwatch"
run
rm -f "$wd/state/branch_hygiene_review_billwatch"
run
ok "a blip that recovers before the threshold never alerts" "[ ! -s '$ALERT_LOG' ]"
ok "a blip that recovers before the threshold leaves no stray markers" \
   "[ ! -f '$wd/state/hygiene_stuck_since_billwatch' ]"

rm -rf "$tmp"
echo "Hygiene-stuck check: $P passed, $F failed"
[ "$F" -eq 0 ]
