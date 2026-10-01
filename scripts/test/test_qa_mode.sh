#!/usr/bin/env bash
# qa_mode.sh: on/off restores EXACTLY what it disabled; lane/unlane toggle one repo; never touches non-dev lanes; tasks.json stays valid.
command -v jq >/dev/null 2>&1 || { echo "  SKIP: jq not installed"; exit 0; }
Q="$(cd "$(dirname "$0")/../.." && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=0; F=0; ok(){ if [ "$2" = 1 ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
mkdir -p "$T/state"
cat > "$T/tasks.json" <<'J'
[{"id":"ongoing-a","type":"aider_fix","repo":"/x/a","enabled":true},
 {"id":"ongoing-b","type":"aider_fix","repo":"/x/b","enabled":true},
 {"id":"ongoing-c","type":"aider_fix","repo":"/x/c","enabled":false},
 {"id":"ongoing-iptv-apps","type":"aider_fix","repo":"/x/iptv_apps","enabled":true},
 {"id":"chickadee-railway-404","type":"aider_fix","repo":"/x/z","enabled":false},
 {"id":"other-job","type":"shell","enabled":true}]
J
M() { OVN_DIR="$T" bash "$Q/qa_mode.sh" "$@"; }
en(){ jq -r --arg id "$1" '.[]|select(.id==$id)|.enabled' "$T/tasks.json"; }
M status | grep -q "mode: DEV" && ok "status: DEV before anything" 1 || ok "status: DEV before anything" 0
M on >/dev/null
ok "on: every enabled ongoing-* lane is disabled" "$([ "$(en ongoing-a)" = false ] && [ "$(en ongoing-b)" = false ] && [ "$(en ongoing-iptv-apps)" = false ] && echo 1 || echo 0)"
ok "on: an already-disabled lane stays disabled and non-dev tasks are untouched" "$([ "$(en ongoing-c)" = false ] && [ "$(en other-job)" = true ] && [ "$(en chickadee-railway-404)" = false ] && echo 1 || echo 0)"
ok "on: remembers exactly the 3 lanes it disabled" "$([ "$(jq -r '.disabled_lanes|length' "$T/state/qa_mode.json")" = 3 ] && echo 1 || echo 0)"
ok "on twice is a no-op (does not forget the first list)" "$(M on | grep -q 'already in QA mode' && [ "$(jq -r '.disabled_lanes|length' "$T/state/qa_mode.json")" = 3 ] && echo 1 || echo 0)"
M lane iptv_apps >/dev/null
ok "lane <repo> (underscore name) enables ongoing-iptv-apps and records it as a temp lane" "$([ "$(en ongoing-iptv-apps)" = true ] && jq -e '.temp_lanes|index("ongoing-iptv-apps")' "$T/state/qa_mode.json" >/dev/null && echo 1 || echo 0)"
M unlane iptv_apps >/dev/null
ok "unlane disables it again and drops it from temp_lanes" "$([ "$(en ongoing-iptv-apps)" = false ] && [ "$(jq -r '.temp_lanes|length' "$T/state/qa_mode.json")" = 0 ] && echo 1 || echo 0)"
ok "lane for an unknown repo fails without touching tasks.json" "$(M lane nope >/dev/null 2>&1; [ $? -ne 0 ] && jq -e . "$T/tasks.json" >/dev/null && echo 1 || echo 0)"
M off >/dev/null
ok "off restores exactly the lanes that on disabled (a,b,iptv-apps enabled; c still disabled)" "$([ "$(en ongoing-a)" = true ] && [ "$(en ongoing-b)" = true ] && [ "$(en ongoing-iptv-apps)" = true ] && [ "$(en ongoing-c)" = false ] && echo 1 || echo 0)"
ok "off removes the QA-mode state file" "$([ ! -f "$T/state/qa_mode.json" ] && echo 1 || echo 0)"
ok "off when not in QA mode is a harmless no-op" "$(M off | grep -q 'not in QA mode' && echo 1 || echo 0)"
ok "tasks.json is still valid JSON with all 6 tasks" "$([ "$(jq 'length' "$T/tasks.json")" = 6 ] && echo 1 || echo 0)"
echo "  $P passed, $F failed"; [ "$F" = 0 ]
