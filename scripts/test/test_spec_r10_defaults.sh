#!/usr/bin/env bash
# 2026-10-10 (harness R10): spec-gate rules R11 (gut_cli.gd -> gut_cmdln.gd repair) and R12 (VERIFY names a test path nothing creates), and the DEFAULT enforce set
# (OVN_SPEC_GATE_ENFORCE_RULES UNSET = R01,R11: the static repair-only rules; an explicitly set value - empty / `none` included - wins).
#
# Live defects replayed:
#   IPTV-2   the planner emitted bare `VERIFY: pytest ... (cat:..)` lines every pass ("spec-gate lint (shadow, nothing rewritten): R01=6"): R01 existed, was golden-tested, and was never armed.
#   BX-06    xlite techs_data: 20 progress lines called `godot -s addons/gut/cli/gut_cli.gd` (a Node: it can never be an entry point), and the roster-coerce items VERIFY'd
#            `godot -s tests/test_roster_coercion.gd`, a file nothing creates.
# Sections: A R11 golden, B R12 (real git repo as the ref), C default enforce in queue_refill.py, D default enforce in `ovn_spec_gate.py lint`, E scan rows carry R11/R12.
set -uo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)/lib_safe_tmp.sh" || { echo "  FAIL: lib_safe_tmp.sh missing"; exit 1; }   # 2026-10-16: fail-closed sandbox helpers (see lint_unsafe_rm.py)
HERE="$(cd "$(dirname "$0")" && pwd)"
S="$HERE/.."; [ -f "$S/ovn_spec_rules.py" ] || S="$HERE"
Q="$(cd "$S/.." && pwd)"; QR="$Q/queue_refill.py"
[ -f "$S/ovn_spec_rules.py" ] || { echo "  SKIP: ovn_spec_rules.py not found"; exit 0; }
P=0; F=0
ok(){ if _pf="$(set +o | grep ' pipefail$')"; set +o pipefail; eval "$2" >/dev/null 2>&1; _rc=$?; eval "$_pf"; [ "$_rc" = 0 ]; then P=$((P+1)); else F=$((F+1)); echo "  FAIL: $1"; fi; }
tmp="$(safe_mktemp_dir)" || exit 1; trap 'rm -rf "$tmp"' EXIT

echo "== A: R11 (gut_cli.gd -> gut_cmdln.gd)"
cat > "$tmp/a.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ovn_spec_rules as R
BAD_TICK = '- [ ] [T2] tests/test_tech_manager.gd — x VERIFY: `godot --headless -s addons/gut/cli/gut_cli.gd -gdir=tests -gtest=test_tech_manager.gd -gexit`. (cat:test; multifile:no)'
BAD_BARE = '- [ ] [T2] tests/test_tech_manager.gd — x VERIFY: godot --headless -s res://addons/gut/cli/gut_cli.gd -gdir=tests -gexit. (cat:test; multifile:no)'
GOOD = '- [ ] [T2] tests/test_tech_manager.gd — x VERIFY: `godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gexit`. (cat:test; multifile:no)'
PROSE = '- [ ] [T2] a.py — mention addons/gut/cli/gut_cli.gd in the doc comment. VERIFY: `grep -q doc a.py`. (cat:python)'
out = []
l2, fs = R.lint_static(BAD_TICK, only={"R11"})
out.append(("tick-rewritten", "addons/gut/gut_cmdln.gd" in l2 and "gut_cli" not in l2 and [f["rule"] for f in fs] == ["R11"] and fs[0]["sev"] == "repair"))
l3, fs = R.lint_static(BAD_BARE, only={"R11"})
out.append(("bare-res-rewritten", "res://addons/gut/gut_cmdln.gd" in l3 and "gut_cli" not in l3))
out.append(("golden-exact", l2 == BAD_TICK.replace("addons/gut/cli/gut_cli.gd", "addons/gut/gut_cmdln.gd")))
l4, fs = R.lint_static(GOOD, only={"R11"})
out.append(("good-untouched", l4 == GOOD and not fs))
l5, fs = R.lint_static(PROSE, only={"R11"})
out.append(("item-text-mention-untouched", l5 == PROSE and not fs))
out.append(("idempotent", R.lint_static(l2, only={"R11"})[0] == l2))
out.append(("in-STATIC_RULE_IDS", "R11" in R.STATIC_RULE_IDS and R.STATIC_RULE_IDS[:3] == ("R01", "R02", "R03")))
l6, fs = R.lint_static(BAD_BARE)   # all static rules: R01 backticks it, R11 rewrites it
out.append(("R01+R11 compose", "VERIFY: `godot --headless -s res://addons/gut/gut_cmdln.gd" in l6 and sorted(f["rule"] for f in fs) == ["R01", "R11"]))
for k, v in out:
    print(("OK   " if v else "FAIL ") + k)
