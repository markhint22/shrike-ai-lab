#!/usr/bin/env bash
# Regression test for gpu_autoswap.sh — the GPU auto-swap watcher that restores the
# 27B llama container whenever the 3090 frees up, and must NEVER try to start it while
# something else (art gen, training) is holding enough VRAM (that would OOM the GPU).
#
# Sandboxed entirely: fake `docker`/`nvidia-smi`/`ps`/`curl`/`sleep` on PATH (no real
# GPU/docker calls, no real ntfy traffic, no 2min real sleep loop) and a fake HOME (so
# state/logs are throwaway, never touching the real host's state).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
if [ -n "${OVN_GPU_AUTOSWAP:-}" ]; then
  G="$OVN_GPU_AUTOSWAP"
else
  G="$HERE/../../gpu_autoswap.sh"; [ -f "$G" ] || G="$HERE/../gpu_autoswap.sh"; [ -f "$G" ] || G="$HERE/gpu_autoswap.sh"
fi
[ -f "$G" ] || { echo "  SKIP: gpu_autoswap.sh not found"; exit 0; }

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

cat > "$tmp/bin/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$tmp/bin/docker" <<'EOF'
#!/usr/bin/env bash
echo "DOCKER_CALL $*" >> "$FAKE_DOCKER_LOG"
case "$1" in
  inspect) echo "${FAKE_RUNNING:-false}" ;;
  exec) [ "${FAKE_HEALTHY:-0}" = "1" ] && exit 0 || exit 1 ;;
  ps) echo -n "${FAKE_DUP:-}" ;;
  start) exit 0 ;;
  rm) exit 0 ;;
  *) exit 0 ;;
esac
EOF

cat > "$tmp/bin/nvidia-smi" <<'EOF'
#!/usr/bin/env bash
echo "NVSMI_CALL $*" >> "$FAKE_NVSMI_LOG"
args="$*"
case "$args" in
  *query-gpu=memory.used*) echo "${FAKE_USED:-0}, ${FAKE_TOTAL:-24000}" ;;
  *query-compute-apps=pid,used_memory*) echo "${FAKE_HOLDERS:-}" ;;
  *query-compute-apps=pid\ --format*) echo "${FAKE_TOP_PID:-}" ;;
  *) echo "" ;;
esac
EOF

cat > "$tmp/bin/ps" <<'EOF'
#!/usr/bin/env bash
field=""
for a in "$@"; do
  case "$a" in
    cmd=) field=cmd ;;
    etime=) field=etime ;;
    etimes=) field=etimes ;;
  esac
done
case "$field" in
  cmd) echo "${FAKE_TOP_CMD:-fake-training-job}" ;;
  etime) echo "${FAKE_TOP_ET:-00:33:00}" ;;
  etimes) echo "${FAKE_TOP_SECS:-2000}" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/"*

reset_env(){
  export HOME="$tmp/home"
  rm -rf "$HOME"; mkdir -p "$HOME/overnight-queue/state" "$HOME/overnight-queue/logs"
  export FAKE_CURL_LOG="$tmp/curl.log"; export FAKE_DOCKER_LOG="$tmp/docker.log"; export FAKE_NVSMI_LOG="$tmp/nvsmi.log"
  : > "$FAKE_CURL_LOG"; : > "$FAKE_DOCKER_LOG"; : > "$FAKE_NVSMI_LOG"
  unset FAKE_RUNNING FAKE_HEALTHY FAKE_DUP FAKE_USED FAKE_TOTAL FAKE_HOLDERS FAKE_TOP_PID FAKE_TOP_CMD FAKE_TOP_ET FAKE_TOP_SECS
}
export PATH="$tmp/bin:$PATH"
export NTFY_TOPIC="shrike_gpuautoswap_selftest_ignore"

# --- A: healthy path — container already running -> no-op, no GPU query, no docker start ---
reset_env
export FAKE_RUNNING="true"
bash "$G"; rc=$?
ok "already running: exits 0" "[ $rc -eq 0 ]"
ok "already running: never queries nvidia-smi (no unnecessary GPU polling)" "[ ! -s '$FAKE_NVSMI_LOG' ]"
ok "already running: never calls docker start" "! grep -q 'DOCKER_CALL start' '$FAKE_DOCKER_LOG'"
ok "already running: no alert fired" "[ ! -s '$FAKE_CURL_LOG' ]"

# --- B: art-window / coder-window hold -> must skip entirely, even if container is down ---
reset_env
export FAKE_RUNNING="false"
touch "$HOME/overnight-queue/state/art_window.hold"
bash "$G"; rc=$?
ok "art window hold: exits 0" "[ $rc -eq 0 ]"
ok "art window hold: never even checks if the container is running (bails before docker inspect)" "[ ! -s '$FAKE_DOCKER_LOG' ]"
ok "art window hold: never queries the GPU" "[ ! -s '$FAKE_NVSMI_LOG' ]"

