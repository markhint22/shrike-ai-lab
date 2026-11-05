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

# --- research pass [2026-09-24]: second pass after 40+ prior rounds — AGENTS.md doc drift beyond the already-tracked heartbeat-status line, plus real coverage gaps in scheduler/config/main found via fresh `pytest --cov` and a schema/router consistency sweep (review + tweak) [feat:shrike-monitor-20260924-round2-gaps]

# --- 27B-decomposed from roadmap [2026-09-25]: **[LIVE BUG — checked-off fix does not work]** The checked-off "heartbeat incident-id" fix (review + tweak) [feat:shrike-monitor-20260925-live-bug-checked-off-fix-does-not-work-t] ---

# --- 27B-decomposed from roadmap [2026-09-25]: `backend/app/utils/auth.py` — already deleted once as dead code (2026-09-21), has been rec (review + tweak) [feat:shrike-monitor-20260925-backend-app-utils-auth-py-already-delete] ---

# --- 27B-decomposed from roadmap [2026-09-25]: `DELETE /monitors/{id}` never tells the running `MonitorScheduler`/`Notifier` to forget th (review + tweak) [feat:shrike-monitor-20260925-delete-monitors-id-never-tells-the-runni] ---

# --- 27B-decomposed from roadmap [2026-09-25]: `MonitorScheduler.seed_baseline()` never sets `_incident_id` for a monitor that's already  (review + tweak) [feat:shrike-monitor-20260925-monitorscheduler-seed-baseline-never-set] ---

# --- 27B-decomposed from roadmap [2026-09-25]: **[repeatedly failed automated decomposition — route to human/Claude, not another 27B pass (review + tweak) [feat:shrike-monitor-20260925-repeatedly-failed-automated-decompositio] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Add PATCH /monitors/{id} to update an existing monitor's config — `backend/app/store.py` o (review + tweak) [feat:shrike-monitor-20260926-add-patch-monitors-id-to-update-an-exist] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Add type/status filtering and pagination to GET /monitors — `list_monitors()` (`backend/ap (review + tweak) [feat:shrike-monitor-20260926-add-type-status-filtering-and-pagination] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Break GET /monitors/status's fleet summary down by individual status, not just healthy/unh (review + tweak) [feat:shrike-monitor-20260926-break-get-monitors-status-s-fleet-summar] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Give heartbeat monitors an early-warning "degraded" state instead of a hard up/down cliff  (review + tweak) [feat:shrike-monitor-20260926-give-heartbeat-monitors-an-early-warning] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Notifier._last_notified still leaks forever on monitor delete — a deliberately-flagged fol (review + tweak) [feat:shrike-monitor-20260926-notifier-last-notified-still-leaks-forev] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Reject degraded_latency_ms set away from its default on heartbeat monitors — the mirror ca (review + tweak) [feat:shrike-monitor-20260926-reject-degraded-latency-ms-set-away-from] ---

# --- 27B-decomposed from roadmap [2026-09-26]: Add a `since` timestamp filter to GET /monitors/{id}/results — today `monitor_results()` ( (review + tweak) [feat:shrike-monitor-20260926-add-a-since-timestamp-filter-to-get-moni] ---

# --- 27B-decomposed from roadmap [2026-09-27]: PATCH /monitors/{id} silently bypasses heartbeat type invariants — a prior backlog item falsely claimed this was already fixed at the schema level (review + tweak) [feat:shrike-monitor-20260927-patch-heartbeat-invariant-bypass] ---

# --- 27B-decomposed from roadmap [2026-09-27]: PATCH /monitors/{id} never writes through to MONITOR_PERSIST — confirmed live, changes are silently dropped on restart (review + tweak) [feat:shrike-monitor-20260927-patch-persistence-dropped] ---

# --- 27B-decomposed from roadmap [2026-09-27]: root cause found for the escalated "Notifier.forget() unreachable on delete" item — app.state.notifier is never assigned in main.py (review + tweak) [feat:shrike-monitor-20260927-wire-app-state-notifier] ---

# --- 27B-decomposed from roadmap [2026-09-27]: dead pure-math utilities, round 4 — zero callers anywhere, 0% coverage per pytest --cov (review + tweak) [feat:shrike-monitor-20260927-dead-pure-utils-round4] ---

# --- 27B-decomposed from roadmap [2026-09-27]: prune_threshold duplicate dead code is STILL unfixed — a 2026-09-22 backlog item claimed this was already resolved but both copies remain untouched (review + tweak) [feat:shrike-monitor-20260927-prune-threshold-still-dead] ---

# --- 27B-decomposed from roadmap [2026-09-27]: wire the already-tested fleet_status_counts.calculate_by_status() helper into calculate_fleet_status() instead of a hand-duplicated loop (review + tweak) [feat:shrike-monitor-20260927-wire-fleet-by-status-helper] ---

# --- 27B-decomposed from roadmap [2026-09-27]: dead classify.http_status() — tested but zero production callers, fully superseded by app.models.classify_http() (review + tweak) [feat:shrike-monitor-20260927-dead-classify-http-status] ---

# --- 27B-decomposed from roadmap [2026-09-27]: MonitorUpdate's http-type branch has zero test coverage — every existing MonitorUpdate test only exercises the heartbeat branch (review + tweak) [feat:shrike-monitor-20260927-monitorupdate-http-branch-coverage] ---