PY
python3 "$tmp/a.py" "$S" > "$tmp/a.out" 2>&1
for k in tick-rewritten bare-res-rewritten golden-exact good-untouched item-text-mention-untouched idempotent in-STATIC_RULE_IDS "R01+R11 compose"; do
  ok "A: $k" "grep -qx 'OK   $k' '$tmp/a.out'"
done

echo "== B: R12 (VERIFY names a test path that does not exist and nothing creates)"
command -v git >/dev/null 2>&1 || { echo "  SKIP: no git"; }
R="$tmp/repo"; mkdir -p "$R/tests" "$R/scripts"; git -C "$R" init -q 2>/dev/null
printf 'extends GutTest\n' > "$R/tests/test_exists.gd"; printf 'x=1\n' > "$R/scripts/a.gd"
mkdir -p "$R/iptv-backend/tests" "$R/web/tests"; printf 'def test_x(): pass\n' > "$R/iptv-backend/tests/test_content_dedup.py"; printf 'def test_y(): pass\n' > "$R/web/tests/test_web.py"
git -C "$R" add -A; git -C "$R" -c user.email=t@t -c user.name=t commit -q -m seed
cat > "$tmp/b.py" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ovn_spec_rules as R
ctx = R.Ctx(sys.argv[2], ref="HEAD")
def it(tier, target, text, verify, feat="f1"):
    return '- [ ] [%s] %s — %s VERIFY: `%s`. (cat:test; multifile:no) [feat:%s]' % (tier, target, text, verify, feat)
MISSING = it("T3", "scripts/a.gd", "Coerce entries to arrays", "godot --headless -s tests/test_roster_coercion.gd")
EXISTS = it("T2", "scripts/a.gd", "Tweak a", "godot --headless -s addons/gut/gut_cmdln.gd -gdir=tests -gtest=test_exists.gd -gexit")
CREATES = it("T2", "tests/test_new.gd", "Create tests/test_new.gd with a test", "godot --headless -s addons/gut/gut_cmdln.gd -gtest=test_new.gd -gexit")
SIB_A = it("T2", "tests/test_sib.gd", "Create tests/test_sib.gd covering a", "godot --headless -s addons/gut/gut_cmdln.gd -gtest=test_sib.gd -gexit", "f2")
SIB_B = it("T2", "scripts/a.gd", "Tweak a", "godot --headless -s addons/gut/gut_cmdln.gd -gtest=test_sib.gd -gexit", "f2")
OTHERFEAT = it("T2", "scripts/a.gd", "Tweak a", "godot --headless -s addons/gut/gut_cmdln.gd -gtest=test_sib.gd -gexit", "f3")
PYMISS = it("T2", "app/x.py", "Fix x", "pytest tests/test_nothing_here.py::test_x -q")
NONTEST = it("T2", "scripts/a.gd", "Tweak a", "godot --headless --check-only -s scripts/other_missing.gd")
CD_OK = it("T2", "iptv-backend/app/x.py", "Fix x", "cd iptv-backend && python3 -m pytest tests/test_content_dedup.py -q")
CD_SUB = it("T2", "iptv-backend/app/x.py", "Fix x", "(cd iptv-backend && pytest tests/test_content_dedup.py::test_x -q)")
CD_QUOTED = it("T2", "iptv-backend/app/x.py", "Fix x", "cd 'iptv-backend' && pytest tests/test_content_dedup.py")
CD_MISS = it("T2", "iptv-backend/app/x.py", "Fix x", "cd iptv-backend && python3 -m pytest tests/test_nothing_here.py -q")
CD_WRONGDIR = it("T2", "iptv-backend/app/x.py", "Fix x", "cd web && python3 -m pytest tests/test_content_dedup.py -q")
CD_ABS = it("T2", "iptv-backend/app/x.py", "Fix x", "cd /elsewhere && pytest tests/test_content_dedup.py")
def r12(lines):
    out = R.lint_batch(lines, ctx)
    return [[f["rule"] for f in fs if f["rule"] == "R12"] for _, fs in out], out
