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
- [ ] [T2] backend/app/routers/monitors.py — Modify `_build_monitor_status_item()` to populate `checks` using `len(results)`, `uptime_percent` using `round(uptime_ratio(results) * 100, 1)` (or None if no results), and `latency_p95_ms` using `latency_stats(results)["p95"]` for HTTP monitors. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitors_api.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-the-status-console-issues-one-request-pe]
- [ ] [T3] backend/app/static/console.html — Rewrite the `refresh()` function to call only `api("/monitors/status")` and iterate over `fleet.monitors` to build table rows, removing all per-monitor `/monitors/{id}/status` calls and the `/monitors?limit=1000` call. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console.py`. (cat:typescript; multifile:no) [feat:shrike-monitor-20261106-the-status-console-issues-one-request-pe]
- [ ] [T4] backend/tests/test_console.py — Update the existing assertion that checks for `"/monitors?limit="` to instead assert that `"fleet.monitors"` is present in the console HTML content. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-status-console-issues-one-request-pe]
- [ ] [T5] backend/tests/test_console_single_fetch.py — Create a new test file that verifies `GET /monitors/status` returns items with `checks`, `uptime_percent`, and `latency_p95_ms` populated correctly for an HTTP monitor with mixed results, and asserts the console HTML contains `fleet.monitors`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_single_fetch.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-status-console-issues-one-request-pe]

# --- 27B-decomposed from roadmap [2026-11-06]: The console is not announced to assistive tech and has no landmarks — backend/app/static/c (review + tweak) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv] ---
- [ ] [T1] backend/tests/test_console_a11y.py — Add test asserting `role="alert"` exists in HTML VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_role_alert` (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T2] backend/tests/test_console_a11y.py — Add test asserting `aria-live="polite"` exists in HTML VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_aria_live` (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T3] backend/tests/test_console_a11y.py — Add test asserting `<main` landmark exists in HTML VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_main_landmark` (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T4] backend/tests/test_console_a11y.py — Add test asserting `<caption` exists in HTML VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_caption` (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T5] backend/tests/test_console_a11y.py — Add test asserting exactly 6 occurrences of `scope="col"` in HTML VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_scope_col_count` (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T3] backend/app/static/console.html — Add `role="alert"` to `#err` element VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_role_alert` (cat:web; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T3] backend/app/static/console.html — Add `aria-live="polite"` to `#upd` and `#summary` elements VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_aria_live` (cat:web; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T3] backend/app/static/console.html — Wrap content after `<h1>` in `<main>` landmark VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_main_landmark` (cat:web; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T3] backend/app/static/console.html — Add `<caption class="muted">Monitor status, refreshed every 15 seconds</caption>` as first child of table VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_caption` (cat:web; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]
- [ ] [T3] backend/app/static/console.html — Add `scope="col"` to all 6 `<th>` cells VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_a11y.py::test_scope_col_count` (cat:web; multifile:no) [feat:shrike-monitor-20261106-the-console-is-not-announced-to-assistiv]

# --- 27B-decomposed from roadmap [2026-11-06]: `GET /console` is served without any security headers — `console()` in backend/app/main.py (review + tweak) [feat:shrike-monitor-20261106-get-console-is-served-without-any-securi] ---
- [ ] [T1] backend/tests/test_console_headers.py — Add `test_console_security_headers_present` asserting `GET /console` returns `X-Frame-Options: DENY`, `X-Content-Type-Options: nosniff`, and `Referrer-Policy: no-referrer`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_headers.py::test_console_security_headers_present`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-get-console-is-served-without-any-securi]
- [ ] [T1] backend/tests/test_console_headers.py — Add `test_console_csp_header_values` asserting `GET /console` returns `Content-Security-Policy` containing `default-src 'none'`, `script-src 'unsafe-inline'`, `style-src 'unsafe-inline'`, `connect-src 'self'`, `base-uri 'none'`, `form-action 'none'`, and `frame-ancestors 'none'`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_headers.py::test_console_csp_header_values`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-get-console-is-served-without-any-securi]
- [ ] [T1] backend/tests/test_console_headers.py — Add `test_health_endpoint_no_csp` asserting `GET /health` does NOT contain a `Content-Security-Policy` header. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_headers.py::test_health_endpoint_no_csp`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-get-console-is-served-without-any-securi]
- [ ] [T3] backend/app/main.py — Modify `console()` to pass `headers={"Content-Security-Policy": "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'", "X-Frame-Options": "DENY", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer"}` to the `HTMLResponse` constructor. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_console_headers.py tests/test_console.py`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-get-console-is-served-without-any-securi]

# --- 27B-decomposed from roadmap [2026-11-06]: The Docker build context has no `.dockerignore`, so `COPY . .` bakes `.venv`, `.env`, `mon (review + tweak) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig] ---
- [ ] [T1] backend/.dockerignore — Add `.venv/` as the first line to exclude virtual environments from the Docker build context. VERIFY: `cd backend && grep -q "^\.venv/$" .dockerignore`. (cat:infra; multifile:no) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig]
- [ ] [T1] backend/.dockerignore — Add `.env`, `.env.*`, and `*.db` lines to exclude environment files and database artifacts. VERIFY: `cd backend && grep -q "^\.env$" .dockerignore && grep -q "^\.env\.\*$" .dockerignore && grep -q "^\*\.db$" .dockerignore`. (cat:infra; multifile:no) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig]
- [ ] [T1] backend/.dockerignore — Add `__pycache__/`, `*.pyc`, `.pytest_cache/`, and `.coverage` lines to exclude Python cache and test artifacts. VERIFY: `cd backend && grep -q "^__pycache__/$" .dockerignore && grep -q "^\*\.pyc$" .dockerignore && grep -q "^\.pytest_cache/$" .dockerignore && grep -q "^\.coverage$" .dockerignore`. (cat:infra; multifile:no) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig]
- [ ] [T1] backend/.dockerignore — Add `tests/` line to exclude the test directory from the production image. VERIFY: `cd backend && grep -q "^tests/$" .dockerignore`. (cat:infra; multifile:no) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig]
- [ ] [T2] backend/tests/test_dockerignore.py — Create a test that asserts `backend/.dockerignore` exists and contains the required exclusion lines (`.venv/`, `.env`, `*.db`, `__pycache__/`) as exact stripped lines. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_dockerignore.py::test_dockerignore_exists_and_contains_exclusions`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig]
- [ ] [T2] backend/tests/test_dockerignore.py — Add a test that asserts `backend/.dockerignore` does NOT contain lines equal to `requirements.txt`, `app/`, or `start.sh` to ensure essential files are not excluded. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_dockerignore.py::test_dockerignore_does_not_exclude_essential_files`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-docker-build-context-has-no-dockerig]

