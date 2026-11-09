#!/usr/bin/env bash
# hotfix-scout-hang (2026-11-08): ovn_scout_ground.py spun 4h52m at 100% CPU on `res://tests/x.gd` (xlite). Root cause: fixture_candidates' conftest walk
# `while found < 2: ... d = os.path.dirname(d)` never ends for a path that starts with '//' (PATH_RE has no ':', so res://tests/x.gd tokenizes as //tests/x.gd and
# dirname('//') == '//'). Also: PATH_RE alone is quadratic on one long run of path characters. Fixed: repo-relative token, bounded walk, linear/capped scans, and an
# OVN_SCOUT_BUDGET_S (default 20) forked-child wall-clock watchdog. Mutation proof: the OLD code (bug re-introduced by patching the fixed module) must hang here.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
SRC="$HERE/../../ovn_scout_ground.py"; [ -f "$SRC" ] || SRC="$HERE/../ovn_scout_ground.py"
[ -f "$SRC" ] || { echo "  SKIP: ovn_scout_ground.py not found"; exit 0; }
type -P timeout >/dev/null 2>&1 || { echo "  SKIP: no timeout binary"; exit 0; }
export NTFY_SERVER=http://127.0.0.1:9 OVN_NOTIFY_DISABLE=1 TZ=UTC
T="$(safe_mktemp_dir hotfix_scout)" || exit 1
trap 'safe_rm_rf "$T"' EXIT
rc=0; ok(){ echo "  ok   $1"; }; bad(){ echo "  FAIL: $1"; rc=1; }
cp "$SRC" "$T/ovn_scout_ground.py"; cp "$(dirname "$SRC")/ovn_park_unworkable.py" "$T/" 2>/dev/null

# a throwaway xlite-shaped repo: a source file, a test file, and an item whose VERIFY line names res://tests/test_a.gd and talks about fixtures
R="$T/repo"; mkdir -p "$R/scripts" "$R/tests"
printf 'extends Node\nfunc go():\n\tpass\n' > "$R/scripts/a.gd"; printf 'extends GutTest\nfunc test_a():\n\tassert_true(true)\n' > "$R/tests/test_a.gd"
git -C "$R" init -q 2>/dev/null; git -C "$R" add -A >/dev/null 2>&1; git -C "$R" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
printf 'FILES: scripts/a.gd tests/test_a.gd\n\n' > "$T/log.txt"
printf '%s\n' '- [ ] [T5] tests/test_a.gd - add a case; the fixture uses the db session. VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_a.gd -gexit`' > "$T/item.txt"

mutant(){  # $1 out-file; remaining args: "old=>>new" python edits applied to a copy of the fixed module (an anchor that is missing fails the test loudly)
  local out="$1"; shift; cp "$T/ovn_scout_ground.py" "$out"
  python3 - "$out" "$@" <<'PY' || return 1
import sys
p = sys.argv[1]; s = open(p).read()
for e in sys.argv[2:]:
    old, new = e.split("=>>")
    assert old in s, "mutation anchor missing: " + old
    s = s.replace(old, new, 1)
open(p, "w").write(s)
PY
}
OLD="$T/old_scout.py"
mutant "$OLD" 'for _hop in range(40):=>>while True:' 'if not d or nd == d:=>>if not d:' 'tok = clean_tok(tok)=>>tok = tok' || { bad "could not build the old-code mutant"; exit 1; }

echo "== root cause: res://tests/... path"
s=$(date +%s); out="$(timeout 20 env OVN_SCOUT_BUDGET_S=0 python3 "$T/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/item.txt" 120000 2>/dev/null)"; r=$?
e=$(( $(date +%s) - s ))
{ [ $r -eq 0 ] && [ $e -lt 10 ]; } && ok "fixed module finishes (rc=0, ${e}s) without any budget help" || bad "fixed module rc=$r after ${e}s"
printf '%s\n' "$out" | grep -q $'^KEEP\tscripts/a.gd$' && ok "grounding output intact (KEEP scripts/a.gd)" || bad "KEEP row missing: $out"
mkdir -p "$T/oldd"; cp "$OLD" "$T/oldd/ovn_scout_ground.py"; cp "$T/ovn_park_unworkable.py" "$T/oldd/" 2>/dev/null
timeout 6 env OVN_SCOUT_BUDGET_S=0 python3 "$T/oldd/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/item.txt" 120000 >/dev/null 2>&1; r=$?
[ $r -eq 124 ] && ok "OLD code spins forever on the same input (timeout rc=124): the test can fail" || bad "old-code mutant did not hang (rc=$r): the regression test would not catch the bug"

echo "== root cause only the bounded walk: absolute '/x' style path (walk must terminate even without the token fix)"
mutant "$T/oldd/ovn_scout_ground.py" 'tok = clean_tok(tok)=>>tok = tok' || bad "mutant"
s=$(date +%s); timeout 15 env OVN_SCOUT_BUDGET_S=0 python3 "$T/oldd/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/item.txt" 120000 >/dev/null 2>&1; r=$?
[ $r -eq 0 ] && ok "bounded conftest walk alone terminates (rc=0)" || bad "bounded walk alone still hangs (rc=$r)"

