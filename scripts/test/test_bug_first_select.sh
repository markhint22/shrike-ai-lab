#!/usr/bin/env bash
# Bugs-first policy (2026-10-02, branch qa/h8-bug-first) - SELECTION + GUARD + STAGE-RUNNER PICK.
# DECISION FROM MARK: a manual-test bug (Mark's hand-logged bug, queue line 'Manual-test bug (reported by Mark ... src:manual' + [feat:..-manual-<8hex>])
# outranks every roadmap/refill item in its repo's lane, the lane works ONLY bug items while one is open, a bug gets 2 failed attempts then is
# ESCALATED (never silently AUTO-SKIPped), and with no manual bug anywhere the loop behaves exactly as before.
#
# Real code under test (nothing re-implemented): scripts/lib_item_select.sh (ovn_resolve_top_item / ovn_bug_first_order / ovn_is_schema_item),
# scripts/ovn_item_guard.sh (run as cron would: bash <path> args, a stub `curl` first on PATH to catch the relay note - nothing reaches the network),
# and the REAL ovn_stage_runner.sh picker via lib_osr_fixture.sh. The run_overnight.sh wiring is in test_bug_first_loop.sh.
# The guard uses GNU `sed -i` (like the existing guard tests): run on the box / any Linux host.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../lib_item_select.sh"; [ -f "$LIB" ] || LIB="$HERE/lib_item_select.sh"
G="$HERE/../ovn_item_guard.sh"; [ -f "$G" ] || G="$HERE/ovn_item_guard.sh"
[ -f "$LIB" ] && [ -f "$G" ] || { echo "  SKIP: lib_item_select.sh / ovn_item_guard.sh not found"; exit 0; }
if ! sed --version >/dev/null 2>&1; then echo "  SKIP: needs GNU sed (the guard uses sed -i); run on the box"; exit 0; fi
unset NTFY_SERVER NTFY_TOPIC OVN_BUG_FIRST OVN_BUG_FOCUS OVN_BUG_ATTEMPT_CAP OVN_GUARD_ATTEMPTS OVN_SCHEMA_BUDGET OVN_BUG_BRIEF_DIR
unset OVN_ITEM_FAIL_CAP OVN_ITEM_NOOP_CAP OVN_ITEM_TOKEN_CAP
# shellcheck source=/dev/null
source "$LIB"

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (expected [$2] got [$3])"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

BUG1='- [ ] [T3] android/app/Foo.kt — Manual-test bug (reported by Mark, flow home-countries-filter, 2026-10-02): Qatar missing from the countries filter. First write a failing test that reproduces this, then fix it; if the cause is not in this file, say so. VERIFY: `cd android && ./gradlew testDebugUnitTest`. (cat:bugfix; multifile:no; src:manual) [feat:iptv_apps-20261002-manual-aaaa1111]'
BUG2='- [ ] [T3] android/app/Bar.kt — Manual-test bug (reported by Mark, flow discover-add, 2026-10-02): the plus button does not add the channel. First write a failing test that reproduces this, then fix it. VERIFY: `true`. (cat:bugfix; multifile:no; src:manual) [feat:iptv_apps-20261002-manual-bbbb2222]'
STEP2='- [ ] [T3] android/app/Baz.kt — step 2 of 2: wire the fix into the screen. VERIFY: `true`. (cat:bugfix; multifile:no; src:manual) [feat:iptv_apps-20261002-manual-aaaa1111]'
RA='- [ ] [T2] `app/roadmap_a.py` — new feature A. VERIFY: `pytest -q`. (cat:python)'
RB='- [ ] [T2] `app/roadmap_b.py` — new feature B. (cat:python)'
RC='- [ ] [T3] `app/roadmap_c.py` — new feature C. (cat:python)'
EMERG='- [ ] 🚨 EMERGENCY DEPLOY FIX billwatch: railway deploy failed, fix first'
NEARMISS='- [ ] [T2] `app/manual_review.py` — add a manual review queue (cat:python) [feat:iptv_apps-20261002-manual-add-flow]'