# --- 27B-decomposed from roadmap [2026-11-06]: CHANGELOG.md `[Unreleased]` documents helpers that do not exist and omits everything actua (review + tweak) [feat:shrike-monitor-20261106-changelog-md-unreleased-documents-helper] ---
- [ ] [T1] backend/tests/test_changelog_accuracy.py — Add test asserting the `[Unreleased]` section of `CHANGELOG.md` does not contain strings `clamp`, `ema`, `pct_change`, `round_sig`, `uptime_pct`, `next_state`, or `classify_status`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_changelog_accuracy.py::test_unreleased_no_ghost_helpers`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-changelog-md-unreleased-documents-helper]
- [ ] [T1] backend/tests/test_changelog_accuracy.py — Add test asserting the `[Unreleased]` section of `CHANGELOG.md` contains strings `PATCH /monitors/{id}`, `regenerate-ping-token`, `/monitors/status`, `X-Ping-Token`, `MONITOR_PERSIST`, and `/console`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_changelog_accuracy.py::test_unreleased_shipped_features`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-changelog-md-unreleased-documents-helper]
- [ ] [T2] CHANGELOG.md — Replace the inaccurate `[Unreleased]` section content with accurate `### Added` entries for `PATCH /monitors/{id}`, `POST /monitors/{id}/regenerate-ping-token`, `GET /monitors/status`, windowed status fields, per-monitor probe options, `X-Ping-Token` header, `MONITOR_API_TOKEN` auth, `MONITOR_PERSIST`, and `/console`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_changelog_accuracy.py::test_unreleased_shipped_features`. (cat:docs; multifile:no) [feat:shrike-monitor-20261106-changelog-md-unreleased-documents-helper]
- [ ] [T2] CHANGELOG.md — Add a `### Removed` entry in the `[Unreleased]` section noting the deletion of unused helper modules (`app/utils/clamp.py`, `app/utils/ema.py`, etc.) and functions. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_changelog_accuracy.py::test_unreleased_removed_section`. (cat:docs; multifile:no) [feat:shrike-monitor-20261106-changelog-md-unreleased-documents-helper]

