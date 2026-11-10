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

# --- 27B-decomposed from roadmap [2026-11-04]: Recorded latency includes the SSRF guard's DNS resolution, inflating latency and causing f (review + tweak) [feat:shrike-monitor-20261104-recorded-latency-includes-the-ssrf-guard] ---

# --- 27B-decomposed from roadmap [2026-11-04]: The per-request `allow_private_urls` flag on POST /monitors is silently ignored by the pro (review + tweak) [feat:shrike-monitor-20261104-the-per-request-allow-private-urls-flag-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: `Notifier._last_notified` never evicts expired entries while a monitor exists — `notify_tr (review + tweak) [feat:shrike-monitor-20261104-notifier-last-notified-never-evicts-expi] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Notifications are sent serially inside the tick, so one dead shrike-notify stalls the whol (review + tweak) [feat:shrike-monitor-20261104-notifications-are-sent-serially-inside-t] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Heartbeat pings only work with POST, but cron tools and `curl` default to GET — `ping()` i (review + tweak) [feat:shrike-monitor-20261104-heartbeat-pings-only-work-with-post-but-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: Credentials embedded in a monitored URL (`https://user:pass@host/health`, accepted by `Mon (review + tweak) [feat:shrike-monitor-20261104-credentials-embedded-in-a-monitored-url-] ---

# --- 27B-decomposed from roadmap [2026-11-04]: A failed startup rehydrate leaves the service "healthy" with zero monitors while the DB st (review + tweak) [feat:shrike-monitor-20261104-a-failed-startup-rehydrate-leaves-the-se] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `humanize_seconds()` renders 59.96 s as "60.0s" instead of rolling over to "1m 0s" — in ba (review + tweak) [feat:shrike-monitor-20261106-humanize-seconds-renders-59-96-s-as-60-0] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A whitespace-only monitor name is accepted by the API, and `validate_name()` accepts a tra (review + tweak) [feat:shrike-monitor-20261106-a-whitespace-only-monitor-name-is-accept] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A monitor URL with no host, embedded whitespace or an internal-only hostname is accepted a (review + tweak) [feat:shrike-monitor-20261106-a-monitor-url-with-no-host-embedded-whit] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The heartbeat ping token is written to the access log in clear text — README.md says the ` (review + tweak) [feat:shrike-monitor-20261106-the-heartbeat-ping-token-is-written-to-t] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `HeartbeatPingResponse` carries a stray `body_contains` field that is always null — the la (review + tweak) [feat:shrike-monitor-20261106-heartbeatpingresponse-carries-a-stray-bo] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The status console issues one request per monitor on every 15 s refresh (N+1) — `refresh() (review + tweak) [feat:shrike-monitor-20261106-the-status-console-issues-one-request-pe] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The console is not announced to assistive tech and has no landmarks — backend/app/static/c (review + tweak) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `GET /console` is served without any security headers — `console()` in backend/app/main.py (review + tweak) [feat:shrike-monitor-20261106-get-console-is-served-without-any-securi] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The Docker build context has no `.dockerignore`, so `COPY . .` bakes `.venv`, `.env`, `mon (review + tweak) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig] ---

# --- 27B-decomposed from roadmap [2026-11-06]: CHANGELOG.md `[Unreleased]` documents helpers that do not exist and omits everything actua (review + tweak) [feat:shrike-monitor-20261106-changelog-md-unreleased-documents-helper] ---

# --- 27B-decomposed from roadmap [2026-11-06]: README's API table omits four live endpoints and nothing guards it against drift — README. (review + tweak) [feat:shrike-monitor-20261106-readme-s-api-table-omits-four-live-endpo] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A NOTIFY_URL without a scheme silently disables alerting while logging only retry warnings (review + tweak) [feat:shrike-monitor-20261106-a-notify-url-without-a-scheme-silently-d] ---

# --- 27B-decomposed from roadmap [2026-11-06]: OpenAPI under-documents the ping and token-regeneration endpoints — `ping()` in backend/ap (review + tweak) [feat:shrike-monitor-20261106-openapi-under-documents-the-ping-and-tok] ---

# --- 27B-decomposed from roadmap [2026-11-06]: Responses that carry a secret ping token are cacheable — `create_monitor()` (POST /monitor (review + tweak) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token] ---

