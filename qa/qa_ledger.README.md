# S12 - escape ledger + scorecards (`qa_ledger.py`, `qa_scorecard.py`, `qa_ledger_cron.sh`)

Nothing measured how many defects escape the gates. This is the measurement backbone: one ledger row per LANDED item, later
outcome events appended to it, a per-feature / per-promote scorecard (cells, never a composite score) and an escape-rate report.
Pure observation: read-only git, no locks, no network, never blocks anything, always exit 0.

## Files and state (everything under `$OVN_DIR/state`, default `~/overnight-queue`)

| file | what |
|---|---|
| `qa_ledger.jsonl` | append-only; `{"kind":"landed"}` rows and `{"kind":"event"}` rows |
| `qa_ledger.cursor` | byte offset into `outcomes.jsonl`; only complete (newline-terminated) lines are consumed; written last (crash-safe, rows are deduped by key anyway) |
| `qa_ledger.prev.json` | last outcome epoch per repo (lower bound of the commit-attribution window) |
| `qa_ledger.lock` | held by the cron wrapper (`flock -n`, mkdir fallback if flock is missing) |
| `logs/qa_ledger_cron.log` | one line per cron pass |

## Run

    python3 qa/qa_ledger.py derive [--no-record] [--rescan-days 15] [--no-events]
    python3 qa/qa_ledger.py mark-escape --repo R --ref SHA --note TEXT [--no-record]
    python3 qa/qa_ledger.py summary [--repo R]
    python3 qa/qa_scorecard.py feature --repo R --feat TAG [--json]
    python3 qa/qa_scorecard.py promote --repo R --from REF --to REF [--json]
    python3 qa/qa_scorecard.py report  [--days 30] [--repo R] [--mature-days 7] [--json]
    qa/qa_ledger_cron.sh                      # cron: e.g.  23 * * * *  $HOME/overnight-queue/qa/qa_ledger_cron.sh

`derive` and `mark-escape` print one JSON verdict line (qa_common contract; `--no-record` keeps them out of `qa_shadow/ledger.jsonl`,
the cron wrapper always passes it). Exit 0 always. Python: runs on box `python3.12` and Mac `python3` (stdlib only).
Modes: this tool is observation-only, so `qa_common.mode("ledger")` is informational (default `shadow`); there is nothing to enforce.

## What a landed record is

Source: an `outcomes.jsonl` row with `class=landed` and a `pushed*` / `stage(higher-tier)` status (rows with garbage status such as
`U OVERNIGHT_PROGRESS.md`, torn JSON and NUL-byte lines are skipped).

* **commits** - outcomes carry NO sha. Commits are attributed by time: non-merge commits on `origin/overnight/feature`,
  `origin/claude/feature`, `origin/develop`, `origin/main` committed in `(max(previous outcome of the repo, ts-duration-600s), ts+60s]`,
  excluding pipeline housekeeping (`chore(queue|sync|overnight)`, `fix(queue)`, merges, reverts, commits that touch only
  OVERNIGHT_PROGRESS.md), at most the 4 closest to the outcome, each commit claimed once. `commit_basis` = `time-window | none | no-clone`.
* **risk class** - `A` auth / paywall / RevenueCat / billing / payments / migrations / prod config (Dockerfile, railway, vercel, .env) /
  alert path (ntfy, notify, alerts): decided by changed file path words first, item text (`A_TEXT`) second. `C` tests/docs-only
  or delete-only changes. `B` any other source change (so B is wider than "T3+/endpoint": T1/T2 source edits are B too). If no commit
  was attributed, text/tier/category decide (`risk_basis` says `text-only:*`). Tests-only beats A (an auth test is C).
* **weak_oracle** - the item's `VERIFY:` command is existence-only (no test runner / script / curl / alembic). Item text comes from
  `OVERNIGHT_PROGRESS.md` on the clone (`git show`), matched by `[feat:...]` tag or the pipeline's item-hash algorithm; `null` = no text found.