mkprog(){ # <name> lines... -> prints repo dir
  local r="$tmp/$1"; shift; mkdir -p "$r"
  { echo '# Progress'; echo; echo '## Next Steps'; printf '%s\n' "$@"; } > "$r/OVERNIGHT_PROGRESS.md"
  echo "$r"
}
# the OLD selector, verbatim from before this change (reference for the byte-for-byte proofs)
old_top(){ grep -nE '^- \[ \]' "$1/OVERNIGHT_PROGRESS.md" 2>/dev/null | grep -viE 'HUMAN-ONLY|AUTO-SKIP|HARD FILE BAN|BLOCKED|\[CLAUDE\]' | head -1; }

echo "== A: ordering through the real ovn_resolve_top_item =="
r="$(mkprog a1 "$RA" "$RB" "$BUG1" "$RC")"
top="$(ovn_resolve_top_item "$r")"
ok "roadmap items first in the file, bug below: the BUG is the top item" "printf '%s' \"\$top\" | grep -q 'Foo.kt'"
eq "line number refers to the bug's real line (guard edits that line)" "6" "${top%%:*}"
r="$(mkprog a2 "$RA" "$BUG1" "$RB" "$BUG2")"
ok "two bugs: file order between them (first bug wins)" "ovn_resolve_top_item '$r' | grep -q 'Foo.kt'"
r="$(mkprog a3 "$RA" "$RB" "$EMERG" "$BUG1")"
ok "bug + EMERGENCY: the EMERGENCY keeps precedence above the bug" "ovn_resolve_top_item '$r' | grep -q 'EMERGENCY DEPLOY FIX'"
r="$(mkprog a3b "$EMERG" "$RA" "$BUG1")"
ok "EMERGENCY already on top stays on top" "ovn_resolve_top_item '$r' | grep -q 'EMERGENCY DEPLOY FIX'"
r="$(mkprog a4 "$RA" "- [ ] [CLAUDE] [bug-escalated: 2 failed attempts] ${BUG1#- \[ \] }" "$RB")"
ok "escalated ([CLAUDE]) bug is not open: the lane returns to the normal top item" "ovn_resolve_top_item '$r' | grep -q 'roadmap_a.py'"
r="$(mkprog a5 "$RA" "- [ ] [AUTO-SKIP after 4 cycles] ${BUG1#- \[ \] }" "$RB")"
ok "parked (AUTO-SKIP) bug is ignored" "ovn_resolve_top_item '$r' | grep -q 'roadmap_a.py'"
r="$(mkprog a5b "$RA" "- [x] ${BUG1#- \[ \] }" "$RB")"
ok "a checked-off bug is ignored" "ovn_resolve_top_item '$r' | grep -q 'roadmap_a.py'"
r="$(mkprog a6 "$RA" "$BUG1" "$RB")"
ok "kill switch OVN_BUG_FIRST=off: the old top-of-file item (roadmap_a)" "OVN_BUG_FIRST=off ovn_resolve_top_item '$r' | grep -q 'roadmap_a.py'"
eq "kill switch: result equals the OLD selector byte for byte" "$(old_top "$r")" "$(OVN_BUG_FIRST=off ovn_resolve_top_item "$r")"
r="$(mkprog a7 "$RA" "$STEP2" "$RB")"
ok "a brief step that shares the manual feat tag (no 'Manual-test bug' wording) is a bug item" "ovn_resolve_top_item '$r' | grep -q 'Baz.kt'"
r="$(mkprog a8 "$NEARMISS" "$RA")"
ok "a roadmap feature tagged ...-manual-add-flow is NOT a bug (needs 8 hex id)" "ovn_resolve_top_item '$r' | grep -q 'manual_review.py'"
eq "near-miss leaves ordering exactly as before" "$(old_top "$r")" "$(ovn_resolve_top_item "$r")"
# scout-file match must not drag the lane off the bug while it is open (lane focus), but the old behaviour returns with the kill switch
r="$(mkprog a9 "$RA" "$RB" "$BUG1")"
tl="$tmp/a9.log"; printf 'VERDICT: PROCEED\nPLAN: do B\nFILES: app/roadmap_b.py\n' > "$tl"
ok "scout names a roadmap file while a bug is open: still the bug (lane focus)" "ovn_resolve_top_item '$r' '$tl' | grep -q 'Foo.kt'"
ok "...and with the kill switch the scout's file wins as before" "OVN_BUG_FIRST=off ovn_resolve_top_item '$r' '$tl' | grep -q 'roadmap_b.py'"
printf 'VERDICT: PROCEED\nPLAN: fix\nFILES: android/app/Foo.kt\n' > "$tl"
ok "scout names the bug's own file: the bug" "ovn_resolve_top_item '$r' '$tl' | grep -q 'Foo.kt'"

echo "== B: no manual bug anywhere -> byte-for-byte the old behaviour =="
for i in 1 2 3; do
  case $i in 1) r="$(mkprog b1 "$RA" "$RB" "$RC")";; 2) r="$(mkprog b2 "$EMERG" "$RA" "- [ ] [AUTO-SKIP x] $RB")";; 3) r="$(mkprog b3 "- [ ] [CLAUDE] x" "$RC" "$RA")";; esac
  eq "fixture $i: ovn_resolve_top_item == old selector" "$(old_top "$r")" "$(ovn_resolve_top_item "$r")"
  ok "fixture $i: ovn_bug_first_order is a pure pass-through" "[ \"\$(grep -E '^- \\[ \\]' '$r/OVERNIGHT_PROGRESS.md' | ovn_bug_first_order)\" = \"\$(grep -E '^- \\[ \\]' '$r/OVERNIGHT_PROGRESS.md')\" ]"
