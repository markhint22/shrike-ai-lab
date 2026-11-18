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
- [ ] [T1] backend/app/services/tags.py — Add `class TagRegistry` with `get(monitor_id: str) -> list[str]`, `set_tags(monitor_id: str, tags: list[str]) -> list[str]` (dedupes case-insensitively, keeps first occurrence), and `remove(monitor_id: str) -> None`; export singleton `registry`. VERIFY: `cd backend && python3 -c "from app.services.tags import registry; assert registry.set_tags('m1', ['Prod','prod','api']) == ['api','prod']; assert registry.get('m1') == ['api','prod']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-per-monitor-tags-routes-create-b]
- [ ] [T2] backend/tests/test_tags_service.py — Add unit tests for `TagRegistry` verifying case-insensitive deduplication order, empty list handling, and `remove` clearing state. VERIFY: `cd backend && python3 -m pytest tests/test_tags_service.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-per-monitor-tags-routes-create-b]
- [ ] [T3] backend/app/routers/tags.py — Create file with `router = APIRouter(prefix="/monitors", tags=["monitors"], dependencies=[Depends(require_api_token)])`, `class TagsBody(BaseModel)` with `tags: list[str] = Field(default_factory=list, max_length=50)`, and `GET /{monitor_id}/tags` returning 404 if `store.get(monitor_id)` is None else `{"monitor_id": monitor_id, "tags": registry.get(monitor_id)}`. VERIFY: `cd backend && python3 -c "from app.routers.tags import router, TagsBody; assert router.prefix == '/monitors' and hasattr(TagsBody, 'tags')"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261117-add-the-per-monitor-tags-routes-create-b]
- [ ] [T5] backend/tests/test_tags_router.py — Create test file mounting `tags.router` on fresh `FastAPI()`, creating monitor via `await store.create('probe', url='http://example.com')`, asserting PUT `['Prod','prod','api']` returns `['api','prod']`, GET returns same, unknown ID returns 404 for both, and cleanup with `store.clear()` and `registry.remove(id)`. VERIFY: `cd backend && python3 -m pytest tests/test_tags_router.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-per-monitor-tags-routes-create-b]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the tag listing routes - in `backend/app/routers/tags.py` add a second router `tag_ind (review + tweak) [feat:shrike-monitor-20261117-add-the-tag-listing-routes-in-backend-ap] ---
- [ ] [T1] backend/app/routers/tags.py — Add `tag_index_router` with `GET ""` and `GET "/{tag}/monitors` endpoints using `registry.counts()` and `registry.monitors_with(tag)` VERIFY: `cd backend && python3 -c "from backend.app.routers.tags import tag_index_router; print('ok')"` (cat:endpoint; multifile:no) [feat:shrike-monitor-20261117-add-the-tag-listing-routes-in-backend-ap]
- [ ] [T2] backend/tests/test_tag_index_router.py — Create test file mounting `tag_index_router` on fresh `FastAPI()` and verifying `/tags` returns correct counts for seeded registry VERIFY: `cd backend && python3 -m pytest tests/test_tag_index_router.py::test_tags_list -q` (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-tag-listing-routes-in-backend-ap]
- [ ] [T3] backend/tests/test_tag_index_router.py — Add test case verifying `/tags/b/monitors` returns `['m1', 'm2']` for tag 'b' VERIFY: `cd backend && python3 -m pytest tests/test_tag_index_router.py::test_tag_monitors_list -q` (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-tag-listing-routes-in-backend-ap]
- [ ] [T4] backend/tests/test_tag_index_router.py — Add test case verifying unknown tag returns empty list with status 200 VERIFY: `cd backend && python3 -m pytest tests/test_tag_index_router.py::test_unknown_tag_empty -q` (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-tag-listing-routes-in-backend-ap]
- [ ] [T5] backend/tests/test_tag_index_router.py — Add cleanup logic to remove 'm1' and 'm2' from registry at end of test suite VERIFY: `cd backend && python3 -m pytest tests/test_tag_index_router.py -q` (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-tag-listing-routes-in-backend-ap]

