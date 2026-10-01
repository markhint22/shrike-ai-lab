# qa/baseline_verify.py - baseline-relative full-suite verification (gate S4, key `baseline`)

Library + CLI. NOT wired into any runner (see `qa/patches/staged_verify_baseline.md` for the shadow-mode wiring patch).

## Why

`ovn_stage_runner.sh full_verify()` needs the WHOLE suite green. One pre-existing red test (e.g. the TAA stale-pricing tests,
01:12-07:00 on 2026-10-01) makes every staged step `stage-unverified` and discards finished work. This gate stores the repo's red
test-id set and answers "did THIS change add any NEW failure?" instead.

## What it decides

| result | meaning |
|---|---|
| `PASS` | no new failing ids (pre-existing red tolerated, listed under `preexisting`; `fixed` = baseline ids now passing) |
| `FAIL` | at least one new failing id, OR a non-baselineable gate failure (`QUALITY FAIL`, `SEMANTIC FAIL`, fail-closed, `bash -n` syntax error, docker build error) |
| `UNVERIFIED` | a would-be PASS where full_verify stages were skipped and apply to the change (see "Skipped stages"); failures present and no baseline / baseline older than 24h; truncated or timed-out log; id count below the summary's failed count; runner said failed but nothing parseable. Never a guess. |

Exit code is always 0 (`qa_common.main_guard`); one JSON line on stdout. This includes bad/missing arguments (argparse is wrapped:
`--bogus`, no subcommand, `--help`, a non-integer `--days` all yield an UNVERIFIED JSON line, never exit 2). Mode via `qa_common.mode("baseline")` (default `shadow`).
`growth` is a separate field: set when the stored red set grew since the last snapshot (pending, un-accepted) or last accepted a growth.

## Commands

```
python3.12 qa/baseline_verify.py snapshot --repo R --failing-file F [--format auto|pytest|vitest|gradle|gut|verify-log|ids]
                                          [--commit SHA] [--source TAG] [--accept-growth]
python3.12 qa/baseline_verify.py compare  --repo R --failing-file F [--format ...] [--base-sha S] [--runner-failed]
                                          [--changed-file P ...] [--changed-files-from FILE] [--strict-overlap] [--worktree DIR]
python3.12 qa/baseline_verify.py refresh  --repo R [--ref origin/overnight/feature] [--timeout 900]   # pytest repos
python3.12 qa/baseline_verify.py show     --repo R
python3.12 qa/baseline_verify.py parse    --failing-file F          # debug: parsed ids / hard failures / completeness
python3.12 qa/baseline_verify.py replay   --logs-dir ~/overnight-queue/state/stage_runs [--days 14] [--out FILE]
```
Always add `--no-record` for ad-hoc/replay use (otherwise one row is appended to `state/qa_shadow/baseline.jsonl`).
State: `$OVN_DIR/state/qa_baselines/verify/<repo>.json` (atomic replace, no locks) and `growth_alerts.jsonl` beside it.
Runs under the Mac `python3` and the box `/usr/bin/python3.12`. Runtime: p50 49 ms / p90 63 ms / max 78 ms per `compare` on the box
over the 150 most recent real verify logs (the 860 KB log included); `refresh` = the repo's suite time (TAA 43 s, shrike-notify 16 s).

## Parsers

* **pytest -q** (also xdist): `FAILED`/`ERROR` node ids from the short summary (bracket-aware, message stripped). Incomplete if there
  is no final `N passed/failed in Xs` line (timeout cut mid-progress-bar - this is what the old 300s cap produced) or fewer ids than the
  summary's failed+error count.
* **vitest**: `FAIL file > suite > name` and file-level `FAIL file [ file ]`; incomplete without a `Test Files` line.
* **gradle** (a `BUILD FAILED` with no parseable failing id is INCOMPLETE, never "no failing tests"): failed test methods (`Class > test FAILED`), failed tasks (`task:app:compile...`), and one `kotlinc:<file>` id per source
  file with a compiler error (no line numbers, `/tmp/stage-*` stripped) so a compile error in a NEW file is a new failure even though the
  coarse task id is already red; likewise `javac:<file>` for `File.java:N: error:` and the legacy `e: /p.kt: (l, c)` Kotlin format.
  Incomplete without `BUILD SUCCESSFUL/FAILED`.