done
eq "ovn_open_bug_count is 0 with no bug" "0" "$(ovn_open_bug_count "$tmp/b1")"
eq "ovn_open_bug_count counts open unparked bugs only" "2" "$(ovn_open_bug_count "$(mkprog b4 "$RA" "$BUG1" "$BUG2" "- [x] ${BUG2#- \[ \] }" "- [ ] [CLAUDE] [bug-escalated: x] ${BUG2#- \[ \] }")")"
eq "kill switch: ovn_open_bug_count is 0" "0" "$(OVN_BUG_FIRST=off ovn_open_bug_count "$tmp/b4")"

echo "== C: lane focus (ovn_bug_first_order) =="
lines="$(printf '%s\n' "$RA" "$BUG1" "$EMERG" "$RB" "$BUG2")"
out="$(printf '%s\n' "$lines" | ovn_bug_first_order)"
eq "focus: EMERGENCY, then both bugs, nothing else" "3" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
ok "focus: order is emergency, bug1, bug2" "[ \"\$(printf '%s\n' \"\$out\" | cut -c1-30 | tr '\n' '|')\" = \"\$(printf '%s\n' \"$EMERG\" \"$BUG1\" \"$BUG2\" | cut -c1-30 | tr '\n' '|')\" ]"
out="$(printf '%s\n' "$lines" | OVN_BUG_FOCUS=off ovn_bug_first_order)"
eq "OVN_BUG_FOCUS=off: bugs first but the rest kept (5 lines)" "5" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
ok "OVN_BUG_FOCUS=off: roadmap items come after the bugs" "printf '%s\n' \"\$out\" | tail -2 | grep -q roadmap_a"
ok "grep -n prefixed input works too" "printf '%s\n' '4:$RA' '9:$BUG1' | ovn_bug_first_order | head -1 | grep -q '^9:'"
# pipefail + early-exit readers: a 6000-line list piped into grep -q must not turn into a SIGPIPE status
big="$tmp/big.txt"; { for i in $(seq 1 3000); do printf '%s\n' "- [ ] [T3] \`app/f$i.py\` — thing $i with a fairly long description to make the stream big enough to fill a pipe buffer (cat:python)"; done; printf '%s\n' "$BUG1"; } > "$big"
bad=0; for i in $(seq 1 15); do cat "$big" | ovn_bug_first_order | grep -q 'Foo.kt' || bad=$((bad+1)); done
eq "pipefail-safe: 15 early-exit readers over a 3001-line input all succeed" "0" "$bad"
bad=0; grep -v 'Foo.kt' "$big" > "$tmp/big2.txt"; for i in $(seq 1 10); do cat "$tmp/big2.txt" | ovn_bug_first_order | grep -q 'f1.py' || bad=$((bad+1)); done
eq "pipefail-safe pass-through (no bug) with early-exit readers" "0" "$bad"

