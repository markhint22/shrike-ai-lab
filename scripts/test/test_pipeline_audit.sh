#!/usr/bin/env bash
# Regression test: ovn_pipeline_audit.sh's own checks must not produce false CRITICALs
# (2026-09-10).
#
# Real incident this closes: the audit's first live run reported 2 false CRITICALs that
# would have paged someone for nothing: (1) the lock-holder check used
# `fuser file | tr -d ' '` which mashes multiple space-separated PIDs (fuser can report
# several, e.g. "503939 503978 503979") into one unparseable concatenated string that never
# matches a real PID, so ANY multi-holder lock (the normal case for a shell pipeline holding
# a lock file across several file descriptors) was flagged as "orphaned"; (2) the LiteLLM
# check used `curl -fsS`, which treats any non-2xx as failure — but LiteLLM's own /health
# endpoint correctly returns 401 Unauthorized without an API key, which is proof the service
# IS up, not down. Both were caught by manually verifying the "critical" findings against
# raw `fuser`/`curl -v` output before trusting them - this test locks that verification in
# so the same two false-positive patterns can't silently regress.
set -uo pipefail
A="${OVN_PIPELINE_AUDIT:-$HOME/overnight-queue/ovn_pipeline_audit.sh}"
[ -f "$A" ] || { echo "  SKIP: $A not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
mkdir -p "$tmp/bin"

# --- extract the two real check blocks verbatim from the live script (sed by section
# marker, same convention as other tests in this suite) rather than reimplementing the
# logic, so the test tracks the actual production code, not a paraphrase of it. ---
lock_block="$(sed -n '/^section "5\. Locks/,/^section "6\. Core service/p' "$A" | sed '$d' | grep -v '^section ')"
litellm_block="$(sed -n '/^section "6\. Core service/,/^if \[ -f state\/PAUSED/p' "$A" | sed '$d' | grep -v '^section ')"

run_block(){  # $1=block text, $2=extra setup (sourced before), stdout captured
  ( cd "$tmp/wd" && PATH="$tmp/bin:$PATH" bash -c "
      crit(){ echo \"[CRIT] \$*\"; }
      warn(){ echo \"[WARN] \$*\"; }
      pass(){ echo \"[OK] \$*\"; }
      $2
      $1
  " )
}

mkdir -p "$tmp/wd/state"

# --- A: fuser reports multiple space-separated PIDs, all live -> must NOT be flagged CRIT ---
touch "$tmp/wd/state/run.lock"
cat > "$tmp/bin/fuser" <<'EOF'
#!/usr/bin/env bash
echo "$1: 11111 22222 33333"
EOF
chmod +x "$tmp/bin/fuser"
cat > "$tmp/bin/ps" <<'EOF'
#!/usr/bin/env bash
# only 33333 is "alive" - simulates the real-world case of stale + live fds mixed
for a in "$@"; do
  if [ "$a" = "33333" ]; then echo "fake-live-cmd"; exit 0; fi
done
exit 1
EOF
chmod +x "$tmp/bin/ps"
out="$(run_block "$lock_block" "")"
ok "multi-PID lock holder with at least one live PID is NOT flagged critical" \
   "! echo \"\$(cat <<<'$out')\" | grep -q CRIT"
ok "multi-PID lock holder is reported OK, not as an orphan" \
   "echo \"$out\" | grep -q 'held by live PID'"

# --- B: fuser reports PIDs but NONE are live -> genuinely orphaned, MUST still be flagged ---
cat > "$tmp/bin/ps" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/bin/ps"
out="$(run_block "$lock_block" "")"
ok "a genuinely orphaned lock (no live holder at all) still trips CRIT" \
   "echo \"$out\" | grep -q CRIT"

# --- C: lock file exists but fuser finds no holder at all (already released) -> reported OK ---
touch "$tmp/wd/state/run.lock"
cat > "$tmp/bin/fuser" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$tmp/bin/fuser"
out="$(run_block "$lock_block" "")"
ok "an existing but unheld lock file is reported OK, not flagged" \
   "echo \"$out\" | grep -q 'not currently held' && ! echo \"$out\" | grep -q CRIT"
rm -f "$tmp/wd/state/run.lock"

# --- C: LiteLLM /health returns 401 (needs an API key) -> service IS up, must NOT be CRIT ---
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
# emulate `curl -s -o /dev/null --max-time 5 -w '%{http_code}' ...` returning 401
echo -n "401"
EOF
chmod +x "$tmp/bin/curl"
cat > "$tmp/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$tmp/bin/systemctl"
out="$(run_block "$litellm_block" "")"
ok "LiteLLM returning HTTP 401 (auth required, but responding) is NOT flagged critical" \
   "! echo \"$out\" | grep -q 'NOT reachable'"
ok "LiteLLM returning HTTP 401 is reported reachable" \
   "echo \"$out\" | grep -q 'is reachable'"

# --- D: LiteLLM genuinely down (curl gets no response at all, http_code 000) -> MUST flag ---
cat > "$tmp/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo -n "000"
EOF
chmod +x "$tmp/bin/curl"
out="$(run_block "$litellm_block" "")"
ok "LiteLLM genuinely unreachable (curl returns 000) still trips critical" \
   "echo \"$out\" | grep -q 'NOT reachable'"

echo
echo "test_pipeline_audit: $P passed, $F failed"
[ "$F" -eq 0 ]
