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
- [ ] [T2] backend/tests/test_readme_layout_paths_exist.py — Add test function `test_readme_layout_lists_the_core_service_modules` that reads `ROOT / "README.md"`, extracts the layout section, and asserts the section text contains `checker.py`, `scheduler.py`, `notifier.py`, `store.py`, and `persistence.py`. VERIFY: `cd backend && python3 -m pytest tests/test_readme_layout_paths_exist.py::test_readme_layout_lists_the_core_service_modules -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-readme-layout-can-drift-from-the-tree-wi]

# --- 27B-decomposed from roadmap [2026-11-11]: `railway.toml`, the Dockerfile and `start.sh` are not checked against the app - `backend/r (review + tweak) [feat:shrike-monitor-20261111-railway-toml-the-dockerfile-and-start-sh] ---
- [ ] [T1] backend/tests/test_deploy_config_matches_app.py — Create file with `test_railway_healthcheck_path_is_a_real_route_and_dockerfile_runs_start_script` that parses `backend/railway.toml` using `tomllib`, asserts `cfg["build"]["builder"] == "DOCKERFILE"`, `cfg["build"]["dockerfilePath"] == "Dockerfile"`, `cfg["deploy"]["healthcheckPath"] in {getattr(r, "path", None) for r in app.routes}`, and `cfg["deploy"]["healthcheckTimeout"] > 0`. VERIFY: `cd backend && python3 -m pytest tests/test_deploy_config_matches_app.py::test_railway_healthcheck_path_is_a_real_route_and_dockerfile_runs_start_script -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-railway-toml-the-dockerfile-and-start-sh]
- [ ] [T1] backend/tests/test_deploy_config_matches_app.py — Add assertion to `test_railway_healthcheck_path_is_a_real_route_and_dockerfile_runs_start_script` that reads `backend/Dockerfile` and asserts it contains `CMD ["./start.sh"]`, `COPY requirements.txt .`, and `RUN chmod +x start.sh`. VERIFY: `cd backend && python3 -m pytest tests/test_deploy_config_matches_app.py::test_railway_healthcheck_path_is_a_real_route_and_dockerfile_runs_start_script -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-railway-toml-the-dockerfile-and-start-sh]
- [ ] [T1] backend/tests/test_deploy_config_matches_app.py — Add `test_start_script_serves_app_main_on_port_env_with_default` that reads `backend/start.sh` and asserts it contains `app.main:app`, `--port "${PORT:-8000}"`, and `--host 0.0.0.0`. VERIFY: `cd backend && python3 -m pytest tests/test_deploy_config_matches_app.py::test_start_script_serves_app_main_on_port_env_with_default -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-railway-toml-the-dockerfile-and-start-sh]

# --- 27B-decomposed from roadmap [2026-11-11]: `MonitorScheduler._maybe_notify` semaphore branches are untested - `backend/app/services/s (review + tweak) [feat:shrike-monitor-20261111-monitorscheduler-maybe-notify-semaphore-] ---
- [ ] [T1] backend/tests/test_scheduler_maybe_notify_semaphore_paths.py — Add `async def test_maybe_notify_skips_when_nothing_to_send_and_awaits_send_with_or_without_semaphore` that instantiates `MonitorScheduler`, mocks `_prepare_notify` to return `None`, and asserts the send list remains empty. VERIFY: `cd backend && python3 -m pytest tests/test_scheduler_maybe_notify_semaphore_paths.py::test_maybe_notify_skips_when_nothing_to_send_and_awaits_send_with_or_without_semaphore -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-monitorscheduler-maybe-notify-semaphore-]
- [ ] [T1] backend/tests/test_scheduler_maybe_notify_semaphore_paths.py — Extend `test_maybe_notify_skips_when_nothing_to_send_and_awaits_send_with_or_without_semaphore` to mock `_prepare_notify` returning a coroutine, set `sched._notify_sem = None`, and assert the send list contains `"sent"`. VERIFY: `cd backend && python3 -m pytest tests/test_scheduler_maybe_notify_semaphore_paths.py::test_maybe_notify_skips_when_nothing_to_send_and_awaits_send_with_or_without_semaphore -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-monitorscheduler-maybe-notify-semaphore-]
- [ ] [T1] backend/tests/test_scheduler_maybe_notify_semaphore_paths.py — Extend `test_maybe_notify_skips_when_nothing_to_send_and_awaits_send_with_or_without_semaphore` to set `sched._notify_sem = asyncio.Semaphore(1)`, call `_maybe_notify` twice, and assert the send list contains two `"sent"` entries and `sched._notify_sem._value == 1`. VERIFY: `cd backend && python3 -m pytest tests/test_scheduler_maybe_notify_semaphore_paths.py::test_maybe_notify_skips_when_nothing_to_send_and_awaits_send_with_or_without_semaphore -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-monitorscheduler-maybe-notify-semaphore-]

# --- 27B-decomposed from roadmap [2026-11-11]: `MonitorUpdate` heartbeat-url rule and status-code range errors are untested - `backend/ap (review + tweak) [feat:shrike-monitor-20261111-monitorupdate-heartbeat-url-rule-and-sta] ---
- [ ] [T1] backend/tests/test_schemas_monitor_update_heartbeat_url_and_status_range.py — Add `test_monitor_update_heartbeat_requires_empty_url` asserting `ValidationError` with match "url must be empty for heartbeat monitors" for `MonitorUpdate(effective_type="heartbeat", url="http://example.com")` and `MonitorUpdate(effective_type="heartbeat", url="").url == ""`. VERIFY: `cd backend && python3 -m pytest tests/test_schemas_monitor_update_heartbeat_url_and_status_range.py::test_monitor_update_heartbeat_requires_empty_url -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-monitorupdate-heartbeat-url-rule-and-sta]
- [ ] [T1] backend/tests/test_schemas_monitor_update_heartbeat_url_and_status_range.py — Add `test_monitor_update_status_code_range_and_null_handling` asserting `MonitorUpdate(expected_status_codes=None).expected_status_codes is None`, `[100, 599]` accepted unchanged, and `ValidationError` matching "status code <bad> must be between 100 and 599" for `bad` in (99, 600) with `MonitorUpdate(expected_status_codes=[200, bad])`. VERIFY: `cd backend && python3 -m pytest tests/test_schemas_monitor_update_heartbeat_url_and_status_range.py::test_monitor_update_status_code_range_and_null_handling -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-monitorupdate-heartbeat-url-rule-and-sta]
- [ ] [T2] backend/tests/test_schemas_monitor_update_heartbeat_url_and_status_range.py — Execute full test file to confirm both new tests pass against existing `backend/app/schemas.py` implementation. VERIFY: `cd backend && python3 -m pytest tests/test_schemas_monitor_update_heartbeat_url_and_status_range.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-monitorupdate-heartbeat-url-rule-and-sta]

# --- 27B-decomposed from roadmap [2026-11-11]: The heartbeat route registers one duplicate OpenAPI operationId; give GET and POST unique  (review + tweak) [feat:shrike-monitor-20261111-the-heartbeat-route-registers-one-duplic] ---
- [ ] [T3] backend/app/routers/heartbeat.py — Replace `@router.api_route('/heartbeat/{monitor_id}', methods=['GET', 'POST'], ...)` with stacked `@router.get('/heartbeat/{monitor_id}', operation_id='ping_heartbeat_get', ...)` and `@router.post('/heartbeat/{monitor_id}', operation_id='ping_heartbeat_post', ...)` decorators above the same `async def ping` handler, preserving all existing kwargs (`summary`, `responses`, `response_model`, etc.) and handler body exactly. VERIFY: `cd backend && python3 -c "from app.main import app; from fastapi.openapi.utils import get_openapi; schema = get_openapi(title='t', version='1', routes=app.routes); ops = [op.get('operationId') for path in schema['paths'].values() for op in path.values() if isinstance(op, dict)]; assert 'ping_heartbeat_get' in ops and 'ping_heartbeat_post' in ops; print('OK')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-the-heartbeat-route-registers-one-duplic]
- [ ] [T1] backend/tests/test_openapi_operation_ids_unique.py — Create test file with `import warnings`, `from collections import Counter`, `from app.main import app`, and `test_every_openapi_operation_id_is_unique_and_no_duplicate_warning` that builds schema via `get_openapi(title='t', version='1', routes=app.routes)` inside `warnings.catch_warnings(record=True)` with `simplefilter('always')`, asserts no `operationId` count > 1, no warning contains `Duplicate Operation ID`, and both `ping_heartbeat_get` and `ping_heartbeat_post` are present. VERIFY: `cd backend && python3 -m pytest tests/test_openapi_operation_ids_unique.py -q -k test_every_openapi_operation_id_is_unique_and_no_duplicate_warning`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-the-heartbeat-route-registers-one-duplic]
- [ ] [T2] backend/tests/test_heartbeat_auth_separation.py — Verify existing heartbeat auth separation tests still pass with the new dual-registration pattern. VERIFY: `cd backend && python3 -m pytest tests/test_heartbeat_auth_separation.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-the-heartbeat-route-registers-one-duplic]
- [ ] [T2] backend/tests/test_heartbeat_header_token.py — Verify existing heartbeat header token tests still pass with the new dual-registration pattern. VERIFY: `cd backend && python3 -m pytest tests/test_heartbeat_header_token.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-the-heartbeat-route-registers-one-duplic]
- [ ] [T2] backend/tests/test_heartbeat_ping_response_fields.py — Verify existing heartbeat ping response field tests still pass with the new dual-registration pattern. VERIFY: `cd backend && python3 -m pytest tests/test_heartbeat_ping_response_fields.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-the-heartbeat-route-registers-one-duplic]

# --- 27B-decomposed from roadmap [2026-11-11]: `DELETE /monitors/{id}` without a scheduler on `app.state` is untested - `backend/app/rout (review + tweak) [feat:shrike-monitor-20261111-delete-monitors-id-without-a-scheduler-o] ---
- [ ] [T1] backend/tests/test_delete_monitor_without_scheduler.py — Create file with `from fastapi.testclient import TestClient`, `from app.main import app`, `from app.store import store`, and empty test function `test_delete_monitor_returns_204_when_no_scheduler_is_attached` that passes trivially. VERIFY: `cd backend && python3 -m pytest tests/test_delete_monitor_without_scheduler.py -q -k test_delete_monitor_returns_204_when_no_scheduler_is_attached`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-delete-monitors-id-without-a-scheduler-o]
- [ ] [T2] backend/tests/test_delete_monitor_without_scheduler.py — Modify `test_delete_monitor_returns_204_when_no_scheduler_is_attached` to call `store.clear()` at start, create an HTTP monitor via `c.post('/monitors', json={'name': 'm', 'type': 'http', 'url': 'https://example.com/h', 'interval_seconds': 60})` inside `with TestClient(app) as c:`, and assert the response status is 201. VERIFY: `cd backend && python3 -m pytest tests/test_delete_monitor_without_scheduler.py -q -k test_delete_monitor_returns_204_when_no_scheduler_is_attached`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-delete-monitors-id-without-a-scheduler-o]
- [ ] [T3] backend/tests/test_delete_monitor_without_scheduler.py — Modify `test_delete_monitor_returns_204_when_no_scheduler_is_attached` to extract `mid` from the created monitor response, save `sched = getattr(app.state, 'scheduler', None)`, and set `app.state.scheduler = None`. VERIFY: `cd backend && python3 -m pytest tests/test_delete_monitor_without_scheduler.py -q -k test_delete_monitor_returns_204_when_no_scheduler_is_attached`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-delete-monitors-id-without-a-scheduler-o]
- [ ] [T4] backend/tests/test_delete_monitor_without_scheduler.py — Modify `test_delete_monitor_returns_204_when_no_scheduler_is_attached` to perform `c.delete(f'/monitors/{mid}')` and assert `status_code == 204` and `store.get(mid) is None`. VERIFY: `cd backend && python3 -m pytest tests/test_delete_monitor_without_scheduler.py -q -k test_delete_monitor_returns_204_when_no_scheduler_is_attached`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-delete-monitors-id-without-a-scheduler-o]
- [ ] [T5] backend/tests/test_delete_monitor_without_scheduler.py — Modify `test_delete_monitor_returns_204_when_no_scheduler_is_attached` to wrap the scheduler manipulation in a `try...finally` block that restores `app.state.scheduler = sched` and calls `store.clear()` at the end. VERIFY: `cd backend && python3 -m pytest tests/test_delete_monitor_without_scheduler.py -q -k test_delete_monitor_returns_204_when_no_scheduler_is_attached`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-delete-monitors-id-without-a-scheduler-o]