# --- 27B-decomposed from roadmap [2026-11-06]: README's API table omits four live endpoints and nothing guards it against drift — README. (review + tweak) [feat:shrike-monitor-20261106-readme-s-api-table-omits-four-live-endpo] ---
- [ ] [T1] backend/tests/test_readme_routes.py — Create new test file with a fixture that loads README.md content and a helper to extract route lines from `app.routes` excluding HEAD/OPTIONS and doc paths. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_routes.py::test_fixture_loads_readme`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-readme-s-api-table-omits-four-live-endpo]
- [ ] [T2] backend/tests/test_readme_routes.py — Add test `test_all_live_endpoints_documented` that iterates over valid routes, normalizes `{monitor_id}` to `{id}`, and asserts each method+path pair appears in the README text. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_routes.py::test_all_live_endpoints_documented`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-readme-s-api-table-omits-four-live-endpo]
- [ ] [T3] backend/tests/test_readme_routes.py — Add test `test_query_params_documented` that asserts the README text contains the strings `since`, `sla_target`, and `offset`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_routes.py::test_query_params_documented`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-readme-s-api-table-omits-four-live-endpo]
- [ ] [T4] README.md — Add table rows for `PATCH /monitors/{id}`, `POST /monitors/{id}/regenerate-ping-token`, `GET /monitors/status`, and `GET /console` with their respective methods and one-line purposes. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_routes.py::test_all_live_endpoints_documented`. (cat:docs; multifile:no) [feat:shrike-monitor-20261106-readme-s-api-table-omits-four-live-endpo]
- [ ] [T5] README.md — Add a sentence below the API table documenting the `since` query parameter for `/results`, and the `type`, `status`, `name`, `limit`, `offset` filters for `GET /monitors`, and `sla_target` for `/status`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_readme_routes.py::test_query_params_documented`. (cat:docs; multifile:no) [feat:shrike-monitor-20261106-readme-s-api-table-omits-four-live-endpo]

# --- 27B-decomposed from roadmap [2026-11-06]: A NOTIFY_URL without a scheme silently disables alerting while logging only retry warnings (review + tweak) [feat:shrike-monitor-20261106-a-notify-url-without-a-scheme-silently-d] ---
- [ ] [T1] backend/app/main.py — Add `verify_notify_config(settings: Settings) -> None` function that raises `RuntimeError` if `settings.notify_url.strip()` is non-empty and does not start with `http://` or `https://`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_main_notify_config.py::test_verify_notify_config_valid_urls` (cat:python; multifile:no) [feat:shrike-monitor-20261106-a-notify-url-without-a-scheme-silently-d]
- [ ] [T2] backend/tests/test_main_notify_config.py — Create test file with cases for valid URLs (`https://notify.example.com`, `http://localhost:8001`, `""`) and invalid URLs (`shrike-notify:8001`, `localhost:8001`, `ftp://x`) asserting `RuntimeError` is raised for invalid ones. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_main_notify_config.py` (cat:test; multifile:no) [feat:shrike-monitor-20261106-a-notify-url-without-a-scheme-silently-d]
- [ ] [T3] backend/app/main.py — Call `verify_notify_config(settings)` immediately after `verify_api_token_config(settings)` in the startup/lifespan logic. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_main_notify_config.py tests/test_main_config_verification.py` (cat:python; multifile:no) [feat:shrike-monitor-20261106-a-notify-url-without-a-scheme-silently-d]