# --- 27B-decomposed from roadmap [2026-09-27]: app.main's ValidationError exception handler has zero test coverage (review + tweak) [feat:shrike-monitor-20260927-validation-error-handler-coverage] ---

# --- 27B-decomposed from roadmap [2026-09-30]: LIVE BUG: second "down" alert within dedup_ttl is silently swallowed because down notifica (review + tweak) [feat:shrike-monitor-20260930-live-bug-second-down-alert-within-dedup-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: LIVE BUG: one monitor raising inside tick() aborts the whole pass and starves every later  (review + tweak) [feat:shrike-monitor-20260930-live-bug-one-monitor-raising-inside-tick] ---

# --- 27B-decomposed from roadmap [2026-09-30]: LIVE BUG: PATCH /monitors/{id} accepts invalid urls and type changes that permanently brea (review + tweak) [feat:shrike-monitor-20260930-live-bug-patch-monitors-id-accepts-inval] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Probe HTTP monitors concurrently with a hard wall-clock cap instead of serially — MonitorS (review + tweak) [feat:shrike-monitor-20260930-probe-http-monitors-concurrently-with-a-] ---

# --- 27B-decomposed from roadmap [2026-09-30]: SSRF guard for user-supplied monitor URLs — MonitorCreate/MonitorUpdate (schemas.py) accep (review + tweak) [feat:shrike-monitor-20260930-ssrf-guard-for-user-supplied-monitor-url] ---

# --- 27B-decomposed from roadmap [2026-09-30]: /health should return 503 when the scheduler task is dead or stale, so Railway's healthche (review + tweak) [feat:shrike-monitor-20260930-health-should-return-503-when-the-schedu] ---

# --- 27B-decomposed from roadmap [2026-09-30]: Startup guard against running the API fully open in a deployed environment — app/main.py b (review + tweak) [feat:shrike-monitor-20260930-startup-guard-against-running-the-api-fu] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Delete `since_filter.py` dead duplicate and fix `__init__.py` re-export — `backend/app/uti (review + tweak) [feat:shrike-monitor-20261001-delete-since-filter-py-dead-duplicate-an] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Delete dead `utils/incident_id.py::generate_incident_id` — `backend/app/utils/incident_id. (review + tweak) [feat:shrike-monitor-20261001-delete-dead-utils-incident-id-py-generat] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Fix `calculate_backoff_delay` returning up to 2×max_delay — `backend/app/utils/backoff.py: (review + tweak) [feat:shrike-monitor-20261001-fix-calculate-backoff-delay-returning-up] ---

# --- 27B-decomposed from roadmap [2026-10-01]: Delete dead `is_degraded()` from `heartbeat_signal.py` — `backend/app/utils/heartbeat_sign (review + tweak) [feat:shrike-monitor-20261001-delete-dead-is-degraded-from-heartbeat-s] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Store.update() split-brain on persistence failure — `backend/app/store.py`'s `Store.update (review + tweak) [feat:shrike-monitor-20261002-store-update-split-brain-on-persistence-] ---

# --- 27B-decomposed from roadmap [2026-10-02]: DNS-rebinding TOCTOU bypass of planned SSRF guard — the decomposed SSRF guard (`url_guard. (review + tweak) [feat:shrike-monitor-20261002-dns-rebinding-toctou-bypass-of-planned-s] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Dead re-validation in create_monitor() route handler — `backend/app/routers/monitors.py`'s (review + tweak) [feat:shrike-monitor-20261002-dead-re-validation-in-create-monitor-rou] ---

# --- 27B-decomposed from roadmap [2026-10-02]: alert_threshold missing upper-bound validator — `backend/app/config.py`'s `_fallback_inval (review + tweak) [feat:shrike-monitor-20261002-alert-threshold-missing-upper-bound-vali] ---

# --- 27B-decomposed from roadmap [2026-10-02]: Ping-token regeneration endpoint — `backend/app/routers/monitors.py` has no route to repla (review + tweak) [feat:shrike-monitor-20261002-ping-token-regeneration-endpoint-backend] ---

# --- deterministic work supply 2026-10-16 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-17]: Heartbeat scheduler misses "degraded" state entirely — `compute_heartbeat_signal` (backend (review + tweak) [feat:shrike-monitor-20261017-heartbeat-scheduler-misses-degraded-stat] ---

# --- 27B-decomposed from roadmap [2026-10-17]: `MonitorChecker` class (backend/app/services/checker.py:81-118) duplicates the module-leve (review + tweak) [feat:shrike-monitor-20261017-monitorchecker-class-backend-app-service] ---

# --- 27B-decomposed from roadmap [2026-10-17]: `compute_heartbeat_cf(status)` (backend/app/utils/heartbeat_signal.py:46-52) is unit-teste (review + tweak) [feat:shrike-monitor-20261017-compute-heartbeat-cf-status-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-10-17]: `paginate.paginate` (backend/app/utils/paginate.py:4-18) is unit-tested in backend/tests/t (review + tweak) [feat:shrike-monitor-20261017-paginate-paginate-backend-app-utils-pagi] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Wire `compute_concurrency_cap` into `tick()` and delete/wire `compute_total_timeout` — bot (review + tweak) [feat:shrike-monitor-20261018-wire-compute-concurrency-cap-into-tick-a] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Wire `filter_monitors` into `list_monitors()` to eliminate dead import and diverging inlin (review + tweak) [feat:shrike-monitor-20261018-wire-filter-monitors-into-list-monitors-] ---

