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
- [ ] [T2] backend/tests/test_maintenance_windows.py — Add `test_remove_and_prune` verifying `remove` returns True for existing IDs and False for missing, and `prune` removes expired windows returning correct count. VERIFY: `cd backend && python3 -m pytest tests/test_maintenance_windows.py::test_remove_and_prune -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-an-in-memory-maintenance-window-stor]

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure annotator for status items - in `backend/app/services/maintenance.py` add `anno (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-annotator-for-status-items-in] ---
- [ ] [T1] backend/app/services/maintenance.py — Add `annotate_in_maintenance(items: list[dict], active_windows: list[dict]) -> list[dict]` that returns a new list of item copies with `in_maintenance` boolean set to True if any window has `monitor_id` None or matching item `id`, leaving `status` untouched. VERIFY: `cd backend && python3 -c "from app.services.maintenance import annotate_in_maintenance; items=[{'id':1,'status':'up'}]; windows=[{'monitor_id':None}]; res=annotate_in_maintenance(items,windows); assert res[0]['in_maintenance']==True and res[0]['status']=='up' and items[0].get('in_maintenance') is None"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-annotator-for-status-items-in]
- [ ] [T1] backend/tests/test_maintenance_windows.py — Add `test_annotate_marks_only_covered_monitors_and_keeps_status` verifying that items with matching or global windows get `in_maintenance=True`, others get False, and original item status remains unchanged. VERIFY: `cd backend && python3 -m pytest tests/test_maintenance_windows.py -q -k test_annotate_marks_only_covered_monitors_and_keeps_status`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-annotator-for-status-items-in]

# --- 27B-decomposed from roadmap [2026-11-12]: Add the `/maintenance` router - create `backend/app/routers/maintenance.py` gated by `Depe (review + tweak) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen] ---
- [ ] [T1] backend/app/schemas.py — Add `MaintenanceCreate` Pydantic model with optional `monitor_id`, required `start: float`, required `end: float`, and `reason: str = Field("", max_length=200)`. VERIFY: `cd backend && python3 -c "from app.schemas import MaintenanceCreate; m=MaintenanceCreate(start=1.0, end=2.0); assert m.reason==''"`. (cat:schema; multifile:no) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen]
- [ ] [T1] backend/app/routers/maintenance.py — Add `GET /maintenance` endpoint that returns all maintenance windows from the `windows` store. VERIFY: `cd backend && python3 -c "from app.routers.maintenance import router; assert any(r.path=='/maintenance' and 'GET' in r.methods for r in router.routes)"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen]
- [ ] [T1] backend/app/routers/maintenance.py — Create router with `POST /maintenance` endpoint that validates `end > start` (returning 422 if invalid), creates a window in the `windows` store, and returns 201 with the created window. VERIFY: `cd backend && python3 -c "from app.routers.maintenance import router; assert hasattr(router, 'routes')"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen]
- [ ] [T1] backend/app/routers/maintenance.py — Add `DELETE /maintenance/{window_id}` endpoint that removes a window by ID, returning 204 on success or 404 if the ID is not found. VERIFY: `cd backend && python3 -c "from app.routers.maintenance import router; assert any('DELETE' in r.methods for r in router.routes)"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen]
- [ ] [T1] backend/app/routers/maintenance.py — Apply `Depends(require_api_token)` to all endpoints in the maintenance router to enforce authentication. VERIFY: `cd backend && python3 -c "from app.routers.maintenance import router; assert all(any(dep.dependency.__name__=='require_api_token' for dep in r.dependant.dependencies) for r in router.routes if r.methods)"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen]
- [ ] [T2] backend/tests/test_maintenance_router.py — Create test file with `test_create_list_delete_window_roundtrip` that mounts the maintenance router on a fresh FastAPI app, creates a window via POST, lists it via GET, and deletes it via DELETE. VERIFY: `cd backend && python3 -m pytest tests/test_maintenance_router.py::test_create_list_delete_window_roundtrip -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen]
- [ ] [T2] backend/tests/test_maintenance_router.py — Add `test_end_before_start_is_422` test that verifies POSTing a maintenance window with `end <= start` returns a 422 status code. VERIFY: `cd backend && python3 -m pytest tests/test_maintenance_router.py::test_end_before_start_is_422 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261112-add-the-maintenance-router-create-backen]

