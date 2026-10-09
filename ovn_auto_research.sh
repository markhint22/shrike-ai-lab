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

# mkdir lock (macOS has no flock by default).
# 2026-10-09: the lock records its holder ("<pid> <epoch>") and every skip says WHO holds it, how old the lock is and whether that pid is alive
# (ps stat, never kill -0: a killed-but-unreaped child still answers kill -0). A lock whose holder is dead, or that is older than LOCK_STALE_H (3h), is
# removed and the run continues. Why this exists: run.log alternated "daily cap reached" / "another run active - skip" / "another run active - skip"
# for days; the old code took the lock BEFORE the cap check and only installed the releasing trap AFTER it, so every cap-reached run leaked the lock
# (now fixed: the trap is installed right after the lock is taken). OVN_AR_LOCK_DIAG=off restores the old 2h-by-mtime rule with no holder bookkeeping.
LOCKD="$STATE/run.lock.d"
LOCK_STALE_H="${OVN_AR_LOCK_STALE_H:-3}"
LOCK_HOLDER_PATTERN="${OVN_AR_LOCK_HOLDER_PATTERN:-ovn_auto_research}"   # a live pid whose command does not contain this is a REUSED pid, i.e. not our holder
mtime_epoch(){ stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
holder_state(){   # <pid> -> prints "alive(<stat>)" or "dead(<why>)"; returns 0 if alive
  local st cmd; st="$(ps -o stat= -p "$1" 2>/dev/null | tr -d ' ')"
  if [ -z "$st" ]; then echo "dead(no such process)"; return 1; fi
  case "$st" in Z*) echo "dead(zombie)"; return 1;; esac
  cmd="$(ps -o command= -p "$1" 2>/dev/null)"
  case "$cmd" in *"$LOCK_HOLDER_PATTERN"*) echo "alive($st)"; return 0;; *) echo "dead(pid reused by another command)"; return 1;; esac
}
release_lock(){   # only remove a lock that is still OURS (a later run may have cleaned a stale one and taken it)
  local hp; hp="$(cut -d' ' -f1 "$LOCKD/holder" 2>/dev/null)"
  if [ -z "$hp" ] || [ "$hp" = "$$" ]; then rm -rf "$LOCKD"; fi
}
GUARD="$LOCKD.takeover"; HAVE_GUARD=""
NOHOLDER_STALE_MIN="${OVN_AR_LOCK_NOHOLDER_STALE_MIN:-10}"; GUARD_STALE_MIN="${OVN_AR_LOCK_GUARD_STALE_MIN:-10}"
drop_guard(){   # only the takeover guard WE hold
  if [ -n "$HAVE_GUARD" ]; then
    case "$(head -n 1 "$GUARD/owner" 2>/dev/null)" in ""|"$$") rm -rf "$GUARD";; esac
    HAVE_GUARD=""
  fi
}
WORK=""
if mkdir "$LOCKD" 2>/dev/null; then
  [ "${OVN_AR_LOCK_DIAG:-on}" = "off" ] || echo "$$ $(date +%s)" > "$LOCKD/holder"
elif [ "${OVN_AR_LOCK_DIAG:-on}" = "off" ]; then
  if [ -n "$(find "$LOCKD" -maxdepth 0 -mmin +120 2>/dev/null)" ]; then rm -rf "$LOCKD"; mkdir "$LOCKD" 2>/dev/null || exit 0
  else log "another run active - skip"; exit 0; fi
