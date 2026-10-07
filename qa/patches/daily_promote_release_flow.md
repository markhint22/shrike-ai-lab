# Patch description: adopt the release-branch flow in `daily_promote.sh` / `promote_to_prod.sh`

> **2026-10-02 UPDATE (qa/h4-promotegate): a simplified form of this flow IS now in `promote_to_prod.sh`, behind the kill switch `OVN_RELEASE_FLOW=on` (default OFF,
> only the exact value `on` enables it; OFF is byte-identical to before, proven against the previous script on the same fixtures).** It differs from sections 2/3 below:
> there is no `shadow`/`enforce` tri-state and no `--release` flag; the per-repo gate is in `promote_to_prod.sh` (so `daily_promote.sh` and a manual promote behave the same);
> the candidate comes from `qa/promote_gate.py` (= `release_candidate.compute_plan`, re-run at promote time); `release/YYYYMMDD` is created on origin at the candidate SHA
> with a plain non-forced push; main is then fast-forwarded with `git push origin <candidate-sha>:refs/heads/main` (no `--force`, no `+` refspec; git itself refuses if main moved);
> the `prod-<ts>-<repo>` tag is created at the candidate. Only plan verdicts PASS/FLAG promote; UNVERIFIED (fallback to the develop tip) / no candidate / main not an ancestor => that repo
> is skipped. Not done (still as described below): the in-promote staging poll loop, `staging_smoke.py` as the smoke step, the migration check on the release branch, the
> `branch_hygiene.sh`/`reconcile_branches.sh` follow-ups of section 4 (reconcile's "direct commit on main" alert is NOT triggered by a fast-forward promote but WILL fire for a
> hotfix; release branches are pruned by hygiene once they are ancestors of main).
>
> The **staging-evidence gate** is separate and independent of the release flow: see section 8 at the end of this file.

(Original design text follows; sections 2-3 are the longer-term target, not what is applied.)

Status: design + exact edits. Nothing in this file has been applied; the integrator applies it behind the shadow switch below.
Built against the live scripts as of 2026-10-01 (`daily_promote.sh` md5 d7197600..., `promote_to_prod.sh` md5 0c076577..., identical on the box and in shared).

## 1. The flow (what changes, what does not)

```
today:     develop --(promote_to_prod.sh: smoke, migration check, merge --no-ff)--> main --> prod deploy, tag prod-<ts>-<repo>
proposed:  develop --(candidate rule)--> release/YYYYMMDD --(gates, staging check, staging smoke)--> ff main to release/YYYYMMDD --> prod deploy, tag prod-<ts>-<repo>
hotfix:    main --> hotfix/<name> --(fast gates + smoke)--> main  AND  develop
```

Unchanged on purpose: staging still auto-deploys `develop` (Railway trigger = develop; see section 6 for why that is kept); `branch_hygiene.sh`
still merges green feature work into develop; `reconcile_branches.sh` still owns develop -> feature branches and the main -> develop back-merge; the
`prod-<ts>-<repo>` tag is still the rollback anchor; mobile stays a separate human step.

What is new:

1. **A release candidate is a SHA, not "develop's tip".** `qa/release_candidate.py plan` picks the newest develop first-parent commit that (a) contains
   main, (b) is a green hygiene merge (subject has `gate=tests-green`; main->develop sync merges inherit the status below them), and (c) has no QA FAIL
   in `state/qa_shadow/*.jsonl` anywhere in `main..candidate`. If none qualifies it returns the tip marked UNVERIFIED (never PASS).
2. **`release/YYYYMMDD` is cut at that SHA** (name gets `-2`, `-3` on collision; an existing branch already at the candidate is reused, so cut is idempotent).
3. **Promote = fast-forward `main` to the release branch** (`git push origin release/X:refs/heads/main`, no `--force`). A fast-forward push is atomic and is
   refused by the server if main moved (a hotfix landed) - that is the "lease"; the repo is reported BLOCKED and re-cut next run. No merge commit ever lands on main, so
   the `release: promote develop -> main` commits (and the reconcile back-merge they require) disappear. The prod deploy is of exactly the SHA that was gated and smoked.
4. **Hotfix** branches come from `main` (`hotfix/<name>`), merge to main (ff or `--no-ff`, subject must start `release: hotfix`) and then to develop
   (the existing 20-minute `reconcile_branches.sh` back-merge does this automatically; merging explicitly in the same step is faster).

Measured on the 8 real repos (box, last 14 promotes each; `release_candidate.py history`): the rule would have chosen exactly what was promoted in 98 of 101
promotes and a fast-forward of main was possible in 101 of 101 (the back-merge invariant main in develop holds). The 3 differences were all iptv_apps promotes whose
develop tip was a manual `chore(release): merge claude/feature into develop` / `fix:` commit (no hygiene gate on that merge) - the rule held them back one merge.

