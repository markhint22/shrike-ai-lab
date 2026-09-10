#!/usr/bin/env bash
# ovn_stage_sweep.sh — run the multi-stage runner on a few repos that have doable T3+ items.
#
# DEDICATED INFERENCE (2026-09-07): the single-threaded llama-server has no --parallel, so when the
# fleet's aider procs and the stage runner hit the 27B at once, each request queues and effective
# throughput HALVES (measured 60 tok/s solo -> 27 tok/s contended), which is what makes higher-tier
# steps hit the 500s timeout and fail. Since higher-tier is the priority, we PAUSE the fleet for the
# sweep so the staged items get the 27B to themselves (~2x faster -> far fewer timeouts). The fleet
# checks state/PAUSED between items and resumes the moment we clear it. A trap guarantees un-pause even
# on crash; pause_guard.sh clears a stale stage-owned pause as a backstop.
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
MAX="${OVN_STAGE_SWEEP_MAX:-1}"; done=0
DEDICATE="${OVN_STAGE_DEDICATE:-1}"

paused_by_us=0
if [ "$DEDICATE" = 1 ] && [ ! -f state/PAUSED ]; then
  touch state/PAUSED; date +%s > state/stage_pause_since; paused_by_us=1
  echo "$(date '+%F %T') stage-sweep: paused fleet for dedicated 27B" >> logs/ovn_stage_runner.log
fi
cleanup(){ [ "$paused_by_us" = 1 ] && rm -f state/PAUSED state/stage_pause_since; }
trap cleanup EXIT INT TERM

# WAIT for the fleet's in-flight aider to actually FINISH before starting — a fixed sleep wasn't enough
# (a fleet item runs up to 600s). If our higher-tier item ran CONCURRENTLY with a fleet aider on the
# single-threaded llama-server, that contention is exactly what times out higher-tier tasks. The fleet
# is PAUSED so it won't start a NEW item; we just poll until the current one drains, capped so we never
# hang. Only THEN do we have the GPU truly to ourselves.
# ensure the fleet is paused even if we didn't set it (idempotent) — belt for the drain-wait below
[ -f state/PAUSED ] || { touch state/PAUSED; date +%s > state/stage_pause_since; }
# ALWAYS wait for the GPU to be free (zero aiders) before starting — regardless of WHO paused the fleet.
# This is the hard no-contention guarantee: a higher-tier item never runs concurrently with any other
# aider on the single-threaded server. Capped at ~11 min so a stuck fleet item can't hang the sweep.
for _w in $(seq 1 66); do
  pgrep -f 'bin/aider ' >/dev/null 2>&1 || break
  sleep 10
done
echo "$(date '+%F %T') stage-sweep: GPU idle (0 aiders), starting dedicated" >> logs/ovn_stage_runner.log

# ONLY godot (.gd) is permanently routed away from the 27B: it's measured at ~0% there (the model can't
# produce a working Godot edit, so aider just wanders until the 25-min timeout — a pure wasted slot).
# EVERYTHING ELSE the 27B still ATTEMPTS itself — frontend (.vue/.tsx), wiring/integrate, and T4/T5 —
# because it lands *some* of those (e.g. shrike-notify T4 100%), and the verify layer + per-item
# escalation route the ones it can't. We are NOT skimming the hard work away from it; only godot.
# Safe to commit here because the fleet is PAUSED for the sweep (no git race on the repo).
escalate_godot(){ # $1=repo $2=file  -> tag doable GODOT T3+ items route-to-Claude, commit+push
  local r="$1" f="$2" n
  n="$(python3 - "$f" <<'PY'
import re,sys
f=sys.argv[1]; L=open(f,encoding="utf-8").read().split("\n"); n=0
for i,l in enumerate(L):
    if l.startswith("- [ ] ") and re.search(r"\[T[1-5]\]|·T[1-5]·",l) and not re.search(r"AUTO-SKIP|HUMAN-ONLY|BLOCKED",l):
        if re.search(r"\.gd\b",l,re.I):
            L[i]=l.replace("- [ ] ","- [ ] [AUTO-SKIP godot(.gd) — 27B measured 0%, route to CLAUDE] ",1); n+=1
if n: open(f,"w",encoding="utf-8").write("\n".join(L))
print(n)
PY
)"
  [ "${n:-0}" -gt 0 ] || return 0
  ( cd "repos/$r" && git add OVERNIGHT_PROGRESS.md &&
    git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "chore(queue): route $n godot(.gd) items to Claude — 27B can't do Godot; keep it on code it can land" &&
    { git push -q origin overnight/feature 2>/dev/null || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }; } ) &&
    echo "$(date '+%F %T') stage-sweep: routed $n godot $r items to Claude" >> logs/ovn_stage_runner.log
}

ALL_REPOS="gitlark billwatch test-automation-agent shrike-notify shrike-monitor iptv_apps xlite"  # xlite: only its .gd is filtered out (routed to Claude); any non-godot work IS run by the 27B

# Pass 1 (always, all repos): route GODOT items to Claude. Only godot — nothing else is skimmed.
for r in $ALL_REPOS; do
  f="repos/$r/OVERNIGHT_PROGRESS.md"; [ -f "$f" ] || continue
  grep -qE '^- \[ \] .*\.gd\b' "$f" && escalate_godot "$r" "$f"
done

# Pass 2 (MAX-bounded): RUN any repo with a doable NON-GODOT T3+ item. The runner's auto-pick prefers
# python (highest land-rate) but also TRIES the harder frontend/wiring/T4/T5 items — we do NOT restrict
# it to python. Godot is the only thing excluded here (it's been routed to Claude in Pass 1).
for r in $ALL_REPOS; do
  [ "$done" -ge "$MAX" ] && break
  f="repos/$r/OVERNIGHT_PROGRESS.md"; [ -f "$f" ] || continue
  nongodot="$(grep -E '^- \[ \] ' "$f" | grep -vE 'AUTO-SKIP|HUMAN-ONLY|BLOCKED' | grep -E '\[T[345]\]|·T[345]·' | grep -viE '\.gd\b')"
  [ -z "$nongodot" ] && continue
  timeout 1500 bash ovn_stage_runner.sh "$r" >> logs/ovn_stage_runner.log 2>&1 && done=$((done+1))
done
echo "$(date '+%F %T') stage-sweep ran $done repo(s)$([ "$paused_by_us" = 1 ] && echo ' (dedicated)')" >> logs/ovn_stage_runner.log
# cleanup() on EXIT clears the pause -> fleet resumes immediately
