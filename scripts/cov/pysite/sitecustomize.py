# Starts coverage.py in EVERY python process of the test run when COVERAGE_PROCESS_START is set (subprocess coverage).
try:
    import coverage
    coverage.process_startup()
except Exception:
    pass
