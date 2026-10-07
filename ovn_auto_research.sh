#!/usr/bin/env bash
# ovn_auto_research.sh — MAC-SIDE durable auto-research (2026-09-30).
#
# Closes the gap where ovn_research_trigger_check.sh (box cron) DETECTS a starving repo but nothing
# acts on it: only a Claude session can research a repo and write grounded roadmap features, and the
# box has no claude CLI/credentials. This runs on the Mac (launchd, like claude_queue_bridge.sh) using
# the Mac's existing `claude` login, so it needs no new credential and no API key on the box.
#
# Per run: read state/research_trigger_starving.json from the box, pick up to MAX_PER_RUN repos that
# have been starving >= MIN_STARVE_H and are not in per-repo cooldown, run ONE headless `claude -p`
# research pass per repo (read-only tools + WebSearch, hard $ cap), validate the proposed lines
# (format, dedupe, must cite a real file path), append the accepted ones to roadmap/<repo>.md on the
# box as [ready], commit there, and record a cooldown marker.
#
# Safety: daily cap (MAX_PER_DAY), per-repo cooldown, per-pass $ cap, lock (no overlap), the local
# clone must be unchanged afterwards (agent had no Bash/Edit, this is a belt-and-braces check),
# OVN_AUTO_RESEARCH=off kill switch, DRY_RUN=1 to validate without touching the box roadmap.
# Zero accepted items is a VALID outcome (an infra repo can be genuinely complete) - it still sets
# the cooldown so a complete repo is not re-researched every run.
set -uo pipefail