else
  # judge_lock sets hpid/hts/hline/hstate/h_alive/age_s/stale from whatever lock is on disk RIGHT NOW (it is called twice: once to decide, once more under
  # the takeover guard to confirm). The holder file is untrusted input (a crash can leave it truncated or garbage): only "<digits> <digits>" is believed,
  # anything else is unknown and the age falls back to the lock directory's mtime. A lock with NO holder file (a leaked empty dir from the old script, or a
  # run between its mkdir and its holder write - milliseconds) is stale after NOHOLDER_STALE_MIN (10) minutes, not 3h.
  judge_lock(){   # [dir]  (default: the lock path)
    local jd="${1:-$LOCKD}"
    hpid=""; hts=""; hline=""; stale=""
    hline="$(head -n 1 "$jd/holder" 2>/dev/null)" || true   # not `read < file 2>/dev/null`: the failed redirect would print a raw bash error first
    if [[ "$hline" =~ ^([0-9]{1,9})\ ([0-9]{1,12})$ ]]; then hpid="${BASH_REMATCH[1]}"; hts="${BASH_REMATCH[2]}"
    elif [[ "$hline" =~ ^[0-9]{1,9}$ ]]; then hpid="$hline"; fi
    now_s="$(date +%s)"
    case "$hts" in ""|*[!0-9]*) hts="$(mtime_epoch "$jd")"; case "$hts" in ""|*[!0-9]*) hts="$now_s";; esac;; esac
    age_s=$(( now_s - hts )); [ "$age_s" -ge 0 ] || age_s=0
    if [ -n "$hpid" ]; then
      hstate="$(holder_state "$hpid")" && h_alive=1 || h_alive=0
    else
      if [ -n "$hline" ]; then hstate="unknown(invalid holder file)"; else hstate="unknown(no holder file)"; fi
      h_alive=1
    fi
    if [ "$h_alive" = 0 ]; then stale="holder dead"
    elif [ -z "$hline" ] && [ "$age_s" -gt $(( NOHOLDER_STALE_MIN * 60 )) ]; then stale="no holder file for more than ${NOHOLDER_STALE_MIN}m"
    elif [ "$age_s" -gt $(( LOCK_STALE_H * 3600 )) ]; then stale="lock older than ${LOCK_STALE_H}h"; fi
  }
  judge_lock
  if [ -n "$stale" ]; then
    log "stale run lock removed ($stale): holder pid=${hpid:-?} $hstate age=$(( age_s / 60 ))m"
    # Takeover is serialised by a mkdir MUTEX ($GUARD): only one run at a time may judge-move-recreate, so a third run can never have its fresh lock deleted
    # by a slower run's cleanup. Under the guard the verdict is re-taken from the disk (a lock that is no longer stale = another run got there first -> skip),
    # then the stale lock is moved aside (never deleted in place) and re-created. A guard leaked by a killed run is cleaned after GUARD_STALE_MIN minutes.
    trap 'rm -rf "${WORK:-}"; drop_guard' EXIT
    if ! mkdir "$GUARD" 2>/dev/null; then
      gts="$(mtime_epoch "$GUARD")"; case "$gts" in ""|*[!0-9]*) gts="$(date +%s)";; esac
      if [ $(( $(date +%s) - gts )) -gt $(( GUARD_STALE_MIN * 60 )) ]; then
        log "takeover guard older than ${GUARD_STALE_MIN}m (its run died) - removed"
        rm -rf "$GUARD"; mkdir "$GUARD" 2>/dev/null || { log "another run is taking over the stale lock - skip"; exit 0; }
      else log "another run is taking over the stale lock - skip"; exit 0; fi
    fi
    HAVE_GUARD=1; echo "$$" > "$GUARD/owner"
    log "stale run lock: takeover guard taken"
    if [ -d "$LOCKD" ]; then
      judge_lock
      if [ -z "$stale" ]; then log "lock was replaced by another run during the stale cleanup - skip"; exit 0; fi
      log "stale run lock confirmed under the takeover guard ($stale)"
      stale_dir="$LOCKD.stale.$$"; confirmed_line="$hline"
      mv "$LOCKD" "$stale_dir" 2>/dev/null || { log "lock changed under us after a stale cleanup - skip"; exit 0; }
      # the moved directory must STILL be the lock we confirmed: same holder line AND still stale when judged again as the moved dir (a fresh holder-less lock
      # swapped in by another run has the same empty holder line as the stale one, but it is not stale)
      moved_line="$(head -n 1 "$stale_dir/holder" 2>/dev/null)" || true
      judge_lock "$stale_dir"
      if [ "$moved_line" != "$confirmed_line" ] || [ -z "$stale" ]; then   # swapped between the confirmation and the move: put it back, never mv onto an existing dir (it would nest)
        if [ ! -e "$LOCKD" ]; then mv "$stale_dir" "$LOCKD" 2>/dev/null || rm -rf "$stale_dir"; else rm -rf "$stale_dir"; fi
        log "lock was replaced by another run during the stale cleanup - skip"; exit 0
      fi
      rm -rf "$stale_dir"
    fi
    mkdir "$LOCKD" 2>/dev/null || { log "lost the lock race after a stale cleanup - skip"; exit 0; }
    echo "$$ $(date +%s)" > "$LOCKD/holder"
    drop_guard
  else
    log "another run active - skip (lock holder pid=${hpid:-?} $hstate age=$(( age_s / 60 ))m)"; exit 0
  fi
fi
trap 'rm -rf "${WORK:-}"; drop_guard; release_lock' EXIT

TODAY="$(date +%F)"; CNT_FILE="$STATE/count_$TODAY"; used="$(cat "$CNT_FILE" 2>/dev/null || echo 0)"
[ "$used" -ge "$MAX_PER_DAY" ] && { log "daily cap reached ($used/$MAX_PER_DAY) - skip"; exit 0; }

