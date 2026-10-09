# gate_migrations (S6) - Postgres migration + OpenAPI gate, with prod-shaped data

Answers one question per commit: *"if this diff reaches a real Postgres that already holds data, do migrations still apply,
does the schema still match the models, and did we silently break the API contract?"*

It exists because the checks that ran before it were all SQLite / empty-DB / static:
billwatch's 2026-09-14 prod 500 was model/DB drift against live data, iptv_apps' migration chain cannot even run on Postgres
(see "Real catches"), and test-automation-agent's `entrypoint.sh` swallows a failed `alembic upgrade` and falls back to `create_all()`.

## Files

| file | role |
|---|---|
| `qa/gate_migrations.py` | the gate (CLI contract from `docs/QA_GATES_SPEC.md`), stdlib only |
| `qa/prodshape.py` | prod-SHAPED synthetic data from STATISTICS; `collect` gathers the statistics over a read-only connection |
| `qa/_migr_helper.py` | the only code that imports a repo's backend; runs under the repo's own venv (`heads`, `upgrade`, `downgrade`, `diffs`, `openapi`) |
| `qa/qa_repos.json` | registry: backend dir, alembic.ini, venv, DB URL flavour, OpenAPI module, notes, per repo |
| `qa/replay_migrations.py` | replays the gate over the last N commits touching models/migrations (path-selected, unlike `qa_replay.py`) |
| `scripts/test/test_qa_migrations.{sh,py}` | tests: unit + real-postgres integration scenarios with negative/benign controls |
| `scripts/test/fixtures_qa_migrations/*.stats.json` | hand-written stats fixtures (`fx` for the tests, `billwatch` as a realistic example) |

## Run

    python3 qa/gate_migrations.py check --repo billwatch --base origin/develop~5 --head origin/develop [--no-record] [--enforce-exit]
        [--prodshape auto|off|stress] [--stats FILE] [--no-openapi] [--breaking-verdict FLAG|FAIL] [--budget SECONDS]

Prints ONE JSON line (the `qa_common.verdict` dict; `details.steps[]` has one entry per step, `details.timings_ms` the cost).
Works under `/usr/bin/python3.12` (box) and the Mac `python3` (3.14). Needs: a docker daemon with `postgres:16` already pulled
(no network), and the clone's own `.venv` (symlinked into a detached worktree, never committed).
Mode comes from `qa_common.mode("migrations")` (default **shadow**; env `OVN_QA_MIGRATIONS`; `off` => NA before anything starts).
`qa/qa_run_shadow.sh` runs it only for repos registered in `qa/qa_repos.json` (the four with alembic); other repos are skipped, not logged as NA.

    python3 qa/replay_migrations.py billwatch --n 20 --paths models|api|both [--extra "--prodshape stress"]
    python3 qa/prodshape.py collect --repo billwatch          # QA_STATS_DATABASE_URL=... (read replica!) -> state/qa_prodshape/billwatch.stats.json
    python3 qa/prodshape.py describe --stats FILE

## What it checks (steps)

Diff relevance first: only `.py/.ini/.mako` changes under the repo's backend dir, excluding `tests/ docs/ scripts/ htmlcov/`, count.
Nothing relevant => verdict **NA** (no container is started). Then, against ONE throwaway `postgres:16` container
(`qa-pg-<pid>`, `127.0.0.1` random port, tmpfs, `fsync=off`, 2 CPUs, always removed):

1. **heads** - alembic can load the scripts; exactly one head (multiple heads: FAIL, or FLAG if base already had them).
2. **upgrade_empty** - `alembic upgrade head` on an empty database. Failing at head but not at base: FAIL. Also failing at base
   (the chain is broken independent of this diff, so nothing else about it can be checked): UNVERIFIED, recorded under
   `details.standing`. A revision id > 32 chars (Postgres-only) is FAIL when NEW in this diff; when already at base the chain is run
   with `version_num` widened, the step is PASS with a "standing" note and the remaining steps run. Repo code that cannot even
   import here (also at base): UNVERIFIED.
3. **drift** - alembic-check equivalent with `compare_type=True` and `compare_server_default=True` (forced by the helper, regardless
   of the repo's env.py), returned as structured diffs. Only drift that is NEW relative to base counts (set difference on a stable key:
   op|table|name|detail); table/column/type/nullable/constraint/FK drift => FAIL, index/server-default/comment-only => FLAG.
   Pre-existing drift is reported in `details` (`preexisting`, `preexisting_sample`) but is not a finding. If the base itself cannot be
   upgraded, the baseline is taken from the nearest buildable ancestor (`base~1` .. `base~5`, `QA_DRIFT_ANCESTOR_TRIES`); new drift
   against an ancestor baseline is at most FLAG (it can mis-attribute drift that landed in between). No buildable baseline at all:
   UNVERIFIED "cannot attribute" (this used to FLAG every head drift item).
