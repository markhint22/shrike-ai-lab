#!/usr/bin/env bash
# Regression test: queue_refill.py must relocate NEW test files that an item places outside the repo's collected test dir (2026-10-08).
# Incident: planner items named new tests in iptv-backend/app/jobs/; pytest never collects that dir, so the fleet shipped 8 uncollected test files and a
# placeholder `assert True` file that held 235 commits at the enforcing antigaming gate for 17h.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
PY="${OVN_QUEUE_REFILL_PY:-$HERE/../../queue_refill.py}"
[ -f "$PY" ] || PY="$HOME/overnight-queue/queue_refill.py"
[ -f "$PY" ] || { echo "  SKIP: queue_refill.py not found"; exit 0; }
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- iptv-shaped repo: collected dir is iptv-backend/tests/
r="$tmp/iptv"; mkdir -p "$r/iptv-backend/tests" "$r/iptv-backend/app/jobs"
echo "x = 1" > "$r/iptv-backend/app/jobs/existing_job.py"
echo "def test_old(): assert 1" > "$r/iptv-backend/app/jobs/test_existing_in_jobs.py"   # an EXISTING stray test file: never moved
: > "$r/OVERNIGHT_PROGRESS.md"; : > "$r/OVERNIGHT_DONE.md"
cat > "$tmp/bl1.md" <<'EOT'
- [ ] [T2] iptv-backend/app/jobs/test_new_thing.py — Add a test for the new job. VERIFY: `pytest iptv-backend/app/jobs/test_new_thing.py -v`
- [ ] [T2] iptv-backend/app/jobs/existing_job.py — Wire it. Also add iptv-backend/app/services/new_thing_test.py. VERIFY: `pytest iptv-backend/app/services/new_thing_test.py`
- [ ] [T2] iptv-backend/tests/test_already_ok.py — Already in the collected dir. VERIFY: `pytest iptv-backend/tests/test_already_ok.py`
- [ ] [T2] iptv-backend/app/jobs/test_existing_in_jobs.py — Extend an existing stray test. VERIFY: `pytest iptv-backend/app/jobs/test_existing_in_jobs.py`
EOT
out="$(python3 "$PY" "$r/OVERNIGHT_PROGRESS.md" "$tmp/bl1.md" 10)"
prog="$(cat "$r/OVERNIGHT_PROGRESS.md")"
ok "reports the relocation count" "printf '%s' \"\$out\" | grep -q 'RELOCATED_TESTS=2'"
ok "a NEW test in app/jobs is rewritten to iptv-backend/tests/ in the path AND the VERIFY" "printf '%s' \"\$prog\" | grep -q 'iptv-backend/tests/test_new_thing.py — Add a test' && printf '%s' \"\$prog\" | grep -q 'pytest iptv-backend/tests/test_new_thing.py -v'"
ok "no trace of the old uncollected path remains for that item" "! printf '%s' \"\$prog\" | grep -q 'app/jobs/test_new_thing.py'"
ok "a *_test.py name in app/services is relocated too" "printf '%s' \"\$prog\" | grep -q 'iptv-backend/tests/new_thing_test.py'"
ok "the non-test file in the same line is NOT touched" "printf '%s' \"\$prog\" | grep -q 'iptv-backend/app/jobs/existing_job.py — Wire it'"
ok "NEGATIVE: an item already in the collected dir is unchanged" "printf '%s' \"\$prog\" | grep -q 'iptv-backend/tests/test_already_ok.py — Already in the collected dir'"
ok "NEGATIVE: an EXISTING stray test file is never moved" "printf '%s' \"\$prog\" | grep -q 'iptv-backend/app/jobs/test_existing_in_jobs.py — Extend'"
ok "the original (unrelocated) lines are removed from the backlog, nothing duplicated" "[ \"\$(grep -c 'test_new_thing' \"$tmp/bl1.md\")\" = 0 ]"

# --- godot-shaped repo: collected dir is tests/
g="$tmp/gd"; mkdir -p "$g/tests" "$g/scripts/battle"; : > "$g/project.godot"
: > "$g/OVERNIGHT_PROGRESS.md"; : > "$g/OVERNIGHT_DONE.md"
cat > "$tmp/bl2.md" <<'EOT'
- [ ] [T2] scripts/battle/test_overwatch.gd — Write the test. VERIFY: `grep -q test_ok scripts/battle/test_overwatch.gd`
EOT
python3 "$PY" "$g/OVERNIGHT_PROGRESS.md" "$tmp/bl2.md" 5 >/dev/null
ok "godot repo: a new test .gd outside tests/ is relocated to tests/" "grep -q 'tests/test_overwatch.gd — Write the test' \"$g/OVERNIGHT_PROGRESS.md\" && ! grep -q 'scripts/battle/test_overwatch.gd' \"$g/OVERNIGHT_PROGRESS.md\""

# --- unknown repo shape: nothing rewritten
u="$tmp/other"; mkdir -p "$u"; : > "$u/OVERNIGHT_PROGRESS.md"; : > "$u/OVERNIGHT_DONE.md"
echo '- [ ] [T2] lib/test_x.py — a test. VERIFY: `true`' > "$tmp/bl3.md"
python3 "$PY" "$u/OVERNIGHT_PROGRESS.md" "$tmp/bl3.md" 5 >/dev/null
ok "unknown repo layout: no rewrite" "grep -q 'lib/test_x.py' \"$u/OVERNIGHT_PROGRESS.md\""
echo; echo "queue_refill relocate: $P passed, $F failed"
[ "$F" = 0 ]
