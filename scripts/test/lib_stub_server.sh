# lib_stub_server.sh - Y1 (2026-11-04): start a local python stub server on a random port and WAIT until it accepts connections.
# Replaces `PORT=$((20000+RANDOM%20000)); stub $PORT & sleep 1`, which was a race (a slow python start under load, or a port already taken, left the
# first request with no server: test_qa_devicelane section 19 flaked red once on 2026-11-04 12:17).
# start_stub_server <python> <script> <portvar>   - runs `<python> <script> <port>`; sets $<portvar> and $STUB_PID; returns 1 after STUB_TRIES attempts.
#   Per attempt: pick a port (STUB_FIRST_PORT, a test hook, is used for the first attempt only), start, poll (python socket connect) up to STUB_WAIT_S seconds;
#   if the process dies (bind failure) or never listens, kill it and re-pick a port. Never kills anything but its own child.
start_stub_server(){
  local py="$1" script="$2" var="$3" tries="${STUB_TRIES:-6}" waits="${STUB_WAIT_S:-10}" n=0 port pid i
  STUB_PID=""
  while [ "$n" -lt "$tries" ]; do
    n=$((n+1))
    if [ "$n" = 1 ] && [ -n "${STUB_FIRST_PORT:-}" ]; then port="$STUB_FIRST_PORT"; else port=$((20000 + RANDOM % 20000)); fi
    "$py" "$script" "$port" >/dev/null 2>&1 & pid=$!
    for ((i=0; i<waits*5; i++)); do
      kill -0 "$pid" 2>/dev/null || break
      if "$py" -c "import socket,sys; socket.create_connection(('127.0.0.1',int(sys.argv[1])),0.3).close()" "$port" 2>/dev/null; then
        # our child must still be alive AFTER the connect succeeded (else a foreign listener answered and our own bind failed)
        sleep 0.5; kill -0 "$pid" 2>/dev/null || break
        printf -v "$var" '%s' "$port"; STUB_PID="$pid"; return 0
      fi
      sleep 0.2
    done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
  done
  return 1
}