# --- 27B-decomposed from roadmap [2026-11-06]: PATCH /monitors/{id} with {"timeout_seconds": null} corrupts the monitor and then 500s eve (review + tweak) [feat:shrike-monitor-20261106-patch-monitors-id-with-timeout-seconds-n] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The startup log line prints the full MONITOR_DATABASE_URL including the database password  (review + tweak) [feat:shrike-monitor-20261106-the-startup-log-line-prints-the-full-mon] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `redact_text()` corrupts error messages when the URL userinfo is short (a username with no (review + tweak) [feat:shrike-monitor-20261106-redact-text-corrupts-error-messages-when] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `redact_url()` leaves credentials that are passed in the query string, and `probe()` logs  (review + tweak) [feat:shrike-monitor-20261106-redact-url-leaves-credentials-that-are-p] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `humanize_seconds()` renders 3599.96 s as "0h 59m" instead of "1h 0m" -- in backend/app/ut (review + tweak) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h] ---

# --- 27B-decomposed from roadmap [2026-11-06]: `calculate_backoff_delay()` raises OverflowError for any attempt of about 1024 or more --  (review + tweak) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe] ---

# --- 27B-decomposed from roadmap [2026-11-06]: SCHEDULER_TICK_SECONDS accepts absurdly small and absurdly large values -- `Settings._fall (review + tweak) [feat:shrike-monitor-20261106-scheduler-tick-seconds-accepts-absurdly-] ---

# --- 27B-decomposed from roadmap [2026-11-06]: NOTIFY_TOKEN and NOTIFY_TOPIC are used verbatim, so a trailing newline from a pasted secre (review + tweak) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v] ---

# --- 27B-decomposed from roadmap [2026-11-06]: A monitor with no recorded results reports `sla_met: false` and `uptime_percent: 0.0`, i.e (review + tweak) [feat:shrike-monitor-20261106-a-monitor-with-no-recorded-results-repor] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The API's 401 responses carry no `WWW-Authenticate` header -- `require_api_token()` (backe (review + tweak) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut] ---
- [ ] [T1] backend/tests/test_auth_www_authenticate.py — Add test verifying 200 response does NOT include `WWW-Authenticate` header when token is valid. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_www_authenticate.py::test_valid_token_no_www_authenticate`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut]
- [ ] [T1] backend/tests/test_auth_www_authenticate.py — Add test verifying 401 response detail message remains "missing or invalid API token". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_www_authenticate.py::test_detail_message_unchanged`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut]

# --- 27B-decomposed from roadmap [2026-11-06]: `_extract_bearer_token()` mis-parses harmless whitespace variants, so a correct token is r (review + tweak) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless] ---
- [ ] [T1] backend/app/auth.py — Replace `authorization.partition(" ")` logic in `_extract_bearer_token` with `parts = authorization.split(None, 1)` and return `parts[1].strip()` if scheme is Bearer (case-insensitive) and len(parts)==2, else "". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_bearer_whitespace.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless]
- [ ] [T2] backend/tests/test_auth_bearer_whitespace.py — Add pure unit tests for `_extract_bearer_token` verifying "Bearer abc", "bearer abc", "BEARER abc", "Bearer  abc", "Bearer\tabc", "Bearer abc " all return "abc", and None, "", "Bearer", "Bearer ", "Basic abc" return "". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_bearer_whitespace.py::TestExtractBearerToken`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless]
- [ ] [T3] backend/tests/test_auth_bearer_whitespace.py — Add TestClient integration test verifying that a request with header "Bearer  <valid_token>" (two spaces) returns 200 and "Bearer wrong" returns 401. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_bearer_whitespace.py::TestClientBearerWhitespace`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless]
- [ ] [T4] backend/tests/test_monitors_auth.py — Verify existing auth tests still pass with the updated whitespace handling in `_extract_bearer_token`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitors_auth.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless]
- [ ] [T5] backend/tests/test_monitors_api_token_auth.py — Verify existing API token auth tests still pass with the updated whitespace handling in `_extract_bearer_token`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitors_api_token_auth.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless]

