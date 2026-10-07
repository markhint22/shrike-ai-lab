# Patch (SUPERSEDED 2026-10-02 - the shadow wiring was applied differently, see qa/baseline.README.md "Staged-runner shadow wiring"): baseline-relative verify in `ovn_stage_runner.sh`

Target: `~/overnight-queue/ovn_stage_runner.sh` (box) and `scripts/overnight-queue/ovn_stage_runner.sh` (repo). Line numbers are from
the box copy as read on 2026-10-01. The integrator applies this; the gate builder applied nothing. Shadow mode only: the real
`full_verify` verdict keeps deciding everything; the baseline verdict is computed and logged next to it. Any failure in the shadow
helper is swallowed (`return 0` always, 30s timeout).

## What it does

* After each real `full_verify` call it runs `qa/baseline_verify.py compare` on that run's `verify.log` (`--format verify-log`),
  with `--runner-failed` when the real verdict was a failure, `--changed-files-from` (the step diff, for the masked-risk note) and
  `--base-sha`.
* Writes the would-be verdict to `<run>.baseline.json` (NOT into `verify.log`: the repair loop greps that file for
  `Error|FAILED|assert`, an appended line could pollute the repair prompt) and appends one comparison row to
  `state/qa_shadow/baseline_vs_real.jsonl`.
* `compare` itself appends to `state/qa_shadow/baseline.jsonl` via `qa_common.record` (the canonical shadow log).
* If the would-be verdict is UNVERIFIED because the baseline is missing/expired, kicks ONE background `refresh` for that repo
  (nice'd, no locks, rate limited to once per 30 min per repo) so the next run has a baseline.

## Diff 1: helper (insert after the closing `}` of `full_verify()` -- line ~686 -- i.e. before the `VERIFIED=0` line at ~833)

`full_verify` ends with `return $((1 - vok))`, so its exit status is a clean 0/1 and `$?` can be captured right after it.

```bash
# ---- QA S4 (shadow): baseline-relative verdict logged NEXT TO the real full_verify verdict. Never changes control flow. ----
qa_baseline_shadow(){   # $1 = real full_verify rc (0 verified / 1 not); $2 = label (first|regen|repairN)
  [ "${OVN_QA_BASELINE:-shadow}" = off ] && return 0
  local qb="$HOME/overnight-queue/qa/baseline_verify.py" py=/usr/bin/python3.12 vlog="${SLOG%.jsonl}.verify.log"
  { [ -f "$qb" ] && [ -x "$py" ] && [ -s "$vlog" ]; } || return 0
  local repo_name; repo_name="$(basename "$rd")"
  local chg="${SLOG%.jsonl}.changed"
  git -C "$wt" diff --name-only origin/overnight/feature..HEAD 2>/dev/null | head -80 > "$chg"
  local rf=""; [ "$1" != 0 ] && rf="--runner-failed"
  local out
  out="$(OVN_DIR="$HOME/overnight-queue" timeout 30 "$py" "$qb" compare --repo "$repo_name" --failing-file "$vlog" \
        --format verify-log $rf --changed-files-from "$chg" --worktree "$wt" \
        --base-sha "$(git -C "$wt" rev-parse origin/overnight/feature 2>/dev/null)" 2>/dev/null | tail -1)" || out=""
  [ -n "$out" ] || return 0
  printf '%s\n' "$out" > "${SLOG%.jsonl}.baseline.json"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg run "$(basename "${SLOG%.jsonl}")" --arg repo "$repo_name" --arg label "${2:-first}" \
       --arg real "$([ "$1" = 0 ] && echo verified || echo not_verified)" --argjson would "$out" \
       '{ts:(now|todate),run:$run,repo:$repo,label:$label,real:$real,would:$would.verdict,summary:$would.summary,
         new:($would.details.new_failures|if type=="array" then length else null end),
         pre:($would.details.preexisting|length),growth:($would.details.growth!=null)}' \
       >> "$HOME/overnight-queue/state/qa_shadow/baseline_vs_real.jsonl" 2>/dev/null
    # no/expired baseline while failures are present -> refresh once in the background (rate limited, lock-free, nice'd)
    if printf '%s' "$out" | jq -e '.verdict=="UNVERIFIED" and (.details.failing_count>0) and (.details.baseline==null or .details.baseline.expired)' >/dev/null 2>&1; then
      local stamp="$HOME/overnight-queue/state/qa_baselines/verify/.refresh.$repo_name"
      if [ -z "$(find "$stamp" -mmin -30 2>/dev/null)" ]; then
        mkdir -p "$(dirname "$stamp")"; : > "$stamp"
        ( OVN_DIR="$HOME/overnight-queue" nohup timeout 1000 "$py" "$qb" refresh --repo "$repo_name" >/dev/null 2>&1 & ) 2>/dev/null
      fi
    fi
  fi
  return 0
}
```

## Diff 2: call sites (capture the real rc BEFORE the existing branch; behaviour unchanged)

Current (line ~836):

```bash
VERIFIED=0
if [ "$passed" -gt 0 ]; then
  if full_verify; then VERIFIED=1; say "independent full-verify: PASSED — the combined result is real"
  else
```

Replace the `if full_verify; then` line with:

```bash
  full_verify; _fv_rc=$?; qa_baseline_shadow "$_fv_rc" first
  if [ "$_fv_rc" = 0 ]; then VERIFIED=1; say "independent full-verify: PASSED — the combined result is real"
```

Regen call (line ~841, inside the `try_regen` branch):

```bash
      full_verify; _fv_rc=$?; qa_baseline_shadow "$_fv_rc" regen
      if [ "$_fv_rc" = 0 ]; then VERIFIED=1; passed="$NSTEPS"; say "REGEN PASSED — verified after regenerating the stale artifact (no model needed)"; fi
```

Repair loop (line ~873, `if full_verify; then`): same two-line form with label `repair$_rr`. Shadowing only the first call is acceptable:
later calls judge a different question (the model edited code to fix the failure).

## Diff 3: keep baselines fresh (cron, not part of the runner)

```cron
# baseline red sets for staged verify (shadow). 24h expiry; refresh every 6h on the fleet branch head. Lock-free, nice'd, python repos only.
17 */6 * * *  cd ~/overnight-queue && for r in billwatch gitlark iptv_apps shrike-monitor shrike-notify test-automation-agent; do OVN_DIR=$HOME/overnight-queue /usr/bin/python3.12 qa/baseline_verify.py refresh --repo $r >/dev/null 2>&1; done
```

`refresh` runs the repo's own `.venv/bin/pytest` in a detached worktree of `origin/overnight/feature` (CPU nice'd, 900s timeout =>
UNVERIFIED and the old baseline untouched), then snapshots through the deterministic rules (complete log only; growth => alert, never
widen). Measured on the box: test-automation-agent 43s, shrike-notify 16s (both 0 red at the time). Gradle/GUT/vitest are not refreshed by
this command (python only); for iptv-android compile reds the baseline can only come from `snapshot --failing-file` of a clean-base
log, otherwise those runs stay UNVERIFIED (see README, Known limitations).