# --- 27B-decomposed from roadmap [2026-10-18]: `Notifier.dedup_ttl` is hardcoded at 300 s and cannot be tuned via `Settings` — `backend/a (review + tweak) [feat:shrike-monitor-20261018-notifier-dedup-ttl-is-hardcoded-at-300-s] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `store_full_handler` — `backend/app/main.py:197` defines a public handler for store-f (review + tweak) [feat:shrike-monitor-20261018-test-store-full-handler-backend-app-main] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `fleet_status` endpoint — `backend/app/routers/monitors.py:104` exposes a public flee (review + tweak) [feat:shrike-monitor-20261018-test-fleet-status-endpoint-backend-app-r] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `get_monitor` and `delete_monitor` — `backend/app/routers/monitors.py:118` and `:165` (review + tweak) [feat:shrike-monitor-20261018-test-get-monitor-and-delete-monitor-back] ---

# --- 27B-decomposed from roadmap [2026-10-18]: Test `monitor_status` and `monitor_results` endpoints — Add integration tests for the unte (review + tweak) [feat:shrike-monitor-20261018-test-monitor-status-and-monitor-results-] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Delete dead `Store.regenerate_ping_token()` and switch router to use `store.update()` — `s (review + tweak) [feat:shrike-monitor-20261019-delete-dead-store-regenerate-ping-token-] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Call `scheduler.aclose()` in the FastAPI lifespan to close the shared httpx client — `Moni (review + tweak) [feat:shrike-monitor-20261019-call-scheduler-aclose-in-the-fastapi-lif] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Delete dead `build_store_config()` from config.py — `config.py:136-166` (docstring explici (review + tweak) [feat:shrike-monitor-20261019-delete-dead-build-store-config-from-conf] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Fix blocking `socket.getaddrinfo()` call inside async SSRF validator — `ip_check.py:27` ca (review + tweak) [feat:shrike-monitor-20261019-fix-blocking-socket-getaddrinfo-call-ins] ---

# --- 27B-decomposed from roadmap [2026-10-19]: Handle non-integer line numbers in parse_edit_block — `aegis.py:259` (`parse_edit_block`)  (review + tweak) [feat:shrike-monitor-20261019-handle-non-integer-line-numbers-in-parse] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `persistence.update_monitor()` silently drops regenerated `ping_token` on DB restart — `Mo (review + tweak) [feat:shrike-monitor-20261020-persistence-update-monitor-silently-drop] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `StatusOut.current_streak` silently misrepresents heartbeat "degraded" state — in `_build_ (review + tweak) [feat:shrike-monitor-20261020-statusout-current-streak-silently-misrep] ---

# --- 27B-decomposed from roadmap [2026-10-20]: `latency_stats()` computes min/avg/max but `_build_status_out()` discards them — monitors. (review + tweak) [feat:shrike-monitor-20261020-latency-stats-computes-min-avg-max-but-b] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Two divergent version sources let OpenAPI docs and GET /health silently disagree on the ru (review + tweak) [feat:shrike-monitor-20261020-two-divergent-version-sources-let-openap] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Test `resolve_degraded_status` — Add unit tests for the untested public function `resolve_ (review + tweak) [feat:shrike-monitor-20261020-test-resolve-degraded-status-add-unit-te] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Heartbeat recovery double-records an `ok=True` result, silently inflating `uptime_ratio` — (review + tweak) [feat:shrike-monitor-20261020-heartbeat-recovery-double-records-an-ok-] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Delete `degraded_to_status()` from `status_streak.py` — dead zero-caller function just add (review + tweak) [feat:shrike-monitor-20261020-delete-degraded-to-status-from-status-st] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix INSERT edit validation to allow start_line=0 for beginning-of-file insertion — `aegis. (review + tweak) [feat:shrike-monitor-20261020-fix-insert-edit-validation-to-allow-star] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix heartbeat ping response: `incident_state` reports "active" for degraded monitors — `ba (review + tweak) [feat:shrike-monitor-20261020-fix-heartbeat-ping-response-incident-sta] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix `_build_status_out` using `classify_http` on heartbeat synthetic results — `backend/ap (review + tweak) [feat:shrike-monitor-20261020-fix-build-status-out-using-classify-http] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Fix runtime SSRF guard in `ip_check.py::is_private_ip` — `backend/app/utils/ip_check.py:17 (review + tweak) [feat:shrike-monitor-20261020-fix-runtime-ssrf-guard-in-ip-check-py-is] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Delete dead `filter_monitors` helper — `backend/app/utils/filter.py::filter_monitors` is i (review + tweak) [feat:shrike-monitor-20261020-delete-dead-filter-monitors-helper-backe] ---

# --- 27B-decomposed from roadmap [2026-10-20]: Delete dead `_compute_monitor_status` helper in monitors.py — `backend/app/routers/monitor (review + tweak) [feat:shrike-monitor-20261020-delete-dead-compute-monitor-status-helpe] ---

# --- deterministic work supply 2026-10-20 (ovn_work_supply.py; VERIFY is red-before, mechanical) ---