WORK="$(mktemp -d)"
FORCE="${OVN_AR_FORCE_REPOS:-}"   # testing only: space-separated repos; bypasses starving/ready/cooldown checks (caps still apply)
if [ -z "$FORCE" ]; then
  ssh -o ConnectTimeout=20 -o BatchMode=yes "$SRV" "cat ~/$REMOTE/state/research_trigger_starving.json" > "$WORK/starving.json" 2>"$WORK/err" \
    || { log "ssh/starving.json read failed: $(head -c 200 "$WORK/err")"; exit 1; }
fi

# starving repos, longest first, fresh snapshot only (checker runs every 30 min; >3h old = checker itself is dead)
if [ -n "$FORCE" ]; then CANDIDATES="$FORCE"; else
# 2026-10-09 (review fix): Claude capacity is scarce, so a candidate must be BOTH on the lane allowlist (OVN_AR_REPOS, default "iptv_apps xlite" = the
# active dev lanes; "all" disables it) AND really short of work: the trigger check writes each record's `pullable` count (what the fleet can take next);
# a repo whose pullable is above OVN_AR_PULLABLE_MAX (default 10 = OVN_TRIGGER_PULLABLE_MIN) is not starving whatever the planner log says. Without this the
# round-robin handed the 2nd daily slot to shrike-notify (pullable 42) / shrike-monitor (35) and xlite got nothing. Excluded repos are logged with the reason.
python3 - "$WORK/starving.json" "$MIN_STARVE_H" "${OVN_AR_PULLABLE_MAX:-10}" "${OVN_AR_REPOS-iptv_apps xlite}" > "$WORK/cand.tsv" 2> "$WORK/cand.err" <<'PY'
import json, sys, time
mn = float(sys.argv[2]); pmax = float(sys.argv[3]); allow = sys.argv[4].split()
try:
    d = json.load(open(sys.argv[1]))
    if not isinstance(d, dict):
        raise ValueError("not an object")
except (OSError, ValueError):   # an empty / truncated / non-JSON snapshot is "nothing to do", not a traceback in run.log
    sys.stderr.write("starving snapshot unreadable (empty, truncated or not a JSON object) - ignored\n"); sys.exit(0)
if time.time() - d.get("checked_at", 0) > 3 * 3600:
    sys.stderr.write("stale starving snapshot - ignored\n"); sys.exit(0)
for r in sorted(d.get("starving", []), key=lambda x: -x["hours"]):
    if r["hours"] < mn:
        continue
    if allow and "all" not in allow and r["repo"] not in allow:
        sys.stderr.write("excluded %s: not in the research lane allowlist (OVN_AR_REPOS=%s)\n" % (r["repo"], " ".join(allow))); continue
    pull = r.get("pullable")
    if isinstance(pull, (int, float)) and not isinstance(pull, bool) and pull > pmax:
        sys.stderr.write("excluded %s: pullable=%s > %s (not really starving)\n" % (r["repo"], pull, int(pmax) if pmax == int(pmax) else pmax)); continue
    print("%s\t%s" % (r["repo"], r["hours"]))
PY
[ -s "$WORK/cand.err" ] && while IFS= read -r l; do log "$l"; done < "$WORK/cand.err"
# 2026-10-09 ORDER: with MAX_PER_DAY=2 "longest-starving first" gave BOTH daily slots to xlite (10-08 01:33+03:47, 10-09 02:05+04:20) while iptv_apps' last pass
# was 10-07 08:21. roundrobin = fewest passes that ACCEPTED items in the last 48h (from run.log "<repo>: accepted N/M" lines, N>0) first, then the longest
# starving. OVN_AR_ORDER=legacy keeps the old longest-first order. The chosen order is logged so the next run shows it.
CANDIDATES="$(python3 - "$WORK/cand.tsv" "$LOG" "${OVN_AR_ORDER:-roundrobin}" 2> "$WORK/order.err" <<'PY'
import re, sys, time
cand, log_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
rows = [l.rstrip("\n").split("\t") for l in open(cand) if l.strip()]
acc = {}
if mode != "legacy":
    pat = re.compile(r"^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (\S+): accepted (\d+)/\d+\s*$")
    try:
        for ln in open(log_path, errors="replace"):
            m = pat.match(ln)
            if m and int(m.group(3)) > 0:
                try:
                    t = time.mktime(time.strptime(m.group(1), "%Y-%m-%d %H:%M:%S"))
                except ValueError:
                    continue
                if time.time() - t <= 48 * 3600:
                    acc[m.group(2)] = acc.get(m.group(2), 0) + 1
    except OSError:
        pass
    rows.sort(key=lambda r: (acc.get(r[0], 0), -float(r[1])))   # stable: ties keep the longest-starving order
