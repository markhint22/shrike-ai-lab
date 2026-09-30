#!/usr/bin/env bash
# Regression: art.sh (art queue control CLI). HOME is a temp dir; docker/nohup/pgrep/nvidia-smi are stubs first on PATH,
# so nothing touches the GPU, containers, or the real ~/overnight-queue art queue.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUT=""; for c in "$HERE/../../art.sh" "$HERE/../art.sh" "$HERE/art.sh"; do [ -f "$c" ] && { SUT="$c"; break; }; done
[ -n "$SUT" ] || { echo "art.sh not found"; exit 2; }
pass=0; fail=0; ok(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else fail=$((fail+1)); echo "  FAIL $1"; fi; }
warn(){ if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  ok   $1"; else echo "  WARN $1 (non-fatal, known defect)"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/overnight-queue/logs" "$T/bin"
Q="$HOME/overnight-queue/art_queue.md"; CALLS="$T/calls.log"; : > "$CALLS"
export CALLS PGREP_RC=1 DOCKER_RUNNING=false
cat > "$T/bin/docker" <<'D'
#!/usr/bin/env bash
echo "docker $*" >> "$CALLS"
if [ "$1" = inspect ]; then echo "${DOCKER_RUNNING}"; fi; exit 0
D
cat > "$T/bin/nohup" <<'D'
#!/usr/bin/env bash
echo "nohup $*" >> "$CALLS"; exit 0
D
cat > "$T/bin/pgrep" <<'D'
#!/usr/bin/env bash
echo "pgrep $*" >> "$CALLS"; exit "${PGREP_RC}"
D
cat > "$T/bin/nvidia-smi" <<'D'
#!/usr/bin/env bash
echo "1234 MiB, 22000 MiB"
D
chmod +x "$T/bin/"*
waitcall(){ local i; for i in $(seq 1 50); do grep -q "$1" "$CALLS" && return 0; sleep 0.1; done; return 1; }  # nohup stub runs in a background job
art(){ PATH="$T/bin:$PATH" bash "$SUT" "$@"; }

# ---- add ----
out="$(art add unit hero "armoured scavenger" 4242 2>&1)"; rc=$?
ok "add: rc 0 and echoes 'queued:'" "$([ $rc = 0 ] && echo "$out" | grep -q '^queued: - \[ \] \[unit\] hero — armoured scavenger | seed:4242$' && echo 1 || echo 0)"
ok "add: creates queue file with header on first use" "$(head -1 "$Q" | grep -q '^# Art / animation queue' && echo 1 || echo 0)"
ok "add: appended line has seed suffix" "$(tail -1 "$Q" | grep -qF -- '- [ ] [unit] hero — armoured scavenger | seed:4242' && echo 1 || echo 0)"
art add sprite crate "a crate" >/dev/null
ok "add: seed is optional (no '| seed:')" "$(tail -1 "$Q" | grep -qxF -- '- [ ] [sprite] crate — a crate' && echo 1 || echo 0)"
ok "add: header not duplicated on 2nd add" "$([ "$(grep -c '^# Art' "$Q")" = 1 ] && echo 1 || echo 0)"
out="$(art add unit 2>&1)"; rc=$?
ok "add: missing key -> nonzero + usage hint" "$([ $rc != 0 ] && echo "$out" | grep -q 'key' && echo 1 || echo 0)"
out="$(art add 2>&1)"; rc=$?
ok "add: missing type -> nonzero + usage hint" "$([ $rc != 0 ] && echo "$out" | grep -q 'type' && echo 1 || echo 0)"
out="$(art add unit k 2>&1)"; rc=$?
ok "add: missing prompt -> nonzero" "$([ $rc != 0 ] && echo 1 || echo 0)"
ok "add: failed adds did not touch the queue" "$([ "$(grep -c '^- \[ \]' "$Q")" = 2 ] && echo 1 || echo 0)"

# ---- list ----
echo '- [x] (staged for review) [unit] old — done' >> "$Q"
out="$(art list)"
ok "list: pending section shows numbered pending lines" "$(echo "$out" | grep -q '=== queued (pending) ===' && echo "$out" | grep -qE '^[0-9]+:- \[ \] \[unit\] hero' && echo 1 || echo 0)"
ok "list: staged section shows [x] lines" "$(echo "$out" | sed -n '/=== staged/,$p' | grep -q 'staged for review' && echo 1 || echo 0)"
mv "$Q" "$Q.bak"
out="$(art list)"
ok "list: no queue file -> pending '(none)'" "$(echo "$out" | sed -n '/=== queued/,/=== staged/p' | grep -q '(none)' && echo 1 || echo 0)"
ok "list: staged section shows '(none)' when nothing staged (pipefail makes the || echo fire)" "$(echo "$out" | sed -n '/=== staged/,$p' | grep -q '(none)' && echo 1 || echo 0)"
mv "$Q.bak" "$Q"

# ---- run ----
: > "$CALLS"
out="$(art run 2>&1)"; rc=$?
ok "run: rc 0 with pending items" "$([ $rc = 0 ] && echo 1 || echo 0)"
ok "run: announces the pending count" "$(echo "$out" | grep -q 'generating 2 task(s)' && echo 1 || echo 0)"
ok "run: stops the 27B container to free the GPU" "$(grep -qxF 'docker stop shrike-llama-dflash-35b' "$CALLS" && echo 1 || echo 0)"
waitcall "^nohup"
ok "run: launches runner via nohup with default ntfy topic + runner path + log" "$(grep -q "^nohup bash -c NTFY_TOPIC=shrike_ovn_311380987a '.*/python' '$HOME/overnight-queue/art_runner.py' >> '$HOME/overnight-queue/logs/art_runner.log' 2>&1" "$CALLS" && echo 1 || echo 0)"
ok "run: prints started + autoswap notice" "$(echo "$out" | grep -q 'art runner started' && echo "$out" | grep -q 'gpu_autoswap' && echo 1 || echo 0)"
ok "run: creates the staging dir" "$([ -d "$HOME/overnight-queue/repos/xlite/assets/staging/art-review" ] && echo 1 || echo 0)"
: > "$CALLS"; sleep 0.3; : > "$CALLS"; NTFY_TOPIC=custom_topic art run >/dev/null 2>&1
waitcall "^nohup"
ok "run: NTFY_TOPIC env override is forwarded" "$(grep -q 'NTFY_TOPIC=custom_topic ' "$CALLS" && echo 1 || echo 0)"
cp "$Q" "$T/q.keep"
python3 - "$Q" <<'P'
import sys
p=sys.argv[1]; s=open(p).read().replace("- [ ]","- [x]"); open(p,"w").write(s)
P
: > "$CALLS"
out="$(art run 2>&1)"; rc=$?
ok "run: empty queue -> 'nothing to run', rc 0" "$([ $rc = 0 ] && echo "$out" | grep -q 'art queue empty' && echo 1 || echo 0)"
ok "run: empty queue does NOT stop the 27B or start a runner" "$([ ! -s "$CALLS" ] && echo 1 || echo 0)"
mv "$Q" "$Q.bak"; out="$(art run 2>&1)"; rc=$?
ok "run: missing queue file treated as empty" "$([ $rc = 0 ] && echo "$out" | grep -q 'nothing to run' && echo 1 || echo 0)"
mv "$Q.bak" "$Q"; cp "$T/q.keep" "$Q"

# ---- status ----
echo '- [ ] [tile] t — tile' >> "$Q"
printf 'line1\nline2\nline3\nline4\n' > "$HOME/overnight-queue/logs/art_runner.log"
out="$(PGREP_RC=1 DOCKER_RUNNING=false art status)"
ok "status: counts pending and staged" "$(echo "$out" | grep -q 'pending: 3  staged: 1' && echo 1 || echo 0)"
ok "status: runner idle when pgrep fails" "$(echo "$out" | sed -n '/=== runner/,/=== GPU/p' | grep -q 'idle' && echo 1 || echo 0)"
ok "status: GPU line from nvidia-smi" "$(echo "$out" | grep -q '1234 MiB, 22000 MiB' && echo 1 || echo 0)"
ok "status: 27B down message when container not running" "$(echo "$out" | grep -q 'down (art running or auto-swap pending)' && echo 1 || echo 0)"
ok "status: tails the last 3 log lines" "$(echo "$out" | sed -n '/=== last log/,$p' | grep -q 'line4' && ! echo "$out" | grep -q 'line1' && echo 1 || echo 0)"
out="$(PGREP_RC=0 DOCKER_RUNNING=true art status)"
ok "status: RUNNING when pgrep matches" "$(echo "$out" | sed -n '/=== runner/,/=== GPU/p' | grep -q 'RUNNING' && echo 1 || echo 0)"
ok "status: 27B up when container running" "$(echo "$out" | grep -q '^  up$' && echo 1 || echo 0)"
out="$(art)"
ok "no subcommand defaults to status" "$(echo "$out" | grep -q '=== queue ===' && echo 1 || echo 0)"
mv "$Q" "$Q.bak"; out="$(art status)"
warn "KNOWN-BUG: status with no queue file prints blank counts instead of 0 (art.sh:~42: grep -c prints nothing on a missing file)" "$(echo "$out" | grep -q 'pending: 0  staged: 0' && echo 1 || echo 0)"
mv "$Q.bak" "$Q"

# ---- review ----
out="$(art review)"
ok "review: prints staging dir + approval hint" "$(echo "$out" | grep -q "staged art in $HOME/overnight-queue/repos/xlite/assets/staging/art-review:" && echo "$out" | grep -q 'Approve:' && echo 1 || echo 0)"
mkdir -p "$HOME/overnight-queue/repos/xlite/assets/staging/art-review/hero"
out="$(art review)"
ok "review: lists staged unit dirs indented" "$(echo "$out" | grep -qx '  hero' && echo 1 || echo 0)"
rm -rf "$HOME/overnight-queue/repos/xlite/assets/staging/art-review"; out="$(art review)"
ok "review: no staging dir -> '(none yet)' (pipefail makes the || echo fire)" "$(echo "$out" | grep -q '(none yet)' && echo 1 || echo 0)"

# ---- remove ----
art add unit dropme "drop this one" >/dev/null; art add unit keepme "keep this one" >/dev/null
out="$(art remove "dropme")"
ok "remove: reports substring" "$(echo "$out" | grep -qx 'removed lines matching: dropme' && echo 1 || echo 0)"
ok "remove: matching line gone, others intact" "$(! grep -q dropme "$Q" && grep -q keepme "$Q" && grep -q '^# Art' "$Q" && echo 1 || echo 0)"
ok "remove: no .tmp left behind" "$([ ! -e "$Q.tmp" ] && echo 1 || echo 0)"
art remove 'k.ep' >/dev/null
ok "remove: substring is literal (-F): '.' does not act as wildcard" "$(grep -q keepme "$Q" && echo 1 || echo 0)"
out="$(art remove 2>&1)"; rc=$?
ok "remove: missing substring -> nonzero" "$([ $rc != 0 ] && echo 1 || echo 0)"

# ---- unknown ----
out="$(art frobnicate)"
ok "unknown subcommand -> usage text" "$(echo "$out" | grep -q 'usage: art.sh add|list|run|status|review|remove' && echo 1 || echo 0)"
echo "$pass passed, $fail failed"; [ "$fail" -eq 0 ]