# --- 27B-decomposed from roadmap [2026-11-13]: Wire the maintenance router into the app - in `backend/app/main.py` import `maintenance` a (review + tweak) [feat:shrike-monitor-20261113-wire-the-maintenance-router-into-the-app] ---
- [ ] [T1] backend/app/routers/maintenance.py — Add a stub `@router.get("/{window_id}")` endpoint returning `{"window_id": window_id}` VERIFY: `cd backend && python3 -c "from app.routers.maintenance import router; print([r.path for r in router.routes])"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-wire-the-maintenance-router-into-the-app]
- [ ] [T1] backend/app/routers/maintenance.py — Add `router = APIRouter(prefix="/maintenance", tags=["maintenance"])` and a stub `@router.get("")` endpoint returning `{"status": "ok"}` VERIFY: `cd backend && python3 -c "from app.routers.maintenance import router; print(router.prefix)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-wire-the-maintenance-router-into-the-app]
- [ ] [T3] backend/app/main.py — Import `maintenance` from `app.routers` and add `app.include_router(maintenance.router)` immediately after the heartbeat router inclusion VERIFY: `cd backend && python3 -c "from app.main import app; print('/maintenance' in app.openapi()['paths'])"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-wire-the-maintenance-router-into-the-app]
- [ ] [T2] backend/tests/test_maintenance_wired.py — Create file with `test_maintenance_routes_registered` asserting `/maintenance` and `/maintenance/{window_id}` exist in `app.openapi()["paths"]` VERIFY: `cd backend && python3 -m pytest tests/test_maintenance_wired.py -q -k test_maintenance_routes_registered`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-wire-the-maintenance-router-into-the-app]

# --- 27B-decomposed from roadmap [2026-11-13]: Document the maintenance windows and their limits - create `docs/MAINTENANCE.md` stating t (review + tweak) [feat:shrike-monitor-20261113-document-the-maintenance-windows-and-the] ---
- [ ] [T1] docs/MAINTENANCE.md — Create file with section stating windows are held in memory and lost on restart VERIFY: `grep -q "in memory" docs/MAINTENANCE.md && grep -q "lost on restart" docs/MAINTENANCE.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-maintenance-windows-and-the]
- [ ] [T1] docs/MAINTENANCE.md — Add section stating windows do not suppress alerts or probes and only annotate via `annotate_in_maintenance` VERIFY: `grep -q "do not suppress" docs/MAINTENANCE.md && grep -q "annotate_in_maintenance" docs/MAINTENANCE.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-maintenance-windows-and-the]
- [ ] [T1] docs/MAINTENANCE.md — List the three maintenance routes in a code block or list VERIFY: `grep -q "/maintenance" docs/MAINTENANCE.md && grep -c "POST\|GET\|DELETE" docs/MAINTENANCE.md | grep -q "3"`. (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-maintenance-windows-and-the]
- [ ] [T2] backend/tests/test_maintenance_doc.py — Create test file with `test_maintenance_doc_states_the_in_memory_limit` asserting doc contains "in memory" and "/maintenance" VERIFY: `cd backend && python3 -m pytest tests/test_maintenance_doc.py -q -k test_maintenance_doc_states_the_in_memory_limit`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-document-the-maintenance-windows-and-the]

# --- 27B-decomposed from roadmap [2026-11-13]: Add a TCP connect probe - create `backend/app/services/check_tcp.py` with `async def tcp_p (review + tweak) [feat:shrike-monitor-20261113-add-a-tcp-connect-probe-create-backend-a] ---
- [ ] [T1] backend/app/services/check_tcp.py — Add `async def tcp_probe(host: str, port: int, timeout: float = 5.0, connect=None, allow_private: bool = False) -> dict` that imports `resolve_and_validate` from `app.utils.ip_check`, calls it first, returns `{"ok": False, "latency_ms": None, "error": str(e)}` on ValueError, defaults `connect` to a wrapper around `asyncio.open_connection` with `asyncio.wait_for` and writer close, measures latency, and returns `{"ok": True, "latency_ms": float, "error": ""}` on success or `{"ok": False, "latency_ms": None, "error": str(e)}` on OSError/Timeout. VERIFY: `cd backend && python3 -c "import ast; ast.parse(open('app/services/check_tcp.py').read())"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-a-tcp-connect-probe-create-backend-a]
- [ ] [T2] backend/tests/test_check_tcp.py — Add `test_tcp_probe_ok_reports_latency` using a fake `connect` coroutine that returns dummy reader/writer, asserting `result["ok"] is True` and `result["latency_ms"] >= 0`. VERIFY: `cd backend && python3 -m pytest tests/test_check_tcp.py::test_tcp_probe_ok_reports_latency -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-tcp-connect-probe-create-backend-a]
- [ ] [T2] backend/tests/test_check_tcp.py — Add `test_tcp_probe_connect_error_is_not_ok` using a fake `connect` that raises `OSError("boom")`, asserting `result["ok"] is False` and `"boom" in result["error"]`. VERIFY: `cd backend && python3 -m pytest tests/test_check_tcp.py::test_tcp_probe_connect_error_is_not_ok -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-tcp-connect-probe-create-backend-a]
- [ ] [T2] backend/tests/test_check_tcp.py — Add `test_tcp_probe_blocks_private_resolution` using `monkeypatch.setattr` on `resolve_and_validate` to raise `ValueError("blocked")`, asserting `result["ok"] is False` and `"blocked" in result["error"]`. VERIFY: `cd backend && python3 -m pytest tests/test_check_tcp.py::test_tcp_probe_blocks_private_resolution -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-tcp-connect-probe-create-backend-a]