# --- 27B-decomposed from roadmap [2026-11-17]: Wire the tag routers - in `backend/app/main.py` add `tags` to the existing `from app.route (review + tweak) [feat:shrike-monitor-20261117-wire-the-tag-routers-in-backend-app-main] ---
- [ ] [T1] backend/app/routers/tags.py — Add `router = APIRouter()` and `tag_index_router = APIRouter()` definitions with placeholder routes for `/monitors/{monitor_id}/tags` and `/tags` to ensure importability. VERIFY: `cd backend && python3 -c "from app.routers.tags import router, tag_index_router; print('ok')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-wire-the-tag-routers-in-backend-app-main]
- [ ] [T2] backend/app/routers/tags.py — Implement logic in the `/monitors/{monitor_id}/tags` route to return 404 if the monitor ID does not exist in the store. VERIFY: `cd backend && python3 -m pytest tests/test_tags_wired.py::test_unknown_monitor_tags_is_404 -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-wire-the-tag-routers-in-backend-app-main]
- [ ] [T3] backend/app/main.py — Add `tags` to the `from app.routers import ...` line and insert `app.include_router(tags.router)` and `app.include_router(tags.tag_index_router)` immediately after `app.include_router(monitors.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/monitors/{monitor_id}/tags' in app.openapi()['paths']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-wire-the-tag-routers-in-backend-app-main]
- [ ] [T4] backend/tests/test_tags_wired.py — Create the file with `test_tag_routes_registered` asserting `/monitors/{monitor_id}/tags` and `/tags` are in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_tags_wired.py::test_tag_routes_registered -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-wire-the-tag-routers-in-backend-app-main]
- [ ] [T5] backend/tests/test_tags_wired.py — Add `test_unknown_monitor_tags_is_404` using `TestClient` to verify 404 response for non-existent monitor, ensuring `settings.monitor_api_token` is unset and restored in `finally`. VERIFY: `cd backend && python3 -m pytest tests/test_tags_wired.py::test_unknown_monitor_tags_is_404 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-wire-the-tag-routers-in-backend-app-main]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the badge colour table - create `backend/app/utils/badge.py` with `BADGE_COLORS: dict[ (review + tweak) [feat:shrike-monitor-20261117-add-the-badge-colour-table-create-backen] ---
- [ ] [T1] backend/app/utils/badge.py — Add `BADGE_COLORS` dictionary mapping "up", "down", "degraded", "pending" to their respective hex color codes. VERIFY: `cd backend && python3 -c "from app.utils.badge import BADGE_COLORS; assert BADGE_COLORS['up'] == '#3fb950' and BADGE_COLORS['down'] == '#f85149' and BADGE_COLORS['degraded'] == '#d29922' and BADGE_COLORS['pending'] == '#8b949e'"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-colour-table-create-backen]
- [ ] [T1] backend/app/utils/badge.py — Add `badge_color(status: str) -> str` function that returns `BADGE_COLORS[status]` if status is in `BADGE_COLORS`, otherwise returns `BADGE_COLORS["pending"]`. VERIFY: `cd backend && python3 -c "from app.utils.badge import badge_color; assert badge_color('up') == '#3fb950' and badge_color('unknown') == '#8b949e'"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-colour-table-create-backen]
- [ ] [T2] backend/tests/test_badge_color.py — Create test file with `test_each_status_has_its_colour` asserting `badge_color` returns the correct hex for "up", "down", "degraded", and "pending". VERIFY: `cd backend && python3 -m pytest tests/test_badge_color.py::test_each_status_has_its_colour -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-colour-table-create-backen]
- [ ] [T2] backend/tests/test_badge_color.py — Add `test_unknown_status_uses_the_pending_colour` asserting `badge_color("critical")` and `badge_color("")` return the pending color `#8b949e`. VERIFY: `cd backend && python3 -m pytest tests/test_badge_color.py::test_unknown_status_uses_the_pending_colour -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-colour-table-create-backen]
- [ ] [T2] backend/tests/test_badge_color.py — Add `test_colours_are_hex_values` asserting all values in `BADGE_COLORS` match the regex `^#[0-9a-f]{6}$`. VERIFY: `cd backend && python3 -m pytest tests/test_badge_color.py::test_colours_are_hex_values -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-colour-table-create-backen]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the SVG renderer - in `backend/app/utils/badge.py` add `render_badge_svg(label: str, m (review + tweak) [feat:shrike-monitor-20261117-add-the-svg-renderer-in-backend-app-util] ---
- [ ] [T1] backend/app/utils/badge.py — Add `badge_color(status: str) -> str` returning a hex color string based on status input VERIFY: `cd backend && python3 -c "from app.utils.badge import badge_color; assert badge_color('ok') == '#4c1"'`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-svg-renderer-in-backend-app-util]
- [ ] [T2] backend/app/utils/badge.py — Add `render_badge_svg(label: str, message: str, status: str) -> str` constructing the SVG string with correct width formula, `role="img"`, `aria-label`, escaped text via `xml.sax.saxutils.escape`, and `badge_color(status)` fill VERIFY: `cd backend && python3 -c "from app.utils.badge import render_badge_svg; s=render_badge_svg('a','b','ok'); assert s.startswith('<svg') and 'role=\"img\"' in s and 'aria-label=\"a: b\"' in s"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-svg-renderer-in-backend-app-util]
- [ ] [T3] backend/tests/test_badge_svg.py — Add `test_svg_contains_label_message_and_colour` asserting the SVG output contains the label, message, and the correct color from `badge_color` VERIFY: `cd backend && python3 -m pytest tests/test_badge_svg.py::test_svg_contains_label_message_and_colour -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-svg-renderer-in-backend-app-util]
- [ ] [T4] backend/tests/test_badge_svg.py — Add `test_markup_in_label_is_escaped` asserting `<script>x</script>` in label results in `&lt;script&gt;` in output and raw tags are absent VERIFY: `cd backend && python3 -m pytest tests/test_badge_svg.py::test_markup_in_label_is_escaped -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-svg-renderer-in-backend-app-util]
- [ ] [T5] backend/tests/test_badge_svg.py — Add `test_quote_in_message_is_escaped_in_aria_label` asserting a double quote in message appears as `&quot;` in the `aria-label` attribute VERIFY: `cd backend && python3 -m pytest tests/test_badge_svg.py::test_quote_in_message_is_escaped_in_aria_label -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-svg-renderer-in-backend-app-util]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the badge router - create `backend/app/routers/badge.py` with `router = APIRouter(pref (review + tweak) [feat:shrike-monitor-20261117-add-the-badge-router-create-backend-app-] ---
- [ ] [T1] backend/app/routers/badge.py — Add `render_badge_svg(name: str, status: str, color: str) -> str` returning a valid SVG string containing the monitor name and the hex color code. VERIFY: `cd backend && python3 -c "from app.routers.badge import render_badge_svg; svg = render_badge_svg('test', 'ok', '#3fb950'); assert 'test' in svg and '#3fb950' in svg"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-router-create-backend-app-]
- [ ] [T2] backend/app/routers/badge.py — Add `router = APIRouter(prefix="/monitors", tags=["monitors"], dependencies=[Depends(require_api_token)])` and the `GET /{monitor_id}/badge` endpoint that returns 404 if monitor is missing, otherwise returns SVG response with `no-store` cache control. VERIFY: `cd backend && python3 -c "from app.routers.badge import router; assert router.prefix == '/monitors' and len(router.routes) > 0"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-router-create-backend-app-]
- [ ] [T3] backend/app/routers/__init__.py — Import `badge` router and include it in the main router aggregation. VERIFY: `cd backend && python3 -c "from app.routers import badge; print('ok')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-router-create-backend-app-]
- [ ] [T4] backend/app/main.py — Include the `badge` router in the FastAPI application instance. VERIFY: `cd backend && python3 -c "from app.main import app; routes = [r.path for r in app.routes]; assert any('/monitors/{monitor_id}/badge' in p for p in routes)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-router-create-backend-app-]
- [ ] [T5] backend/tests/test_badge_router.py — Create test file that mounts only the badge router on a fresh FastAPI app, creates a monitor named 'probe', records an ok CheckResult, asserts 200 status, SVG content type, no-store header, body contains 'probe' and '#3fb950', asserts 404 for unknown id, and calls store.clear(). VERIFY: `cd backend && python3 -m pytest tests/test_badge_router.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-badge-router-create-backend-app-]

