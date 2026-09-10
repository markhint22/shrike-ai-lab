# Grooming proposal — shrike-monitor — 2026-09-05 04:00

## Deterministically stale (target file already gone — safe to drop)
```
- [ ] [AUTO-SKIP after 4 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [T2] Add TestClient tests for monitor CRUD in backend/tests/test_monitors_api.py (201 create, 200 get, 404 unknown, list, 204 delete, 404 delete-unknown)
```

## Current Next Steps
```
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `Monitor.to_dict` and `CheckResult.to_dict` in backend/app/models.py (round-trip all fields)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add tests for `classify_http` boundary in backend/app/models.py (latency exactly == degraded_latency_ms -> degraded; a None latency but ok -> up)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add tests for `heartbeat_overdue` boundary in backend/app/models.py (now exactly at interval+grace -> not overdue; one second past -> overdue)
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `worst_status` helper in backend/app/models.py returning the worst of a list of statuses (down>degraded>up>pending) + tests
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `latency_stats` helper in backend/app/models.py (min/avg/max/p95 over the ok results' latency_ms, ignoring None) + tests
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `consecutive_failures` helper in backend/app/models.py (count trailing non-ok results) + tests
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `should_alert` helper in backend/app/models.py (True when consecutive_failures >= a threshold, transitioning up->down) + tests
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add validation to `MonitorCreate` in backend/app/schemas.py requiring url to be non-empty when type=="http" (model validator) + a test
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T1] Add a `pattern`/scheme check that http monitor urls start with http:// or https:// in backend/app/schemas.py + a test
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add tests for `Store.results` limit argument and empty-monitor behavior in backend/app/store.py
- [ ] [HUMAN-ONLY BLOCKED ITEM — auto-skipped after 3 failed cycles; needs a human] [T2] Add a `Store.record_probe` convenience that records + trims, and a `Store.latest(monitor_id)` returning the most recent result or None, in backend/app/store.py + tests
- [x] [T2] Add a `Store.count()` and `Store.exists(id)` helper in backend/app/store.py + tests
- [x] [T2] Add a module logger to backend/app/services/checker.py and log a probe failure at warning level (url + error)
- [x] [T2] Add an `ok_status_codes` set option to `probe` in backend/app/services/checker.py (explicit allowed codes overrides the range) + tests
- [x] [T2] Add a `probe` timeout param that builds the httpx.Timeout in backend/app/services/checker.py (currently hardcoded 10s) + a test using an injected fetch
- [ ] [AUTO-SKIP after 4 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [T2] Add TestClient tests for monitor CRUD in backend/tests/test_monitors_api.py (201 create, 200 get, 404 unknown, list, 204 delete, 404 delete-unknown)
- [x] [T2] Add a `GET /status` summary endpoint returning counts of monitors by status, in backend/app/routers/monitors.py + a test
- [x] [T2] Add an `is_due(monitor, now, last_checked_at)` pure helper (for the scheduler) in backend/app/models.py + tests
- [x] [T2] Add `incident` tracking: a pure `detect_incidents(results)` that returns (start,end) down-periods from a result list, in backend/app/models.py + tests
- [x] [T2] Add a `Health.extra` with monitor count + uptime seconds in the /health handler in backend/app/main.py + a test
- [x] [T2] Add a `.ovn-verify.sh` at repo root running `cd backend && .venv/bin/pytest -q` so the overnight gate verifies this repo
- [ ] [T2] Guard `probe` against a fetch returning a non-int (defensive) in backend/app/services/checker.py + a test
- [x] (already-satisfied in code, implement-verified) [T2] Add a `max_length` bound + trim to CheckResult.error at construction time (helper in models.py) + tests
```

## Proposed (LLM re-evaluation — review before applying)
1. Add tests for `Monitor.to_dict` and `CheckResult.to_dict` in backend/app/models.py (round-trip all fields)
2. Add tests for `classify_http` boundary in backend/app/models.py (latency exactly == degraded_latency_ms -> degraded; a None latency but ok -> up)
3. Add tests for `heartbeat_overdue` boundary in backend/app/models.py (now exactly at interval+grace -> not overdue; one second past -> overdue)
4. Add a `worst_status` helper in backend/app/models.py returning the worst of a list of statuses (down>degraded>up>pending) + tests
5. Add a `latency_stats` helper in backend/app/models.py (min/avg/max/p95 over the ok results' latency_ms, ignoring None) + tests
6. Add a `consecutive_failures` helper in backend/app/models.py (count trailing non-ok results) + tests
7. Add a `should_alert` helper in backend/app/models.py (True when consecutive_failures >= a threshold, transitioning up->down) + tests
8. Add validation to `MonitorCreate` in backend/app/schemas.py requiring url to be non-empty when type=="http" (model validator) + a test
9. Add a `pattern`/scheme check that http monitor urls start with http:// or https:// in backend/app/schemas.py + a test
10. Add tests for `Store.results` limit argument and empty-monitor behavior in backend/app/store.py
11. Add a `Store.record_probe` convenience that records + trims, and a `Store.latest(monitor_id)` returning the most recent result or None, in backend/app/store.py + tests
12. Guard `probe` against a fetch returning a non-int (defensive) in backend/app/services/checker.py + a test
13. Add TestClient tests for monitor CRUD in backend/tests/test_monitors_api.py (201 create, 200 get, 404 unknown, list, 204 delete, 404 delete-unknown)
14. Add a `GET /health` endpoint returning service version and uptime in backend/app/routers/monitors.py + a test
15. Add a `POST /heartbeat/{monitor_id}` endpoint to record manual heartbeats in backend/app/routers/heartbeat.py + a test