# --- 27B-decomposed from roadmap [2026-11-06]: OpenAPI under-documents the ping and token-regeneration endpoints — `ping()` in backend/ap (review + tweak) [feat:shrike-monitor-20261106-openapi-under-documents-the-ping-and-tok] ---
- [ ] [T1] backend/app/schemas.py — Add `class PingTokenResponse(BaseModel): ping_token: str` to the module VERIFY: `cd backend && .venv/bin/python -c "from backend.app.schemas import PingTokenResponse; assert hasattr(PingTokenResponse, 'ping_token')"` (cat:schema; multifile:no) [feat:shrike-monitor-20261106-openapi-under-documents-the-ping-and-tok]
- [ ] [T2] backend/app/routers/heartbeat.py — Add `401: {"description": "Missing or invalid ping token"}` to the `responses` dictionary of the `ping()` endpoint VERIFY: `cd backend && .venv/bin/python -c "from backend.app.main import app; spec = app.openapi(); assert '401' in spec['paths']['/heartbeat/{monitor_id}']['post']['responses']"` (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-openapi-under-documents-the-ping-and-tok]
- [ ] [T3] backend/app/routers/monitors.py — Import `PingTokenResponse` from `backend.app.schemas` and update the `regenerate_ping_token()` route decorator to include `response_model=PingTokenResponse` and `responses={404: {"description": "Monitor not found"}, 400: {"description": "Not a heartbeat monitor"}}`, changing the return statement to `return PingTokenResponse(ping_token=new_token)` VERIFY: `cd backend && .venv/bin/python -c "from backend.app.main import app; spec = app.openapi(); path = spec['paths']['/monitors/{monitor_id}/regenerate-ping-token']['post']; assert path['responses']['200']['content']['application/json']['schema']['\$ref'].endswith('PingTokenResponse'); assert '404' in path['responses'] and '400' in path['responses']"` (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-openapi-under-documents-the-ping-and-tok]
- [ ] [T4] backend/tests/test_openapi_ping_contract.py — Create new test file with tests asserting `"401"` is in the POST `/heartbeat/{monitor_id}` responses, the POST `/monitors/{monitor_id}/regenerate-ping-token` 200 schema `$ref` ends with `PingTokenResponse`, and `"404"`/`"400"` are in its responses VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_openapi_ping_contract.py` (cat:test; multifile:no) [feat:shrike-monitor-20261106-openapi-under-documents-the-ping-and-tok]

# --- 27B-decomposed from roadmap [2026-11-06]: Responses that carry a secret ping token are cacheable — `create_monitor()` (POST /monitor (review + tweak) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token] ---
- [ ] [T1] backend/tests/test_secret_responses_no_store.py — Add test asserting POST /monitors response includes `cache-control: no-store` header. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_secret_responses_no_store.py::test_create_monitor_no_store`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token]
- [ ] [T1] backend/tests/test_secret_responses_no_store.py — Add test asserting POST /monitors/{id}/regenerate-ping-token response includes `cache-control: no-store` header. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_secret_responses_no_store.py::test_regenerate_ping_token_no_store`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token]
- [ ] [T1] backend/tests/test_secret_responses_no_store.py — Add test asserting GET /monitors/{id} response does NOT include `cache-control: no-store` header. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_secret_responses_no_store.py::test_get_monitor_no_no_store`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token]
- [ ] [T3] backend/app/routers/monitors.py — Modify `create_monitor` to accept `response: Response` and set `response.headers["Cache-Control"] = "no-store"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_secret_responses_no_store.py::test_create_monitor_no_store`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token]
- [ ] [T3] backend/app/routers/monitors.py — Modify `regenerate_ping_token` to accept `response: Response` and set `response.headers["Cache-Control"] = "no-store"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_secret_responses_no_store.py::test_regenerate_ping_token_no_store`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token]
- [ ] [T2] backend/tests/test_secret_responses_no_store.py — Run full test suite for new file and existing ping token tests to ensure no regressions. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_secret_responses_no_store.py tests/test_ping_token.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-responses-that-carry-a-secret-ping-token]

# --- 27B-decomposed from roadmap [2026-11-06]: PATCH /monitors/{id} with {"timeout_seconds": null} corrupts the monitor and then 500s eve (review + tweak) [feat:shrike-monitor-20261106-patch-monitors-id-with-timeout-seconds-n] ---
- [ ] [T1] backend/app/schemas.py — Add "timeout_seconds" to the `NON_NULLABLE_UPDATE_FIELDS` frozenset in the `MonitorUpdate` class. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitor_update_null_fields.py`. (cat:schema; multifile:no) [feat:shrike-monitor-20261106-patch-monitors-id-with-timeout-seconds-n]
- [ ] [T2] backend/tests/test_monitor_update_null_timeout.py — Create new test file with fixtures and tests verifying that PATCHing `timeout_seconds: null` returns 422, subsequent GETs return 200 with original value, and valid updates still work. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitor_update_null_timeout.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-patch-monitors-id-with-timeout-seconds-n]
- [ ] [T3] backend/tests/test_monitor_update_null_timeout.py — Add specific test case for HTTP monitor ensuring `timeout_seconds` remains 10.0 after failed null update and list endpoint is not corrupted. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitor_update_null_timeout.py::test_http_monitor_null_timeout_preserves_value`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-patch-monitors-id-with-timeout-seconds-n]
- [ ] [T4] backend/tests/test_monitor_update_null_timeout.py — Add specific test case for heartbeat monitor ensuring `timeout_seconds` remains 10.0 after failed null update and list endpoint is not corrupted. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitor_update_null_timeout.py::test_heartbeat_monitor_null_timeout_preserves_value`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-patch-monitors-id-with-timeout-seconds-n]
- [ ] [T5] backend/tests/test_monitor_update_null_timeout.py — Add test case verifying that `{"timeout_seconds": 5}` still returns 200 and updates the value correctly. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitor_update_null_timeout.py::test_valid_timeout_update_still_works`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-patch-monitors-id-with-timeout-seconds-n]