def show(k, v): print(("OK   " if v else "FAIL ") + k)
res, out = r12([MISSING]); show("missing-test-rejected", res[0] == ["R12"])
fl = [f for f in out[0][1] if f["rule"] == "R12"]
f = fl[0] if fl else {}
show("sev-reject-and-names-the-path", f.get("sev") == "reject" and f.get("evidence") == ["tests/test_roster_coercion.gd"])
res, _ = r12([EXISTS]); show("existing-test-passes", res[0] == [])
res, _ = r12([CREATES]); show("item-creating-its-own-test-passes", res[0] == [])
res, _ = r12([SIB_A, SIB_B]); show("test-created-by-a-sibling-of-the-same-feat-passes", res == [[], []])
res, _ = r12([SIB_A, OTHERFEAT]); show("sibling-of-ANOTHER-feat-does-not-count", res == [[], ["R12"]])
res, _ = r12([PYMISS]); show("pytest-missing-test-file-rejected", res[0] == ["R12"])
res, _ = r12([CD_OK]); show("cd-prefixed-pytest-on-an-existing-file-passes", res[0] == [])
res, _ = r12([CD_SUB]); show("subshell-cd-pytest-with-node-id-passes", res[0] == [])
res, _ = r12([CD_QUOTED]); show("quoted-cd-dir-passes", res[0] == [])
res, _ = r12([CD_MISS]); show("cd-prefixed-pytest-on-a-missing-file-still-rejected", res[0] == ["R12"])
res, _ = r12([CD_WRONGDIR]); show("cd-into-the-wrong-dir-still-rejected", res[0] == ["R12"])
res, _ = r12([CD_ABS]); show("cd-to-an-absolute-dir-is-not-trusted", res[0] == ["R12"])
res, _ = r12([NONTEST]); show("non-test-script-path-not-judged", res[0] == [])
res, _ = R.lint_batch([MISSING], None) and r12([MISSING]);
out2 = R.lint_batch([MISSING], None); show("no-ctx-says-nothing", not [f for f in out2[0][1] if f["rule"] == "R12"])
empty = R.Ctx("/nonexistent-dir-xyz", ref="HEAD"); out3 = R.lint_batch([MISSING], empty); show("no-tree-says-nothing", not [f for f in out3[0][1] if f["rule"] == "R12"])
PY
python3 "$tmp/b.py" "$S" "$R" > "$tmp/b.out" 2>&1
for k in cd-prefixed-pytest-on-an-existing-file-passes subshell-cd-pytest-with-node-id-passes quoted-cd-dir-passes cd-prefixed-pytest-on-a-missing-file-still-rejected cd-into-the-wrong-dir-still-rejected cd-to-an-absolute-dir-is-not-trusted missing-test-rejected sev-reject-and-names-the-path existing-test-passes item-creating-its-own-test-passes test-created-by-a-sibling-of-the-same-feat-passes sibling-of-ANOTHER-feat-does-not-count pytest-missing-test-file-rejected non-test-script-path-not-judged no-ctx-says-nothing no-tree-says-nothing; do
  ok "B: $k" "grep -qx 'OK   $k' '$tmp/b.out'"
done

