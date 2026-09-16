#!/usr/bin/env bash
# Regression guards for the 2026-09-16 context-overflow chain (billwatch/iptv_apps/xlite
# hitting qwen-dflash-27B's 65536-token hard limit, "model-api-error" outcome class).
# Four independent layers all had to be fixed; this file guards all four so a future edit
# can't silently regress any one of them back to a full-file reload.
set -uo pipefail
R="${OVN_RUNNER:-$HOME/overnight-queue/run_overnight.sh}"
TASKS="${OVN_TASKS:-$HOME/overnight-queue/tasks.json}"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

[ -f "$R" ] || { echo "  (skip: $R not present on this host)"; echo "Context budget invariants: 0 passed, 0 failed"; exit 0; }

# --- Layer 1: the --read arg must be capped to a bounded tail, not the whole file ---
ok "PROGRESS_MAX_BYTES cap exists" "grep -q 'PROGRESS_MAX_BYTES=' $R"
ok "tail file used when over the cap" "grep -q 'PROGRESS_TAIL_FILE=' $R"
ok "uncapped --read only used in the ELSE (under-cap) branch" \
  "awk '/PROGRESS_MAX_BYTES=\"/{c=1} c && /PROGRESS_READ_ARGS=\\(--read \"OVERNIGHT_PROGRESS.md\"\\)/{f=NR} c && /PROGRESS_TAIL_FILE=/{t=NR} END{exit !(t>0 && f>0 && f>t)}' $R"

# --- Layer 2: the tail file's OWN content must not literally name the source file
#     (aider auto-loads any mentioned existing repo file IN FULL - the whole point of
#     the tail cap is defeated if the tail's own header/body re-mentions it) ---
ok "tail header does not print the literal source filename" \
  "! grep -A3 'PROGRESS_TAIL_FILE=\"/tmp' $R | grep -q 'bytes of OVERNIGHT_PROGRESS.md'"
ok "tail content is sed-stripped of the literal source filename" \
  "grep -qE 'tail -c .\\\$PROGRESS_MAX_BYTES. OVERNIGHT_PROGRESS\\.md \\| sed' $R"

# --- Layer 3: the scout's free-text PLAN gets embedded verbatim into the next prompt -
#     it must be sanitized first (a 27B model saying \"per OVERNIGHT_PROGRESS.md...\" in
#     its own plan re-triggers the same full-file auto-load) ---
ok "OVN_PLAN is sanitized before being embedded in the implement prompt" \
  "grep -qE 'OVN_PLAN=\"\\\$\\(printf .%s. \"\\\$OVN_PLAN\" \\| sed' $R"

# --- Layer 4 (the actual dominant source): tasks.json's own persistent prompts must
#     never literally name OVERNIGHT_PROGRESS.md or README.md - every one of the 10
#     ongoing-* task definitions had this and it fired on EVERY SINGLE scout/implement
#     call, independent of layers 1-3 (all real, all insufficient on their own). ---
if [ -f "$TASKS" ] && command -v python3 >/dev/null 2>&1; then
  BAD="$(python3 -c "
import json, sys
try:
    tasks = json.load(open('$TASKS'))
except Exception as e:
    print('PARSE_ERROR:' + str(e)); sys.exit(0)
hits = []
for t in tasks:
    p = t.get('prompt', '')
    if 'OVERNIGHT_PROGRESS.md' in p or 'README.md' in p:
        hits.append(t.get('id', '?'))
print(','.join(hits))
")"
  ok "tasks.json prompts contain no literal OVERNIGHT_PROGRESS.md/README.md mentions" "[ -z \"$BAD\" ]"
  [ -n "$BAD" ] && echo "    (offending task ids: $BAD)"
else
  echo "  (skip: $TASKS not present or python3 unavailable on this host)"
fi

echo "Context budget invariants: $P passed, $F failed"
[ "$F" -eq 0 ]