# --- 27B-decomposed from roadmap [2026-11-11]: `test_monitors_status_api.py` repeats two tests three times each - `backend/tests/test_mon (review + tweak) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-] ---
- [ ] [T1] backend/tests/test_monitors_status_api.py — Remove the first duplicate definition of `test_monitor_status_not_found` and its body (lines ~61-70) VERIFY: `cd backend && test "$(grep -c 'def test_monitor_status_not_found' tests/test_monitors_status_api.py)" -eq 2`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-]
- [ ] [T1] backend/tests/test_monitors_status_api.py — Remove the second duplicate definition of `test_monitor_status_not_found` and its body (lines ~142-151) VERIFY: `cd backend && test "$(grep -c 'def test_monitor_status_not_found' tests/test_monitors_status_api.py)" -eq 1`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-]
- [ ] [T1] backend/tests/test_monitors_status_api.py — Remove the first duplicate definition of `test_monitor_status_auth_required` and its body (lines ~71-80) VERIFY: `cd backend && test "$(grep -c 'def test_monitor_status_auth_required' tests/test_monitors_status_api.py)" -eq 2`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-]
- [ ] [T1] backend/tests/test_monitors_status_api.py — Remove the second duplicate definition of `test_monitor_status_auth_required` and its body (lines ~152-161) VERIFY: `cd backend && test "$(grep -c 'def test_monitor_status_auth_required' tests/test_monitors_status_api.py)" -eq 1`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-]
- [ ] [T2] backend/tests/test_monitors_status_api.py — Verify the file contains exactly one definition of each target test and no syntax errors VERIFY: `cd backend && python3 -m py_compile tests/test_monitors_status_api.py && test "$(grep -c 'def test_monitor_status_not_found' tests/test_monitors_status_api.py)" -eq 1 && test "$(grep -c 'def test_monitor_status_auth_required' tests/test_monitors_status_api.py)" -eq 1`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-]
- [ ] [T2] backend/tests/test_monitors_status_api.py — Run the full test suite for this file to ensure remaining tests pass VERIFY: `cd backend && python3 -m pytest tests/test_monitors_status_api.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-monitors-status-api-py-repeats-two-]

# --- 27B-decomposed from roadmap [2026-11-11]: `test_results_incidents.py` defines `test_monitor_results_auth_required` twice - `backend/ (review + tweak) [feat:shrike-monitor-20261111-test-results-incidents-py-defines-test-m] ---
- [ ] [T2] backend/tests/test_results_incidents.py — Verify the remaining `test_monitor_results_auth_required` function is syntactically valid and correctly indented within the module. VERIFY: `cd backend && python3 -m py_compile tests/test_results_incidents.py`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-results-incidents-py-defines-test-m]
- [ ] [T3] backend/tests/test_results_incidents.py — Execute the specific test to ensure it passes with the duplicate removed. VERIFY: `cd backend && python3 -m pytest tests/test_results_incidents.py::test_monitor_results_auth_required -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-results-incidents-py-defines-test-m]
- [ ] [T4] backend/tests/test_results_incidents.py — Run the full test file to ensure no other tests were affected by the deletion. VERIFY: `cd backend && python3 -m pytest tests/test_results_incidents.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-results-incidents-py-defines-test-m]
- [ ] [T5] backend/tests/test_results_incidents.py — Confirm via grep that exactly one definition of `test_monitor_results_auth_required` exists in the file. VERIFY: `cd backend && test "$(grep -c 'def test_monitor_results_auth_required' tests/test_results_incidents.py)" -eq 1`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-results-incidents-py-defines-test-m]
- [ ] [T1] backend/tests/test_results_incidents.py — Remove the first occurrence of `async def test_monitor_results_auth_required` (including its docstring) located around line 164, ensuring the second occurrence remains. VERIFY: `cd backend && python3 -c "import ast; tree=ast.parse(open('tests/test_results_incidents.py').read()); funcs=[n.name for n in ast.walk(tree) if isinstance(n, ast.AsyncFunctionDef) and n.name=='test_monitor_results_auth_required']; assert len(funcs)==1, f'Found {len(funcs)} occurrences'"`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-test-results-incidents-py-defines-test-m]

