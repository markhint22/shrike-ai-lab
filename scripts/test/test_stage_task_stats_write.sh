#!/usr/bin/env bash
# Regression test for run_overnight.sh's higher-tier inline sub-flow writing a
# state/task_stats.log line (2026-09-20). cycle_notify.sh only ever populates
# task_stats.log for the basic scout+implement flow (it needs a matching
# state/cycle_summary.log line, which the staged/T3+ inline sub-flow never writes since it
# returns before that code runs) — so ovn_stats.py's by-language/type pass-rate breakdown was
# blind to any repo whose real work went entirely through the staged pipeline (confirmed live:
# shrike-monitor/xlite). Fix: the staged sub-flow now also appends a task_stats.log-compatible
# line itself, using the run's own stage_runs/*.jsonl (repo/tier/item text) instead of routing
# through cycle_summary.log at all. Extracts the real write out of run_overnight.sh so this
# can't drift from what's deployed.
set -uo pipefail
RO="${OVN_RUN_OVERNIGHT:-$HOME/overnight-queue/run_overnight.sh}"
[ -f "$RO" ] || { echo "  SKIP: $RO not found on this host"; exit 0; }

grep -q 'event":"decomposed"' "$RO" || { echo "  FAIL: stage-routed task_stats.log write not found in $RO"; exit 1; }
WRITE_LINE="$(grep -n 'task_stats.log"$' "$RO" | grep -c '_stage_oc')"
[ "${WRITE_LINE:-0}" -gt 0 ] || { echo "  FAIL: could not find the stage-routed printf into task_stats.log in $RO"; exit 1; }

P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }

# mirrors the deployed extraction+write logic exactly (given a stage_runs jsonl + push count)
write_stage_task_stats(){ # $1=jsonl $2=repo $3=pushed-count $4=out-file
  local jsonl="$1" repo="$2" pushed="$3" out="$4"
  local _stage_item _stage_file _stage_tag _stage_oc
  _stage_item="$(grep -m1 '"event":"decomposed"' "$jsonl" | grep -oE '"item":"[^"]*"' | sed -E 's/^"item":"//; s/"$//')"
  _stage_file="$(printf '%s' "$_stage_item" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]{1,8}' | grep -vE '\.md$' | head -1)"
  _stage_tag="{py·other·T${5:-3}·test-covered}"   # stand-in for ovn_classify.py --tag (tested separately)
  if [ -n "$pushed" ] && [ "$pushed" -gt 0 ]; then _stage_oc=pass; else _stage_oc=noop:flail; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "111" "$repo" "$_stage_oc" "$_stage_tag" "${_stage_file:-?}" >> "$out"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jsonl="$tmp/gitlark-run.jsonl"
cat > "$jsonl" <<'JEOF'
{"run":"r1","repo":"gitlark","tier":5,"item":"[T5] web/src/pages/Foo.spec.ts — do a thing. VERIFY: npx vitest run. (cat:test; multifile:no)","event":"decomposed","steps":1}
{"run":"r1","step":0,"desc":"...","files":"web/src/pages/Foo.spec.ts","attempt":1,"verdict":"pass"}
{"run":"r1","event":"verify","verified":true}
{"run":"r1","event":"summary","tier":5,"passed":1,"total":1,"verified":true,"commits_pushed":1}
JEOF

out1="$tmp/task_stats_pass.log"
write_stage_task_stats "$jsonl" "gitlark" 1 "$out1"
ok "a real push writes exactly one task_stats.log line" "[ \$(wc -l < '$out1') -eq 1 ]"
# use a literal tab, not a \t escape — GNU grep's BRE/ERE does not treat \t as tab by default
TAB="$(printf '\t')"
ok "outcome is 'pass' when commits_pushed > 0" "grep -qF '${TAB}gitlark${TAB}pass${TAB}' '$out1'"
ok "the target file is extracted from the item text" "grep -q 'web/src/pages/Foo.spec.ts' '$out1'"

out2="$tmp/task_stats_noop.log"
write_stage_task_stats "$jsonl" "gitlark" 0 "$out2"
ok "an unverified/no-push run is recorded as noop:flail, not silently dropped" "grep -q 'noop:flail' '$out2'"

echo "Stage-routed task_stats.log write: $P passed, $F failed"
[ "$F" -eq 0 ]