# --- 27B-decomposed from roadmap [2026-11-13]: Add a DNS resolution probe - create `backend/app/services/check_dns.py` with `async def dn (review + tweak) [feat:shrike-monitor-20261113-add-a-dns-resolution-probe-create-backen] ---
- [ ] [T1] backend/app/services/check_dns.py — Add `async def dns_probe(hostname: str, expected_ips: list[str] | None = None, resolver=None) -> dict` that returns `{"ok": bool, "ips": list[str], "latency_ms": float, "error": str | None}`, using an injectable `resolver` coroutine (defaulting to `loop.getaddrinfo` with deduplication) and setting `ok=True` only if IPs resolve and match `expected_ips` if provided. VERIFY: `cd backend && python3 -c "from app.services.check_dns import dns_probe; print('imported')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-a-dns-resolution-probe-create-backen]
- [ ] [T2] backend/tests/test_check_dns.py — Add `test_dns_probe_ok_without_expectation` that mocks a resolver returning valid IPs and asserts `ok=True`, correct `ips`, and `latency_ms > 0`. VERIFY: `cd backend && python3 -m pytest tests/test_check_dns.py::test_dns_probe_ok_without_expectation -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-dns-resolution-probe-create-backen]
- [ ] [T2] backend/tests/test_check_dns.py — Add `test_dns_probe_expected_ip_mismatch_is_not_ok` that mocks a resolver returning IPs not in `expected_ips` and asserts `ok=False`. VERIFY: `cd backend && python3 -m pytest tests/test_check_dns.py::test_dns_probe_expected_ip_mismatch_is_not_ok -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-dns-resolution-probe-create-backen]
- [ ] [T2] backend/tests/test_check_dns.py — Add `test_dns_probe_resolution_error_is_not_ok` that mocks a resolver raising an exception and asserts `ok=False` with the error message in `error`. VERIFY: `cd backend && python3 -m pytest tests/test_check_dns.py::test_dns_probe_resolution_error_is_not_ok -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-dns-resolution-probe-create-backen]

# --- 27B-decomposed from roadmap [2026-11-13]: Add certificate expiry arithmetic - create `backend/app/services/check_tls.py` with `days_ (review + tweak) [feat:shrike-monitor-20261113-add-certificate-expiry-arithmetic-create] ---
- [ ] [T1] backend/app/services/check_tls.py — Add `days_until_expiry(not_after: str, now: float) -> float` using `ssl.cert_time_to_seconds` to calculate fractional days remaining. VERIFY: `cd backend && python3 -c "from app.services.check_tls import days_until_expiry; import ssl; now = ssl.cert_time_to_seconds('Jun  1 12:00:00 2027 GMT'); assert abs(days_until_expiry('Jun  1 12:00:00 2027 GMT', now) - 0.0) < 1e-9"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-certificate-expiry-arithmetic-create]
- [ ] [T2] backend/tests/test_check_tls_expiry.py — Add `test_days_until_expiry_positive_and_negative` verifying positive days for future dates and negative for past dates relative to a fixed `now`. VERIFY: `cd backend && python3 -m pytest tests/test_check_tls_expiry.py -q -k test_days_until_expiry_positive_and_negative`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-certificate-expiry-arithmetic-create]

# --- 27B-decomposed from roadmap [2026-11-13]: Add the TLS probe - in `backend/app/services/check_tls.py` add `async def tls_probe(host:  (review + tweak) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service] ---
- [ ] [T1] backend/app/services/check_tls.py — Add `async def tls_probe(host: str, port: int = 443, min_days: float = 7.0, timeout: float = 5.0, fetch_cert=None, allow_private: bool = False) -> dict` that resolves host via `resolve_and_validate`, uses injected `fetch_cert` or default SSL connection to get cert, calculates `days_left`, and returns `{"ok": days_left >= min_days, "days_left": days_left, "error": None}` on success or `{"ok": False, "days_left": 0.0, "error": str(e)}` on failure. VERIFY: `cd backend && python3 -c "from backend.app.services.check_tls import tls_probe; print('imported')"` (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service]
- [ ] [T1] backend/app/services/check_tls.py — Ensure default `fetch_cert` implementation opens `asyncio.open_connection` with `ssl.create_default_context()` and extracts cert via `get_extra_info("ssl_object").getpeercert()`, handling `ssl.SSLCertVerificationError` to return error dict. VERIFY: `cd backend && python3 -c "import inspect; from backend.app.services.check_tls import tls_probe; src = inspect.getsource(tls_probe); assert 'create_default_context' in src and 'getpeercert' in src"` (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service]
- [ ] [T1] backend/app/services/check_tls.py — Ensure `days_left` calculation uses `datetime.now(timezone.utc)` and cert `notAfter` field, handling missing `notAfter` by returning error dict. VERIFY: `cd backend && python3 -c "import inspect; from backend.app.services.check_tls import tls_probe; src = inspect.getsource(tls_probe); assert 'notAfter' in src and 'timezone.utc' in src"` (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service]
- [ ] [T2] backend/tests/test_check_tls_expiry.py — Add `test_tls_probe_ok_when_enough_days_left_and_not_ok_when_close_to_expiry` with a fake `fetch_cert` returning certs with 30 days and 3 days left, patching `resolve_and_validate` to return valid IP, asserting `ok` is True for 30 days and False for 3 days. VERIFY: `cd backend && python3 -m pytest tests/test_check_tls_expiry.py -q -k test_tls_probe_ok_when_enough_days_left_and_not_ok_when_close_to_expiry` (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service]
- [ ] [T2] backend/tests/test_check_tls_expiry.py — Add `test_tls_probe_error_on_invalid_host` patching `resolve_and_validate` to raise exception, asserting `ok` is False and `error` contains the exception message. VERIFY: `cd backend && python3 -m pytest tests/test_check_tls_expiry.py -q -k test_tls_probe_error_on_invalid_host` (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service]
- [ ] [T2] backend/tests/test_check_tls_expiry.py — Add `test_tls_probe_error_on_ssl_failure` patching `fetch_cert` to raise `ssl.SSLCertVerificationError`, asserting `ok` is False and `error` is populated. VERIFY: `cd backend && python3 -m pytest tests/test_check_tls_expiry.py -q -k test_tls_probe_error_on_ssl_failure` (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-tls-probe-in-backend-app-service]