## Reading the shadow data (before enforcing)

```bash
jq -r '[.real,.would]|@tsv' state/qa_shadow/baseline_vs_real.jsonl | sort | uniq -c
#   not_verified PASS        <- steps baseline-relative verify would have rescued
#   not_verified UNVERIFIED  <- no/expired baseline or truncated log (tune refresh cadence)
#   not_verified FAIL        <- still a genuine failure
#   verified     FAIL|UNVERIFIED  <- MUST be ~0: a hit means the gate disagrees with a green real verify (parser bug)
```

Suggested promotion criteria: >= 3 days of shadow, `verified`+`FAIL` count 0, and 10 `not_verified`+`PASS` rows read by hand (each
`.baseline.json` lists the pre-existing ids and any `masked_risk`).

## Diff 4 (LATER, only after the shadow data above; do NOT apply with Diffs 1-3): enforce

Add an `elif` after the `_fv_rc = 0` branch so the would-be PASS rescues the run only when the mode file says `enforce`:

```bash
  elif [ "$(jq -r .verdict "${SLOG%.jsonl}.baseline.json" 2>/dev/null)" = PASS ] \
       && [ "$(OVN_DIR="$HOME/overnight-queue" /usr/bin/python3.12 -c 'import sys;sys.path.insert(0,"qa");import qa_common as q;print(q.mode("baseline"))')" = enforce ]; then
    VERIFIED=1; say "baseline-relative verify: PASSED (only pre-existing red) - $(jq -r .summary "${SLOG%.jsonl}.baseline.json")"
```

Pass `--strict-overlap` to `compare` in enforce mode if you want a pre-existing red test in the area the step touched to stay
UNVERIFIED instead of PASS-with-risk.