if rows:
    sys.stderr.write("candidate order (%s): %s\n" % (mode, " ".join("%s[accepted48h=%d starving=%sh]" % (r[0], acc.get(r[0], 0), r[1]) for r in rows)))
for r in rows:
    print(r[0])
PY
)"; [ -s "$WORK/order.err" ] && log "$(cat "$WORK/order.err")"; fi
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
  scp -q "$SRV:$REMOTE/backlog/$repo.md" "$in/backlog.md" 2>/dev/null || true   # open backlog feature groups feed the prompt's do-not-repeat list
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
  # 2026-10-09: the supply (ovn_work_supply.py) now turns mechanical gaps into finished items, and the validator rejects them here ('mechanical-gap: handled
  # by supply'). Tell the agent up front so the pass is spent on design-level / bug-hunting work, and list the features that are already OPEN so it does not
  # re-propose them (7 of 8 recent passes had 'near-duplicate of an existing roadmap item' rejects). OVN_AR_DESIGN_ONLY=off restores the old prompt.
  scope_rules=""
  if [ "${OVN_AR_DESIGN_ONLY:-on}" != "off" ]; then
    open_titles="$(python3 "$VALIDATE" --open-titles "$in/roadmap.md" "$in/backlog.md" 2>/dev/null)"
    scope_rules="SCOPE: DESIGN-LEVEL and BUG-HUNTING research ONLY. NEVER propose mechanical gaps: docstrings, comments, unused imports, missing return/type annotations, or deleting dead stubs/helpers without a callers analysis (Grep proof that nothing calls them). A deterministic supply already generates those as finished items and the validator auto-rejects them ('mechanical-gap: handled by supply'), so they only waste this pass. 'Missing tests' (priority 3) applies ONLY to important modules with real logic, never to small side-effect-free helpers (the supply writes those tests). Spend the pass on what only reading and judgement can find: live bugs and silent failures, security/legal/reliability gaps, broken user-visible flows, missing behaviour that fits the repo's wedge.
DO NOT REPEAT - these features are already OPEN (roadmap [ready]/needs-research, or backlog items still waiting to be worked):
${open_titles:-(none)}"
  fi
  prompt="You are refueling ONE repo's feature roadmap for an autonomous overnight coding fleet (a local 27B model implements items one at a time, each gated by the repo's tests). REPO: $repo. A READ-ONLY checkout of the CURRENT code the fleet works on is $src (read ONLY this checkout - any other clone of the repo can be stale; you have no write or edit tools at all).
Read: $in/roadmap.md (current roadmap: note the stated maturity/stopping point and everything already decomposed/done - do NOT duplicate), $in/README.md (line format), $in/recent.txt (recent commits + queue tail). Then read the real repo (README, docs, file tree, the code you propose to touch).
Produce up to 10 NEW features worth building, grounded in actual code. Priority: (1) real live bugs/silent failures with file evidence, (2) security/legal/store/reliability gaps, (3) missing tests for important untested modules, (4) features fitting the repo's wedge. HONESTY: if the repo is genuinely at its 'complete - maintain only' line, return FEWER items, even zero; never invent filler. Every item must cite files that exist (verify with Read/Grep in the checkout). Art generation is human-gated: propose no art items.
QUALITY RULES (a 2026-10-04 audit of the fleet's landings found 19 dead helpers nothing calls, ghost tests that never run, and add/remove loops): (a) NEVER propose adding a new standalone helper/predicate/constant/formatter function, or a test for one, unless the SAME item also changes an existing production caller to use it - name that caller as file:line and verify it exists; a function nothing calls is rejected. (b) NEVER propose deleting a file or function without Grep-verifying in the checkout that it still exists and has no non-test callers; never re-propose anything the roadmap already marks done [x] or decomposed. (c) Tests must live where the repo's own test command collects them (iptv_apps: iptv-backend/tests/ ONLY, never next to modules under app/; xlite: res://tests/ ONLY, never res://test/). (d) Prefer items that change user-visible behaviour or fix a real bug; at most 2 test-only items per pass, and only for important modules with real logic and no existing test. (e) One item = one behavioural change with a concrete verifiable outcome; no refactor/cleanup/rename items unless you demonstrate a defect they fix.
${scope_rules:+$scope_rules
}Your FINAL reply must contain ONLY the feature lines (no preamble, no commentary, no code fences), one per line, exactly:
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
