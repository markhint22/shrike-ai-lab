# contract_fuzz - QA-N2: hermetic Schemathesis contract fuzz of the release candidate (SHADOW)

Runtime input-handling evidence that none of the diff-structural Phase 1 gates give: it starts the candidate backend and throws
OpenAPI-derived requests at it, looking for **5xx responses** and **responses that violate their own declared schema** (the class of the
billwatch `/api/alerts` 500-since-May and the civic-router 404 P0s). Nightly, shadow only, **not a hygiene gate** and no enforce path.

    python3 qa/contract_fuzz.py check --repo iptv_apps [--ref origin/develop] [--no-record] [--accept-baseline]

One JSON verdict line on stdout, exit code 0 always. The module is deliberately **not** named `gate_*.py`: `qa_run_shadow.sh` runs every
`gate_*.py` sequentially after every hygiene merge and a fuzz run takes about half a minute to several minutes. `qa_run_shadow.sh` is untouched.

## How it stays hermetic (shared staging, rate limits and outbound fetches are never touched)

1. `qa_common.worktree(repo, ref)`: a detached worktree of the candidate SHA (default `origin/develop`), always removed.
2. The app is started with the **repo's own venv python** (`<clone>/iptv-backend/.venv/bin/python`; absent => `UNVERIFIED no venv`) on
   `127.0.0.1:<free port>`, from the worktree, with a **scrubbed environment**: no ambient secrets, `HOME` = a temp dir, SQLite file DB in a temp dir
   (`DATABASE_URL`), `RATE_LIMIT_ENABLED=false`, dummy JWT/admin/metrics secrets, every outbound-service key (Stripe, SendGrid, TMDB, YouTube, RevenueCat,
   Apple/Google, FCM/APNs, Sentry) blank. This is the repo test suite's own bootstrap (`tests/conftest.py`: SQLite + `Base.metadata.create_all`; the app's
   lifespan runs `init_db()` = `create_all` itself). The launcher refuses to run if `app` was imported from outside the worktree (e.g. an editable install of the live clone).
3. **Outbound guard** (defence in depth, NOT a sandbox): the app runs behind a launcher that, before importing the app, blocks every non-loopback `connect()`,
   `getaddrinfo`/`gethostbyname`, and UDP `sendto`/`sendmsg`, and makes `import aiodns/pycares/uvloop` fail (c-ares and libuv resolve/connect in native code, outside any
   Python-level guard; the first trial run showed aiohttp's c-ares resolver resolving github.io IPs, and uvicorn's default `loop=auto` picks uvloop when the venv has it, which silently
   bypassed every patch: the app is therefore served with `loop="asyncio"`, and the tests prove an `asyncio.open_connection` to `.invalid`/`192.0.2.1` is blocked and counted). Attempts are counted in the
   verdict (`details.blocked_outbound`, `blocked_outbound_hosts`) and the summary says `blocked N outbound attempt(s) (in-process guard; see README for its limits)`. A non-zero
   count means an app code path reaches for the network that is not in the exclude list below: extend the list. The exclude list (item 4) is the primary protection; the guard is Python-level, so native
   extensions with their own sockets would bypass it; verify with `ss -tunap` during a run (the 2026-10-09 acceptance run: 96 samples, no non-loopback socket owned by the app/fuzz processes).
4. Routes that fetch URLs, proxy, send mail or call payment/store APIs are **excluded** from the fuzz (table in `contract_fuzz.py`, `REPOS[...]["exclude_paths"]`);
   the number of excluded operations is in every verdict (`operations_excluded`, and `excluded N/M ops` in the summary) and is cross-checked against what
   schemathesis itself dropped (`details.exclude_count_mismatch` appears only when they disagree).
5. `finally`: the app and the schemathesis process groups are killed (TERM, then KILL) and the temp dirs removed; the worktree is removed by `qa_common`.
   A SIGTERM to the fuzzer (cron timeout) is turned into the same cleanup.

## What is fuzzed