# --- 27B-decomposed from roadmap [2026-11-17]: Wire the badge router - in `backend/app/main.py` add `badge` to the existing `from app.rou (review + tweak) [feat:shrike-monitor-20261117-wire-the-badge-router-in-backend-app-mai] ---
- [ ] [T3] backend/app/main.py — Add `badge` to the `from app.routers import ...` line and insert `app.include_router(badge.router)` immediately after `app.include_router(monitors.router)` VERIFY: `cd backend && python3 -c "from app.main import app; assert '/monitors/{monitor_id}/badge' in app.openapi()['paths']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-wire-the-badge-router-in-backend-app-mai]
- [ ] [T2] backend/tests/test_badge_wired.py — Create file with `test_badge_route_registered` asserting `/monitors/{monitor_id}/badge` is in `app.openapi()['paths']` VERIFY: `cd backend && python3 -m pytest tests/test_badge_wired.py::test_badge_route_registered -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-wire-the-badge-router-in-backend-app-mai]
- [ ] [T2] backend/tests/test_badge_wired.py — Add `test_badge_requires_the_token_when_one_is_set` that sets `settings.monitor_api_token`, asserts 401 without token, 404 with valid token, and restores token in `finally` VERIFY: `cd backend && python3 -m pytest tests/test_badge_wired.py::test_badge_requires_the_token_when_one_is_set -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-wire-the-badge-router-in-backend-app-mai]

# --- 27B-decomposed from roadmap [2026-11-17]: Document the badge - create `docs/BADGE.md` (title `# Status badge`) stating that `GET /mo (review + tweak) [feat:shrike-monitor-20261117-document-the-badge-create-docs-badge-md-] ---
- [ ] [T1] backend/app/utils/badge.py — Add `BADGE_COLORS` dictionary mapping status keys to hex color strings VERIFY: `cd backend && python3 -c "from app.utils.badge import BADGE_COLORS; assert len(BADGE_COLORS) > 0"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-document-the-badge-create-docs-badge-md-]
- [ ] [T2] docs/BADGE.md — Create file with title `# Status badge`, stating `GET /monitors/{monitor_id}/badge` requires API token, returns `image/svg+xml` with `Cache-Control: no-store`, and includes a table of every key in `BADGE_COLORS` with its hex value VERIFY: `grep -q "# Status badge" docs/BADGE.md && grep -q "GET /monitors/{monitor_id}/badge" docs/BADGE.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-document-the-badge-create-docs-badge-md-]
- [ ] [T3] backend/tests/test_badge_doc.py — Create test file with `test_badge_doc_names_the_route` asserting the route path appears in `../docs/BADGE.md` VERIFY: `cd backend && python3 -m pytest tests/test_badge_doc.py::test_badge_doc_names_the_route -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-document-the-badge-create-docs-badge-md-]
- [ ] [T4] backend/tests/test_badge_doc.py — Add `test_badge_doc_lists_every_status_colour` asserting each key and hex value from `BADGE_COLORS` appears in `../docs/BADGE.md` VERIFY: `cd backend && python3 -m pytest tests/test_badge_doc.py::test_badge_doc_lists_every_status_colour -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-document-the-badge-create-docs-badge-md-]
- [ ] [T5] docs/BADGE.md — Ensure the table in `docs/BADGE.md` matches the exact keys and hex values currently defined in `backend/app/utils/badge.py` VERIFY: `cd backend && python3 -m pytest tests/test_badge_doc.py -q`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-document-the-badge-create-docs-badge-md-]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the stable jitter fraction - create `backend/app/utils/jitter.py` with `jitter_fractio (review + tweak) [feat:shrike-monitor-20261117-add-the-stable-jitter-fraction-create-ba] ---
- [ ] [T1] backend/app/utils/jitter.py — Add `jitter_fraction(key: str) -> float` returning `int.from_bytes(hashlib.sha256(key.encode("utf-8")).digest()[:8], "big") / 2**64` VERIFY: `cd backend && python3 -c "from app.utils.jitter import jitter_fraction; assert isinstance(jitter_fraction('test'), float)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-stable-jitter-fraction-create-ba]
- [ ] [T1] backend/tests/test_jitter_fraction.py — Add `test_same_key_gives_the_same_fraction` asserting `jitter_fraction("abc") == jitter_fraction("abc")` VERIFY: `cd backend && python3 -m pytest tests/test_jitter_fraction.py::test_same_key_gives_the_same_fraction -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-stable-jitter-fraction-create-ba]
- [ ] [T1] backend/tests/test_jitter_fraction.py — Add `test_fraction_is_in_unit_interval` asserting `0.0 <= jitter_fraction(f"key_{i}") < 1.0` for `i` in `range(50)` VERIFY: `cd backend && python3 -m pytest tests/test_jitter_fraction.py::test_fraction_is_in_unit_interval -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-stable-jitter-fraction-create-ba]
- [ ] [T1] backend/tests/test_jitter_fraction.py — Add `test_different_keys_usually_differ` asserting `jitter_fraction("a") != jitter_fraction("b")` VERIFY: `cd backend && python3 -m pytest tests/test_jitter_fraction.py::test_different_keys_usually_differ -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-stable-jitter-fraction-create-ba]
- [ ] [T1] backend/tests/test_jitter_fraction.py — Add `test_known_value` asserting `jitter_fraction("") == int.from_bytes(hashlib.sha256(b"").digest()[:8], "big") / 2**64` VERIFY: `cd backend && python3 -m pytest tests/test_jitter_fraction.py::test_known_value -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-stable-jitter-fraction-create-ba]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the jitter offset - in `backend/app/utils/jitter.py` add `jitter_offset(key: str, inte (review + tweak) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti] ---
- [ ] [T1] backend/app/utils/jitter.py — Add `jitter_offset(key: str, interval_seconds: float, max_fraction: float = 0.1) -> float` returning `jitter_fraction(key) * interval_seconds * min(max_fraction, 1.0)` and `0.0` when `interval_seconds <= 0` or `max_fraction <= 0`. VERIFY: `cd backend && python3 -c "from app.utils.jitter import jitter_offset; assert jitter_offset('k', 10, 0.1) >= 0"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti]
- [ ] [T2] backend/tests/test_jitter_offset.py — Add `test_offset_is_below_the_allowed_fraction_of_the_interval` asserting `jitter_offset('key', 100.0, 0.1) < 10.0`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_offset.py::test_offset_is_below_the_allowed_fraction_of_the_interval -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti]
- [ ] [T2] backend/tests/test_jitter_offset.py — Add `test_non_positive_interval_gives_zero` asserting `jitter_offset('key', 0.0, 0.1) == 0.0` and `jitter_offset('key', -1.0, 0.1) == 0.0`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_offset.py::test_non_positive_interval_gives_zero -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti]
- [ ] [T2] backend/tests/test_jitter_offset.py — Add `test_non_positive_fraction_gives_zero` asserting `jitter_offset('key', 100.0, 0.0) == 0.0` and `jitter_offset('key', 100.0, -0.5) == 0.0`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_offset.py::test_non_positive_fraction_gives_zero -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti]
- [ ] [T2] backend/tests/test_jitter_offset.py — Add `test_fraction_above_one_is_capped_at_one` asserting `jitter_offset('key', 100.0, 5.0) <= 100.0`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_offset.py::test_fraction_above_one_is_capped_at_one -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti]
- [ ] [T2] backend/tests/test_jitter_offset.py — Add `test_offset_is_stable_for_a_key` asserting `jitter_offset('stable_key', 10.0, 0.1) == jitter_offset('stable_key', 10.0, 0.1)`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_offset.py::test_offset_is_stable_for_a_key -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-jitter-offset-in-backend-app-uti]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the even spread - in `backend/app/utils/jitter.py` add `spread_offsets(keys: list[str] (review + tweak) [feat:shrike-monitor-20261117-add-the-even-spread-in-backend-app-utils] ---
- [ ] [T1] backend/app/utils/jitter.py — Add `spread_offsets(keys: list[str], interval_seconds: float) -> dict[str, float]` that returns `{}` for empty keys or `interval_seconds <= 0`, otherwise sorts unique keys and maps each to `i * interval_seconds / n`. VERIFY: `cd backend && python3 -c "from app.utils.jitter import spread_offsets; assert spread_offsets(['b','a'], 10.0) == {'a': 0.0, 'b': 5.0}"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-even-spread-in-backend-app-utils]
- [ ] [T2] backend/tests/test_jitter_spread.py — Add `test_offsets_are_evenly_spaced_in_sorted_key_order` asserting that for keys `['z', 'a', 'm']` and interval `30.0`, the result is `{'a': 0.0, 'm': 10.0, 'z': 20.0}`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_spread.py::test_offsets_are_evenly_spaced_in_sorted_key_order -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-even-spread-in-backend-app-utils]
- [ ] [T2] backend/tests/test_jitter_spread.py — Add `test_duplicate_keys_count_once` asserting that for keys `['a', 'a', 'b']` and interval `10.0`, the result is `{'a': 0.0, 'b': 5.0}`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_spread.py::test_duplicate_keys_count_once -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-even-spread-in-backend-app-utils]
- [ ] [T2] backend/tests/test_jitter_spread.py — Add `test_empty_keys_give_empty_dict` asserting that `spread_offsets([], 10.0)` returns `{}`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_spread.py::test_empty_keys_give_empty_dict -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-even-spread-in-backend-app-utils]
- [ ] [T2] backend/tests/test_jitter_spread.py — Add `test_non_positive_interval_gives_empty_dict` asserting that `spread_offsets(['a'], 0.0)` and `spread_offsets(['a'], -1.0)` both return `{}`. VERIFY: `cd backend && python3 -m pytest tests/test_jitter_spread.py::test_non_positive_interval_gives_empty_dict -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-even-spread-in-backend-app-utils]

# --- 27B-decomposed from roadmap [2026-11-17]: Document the jitter helpers - create `docs/SCHEDULING.md` (title `# Probe scheduling`) wit (review + tweak) [feat:shrike-monitor-20261117-document-the-jitter-helpers-create-docs-] ---
- [ ] [T1] backend/app/config.py — Add `scheduler_tick_seconds: int = 30` to the `Settings` class VERIFY: `cd backend && python3 -c "from app.config import Settings; assert Settings().scheduler_tick_seconds == 30"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-document-the-jitter-helpers-create-docs-]
- [ ] [T2] docs/SCHEDULING.md — Create file with title `# Probe scheduling`, section `Jitter helpers` listing `jitter_fraction`, `jitter_offset`, `spread_offsets` as unused, and section naming `SCHEDULER_TICK_SECONDS` VERIFY: `grep -q "SCHEDULER_TICK_SECONDS" docs/SCHEDULING.md && grep -q "jitter_fraction" docs/SCHEDULING.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-document-the-jitter-helpers-create-docs-]
- [ ] [T3] backend/tests/test_scheduling_doc.py — Create test file with `test_scheduling_doc_names_every_jitter_helper` that reads `../docs/SCHEDULING.md` and asserts presence of `jitter_fraction`, `jitter_offset`, `spread_offsets`, and `SCHEDULER_TICK_SECONDS` VERIFY: `cd backend && python3 -m pytest tests/test_scheduling_doc.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-document-the-jitter-helpers-create-docs-]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the configuration reference - create `docs/CONFIGURATION.md` (title `# Configuration`) (review + tweak) [feat:shrike-monitor-20261117-add-the-configuration-reference-create-d] ---
- [ ] [T1] backend/app/config.py — Add a `validation_alias` to the `api_token` field in `Settings` if missing, or ensure all fields with aliases are correctly marked for documentation generation. VERIFY: `cd backend && python3 -c "from app.config import Settings; print([f.name for f in Settings.model_fields.values() if f.validation_alias])"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-configuration-reference-create-d]
- [ ] [T2] docs/CONFIGURATION.md — Create the file with title `# Configuration` and a markdown table header `| Variable | Default | Description |`. VERIFY: `test -f docs/CONFIGURATION.md && grep -q "# Configuration" docs/CONFIGURATION.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-add-the-configuration-reference-create-d]
- [ ] [T3] docs/CONFIGURATION.md — Populate the table with one row per field in `Settings.model_fields`, using `validation_alias` if present else `name.upper()` for the variable column, and the field default for the default column. VERIFY: `cd backend && python3 -c "from app.config import Settings; import re; doc=open('../docs/CONFIGURATION.md').read(); [assert f.validation_alias or f.name.upper() in doc for f in Settings.model_fields.values()]"`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-add-the-configuration-reference-create-d]
- [ ] [T4] backend/tests/test_configuration_doc.py — Create the test file with `test_configuration_doc_lists_every_setting` that reads `../docs/CONFIGURATION.md` and asserts every backticked variable name from `Settings.model_fields` is present. VERIFY: `cd backend && python3 -m pytest tests/test_configuration_doc.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-configuration-reference-create-d]
- [ ] [T5] docs/CONFIGURATION.md — Ensure the description column for each row contains exactly one plain sentence explaining the field's purpose. VERIFY: `cd backend && python3 -c "import re; lines=open('../docs/CONFIGURATION.md').readlines(); rows=[l for l in lines if l.startswith('|') and 'Variable' not in l]; [assert len(re.findall(r'[.!?]', r.split('|')[2]))==1 for r in rows]"`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-add-the-configuration-reference-create-d]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the notifier reference - create `docs/NOTIFIER.md` (title `# Notifier`) listing every  (review + tweak) [feat:shrike-monitor-20261117-add-the-notifier-reference-create-docs-n] ---
- [ ] [T1] backend/app/services/notifier.py — Add a `__docstring__` or inline comment block above `__init__` and `notify_transition` that explicitly lists all parameter names and their types to ensure `inspect.signature` alignment for documentation generation. VERIFY: `cd backend && python3 -c "import inspect; from app.services.notifier import Notifier; sig = inspect.signature(Notifier.__init__); print([p for p in sig.parameters if p != 'self'])"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-notifier-reference-create-docs-n]
- [ ] [T2] docs/NOTIFIER.md — Create the file with title `# Notifier` and a section listing every parameter of `Notifier.__init__` (excluding `self`) with one plain sentence each. VERIFY: `test -f docs/NOTIFIER.md && grep -q "# Notifier" docs/NOTIFIER.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-add-the-notifier-reference-create-docs-n]
- [ ] [T5] backend/tests/test_notifier_doc.py — Create the test file with `test_notifier_doc_lists_every_init_parameter` that reads `../docs/NOTIFIER.md` and asserts every parameter name from `inspect.signature(Notifier.__init__)` (skipping `self`) is present in the text. VERIFY: `cd backend && python3 -m pytest tests/test_notifier_doc.py::test_notifier_doc_lists_every_init_parameter -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-notifier-reference-create-docs-n]
- [ ] [T3] docs/NOTIFIER.md — Append a section to the existing file listing every argument of `notify_transition` with one plain sentence each. VERIFY: `grep -q "notify_transition" docs/NOTIFIER.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-add-the-notifier-reference-create-docs-n]
- [ ] [T4] docs/NOTIFIER.md — Append a short section titled `## Duplicate Guard` explaining the `dedup_ttl` parameter and its behavior in preventing duplicate notifications. VERIFY: `grep -q "Duplicate Guard" docs/NOTIFIER.md && grep -q "dedup_ttl" docs/NOTIFIER.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-add-the-notifier-reference-create-docs-n]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the masked settings view helper - create `backend/app/utils/settings_view.py` with `de (review + tweak) [feat:shrike-monitor-20261117-add-the-masked-settings-view-helper-crea] ---
- [ ] [T1] backend/app/utils/settings_view.py — Add `describe_settings` function that iterates `type(settings).model_fields` sorted by key, masking values for fields with "token" in name to "***" if non-empty string or "" if empty, and returning other values as-is. VERIFY: `cd backend && python3 -c "from app.utils.settings_view import describe_settings; from app.config import Settings; s = Settings(max_results=7); d = describe_settings(s); assert any(x['name']=='max_results' and x['value']==7 for x in d)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-masked-settings-view-helper-crea]
- [ ] [T2] backend/tests/test_settings_view.py — Add `test_names_are_sorted` verifying that the list of names from `describe_settings(Settings())` is equal to its sorted version. VERIFY: `cd backend && python3 -m pytest tests/test_settings_view.py::test_names_are_sorted -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-masked-settings-view-helper-crea]
- [ ] [T3] backend/tests/test_settings_view.py — Add `test_token_values_are_masked_when_set` verifying that `describe_settings(Settings(monitor_api_token='s3cret', notify_token='n'))` returns "***" for both token fields. VERIFY: `cd backend && python3 -m pytest tests/test_settings_view.py::test_token_values_are_masked_when_set -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-masked-settings-view-helper-crea]
- [ ] [T4] backend/tests/test_settings_view.py — Add `test_empty_token_stays_empty` verifying that `describe_settings(Settings(monitor_api_token='', notify_token=''))` returns "" for both token fields. VERIFY: `cd backend && python3 -m pytest tests/test_settings_view.py::test_empty_token_stays_empty -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-masked-settings-view-helper-crea]
- [ ] [T5] backend/tests/test_settings_view.py — Add `test_plain_values_are_unchanged` verifying that `describe_settings(Settings(max_results=7))` returns 7 for `max_results` and that non-token fields retain their original values. VERIFY: `cd backend && python3 -m pytest tests/test_settings_view.py::test_plain_values_are_unchanged -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-masked-settings-view-helper-crea]

# --- 27B-decomposed from roadmap [2026-11-17]: Pin the README environment table to the settings - in `README.md` add a table row to the e (review + tweak) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-] ---
- [ ] [T3] README.md — Add a row to the existing environment variables table for `AEGIS_API_TOKEN` with a plain one-sentence description matching the column shape of the `ALERT_THRESHOLD` row. VERIFY: `grep -q "AEGIS_API_TOKEN" README.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]
- [ ] [T3] README.md — Add a row to the existing environment variables table for `AEGIS_ALLOW_PRIVATE_URLS` with a plain one-sentence description matching the column shape of the `ALERT_THRESHOLD` row. VERIFY: `grep -q "AEGIS_ALLOW_PRIVATE_URLS" README.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]
- [ ] [T3] README.md — Add a row to the existing environment variables table for `AEGIS_NOTIFY_DEDUP_TTL` with a plain one-sentence description matching the column shape of the `ALERT_THRESHOLD` row. VERIFY: `grep -q "AEGIS_NOTIFY_DEDUP_TTL" README.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]
- [ ] [T3] README.md — Add a row to the existing environment variables table for `AEGIS_REQUIRE_TOKEN` with a plain one-sentence description matching the column shape of the `ALERT_THRESHOLD` row. VERIFY: `grep -q "AEGIS_REQUIRE_TOKEN" README.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]
- [ ] [T3] README.md — Add a row to the existing environment variables table for `AEGIS_TICK_INTERVAL` with a plain one-sentence description matching the column shape of the `ALERT_THRESHOLD` row. VERIFY: `grep -q "AEGIS_TICK_INTERVAL" README.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]
- [ ] [T4] README.md — Add rows to the existing environment variables table for any remaining `Settings` variables not yet listed (e.g., `AEGIS_LOG_LEVEL`, `AEGIS_DB_PATH`) with plain one-sentence descriptions matching the column shape of the `ALERT_THRESHOLD` row. VERIFY: `cd backend && python3 -m pytest tests/test_readme_env_table.py -q`. (cat:docs; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]
- [ ] [T1] backend/tests/test_readme_env_table.py — Create the test file with a helper function `extract_setting_aliases()` that imports `Settings` from `backend.app.config`, iterates `Settings.model_fields`, and returns a set of expected environment variable names (using `validation_alias` if it is a string, otherwise `name.upper()`). VERIFY: `cd backend && python3 -m pytest tests/test_readme_env_table.py::test_helper_extracts_aliases -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]
- [ ] [T2] backend/tests/test_readme_env_table.py — Add the test function `test_readme_lists_every_setting_variable` that reads `../README.md` relative to the test file, extracts all backticked strings from the environment table section, and asserts that every name from `extract_setting_aliases()` is present in the extracted set. VERIFY: `cd backend && python3 -m pytest tests/test_readme_env_table.py::test_readme_lists_every_setting_variable -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-pin-the-readme-environment-table-to-the-]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the window uptime helper - create `backend/app/utils/uptime_window.py` with `uptime_pe (review + tweak) [feat:shrike-monitor-20261117-add-the-window-uptime-helper-create-back] ---
- [ ] [T2] backend/app/utils/uptime_window.py — Implement `uptime_percent(results, now, window_seconds)` returning `None` if `window_seconds <= 0` or no results in `[now - window_seconds, now]`, else `round(ok_count / total * 100, 3)`. VERIFY: `cd backend && python3 -c "from app.utils.uptime_window import uptime_percent; assert uptime_percent([], 100.0, 60.0) is None"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-window-uptime-helper-create-back]
- [ ] [T1] backend/app/utils/uptime_window.py — Add module docstring and import `CheckResult` from `app.models`. VERIFY: `cd backend && python3 -c "from app.utils.uptime_window import uptime_percent; print('ok')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-window-uptime-helper-create-back]
- [ ] [T3] backend/tests/test_uptime_window_percent.py — Create test file with `test_all_ok_is_one_hundred` verifying 100.0 return for all successful checks in window. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_window_percent.py::test_all_ok_is_one_hundred -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-window-uptime-helper-create-back]
- [ ] [T4] backend/tests/test_uptime_window_percent.py — Add `test_half_failed_is_fifty` verifying 50.0 return for mixed success/failure checks in window. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_window_percent.py::test_half_failed_is_fifty -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-window-uptime-helper-create-back]
- [ ] [T5] backend/tests/test_uptime_window_percent.py — Add `test_results_outside_the_window_are_ignored` verifying checks before `now - window_seconds` are excluded from calculation. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_window_percent.py::test_results_outside_the_window_are_ignored -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-window-uptime-helper-create-back]

# --- 27B-decomposed from roadmap [2026-11-17]: Add the three window summary - in `backend/app/utils/uptime_window.py` add `UPTIME_WINDOWS (review + tweak) [feat:shrike-monitor-20261117-add-the-three-window-summary-in-backend-] ---
- [ ] [T1] backend/app/utils/uptime_window.py — Add `UPTIME_WINDOWS: dict[str, int] = {"1h": 3600, "24h": 86400, "7d": 604800}` and import `CheckResult` from `backend.app.models` VERIFY: `cd backend && python3 -c "from app.utils.uptime_window import UPTIME_WINDOWS; assert list(UPTIME_WINDOWS.keys()) == ['1h', '24h', '7d']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-three-window-summary-in-backend-]
- [ ] [T1] backend/app/utils/uptime_window.py — Add `uptime_windows(results: list[CheckResult], now: float) -> dict[str, float | None]` that iterates `UPTIME_WINDOWS` in order and returns `{label: uptime_percent(results, now, seconds)}` VERIFY: `cd backend && python3 -c "from app.utils.uptime_window import uptime_windows; assert isinstance(uptime_windows([], 0.0), dict)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261117-add-the-three-window-summary-in-backend-]
- [ ] [T2] backend/tests/test_uptime_windows.py — Create test file with `test_keys_are_the_three_labels_in_order` asserting `list(uptime_windows([], 0.0).keys()) == ["1h", "24h", "7d"]` VERIFY: `cd backend && python3 -m pytest tests/test_uptime_windows.py::test_keys_are_the_three_labels_in_order -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-three-window-summary-in-backend-]
- [ ] [T2] backend/tests/test_uptime_windows.py — Add `test_recent_failure_lowers_only_the_short_window` with a failure at `now - 1800` and success at `now - 10800`, asserting `result["1h"] == 0.0` and `result["24h"] < 100.0` VERIFY: `cd backend && python3 -m pytest tests/test_uptime_windows.py::test_recent_failure_lowers_only_the_short_window -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-three-window-summary-in-backend-]
- [ ] [T2] backend/tests/test_uptime_windows.py — Add `test_empty_results_give_none_for_every_window` asserting all values in `uptime_windows([], 0.0).values()` are `None` VERIFY: `cd backend && python3 -m pytest tests/test_uptime_windows.py::test_empty_results_give_none_for_every_window -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261117-add-the-three-window-summary-in-backend-]

# --- 27B-decomposed from roadmap [2026-11-18]: Add the uptime router - create `backend/app/routers/uptime.py` with `router = APIRouter(pr (review + tweak) [feat:shrike-monitor-20261118-add-the-uptime-router-create-backend-app] ---
- [ ] [T1] backend/app/utils/uptime.py — Add `uptime_windows(results: list, now: float) -> dict` that computes percentage uptime for '1h', '24h', and '7d' windows based on `CheckResult.ok` and `checked_at`. VERIFY: `cd backend && python3 -c "from app.utils.uptime import uptime_windows; print(uptime_windows([], time.time()))"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-add-the-uptime-router-create-backend-app]
- [ ] [T3] backend/app/routers/uptime.py — Create router with `APIRouter(prefix="/monitors", tags=["monitors"], dependencies=[Depends(require_api_token)])` and `GET /{monitor_id}/uptime` endpoint returning 404 if monitor not found, else uptime dict. VERIFY: `cd backend && python3 -c "from app.routers.uptime import router; print(router.prefix)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-add-the-uptime-router-create-backend-app]
- [ ] [T4] backend/app/routers/__init__.py — Import and include `uptime.router` in the main router aggregation. VERIFY: `cd backend && python3 -c "from app.routers import api_router; print(any(hasattr(r, 'path') and '/uptime' in r.path for r in api_router.routes))"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-add-the-uptime-router-create-backend-app]
- [ ] [T2] backend/tests/test_uptime_windows.py — Add unit tests for `uptime_windows` verifying correct percentage calculation for mixed ok/fail results and empty lists. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_windows.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-add-the-uptime-router-create-backend-app]
- [ ] [T5] backend/tests/test_uptime_router.py — Create integration test mounting uptime router on fresh FastAPI app, creating probe monitor, recording ok/fail CheckResults, asserting 200 with `uptime['1h'] == 50.0`, 404 for unknown id, and calling `store.clear()`. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_router.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-add-the-uptime-router-create-backend-app]

# --- 27B-decomposed from roadmap [2026-11-18]: Wire the uptime router - in `backend/app/main.py` add `uptime` to the existing `from app.r (review + tweak) [feat:shrike-monitor-20261118-wire-the-uptime-router-in-backend-app-ma] ---
- [ ] [T3] backend/app/main.py — Add `uptime` to the `from app.routers import ...` line and insert `app.include_router(uptime.router)` immediately after `app.include_router(monitors.router)`. VERIFY: `cd backend && python3 -c "from app.main import app; assert '/monitors/{monitor_id}/uptime' in app.openapi()['paths']"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-wire-the-uptime-router-in-backend-app-ma]
- [ ] [T1] backend/tests/test_uptime_wired.py — Create file with `test_uptime_route_registered` asserting `/monitors/{monitor_id}/uptime` exists in `app.openapi()['paths']`. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_wired.py::test_uptime_route_registered -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-wire-the-uptime-router-in-backend-app-ma]
- [ ] [T1] backend/tests/test_uptime_wired.py — Add `test_uptime_unknown_monitor_is_404` that sets `app.main.settings.monitor_api_token = None`, calls `TestClient(app).get('/monitors/does-not-exist/uptime')`, asserts status 404, and restores token in `finally`. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_wired.py::test_uptime_unknown_monitor_is_404 -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-wire-the-uptime-router-in-backend-app-ma]

# --- 27B-decomposed from roadmap [2026-11-18]: Document the uptime windows - create `docs/UPTIME.md` (title `# Uptime by window`) listing (review + tweak) [feat:shrike-monitor-20261118-document-the-uptime-windows-create-docs-] ---
- [ ] [T1] backend/app/utils/uptime_window.py — Add `UPTIME_WINDOWS` dictionary mapping window names to their lengths in seconds. VERIFY: `cd backend && python3 -c "from app.utils.uptime_window import UPTIME_WINDOWS; assert isinstance(UPTIME_WINDOWS, dict) and all(isinstance(v, int) for v in UPTIME_WINDOWS.values())"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-document-the-uptime-windows-create-docs-]
- [ ] [T1] docs/UPTIME.md — Create file with title `# Uptime by window`, listing every key from `UPTIME_WINDOWS` with its length in seconds, stating that a window with no checks is `null`, and naming `GET /monitors/{monitor_id}/uptime` as read-only behind the API token. VERIFY: `grep -q "# Uptime by window" docs/UPTIME.md && grep -q "GET /monitors/{monitor_id}/uptime" docs/UPTIME.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261118-document-the-uptime-windows-create-docs-]
- [ ] [T1] backend/tests/test_uptime_doc.py — Create test file with `test_uptime_doc_lists_every_window` that reads `../docs/UPTIME.md` relative to the test file and asserts every key and its seconds value from `UPTIME_WINDOWS` appear in the doc. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_doc.py::test_uptime_doc_lists_every_window -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-document-the-uptime-windows-create-docs-]
- [ ] [T1] backend/tests/test_uptime_doc.py — Add `test_uptime_doc_names_the_route` that reads `../docs/UPTIME.md` and asserts the string `GET /monitors/{monitor_id}/uptime` is present. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_doc.py::test_uptime_doc_names_the_route -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-document-the-uptime-windows-create-docs-]
- [ ] [T2] backend/tests/test_uptime_doc.py — Ensure both tests pass together by running the full file. VERIFY: `cd backend && python3 -m pytest tests/test_uptime_doc.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-document-the-uptime-windows-create-docs-]

# --- 27B-decomposed from roadmap [2026-11-18]: Add the cell guard and row builder - create `backend/app/utils/result_csv.py` with `safe_c (review + tweak) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat] ---
- [ ] [T1] backend/app/utils/result_csv.py — Add `safe_cell` function that returns empty string for None and prefixes strings starting with `=`, `+`, `-`, or `@` with a single quote to prevent spreadsheet evaluation. VERIFY: `cd backend && python3 -c "from app.utils.result_csv import safe_cell; assert safe_cell(None) == ''; assert safe_cell('=1+1') == \"'=1+1\"; assert safe_cell('+1') == \"'+1\"; assert safe_cell('-1') == \"'-1\"; assert safe_cell('@x') == \"'@x\"; assert safe_cell('hello') == 'hello'"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat]
- [ ] [T1] backend/app/utils/result_csv.py — Add `RESULT_COLUMNS` tuple constant with values `("checked_at", "ok", "status_code", "latency_ms", "error")`. VERIFY: `cd backend && python3 -c "from app.utils.result_csv import RESULT_COLUMNS; assert RESULT_COLUMNS == ('checked_at', 'ok', 'status_code', 'latency_ms', 'error')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat]
- [ ] [T1] backend/app/utils/result_csv.py — Add `result_rows` function that takes a list of `CheckResult` objects and returns a list of lists where each inner list contains string representations of the result fields in the order defined by `RESULT_COLUMNS`, converting boolean `ok` to `'true'` or `'false'` and passing all values through `safe_cell`. VERIFY: `cd backend && python3 -c "from app.utils.result_csv import result_rows, RESULT_COLUMNS; from unittest.mock import Mock; r = Mock(); r.checked_at='t'; r.ok=True; r.status_code=200; r.latency_ms=10; r.error=None; rows = result_rows([r]); assert len(rows) == 1; assert rows[0][0] == 't'; assert rows[0][1] == 'true'; assert rows[0][2] == '200'; assert rows[0][3] == '10'; assert rows[0][4] == ''"`. (cat:python; multifile:no) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat]
- [ ] [T2] backend/tests/test_result_csv_rows.py — Create test file with `test_formula_prefixes_are_neutralised` verifying that inputs `=1+1`, `+1`, `-1`, and `@x` are returned by `safe_cell` with a leading single quote. VERIFY: `cd backend && python3 -m pytest tests/test_result_csv_rows.py::test_formula_prefixes_are_neutralised -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat]
- [ ] [T2] backend/tests/test_result_csv_rows.py — Add `test_plain_text_and_none` verifying that `safe_cell(None)` returns empty string and `safe_cell('plain')` returns `'plain'` unchanged. VERIFY: `cd backend && python3 -m pytest tests/test_result_csv_rows.py::test_plain_text_and_none -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat]
- [ ] [T2] backend/tests/test_result_csv_rows.py — Add `test_columns_are_in_the_documented_order` verifying that `RESULT_COLUMNS` matches the expected tuple `("checked_at", "ok", "status_code", "latency_ms", "error")`. VERIFY: `cd backend && python3 -m pytest tests/test_result_csv_rows.py::test_columns_are_in_the_documented_order -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat]
- [ ] [T2] backend/tests/test_result_csv_rows.py — Add `test_rows_follow_the_column_order` verifying that `result_rows` produces output where each row's elements correspond to the fields in `RESULT_COLUMNS` order, specifically checking that boolean `ok` is converted to `'true'`/`'false'` and other fields are stringified correctly. VERIFY: `cd backend && python3 -m pytest tests/test_result_csv_rows.py::test_rows_follow_the_column_order -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261118-add-the-cell-guard-and-row-builder-creat]
