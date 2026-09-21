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
- [ ] [T1] backend/app/config.py — Add `api_token: str = ""` field to `Settings` class with env var name `MONITOR_API_TOKEN`. VERIFY: `python -c "from backend.app.config import Settings; s=Settings(); assert hasattr(s, 'api_token') and s.api_token == ''"`. (cat:schema; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
- [ ] [T1] backend/app/utils/auth.py — Add `verify_bearer_token(request, expected_token)` function that returns `True` if `expected_token` is empty or matches the request's `Authorization: Bearer <token>` header using `secrets.compare_digest`, else `False`. VERIFY: `python -m pytest backend/tests/test_auth.py::test_verify_bearer_token -v`. (cat:python; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
- [ ] [T2] backend/tests/test_auth.py — Add unit tests for `verify_bearer_token` covering: empty expected token (no-op), valid token match, invalid token mismatch, missing header, and non-bearer scheme. VERIFY: `python -m pytest backend/tests/test_auth.py::test_verify_bearer_token -v`. (cat:test; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
- [ ] [T3] backend/app/routers/monitors.py — Add `Depends(verify_api_token)` to all routes in the router (`POST /`, `DELETE /{id}`, `GET /`, `GET /{id}`, etc.) where `verify_api_token` is a FastAPI dependency that raises `HTTPException(401)` if `verify_bearer_token` returns `False`. VERIFY: `python -m pytest backend/tests/test_monitors_auth.py -v`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
- [ ] [T3] backend/app/routers/monitors.py — Ensure the dependency is defined or imported correctly such that it accesses `request.headers` and `Settings.api_token` via `get_settings()`. VERIFY: `grep -n "verify_api_token" backend/app/routers/monitors.py | wc -l` returns count > 0. (cat:endpoint; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
- [ ] [T2] backend/tests/test_monitors_auth.py — Add integration tests using `TestClient`: 1) Set `MONITOR_API_TOKEN=test_token`, send request without header, expect 401; 2) Send with correct header, expect 200; 3) Set `MONITOR_API_TOKEN=""`, send without header, expect 200. VERIFY: `python -m pytest backend/tests/test_monitors_auth.py -v`. (cat:test; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
- [ ] [T4] backend/app/routers/heartbeat.py — Verify that heartbeat routes do NOT use the new monitor auth dependency (they should remain open or use their own ping-token logic if any, but per spec, only `/monitors*` is gated). VERIFY: `grep -L "verify_api_token" backend/app/routers/heartbeat.py`. (cat:endpoint; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
- [ ] [T2] backend/tests/test_config_api_token.py — Add test verifying `Settings` loads `MONITOR_API_TOKEN` from environment correctly and defaults to empty string. VERIFY: `python -m pytest backend/tests/test_config_api_token.py -v`. (cat:test; multifile:no) [feat:shrike-monitor-20260921-add-bearer-token-authentication-protecti]