* **flags** - `untested-change`, `redgreen-suspect`, `after-rebase`, `stage` copied from the outcome status.

## Escape signals (events), exactly how each is detected

All events are re-derived every pass for records younger than `--rescan-days` (15), keyed so reruns never duplicate.

| event | rule | confidence |
|---|---|---|
| `revert` | a commit whose body says `This reverts commit <sha>` with a sha that is one of the record's commits, or subject `Revert "<subject>"` equal to one of its subjects; revert within 14 days of the landing | `sha` / `subject` |
| `hotfix` | a later non-merge commit with subject `fix...` / `hotfix...`, within 7 days, touching >=1 same non-trivial file (docs, lockfiles, `__init__.py`, requirements, OVERNIGHT_PROGRESS ignored). Attributed to the ONE record that best explains it (most overlapping files, then most recent). Not counted: the pipeline's own in-flight `repair staged item to pass verification`, anything in the same `feat_tag` as the fix (continuation, not escape) | `strong` = repair-style subject (duplicate / missing / broken / syntax / import error / restore / regress ...) on a focused commit (<=12 files); everything else `weak` |
| `emergency` | commit whose subject mentions EMERGENCY and is not test-watch (deploy-fix items from `ovn_enqueue_emergency`). Always a repo-level event; additionally attributed to the one landed record (<=7d before) with the best file overlap with the paths in the item the commit added to OVERNIGHT_PROGRESS.md | `repo-level` / `file-overlap` |
| `test_watch_red` | same, subject has `suite red` / `test-watch` (from `ovn_test_watch.sh`) | `repo-level` / `file-overlap` |
| `escape` | manual: `mark-escape --repo R --ref SHA --note TEXT`. Attaches to the record owning that commit; else to records landed <=30d earlier that share files with the commit; else a repo-level unattributed event | `manual-commit` / `manual-file-overlap` / `manual-unattributed` |

Report headline: **strong** escapes = revert + manual + hotfix-strong + emergency/test-watch with file overlap. **any** adds weak hotfix.
Rates are per 100 MATURE features (every record >= 7 days old, so the 7-day windows are closed); young features are listed but not in rates.

## Scorecard cells

`feature` / `promote` print one row per feature: gate cells + `escape` + `oracle`. Vocabulary PASS FAIL FLAG NA UNVERIFIED, no composite.
* gate cell = worst verdict among `state/qa_shadow/<gate>.jsonl` records whose `ref` matches one of the feature's commits (or the promote `--to` sha).
  `NA` = that gate has no shadow log at all; `UNVERIFIED` = log exists but nothing covers this feature. Gates listed: antigaming, scanners,
  migrations, baseline_verify, acceptance_card, staging_check, release_candidate, device_lane + any other `qa_shadow/*.jsonl` (names normalised: `gate_`/`qa_` prefix dropped).
* `escape`: `FAIL` any attributed event; `PASS` (printed with its note) means only "no git evidence found", never proof of no escape; `PASS` only if mature (>=7d) AND every record had attributed commits; `UNVERIFIED` mature but some records have no commits (events need files); `NA` too young.
* `oracle`: `FLAG` existence-only VERIFY, `PASS` runner VERIFY, `NA` unknown.
* `promote` also says how many commits of the range are pipeline housekeeping and how many have NO ledger row (human commits are not covered by the card).

`report` prints: counts, escape per 100 by repo / risk class / type / risk x repo (strong and any), weak-oracle share, `untested-change` / `redgreen:SUSPECT`
share, commit-attribution coverage, stage-unverified counts per repo (read straight from outcomes.jsonl; those never land) and repo-level EMERGENCY events with no attributable feature.

## Measured (real box data, scratch copy in /tmp, 2026-10-01)

