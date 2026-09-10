# Grooming proposal — shrike-monitor — 2026-09-07 04:00

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
- [ ] [AUTO-SKIP after 4 no-op cycles — already-done, mis-targeted, or beyond the 27B; review] [T2] Add TestClient tests for monitor CRUD in backend/tests/test_monitors_api.py (201 create, 200 get, 404 unknown, list, 204 delete, 404 delete-unknown)
```

## Proposed (LLM re-evaluation — review before applying)
1. Add `worst_status` helper in backend/app/models.py returning the worst of a list of statuses (down>degraded>up>pending) and add corresponding unit tests
2. Add `latency_stats` helper in backend/app/models.py calculating min/avg/max/p95 over ok results' latency_ms (ignoring None) and add corresponding unit tests
3. Add `consecutive_failures` helper in backend/app/models.py counting trailing non-ok results and add corresponding unit tests
4. Add `should_alert` helper in backend/app/models.py returning True when consecutive_failures >= threshold with up->down transition and add corresponding unit tests
5. Add validation to `MonitorCreate` in backend/app/schemas.py requiring url to be non-empty when type=="http" using a model validator and add a test
6. Add a URL scheme check in backend/app/schemas.py ensuring http monitor urls start with http:// or https:// and add a test
7. Add tests for `Store.results` limit argument and empty-monitor behavior in backend/app/store.py
8. Add `Store.record_probe` convenience method (records + trims) and `Store.latest(monitor_id)` method in backend/app/store.py with corresponding tests
9. Add TestClient tests for monitor CRUD endpoints in backend/tests/test_monitors_api.py covering 201 create, 200 get, 404 unknown, list, 204 delete, and 404 delete-unknown
