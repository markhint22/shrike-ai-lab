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
