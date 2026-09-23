# shrike-monitor — RELEASE-READINESS backlog (27B-friendly), release-blockers FIRST
# TOP blocker: heartbeat monitors never report "down" when overdue (status endpoint uses
# summarize_status for all types). The first 3 items fix that.


# --- refill (2026-09-05): remaining uncovered schema bounds + checker/incident edges ---

# --- refill 2026-09-06: uptime/heartbeat build-out (self-verifying) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Heartbeat dead-man logic, uptime ratio, http status classifier, incident transitions (pure (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Monitor create validation + ping-token-shown-once security {cat: backend; size: S; multifi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-07]: Minimal status page/API for the fleet dashboard to read {cat: backend; size: S; multifile: (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Seed scheduler status baseline from persisted results on restart — currently MonitorSchedu (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-11]: Wire downtime duration into notifier alert bodies — app/utils/duration.py's humanize_secon (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Heartbeat monitors never record down/up CheckResults, leaving uptime_ratio and incident hi (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: Notifier retries hammer shrike-notify with no backoff — app/services/notifier.py's notify_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-13]: GET /health never checks whether MonitorScheduler's background loop is alive — app/main.py (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire heartbeat down/up CheckResults into the actual tick loop — `MonitorScheduler._record_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Notifier alert bodies show raw seconds instead of the existing humanizer — `Notifier.notif (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Expose total downtime duration on monitor status — `app/utils/downtime.py`'s `downtime_sec (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Remove dead/misleading `MonitorResponse` schema — `app/schemas.py:49`'s `MonitorResponse`  (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Heartbeat ping-token comparison is not constant-time — `routers/heartbeat.py:31`'s `ping() (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Fix TypeError crash in MonitorScheduler._maybe_notify's notifier call — `MonitorScheduler. (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire Settings.max_results/max_monitors into the actual Store instance — `Settings.max_resu (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Wire dead sla_met() helper into a real SLA-compliance field — `app/utils/sla_met.py`'s `sl (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete dead duplicate is_overdue() heartbeat helper — `app/services/heartbeat.py`'s `is_ov (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete dead duplicate consecutive_failures(list[bool]) util — `app/utils/consecutive_failu (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-14]: Delete two dead duplicate HTTP-status classifiers — `app/services/checker.py`'s `classify_ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Negative MAX_RESULTS/MAX_MONITORS env var crashes the store on the first write — `Settings (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Three more dead exports in app/services/checker.py never reach production — `determine_inc (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: Entire app/utils/status_streak.py module (3 functions) built and unit-tested but never wir (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-17]: app/utils/alert_key.py's alert_key() dead — Notifier's real dedup mechanism (`Notifier._la (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: app/utils/severity_from_code.py's severity_from_code() dead — `Notifier.notify_transition( (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Two more dead uptime-ratio-family duplicates, on top of the wired app.models.uptime_ratio( (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: parse_comma_separated() dead — duplicates config.py's inline CORS parsing verbatim — `app/ (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Five pure-math utility modules with full test coverage and zero production callers — `clam (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete the still-orphaned `compute_initial_status()` from status_streak.py — unlike its tw (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete the dead event-driven incident state machine `next_state()` in `app/services/incide (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete the dead `humanize_count()` helper in `app/utils/humanize.py` — this pure compact-c (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-18]: Delete the dead `resolve_checker_dependencies()` introspection helper in `app/services/che (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: `app/services/checker.py`'s `probe()` has a whole notifier/status_code-aware notify branch (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: `MonitorPersistence.save_result()` never prunes old rows — the `results` table grows witho (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Three more zero-caller functions in `app/models.py` itself, on top of the checker.py/incid (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: Notifier fires on every single status flip with no consecutive-failure debounce, even thou (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-19]: `app/config.py`'s `load_config_from_env()` is fully dead — zero callers anywhere, not even (review + tweak) ---