# --- 27B-decomposed from roadmap [2026-11-11]: Drop the unreachable fallback line in `Settings._fallback_invalid_float` - `backend/app/co (review + tweak) [feat:shrike-monitor-20261111-drop-the-unreachable-fallback-line-in-se] ---
- [ ] [T1] backend/app/config.py — Replace the `if info.field_name == 'scheduler_tick_seconds': return ...` block and the final `return parsed if parsed > 0 else default` line with a single `return parsed if 0.1 <= parsed <= 3600 else default` inside `_fallback_invalid_float`. VERIFY: `cd backend && python3 -m pytest tests/test_config_tick_bounds.py tests/test_config.py -q` (cat:refactor; multifile:no) [feat:shrike-monitor-20261111-drop-the-unreachable-fallback-line-in-se]
- [ ] [T2] backend/app/config.py — Verify the dead code line `return parsed if parsed > 0 else default` is completely removed from `_fallback_invalid_float`. VERIFY: `test "$(grep -c 'return parsed if parsed > 0 else default' app/config.py)" -eq 0` (cat:refactor; multifile:no) [feat:shrike-monitor-20261111-drop-the-unreachable-fallback-line-in-se]

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure status-page builder - create `backend/app/services/status_page.py` with `build_ (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba] ---
- [ ] [T1] backend/app/services/status_page.py — Add `build_status_page` function that computes overall status as the worst present (down > degraded > pending > up) or 'pending' if empty, counts statuses, and sorts monitors by severity then name. VERIFY: `cd backend && python3 -c "from app.services.status_page import build_status_page; print(build_status_page([], 0)['overall'])"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba]
- [ ] [T2] backend/tests/test_status_page_builder.py — Add `test_overall_is_worst_status_present` asserting that a mix of 'up' and 'down' returns 'down', and 'degraded' and 'up' returns 'degraded'. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_builder.py::test_overall_is_worst_status_present -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba]
- [ ] [T2] backend/tests/test_status_page_builder.py — Add `test_empty_fleet_is_pending` asserting that an empty list results in overall status 'pending' and empty counts. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_builder.py::test_empty_fleet_is_pending -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba]
- [ ] [T2] backend/tests/test_status_page_builder.py — Add `test_monitors_sorted_worst_first_then_name` asserting monitors are sorted by severity (down first) and then alphabetically by name. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_builder.py::test_monitors_sorted_worst_first_then_name -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba]
- [ ] [T3] backend/app/services/status_page.py — Ensure `generated_at` field in the returned dict matches the `now` argument passed to the function. VERIFY: `cd backend && python3 -c "from app.services.status_page import build_status_page; assert build_status_page([], 123.45)['generated_at'] == 123.45"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba]
- [ ] [T3] backend/app/services/status_page.py — Ensure `counts` dictionary in the returned dict accurately reflects the frequency of each status in the input items. VERIFY: `cd backend && python3 -c "from app.services.status_page import build_status_page; r=build_status_page([{'id':'1','name':'a','status':'up','uptime_24h_percent':99}], 0); assert r['counts']=={'up':1}"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-status-page-builder-create-ba]

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /status-page` as its own router - create `backend/app/routers/status_page.py` wit (review + tweak) [feat:shrike-monitor-20261111-add-get-status-page-as-its-own-router-cr] ---
- [ ] [T1] backend/app/routers/status_page.py — Add `@router.get("/status-page")` async function that iterates `store.list()`, builds items using `_build_monitor_status_item(monitor, store.results(monitor.id))`, and returns `build_status_page(items, time.time())`. VERIFY: `cd backend && python3 -c "from app.routers.status_page import router; print([r.path for r in router.routes])"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261111-add-get-status-page-as-its-own-router-cr]
- [ ] [T1] backend/app/routers/status_page.py — Add `router = APIRouter(tags=["status-page"], dependencies=[Depends(require_api_token)])` and import `require_api_token` from `app.auth`, `store` from `app.store`, `_build_monitor_status_item` from `app.routers.monitors`, and `build_status_page` from `app.utils.fleet_status_counts`. VERIFY: `cd backend && python3 -c "from app.routers.status_page import router; print(router)"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261111-add-get-status-page-as-its-own-router-cr]
- [ ] [T2] backend/tests/test_status_page_router.py — Create test file with `test_status_page_reports_down_monitor` that mounts the status-page router on a fresh `FastAPI()`, creates an HTTP monitor via `await store.create(...)`, records a failing `CheckResult`, asserts `overall == "down"` and monitor presence, then calls `store.clear()`. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_router.py -q -k test_status_page_reports_down_monitor`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-get-status-page-as-its-own-router-cr]