4. **roundtrip** - `downgrade -1` then `upgrade head`; only when the diff adds/changes a file under `alembic/versions/`.
5. **prodshape** - only when the diff adds a migration AND there is data to shape (stats file, or `--prodshape stress`): build the
   BASE schema in a fresh DB, load the synthetic dataset, then run the HEAD `alembic upgrade head` on top. FAIL if that breaks while the
   empty-DB upgrade passed (e.g. new NOT NULL / UNIQUE / FK / narrower type vs nulls, duplicates, long text). UNVERIFIED if the data could
   not be fully loaded (never a PASS on partial evidence).
6. **openapi** - `app.openapi()` at base and head (via the repo venv), diffed. BREAKING = removed path/method, removed 2xx status/body,
   removed/newly-required request field or parameter, removed request enum value, type change (request narrowing / response change),
   response field removed or became nullable. Resolves `$ref`/`allOf`/`anyOf`, cycle-safe. Breaking => **FLAG** by default
   (`--breaking-verdict FAIL` escalates; deliberate removals are legitimate, a human or the integrator decides); additive => PASS.

Overall: any FAIL => FAIL; else any FLAG => FLAG; else any UNVERIFIED => UNVERIFIED; else PASS (NA steps ignored). The summary line
names the offending steps; wording is "evidence found", never "verified correct".

## prodshape: how the synthetic data is made (statistics only)

Stats file (`state/qa_prodshape/<repo>.stats.json`, version 1): per table `rows`; per column `null_frac`, `distinct`, `max_len`
(`dup_count` informational). The loader introspects the real BASE schema (types, enums, PK/unique, FKs, defaults) and emits
`INSERT ... SELECT ... FROM generate_series` per table in FK order: nulls spread deterministically at `null_frac` (nullable columns
only), `distinct` values cycled (=> exactly the stated duplicates, except where the base schema already has UNIQUE/PK), one value of
length `max_len` per text column, enum values from the real labels, FK values sampled from loaded parents, serial PKs left to the
database. Row counts are capped (`QA_PRODSHAPE_MAX_ROWS`, default 50000/table). FK/triggers are bypassed during the load
(`session_replication_role=replica`); the data still honours FKs by construction. Tables/columns missing at the base schema are
ignored and listed.

`collect` (run by an operator against a replica/snapshot - **this build never ran it against production or staging**): reads
`QA_STATS_DATABASE_URL` from the environment only, converts it into libpq env vars (no secret in argv, never printed, error text
redacted), forces `default_transaction_read_only=on`, wraps every statement in `BEGIN READ ONLY`, refuses to run unless
`SHOW transaction_read_only` is `on`, and selects only `count(*)`, null counts, `count(distinct)` and `max(length())` - never a value.
Uses local `psql` or, if absent, `docker run postgres:16 psql --network host`.
`--prodshape stress` builds a clearly labelled worst-case profile from the schema alone (25% nulls, 50% duplicates, long text): it
answers "does this migration survive hostile data", not "does it survive prod".

## Hard-rule compliance (docs/QA_GATES_SPEC.md)

shadow default; UNVERIFIED (exit 0) on no docker / no venv / container start failure / timeout / budget exhausted / app cannot import
at base; repos read only through detached worktrees (always removed), venv symlinked, nothing committed; no locks (nice/ionice via
`qa_common.cpu_prefix`, plus a per-step and a total `--budget`, default `QA_GATE_TIMEOUT-120` = 780s: it must stay under the shadow runner's 900s SIGKILL cap so a slow run answers UNVERIFIED and removes its container instead of dying silently); repo code runs with a SCRUBBED environment (PATH, HOME,
`DATABASE_URL` for the throwaway container, proxies pointed at a dead port) - ambient secrets and `.env` files are never visible, and
output goes through a URL scrubber; real-entry-point tests under `env -i` with abs and relative paths and `NTFY_SERVER` set.
Container hygiene: removed in `finally`, `atexit` and on SIGTERM; a SIGKILLed run's orphan (`qa-pg-<deadpid>`) is reaped by the next run.

## Known limitations

- Needs a daemon: on the Mac without Docker running every relevant diff is UNVERIFIED (tests assert that).
- "No network" for backend code is by scrubbed env + dead proxy, not by a network namespace: the container's published port is on
  host loopback so a netns would cut the DB too. The repos' import/migration paths make no outbound calls in the replays.
- The repo's venv is shared across base/head: a commit that changes `requirements*.txt` is tested against the clone's existing venv.
- Only the last migration is round-tripped; the data-migration *result* (values) is not asserted, only that it runs.
- Composite foreign keys are not modelled by the loader (each column is generated independently; FK enforcement is off during load).
  Composite UNIQUE: the last column is made unique. Column-level CHECK constraints are not modelled: a table whose CHECK rejects the
  synthetic values is reported as a load failure (UNVERIFIED), never a pass.
- Drift is judged against the base commit's drift; if base cannot be built, drift is reported as FLAG without attribution.
- OpenAPI diff is structural (path/schema level); it does not understand semantic changes (changed meaning, auth, pagination defaults).
- Real prod statistics do not exist yet: until an operator runs `collect`, the `prodshape` step is NA unless `--prodshape stress`.

