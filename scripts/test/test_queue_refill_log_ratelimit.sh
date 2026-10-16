#!/usr/bin/env bash
# Regression test (2026-10-10, F7): queue_refill.sh must not log the same dry-lane lines on every run. It runs at the end of every fleet cycle (idle lanes: ~every 90 s);
# logs/queue_refill.log reached 12 MB / 170k lines of "backlog DRY" / "still dry" / "pass complete". log_rl prints a repeated message once per QR_LOG_REPEAT_S, prints a
# CHANGED message at once, and QR_LOG_REPEAT_S=0 restores the old log-everything behaviour. The dry bookkeeping (qr_dry marker) is unaffected.
# Every case also runs against a MUTANT of the script (log_rl made a plain log) and must fail there.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="${OVN_QUEUE_REFILL:-$HERE/../../queue_refill.sh}"
[ -f "$Q" ] || Q="$HOME/overnight-queue/queue_refill.sh"
[ -f "$Q" ] || { echo "  SKIP: queue_refill.sh not found"; exit 0; }
P=0; F=0
# assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141)
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(__d="$(mktemp -d)" && [ -n "$__d" ] && cd "$__d" && pwd -P)" || exit 1; trap 'rm -rf "$tmp"' EXIT

# a private $HOME/overnight-queue (queue_refill.sh does `cd "$HOME/overnight-queue"`) per script variant
mkhome(){ # $1=dir $2=script
  local w="$1/overnight-queue"
  mkdir -p "$w/repos/foo" "$w/backlog" "$w/state" "$1/aider-venv/bin"
  cp "$2" "$w/queue_refill.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$w/queue.sh"; chmod +x "$w/queue.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$1/aider-venv/bin/curl"; chmod +x "$1/aider-venv/bin/curl"
  : > "$w/backlog/foo.md"; : > "$w/repos/foo/OVERNIGHT_PROGRESS.md"
}
run(){ # $1=home dir, rest = env assignments ; prints the script output
  local h="$1"; shift
  ( cd "$h/overnight-queue" && env HOME="$h" MIN_DOABLE=15 "$@" bash ./queue_refill.sh foo 2>&1 )
}
count(){ printf '%s\n' "$1" | grep -c -- "$2"; }

# ---- the real script
R="$tmp/real"; mkhome "$R" "$Q"
o1="$(run "$R")"; o2="$(run "$R")"; o3="$(run "$R")"
ok "run 1 (newly dry) logs the DRY line and the pass-complete line" "[ \"\$(count \"\$o1\" 'backlog DRY')\" = 1 ] && [ \"\$(count \"\$o1\" 'queue_refill pass complete')\" = 1 ]"
ok "run 2 (state unchanged, inside the window): no DRY line, no pass-complete; 'still dry' appears ONCE (first run that is dry-but-not-new)" "[ \"\$(count \"\$o2\" 'backlog DRY')\" = 0 ] && [ \"\$(count \"\$o2\" 'pass complete')\" = 0 ] && [ \"\$(count \"\$o2\" 'still dry')\" = 1 ]"
ok "run 3: completely quiet (no DRY, no 'still dry', no pass-complete)" "[ -z \"\$o3\" ]"
ok "the dry bookkeeping is unchanged (qr_dry marker exists; liveness stamp written)" "[ -f '$R/overnight-queue/state/qr_dry_foo' ] && [ -s '$R/overnight-queue/state/qr_last_pass' ]"

# a CHANGED message prints at once: a doable item appears (d=1, below MIN_DOABLE but with an empty backlog it is still DRY with a different count)
printf -- '- [ ] [T2] x — y\n' > "$R/overnight-queue/repos/foo/OVERNIGHT_PROGRESS.md"
o4="$(run "$R")"
ok "a changed message (1 doable instead of 0) is logged at once" "[ \"\$(count \"\$o4\" '1 doable')\" = 1 ]"
o5="$(run "$R" MIN_DOABLE=1)"
ok "a different state (doable >= MIN_DOABLE) is logged at once too (recovery wording)" "[ \"\$(count \"\$o5\" 'ok, no refill')\" = 1 ]"
o6="$(run "$R" MIN_DOABLE=1)"
ok "... and then stays quiet" "[ \"\$(count \"\$o6\" 'ok, no refill')\" = 0 ]"

# the window expires: the stamp in the state file is aged past QR_LOG_REPEAT_S -> the same message prints once more
printf '0\n%s\n' "$(sed -n 2p "$R/overnight-queue/state/qr_log_foo")" > "$R/overnight-queue/state/qr_log_foo"
o7="$(run "$R" MIN_DOABLE=1)"
ok "after the repeat window the unchanged message is printed once more" "[ \"\$(count \"\$o7\" 'ok, no refill')\" = 1 ]"

# kill switch
K="$tmp/off"; mkhome "$K" "$Q"
k1="$(run "$K" QR_LOG_REPEAT_S=0)"; k2="$(run "$K" QR_LOG_REPEAT_S=0)"; k3="$(run "$K" QR_LOG_REPEAT_S=0)"
ok "QR_LOG_REPEAT_S=0 restores the old behaviour (every run logs DRY / pass complete)" "[ \"\$(count \"\$k1\$k2\$k3\" 'backlog DRY')\" = 3 ] && [ \"\$(count \"\$k1\$k2\$k3\" 'pass complete')\" = 3 ]"
G="$tmp/garbage"; mkhome "$G" "$Q"
g1="$(run "$G" QR_LOG_REPEAT_S=abc)"; g2="$(run "$G" QR_LOG_REPEAT_S=abc)"
ok "a garbage QR_LOG_REPEAT_S falls back to the default window instead of crashing" "[ \"\$(count \"\$g1\" 'backlog DRY')\" = 1 ] && [ \"\$(count \"\$g2\" 'backlog DRY')\" = 0 ]"

