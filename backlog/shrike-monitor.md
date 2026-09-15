# shrike-monitor — RELEASE-READINESS backlog (27B-friendly), release-blockers FIRST
# TOP blocker: heartbeat monitors never report "down" when overdue (status endpoint uses
# summarize_status for all types). The first 3 items fix that.

- [ ] [T2] backend/app/config.py — new module with a Settings reading env via os.environ (no new dep): SERVICE_VERSION default "0.1.0", MAX_RESULTS int default 100, MAX_MONITORS int default 1000, CORS_ORIGINS comma-split to list default ["*"]. VERIFY: test with monkeypatched env asserts parsed values, and asserts defaults when unset. (polish:config)
- [ ] [T2] backend/app/logging_config.py — new module with configure_logging(level="INFO") that installs a timestamped formatter on a handler and returns the "shrike-monitor" logger, idempotently (no duplicate handlers on repeat calls). VERIFY: call twice; assert logger.level == logging.INFO and handler count does not grow between calls. (polish:logging)
- [ ] [T1] backend/app/version.py — new module defining __version__ = "0.1.0". VERIFY: from app.version import __version__; assert isinstance(__version__, str) and __version__. (polish:release)

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
- [ ] [T2] backend/app/routers/monitors.py — Import `sla_met` from `backend.app.utils.sla_met` and add `sla_target: float | None = Query(None, ge=0.0, le=1.0)` parameter to `monitor_status()`. VERIFY: grep -n "sla_target" backend/app/routers/monitors.py && grep -n "from backend.app.utils.sla_met import sla_met" backend/app/routers/monitors.py (cat:endpoint; multifile:no)
- [ ] [T3] backend/app/routers/monitors.py — In `monitor_status()`, compute `sla_met_value = sla_met(results, sla_target) if sla_target is not None else None` and pass it to `StatusOut`. VERIFY: python -m pytest backend/tests/test_monitors_status_api.py::test_status_sla_met_with_target -v (cat:endpoint; multifile:no)
- [ ] [T4] backend/tests/test_monitors_status_api.py — Add test `test_status_sla_met_with_target` that mocks a monitor with 100% uptime, calls `/monitors/{id}/status?sla_target=0.95`, and asserts `response.json()["sla_met"] is True`. VERIFY: python -m pytest backend/tests/test_monitors_status_api.py::test_status_sla_met_with_target -v (cat:test; multifile:no)
- [ ] [T5] backend/tests/test_monitors_status_api.py — Add test `test_status_sla_met_without_target` that calls `/monitors/{id}/status` without query params and asserts `response.json()["sla_met"] is None`. VERIFY: python -m pytest backend/tests/test_monitors_status_api.py::test_status_sla_met_without_target -v (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Delete dead duplicate is_overdue() heartbeat helper — `app/services/heartbeat.py`'s `is_ov (review + tweak) ---
- [ ] [T1] backend/tests/test_heartbeat.py — Remove the file entirely as it tests the dead `is_overdue` helper. VERIFY: `test -f backend/tests/test_heartbeat.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T2] backend/app/services/heartbeat.py — Remove the file entirely as it contains the duplicate `is_overdue` logic. VERIFY: `test -f backend/app/services/heartbeat.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no)
- [ ] [T3] backend/app/services/__init__.py — Remove any imports or exports of `is_overdue` or the `heartbeat` service module if present. VERIFY: `grep -r "from .heartbeat import\|from app.services.heartbeat import" backend/ && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no)
- [ ] [T4] backend/tests/test_core.py — Ensure no indirect imports of the deleted module exist in core integration tests. VERIFY: `grep -r "services.heartbeat\|is_overdue" backend/tests/test_core.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T5] backend/tests/test_scheduler.py — Verify scheduler tests do not rely on the deleted service module for heartbeat logic. VERIFY: `grep -r "services.heartbeat\|is_overdue" backend/tests/test_scheduler.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Delete dead duplicate consecutive_failures(list[bool]) util — `app/utils/consecutive_failu (review + tweak) ---
- [ ] [T4] backend/app/utils/consecutive_failures.py — Delete the file containing the dead `consecutive_failures` utility. VERIFY: `test -f backend/app/utils/consecutive_failures.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no)
- [ ] [T4] backend/tests/test_consecutive_failures.py — Delete the test file for the removed utility. VERIFY: `test -f backend/tests/test_consecutive_failures.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T3] backend/app/utils/__init__.py — Remove any import or export of `consecutive_failures` if present to prevent import errors. VERIFY: `grep -q "consecutive_failures" backend/app/utils/__init__.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:no)
- [ ] [T3] backend/tests/test_core.py — Verify no references to the deleted utils version remain in core tests. VERIFY: `grep -q "from app.utils.consecutive_failures import" backend/tests/test_core.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T3] backend/tests/test_models.py — Verify no references to the deleted utils version remain in model tests. VERIFY: `grep -q "from app.utils.consecutive_failures import" backend/tests/test_models.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T3] backend/app/services/scheduler.py — Confirm scheduler still imports and uses `app.models.consecutive_failures` exclusively. VERIFY: `grep -q "from app.models import consecutive_failures" backend/app/services/scheduler.py && echo "PASS" || echo "FAIL"`. (cat:refactor; multifile:no)
- [ ] [T3] backend/app/models.py — Confirm `app.models.consecutive_failures` remains intact and is the active implementation. VERIFY: `grep -q "def consecutive_failures" backend/app/models.py && echo "PASS" || echo "FAIL"`. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_refactor_cleanup.py — Add a test asserting `app.utils.consecutive_failures` module does not exist. VERIFY: `cd backend && python -m pytest tests/test_refactor_cleanup.py -v`. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-14]: Delete two dead duplicate HTTP-status classifiers — `app/services/checker.py`'s `classify_ (review + tweak) ---
- [ ] [T2] backend/tests/test_core.py — Remove the test case(s) specifically targeting `classify_status` from `app.services.checker`, ensuring other tests in the file remain intact. VERIFY: `grep -q "classify_status" backend/tests/test_core.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T2] backend/tests/test_service_helpers.py — Remove the test case(s) specifically targeting `http_status` from `app.services.classify`, ensuring other tests in the file remain intact. VERIFY: `grep -q "http_status" backend/tests/test_service_helpers.py && echo "FAIL" || echo "PASS"`. (cat:test; multifile:no)
- [ ] [T4] backend/app/services/checker.py — Delete the function definition `classify_status(code)` and any imports solely used by it. VERIFY: `grep -q "def classify_status" backend/app/services/checker.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:yes)
- [ ] [T4] backend/app/services/classify.py — Delete the function definition `http_status(code, latency_ms, degraded_ms)` and any imports solely used by it. VERIFY: `grep -q "def http_status" backend/app/services/classify.py && echo "FAIL" || echo "PASS"`. (cat:refactor; multifile:yes)
- [ ] [T3] backend/app/services/checker.py — Ensure the module imports and remaining logic do not reference the deleted `classify_status` function. VERIFY: `python -c "import backend.app.services.checker"`. (cat:python; multifile:no)
- [ ] [T3] backend/app/services/classify.py — Ensure the module imports and remaining logic do not reference the deleted `http_status` function. VERIFY: `python -c "import backend.app.services.classify"`. (cat:python; multifile:no)
- [ ] [T1] backend/tests/test_core.py — Verify that the remaining tests in `test_core.py` pass after removing `classify_status` tests. VERIFY: `pytest backend/tests/test_core.py -v`. (cat:test; multifile:no)
- [ ] [T1] backend/tests/test_service_helpers.py — Verify that the remaining tests in `test_service_helpers.py` pass after removing `http_status` tests. VERIFY: `pytest backend/tests/test_service_helpers.py -v`. (cat:test; multifile:no)
