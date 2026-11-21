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

# --- 27B-decomposed from roadmap [2026-11-06]: `_extract_bearer_token()` mis-parses harmless whitespace variants, so a correct token is r (review + tweak) [feat:shrike-monitor-20261106-extract-bearer-token-mis-parses-harmless] ---

# --- 27B-decomposed from roadmap [2026-11-06]: The OpenAPI schema documents none of the error responses the /monitors routes really retur (review + tweak) [feat:shrike-monitor-20261106-the-openapi-schema-documents-none-of-the] ---

# --- 27B-decomposed from roadmap [2026-11-06]: README's Status semantics section never says heartbeat monitors can be `degraded` or how a (review + tweak) [feat:shrike-monitor-20261106-readme-s-status-semantics-section-never-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: A monitor URL with a newline, tab, space or an out-of-range/non-numeric port is accepted a (review + tweak) [feat:shrike-monitor-20261109-a-monitor-url-with-a-newline-tab-space-o] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `Store.update()` will overwrite any Monitor attribute including `id`, `created_at` and eve (review + tweak) [feat:shrike-monitor-20261109-store-update-will-overwrite-any-monitor-] ---

# --- 27B-decomposed from roadmap [2026-11-09]: The notifier retries permanent 4xx publish errors (bad token, wrong topic) with backoff sl (review + tweak) [feat:shrike-monitor-20261109-the-notifier-retries-permanent-4xx-publi] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `_codes_from_str()` accepts booleans, floats, numeric strings and out-of-range numbers fro (review + tweak) [feat:shrike-monitor-20261109-codes-from-str-accepts-booleans-floats-n] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `tick()`'s overall gather timeout ignores the per-probe 5 s grace, so a fleet of slow 60 s (review + tweak) [feat:shrike-monitor-20261109-tick-s-overall-gather-timeout-ignores-th] ---

# --- 27B-decomposed from roadmap [2026-11-09]: `percentile()` gives a misleading "cannot convert float NaN to integer" error for `p=nan`  (review + tweak) [feat:shrike-monitor-20261109-percentile-gives-a-misleading-cannot-con] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The notifier sends `priority: "medium"` for 3xx, 4xx and unknown status codes, but shrike- (review + tweak) [feat:shrike-monitor-20261110-the-notifier-sends-priority-medium-for-3] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `classify_heartbeat_incident` and `derive_heartbeat_incidents` raise TypeError when a fail (review + tweak) [feat:shrike-monitor-20261110-classify-heartbeat-incident-and-derive-h] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `humanize_seconds` fails with a misleading "cannot convert float NaN to integer" for NaN a (review + tweak) [feat:shrike-monitor-20261110-humanize-seconds-fails-with-a-misleading] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `is_private_ip` treats IPv4-compatible (`::7f00:1`), IPv4-translated (`::ffff:0:7f00:1`) a (review + tweak) [feat:shrike-monitor-20261110-is-private-ip-treats-ipv4-compatible-7f0] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `RedactTokenFilter` is only tested with tuple args - `backend/app/logging_config.py` `Reda (review + tweak) [feat:shrike-monitor-20261110-redacttokenfilter-is-only-tested-with-tu] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `probe` with a fetch that returns a dict (the SSRF/blocked-target signal) is untested - `b (review + tweak) [feat:shrike-monitor-20261110-probe-with-a-fetch-that-returns-a-dict-t] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The status-code (de)serialisers `_codes_to_str` / `_codes_from_str` in the persistence lay (review + tweak) [feat:shrike-monitor-20261110-the-status-code-de-serialisers-codes-to-] ---

# --- 27B-decomposed from roadmap [2026-11-10]: The no-hostname rejection of the SSRF pre-check is untested - `backend/app/services/checke (review + tweak) [feat:shrike-monitor-20261110-the-no-hostname-rejection-of-the-ssrf-pr] ---

# --- 27B-decomposed from roadmap [2026-11-10]: `_stream_get` falls back to UTF-8 when the response declares an unknown charset, but nothi (review + tweak) [feat:shrike-monitor-20261110-stream-get-falls-back-to-utf-8-when-the-] ---

