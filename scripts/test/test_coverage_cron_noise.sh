#!/usr/bin/env bash
# scripts/ovn_coverage_cron.sh (2026-10-09): the nightly INSTRUMENTED run failed 7-9 tests every night since 10-04 because coverage.py's own stderr warning
# ("CoverageWarning: Couldn't import C tracer: ... (no-ctracer)", 246 lines per run on the box) leaked into the captured got-values of the 'buckets' and
# 'outcomes: every row is valid JSON' tests (the uninstrumented 06:00 run is green). The cron now silences those warnings through Python's warning filter
# (PYTHONWARNINGS, inherited by every instrumented child) - no test file, no coverage floor, no baseline change.
# This runs the REAL cron script, which runs the REAL scripts/cov/run_coverage.sh (BASH_ENV xtrace hook + sitecustomize + COVERAGE_PROCESS_START exactly as
# in production) over a probe test that captures `python3 ... 2>&1` the way the two failing tests do. Only the `coverage` package is faked (it emits the same
# CoverageWarning from process_startup(), which is what the real one does on the box), so the test needs no coverage install. Then 3 mutants must be caught.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OQ="$HERE/../.."; [ -f "$OQ/scripts/ovn_coverage_cron.sh" ] || OQ="$HERE/.."
CRON="$OQ/scripts/ovn_coverage_cron.sh"
for f in scripts/ovn_coverage_cron.sh scripts/cov/run_coverage.sh scripts/cov/cov_env.sh scripts/cov/ovn_cov_report.py scripts/cov/pysite/sitecustomize.py scripts/lib_lock.sh scripts/test/ntfy_guard.sh; do
  [ -f "$OQ/$f" ] || { echo "  SKIP: $f not found"; exit 0; }; done