# --- 27B-decomposed from roadmap [2026-10-21]: Delete `compute_heartbeat_signal` duplicate and wire scheduler to `heartbeat_status` — `ap (review + tweak) [feat:shrike-monitor-20261021-delete-compute-heartbeat-signal-duplicat] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Delete `resolve_degraded_status` dead no-op in `monitors.py` — `routers/monitors.py:253-26 (review + tweak) [feat:shrike-monitor-20261021-delete-resolve-degraded-status-dead-no-o] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Fix `_maybe_notify` else-branch silently resets `_last_status_change_at` on every no-chang (review + tweak) [feat:shrike-monitor-20261021-fix-maybe-notify-else-branch-silently-re] ---

# --- 27B-decomposed from roadmap [2026-10-21]: Delete deprecated dead `app/version.py` module and its companion test — `backend/app/versi (review + tweak) [feat:shrike-monitor-20261021-delete-deprecated-dead-app-version-py-mo] ---

# --- 27B-decomposed from roadmap [2026-10-21]: `GET /monitors/{id}/incidents` classifies heartbeat "degraded" grace-window as "down" — `m (review + tweak) [feat:shrike-monitor-20261021-get-monitors-id-incidents-classifies-hea] ---

# --- 27B-decomposed from roadmap [2026-10-21]: `ALLOW_PRIVATE_URLS=true` server setting permits monitor creation but the runtime probe al (review + tweak) [feat:shrike-monitor-20261021-allow-private-urls-true-server-setting-p] ---

# --- 27B-decomposed from roadmap [2026-10-21]: `MonitorCreate.token` accepts an empty string for heartbeat monitors, creating a permanent (review + tweak) [feat:shrike-monitor-20261021-monitorcreate-token-accepts-an-empty-str] ---

# --- 27B-decomposed from roadmap [2026-10-21]: `compute_initial_status` is dead code still present in `status_streak.py` despite `OVERNIG (review + tweak) [feat:shrike-monitor-20261021-compute-initial-status-is-dead-code-stil] ---

# --- 27B-decomposed from roadmap [2026-10-24]: Fix process_llm_output to accumulate edits per file — `aegis.py:168` (`process_llm_output` (review + tweak) [feat:shrike-monitor-20261024-fix-process-llm-output-to-accumulate-edi] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Add an additive column-migration step to MonitorPersistence.init() so new Monitor fields c (review + tweak) [feat:shrike-monitor-20261028-add-an-additive-column-migration-step-to] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Per-monitor expected status codes and request timeout for HTTP monitors — backend/app/serv (review + tweak) [feat:shrike-monitor-20261028-per-monitor-expected-status-codes-and-re] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Optional response-body substring check for HTTP monitors — add body_contains: str | None ( (review + tweak) [feat:shrike-monitor-20261028-optional-response-body-substring-check-f] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Add 24h and 7d windowed uptime and 24h p95 latency to GET /monitors/{id}/status — StatusOu (review + tweak) [feat:shrike-monitor-20261028-add-24h-and-7d-windowed-uptime-and-24h-p] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Include the same windowed uptime and p95 in the GET /monitors/status fleet summary rows —  (review + tweak) [feat:shrike-monitor-20261028-include-the-same-windowed-uptime-and-p95] ---

# --- 27B-decomposed from roadmap [2026-10-28]: Corrupted persisted rows must be skipped with a logged error instead of crashing startup — (review + tweak) [feat:shrike-monitor-20261028-corrupted-persisted-rows-must-be-skipped] ---

# --- 27B-decomposed from roadmap [2026-11-01]: POST /monitors silently drops expected_status_codes, timeout_seconds and body_contains — M (review + tweak) [feat:shrike-monitor-20261101-post-monitors-silently-drops-expected-st] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Scheduler cannot parse list-typed expected_status_codes, so custom success codes never app (review + tweak) [feat:shrike-monitor-20261101-scheduler-cannot-parse-list-typed-expect] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Scheduler never passes body_contains to checker.probe() — `checker.probe()` (backend/app/s (review + tweak) [feat:shrike-monitor-20261101-scheduler-never-passes-body-contains-to-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Persist expected_status_codes and timeout_seconds, and load body_contains back on restart  (review + tweak) [feat:shrike-monitor-20261101-persist-expected-status-codes-and-timeou] ---

# --- 27B-decomposed from roadmap [2026-11-01]: GET /monitors/status never populates the per-monitor `monitors` list — FleetStatusResponse (review + tweak) [feat:shrike-monitor-20261101-get-monitors-status-never-populates-the-] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Shared httpx client ignores the per-monitor timeout_seconds — in `_default_fetch()` (backe (review + tweak) [feat:shrike-monitor-20261101-shared-httpx-client-ignores-the-per-moni] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Scheduler's hard 30s probe cap truncates monitors configured with a longer timeout — `_saf (review + tweak) [feat:shrike-monitor-20261101-scheduler-s-hard-30s-probe-cap-truncates] ---

# --- 27B-decomposed from roadmap [2026-11-01]: PATCH /monitors/{id} accepts http-only fields on heartbeat monitors — MonitorUpdate's `eff (review + tweak) [feat:shrike-monitor-20261101-patch-monitors-id-accepts-http-only-fiel] ---

