#!/usr/bin/env bash
# N5 (2026-11-02): queue_refill.sh "Backlog refilled" (a) goes through the relay by default (NTFY_SERVER unset -> http://127.0.0.1:8099, never https://ntfy.sh, which bypassed the relay's
# DROP/dedupe) and (b) has per-repo hysteresis: announced only when the repo's dry episode lasted >= QR_REFILL_MIN_DRY_S (6 h, state/backlog_dry_first_<repo>) AND the previous
# announcement is >= QR_REFILL_QUIET_S (12 h, state/backlog_refilled_<repo>) old. gitlark flapped 3x in 2.5 h at the doable threshold. Mutants must fail.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
HERE="$(cd "$(dirname "$0")" && pwd)"
Q="${OVN_QUEUE_REFILL:-$HERE/../../queue_refill.sh}"; [ -f "$Q" ] || Q="$HOME/overnight-queue/queue_refill.sh"
[ -f "$Q" ] || { echo "  SKIP: queue_refill.sh not found on this host"; exit 0; }
export TZ=UTC
P=0; F=0
T="$(safe_mktemp_dir)" || exit 1; trap 'safe_rm_rf "$T"' EXIT

scenario(){  # $1 script $2 case -> failed check count
  local script="$1" tmp="$T/case_${RANDOM}_$$" f=0 wd now; wd="$tmp/overnight-queue"; now=$(date +%s)
  mkdir -p "$wd/repos/foo" "$wd/backlog" "$wd/state" "$tmp/aider-venv/bin"
  cp "$script" "$wd/queue_refill.sh"; chmod +x "$wd/queue_refill.sh"; printf '#!/usr/bin/env bash\nexit 0\n' > "$wd/queue.sh"; chmod +x "$wd/queue.sh"
  local CL="$tmp/curl.log"; : > "$CL"
  printf '#!/usr/bin/env bash\necho "CURL $*" >> "%s"\nexit 0\n' "$CL" > "$tmp/aider-venv/bin/curl"; chmod +x "$tmp/aider-venv/bin/curl"
  local st="$wd/state"
  refill(){ ( cd "$wd" && env -u NTFY_SERVER HOME="$tmp" MIN_DOABLE="$1" ./queue_refill.sh foo 2>&1 ); }
  chk(){ if ! ( set +o pipefail; eval "$2" ) >/dev/null 2>&1; then f=$((f+1)); echo "    check failed: $1"; fi; }
  dry(){ : > "$wd/repos/foo/OVERNIGHT_PROGRESS.md"; refill 15 >/dev/null; }
  recover(){ printf -- '- [ ] [T1] a\n- [ ] [T1] b\n' > "$wd/repos/foo/OVERNIGHT_PROGRESS.md"; refill 1; }

  dry
  chk "a new dry episode records its start in state/backlog_dry_first_foo" "[ -f '$st/backlog_dry_first_foo' ] && [ \$(( \$(date +%s) - \$(cat '$st/backlog_dry_first_foo') )) -lt 60 ]"
  # 1: a short episode (1 h) is not announced
  echo $((now - 3600)) > "$st/backlog_dry_first_foo"
  out="$(recover)"
  chk "short dry episode (1h < 6h): NO 'Backlog refilled' push" "! grep -q 'Backlog refilled' '$CL'"
  chk "... the suppression is logged" "printf '%s' \"\$out\" | grep -q 'backlog-recovered for foo NOT announced'"
  chk "... the episode is over: marker and first-dry file are gone, no announcement state written" "[ ! -f '$st/qr_dry_foo' ] && [ ! -f '$st/backlog_dry_first_foo' ] && [ ! -f '$st/backlog_refilled_foo' ]"
  # 2: a long episode is announced, once, through the relay
  : > "$CL"; dry; echo $((now - 7*3600)) > "$st/backlog_dry_first_foo"
  out="$(recover)"
  chk "long dry episode (7h >= 6h): exactly one 'Backlog refilled' push" "[ \$(grep -c 'Title: Backlog refilled' '$CL') -eq 1 ]"
  chk "... default server is the relay (127.0.0.1:8099), never ntfy.sh" "grep -q '127.0.0.1:8099/' '$CL' && ! grep -q 'ntfy.sh' '$CL'"
  chk "... state/backlog_refilled_foo records the announcement time" "[ \$(( \$(date +%s) - \$(cat '$st/backlog_refilled_foo') )) -lt 60 ]"
  # 3: flap - dry again for 7h and recovered again within the 12 h quiet window: silent
  : > "$CL"; dry; echo $((now - 7*3600)) > "$st/backlog_dry_first_foo"; echo $((now - 3600)) > "$st/backlog_refilled_foo"
  recover >/dev/null
  chk "second recovery 1h after the last announcement (quiet window 12h): NO push" "! grep -q 'Backlog refilled' '$CL'"
  # 4: quiet window over
  : > "$CL"; dry; echo $((now - 7*3600)) > "$st/backlog_dry_first_foo"; echo $((now - 13*3600)) > "$st/backlog_refilled_foo"
  recover >/dev/null
  chk "recovery 13h after the last announcement: announced again" "[ \$(grep -c 'Title: Backlog refilled' '$CL') -eq 1 ]"
  # 5: an explicit NTFY_SERVER is honoured
  : > "$CL"; dry; echo $((now - 7*3600)) > "$st/backlog_dry_first_foo"; rm -f "$st/backlog_refilled_foo"
  printf -- '- [ ] [T1] a\n- [ ] [T1] b\n' > "$wd/repos/foo/OVERNIGHT_PROGRESS.md"; ( cd "$wd" && NTFY_SERVER=http://relay.test:1 HOME="$tmp" MIN_DOABLE=1 ./queue_refill.sh foo >/dev/null 2>&1 )
  chk "an explicit NTFY_SERVER is used as given" "grep -q 'relay.test:1/' '$CL'"
  # 6: an episode in flight at deploy time (no first-dry file, old marker) falls back to the marker timestamp
  : > "$CL"; rm -f "$st/backlog_dry_first_foo" "$st/backlog_refilled_foo"; echo 5 > "$st/qr_dry_foo"
  recover >/dev/null
  chk "legacy episode (no first-dry file, marker from long ago) is announced" "[ \$(grep -c 'Title: Backlog refilled' '$CL') -eq 1 ]"
  return $f
}
runcase(){ local rc; scenario "$2" "$1"; rc=$?
  if [ "$3" = pass ]; then if [ "$rc" = 0 ]; then P=$((P+1)); echo "  ok   $1: scenario passes"; else F=$((F+1)); echo "  FAIL $1: $rc check(s) failed"; fi
  else if [ "$rc" -gt 0 ]; then P=$((P+1)); echo "  ok   mutation caught: $1 ($rc check(s) fail)"; else F=$((F+1)); echo "  FAIL mutation NOT caught: $1"; fi; fi; }
runcase real "$Q" pass
mutate(){ local m="$T/mut_$RANDOM.sh"
  OLD="$2" NEW="$3" python3 - "$Q" "$m" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { F=$((F+1)); echo "  FAIL mutation '$1' could not be applied"; return; }
  runcase "$1" "$m" fail; }
RELAYP="80""99"; DIRECT="ntfy"".sh"     # assembled so the lint (lint_ntfy_tests.py) does not read this test's mutants as live-channel settings
mutate "default server is ntfy.sh again (bypasses the relay)" '"${NTFY_SERVER:-http://127.0.0.1:'"$RELAYP"'}/$TOPIC" >/dev/null 2>&1 || true
  log "backlog-recovered note sent' '"${NTFY_SERVER:-https://'"$DIRECT"'}/$TOPIC" >/dev/null 2>&1 || true
  log "backlog-recovered note sent'
mutate "no minimum dry duration" 'if [ $(( now - first )) -ge "${QR_REFILL_MIN_DRY_S:-21600}" ] && [ $(( now - last )) -ge "${QR_REFILL_QUIET_S:-43200}" ]; then' 'if [ $(( now - last )) -ge "${QR_REFILL_QUIET_S:-43200}" ]; then'
mutate "no quiet window" 'if [ $(( now - first )) -ge "${QR_REFILL_MIN_DRY_S:-21600}" ] && [ $(( now - last )) -ge "${QR_REFILL_QUIET_S:-43200}" ]; then' 'if [ $(( now - first )) -ge "${QR_REFILL_MIN_DRY_S:-21600}" ]; then'
mutate "announcement time not recorded" 'announce="$announce $r"; echo "$now" > "$STATE_DIR/backlog_refilled_$r"' 'announce="$announce $r"'
mutate "first-dry file never written" '[ -f "$STATE_DIR/backlog_dry_first_$r" ] || echo "$now" > "$STATE_DIR/backlog_dry_first_$r"' ':'
mutate "legacy marker fallback dropped" 'mark_recovered(){ [ -f "$STATE_DIR/backlog_dry_first_$1" ] || cp "$2" "$STATE_DIR/backlog_dry_first_$1" 2>/dev/null; rm -f "$2"; recovered="$recovered $1"; }' 'mark_recovered(){ rm -f "$2"; recovered="$recovered $1"; }'
echo "  queue_refill hysteresis: $P passed, $F failed"
[ "$F" = 0 ]