## 2. `daily_promote.sh` - exact edits

Add one switch near the top, after `REPOS=`:

```bash
# release-branch flow: off (today's behaviour) | shadow (run the new flow in report-only mode NEXT TO the old promote) | enforce (new flow promotes)
RELEASE_FLOW="${OVN_RELEASE_FLOW:-off}"
QA="$DIR/qa"
```

### 2a. shadow mode (adopt first, for >= 1 week): inside the per-repo loop, BEFORE `out="$(./promote_to_prod.sh ...)"`

```bash
  if [ "$RELEASE_FLOW" != "off" ]; then
    rf="$(python3.12 "$QA/release_candidate.py" cut --repo "$r" --run-gates 2>/dev/null | tail -1)"      # shadow: scratch clone, never pushes
    sc="$(python3.12 "$QA/staging_check.py"    check --repo "$r" --release-plan 2>/dev/null | tail -1)"
    sm="$(python3.12 "$QA/staging_smoke.py"    check --repo "$r" 2>/dev/null | tail -1)"
    rf_line="$(printf '%s\n%s\n%s' "$rf" "$sc" "$sm" | python3.12 -c 'import sys,json
for l in sys.stdin:
    try: j=json.loads(l)
    except ValueError: continue
    print("  [release-flow:%s] %s %s" % (j["gate"], j["verdict"], j["summary"][:140]))')"
    echo "$rf_line"
  fi
```

Every gate here is itself shadow (it records to `state/qa_shadow/` and exits 0), so this block cannot change the outcome of today's promote. It produces the data
needed to decide when to flip: how often the candidate differs from the tip, how often staging was behind, how often smoke would have failed.

### 2b. enforce mode: replace the single promote call

```bash
  if [ "$RELEASE_FLOW" = "enforce" ]; then
    out="$(OVN_QA_RELEASE_CANDIDATE=enforce ./promote_to_prod.sh --yes --release "repos/$r" 2>&1)"
  else
    out="$(./promote_to_prod.sh --yes "repos/$r" 2>&1)"
  fi
```

The result classification below it (`PROMOTED` / `nothing to promote` / else blocked) keeps working because `--release` prints the same markers.

### 2c. ntfy summary

Add the candidate to the body so a held-back day is visible: after `body=...` append, per promoted repo, `release/<date>@<sha10>`, and for a FLAG/UNVERIFIED
plan add `held back N merge(s)` (read from the plan JSON). Priority logic is unchanged (BLOCKED -> high).

### 2d. staging deploy evidence must reach the box

The box has no Railway CLI/login (verified: `railway: command not found`; the login is a browser session on the Mac). `staging_check.py` therefore supports a file
provider. Add to the **Mac** crontab (every 10 min), beside deploy_watch:

```
*/10 * * * * cd ~/LocalProjects/shared/scripts/overnight-queue && for r in billwatch gitlark iptv_apps; do OVN_DIR=/tmp/qa-export python3 qa/staging_check.py export --repo $r >/dev/null 2>&1; done && rsync -a /tmp/qa-export/state/staging_deploys/ gpu:overnight-queue/state/staging_deploys/
```