# --- 27B-decomposed from roadmap [2026-09-20]: Add bearer-token authentication protecting the monitor-management API — confirmed via grep (review + tweak) [feat:shrike-monitor-20260920-add-bearer-token-authentication-protecti] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Add bearer-token authentication protecting the monitor-management API — confirmed via grep (review + tweak) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Two zero-caller orphans left over from the bearer-token work itself, found by direct grep  (review + tweak) [feat:shrike-monitor-20260921-two-zero-caller-orphans-left-over-from-t] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Two more dead time-math helpers in `app/services/scheduler.py`, on top of the already-trac (review + tweak) [feat:shrike-monitor-20260921-two-more-dead-time-math-helpers-in-app-s] ---

# --- 27B-decomposed from roadmap [2026-09-21]: Two independent dead implementations of the same "rows to prune" calculation, neither one  (review + tweak) [feat:shrike-monitor-20260921-two-independent-dead-implementations-of-] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `app/utils/auth.py` is an entirely dead module that also hides a live name-collision bug — (review + tweak) [feat:shrike-monitor-20260921-app-utils-auth-py-is-an-entirely-dead-mo] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `app/main.py`'s `verify_token()` is a dead fourth reimplementation of heartbeat ping-token (review + tweak) [feat:shrike-monitor-20260921-app-main-py-s-verify-token-is-a-dead-fou] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `app/utils/humanize.py`'s `humanize_bytes()` is fully implemented and thoroughly unit-test (review + tweak) [feat:shrike-monitor-20260921-app-utils-humanize-py-s-humanize-bytes-i] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `Store.record_probe()` is a dead convenience wrapper nothing calls — `record_probe(self, m (review + tweak) [feat:shrike-monitor-20260921-store-record-probe-is-a-dead-convenience] ---

# --- 27B-decomposed from roadmap [2026-09-21]: `app/utils/backoff.py` has a dead, unreachable string-literal statement sitting AFTER the  (review + tweak) [feat:shrike-monitor-20260921-app-utils-backoff-py-has-a-dead-unreacha] ---