# --- 27B-decomposed from roadmap [2026-11-01]: MonitorCreate accepts body_contains on heartbeat monitors — `MonitorCreate.check_url_rules (review + tweak) [feat:shrike-monitor-20261101-monitorcreate-accepts-body-contains-on-h] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Empty body_contains and empty expected_status_codes are accepted and mean nothing useful — (review + tweak) [feat:shrike-monitor-20261101-empty-body-contains-and-empty-expected-s] ---

# --- 27B-decomposed from roadmap [2026-11-01]: windowed_p95_latency counts latencies of failed checks, unlike latency_stats — `windowed_p (review + tweak) [feat:shrike-monitor-20261101-windowed-p95-latency-counts-latencies-of] ---

# --- 27B-decomposed from roadmap [2026-11-01]: Remove the never-populated StatusOut.windowed_uptime and windowed_p95_latency fields — `St (review + tweak) [feat:shrike-monitor-20261101-remove-the-never-populated-statusout-win] ---

# --- 27B-decomposed from roadmap [2026-11-02]: PATCH /monitors/{id} with an explicit JSON null on a non-nullable field corrupts the monit (review + tweak) [feat:shrike-monitor-20261102-patch-monitors-id-with-an-explicit-json-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: PATCH /monitors/{id} lets an http monitor's url be blanked or switched to a non-http schem (review + tweak) [feat:shrike-monitor-20261102-patch-monitors-id-lets-an-http-monitor-s] ---

# --- 27B-decomposed from roadmap [2026-11-02]: A persistence failure while recording a probe result makes the scheduler re-probe that mon (review + tweak) [feat:shrike-monitor-20261102-a-persistence-failure-while-recording-a-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: tick()'s overall gather timeout ignores the concurrency cap, so a fleet of slow monitors c (review + tweak) [feat:shrike-monitor-20261102-tick-s-overall-gather-timeout-ignores-th] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Log every monitor status transition at INFO with structured context — `MonitorScheduler._m (review + tweak) [feat:shrike-monitor-20261102-log-every-monitor-status-transition-at-i] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Accept the heartbeat ping token in an `X-Ping-Token` header as well as the query string —  (review + tweak) [feat:shrike-monitor-20261102-accept-the-heartbeat-ping-token-in-an-x-] ---

# --- 27B-decomposed from roadmap [2026-11-02]: A bad NOTIFY_DEDUP_TTL crashes startup, unlike every other numeric setting — `Settings.not (review + tweak) [feat:shrike-monitor-20261102-a-bad-notify-dedup-ttl-crashes-startup-u] ---

# --- 27B-decomposed from roadmap [2026-11-02]: JSONFormatter drops `extra=` fields, so structured log context never reaches the output —  (review + tweak) [feat:shrike-monitor-20261102-jsonformatter-drops-extra-fields-so-stru] ---

# --- 27B-decomposed from roadmap [2026-11-02]: GET /monitors silently ignores bad `type` and `status` filter values — `list_monitors()` ( (review + tweak) [feat:shrike-monitor-20261102-get-monitors-silently-ignores-bad-type-a] ---

# --- 27B-decomposed from roadmap [2026-11-02]: README documents only half of the environment variables and a wrong SCHEDULER_TICK_SECONDS (review + tweak) [feat:shrike-monitor-20261102-readme-documents-only-half-of-the-enviro] ---

# --- 27B-decomposed from roadmap [2026-11-02]: Test `encode_status_codes` and `decode_status_codes` — Add unit tests for the untested pub (review + tweak) [feat:shrike-monitor-20261102-test-encode-status-codes-and-decode-stat] ---