`schemathesis` from `~/qa-venv` (4.28.0): `--seed 42` (4.x has `--seed`, not `--hypothesis-seed`), `--generation-deterministic --no-shrink`, `-n 25`, `-w 1`,
`--phases examples,fuzzing` (no coverage/stateful phase), `--mode all`, `--checks not_a_server_error,response_schema_conformance` only (no
`negative_data_rejection`, no `ignored_auth`), `--request-timeout 15`, `nice -n 15` (+ `ionice -c3`, `QA_CPUSET` when set). One throwaway user is registered
and logged in on the ephemeral DB; its bearer token reaches schemathesis through a 0600 `--config-file` (`headers = { Authorization = "Bearer ${FUZZ_TOKEN}" }`) and the `FUZZ_TOKEN`
environment variable, never argv (argv is visible to every user in `ps`). `details.argv` records the command line that really ran (redacted) and the baseline fingerprint hashes exactly those flags,
so changing the seed, `-n`, `-w`, phases, checks, mode, request timeout or excludes makes an old baseline `UNVERIFIED` (re-accept) instead of a noisy comparison.

**Transient network errors.** The box is shared with the fleet (load of 10-16 was seen), so a lone `[network_error] ReadTimeout|ConnectTimeout|ConnectionError` can be a CPU spike. Those operations are
re-run once (`--include-name-regex`, same seed, same app). A signature that does not repeat is not a signature: it is listed in `details.transient_network_errors` (with a count) and the verdict ignores it.
One that repeats stays a signature. 5xx and schema findings are never re-checked away. Too little wall-cap left, or an incomplete re-run => the errors stay signatures (conservative). Same code + same seed + a fresh DB => the same signature set
(verified: 3 consecutive real runs on develop 67ed0626 gave the identical 33 signatures; ~35 s each).

### Excluded-route policy (iptv_apps)

| pattern | why |
|---|---|
| `^/api/streams/import*`, `/relay`, `/{stream_id}/proxy`, `/{stream_id}/check`, `/sources/{id}/refresh` | fetch caller-supplied or stored URLs (SSRF surface) |
| `^/api/epg/sources/{id}/(refresh\|auto-map)` | fetch an XMLTV URL |
| `^/api/discover/` | fetch the remote iptv-org catalog / YouTube (inside the sandbox they answered 502 because the guard refused the connect: pure artifact) |
| `^/api/admin/youtube`, `/api/content/identify` | YouTube / TMDB lookups |
| `^/api/subscription/(apple\|google)/`, `stripe/(checkout\|portal)`, `/cancel` | store / payment API calls |
| `/api/auth/password/forgot`, `resend-verification-email`, `/api/feedback` | send mail |
| `DELETE /api/account/me`, `PATCH /api/auth/email` | would delete / re-key the throwaway user whose token the run uses |

Rule for adding to the list: if a route can open a socket to anything but the app's own DB, exclude it and say why. Prefer a precise regex over a prefix.
Everything else, including inbound webhooks, is fuzzed.

## Verdicts

| verdict | when |
|---|---|
| `PASS` | run completed and no signature outside the accepted baseline. `fixed` signatures (in the baseline, gone now) are listed in `details.fixed`. Also the verdict of the `--accept-baseline` run itself (summary `baseline accepted`) |
| `FLAG` | `no baseline: N signatures observed` (first run), or `N new signature(s) vs baseline: ...` (`details.new`, up to 10). Never FAIL: shadow |
| `NA` | repo not configured (everything except `iptv_apps` for now) or `OVN_CONTRACT_FUZZ=off` |
| `UNVERIFIED` | could not judge: no clone / no venv / schemathesis missing / unresolvable ref / app failed to start (redacted log tail) / app died during the fuzz / auth bootstrap failed / timeout (`OVN_FUZZ_TIMEOUT_S`, default 600, total wall clock) / schemathesis crashed or did not complete / baseline recorded with different fuzz parameters |

Shadow rows go to `state/qa_shadow/contract_fuzz.jsonl` (first-run rows carry the full signature list in `details.signatures`, capped at 300).

## Baseline procedure (human step)

The baseline `state/qa_shadow/contract_fuzz_baseline_<repo>.json` is written **only** by `--accept-baseline` (atomic write), never by a plain run.

1. First run, manual: `python3 qa/contract_fuzz.py check --repo iptv_apps --ref origin/develop` => `FLAG no baseline: N signatures observed`.
2. Read the signatures (below). **Real 5xx are bugs for the Claude queue; do not accept them blindly**: triage first. Accept what is understood or already ticketed
   (e.g. the fail-closed RevenueCat webhook 503, naive-datetime `date-time` schema findings).