# --- 27B-decomposed from roadmap [2026-11-06]: The OpenAPI schema documents none of the error responses the /monitors routes really retur (review + tweak) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the] ---
- [ ] [T3] backend/app/routers/monitors.py — Add `responses={404: {"description": "Monitor not found"}}` to the decorators for `get_monitor`, `update_monitor`, `delete_monitor`, `get_monitor_status`, `get_monitor_results`, and `get_monitor_incidents`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_id_routes_have_404 tests/test_openapi_error_responses.py::test_subroutes_have_404`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T3] backend/app/routers/monitors.py — Add `responses={507: {"description": "Store is full (max monitors reached)"}}` to the decorator for `create_monitor`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_post_monitors_has_507`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T3] backend/app/routers/monitors.py — Pass `responses={401: {"description": "Missing or invalid API token"}}` to the `APIRouter(...)` constructor. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_all_monitors_routes_have_401`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T1] backend/tests/test_openapi_error_responses.py — Add test asserting `POST /monitors` OpenAPI responses include "507" with description "Store is full (max monitors reached)". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_post_monitors_has_507`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T1] backend/tests/test_openapi_error_responses.py — Add test asserting `GET /monitors/{monitor_id}`, `PATCH /monitors/{monitor_id}`, and `DELETE /monitors/{monitor_id}` OpenAPI responses include "404" with description "Monitor not found". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_id_routes_have_404`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T1] backend/tests/test_openapi_error_responses.py — Add test asserting `GET /monitors/{monitor_id}/status`, `GET /monitors/{monitor_id}/results`, and `GET /monitors/{monitor_id}/incidents` OpenAPI responses include "404" with description "Monitor not found". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_subroutes_have_404`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T1] backend/tests/test_openapi_error_responses.py — Add test asserting all `/monitors` paths and methods except `POST /monitors/{monitor_id}/regenerate-ping-token` include "401" in OpenAPI responses. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_all_monitors_routes_have_401`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T1] backend/tests/test_openapi_error_responses.py — Add test asserting `GET /monitors` and `GET /monitors/status` do NOT include "404" in OpenAPI responses. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_list_and_status_no_404`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]
- [ ] [T1] backend/tests/test_openapi_error_responses.py — Add test asserting `/health` and `/heartbeat/{monitor_id}` do NOT include "401" in OpenAPI responses. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_error_responses.py::test_health_heartbeat_no_401`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the]

# --- 27B-decomposed from roadmap [2026-11-06]: README's Status semantics section never says heartbeat monitors can be `degraded` or how a (review + tweak) [feat:shrike-monitor-20261106-readme-s-status-semantics-section-never-] ---
- [ ] [T1] backend/app/models.py — Update `heartbeat_status` docstring to explicitly document the `created_at` baseline for never-pinged heartbeats and the specific time windows for `pending`, `degraded`, and `down` states. VERIFY: `cd backend && .venv/bin/python -c "import inspect; from app.models import heartbeat_status; assert 'created_at' in inspect.getdoc(heartbeat_status)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-readme-s-status-semantics-section-never-]
- [ ] [T2] README.md — Add a new subsection or bullets under "Status semantics" for heartbeats, explicitly stating: "heartbeat degraded window" is `interval_seconds` to `interval_seconds + grace_seconds`, "never-pinged heartbeat" uses `created_at` as baseline, and `grace_seconds` only widens the gap before `down`. VERIFY: `grep -q "heartbeat degraded window" README.md && grep -q "never-pinged heartbeat" README.md && grep -q "created_at" README.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261106-readme-s-status-semantics-section-never-]
- [ ] [T3] README.md — Insert a code block or table row in the heartbeat section with the exact string `interval 60, grace 30: up <=60s, degraded 61-90s, down >90s` to serve as the parseable source of truth for tests. VERIFY: `grep -q "interval 60, grace 30: up <=60s, degraded 61-90s, down >90s" README.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261106-readme-s-status-semantics-section-never-]
- [ ] [T4] backend/tests/test_readme_heartbeat_semantics.py — Create new test file that asserts the presence of the three required phrases ("heartbeat degraded window", "never-pinged heartbeat", "created_at") in `README.md`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_heartbeat_semantics.py::test_readme_contains_required_phrases`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-readme-s-status-semantics-section-never-]
- [ ] [T5] backend/tests/test_readme_heartbeat_semantics.py — Add a test that regex-parses the `interval 60, grace 30: up <=60s, degraded 61-90s, down >90s` line from `README.md` and asserts `heartbeat_status` returns 'up' at now=60, 'degraded' at now=75, and 'down' at now=91 for a monitor with `interval_seconds=60, grace_seconds=30`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_heartbeat_semantics.py::test_heartbeat_status_matches_readme_table`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-readme-s-status-semantics-section-never-]