echo "== C: queue_refill.py default enforce (UNSET = R01,R11; set-but-empty = nothing)"
mkq(){ local d="$1"; rm -rf "${d:?}"; mkdir -p "$d/repos/demo" "$d/backlog" "$d/state" "$d/scripts"; cp "$S"/*.py "$d/scripts/" 2>/dev/null; cp "$QR" "$d/queue_refill.py"
  printf '# Progress\n## Next Steps\n' > "$d/repos/demo/OVERNIGHT_PROGRESS.md"; : > "$d/repos/demo/OVERNIGHT_DONE.md"; }
L_BARE='- [ ] [T2] f.txt — rename old. VERIFY: grep -q old f.txt (cat:python; multifile:no)'
L_GUTCLI='- [ ] [T2] tests/t.gd — add a case. VERIFY: `godot --headless -s addons/gut/cli/gut_cli.gd -gdir=tests -gexit`. (cat:test; multifile:no)'
L_VAC='- [ ] [T2] g.txt — rename old. VERIFY: `grep -q old g.txt && echo "FAIL" || echo "PASS"`. (cat:python; multifile:no)'
L_NARR='- [ ] [T2] h.txt — remove old. VERIFY: `grep -q old h.txt` returns non-zero after the change. (cat:python; multifile:no)'
refill(){ local d="$1"; shift; ( cd "$d" && env "$@" python3 queue_refill.py repos/demo/OVERNIGHT_PROGRESS.md backlog/demo.md 10 ) >/dev/null 2>&1; }
D="$tmp/q1"; mkq "$D"; printf '%s\n%s\n%s\n%s\n' "$L_BARE" "$L_GUTCLI" "$L_VAC" "$L_NARR" > "$D/backlog/demo.md"
env -u OVN_SPEC_GATE_ENFORCE_RULES OVN_SPEC_GATE_NOW=2026-10-10T00:00:00Z bash -c "cd '$D' && python3 queue_refill.py repos/demo/OVERNIGHT_PROGRESS.md backlog/demo.md 10" >/dev/null 2>&1
PG="$D/repos/demo/OVERNIGHT_PROGRESS.md"
ok "C1 UNSET env: the bare VERIFY is pulled BACKTICKED (R01 on by default)" "grep -qF -- 'VERIFY: \`grep -q old f.txt\` (cat:python' '$PG'"
ok "C2 UNSET env: the gut_cli.gd VERIFY is pulled rewritten to gut_cmdln.gd (R11 on by default)" "grep -qF -- 'addons/gut/gut_cmdln.gd' '$PG' && ! grep -qF -- 'gut_cli.gd' '$PG'"
ok "C3 UNSET env: R02 (vacuous echo) and R03 (narrated failure) stay OPT-IN: those two lines are pulled byte-for-byte" "grep -qxF -- '$L_VAC' '$PG' && grep -qxF -- '$L_NARR' '$PG'"
D="$tmp/q2"; mkq "$D"; printf '%s\n%s\n' "$L_BARE" "$L_GUTCLI" > "$D/backlog/demo.md"; refill "$D" OVN_SPEC_GATE_ENFORCE_RULES=
ok "C4 KILL SWITCH: OVN_SPEC_GATE_ENFORCE_RULES set EMPTY -> nothing repaired, lines pulled unchanged" "grep -qxF -- '$L_BARE' '$D/repos/demo/OVERNIGHT_PROGRESS.md' && grep -qxF -- '$L_GUTCLI' '$D/repos/demo/OVERNIGHT_PROGRESS.md'"
D="$tmp/q3"; mkq "$D"; printf '%s\n%s\n' "$L_BARE" "$L_GUTCLI" > "$D/backlog/demo.md"; refill "$D" OVN_SPEC_GATE_ENFORCE_RULES=none
ok "C5 OVN_SPEC_GATE_ENFORCE_RULES=none = nothing enforced too" "grep -qxF -- '$L_BARE' '$D/repos/demo/OVERNIGHT_PROGRESS.md'"
D="$tmp/q4"; mkq "$D"; printf '%s\n%s\n' "$L_VAC" "$L_BARE" > "$D/backlog/demo.md"; refill "$D" OVN_SPEC_GATE_ENFORCE_RULES=R02
ok "C6 an explicit list WINS over the default: only R02 -> the vacuous echo is repaired, the bare VERIFY is NOT backticked" "! grep -qxF -- '$L_VAC' '$D/repos/demo/OVERNIGHT_PROGRESS.md' && grep -qxF -- '$L_BARE' '$D/repos/demo/OVERNIGHT_PROGRESS.md'"
D="$tmp/q5"; mkq "$D"; printf '%s\n' "$L_BARE" > "$D/backlog/demo.md"; refill "$D" OVN_SPEC_GATE=off
ok "C7 OVN_SPEC_GATE=off disables even the default repairs" "grep -qxF -- '$L_BARE' '$D/repos/demo/OVERNIGHT_PROGRESS.md'"

echo "== D: ovn_spec_gate.py lint default enforce"
GATE="$S/ovn_spec_gate.py"
IN="$(printf '%s\n%s\n%s\nnot an item\n' "$L_BARE" "$L_GUTCLI" "$L_VAC")"
lint(){ printf '%s\n' "$IN" | ( cd "$tmp" && env "$@" python3 "$GATE" lint repos/demo 2>"$tmp/lint.err" ); }
out="$(lint -u OVN_SPEC_GATE_ENFORCE_RULES OVN_DIR="$tmp")"
ok "D1 UNSET env: lint backticks the bare VERIFY and rewrites gut_cli.gd, leaves the vacuous echo, says what is enforced" "printf '%s' '$out' | grep -qF 'VERIFY: \`grep -q old f.txt\` (cat' && printf '%s' '$out' | grep -qF 'gut_cmdln.gd' && ! printf '%s' '$out' | grep -qF 'gut_cli.gd' && printf '%s' '$out' | grep -qF 'echo \"FAIL\"' && grep -q 'enforced: R01,R11' '$tmp/lint.err'"
out="$(lint OVN_SPEC_GATE_ENFORCE_RULES= OVN_DIR="$tmp")"
ok "D2 set EMPTY: stdin echoed unchanged (kill switch)" "[ \"\$out\" = \"\$IN\" ]"
out="$(lint OVN_SPEC_GATE_ENFORCE_RULES=R01,R02,R03,R11 OVN_DIR="$tmp")"
ok "D3 all four armed: R02 now repairs the vacuous echo as well" "! printf '%s' '$out' | grep -qF 'echo \"FAIL\"'"

echo "== E: scan rows carry R11 / R12 as shadow findings"
python3 - "$S" "$R" > "$tmp/e.out" 2>&1 <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import ovn_spec_gate as G, ovn_spec_rules as R
print("OK   quarantine-list-has-R12" if "R12" in G.QUARANTINE_RULES else "FAIL quarantine-list-has-R12")
print("OK   static-repair-list-has-R11" if "R11" in G.STATIC_REPAIR_RULES else "FAIL static-repair-list-has-R11")
print("OK   default-is-R01-R11" if G.DEFAULT_ENFORCE_RULES == "R01,R11" else "FAIL default-is-R01-R11")
PY
ok "E1 R12 is a quarantine-capable rule (armed only by naming it)" "grep -qx 'OK   quarantine-list-has-R12' '$tmp/e.out'"
ok "E2 R11 is in the static repair list" "grep -qx 'OK   static-repair-list-has-R11' '$tmp/e.out'"
ok "E3 the default constant is exactly R01,R11" "grep -qx 'OK   default-is-R01-R11' '$tmp/e.out'"
ok "E4 queue_refill.py knows R12 as a quarantine rule and R11 as a static rule" "grep -q 'GATE_QUARANTINE_RULES = (.*\"R12\"' '$QR' && grep -q 'GATE_STATIC_RULES = (.*\"R11\"' '$QR'"

echo "spec r10 defaults: $P passed, $F failed"
[ "$F" -eq 0 ]
