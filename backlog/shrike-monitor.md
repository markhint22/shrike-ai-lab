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
- [ ] [T1] backend/app/services/checker.py — Remove the dead `notifier=None, monitor_id: str = "unknown", monitor_name: str = "unknown", old_status: str = "pending"` parameters from `probe()`'s signature; the only real production caller, `MonitorScheduler.tick()` in backend/app/services/scheduler.py, never passes them. VERIFY: `! grep -q "notifier=None" backend/app/services/checker.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-checker-probe-dead-notifier-branch-v2]

# --- 27B-decomposed from roadmap [2026-09-22 refill]: two dead time-math helpers in `app/services/scheduler.py`, on top of the already-tracked debounce/should_alert item (review + tweak) [feat:shrike-monitor-20260922-scheduler-dead-time-math-helpers] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: two independent dead implementations of the "rows to prune" calculation, neither one actually used by the pruning that ships (review + tweak) [feat:shrike-monitor-20260922-dead-prune-threshold-duplicates] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: four dead pure-math utility modules with full test coverage and zero production callers (review + tweak) [feat:shrike-monitor-20260922-dead-pure-math-utils] ---

# --- 27B-decomposed from roadmap [2026-09-22 refill]: four more dead single-caller-is-its-own-test functions (worst_status, record_probe, verify_token, duplicate uptime_ratio) (review + tweak) [feat:shrike-monitor-20260922-misc-dead-functions] ---
- [ ] [T1] backend/app/main.py — Delete the dead `async def verify_token(monitor_id: str, token: str | None = None) -> None` function; confirmed via grep its only reference repo-wide outside its own definition is `test_verify_token_behavior` in backend/tests/test_ping_token.py — the real heartbeat ping-token check lives inline in `app/routers/heartbeat.py::ping()` and never calls `main.verify_token`. VERIFY: `! grep -q "async def verify_token" backend/app/main.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-misc-dead-functions]
- [ ] [T1] backend/tests/test_ping_token.py — Delete `test_verify_token_behavior()`, the only caller of the now-deleted `app.main.verify_token`, and add a regression assertion proving it is gone from `app.main`'s namespace: `assert not hasattr(main_module, "verify_token")`. VERIFY: `cd backend && .venv/bin/pytest tests/test_ping_token.py -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-misc-dead-functions]
- [ ] [T1] backend/app/utils/uptime.py — Delete this entire module (`uptime_ratio(results: list[CheckResult]) -> float`); it is a functionally-identical duplicate of the wired `app.models.uptime_ratio()`, which every real caller (`routers/monitors.py`'s `/status` endpoints) actually uses — confirmed via grep this module's only reference repo-wide outside its own definition is its dedicated test file, backend/tests/test_uptime.py. VERIFY: `test ! -f backend/app/utils/uptime.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-misc-dead-functions]
- [ ] [T1] backend/tests/test_uptime.py — Delete this entire test file; it exists solely to test the now-deleted `app/utils/uptime.py`. VERIFY: `test ! -f backend/tests/test_uptime.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-misc-dead-functions]