# --- 27B-decomposed from roadmap [2026-11-13]: Add a check registry with a result adapter - create `backend/app/services/check_registry.p (review + tweak) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt] ---
- [ ] [T1] backend/app/services/check_registry.py — Add `tcp_probe`, `dns_probe`, and `tls_probe` async stub functions returning `{"ok": True, "latency_ms": 0.0, "error": None}` VERIFY: `cd backend && python3 -c "from app.services.check_registry import tcp_probe, dns_probe, tls_probe; import asyncio; assert asyncio.run(tcp_probe()) == {'ok': True, 'latency_ms': 0.0, 'error': None}"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt]
- [ ] [T1] backend/app/services/check_registry.py — Add `CHECKS` dictionary mapping "tcp", "dns", "tls" to their respective probe functions VERIFY: `cd backend && python3 -c "from app.services.check_registry import CHECKS; assert set(CHECKS.keys()) == {'tcp', 'dns', 'tls'}"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt]
- [ ] [T1] backend/app/services/check_registry.py — Add `def to_check_result(probe: dict, now: float)` that constructs and returns an `app.models.CheckResult` instance mapping `probe['ok']`, `probe['latency_ms']`, `probe['error']`, and `now` to the model fields VERIFY: `cd backend && python3 -c "from app.services.check_registry import to_check_result; from app.models import CheckResult; r = to_check_result({'ok': True, 'latency_ms': 10.5, 'error': None}, 123.4); assert isinstance(r, CheckResult) and r.ok == True and r.latency_ms == 10.5 and r.checked_at == 123.4"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt]
- [ ] [T1] backend/tests/test_check_registry.py — Add `test_run_check_dispatches_to_injected_probe` that monkeypatches a probe in `CHECKS` and asserts `run_check` calls it with correct kwargs and returns its result VERIFY: `cd backend && python3 -m pytest tests/test_check_registry.py::test_run_check_dispatches_to_injected_probe -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt]
- [ ] [T1] backend/tests/test_check_registry.py — Add `test_run_check_unknown_kind_raises` that asserts `run_check("unknown")` raises `ValueError` with message "unknown check kind: unknown" VERIFY: `cd backend && python3 -m pytest tests/test_check_registry.py::test_run_check_unknown_kind_raises -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt]
- [ ] [T1] backend/tests/test_check_registry.py — Add `test_to_check_result_maps_fields` that asserts `to_check_result` correctly maps input dict fields to `CheckResult` attributes including `checked_at` VERIFY: `cd backend && python3 -m pytest tests/test_check_registry.py::test_to_check_result_maps_fields -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-a-check-registry-with-a-result-adapt]

# --- 27B-decomposed from roadmap [2026-11-13]: Document the check modules - create `docs/CHECK_TYPES.md` describing the three probes, the (review + tweak) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c] ---
- [ ] [T1] backend/app/services/checker.py — Add a module-level constant `CHECK_REGISTRY` mapping each probe name to its return key tuple and private-address guard status. VERIFY: `cd backend && python3 -c "from app.services.checker import CHECK_REGISTRY; assert 'http' in CHECK_REGISTRY"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c]
- [ ] [T1] docs/CHECK_TYPES.md — Create the documentation file describing the three probes, their return keys, the private-address guard, and the note that they are not selectable via `MonitorCreate.type` yet. VERIFY: `test -f docs/CHECK_TYPES.md && grep -q "private-address" docs/CHECK_TYPES.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c]
- [ ] [T1] backend/tests/test_check_types_doc.py — Create the test file with the function `test_check_types_doc_names_registry_kinds` that asserts every key in `CHECK_REGISTRY` appears in the content of `docs/CHECK_TYPES.md`. VERIFY: `cd backend && python3 -m pytest tests/test_check_types_doc.py -q -k test_check_types_doc_names_registry_kinds`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c]
- [ ] [T2] docs/CHECK_TYPES.md — Ensure the documentation explicitly lists the return keys for each probe (e.g., `status`, `latency_ms`) matching the implementation in `checker.py`. VERIFY: `grep -q "latency_ms" docs/CHECK_TYPES.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c]
- [ ] [T2] docs/CHECK_TYPES.md — Add a section explicitly stating that `MonitorCreate.type` does not currently accept these probe names and requires a maintainer decision for contract change. VERIFY: `grep -q "MonitorCreate.type" docs/CHECK_TYPES.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c]
- [ ] [T2] backend/tests/test_check_types_doc.py — Add a test `test_check_types_doc_mentions_private_guard` that asserts the string "private-address guard" or similar is present in the doc. VERIFY: `cd backend && python3 -m pytest tests/test_check_types_doc.py -q -k test_check_types_doc_mentions_private_guard`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-document-the-check-modules-create-docs-c]