* **pytest** also treats `INTERNALERROR>` as incomplete. An empty / unrecognisable verify-log is incomplete (so UNVERIFIED even without `--runner-failed`).
* **Redaction (hard rule 5)**: every id/hard string is passed through `redact()` before it is stored or printed: URL credentials, `password|secret|token|api_key|auth...=value`,
  `Bearer ...`, `sk-/ghp_/xox..` keys, AWS keys, JWTs and long mixed alphanumeric blobs (>=32 chars) become `***`. Applied identically at snapshot and compare time.
* **GUT**: `res://file.gd::test` from the Run Summary block, `godot-parse:` / `godot-load:` ids; incomplete without `---- Totals ----`.
* **verify-log** (the staged runner's `<run>.verify.log`): splits the `-- pytest FULL in <pkg> --` / `gradlew` / `GUT` / `vitest` / `docker`
  sections, prefixes ids with `[<pkg>]`, and collects the hard failures above.
* **ids**: plain id list, accepted for snapshots ONLY with `--source deterministic:<tool>`.

## Hard rules baked in

* Only deterministic code writes baselines: snapshot input must be a COMPLETE parse of a real run log with no hard failures; truncated /
  timed-out / quality-failed logs are refused; hand-fed id lists need a `deterministic:` source tag. Nothing here calls an LLM.
* Never auto-widen: new ids vs the active baseline => baseline unchanged, `pending_growth` stored, `growth_alerts.jsonl` row, `compare`
  shows `GROWTH ALERT`. Widening needs `--accept-growth`. Shrinking (tests got fixed) is accepted automatically. A fresh snapshot over
  `OVN_QA_BASELINE_MAX` (default 300) ids is refused (mostly-red suite: look at it).
* 24h expiry (`OVN_QA_BASELINE_TTL_S`, default 86400), checked at compare time; expired == missing. Replacing an EXPIRED baseline with a larger
  red set is logged to `growth_alerts.jsonl` as `growth_accepted_after_expiry` (snapshot status `stored_fresh_grown`), so waiting out the TTL is not a silent widen.
* No locks, no repo writes (refresh uses `qa_common.worktree`, removed afterwards), nothing outside `state/qa_baselines/` and `state/qa_shadow/`.
* `--base-sha`: if given and the baseline commit is known, a non-ancestor baseline commit adds a `warning` (details only).

## Skipped stages (no false-confidence PASS)

`full_verify()` runs gradle, GUT, vitest, the `bash -n` shell scan and docker build only `if vok=1`, so after the first failing stage (typically a
pre-existing pytest red) those stages never run and the log cannot show them failing. `parse_verify_log` records `first_failed_stage` and
`skipped_stages` (runner order: pytest, gradle, gut, vitest, shell, docker; after a gradle failure further gradle projects count as skipped).
Before returning PASS, `compare` calls `skipped_stage_check`:

* changed files unknown (no `--changed-file/--changed-files-from`) while stages were skipped -> **UNVERIFIED**;
* a skipped stage applies to a changed file (`.kt/.java/.gradle` -> gradle; `.gd/.tscn/project.godot` -> GUT; `.js/.ts/.vue/.json` -> vitest;
  `Dockerfile*` -> docker) -> **UNVERIFIED** (this gate cannot run those builds);
* skipped shell stage: `bash -n` is run here on every changed `*.sh` that exists under `--worktree` (syntax error -> **FAIL**; file unreadable -> UNVERIFIED);
* otherwise (e.g. a Python-only change) PASS, with `details.skipped_stages` listing what did not run. Enforce wiring must pass
  `--changed-files-from` and `--worktree` (the patch helper does) and should use `--strict-overlap` initially.

## Masked-risk note (important limitation)

Id-set comparison cannot see a change that makes an ALREADY-red test worse (same id, different failure). `compare` therefore reports
`details.masked_risk` = pre-existing red ids that look related to the files the change touched (test file edited, test stem ~ source stem,
migration test vs alembic edit, `kotlinc:` same file, gradle task vs edit under that module). Default: PASS with `[RISK ...]` in the summary;
`--strict-overlap` turns it into UNVERIFIED.

## Replay results (real data, 2026-09-07..2026-10-01, box `state/stage_runs`)

See the final report / numbers below (reproduce: `replay --logs-dir ~/overnight-queue/state/stage_runs --days 14 --no-record`).

**Re-measured after the fix round (same box logs, same 14 days; 907 runs now)** - the skipped-stage rule and the stricter gradle parser change the
numbers slightly: classes 70 quality/semantic-only, 53 test+gate, 19 incomplete (was 17 incomplete + 2 unparsed: two gradle `BUILD FAILED`
logs without ids are now incomplete), 140 test-only. Proxy A 19 PASS (12 clean + 7 overlap-risk) / 43 FAIL / 78 UNVERIFIED (was 21/43/76);
B 12 PASS / 7 / 121 (was 13/7/120); C 29 / 68 / 43 (was 31/68/41). So the honest rescue range is **19-29 of 282 (7-10%)**. The replay's
changed-file lists come from each run's plan, so it understates how often the rule fires in live use when files are unknown; in the live
wiring unknown changed files => UNVERIFIED. The older table below is the pre-fix measurement, kept for history.

Last 14 days (pre-fix): 906 staged runs; 392 were not verified (the "389/901" in the plan); **110 of those never reached `full_verify`** (no step
passed, so there is no verify log and baseline-relative verify cannot matter); 282 reached it and failed:

| class (of the 282) | n | rescuable by baseline-relative verify? |
|---|---|---|
| gate failure only: QUALITY/SEMANTIC FAIL (stub, 0-byte file, no test exercises change, claimed integration absent) | 70 | no, correctly stays FAIL |
| test failures AND a QUALITY/SEMANTIC FAIL | 53 | no, stays FAIL |
| log truncated (pytest cut by the timeout) | 17 | no -> UNVERIFIED |
| no parseable failure | 2 | UNVERIFIED |
| test failures only | 140 | see proxies below |

For the 140 test-failure-only runs, "pre-existing" is PROXIED (no clean-base re-run exists in the logs): the same id failed in another
item's run of the same repo within 24h with no green run in between (A = earlier runs; B = >=2 distinct earlier items; C = earlier or later
runs). Would-be verdict: A: 21 PASS / 43 FAIL / 76 UNVERIFIED; B: 13 / 7 / 120; C: 31 / 68 / 41. So **baseline-relative verify would have
rescued roughly 21-31 of the 282 failed verifies (7-11%) even with a perfect proxy-quality baseline; about 14-19 (5-7%) with no
overlap-risk note**. The 41-76 UNVERIFIED are failures nobody can classify without a real clean-base baseline: with a refreshed baseline
some become PASS, some FAIL. The big structural finding is that 123 of 282 (44%) failed on QUALITY/SEMANTIC guards, not tests, and a
baseline does not touch those.