echo "== D: schema budget must not apply to a manual bug =="
SB='- [ ] [T3] backend/app/models/user.py — Manual-test bug (reported by Mark, flow x, 2026-10-02): alembic migration drops a column. VERIFY: `true`. (cat:bugfix; src:manual) [feat:b-20261002-manual-cccc3333]'
eq "failcap for a schema-shaped bug stays at the base 3" "3" "$(ovn_schema_budget failcap 3 "$SB")"
eq "tokcap for a schema-shaped bug stays at the base" "200000" "$(ovn_schema_budget tokcap 200000 "$SB")"
eq "best-of-N for a schema-shaped bug stays at the base" "3" "$(ovn_schema_budget bestn 3 "$SB")"
eq "a NON-bug schema item still gets base+2 (unchanged)" "5" "$(ovn_schema_budget failcap 3 '- [ ] [T3] backend/app/models/user.py — add column')"
eq "kill switch: the schema bug gets the schema budget again" "5" "$(OVN_BUG_FIRST=off ovn_schema_budget failcap 3 "$SB")"

echo "== E: attempt cap + escalation through the real ovn_item_guard.sh =="
BIN="$tmp/bin"; mkdir -p "$BIN"
cat > "$BIN/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$tmp/curl.calls"
exit 0
EOF
chmod +x "$BIN/curl"
export PATH="$BIN:$PATH"
new_repo(){ # <name> lines...
  local r="$tmp/$1"; shift; mkdir -p "$r"
  ( cd "$r" && git init -q && git config user.email t@t.com && git config user.name t \
    && { echo '# Progress'; echo; echo '## Next Steps'; printf '%s\n' "$@"; } > OVERNIGHT_PROGRESS.md && git add -A && git commit -q -m init )
  echo "$r"
}
guard(){ # <repo> <status> <state> <id> [log] -> runs the guard as cron would (env passed through)
  bash "$G" "$1" "$2" "$3" "$4" "${5:-}" >/dev/null 2>&1
}
mklog(){ printf 'Tokens: %sk sent, 100 received.\n' "$1" > "$tmp/log_$2.log"; echo "$tmp/log_$2.log"; }
prog(){ cat "$1/OVERNIGHT_PROGRESS.md"; }

r="$(new_repo e1 "$RA" "$BUG1" "$RB")"; st="$tmp/st1"; mkdir -p "$st"; : > "$tmp/curl.calls"
echo "topic-x" > "$st/ntfy_topic"
export NTFY_SERVER="http://127.0.0.1:1"      # a dead local port: the stub curl above swallows the call anyway
guard "$r" 'reverted(build-break)' "$st" ongoing-x "$(mklog 5 e1a)"
ok "1st failed attempt: NOT escalated yet" "! prog '$r' | grep -q 'bug-escalated'"
ok "1st failed attempt: bug counter is 1" "[ \"\$(cat '$st'/item_fails/ongoing-x.*.bugcount)\" = 1 ]"
ok "no relay note yet" "[ ! -s '$tmp/curl.calls' ]"
guard "$r" 'no-op(stage-unverified) stage(higher-tier)' "$st" ongoing-x "$(mklog 5 e1b)"
ok "2nd failed attempt: the bug line is tagged [CLAUDE] [bug-escalated: ...]" "prog '$r' | grep -F 'Foo.kt' | grep -q '^- \\[ \\] \\[CLAUDE\\] \\[bug-escalated: 2 failed attempts (cap 2), last: no-op(stage-unverified)'"
ok "NOT silently AUTO-SKIPped" "! prog '$r' | grep -q 'AUTO-SKIP'"
eq "the roadmap lines are untouched" "$RA" "$(prog "$r" | grep -F 'roadmap_a.py')"
ok "the escalation is committed in the repo" "git -C '$r' log -1 --format=%s | grep -q 'escalate manual-test bug'"
ok "bug_escalations.jsonl has exactly one line" "[ \"\$(wc -l < '$st/bug_escalations.jsonl')\" = 1 ]"
j="$(cat "$st/bug_escalations.jsonl")"
ok "jsonl: repo + note + attempts + item hash + last failure + brief key" "python3 -c \"import json,sys; d=json.loads(sys.argv[1]); assert d['repo']=='e1' and d['attempts']==2 and len(d['item_hash'])==32 and 'Qatar' in d['note'] and d['last_status'].startswith('no-op') and d['feat']=='[feat:iptv_apps-20261002-manual-aaaa1111]' and 'brief' in d and 'last_failure' in d\" '$j'"
eq "exactly ONE relay note sent" "1" "$(wc -l < "$tmp/curl.calls" | tr -d ' ')"
ok "relay note: title 'Manual bug escalated: e1', default priority, topic from state/ntfy_topic" "grep -q 'Title: Manual bug escalated: e1' '$tmp/curl.calls' && grep -q 'Priority: default' '$tmp/curl.calls' && grep -q '/topic-x' '$tmp/curl.calls'"
ok "relay note never urgent / no emergency words in the title" "! grep -iE 'urgent|emergency|DOWN' '$tmp/curl.calls' | grep -q Title"
ok "counters of the escalated item are cleared" "! ls '$st'/item_fails/ 2>/dev/null | grep -q bugcount"
# the lane moves on: a failure of the NEXT top item (roadmap_a) uses the generic caps and no second note appears
guard "$r" 'reverted(build-break)' "$st" ongoing-x "$(mklog 5 e1c)"
eq "no second relay note (once per item)" "1" "$(wc -l < "$tmp/curl.calls" | tr -d ' ')"
ok "the generic item that is now on top is tracked on the generic counter, not escalated" "! prog '$r' | grep -F 'roadmap_a.py' | grep -q 'bug-escalated' && ls '$st'/item_fails/ | grep -q '\\.count$'"