# --- 27B-decomposed from roadmap [2026-11-11]: README `## Layout` can drift from the tree with nothing noticing - `README.md` lists every (review + tweak) [feat:shrike-monitor-20261111-readme-layout-can-drift-from-the-tree-wi] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `railway.toml`, the Dockerfile and `start.sh` are not checked against the app - `backend/r (review + tweak) [feat:shrike-monitor-20261111-railway-toml-the-dockerfile-and-start-sh] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `MonitorScheduler._maybe_notify` semaphore branches are untested - `backend/app/services/s (review + tweak) [feat:shrike-monitor-20261111-monitorscheduler-maybe-notify-semaphore-] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `MonitorUpdate` heartbeat-url rule and status-code range errors are untested - `backend/ap (review + tweak) [feat:shrike-monitor-20261111-monitorupdate-heartbeat-url-rule-and-sta] ---

# --- 27B-decomposed from roadmap [2026-11-11]: The heartbeat route registers one duplicate OpenAPI operationId; give GET and POST unique  (review + tweak) [feat:shrike-monitor-20261111-the-heartbeat-route-registers-one-duplic] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `DELETE /monitors/{id}` without a scheduler on `app.state` is untested - `backend/app/rout (review + tweak) [feat:shrike-monitor-20261111-delete-monitors-id-without-a-scheduler-o] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `test_monitors_status_api.py` repeats two tests three times each - `backend/tests/test_mon (review + tweak) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-] ---

