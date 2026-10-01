# Gate S10 - release branch, staging evidence, staging smoke (shadow)

Three scripts, one CLI contract (`docs/QA_GATES_SPEC.md`), all **shadow-only**: they log to `state/qa_shadow/<gate>.jsonl`, print one JSON line, exit 0.
The only exception is `--enforce-exit` together with `OVN_QA_<GATE>=enforce` (FAIL -> exit 1).

| file | gate key | what |
|---|---|---|
| `qa/release_candidate.py` | `release_candidate` | `plan` / `cut` / `history`: choose the release-candidate SHA, name and (scratch-)cut `release/YYYYMMDD` |
| `qa/staging_check.py` | `staging_check` | does the staging backend serve the candidate SHA? (`check`, `export`) |
| `qa/staging_smoke.py` + `qa/staging_smoke.conf` | `staging_smoke` | real smoke per repo: health, login, business endpoint, DB write + read-back, frontend, CORS |
| `qa/patches/daily_promote_release_flow.md` | - | exact edits to adopt the flow (NOT applied) |
| `scripts/test/test_qa_release.py` | - | 114 checks, negative + benign controls, real entry points under `env -i` |

## Branch design (decision 4: "I want a release branch, use your judgement")

`develop -> release/YYYYMMDD -> main`, hotfixes `main -> hotfix/* -> main + develop`. Promote is a **fast-forward of main to the release branch** (no merge commit), tagged
`prod-<ts>-<repo>` as today. Reasoning and the exact script edits are in the patch doc. Key properties: prod deploys exactly the SHA that was gated and smoked; main can only move
forward (git refuses a non-ff push, which doubles as the "main moved under us" lease); the existing back-merge invariant (main is contained in develop) is what makes the
fast-forward possible - measured true for 101/101 historical promotes.

## release_candidate.py

```
python3.12 qa/release_candidate.py plan    --repo billwatch [--date YYYYMMDD] [--main origin/main] [--develop origin/develop] [--fetch] [--no-record]
python3.12 qa/release_candidate.py cut     --repo billwatch [--run-gates] [--keep] [--really-push]
python3.12 qa/release_candidate.py history --repo billwatch [--n 14]      # retrospective on real promotes, measurement only
```

**Candidate rule** - first-parent walk of `main..develop`, newest first; the first commit that is all of:
1. contains `origin/main` (otherwise main cannot fast-forward to it);
2. a **green hygiene merge** - subject contains `gate=tests-green`. `gate=no-tests` and direct/manual commits are not green. A `reconcile main -> develop` sync merge adds no content, so it
   inherits the status of the nearest older non-sync commit (or green if it sits directly on main). A green merge validates everything below it (hygiene tests the merge result), so a manual commit
   is held back only until the next green merge lands on top (hours, not days);
3. no `FAIL` row for this repo in `state/qa_shadow/*.jsonl` (gates other than release_candidate/staging_check/staging_smoke) whose commit (`ref`, `details.head|commit|sha`; for `base..head` only the head) is anywhere in `main..candidate`, including feature-branch commits inside merges.

If nothing qualifies: develop tip, verdict `UNVERIFIED` (`fallback: true`). Verdicts: `PASS` tip qualifies; `FLAG` an older candidate (the held-back merges are listed with the reason each was skipped);
`UNVERIFIED` fallback/cannot compute; `NA` develop == main. `details` carries: candidate, release branch name, `ff_main_possible`, commits since main (60 shown, total counted), features (`feat(...)` subjects),
held_back, skipped+reasons, and `coverage` (how many shadow rows exist for the repo; 0 means the no-FAIL check is vacuous and the summary says so).

**cut** works in a throwaway `git clone --shared` under `/tmp`, so the live clone never gains a ref, branch or worktree (tested: refs/worktrees/branches identical before and after). It creates a real
local `release/<date>` branch there, **simulates the fast-forward of main** (detached `merge --ff-only`; failure => `FAIL`), optionally runs every sibling `qa/gate_*.py` against `main..candidate`
(`--run-gates`; a FAIL fails the cut, a crashing gate is UNVERIFIED for that gate only) and prints `would_push` (branch, ff main, tag). `--keep` leaves the scratch clone for inspection.
`--really-push` is refused unless the gate mode is `enforce` and the verdict is PASS/FLAG; it then pushes **only the new release branch, non-forced** - never main, never a tag.
Promoting main is deliberately not implemented in this build (shadow only); the code for it is in the patch doc.

