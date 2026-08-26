#!/usr/bin/env bash
#
# branch_hygiene.sh — daily branch reconciliation for the overnight fleet.
#
# WHY THIS EXISTS
#   The overnight runner commits agent work to a persistent `overnight/feature`
#   branch per repo and (by original design) "never touches main — you review and
#   merge yourself". That manual step lapsed, so `overnight/feature` silently
#   drifted 40-90 commits ahead of `main` in several repos = orphaned work.
#
#   This script makes that reconciliation automatic and daily, so work either
#   LANDS on main (when it passes the gate) or is LOUDLY FLAGGED for review —
#   it can never again silently accumulate.
#
# WHAT IT DOES, per managed repo:
#   1. git fetch --prune  (drop local refs whose remote is gone)
#   2. delete branches already merged into main   (local + remote)
#   3. delete stale dated overnight/YYYY-MM-DD/* branches older than KEEP_DAYS
#   4. reconcile overnight/feature -> main behind a build+test GATE:
#         green -> merge --no-ff into main, push (auto-deploy),
#                  then fast-forward overnight/feature to main (kept in sync)
#         red   -> DO NOT merge; drop a NEEDS-REVIEW flag file + report line
#   5. append a one-line-per-repo summary to $REPORT_FILE (if set)
#
# SAFETY
#   - Never force-pushes. Never deletes main, overnight/feature, or dependabot/*.
#   - All merges are conflict-checked first; a conflicted merge is aborted + flagged.
#   - Per-repo opt-out: set auto_merge=false for a repo to FLAG-ONLY (prune still runs).
#   - Idempotent: safe to run repeatedly.
#
# USAGE
#   branch_hygiene.sh --from-config          # repos from recurring_tasks.json
#   branch_hygiene.sh /path/to/repo ...      # explicit repo paths
#   KEEP_DAYS=3 AUTO_MERGE_DEFAULT=true branch_hygiene.sh --from-config
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_DAYS="${KEEP_DAYS:-3}"                       # keep dated overnight/* this many days
AUTO_MERGE_DEFAULT="${AUTO_MERGE_DEFAULT:-true}"  # gated auto-merge on green tests
TEST_TIMEOUT="${TEST_TIMEOUT:-900}"               # seconds for the test/build gate
STATE_DIR="${STATE_DIR:-$SCRIPT_DIR/state}"
REPORT_FILE="${REPORT_FILE:-}"                    # optional markdown report to append to
DRY_RUN="${DRY_RUN:-0}"                           # 1 = log mutations instead of running them
NOW_EPOCH="$(date +%s)"

# Per-repo auto-merge opt-out (basename). Set to "false" to flag-only (no merge to main).
# 2026-08-25: per explicit user decision, billwatch + shrike-labs-website are now
# treated EXACTLY like the other repos — green (gated) work auto-merges to main,
# which for these two means an autonomous PRODUCTION deploy. The build+test gate
# is the only guard (nothing merges unless tests ran green). Re-add an entry here
# as [name]=false to restore human-approved deploys for any repo.
declare -A AUTO_MERGE_OVERRIDE=(
  # 2026-08-25: temporarily flag-only again for the two LIVE PRODUCTION sites
  # during the Qwen3-Coder trial. The coder is 20x faster but showed rough edges
  # (syntax errors -> tests:FAIL) on night 1, so don't let it auto-deploy to prod
  # until it proves reliable. Re-empty this to restore full auto-merge.
  [billwatch]=false
  [shrike-labs-website]=false
)

log()  { echo "[branch-hygiene $(date '+%H:%M:%S')] $*"; }
report(){ [ -n "$REPORT_FILE" ] && echo "$*" >> "$REPORT_FILE" || true; }

