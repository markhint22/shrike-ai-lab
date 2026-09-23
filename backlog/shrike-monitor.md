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
- [ ] [T1] backend/app/utils/__init__.py — Remove the now-broken `from app.utils.humanize_count import humanize_count  # noqa: E402,F401` re-export line, since the module it imports from was just deleted. VERIFY: `! grep -q "humanize_count" backend/app/utils/__init__.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
- [ ] [T2] backend/tests/test_utils.py — Add a regression assertion, matching this repo's established `test_no_X_export` precedent, proving both `humanize_bytes` and `humanize_count` are gone from `app.utils`'s namespace. VERIFY: `cd backend && .venv/bin/pytest tests/test_utils.py -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
- [ ] [T2] backend/app/utils/humanize.py — Confirm no other file in the repo still imports either deleted name after both deletions land. VERIFY: `! grep -rn "humanize_bytes\|humanize_count" backend/app`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: Heartbeat monitors never get a real incident_id, causing Notifier's permanent dedup cache to silently kill all future alerts for that monitor after its first down/up cycle (review + tweak) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug] ---
- [ ] [T2] backend/app/services/scheduler.py — In `MonitorScheduler.tick()`'s incident-transition state-building loop, replace the hardcoded `cf = 0` for heartbeat monitors with a real failure signal: use `1 if status == "down" else 0` (a heartbeat has no "partial" failure count the way an http probe does — being overdue at all is the equivalent of a full miss) so `evaluate_incident_transitions()` can actually assign a fresh incident id once a heartbeat's `status == "down"` and this pseudo-count crosses the threshold. VERIFY: `grep -n 'if monitor.type == "http"' backend/app/services/scheduler.py`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug]
- [ ] [T2] backend/app/services/scheduler.py — Lower `evaluate_incident_transitions`'s effective threshold check for heartbeat monitors specifically (e.g. pass a per-monitor-type threshold of 1 for heartbeats vs `self.config.alert_threshold` for http, since a single overdue tick is already a real outage for a dead-man's-switch), so a heartbeat's very first down tick assigns a real incident id rather than requiring 3 synthetic "misses" that heartbeats don't actually accumulate. VERIFY: `cd backend && .venv/bin/pytest tests/test_scheduler.py -k incident -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug]
- [ ] [T2] backend/tests/test_scheduler.py — Update `test_seed_baseline_computes_incident_state`'s heartbeat assertion (currently `assert sched._incident_state[mon_hb.id] is False` with the comment "cf is always 0 for heartbeats, so no incident even if down") to reflect the fixed behavior: a down heartbeat monitor now DOES register as an active incident. VERIFY: `cd backend && .venv/bin/pytest tests/test_scheduler.py::test_seed_baseline_computes_incident_state -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug]
- [ ] [T3] backend/tests/test_scheduler.py — Add a regression test driving a heartbeat monitor through two full down->up cycles (advance `now` past overdue, tick; advance `now` and record a fresh ping via `store.touch_last_ping`/`store.record`, tick; repeat) against a REAL `app.services.notifier.Notifier` instance (with an injected fake `publish` callable, not `_RecordingNotifier`/`_SpyNotifier`), asserting BOTH cycles' "up" transitions actually call the fake `publish` (i.e. neither is silently suppressed as a duplicate by `Notifier._last_notified`). VERIFY: `cd backend && .venv/bin/pytest tests/test_scheduler.py -k heartbeat_two_cycles -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug]
- [ ] [T2] backend/tests/test_notifier.py — Add a companion regression test asserting that two heartbeat down->up incidents (both ending in status "up") with DIFFERENT non-None incident_ids each produce a sent notification via `Notifier.notify_transition()`, mirroring the existing `test_two_distinct_incidents_...` test already covering this for http monitors. VERIFY: `cd backend && .venv/bin/pytest tests/test_notifier.py -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug]
- [ ] [T2] backend/app/services/scheduler.py — Run the full scheduler + notifier test suites together to confirm the incident-id fix for heartbeats doesn't change any existing http-monitor incident/notification test outcomes. VERIFY: `cd backend && .venv/bin/pytest tests/test_scheduler.py tests/test_notifier.py -v`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-heartbeat-incident-id-dedup-bug]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: Store.create()'s StoreFull exception is never caught at the API layer — POST /monitors crashes 500 instead of a clean error at capacity (review + tweak) [feat:shrike-monitor-20260922-storefull-exception-handler] ---
- [ ] [T1] backend/app/main.py — Import `StoreFull` from `app.store` and register a new `@app.exception_handler(StoreFull)` (placed alongside the existing `ValidationError` handler) that returns a `JSONResponse(status_code=507, content={"detail": str(exc)})`, logging a warning first. VERIFY: `grep -n "exception_handler(StoreFull)" backend/app/main.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-storefull-exception-handler]
- [ ] [T2] backend/tests/test_monitors_api.py — Add a regression test that creates monitors up to `Settings().max_monitors` (or a small test-configured `store.max_monitors`), then asserts the next `POST /monitors` call returns HTTP 507 with a JSON body containing a `detail` key, instead of raising an unhandled 500. VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_api.py -k store_full -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-storefull-exception-handler]
- [ ] [T2] backend/app/main.py — Confirm the new StoreFull handler doesn't interfere with any other 5xx-adjacent test by running the full main/monitors test suites together. VERIFY: `cd backend && .venv/bin/pytest tests/test_main_config_verification.py tests/test_monitors_api.py -v`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-storefull-exception-handler]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: StatusOut.uptime_percent field exists but is never populated — GET /monitors/{id}/status always returns 0.0 regardless of real uptime (review + tweak) [feat:shrike-monitor-20260922-wire-uptime-percent] ---
- [ ] [T1] backend/app/routers/monitors.py — In `_build_status_out()`, compute `uptime_percent = round(up_ratio * 100, 1)` right after `up_ratio = uptime_ratio(results)` is computed, and pass `uptime_percent=uptime_percent` into the returned `StatusOut(...)` call. VERIFY: `grep -n "uptime_percent=uptime_percent" backend/app/routers/monitors.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-uptime-percent]
- [ ] [T2] backend/tests/test_monitors_status_api.py — Add a regression test that records 3 ok + 1 failed check for a monitor, then asserts `GET /monitors/{id}/status`'s JSON body has `uptime_percent == 75.0` (not `0.0`). VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_status_api.py -k uptime_percent -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-uptime-percent]
- [ ] [T1] backend/tests/test_monitors_status_api.py — Add a second regression test for the zero-results case, asserting `GET /monitors/{id}/status` for a freshly created monitor with no recorded checks returns `uptime_percent == 0.0` (uptime_ratio's own documented empty-input behavior), so the fix doesn't regress the pending-monitor case. VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_status_api.py -k uptime_percent -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-uptime-percent]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: Settings.service_version unused + GET /health exposes no version field at all (review + tweak) [feat:shrike-monitor-20260922-wire-version-into-health] ---
- [ ] [T1] backend/app/schemas.py — Add a `version: str = ""` field to the `Health` model. VERIFY: `grep -n "version: str" backend/app/schemas.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-version-into-health]
- [ ] [T1] backend/app/main.py — In the `health()` handler, pass `version=settings.service_version` into the `Health(...)` response for both the healthy and (if practical) the persistence-failure JSONResponse paths. VERIFY: `grep -n "version=settings.service_version" backend/app/main.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-version-into-health]
- [ ] [T2] backend/tests/test_main_config_verification.py — Add a regression test asserting `GET /health`'s JSON body includes a non-empty `version` field matching `settings.service_version`. VERIFY: `cd backend && .venv/bin/pytest tests/test_main_config_verification.py -k version -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-version-into-health]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: monitor_incidents() docstring stale, still claims heartbeat monitors always return an empty incidents list (review + tweak) [feat:shrike-monitor-20260922-fix-stale-incidents-docstring] ---
- [ ] [T1] backend/app/routers/monitors.py — Update `monitor_incidents()`'s docstring to remove the stale claim that heartbeat monitors "always return an empty list", replacing it with accurate wording matching README.md's already-correct "(HTTP and heartbeat monitors)" description — heartbeat monitors now derive real incidents from their synthetic CheckResults recorded on each status transition. VERIFY: `! grep -q "always return an empty list" backend/app/routers/monitors.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-fix-stale-incidents-docstring]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: MonitorScheduler.get_current_incident_id() is a dead public method, zero callers anywhere (review + tweak) [feat:shrike-monitor-20260922-delete-get-current-incident-id] ---
- [ ] [T1] backend/app/services/scheduler.py — Delete the dead `get_current_incident_id(self, monitor_id: str) -> str | None` method; confirmed via grep it has zero callers anywhere in backend/app or backend/tests. VERIFY: `! grep -q "def get_current_incident_id" backend/app/services/scheduler.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-delete-get-current-incident-id]
- [ ] [T1] backend/app/services/scheduler.py — Run the scheduler test suite to confirm nothing else in the module referenced the deleted method. VERIFY: `cd backend && .venv/bin/pytest tests/test_scheduler.py -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-delete-get-current-incident-id]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: downtime_seconds() cannot count an ongoing/current outage — GET /status undercounts downtime for a monitor currently down (review + tweak) [feat:shrike-monitor-20260922-downtime-seconds-ongoing-outage] ---
- [ ] [T2] backend/app/routers/monitors.py — In `_build_status_out()`, after building `checks_for_downtime`, if `results` is non-empty and the most recent result is down (`not results[-1].ok`), append a synthetic `(time.time(), False)` tuple to `checks_for_downtime` before calling `downtime_seconds()`, so the ongoing outage since the last recorded check is included in the total. VERIFY: `grep -n "checks_for_downtime.append\|checks_for_downtime +" backend/app/routers/monitors.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-downtime-seconds-ongoing-outage]
- [ ] [T2] backend/tests/test_monitors_status_api.py — Add a regression test: create an http monitor, record a single failed CheckResult with `checked_at` set to ~300 seconds before the test's mocked "now", call `GET /monitors/{id}/status`, and assert `downtime_seconds` is close to 300 (not 0.0). VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_status_api.py -k downtime -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-downtime-seconds-ongoing-outage]
- [ ] [T1] backend/tests/test_monitors_status_api.py — Add a companion regression test proving a monitor whose most recent result is UP does not get a synthetic trailing span added (downtime_seconds unaffected by wall-clock time since a healthy check). VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_status_api.py -k downtime -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-downtime-seconds-ongoing-outage]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: latency_stats() (min/avg/max/p95, fully built + tested + already wired to the correct percentile()) has zero production callers — no endpoint exposes it (review + tweak) [feat:shrike-monitor-20260922-wire-latency-stats] ---
- [ ] [T2] backend/app/schemas.py — Add a `latency_p95_ms: float | None = None` field to `StatusOut` (start with p95 alone as the single most actionable latency stat for a status page; min/avg/max can follow the same pattern later). VERIFY: `grep -n "latency_p95_ms" backend/app/schemas.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-latency-stats]
- [ ] [T2] backend/app/routers/monitors.py — In `_build_status_out()`, import `latency_stats` from `app.models`, compute `stats = latency_stats(results) if mon.type == "http" else {"p95": None}`, and pass `latency_p95_ms=stats["p95"]` into the `StatusOut(...)` call. VERIFY: `grep -n "latency_stats(results)" backend/app/routers/monitors.py`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-wire-latency-stats]
- [ ] [T2] backend/tests/test_monitors_status_api.py — Add a regression test recording several http CheckResults with distinct latency_ms values, then asserting `GET /monitors/{id}/status`'s `latency_p95_ms` matches the value `latency_stats()` itself would compute for the same results. VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_status_api.py -k latency -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-latency-stats]
- [ ] [T1] backend/tests/test_monitors_status_api.py — Add a companion regression test asserting a heartbeat monitor's `GET /status` response has `latency_p95_ms == None` (heartbeats never carry latency data). VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_status_api.py -k latency -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-wire-latency-stats]
- [ ] [T1] backend/app/routers/monitors.py — Run the full monitors router + models test suites to confirm the new field doesn't break any existing StatusOut-shape assertions. VERIFY: `cd backend && .venv/bin/pytest tests/test_monitors_status_api.py tests/test_schemas.py tests/test_models.py -v`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-wire-latency-stats]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: app/utils/jitter.py's with_jitter() is dead, zero callers — distinct from backoff.py's own separate ad-hoc jitter reimplementation (review + tweak) [feat:shrike-monitor-20260922-delete-dead-with-jitter] ---
- [ ] [T1] backend/app/utils/jitter.py — Delete this entire module (`with_jitter(base, frac, rand)`); confirmed via grep it has zero callers anywhere outside its own dedicated test file, backend/tests/test_utils.py — `app/services/notifier.py`'s retry backoff uses `app/utils/backoff.py`'s own separate inline jitter implementation instead. VERIFY: `test ! -f backend/app/utils/jitter.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-delete-dead-with-jitter]
- [ ] [T1] backend/tests/test_utils.py — Remove the `with_jitter` import and its three test cases (`test_with_jitter_base`, `test_with_jitter_bounds`, `test_with_jitter_noop`), now that the module is deleted. VERIFY: `! grep -q "with_jitter" backend/tests/test_utils.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-delete-dead-with-jitter]
- [ ] [T1] backend/app/utils/jitter.py — Confirm no other file in the repo still imports the deleted name. VERIFY: `! grep -rn "with_jitter" backend/app backend/tests`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-delete-dead-with-jitter]

# --- 27B-decomposed from roadmap [2026-09-22 round 3]: MonitorCreate doesn't validate token/type consistency — a token attached to an http monitor is silently accepted but unusable (review + tweak) [feat:shrike-monitor-20260922-validate-token-type-consistency] ---
- [ ] [T2] backend/app/schemas.py — In `MonitorCreate.check_url_rules()`, add a check that raises `ValueError("token must not be set for http monitors")` when `self.type == "http" and self.token is not None`, matching the existing pattern used for the `url` field's type-consistency checks in the same validator. VERIFY: `grep -n "token must not be set for http" backend/app/schemas.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-validate-token-type-consistency]
- [ ] [T1] backend/tests/test_schemas.py — Add a regression test asserting `MonitorCreate(type="http", url="https://x", token="abc")` raises a `ValidationError` (or `pydantic.ValidationError`, matching this validator's existing raise style). VERIFY: `cd backend && .venv/bin/pytest tests/test_schemas.py -k token_type -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-validate-token-type-consistency]
- [ ] [T1] backend/tests/test_schemas.py — Add a companion regression test confirming `MonitorCreate(type="heartbeat", token="abc")` still succeeds (the new check only rejects http+token, not heartbeat+token, which remains a legitimate use case for supplying a pre-existing ping token). VERIFY: `cd backend && .venv/bin/pytest tests/test_schemas.py -k token_type -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-validate-token-type-consistency]
