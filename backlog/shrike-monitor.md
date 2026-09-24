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

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: MonitorCreate doesn't validate token/type consistency — a token attached to an http monitor is silently accepted but unusable (review + tweak) [feat:shrike-monitor-20260922-validate-token-type-consistency] ---

# --- research pass [2026-09-23]: AGENTS.md + backlog top-of-file note both still claim the heartbeat "never reports down" bug is an open top blocker, but app/routers/monitors.py's status/fleet handlers already call app.models.overall_status(), which dispatches heartbeat monitors through heartbeat_status() — the bug is already fixed in code, only the docs are stale (review + tweak) [feat:shrike-monitor-20260923-stale-docs-and-dead-code]

# --- research pass [2026-09-23]: real production code paths and config edge-case branches with zero test coverage per `pytest --cov=app --cov-report=term-missing` (review + tweak) [feat:shrike-monitor-20260923-untested-production-paths]
- [ ] [T1] backend/tests/test_store.py — `Store.rehydrate()`'s early-return no-op path (`if self.persist is None: return`) is flagged Missing by `pytest --cov` — no existing test calls `rehydrate()` on a `Store` that never had `attach_persistence()` called first. Add a test asserting it's a safe no-op (returns `None`, doesn't raise, leaves `_monitors`/`_results` untouched). VERIFY: `cd backend && .venv/bin/pytest --cov=app.store --cov-report=term-missing -q` shows `app/store.py` at 100%. (cat:python; multifile:no) [feat:shrike-monitor-20260923-untested-production-paths]

# --- research pass [2026-09-24]: second pass after 40+ prior rounds — AGENTS.md doc drift beyond the already-tracked heartbeat-status line, plus real coverage gaps in scheduler/config/main found via fresh `pytest --cov` and a schema/router consistency sweep (review + tweak) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T1] AGENTS.md — three Gotchas bullets are stale, distinct from the already-tracked heartbeat-status-dispatch line above them: "There is no scheduler yet" (app/services/scheduler.py's MonitorScheduler exists, 146 stmts, 95% covered, started from main.py's lifespan), "Heartbeat pings are unauthenticated/spoofable in v1 (per-monitor ping token pending)" (app/routers/heartbeat.py's ping() already requires a matching ping_token, constant-time compared via app.utils.constant_time_compare, tested in tests/test_ping_token.py and tests/test_heartbeat_auth_separation.py), and "Store is in-memory (monitors/results lost on restart — DB persistence is a Claude item)" (app/persistence.py's MonitorPersistence + MONITOR_PERSIST env var already ships and is tested in tests/test_persistence.py). Rewrite the Gotchas section to match current reality. VERIFY: `grep -n 'no scheduler yet\|unauthenticated/spoofable\|DB persistence is a Claude item' AGENTS.md` returns nothing after the fix. (cat:docs; multifile:no) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T2] backend/app/models.py, backend/app/main.py — `validate_name()` (models.py:29) has zero production callers: `Store.create()` builds `Monitor(...)` directly without calling it, and `MonitorCreate`'s Pydantic `name` field already enforces the identical `^[A-Za-z0-9 _.-]{1,80}$` pattern before a request ever reaches the store. That makes main.py's `@app.exception_handler(ValidationError)` (lines 114-118, 0% covered) dead wiring for an exception nothing in the real request path ever raises. Either delete `validate_name()`/the handler, or wire `validate_name()` into `Store.create()` as real defense-in-depth and add a test that drives an actual `ValidationError` through to a 422. VERIFY: `cd backend && .venv/bin/pytest --cov=app.main --cov=app.models --cov-report=term-missing -q` shows `app/main.py` lines 117-118 Missing, and `grep -rn "validate_name(" backend/app` has no caller outside its own definition and its own unit test. (cat:dead-code; multifile:yes) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T2] backend/app/services/scheduler.py — `run_forever()`'s loop (lines 281-288: `while True: try: await self.tick() except Exception: logger.exception(...) ; await asyncio.sleep(...)`) has zero test coverage. No test proves a `tick()` exception is actually caught and logged and that the loop survives to the next iteration instead of dying silently — this is the real always-on production loop the whole service depends on. Add a test with a mocked `tick()` that raises once then succeeds, asserting `run_forever` keeps going and both calls happen. VERIFY: `cd backend && .venv/bin/pytest --cov=app.services.scheduler --cov-report=term-missing -q` shows lines 283-288 Missing beforehand. (cat:python; multifile:no) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T2] backend/app/services/scheduler.py — the incident-resolution branch (line 187: `self._incident_id[t["monitor_id"]] = None` when `t["new_incident"]` is False) has zero test coverage. Existing tests (`test_scheduler_triggers_incident_eval`, `test_seed_baseline_incident_state`, etc.) only exercise the incident-opens branch (line 185, asserted via `sched._incident_state`) and never drive an incident closed to check `_incident_id` actually resets. Add a test that opens an incident then resolves it across two `tick()` calls and asserts `sched._incident_id[mon.id]` goes from a non-None string back to `None`. VERIFY: `cd backend && .venv/bin/pytest --cov=app.services.scheduler --cov-report=term-missing -q tests/test_scheduler.py` shows line 187 Missing beforehand. (cat:python; multifile:no) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T1] backend/app/config.py — `Settings._fallback_invalid_int`'s direct-int branch (line 83-84: `if isinstance(v, int) and v < 1: return cls.model_fields[info.field_name].default`) has zero test coverage — existing tests (test_config.py, test_config_alert_threshold.py) only push non-positive values through the string-parsing branch (env vars are always strings), never a raw non-positive int passed directly to `Settings(max_results=-5)` or similar. Add a test covering the direct-int path. VERIFY: `cd backend && .venv/bin/pytest --cov=app.config --cov-report=term-missing -q` shows line 84 Missing beforehand. (cat:python; multifile:no) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T1] backend/app/config.py — `coerce_float`'s final catch-all `return None` (line 194, reached only when the input is neither `None`, `int`/`float`, nor `str` — e.g. a list or dict) has zero test coverage. Add a test calling `coerce_float([1, 2])` (or another non-scalar type) and asserting it returns `None` instead of raising. VERIFY: `cd backend && .venv/bin/pytest --cov=app.config --cov-report=term-missing -q` shows line 194 Missing beforehand. (cat:python; multifile:no) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T2] backend/app/main.py, backend/tests/test_core.py — the module-level `Notifier(...)` construction (main.py line 48, inside `if settings.notify_url:`) is never actually exercised. `test_core.py`'s only related assertion (~line 644-654) is itself gated behind `if settings.notify_url:`, and no test ever sets `NOTIFY_URL` before that check runs, so the "real Notifier gets built" branch silently never executes in CI — only the `notifier is None` branch does. Add a test that sets `NOTIFY_URL`/`NOTIFY_TOPIC`/`NOTIFY_TOKEN` and asserts a real `Notifier` is constructed with those values (via a fresh `Settings()` + the same construction logic, or an importlib reload of app.main). VERIFY: `cd backend && .venv/bin/pytest --cov=app.main --cov-report=term-missing -q` shows line 48 Missing beforehand. (cat:python; multifile:yes) [feat:shrike-monitor-20260924-round2-gaps]
- [ ] [T2] backend/app/routers/heartbeat.py, backend/app/schemas.py — `POST /heartbeat/{monitor_id}` is the only endpoint in the whole API with no `response_model` — every route in `routers/monitors.py` declares one (`MonitorCreated`, `MonitorOut`, `StatusOut`, `list[ResultOut]`, `list[Incident]`, `FleetStatusResponse`), but `ping()` just returns a raw `dict` (`id`, `received_at`, `status`, `uptime_ratio`, `incident_state`), so its response shape is untyped, unvalidated by FastAPI, and absent from the OpenAPI schema. Add a `HeartbeatPingResponse` model to schemas.py and set `response_model=HeartbeatPingResponse` on the route. VERIFY: `cd backend && .venv/bin/uvicorn app.main:app --port 8080 & sleep 1 && curl -s http://localhost:8080/openapi.json | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['paths']['/heartbeat/{monitor_id}']['post']['responses']['200'])"` shows no concrete `$ref` schema before the fix. (cat:python; multifile:yes) [feat:shrike-monitor-20260924-round2-gaps]