Largest real pre-existing reds in the window: iptv-android `compileFireTv{Debug,Release}UnitTestKotlin` (24/22 runs; `FavoritesRepositoryTest.kt`
compile error, rescues 13 iptv_apps runs whose steps touched only backend/web/iOS), TAA `test_migration_drift` / `test_llm_service`
(stale pricing, 2026-10-01 01:12-07:00), shrike-monitor notifier/scheduler tests.

## Known limitations

* The replay baseline is a PROXY; real quality depends on `refresh` giving a true clean-base red set. Refresh covers python/pytest repos only;
  gradle/GUT/vitest baselines need `snapshot` from a clean-base run log (no hook exists yet), else those runs stay UNVERIFIED.
* Id equality only: cannot see a pre-existing red test getting worse, flaky tests (a flaky red test that happens to be absent from the
  baseline is a "new failure" -> FAIL; fail-closed), or two different failures under one id.
* A baseline refreshed from `origin/overnight/feature` head includes already-landed fleet work; reds that land between refreshes show as new
  (conservative) until the next refresh.
* `verify.log` holds only the LAST `full_verify` of a run (the file is truncated per call); repair-round outcomes are not separately replayable.
* vitest and GUT parsers are verified against synthetic/excerpted fixtures only (no vitest FULL line exists in any production log; the GUT
  excerpt format is from a real xlite log but only one failing-GUT example was available).
* Not verified: behaviour inside the real `ovn_stage_runner.sh` (not wired); the patch helper was exercised against a fake `$HOME` on the box,
  not inside a live staged run.