reset_env
export FAKE_RUNNING="false"
touch "$HOME/overnight-queue/state/coder_window.hold"
bash "$G"; rc=$?
ok "coder window hold: also skips entirely" "[ $rc -eq 0 ] && [ ! -s '$FAKE_DOCKER_LOG' ]"

# --- C: the actual guard case — GPU contention (not enough free VRAM) -> must NOT start
#     the container (would OOM), must log the holder, and must alert ONCE past the
#     starvation threshold, deduped on subsequent ticks for the same pid.
# The dedupe sweep does `kill -0 $pid` to drop flags for pids that are gone, so the
# "holder" here must be a REAL live pid (a background /bin/sleep, using the real
# binary since `sleep` on PATH is faked as a no-op for the script's own retry loop) ---
reset_env
/bin/sleep 300 & holder_pid=$!
export FAKE_RUNNING="false" FAKE_USED="20000" FAKE_TOTAL="24000"   # free=4000 < 21000 needed
export FAKE_TOP_PID="$holder_pid" FAKE_TOP_CMD="python train.py" FAKE_TOP_ET="00:33:00" FAKE_TOP_SECS="2000"
export FAKE_HOLDERS="$holder_pid, 20000, python"
bash "$G"; rc=$?
ok "GPU contention: exits 0 (not an error, just deferred)" "[ $rc -eq 0 ]"
ok "GPU contention: never calls docker start (would OOM the GPU)" "! grep -q 'DOCKER_CALL start' '$FAKE_DOCKER_LOG'"
ok "GPU contention: alerts once the non-27B holder has starved the fleet past the threshold" \
   "grep -q 'GPU held' '$FAKE_CURL_LOG'"
ok "GPU contention: records a per-pid dedupe flag" "[ -f \"$HOME/overnight-queue/state/gpu_holder_alerted_$holder_pid\" ]"
n1=$(grep -c 'GPU held' "$FAKE_CURL_LOG")
: > "$FAKE_CURL_LOG"
bash "$G"   # second tick, same holder still there -> must NOT re-alert
n2=$(grep -c 'GPU held' "$FAKE_CURL_LOG" || true)
ok "GPU contention: second tick with the same holder does not re-alert (deduped)" "[ '$n1' -eq 1 ] && [ '${n2:-0}' -eq 0 ]"
kill "$holder_pid" 2>/dev/null; wait "$holder_pid" 2>/dev/null

# --- D: contention but holder hasn't starved long enough yet -> no alert at all ---
reset_env
export FAKE_RUNNING="false" FAKE_USED="20000" FAKE_TOTAL="24000"
export FAKE_TOP_PID="5555" FAKE_TOP_CMD="python train.py" FAKE_TOP_ET="00:02:00" FAKE_TOP_SECS="120"
export FAKE_HOLDERS="5555, 20000, python"
bash "$G"
ok "GPU contention under the starvation threshold: no alert yet" "[ ! -s '$FAKE_CURL_LOG' ]"

# --- E: contention but the holder IS the llama-server itself (e.g. mid-load) -> no false alarm ---
reset_env
export FAKE_RUNNING="false" FAKE_USED="20000" FAKE_TOTAL="24000"
export FAKE_TOP_PID="6666" FAKE_TOP_CMD="/usr/bin/llama-server --model foo" FAKE_TOP_ET="00:40:00" FAKE_TOP_SECS="2400"
export FAKE_HOLDERS="6666, 20000, llama-server"
bash "$G"
ok "GPU held by llama-server itself: no 'starved by a non-27B holder' alert" "[ ! -s '$FAKE_CURL_LOG' ]"

# --- F: the recovery case — GPU frees up + container down -> must restart + confirm healthy ---
reset_env
export FAKE_RUNNING="false" FAKE_USED="1000" FAKE_TOTAL="24000"   # free=23000 >= 21000
export FAKE_HEALTHY="1"
bash "$G"; rc=$?
ok "GPU freed: exits 0" "[ $rc -eq 0 ]"
ok "GPU freed: calls docker start" "grep -q 'DOCKER_CALL start' '$FAKE_DOCKER_LOG'"
ok "GPU freed: fires the restored alert once healthy" "grep -q '27B restored' '$FAKE_CURL_LOG'"

# --- G: GPU freed, container started, but never becomes healthy -> must alert FAILURE and exit 1 ---
reset_env
export FAKE_RUNNING="false" FAKE_USED="1000" FAKE_TOTAL="24000"
export FAKE_HEALTHY="0"
bash "$G"; rc=$?
ok "restart never healthy: exits 1 (surfaces as a real failure)" "[ $rc -eq 1 ]"
ok "restart never healthy: fires a FAILED alert (not silently swallowed)" "grep -q 'auto-restart FAILED' '$FAKE_CURL_LOG'"

echo "gpu_autoswap.sh: $P passed, $F failed"
[ "$F" -eq 0 ]
