#!/usr/bin/env bash
# 2026-10-02: ovn_hygiene_stuck_check.sh must also escalate a repo whose first pending commit is QA-blocked (state/qa_blocked/*.json).
# That path exits hygiene 0 with no branch_hygiene_review_* flag, so before this the repo could starve for days behind one alerts.log line.
# Sequence: fresh record (silent) -> past threshold (ONE alert) -> cooldown (silent) -> past reminder window (ONE reminder) -> record gone
# (ONE cleared note, marker removed). Plus controls: a record that is not old enough never alerts; an unreadable record never alerts; two branches
# of one repo are tracked independently. curl is a stub; nothing reaches the network.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
H="${OVN_HYGIENE_STUCK_CHECK:-$HERE/../../ovn_hygiene_stuck_check.sh}"
[ -f "$H" ] || { echo "  SKIP: $H not found"; exit 0; }
command -v jq >/dev/null || { echo "  SKIP: no jq"; exit 0; }
date -u -d @0 +%s >/dev/null 2>&1 && GNU=1 || GNU=0
iso(){ if [ "$GNU" = 1 ]; then date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; else date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; fi; }
P=0; F=0
# 2026-10-08: assertions are evaluated with pipefail OFF - under pipefail `A | grep -q X` is flaky (grep -q exits at its first hit, A may take SIGPIPE: rc 141) and `! A | grep -q X` can mask a real failure
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; wd="$tmp/overnight-queue"; mkdir -p "$wd/state/qa_blocked" "$tmp/bin"
cp "$H" "$wd/ovn_hygiene_stuck_check.sh"
AL="$tmp/alerts.log"; : > "$AL"
printf '#!/usr/bin/env bash\nfor a in "$@"; do echo "$a" >> "%s"; done\nexit 0\n' "$AL" > "$tmp/bin/curl"; chmod +x "$tmp/bin/curl"
run(){ ( cd "$wd" && HOME="$tmp" NTFY_SERVER=http://127.0.0.1:9 PATH="$tmp/bin:$PATH" bash ovn_hygiene_stuck_check.sh >"$tmp/out.log" 2>&1 ); }
rec(){ # rec <key> <age_hours>
  jq -n --arg s "$(iso $(( $(date +%s) - $2 * 3600 )))" '{repo:"app",gate:"stub",commit:"abcdef0123456789",held_commits:3,finding:"seeded bad change",since:$s}' > "$wd/state/qa_blocked/$1.json"; }
K1=app__overnight_feature; K2=app__claude_feature

rec $K1 0; run
ok "fresh record: no alert" "[ ! -s '$AL' ]"
rec $K1 3; run
ok "record older than 2h: exactly one QA-blocked alert naming repo+branch key" "[ \$(grep -c 'QA-blocked: $K1' '$AL') -eq 1 ]"
ok "alert text carries gate and commit" "grep -q 'gate=stub commit=abcdef012345' '$AL'"
: > "$AL"; run; run
ok "cooldown: no repeat alert" "[ ! -s '$AL' ]"
echo $(( $(date +%s) - 7*3600 )) > "$wd/state/qa_stuck_alerted_$K1"; run
ok "past the reminder window: exactly one reminder" "[ \$(grep -c 'QA-blocked still: $K1' '$AL') -eq 1 ]"
: > "$AL"; rm -f "$wd/state/qa_blocked/$K1.json"; run
ok "record gone: exactly one cleared note" "[ \$(grep -c 'QA-block cleared: $K1' '$AL') -eq 1 ]"
ok "record gone: alerted marker removed" "[ ! -f '$wd/state/qa_stuck_alerted_$K1' ]"
: > "$AL"; run; ok "afterwards: silent" "[ ! -s '$AL' ]"

# controls
: > "$AL"; rec $K1 1; run; rm -f "$wd/state/qa_blocked/$K1.json"; run
ok "a block that clears before the threshold never alerts (no stray marker)" "[ ! -s '$AL' ] && [ ! -f '$wd/state/qa_stuck_alerted_$K1' ]"
echo '{not json' > "$wd/state/qa_blocked/$K2.json"; run
ok "unreadable record never alerts on a guess" "[ ! -s '$AL' ]"
rec $K1 5; rec $K2 0; run
ok "two branches of one repo are independent: only the old one alerts" "[ \$(grep -c 'QA-blocked: $K1' '$AL') -eq 1 ] && [ \$(grep -c 'QA-blocked: $K2' '$AL') -eq 0 ]"
ok "the existing branch_hygiene_review_* path is untouched (no flag, no hygiene alert)" "! grep -q 'Branch hygiene' '$AL'"
rm -rf "$tmp"
echo "QA-blocked stuck check: $P passed, $F failed"
[ "$F" -eq 0 ]