command -v flock >/dev/null 2>&1 || { echo "  SKIP: no flock on this host (the cron script takes a flock)"; exit 0; }
OQ="$(cd "$OQ" && pwd)"; CRON="$OQ/scripts/ovn_coverage_cron.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
T="$(cd "$T" && pwd -P)"   # /private/var vs /var on macOS
# lib_lock.sh calls `flock -w 0`; the homebrew flock on macOS (discoteq 0.4.0) rejects a zero timeout. Map it to `-n` (same meaning) so the test runs on a Mac too.
mkdir -p "$T/shim"; REALFLOCK="$(command -v flock)"
cat > "$T/shim/flock" <<EOF
#!/usr/bin/env bash
a=(); while [ \$# -gt 0 ]; do if [ "\$1" = "-w" ] && [ "\${2:-}" = "0" ]; then a+=(-n); shift 2; else a+=("\$1"); shift; fi; done
exec "$REALFLOCK" "\${a[@]}"
EOF
chmod +x "$T/shim/flock"
P=0; F=0
# assertions are evaluated with pipefail OFF (no `x | grep -q` flakiness); conditions use grep -c / [ ] only
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $SUITE: $1"; fi; }

# ---- a fake `coverage` package: process_startup() warns exactly like the real one does when the C tracer is missing (once per process) ----
mkdir -p "$T/fakepy/coverage"
cat > "$T/fakepy/coverage/__init__.py" <<'PY'
import os, warnings
class CoverageWarning(Warning):
    pass
def process_startup(*a, **k):   # the box's dist-packages/a1_coverage.pth calls process_startup(slug=...), sitecustomize.py calls it bare
    if os.environ.get("COVERAGE_PROCESS_START"):
        warnings.warn("Couldn't import C tracer: No module named 'coverage.tracer' (no-ctracer); see https://coverage.readthedocs.io/en/7.13.5/messages.html#warning-no-ctracer",
                      category=CoverageWarning, stacklevel=2)
PY

build(){  # fake queue dir: the REAL cov harness + lib + guard, a probe test, and a runner shim around the real run_coverage.sh
  Q="$T/q.$RANDOM"; mkdir -p "$Q/scripts/cov/pysite" "$Q/scripts/test" "$Q/state"
  cp "$OQ/scripts/cov/run_coverage.sh" "$OQ/scripts/cov/cov_env.sh" "$OQ/scripts/cov/ovn_cov_report.py" "$Q/scripts/cov/"
  cp "$OQ/scripts/cov/pysite/sitecustomize.py" "$Q/scripts/cov/pysite/"
  cp "$OQ/scripts/lib_lock.sh" "$Q/scripts/"; cp "$OQ/scripts/test/ntfy_guard.sh" "$Q/scripts/test/"
  # the probe mimics the two failing tests: a python subprocess whose stdout AND stderr are captured into the value that is compared
  cat > "$Q/scripts/test/probe_noise_test.sh" <<'EOS'
#!/usr/bin/env bash
got="$(python3 -c 'print("bad benign good")' 2>&1)"
if [ "$got" = "bad benign good" ]; then echo "  ok   buckets: context-exceeded error = bad (got-value clean)"; else echo "  FAIL buckets (expected [bad benign good] got [$got])"; fi
got="$(python3 -c 'import json; print(json.dumps({"bad": 0}))' 2>&1)"
if [ "$got" = '{"bad": 0}' ]; then echo "  ok   outcomes: every row is valid JSON (got-value clean)"; else echo "  FAIL outcomes: every row is valid JSON (expected [{\"bad\": 0}] got [$got])"; fi
EOS
  # runner shim = what OVN_COV_RUNNER points at: runs the REAL run_coverage.sh over the probe, then publishes its log as run_all.log + a canned report
  cat > "$Q/scripts/cov/shim_runner.sh" <<EOS
#!/usr/bin/env bash
probe="\${PROBE:-probe_noise_test.sh}"
bash "$Q/scripts/cov/run_coverage.sh" "\$probe" > "\$OVN_COV_DIR.runner.out" 2>&1
cp "\$OVN_COV_DIR/out.\$probe.log" "\$OVN_COV_DIR/run_all.log"
cat > "\$OVN_COV_DIR/report.json" <<J
{"scripts":[{"file":"a.sh","lang":"bash","hit":90,"lines":100},{"file":"b.py","lang":"python","hit":90,"lines":100}]}
J
EOS
  chmod +x "$Q/scripts/cov/shim_runner.sh"
  echo '{"bash": 80, "python": 80}' > "$Q/base.json"
}
cron(){  # $1=cron script to run; remaining args = extra VAR=val
  local s="$1"; shift
  ( env -u PYTHONWARNINGS -u COVERAGE_PROCESS_START -u BASH_ENV -u OVN_COV_DIR PATH="$T/shim:$PATH" PYTHONPATH="$T/fakepy" OVN_Q="$Q" OVN_COV_NIGHTLY_DIR="$Q/cov" OVN_COV_BASELINE="$Q/base.json" \
      OVN_COV_RUNNER="$Q/scripts/cov/shim_runner.sh" "$@" bash "$s" > "$Q/cron.out" 2>&1 < /dev/null )
}
hist(){ tail -1 "$Q/state/coverage_history.log" 2>/dev/null; }

run_suite(){  # $1=label $2=cron script path
  SUITE="$1"
  build
  # control A: the harness itself really reproduces the production noise when the cron does NOT filter it (kill switch = debugging mode)
  cron "$2" OVN_COV_KEEP_WARNINGS=1
  ok "negative control: with OVN_COV_KEEP_WARNINGS=1 the CoverageWarning pollutes both got-values (2 FAIL lines carrying the warning text)" \
     "[ \"\$(grep -c '^  FAIL ' '$Q/cov/run_all.log')\" = 2 ] && [ \"\$(grep -c 'CoverageWarning' '$Q/cov/run_all.log')\" -ge 2 ]"
  ok "negative control: the cron then counts them as failing (failing=2 in the history line, a 'failing test line' alert)" \
     "[ \"\$(hist | grep -c 'failing=2')\" = 1 ] && [ \"\$(grep -c 'failing test line' '$Q/state/alerts.log')\" = 1 ]"
  # the real thing
  : > "$Q/state/alerts.log"; : > "$Q/state/coverage_history.log"
  cron "$2"
  ok "default run: the captured stdout used by the two tests is clean - no CoverageWarning anywhere in the run log" "[ \"\$(grep -c 'CoverageWarning' '$Q/cov/run_all.log')\" = 0 ] && [ \"\$(grep -c 'Couldn' '$Q/cov/run_all.log')\" = 0 ]"
  ok "default run: both probe tests pass (2 ok lines, 0 FAIL lines)" "[ \"\$(grep -c '^  ok ' '$Q/cov/run_all.log')\" = 2 ] && [ \"\$(grep -c '^  FAIL ' '$Q/cov/run_all.log')\" = 0 ]"
  ok "default run: history says failing=0 and no alert of any kind was raised" "[ \"\$(hist | grep -c 'failing=0')\" = 1 ] && [ ! -s '$Q/state/alerts.log' ]"
  ok "the run still goes through the real instrumented harness (BASH_ENV xtrace files were written, the report step ran)" "[ \"\$(ls '$Q/cov' | grep -c '^bash\\..*\\.x\$')\" -gt 0 ] && [ -s '$Q/state/coverage_latest.json' ]"
  # warnings that are NOT coverage's stay visible (the filter is message-scoped, not a blanket 'ignore'), and a pre-set PYTHONWARNINGS is extended, not replaced
  cat > "$Q/scripts/test/probe_other_warning.sh" <<'EOS'
#!/usr/bin/env bash
python3 -c 'import warnings; warnings.warn("unrelated warning must stay visible", UserWarning)' 2>&1
echo "PW=[$PYTHONWARNINGS]"
EOS
  cron "$2" PROBE=probe_other_warning.sh PYTHONWARNINGS=error::ResourceWarning
  ok "the filter is scoped to coverage's own messages: an unrelated UserWarning is still printed" "[ \"\$(grep -c 'unrelated warning must stay visible' '$Q/cov/run_all.log')\" -ge 1 ]"
  ok "an already-set PYTHONWARNINGS is kept and our filters are appended after it" "[ \"\$(grep -c -F 'PW=[error::ResourceWarning,ignore:Couldn' '$Q/cov/run_all.log')\" = 1 ]"
  # PASSING test lines that merely mention failed attempts (seen in the box's 10-09 nightly log) must not count as failures; real failures still must
  cat > "$Q/scripts/test/probe_ok_failed_words.sh" <<'EOS'
#!/usr/bin/env bash
echo "  ok   cycle 1 (1 failed attempt): not escalated yet"
echo "  ok   attempt 2 (cap 2): the bug line is '[CLAUDE] [bug-escalated: 2 failed attempts (cap 2)]'"
echo "  ok   fixture: the bug was escalated after 2 failed (verify red) attempts"
echo "  42 passed, 0 failed"
EOS
  : > "$Q/state/alerts.log"; : > "$Q/state/coverage_history.log"
  cron "$2" PROBE=probe_ok_failed_words.sh
  ok "passing 'ok' lines that say '1 failed attempt' / '2 failed attempts' / '2 failed (verify red) attempts' are not failures: failing=0, no alert" "[ \"\$(grep -c 'ok ' '$Q/cov/run_all.log')\" -ge 3 ] && [ \"\$(hist | grep -c 'failing=0')\" = 1 ] && [ ! -s '$Q/state/alerts.log' ]"
  cat >> "$Q/scripts/test/probe_ok_failed_words.sh" <<'EOS'
echo "  FAIL buckets: something real (expected [a] got [b])"
echo "  41 passed, 1 failed"
echo "❌ SOME QUEUE TESTS FAILED"
EOS
  : > "$Q/state/alerts.log"; : > "$Q/state/coverage_history.log"
  cron "$2" PROBE=probe_ok_failed_words.sh
  ok "genuine failure lines (FAIL line, 'N failed' summary, the red-X banner) are still counted: failing=3 and a failing-test alert" "[ \"\$(hist | grep -c 'failing=3')\" = 1 ] && [ \"\$(grep -c '3 failing test line' '$Q/state/alerts.log')\" = 1 ]"
}

run_suite "real" "$CRON"
[ "$F" -eq 0 ] && echo "  ok   real cron script: all scenario assertions hold"

mutate(){  # $1=label $2=old $3=new
  OLD="$2" NEW="$3" python3 - "$CRON" "$T/mutant_cron.sh" <<'PY'
import os, sys
s = open(sys.argv[1]).read()
if s.count(os.environ["OLD"]) != 1:
    sys.exit("mutation anchor not found exactly once: " + os.environ["OLD"])
open(sys.argv[2], "w").write(s.replace(os.environ["OLD"], os.environ["NEW"]))
PY
  [ $? -eq 0 ] || { F=$((F+1)); echo "  FAIL: mutation '$1' could not be applied"; return; }
  local out; out="$(run_suite "mutant" "$T/mutant_cron.sh" 2>&1)"
  if [ "$(printf '%s\n' "$out" | grep -c 'FAIL: mutant')" -gt 0 ]; then P=$((P+1)); echo "  ok   mutation caught: $1"; else F=$((F+1)); echo "  FAIL: mutation NOT caught: $1"; fi
}
# anchors live in here-docs so their quotes stay verbatim
anchor(){ IFS= read -r -d '' "$1" || true; }
anchor EXPORT_LINE <<'X'
  export PYTHONWARNINGS="${PYTHONWARNINGS:+$PYTHONWARNINGS,}ignore:Couldn't import C tracer,ignore:Couldn't parse Python file,ignore:No data was collected"
X
anchor TRACER_MSG <<'X'
ignore:Couldn't import C tracer,
X
anchor TRACER_MSG_BAD <<'X'
ignore:Couldn't import X tracer,
X
anchor FILTERS <<'X'
ignore:Couldn't import C tracer,ignore:Couldn't parse Python file,ignore:No data was collected"
X
anchor KEEP_IF <<'X'
if [ "${OVN_COV_KEEP_WARNINGS:-0}" != "1" ]; then
X
EXPORT_LINE="${EXPORT_LINE%$'\n'}"; TRACER_MSG="${TRACER_MSG%$'\n'}"; TRACER_MSG_BAD="${TRACER_MSG_BAD%$'\n'}"; FILTERS="${FILTERS%$'\n'}"; KEEP_IF="${KEEP_IF%$'\n'}"
mutate "filter export removed" "$EXPORT_LINE" '  :'
mutate "filter does not match coverage's message" "$TRACER_MSG" "$TRACER_MSG_BAD"
mutate "blanket ignore of every warning" "$FILTERS" 'ignore"'
anchor OKFILTER <<'X'
grep -av '^[[:space:]]*ok[[:space:]]' "$D/run_all.log" 2>/dev/null | grep -acE
X
OKFILTER="${OKFILTER%$'\n'}"
mutate "passing 'ok ... failed attempt' lines counted as failures (the failing=3 residue)" "$OKFILTER" "cat \"\$D/run_all.log\" 2>/dev/null | grep -acE"
mutate "kill switch ignored" "$KEEP_IF" 'if true; then'

echo "coverage_cron_noise: $P passed, $F failed"
[ "$F" -eq 0 ]