# --- 27B-decomposed from roadmap [2026-11-11]: Wire the status-page router into the app - in `backend/app/main.py` import `status_page` w (review + tweak) [feat:shrike-monitor-20261111-wire-the-status-page-router-into-the-app] ---
- [ ] [T1] backend/app/routers/status_page.py — Create the router module with a `/status-page` GET endpoint that returns 200 JSON and enforces API token auth via dependency. VERIFY: `cd backend && python3 -c "from app.routers.status_page import router; print(router)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-wire-the-status-page-router-into-the-app]
- [ ] [T3] backend/app/main.py — Import `status_page` from `app.routers` and add `app.include_router(status_page.router)` immediately after `app.include_router(heartbeat.router)`. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_wired.py -q -k test_status_page_route_registered_and_gated_by_api_token`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-wire-the-status-page-router-into-the-app]
- [ ] [T2] backend/tests/test_status_page_wired.py — Create the test file with `test_status_page_route_registered_and_gated_by_api_token` that asserts `/status-page` is in `app.openapi()["paths"]` and returns 401 without token when `settings.monitor_api_token` is set. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_wired.py -q -k test_status_page_route_registered_and_gated_by_api_token`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-wire-the-status-page-router-into-the-app]

# --- 27B-decomposed from roadmap [2026-11-11]: Add an optional `status` filter to the status page - in `backend/app/routers/status_page.p (review + tweak) [feat:shrike-monitor-20261111-add-an-optional-status-filter-to-the-sta] ---
- [ ] [T1] backend/app/routers/status_page.py — Add `status: str | None = Query(None)` parameter to the status endpoint function and filter the monitors list to only those where `monitor.status == status` if `status` is not None. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_router.py -q -k test_status_filter_limits_monitors_but_not_counts`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261111-add-an-optional-status-filter-to-the-sta]
- [ ] [T1] backend/tests/test_status_page_router.py — Add `test_status_filter_limits_monitors_but_not_counts` that asserts filtering by a valid status reduces the monitors list but leaves `overall` and `counts` unchanged, and filtering by an unknown status returns an empty monitors list with full counts. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_router.py -q -k test_status_filter_limits_monitors_but_not_counts`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-an-optional-status-filter-to-the-sta]

