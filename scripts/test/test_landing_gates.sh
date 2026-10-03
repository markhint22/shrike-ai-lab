#!/usr/bin/env bash
# Tests for the landing gates (2026-10-03, diagnosis A4): check_migrations.py revision-less/placeholder check,
# lib_dep_import_check.py (removed-but-imported requirement + clean-venv import), ovn_alembic_autogen.sh --drop-stubs,
# and the hook wiring in run_overnight.sh / branch_hygiene.sh / ovn_stage_runner.sh.
# Real incident fixtures: iptv_apps 0011_subscription_last_event_ms.py (docstring-only, no revision) and
# requirements.txt without aiohttp while app code imports it. Every check has a NEGATIVE (bad seeded) and a
# BENIGN (clean) control. Hermetic: the clean-venv test installs a locally-built wheel (no network).
set -uo pipefail
Q="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CM="$Q/scripts/check_migrations.py"; LIB="$Q/scripts/lib_dep_import_check.py"; AG="$Q/scripts/ovn_alembic_autogen.sh"
P=0; F=0
ok(){  if eval "$2" >/dev/null 2>&1; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
nok(){ if eval "$2" >/dev/null 2>&1; then F=$((F+1)); echo "  FAIL(expected-false): $1"; else P=$((P+1)); fi; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export OVN_DEP_CACHE="$T/cache"
export OVN_DEP_GATE=enforce   # the lib defaults to shadow; cases below that test the default unset it explicitly
G(){ git -c user.name=t -c user.email=t@t "$@"; }

# ---------- 1. check_migrations.py: stub / revision-less ----------
mk_chain(){ mkdir -p "$1/alembic/versions"; printf 'revision = "0010"\ndown_revision = None\n' > "$1/alembic/versions/0010_a.py"; }
d="$T/m1"; mk_chain "$d"
python3 "$CM" "$d" >/dev/null 2>&1; rc=$?
ok  "BENIGN clean chain -> exit 0" "[ $rc -eq 0 ]"
printf '"""Placeholder - the implement step fills in revision/down_revision/upgrade/downgrade."""\n' > "$d/alembic/versions/0011_subscription_last_event_ms.py"
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
nok "NEGATIVE placeholder stub -> non-zero" "[ $rc -eq 0 ]"
ok  "stub flagged by name + 'placeholder'" "printf '%s' \"\$out\" | grep -q '0011_subscription_last_event_ms.py.*placeholder'"
rm "$d/alembic/versions/0011_subscription_last_event_ms.py"
python3 "$CM" "$d" >/dev/null 2>&1; rc=$?
ok  "stub removed -> exit 0 again" "[ $rc -eq 0 ]"
printf '"""just a docstring, no marker"""\ndef upgrade(): pass\n' > "$d/alembic/versions/0012_norev.py"
out="$(python3 "$CM" "$d" 2>&1)"; rc=$?
nok "NEGATIVE revision-less file (no marker) -> non-zero" "[ $rc -eq 0 ]"
ok  "revision-less flagged" "printf '%s' \"\$out\" | grep -q \"0012_norev.py.*no 'revision'\""
printf 'revision: str = "0012"\ndown_revision: Union[str, None] = "0010"\n' > "$d/alembic/versions/0012_norev.py"
python3 "$CM" "$d" >/dev/null 2>&1; rc=$?
ok  "BENIGN annotated 'revision: str = ...' -> exit 0" "[ $rc -eq 0 ]"

# BENIGN: a filled-in migration that kept the placeholder docstring (revision present) must NOT be flagged
printf '"""Placeholder - the implement step fills in revision/down_revision/upgrade/downgrade."""\nrevision = "0013"\ndown_revision = "0012"\ndef upgrade(): pass\ndef downgrade(): pass\n' > "$d/alembic/versions/0013_filled.py"
python3 "$CM" "$d" >/dev/null 2>&1; rc=$?
ok  "BENIGN filled migration with leftover marker docstring -> exit 0" "[ $rc -eq 0 ]"
rm "$d/alembic/versions/0013_filled.py"

# real alembic agrees with the gate on the incident shape (skipped if no alembic on this host)
AL="$(ls "$HOME/qa-venv/bin/alembic" 2>/dev/null || command -v alembic || true)"
if [ -n "$AL" ]; then
  d="$T/real"; mkdir -p "$d/alembic/versions"
  printf '[alembic]\nscript_location = alembic\nsqlalchemy.url = sqlite:///%s/x.db\n' "$d" > "$d/alembic.ini"
  printf 'from alembic import context\ndef run_migrations_online():\n    pass\n' > "$d/alembic/env.py"
  printf '<%% print("") %%>\n' > /dev/null
  printf '"""x"""\nrevision = "0010"\ndown_revision = None\ndef upgrade(): pass\ndef downgrade(): pass\n' > "$d/alembic/versions/0010_a.py"
  ( cd "$d" && "$AL" heads ) >/dev/null 2>&1; ok "real alembic: clean chain loads" "[ $? -eq 0 ]"
  printf '"""Placeholder - the implement step fills in revision/down_revision/upgrade/downgrade."""\n' > "$d/alembic/versions/0011_subscription_last_event_ms.py"
  ( cd "$d" && "$AL" heads ) >/dev/null 2>&1; rc=$?
  nok "real alembic: the revision-less stub breaks 'alembic heads' (incident reproduced)" "[ $rc -eq 0 ]"
  python3 "$CM" "$d" >/dev/null 2>&1; rc=$?
  nok "check_migrations agrees with real alembic on the stub tree" "[ $rc -eq 0 ]"
else echo "  (alembic not on this host: real-alembic cases skipped)"; fi

# ---------- 2. removed-but-still-imported requirements ----------
mkrepo(){ rm -rf "$1"; mkdir -p "$1/app" "$1/tests"; G -C "$1" init -q; }
r="$T/r1"; mkrepo "$r"
printf 'fastapi==0.110\naiohttp==3.9\nrequests\n' > "$r/requirements.txt"
printf 'import aiohttp\nimport fastapi\n' > "$r/app/service.py"
printf 'import requests\n' > "$r/app/main.py"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"
printf 'fastapi==0.110\nrequests\n' > "$r/requirements.txt"; G -C "$r" commit -qam "drop aiohttp"
out="$(python3 "$LIB" removed --repo "$r" --before "$b" 2>&1)"; rc=$?
nok "NEGATIVE aiohttp removed while app imports it -> FAIL" "[ $rc -eq 0 ]"
ok  "names the package and the importing file" "printf '%s' \"\$out\" | grep -q \"'aiohttp'.*app/service.py\""
OVN_DEP_GATE=shadow python3 "$LIB" removed --repo "$r" --before "$b" >/dev/null 2>&1; ok "shadow mode never blocks" "[ $? -eq 0 ]"
OVN_DEP_GATE=off python3 "$LIB" removed --repo "$r" --before "$b" >/dev/null 2>&1; ok "off mode never blocks" "[ $? -eq 0 ]"
out="$(env -u OVN_DEP_GATE python3 "$LIB" removed --repo "$r" --before "$b" 2>&1)"; rc=$?
ok  "default mode is shadow: reports FAIL but exits 0" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q 'would FAIL'"
# swap of sibling distributions providing the same module is not a loss; google-api-python-client maps to googleapiclient
r="$T/r2b"; mkrepo "$r"
printf 'psycopg2-binary\ngoogle-api-python-client\n' > "$r/requirements.txt"; printf 'import psycopg2\nimport googleapiclient\n' > "$r/app/main.py"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"
printf 'psycopg2\n' > "$r/requirements.txt"; G -C "$r" commit -qam "swap + drop google"
out="$(python3 "$LIB" removed --repo "$r" --before "$b" 2>&1)"; rc=$?
nok "NEGATIVE google-api-python-client removed, 'import googleapiclient' remains -> FAIL" "[ $rc -eq 0 ]"
ok  "psycopg2-binary -> psycopg2 swap not reported" "! printf '%s' \"\$out\" | grep -q psycopg2"
# benign: removal of a package nothing imports
r="$T/r2"; mkrepo "$r"
printf 'fastapi\nunusedlib\n' > "$r/requirements.txt"; printf 'import fastapi\n' > "$r/app/main.py"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"
printf 'fastapi\n' > "$r/requirements.txt"; G -C "$r" commit -qam "drop unused"
python3 "$LIB" removed --repo "$r" --before "$b" >/dev/null 2>&1; ok "BENIGN removal of an unimported package -> pass" "[ $? -eq 0 ]"
# benign: only tests import it
r="$T/r3"; mkrepo "$r"
printf 'fastapi\naiohttp\n' > "$r/requirements.txt"; printf 'import fastapi\n' > "$r/app/main.py"; printf 'import aiohttp\n' > "$r/tests/test_x.py"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"
printf 'fastapi\n' > "$r/requirements.txt"; G -C "$r" commit -qam "drop"
python3 "$LIB" removed --repo "$r" --before "$b" >/dev/null 2>&1; ok "BENIGN test-only import of removed pkg -> pass" "[ $? -eq 0 ]"
# name mapping: pyjwt -> jwt
r="$T/r4"; mkrepo "$r"
printf 'fastapi\nPyJWT>=2\n' > "$r/requirements.txt"; printf 'import jwt\n' > "$r/app/main.py"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"
printf 'fastapi\n' > "$r/requirements.txt"; G -C "$r" commit -qam "drop"
python3 "$LIB" removed --repo "$r" --before "$b" >/dev/null 2>&1; nok "NEGATIVE pyjwt removed, 'import jwt' remains -> FAIL (mapping)" "[ $? -eq 0 ]"
# pre-existing mismatch not touched by the diff must not block (scoped to deleted lines)
r="$T/r5"; mkrepo "$r"
printf 'fastapi\n' > "$r/requirements.txt"; printf 'import aiohttp\n' > "$r/app/main.py"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"
printf 'fastapi\nextra\n' > "$r/requirements.txt"; G -C "$r" commit -qam "add extra"
python3 "$LIB" removed --repo "$r" --before "$b" >/dev/null 2>&1; ok "BENIGN pre-existing mismatch, nothing removed -> pass" "[ $? -eq 0 ]"
# moved to another requirements file -> still declared
r="$T/r6"; mkrepo "$r"
printf 'aiohttp\n' > "$r/requirements.txt"; printf 'import aiohttp\n' > "$r/app/main.py"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"
printf '' > "$r/requirements.txt"; printf 'aiohttp==3.9\n' > "$r/requirements-prod.txt"; G -C "$r" add -A; G -C "$r" commit -qm move
python3 "$LIB" removed --repo "$r" --before "$b" >/dev/null 2>&1; ok "BENIGN dependency moved to requirements-prod.txt -> pass" "[ $? -eq 0 ]"

# ---------- 3. clean-venv import of app.main (hermetic: local wheel) ----------
python3 - "$T" <<'PY'
import sys, zipfile, os
t = sys.argv[1]; os.makedirs(t + "/vendor", exist_ok=True)
w = t + "/vendor/fakeaio-1.0-py3-none-any.whl"
with zipfile.ZipFile(w, "w") as z:
    z.writestr("fakeaio/__init__.py", "X = 1\n")
    z.writestr("fakeaio-1.0.dist-info/METADATA", "Metadata-Version: 2.1\nName: fakeaio\nVersion: 1.0\n")
    z.writestr("fakeaio-1.0.dist-info/WHEEL", "Wheel-Version: 1.0\nGenerator: t\nRoot-Is-Purelib: true\nTag: py3-none-any\n")
    z.writestr("fakeaio-1.0.dist-info/RECORD", "")
PY
mkapp(){ rm -rf "$1"; mkdir -p "$1/app" "$1/vendor"; cp "$T/vendor/fakeaio-1.0-py3-none-any.whl" "$1/vendor/"; touch "$1/app/__init__.py"; }
a="$T/app1"; mkapp "$a"; printf 'import fakeaio\napp = fakeaio.X\n' > "$a/app/main.py"
printf '' > "$a/requirements.txt"
out="$(python3 "$LIB" clean-import --repo "$a" 2>&1)"; rc=$?
nok "NEGATIVE requirements.txt lacks the imported dep -> FAIL" "[ $rc -eq 0 ]"
ok  "failure names the module" "printf '%s' \"\$out\" | grep -q \"module 'fakeaio'\""
printf './vendor/fakeaio-1.0-py3-none-any.whl\n' > "$a/requirements.txt"
out="$(python3 "$LIB" clean-import --repo "$a" 2>&1)"; rc=$?
ok  "BENIGN dep present in requirements.txt -> PASS" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q 'PASS'"
n1="$(ls "$OVN_DEP_CACHE" | wc -l)"; python3 "$LIB" clean-import --repo "$a" >/dev/null 2>&1
ok  "venv cached by requirements hash (no new venv on 2nd run)" "[ \"\$(ls '$OVN_DEP_CACHE' | wc -l)\" = '$n1' ]"
# non-dependency import failure -> UNVERIFIED (exit 0)
a2="$T/app2"; mkapp "$a2"; printf 'raise RuntimeError("needs DATABASE_URL")\n' > "$a2/app/main.py"; printf '' > "$a2/requirements.txt"
out="$(python3 "$LIB" clean-import --repo "$a2" 2>&1)"; rc=$?
ok  "env-dependent app import failure -> UNVERIFIED, exit 0" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q UNVERIFIED"
# pip failure (unresolvable local path) -> UNVERIFIED, never blocks
a3="$T/app3"; mkapp "$a3"; printf 'import os\n' > "$a3/app/main.py"; printf './vendor/nope.whl\n' > "$a3/requirements.txt"
out="$(python3 "$LIB" clean-import --repo "$a3" 2>&1)"; rc=$?
ok  "pip install failure -> UNVERIFIED, exit 0" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q UNVERIFIED"
ok  "pip failure leaves a negative-cache marker" "ls '$OVN_DEP_CACHE' | grep -q '\\.fail$'"
out="$(python3 "$LIB" clean-import --repo "$a3" 2>&1)"; rc=$?
ok  "second run served by negative cache (no pip retry)" "[ $rc -eq 0 ] && printf '%s' \"\$out\" | grep -q 'negative cache'"
# no backend at all
mkdir -p "$T/none"; python3 "$LIB" clean-import --repo "$T/none" >/dev/null 2>&1; ok "no app/main.py -> exit 0" "[ $? -eq 0 ]"
# gate: no dependency file touched -> clean-import not run
r="$T/r7"; mkrepo "$r"; printf 'x\n' > "$r/app/main.py"; printf 'import nothere\n' >> "$r/app/main.py"; printf '' > "$r/requirements.txt"
G -C "$r" add -A; G -C "$r" commit -qm base; b="$(G -C "$r" rev-parse HEAD)"; printf 'y\n' > "$r/other.txt"; G -C "$r" add other.txt; G -C "$r" commit -qm other
out="$(python3 "$LIB" gate --repo "$r" --before "$b" 2>&1)"; rc=$?
ok  "gate: diff without dependency files is not checked -> exit 0, no clean-import" "[ $rc -eq 0 ] && ! printf '%s' \"\$out\" | grep -q clean-import"

# ---------- 4. ovn_alembic_autogen.sh --drop-stubs ----------
r="$T/s1"; mkdir -p "$r/svc/alembic/versions"; G -C "$r" init -q
printf 'revision = "0010"\ndown_revision = None\n' > "$r/svc/alembic/versions/0010_a.py"
G -C "$r" add -A; G -C "$r" commit -qm base; h0="$(G -C "$r" rev-parse HEAD)"
git -c user.name=t -c user.email=t@t -C "$r" status --short >/dev/null
bash "$AG" --drop-stubs "$r" >/dev/null 2>&1
ok  "BENIGN no stub -> no commit, HEAD unchanged" "[ \"\$(git -C '$r' rev-parse HEAD)\" = '$h0' ]"
printf '"""Placeholder - the implement step fills in revision/down_revision/upgrade/downgrade."""\n' > "$r/svc/alembic/versions/0011_stub.py"
printf '"""Placeholder - the implement step fills in x"""\nrevision = "0012"\ndown_revision = "0010"\n' > "$r/svc/alembic/versions/0012_filled_keeps_marker.py"
G -C "$r" add -A; G -C "$r" commit -qm "stub commit"
out="$(GIT_AUTHOR_NAME=t GIT_COMMITTER_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_EMAIL=t@t bash "$AG" --drop-stubs "$r" 2>&1)"
ok  "NEGATIVE stub is deleted from the tree" "[ ! -e '$r/svc/alembic/versions/0011_stub.py' ]"
ok  "deletion is committed (tree clean)" "git -C '$r' diff --quiet HEAD && [ -z \"\$(git -C '$r' status --porcelain)\" ]"
ok  "stub gone from HEAD" "! git -C '$r' ls-files | grep -q 0011_stub"
ok  "a file with a revision is kept even if it carries the marker" "[ -e '$r/svc/alembic/versions/0012_filled_keeps_marker.py' ]"
ok  "status line printed" "printf '%s' \"\$out\" | grep -q 'removed unfilled placeholder stub'"
# commit must be scoped to the deleted stub: an unrelated staged file is NOT swept into it, and stays staged
printf '"""Placeholder - the implement step fills in x"""\n' > "$r/svc/alembic/versions/0014_stub2.py"
G -C "$r" add svc/alembic/versions/0014_stub2.py; G -C "$r" commit -qm "stub2"
printf 'keep\n' > "$r/b.txt"; G -C "$r" add b.txt
GIT_AUTHOR_NAME=t GIT_COMMITTER_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_EMAIL=t@t bash "$AG" --drop-stubs "$r" >/dev/null 2>&1
ok  "NEGATIVE staged unrelated file not swept into the stub-drop commit" "! git -C '$r' show --name-only --format= HEAD | grep -q b.txt"
ok  "unrelated file still staged afterwards" "git -C '$r' diff --cached --name-only | grep -q b.txt"
G -C "$r" reset -q b.txt; rm -f "$r/b.txt"
# commit failure (no identity) must not reset --hard unrelated working-tree edits
printf '"""Placeholder - the implement step fills in x"""\n' > "$r/svc/alembic/versions/0015_stub3.py"
G -C "$r" add svc/alembic/versions/0015_stub3.py; G -C "$r" commit -qm "stub3"
printf 'edit\n' > "$r/svc/alembic/versions/0010_a.py"
( export HOME="$T/nohome" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME= GIT_COMMITTER_NAME= GIT_AUTHOR_EMAIL= GIT_COMMITTER_EMAIL= EMAIL=; bash "$AG" --drop-stubs "$r" >/dev/null 2>&1 )
ok  "BENIGN failed commit keeps unrelated uncommitted edits" "grep -q edit '$r/svc/alembic/versions/0010_a.py'"
git -C "$r" checkout -q -- svc/alembic/versions/0010_a.py 2>/dev/null
OVN_ALEMBIC_AUTOGEN_DISABLE=1 bash "$AG" --drop-stubs "$r" >/dev/null 2>&1; ok "kill switch exits 0" "[ $? -eq 0 ]"
bash "$AG" --drop-stubs "$T/does-not-exist" >/dev/null 2>&1; ok "bad repo path exits 0" "[ $? -eq 0 ]"

# ---------- 5. hook wiring + fail-safe guards ----------
RO="$Q/run_overnight.sh"; BH="$Q/branch_hygiene.sh"; SR="$Q/ovn_stage_runner.sh"
_a="$(grep -n -- '--drop-stubs' "$RO" | head -1 | cut -d: -f1)"; _b="$(grep -n '_migcheck_out="\$(python3' "$RO" | head -1 | cut -d: -f1)"
ok  "run_overnight: drop-stubs before migration gate" "[ -n '$_a' ] && [ -n '$_b' ] && [ '$_a' -lt '$_b' ]"
ok  "run_overnight: drop-stubs again after the revert" "grep -B3 'emit_alert warn \"\$id\" \"migration-safety gate reverted' '$RO' | grep -q -- '--drop-stubs'"
ok  "run_overnight: dep gate guarded by [ -f lib ] (fail-safe)" "grep -q 'if \\[ -f \"\$SCRIPT_DIR/scripts/lib_dep_import_check.py\" \\]' '$RO'"
ok  "run_overnight: dep gate reverts with reverted(dep-import)" "grep -q 'reverted(dep-import)' '$RO'"
ok  "branch_hygiene: clean-import gate guarded by [ -f lib ]" "grep -q 'if \\[ -f \"\$HOME/overnight-queue/scripts/lib_dep_import_check.py\" \\]' '$BH'"
ok  "stage runner full_verify: lib guarded + vok=0 on fail" "grep -q 'DEP-IMPORT FAIL' '$SR' && grep -q 'if \\[ -f scripts/lib_dep_import_check.py \\]' '$SR'"
ok  "stage runner full_verify runs check_migrations" "grep -q 'MIGRATION SAFETY FAIL (see above)' '$SR'"
for f in "$RO" "$BH" "$SR" "$AG"; do ok "bash -n $(basename "$f")" "bash -n '$f'"; done

echo "landing gates: $P passed, $F failed"
[ "$F" -eq 0 ]