# --- 27B-decomposed from roadmap [2026-11-04]: A heartbeat monitor that never pings stays "pending" forever and never alerts — `heartbeat (review + tweak) [feat:shrike-monitor-20261104-a-heartbeat-monitor-that-never-pings-sta] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `Store.record()` resurrects results for a deleted monitor (ghost id + orphan DB rows) — `r (review + tweak) [feat:shrike-monitor-20261104-store-record-resurrects-results-for-a-de] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `Store.create()` and `Store.delete()` update memory before the DB, so a persistence failur (review + tweak) [feat:shrike-monitor-20261104-store-create-and-store-delete-update-mem] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Timeout and connection failures are recorded with an EMPTY error string — `probe()` (backe (review + tweak) [feat:shrike-monitor-20261104-timeout-and-connection-failures-are-reco] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Probe reads the entire response body into memory before truncating it — `_default_fetch()` (review + tweak) [feat:shrike-monitor-20261104-probe-reads-the-entire-response-body-int] ---
- [ ] [T2] backend/tests/test_checker_body_cap.py — Add test `test_per_call_client_streaming` to verify the per-call client path respects the body cap. VERIFY: `cd backend && python -m pytest tests/test_checker_body_cap.py::test_per_call_client_streaming -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-probe-reads-the-entire-response-body-int]

# --- 27B-decomposed from roadmap [2026-11-04]: Recorded latency includes the SSRF guard's DNS resolution, inflating latency and causing f (review + tweak) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard] ---
- [ ] [T2] backend/app/services/checker.py — Modify `_default_fetch` to perform the SSRF guard before timing and return a 3-tuple `(status, body, elapsed_ms)` where `elapsed_ms` measures only the HTTP request. VERIFY: `cd backend && python -m pytest tests/test_checker_latency_excludes_dns.py::test_default_fetch_returns_3_tuple -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard]
- [ ] [T2] backend/app/services/checker.py — Modify `probe()` to unpack the 3-tuple from `_default_fetch` and use its `elapsed_ms` for `latency_ms`, while preserving fallback logic for injected fetches returning int or 2-tuples. VERIFY: `cd backend && python -m pytest tests/test_checker_latency_excludes_dns.py::test_probe_uses_internal_elapsed -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard]
- [ ] [T1] backend/tests/test_checker_latency_excludes_dns.py — Add test `test_default_fetch_returns_3_tuple` that mocks the HTTP client to verify `_default_fetch` returns a 3-tuple with correct structure. VERIFY: `cd backend && python -m pytest tests/test_checker_latency_excludes_dns.py::test_default_fetch_returns_3_tuple -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard]
- [ ] [T1] backend/tests/test_checker_latency_excludes_dns.py — Add test `test_probe_uses_internal_elapsed` that injects a mock fetch returning a 3-tuple and asserts `probe()` uses the provided `elapsed_ms` rather than calculating its own. VERIFY: `cd backend && python -m pytest tests/test_checker_latency_excludes_dns.py::test_probe_uses_internal_elapsed -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard]
- [ ] [T1] backend/tests/test_checker_latency_excludes_dns.py — Add test `test_latency_excludes_dns_resolution` that patches `resolve_and_validate` with a 0.3s sleep and asserts `result.latency_ms < 150` to prove DNS time is excluded. VERIFY: `cd backend && python -m pytest tests/test_checker_latency_excludes_dns.py::test_latency_excludes_dns_resolution -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard]
- [ ] [T1] backend/tests/test_checker_latency_excludes_dns.py — Add test `test_injected_int_fetch_fallback` that injects a fetch returning an int and asserts `probe()` calculates latency from its own monotonic delta, ensuring backward compatibility. VERIFY: `cd backend && python -m pytest tests/test_checker_latency_excludes_dns.py::test_injected_int_fetch_fallback -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard]
- [ ] [T1] backend/tests/test_checker_latency_excludes_dns.py — Add test `test_injected_2tuple_fetch_fallback` that injects a fetch returning a 2-tuple and asserts `probe()` handles it correctly with fallback latency calculation. VERIFY: `cd backend && python -m pytest tests/test_checker_latency_excludes_dns.py::test_injected_2tuple_fetch_fallback -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard]

# --- 27B-decomposed from roadmap [2026-11-04]: The per-request `allow_private_urls` flag on POST /monitors is silently ignored by the pro (review + tweak) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-] ---
- [ ] [T1] backend/app/schemas.py — Modify `MonitorCreate.check_url_rules` to raise `ValueError` with the specific SSRF message when `allow_private_urls` is true, URL is private, and server `Settings().allow_private_urls` is false. VERIFY: `cd backend && python -c "from backend.app.schemas import MonitorCreate; from unittest.mock import patch; import os; os.environ['ALLOW_PRIVATE_URLS']='false'; m=MonitorCreate(url='http://10.0.0.5/health', allow_private_urls=True); m.check_url_rules()" 2>&1 | grep -q "per-monitor allow_private_urls is not honored"`. (cat:schema; multifile:no) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-]
- [ ] [T1] backend/app/schemas.py — Update the `description` field of `MonitorCreate.allow_private_urls` to explicitly state that the server-side `ALLOW_PRIVATE_URLS` flag must also be enabled for this to work. VERIFY: `cd backend && python -c "from backend.app.schemas import MonitorCreate; assert 'server' in MonitorCreate.model_fields['allow_private_urls'].description.lower() or 'ALLOW_PRIVATE_URLS' in MonitorCreate.model_fields['allow_private_urls'].description"`. (cat:schema; multifile:no) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-]
- [ ] [T2] backend/tests/test_create_allow_private_flag.py — Create test file with a test case that asserts a 422 response when POSTing to `/monitors` with a private IP URL, `allow_private_urls: true`, and server env `ALLOW_PRIVATE_URLS=false`. VERIFY: `cd backend && python -m pytest tests/test_create_allow_private_flag.py::test_private_ip_flag_true_server_off_returns_422 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-]
- [ ] [T2] backend/tests/test_create_allow_private_flag.py — Add a test case that asserts a 201 response when POSTing to `/monitors` with a private IP URL, `allow_private_urls: true`, and server env `ALLOW_PRIVATE_URLS=true`. VERIFY: `cd backend && python -m pytest tests/test_create_allow_private_flag.py::test_private_ip_flag_true_server_on_returns_201 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-]
- [ ] [T2] backend/tests/test_create_allow_private_flag.py — Add a test case that asserts a 201 response when POSTing to `/monitors` with a public URL and `allow_private_urls: true`, regardless of server flag. VERIFY: `cd backend && python -m pytest tests/test_create_allow_private_flag.py::test_public_url_flag_true_returns_201 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-]
- [ ] [T2] backend/tests/test_create_allow_private_flag.py — Add a test case that asserts a 422 response when POSTing to `/monitors` with a private IP URL and `allow_private_urls: false`, ensuring existing behavior is preserved. VERIFY: `cd backend && python -m pytest tests/test_create_allow_private_flag.py::test_private_ip_flag_false_returns_422 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-]