# --- 27B-decomposed from roadmap [2026-11-06]: The startup log line prints the full MONITOR_DATABASE_URL including the database password  (review + tweak) [feat:shrike-monitor-20261106-the-startup-log-line-prints-the-full-mon] ---
- [ ] [T3] backend/app/main.py — Import `redact_url` from `backend.app.utils.redact_url` and modify the `lifespan()` function to pass `redact_url(settings.database_url)` in the persistence enabled log line and `redact_url(settings.notify_url)` in the STARTUP_GUARD warning log line, replacing the raw `settings.database_url` and `settings.notify_url` arguments. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_main_lifespan_redacts_db_url.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-the-startup-log-line-prints-the-full-mon]
- [ ] [T1] backend/tests/test_main_lifespan_redacts_db_url.py — Add a new test file with a fixture that monkeypatches `app.main.MonitorPersistence` with a fake class (async init/close/load_all) and patches `app.main.settings` (persist=True, database_url="postgresql+asyncpg://user:SECRETPW@db.example:5432/x", notify_url="https://hooks.slack.com/services/T000/B000/XXX"), then runs `async with lifespan(app)` and asserts no caplog record contains "SECRETPW" while the persistence log line contains "db.example:5432" and "***@". VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_main_lifespan_redacts_db_url.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-startup-log-line-prints-the-full-mon]
- [ ] [T2] backend/tests/test_main_startup_guard.py — Modify the existing test to assert that if `settings.notify_url` contains a password (e.g., "https://user:pass@hooks.example.com"), the logged STARTUP_GUARD message does not contain "pass" but does contain "***@" or the redacted host, ensuring the redaction is applied in the guard warning as well. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_main_startup_guard.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-startup-log-line-prints-the-full-mon]
- [ ] [T2] backend/tests/test_main_lifespan_shutdown.py — Verify that the existing shutdown test still passes with the modified `lifespan()` logic to ensure no regression in the lifespan context manager behavior when persistence is disabled or enabled. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_main_lifespan_shutdown.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-startup-log-line-prints-the-full-mon]

# --- 27B-decomposed from roadmap [2026-11-06]: `redact_text()` corrupts error messages when the URL userinfo is short (a username with no (review + tweak) [feat:shrike-monitor-20261106-redact-text-corrupts-error-messages-when] ---
- [ ] [T1] backend/app/utils/redact_url.py — Change `redact_text` to replace `info + "@"` with `"***@"` instead of replacing `info` with `"***"` to prevent corrupting text where the username appears as a common substring. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_url.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-redact-text-corrupts-error-messages-when]
- [ ] [T2] backend/tests/test_redact_text_short_userinfo.py — Add test asserting `redact_text("ConnectError: all attempts failed", "http://a@host/x")` returns the input string unchanged. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_text_short_userinfo.py::test_short_userinfo_no_corruption`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-text-corrupts-error-messages-when]
- [ ] [T3] backend/tests/test_redact_text_short_userinfo.py — Add test asserting `redact_text("failed for http://a@host/x", "http://a@host/x")` returns `"failed for http://***@host/x"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_text_short_userinfo.py::test_short_userinfo_url_form`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-text-corrupts-error-messages-when]
- [ ] [T4] backend/tests/test_redact_text_short_userinfo.py — Add test asserting `redact_text("boom user:pw@h", "https://user:pw@h/p")` returns `"boom ***@h"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_text_short_userinfo.py::test_userpass_form`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-text-corrupts-error-messages-when]
- [ ] [T5] backend/tests/test_redact_text_short_userinfo.py — Add test asserting `redact_text("text", "http://host/path")` returns `"text"` unchanged when URL has no userinfo. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_text_short_userinfo.py::test_no_userinfo`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-text-corrupts-error-messages-when]

