# Grooming proposal — shrike-monitor — 2026-09-10 04:00

## Current Next Steps
```
- [x] [T1] Add tests for `Monitor.to_dict` and `CheckResult.to_dict` in backend/app/models.py (round-trip all fields)
- [x] [T1] Add tests for `classify_http` boundary in backend/app/models.py (latency exactly == degraded_latency_ms -> degraded; a None latency but ok -> up)
- [x] (already-satisfied in code, implement-verified) [T2] Add tests for `heartbeat_overdue` boundary in backend/app/models.py (now exactly at interval+grace -> not overdue; one second past -> overdue)
- [x] (already-satisfied in code, implement-verified) [T2] Add a `worst_status` helper in backend/app/models.py returning the worst of a list of statuses (down>degraded>up>pending) + tests
- [x] (already-satisfied in code, implement-verified) [T2] Add a `latency_stats` helper in backend/app/models.py (min/avg/max/p95 over the ok results' latency_ms, ignoring None) + tests
- [x] [T2] Add a `consecutive_failures` helper in backend/app/models.py (count trailing non-ok results) + tests
- [x] (already-satisfied in code, implement-verified) [T2] Add a `should_alert` helper in backend/app/models.py (True when consecutive_failures >= a threshold, transitioning up->down) + tests
- [x] [T1] Add validation to `MonitorCreate` in backend/app/schemas.py requiring url to be non-empty when type=="http" (model validator) + a test
- [x] [T1] Add a `pattern`/scheme check that http monitor urls start with http:// or https:// in backend/app/schemas.py + a test
- [x] [T2] Add tests for `Store.results` limit argument and empty-monitor behavior in backend/app/store.py
- [x] (already-satisfied in code, implement-verified) [T2] Add a `Store.record_probe` convenience that records + trims, and a `Store.latest(monitor_id)` returning the most recent result or None, in backend/app/store.py + tests
- [x] [AUTO-SKIP after 4 failed-to-land cycles — kept reverting (already-done, too hard for the 27B, or a sibling-file gate fail); review — NOT necessarily human-only] [HUMAN] [T1] backend/app/main.py — pass a description and license_info to FastAPI(...) for a complete OpenAPI doc. VERIFY: GET /openapi.json → json["info"]["description"] is a non-empty string. (polish:docs)  <!-- superseded by recovery decomposition below -->
- [x] (already-satisfied in code, implement-verified) [T1] backend/app/main.py — Add `description="Shrike Monitor API"` and `license_info={"name": "MIT"}` arguments to the `FastAPI(...)` instantiation. VERIFY: `curl -s http://localhost:8000/openapi.json | jq '.info.description'` returns `"Shrike Monitor API"`. (cat:docs; recovery:decomposed)
```

## Proposed (LLM re-evaluation — review before applying)
1. Add a `Store.get_monitor` method in backend/app/store.py to retrieve a single monitor by ID, returning None if not found, and add a unit test for it.
2. Implement a `calculate_uptime_percentage` helper in backend/app/utils/uptime.py that takes a list of CheckResults and a time window, returning the percentage of 'up' status, with tests for edge cases (empty list, all down).
3. Add a `validate_interval` function in backend/app/schemas.py to ensure monitor check intervals are >= 30 seconds, raising a ValueError if violated, and add a test case.
