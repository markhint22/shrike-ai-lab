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
- [ ] [T5] backend/tests/test_utils.py — Ensure existing tests for `parse_comma_separated` cover the specific input patterns used by CORS configuration (e.g., "http://a.com, http://b.com"). VERIFY: python -m pytest backend/tests/test_utils.py -v. (cat:test; multifile:no)

# --- 27B-decomposed from roadmap [2026-09-18]: Five pure-math utility modules with full test coverage and zero production callers — `clam (review + tweak) ---
- [ ] [T1] backend/app/utils/clamp.py — Remove the `clamp` function and its docstring as it has zero production callers. VERIFY: `grep -r "from.*utils.clamp import" backend/app/ --include="*.py" | grep -v test_ | wc -l` returns 0. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_clamp.py — Delete the entire test file for the removed `clamp` utility. VERIFY: `test ! -f backend/tests/test_clamp.py`. (cat:test; multifile:no)
- [ ] [T1] backend/app/utils/ema.py — Remove the `ema` function and its docstring as it has zero production callers. VERIFY: `grep -r "from.*utils.ema import" backend/app/ --include="*.py" | grep -v test_ | wc -l` returns 0. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_ema.py — Delete the entire test file for the removed `ema` utility. VERIFY: `test ! -f backend/tests/test_ema.py`. (cat:test; multifile:no)
- [ ] [T1] backend/app/utils/mean_stdev.py — Remove the `mean_stdev` function and its docstring as it has zero production callers. VERIFY: `grep -r "from.*utils.mean_stdev import" backend/app/ --include="*.py" | grep -v test_ | wc -l` returns 0. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_mean_stdev.py — Delete the entire test file for the removed `mean_stdev` utility. VERIFY: `test ! -f backend/tests/test_mean_stdev.py`. (cat:test; multifile:no)
- [ ] [T1] backend/app/utils/pct_change.py — Remove the `pct_change` function and its docstring as it has zero production callers. VERIFY: `grep -r "from.*utils.pct_change import" backend/app/ --include="*.py" | grep -v test_ | wc -l` returns 0. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_pct_change.py — Delete the entire test file for the removed `pct_change` utility. VERIFY: `test ! -f backend/tests/test_pct_change.py`. (cat:test; multifile:no)
- [ ] [T1] backend/app/utils/round_sig.py — Remove the `round_sig` function and its docstring as it has zero production callers. VERIFY: `grep -r "from.*utils.round_sig import" backend/app/ --include="*.py" | grep -v test_ | wc -l` returns 0. (cat:refactor; multifile:no)
- [ ] [T1] backend/tests/test_round_sig.py — Delete the entire test file for the removed `round_sig` utility. VERIFY: `test ! -f backend/tests/test_round_sig.py`. (cat:test; multifile:no)
