#!/usr/bin/env bash
# G9 gold row (2026-10-16): the landing dep-removal check is replayed through qa_replay.py --gold.
# Fixture: a temp repo with a requirements removal whose import remains (must be CAUGHT, FAIL) and a benign commit
# touching no dependency file (must be CLEAN). Also checks the shipped gold_set.json / QA_GOLD_SET.md G9 wiring.
# Hermetic: env -i, temp repos via OVN_REPOS_DIR, no network. Runs both as an absolute and a relative path.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
Q="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P=0; F=0
ok(){  if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
T="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$T"' EXIT
G(){ git -c user.name=t -c user.email=t@t "$@"; }
mkdir -p "$T/repos/fixrepo/app" "$T/home"
R="$T/repos/fixrepo"
G -C "$R" init -q
printf 'fastapi\naiohttp==3.9\n' > "$R/requirements.txt"; printf 'import aiohttp\nimport fastapi\n' > "$R/app/service.py"
G -C "$R" add -A; G -C "$R" commit -qm base; B1="$(G -C "$R" rev-parse HEAD)"
printf 'fastapi\n' > "$R/requirements.txt"; G -C "$R" commit -qam "fleet drops aiohttp, code still imports it"; H1="$(G -C "$R" rev-parse HEAD)"
printf 'print("docs")\n' > "$R/README.md"; G -C "$R" add -A; G -C "$R" commit -qm "docs only"; H2="$(G -C "$R" rev-parse HEAD)"
cat > "$T/gold.json" <<JSON
{"rows": [
 {"id": "G9", "repo": "fixrepo", "base": "$B1", "head": "$H1", "gate": "landing:lib_dep_import_check:removed", "kind": "true_positive", "title": "fixture"},
 {"id": "C1", "repo": "fixrepo", "base": "$H1", "head": "$H2", "gate": "landing:lib_dep_import_check:removed", "kind": "benign", "title": "fixture control"}
]}
JSON
run_replay(){ # $1 = path to qa_replay.py as given (absolute or relative to $Q)
  ( cd "$Q" && env -i PATH="$PATH" HOME="$T/home" OVN_REPOS_DIR="$T/repos" python3 "$1" --gold --gold-file "$T/gold.json" --only G9,C1 2>&1 )
}
out_abs="$(run_replay "$Q/qa/qa_replay.py")"; rc_abs=$?
out_rel="$(run_replay "qa/qa_replay.py")"; rc_rel=$?
ok  "absolute path: G9 (removed-but-imported) is CAUGHT" "printf '%s' \"\$out_abs\" | grep -q 'G9 .*landing:lib_dep_import_check:removed *CAUGHT'"
ok  "relative path: G9 is CAUGHT" "printf '%s' \"\$out_rel\" | grep -q 'G9 .*landing:lib_dep_import_check:removed *CAUGHT'"
ok  "benign docs-only commit (no dependency file) is CLEAN" "printf '%s' \"\$out_abs\" | grep -q 'C1 .*CLEAN'"
ok  "G9 is not EXPECTED_AFTER_MERGE or MISSED" "! printf '%s' \"\$out_abs\" | grep -q 'G9 .*\\(EXPECTED_AFTER_MERGE\\|MISSED\\|UNMEASURED\\)'"
nok "no FALSE_POSITIVE in the fixture replay" "printf '%s' \"\$out_abs\" | grep -q FALSE_POSITIVE"
# the gate itself, run the way the replay runs it: HEAD equals after, enforce mode
ok  "lib exits 1 on the removed-but-imported fixture (HEAD == after)" "cd '$R' && env -i PATH=\"\$PATH\" HOME='$T/home' OVN_DEP_GATE=enforce python3 '$Q/scripts/lib_dep_import_check.py' removed --repo '$R' --before '$B1' --after '$H1'; [ \$? -eq 1 ]"
# shipped wiring
ok  "shipped gold_set.json: G9 gate is the landing removed-mode check" "python3 -c \"import json,sys; r=[x for x in json.load(open(sys.argv[1]))['rows'] if x['id']=='G9'][0]; sys.exit(0 if r['gate']=='landing:lib_dep_import_check:removed' and 'pending' not in r else 1)\" '$Q/qa/gold_set.json'"
# the gold doc lives at the repo root (docs/), outside scripts/overnight-queue: a box or live-dir copy of the queue tree has no docs/.
# Absent -> an explicit SKIP with its reason (not a PASS, not a FAIL); present -> the G9 row must say CAUGHT.
DOC="$Q/../../docs/QA_GOLD_SET.md"
S=0
if [ -f "$DOC" ]; then
  ok  "shipped QA_GOLD_SET.md: G9 row says CAUGHT" "grep -q '^| G9 .*CAUGHT' '$DOC'"
else
  S=$((S+1)); echo "  SKIP: shipped QA_GOLD_SET.md G9 row not checked - $DOC is not in this tree (docs/ lives at the repo root, outside scripts/overnight-queue)"
fi
echo "qa gold G9: $P passed, $F failed, $S skipped"
[ "$F" -eq 0 ]
