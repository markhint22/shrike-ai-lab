#!/usr/bin/env bash
# Z2 (2026-11-07): scout fixture grounding (ovn_scout_ground.py) - the real module must pass test_z2_scout_fixtures.py, and every mutant of the new code must FAIL it
# (mutation proof: a regression test that cannot fail on the old behaviour is not a test).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }
SRC="$HERE/../../ovn_scout_ground.py"; [ -f "$SRC" ] || SRC="$HERE/../ovn_scout_ground.py"
[ -f "$SRC" ] || { echo "  SKIP: ovn_scout_ground.py not found"; exit 0; }
T="$(safe_mktemp_dir)" || exit 1
trap 'rm -rf "${T:?}"' EXIT
rc=0
echo "== real module"
OVN_SCOUT_GROUND_PY="$SRC" python3 "$HERE/test_z2_scout_fixtures.py" 2>/dev/null || rc=1
mut(){  # $1=label $2=python expression of the edit (operates on s)
  cp "$SRC" "$T/ovn_scout_ground.py"; cp "$(dirname "$SRC")/ovn_park_unworkable.py" "$T/" 2>/dev/null
  python3 - "$T/ovn_scout_ground.py" "$2" <<'PY'
import sys
p, old_new = sys.argv[1], sys.argv[2].split("=>>")
s = open(p).read()
assert old_new[0] in s, "mutation anchor missing: " + old_new[0]
open(p, "w").write(s.replace(old_new[0], old_new[1], 1))
PY
  if OVN_SCOUT_GROUND_PY="$T/ovn_scout_ground.py" python3 "$HERE/test_z2_scout_fixtures.py" >/dev/null 2>&1; then echo "  FAIL: mutant '$1' SURVIVED"; rc=1; else echo "  ok   mutant '$1' is killed"; fi
}
echo "== mutants"
mut "fixture grounding returns nothing"      '    return cands
=>>    return []
'
mut "FK parents not followed"                'for tgt in FK_RE.findall(txt):=>>for tgt in []:'
mut "conftest never added"                   'while found < 2:=>>while False:'
mut "extra-file bound ignored"               'if path in workable or len(extras) >= max_extra or too_big_or_banned(path):=>>if path in workable or too_big_or_banned(path):'
mut "byte budget ignored"                    '            if extra_bytes + sz > budget_left:
                continue
            extras.append((path, why)); extra_bytes += sz; added_bytes += sz=>>            extras.append((path, why)); extra_bytes += sz; added_bytes += sz'
mut "non-DB tests also pulled in"            'needs = bool(loaded_models) or bool(DB_HINT_RE.search(item_text)) or bool(DB_HINT_RE.search(test_txt))=>>needs = True'
mut "named model classes not loaded"         'if pf and pf not in seen_p and pf not in workable and named < 3:=>>if False:'
exit $rc
