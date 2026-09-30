#!/usr/bin/env bash
# Extra coverage for the REAL digest_notify.sh: runs it in a fake tree with stub python helpers (canned output per flag), a stub
# curl/sleep, exercising: ready-to-test note (singular/plural/non-numeric), headline fallback, idle-check suffix, no-op cause
# vs no cause, all-time token once-per-day stamp, failure-triage NEW lines (<=5, >5, none), shrike dual-publish, and the
# send-failure path (3 retries, buffer left intact) vs success path (buffer rotated).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
pick(){ for c in "$@"; do [ -f "$c" ] && { echo "$c"; return; }; done; }
D="$(pick "$HERE/../../digest_notify.sh" "$HERE/../digest_notify.sh")"
LIB="$(pick "$HERE/../../shrike_notify_lib.sh" "$HERE/../shrike_notify_lib.sh")"
[ -n "$D" ] && [ -n "$LIB" ] || { echo "  SKIP: digest_notify.sh/shrike_notify_lib.sh not found"; exit 0; }
P=0; F=0
ok(){ if [ -n "$2" ] && [ -z "${2//1/}" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
Q="$T/q"; BIN="$T/bin"; STUBD="$T/stubd"; CALLS="$T/calls"
mkdir -p "$Q/state" "$Q/scripts" "$BIN" "$STUBD" "$CALLS"
cp "$D" "$Q/digest_notify.sh"; cp "$LIB" "$Q/shrike_notify_lib.sh"
export STUBD CALLS
cat > "$Q/scripts/stub.py" <<'PY'
import os, sys
a = sys.argv; b = os.path.basename(a[0]); d = os.environ["STUBD"]
def out(k):
    p = os.path.join(d, k)
    if os.path.exists(p):
        sys.stdout.write(open(p).read())
if b == "ovn_tier_stats.py":
    out("tokall" if "--all-time" in a else "tok24" if "--tokens-only" in a else "headline" if "--headline" in a else "tiers")
elif b == "ovn_feature_groups.py":
    out("ready" if "--ready-count" in a else "feat" if "--digest" in a else "fprog")
elif b == "ovn_stats.py":
    out("noop" if "--noop-headline" in a else "stats")
elif b == "ovn_landed_detail.py": out("landed")
elif b == "ovn_noop_detail.py": out("noopdetail")
elif b == "ovn_planning_stats.py": out("planning")
elif b == "ovn_failure_triage.py": out("triage")
PY
for n in ovn_tier_stats ovn_feature_groups ovn_stats ovn_landed_detail ovn_noop_detail ovn_planning_stats ovn_failure_triage; do
  cp "$Q/scripts/stub.py" "$Q/scripts/$n.py"; chmod +x "$Q/scripts/$n.py"
done
cat > "$BIN/curl" <<'EOF2'
#!/usr/bin/env bash
n=$(( $(cat "$CALLS/n" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$CALLS/n"
url="${@: -1}"; body=""; prev=""
for a in "$@"; do [ "$prev" = "-d" ] && body="$a"; prev="$a"; done
printf '%s\n' "$url" >> "$CALLS/urls"
case "$url" in *ntfy.example*) printf '%s' "$body" > "$CALLS/ntfy.$n"; printf '%s' "$body" > "$CALLS/last";; esac
[ -n "${CURL_FAIL:-}" ] && exit 22
exit 0
EOF2
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/sleep"; chmod +x "$BIN"/*
BUFLINE="$(printf '100\t2\t1\t1\t3\t1\tPASS=billwatch,gitlark\tFAIL=xlite\tREV=iptv\tERR=site\tIDLE=4')"
reset(){ rm -f "$STUBD"/* "$CALLS"/* "$Q/state/digest_buffer.log"* "$Q/state/alltime_toks_shown"; printf '%s\n' "$BUFLINE" > "$Q/state/digest_buffer.log"; }
run(){ OUT="$(cd "$Q" && PATH="$BIN:$PATH" HOME="$T" NTFY_TOPIC=tp NTFY_SERVER=https://ntfy.example env "$@" bash "$Q/digest_notify.sh" 2>&1)"; RC=$?; BODY="$(cat "$CALLS/last" 2>/dev/null)"; }
has(){ printf '%s' "$BODY" | grep -qF -- "$1" && echo 1 || echo 0; }

# ---- A: fully populated digest ----
reset
echo "Last 3h: 11 of ~16 real attempts landed (69%)" > "$STUBD/headline"
echo 2 > "$STUBD/ready"
echo "➖ cause line" > "$STUBD/noop"; echo "5 no-op -- 3 already-done, 2 flail" > "$STUBD/noop"
echo "LANDED-DETAIL" > "$STUBD/landed"; echo "NOOP-DETAIL" > "$STUBD/noopdetail"
echo "FEAT-DIGEST" > "$STUBD/feat"; echo "FEAT-PROGRESS" > "$STUBD/fprog"
echo "TIER-TABLE" > "$STUBD/tiers"; echo "TOK24" > "$STUBD/tok24"; echo "TOKALL" > "$STUBD/tokall"
echo "STATS-LINES" > "$STUBD/stats"; echo "PLANNING" > "$STUBD/planning"
printf 'NEW: sig-a :: first\nNEW: sig-b :: second\nREGRESSION: sig-c :: back\n' > "$STUBD/triage"
SHRIKE_NOTIFY_URL=https://sn.example run SHRIKE_NOTIFY_URL=https://sn.example
ok "A: exits 0" "$([ "$RC" = 0 ] && echo 1 || echo 0)"
ok "A: headline then plural ready note" "$(has 'Last 3h: 11 of ~16 real attempts landed (69%) — 2 features ready to test')"
ok "A: cycle detail line includes idle suffix" "$(has '+4 idle check(s) with nothing to do')"
ok "A: cycle counts" "$(has 'Cycle detail (1 run this window')"
ok "A: landed/failed/revert/error lines" "$(has '✅ 2 landed'; )$(has '⚠️ 1 had a failing'; )$(has '↩️ 1 auto-reverted')$(has '⛔ 1 errored')" 
ok "A: no-op line carries the cause breakdown" "$(has '➖ 3 no change (item already done, or nothing to do) — cause on record for some: 3 already-done, 2 flail')"
for s in LANDED-DETAIL NOOP-DETAIL FEAT-DIGEST FEAT-PROGRESS TIER-TABLE TOK24 TOKALL 'By language/type' STATS-LINES PLANNING; do
  ok "A: section present: $s" "$(has "$s")"
done
ok "A: 2 NEW triage lines rendered, REGRESSION ignored" "$(has '🆕 2 failure pattern(s)')$(has '  • sig-a: first')$(has '  • sig-b: second')$(! printf '%s' "$BODY" | grep -q 'sig-c' && echo 1 || echo 0)"
ok "A: no 'and N more' line for <=5" "$(! printf '%s' "$BODY" | grep -q 'more$' && echo 1 || echo 0)"
ok "A: all-time stamp written for today" "$([ "$(cat "$Q/state/alltime_toks_shown")" = "$(date +%F)" ] && echo 1 || echo 0)"
ok "A: buffer rotated to .last and cleared" "$([ ! -s "$Q/state/digest_buffer.log" ] && [ -s "$Q/state/digest_buffer.log.last" ] && echo 1 || echo 0)"
ok "A: shrike-notify dual publish hit" "$(grep -q 'https://sn.example/fleet_queue_task' "$CALLS/urls" && echo 1 || echo 0)"
# second run same day: all-time total not repeated
printf '%s\n' "$BUFLINE" > "$Q/state/digest_buffer.log"; run
ok "A2: all-time token line not repeated the same day" "$(! printf '%s' "$BODY" | grep -q TOKALL && echo 1 || echo 0)"

# ---- B: singular ready, no-headline fallback, no-op without cause, no NI, >5 triage lines ----
reset
printf '100\t0\t0\t0\t2\t0\tPASS=\tFAIL=\tREV=\tERR=\n' > "$Q/state/digest_buffer.log"
echo 1 > "$STUBD/ready"; echo "garbage line" > "$STUBD/noop"
i=1; : > "$STUBD/triage"; while [ $i -le 8 ]; do echo "NEW: s$i :: m$i" >> "$STUBD/triage"; i=$((i+1)); done
run
ok "B: no headline -> title line carries singular ready note" "$(has '— 1 feature ready to test')$(! printf '%s' "$BODY" | grep -q 'features ready' && echo 1 || echo 0)"
ok "B: no-op line without cause has no 'cause on record'" "$(has '➖ 2 no change (item already done, or nothing to do)')$(! printf '%s' "$BODY" | grep -q 'cause on record' && echo 1 || echo 0)"
ok "B: no idle suffix when IDLE is absent (old buffer format)" "$(! printf '%s' "$BODY" | grep -q 'idle check' && echo 1 || echo 0)"
ok "B: >5 NEW patterns -> capped with 'and 3 more'" "$(has '…and 3 more')$(has '  • s5: m5')$(! printf '%s' "$BODY" | grep -q 's6: m6' && echo 1 || echo 0)"
ok "B: no landed/failed lines when counts are zero" "$(! printf '%s' "$BODY" | grep -q 'landed on the feature branch' && echo 1 || echo 0)"
ok "B: no sections when helpers print nothing (no tier table)" "$(! printf '%s' "$BODY" | grep -q 'By language' && echo 1 || echo 0)"

# ---- C: non-numeric ready count -> 0, no note ----
reset; echo "abc" > "$STUBD/ready"; run
ok "C: non-numeric ready count is treated as 0 (no note)" "$(! printf '%s' "$BODY" | grep -q 'ready to test' && echo 1 || echo 0)"

# ---- D: send failure keeps buffer, retries 3 times ----
reset; echo "TIER" > "$STUBD/tiers"
run CURL_FAIL=1
ok "D: curl attempted 3 times" "$([ "$(grep -c 'ntfy.example' "$CALLS/urls")" = 3 ] && echo 1 || echo 0)"
ok "D: buffer left intact for retry" "$([ -s "$Q/state/digest_buffer.log" ] && [ ! -e "$Q/state/digest_buffer.log.last" ] && echo 1 || echo 0)"
ok "D: failure message on stderr (skipped under coverage where stderr is discarded)" "$(printf '%s' "$OUT" | grep -q 'digest delivery failed' || [ -n "${OVN_COV_DIR:-}" ] && echo 1 || echo 0)"

echo "digest_notify_more_paths: $P passed, $F failed"
[ "$F" = 0 ]