echo "-- E2: same item, two more failures after a human un-tags it: the tag is applied again but the jsonl/relay stay once per item hash"
sed -i 's/ \[CLAUDE\] \[bug-escalated: [^]]*\]//' "$r/OVERNIGHT_PROGRESS.md"
guard "$r" 'reverted(x)' "$st" ongoing-x "$(mklog 5 e1d)"; guard "$r" 'reverted(x)' "$st" ongoing-x "$(mklog 5 e1e)"
ok "re-tagged" "prog '$r' | grep -F 'Foo.kt' | grep -q 'bug-escalated'"
eq "jsonl still one line for that hash" "1" "$(wc -l < "$st/bug_escalations.jsonl" | tr -d ' ')"
eq "relay still one note" "1" "$(wc -l < "$tmp/curl.calls" | tr -d ' ')"

echo "-- E3: caps, overrides, budgets"
r="$(new_repo e3 "$RA" "$BUG1" "$RB")"; st="$tmp/st3"; mkdir -p "$st"
OVN_BUG_ATTEMPT_CAP=3 guard "$r" 'reverted(x)' "$st" ongoing-y "$(mklog 5 e3a)"; OVN_BUG_ATTEMPT_CAP=3 guard "$r" 'reverted(x)' "$st" ongoing-y "$(mklog 5 e3b)"
ok "OVN_BUG_ATTEMPT_CAP=3: not escalated after 2" "! prog '$r' | grep -q 'bug-escalated'"
OVN_BUG_ATTEMPT_CAP=3 guard "$r" 'reverted(x)' "$st" ongoing-y "$(mklog 5 e3c)"
ok "OVN_BUG_ATTEMPT_CAP=3: escalated after 3" "prog '$r' | grep -q 'bug-escalated: 3 failed attempts (cap 3)'"
r="$(new_repo e3b "$BUG1")"; st="$tmp/st3b"; mkdir -p "$st"
OVN_GUARD_ATTEMPTS=2 guard "$r" 'no-op(x)' "$st" ongoing-y "$(mklog 5 e3d)"
ok "OVN_GUARD_ATTEMPTS=2 (best-of-N used both tries in ONE cycle): escalated after that single cycle" "prog '$r' | grep -q 'bug-escalated: 2 failed attempts'"
r="$(new_repo e3c "$BUG1")"; st="$tmp/st3c"; mkdir -p "$st"
OVN_GUARD_ATTEMPTS=garbage guard "$r" 'no-op(x)' "$st" ongoing-y "$(mklog 5 e3e)"
ok "a garbage OVN_GUARD_ATTEMPTS counts as 1" "! prog '$r' | grep -q 'bug-escalated' && [ \"\$(cat '$st'/item_fails/ongoing-y.*.bugcount)\" = 1 ]"
r="$(new_repo e3d "$BUG1")"; st="$tmp/st3d"; mkdir -p "$st"
guard "$r" 'skip(exhausted)' "$st" ongoing-y "$(mklog 5 e3f)"; guard "$r" 'held(x)' "$st" ongoing-y "$(mklog 5 e3g)"; guard "$r" 'skip(paused)' "$st" ongoing-y "$(mklog 5 e3h)"
ok "skip*/held* cycles (nothing attempted) never count against the bug" "! prog '$r' | grep -q 'bug-escalated' && ! ls '$st'/item_fails/ 2>/dev/null | grep -q bugcount"
r="$(new_repo e3e "$BUG1")"; st="$tmp/st3e"; mkdir -p "$st"
guard "$r" 'no-op(BLOCKED)' "$st" ongoing-y "$(mklog 5 e3i)"; guard "$r" 'no-op(NEEDS-DECISION)' "$st" ongoing-y "$(mklog 5 e3j)"
ok "BLOCKED / NEEDS-DECISION no-ops DO count as failed attempts for a bug (2 -> escalated, not parked at the generic 4)" "prog '$r' | grep -q 'bug-escalated' && ! prog '$r' | grep -q 'AUTO-SKIP'"
r="$(new_repo e3f "$BUG1")"; st="$tmp/st3f"; mkdir -p "$st"
guard "$r" 'no-op(stage-unverified) stage(higher-tier)' "$st" ongoing-y "$(mklog 250 e3k)"
ok "one cycle that burns 250k tokens escalates by spend (reason says so)" "prog '$r' | grep -q 'bug-escalated: 250000 tokens spent in 1 attempt(s) without a fix'"
r="$(new_repo e3g "$SB")"; st="$tmp/st3g"; mkdir -p "$st"
guard "$r" 'reverted(x)' "$st" ongoing-y "$(mklog 5 e3l)"; guard "$r" 'reverted(x)' "$st" ongoing-y "$(mklog 5 e3m)"
ok "schema-shaped bug escalates at 2 (no schema budget), a generic schema item would get 5" "prog '$r' | grep -q 'bug-escalated: 2 failed attempts'"
r="$(new_repo e3h "- [ ] [T3] backend/app/models/user.py — add column. VERIFY: true")"; st="$tmp/st3h"; mkdir -p "$st"
for i in 1 2 3 4; do guard "$r" 'reverted(x)' "$st" ongoing-y "$(mklog 5 e3n$i)"; done
ok "UNCHANGED: a generic schema item still has the +2 budget (not parked after 4 failures)" "! prog '$r' | grep -q 'AUTO-SKIP'"
r="$(new_repo e3i "- [ ] [T3] backend/app/routers/users.py — add endpoint. VERIFY: true")"; st="$tmp/st3i"; mkdir -p "$st"
for i in 1 2 3; do guard "$r" 'reverted(x)' "$st" ongoing-y "$(mklog 5 e3o$i)"; done
ok "UNCHANGED: a generic item still parks via AUTO-SKIP at the 3rd failure (not 2)" "prog '$r' | grep -q 'AUTO-SKIP after 3 failed-to-land cycles'"
ok "UNCHANGED: ...and writes no escalation record" "[ ! -f '$st/bug_escalations.jsonl' ]"

