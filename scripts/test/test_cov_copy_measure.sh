#!/usr/bin/env bash
# scripts/cov (qacov QA-3, 2026-10-10): the coverage harness now (1) measures a pipeline script that a test COPIES into a temp dir before running it (attributed back to the real script
# by basename), (2) still counts never-imported TOP-LEVEL files at 0 % (the old `source` semantics, via one no-op run) and lists the never-imported scripts/ ones, (3) with OVN_COV_QA=1 measures
# qa/ - including `env -i` entry-point runs, through scripts/cov/shim/env - as SEPARATE bash-qa/python-qa rows that are not part of the nightly floor totals.
# Runs the REAL run_coverage.sh + ovn_cov_report.py against a tiny fixture tree with a one-test "suite". Needs python3 with coverage.py (the box; SKIP elsewhere unless python3 has it).
# Mutants of the report (copy folding off) and of the shim (no cov vars after -i) must fail the matching assertions. bash 3.2 ok.
set -uo pipefail
unset BASH_ENV COVERAGE_PROCESS_START OVN_COV_DIR OVN_COV_REAL_ENV OVN_COV_QA OVN_Q   # when this test itself runs inside an instrumented suite run, its NESTED harness runs must not inherit the outer instrumentation
HERE="$(cd "$(dirname "$0")" && pwd)"
COV="$HERE/../cov"; [ -d "$COV" ] || { echo "  SKIP: scripts/cov not found"; exit 0; }
python3 -c "import coverage" >/dev/null 2>&1 || { echo "  SKIP: python3 has no coverage.py (runs on the box)"; exit 0; }
[ -f "$COV/shim/env" ] || { echo "  FAIL: scripts/cov/shim/env missing"; exit 1; }
P=0; F=0
ok(){ if [ "$2" = "1" ]; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
T="$(mktemp -d)"; T="$(cd "$T" && pwd -P)"; trap 'rm -rf "$T"' EXIT
mkfix(){  # <name>: fixture Q with scripts/{foo,bar,never}.py, top_never.py, qa/{gate.py,q.sh} and a one-test suite
  local q="$T/$1/q"; mkdir -p "$q/scripts/test" "$q/qa" "$q/scripts/cov"
  cp -R "$COV/." "$q/scripts/cov/"; rm -rf "$q/scripts/cov/__pycache__" "$q/scripts/cov/pysite/__pycache__"
  cp "$HERE/ntfy_guard.sh" "$q/scripts/test/"
  printf 'import sys\ndef used(x):\n    return x + 1\n\ndef other(x):\n    return x * 2\n\nif __name__ == "__main__":\n    print(used(1))\n' > "$q/scripts/foo.py"
  printf 'def a():\n    return 1\ndef b():\n    return 2\nprint(a())\n' > "$q/scripts/bar.py"
  printf 'def z():\n    return 3\nprint(z())\n' > "$q/scripts/never.py"
  printf 'def t():\n    return 1\nprint(t())\n' > "$q/top_never.py"
  printf 'import sys\ndef g():\n    return 1\ndef h():\n    return 2\nprint(g())\n' > "$q/qa/gate.py"
  printf '#!/usr/bin/env bash\necho qa\n' > "$q/qa/q.sh"
  printf 'def c():\n    return 1\nprint(c())\n' > "$q/scripts/conftest.py"   # a generic basename that also exists OUTSIDE the tree (see test_x.sh)
  printf '#!/usr/bin/env bash\necho junk\n' > "$q/._junk.sh"; printf 'x = 1\n' > "$q/scripts/._junk.py"   # macOS AppleDouble leftovers (the box has several): never script rows
  cat > "$q/scripts/test/test_x.sh" <<'TX'
#!/usr/bin/env bash
D="$(mktemp -d)"; cp ../foo.py "$D/foo.py"; python3 "$D/foo.py"; rm -rf "$D"   # like the real tests: the copy is gone long before the report runs
python3 ../bar.py
G="$(mktemp -d)"; cp ../conftest.py "$G/conftest.py"; python3 "$G/conftest.py"; rm -rf "$G"   # an UNRELATED conftest.py run from outside the tree
for i in 1 2 3; do python3 -c "pass"; done   # empty data files: they hash alike, and combine drops later files that hash like an earlier one (it dropped the no-op data until it got its own dir)
env -i PATH="$PATH" python3 ../../qa/gate.py
env -i PATH="$PATH" bash ../../qa/q.sh
TX
  printf '%s' "$q"
}
cov(){ # <name> [env assignments...]: run the harness, leave the report in $T/<name>/out and the JSON in $T/<name>/cov/report.json
  local n="$1"; shift
  ( export OVN_Q="$T/$n/q" OVN_COV_DIR="$T/$n/cov"; for kv in "$@"; do export "$kv"; done; bash "$T/$n/q/scripts/cov/run_coverage.sh" test_x.sh ) > "$T/$n/out" 2>&1
}
row(){ python3 -c "
import json,sys
d=json.load(open('$T/$1/cov/report.json'))
for r in d['scripts']:
    if r['file']=='$2': print('%s %d/%d' % (r['lang'], r['hit'], r['lines'])); sys.exit(0)
print('absent')"; }

Q="$(mkfix base)"; cov base
ok "the suite ran (test_x.sh rc=0) and a report was written" "$(grep -q 'test_x.sh rc=0' "$T/base/out" && [ -f "$T/base/cov/report.json" ] && echo 1 || echo 0)"
ok "COPY-BASED test: scripts/foo.py (run only as a temp copy that the test already DELETED) is measured: python 6/7" "$([ "$(row base scripts/foo.py)" = 'python 6/7' ] && echo 1 || echo 0)"
ok "in-place run unchanged: scripts/bar.py is python 4/5" "$([ "$(row base scripts/bar.py)" = 'python 4/5' ] && echo 1 || echo 0)"
ok "a never-run TOP-LEVEL script is still counted at 0 (old source semantics kept): top_never.py python 0/3" "$([ "$(row base top_never.py)" = 'python 0/3' ] && echo 1 || echo 0)"
ok "a never-imported scripts/ file is not in the totals but is LISTED: scripts/never.py" "$([ "$(row base scripts/never.py)" = absent ] && grep -q 'no test ever imported or ran.*scripts/never.py' "$T/base/out" && echo 1 || echo 0)"
ok "qa/ is NOT measured by default (no qa rows, no qa totals line)" "$([ "$(row base qa/gate.py)" = absent ] && [ "$(row base qa/q.sh)" = absent ] && ! grep -q 'TOTAL (qa/' "$T/base/out" && echo 1 || echo 0)"
ok "AppleDouble junk (._junk.sh, scripts/._junk.py) is never a row" "$([ "$(row base ._junk.sh)" = absent ] && [ "$(row base scripts/._junk.py)" = absent ] && ! grep -q '\._junk' "$T/base/out" && echo 1 || echo 0)"
ok "GENERIC BASENAMES: an out-of-tree conftest.py run is NOT folded onto scripts/conftest.py (no row, not in any total)" "$([ "$(row base scripts/conftest.py)" = absent ] && echo 1 || echo 0)"
mkdir -p "$T/gb/a" "$T/gb/b" "$T/gb/c"; : > "$T/gb/a/__init__.py"; : > "$T/gb/a/__main__.py"; : > "$T/gb/b/conftest.py"; : > "$T/gb/b/setup.py"; printf 'x = 1\n' > "$T/gb/c/real.py"
gb(){ ( cd "$1/scripts/cov" && python3 -c "
import ovn_cov_report as m
print(sorted(m.py_by_basename('$T/gb')))" ); }
ok "GENERIC BASENAMES: py_by_basename lists real.py only (never __init__.py, __main__.py, conftest.py, setup.py)" "$([ "$(gb "$T/base/q")" = "['real.py']" ] && echo 1 || echo 0)"
ok "core TOTAL counts foo+bar+top_never only: 10/15" "$(grep -q '^TOTAL: 10/15 lines' "$T/base/out" && echo 1 || echo 0)"

Q="$(mkfix qa)"; cov qa OVN_COV_QA=1
ok "OVN_COV_QA=1: the env -i python entry point is measured through the shim: qa/gate.py python-qa 5/6" "$([ "$(row qa qa/gate.py)" = 'python-qa 5/6' ] && echo 1 || echo 0)"
ok "OVN_COV_QA=1: the env -i bash entry point is measured: qa/q.sh bash-qa 1/1" "$([ "$(row qa qa/q.sh)" = 'bash-qa 1/1' ] && echo 1 || echo 0)"
ok "OVN_COV_QA=1: qa rows are informational - the core TOTAL is unchanged (10/15) and a separate qa total line is printed" "$(grep -q '^TOTAL: 10/15 lines' "$T/qa/out" && grep -q 'TOTAL (qa/, informational' "$T/qa/out" && echo 1 || echo 0)"
ok "OVN_COV_QA=1: the languages are python-qa/bash-qa, so the nightly's per-language floor sums (python / bash) never see them" "$(python3 -c "
import json
d=json.load(open('$T/qa/cov/report.json'))
core=sum(r['lines'] for r in d['scripts'] if r['lang'] in ('python','bash'))
print(1 if core==15 and any(r['lang']=='python-qa' for r in d['scripts']) else 0)")"

# ---- mutants
Q="$(mkfix mut1)"; python3 - "$T/mut1/q/scripts/cov/ovn_cov_report.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "rel = by_base.get(os.path.basename(ap))\n"
assert s.count(old) == 2, s.count(old)          # the json path and the data-file path
open(p, "w").write(s.replace(old, "rel = None\n"))
PY
cov mut1
ok "MUTANT 1 (copies not folded back): scripts/foo.py vanishes - proves the COPY-BASED assertion bites" "$([ "$(row mut1 scripts/foo.py)" = absent ] && echo 1 || echo 0)"
Q="$(mkfix mut2)"; python3 - "$T/mut2/q/scripts/cov/shim/env" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '    exec "$real" -i ${add[@]+"${add[@]}"} "$@"\n'
assert s.count(old) == 1
open(p, "w").write(s.replace(old, '    exec "$real" -i "$@"\n'))
PY
cov mut2 OVN_COV_QA=1
ok "MUTANT 2 (shim does not re-add the cov vars after env -i): qa/gate.py is unmeasured (0/6 or absent) - proves the env -i assertion bites" "$(case "$(row mut2 qa/gate.py)" in 'python-qa 5/6') echo 0;; *) echo 1;; esac)"
Q="$(mkfix mut3)"; python3 - "$T/mut3/q/scripts/cov/ovn_cov_report.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '            if fn.startswith("._"):'
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "            if False:"))
PY
cov mut3
ok "MUTANT 3 (AppleDouble filter off): ._junk.sh becomes a 0/1 bash row - proves the AppleDouble assertion bites" "$([ "$(row mut3 ._junk.sh)" = 'bash 0/1' ] && echo 1 || echo 0)"
Q="$(mkfix mut4)"; python3 - "$T/mut4/q/scripts/cov/ovn_cov_report.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "        return {f: set(cd.lines(f) or []) for f in cd.measured_files()}\n"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "        return {}\n"))
PY
cov mut4
ok "MUTANT 4 (executed lines not read from the data file = the json-only fold): a copy the test already deleted is lost - proves the deleted-copy assertion bites" "$([ "$(row mut4 scripts/foo.py)" != 'python 6/7' ] && echo 1 || echo 0)"
Q="$(mkfix mut5)"; python3 - "$T/mut5/q/scripts/cov/ovn_cov_report.py" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = '        if os.path.isdir(noopdir):\n'
assert s.count(old) == 1
open(p, "w").write(s.replace(old, '        if False:\n'))
PY
cov mut5
ok "MUTANT 5 (no-op data not merged): the never-run top-level script vanishes from the totals - proves the top_never assertion bites" "$([ "$(row mut5 top_never.py)" = absent ] && echo 1 || echo 0)"
Q="$(mkfix mut6)"; python3 - "$T/mut6/q/scripts/cov/run_coverage.sh" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
old = "data_file = $D/py_noop/.coverage"
assert s.count(old) == 1
open(p, "w").write(s.replace(old, "data_file = $D/py/.coverage"))
PY
cov mut6
ok "MUTANT 6 (no-op data back in the main data dir, where combine dedups it away): top_never.py vanishes - proves the separate-dir fix is pinned" "$([ "$(row mut6 top_never.py)" = absent ] && echo 1 || echo 0)"
Q="$(mkfix mut8)"; python3 - "$T/mut8/q/scripts/cov/ovn_cov_report.py" "$T/mut8/q/scripts/cov/run_coverage.sh" <<'PY'
import sys
a, b = sys.argv[1:3]
s = open(a).read(); old = 'GENERIC_BASENAMES = ("conftest.py", "__init__.py", "__main__.py", "setup.py")'
assert s.count(old) == 1; open(a, "w").write(s.replace(old, "GENERIC_BASENAMES = ()"))
t = open(b).read(); old = "! -name conftest.py ! -name __init__.py ! -name __main__.py ! -name setup.py "
assert t.count(old) == 1; open(b, "w").write(t.replace(old, ""))
PY
cov mut8
ok "MUTANT 8 (generic basenames folded like any other, the pre-review behaviour): scripts/conftest.py gets a row from the unrelated file AND py_by_basename lists the generic names - proves both generic-basename assertions bite" "$([ "$(row mut8 scripts/conftest.py)" != absent ] && [ "$(gb "$T/mut8/q")" != "['real.py']" ] && echo 1 || echo 0)"
# nested: this harness run under an OUTER OVN_COV_QA=1 run (outer shim first on PATH, OVN_COV_REAL_ENV pointing at it) used to loop forever in the shim
Q="$(mkfix nest)"; mkdir -p "$T/outer_shim"; cp "$COV/shim/env" "$T/outer_shim/env"
( export PATH="$T/outer_shim:$PATH"; export OVN_COV_REAL_ENV="$T/outer_shim/env"; export OVN_Q="$T/nest/q" OVN_COV_DIR="$T/nest/cov" OVN_COV_QA=1; cd "$T/nest/q/scripts/test" && timeout 120 bash "$T/nest/q/scripts/cov/run_coverage.sh" test_x.sh ) > "$T/nest/out" 2>&1; echo $? > "$T/nest/rc"
ok "NESTED under an outer shim (the 30-min hang): the QA run finishes (rc 0, well under the 120 s timeout) and still measures qa/gate.py" "$([ "$(cat "$T/nest/rc")" = 0 ] && [ "$(row nest qa/gate.py)" = 'python-qa 5/6' ] && echo 1 || echo 0)"
Q="$(mkfix nest2)"; cp "$COV/shim/env" "$T/outer_shim/env"; python3 - "$T/nest2/q/scripts/cov/run_coverage.sh" "$T/nest2/q/scripts/cov/shim/env" "$T/outer_shim/env" <<'PY'
import sys
a, b = sys.argv[1:3]
s = open(a).read(); old = 'OVN_COV_REAL_ENV="$(PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin command -v env || echo /usr/bin/env)"'
assert s.count(old) == 1; open(a, "w").write(s.replace(old, 'OVN_COV_REAL_ENV="$(command -v env)"'))
t = open(b).read(); old = '[ "$real" -ef "${BASH_SOURCE[0]}" ] && real=/usr/bin/env'
assert t.count(old) == 1; open(b, "w").write(t.replace(old, ":")); open(sys.argv[3], "w").write(t.replace(old, ":"))   # the outer shim is the pre-fix one too
PY
( export PATH="$T/outer_shim:$PATH"; export OVN_COV_REAL_ENV="$T/outer_shim/env"; export OVN_Q="$T/nest2/q" OVN_COV_DIR="$T/nest2/cov" OVN_COV_QA=1; cd "$T/nest2/q/scripts/test" && timeout 25 bash "$T/nest2/q/scripts/cov/run_coverage.sh" test_x.sh ) > "$T/nest2/out" 2>&1; echo $? > "$T/nest2/rc"
ok "MUTANT 7 (fixes removed): the nested run does NOT finish in time (timeout rc 124) - proves the nested assertion pins the hang" "$([ "$(cat "$T/nest2/rc")" = 124 ] && echo 1 || echo 0)"
pkill -f "$T/nest2" >/dev/null 2>&1 || true
echo "  $P passed, $F failed"; [ "$F" = 0 ]