# --- 27B-decomposed from roadmap [2026-11-11]: `test_results_incidents.py` defines `test_monitor_results_auth_required` twice - `backend/ (review + tweak) [feat:shrike-monitor-20261111-test-results-incidents-py-defines-test-m] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Drop the unreachable fallback line in `Settings._fallback_invalid_float` - `backend/app/co (review + tweak) [feat:shrike-monitor-20261111-drop-the-unreachable-fallback-line-in-se] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure status-page builder - create `backend/app/services/status_page.py` with `build_ (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /status-page` as its own router - create `backend/app/routers/status_page.py` wit (review + tweak) [feat:shrike-monitor-20261111-add-get-status-page-as-its-own-router-cr] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Wire the status-page router into the app - in `backend/app/main.py` import `status_page` w (review + tweak) [feat:shrike-monitor-20261111-wire-the-status-page-router-into-the-app] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add an optional `status` filter to the status page - in `backend/app/routers/status_page.p (review + tweak) [feat:shrike-monitor-20261111-add-an-optional-status-filter-to-the-sta] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Document the status page - create `docs/STATUS_PAGE.md` describing `GET /status-page` (fie (review + tweak) [feat:shrike-monitor-20261111-document-the-status-page-create-docs-sta] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure incident merger - create `backend/app/services/incident_feed.py` with `merge_in (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-incident-merger-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure incident summary - in `backend/app/services/incident_feed.py` add `summarize_in (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-incident-summary-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /incidents` as its own router - create `backend/app/routers/incident_feed.py` wit (review + tweak) [feat:shrike-monitor-20261111-add-get-incidents-as-its-own-router-crea] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /incidents/summary` to the same router - in `backend/app/routers/incident_feed.py (review + tweak) [feat:shrike-monitor-20261111-add-get-incidents-summary-to-the-same-ro] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Wire the incident feed router into the app - in `backend/app/main.py` import `incident_fee (review + tweak) [feat:shrike-monitor-20261111-wire-the-incident-feed-router-into-the-a] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add an in-memory maintenance window store - create `backend/app/services/maintenance.py` w (review + tweak) [feat:shrike-monitor-20261111-add-an-in-memory-maintenance-window-stor] ---

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure annotator for status items - in `backend/app/services/maintenance.py` add `anno (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-annotator-for-status-items-in] ---

# --- 27B-decomposed from roadmap [2026-11-12]: Add the `/maintenance` router - create `backend/app/routers/maintenance.py` gated by `Depe (review + tweak) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Wire the maintenance router into the app - in `backend/app/main.py` import `maintenance` a (review + tweak) [feat:shrike-monitor-20261113-wire-the-maintenance-router-into-the-app] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Document the maintenance windows and their limits - create `docs/MAINTENANCE.md` stating t (review + tweak) [feat:shrike-monitor-20261113-document-the-maintenance-windows-and-the] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add a TCP connect probe - create `backend/app/services/check_tcp.py` with `async def tcp_p (review + tweak) [feat:shrike-monitor-20261113-add-a-tcp-connect-probe-create-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add a DNS resolution probe - create `backend/app/services/check_dns.py` with `async def dn (review + tweak) [feat:shrike-monitor-20261113-add-a-dns-resolution-probe-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add certificate expiry arithmetic - create `backend/app/services/check_tls.py` with `days_ (review + tweak) [feat:shrike-monitor-20261113-add-certificate-expiry-arithmetic-create] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the TLS probe - in `backend/app/services/check_tls.py` add `async def tls_probe(host:  (review + tweak) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add a check registry with a result adapter - create `backend/app/services/check_registry.p (review + tweak) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Document the check modules - create `docs/CHECK_TYPES.md` describing the three probes, the (review + tweak) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the SLA row builder - create `backend/app/services/sla_report.py` with `CSV_COLUMNS =  (review + tweak) [feat:shrike-monitor-20261113-add-the-sla-row-builder-create-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add CSV rendering - in `backend/app/services/sla_report.py` add `rows_to_csv(rows: list[di (review + tweak) [feat:shrike-monitor-20261113-add-csv-rendering-in-backend-app-service] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add `GET /reports/sla` as its own router - create `backend/app/routers/reports.py` gated b (review + tweak) [feat:shrike-monitor-20261113-add-get-reports-sla-as-its-own-router-cr] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Wire the reports router into the app - in `backend/app/main.py` import `reports` and inclu (review + tweak) [feat:shrike-monitor-20261113-wire-the-reports-router-into-the-app-in-] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Document the report and pin its columns - create `docs/SLA_REPORT.md` describing the query (review + tweak) [feat:shrike-monitor-20261113-document-the-report-and-pin-its-columns-] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the percentile summary - create `backend/app/services/latency_report.py` with `latency (review + tweak) [feat:shrike-monitor-20261113-add-the-percentile-summary-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the histogram - in `backend/app/services/latency_report.py` add `latency_histogram(lat (review + tweak) [feat:shrike-monitor-20261113-add-the-histogram-in-backend-app-service] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add `GET /latency/{monitor_id}` as its own router - create `backend/app/routers/latency.py (review + tweak) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Wire the latency router into the app - in `backend/app/main.py` import `latency` and inclu (review + tweak) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the hourly bucket helper - create `backend/app/utils/timeline.py` with `hourly_ok_fail (review + tweak) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-13]: Add the timeline router - create `backend/app/routers/timeline.py` with `router = APIRoute (review + tweak) [feat:shrike-monitor-20261113-add-the-timeline-router-create-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Wire the timeline router - in `backend/app/main.py` change the line `from app.routers impo (review + tweak) [feat:shrike-monitor-20261115-wire-the-timeline-router-in-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Add the transitions helper - create `backend/app/utils/transitions.py` with `status_transi (review + tweak) [feat:shrike-monitor-20261115-add-the-transitions-helper-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Add the flap counter - in `backend/app/utils/transitions.py` add `flap_count(transitions:  (review + tweak) [feat:shrike-monitor-20261115-add-the-flap-counter-in-backend-app-util] ---

# --- 27B-decomposed from roadmap [2026-11-15]: Add the transitions router - create `backend/app/routers/transitions.py` with `router = AP (review + tweak) [feat:shrike-monitor-20261115-add-the-transitions-router-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Wire the transitions router - in `backend/app/main.py` import `transitions` in the `from a (review + tweak) [feat:shrike-monitor-20261116-wire-the-transitions-router-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the reliability helper - create `backend/app/utils/reliability.py` with `reliability_s (review + tweak) [feat:shrike-monitor-20261116-add-the-reliability-helper-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the reliability router - create `backend/app/routers/reliability.py` with `router = AP (review + tweak) [feat:shrike-monitor-20261116-add-the-reliability-router-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Wire the reliability router - in `backend/app/main.py` import `reliability` in the `from a (review + tweak) [feat:shrike-monitor-20261116-wire-the-reliability-router-in-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the downsample helper - create `backend/app/utils/series.py` with `downsample_results( (review + tweak) [feat:shrike-monitor-20261116-add-the-downsample-helper-create-backend] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the series router - create `backend/app/routers/series.py` with `router = APIRouter(pr (review + tweak) [feat:shrike-monitor-20261116-add-the-series-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Wire the series router - in `backend/app/main.py` import `series` in the `from app.routers (review + tweak) [feat:shrike-monitor-20261116-wire-the-series-router-in-backend-app-ma] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the API reference doc - create `docs/API_REFERENCE.md` (title `# API reference`) with  (review + tweak) [feat:shrike-monitor-20261116-add-the-api-reference-doc-create-docs-ap] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Pin the core routes to the doc - in `backend/tests/test_api_reference_doc.py` add `test_co (review + tweak) [feat:shrike-monitor-20261116-pin-the-core-routes-to-the-doc-in-backen] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the age pruning helper - create `backend/app/utils/retention.py` with `prune_by_age(re (review + tweak) [feat:shrike-monitor-20261116-add-the-age-pruning-helper-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the count pruning and combined helpers - in `backend/app/utils/retention.py` add `prun (review + tweak) [feat:shrike-monitor-20261116-add-the-count-pruning-and-combined-helpe] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the retention report helper - in `backend/app/utils/retention.py` add `retention_repor (review + tweak) [feat:shrike-monitor-20261116-add-the-retention-report-helper-in-backe] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the retention preview router - create `backend/app/routers/retention.py` with `router  (review + tweak) [feat:shrike-monitor-20261116-add-the-retention-preview-router-create-] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Wire the retention preview router - in `backend/app/main.py` add `retention` to the existi (review + tweak) [feat:shrike-monitor-20261116-wire-the-retention-preview-router-in-bac] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Document retention - create `docs/RETENTION.md` (title `# Result retention`) explaining th (review + tweak) [feat:shrike-monitor-20261116-document-retention-create-docs-retention] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the tag normalizer - create `backend/app/utils/tags.py` with `normalize_tag(tag: str)  (review + tweak) [feat:shrike-monitor-20261116-add-the-tag-normalizer-create-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-16]: Add the in-memory tag registry - create `backend/app/services/tags.py` with `class TagRegi (review + tweak) [feat:shrike-monitor-20261116-add-the-in-memory-tag-registry-create-ba] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the per-monitor tags routes - create `backend/app/routers/tags.py` with `router = APIR (review + tweak) [feat:shrike-monitor-20261117-add-the-per-monitor-tags-routes-create-b] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the tag listing routes - in `backend/app/routers/tags.py` add a second router `tag_ind (review + tweak) [feat:shrike-monitor-20261117-add-the-tag-listing-routes-in-backend-ap] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Wire the tag routers - in `backend/app/main.py` add `tags` to the existing `from app.route (review + tweak) [feat:shrike-monitor-20261117-wire-the-tag-routers-in-backend-app-main] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the badge colour table - create `backend/app/utils/badge.py` with `BADGE_COLORS: dict[ (review + tweak) [feat:shrike-monitor-20261117-add-the-badge-colour-table-create-backen] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the SVG renderer - in `backend/app/utils/badge.py` add `render_badge_svg(label: str, m (review + tweak) [feat:shrike-monitor-20261117-add-the-svg-renderer-in-backend-app-util] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the badge router - create `backend/app/routers/badge.py` with `router = APIRouter(pref (review + tweak) [feat:shrike-monitor-20261117-add-the-badge-router-create-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Wire the badge router - in `backend/app/main.py` add `badge` to the existing `from app.rou (review + tweak) [feat:shrike-monitor-20261117-wire-the-badge-router-in-backend-app-mai] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Document the badge - create `docs/BADGE.md` (title `# Status badge`) stating that `GET /mo (review + tweak) [feat:shrike-monitor-20261117-document-the-badge-create-docs-badge-md-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the stable jitter fraction - create `backend/app/utils/jitter.py` with `jitter_fractio (review + tweak) [feat:shrike-monitor-20261117-add-the-stable-jitter-fraction-create-ba] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the jitter offset - in `backend/app/utils/jitter.py` add `jitter_offset(key: str, inte (review + tweak) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the even spread - in `backend/app/utils/jitter.py` add `spread_offsets(keys: list[str] (review + tweak) [feat:shrike-monitor-20261117-add-the-even-spread-in-backend-app-utils] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Document the jitter helpers - create `docs/SCHEDULING.md` (title `# Probe scheduling`) wit (review + tweak) [feat:shrike-monitor-20261117-document-the-jitter-helpers-create-docs-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the configuration reference - create `docs/CONFIGURATION.md` (title `# Configuration`) (review + tweak) [feat:shrike-monitor-20261117-add-the-configuration-reference-create-d] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the notifier reference - create `docs/NOTIFIER.md` (title `# Notifier`) listing every  (review + tweak) [feat:shrike-monitor-20261117-add-the-notifier-reference-create-docs-n] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the masked settings view helper - create `backend/app/utils/settings_view.py` with `de (review + tweak) [feat:shrike-monitor-20261117-add-the-masked-settings-view-helper-crea] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Pin the README environment table to the settings - in `README.md` add a table row to the e (review + tweak) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the window uptime helper - create `backend/app/utils/uptime_window.py` with `uptime_pe (review + tweak) [feat:shrike-monitor-20261117-add-the-window-uptime-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-17]: Add the three window summary - in `backend/app/utils/uptime_window.py` add `UPTIME_WINDOWS (review + tweak) [feat:shrike-monitor-20261117-add-the-three-window-summary-in-backend-] ---

# --- 27B-decomposed from roadmap [2026-11-18]: Add the uptime router - create `backend/app/routers/uptime.py` with `router = APIRouter(pr (review + tweak) [feat:shrike-monitor-20261118-add-the-uptime-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-18]: Wire the uptime router - in `backend/app/main.py` add `uptime` to the existing `from app.r (review + tweak) [feat:shrike-monitor-20261118-wire-the-uptime-router-in-backend-app-ma] ---

# --- 27B-decomposed from roadmap [2026-11-18]: Document the uptime windows - create `docs/UPTIME.md` (title `# Uptime by window`) listing (review + tweak) [feat:shrike-monitor-20261118-document-the-uptime-windows-create-docs-] ---

# --- 27B-decomposed from roadmap [2026-11-18]: Add the cell guard and row builder - create `backend/app/utils/result_csv.py` with `safe_c (review + tweak) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the CSV renderer - in `backend/app/utils/result_csv.py` add `render_csv(results: list[ (review + tweak) [feat:shrike-monitor-20261119-add-the-csv-renderer-in-backend-app-util] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Add the export router - create `backend/app/routers/export.py` with `router = APIRouter(pr (review + tweak) [feat:shrike-monitor-20261119-add-the-export-router-create-backend-app] ---

# --- 27B-decomposed from roadmap [2026-11-19]: Wire the export router - in `backend/app/main.py` add `export` to the existing `from app.r (review + tweak) [feat:shrike-monitor-20261119-wire-the-export-router-in-backend-app-ma] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Document the export - create `docs/EXPORT.md` (title `# Result export`) naming `GET /monit (review + tweak) [feat:shrike-monitor-20261120-document-the-export-create-docs-export-m] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the duration text helper - create `backend/app/utils/status_text.py` with `since_text( (review + tweak) [feat:shrike-monitor-20261120-add-the-duration-text-helper-create-back] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the status sentence helper - in `backend/app/utils/status_text.py` add `status_sentenc (review + tweak) [feat:shrike-monitor-20261120-add-the-status-sentence-helper-in-backen] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the status code grouping helper - create `backend/app/utils/failures.py` with `failure (review + tweak) [feat:shrike-monitor-20261120-add-the-status-code-grouping-helper-crea] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the error text grouping helper - in `backend/app/utils/failures.py` add `failures_by_e (review + tweak) [feat:shrike-monitor-20261120-add-the-error-text-grouping-helper-in-ba] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Add the failures router - create `backend/app/routers/failures.py` with `router = APIRoute (review + tweak) [feat:shrike-monitor-20261120-add-the-failures-router-create-backend-a] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Wire the failures router - in `backend/app/main.py` add `failures` to the existing `from a (review + tweak) [feat:shrike-monitor-20261120-wire-the-failures-router-in-backend-app-] ---

# --- 27B-decomposed from roadmap [2026-11-20]: Document the failure breakdown - create `docs/FAILURES.md` (title `# Failure breakdown`) n (review + tweak) [feat:shrike-monitor-20261120-document-the-failure-breakdown-create-do] ---
- [ ] [T2] docs/FAILURES.md — Append response keys `total_failures`, `by_status_code`, and `by_error` to the documentation. VERIFY: `grep -q "total_failures" docs/FAILURES.md && grep -q "by_status_code" docs/FAILURES.md && grep -q "by_error" docs/FAILURES.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261120-document-the-failure-breakdown-create-do]
- [ ] [T3] docs/FAILURES.md — Add statement that error text is cut to 80 characters and failures without a status code are keyed `none`. VERIFY: `grep -q "80 characters" docs/FAILURES.md && grep -q "keyed \`none\`" docs/FAILURES.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261120-document-the-failure-breakdown-create-do]
- [ ] [T5] backend/tests/test_failures_doc.py — Add test `test_failures_doc_lists_every_response_key` asserting `total_failures`, `by_status_code`, and `by_error` are present in the doc. VERIFY: `cd backend && python3 -m pytest tests/test_failures_doc.py::test_failures_doc_lists_every_response_key -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261120-document-the-failure-breakdown-create-do]

# --- 27B-decomposed from roadmap [2026-11-20]: Add the half averages helper - create `backend/app/utils/latency_trend.py` with `half_aver (review + tweak) [feat:shrike-monitor-20261120-add-the-half-averages-helper-create-back] ---
- [ ] [T1] backend/app/utils/latency_trend.py — Add `half_averages` function that filters `CheckResult` list for `ok=True` and non-null latency, returns `None` if count < 4, else returns tuple of average latency for first half (`items[:n//2]`) and second half (`items[n//2:]`). VERIFY: `cd backend && python3 -c "from app.utils.latency_trend import half_averages; print('ok')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261120-add-the-half-averages-helper-create-back]
- [ ] [T1] backend/tests/test_latency_trend_halves.py — Add test file with `test_fewer_than_four_usable_results_gives_none` verifying `half_averages` returns `None` for lists with <4 valid results. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_halves.py::test_fewer_than_four_usable_results_gives_none -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261120-add-the-half-averages-helper-create-back]
- [ ] [T1] backend/tests/test_latency_trend_halves.py — Add `test_failed_and_latencyless_results_are_ignored` verifying results with `ok=False` or `latency=None` are excluded from calculation. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_halves.py::test_failed_and_latencyless_results_are_ignored -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261120-add-the-half-averages-helper-create-back]
- [ ] [T1] backend/tests/test_latency_trend_halves.py — Add `test_halves_are_averaged_in_recorded_order` verifying correct average calculation for a list of 4+ valid results split at `n//2`. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_halves.py::test_halves_are_averaged_in_recorded_order -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261120-add-the-half-averages-helper-create-back]
- [ ] [T1] backend/tests/test_latency_trend_halves.py — Add `test_odd_count_puts_the_extra_result_in_the_newer_half` verifying that for odd counts, the extra item goes to the newer half (e.g., 5 items -> 2 old, 3 new). VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_halves.py::test_odd_count_puts_the_extra_result_in_the_newer_half -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261120-add-the-half-averages-helper-create-back]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the trend classifier - in `backend/app/utils/latency_trend.py` add `latency_trend(resu (review + tweak) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-] ---
- [ ] [T1] backend/app/utils/latency_trend.py — Add `latency_trend` function returning default unknown dict when inputs are insufficient or older average is 0. VERIFY: `cd backend && python3 -c "from app.utils.latency_trend import latency_trend; assert latency_trend([]) == {'direction': 'unknown', 'change_pct': None, 'older_avg_ms': None, 'newer_avg_ms': None}"`. (cat:python; multifile:no) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-]
- [ ] [T1] backend/app/utils/latency_trend.py — Implement logic to split results into halves, calculate averages, and determine direction based on `threshold_pct` and change percentage. VERIFY: `cd backend && python3 -c "from app.utils.latency_trend import latency_trend; from unittest.mock import Mock; r=[Mock(latency_ms=100), Mock(latency_ms=100), Mock(latency_ms=200), Mock(latency_ms=200)]; res=latency_trend(r); assert res['direction']=='slower' and res['change_pct']==100.0"`. (cat:python; multifile:no) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-]
- [ ] [T2] backend/tests/test_latency_trend_classify.py — Create test file with `test_slower_when_newer_half_is_much_higher` verifying the 'slower' direction and correct percentage calculation. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_classify.py::test_slower_when_newer_half_is_much_higher -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-]
- [ ] [T2] backend/tests/test_latency_trend_classify.py — Add `test_faster_when_newer_half_is_much_lower` verifying the 'faster' direction when newer average is significantly lower. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_classify.py::test_faster_when_newer_half_is_much_lower -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-]
- [ ] [T2] backend/tests/test_latency_trend_classify.py — Add `test_steady_inside_the_threshold` verifying the 'steady' direction when change is within the threshold. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_classify.py::test_steady_inside_the_threshold -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-]
- [ ] [T2] backend/tests/test_latency_trend_classify.py — Add `test_unknown_with_too_few_results` verifying the default unknown response when input list is too short to split. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_classify.py::test_unknown_with_too_few_results -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-]
- [ ] [T2] backend/tests/test_latency_trend_classify.py — Add `test_threshold_is_inclusive` verifying that exactly hitting the threshold triggers 'slower' or 'faster' as per inclusive logic. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_classify.py::test_threshold_is_inclusive -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-trend-classifier-in-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the latency trend router - create `backend/app/routers/latency_trend.py` with `router  (review + tweak) [feat:shrike-monitor-20261121-add-the-latency-trend-router-create-back] ---
- [ ] [T1] backend/app/utils/latency_trend.py — Add pure function `latency_trend(results: list[dict], threshold_pct: float) -> dict` that computes `direction` and `change_pct` from the last two latency values, returning `{'direction': 'slower', 'change_pct': 200.0}` for inputs `[100, 100, 300, 300]` with `threshold_pct=20.0`. VERIFY: `cd backend && python3 -c "from app.utils.latency_trend import latency_trend; r = latency_trend([{'latency_ms': 100}, {'latency_ms': 100}, {'latency_ms': 300}, {'latency_ms': 300}], 20.0); assert r['direction'] == 'slower' and r['change_pct'] == 200.0"`. (cat:python; multifile:no) [feat:shrike-monitor-20261121-add-the-latency-trend-router-create-back]
- [ ] [T2] backend/app/routers/latency_trend.py — Create file with `router = APIRouter(prefix="/monitors", tags=["monitors"], dependencies=[Depends(require_api_token)])` and endpoint `GET /{monitor_id}/latency-trend` that returns 404 with detail "monitor not found" if `store.get(monitor_id)` is None, else returns `{"monitor_id": monitor_id, **latency_trend(store.results(monitor_id), threshold_pct)}`. VERIFY: `cd backend && python3 -c "from app.routers.latency_trend import router; assert router.prefix == '/monitors' and router.tags == ['monitors']"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261121-add-the-latency-trend-router-create-back]
- [ ] [T3] backend/app/routers/__init__.py — Import `latency_trend` from `app.routers.latency_trend` and add `router.include_router(latency_trend.router)` to the main router. VERIFY: `cd backend && python3 -c "from app.main import app; paths = [r.path for r in app.routes]; assert '/monitors/{monitor_id}/latency-trend' in paths"`. (cat:refactor; multifile:no) [feat:shrike-monitor-20261121-add-the-latency-trend-router-create-back]
- [ ] [T1] backend/tests/test_latency_trend_util.py — Add unit test `test_latency_trend_slower` that imports `latency_trend` from `app.utils.latency_trend`, calls it with four results having latencies 100, 100, 300, 300 and threshold 20.0, and asserts `direction == 'slower'` and `change_pct == 200.0`. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_util.py::test_latency_trend_slower -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-latency-trend-router-create-back]
- [ ] [T2] backend/tests/test_latency_trend_router.py — Create test file that mounts `latency_trend.router` on a fresh `FastAPI()` instance, uses `httpx.AsyncClient`, creates an http monitor via `await store.create('probe', url='http://example.com')`, records four ok results with latencies 100, 100, 300, 300, asserts response JSON has `direction == 'slower'` and `change_pct == 200.0`, asserts unknown ID returns 404, and calls `store.clear()` in finally block. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_router.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-latency-trend-router-create-back]

# --- 27B-decomposed from roadmap [2026-11-21]: Wire the latency trend router - in `backend/app/main.py` add `latency_trend` to the existi (review + tweak) [feat:shrike-monitor-20261121-wire-the-latency-trend-router-in-backend] ---
- [ ] [T1] backend/app/routers/latency.py — Add `router = APIRouter()` and a `GET /monitors/{monitor_id}/latency-trend` endpoint that returns 404 if the monitor ID is not in the store, otherwise returns an empty list or placeholder trend data. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_wired.py::test_latency_trend_route_registered -q`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261121-wire-the-latency-trend-router-in-backend]
- [ ] [T3] backend/app/main.py — Import `latency_trend` in the existing `from app.routers import ...` line and add `app.include_router(latency_trend.router)` immediately after `app.include_router(monitors.router)`. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_wired.py::test_latency_trend_route_registered -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261121-wire-the-latency-trend-router-in-backend]
- [ ] [T2] backend/tests/test_latency_trend_wired.py — Create the test file with `test_latency_trend_route_registered` asserting `/monitors/{monitor_id}/latency-trend` is in `app.openapi()['paths']` and `test_latency_trend_unknown_monitor_is_404` using `TestClient` to verify a 404 response for an unknown monitor, ensuring `settings.monitor_api_token` is unset and restored. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_wired.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-wire-the-latency-trend-router-in-backend]

# --- 27B-decomposed from roadmap [2026-11-21]: Document the latency trend - create `docs/LATENCY_TREND.md` (title `# Latency trend`) expl (review + tweak) [feat:shrike-monitor-20261121-document-the-latency-trend-create-docs-l] ---
- [ ] [T2] docs/LATENCY_TREND.md — Create file with title `# Latency trend` and list the four direction values `faster`, `steady`, `slower`, `unknown`. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_doc.py::test_latency_trend_doc_lists_every_direction -q`. (cat:docs; multifile:no) [feat:shrike-monitor-20261121-document-the-latency-trend-create-docs-l]
- [ ] [T1] backend/tests/test_latency_trend_doc.py — Add `test_latency_trend_doc_names_the_route` which asserts `docs/LATENCY_TREND.md` contains the route path for latency trends. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_doc.py::test_latency_trend_doc_names_the_route -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-document-the-latency-trend-create-docs-l]
- [ ] [T2] docs/LATENCY_TREND.md — Add explanation that only ok results with a latency are used and fewer than four give `unknown`. VERIFY: `grep -q "only ok results" docs/LATENCY_TREND.md && grep -q "fewer than four" docs/LATENCY_TREND.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261121-document-the-latency-trend-create-docs-l]
- [ ] [T1] backend/tests/test_latency_trend_doc.py — Add `test_latency_trend_doc_lists_every_direction` which asserts `docs/LATENCY_TREND.md` contains `faster`, `steady`, `slower`, and `unknown`. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_doc.py::test_latency_trend_doc_lists_every_direction -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-document-the-latency-trend-create-docs-l]
- [ ] [T2] docs/LATENCY_TREND.md — Add explanation that the default threshold is 20 percent. VERIFY: `grep -q "20 percent" docs/LATENCY_TREND.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261121-document-the-latency-trend-create-docs-l]
- [ ] [T2] docs/LATENCY_TREND.md — Add the route path for latency trends to satisfy the route naming test. VERIFY: `cd backend && python3 -m pytest tests/test_latency_trend_doc.py::test_latency_trend_doc_names_the_route -q`. (cat:docs; multifile:no) [feat:shrike-monitor-20261121-document-the-latency-trend-create-docs-l]

# --- 27B-decomposed from roadmap [2026-11-21]: Add the HTTP monitor lint helper - create `backend/app/utils/monitor_lint.py` with `LINT_C (review + tweak) [feat:shrike-monitor-20261121-add-the-http-monitor-lint-helper-create-] ---
- [ ] [T1] backend/app/utils/monitor_lint.py — Create file with `LINT_CODES` tuple and `lint_http_monitor(monitor: Monitor) -> list[dict]` function that returns empty list for non-http types and checks `timeout_exceeds_interval`, `degraded_above_timeout`, and `very_short_interval` in order. VERIFY: `cd backend && python3 -c "from app.utils.monitor_lint import LINT_CODES, lint_http_monitor; print(LINT_CODES)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261121-add-the-http-monitor-lint-helper-create-]
- [ ] [T2] backend/tests/test_monitor_lint_http.py — Create test file with `test_clean_http_monitor_has_no_warnings` asserting empty list for interval 60, timeout 10, degraded 1000. VERIFY: `cd backend && python3 -m pytest tests/test_monitor_lint_http.py::test_clean_http_monitor_has_no_warnings -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-http-monitor-lint-helper-create-]
- [ ] [T2] backend/tests/test_monitor_lint_http.py — Add `test_timeout_not_below_interval_is_flagged` asserting `timeout_exceeds_interval` code is present when timeout equals interval. VERIFY: `cd backend && python3 -m pytest tests/test_monitor_lint_http.py::test_timeout_not_below_interval_is_flagged -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-http-monitor-lint-helper-create-]
- [ ] [T2] backend/tests/test_monitor_lint_http.py — Add `test_degraded_threshold_at_or_above_timeout_is_flagged` asserting `degraded_above_timeout` code is present when degraded_latency_ms >= timeout_seconds * 1000. VERIFY: `cd backend && python3 -m pytest tests/test_monitor_lint_http.py::test_degraded_threshold_at_or_above_timeout_is_flagged -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-http-monitor-lint-helper-create-]
- [ ] [T2] backend/tests/test_monitor_lint_http.py — Add `test_interval_below_ten_seconds_is_flagged` asserting `very_short_interval` code is present when interval_seconds < 10. VERIFY: `cd backend && python3 -m pytest tests/test_monitor_lint_http.py::test_interval_below_ten_seconds_is_flagged -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-http-monitor-lint-helper-create-]
- [ ] [T2] backend/tests/test_monitor_lint_http.py — Add `test_heartbeat_monitor_gets_no_http_warnings` asserting empty list for a monitor with type "heartbeat". VERIFY: `cd backend && python3 -m pytest tests/test_monitor_lint_http.py::test_heartbeat_monitor_gets_no_http_warnings -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261121-add-the-http-monitor-lint-helper-create-]