# --- 27B-decomposed from roadmap [2026-11-11]: Document the status page - create `docs/STATUS_PAGE.md` describing `GET /status-page` (fie (review + tweak) [feat:shrike-monitor-20261111-document-the-status-page-create-docs-sta] ---
- [ ] [T1] backend/app/services/status_page.py — Add `build_status_page(monitors: list[dict], uptime_pct: float) -> dict` returning a dict with keys `generated_at`, `overall_status`, `uptime_percentage`, `monitors`, `severity_order`, `status_filter_options`. VERIFY: `cd backend && python3 -c "from app.services.status_page import build_status_page; d = build_status_page([], 0.0); assert set(d.keys()) == {'generated_at', 'overall_status', 'uptime_percentage', 'monitors', 'severity_order', 'status_filter_options'}"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-document-the-status-page-create-docs-sta]
- [ ] [T2] backend/app/main.py — Import `status_page_router` from `app.routers.status_page` and include it with `app.include_router(status_page_router)` after existing routers. VERIFY: `cd backend && python3 -c "from app.main import app; routes = [r.path for r in app.routes]; assert '/status-page' in routes". (cat:python; multifile:no) [feat:shrike-monitor-20261111-document-the-status-page-create-docs-sta]
- [ ] [T1] docs/STATUS_PAGE.md — Create file documenting `GET /status-page` with sections for fields (`generated_at`, `overall_status`, `uptime_percentage`, `monitors`, `severity_order`, `status_filter_options`), severity order, status filter usage, API token rule (same as `/monitors`), and differences from `GET /monitors/status`. VERIFY: `grep -q "generated_at" docs/STATUS_PAGE.md && grep -q "overall_status" docs/STATUS_PAGE.md && grep -q "uptime_percentage" docs/STATUS_PAGE.md && grep -q "monitors" docs/STATUS_PAGE.md && grep -q "severity_order" docs/STATUS_PAGE.md && grep -q "status_filter_options" docs/STATUS_PAGE.md`. (cat:docs; multifile:no) [feat:shrike-monitor-20261111-document-the-status-page-create-docs-sta]
- [ ] [T1] backend/app/routers/status_page.py — Create `router = APIRouter()` and `@router.get("/status-page")` endpoint that accepts `status: str | None = Query(None)` and returns `build_status_page(monitors, uptime)` filtered by status if provided. VERIFY: `cd backend && python3 -c "from app.routers.status_page import router; assert hasattr(router, 'get')". (cat:endpoint; multifile:no) [feat:shrike-monitor-20261111-document-the-status-page-create-docs-sta]
- [ ] [T1] backend/tests/test_status_page_doc.py — Create test file with `test_status_page_doc_mentions_every_top_level_key` that imports `build_status_page`, calls it with `([], 0.0)`, reads `../docs/STATUS_PAGE.md`, and asserts every top-level key from the returned dict appears in the doc content. VERIFY: `cd backend && python3 -m pytest tests/test_status_page_doc.py -q -k test_status_page_doc_mentions_every_top_level_key`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-document-the-status-page-create-docs-sta]

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure incident merger - create `backend/app/services/incident_feed.py` with `merge_in (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-incident-merger-create-backen] ---
- [ ] [T1] backend/app/services/incident_feed.py — Add `merge_incidents` function that filters by `since`, enriches with `monitor_name`, sorts by `started_at` desc, and limits results. VERIFY: `cd backend && python3 -c "from app.services.incident_feed import merge_incidents; print(merge_incidents([], {}, None, 10))"` (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-incident-merger-create-backen]
- [ ] [T2] backend/tests/test_incident_feed_merge.py — Add `test_merge_incidents_sorts_names_and_limits` verifying sorting, name enrichment, and limit application. VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_merge.py::test_merge_incidents_sorts_names_and_limits -q` (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-incident-merger-create-backen]
- [ ] [T2] backend/tests/test_incident_feed_merge.py — Add `test_merge_incidents_since_drops_ended_before_cutoff_but_keeps_ongoing` verifying `since` filtering logic for ended vs ongoing incidents. VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_merge.py::test_merge_incidents_since_drops_ended_before_cutoff_but_keeps_ongoing -q` (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-incident-merger-create-backen]

