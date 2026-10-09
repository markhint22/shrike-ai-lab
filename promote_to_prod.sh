#!/usr/bin/env bash
# Gated promotion of develop (staging) -> main (prod). This is the ONLY path to
# production now that branch_hygiene merges the fleet's work into develop, not main.
#
# For each repo it:
#   1. fetches, shows what would ship (develop..main commit + file diff)
#   2. runs the staging smoke test IF a staging URL is configured for that repo
#      (state/staging_url_<repo> = "<backend_url> [frontend_origin]") — a red smoke
#      test blocks the promote unless --force
#   3. requires typed confirmation (skip with --yes for a scheduled daily promote)
#   4. merges develop -> main --no-ff, pushes (triggers the Railway/Vercel PROD deploy),
#      and tags prod-YYYYMMDD-HHMM-<repo> for one-command rollback
#
# 2026-10-02 (qa/h4-promotegate): two additions, both default to today's behaviour.
#   * staging-evidence gate: before a repo is promoted, qa/promote_gate.py re-runs the release-candidate plan and
#     staging_check (file provider = the Mac's 10-minutely snapshot) and prints a "[candidate]" and a "[staging-gate]"
#     line. ONLY when the staging_check gate mode is `enforce` (env OVN_QA_STAGING_CHECK=enforce, or
#     state/qa_gate_modes.json) AND the verdict is FAIL (staging behind / diverged / latest deploy failed) is THIS repo
#     skipped (log line + one WARN in state/alerts.log); other repos are unaffected. UNVERIFIED / NA / stale snapshot /
#     missing evidence / helper crash NEVER block. Rollback: unset the mode (shadow = log only). --force overrides.
#   * release-branch flow, kill switch OVN_RELEASE_FLOW=on (default OFF = byte-identical to before): instead of
#     merging develop -> main, main is FAST-FORWARDED to the release candidate SHA (newest green hygiene merge, which
#     may be older than develop's tip), a release/YYYYMMDD branch is created at that SHA, and prod-<ts>-<repo> is
#     tagged as today. No merge commit, never a force push (git itself refuses a non-fast-forward = "main moved").
#     Design + rationale: qa/patches/daily_promote_release_flow.md.
#
# 2026-10-03 (qa/h11-promote-alerting, A3): the staging-evidence gate now ENFORCES by default (promote_gate.py DEFAULT_MODE) for repos that have a
#   staging backend. Blocks THIS repo (others unaffected, see feedback_daily-promote-no-skip-all) on staging FAIL (BEHIND / DIVERGED / latest deploy
#   FAILED) and fails CLOSED on a stale/missing exported staging_deploys file. NA (no staging backend) and other UNVERIFIED still proceed, but print
#   "[unverified]" and daily_promote.sh lists them. Rollback: `qa/qa_enforce.sh staging_check shadow` or OVN_PROMOTE_STAGING_GATE=shadow.
#   The staging smoke also gets the candidate SHA (STAGING_EXPECT_SHA) to check PROVENANCE; after the push the promoted SHA is logged
#   ("[prod-deploy]") and qa/promote_postcheck.py is started DETACHED to watch the prod deploy (emergency push on FAILED). Kill switch OVN_POSTCHECK=off.
#
# Usage:
#   promote_to_prod.sh repos/billwatch                 # interactive, smoke-gated
#   promote_to_prod.sh --yes repos/billwatch           # non-interactive (cron)
#   promote_to_prod.sh --force repos/billwatch         # promote even if smoke fails
#   promote_to_prod.sh --dry-run repos/billwatch       # show only
set -uo pipefail
DIR="$HOME/overnight-queue"; STATE="$DIR/state"; SMOKE="$DIR/staging_smoke.sh"
YES=0; FORCE=0; DRY=0; NOW="$(date +%Y%m%d-%H%M)"
args=()
for a in "$@"; do case "$a" in
  --yes) YES=1;; --force) FORCE=1;; --dry-run) DRY=1;; *) args+=("$a");; esac; done