# a corrupt state file never silences or crashes the log
printf 'junk\n' > "$R/overnight-queue/state/qr_log_foo"
o8="$(run "$R" MIN_DOABLE=1)"
ok "a corrupt state file: the line is printed (no crash)" "[ \"\$(count \"\$o8\" 'ok, no refill')\" = 1 ]"

# ---- round-3 review: (a) a plain log() line for the key (roadmap-ready) is a state change: the identical DRY line that follows it must NOT be swallowed as a repeat
mkroad(){ mkdir -p "$1/overnight-queue/roadmap"; printf -- '- [ ] [P1] [ready] build x\n' > "$1/overnight-queue/roadmap/foo.md"; }
S="$tmp/reset"; mkhome "$S" "$Q"
s1="$(run "$S")"; mkroad "$S"; s2="$(run "$S")"; rm -f "$S/overnight-queue/roadmap/foo.md"; s3="$(run "$S")"
ok "reset: DRY, then a roadmap-ready line, then the SAME DRY message: it is printed again (not mistaken for a repeat of run 1)" "[ \"\$(count \"\$s1\" 'backlog DRY')\" = 1 ] && [ \"\$(count \"\$s2\" 'planner will refill')\" = 1 ] && [ \"\$(count \"\$s3\" 'backlog DRY')\" = 1 ]"
# (b) the stamp is written atomically: through a temp file + mv (a mv shim in the venv bin dir records its calls), never by truncating the state file in place
A="$tmp/atomic"; mkhome "$A" "$Q"
printf '#!/bin/sh\necho "$@" >> "%s/mv.log"\nexec /bin/mv "$@"\n' "$A" > "$A/aider-venv/bin/mv"; chmod +x "$A/aider-venv/bin/mv"
run "$A" >/dev/null
ok "atomic: the state stamp was installed with mv from a temp file; no temp file is left behind" "grep -q 'qr_log_foo.tmp' '$A/mv.log' && [ -z \"\$(ls '$A/overnight-queue/state' | grep 'tmp')\" ] && [ \"\$(wc -l < '$A/overnight-queue/state/qr_log_foo' | tr -d ' ')\" = 2 ]"

# ---- the mutant: log_rl never suppresses -> the quiet-run assertions must fail
sed 's|if \[ "\$last_sig" = "\$sig" \] && \[ \$(( \$(date +%s) - last_ts )) -lt "\$QR_LOG_REPEAT_S" \]; then return 0; fi|:|' "$Q" > "$tmp/mutant.sh"
if cmp -s "$Q" "$tmp/mutant.sh"; then F=$((F+1)); echo "  FAIL: mutation anchor not found in queue_refill.sh"; else
  M="$tmp/mut"; mkhome "$M" "$tmp/mutant.sh"
  m1="$(run "$M")"; m2="$(run "$M")"; m3="$(run "$M")"
  ok "MUTATION caught: with the suppression removed run 3 is NOT quiet (the quiet-run check would fail)" "[ -n \"\$m3\" ] && [ \"\$(count \"\$m2\$m3\" 'backlog DRY')\" = 2 ]"
fi
# mutants for the round-3 checks
sed 's|^log_rl_reset(){.*|log_rl_reset(){ :; }|' "$Q" > "$tmp/mutant_reset.sh"
if cmp -s "$Q" "$tmp/mutant_reset.sh"; then F=$((F+1)); echo "  FAIL: reset mutation anchor not found"; else
  S2="$tmp/reset_m"; mkhome "$S2" "$tmp/mutant_reset.sh"
  x1="$(run "$S2")"; mkroad "$S2"; x2="$(run "$S2")"; rm -f "$S2/overnight-queue/roadmap/foo.md"; x3="$(run "$S2")"
  ok "MUTATION caught: without log_rl_reset the identical DRY line after a roadmap-ready line is swallowed" "[ \"\$(count \"\$x3\" 'backlog DRY')\" = 0 ]"
fi
sed -e 's|> "\$f.tmp.\$\$"|> "$f"|' -e 's|mv -f "\$f.tmp.\$\$" "\$f"|:|' "$Q" > "$tmp/mutant_atomic.sh"
if cmp -s "$Q" "$tmp/mutant_atomic.sh"; then F=$((F+1)); echo "  FAIL: atomic mutation anchor not found"; else
  A2="$tmp/atomic_m"; mkhome "$A2" "$tmp/mutant_atomic.sh"
  printf '#!/bin/sh\necho "$@" >> "%s/mv.log"\nexec /bin/mv "$@"\n' "$A2" > "$A2/aider-venv/bin/mv"; chmod +x "$A2/aider-venv/bin/mv"
  run "$A2" >/dev/null
  ok "MUTATION caught: an in-place write never goes through mv" "! grep -qs 'qr_log_foo.tmp' '$A2/mv.log'"
fi
echo; echo "queue_refill log ratelimit: $P passed, $F failed"
[ "$F" = 0 ]
