#!/usr/bin/env bash
# Tests for work_summary.py — the "what did the fleet actually DO" 24h digest embedded in
# supervisor.sh's push (both the "N item(s) need attention" and the once-daily all-clear
# "Overnight fleet — daily work summary" variants). Previously untested. Added 2026-09-20
# alongside the script's own "📝 Landed detail" addition (per-item repo+tier+file lines,
# sourced from state/task_stats.log via scripts/ovn_landed_detail.py) - covers both the
# pre-existing aggregate-count behavior (regression coverage that didn't exist before) and
# the new detail section. Runs against a fixture $HOME so it never touches production data.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WS="$HERE/../../work_summary.py"; [ -f "$WS" ] || WS="$HERE/../work_summary.py"; [ -f "$WS" ] || WS="$HERE/work_summary.py"
[ -f "$WS" ] || { echo "  SKIP: work_summary.py not found"; exit 0; }
LANDED_DETAIL="$(dirname "$WS")/scripts/ovn_landed_detail.py"

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Isolate HOME too, not just CWD: ovn_landed_detail.py's own default state-file lookup
# falls back to "~/overnight-queue/state/task_stats.log" (see its header) when no
# TASK_STATS override is set - without this, test 1/2 below would silently read REAL
# production task_stats.log instead of this fixture's empty/absent one (confirmed live:
# without this export, "no landed-detail header" and "shows the real target file for
# gitlark" both failed against real prod data on the actual server, not this fixture).
export HOME="$tmp/fakehome"
cd "$tmp"
mkdir -p state
OUT="state/outcomes.jsonl"
now="$(date -u +%FT%TZ 2>/dev/null || python3 -c 'import datetime;print(datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"))')"

# --- 1: pre-existing aggregate-count behavior (no prior test covered this at all) ---
cat > "$OUT" <<EOF2
{"ts":"$now","repo":"billwatch","id":"ongoing-billwatch","type":"aider_fix","tier":"2","category":"endpoint","class":"landed","severity":"good","attempt":1,"fail_reason":"","status":"pushed(tests:pass)","tokens_sent":1,"tokens_recv":1}
{"ts":"$now","repo":"gitlark","id":"ongoing-gitlark","type":"aider_fix","tier":"3","category":"vue","class":"landed","severity":"good","attempt":1,"fail_reason":"","status":"pushed(tests:pass)","tokens_sent":1,"tokens_recv":1}
{"ts":"$now","repo":"billwatch","id":"ongoing-billwatch","type":"aider_fix","tier":"1","category":"vue","class":"noop","severity":"bad","attempt":1,"fail_reason":"landed","status":"no-op","tokens_sent":1,"tokens_recv":1}
EOF2
out1="$(python3 "$WS" 24 2>&1)"
ok "reports the landed/no-op aggregate line" "printf '%s' \"\$out1\" | grep -qE 'Last 24h: 2 landed .* 1 no-op'"
ok "reports landed-by-tier"                  "printf '%s' \"\$out1\" | grep -q 'T2:1 T3:1'"
ok "reports by-repo counts"                  "printf '%s' \"\$out1\" | grep -q 'billwatch 1'"

# --- 2: no landed detail section when task_stats.log has nothing in the window (script
#     absent from this fixture's cwd, or simply no rows) - must not crash or print an
#     empty/broken section ---
ok "no landed-detail header when there's nothing to show" "! printf '%s' \"\$out1\" | grep -q 'Landed detail'"

# --- 3: the new per-item detail section appears once task_stats.log has real rows, WITHOUT
#     removing any of the pre-existing aggregate lines ---
if [ -f "$LANDED_DETAIL" ]; then
  mkdir -p scripts
  cp "$LANDED_DETAIL" scripts/ovn_landed_detail.py
  ts="$(date +%s)"
  cat > state/task_stats.log <<EOF3
$ts	billwatch	pass	{py·other·T2·test-covered}	billwatch-backend/app/services/trending_service.py
$ts	gitlark	pass	{vue·a11y·T3·test-covered}	web/src/pages/SelectRepositoriesPage.vue
EOF3
  out2="$(OVN_LANDED_DETAIL_SCRIPT="$tmp/scripts/ovn_landed_detail.py" python3 "$WS" 24 2>&1)"
  ok "aggregate line is still present alongside the new detail section" \
     "printf '%s' \"\$out2\" | grep -qE 'Last 24h: 2 landed'"
  ok "landed-detail header appears"          "printf '%s' \"\$out2\" | grep -q 'Landed detail'"
  ok "shows the real target file for billwatch" \
     "printf '%s' \"\$out2\" | grep -q 'billwatch (T2·other): billwatch-backend/app/services/trending_service.py'"
  ok "shows the real target file for gitlark" \
     "printf '%s' \"\$out2\" | grep -q 'gitlark (T3·a11y): web/src/pages/SelectRepositoriesPage.vue'"

  # --- 4: a missing/broken detail script must never crash work_summary.py itself ---
  out3="$(OVN_LANDED_DETAIL_SCRIPT="$tmp/scripts/does_not_exist.py" python3 "$WS" 24 2>&1)"
  ok "missing detail script: work_summary.py still runs and reports aggregates" \
     "printf '%s' \"\$out3\" | grep -qE 'Last 24h: 2 landed'"
else
  echo "  SKIP: ovn_landed_detail.py not found — skipping detail-section checks"
fi

# --- 5: no outcomes file at all ---
rm -f "$OUT"
out4="$(python3 "$WS" 24 2>&1)"
ok "no outcomes file: reports gracefully instead of crashing" "printf '%s' \"\$out4\" | grep -q 'no outcomes file'"

echo "work_summary.py: $P passed, $F failed"
[ "$F" -eq 0 ]
