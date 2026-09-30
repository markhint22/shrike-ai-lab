#!/usr/bin/env bash
# run_overnight.sh main loop, part 2 (real script end to end in a hermetic fake tree): mid-run pause handling, best-of-N retry loop
# (enabled via state/pilot_flags.env), coder fast-batch pre-pass through the real main flow, model-metadata pass-through.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_ro_core.sh"
ro_init
ro_hook_stubs
ro_link update_progress.py dedupe_progress_headers.py dedupe_gd_duplicate_functions.py dedupe_python_duplicate_defs.py \
        scripts/ovn_classify.py scripts/ovn_progress_slice.py scripts/ovn_credit_already_satisfied.sh scripts/ovn_retire_vague.py scripts/ovn_extract_failure.sh
ST="$T/tree/state"; HK="$RO_STUB/hooks.log"; R="$T/repos"
mkdir -p "$ST"
row(){ printf '%s\n' "$REP" | grep -F "| $1 |" | head -1; }
rows(){ printf '%s\n' "$REP" | grep -cF "| $1 |"; }

echo "=== pause requested mid-run ==="
for n in p1 p2 p3; do ro_mkrepo "r-$n" >/dev/null; done
cat > "$RO_STUB/scn" <<EOF
case "\$(basename "\$(pwd)")" in
  r-p1) IMPL_SEQ=ok; SCN_TOUCH="$ST/PAUSED";;