`history` replays the rule on the last N `release: promote` merges of main (main=parent1, develop=parent2) and reports tip==candidate, held-back, fallback and ff-impossible counts.

## staging_check.py

Finds out what staging actually runs. Provider order (`--provider auto`): `http` (a `commit|commit_sha|git_sha|sha` key in `/health` - none of our backends has one yet),
`railway` (`railway link` + `railway deployment list --json --environment staging --service <id>` from an isolated temp cwd, account login, same model as `deploy_watch.sh`; project/service ids
are the public ones `deploy_watch.sh` already hardcodes), `file` (`state/staging_deploys/<repo>.json`, produced by `staging_check.py export` on the Mac, max age 30 min).

Relations: `MATCH`, `MATCH_SUPERSET` (staging contains the candidate; PASS but noted), `MISMATCH_BEHIND`, `MISMATCH_DIVERGED`, `MISMATCH_FAILED` (latest staging deploy FAILED/CRASHED while an older build keeps
serving - the billwatch incident class), `UNVERIFIED` (still building, no evidence, commit unknown to the clone). `REMOVED`/`SKIPPED` builds are ignored. Repos with no staging backend
(website, xlite, test-automation-agent) return `NA`. Output contains only deployment id, status and commit hashes - never a token.

**Platform fact:** the GPU box has no Railway CLI and its login is a browser session on the Mac, so on the box this gate is UNVERIFIED unless the Mac exports the deploy list (see patch doc 2d) or
the backends expose their commit in `/health` (Railway injects `RAILWAY_GIT_COMMIT_SHA`).

## staging_smoke.py

Per repo, from `qa/staging_smoke.conf`. **Staging only**: the base URL (`state/staging_url_<repo>` or `--base-url`) must contain `staging`; production URLs are refused before any request.

| step | billwatch | gitlark | iptv_apps (Chickadee) |
|---|---|---|---|
| health (2xx/307 + JSON content-type + key) | /health | /health | /health |
| login (staging test account) | form `/api/auth/login` as `qa-smoke@shrikelabs.dev` (auto-registered once) | **N/A: GitHub-OAuth only**; `QA_SMOKE_GITLARK_TOKEN` enables it | JSON `/api/auth/login` as the premium staging tester |
| business | bills search, topics (auth), anonymous `/api/auth/me` must be 401 | public snippets search/trending, anonymous `/api/workspaces` must be 401 | `/api/subscription/status` must say premium+active (paywall chain intact), streams list, anonymous `/api/streams` must be 401 |
| write + read-back | PATCH display_name, read via `/api/auth/me` | create/read/delete snippet (needs token) | create profile `E2E smoke <marker>`, find it in `/api/profiles`, delete it (cleanup always attempted; the janitor sweeps `E2E ...` profiles as a backstop) |
| frontend via curl | billwatch.vercel.app | gitlark.vercel.app | chickadeestream.com |
| CORS | preflight echoes the real origins; an arbitrary origin must NOT be echoed | same | same |

Verdict: any step FAIL -> `FAIL`; else any step that could not run for infra reasons -> `UNVERIFIED`; else steps N/A by design -> `FLAG` ("PARTIAL", gaps named - never a silent PASS); else `PASS`.
Only an HTTP response can fail a step; timeouts/DNS/refused are `UNVERIFIED` (one retry first).

**Credentials** (never printed; every secret and token seen in a run is scrubbed from the output and the shadow log; tested): env vars (`QA_SMOKE_BILLWATCH_EMAIL/PASSWORD`, `QA_SMOKE_CHICKADEE_EMAIL/PASSWORD`,
`QA_SMOKE_GITLARK_TOKEN`) -> `state/qa_creds/<name>.json` (0600, dir 0700) -> for iptv_apps the documented staging defaults in `scripts/e2e_janitor.py`, read with `git show origin/develop:...`
(the memory note `reference_chickadee-staging-test-account.md` and `iptv_apps/docs/TEST_ACCOUNTS.md` document the accounts; nothing is copied into this repo) -> billwatch only: auto-register a
random-password account on staging and save it to `state/qa_creds/billwatch.json`. **Integrator action:** that file must exist on the box (`~/overnight-queue/state/qa_creds/billwatch.json`), otherwise the box sees
"account exists, no stored credentials" and billwatch smoke is UNVERIFIED there. (I created the account from the Mac using a scratch state dir; the credential file is in `/tmp/qa-rel-ovn` on the Mac and in
`/tmp/qa-build-release-1/ovn` on the box, not in production state.)