# --- 27B-decomposed from roadmap [2026-09-22 refill]: `app/utils/backoff.py` misplaced-docstring bug + `Settings.scheduler_tick_seconds` missing a non-positive-value guard (review + tweak) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard] ---
- [ ] [T1] backend/app/utils/backoff.py — Move the stray string literal `"""Exponential backoff with jitter for retry logic."""` from the LAST line of the file (after `calculate_backoff_delay()`'s `return`, where Python evaluates and discards it as a no-op expression) to the very FIRST line of the file, before `import random`, so it becomes the real module docstring. VERIFY: `python3 -c "import sys; sys.path.insert(0, 'backend'); import app.utils.backoff as m; assert m.__doc__ and 'backoff' in m.__doc__.lower()"`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]
- [ ] [T1] backend/app/utils/backoff.py — Delete the now-duplicate trailing copy of the docstring string literal at the bottom of the file; the text must appear exactly once, at the top. VERIFY: `test $(grep -c "Exponential backoff with jitter for retry logic" backend/app/utils/backoff.py) -eq 1`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]
- [ ] [T2] backend/tests/test_backoff.py — Add one regression assertion that `app.utils.backoff.__doc__` is now the expected non-None string, guarding against this docstring-placement bug regressing. VERIFY: `cd backend && .venv/bin/pytest tests/test_backoff.py -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]
- [ ] [T2] backend/app/config.py — Add a `@field_validator("scheduler_tick_seconds", mode="before")` (a new validator, since `_fallback_invalid_int` is int-specific and this field is a `float`) that falls back to the field default (5.0) when the env value is unparseable as a float or is non-positive, matching the "never crash startup on bad config" contract already documented for `max_results`/`max_monitors`/`alert_threshold`. VERIFY: `grep -q "scheduler_tick_seconds" backend/app/config.py && grep -c "field_validator" backend/app/config.py | grep -qE "^[3-9]$|^[1-9][0-9]+$"`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]
- [ ] [T2] backend/tests/test_config.py — Add a regression test asserting `Settings(SCHEDULER_TICK_SECONDS="0").scheduler_tick_seconds == 5.0` (a non-positive value falls back to the default). VERIFY: `cd backend && .venv/bin/pytest tests/test_config.py -k scheduler_tick -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]
- [ ] [T2] backend/tests/test_config.py — Add a regression test asserting `Settings(SCHEDULER_TICK_SECONDS="not-a-number").scheduler_tick_seconds == 5.0` (an unparseable value falls back to the default), matching the existing boundary-test style already in this suite. VERIFY: `cd backend && .venv/bin/pytest tests/test_config.py -k scheduler_tick -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]
- [ ] [T2] backend/tests/test_config.py — Add a regression test asserting a valid positive value passes through unchanged, e.g. `Settings(SCHEDULER_TICK_SECONDS="10.5").scheduler_tick_seconds == 10.5`, so the new validator only rejects bad input and never mangles a good one. VERIFY: `cd backend && .venv/bin/pytest tests/test_config.py -k scheduler_tick -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]
- [ ] [T2] backend/app/config.py — Run the full config and scheduler test suites together to confirm the new validator doesn't break `MonitorScheduler.__init__`'s existing `tick_seconds=settings.scheduler_tick_seconds` wiring in backend/app/main.py or any existing test that constructs `Settings()` directly. VERIFY: `cd backend && .venv/bin/pytest tests/test_config.py tests/test_scheduler.py -v`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-backoff-docstring-and-tick-seconds-guard]

# --- 27B-decomposed from roadmap [2026-09-22 refill]: dead `humanize_bytes()` and orphaned `humanize_count.py` (relocated reincarnation of an already-flagged pattern, distinct from the already-queued app/utils/auth.py item) (review + tweak) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count] ---
- [ ] [T1] backend/app/utils/humanize.py — Delete the dead `humanize_bytes(num: float) -> str` function; confirmed via grep it has zero callers anywhere under backend/app/ outside its own definition — unlike its sibling `humanize_seconds()` in `app/utils/duration.py`, which IS wired into `Notifier.notify_transition()`, nothing in this codebase currently displays a byte count on any schema or endpoint. VERIFY: `! grep -q "def humanize_bytes" backend/app/utils/humanize.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
- [ ] [T1] backend/tests/test_utils.py — Delete the humanize_bytes test block (8 `test_humanize_bytes_*` cases) and its `from app.utils.humanize import humanize_bytes` import, now that the function is deleted. VERIFY: `! grep -q "humanize_bytes" backend/tests/test_utils.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
- [ ] [T1] backend/app/utils/humanize_count.py — Delete this entire module (`humanize_count(n: int) -> str`); confirmed via grep it has zero test coverage anywhere in backend/tests/ (no `test_humanize_count*` case exists) and its only "caller" is an unused re-export in app/utils/__init__.py. VERIFY: `test ! -f backend/app/utils/humanize_count.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
- [ ] [T1] backend/app/utils/__init__.py — Remove the now-broken `from app.utils.humanize_count import humanize_count  # noqa: E402,F401` re-export line, since the module it imports from was just deleted. VERIFY: `! grep -q "humanize_count" backend/app/utils/__init__.py`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
- [ ] [T2] backend/tests/test_utils.py — Add a regression assertion, matching this repo's established `test_no_X_export` precedent, proving both `humanize_bytes` and `humanize_count` are gone from `app.utils`'s namespace. VERIFY: `cd backend && .venv/bin/pytest tests/test_utils.py -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
- [ ] [T2] backend/app/utils/humanize.py — Confirm no other file in the repo still imports either deleted name after both deletions land. VERIFY: `! grep -rn "humanize_bytes\|humanize_count" backend/app`. (cat:python; multifile:yes) [feat:shrike-monitor-20260922-dead-humanize-bytes-and-count]