[ "${#args[@]}" -gt 0 ] || { echo "usage: promote_to_prod.sh [--yes|--force|--dry-run] repos/<name> ..."; exit 2; }

# post_promote <name> <promoted-sha>: log the prod deploy SHA, then start the prod-deploy watcher DETACHED (all fds redirected so a cron/daily_promote
# command substitution can never wait on it; bounded by OVN_POSTCHECK_TIMEOUT inside the helper). OVN_POSTCHECK_SYNC=1 runs it in the foreground (tests).
post_promote(){
  local pname="$1" psha="$2"
  echo "  [prod-deploy] $pname promoted SHA ${psha:-?} (main tip; the Railway PROD deploy builds exactly this commit)"
  [ -n "$psha" ] && [ "${OVN_POSTCHECK:-on}" != "off" ] && [ -f "$DIR/qa/promote_postcheck.py" ] || return 0
  # only repos with a Railway PROD export can be watched (billwatch gitlark iptv_apps); others would log a permanent "UNVERIFIED" WARN 30 min later
  case " ${OVN_PROD_DEPLOY_REPOS:-billwatch gitlark iptv_apps} " in *" $pname "*) ;; *)
    [ -f "$STATE/prod_deploys/$pname.json" ] || { echo "  [prod-deploy] no prod deploy source for $pname (no Railway prod export): post-promote check skipped"; return 0; };; esac
  local py; py="$(command -v python3.12 || command -v python3)"; [ -n "$py" ] || return 0
  mkdir -p "$DIR/logs" 2>/dev/null
  if [ "${OVN_POSTCHECK_SYNC:-0}" = "1" ]; then
    OVN_DIR="$DIR" "$py" "$DIR/qa/promote_postcheck.py" watch --repo "$pname" --sha "$psha" >> "$DIR/logs/promote_postcheck.out" 2>&1 < /dev/null
  else
    OVN_DIR="$DIR" nohup "$py" "$DIR/qa/promote_postcheck.py" watch --repo "$pname" --sha "$psha" >> "$DIR/logs/promote_postcheck.out" 2>&1 < /dev/null &
    disown 2>/dev/null || true
  fi
  echo "  [prod-deploy] post-promote check started (detached): result in logs/promote_postcheck.log, FAILED => emergency push + alerts.log"
}

for repo in "${args[@]}"; do
  name="$(basename "$repo")"
  [ -d "$repo/.git" ] || { echo "SKIP $name (no checkout)"; continue; }
  timeout 30 git -C "$repo" fetch -q origin 2>/dev/null  # 2026-09-15: timeout so a stalled fetch can't hang this repo's promote
  DEF="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"; DEF="${DEF:-main}"
  if ! git -C "$repo" rev-parse --verify -q origin/develop >/dev/null; then echo "SKIP $name (no develop)"; continue; fi
  ahead="$(git -C "$repo" rev-list --count origin/$DEF..origin/develop 2>/dev/null || echo 0)"
  echo "=================================================================="
  echo "$name: develop is +$ahead ahead of $DEF"
  [ "${ahead:-0}" -eq 0 ] && { echo "  nothing to promote."; continue; }
  # 2026-10-09: develop "+1" that is only a tree-identical reconcile/sync commit used to create an empty "release: promote" merge + a prod deploy every day. OVN_PROMOTE_SKIP_IDENTICAL=0 = old behaviour; --force still promotes.
  [ "${OVN_PROMOTE_SKIP_IDENTICAL:-1}" != "0" ] && [ "$FORCE" -ne 1 ] && git -C "$repo" diff --quiet "origin/$DEF" origin/develop 2>/dev/null && { echo "  nothing to promote (tree identical)."; continue; }
  git -C "$repo" log --oneline "origin/$DEF..origin/develop" | sed 's/^/    /' | head -20
  echo "  files:"; git -C "$repo" diff --stat "origin/$DEF..origin/develop" | tail -12 | sed 's/^/    /'

  # 2026-10-02: candidate + staging-evidence gate (see header). Bounded (qa_timeout), never fatal: no output => no evidence => never blocks.
  gate_blk=0; gate_cand=""; gate_rbranch=""; gate_cverdict=""; gate_unv=0; gate_reason=""; gate_alem=""
  if [ -f "$DIR/qa/promote_gate.py" ]; then
    gj="$(PATH="$HOME/qa-venv/bin:$HOME/qa-tools/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
      PY="$(command -v python3.12 || command -v python3)"
      OVN_DIR="$DIR" OVN_REPOS_DIR="$(cd "$(dirname "$repo")" && pwd)" "$PY" "$DIR/qa/qa_timeout.py" "${OVN_PROMOTE_GATE_TIMEOUT:-90}" \
        "$PY" "$DIR/qa/promote_gate.py" check --repo "$name" --main "origin/$DEF" 2>/dev/null | tail -1)"
    gf="$(printf '%s' "$gj" | PATH="/usr/local/bin:/usr/bin:/bin:$HOME/qa-venv/bin:$PATH" python3 -c 'import sys,json