# --- 27B-decomposed from roadmap [2026-11-09]: A monitor URL with a newline, tab, space or an out-of-range/non-numeric port is accepted a (review + tweak) [feat:shrike-monitor-20261109-a-monitor-url-with-a-newline-tab-space-o] ---
- [ ] [T1] backend/app/schemas.py — Add whitespace/control character validation at the start of `_url_host_problem` to return "url must not contain whitespace or control characters" if any char in the raw url has `ch.isspace()` or `ord(ch) < 32` or `ord(ch) == 127`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_url_host_validation.py::test_url_host_problem_whitespace_control -k "whitespace"` (cat:python; multifile:no) [feat:shrike-monitor-20261109-a-monitor-url-with-a-newline-tab-space-o]
- [ ] [T1] backend/app/schemas.py — Add port validation in `_url_host_problem` after the host check, wrapping `parsed.port` access in `try/except ValueError` to return "url port is invalid" on exception, and also returning "url port is invalid" if port is not None and not in 1..65535. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_url_host_validation.py::test_url_host_problem_port_invalid -k "port"` (cat:python; multifile:no) [feat:shrike-monitor-20261109-a-monitor-url-with-a-newline-tab-space-o]
- [ ] [T2] backend/tests/test_url_host_validation.py — Add parametrized test cases for the seven invalid URLs (`"http://example.com/\n"`, `"http://exa\nmple.com/"`, `"http://example.com/a b"`, `"http://example.com\t/x"`, `"http://example.com:99999/"`, `"http://example.com:abc/"`, `"http://example.com:0/"`) asserting `_url_host_problem` returns a non-None string. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_url_host_validation.py::test_url_host_problem_invalid_urls` (cat:test; multifile:no) [feat:shrike-monitor-20261109-a-monitor-url-with-a-newline-tab-space-o]
- [ ] [T2] backend/tests/test_url_host_validation.py — Add parametrized test cases for the four valid URLs (`"http://example.com/health"`, `"https://api.example.com:8443/x"`, `"http://[2001:4860:4860::8888]:8080/"`, `"http://example.com/a%20b"`) asserting `_url_host_problem` returns None. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_url_host_validation.py::test_url_host_problem_valid_urls` (cat:test; multifile:no) [feat:shrike-monitor-20261109-a-monitor-url-with-a-newline-tab-space-o]