3. `python3 qa/contract_fuzz.py check --repo iptv_apps --ref origin/develop --accept-baseline` records exactly what that run observed.
4. From then on the nightly run says `PASS` or `FLAG new signature(s)`. Fixing a bug shows up as `fixed`; re-accept occasionally to drop fixed entries.
5. The baseline stores a fingerprint of seed, `-n`, checks, phases, mode, the exclude list and the schemathesis version. Changing any of them (including editing
   the exclude table or upgrading schemathesis) makes the next run `UNVERIFIED ... different fuzz parameters`: review, then re-accept. (Env tunables: `OVN_FUZZ_SEED`,
   `OVN_FUZZ_MAX_EXAMPLES`, `OVN_FUZZ_MODE`.)

## Reading a signature

`METHOD /path/template [check] class`:

* `GET /api/settings [not_a_server_error] 500`: the server answered 500 to a generated request (class = HTTP status). 503 counts too (`... webhook [not_a_server_error] 503`).
* `GET /api/auth/me [response_schema_conformance] JsonSchemaError@200`: the 200 response does not match the schema the OpenAPI document promises (class = failure type `@` response status).
  Typical on this repo: `created_at` serialised as a naive datetime where the schema says `date-time`; 422 bodies that are not the declared validation-error shape.
* `GET /slow [network_error] ReadTimeout`: the request raised instead of answering (server-indicative types only: timeouts, resets, protocol errors). Client-side failures
  (the HTTP library refusing to send a generated header/URL, e.g. `InvalidHeader`) are only counted in `details.client_side_errors`.

Signatures never contain bodies, headers, tokens or messages. To see the failing request for a signature, rerun with `OVN_FUZZ_KEEP_REPORT=/some/private/file.ndjson`
(the raw report: it holds generated request bodies; keep it private and delete it) and read the `ScenarioFinished` events. Note several 500s only appear after earlier
generated requests changed state (e.g. a `PUT /api/settings` with odd data makes a later `GET /api/settings` 500); a bare `curl` of the route on a fresh app returns 200.

First observed on develop `67ed0626` (2026-10-09, `--no-record`, nothing accepted): 33 signatures = 10 server-error ones
(`POST /api/epg/mappings`, `PUT|GET /api/settings`, `GET /api/content/vod`, `GET /api/epg/reminders`, `GET /api/subscription/billing-history?page=<huge int>`,
`GET /api/analytics/content/<huge int>`, `DELETE /api/streams/session/0`, `POST /api/streams/bulk` all 500; `POST /api/subscription/revenuecat/webhook` 503 = fail-closed without a secret)
and 23 schema-conformance ones.

## Operating it

* Cron (box; **not installed**, install after the first manual run and a reviewed `--accept-baseline`):
  `20 4 * * * cd ~/overnight-queue && bash qa/contract_fuzz_cron.sh >> logs/contract_fuzz.log 2>&1`. CPU only (nice 15), no GPU.
* `qa/contract_fuzz_cron.sh`: `flock -n state/contract_fuzz.lock`, skips when `state/PAUSED` exists or the 1-min load average is above `OVN_FUZZ_LOAD_MAX` (6), appends one
  summary line per repo to `logs/contract_fuzz.log`, always exits 0. Kill switch `OVN_CONTRACT_FUZZ=off`. `OVN_FUZZ_REPOS` (default `iptv_apps`), `OVN_FUZZ_REF`, `OVN_FUZZ_TIMEOUT_S`.
* Other env: `OVN_FUZZ_SCHEMATHESIS` (binary, default `~/qa-venv/bin/schemathesis`), `OVN_FUZZ_START_TIMEOUT_S` (60), `OVN_FUZZ_REQUEST_TIMEOUT_S` (15),
  `OVN_FUZZ_CONFIG_JSON` (a JSON file adding/overriding repo entries, used by the tests), `OVN_FUZZ_KEEP_REPORT`.
* Adding a repo: add an entry to `REPOS` (app dir, venv candidates, `module:app`, env, auth bootstrap, exclude list). Audit its outbound routes first.
* Shadow for at least 14 nightly runs before any discussion of enforcement; there is no enforce path in this package.
* Tests: `scripts/test/test_contract_fuzz.py` (fixtures in `scripts/test/fixtures/contract_fuzz/`, regenerate with `OVN_TEST_GEN_FIXTURES=<dir>`). Box only for the stub-app cases:
  needs `~/qa-venv/bin/schemathesis` and a python with fastapi+uvicorn for the stub (the iptv_apps repo venv is used; `~/qa-venv` has no fastapi). Without them it prints
  `SKIP: <module> missing` and exits 0, unless `OVN_REQUIRE_QA_VENV` is set.