* Replay of the whole `outcomes.jsonl` (16,353 rows, since 2026-09-07): 3,707 landed records, 2,873 (78%) with attributed commits, 0 crashes, 2.6-4.3 s total. Incremental pass (nothing new, 15d event rescan of all 7 repos): p50 1.17 s / p90 1.22 s. `report` p50 0.35 s, `feature` 0.12 s.
* Sanity vs `ovn_stats.py 168` (7 days): ledger 1,080 landed vs `outcomes.jsonl` class=landed 1,081 (the 1 row skipped is a garbage-status row) vs `task_stats.log` pass 1,037 (the 43 delta = `stage(higher-tier)` / other `pushed*` variants that the legacy log buckets differently). Per repo the two differ by 2-11 (billwatch 197 vs 186, iptv_apps 152 vs 129+13 under the spelling `iptv-apps`/`iptv_apps`, xlite 136 vs 133) - same direction, not an exact match; I did not reconcile the remainder row by row.
* Last 14 days: 1,976 landed records, 1,404 features, 796 mature. Events: 2 reverts (both real), 100 strong hotfix, 242 weak hotfix, 3 emergency (repo-level), 23 test-watch (repo-level; 3 attributed). Escaped features: strong 44 (5.5 per 100), any 109 (13.7 per 100).
* Precision, judged by reading each sampled flag (subject of the landed item vs subject of the fix):
  * Strong hotfix (final rule, 20 random of 100): 18 real (duplicate test/function definitions, missing imports, SyntaxError, restored vendored file, orphan duplicate script), 2 not escapes (a pre-existing-regression fix, an ambiguous test rewrite) = ~90%, n=20 (wide interval).
  * Weak hotfix (12 sampled from an earlier rule version, same weak definition): ~4 real = ~33%. This is why it is reported separately and never in the headline.
  * Earlier rule versions I rejected after reading flags: "any later fix on the same file attributed to every record" (1,796 events, ~5x inflated), "non-pipeline fix on same file counts as strong" (1/9 real), and counting the pipeline's own `repair staged item` loop (all false).
  * Reverts 2/2 real. Test-watch attributed 3/3 plausible (same test files the red suite named) but tiny n.
* Weak-oracle share is only measurable for 560 of 1,976 records (28%): item text is looked up in the CURRENT OVERNIGHT_PROGRESS.md and many items have been archived or rewritten. Of those 560, 67.5% have existence-only VERIFY.
* Commit attribution quality (14 random tagged records read by eye): ~9 clean, ~4-5 carry an unrelated neighbouring commit (the time window cannot separate commits made by concurrent lanes: fleet, interactive session, reconcile). It is an attribution, not a join key.

## Known limitations / blind spots (read before trusting a number)

* **No prod telemetry.** Escapes are only what shows up in git (revert, fix, EMERGENCY item) or what Mark marks by hand. Every rate is a LOWER BOUND; silent bugs, bugs fixed in a PR title that does not say "fix", and anything found only in prod are invisible. Mark-reported bugs need `mark-escape` or they do not exist for the ledger.
* **Outcomes have no sha.** Attribution is by time (see above); two lanes committing in the same window can swap commits. `commit_basis=none` records (18% here) can never get file-overlap events (only manual ones attach to them via the SHA owner or files).
* **Hotfix is a heuristic.** A repair-style fix on a shared file shortly after a landing is not proof the landing caused it (strong precision ~90% on n=20, weak ~33%). Same-feature continuations are excluded by `feat_tag`; untagged continuations are not.
* **EMERGENCY events are mostly unattributable** (16 of 19 test-watch events and all 3 deploy emergencies had no record with file overlap): the error excerpt rarely names the file the landing touched. They are reported as repo-level counts.
* **Escape window is 7 days (hotfix/emergency) / 14 days (revert)**; a record is rescanned only while younger than `--rescan-days` (15). Later problems are missed. Reverted-before-landing outcomes (`reverted(build-break)`, `no-op(reverted-red)`) are NOT escapes: they never landed.
* **Human and interactive-session commits are not ledger rows.** They only appear as fix/revert evidence or in the "unattributed" line of a promote card.
* **Branch coverage depends on the clone being fetched.** The tool never fetches (read-only); a stale clone under-reports. The box clones are fetched by the pipeline; Mac clones may lag.
* **Weak-oracle** is a regex on the VERIFY command (runner words: pytest, npm test, tsc, gradle, `.sh`, curl, alembic ...). A `python -c` assertion counts as a runner-less (weak) command only if it also lacks those words; `grep -q ... && echo PASS` is weak by design.
* Risk class is path-word based: a file named `token_utils.py` is A even if it handles CSRF-irrelevant tokens; renamed-but-sensitive files (`gate.py`) are B.
* `type` in the report is the outcome's `type` field (today always `aider_fix`), so the by-type table is currently one row.
* The cron wrapper does not fetch, notify or alert; if it cannot run it logs and exits 0 (check `logs/qa_ledger_cron.log` age).

