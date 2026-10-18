#!/usr/bin/env bash
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="$(command -v python3.12 || command -v python3)"
"$PY" "$HERE/test_ovn_needs_research_promote.py"
