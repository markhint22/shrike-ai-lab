#!/usr/bin/env bash
# ovn_test_watch.sh — periodic FULL-SUITE health watchdog (server cron, lock-aware).
#
# The per-cycle gate only runs tests RELATED to the files a commit touched, so a pre-existing or
# flaky failure in untouched code can sit red for days without the fleet noticing. This watchdog
# runs each repo's WHOLE suite on the latest overnight/feature, and when a suite is red it files an
# [EMERGENCY] triage-and-fix item at the TOP of that repo's Next Steps (worked first next cycle) and
# alerts. It reuses the fleet's already-provisioned .venv/node_modules (no re-provision) and
# serializes on run.lock so it never interrupts a cycle and never races the checkout.
#
# Cron (server):  17 */6 * * *  cd ~/overnight-queue && ./ovn_test_watch.sh >> logs/ovn_test_watch.log 2>&1
set -uo pipefail
cd "$HOME/overnight-queue" || exit 1
export PATH="$HOME/aider-venv/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
TOPIC="${NTFY_TOPIC:-shrike_ovn_311380987a}"
REPOS="${*:-billwatch gitlark iptv_apps test-automation-agent xlite shrike-notify shrike-monitor shrike-labs-website}"
GODOT="$HOME/godot/godot4"
log(){ echo "$(date '+%F %T') $*"; }

# ---- serialize on the cycle lock: WAIT for a running cycle, never interrupt it ----
exec 200>state/run.lock
if ! flock -w 1200 200; then log "could not acquire run.lock in 20min — skipping this health pass"; exit 0; fi
log "=== test-health sweep start ==="

emergency_enqueue(){ # $1=repo $2=area $3=failing-detail
  local repo="$1" area="$2" detail="$3"
  local pf="repos/$repo/OVERNIGHT_PROGRESS.md"
  [ -f "$pf" ] || return 0
  local item="- [ ] [EMERGENCY][T2] ${area} suite is RED — TRIAGE then FIX: decide whether the CODE is wrong (fix the code) or the TEST is stale/flaky (fix or update the test), then get the whole suite green. Failing: ${detail}"
  # already filed an open emergency for this area? don't pile duplicates.
  if grep -qF "[EMERGENCY][T2] ${area} suite is RED" "$pf"; then log "$repo/$area: emergency already queued — skip"; return 0; fi
  # insert right after the "## Next Steps" header so it's the top item worked next cycle
  python3 - "$pf" "$item" <<'PY'
import sys
pf, item = sys.argv[1], sys.argv[2]
lines = open(pf, encoding="utf-8").read().splitlines(keepends=True)
out, inserted = [], False
for ln in lines:
    out.append(ln)
    if not inserted and ln.strip().lower().startswith("## next steps"):
        out.append(item + "\n")
        inserted = True
if not inserted:  # no Next Steps header — prepend a section
    out = ["## Next Steps\n", item + "\n", "\n"] + out
open(pf, "w", encoding="utf-8").write("".join(out))
PY
  ( cd "repos/$repo"
    git add OVERNIGHT_PROGRESS.md
    git -c user.email=fleet@shrike.local -c user.name=shrike-fleet commit -q -m "fix(queue): [EMERGENCY] ${area} suite red — triage+fix queued by test-watch"
    git push -q origin overnight/feature || { git pull -q --rebase origin overnight/feature && git push -q origin overnight/feature; }
  ) && log "$repo/$area: EMERGENCY fix item queued + pushed"
  curl -fsS --max-time 8 -H "Title: ${repo} ${area} tests are red" -H "Tags: rotating_light" \
    -d "The full-suite watchdog found ${area} failing in ${repo}. An [EMERGENCY] triage+fix item was queued at the top of its Next Steps — the fleet will work it first next cycle. Failing: ${detail:0:300}" \
    "https://ntfy.sh/$TOPIC" >/dev/null 2>&1 || true
}