## Integration notes (for the integrator)

Nothing here is wired. To enable: deploy `qa/` to `~/overnight-queue/qa/` by atomic `mv`, add the cron line above (hourly is plenty; the pass takes ~1-4 s), register `scripts/test/test_qa_ledger.sh` in `run_all.sh`.
`state/qa_shadow/*.jsonl` is only READ here (any `ref` that is a >=7-char commit sha prefix of one of the feature's commits, or the promote `--to` sha, binds a gate record to a feature) - gate builders should log the head sha as `ref`.

## Hardening round (review fixes) - false confidence removed

* **Poison rows can no longer freeze the ledger.** Every `outcomes.jsonl` row is validated (`clean_outcome`): non-dict rows, non-string `status`/`repo`/`ts`, list/dict `repo`, unsafe repo names (path separators, leading `-`/`.`) are rejected; dict/list typed optional fields (`feat_tag`, `item_hash`, `tier`, `duration_s`, ...) are coerced. Each row is also built inside its own try/except, and the event scan is isolated, so the cursor always advances.
* **Skipped rows are reported, never silent.** `derive` returns `FLAG` (not `PASS`) with `details.skipped_rows` (bad_json + malformed_rows + failed_rows) whenever it could not read something, and `FLAG` with `event_scan_error` if the event scan crashed (escape events were then NOT updated). On the real 16,353-row replay this surfaces 4 unparseable lines once.
* `qa_scorecard report` guards its own outcomes reader the same way and prints `WARNING: N outcomes.jsonl line(s) were unreadable`; hostile `qa_shadow` rows are skipped and an unreadable gate verdict becomes `UNVERIFIED`, never `PASS`.
* Ledger lines read back from disk are shape-checked (`valid_rec`/`valid_event`); corrupt lines are skipped.
* `mark-escape`: `--repo` must be a plain name; `--ref` may not start with `-` or contain whitespace (checked before git runs). An escape that attaches to no landed record returns `FLAG` ("no scorecard will show it") instead of `PASS`.
* The clean `escape` cell says "lower bound ... NOT proof of no escape" and is printed on the card. A clean card means only that no git evidence was found.
* Still true after the fix (reviewer notes, unchanged): attribution is by time window (about a third of read records carried a neighbouring commit, 22% have no commits), weak hotfix precision ~33% (n=12), test-watch n=3, item-text lookup works for 28% of records. The wrapper alerts nobody; check `logs/qa_ledger_cron.log` for `FLAG`/`UNVERIFIED` verdicts.
* Replay re-run after the fix (box data copy, scratch, 16,353 rows): 3,707 landed (unchanged), 2,873 with commits (unchanged), derive 2.6 s, incremental 0.9 s; the 4 bad-json lines now yield FLAG. 14d report: 1,958 records, 791 mature, strong 45 (5.7/100), any 110 (13.9/100) - drift vs the earlier numbers is the window moving by hours plus new landings, not a logic change.