# --- 27B-decomposed from roadmap [2026-11-13]: Add the SLA row builder - create `backend/app/services/sla_report.py` with `CSV_COLUMNS =  (review + tweak) [feat:shrike-monitor-20261113-add-the-sla-row-builder-create-backend-a] ---
- [ ] [T2] backend/app/services/sla_report.py — Implement `build_sla_rows` to filter results by `since`/`until`, count checks/failures, and calculate `uptime_percent` (100.0 if no checks, else rounded to 2 decimals). VERIFY: `cd backend && python3 -c "from app.services.sla_report import build_sla_rows; m=[{'id':'m1','name':'t','type':'http'}]; r={'m1':[{'checked_at':1.0,'ok':True}]}; res=build_sla_rows(m,r,0.0,2.0); assert res[0]['uptime_percent']==100.0 and res[0]['checks']==1"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-sla-row-builder-create-backend-a]
- [ ] [T1] backend/app/services/sla_report.py — Add module with `CSV_COLUMNS` constant and empty `build_sla_rows` stub returning `[]`. VERIFY: `cd backend && python3 -c "from app.services.sla_report import CSV_COLUMNS; assert CSV_COLUMNS == ['monitor_id', 'name', 'type', 'checks', 'failures', 'uptime_percent', 'p95_latency_ms', 'downtime_seconds']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-sla-row-builder-create-backend-a]
- [ ] [T3] backend/app/services/sla_report.py — Extend `build_sla_rows` to calculate `p95_latency_ms` using `app.utils.percentile.percentile` on ok results with latency, returning `None` if no valid latencies. VERIFY: `cd backend && python3 -c "from app.services.sla_report import build_sla_rows; m=[{'id':'m1','name':'t','type':'http'}]; r={'m1':[{'checked_at':1.0,'ok':True,'latency_ms':100.0}]}; res=build_sla_rows(m,r,0.0,2.0); assert res[0]['p95_latency_ms']==100.0"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-sla-row-builder-create-backend-a]
- [ ] [T4] backend/app/services/sla_report.py — Extend `build_sla_rows` to calculate `downtime_seconds` using `app.utils.downtime.downtime_seconds` on `(checked_at, ok)` pairs. VERIFY: `cd backend && python3 -c "from app.services.sla_report import build_sla_rows; m=[{'id':'m1','name':'t','type':'http'}]; r={'m1':[{'checked_at':1.0,'ok':False},{'checked_at':2.0,'ok':True}]}; res=build_sla_rows(m,r,0.0,3.0); assert res[0]['downtime_seconds']>=1.0"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-sla-row-builder-create-backend-a]
- [ ] [T5] backend/tests/test_sla_report_rows.py — Create test file with `test_build_sla_rows_counts_failures_and_uptime` verifying failure counts and uptime calculation for a monitor with mixed results. VERIFY: `cd backend && python3 -m pytest tests/test_sla_report_rows.py::test_build_sla_rows_counts_failures_and_uptime -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-sla-row-builder-create-backend-a]

# --- 27B-decomposed from roadmap [2026-11-13]: Add CSV rendering - in `backend/app/services/sla_report.py` add `rows_to_csv(rows: list[di (review + tweak) [feat:shrike-monitor-20261113-add-csv-rendering-in-backend-app-service] ---
- [ ] [T1] backend/app/services/sla_report.py — Add `CSV_COLUMNS` constant and `rows_to_csv(rows: list[dict]) -> str` function using `csv` module with `\n` line endings and empty string for None values. VERIFY: `cd backend && python3 -c "from app.services.sla_report import rows_to_csv, CSV_COLUMNS; print('OK')"` (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-csv-rendering-in-backend-app-service]
- [ ] [T1] backend/tests/test_sla_report_csv.py — Create test file with `test_rows_to_csv_has_header_and_one_line_per_row` asserting header matches `CSV_COLUMNS` and line count equals row count + 1. VERIFY: `cd backend && python3 -m pytest tests/test_sla_report_csv.py::test_rows_to_csv_has_header_and_one_line_per_row -q` (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-csv-rendering-in-backend-app-service]
- [ ] [T2] backend/tests/test_sla_report_csv.py — Add `test_rows_to_csv_renders_none_as_empty_cell` asserting that None values in input rows result in empty strings in the CSV output. VERIFY: `cd backend && python3 -m pytest tests/test_sla_report_csv.py::test_rows_to_csv_renders_none_as_empty_cell -q` (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-csv-rendering-in-backend-app-service]

# --- 27B-decomposed from roadmap [2026-11-13]: Add `GET /reports/sla` as its own router - create `backend/app/routers/reports.py` gated b (review + tweak) [feat:shrike-monitor-20261113-add-get-reports-sla-as-its-own-router-cr] ---
- [ ] [T1] backend/app/routers/reports.py — Add `require_api_token` dependency import and define `sla_report` endpoint with `since`, `until`, `format` query params, defaulting `since` to 7 days ago, `until` to now, and handling `json`/`csv` formats. VERIFY: `cd backend && python3 -c "from app.routers.reports import sla_report; print('ok')"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261113-add-get-reports-sla-as-its-own-router-cr]
- [ ] [T2] backend/app/routers/reports.py — Implement logic to fetch monitor SLA data from store, format as JSON list or CSV string with header row, and return appropriate response type. VERIFY: `cd backend && python3 -c "from app.routers.reports import sla_report; print('ok')"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261113-add-get-reports-sla-as-its-own-router-cr]
- [ ] [T3] backend/app/routers/reports.py — Ensure `format` parameter defaults to `json` for any non-csv value and returns `PlainTextResponse` with `text/csv` media type for csv. VERIFY: `cd backend && python3 -c "from app.routers.reports import sla_report; print('ok')"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261113-add-get-reports-sla-as-its-own-router-cr]
- [ ] [T4] backend/tests/test_reports_router.py — Create test file with `test_sla_report_json_lists_each_monitor` that mounts router on fresh FastAPI, calls endpoint with default format, and asserts JSON response contains monitor list. VERIFY: `cd backend && python3 -m pytest tests/test_reports_router.py::test_sla_report_json_lists_each_monitor -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-get-reports-sla-as-its-own-router-cr]
- [ ] [T5] backend/tests/test_reports_router.py — Add `test_sla_report_csv_has_header_row` that calls endpoint with `format=csv`, asserts response media type is `text/csv`, and first line contains header columns. VERIFY: `cd backend && python3 -m pytest tests/test_reports_router.py::test_sla_report_csv_has_header_row -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-get-reports-sla-as-its-own-router-cr]

# --- 27B-decomposed from roadmap [2026-11-13]: Wire the reports router into the app - in `backend/app/main.py` import `reports` and inclu (review + tweak) [feat:shrike-monitor-20261113-wire-the-reports-router-into-the-app-in-] ---
- [ ] [T1] backend/app/routers/reports.py — Create the file with a FastAPI APIRouter named `router` and a GET endpoint `/sla` that returns `{"status": "ok"}`. VERIFY: `cd backend && python3 -c "from app.routers.reports import router; assert hasattr(router, 'routes')"` (cat:endpoint; multifile:no) [feat:shrike-monitor-20261113-wire-the-reports-router-into-the-app-in-]
- [ ] [T3] backend/app/main.py — Import `from app.routers import reports` and add `app.include_router(reports.router, prefix="/reports")` immediately after the heartbeat router inclusion. VERIFY: `cd backend && python3 -m pytest tests/test_reports_wired.py -q -k test_reports_sla_route_registered` (cat:python; multifile:no) [feat:shrike-monitor-20261113-wire-the-reports-router-into-the-app-in-]
- [ ] [T2] backend/tests/test_reports_wired.py — Create the file with a test function `test_reports_sla_route_registered` that imports `app` from `backend.app.main` and asserts `/reports/sla` is in `app.openapi()["paths"]`. VERIFY: `cd backend && python3 -m pytest tests/test_reports_wired.py -q -k test_reports_sla_route_registered --collect-only` (cat:test; multifile:no) [feat:shrike-monitor-20261113-wire-the-reports-router-into-the-app-in-]

# --- 27B-decomposed from roadmap [2026-11-13]: Document the report and pin its columns - create `docs/SLA_REPORT.md` describing the query (review + tweak) [feat:shrike-monitor-20261113-document-the-report-and-pin-its-columns-] ---
- [ ] [T1] backend/app/utils/sla_met.py — Add `CSV_COLUMNS` constant listing the exact column names for the SLA report output. VERIFY: `cd backend && python3 -c "from app.utils.sla_met import CSV_COLUMNS; assert len(CSV_COLUMNS) > 0"` (cat:python; multifile:no) [feat:shrike-monitor-20261113-document-the-report-and-pin-its-columns-]
- [ ] [T2] docs/SLA_REPORT.md — Create documentation file describing query parameters, column meanings, and defaults for the SLA report. VERIFY: `test -f docs/SLA_REPORT.md && grep -q "query parameters" docs/SLA_REPORT.md` (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-report-and-pin-its-columns-]
- [ ] [T3] docs/SLA_REPORT.md — Ensure each name in `CSV_COLUMNS` is explicitly documented in the markdown file. VERIFY: `cd backend && python3 -c "from app.utils.sla_met import CSV_COLUMNS; content = open('../docs/SLA_REPORT.md').read(); missing = [c for c in CSV_COLUMNS if c not in content]; assert not missing, f'Missing: {missing}'"` (cat:docs; multifile:no) [feat:shrike-monitor-20261113-document-the-report-and-pin-its-columns-]
- [ ] [T4] backend/tests/test_sla_report_doc.py — Create test file with `test_sla_report_doc_lists_every_csv_column` that asserts each name in `CSV_COLUMNS` appears in the doc. VERIFY: `cd backend && python3 -m pytest tests/test_sla_report_doc.py -q -k test_sla_report_doc_lists_every_csv_column` (cat:test; multifile:no) [feat:shrike-monitor-20261113-document-the-report-and-pin-its-columns-]
- [ ] [T5] backend/tests/test_sla_report_doc.py — Add import for `CSV_COLUMNS` from `app.utils.sla_met` and file path resolution for `docs/SLA_REPORT.md`. VERIFY: `cd backend && python3 -m pytest tests/test_sla_report_doc.py -q -k test_sla_report_doc_lists_every_csv_column` (cat:test; multifile:no) [feat:shrike-monitor-20261113-document-the-report-and-pin-its-columns-]

# --- 27B-decomposed from roadmap [2026-11-13]: Add the percentile summary - create `backend/app/services/latency_report.py` with `latency (review + tweak) [feat:shrike-monitor-20261113-add-the-percentile-summary-create-backen] ---
- [ ] [T1] backend/app/services/latency_report.py — Add `latency_percentiles` function that returns a dict with keys "count", "p50", "p90", "p95", "p99" using `app.utils.percentile.percentile`, ensuring all percentile values are None if the input list is empty. VERIFY: `cd backend && python3 -c "from app.services.latency_report import latency_percentiles; print(latency_percentiles([]))"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-percentile-summary-create-backen]
- [ ] [T1] backend/tests/test_latency_report_percentiles.py — Add test `test_latency_percentiles_empty_is_none` asserting that `latency_percentiles([])` returns a dict where p50, p90, p95, and p99 are all None. VERIFY: `cd backend && python3 -m pytest tests/test_latency_report_percentiles.py::test_latency_percentiles_empty_is_none -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-percentile-summary-create-backen]
- [ ] [T1] backend/tests/test_latency_report_percentiles.py — Add test `test_latency_percentiles_known_values` asserting that `latency_percentiles([1, 2, 3, 4, 5])` returns correct count and percentile values calculated via `app.utils.percentile.percentile`. VERIFY: `cd backend && python3 -m pytest tests/test_latency_report_percentiles.py::test_latency_percentiles_known_values -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-percentile-summary-create-backen]

# --- 27B-decomposed from roadmap [2026-11-13]: Add the histogram - in `backend/app/services/latency_report.py` add `latency_histogram(lat (review + tweak) [feat:shrike-monitor-20261113-add-the-histogram-in-backend-app-service] ---
- [ ] [T1] backend/app/services/latency_report.py — Add `latency_histogram(latencies: list[float], edges=(50, 100, 250, 500, 1000, 2500)) -> list[dict]` function that returns cumulative counts per edge and a final `{"le": "+Inf", "count": total}` bucket. VERIFY: `cd backend && python3 -c "from app.services.latency_report import latency_histogram; print(latency_histogram([10, 60, 300]))"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-histogram-in-backend-app-service]
- [ ] [T2] backend/tests/test_latency_report_histogram.py — Add test `test_latency_histogram_is_cumulative_with_inf_bucket` asserting that for input `[10, 60, 300]`, the counts are cumulative (e.g., le=100 has count 2) and the last bucket is `{"le": "+Inf", "count": 3}`. VERIFY: `cd backend && python3 -m pytest tests/test_latency_report_histogram.py -q -k test_latency_histogram_is_cumulative_with_inf_bucket`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-histogram-in-backend-app-service]

# --- 27B-decomposed from roadmap [2026-11-13]: Add `GET /latency/{monitor_id}` as its own router - create `backend/app/routers/latency.py (review + tweak) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro] ---
- [ ] [T1] backend/app/routers/latency.py — Add `latency_histogram(results: list[dict], window_seconds: int) -> dict` helper that counts latency buckets (0-100ms, 100-500ms, 500ms-1s, 1s+) for results within the window. VERIFY: `cd backend && python3 -c "from app.routers.latency import latency_histogram; print(latency_histogram([{'latency_ms': 50}, {'latency_ms': 200}], 86400))"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro]
- [ ] [T1] backend/app/routers/latency.py — Add `get_latency(monitor_id: str, window_seconds: int = Query(86400, ge=60, le=2592000), store=Depends(get_store), _=Depends(require_api_token))` endpoint that returns 404 if monitor not found, else returns dict with `monitor_id`, `window_seconds`, `latency_percentiles(...)`, and `histogram`. VERIFY: `cd backend && python3 -c "from app.routers.latency import get_latency; print(get_latency.__name__)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro]
- [ ] [T3] backend/app/routers/__init__.py — Import and export the latency router module if the package uses explicit exports, or ensure it's discoverable by the main app. VERIFY: `cd backend && python3 -c "from app.routers import latency; print(latency)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro]
- [ ] [T4] backend/app/main.py — Include the latency router in the FastAPI app instance with prefix `/latency` if not auto-discovered. VERIFY: `cd backend && python3 -c "from app.main import app; print([r.path for r in app.routes if 'latency' in r.path])"`. (cat:python; multifile:yes) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro]
- [ ] [T2] backend/tests/test_latency_router.py — Create test file with `test_latency_report_for_monitor_with_results` that mounts the latency router on a fresh FastAPI app, creates a monitor with ok results, calls the endpoint, and asserts 200 status with correct keys. VERIFY: `cd backend && python3 -m pytest tests/test_latency_router.py::test_latency_report_for_monitor_with_results -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro]
- [ ] [T2] backend/tests/test_latency_router.py — Add `test_latency_report_unknown_monitor_is_404` that calls the endpoint with an unknown monitor ID and asserts 404 status with detail "monitor not found". VERIFY: `cd backend && python3 -m pytest tests/test_latency_router.py::test_latency_report_unknown_monitor_is_404 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-get-latency-monitor-id-as-its-own-ro]