(or add `"commit": os.getenv("RAILWAY_GIT_COMMIT_SHA")` to each backend `/health`; `staging_check.py`'s `http` provider then needs nothing else. That is the better long-term fix and is an app change, not a pipeline change.)
A stale export (> 30 min) makes the gate UNVERIFIED, never PASS.

## 3. `promote_to_prod.sh` - exact edits (new `--release` mode; the existing path is untouched)

Add `REL=0` and parse `--release) REL=1;;` next to `--yes/--force/--dry-run`. Inside the per-repo loop, immediately after the `nothing to promote` check, branch:

```bash
  if [ "$REL" -eq 1 ]; then
    # 1) plan + cut (the cut only PUSHES the release branch, in enforce mode, and only when plan is PASS/FLAG and main can fast-forward)
    plan="$(python3.12 "$DIR/qa/release_candidate.py" cut --repo "$name" --run-gates --really-push --enforce-exit 2>/dev/null | tail -1)"
    pv="$(printf '%s' "$plan" | python3.12 -c 'import sys,json;j=json.loads(sys.stdin.read());print(j["verdict"]);' 2>/dev/null)"
    rbranch="$(printf '%s' "$plan" | python3.12 -c 'import sys,json;print(json.loads(sys.stdin.read())["details"].get("scratch_branch",""))' 2>/dev/null)"
    case "$pv" in PASS|FLAG) ;; *) echo "  🔴 release cut: $pv - NOT promoting $name"; echo "$plan" | cut -c1-300; continue;; esac
    timeout 30 git -C "$repo" fetch -q origin   # make origin/<release branch> visible locally
    # 2) staging must serve the candidate (poll up to 20 min: staging builds take ~3-6 min after the develop merge)
    for i in 1 2 3 4 5 6 7 8; do
      sc="$(python3.12 "$DIR/qa/staging_check.py" check --repo "$name" --sha "$(git -C "$repo" rev-parse "origin/$rbranch")" 2>/dev/null | tail -1)"
      case "$(printf '%s' "$sc" | python3.12 -c 'import sys,json;print(json.loads(sys.stdin.read())["verdict"])')" in PASS) break;; esac
      sleep 150
    done
    # 3) real staging smoke (replaces staging_smoke.sh for repos that have a smoke config; FLAG = PARTIAL coverage, allowed; FAIL/UNVERIFIED block)
    sm="$(python3.12 "$DIR/qa/staging_smoke.py" check --repo "$name" --enforce-exit 2>/dev/null | tail -1)"
    sv="$(printf '%s' "$sm" | python3.12 -c 'import sys,json;print(json.loads(sys.stdin.read())["verdict"])')"
    case "$sv" in PASS|FLAG|NA) ;; *) echo "  🔴 staging smoke: $sv - NOT promoting $name"; continue;; esac
    # 4) migration safety on the RELEASE branch (today check_migrations.py reads the repo's CHECKED-OUT tree, i.e. overnight/feature, not develop)
    #    -> run it against a worktree of the release branch (gate S6, qa/gate_migrations.py, when integrated)
    # 5) fast-forward main to the release branch (atomic; the server refuses if main moved) and tag
    timeout 30 git -C "$repo" fetch -q origin
    if git -C "$repo" merge-base --is-ancestor "origin/$DEF" "origin/$rbranch"; then
      tag="prod-$NOW-$name"; sha="$(git -C "$repo" rev-parse "origin/$rbranch")"
      if timeout 30 git -C "$repo" push -q origin "origin/$rbranch:refs/heads/$DEF" \
         && git -C "$repo" tag "$tag" "$sha" && timeout 30 git -C "$repo" push -q origin "$tag"; then
        echo "  ✅ PROMOTED $name $rbranch -> $DEF (fast-forward, ${sha:0:10}). Prod deploy triggered. Rollback: git checkout $tag"
      else echo "  ⚠️ push failed (main moved? it will re-cut next run)"; fi
    else
      echo "  🔴 main is not an ancestor of $rbranch (a hotfix landed) - NOT promoting; reconcile back-merge + re-cut next run"
    fi
    continue
  fi
```

Notes: the push uses no `--force`, so the safety property "main only ever moves forward to a gated SHA" is enforced by git itself. The worktree/merge machinery
at the bottom of the script is skipped in this mode (no merge commit is created).

## 4. Files that must be touched for the flow to coexist (not by this patch, listed so nothing surprises you)

| script | why | edit |
|---|---|---|
| `branch_hygiene.sh` step 2 | it deletes every remote branch that is an ancestor of `origin/main`. After a ff promote `release/X` IS an ancestor of main, so it is pruned within 1-3h. Harmless (the `prod-*` tag keeps the SHA) but surprising. | optional: add `release/` to `$protected` for N days if you want the branches to stay visible; a release branch is **never** pruned before promote (it is ahead of main). |
| `reconcile_branches.sh` ~line 224 | counts "direct commits on main" with `grep -vE '^release: promote\|^Merge '`. A hotfix on main would raise the "NON-promote commit on main" alert. | extend the regex to `^release: (promote\|hotfix)\|^Merge `; require hotfix merge subjects to start `release: hotfix`. |
| `deploy_watch.sh` | none - prod still deploys from main; the SHA is simply a release tip. | none |
| `staging_smoke.sh` | stays as the fallback for repos without a smoke config (website, agent, xlite have no staging backend: `staging_check`/`staging_smoke` return NA for them). | none |

## 5. Phased rollout

1. **Shadow (now):** `OVN_RELEASE_FLOW=shadow`. Daily promote behaves exactly as today; the release plan, cut, staging check and smoke are logged next to it.
2. **Cut enforced, promote old:** the release branch is pushed daily (visible, auditable) but main still gets the old merge. Compare release tip vs old promote.
3. **Promote enforced (`--release`):** flip `OVN_RELEASE_FLOW=enforce` repo by repo, starting with shrike-labs-website (ahead=1 per day, no staging: only the candidate rule applies), then billwatch/gitlark/iptv_apps (full chain), xlite/test-automation-agent last.
4. **Retire** the `release: promote` merge path and the "direct commit on main" alert for promote subjects.

Gate to leave shadow: >= 7 consecutive days with no `staging_check` FAIL that was not a real staging problem, `staging_smoke` UNVERIFIED rate < 10% (creds provisioned on the box), and the candidate == tip on >= 80% of days.

## 6. Why staging stays on `develop` (and what that costs)

Railway staging deploys the `develop` branch (trigger set 2026-09-15). The candidate can be older than the tip (a held-back merge). Then staging serves a **superset** of the
candidate (`MATCH_SUPERSET`): smoke ran on code that contains the candidate plus newer commits. Consequences: a PASS is strong evidence (superset healthy implies candidate
very likely healthy); a FAIL may be caused by the newer commit and blocks a candidate that is fine (fail safe, costs one day). To get exact-SHA staging instead, repoint the
staging trigger to a fixed branch `release/staging` that the cut step force-moves - deliberately NOT proposed: it needs a force-push ref owned by automation and a GraphQL trigger change.

## 7. Failure semantics (so the integrator does not turn infra noise into blocked releases)

| situation | gate verdict | promote behaviour in enforce |
|---|---|---|
| no qualified candidate / develop tip fallback | UNVERIFIED | skip repo this run, report |
| main cannot fast-forward (un-back-merged commit on main) | FAIL (cut) | skip repo; reconcile back-merges within 20 min; next run re-cuts |
| staging serves older build / latest staging deploy FAILED | FAIL | block (this is the silent-stale-staging incident class) |
| staging evidence missing (box, export stale, railway login expired) | UNVERIFIED | block that repo for the day, loud in the summary (never promote on missing evidence) |
| smoke step got an HTTP failure | FAIL | block |
| smoke could not reach staging / creds not provisioned | UNVERIFIED | block that repo, report as infra not as bad code |
| smoke partial (no login mechanism, e.g. gitlark) | FLAG | allowed; the summary names the gap |

## 8. Staging-evidence gate in the promote (2026-10-02, applied, default shadow)

`promote_to_prod.sh` calls `qa/promote_gate.py check --repo <r> --main origin/<default>` for every repo that is ahead (bounded by `qa/qa_timeout.py`, `OVN_PROMOTE_GATE_TIMEOUT`, default 90 s).
It re-runs the release-candidate plan and `staging_check` (file provider only = the Mac's 10-minutely snapshot `state/staging_deploys/<repo>.json`, stale > 30 min => UNVERIFIED),
prints two lines that `daily_promote.sh` keeps whole in `logs/daily_promote.log`:

```
  [candidate] 743980f62f FLAG, 1 develop merge(s) held back, release branch release/20261002, main fast-forwardable: yes
  [staging-gate] mode=shadow staging_check=FAIL/MISMATCH_BEHIND serving=726d250f9a provider=file -> proceed (staging serves ..., BEHIND the candidate (not deployed yet))
```

and **blocks that repo only** when mode is `enforce` AND staging_check says FAIL with relation MISMATCH_BEHIND / MISMATCH_DIVERGED / MISMATCH_FAILED. A blocked repo prints
`STAGING-GATE BLOCK`, appends one line `WARN | promote-staging-gate | <repo> promote SKIPPED ...` to `state/alerts.log`, and the daily summary gets a `HELD` line (priority high);
the other repos are processed normally. PASS, NA, every UNVERIFIED flavour (stale/corrupt/missing snapshot, still BUILDING, commit unknown to the clone), a crashing/garbage-printing/hanging
helper, a missing `qa/` dir and mode `off`/`shadow` NEVER block. `--force` overrides a block (human decision, loud line, no alert).

Mode: env `OVN_QA_STAGING_CHECK` > `state/qa_gate_modes.json` (when present; `{"staging_check":"enforce"}` or nested under `modes`/`gates`, value a string or `{"mode":..}`) > `state/qa_modes.json`
(`qa_common.mode`) > `shadow`.
- Turn on: `echo '{"staging_check":"enforce"}' > ~/overnight-queue/state/qa_gate_modes.json` (or `export OVN_QA_STAGING_CHECK=enforce` in the cron line).
- One-command rollback: `rm ~/overnight-queue/state/qa_gate_modes.json` or set the env to `shadow`.
- Caveat to know before enabling: with the release flow OFF the promote ships develop's TIP but the gate checks the CANDIDATE (the newest green merge, possibly older than the tip). Staging deploys
  develop, so a healthy staging at or past the candidate is MATCH/MATCH_SUPERSET. A tip merged minutes before 09:00 that staging has not built yet does not block on its own (candidate older) - it blocks only
  when staging is behind the candidate.

Tests: `scripts/test/test_promote_gate.sh` (73 checks; real scripts under `env -i`, throwaway bare origins; negative controls for each FAIL relation, benign controls for each UNVERIFIED flavour,
the release flow ON/OFF incl. a hotfix landing mid-promote). It fails 43 checks against the previous `promote_to_prod.sh`/`daily_promote.sh`.