esac
EOF
ro_tasks "$(jq -nc --arg R "$R" '[{id:"t-p1",repo:($R+"/r-p1"),prompt:"x"},{id:"t-p2",repo:($R+"/r-p2"),prompt:"x"},{id:"t-p3",repo:($R+"/r-p3"),prompt:"x"}]')"
: > "$HK"
ro_run_main
REP="$(ro_report)"
eq "run still exits 0" 0 "$RO_RC"
has "first task ran before the pause took effect" "$(row t-p1)" "pushed"
has "remaining tasks reported skipped(paused)" "$(row t-p2)" "skipped(paused)"
has "last task reported skipped(paused)" "$(row t-p3)" "skipped(paused)"
has "log explains the mid-run stop" "$RO_OUT" "Queue paused mid-run"
has "log counts the skipped tasks" "$RO_OUT" "2 task(s) skipped."
has "final line says stopped early" "$RO_OUT" "stopped early due to pause"
eq "paused tasks never reached aider" 0 "$(grep -cE 'r-p2|r-p3' "$RO_STUB/aider_cwds")"
has "end-of-cycle hooks still run after a pause" "$(cat "$HK")" "cycle_notify.sh"
hasnt "no outcome recorded for paused tasks" "$(cat "$ST/outcomes.jsonl")" "t-p2"
rm -f "$ST/PAUSED" "$T/tree/reports"/* "$RO_STUB/aider_cwds"

echo "=== best-of-N (state/pilot_flags.env) ==="
for n in bon-land bon-never bon-blocked bon-off; do ro_mkrepo "r-$n" >/dev/null; done
echo 'OVN_BESTOF_N=3' > "$ST/pilot_flags.env"
cat > "$RO_STUB/scn" <<'EOF'
case "$(basename "$(pwd)")" in
  r-bon-land)    if [ "$(grep -c '^scout$' "$S/aider_kinds" 2>/dev/null || true)" -ge 2 ]; then IMPL_SEQ=ok; else IMPL_SEQ=none; fi; SCOUT_EXTRA="this is a refactor";;
  r-bon-never)   IMPL_SEQ="none"; SCOUT_EXTRA="a multi-file change";;
  r-bon-blocked) SCOUT_VERDICT=BLOCKED; SCOUT_EXTRA="multiple files involved";;
  r-bon-off)     IMPL_SEQ="none";;
esac
EOF
: > "$RO_STUB/aider_n"; rm -f "$RO_STUB/impl_n" "$RO_STUB/aider_kinds"
ro_tasks "$(jq -nc --arg R "$R" '[{id:"t-bl",repo:($R+"/r-bon-land"),prompt:"x"},{id:"t-bn",repo:($R+"/r-bon-never"),prompt:"x"},{id:"t-bb",repo:($R+"/r-bon-blocked"),prompt:"x"},{id:"t-bo",repo:($R+"/r-bon-off"),prompt:"plain item"}]')"
ro_run_main
REP="$(ro_report)"
oc(){ jq -r --arg id "$1" --arg f "$2" 'select(.id==$id) | .[$f]' "$ST/outcomes.jsonl" | tail -1; }
has "pilot flags file was sourced (best-of-N active)" "$RO_OUT" "best-of-N: item t-bl attempt 2/3"
has "hard item that no-op'd lands on the retry" "$(row t-bl)" "pushed"
eq "landed on attempt 2 -> outcome attempt=2" 2 "$(oc t-bl attempt)"
eq "item that never lands is retried up to N (attempt=3)" 3 "$(oc t-bn attempt)"
has "never-landing item ends as no-op" "$(row t-bn)" "no-op"
has "retry log shows the previous status" "$RO_OUT" "attempt 3/3 (prev: no-op)"
eq "BLOCKED verdict is NOT retried (attempt stays 1)" 1 "$(oc t-bb attempt)"
eq "item whose log has no hard-item marker is not retried" 1 "$(oc t-bo attempt)"
hasnt "no best-of-N line for the blocked / plain items" "$RO_OUT" "item t-bb attempt"
rm -f "$ST/pilot_flags.env" "$T/tree/reports"/*

echo "=== model metadata file is passed through to aider ==="
ro_mkrepo r-meta >/dev/null
echo '{}' > "$T/tree/model-metadata.json"
echo 'IMPL_SEQ=none' > "$RO_STUB/scn"
ro_tasks "$(jq -nc --arg R "$R" '[{id:"t-meta",repo:($R+"/r-meta"),prompt:"x",map_tokens:"null"}]')"
ro_run_main
has "aider got --model-metadata-file" "$(cat "$RO_STUB/aider.last_args")" "--model-metadata-file $T/tree/model-metadata.json"
has "map_tokens 'null' falls back to the 3072 default" "$(cat "$RO_STUB/aider.last_args")" "--map-tokens 3072"
has "model passed as openai/<name>" "$(cat "$RO_STUB/aider.last_args")" "--model openai/qwen-dflash-27B"
rm -f "$T/tree/model-metadata.json" "$T/tree/reports"/*

echo "=== coder fast-batch pre-pass through the real main flow ==="
for n in c1 c2 c3 s1; do ro_mkrepo "r-$n" >/dev/null; done
printf '#!/bin/bash\necho "serve $*" >> "%s/serve.log"\nexit 0\n' "$RO_STUB" > "$T/serve_ok.sh"; chmod +x "$T/serve_ok.sh"
echo 'IMPL_SEQ=ok' > "$RO_STUB/scn"; : > "$RO_STUB/docker.log"; : > "$RO_STUB/aider_cwds"; rm -f "$RO_STUB/impl_n"
ro_tasks "$(jq -nc --arg R "$R" '[{id:"t-c1",repo:($R+"/r-c1"),prompt:"x",coder_eligible:true},{id:"t-c2",repo:($R+"/r-c2"),prompt:"x",coder_eligible:true},{id:"t-c3",repo:($R+"/r-c3"),prompt:"x",coder_eligible:true},{id:"t-s1",repo:($R+"/r-s1"),prompt:"x",persistent_branch:true}]')"
ro_run_main OVN_CODER_FAST=1 OVN_CODER_MIN_BATCH=3 OVN_SERVE_EVAL="$T/serve_ok.sh"
REP="$(ro_report)"
eq "coder batch run exits 0" 0 "$RO_RC"
has "prepass opened a coder window for 3 items" "$RO_OUT" "CODER FAST BATCH: 3 eligible simple item(s) >= break-even 3"
has "coder window opened then closed" "$RO_OUT" "CODER WINDOW: 27B restored + healthy."
has "27B container stopped + restarted around the batch" "$(cat "$RO_STUB/docker.log")" "docker start shrike-llama-dflash-35b"
has "serve-eval started the coder gguf" "$(cat "$RO_STUB/serve.log")" "serve Qwen3-Coder-30B-A3B-Instruct-Q4_K_M.gguf 32768"
has "coder rows are tagged (coder)" "$(row t-c1)" "(coder)"
has "coder task used the diff edit format + coder model" "$RO_OUT" "[CODER] Task t-c1 (model=coder-30b, edit-format=diff)"
eq "non-eligible persistent task was not in the coder batch" 0 "$(printf '%s\n' "$REP" | grep -F '| t-s1 |' | grep -c '(coder)')"
has "non-eligible task still runs afterwards on the 27B" "$(row t-s1)" "pushed"
eq "coder hold marker cleaned up" 0 "$([ -f "$ST/coder_window.hold" ] && echo 1 || echo 0)"
known_bug "tasks already processed in the coder window are processed AGAIN by the main loop (CODER_DONE is only consulted inside coder_process_index, never by the main for-loop at run_overnight.sh:3068); t-c1 has $(rows t-c1) report rows, expected 1; patch: after the ENABLED check add: [ \"\${OVN_CODER_FAST:-0}\" = 1 ] && case \" \${CODER_DONE:-} \" in *\" \$ID \"*) continue;; esac" "$([ "$(rows t-c1)" = 1 ] && echo 1 || echo 0)"

echo "=== coder window failure falls back to 27B ==="
touch "$RO_STUB/coder_unhealthy"
ro_tasks "$(jq -nc --arg R "$R" '[{id:"t-c1",repo:($R+"/r-c1"),prompt:"x",coder_eligible:true},{id:"t-c2",repo:($R+"/r-c2"),prompt:"x",coder_eligible:true}]')"
echo 'IMPL_SEQ=none' > "$RO_STUB/scn"
rm -f "$T/tree/reports"/*
ro_run_main OVN_CODER_FAST=1 OVN_CODER_MIN_BATCH=2 OVN_SERVE_EVAL="$T/serve_ok.sh"
REP="$(ro_report)"
has "unhealthy coder backend: window open FAILED logged" "$RO_OUT" "window open FAILED"
hasnt "no row tagged (coder) after a failed window" "$REP" "(coder)"
has "items fall back to the normal 27B path" "$(row t-c1)" "no-op"
rm -f "$RO_STUB/coder_unhealthy"

ro_summary