# --- resolve repo list -------------------------------------------------------
#   --repos-dir <dir>  : every git repo directly under <dir>   (server layout)
#   --from-config      : persistent_branch repos in recurring_tasks.json
#   <path> [<path>...] : explicit repo paths
REPOS=()
if [ "${1:-}" = "--repos-dir" ]; then
  base="${2:-}"
  if [ -d "$base" ]; then
    for d in "$base"/*/; do [ -d "$d/.git" ] && REPOS+=("${d%/}"); done
  fi
elif [ "${1:-}" = "--from-config" ]; then
  CFG="$SCRIPT_DIR/recurring_tasks.json"
  if [ -f "$CFG" ]; then
    while IFS= read -r r; do [ -n "$r" ] && [ "$r" != "null" ] && REPOS+=("$r"); done \
      < <(jq -r '.[]? | select((.persistent_branch // false) == true) | .repo' "$CFG" 2>/dev/null | sort -u)
  fi
else
  for a in "$@"; do REPOS+=("$a"); done
fi
if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "no repos to process (use --repos-dir <dir>, --from-config, or pass paths)"; exit 0
fi

# --- gate: build + test the feature worktree; 0=pass, 1=fail, 2=nothing-to-run ---
# $1 = main clone (source of the PROVISIONED, gitignored .venv/node_modules/GUT
#      that a fresh worktree lacks); $2 = worktree (feature code to gate).
# FIX 2026-08-25: a fresh worktree has no .venv, so the old check
# `command -v pytest` tested the GLOBAL interpreter (no pytest) and every python
# repo returned "nothing to run" -> flagged forever, and Godot wasn't handled at
# all. Now we reuse the main clone's provisioned venv against the worktree code
# (verified live: main-clone pytest collects+runs the worktree's tests), and add
# a GUT gate for Godot repos.
run_gate() {
  local repo="$1" dir="$2" ran=0 rc=0
  # web build+test (self-provisions via npm ci in the worktree). 2026-08-25 #6:
  # scan root AND one-level subdirs (web/, billwatch-web/, ...) - the frontend
  # is rarely at the repo root, so the old root-only check silently gated nothing
  # for most repos' web app.
  while IFS= read -r pj; do
    [ -z "$pj" ] && continue
    pdir="$(dirname "$pj")"
    if jq -e '.scripts.build' "$pj" >/dev/null 2>&1; then
      log "  gate: npm build in $pdir"
      ( cd "$pdir" && timeout "$TEST_TIMEOUT" bash -c 'npm ci --no-audit --no-fund 2>/dev/null || npm install --no-audit --no-fund; npm run build' ) >/dev/null 2>&1 || return 1
      ran=1
    fi
    if jq -e '.scripts.test' "$pj" >/dev/null 2>&1; then
      log "  gate: npm test in $pdir"
      ( cd "$pdir" && CI=1 timeout "$TEST_TIMEOUT" npm test --silent -- --run 2>/dev/null ) ; rc=$?
      [ "$rc" -gt 1 ] && return 1
      ran=1
    fi
  done < <(find "$dir" -maxdepth 2 -name package.json -not -path '*/node_modules/*' 2>/dev/null)
  # python: reuse the main clone's PROVISIONED venv against the worktree code.
  local venv_pytest pkg_rel wt_pkg
  venv_pytest="$(find "$repo" -maxdepth 4 -type f -path '*/.venv/bin/pytest' 2>/dev/null | head -1)"
  if [ -n "$venv_pytest" ]; then
    pkg_rel="${venv_pytest%/.venv/bin/pytest}"; pkg_rel="${pkg_rel#"$repo"}"; pkg_rel="${pkg_rel#/}"
    wt_pkg="$dir${pkg_rel:+/$pkg_rel}"
    if [ -d "$wt_pkg" ]; then
      log "  gate: pytest (reusing provisioned venv) in $wt_pkg"
      ( cd "$wt_pkg" && timeout "$TEST_TIMEOUT" "$venv_pytest" -q --no-cov 2>/dev/null ) || return 1
      ran=1
    fi
  fi
  # godot / GUT (e.g. xlite): reuse installed headless Godot + the repo's own
  # vendored addons/gut. Exit code is untrustworthy - gate on the JUnit XML
  # failures count + no-asserts + a parse-error scan of --import output (same
  # rules as the queue's run_repo_verification Godot branch).
  if [ -f "$dir/project.godot" ] && [ -x "$HOME/godot/godot4" ]; then
    local gout xml; gout="$(mktemp)"
    ( cd "$dir" && timeout 120 "$HOME/godot/godot4" --headless --path . --import ) >"$gout" 2>&1
    if grep -qE "SCRIPT ERROR|Parse Error|ERROR: Failed to load" "$gout"; then rm -f "$gout"; return 1; fi
    if [ -f "$dir/addons/gut/gut_cmdln.gd" ]; then
      xml="$(mktemp)"
      ( cd "$dir" && timeout 120 "$HOME/godot/godot4" --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit "-gjunit_xml_file=$xml" ) >>"$gout" 2>&1
      if [ ! -s "$xml" ] || ! grep -qE 'failures="0"' "$xml" || grep -qE 'status="no asserts"' "$xml"; then rm -f "$xml" "$gout"; return 1; fi
      rm -f "$xml"
    fi
    rm -f "$gout"; ran=1
  fi
  [ "$ran" -eq 1 ] && return 0 || return 2
}