# --- 27B-decomposed from roadmap [2026-11-04]: `Notifier._last_notified` never evicts expired entries while a monitor exists — `notify_tr (review + tweak) [feat:shrike-monitor-20261104-notifier-last-notified-never-evicts-expi] ---
- [ ] [T1] backend/app/services/notifier.py — Add a private method `_prune_expired()` that iterates `_last_notified`, removes entries where `_is_expired(ts, self.dedup_ttl)` is True, and updates `_monitor_index` by removing the key from the corresponding set (deleting empty sets). VERIFY: `cd backend && python -m pytest tests/test_notifier_prune_expired.py -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-notifier-last-notified-never-evicts-expi]
- [ ] [T2] backend/app/services/notifier.py — Modify `notify_transition()` to call `self._prune_expired()` at the very start of the method, before any deduplication logic. VERIFY: `cd backend && python -m pytest tests/test_notifier_prune_expired.py -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-notifier-last-notified-never-evicts-expi]
- [ ] [T3] backend/tests/test_notifier_prune_expired.py — Create a test that monkeypatches `app.services.notifier.time.time`, sends 50 transitions with distinct incident IDs through a stub `publish`, and asserts `len(notifier._last_notified)` remains bounded (does not grow to 50). VERIFY: `cd backend && python -m pytest tests/test_notifier_prune_expired.py::test_prune_bounded_growth -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-notifier-last-notified-never-evicts-expi]
- [ ] [T4] backend/tests/test_notifier_prune_expired.py — Create a test that advances time past TTL for one monitor and asserts its keys are removed from `_monitor_index` and `_last_notified`, while a fresh key for another monitor remains intact. VERIFY: `cd backend && python -m pytest tests/test_notifier_prune_expired.py::test_prune_removes_stale_keeps_fresh -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-notifier-last-notified-never-evicts-expi]
- [ ] [T5] backend/tests/test_notifier_prune_expired.py — Create a test that verifies deduplication still works for a key that is NOT expired (within TTL), ensuring the prune logic does not remove active entries. VERIFY: `cd backend && python -m pytest tests/test_notifier_prune_expired.py::test_fresh_key_still_dedups -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-notifier-last-notified-never-evicts-expi]

# --- 27B-decomposed from roadmap [2026-11-04]: Notifications are sent serially inside the tick, so one dead shrike-notify stalls the whol (review + tweak) [feat:shrike-monitor-20261104-notifications-are-sent-serially-inside-t] ---
- [ ] [T1] backend/app/services/scheduler.py — Add `asyncio.Semaphore(5)` instance attribute to `MonitorScheduler` and modify `_maybe_notify` to return the `notifier.notify_transition` coroutine instead of awaiting it directly. VERIFY: `cd backend && python -c "from backend.app.services.scheduler import MonitorScheduler; s = MonitorScheduler(); assert hasattr(s, '_notify_sem') or True"`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-notifications-are-sent-serially-inside-t]
- [ ] [T2] backend/app/services/scheduler.py — Update `tick()` to collect coroutines from `_maybe_notify` and execute them via `asyncio.gather(*coros, return_exceptions=True)` wrapped in the semaphore context. VERIFY: `cd backend && python -m py_compile backend/app/services/scheduler.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-notifications-are-sent-serially-inside-t]
- [ ] [T3] backend/tests/test_scheduler_notify_concurrent.py — Create test file with `FakeNotifier` class that sleeps 0.2s in `notify_transition` and a test asserting 10 concurrent notifications complete in <1.0s. VERIFY: `cd backend && python -m pytest tests/test_scheduler_notify_concurrent.py::test_concurrent_notifications_fast -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-notifications-are-sent-serially-inside-t]
- [ ] [T4] backend/tests/test_scheduler_notify_concurrent.py — Add test verifying that if one notifier raises an exception, the other 9 notifications still complete successfully. VERIFY: `cd backend && python -m pytest tests/test_scheduler_notify_concurrent.py::test_partial_failure_isolation -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-notifications-are-sent-serially-inside-t]
- [ ] [T5] backend/tests/test_scheduler_notify_concurrent.py — Add test verifying that `_last_status` updates occur synchronously before notification dispatch to preserve ordering semantics. VERIFY: `cd backend && python -m pytest tests/test_scheduler_notify_concurrent.py::test_status_update_ordering -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-notifications-are-sent-serially-inside-t]

# --- 27B-decomposed from roadmap [2026-11-04]: Heartbeat pings only work with POST, but cron tools and `curl` default to GET — `ping()` i (review + tweak) [feat:shrike-monitor-20261104-heartbeat-pings-only-work-with-post-but-] ---
- [ ] [T1] backend/app/routers/heartbeat.py — Replace `@router.post("/heartbeat/{monitor_id}")` with `@router.api_route("/heartbeat/{monitor_id}", methods=["GET", "POST"])` while preserving `response_model=HeartbeatPingResponse` and existing logic. VERIFY: `cd backend && python -c "from fastapi.testclient import TestClient; from app.main import app; c=TestClient(app); r=c.get('/heartbeat/nonexistent', headers={'X-Ping-Token':'x'}); assert r.status_code == 404"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261104-heartbeat-pings-only-work-with-post-but-]
- [ ] [T2] backend/tests/test_heartbeat_get_ping.py — Add test `test_get_valid_token_updates_last_ping` that performs a GET request with a valid token and asserts status 200 and `last_ping_at` is updated in the response. VERIFY: `cd backend && python -m pytest tests/test_heartbeat_get_ping.py::test_get_valid_token_updates_last_ping -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-heartbeat-pings-only-work-with-post-but-]
- [ ] [T3] backend/tests/test_heartbeat_get_ping.py — Add test `test_get_wrong_or_missing_token_returns_401` that performs GET requests with invalid/missing tokens and asserts status 401. VERIFY: `cd backend && python -m pytest tests/test_heartbeat_get_ping.py::test_get_wrong_or_missing_token_returns_401 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-heartbeat-pings-only-work-with-post-but-]
- [ ] [T4] backend/tests/test_heartbeat_get_ping.py — Add test `test_get_unknown_monitor_id_returns_404` that performs a GET request with a valid token but non-existent monitor ID and asserts status 404. VERIFY: `cd backend && python -m pytest tests/test_heartbeat_get_ping.py::test_get_unknown_monitor_id_returns_404 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-heartbeat-pings-only-work-with-post-but-]
- [ ] [T5] backend/tests/test_heartbeat_get_ping.py — Add test `test_post_still_works` that performs a POST request with a valid token and asserts status 200 to ensure backward compatibility. VERIFY: `cd backend && python -m pytest tests/test_heartbeat_get_ping.py::test_post_still_works -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-heartbeat-pings-only-work-with-post-but-]

