#!/usr/bin/env bash
# Regression test: ovn_test_watch.sh's emergency_enqueue() must file a real [EMERGENCY] item at
# the TOP of Next Steps (worked first next cycle) when a full suite goes red, never pile up
# duplicate emergencies for the same area, still work when the file has no "## Next Steps"
# header at all, and must serialize on run.lock (a running cycle is never interrupted) rather
# than racing the checkout (2026-09-10).
#
# The per-repo pytest/vitest/GUT runners themselves aren't exercised here (they'd require a real
# provisioned repo + real test suite on this host) — this targets the actual guard logic that
# decides whether/how to escalate a red suite, which is the part with real failure modes.
set -uo pipefail
REAL="$HOME/overnight-queue"
SH="$REAL/ovn_test_watch.sh"
[ -f "$SH" ] || { echo "  SKIP: $SH not found on this host"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
SANDBOX_HOME="$tmp/home"
OQ="$SANDBOX_HOME/overnight-queue"
mkdir -p "$OQ/state" "$OQ/repos" "$OQ/logs"
# ovn_test_watch.sh itself does `export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"`
# — that ALWAYS puts $HOME/aider-venv/bin ahead of the real system curl, so that's where our fake
# curl has to live for it to actually be picked up once the script (re)exports PATH.
FAKEBIN="$SANDBOX_HOME/aider-venv/bin"; mkdir -p "$FAKEBIN"
CURLLOG="$tmp/curl_calls.log"; : > "$CURLLOG"
cat > "$FAKEBIN/curl" <<'CURL_EOF'
#!/usr/bin/env bash
echo "CURL: $*" >> "$CURLLOG_PATH"
exit 0
CURL_EOF
chmod +x "$FAKEBIN/curl"

new_origin(){ # $1=name $2=progress-file-content
  local o="$tmp/origin_$1.git"
  git init -q --bare "$o"
  local w; w="$(mktemp -d)"
  ( cd "$w" && git init -q -b overnight/feature \
      && git config user.email t@t.com && git config user.name t \
      && printf '%s' "$2" > OVERNIGHT_PROGRESS.md \
      && git add -A && git commit -q -m init \
      && git remote add origin "$o" && git push -q origin overnight/feature )
  git --git-dir="$o" symbolic-ref HEAD refs/heads/overnight/feature
  rm -rf "$w"
  echo "$o"
}
clone_into_repos(){ # $1=repo-name $2=origin-path
  git clone -q "$2" "$OQ/repos/$1"
  ( cd "$OQ/repos/$1" && git checkout -q overnight/feature && git config user.email t@t.com && git config user.name t )
}

# --- exercise emergency_enqueue() directly by sourcing the real script with a bogus repo name
#     (REPOS="${*:-default}" treats a plain "" arg as unset/null and falls back to the real
#     default 8-repo list, so we must pass a real non-empty, non-existent name instead) so its
#     own top-level pytest/vitest/GUT loop is a harmless no-clone skip, then call the function ---
call_enqueue(){ # $1=repo $2=area $3=detail
  ( CURLLOG_PATH="$CURLLOG" PATH="$FAKEBIN:$PATH" HOME="$SANDBOX_HOME" NTFY_TOPIC=ovn-test-watch-unit-test-fake \
    bash -c '
      source "$1" __unittest_no_such_repo__
      emergency_enqueue "$2" "$3" "$4"
    ' _ "$SH" "$1" "$2" "$3"
  )
}

WITH_HEADER=$'# Overnight Progress\n\n## Current Status\nsome notes\n\n## Next Steps\n- [ ] [T1] foo.py — real work. VERIFY: pytest -q\n'
NO_HEADER=$'# Overnight Progress\n\n## Current Status\nsome notes, no Next Steps section at all\n'

# === A: healthy path — suite red -> [EMERGENCY] item inserted right after "## Next Steps",
#        committed+pushed, and an ntfy alert fired ===
oA="$(new_origin A "$WITH_HEADER")"
clone_into_repos repoA "$oA"
: > "$CURLLOG"
call_enqueue repoA pytest "3 failed, 1 error :: test_foo.py::test_bar"
after="$(git --git-dir="$oA" show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "A: EMERGENCY item was inserted" "printf '%s' \"$after\" | grep -q '\[EMERGENCY\]\[T2\] pytest suite is RED'"
ok "A: it lands immediately below the '## Next Steps' header (worked first next cycle)" \
   "printf '%s' \"$after\" | grep -A1 '^## Next Steps' | tail -1 | grep -q EMERGENCY"
ok "A: the real work item below it is undisturbed" "printf '%s' \"$after\" | grep -q 'foo.py — real work'"
ok "A: origin got the commit + push" \
   "git --git-dir='$oA' log --oneline overnight/feature | grep -q 'EMERGENCY.*pytest suite red'"
ok "A: an ntfy alert was actually sent" "grep -q 'ntfy.sh/ovn-test-watch-unit-test-fake' '$CURLLOG'"
ok "A: alert mentions the failing detail" "grep -q 'test_bar' '$CURLLOG'"

# === B: an emergency for the SAME area is already open -> must not pile up a duplicate ===
: > "$CURLLOG"
before="$(git --git-dir="$oA" rev-parse overnight/feature)"
call_enqueue repoA pytest "a different failure this time"
after2="$(git --git-dir="$oA" show overnight/feature:OVERNIGHT_PROGRESS.md)"
now="$(git --git-dir="$oA" rev-parse overnight/feature)"
ok "B: still exactly one pytest EMERGENCY line (no duplicate piled up)" \
   "[ \$(printf '%s' \"$after2\" | grep -c '\[EMERGENCY\]\[T2\] pytest suite is RED') -eq 1 ]"
ok "B: no new commit was made for the duplicate" "[ \"$before\" = \"$now\" ]"
ok "B: no second ntfy alert fired for the duplicate" "[ ! -s '$CURLLOG' ]"

# === C: a DIFFERENT area going red on the same repo IS filed as its own emergency ===
: > "$CURLLOG"
call_enqueue repoA vitest "2 failed :: Button.test.tsx"
after3="$(git --git-dir="$oA" show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "C: both pytest and vitest emergencies now coexist" \
   "printf '%s' \"$after3\" | grep -q 'pytest suite is RED' && printf '%s' \"$after3\" | grep -q 'vitest suite is RED'"

# === D: a progress file with NO '## Next Steps' header at all -> a section is created, not crashed ===
oD="$(new_origin D "$NO_HEADER")"
clone_into_repos repoD "$oD"
: > "$CURLLOG"
call_enqueue repoD pytest "1 failed :: test_x.py"
afterD="$(git --git-dir="$oD" show overnight/feature:OVERNIGHT_PROGRESS.md)"
ok "D: a '## Next Steps' section is synthesized" "printf '%s' \"$afterD\" | grep -q '^## Next Steps'"
ok "D: the emergency item is filed under the new section" \
   "printf '%s' \"$afterD\" | grep -A1 '^## Next Steps' | tail -1 | grep -q EMERGENCY"
ok "D: original notes are preserved" "printf '%s' \"$afterD\" | grep -q 'no Next Steps section at all'"

# === E: run.lock is actually respected — a held lock truly BLOCKS the pass (never races a live
#        cycle's checkout); once released, the waiting pass proceeds normally ===
exec 9>"$OQ/state/run.lock"
flock -x 9
elog="$tmp/e_out.log"; : > "$elog"
( HOME="$SANDBOX_HOME" PATH="$FAKEBIN:$PATH" NTFY_TOPIC=ovn-test-watch-unit-test-fake bash "$SH" __unittest_no_such_repo__ > "$elog" 2>&1 ) &
EPID=$!
sleep 1.5
ok "E: while the lock is held, the pass has NOT started (still waiting, not racing)" \
   "! grep -q 'test-health sweep start' '$elog'"
ok "E: the waiting process is still alive (blocked on flock, not exited/crashed)" "kill -0 $EPID"
flock -u 9; exec 9>&-
wait "$EPID" 2>/dev/null
ok "E: once released, the pass acquires the lock and runs to completion" \
   "grep -q 'test-health sweep start' '$elog' && grep -q 'test-health sweep complete' '$elog'"

echo "Test watch: $P passed, $F failed"
rm -rf "$tmp"
[ "$F" -eq 0 ]