[ "${OVN_AUTO_RESEARCH:-on}" = "off" ] && exit 0
SHARED="${SHARED_DIR:-$HOME/LocalProjects/shared}"
SRV="${OVN_SSH:-mhintermeister@192.168.68.145}"
REMOTE="${OVN_REMOTE_DIR:-overnight-queue}"
CLONES="${OVN_CLONES_DIR:-$HOME/LocalProjects}"
STATE="${OVN_AUTO_RESEARCH_STATE:-$HOME/.ovn_auto_research}"
MAX_PER_RUN="${OVN_AR_MAX_PER_RUN:-2}"
MAX_PER_DAY="${OVN_AR_MAX_PER_DAY:-2}"   # 2026-10-07: Claude capacity is scarce (it hit its usage limit for days); the local Qwen refuel (ovn_local_research.py) is the engine, this is a quality bonus
MIN_STARVE_H="${OVN_AR_MIN_STARVE_H:-0.5}"
# Cooldown depends on the LAST pass's result (2026-10-03). A pass that accepted ZERO items means the repo may be genuinely complete -> wait long
# (COOLDOWN_EMPTY_H) so it is not re-researched every run. A PRODUCTIVE pass only needs a short pause (COOLDOWN_PRODUCTIVE_H, ~one launchd interval):
# the fleet burns 5 items in a few hours, and the starving check (MIN_STARVE_H) already says the repo is dry again. The old flat 18h left the
# Chickadee lane starved for 13h with nothing to do.
COOLDOWN_EMPTY_H="${OVN_AR_COOLDOWN_EMPTY_H:-18}"
COOLDOWN_PRODUCTIVE_H="${OVN_AR_COOLDOWN_PRODUCTIVE_H:-2}"
ar_cooldown_s() {   # <last_accepted_count or empty> -> cooldown seconds
  case "${1:-}" in ''|0) echo $(( COOLDOWN_EMPTY_H * 3600 ));; *[!0-9]*) echo $(( COOLDOWN_EMPTY_H * 3600 ));; *) echo $(( COOLDOWN_PRODUCTIVE_H * 3600 ));; esac
}
BUDGET="${OVN_AR_BUDGET_USD:-4}"
MODEL="${OVN_AR_MODEL:-sonnet}"
CLAUDE_BIN="${OVN_AR_CLAUDE:-$(command -v claude || echo $HOME/.local/bin/claude)}"
# macOS has no `timeout` unless Homebrew coreutils is on PATH (an interactive/restricted PATH made every pass fail with rc=127): use timeout/gtimeout when present, else run unbounded (the claude --max-budget-usd cap still bounds the pass).
TIMEOUT_BIN="$(command -v timeout || command -v gtimeout || true)"
VALIDATE="$SHARED/scripts/overnight-queue/ovn_auto_research_validate.py"
mkdir -p "$STATE"
LOG="$STATE/run.log"
log(){ echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

# mkdir lock (macOS has no flock by default); stale if older than 2h
if ! mkdir "$STATE/run.lock.d" 2>/dev/null; then
  if [ -n "$(find "$STATE/run.lock.d" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rmdir "$STATE/run.lock.d" 2>/dev/null; mkdir "$STATE/run.lock.d" 2>/dev/null || exit 0
  else log "another run active - skip"; exit 0; fi
fi

TODAY="$(date +%F)"; CNT_FILE="$STATE/count_$TODAY"; used="$(cat "$CNT_FILE" 2>/dev/null || echo 0)"
[ "$used" -ge "$MAX_PER_DAY" ] && { log "daily cap reached ($used/$MAX_PER_DAY) - skip"; exit 0; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"; rmdir "$STATE/run.lock.d" 2>/dev/null' EXIT
FORCE="${OVN_AR_FORCE_REPOS:-}"   # testing only: space-separated repos; bypasses starving/ready/cooldown checks (caps still apply)
if [ -z "$FORCE" ]; then
  ssh -o ConnectTimeout=20 -o BatchMode=yes "$SRV" "cat ~/$REMOTE/state/research_trigger_starving.json" > "$WORK/starving.json" 2>"$WORK/err" \
    || { log "ssh/starving.json read failed: $(head -c 200 "$WORK/err")"; exit 1; }
fi

# starving repos, longest first, fresh snapshot only (checker runs every 30 min; >3h old = checker itself is dead)
if [ -n "$FORCE" ]; then CANDIDATES="$FORCE"; else CANDIDATES="$(python3 - "$WORK/starving.json" "$MIN_STARVE_H" <<'PY'
import json, sys, time
d = json.load(open(sys.argv[1])); mn = float(sys.argv[2])
if time.time() - d.get("checked_at", 0) > 3 * 3600:
    sys.stderr.write("stale-snapshot\n"); sys.exit(0)
for r in sorted(d.get("starving", []), key=lambda x: -x["hours"]):
    if r["hours"] >= mn:
        print(r["repo"])
PY
)"; fi
[ -z "$CANDIDATES" ] && { log "no repo starving >= ${MIN_STARVE_H}h (or snapshot stale)"; exit 0; }

done_n=0
for repo in $CANDIDATES; do
  [ "$done_n" -ge "$MAX_PER_RUN" ] && break
  [ "$used" -ge "$MAX_PER_DAY" ] && break
  clone="$CLONES/$repo"; [ -d "$clone/.git" ] || { log "$repo: no local clone at $clone - skip"; continue; }
  marker="$STATE/researched_$repo"
  if [ -z "$FORCE" ] && [ -f "$marker" ] && [ $(( $(date +%s) - $(cat "$marker") )) -lt "$(ar_cooldown_s "$(cat "$STATE/researched_n_$repo" 2>/dev/null)")" ]; then
    log "$repo: in cooldown ($(( $(ar_cooldown_s "$(cat "$STATE/researched_n_$repo" 2>/dev/null)") / 3600 ))h after a pass that accepted ${n_last:-$(cat "$STATE/researched_n_$repo" 2>/dev/null || echo ?)} item(s)) - skip"; continue
  fi
  in="$WORK/in_$repo"; mkdir -p "$in"
  # re-check on the box right before spending money: is it STILL dry? (a refuel/landing may have fixed it)
  ready_n="$(ssh -o BatchMode=yes "$SRV" "grep -cE '^- \[ \] \[P[1-4]\] \[ready\]' ~/$REMOTE/roadmap/$repo.md 2>/dev/null || true")"
  if [ -z "$FORCE" ] && [ "${ready_n:-0}" -gt 0 ] 2>/dev/null; then log "$repo: already has $ready_n [ready] - skip"; continue; fi
  scp -q "$SRV:$REMOTE/roadmap/$repo.md" "$in/roadmap.md" 2>/dev/null || true
  scp -q "$SRV:$REMOTE/roadmap/README.md" "$in/README.md" 2>/dev/null || true
  ssh -o BatchMode=yes "$SRV" "cd ~/$REMOTE/repos/$repo && git log --format='%h %s' -40; echo '####'; tail -60 OVERNIGHT_PROGRESS.md | cut -c1-260" > "$in/recent.txt" 2>/dev/null
  [ -s "$in/roadmap.md" ] || { log "$repo: could not fetch roadmap - skip"; continue; }
  (cd "$clone" && git fetch -q origin 2>/dev/null)
  before="$(cd "$clone" && git status --porcelain | cksum)"
  # 2026-10-04: read a FRESH detached checkout of the branch the fleet works on, never the Mac clone's working tree (it lags: the agent "verified via Read"
  # that files the fleet had deleted still existed, and proposed re-deleting them). Falls back to the clone (with a log line) if the worktree cannot be made.
  src="$WORK/src_$repo"
  if git -C "$clone" worktree add -q --detach "$src" origin/overnight/feature 2>/dev/null || git -C "$clone" worktree add -q --detach "$src" origin/develop 2>/dev/null; then :; else log "$repo: could not create a fresh checkout - reading the clone's working tree (may be stale)"; src="$clone"; fi
  out="$in/proposed.md"; : > "$out"

  log "$repo: starting research pass (model=$MODEL budget=\$$BUDGET)"
  prompt="You are refueling ONE repo's feature roadmap for an autonomous overnight coding fleet (a local 27B model implements items one at a time, each gated by the repo's tests). REPO: $repo. A READ-ONLY checkout of the CURRENT code the fleet works on is $src (read ONLY this checkout - any other clone of the repo can be stale; you have no write or edit tools at all).
Read: $in/roadmap.md (current roadmap: note the stated maturity/stopping point and everything already decomposed/done - do NOT duplicate), $in/README.md (line format), $in/recent.txt (recent commits + queue tail). Then read the real repo (README, docs, file tree, the code you propose to touch).
Produce up to 10 NEW features worth building, grounded in actual code. Priority: (1) real live bugs/silent failures with file evidence, (2) security/legal/store/reliability gaps, (3) missing tests for important untested modules, (4) features fitting the repo's wedge. HONESTY: if the repo is genuinely at its 'complete - maintain only' line, return FEWER items, even zero; never invent filler. Every item must cite files that exist (verify with Read/Grep in the checkout). Art generation is human-gated: propose no art items.
QUALITY RULES (a 2026-10-04 audit of the fleet's landings found 19 dead helpers nothing calls, ghost tests that never run, and add/remove loops): (a) NEVER propose adding a new standalone helper/predicate/constant/formatter function, or a test for one, unless the SAME item also changes an existing production caller to use it - name that caller as file:line and verify it exists; a function nothing calls is rejected. (b) NEVER propose deleting a file or function without Grep-verifying in the checkout that it still exists and has no non-test callers; never re-propose anything the roadmap already marks done [x] or decomposed. (c) Tests must live where the repo's own test command collects them (iptv_apps: iptv-backend/tests/ ONLY, never next to modules under app/; xlite: res://tests/ ONLY, never res://test/). (d) Prefer items that change user-visible behaviour or fix a real bug; at most 2 test-only items per pass, and only for important modules with real logic and no existing test. (e) One item = one behavioural change with a concrete verifiable outcome; no refactor/cleanup/rename items unless you demonstrate a defect they fix.
Your FINAL reply must contain ONLY the feature lines (no preamble, no commentary, no code fences), one per line, exactly:
- [ ] [P<1-4>] [ready] <short title> — <what/why with file paths and evidence> {cat: <backend|web|mobile|game|infra|test>; size: <S|M|L>; multifile: <yes|no>; research: <none|repo|web>}
Status must be the literal word ready. Each item under ~900 characters, single line. If you add nothing, reply with exactly the word NONE."
  ( cd "$in" && ${TIMEOUT_BIN:+$TIMEOUT_BIN 1500} "$CLAUDE_BIN" -p "$prompt" --model "$MODEL" --max-budget-usd "$BUDGET" \
      --permission-mode dontAsk --no-session-persistence \
      --allowedTools "Read Grep Glob WebSearch WebFetch" \
      --add-dir "$src" --add-dir "$in" > "$in/claude_reply.txt" 2> "$in/claude_stderr.txt" ); rc=$?
  [ "$src" != "$clone" ] && { git -C "$clone" worktree remove --force "$src" 2>/dev/null; git -C "$clone" worktree prune 2>/dev/null; }
  cp "$in/claude_reply.txt" "$STATE/last_reply_$repo.txt" 2>/dev/null
  # the agent has no Write tool: the proposed lines ARE its reply (headless scoped-Write permissions are not honored)
  grep '^- \[ \]' "$in/claude_reply.txt" > "$out" 2>/dev/null || true
  after="$(cd "$clone" && git status --porcelain | cksum)"
  if [ "$before" != "$after" ]; then log "$repo: LOCAL CLONE CHANGED during research pass - discarding output, NOT applying (investigate $clone)"; continue; fi
  if [ "$rc" -ne 0 ]; then log "$repo: claude exited rc=$rc: $(tail -c 300 "$in/claude_stderr.txt" "$in/claude_reply.txt" | tr '\n' ' ')"; continue; fi
  if [ ! -s "$out" ] && ! grep -qx 'NONE' "$in/claude_reply.txt"; then log "$repo: reply had no feature lines and no NONE - treating as a FAILED pass, no cooldown set (see $STATE/last_reply_$repo.txt): $(head -c 200 "$in/claude_reply.txt" | tr '\n' ' ')"; continue; fi

  python3 "$VALIDATE" "$out" "$in/roadmap.md" 12 > "$in/accepted.md" 2> "$in/validate.err"
  while read -r l; do log "$repo: $l"; done < "$in/validate.err"
  n="$(grep -c '^- \[ \]' "$in/accepted.md" || true)"
  done_n=$((done_n+1))
  # a DRY_RUN must not consume the daily cap or start the repo's cooldown (it applies nothing)
  if [ -z "${DRY_RUN:-}" ]; then used=$((used+1)); echo "$used" > "$CNT_FILE"; date +%s > "$marker"; echo "${n:-0}" > "$STATE/researched_n_$repo"; fi
  if [ "${n:-0}" -eq 0 ]; then log "$repo: 0 accepted (repo may be complete, or agent output invalid) - cooldown set"; continue; fi
  if [ -n "${DRY_RUN:-}" ]; then log "$repo: DRY_RUN - $n item(s) validated, NOT applied ($in/accepted.md)"; cp "$in/accepted.md" "$STATE/dryrun_$repo.md"; continue; fi

  { echo ""; echo "## Auto-research $TODAY (ovn_auto_research.sh; $n item(s))"; cat "$in/accepted.md"; } > "$in/append.txt"
  scp -q "$in/append.txt" "$SRV:$REMOTE/state/auto_research_append_$repo.txt" || { log "$repo: scp append failed"; continue; }
  if ssh -o BatchMode=yes "$SRV" "cd ~/$REMOTE && cat state/auto_research_append_$repo.txt >> roadmap/$repo.md && rm -f state/auto_research_append_$repo.txt && git add roadmap/$repo.md && git commit -q -m 'chore(roadmap): auto-research $TODAY - $n ready feature(s) for $repo' && git push -q origin overnight-live"; then
    log "$repo: APPENDED $n [ready] feature(s) to box roadmap and pushed"
  else
    log "$repo: append/commit/push on box reported a failure - check 'git status' in ~/$REMOTE"
  fi
done
log "run complete: $done_n repo(s) researched, $used/$MAX_PER_DAY today"