## Measured

### 2026-10-02 (GPU box, shadow, no stats file; last 15 `origin/develop` commits per repo; one gate run per commit, base = commit^)

Selected by path (`qa/replay_migrations.py <repo> --n 15 --paths models|api`): `models` = commits touching models or alembic, `api` = commits
touching schemas/routers. 60 runs each. Box was running the dev loop at the same time, so runtimes are pessimistic.

**models/migrations set, before vs after the attribution fixes made in this review** (PASS / FLAG / FAIL / UNVERIFIED)

| repo | as first built (2026-10-01 policy) | now |
|---|---|---|
| billwatch | 12 / 2 / 1 / 0 | 12 / 2 / 1 / 0 |
| gitlark | 4 / 5 / 6 / 0 | 6 / 2 / 6 / 1 |
| iptv_apps | 2 / 10 / 3 / 0 | 10 / 1 / 3 / 1 |
| test-automation-agent | 5 / 10 / 0 / 0 | 5 / 2 / 0 / 8 |
| **total (60)** | **23 / 27 / 10 / 0** | **33 / 7 / 10 / 10** |

Runtime (now), p50 / p90 / max: billwatch 15.7 / 19.8 / 20.9 s, gitlark 12.9 / 17.9 / 18.3 s, iptv_apps 18.0 / 21.6 / 23.6 s,
test-automation-agent 6.0 / 10.4 / 10.6 s.

**api set** (schemas/routers commits): billwatch 13/0/1/1, gitlark 15/0/0/0, iptv_apps 15/0/0/0, test-automation-agent 13/0/1/1
(p50 8-18 s). Both FAILs are real import breakage at that commit (missing schema, circular import).

Every non-PASS was read against the commit. Classification:

*As first built:* 37 alerts (27 FLAG + 10 FAIL). 22 were the same STANDING condition re-reported on commits that did not cause it
(gitlark 5: ~94 pre-existing UUID-vs-VARCHAR(36) drift items with "base comparison unavailable"; iptv_apps 9: one pre-existing >32-char revision
id; test-automation-agent 8: a chain that already failed at base) and 1 was a false positive (below) => about **62% noise** (23/37).

*Now:* 17 alerts (7 FLAG + 10 FAIL), 10 UNVERIFIED (not alerts), 33 PASS.
- FAIL x10: 9 true (gitlark: two heads, empty migration stub without a revision id, 3x upgrade fails on Postgres with FK/type cast, model FK
  with no migration; iptv_apps: model with no migration, NEW >32-char revision id, app import broken at head) and **1 false positive**:
  billwatch 079aad4bec. At that commit billwatch's `alembic/env.py` imported only `app.database.Base`, not the models, so alembic's metadata
  was nearly empty and every table looked like drift (29 of the 32 items were pre-existing for that reason). The finding is accurate about
  what alembic sees at that commit and wrong about model/DB agreement; current env.py (`import app.main`) does not have the problem.
- FLAG x7: 3 true (downgrade then upgrade fails: enum type not dropped by downgrade x2 in test-automation-agent, index/FK dependency in
  billwatch's squash) and 4 `modify_default` drift items (migration has a `server_default`, model does not: billwatch 647a336fdb, gitlark
  84daf5b923 and 0743178589, iptv_apps 3bc4a830a9). Technically correct, low value in practice (Python-side `default=` is idiomatic). Candidate
  to demote or ignore; not changed because it is a policy call. 84daf5b923's baseline was an ancestor (base~3), so its attribution is the weakest.
- UNVERIFIED x10: test-automation-agent 8 (chain broken at base AND head; accurate and standing), gitlark 1 and iptv_apps 1 (drift exists but no
  buildable baseline within 5 ancestors, cannot attribute).
- False-positive rate now: **1 / 17 alerts (6%)**, 1 / 60 runs (1.7%), counting the 4 low-value server_default flags as true. If those 4 are
  counted as noise: 5 / 17 (29%). Small sample (60 + 60 runs, 4 repos, one week of history); treat as indicative. False negatives were not
  measured (no seeded-bug replay on real repos; the fixture-repo tests cover negatives).
- OpenAPI: one real breaking-change detection in 120 runs (gitlark 1f4f6047c5: connector-credentials `id` integer -> string, 4 endpoints, FLAG),
  no false positives seen. Too few examples to say more.

What changed to get there (all attribution, no check was weakened): drift baseline falls back to the nearest buildable ancestor when base cannot
be upgraded (new drift against an ancestor is at most FLAG; none buildable => UNVERIFIED instead of FLAGging every head drift item); a standing
>32-char revision id is PASS-with-note instead of FLAG per commit (a NEW one is still FAIL); a chain already broken at base is UNVERIFIED
instead of FLAG per commit (still recorded under `details.standing`).

Reproduce: `qa/replay_migrations.py <repo> --n 15 --paths models|api` (needs `OVN_REPOS_DIR` pointing at the clones, docker, python3.12).