# --- 27B-decomposed from roadmap [2026-11-06]: `redact_url()` leaves credentials that are passed in the query string, and `probe()` logs  (review + tweak) [feat:shrike-monitor-20261106-redact-url-leaves-credentials-that-are-p] ---
- [ ] [T1] backend/app/utils/redact_url.py — Modify `redact_url` to parse the query string and replace values for keys in {token, access_token, api_key, apikey, key, secret, password, passwd, auth, signature, sig} (case-insensitive) with `***`, preserving order and other params. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_url_query_secrets.py::test_basic_token_masking`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-redact-url-leaves-credentials-that-are-p]
- [ ] [T2] backend/tests/test_redact_url_query_secrets.py — Add test case verifying `redact_url("https://h/x?token=abc&a=1")` returns `"https://h/x?token=***&a=1"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_url_query_secrets.py::test_basic_token_masking`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-url-leaves-credentials-that-are-p]
- [ ] [T3] backend/tests/test_redact_url_query_secrets.py — Add test case verifying `redact_url("https://h/x?API_KEY=Z#frag")` returns `"https://h/x?API_KEY=***#frag"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_url_query_secrets.py::test_api_key_case_insensitive`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-url-leaves-credentials-that-are-p]
- [ ] [T4] backend/tests/test_redact_url_query_secrets.py — Add test case verifying `redact_url("https://h/x?a=1&b=2")` remains unchanged. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_url_query_secrets.py::test_no_secrets_unchanged`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-url-leaves-credentials-that-are-p]
- [ ] [T5] backend/tests/test_redact_url_query_secrets.py — Add test case verifying `redact_url("https://u:p@h/x?sig=1")` returns `"https://***@h/x?sig=***"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_redact_url_query_secrets.py::test_userinfo_and_query_masked`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-redact-url-leaves-credentials-that-are-p]

# --- 27B-decomposed from roadmap [2026-11-06]: `humanize_seconds()` renders 3599.96 s as "0h 59m" instead of "1h 0m" -- in backend/app/ut (review + tweak) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h] ---
- [ ] [T3] backend/app/utils/duration.py — In the hours branch of `humanize_seconds`, change `hours = int(sec // 3600)` to `hours = int(rounded // 3600)` and `minutes = int((sec % 3600) // 60)` to `minutes = int((rounded % 3600) // 60)`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py tests/test_duration_rollover.py tests/test_duration.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h]
- [ ] [T1] backend/tests/test_duration_hour_rollover.py — Add test case asserting `humanize_seconds(3599.96)` returns `"1h 0m"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py::test_3599_96_rounds_to_1h`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h]
- [ ] [T1] backend/tests/test_duration_hour_rollover.py — Add test case asserting `humanize_seconds(3599.94)` returns `"59m 59s"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py::test_3599_94_stays_minutes`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h]
- [ ] [T1] backend/tests/test_duration_hour_rollover.py — Add test case asserting `humanize_seconds(3600)` returns `"1h 0m"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py::test_3600_exact`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h]
- [ ] [T1] backend/tests/test_duration_hour_rollover.py — Add test case asserting `humanize_seconds(3720)` returns `"1h 2m"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py::test_3720_normal`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h]
- [ ] [T1] backend/tests/test_duration_hour_rollover.py — Add test case asserting `humanize_seconds(86399.99)` returns `"23h 59m"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py::test_86399_99_max_day`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h]
- [ ] [T1] backend/tests/test_duration_hour_rollover.py — Add test case asserting `humanize_seconds(7199.96)` returns `"2h 0m"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_duration_hour_rollover.py::test_7199_96_two_hours`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-humanize-seconds-renders-3599-96-s-as-0h]