# --- per repo ----------------------------------------------------------------
for repo in "${REPOS[@]}"; do
  name="$(basename "$repo")"
  [ -d "$repo/.git" ] || { log "SKIP $name (no .git at $repo)"; report "| $name | skipped (no checkout) |"; continue; }
  log "=== $name ($repo) ==="
  git -C "$repo" fetch --prune --quiet origin 2>/dev/null

  DEF="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
  DEF="${DEF:-main}"

  # 2. delete branches merged into main (local + remote), preserving protected refs
  protected="^(${DEF}|overnight/feature)$"
  git -C "$repo" for-each-ref --format='%(refname:short)' refs/heads \
    | grep -vE "$protected" \
    | while IFS= read -r b; do
        [ -z "$b" ] && continue
        if git -C "$repo" merge-base --is-ancestor "$b" "origin/$DEF" 2>/dev/null; then
          if [ "$DRY_RUN" = 1 ]; then log "  [dry-run] would prune local (merged): $b"
          else git -C "$repo" branch -D "$b" >/dev/null 2>&1 && log "  pruned local (merged): $b"; fi
        fi
      done
  git -C "$repo" for-each-ref --format='%(refname:short)' refs/remotes/origin \
    | sed 's@^origin/@@' \
    | grep -vE "$protected|^(HEAD|origin)$" | grep -vE '^dependabot/' \
    | while IFS= read -r b; do
        [ -z "$b" ] && continue
        if git -C "$repo" merge-base --is-ancestor "origin/$b" "origin/$DEF" 2>/dev/null; then
          if [ "$DRY_RUN" = 1 ]; then log "  [dry-run] would prune remote (merged): $b"
          else git -C "$repo" push --quiet origin --delete "$b" >/dev/null 2>&1 && log "  pruned remote (merged): $b"; fi
        fi
      done

  # 3. delete stale dated overnight/YYYY-MM-DD/* branches older than KEEP_DAYS
  git -C "$repo" for-each-ref --format='%(refname:short)' refs/remotes/origin \
    | sed 's@^origin/@@' \
    | grep -E '^overnight/[0-9]{4}-[0-9]{2}-[0-9]{2}/' \
    | while IFS= read -r b; do
        d="$(echo "$b" | sed -E 's@^overnight/([0-9]{4}-[0-9]{2}-[0-9]{2})/.*@\1@')"
        de="$(date -j -f %Y-%m-%d "$d" +%s 2>/dev/null || date -d "$d" +%s 2>/dev/null)"
        [ -z "$de" ] && continue
        age=$(( (NOW_EPOCH - de) / 86400 ))
        if [ "$age" -gt "$KEEP_DAYS" ]; then
          if [ "$DRY_RUN" = 1 ]; then log "  [dry-run] would prune stale dated: $b (${age}d)"
          else
            git -C "$repo" push --quiet origin --delete "$b" >/dev/null 2>&1 && log "  pruned stale dated: $b (${age}d)"
            git -C "$repo" branch -D "$b" >/dev/null 2>&1
          fi
        fi
      done

  # 4. reconcile overnight/feature -> main behind a gate
  if ! git -C "$repo" rev-parse --verify --quiet origin/overnight/feature >/dev/null; then
    report "| $name | no overnight/feature |"; continue
  fi
  ahead="$(git -C "$repo" rev-list --count origin/$DEF..origin/overnight/feature 2>/dev/null)"
  if [ "${ahead:-0}" -eq 0 ]; then
    rm -f "$STATE_DIR/branch_hygiene_review_${name}"   # clear any stale flag now that it's synced
    log "  overnight/feature already in $DEF — nothing to land"
    report "| $name | in sync |"; continue
  fi

  auto="$AUTO_MERGE_DEFAULT"
  [ -n "${AUTO_MERGE_OVERRIDE[$name]:-}" ] && auto="${AUTO_MERGE_OVERRIDE[$name]}"
  flag="$STATE_DIR/branch_hygiene_review_${name}"
  mkdir -p "$STATE_DIR"

  if [ "$auto" != "true" ]; then
    echo "overnight/feature is ${ahead} commits ahead of $DEF — flag-only (auto_merge disabled) $(date)" > "$flag"
    log "  FLAG-ONLY: $name overnight/feature +$ahead (human approval required)"
    report "| $name | ⚠️ +$ahead, needs human merge (flag-only) |"; continue
  fi

  # isolated worktree at overnight/feature so the live checkout is untouched
  wt="$(mktemp -d "/tmp/hygiene-${name}.XXXX")"
  if ! git -C "$repo" worktree add --detach --quiet "$wt" origin/overnight/feature 2>/dev/null; then
    log "  could not create worktree — flagging"; echo "worktree add failed $(date)" > "$flag"
    report "| $name | ⚠️ +$ahead, worktree failed |"; continue
  fi
  # gate: does overnight/feature build + test?
  run_gate "$repo" "$wt"; g=$?
  git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1

  # Auto-merge ONLY when tests actually ran and passed (g==0). A failed gate (1)
  # OR "no build/test to gate on" (2) is flagged, never merged — so a repo whose
  # tests we can't detect can never be silently auto-deployed.
  if [ "$g" -ne 0 ]; then
    reason=$([ "$g" -eq 1 ] && echo "gate FAILED (build/tests red)" || echo "no build/test gate available")
    echo "$reason: overnight/feature +$ahead $(date)" > "$flag"
    log "  $reason for $name — NOT merging, flagged for review"
    report "| $name | 🔴 +$ahead, $reason — needs review |"; continue
  fi

  # gate passed: tests ran green. Merge overnight/feature into main.
  if [ "$DRY_RUN" = 1 ]; then
    log "  [dry-run] gate green — would merge overnight/feature (+$ahead) -> $DEF, push, sync feature"
    report "| $name | [dry-run] would merge +$ahead (gate green) |"; continue
  fi
  tmp_main="$(mktemp -d "/tmp/hygiene-main-${name}.XXXX")"
  if ! git -C "$repo" worktree add --quiet "$tmp_main" "origin/$DEF" 2>/dev/null; then
    log "  could not create main worktree — flagging"; echo "main worktree failed $(date)" > "$flag"
    report "| $name | ⚠️ +$ahead, main worktree failed |"; continue
  fi
  git -C "$tmp_main" checkout -B "$DEF" "origin/$DEF" --quiet 2>/dev/null
  if git -C "$tmp_main" merge --no-ff --no-edit -m "chore(overnight): reconcile overnight/feature into $DEF (branch-hygiene, gate=$([ $g -eq 0 ] && echo tests-green || echo no-tests))" origin/overnight/feature >/dev/null 2>&1; then
    if git -C "$tmp_main" push --quiet origin "$DEF" 2>/dev/null; then
      # keep overnight/feature in lockstep with the new main tip
      git -C "$repo" push --quiet origin "origin/$DEF:refs/heads/overnight/feature" 2>/dev/null \
        || git -C "$repo" push --quiet origin "+origin/$DEF:refs/heads/overnight/feature" 2>/dev/null
      rm -f "$flag"
      log "  MERGED $name overnight/feature (+$ahead) -> $DEF and synced feature"
      report "| $name | ✅ merged +$ahead to $DEF ($([ $g -eq 0 ] && echo gated || echo no-tests)) |"
    else
      log "  push to $DEF failed — flagging"; echo "push failed $(date)" > "$flag"
      report "| $name | ⚠️ +$ahead, push failed |"
    fi
  else
    git -C "$tmp_main" merge --abort >/dev/null 2>&1
    echo "MERGE CONFLICT: overnight/feature +$ahead vs $DEF $(date)" > "$flag"
    log "  MERGE CONFLICT for $name — aborted, flagged"
    report "| $name | 🔴 +$ahead, merge CONFLICT — needs review |"
  fi
  git -C "$repo" worktree remove --force "$tmp_main" >/dev/null 2>&1
done

log "branch hygiene complete"