# --- 27B-decomposed from roadmap [2026-11-11]: Add a pure incident summary - in `backend/app/services/incident_feed.py` add `summarize_in (review + tweak) [feat:shrike-monitor-20261111-add-a-pure-incident-summary-in-backend-a] ---
- [ ] [T1] backend/app/services/incident_feed.py — Add `summarize_incidents(incidents: list[dict], now: float) -> dict` function returning `{"total", "ongoing", "mttr_seconds", "longest_seconds"}` with correct logic for MTTR (mean of ended) and longest (max duration including ongoing up to `now`, 0.0 if empty). VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_summary.py -q -k 'test_summarize_incidents_mttr_ongoing_and_longest or test_summarize_incidents_empty_list'`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-incident-summary-in-backend-a]
- [ ] [T1] backend/tests/test_incident_feed_summary.py — Create test file with `test_summarize_incidents_mttr_ongoing_and_longest` verifying correct calculation of total, ongoing count, MTTR for ended incidents, and longest duration including ongoing ones. VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_summary.py::test_summarize_incidents_mttr_ongoing_and_longest -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-incident-summary-in-backend-a]
- [ ] [T1] backend/tests/test_incident_feed_summary.py — Add `test_summarize_incidents_empty_list` verifying that an empty list returns `{"total": 0, "ongoing": 0, "mttr_seconds": None, "longest_seconds": 0.0}`. VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_summary.py::test_summarize_incidents_empty_list -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-a-pure-incident-summary-in-backend-a]

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /incidents` as its own router - create `backend/app/routers/incident_feed.py` wit (review + tweak) [feat:shrike-monitor-20261111-add-get-incidents-as-its-own-router-crea] ---
- [ ] [T1] backend/app/routers/incident_feed.py — Add `merge_incidents(incidents: list[dict], monitor_names: dict[str, str]) -> list[dict]` that sorts by `ended_at` descending and injects `monitor_name` from `monitor_names`. VERIFY: `cd backend && python3 -c "from app.routers.incident_feed import merge_incidents; print(merge_incidents([{'id':1,'ended_at':'2023-01-01'},{'id':2,'ended_at':'2023-01-02'}], {'m1':'Name1','m2':'Name2'})[0]['id'])"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-get-incidents-as-its-own-router-crea]
- [ ] [T2] backend/app/routers/incident_feed.py — Add `router = APIRouter()` and `@router.get("/incidents")` endpoint that accepts `since: str | None = Query(None)` and `limit: int = Query(100, ge=1, le=1000)`, iterates `store.list()`, awaits `monitor_incidents(m.id)`, collects results, and returns `merge_incidents(...)`. VERIFY: `cd backend && python3 -c "from app.routers.incident_feed import router; print(router.routes[0].path)"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-get-incidents-as-its-own-router-crea]
- [ ] [T1] backend/tests/test_incident_feed_router.py — Create test file with `test_incident_feed_lists_incidents_across_monitors` that mounts `incident_feed.router` on a fresh `FastAPI()`, creates two monitors with failing then passing results, asserts response contains both incidents newest first with correct `monitor_name`, and calls `store.clear()`. VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_router.py -q -k test_incident_feed_lists_incidents_across_monitors`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-get-incidents-as-its-own-router-crea]

# --- 27B-decomposed from roadmap [2026-11-11]: Add `GET /incidents/summary` to the same router - in `backend/app/routers/incident_feed.py (review + tweak) [feat:shrike-monitor-20261111-add-get-incidents-summary-to-the-same-ro] ---
- [ ] [T1] backend/app/utils/incident_summary.py — Add pure function `summarize_incidents(incidents: list[dict], now: float) -> dict` that computes counts of ongoing incidents and mean time to recovery (MTTR) for resolved ones. VERIFY: `cd backend && python3 -m pytest tests/test_incident_summary.py -q`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-get-incidents-summary-to-the-same-ro]
- [ ] [T2] backend/app/routers/incident_feed.py — Import `summarize_incidents` from `backend.app.utils.incident_summary` and `time` module. VERIFY: `cd backend && python3 -c "from backend.app.routers.incident_feed import router; print('ok')"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-get-incidents-summary-to-the-same-ro]
- [ ] [T3] backend/app/routers/incident_feed.py — Add `GET /incidents/summary` route handler before any `/incidents/{...}` paths, fetching all incidents as dicts and returning `summarize_incidents(incidents, time.time())`. VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_router.py -q -k test_incident_summary_counts_ongoing_and_mttr`. (cat:endpoint; multifile:yes) [feat:shrike-monitor-20261111-add-get-incidents-summary-to-the-same-ro]
- [ ] [T1] backend/tests/test_incident_summary.py — Add unit tests for `summarize_incidents` covering empty list, all ongoing, and mixed resolved/ongoing scenarios with known timestamps. VERIFY: `cd backend && python3 -m pytest tests/test_incident_summary.py -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-get-incidents-summary-to-the-same-ro]
- [ ] [T2] backend/tests/test_incident_feed_router.py — Add `test_incident_summary_counts_ongoing_and_mttr` that mocks the incident store to return known data and asserts the endpoint returns correct ongoing count and MTTR. VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_router.py -q -k test_incident_summary_counts_ongoing_and_mttr`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-get-incidents-summary-to-the-same-ro]