j=json.loads(sys.stdin.read())
print("blk=%d" % (1 if j.get("block") is True else 0))
print("cand=%s" % j.get("candidate", ""))
print("rbranch=%s" % j.get("release_branch", ""))
print("cverdict=%s" % j.get("candidate_verdict", ""))
print("unv=%d" % (1 if j.get("unverified") is True else 0))
print("reason=%s" % str(j.get("reason", "")).replace("\n", " "))
print("alem=%s" % (str(j.get("alembic_verdict", "")) + "|" + str(j.get("alembic_summary", "")).replace("\n", " ")))
for l in j.get("log_lines", []): print("LOG" + l)' 2>/dev/null)"
    while IFS= read -r l; do case "$l" in
      blk=1) gate_blk=1;; cand=*) gate_cand="${l#cand=}";; rbranch=*) gate_rbranch="${l#rbranch=}";;
      cverdict=*) gate_cverdict="${l#cverdict=}";; unv=1) gate_unv=1;; reason=*) gate_reason="${l#reason=}";; alem=*) gate_alem="${l#alem=}";; LOG*) echo "${l#LOG}";; esac; done <<< "$gf"
    if [ "$gate_blk" -eq 1 ]; then
      if [ "$FORCE" -eq 1 ]; then echo "  ⚠️  STAGING-GATE would block $name but --force given - promoting anyway"
      else
        echo "  🔴 STAGING-GATE BLOCK: staging is not serving the candidate, its latest deploy failed, or the staging evidence is stale/missing (${gate_reason:-no reason}) — NOT promoting $name (use --force to override)"
        # transient reasons (staging deploy of the candidate still BUILDING / staging BEHIND = not deployed yet) are retried once by daily_promote.sh:
        # it sets OVN_PROMOTE_DEFER_NOTE=1 on its first pass so a hold that clears 10 minutes later never writes an alerts.log WARN or a relay note.
        case "$gate_reason" in BUILDING|FAIL:MISMATCH_BEHIND) echo "  [transient-hold] $name: ${gate_reason} (staging should catch up shortly; daily_promote.sh retries once)";; esac
        _defer=0; case "$gate_reason" in BUILDING|FAIL:MISMATCH_BEHIND) [ "${OVN_PROMOTE_DEFER_NOTE:-0}" = "1" ] && _defer=1;; esac
        if [ "$DRY" -eq 1 ]; then echo "  [dry-run] would write the alerts.log WARN + once-per-candidate relay note for the hold (skipped)"
        elif [ "$_defer" -eq 0 ]; then
        mkdir -p "$STATE" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN | promote-staging-gate | $name promote SKIPPED: staging_check ${gate_reason:-FAIL} for candidate ${gate_cand:0:10} (enforce); other repos unaffected" >> "$STATE/alerts.log"
        # one relay note per (repo, candidate): class "note" (buffered into the hourly update, never a push of its own - the deploy FAILED emergency comes from deploy_watch.sh)
        _hm="$STATE/promote_held/${name}_${gate_cand:0:10}"
        if [ ! -e "$_hm" ]; then mkdir -p "$STATE/promote_held" 2>/dev/null; : > "$_hm" 2>/dev/null
          curl -fsS --max-time 8 -H "Title: Promote HELD: $name" -H "Tags: no_entry" -H "Priority: default" \
            -d "$name stayed on its last-good prod build: staging gate ${gate_reason:-FAIL} for candidate ${gate_cand:0:10}. Other repos promoted independently." \
            "${NTFY_SERVER:-https://ntfy.sh}/${NTFY_TOPIC:-shrike_ovn_311380987a}" >/dev/null 2>&1 || true
        fi
        fi
        continue
      fi
    fi
  fi
  # 2026-10-03: proceeding without staging evidence is allowed (NA / building / unknown commit) but never silent: daily_promote.sh lists it.
  [ "$gate_unv" -eq 1 ] && [ "$gate_blk" -eq 0 ] && echo "  [unverified] staging gate could not verify $name: ${gate_reason:-no evidence} - promoting WITHOUT staging provenance"
  # prod alembic ancestry (SHADOW): ONE alerts.log WARN per (repo, candidate) on FAIL, never blocks
  case "$gate_alem" in FAIL\|*)
    _am="$STATE/promote_held/alembic_${name}_${gate_cand:0:10}"
    if [ "$DRY" -ne 1 ] && [ ! -e "$_am" ]; then mkdir -p "$STATE/promote_held" 2>/dev/null; : > "$_am" 2>/dev/null
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN | promote-prod-alembic | $name candidate ${gate_cand:0:10}: ${gate_alem#FAIL|} (shadow, not blocking)" >> "$STATE/alerts.log"; fi;; esac
  RELEASE_FLOW=0; [ "${OVN_RELEASE_FLOW:-off}" = "on" ] && RELEASE_FLOW=1

  # staging smoke gate
  surl="$STATE/staging_url_${name}"
  if [ -f "$surl" ]; then
    echo "  -- staging smoke ($(cat "$surl")) --"
    # provenance: the candidate SHA (and clone) let the smoke refuse a healthy-but-STALE staging deploy when /health exposes a commit
    if STAGING_EXPECT_SHA="$gate_cand" STAGING_REPO_DIR="$repo" bash "$SMOKE" $(cat "$surl"); then smoke_ok=1; else smoke_ok=0; fi
    if [ "$smoke_ok" -ne 1 ] && [ "$FORCE" -ne 1 ]; then echo "  🔴 smoke failed — NOT promoting $name (use --force to override)"; continue; fi
  else
    echo "  ⚠️  no staging URL configured (state/staging_url_${name}) — smoke test SKIPPED."
    [ "$YES" -ne 1 ] && [ "$FORCE" -ne 1 ] && echo "     (promoting without a staging check — configure staging to make this safe)"
  fi

  # migration safety gate before prod (2026-09-03)
  if [ -f "$DIR/scripts/check_migrations.py" ] && ! python3 "$DIR/scripts/check_migrations.py" "$repo" >/dev/null 2>&1; then
    echo "  🔴 migration safety FAILED — NOT promoting $name"; python3 "$DIR/scripts/check_migrations.py" "$repo" 2>&1 | grep "✗" | head -3 | sed "s/^/    /"; continue
  fi
  if [ "$DRY" -eq 1 ]; then
    if [ "$RELEASE_FLOW" -eq 1 ]; then echo "  [dry-run] release flow ON: would fast-forward $DEF to candidate ${gate_cand:0:10} via ${gate_rbranch:-?}, push (PROD deploy), tag prod-$NOW-$name"
    else echo "  [dry-run] would merge develop -> $DEF, push (PROD deploy), tag prod-$NOW-$name"; fi
    continue
  fi

  if [ "$YES" -ne 1 ]; then
    printf "  Type 'ship %s' to promote to PROD: " "$name"; read -r ans
    [ "$ans" = "ship $name" ] || { echo "  aborted."; continue; }
  fi

  # 2026-10-02: release-branch flow (OVN_RELEASE_FLOW=on). Fast-forward main to the release candidate; never merge, never force.
  if [ "$RELEASE_FLOW" -eq 1 ]; then
    case "$gate_cverdict" in
      PASS|FLAG) ;;
      *) echo "  🔴 release flow: candidate verdict '${gate_cverdict:-none}' (need PASS/FLAG) — NOT promoting $name"; continue;;
    esac
    if [ -z "$gate_cand" ] || [ -z "$gate_rbranch" ]; then echo "  🔴 release flow: no candidate/branch from the plan — NOT promoting $name"; continue; fi
    if ! git -C "$repo" merge-base --is-ancestor "origin/$DEF" "$gate_cand" 2>/dev/null; then
      echo "  🔴 release flow: $DEF is not an ancestor of candidate ${gate_cand:0:10} (a hotfix landed on $DEF?) — NOT promoting $name; reconcile back-merge + next run re-cuts"; continue
    fi
    # the release branch is the audit trail of exactly what shipped; pushed first, non-forced (an existing name at another SHA is refused by git)
    if ! timeout 30 git -C "$repo" push -q origin "$gate_cand:refs/heads/$gate_rbranch" 2>/dev/null; then
      echo "  🔴 release flow: could not create $gate_rbranch at ${gate_cand:0:10} — NOT promoting $name"; continue
    fi
    git -C "$repo" tag "prod-$NOW-$name" "$gate_cand" 2>/dev/null || true
    if timeout 30 git -C "$repo" push -q origin "$gate_cand:refs/heads/$DEF" && timeout 30 git -C "$repo" push -q origin "prod-$NOW-$name" 2>/dev/null; then
      echo "  ✅ PROMOTED $name develop -> $DEF (+$ahead, fast-forward to release candidate ${gate_cand:0:10} via $gate_rbranch). Prod deploy triggered. Rollback: git checkout prod-$NOW-$name"
      post_promote "$name" "$gate_cand"
    else echo "  ⚠️ push failed ($DEF moved? git refused the non-fast-forward; next run re-cuts)"; fi
    continue
  fi

  wt="$(mktemp -d "/tmp/promote-${name}.XXXX")"
  if ! git -C "$repo" worktree add -q "$wt" "origin/$DEF" 2>/dev/null; then echo "  worktree failed"; continue; fi
  # 2026-09-16 CRITICAL FIX: checkout -B silently fails (detached HEAD) whenever $DEF is
  # already checked out elsewhere sharing this repo's refs; the ambiguous `push origin "$DEF"`
  # below would then resolve to whatever OTHER ref by that name exists (ignoring this
  # worktree's own merged HEAD) - same bug found and fixed in reconcile_branches.sh and
  # branch_hygiene.sh. Main clones here are conventionally on overnight/feature (not
  # $DEF=main), so this has likely been safe in practice, but push HEAD:"$DEF" explicitly
  # for the same defense-in-depth (this script pushes straight to PRODUCTION).
  git -C "$wt" checkout -qB "$DEF" "origin/$DEF"
  if git -C "$wt" merge --no-ff --no-edit -m "release: promote develop -> $DEF ($NOW)" origin/develop >/dev/null 2>&1; then
    git -C "$wt" tag "prod-$NOW-$name" 2>/dev/null || true
    if timeout 30 git -C "$wt" push -q origin "HEAD:$DEF" && timeout 30 git -C "$wt" push -q origin "prod-$NOW-$name" 2>/dev/null; then
      echo "  ✅ PROMOTED $name develop -> $DEF (+$ahead). Prod deploy triggered. Rollback: git checkout prod-$NOW-$name"
      post_promote "$name" "$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
    else echo "  ⚠️ push failed"; fi
  else
    git -C "$wt" merge --abort >/dev/null 2>&1; echo "  🔴 merge conflict develop vs $DEF — resolve manually"
  fi
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
done

# dead-man's-switch ping once the loop finished (no-op unless a heartbeat URL is configured)
[ "$DRY" = "1" ] || { [ -f "$DIR/shrike_notify_lib.sh" ] && . "$DIR/shrike_notify_lib.sh" && shrike_monitor_heartbeat PROMOTE; }
