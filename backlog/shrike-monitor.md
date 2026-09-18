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
- [ ] [T1] backend/app/utils/alert_key.py — Refactor `alert_key` to accept a generic `incident_id` parameter (str/int) and document that it can be a timestamp or counter, ensuring backward compatibility with existing string inputs. VERIFY: python -m pytest backend/tests/test_alert_key.py -v. (cat:python; multifile:no)
- [ ] [T2] backend/app/services/scheduler.py — Add an `incident_id` field to the internal state tracking in `MonitorScheduler` (e.g., `_current_incident_id`) that increments or updates on every status transition, and expose it via a helper method `get_current_incident_id(monitor_id)`. VERIFY: python -m pytest backend/tests/test_scheduler.py -v. (cat:python; multifile:no)
- [ ] [T3] backend/app/services/scheduler.py — Modify the logic that triggers `Notifier.notify_transition` to pass the current `incident_id` retrieved from the scheduler state as a new argument. VERIFY: python -m pytest backend/tests/test_scheduler.py -v. (cat:python; multifile:no)
- [ ] [T4] backend/app/services/notifier.py — Update `Notifier.notify_transition` signature to accept an `incident_id` parameter and update the internal `_last_notified` dictionary keys to use `alert_key(monitor_id, new_status, incident_id)` instead of just `monitor_id`. VERIFY: python -m pytest backend/tests/test_notifier.py -v. (cat:python; multifile:no)
- [ ] [T5] backend/tests/test_notifier.py — Add a regression test `test_distinct_incidents_same_status_not_deduped` that simulates a down->up->down->up sequence on the same monitor with distinct incident IDs, asserting that both "up" notifications are sent. VERIFY: python -m pytest backend/tests/test_notifier.py::test_distinct_incidents_same_status_not_deduped -v. (cat:test; multifile:no)
- [ ] [T3] backend/app/main.py — Ensure the application startup or dependency injection context correctly initializes the `MonitorScheduler` and `Notifier` instances so that the new `incident_id` flow is active in the production runtime. VERIFY: python -m pytest backend/tests/test_core.py -v. (cat:python; multifile:no)