# --- 27B-decomposed from roadmap [2026-11-11]: Wire the incident feed router into the app - in `backend/app/main.py` import `incident_fee (review + tweak) [feat:shrike-monitor-20261111-wire-the-incident-feed-router-into-the-a] ---
- [ ] [T1] backend/app/routers/incident_feed.py — Add a `@router.get("/summary")` endpoint returning `{"count": 0}` VERIFY: `cd backend && python3 -c "from app.routers.incident_feed import router; print([r.path for r in router.routes])"` shows `/incidents/summary`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261111-wire-the-incident-feed-router-into-the-a]
- [ ] [T1] backend/app/routers/incident_feed.py — Add `router = APIRouter(prefix="/incidents", tags=["incidents"])` and a placeholder `@router.get("")` endpoint returning `{"status": "ok"}` VERIFY: `cd backend && python3 -c "from app.routers.incident_feed import router; print([r.path for r in router.routes])"` shows `/incidents`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261111-wire-the-incident-feed-router-into-the-a]
- [ ] [T3] backend/app/main.py — Import `incident_feed` from `app.routers` and add `app.include_router(incident_feed.router)` immediately after the heartbeat router inclusion VERIFY: `cd backend && python3 -c "from app.main import app; paths = [r.path for r in app.routes]; assert '/incidents' in paths and '/incidents/summary' in paths"`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20261111-wire-the-incident-feed-router-into-the-a]
- [ ] [T2] backend/tests/test_incident_feed_wired.py — Create file with `test_incident_routes_registered_once` that imports `app` from `app.main`, extracts all route paths, and asserts `/incidents` and `/incidents/summary` each appear exactly once VERIFY: `cd backend && python3 -m pytest tests/test_incident_feed_wired.py -q -k test_incident_routes_registered_once`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-wire-the-incident-feed-router-into-the-a]

# --- 27B-decomposed from roadmap [2026-11-11]: Add an in-memory maintenance window store - create `backend/app/services/maintenance.py` w (review + tweak) [feat:shrike-monitor-20261111-add-an-in-memory-maintenance-window-stor] ---
- [ ] [T1] backend/app/services/maintenance.py — Add `MaintenanceWindows` class with `add`, `active`, `remove`, `list`, and `prune` methods plus module-level `windows` instance. VERIFY: `cd backend && python3 -c "from app.services.maintenance import windows; w = windows.add(None, 0, 100, 'test'); assert w['id'] and w['monitor_id'] is None"`. (cat:python; multifile:no) [feat:shrike-monitor-20261111-add-an-in-memory-maintenance-window-stor]
- [ ] [T2] backend/tests/test_maintenance_windows.py — Add `test_active_matches_fleet_wide_and_monitor_specific_windows` verifying `active` returns fleet-wide windows for specific monitors and excludes non-matching monitor-specific windows. VERIFY: `cd backend && python3 -m pytest tests/test_maintenance_windows.py::test_active_matches_fleet_wide_and_monitor_specific_windows -q`. (cat:test; multifile:no) [feat:shrike-monitor-20261111-add-an-in-memory-maintenance-window-stor]
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
