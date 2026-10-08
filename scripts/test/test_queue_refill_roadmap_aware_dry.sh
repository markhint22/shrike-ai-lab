#!/usr/bin/env bash
# Regression test: queue_refill.sh's dry-detection must not treat "backlog empty right now" as
# equivalent to "genuinely out of work" when roadmap/<repo>.md still has a [ready] feature
# ovn_planner.sh will decompose into fresh backlog items on its own cadence (2026-09-28).
#
# Before this fix, queue_refill.sh only ever checked backlog/<repo>.md's CURRENT conforming
# line count. Confirmed live: shrike-monitor/test-automation-agent/shrike-notify sit at
# 0/184, 0/237, 1/169 conforming backlog lines far more often than a repo like gitlark
# (17/217) — their backlogs genuinely drain faster than ovn_planner.sh's refill cadence, not
# because they use a different pipeline. That made a transient, self-resolving "backlog just
# drained, planner will refill it soon" gap indistinguishable from a genuine "nothing left
# anywhere" dead end — both got the SAME escalating qr_dry_<repo> marker/reminder treatment,
# which correlated these repos with the ones ovn_fleet_health.sh flagged as starved.
set -uo pipefail
Q="${OVN_QUEUE_REFILL:-$HOME/overnight-queue/queue_refill.sh}"
[ -f "$Q" ] || { echo "  SKIP: $Q not found on this host"; exit 0; }

grep -q "roadmap/\$r.md" "$Q" || { echo "  FAIL: roadmap-aware dry check not found in $Q"; exit 1; }

P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
wd="$tmp/overnight-queue"
mkdir -p "$wd/repos/foo" "$wd/backlog" "$wd/roadmap" "$wd/state" "$tmp/aider-venv/bin"
cp "$Q" "$wd/queue_refill.sh"
cat > "$wd/queue.sh" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$wd/queue.sh"

ALERT_LOG="$tmp/curl.log"; : > "$ALERT_LOG"
cat > "$tmp/aider-venv/bin/curl" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in Title:*) echo "\$a" >> "$ALERT_LOG" ;; esac; done
exit 0
EOF
chmod +x "$tmp/aider-venv/bin/curl"

run_refill(){ ( cd "$wd" && HOME="$tmp" MIN_DOABLE="${1:-15}" ./queue_refill.sh foo 2>&1 ); }

# --- A: backlog empty, roadmap HAS a [ready] feature -> not marked dry, distinct log line ---
: > "$wd/backlog/foo.md"
: > "$wd/repos/foo/OVERNIGHT_PROGRESS.md"
printf -- '- [ ] [P2] [ready] Add rate limiting to the public API\n' > "$wd/roadmap/foo.md"
out="$(run_refill)"
ok "roadmap has [ready] feature: logs the distinct 'planner will refill' message" \
   "printf '%s' \"\$out\" | grep -q 'planner will refill'"
ok "roadmap has [ready] feature: does NOT create the qr_dry marker" "[ ! -f '$wd/state/qr_dry_foo' ]"
ok "roadmap has [ready] feature: does NOT log the genuine 'backlog DRY' line" \
   "! printf '%s' \"\$out\" | grep -q 'backlog DRY'"

# --- B: backlog empty, roadmap has NO [ready] feature (all decomposed/needs-research) ->
#     genuinely dry, same escalating treatment as before this fix ---
printf -- '- [ ] [P2] [decomposed] Add rate limiting to the public API\n- [ ] [P3] [needs-research] Something else\n' > "$wd/roadmap/foo.md"
out2="$(run_refill)"
ok "roadmap has no [ready] feature: logs the genuine 'backlog DRY' line" \
   "printf '%s' \"\$out2\" | grep -q 'backlog DRY'"
ok "roadmap has no [ready] feature: DOES create the qr_dry marker (real dry state)" \
   "[ -f '$wd/state/qr_dry_foo' ]"

# --- C: no roadmap file at all (repo predates roadmap-driven planning) -> unchanged old
#     behavior, same as case B (falls through safely, no crash on a missing file) ---
rm -f "$wd/roadmap/foo.md"
rm -f "$wd/state/qr_dry_foo"
out3="$(run_refill)"
ok "no roadmap file: falls back to the old genuine-dry behavior" \
   "printf '%s' \"\$out3\" | grep -q 'backlog DRY'"
ok "no roadmap file: marker is still created (unchanged fallback)" "[ -f '$wd/state/qr_dry_foo' ]"

# --- D: a repo that WAS genuinely dry recovers the moment its roadmap gets a [ready] feature
#     again (e.g. Claude promotes needs-research -> ready) -> marker clears, recovery note ---
: > "$ALERT_LOG"
printf -- '- [ ] [P2] [ready] Newly promoted feature\n' > "$wd/roadmap/foo.md"
run_refill >/dev/null
ok "roadmap regains a [ready] feature: clears a pre-existing dry marker" "[ ! -f '$wd/state/qr_dry_foo' ]"
ok "roadmap regains a [ready] feature: fires the recovery note" \
   "grep -q 'Backlog refilled' '$ALERT_LOG'"

echo "Queue-refill roadmap-aware dry check: $P passed, $F failed"
[ "$F" -eq 0 ]