# --- 27B-decomposed from roadmap [2026-11-06]: `calculate_backoff_delay()` raises OverflowError for any attempt of about 1024 or more --  (review + tweak) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe] ---
- [ ] [T2] backend/app/utils/backoff.py — Modify `calculate_backoff_delay` to bound the exponent in `exp_delay = base_delay * (2 ** attempt)` by using `min(attempt, 60)` before multiplication. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_backoff_large_attempt.py tests/test_backoff.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe]
- [ ] [T1] backend/tests/test_backoff_large_attempt.py — Add test asserting `calculate_backoff_delay(0, seed=1)` equals the pre-change literal value to pin behavior. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_backoff_large_attempt.py::test_attempt_zero_seed_one_literal`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe]
- [ ] [T1] backend/tests/test_backoff_large_attempt.py — Add test asserting `calculate_backoff_delay(1023, seed=1)` returns a float within `[0, max_delay]` for `max_delay=60.0` and `base_delay=1.0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_backoff_large_attempt.py::test_attempt_1023_seed_one`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe]
- [ ] [T1] backend/tests/test_backoff_large_attempt.py — Add test asserting `calculate_backoff_delay(1024, seed=1)` returns a float within `[0, max_delay]` for `max_delay=60.0` and `base_delay=1.0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_backoff_large_attempt.py::test_attempt_1024_seed_one`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe]
- [ ] [T1] backend/tests/test_backoff_large_attempt.py — Add test asserting `calculate_backoff_delay(1100, seed=1)` returns a float within `[0, max_delay]` for `max_delay=60.0` and `base_delay=1.0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_backoff_large_attempt.py::test_attempt_1100_seed_one`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe]
- [ ] [T1] backend/tests/test_backoff_large_attempt.py — Add test asserting `calculate_backoff_delay(10**6, seed=1)` returns a float within `[0, max_delay]` for `max_delay=30.0` and `base_delay=1000.0`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_backoff_large_attempt.py::test_attempt_1e6_seed_one`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe]
- [ ] [T1] backend/tests/test_backoff_large_attempt.py — Add test asserting `calculate_backoff_delay(-1, seed=1)` raises `ValueError`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_backoff_large_attempt.py::test_negative_attempt_raises_value_error`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-calculate-backoff-delay-raises-overflowe]

# --- 27B-decomposed from roadmap [2026-11-06]: SCHEDULER_TICK_SECONDS accepts absurdly small and absurdly large values -- `Settings._fall (review + tweak) [feat:shrike-monitor-20261106-scheduler-tick-seconds-accepts-absurdly-] ---
- [ ] [T1] backend/tests/test_config_tick_bounds.py — Add test cases verifying `Settings(scheduler_tick_seconds="0.0001")` and `"1e-9"` fallback to 30.0, `"0.1"` stays 0.1, `"3600"` stays 3600.0, `"3601"` and `"99999999"` fallback to 30.0, `"5"` stays 5.0, and invalid strings ("abc", "-1", "0", "inf") fallback to 30.0. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_tick_bounds.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-scheduler-tick-seconds-accepts-absurdly-]
- [ ] [T2] backend/app/config.py — Modify `_fallback_invalid_float` to return the field default (30.0) if the parsed value is not within the range `[0.1, 3600.0]`, ensuring `SCHEDULER_TICK_SECONDS` bounds are enforced. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_tick_bounds.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-scheduler-tick-seconds-accepts-absurdly-]
- [ ] [T3] backend/tests/test_config_tick_bounds.py — Add test cases verifying that valid boundary values `"0.1"` and `"3600"` are preserved, while slightly out-of-bounds values `"0.09"` and `"3600.1"` fallback to 30.0. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_tick_bounds.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-scheduler-tick-seconds-accepts-absurdly-]
- [ ] [T4] backend/app/config.py — Ensure `_fallback_invalid_float` correctly handles the specific case where `SCHEDULER_TICK_SECONDS` is set to `"0.1"` by allowing it through, while rejecting `"0.09"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_tick_bounds.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-scheduler-tick-seconds-accepts-absurdly-]
- [ ] [T5] backend/tests/test_config_tick_bounds.py — Add test cases verifying that non-finite values like `"inf"` and `"nan"` fallback to 30.0, and negative values like `"-1"` fallback to 30.0. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_tick_bounds.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-scheduler-tick-seconds-accepts-absurdly-]

# --- 27B-decomposed from roadmap [2026-11-06]: NOTIFY_TOKEN and NOTIFY_TOPIC are used verbatim, so a trailing newline from a pasted secre (review + tweak) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v] ---
- [ ] [T3] backend/app/config.py — Add a `field_validator("notify_token", "notify_topic", mode="before")` to the `Settings` class that strips surrounding whitespace from string values, ensuring all-whitespace topics fall back to `"monitor-status"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_notify_whitespace.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v]
- [ ] [T1] backend/tests/test_config_notify_whitespace.py — Add test cases verifying `Settings(notify_token="abc\n")` and `Settings(notify_token=" abc ")` result in `notify_token == "abc"`, while `Settings(notify_token="a b")` remains `"a b"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_notify_whitespace.py::test_token_stripping`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v]
- [ ] [T1] backend/tests/test_config_notify_whitespace.py — Add test cases verifying `Settings(notify_topic=" t ")` results in `notify_topic == "t"`, and `Settings(notify_topic="   ")` falls back to `"monitor-status"`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_notify_whitespace.py::test_topic_stripping_and_fallback`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v]
- [ ] [T1] backend/tests/test_config_notify_whitespace.py — Add test cases verifying that unset `notify_token` and `notify_topic` retain their default values (`""` and `"monitor-status"` respectively). VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config_notify_whitespace.py::test_defaults_preserved`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v]
- [ ] [T2] backend/tests/test_config.py — Verify existing configuration tests still pass with the new whitespace handling logic, ensuring no regression in other settings. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_config.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v]
- [ ] [T2] backend/tests/test_notifier.py — Verify notifier tests still pass, confirming that the stripped token and topic are correctly used in headers and URLs without protocol errors. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_notifier.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-notify-token-and-notify-topic-are-used-v]