# --- 27B-decomposed from roadmap [2026-11-09]: `Store.update()` will overwrite any Monitor attribute including `id`, `created_at` and eve (review + tweak) [feat:shrike-monitor-20261109-store-update-will-overwrite-any-monitor-] ---
- [ ] [T1] backend/app/store.py — Modify `_apply_update_fields` to filter keys against `dataclasses.fields(Monitor)` names and explicitly exclude `{"id", "created_at"}`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_store.py::test_apply_update_fields_pure`. (cat:python; multifile:no) [feat:shrike-monitor-20261109-store-update-will-overwrite-any-monitor-]
- [ ] [T2] backend/tests/test_store.py — Add unit test asserting `_apply_update_fields(mon, {"id": "zzz", "created_at": 5.0, "to_dict": 1, "name": "x"})` returns exactly `{"name": "x"}`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_store.py::test_apply_update_fields_pure`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-store-update-will-overwrite-any-monitor-]
- [ ] [T3] backend/tests/test_store.py — Add async test verifying `await store.update(mon.id, id="zzz", name="b")` preserves `mon.id`, updates `name` to "b", and keeps `callable(mon.to_dict)` True. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_store.py::test_update_immutable_fields`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-store-update-will-overwrite-any-monitor-]
- [ ] [T4] backend/tests/test_store.py — Run full test suite for store to ensure no regressions in existing update logic. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_store.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-store-update-will-overwrite-any-monitor-]

# --- 27B-decomposed from roadmap [2026-11-09]: The notifier retries permanent 4xx publish errors (bad token, wrong topic) with backoff sl (review + tweak) [feat:shrike-monitor-20261109-the-notifier-retries-permanent-4xx-publi] ---
- [ ] [T1] backend/app/services/notifier.py — In `notify_transition()`, inside the `except Exception as e:` block, add a check for `isinstance(e, httpx.HTTPStatusError)` where `400 <= e.response.status_code < 500` and status is not 408 or 429; if true, log `logger.error("Notify rejected for monitor %s with HTTP %d; not retrying", monitor_id, e.response.status_code)` and `return False` immediately. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notifier.py::test_notify_transition_401_no_retry`. (cat:python; multifile:no) [feat:shrike-monitor-20261109-the-notifier-retries-permanent-4xx-publi]
- [ ] [T2] backend/tests/test_notifier.py — Add a helper function `_make_http_status_error(code)` that constructs `httpx.HTTPStatusError("x", request=httpx.Request("POST", "http://test"), response=httpx.Response(code, request=httpx.Request("POST", "http://test")))`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notifier.py::test_helper_make_http_status_error`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-the-notifier-retries-permanent-4xx-publi]
- [ ] [T3] backend/tests/test_notifier.py — Add test `test_notify_transition_401_no_retry` that mocks publish to raise `_make_http_status_error(401)`, asserts publish is called exactly once, `notify_transition` returns False, and `sleep_func` is never awaited. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notifier.py::test_notify_transition_401_no_retry`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-the-notifier-retries-permanent-4xx-publi]
- [ ] [T4] backend/tests/test_notifier.py — Add test `test_notify_transition_404_no_retry` that mocks publish to raise `_make_http_status_error(404)`, asserts publish is called exactly once, `notify_transition` returns False, and `sleep_func` is never awaited. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notifier.py::test_notify_transition_404_no_retry`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-the-notifier-retries-permanent-4xx-publi]
- [ ] [T5] backend/tests/test_notifier.py — Add test `test_notify_transition_503_retries` that mocks publish to raise `_make_http_status_error(503)`, asserts publish is called 3 times (max_retries=2), and `sleep_func` is awaited. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notifier.py::test_notify_transition_503_retries`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-the-notifier-retries-permanent-4xx-publi]

