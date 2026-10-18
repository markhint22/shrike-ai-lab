#!/usr/bin/env bash
# Package verify-credit-runner (night review N4, 2026-10-13), findings A and C in lib_verify_clause.sh.
#   A  credit-time VERIFY ran python/pytest clauses with the venv python from the repo root and NO PYTHONPATH, so
#        python -c "from backend.app.x import y"      (x.py itself does `from app.persistence import ...`)  -> ModuleNotFoundError: No module named 'app'
#        pytest tests/test_data.py::test_ok            (file lives in backend/tests, the legacy ROOT conftest does `from app.database import Base`) -> rc 4
#      although the cycle's own .ovn-verify.sh (right root) was green. _verify_py_root derives the project root from the venv path (else backend/ billwatch-backend/ iptv-backend/),
#      and the clause is run EXACTLY as before FIRST: only a FAIL whose output is an import / missing-path error is re-run ONCE with PYTHONPATH <root>:<repo> appended (and a relative tests/ path
#      missing at the cwd but present under <root> runs from <root>), and that result is adopted. A retry, never a default: a clause that passes today cannot flip - the billwatch-backend/alembic/
#      __init__.py package would shadow the installed alembic on PYTHONPATH (reviewer finding; the S-section below uses a root package that shadows an installed library).
#      OVN_VERIFY_PY_ROOT=off restores the old run.
#   C  pytest `path::name` where name is only a PREFIX of the real tests: rc 4 'not found'. OVN_VERIFY_PYTEST_K_FALLBACK=shadow (default) logs a note=pytest-k-fallback row and does NOT
#      credit; =on adopts the `path -k name` result (why=name-substring); =off disables. The retry needs the file to exist, a single node id, and no `cd` in the clause (K-section).
# Every PASS-only-with-the-new-logic assertion below FAILS with the PYTHONPATH export removed / the kill switch off ("benign twin" lines are labelled).
set -o pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
safe_use_short_tmp || exit 1     # 2026-10-17: the shadow log truncates cmd= / clause= at 200 chars; a deep TMPDIR (scratchpad, CI workspace) must not push the asserted token out of it
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."
[ -f "$S/lib_verify_clause.sh" ] || { echo "  SKIP: lib_verify_clause.sh not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
eq(){ if [ "$2" = "$3" ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1 (got [$2] want [$3])"; fi; }
W="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$W"' EXIT
safe_set_sandbox_home "$W" || exit 1; mkdir -p "$HOME"
export PYTHONDONTWRITEBYTECODE=1
unset PYTHONPATH PYTEST_ADDOPTS
export OVN_VERIFY_SHADOW_LOG="$W/shadow.log"

# a real python that has pytest and does NOT already import `app` / `backend` (the fixture's modules must not be satisfiable from the venv)
REALPY=""
_cands="${OVN_TEST_PYTEST_PY:-}"
for g in /home/*/overnight-queue/repos/*/*/.venv/bin/python3 /Users/*/LocalProjects/*/*/.venv/bin/python3 /Users/*/LocalProjects/*/.venv/bin/python3 "$(type -P python3)"; do [ -x "$g" ] && _cands="$_cands $g"; done
for cand in $_cands; do
  "$cand" -c 'import pytest' >/dev/null 2>&1 || continue
  "$cand" -c 'import app' >/dev/null 2>&1 && continue
  "$cand" -c 'import backend' >/dev/null 2>&1 && continue
  REALPY="$cand"; break
done
[ -n "$REALPY" ] || { echo "  SKIP-VACUOUS: no python with pytest (and without an importable 'app') found - ZERO assertions ran, this test proved nothing" | tee /dev/stderr; exit 0; }

. "$S/lib_verify_clause.sh"

mkfix() {  # mkfix <dir> [with-venv-dir]
  R="$W/$1"; rm -rf "$R"; mkdir -p "$R/backend/app" "$R/backend/tests" "$R/backend/.venv/bin" "$R/tests"
  printf '' > "$R/backend/app/__init__.py"
  printf 'class TokenStore:\n    pass\n' > "$R/backend/app/persistence.py"
  printf 'Base = object\n' > "$R/backend/app/database.py"
  printf 'from app.persistence import TokenStore\ny = 1\n' > "$R/backend/app/x.py"
  printf 'def test_ok():\n    assert True\n\ndef test_find_stale_run_ids_returns_old():\n    assert True\n\ndef test_find_stale_run_ids_respects_status():\n    assert True\n' > "$R/backend/tests/test_data.py"
  printf '[pytest]\n' > "$R/pytest.ini"                                  # rootdir = repo root, so the ROOT conftest below is loaded for any path under it
  printf 'from app.database import Base\n' > "$R/conftest.py"
  printf 'from app.database import Base\n' > "$R/tests/conftest.py"        # the legacy root tests/ the billwatch rows tripped over
  printf 'def test_legacy():\n    assert True\n' > "$R/tests/test_legacy.py"
  printf 'def test_find_stale_run_ids_at_root():\n    assert True\n' > "$R/tests/test_trap.py"   # same relative path as backend/tests/test_trap.py, different content (the cd-form trap)
  printf 'def test_find_stale_run_ids_in_backend():\n    assert True\n' > "$R/backend/tests/test_trap.py"
  printf '#!/bin/sh\nexec "%s" "$@"\n' "$REALPY" > "$R/backend/.venv/bin/python3"
  printf '#!/bin/sh\nexec "%s" -m pytest "$@"\n' "$REALPY" > "$R/backend/.venv/bin/pytest"
  chmod +x "$R/backend/.venv/bin/python3" "$R/backend/.venv/bin/pytest"
  cd "$R" || exit 1
}
# progress file with one item per line number; chk <n> prints the verdict
PROG="$W/prog.md"; SHADOW_LOG="$OVN_VERIFY_SHADOW_LOG"; _REPO_LABEL=t
cat > "$PROG" <<'EOP'
- [ ] [T2] backend/app/x.py - import chain. VERIFY: `python -c "from backend.app.x import y; assert y == 1"`
- [ ] [T2] backend/tests/test_data.py - tests/ path only exists under backend. VERIFY: `pytest tests/test_data.py::test_ok -v`
- [ ] [T2] backend/tests/test_data.py - root conftest imports app. VERIFY: `pytest backend/tests/test_data.py::test_ok -v`
- [ ] [T2] backend/app/x.py - genuinely missing module. VERIFY: `python -c "import definitely_missing_mod_xyz"`
- [ ] [T2] backend/app/x.py - a real assertion failure. VERIFY: `python -c "from backend.app.x import y; assert y == 2"`
- [ ] [T2] backend/app/x.py - already passing, no imports. VERIFY: `python -c "print(1)"`
- [ ] [T2] backend/app/x.py - not python. VERIFY: `test -f backend/app/x.py`
- [ ] [T2] backend/app/x.py - PYTHONPATH from the caller is kept first. VERIFY: `python -c "import os; assert os.environ['PYTHONPATH'].split(':')[0] == '/pre/existing'; from backend.app.x import y"`
- [ ] [T2] backend/tests/test_data.py - prefix of real test names. VERIFY: `pytest backend/tests/test_data.py::test_find_stale_run_ids -v`
- [ ] [T2] backend/tests/test_data.py - names no test at all. VERIFY: `pytest backend/tests/test_data.py::test_nope_nothing -v`
- [ ] [T2] backend/tests/missing.py - file does not exist. VERIFY: `pytest backend/tests/missing.py::test_find_stale_run_ids -v`
- [ ] [T2] backend/tests/test_data.py - exact name. VERIFY: `pytest backend/tests/test_data.py::test_find_stale_run_ids_returns_old -v`
- [ ] [T2] backend/tests/test_data.py - two node ids, the first a prefix. VERIFY: `pytest backend/tests/test_data.py::test_find_stale_run_ids backend/tests/test_data.py::test_ok -v`
- [ ] [T2] backend/tests/test_data.py - cd form, prefix name. VERIFY: `cd backend && pytest tests/test_trap.py::test_find_stale_run_ids -v`
- [ ] [T2] backend/app/x.py - plain assertion failure, no import. VERIFY: `python3 -c "assert 1 == 2"`
EOP
chk() { shadow_check "$1"; printf '%s' "$_LAST_VERIFY_RESULT"; }

mkfix fx

# ---------------- A: the root helper itself ----------------
eq "root: a venv path <root>/.venv/bin/python3 -> <root>" "$(_verify_py_root "$R/backend/.venv/bin/python3 -c 'x'")" "$R/backend"
eq "root: a relative venv path is made absolute" "$(_verify_py_root "backend/.venv/bin/pytest tests/a.py")" "$R/backend"
eq "root: no venv in the clause -> first of backend/ billwatch-backend/ iptv-backend/ that exists" "$(_verify_py_root 'python3 -c "x"')" "$R/backend"
eq "root: a non-python clause has no root" "$(_verify_py_root 'test -f a.py')" ""
eq "root: kill switch OVN_VERIFY_PY_ROOT=off -> none" "$(OVN_VERIFY_PY_ROOT=off _verify_py_root "$R/backend/.venv/bin/python3 -c x")" ""
mkdir -p "$W/only_iptv/iptv-backend"; ( cd "$W/only_iptv" && eq "root: falls back to iptv-backend when it is the only candidate" "$(_verify_py_root 'pytest x.py')" "$W/only_iptv/iptv-backend" )
mkdir -p "$W/noroot"; ( cd "$W/noroot" && eq "root: no candidate dir and no venv -> none" "$(_verify_py_root 'pytest x.py')" "" )
cd "$R" || exit 1
eq "cwd: tests/ path missing at the repo root but present under backend/ -> backend" "$(_verify_py_cwd 'pytest tests/test_data.py::test_ok' "$R/backend")" "$R/backend"
eq "cwd: tests/ path that exists at the cwd stays at the cwd" "$(_verify_py_cwd 'pytest tests/test_legacy.py' "$R/backend")" ""
eq "cwd: a clause that cds by itself is left alone" "$(_verify_py_cwd 'cd backend && pytest tests/test_data.py' "$R/backend")" ""

# ---------------- A: shadow_check ----------------
eq "A1 python -c 'from backend.app.x import y' (x.py does 'from app.persistence import ...') PASSES with the project root on PYTHONPATH" "$(chk 1)" PASS
eq "A2 pytest tests/test_data.py::test_ok (file only under backend/) runs from the root and PASSES" "$(chk 2)" PASS
eq "A3 pytest backend/tests/test_data.py::test_ok with a ROOT conftest importing app PASSES" "$(chk 3)" PASS
eq "A4 benign twin: a genuinely missing module still FAILS" "$(chk 4)" FAIL
eq "A5 benign twin: a real assertion failure still FAILS (rc 1, not an import error)" "$(chk 5)" FAIL
eq "A6 benign twin: a clause that never imports the project still PASSES" "$(chk 6)" PASS
eq "A7 benign twin: a non-python clause is unaffected" "$(chk 7)" PASS
eq "A7b a non-python clause leaves no root state behind" "$_VPY_PP|$_VPY_CD" "|"
eq "A8 an existing PYTHONPATH is kept FIRST on the retry (the project roots are appended)" "$(PYTHONPATH=/pre/existing chk 8)" PASS
eq "A8b ... and the caller's PYTHONPATH did not leak out of the run" "${PYTHONPATH:-unset}" unset

# ---------------- A: a RETRY, not a default ----------------
: > "$SHADOW_LOG"
shadow_check 6
eq "R1 a clause that already passes runs with NO project root (identical to the old run)" "$_VPY_PP|$_VPY_CD" "|"
ok "R1 and logs no py-root-retry row" '! grep -q "note=py-root-retry" "$SHADOW_LOG"'
: > "$SHADOW_LOG"
shadow_check 1
eq "R2 the import-chain clause passes via the retry" "$_LAST_VERIFY_RESULT" PASS
ok "R2 a note=py-root-retry row records would=PASS and the original rc" 'grep -q "note=py-root-retry would=PASS orig_rc=1 rc=0 root=$R/backend" "$SHADOW_LOG"'
ok "R2 the note row carries no result= token (readers count result= rows)" '! grep "note=py-root-retry" "$SHADOW_LOG" | grep -q "result="'
: > "$SHADOW_LOG"
shadow_check 15
ok "R3 a real assertion failure (no import error) is NOT retried" '! grep -q "note=py-root-retry" "$SHADOW_LOG"'
: > "$SHADOW_LOG"
shadow_check 4
ok "R4 a genuinely missing module IS retried once and stays FAIL" 'grep -q "note=py-root-retry would=FAIL" "$SHADOW_LOG" && [ "$_LAST_VERIFY_RESULT" = FAIL ]'
: > "$SHADOW_LOG"
shadow_check 7
ok "R5 a non-python clause is never retried" '! grep -q "note=py-root-retry" "$SHADOW_LOG"'

# ---------------- AUDIT (2026-10-14): every FAIL->PASS adoption of the retry is written to state/alerts.log ----------------
rm -f "$W/alerts.log"; : > "$SHADOW_LOG"
shadow_check 1
eq "AU1 the retry-adopted PASS is still a PASS" "$_LAST_VERIFY_RESULT" PASS
ok "AU1 alerts.log (next to the shadow log) gets one py-root-retry audit line" '[ "$(grep -c "py-root-retry" "$W/alerts.log")" = 1 ]'
ok "AU1 the audit line names the item (line number + cksum of its text)" 'grep "py-root-retry" "$W/alerts.log" | grep -q " item=1:[0-9]"'
ok "AU1 the audit line carries the clause" 'grep "py-root-retry" "$W/alerts.log" | grep -q "clause=.*from backend.app.x import y"'
ok "AU1 the audit line names the project root and that it is a FAIL->PASS" 'grep "py-root-retry" "$W/alerts.log" | grep -q "FAIL->PASS under project root $R/backend"'
ok "AU1 the audit line is shaped like an alerts.log line (date | level | key | message)" 'grep "py-root-retry" "$W/alerts.log" | grep -qE "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} info \| py-root-retry \| "'
shadow_check 1
ok "AU2 a second adoption appends a second line (no silent dedupe)" '[ "$(grep -c "py-root-retry" "$W/alerts.log")" = 2 ]'
rm -f "$W/alerts.log"
shadow_check 4
ok "AU3 a retry that stays FAIL writes no audit line (only FAIL->PASS is a false green)" '[ ! -s "$W/alerts.log" ]'
shadow_check 6
ok "AU4 a clause that passes without the retry writes no audit line" '[ ! -s "$W/alerts.log" ]'
rm -f "$W/alerts.log"; OVN_VERIFY_ALERTS_LOG="$W/elsewhere/alerts.log" shadow_check 1
ok "AU5 OVN_VERIFY_ALERTS_LOG redirects the audit line" '[ -s "$W/elsewhere/alerts.log" ] && [ ! -e "$W/alerts.log" ]'
# AU7 (2026-10-14 review): two items with the SAME VERIFY in one auto-credit call. The second is a memo replay of the first's adopted PASS; it is a credit too and must be audited.
rm -f "$W/alerts.log"; : > "$SHADOW_LOG"
MEMO_PROG="$W/memo_prog.md"; { sed -n 1p "$W/prog.md"; sed -n 1p "$W/prog.md"; } > "$MEMO_PROG"
PROG="$MEMO_PROG"; _VC_MEMO_ON=1; _VC_MEMO=""
shadow_check 1; _m1="$_LAST_VERIFY_RESULT"
shadow_check 2; _m2="$_LAST_VERIFY_RESULT"
_VC_MEMO_ON=0; _VC_MEMO=""; PROG="$W/prog.md"
eq "AU7 the first item PASSes via the retry" "$_m1" PASS
eq "AU7 the memo-replayed second item is a PASS too" "$_m2" PASS
ok "AU7 the replayed credit gets its own audit line (2 lines for 2 credits)" '[ "$(grep -c "py-root-retry" "$W/alerts.log")" = 2 ]'
ok "AU7 the replayed audit line names the second line number (item=2:)" 'grep "py-root-retry" "$W/alerts.log" | grep -q " item=2:[0-9]"'
rm -f "$W/alerts.log"; OVN_VERIFY_PY_ROOT=off shadow_check 1
ok "AU6 kill switch off: no retry, no audit line" '[ ! -s "$W/alerts.log" ]'
PROG="$W/prog.md"
: > "$SHADOW_LOG"

# ---------------- S: a root package that shadows an installed library (billwatch-backend/alembic) ----------------
# fixture: backend/pluggy/__init__.py is a REGULAR package named like an installed distribution (pytest's own dependency). On PYTHONPATH it shadows the real one.
SR="$W/fxs"; rm -rf "$SR"; mkdir -p "$SR/backend/pluggy"; printf '' > "$SR/backend/pluggy/__init__.py"
mkdir -p "$SR/backend/.venv/bin"; printf '#!/bin/sh\nexec "%s" "$@"\n' "$REALPY" > "$SR/backend/.venv/bin/python3"; chmod +x "$SR/backend/.venv/bin/python3"; cd "$SR" || exit 1
SPROG="$W/sprog.md"; PROG="$SPROG"
cat > "$SPROG" <<'EOP'
- [ ] [T2] backend/x.py - root package shadows an installed library. VERIFY: `python3 -c "from pluggy import HookimplMarker"`
- [ ] [T2] backend/x.py - chained passing clauses. VERIFY: `python3 -c "print(1)" && python3 -c "from pluggy import HookimplMarker"`
- [ ] [T2] backend/x.py - the shadow breaks it only under the root. VERIFY: `python3 -c "from backend.pluggy import __name__ as n; assert n == 'backend.pluggy'"`
EOP
: > "$SHADOW_LOG"
eq "S1 python3 -c 'from pluggy import HookimplMarker' PASSES although backend/pluggy/__init__.py would shadow it on PYTHONPATH (billwatch alembic case)" "$(chk 1)" PASS
eq "S1 ... and ran with NO project root" "$_VPY_PP|$_VPY_CD" "|"
eq "S2 a chained passing clause + the shadowed import also PASSES" "$(chk 2)" PASS
ok "S2 no py-root-retry row for either" '! grep -q "note=py-root-retry" "$SHADOW_LOG"'
eq "S3 sanity: the shadowing is real (the same import fails with the project root on PYTHONPATH)" "$(PYTHONPATH="$SR/backend:$SR" "$REALPY" -c 'from pluggy import HookimplMarker' >/dev/null 2>&1 && echo ok || echo shadowed)" shadowed
eq "S4 a clause that FAILS for a missing import is retried under the root and passes there" "$(chk 3)" PASS
PROG="$W/prog.md"; cd "$R" || exit 1

# kill switch: the old run (same fixture) fails exactly where the new logic passes
export OVN_VERIFY_PY_ROOT=off
eq "A1 kill switch off: the import chain fails like before (ModuleNotFoundError)" "$(chk 1)" FAIL
eq "A2 kill switch off: the tests/ path fails like before" "$(chk 2)" FAIL
eq "A3 kill switch off: the root conftest import fails like before" "$(chk 3)" FAIL
eq "A6 kill switch off: benign twin still PASS" "$(chk 6)" PASS
unset OVN_VERIFY_PY_ROOT

# ---------------- C: pytest path::name where name is only a prefix ----------------
: > "$SHADOW_LOG"
shadow_check 9
eq "C1 default (shadow): a prefix name keeps the FAIL verdict (no credit)" "$_LAST_VERIFY_RESULT" FAIL
ok "C1 shadow: a note=pytest-k-fallback row says it WOULD pass" 'grep -q "note=pytest-k-fallback mode=shadow would=PASS" "$SHADOW_LOG"'
ok "C1 shadow: the note row does not carry a result= token (readers count result= rows)" '! grep "note=pytest-k-fallback" "$SHADOW_LOG" | grep -q "result="'
ok "C1 shadow: the final FAIL row has no why=name-substring" '! grep "result=FAIL" "$SHADOW_LOG" | grep -q "why=name-substring"'
eq "C1 shadow: _LAST_VERIFY_WHY is not name-substring" "$([ "$_LAST_VERIFY_WHY" = name-substring ] && echo yes || echo no)" no
: > "$SHADOW_LOG"
OVN_VERIFY_PYTEST_K_FALLBACK=on shadow_check 9   # not in a $(...): the label is a global
eq "C2 on: the prefix name credits via -k" "$_LAST_VERIFY_RESULT" PASS
eq "C2 on: labelled name-substring" "$_LAST_VERIFY_WHY" name-substring
ok "C2 on: the PASS row says why=name-substring and runs '-k test_find_stale_run_ids'" 'grep "result=PASS" "$SHADOW_LOG" | grep -q "why=name-substring.*-k test_find_stale_run_ids"'
ok "C2 on: a note row was logged too" 'grep -q "note=pytest-k-fallback mode=on would=PASS" "$SHADOW_LOG"'
: > "$SHADOW_LOG"
eq "C3 off: old behaviour, FAIL, no note row" "$(OVN_VERIFY_PYTEST_K_FALLBACK=off chk 9)" FAIL
ok "C3 off: nothing logged as a note" '! grep -q "note=pytest-k-fallback" "$SHADOW_LOG"'
eq "C4 on, a name that matches no test at all stays FAIL" "$(OVN_VERIFY_PYTEST_K_FALLBACK=on chk 10)" FAIL
: > "$SHADOW_LOG"
eq "C5 on, the FILE does not exist -> no retry, FAIL" "$(OVN_VERIFY_PYTEST_K_FALLBACK=on chk 11)" FAIL
ok "C5 no note row when the file is missing" '! grep -q "note=pytest-k-fallback" "$SHADOW_LOG"'
: > "$SHADOW_LOG"
OVN_VERIFY_PYTEST_K_FALLBACK=on shadow_check 12
eq "C6 benign twin: an exact test name passes on its own, no fallback involved" "$_LAST_VERIFY_RESULT" PASS
ok "C6 no note row for an exact name" '! grep -q "note=pytest-k-fallback" "$SHADOW_LOG"'
eq "C6 label not set for an exact pass" "$([ "$_LAST_VERIFY_WHY" = name-substring ] && echo yes || echo no)" no

# K: the k-fallback only for ONE node id and no cd
: > "$SHADOW_LOG"
eq "K1 on: two node ids, the first a prefix -> no -k fallback (it would apply -k to both ids and could credit a partial match), FAIL" "$(OVN_VERIFY_PYTEST_K_FALLBACK=on chk 13)" FAIL
ok "K1 no note row" '! grep -q "note=pytest-k-fallback" "$SHADOW_LOG"'
: > "$SHADOW_LOG"
eq "K2 on: a clause that cds first (the file is checked against the wrong directory) -> no fallback, FAIL" "$(OVN_VERIFY_PYTEST_K_FALLBACK=on chk 14)" FAIL
ok "K2 no note row" '! grep -q "note=pytest-k-fallback" "$SHADOW_LOG"'
eq "K3 the helper itself prints nothing for the two-id and the cd forms" "$(_verify_k_fallback_cmd 'pytest backend/tests/test_data.py::a backend/tests/test_data.py::b'):$(_verify_k_fallback_cmd 'cd backend && pytest tests/test_trap.py::test_find_stale_run_ids')" ":"
ok "K3 benign twin: a single node id still gets the rewrite" '[ "$(_verify_k_fallback_cmd "pytest backend/tests/test_data.py::test_find_stale_run_ids")" = "pytest backend/tests/test_data.py -k test_find_stale_run_ids" ]'

echo "test_verify_py_root: $P passed, $F failed"
[ "$F" = 0 ]