## Measured (2026-10-01, real repos / real staging)

- `plan`/`history` on the 8 box clones: 46-420 ms per plan. `cut` (scratch clone + ff simulation): 0.08-0.45 s, xlite 1.7 s.
- Retrospective on the last 14 promotes per repo (101 total): candidate == the promoted tip in 98, held back in 3 (iptv_apps, all three were manual merges to develop without a hygiene gate), fallback 0, ff-impossible 0.
- `staging_check` live: billwatch MATCH (Mac railway CLI, 4.4-7 s); gitlark and iptv_apps MATCH on the box via the exported file (23-43 ms); the three staging deployments were serving exactly the candidate each plan chose.
- `staging_smoke` live, 8 runs per repo per host: billwatch PASS p50 2.8 s / p90 2.9 s (Mac), 2.5 / 2.5 (box); iptv_apps PASS 2.6 / 3.3 (Mac), 2.4 / 2.6 (box); gitlark FLAG (PARTIAL by design) 1.5 / 1.5 (Mac), 1.3 / 1.3 (box).

## Known limitations

- No `qa_shadow` data exists yet (the other gates are not integrated), so the "no QA FAIL in range" rule is vacuous today; `coverage.shadow_rows_for_repo` and the PASS summary say so.
- Candidate rule relies on the hygiene subject text `gate=tests-green`; if branch_hygiene's message format changes, every commit looks ungated and plan falls back to UNVERIFIED (loud, not silent).
- Staging deploys `develop`, not the release branch, so the usual result is `MATCH_SUPERSET`/`MATCH`, not an exact-SHA test (patch doc section 6).
- gitlark has no way to log in non-interactively, so its write/read step is untested against the real server (the code path is covered against the local fake with a token). billwatch staging has 0 bills, so its public business check proves the route works, not that data renders.
- The frontend step loads the **production** frontend asset (there is no staging frontend; `billwatch-staging.vercel.app` and `gitlark-staging.vercel.app` return 404), and CORS is tested from the real prod frontend origins against the staging backend.
- `plan` does not fetch (clones are kept fresh by the pipeline; `--fetch` opts in). Promote to main, hotfix automation and tag creation are not implemented (shadow build) - only described in the patch doc.
- Merge-ancestry decisions assume the local clone has the commits; an unknown staging commit is UNVERIFIED, not FAIL.


## Review fixes (qa/release-fix) - the "false confidence" class
Rule: when the gate cannot check something it says UNVERIFIED/FLAG, never PASS.
- `cut --run-gates`: a gate that is UNVERIFIED, crashed, hung (timeout), printed a bogus verdict, or printed PASS but exited non-0 makes the cut
  UNVERIFIED; a gate FLAG makes it FLAG; a missing/empty gates dir (ZERO gates run) is UNVERIFIED. Only FAIL used to downgrade it.
- QA FAIL rows for the repo whose ref cannot be resolved to a commit (branch name, `HEAD~2`, `origin/develop`, no ref, unknown sha) are counted
  (`coverage.unresolved_fail_rows`, `details.unresolved_fail_rows`); while any exist `plan`/`cut` are UNVERIFIED, never PASS. To make a FAIL hold a
  commit back, gates must log the resolved head SHA (`ref`, or `details.head`/`commit`/`sha`).
- Vacuity: the "no-FAIL check is vacuous" warning (and `coverage.no_fail_check_vacuous`) counts only code-facing gate rows; this gate's own rows
  (and staging_check/staging_smoke) no longer end it. It stays a PASS-with-warning on purpose: today no other gate is integrated, so UNVERIFIED
  would be permanent; flip that decision when the other gates write shadow rows.
- A green hygiene commit must be a MERGE commit (2 parents); a direct commit that merely contains `gate=tests-green` is "other".
- staging_check: the staging commit must be 7-40 hex chars (and so must the candidate) or the result is UNVERIFIED; a 1-char prefix was a false MATCH.
- staging_smoke: the target host must end in `.up.railway.app` AND contain `staging` (credentials are sent there); a PASS says "staging BACKEND only".
- CORS note: an `allow-origin: *` answer to an arbitrary origin is accepted (fine for bearer-token APIs, no cookies); only an exact reflection fails.
- Known/accepted: MATCH_SUPERSET is PASS (smoke covers it); billwatch smoke auto-registers `qa-smoke@shrikelabs.dev` on staging even with --no-record.