echo "== wall-clock budget: even the OLD code cannot stall the loop"
mutant "$T/oldd/ovn_scout_ground.py" 'for _hop in range(40):=>>while True:' 'if not d or nd == d:=>>if not d:' 'tok = clean_tok(tok)=>>tok = tok' || bad "mutant"
s=$(date +%s); out="$(timeout 30 env OVN_SCOUT_BUDGET_S=2 python3 "$T/oldd/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/item.txt" 120000 2>"$T/err.txt")"; r=$?
e=$(( $(date +%s) - s ))
{ [ $r -eq 0 ] && [ $e -lt 10 ]; } && ok "hung grounding is killed at the budget: exit 0 after ${e}s" || bad "budget watchdog rc=$r after ${e}s"
grep -q 'scout: budget exceeded' "$T/err.txt" && ok "stderr says 'scout: budget exceeded'" || bad "no budget line: $(cat "$T/err.txt")"
printf '%s\n' "$out" | grep -q $'^KEEP\tscripts/a.gd$' && ok "pre-fixture grounding is kept (fixture stage skipped)" || bad "core rows lost on budget overrun: $out"
# budget hit before ANY row is final: plan unchanged = empty stdout, exit 0
mutant "$T/oldd/ovn_scout_ground.py" 'def tracked_files(root):=>>def tracked_files(root):
    while True: pass' || bad "mutant"
out="$(timeout 30 env OVN_SCOUT_BUDGET_S=1 python3 "$T/oldd/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/item.txt" 120000 2>"$T/err.txt")"; r=$?
{ [ $r -eq 0 ] && [ -z "$out" ] && grep -q 'plan used unchanged' "$T/err.txt"; } && ok "overrun before the first row: empty output, exit 0, plan used unchanged" || bad "early overrun rc=$r out='$out' err=$(cat "$T/err.txt")"
# a crash in the child is NOT swallowed as a budget event
mutant "$T/oldd/ovn_scout_ground.py" 'def tracked_files(root):=>>def tracked_files(root):
    raise RuntimeError("boom")' || bad "mutant"
timeout 30 env OVN_SCOUT_BUDGET_S=5 python3 "$T/oldd/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/item.txt" 120000 >/dev/null 2>&1; r=$?
[ $r -ne 0 ] && [ $r -ne 124 ] && ok "a real crash keeps its non-zero exit (rc=$r)" || bad "crash masked (rc=$r)"

echo "== quadratic PATH_RE on one long run of path characters"
python3 -c "print('x'*190000)" > "$T/long_item.txt"; printf '%s\n' '- [ ] tests/test_a.gd - add a case' >> "$T/long_item.txt"
s=$(date +%s); timeout 20 env OVN_SCOUT_BUDGET_S=0 python3 "$T/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/long_item.txt" 120000 >/dev/null 2>&1; r=$?; e=$(( $(date +%s) - s ))
{ [ $r -eq 0 ] && [ $e -lt 10 ]; } && ok "190 KB single-run item text: linear (${e}s)" || bad "long run rc=$r after ${e}s"
mutant "$T/oldd/ovn_scout_ground.py" 'def path_tokens(text):=>>def path_tokens(text):
    return PATH_RE.findall(text)' 'def strip_path_tokens(text):=>>def strip_path_tokens(text):
    return PATH_RE.sub(" ", text)' || bad "mutant"
timeout 8 env OVN_SCOUT_BUDGET_S=0 python3 "$T/oldd/ovn_scout_ground.py" "$R" "$T/log.txt" "$T/long_item.txt" 120000 >/dev/null 2>&1; r=$?
[ $r -eq 124 ] && ok "old unbounded PATH_RE needs > 8 s on the same text: the test can fail" || bad "unbounded PATH_RE mutant finished (rc=$r)"

echo "== model_index / definitions scans are bounded and linear"
python3 - "$T/ovn_scout_ground.py" <<'PY' && ok "model_index: 5000 classes in one file, linear" || bad "model_index slow or wrong"
import importlib.util, sys, tempfile, os, time, subprocess
spec = importlib.util.spec_from_file_location("g", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
d = tempfile.mkdtemp(prefix="ovn_idx_")
body = "".join("class C%d(Base):\n    x = 1\n" % i for i in range(5000)) + "class Last(Base):\n    __tablename__ = 'last'\n"
os.makedirs(d + "/app"); open(d + "/app/m.py", "w").write(body)
t = time.time(); tables, classes, texts = g.model_index(d, ["app/m.py"]); dt = time.time() - t
assert tables == {"last": "app/m.py"} and classes == {"Last": "app/m.py"}, (tables, classes)   # the table belongs to the LAST class only
assert dt < 3, dt
big = "static\n" * 60000   # the old `\s+` after a modifier spanned newlines: quadratic
open(d + "/app/k.kt", "w").write(big)
t = time.time(); g.find_definitions(d, ["app/k.kt"], {"zzz"}); assert time.time() - t < 3
PY
exit $rc