# --- 27B-decomposed from roadmap [2026-11-13]: Wire the latency router into the app - in `backend/app/main.py` import `latency` and inclu (review + tweak) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-] ---
- [ ] [T1] backend/app/routers/latency.py — Create the latency router module with a GET endpoint `/latency/{monitor_id}` that returns 200 OK VERIFY: `cd backend && python3 -c "from backend.app.routers.latency import router; assert router is not None"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-]
- [ ] [T1] backend/tests/test_latency_router.py — Create a test file asserting the latency router exists and has the correct path prefix VERIFY: `cd backend && python3 -m pytest tests/test_latency_router.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-]
- [ ] [T3] backend/app/main.py — Import the latency router and include it in the FastAPI app after the heartbeat router VERIFY: `cd backend && python3 -c "from backend.app.main import app; assert '/latency/{monitor_id}' in app.openapi()['paths']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-]
- [ ] [T1] backend/tests/test_latency_wired.py — Create a test file with `test_latency_route_registered` asserting `/latency/{monitor_id}` is in `app.openapi()["paths"]` VERIFY: `cd backend && python3 -m pytest tests/test_latency_wired.py -q -k test_latency_route_registered`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-]
- [ ] [T2] backend/tests/test_latency_wired.py — Add a test verifying the latency route returns 200 status code for a valid monitor ID VERIFY: `cd backend && python3 -m pytest tests/test_latency_wired.py -q -k test_latency_route_returns_200`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-]
- [ ] [T2] backend/tests/test_latency_wired.py — Add a test verifying the latency route returns 404 for a non-existent monitor ID VERIFY: `cd backend && python3 -m pytest tests/test_latency_wired.py -q -k test_latency_route_returns_404`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-wire-the-latency-router-into-the-app-in-]

# --- 27B-decomposed from roadmap [2026-11-13]: Add the hourly bucket helper - create `backend/app/utils/timeline.py` with `hourly_ok_fail (review + tweak) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back] ---
- [ ] [T1] backend/app/utils/timeline.py — Add `hourly_ok_failed` function that returns an empty list if `hours <= 0`. VERIFY: `cd backend && python3 -c "from backend.app.utils.timeline import hourly_ok_failed; assert hourly_ok_failed([], 0, 24) == []"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back]
- [ ] [T1] backend/app/utils/timeline.py — Implement bucket generation logic in `hourly_ok_failed` to return exactly `hours` dicts with correct `hour_start` timestamps ordered oldest first. VERIFY: `cd backend && python3 -c "from backend.app.utils.timeline import hourly_ok_failed; r = hourly_ok_failed([], 1000.0, 3); assert len(r) == 3 and r[0]['hour_start'] < r[1]['hour_start'] < r[2]['hour_start']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back]
- [ ] [T1] backend/app/utils/timeline.py — Implement result classification logic in `hourly_ok_failed` to count `ok` and `failed` results into the correct bucket based on `checked_at`, ignoring out-of-window or future results. VERIFY: `cd backend && python3 -c "from backend.app.utils.timeline import hourly_ok_failed; from backend.app.models import CheckResult; r = [CheckResult(checked_at=1000.0, status='ok'), CheckResult(checked_at=2000.0, status='fail')]; res = hourly_ok_failed(r, 3000.0, 1); assert res[0]['ok'] == 1 and res[0]['failed'] == 1"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back]
- [ ] [T2] backend/tests/test_timeline_helper.py — Create test file with `test_buckets_are_oldest_first_with_hour_start` verifying bucket order and start times. VERIFY: `cd backend && python3 -m pytest tests/test_timeline_helper.py::test_buckets_are_oldest_first_with_hour_start -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back]
- [ ] [T2] backend/tests/test_timeline_helper.py — Add `test_ok_and_failed_are_counted_separately` verifying correct counting of ok/failed statuses. VERIFY: `cd backend && python3 -m pytest tests/test_timeline_helper.py::test_ok_and_failed_are_counted_separately -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back]
- [ ] [T2] backend/tests/test_timeline_helper.py — Add `test_results_outside_the_window_are_ignored` verifying exclusion of out-of-window and future results. VERIFY: `cd backend && python3 -m pytest tests/test_timeline_helper.py::test_results_outside_the_window_are_ignored -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back]
- [ ] [T2] backend/tests/test_timeline_helper.py — Add `test_non_positive_hours_gives_empty_list` verifying empty return for hours <= 0. VERIFY: `cd backend && python3 -m pytest tests/test_timeline_helper.py::test_non_positive_hours_gives_empty_list -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-hourly-bucket-helper-create-back]

# --- 27B-decomposed from roadmap [2026-11-13]: Add the timeline router - create `backend/app/routers/timeline.py` with `router = APIRoute (review + tweak) [feat:shrike-monitor-20261113-add-the-timeline-router-create-backend-a] ---
- [ ] [T1] backend/app/utils/timeline.py — Add `hourly_ok_failed(results: list, now: float, hours: int) -> list[dict]` that buckets results into hourly slots based on `checked_at`, returning a list of dicts with keys `ok` and `failed`. VERIFY: `cd backend && python3 -m pytest tests/test_timeline_utils.py -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-timeline-router-create-backend-a]
- [ ] [T3] backend/app/routers/timeline.py — Create router with `APIRouter(prefix="/monitors", tags=["monitors"], dependencies=[Depends(require_api_token)])` and `GET /{monitor_id}/timeline` endpoint that returns 404 if monitor not found, else returns JSON with monitor_id, hours, and buckets from `hourly_ok_failed`. VERIFY: `cd backend && python3 -c "from app.routers.timeline import router; print(router.prefix)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-timeline-router-create-backend-a]
- [ ] [T5] backend/app/routers/__init__.py — Import `timeline` router and add it to the routers list or export it for main app inclusion. VERIFY: `cd backend && python3 -c "from app.routers import timeline; print('ok')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261113-add-the-timeline-router-create-backend-a]
- [ ] [T2] backend/tests/test_timeline_utils.py — Create test file for `hourly_ok_failed` verifying bucket count, timestamp alignment, and correct ok/failed counts for mixed results. VERIFY: `cd backend && python3 -m pytest tests/test_timeline_utils.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-timeline-router-create-backend-a]
- [ ] [T4] backend/tests/test_timeline_router.py — Create test file mounting timeline router on fresh FastAPI app, creating a monitor, recording check results, asserting 200 response with correct bucket structure and 404 for unknown ID. VERIFY: `cd backend && python3 -m pytest tests/test_timeline_router.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261113-add-the-timeline-router-create-backend-a]
