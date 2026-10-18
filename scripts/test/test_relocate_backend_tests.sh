#!/usr/bin/env bash
# Wrapper so run_all.sh executes test_relocate_backend_tests.py (backend/-rooted pytest layout ghost-test relocation, 2026-10-18).
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_relocate_backend_tests.py"