# --- 27B-decomposed from roadmap [2026-11-06]: A monitor with no recorded results reports `sla_met: false` and `uptime_percent: 0.0`, i.e (review + tweak) [feat:shrike-monitor-20261106-a-monitor-with-no-recorded-results-repor] ---
- [ ] [T1] backend/app/routers/monitors.py — Modify `_build_status_out` to compute `sla_met_value` as `compute_sla_met(results, sla_target) if sla_target is not None and results else None`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_monitors_status_api.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-a-monitor-with-no-recorded-results-repor]
- [ ] [T2] backend/tests/test_status_sla_no_results.py — Add test case verifying that a fresh HTTP monitor with no results returns `sla_met: None` and `checks: 0` when queried with `?sla_target=0.9`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_status_sla_no_results.py::test_http_monitor_no_results_sla_none`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-a-monitor-with-no-recorded-results-repor]
- [ ] [T3] backend/tests/test_status_sla_no_results.py — Add test case verifying that a fresh heartbeat monitor with no results returns `sla_met: None` and `checks: 0` when queried with `?sla_target=0.9`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_status_sla_no_results.py::test_heartbeat_monitor_no_results_sla_none`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-a-monitor-with-no-recorded-results-repor]
- [ ] [T4] backend/tests/test_status_sla_no_results.py — Add test case verifying that after recording one successful check, the monitor status returns `sla_met: True` with `?sla_target=0.9`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_status_sla_no_results.py::test_monitor_with_success_sla_true`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-a-monitor-with-no-recorded-results-repor]
- [ ] [T5] backend/tests/test_status_sla_no_results.py — Add test case verifying that after recording one failed check, the monitor status returns `sla_met: False` with `?sla_target=0.9`. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_status_sla_no_results.py::test_monitor_with_failure_sla_false`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-a-monitor-with-no-recorded-results-repor]

# --- 27B-decomposed from roadmap [2026-11-06]: The API's 401 responses carry no `WWW-Authenticate` header -- `require_api_token()` (backe (review + tweak) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut] ---
- [ ] [T3] backend/app/auth.py — Add `headers={"WWW-Authenticate": "Bearer"}` to the HTTPException raised in `require_api_token()` for 401 status. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_www_authenticate.py`. (cat:python; multifile:no) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut]
- [ ] [T1] backend/tests/test_auth_www_authenticate.py — Add test verifying 401 response includes `WWW-Authenticate: Bearer` header when token is missing. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_www_authenticate.py::test_missing_token_www_authenticate`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut]
- [ ] [T1] backend/tests/test_auth_www_authenticate.py — Add test verifying 401 response includes `WWW-Authenticate: Bearer` header when token is invalid. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_www_authenticate.py::test_invalid_token_www_authenticate`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut]
- [ ] [T1] backend/tests/test_auth_www_authenticate.py — Add test verifying 401 response includes `WWW-Authenticate: Bearer` header when using Basic auth scheme. VERIFY: `cd backend && .venv/bin/pytest -q --no-cov tests/test_auth_www_authenticate.py::test_basic_auth_www_authenticate`. (cat:test; multifile:no) [feat:shrike-monitor-20261106-the-api-s-401-responses-carry-no-www-aut]
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