# --- 27B-decomposed from roadmap [2026-11-09]: `_codes_from_str()` accepts booleans, floats, numeric strings and out-of-range numbers fro (review + tweak) [feat:shrike-monitor-20261109-codes-from-str-accepts-booleans-floats-n] ---
- [ ] [T1] backend/app/persistence.py — Modify `_codes_from_str` to return `None` if `parsed` is not a list or if any element fails `type(p) is int and 100 <= p <= 599`, otherwise return the list of ints. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence.py -k "test_codes_from_str"`. (cat:python; multifile:no) [feat:shrike-monitor-20261109-codes-from-str-accepts-booleans-floats-n]
- [ ] [T2] backend/tests/test_persistence.py — Add test cases for `_codes_from_str` verifying valid input `'[200, 201]'` returns `[200, 201]`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence.py -k "test_codes_from_str_valid"`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-codes-from-str-accepts-booleans-floats-n]
- [ ] [T3] backend/tests/test_persistence.py — Add test cases for `_codes_from_str` verifying invalid inputs (`None`, `''`, `'not json'`, `'{"a": 1}'`) return `None`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence.py -k "test_codes_from_str_invalid"`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-codes-from-str-accepts-booleans-floats-n]
- [ ] [T4] backend/tests/test_persistence.py — Add test cases for `_codes_from_str` verifying type-violating inputs (`'[200, true]'`, `'[200.5]'`, `'["200"]'`) return `None`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence.py -k "test_codes_from_str_type_violation"`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-codes-from-str-accepts-booleans-floats-n]
- [ ] [T5] backend/tests/test_persistence.py — Add test cases for `_codes_from_str` verifying out-of-range inputs (`'[99]'`, `'[99999]'`) return `None`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_persistence.py -k "test_codes_from_str_range"`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-codes-from-str-accepts-booleans-floats-n]

# --- 27B-decomposed from roadmap [2026-11-09]: `tick()`'s overall gather timeout ignores the per-probe 5 s grace, so a fleet of slow 60 s (review + tweak) [feat:shrike-monitor-20261109-tick-s-overall-gather-timeout-ignores-th] ---
- [ ] [T3] backend/app/services/scheduler.py — In `MonitorScheduler.tick()`, modify the call to `compute_total_timeout` to pass `per_probe_timeout=compute_probe_cap(max_per_probe_timeout)` instead of `per_probe_timeout=max_per_probe_timeout`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_scheduler_total_timeout_cap.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261109-tick-s-overall-gather-timeout-ignores-th]
- [ ] [T1] backend/tests/test_scheduler_total_timeout_cap.py — Add test file with `test_spy_records_probe_cap_for_11_monitors` and `test_spy_records_probe_cap_for_single_monitor` verifying `compute_total_timeout` receives `per_probe_timeout` equal to `timeout_seconds + 5.0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_scheduler_total_timeout_cap.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-tick-s-overall-gather-timeout-ignores-th]
- [ ] [T4] backend/tests/test_scheduler_tick_gather.py — Update existing timeout assertions to expect the new grace-inclusive total (e.g., 65s per probe instead of 60s) to match the corrected `compute_total_timeout` input. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_scheduler_tick_gather.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-tick-s-overall-gather-timeout-ignores-th]
- [ ] [T4] backend/tests/test_probe_budget.py — Update any hardcoded timeout calculations to include the 5s probe cap grace period to ensure budget checks align with the new total timeout logic. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_probe_budget.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-tick-s-overall-gather-timeout-ignores-th]
- [ ] [T4] backend/tests/test_scheduler.py — Verify existing scheduler tests pass with the updated timeout calculation, updating any mocks or expected values for `compute_total_timeout` calls if they assert on the raw `timeout_seconds`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_scheduler.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-tick-s-overall-gather-timeout-ignores-th]