echo "-- E4: landing clears the bug counter; siblings of a brief; briefs; kill switch; no relay configured"
r="$(new_repo e4 "$BUG1")"; st="$tmp/st4"; mkdir -p "$st"
guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4a)"
guard "$r" 'pushed(tests:pass) stage(higher-tier)' "$st" ongoing-z "$(mklog 5 e4b)"
ok "a landing (staged runner emits no item-hash marker) clears this lane's bug counters" "! ls '$st'/item_fails/ | grep -q bugcount"
guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4c)"
ok "so the next step starts a fresh 2-attempt budget (1 failure: not escalated)" "! prog '$r' | grep -q 'bug-escalated'"
r="$(new_repo e4b "$BUG1" "$STEP2" "$RA")"; st="$tmp/st4b"; mkdir -p "$st"
guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4d)"; guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4e)"
ok "brief: the failing step is tagged with the reason" "prog '$r' | grep -F 'Foo.kt' | grep -q 'bug-escalated: 2 failed attempts'"
ok "brief: the sibling step with the same feat tag is escalated too" "prog '$r' | grep -F 'Baz.kt' | grep -q 'bug-escalated: sibling step'"
ok "brief: an unrelated roadmap line is untouched" "prog '$r' | grep -F 'roadmap_a.py' | grep -qv 'CLAUDE'"
r="$(new_repo e4c "$BUG1")"; st="$tmp/st4c"; mkdir -p "$st/bug_briefs"; echo '{}' > "$st/bug_briefs/iptv_apps-20261002-manual-aaaa1111.json"
guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4f)"; guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4g)"
ok "jsonl records the brief location when a brief file exists" "grep -q 'bug_briefs/iptv_apps-20261002-manual-aaaa1111.json' '$st/bug_escalations.jsonl'"
r="$(new_repo e4d "$BUG1")"; st="$tmp/st4d"; mkdir -p "$st"
for i in 1 2 3; do OVN_BUG_FIRST=off guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4h$i)"; done
ok "OVN_BUG_FIRST=off: the bug is treated like any item (AUTO-SKIP at 3, no escalation, no jsonl)" "prog '$r' | grep -q 'AUTO-SKIP after 3 failed-to-land cycles' && ! prog '$r' | grep -q 'bug-escalated' && [ ! -f '$st/bug_escalations.jsonl' ]"
r="$(new_repo e4e "$BUG1")"; st="$tmp/st4e"; mkdir -p "$st"; : > "$tmp/curl.calls"
( unset NTFY_SERVER; guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4i)"; guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4j)" )
ok "no NTFY_SERVER/topic: escalation + jsonl still happen, no call attempted, no crash" "prog '$r' | grep -q 'bug-escalated' && [ -s '$st/bug_escalations.jsonl' ] && [ ! -s '$tmp/curl.calls' ]"
r="$(new_repo e4f "$BUG1")"; st="$tmp/st4f"; mkdir -p "$st"
NTFY_TOPIC=envtopic guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4k)"; NTFY_TOPIC=envtopic guard "$r" 'reverted(x)' "$st" ongoing-z "$(mklog 5 e4l)"
ok "NTFY_TOPIC env is honoured" "tail -1 '$tmp/curl.calls' | grep -q '/envtopic'"