for r in $REPOS; do
  rd="repos/$r"; [ -d "$rd" ] || { log "$r: no clone — skip"; continue; }
  # get the latest overnight/feature cleanly (fleet is paused under our lock)
  if ! ( cd "$rd" && git fetch -q origin overnight/feature && git checkout -q overnight/feature 2>/dev/null && git reset -q --hard origin/overnight/feature ); then
    log "$r: git sync failed — skip"; continue
  fi
  log "$r: running full suite on overnight/feature"

  # ---- PYTHON: every provisioned .venv/bin/pytest, full suite ----
  while IFS= read -r -d '' vp; do
    d="${vp%/.venv/bin/pytest}"
    out="$( cd "$d" && timeout 360 ./.venv/bin/pytest -q --no-cov 2>&1 | tail -25 )"
    if printf '%s' "$out" | grep -qE '[0-9]+ (failed|error)'; then
      fails="$(printf '%s' "$out" | grep -E 'FAILED|ERROR ' | head -5 | sed 's/  */ /g' | paste -sd'; ' -)"
      [ -z "$fails" ] && fails="$(printf '%s' "$out" | grep -E '[0-9]+ (failed|error)' | tail -1)"
      log "$r: pytest RED in ${d##*/} — $fails"
      emergency_enqueue "$r" "$(basename "$d") pytest" "${fails:-see log}"
    else
      log "$r: pytest green in ${d##*/} ($(printf '%s' "$out" | grep -oE '[0-9]+ passed' | tail -1))"
    fi
  done < <(find "$rd" -maxdepth 4 -type f -path "*/.venv/bin/pytest" -print0 2>/dev/null)

  # ---- WEB: vitest full run + build, per web package ----
  while IFS= read -r -d '' pj; do
    wd="$(dirname "$pj")"
    grep -q '"vitest"' "$pj" 2>/dev/null || continue
    [ -d "$wd/node_modules/vitest" ] || { log "$r: ${wd##*/} not provisioned (no node_modules) — skip web"; continue; }
    out="$( cd "$wd" && CI=true timeout 240 npx vitest run 2>&1 | tail -25 )"
    if printf '%s' "$out" | grep -qE '[0-9]+ failed|✖|FAIL '; then
      fails="$(printf '%s' "$out" | grep -E 'FAIL |✖' | head -5 | paste -sd'; ' -)"
      log "$r: vitest RED in ${wd##*/}"
      emergency_enqueue "$r" "$(basename "$wd") vitest" "${fails:-see log}"
    else
      log "$r: vitest green in ${wd##*/} ($(printf '%s' "$out" | grep -oE '[0-9]+ passed' | tail -1))"
    fi
  done < <(find "$rd" -maxdepth 3 -type f -name package.json -not -path '*/node_modules/*' -print0 2>/dev/null)

  # ---- GODOT (xlite): GUT full suite ----
  if [ -x "$GODOT" ]; then
    while IFS= read -r -d '' gp; do
      gd="$(dirname "$gp")"
      [ -d "$gd/addons/gut" ] || continue
      ( cd "$gd" && timeout 90 "$GODOT" --headless --path . --import >/dev/null 2>&1 )
      out="$( cd "$gd" && timeout 60 "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit 2>&1 | tail -30 )"
      if printf '%s' "$out" | grep -qE 'Failing|[1-9][0-9]* failing|Errors|SCRIPT ERROR'; then
        fails="$(printf '%s' "$out" | grep -iE 'failing|error' | head -5 | paste -sd'; ' -)"
        log "$r: GUT RED — $fails"
        emergency_enqueue "$r" "godot GUT" "${fails:-see log}"
      else
        log "$r: GUT green ($(printf '%s' "$out" | grep -oiE '[0-9]+ passed' | tail -1))"
      fi
    done < <(find "$rd" -maxdepth 3 -type f -name project.godot -print0 2>/dev/null)
  fi
done

log "=== test-health sweep complete ==="