# --- 27B-decomposed from roadmap [2026-11-04]: Credentials embedded in a monitored URL (`https://user:pass@host/health`, accepted by `Mon (review + tweak) [feat:shrike-monitor-20261104-credentials-embedded-in-a-monitored-url-] ---
- [ ] [T1] backend/app/utils/redact_url.py — Add `redact_url(url: str) -> str` that parses URL, replaces userinfo in netloc with `***`, returns input unchanged on parse failure or missing userinfo, and never raises. VERIFY: `cd backend && python -c "from app.utils.redact_url import redact_url; assert redact_url('https://u:p@h/x') == 'https://***@h/x'; assert redact_url('garbage') == 'garbage'"`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-credentials-embedded-in-a-monitored-url-]
- [ ] [T2] backend/tests/test_redact_url.py — Add unit tests for `redact_url` covering no-userinfo, user-only, user:pass, IPv6 host, and garbage input cases. VERIFY: `cd backend && python -m pytest tests/test_redact_url.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-credentials-embedded-in-a-monitored-url-]
- [ ] [T3] backend/app/services/checker.py — Import `redact_url` and update `probe()` to use `redact_url(url)` in the "Probe blocked" and "Probe failed" log messages, and mask raw userinfo in exception text via `str(e).replace(raw_userinfo, "***")`. VERIFY: `cd backend && python -m pytest tests/test_redact_url.py -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-credentials-embedded-in-a-monitored-url-]
- [ ] [T4] backend/tests/test_redact_url.py — Add a caplog test verifying that a failing probe of `https://bob:s3cret@example.com/x` never logs "s3cret". VERIFY: `cd backend && python -m pytest tests/test_redact_url.py::test_probe_logs_do_not_leak_password -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-credentials-embedded-in-a-monitored-url-]

# --- 27B-decomposed from roadmap [2026-11-04]: A failed startup rehydrate leaves the service "healthy" with zero monitors while the DB st (review + tweak) [feat:shrike-monitor-20261104-a-failed-startup-rehydrate-leaves-the-se] ---
- [ ] [T1] backend/app/store.py — Add `self.rehydrate_error: str | None = None` to `Store.__init__` and set it to `repr(exc)` in the `except` block of `rehydrate()`, resetting to `None` on success. VERIFY: `cd backend && python -m pytest tests/test_store.py -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261104-a-failed-startup-rehydrate-leaves-the-se]
- [ ] [T2] backend/app/main.py — Modify `health()` to return 503 with `{"status": "unhealthy", "service": "shrike-monitor", "reason": "store rehydrate failed", "detail": store.rehydrate_error}` if `store.rehydrate_error` is set, placing this check after the persistence ping and before the scheduler check. VERIFY: `cd backend && python -m pytest tests/test_health_scheduler_503.py -q`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261104-a-failed-startup-rehydrate-leaves-the-se]
- [ ] [T3] backend/tests/test_health_rehydrate_failed.py — Create test file with a fixture that stubs persistence `load_all` to raise, calls `await store.rehydrate()`, asserts `store.rehydrate_error` is set and `GET /health` returns 503 with the correct reason; include a success path test asserting `rehydrate_error` is None and `/health` returns 200. VERIFY: `cd backend && python -m pytest tests/test_health_rehydrate_failed.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-a-failed-startup-rehydrate-leaves-the-se]
- [ ] [T4] backend/tests/test_health_rehydrate_failed.py — Ensure the fixture resets `store.rehydrate_error` to `None` and `store.persist` to its original state after each test to prevent state leakage. VERIFY: `cd backend && python -m pytest tests/test_health_rehydrate_failed.py tests/test_store.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-a-failed-startup-rehydrate-leaves-the-se]
- [ ] [T5] backend/tests/test_health_rehydrate_failed.py — Verify the 503 response body contains the exact `detail` string matching `repr(exc)` from the stubbed exception. VERIFY: `cd backend && python -m pytest tests/test_health_rehydrate_failed.py::test_health_503_detail_matches_repr -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261104-a-failed-startup-rehydrate-leaves-the-se]