# --- 27B-decomposed from roadmap [2026-11-09]: `percentile()` gives a misleading "cannot convert float NaN to integer" error for `p=nan`  (review + tweak) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con] ---
- [ ] [T1] backend/app/utils/percentile.py — Change the guard condition in `percentile` from `if p < 0 or p > 100:` to `if not (0 <= p <= 100):` to correctly reject NaN and out-of-range values. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_percentile_util.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con]
- [ ] [T2] backend/tests/test_percentile_util.py — Add a test case asserting that `percentile([1, 2], float("nan"))` raises `ValueError` with message matching "p must be between 0 and 100". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_percentile_util.py::test_percentile_nan_raises_value_error`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con]
- [ ] [T2] backend/tests/test_percentile_util.py — Add a test case asserting that `percentile([1, 2, 3], -0.1)` raises `ValueError` with message matching "p must be between 0 and 100". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_percentile_util.py::test_percentile_negative_raises_value_error`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con]
- [ ] [T2] backend/tests/test_percentile_util.py — Add a test case asserting that `percentile([1, 2, 3], 100.1)` raises `ValueError` with message matching "p must be between 0 and 100". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_percentile_util.py::test_percentile_over_100_raises_value_error`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con]
- [ ] [T2] backend/tests/test_percentile_util.py — Add a test case asserting that `percentile([1, 2, 3], 0)` returns `1.0` and `percentile([1, 2, 3], 100)` returns `3.0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_percentile_util.py::test_percentile_boundaries`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con]
- [ ] [T3] backend/tests/test_percentile_util.py — Ensure the test file imports `percentile` from `app.utils.percentile` if it currently only imports from `app.models`, to guarantee the correct module is tested. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_percentile_util.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con]

# --- 27B-decomposed from roadmap [2026-11-10]: The notifier sends `priority: "medium"` for 3xx, 4xx and unknown status codes, but shrike- (review + tweak) [feat:shrike-monitor-20261110-the-notifier-sends-priority-medium-for-3] ---
- [ ] [T1] backend/app/utils/severity_from_code.py — Change `severity_to_priority` to return `"default"` for `client_error`, `redirect`, and `unknown` categories instead of `"medium"`, and update the docstring to reflect valid shrike-notify priorities. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_severity_from_code.py -k "test_severity_to_priority_404_default or test_severity_to_priority_301_default"`. (cat:python; multifile:no) [feat:shrike-monitor-20261110-the-notifier-sends-priority-medium-for-3]
- [ ] [T2] backend/tests/test_severity_from_code.py — Rename `test_severity_to_priority_404_medium` to `test_severity_to_priority_404_default` and update its assertion to expect `"default"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_severity_from_code.py::test_severity_to_priority_404_default`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-the-notifier-sends-priority-medium-for-3]
- [ ] [T3] backend/tests/test_severity_from_code.py — Rename `test_severity_to_priority_301_medium` to `test_severity_to_priority_301_default` and update its assertion to expect `"default"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_severity_from_code.py::test_severity_to_priority_301_default`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-the-notifier-sends-priority-medium-for-3]
- [ ] [T4] backend/tests/test_severity_from_code.py — Add `test_severity_to_priority_always_valid_notify_priority` that loops over codes `[None, -1, 100, 200, 301, 404, 500, 999]` and asserts the result of `severity_to_priority` is in `{"min", "low", "default", "high", "urgent"}`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_severity_from_code.py::test_severity_to_priority_always_valid_notify_priority`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-the-notifier-sends-priority-medium-for-3]
- [ ] [T5] backend/tests/test_notifier.py — Verify existing notifier tests still pass with the updated priority mapping by running the full notifier test suite. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notifier.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-the-notifier-sends-priority-medium-for-3]

# --- 27B-decomposed from roadmap [2026-11-10]: `classify_heartbeat_incident` and `derive_heartbeat_incidents` raise TypeError when a fail (review + tweak) [feat:shrike-monitor-20261110-classify-heartbeat-incident-and-derive-h] ---
- [ ] [T1] backend/app/utils/incident_classify.py — Change `error = result.get('error', '')` to `error = result.get('error') or ''` in `classify_heartbeat_incident` and `derive_heartbeat_incidents` to handle None values. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_incident_classify.py::test_classify_heartbeat_incident_none_error_is_down`. (cat:python; multifile:no) [feat:shrike-monitor-20261110-classify-heartbeat-incident-and-derive-h]
- [ ] [T2] backend/tests/test_incident_classify.py — Add import for `STATUS_DOWN` from `app.models` if not already present. VERIFY: `cd backend && .venv/bin/python -c "from backend.tests.test_incident_classify import STATUS_DOWN"`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-classify-heartbeat-incident-and-derive-h]
- [ ] [T3] backend/tests/test_incident_classify.py — Add test function `test_classify_heartbeat_incident_none_error_is_down` asserting `classify_heartbeat_incident({"error": None}) == STATUS_DOWN`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_incident_classify.py::test_classify_heartbeat_incident_none_error_is_down`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-classify-heartbeat-incident-and-derive-h]
- [ ] [T4] backend/tests/test_incident_classify.py — Add test function `test_derive_heartbeat_incidents_none_error_does_not_crash` asserting `derive_heartbeat_incidents([{"ok": False, "error": None, "checked_at": 1.0}, {"ok": True, "checked_at": 2.0}]) == [{"status": "down", "started_at": 1.0, "ended_at": 2.0}]`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_incident_classify.py::test_derive_heartbeat_incidents_none_error_does_not_crash`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-classify-heartbeat-incident-and-derive-h]
- [ ] [T5] backend/tests/test_incident_classify.py — Run full test suite for the file to ensure no regressions. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_incident_classify.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-classify-heartbeat-incident-and-derive-h]