# --- 27B-decomposed from roadmap [2026-09-22]: `Settings.scheduler_tick_seconds` has no non-positive-value guard, unlike its three siblin (review + tweak) [feat:shrike-monitor-20260922-settings-scheduler-tick-seconds-has-no-n] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: `app/services/checker.py`'s `probe()` has a whole notifier/status_code-aware notify branch that is dead in production (review + tweak) [feat:shrike-monitor-20260922-checker-probe-dead-notifier-branch] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: two dead time-math helpers in `app/services/scheduler.py`, on top of the already-tracked debounce/should_alert item (review + tweak) [feat:shrike-monitor-20260922-scheduler-dead-time-math-helpers] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: two independent dead implementations of the "rows to prune" calculation, neither one actually used by the pruning that ships (review + tweak) [feat:shrike-monitor-20260922-dead-prune-threshold-duplicates] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: four dead pure-math utility modules with full test coverage and zero production callers (review + tweak) [feat:shrike-monitor-20260922-dead-pure-math-utils] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: four more dead single-caller-is-its-own-test functions (worst_status, record_probe, verify_token, duplicate uptime_ratio) (review + tweak) [feat:shrike-monitor-20260922-misc-dead-functions] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: `app/utils/backoff.py` misplaced-docstring bug + `Settings.scheduler_tick_seconds` missing a non-positive-value guard (review + tweak) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: dead `humanize_bytes()` and orphaned `humanize_count.py` (relocated reincarnation of an already-flagged pattern, distinct from the already-queued app/utils/auth.py item) (review + tweak) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: Heartbeat monitors never get a real incident_id, causing Notifier's permanent dedup cache to silently kill all future alerts for that monitor after its first down/up cycle (review + tweak) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: Store.create()'s StoreFull exception is never caught at the API layer — POST /monitors crashes 500 instead of a clean error at capacity (review + tweak) [feat:shrike-monitor-20260922-storefull-exception-handler] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: StatusOut.uptime_percent field exists but is never populated — GET /monitors/{id}/status always returns 0.0 regardless of real uptime (review + tweak) [feat:shrike-monitor-20260922-wire-uptime-percent] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: Settings.service_version unused + GET /health exposes no version field at all (review + tweak) [feat:shrike-monitor-20260922-wire-version-into-health] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: monitor_incidents() docstring stale, still claims heartbeat monitors always return an empty incidents list (review + tweak) [feat:shrike-monitor-20260922-fix-stale-incidents-docstring] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: MonitorScheduler.get_current_incident_id() is a dead public method, zero callers anywhere (review + tweak) [feat:shrike-monitor-20260922-delete-get-current-incident-id] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: downtime_seconds() cannot count an ongoing/current outage — GET /status undercounts downtime for a monitor currently down (review + tweak) [feat:shrike-monitor-20260922-downtime-seconds-ongoing-outage] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: latency_stats() (min/avg/max/p95, fully built + tested + already wired to the correct percentile()) has zero production callers — no endpoint exposes it (review + tweak) [feat:shrike-monitor-20260922-wire-latency-stats] ---

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: app/utils/jitter.py's with_jitter() is dead, zero callers — distinct from backoff.py's own separate ad-hoc jitter reimplementation (review + tweak) [feat:shrike-monitor-20260922-delete-dead-with-jitter] ---
- [ ] [T1] backend/app/utils/jitter.py — Delete this entire module (`with_jitter(base, frac, rand)`); confirmed via grep it has zero callers anywhere outside its own dedicated test file, backend/tests/test_utils.py — `app/services/notifier.py`'s retry backoff uses `app/utils/backoff.py`'s own separate inline jitter implementation instead. VERIFY: `test ! -f backend/app/utils/jitter.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-delete-dead-with-jitter]
- [ ] [T1] backend/tests/test_utils.py — Remove the `with_jitter` import and its three test cases (`test_with_jitter_base`, `test_with_jitter_bounds`, `test_with_jitter_noop`), now that the module is deleted. VERIFY: `! grep -q "with_jitter" backend/tests/test_utils.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-delete-dead-with-jitter]
- [ ] [T1] backend/app/utils/jitter.py — Confirm no other file in the repo still imports the deleted name. VERIFY: `! grep -rn "with_jitter" backend/app backend/tests`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-delete-dead-with-jitter]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: MonitorCreate doesn't validate token/type consistency — a token attached to an http monitor is silently accepted but unusable (review + tweak) [feat:shrike-monitor-20260922-validate-token-type-consistency] ---
- [ ] [T2] backend/app/schemas.py — In `MonitorCreate.check_url_rules()`, add a check that raises `ValueError("token must not be set for http monitors")` when `self.type == "http" and self.token is not None`, matching the existing pattern used for the `url` field's type-consistency checks in the same validator. VERIFY: `grep -n "token must not be set for http" backend/app/schemas.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-validate-token-type-consistency]
- [ ] [T1] backend/tests/test_schemas.py — Add a regression test asserting `MonitorCreate(type="http", url="https://x", token="abc")` raises a `ValidationError` (or `pydantic.ValidationError`, matching this validator's existing raise style). VERIFY: `cd backend && .venv/bin/pytest tests/test_schemas.py -k token_type -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-validate-token-type-consistency]
- [ ] [T1] backend/tests/test_schemas.py — Add a companion regression test confirming `MonitorCreate(type="heartbeat", token="abc")` still succeeds (the new check only rejects http+token, not heartbeat+token, which remains a legitimate use case for supplying a pre-existing ping token). VERIFY: `cd backend && .venv/bin/pytest tests/test_schemas.py -k token_type -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-validate-token-type-consistency]

# --- research pass [2026-09-23]: AGENTS.md + backlog top-of-file note both still claim the heartbeat "never reports down" bug is an open top blocker, but app/routers/monitors.py's status/fleet handlers already call app.models.overall_status(), which dispatches heartbeat monitors through heartbeat_status() — the bug is already fixed in code, only the docs are stale (review + tweak) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]
- [ ] [T1] AGENTS.md — The "Gotchas" section's "Known correctness bug (top backlog item)" paragraph says `/monitors/{id}/status` "uses summarize_status for ALL types, so a heartbeat monitor never reports down when overdue." That is no longer true: `app/routers/monitors.py`'s `monitor_status` and `fleet_status` handlers both call `app.models.overall_status(mon, results, now)`, which dispatches `monitor.type == "heartbeat"` to `heartbeat_status()` and everything else to `summarize_status()`. Update or remove the stale paragraph so it doesn't send future work chasing an already-fixed bug. VERIFY: `grep -n "overall_status" backend/app/routers/monitors.py` (shows the dispatcher already wired) and `grep -c "never reports .down. when overdue" AGENTS.md` returns 0 after the edit. (cat:docs; multifile:no) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]
- [ ] [T1] backend/app/services/checker.py — Delete the dead `generate_ping_token()` duplicate at the bottom of the file (with its out-of-place mid-file `import secrets`). `app/routers/monitors.py` already defines and uses its own separate `generate_ping_token()` for the real ping-token issuance path (`POST /monitors`); the checker.py copy is never imported by any production code — its only callers are its own tests (`tests/test_checker_import.py::test_generate_ping_token_returns_32_char_hex`, `tests/test_core.py::test_generate_ping_token_is_32_char_hex`). Remove the function and update/delete those two tests. VERIFY: `! grep -n "generate_ping_token" backend/app/services/checker.py`. (cat:python; multifile:yes) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]
- [ ] [T1] backend/app/config.py — Delete the dead `Settings.api_token` property (a one-line alias for `monitor_api_token`). Confirmed via grep it has zero callers anywhere in `app/` or `tests/` — `app/auth.py`'s `require_api_token` reads `settings.monitor_api_token` directly and never touches `settings.api_token`. VERIFY: `! grep -rn "\.api_token\b" backend/app backend/tests`. (cat:python; multifile:no) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]
- [ ] [T1] backend/app/utils/uptime.py — Delete this module. Its `uptime_ratio(results: list[CheckResult])` duplicates `app.models.uptime_ratio` (the one function actually wired into every status endpoint via `app/routers/monitors.py`) with an identical signature and body; confirmed via grep it has zero importers anywhere in `app/` (only mentioned in docstring comments in `app/utils/__init__.py` and `app/services/uptime.py`, never actually imported). Also fix the misleading comment in `app/utils/__init__.py`'s module docstring, which claims "app.utils.uptime.uptime_ratio operates on plain counts" — it does not; it takes `CheckResult` objects, same as `app.models.uptime_ratio`. VERIFY: `test ! -f backend/app/utils/uptime.py`. (cat:python; multifile:yes) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]
- [ ] [T2] backend/app/services/uptime.py — This module is a docstring with zero code: it promises "Uptime as a display-ready percentage... returns a rounded 0-100 percentage, meant for direct display" but defines no function at all (0 statements, confirmed via `pytest --cov`). The real percent-display logic already lives inline in `app/routers/monitors.py::_build_status_out` (`uptime_percent = round(up_ratio * 100, 1)`), so this stub is not blocking anything — delete the file (and its docstring's forward-reference from `app/utils/__init__.py`) rather than leaving an unfulfilled promise in the repo map. VERIFY: `test ! -f backend/app/services/uptime.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]
- [ ] [T1] backend/app/routers/heartbeat.py — The `responses=` metadata on `POST /heartbeat/{monitor_id}` (in the `@router.post(...)` decorator) documents only `404` and `400`, but the handler's primary real-world failure mode — a missing or invalid `?token=` — raises `HTTPException(status_code=401, ...)` on the line right below `coerce_token`. The generated OpenAPI schema currently omits this entirely, so API consumers reading `/docs` won't know a 401 is possible. Add a `401: {"description": "Missing or invalid ping token"}` entry to the responses dict. VERIFY: `grep -n "401" backend/app/routers/heartbeat.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]

# --- research pass [2026-09-23]: real production code paths and config edge-case branches with zero test coverage per `pytest --cov=app --cov-report=term-missing` (review + tweak) [feat:shrike-monitor-20260923-untested-production-paths]
- [ ] [T2] backend/tests/test_checker.py — `app/services/checker.py`'s `_default_fetch()` — the actual `httpx.AsyncClient` GET used in production whenever `probe()` is called without an injected `fetch` — has 0% coverage (lines 21-23 flagged Missing by `pytest --cov=app --cov-report=term-missing`). Every existing test in `tests/` only exercises `probe()` via a fake injected fetch, so the literal code path that runs against real monitored URLs in production has never been executed by the test suite. Add a test that calls `probe(url, fetch=None)` against a local `httpx.MockTransport` (or a tiny local ASGI/http.server target) and asserts a real `CheckResult` comes back. VERIFY: `cd backend && .venv/bin/pytest --cov=app.services.checker --cov-report=term-missing -q` shows no `21-23` in the Missing column for `app/services/checker.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260923-untested-production-paths]
- [ ] [T2] backend/tests/test_notifier.py — `app/services/notifier.py`'s `_default_publish()` — the actual `httpx.AsyncClient.post` call used in production whenever `Notifier` is constructed without an injected `publish` — has 0% coverage (lines 29-31 flagged Missing). Every existing Notifier test injects a fake `publish` callable, so the real network call to shrike-notify has never run under test. Add a test exercising `_default_publish` against a local mock transport. VERIFY: `cd backend && .venv/bin/pytest --cov=app.services.notifier --cov-report=term-missing -q` shows no `29-31` in the Missing column for `app/services/notifier.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260923-untested-production-paths]
- [ ] [T1] backend/tests/test_config.py — `coerce_float()` in `app/config.py` has one untested branch: the final `return None` (reached only when `value` is a type other than `None`/`int`/`float`/`str`, e.g. a list or dict) is flagged Missing by `pytest --cov`. No existing test passes an incompatible type. Add e.g. `assert coerce_float([1, 2]) is None`. VERIFY: `cd backend && .venv/bin/pytest --cov=app.config --cov-report=term-missing -q` shows `app/config.py` with no line in the 190s in Missing. (cat:python; multifile:no) [feat:shrike-monitor-20260923-untested-production-paths]
- [ ] [T1] backend/tests/test_config.py — `Settings._fallback_invalid_int`'s `isinstance(v, int) and v < 1` branch (`app/config.py`, inside the `max_results`/`max_monitors`/`alert_threshold` validator) is flagged Missing by `pytest --cov` — every existing test for those fields goes through the `isinstance(v, str)` env-var-parsing path, never passes a raw non-positive `int` directly to the validator (e.g. `Settings(max_results=0)` constructed in Python rather than via env var). Add a test covering that path. VERIFY: `cd backend && .venv/bin/pytest --cov=app.config --cov-report=term-missing -q` shows `app/config.py` at 100% or with that line no longer in Missing. (cat:python; multifile:no) [feat:shrike-monitor-20260923-untested-production-paths]
- [ ] [T1] backend/tests/test_store.py — `Store.rehydrate()`'s early-return no-op path (`if self.persist is None: return`) is flagged Missing by `pytest --cov` — no existing test calls `rehydrate()` on a `Store` that never had `attach_persistence()` called first. Add a test asserting it's a safe no-op (returns `None`, doesn't raise, leaves `_monitors`/`_results` untouched). VERIFY: `cd backend && .venv/bin/pytest --cov=app.store --cov-report=term-missing -q` shows `app/store.py` at 100%. (cat:python; multifile:no) [feat:shrike-monitor-20260923-untested-production-paths]
