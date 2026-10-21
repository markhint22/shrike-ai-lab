#!/usr/bin/env bash
# 2026-10-20: a manual bug was queued aimed at a comment line (EpgScreen.kt:60 '/** Grid = ...') and at a file that only shared
# the note's word (PlayerActivity.kt, 'player'). A fix aimed at prose or the wrong file lands nothing. The gate refuses such
# candidates -> needs-triage. Tests the SHIPPED helpers in qa/manual_notes_ingest.py on the dry-run evidence shapes, plus a mutant.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; QUEUE="$HERE/../.."; ING="$QUEUE/qa/manual_notes_ingest.py"
P=0; F=0
ok(){ if eval "$2" >/dev/null 2>&1; then P=$((P+1)); echo "  ok   $1"; else F=$((F+1)); echo "  FAIL $1"; fi; }
source "$HERE/lib_safe_tmp.sh" || { echo "cannot source lib_safe_tmp.sh" >&2; exit 2; }
T="$(safe_mktemp_dir supportgate)" || exit 1
cleanup(){ safe_rm_rf "$T"; }
trap cleanup EXIT

# py_support <path-to-ingest> <case> -> prints True/False from the given module's _support_is_code
cat > "$T/probe.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("m", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
def c(e, mt): return {"path": "a.kt", "score": 5.0, "evidence": e, "matched": mt, "located": True}
cases = {
    "comment":  c("a/EpgScreen.kt:60: /** Grid = the real stream list", ["countries"]),
    "code":     c("a/Real.kt:12: val countries = filterCountries(x)", ["countries"]),
    "filename": c("a/PlayerActivity.kt (file name is 'player')", ["player (file is named after it)"]),
    "named":    c("a/x.kt (named in the note)", ["named in note"]),
}
print(m._support_is_code(cases[sys.argv[2]]))
PY
py_support(){ python3 -I "$T/probe.py" "$1" "$2"; }

echo "== the dry-run failures are refused"
ok "comment-only support (EpgScreen.kt /** Grid comment) is NOT code support" "[ \"\$(py_support '$ING' comment)\" = False ]"
ok "file-name-only support (PlayerActivity.kt 'player') is NOT code support" "[ \"\$(py_support '$ING' filename)\" = False ]"
echo "== real support is accepted"
ok "a real code line is code support" "[ \"\$(py_support '$ING' code)\" = True ]"
ok "a file the note names is code support" "[ \"\$(py_support '$ING' named)\" = True ]"
echo "== comment detection"
ok "a javadoc continuation line is a comment" "python3 -I -c \"import importlib.util as u;s=u.spec_from_file_location('m','$ING');m=u.module_from_spec(s);s.loader.exec_module(m);assert m.is_comment_line(' * Grid = x')\""
ok "a code line is not a comment" "python3 -I -c \"import importlib.util as u;s=u.spec_from_file_location('m','$ING');m=u.module_from_spec(s);s.loader.exec_module(m);assert not m.is_comment_line('    val x = 1')\""
echo "== the gate is wired into the decision (not just defined)"
ok "locate path refuses weak support before queuing" "grep -q '_support_is_code(good\[0\])' '$ING'"
ok "a refused candidate is recorded with its reason" "grep -q 'triage_reason' '$ING'"
echo "== mutant: the gate disabled must let the comment through"
sed 's/^def _support_is_code(cand):$/def _support_is_code(cand):\n    return True/' "$ING" > "$T/mut.py"
if [ "$(py_support "$T/mut.py" comment)" = True ]; then echo "  ok   mutant caught: gate disabled lets the comment through"; P=$((P+1)); else echo "  MUTANT-SURVIVED"; F=$((F+1)); fi
echo "manual_notes_support_gate: $P passed, $F failed"
[ "$F" -eq 0 ]