echo "== F: the REAL staged-runner picker =="
. "$HERE/lib_osr_fixture.sh"
trap 'rm -rf "$tmp"; osr_cleanup' EXIT
withlib(){ cp "$REALQ/scripts/lib_item_select.sh" "$Q/scripts/"; }
KT='- [ ] [T3] android/app/Foo.kt — Manual-test bug (reported by Mark, flow f, 2026-10-02): x. VERIFY: `true`. (cat:bugfix; src:manual) [feat:iptv_apps-20261002-manual-aaaa1111]'
PYR='- [ ] [T3] backend/app/real.py — Real python roadmap item (cat:python)'
osr_new; withlib; osr_plan default '[]'
osr_progress "$PYR" "$KT"
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "bug (Kotlin, below a python roadmap item): the stage runner picks the BUG, python-preference skipped" bash -c "grep 'ITEM (T3)' '$T/out.txt' | grep -q 'Foo.kt'"
osr_cleanup
osr_new; osr_plan default '[]'
osr_progress "$PYR" "$KT"
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "CONTROL: without the lib the old picker takes the python roadmap item (proves the fixture discriminates)" bash -c "grep 'ITEM (T3)' '$T/out.txt' | grep -q 'real.py'"
osr_cleanup
osr_new; withlib; osr_plan default '[]'
osr_progress "$PYR" "$KT"
OVN_BUG_FIRST=off OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "kill switch OVN_BUG_FIRST=off: back to the python preference" bash -c "grep 'ITEM (T3)' '$T/out.txt' | grep -q 'real.py'"
osr_cleanup
osr_new; withlib; osr_plan default '[]'
osr_progress "$PYR" '- [ ] [T2] android/app/Low.kt — Manual-test bug (reported by Mark, flow f, 2026-10-02): x. (cat:bugfix; src:manual) [feat:iptv_apps-20261002-manual-dddd4444]'
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "lane focus: an open T2 bug leaves NO T3+ item for the stage runner (the cycle falls through to the scout flow that works the bug)" bash -c "grep -q 'no doable T3+ item found' '$T/out.txt'"
osr_cleanup
osr_new; withlib; osr_plan default '[]'
osr_progress "$PYR" "- [ ] [CLAUDE] [bug-escalated: 2 failed attempts] ${KT#- \[ \] }"
OVN_STAGE_DEDICATE=0 osr_run "$OSR_REPO"
t "an escalated bug no longer blocks the python roadmap item" bash -c "grep 'ITEM (T3)' '$T/out.txt' | grep -q 'real.py'"
osr_cleanup
F=$((F+fail)); P=$((P+pass))

echo; echo "Bug-first select/guard/stage-picker: $P passed, $F failed"
[ "$F" -eq 0 ]