# --- 27B-decomposed from roadmap [2026-11-10]: `humanize_seconds` fails with a misleading "cannot convert float NaN to integer" for NaN a (review + tweak) [feat:shrike-monitor-20261110-humanize-seconds-fails-with-a-misleading] ---
- [ ] [T1] backend/app/utils/duration.py — Add `if sec != sec or sec in (float("inf"), float("-inf")): raise ValueError("sec must be finite")` before the existing negative check in `humanize_seconds`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration.py::test_humanize_seconds_non_finite_raises_clear_error`. (cat:python; multifile:no) [feat:shrike-monitor-20261110-humanize-seconds-fails-with-a-misleading]
- [ ] [T2] backend/tests/test_duration.py — Add `import pytest` if missing and append `test_humanize_seconds_non_finite_raises_clear_error` asserting `pytest.raises(ValueError, match="finite")` for `float("nan")`, `float("inf")`, and `float("-inf")`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration.py::test_humanize_seconds_non_finite_raises_clear_error`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-humanize-seconds-fails-with-a-misleading]
- [ ] [T3] backend/tests/test_duration.py — Verify existing assertions in `test_duration.py` remain green after the fix. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-humanize-seconds-fails-with-a-misleading]
- [ ] [T4] backend/tests/test_duration_rollover.py — Verify rollover logic remains intact and passes. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_rollover.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-humanize-seconds-fails-with-a-misleading]
- [ ] [T5] backend/tests/test_duration_hour_rollover.py — Verify hour rollover logic remains intact and passes. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261110-humanize-seconds-fails-with-a-misleading]

# --- 27B-decomposed from roadmap [2026-11-10]: `is_private_ip` treats IPv4-compatible (`::7f00:1`), IPv4-translated (`::ffff:0:7f00:1`) a (review + tweak) [feat:shrike-monitor-20261110-is-private-ip-treats-ipv4-compatible-7f0] ---
- [ ] [T1] backend/app/utils/ip_check.py — Add module-level constants `_IPV4_COMPATIBLE = ipaddress.ip_network("::/96")`, `_IPV4_TRANSLATED = ipaddress.ip_network("::ffff:0:0:0/96")`, and `_SITE_LOCAL = ipaddress.ip_network("fec0::/10")` after existing network definitions. VERIFY: `cd backend && .venv/bin/python -c "from app.utils.ip_check import _IPV4_COMPATIBLE, _IPV4_TRANSLATED, _SITE_LOCAL; print('OK')"` (cat:python; multifile:no) [feat:shrike-monitor-20261110-is-private-ip-treats-ipv4-compatible-7f0]
- [ ] [T2] backend/app/utils/ip_check.py — In the IPv6 branch of `is_private_ip`, add a check to return `True` if `addr in _SITE_LOCAL`. VERIFY: `cd backend && .venv/bin/python -c "from app.utils.ip_check import is_private_ip; assert is_private_ip('fec0::1') == True; print('OK')"` (cat:python; multifile:no) [feat:shrike-monitor-20261110-is-private-ip-treats-ipv4-compatible-7f0]
- [ ] [T3] backend/app/utils/ip_check.py — In the IPv6 branch of `is_private_ip`, extend the unwrap logic to handle `_IPV4_COMPATIBLE` and `_IPV4_TRANSLATED` networks by extracting the low 32 bits (`ipaddress.IPv4Address(int(addr) & 0xFFFFFFFF)`) and recursively calling `is_private_ip` on the result. VERIFY: `cd backend && .venv/bin/python -c "from app.utils.ip_check import is_private_ip; assert is_private_ip('::7f00:1') == True; assert is_private_ip('::ffff:0:7f00:1') == True; print('OK')"` (cat:python; multifile:no) [feat:shrike-monitor-20261110-is-private-ip-treats-ipv4-compatible-7f0]
- [ ] [T4] backend/app/utils/ip_check.py — Update the docstring of `is_private_ip` to explicitly list IPv4-compatible, IPv4-translated, and site-local addresses as private. VERIFY: `cd backend && .venv/bin/python -c "from app.utils.ip_check import is_private_ip; assert 'IPv4-compatible' in is_private_ip.__doc__ or 'site-local' in is_private_ip.__doc__; print('OK')"` (cat:docs; multifile:no) [feat:shrike-monitor-20261110-is-private-ip-treats-ipv4-compatible-7f0]
- [ ] [T5] backend/tests/test_ip_check.py — Add a parametrized test `test_ipv6_embedded_and_site_local_private` covering `"::7f00:1", "::a00:1", "::c0a8:1", "::ffff:0:7f00:1", "::ffff:0:a9fe:a9fe", "fec0::1", "feff::1"` asserting `is_private_ip` returns `True`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_ip_check.py::test_ipv6_embedded_and_site_local_private` (cat:test; multifile:no) [feat:shrike-monitor-20261110-is-private-ip-treats-ipv4-compatible-7f0]
